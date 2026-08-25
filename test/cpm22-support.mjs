import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  installCpm22File,
  readCpm22File,
} from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import { createCpm22PlatformRuntime } from "@jhlagado/debug80-runtime/platforms/cpm22/runtime";
import { createZ80Runtime } from "@jhlagado/debug80-runtime/z80/runtime";

import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
} from "../src/host/index.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(here, "..");
const debug80Root = resolve(repositoryRoot, "..", "debug80");
const cpmRoot = join(debug80Root, "apps", "debug80-vscode", "roms", "cpm22");

export const representativeSource = Buffer.from([
  "ORG $100",
  "LD C,9",
  "LD DE,MESSAGE",
  "CALL 5",
  "RET",
  "MESSAGE:",
  "DB 72,101,108,108,111,32,102,114,111,109,32,110,97,116,105,118,101,32,65,116,111,109,13,10,36",
  "",
].join("\r\n"), "ascii");

function projectForParts(parts) {
  return Object.freeze({
    parts: Object.freeze(parts.map((bytes, ordinal) => Object.freeze({
      ordinal,
      bank: 0,
      originalBytes: Uint8Array.from(bytes),
      compilerBytes: Uint8Array.from(bytes),
      logicalIdentity: `PART${ordinal}.ASM`,
      diagnosticIdentity: `PART${ordinal}.ASM`,
      physicalIdentity: `proof:PART${ordinal}.ASM`,
      binaryIncludes: Object.freeze([]),
    }))),
  });
}

export async function runCpm22Atom(source = representativeSource, priorOutput, options = {}) {
  const sourceName = options.sourceName ?? "INPUT.ASM";
  const outputName = options.outputName ?? "OUTPUT.COM";
  const command = options.command ??
    (sourceName === "INPUT.ASM" && outputName === "OUTPUT.COM"
      ? "ATOM"
      : `ATOM ${sourceName} ${outputName}`);
  const [bootstrapBytes, baseDiskBytes, atomBytes, census] = await Promise.all([
    readFile(join(cpmRoot, "bootstrap.bin")),
    readFile(join(cpmRoot, "cpm22.img")),
    readFile(join(repositoryRoot, "assets", "atom-cpm22.com")),
    readFile(join(repositoryRoot, "proofs", "cpm22-census.json"), "utf8").then(JSON.parse),
  ]);
  let diskImage = installCpm22File(new Uint8Array(baseDiskBytes), "ATOM.COM", atomBytes);
  if (options.installSource !== false) {
    diskImage = installCpm22File(diskImage, sourceName, source);
  }
  if (priorOutput !== undefined) {
    diskImage = installCpm22File(diskImage, outputName, priorOutput);
  }
  for (const [name, bytes] of options.files ?? []) {
    diskImage = installCpm22File(diskImage, name, bytes);
  }
  const memory = new Uint8Array(0x10000);
  memory.set(bootstrapBytes);
  const platform = createCpm22PlatformRuntime({ diskImage });
  const output = [];
  const runtime = createZ80Runtime(
    { memory, startAddress: 0 },
    0,
    {
      read: platform.ioHandlers.read,
      write(port, value) {
        if ((port & 0xff) === 0) output.push(value & 0xff);
        platform.ioHandlers.write(port, value);
      },
    },
  );
  const runtimeMemory = runtime.hardware.memory;
  let instructions = 0;
  let cycles = 0;
  let minimumSp = 0xffff;
  const bdosCalls = [];
  const randomReadRecords = [];
  let planSequentialReads = 0;
  let sourceSequentialReads = 0;
  const sourceCacheMisses = [];
  let sourceReadCount = 0;
  let lastSourceOffset;
  let measureAtom = false;
  const transcript = (from = 0) => Buffer.from(output.slice(from)).toString("latin1");
  const stepUntil = (predicate, description, maximum = 10_000_000) => {
    for (let count = 0; count < maximum; count += 1) {
      if (measureAtom) {
        minimumSp = Math.min(minimumSp, runtime.getRegisters().sp);
        if (runtime.getPC() === census.sourceReadAddress) {
          lastSourceOffset = (runtime.getRegisters().h << 8) | runtime.getRegisters().l;
          sourceReadCount += 1;
        }
        if (runtime.getPC() === census.sourceCacheMissAddress) {
          const registers = runtime.getRegisters();
          sourceCacheMisses.push(Object.freeze({
            key: (registers.d << 8) | registers.e,
            sourceOffset: lastSourceOffset,
          }));
        }
        if (runtime.getPC() === 5) {
          const registers = runtime.getRegisters();
          const call = registers.c;
          bdosCalls.push(call);
          const fcb = (registers.d << 8) | registers.e;
          if (call === 20 && fcb === census.planFcbAddress) planSequentialReads += 1;
          if (call === 20 && fcb === census.inputFcbAddress) sourceSequentialReads += 1;
          if (call === 33) {
            const fcb = census.inputFcbAddress;
            randomReadRecords.push(
              runtimeMemory[fcb + 33] |
                (runtimeMemory[fcb + 34] << 8) |
                (runtimeMemory[fcb + 35] << 16),
            );
          }
        }
      }
      const result = runtime.step();
      instructions += 1;
      cycles += result.cycles ?? 0;
      if (predicate()) return;
    }
    throw new Error(`timed out waiting for ${description}: ${JSON.stringify(transcript())}`);
  };
  stepUntil(() => transcript().endsWith("A>"), "cold boot");
  options.initializeMemory?.(runtimeMemory);
  const beforeAtomInstructions = instructions;
  const beforeAtomCycles = cycles;
  const atomOutputStart = output.length;
  platform.terminal.enqueueInput(Buffer.from(`${command}\r`, "ascii"));
  stepUntil(() => runtime.getPC() === census.entryAddress, "Atom entry");
  const entrySp = runtime.getRegisters().sp;
  const programInstructions = instructions;
  const programCycles = cycles;
  measureAtom = true;
  stepUntil(() => runtime.getPC() === census.returnAddress, "Atom return tail");
  stepUntil(() => runtime.getPC() !== census.returnAddress, "Atom stack restoration");
  stepUntil(() => true, "Atom return instruction");
  const returnSp = runtime.getRegisters().sp;
  measureAtom = false;
  const atomInstructions = instructions - programInstructions;
  const atomCycles = cycles - programCycles;
  const commandInstructions = instructions - beforeAtomInstructions;
  const commandCycles = cycles - beforeAtomCycles;
  stepUntil(() => transcript(atomOutputStart).endsWith("\r\nA>"), "Atom completion prompt");
  const finalDisk = platform.disk.exportImage();
  const outputFile = readCpm22File(finalDisk, outputName);
  return {
    atomBytes,
    census,
    atomTranscript: transcript(atomOutputStart),
    atomInstructions,
    atomCycles,
    commandInstructions,
    commandCycles,
    atomMinimumSp: minimumSp,
    atomBdosCalls: Object.freeze(bdosCalls.slice()),
    atomRandomReadRecords: Object.freeze(randomReadRecords.slice()),
    atomPlanSequentialReads: planSequentialReads,
    atomSourceSequentialReads: sourceSequentialReads,
    atomSourceCacheMisses: Object.freeze(sourceCacheMisses.slice()),
    atomSourceReads: sourceReadCount,
    entrySp,
    returnSp,
    finalDisk,
    outputFile,
    sourceName,
    outputName,
    command,
    memory: runtimeMemory,
    runtime,
    platform,
    transcript,
    runCommand(nextCommand) {
      const start = output.length;
      platform.terminal.enqueueInput(Buffer.from(`${nextCommand}\r`, "ascii"));
      stepUntil(() => transcript(start).endsWith("\r\nA>"), `${nextCommand} completion`);
      return transcript(start);
    },
    readCurrentFile(name) {
      return readCpm22File(platform.disk.exportImage(), name);
    },
    runOutput() {
      const outputCommand = outputName.slice(0, outputName.lastIndexOf("."));
      return this.runCommand(outputCommand);
    },
  };
}

export async function expectedRepresentativeProgram() {
  return expectedMultipartProgram([representativeSource]);
}

export async function expectedMultipartProgram(parts) {
  const assembly = await assembleResolvedAtomProject(projectForParts(parts), {
    target: { start: 0x100, capacity: 0x4780 },
  });
  assert.equal(assembly.native.carry, 0);
  return materializeAtomGeneration(assembly.generation);
}
