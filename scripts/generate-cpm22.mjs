import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";
import { translateAtomLineToAzm } from "../src/host/translation/atom-to-azm.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "native");
const outputPath = join(repositoryRoot, "assets", "atom-cpm22.com");
const reportPath = join(repositoryRoot, "proofs", "cpm22-census.json");

async function linkedSource() {
  const parts = await Promise.all(
    ["atom-00.asm", "atom-01.asm", "atom-02.asm", "atom-03.asm", "atom-04.asm"]
      .map((name) => readFile(join(nativeRoot, name), "utf8")),
  );
  assert.match(parts[0], /^ORG 0\n/);
  parts[0] = parts[0].replace(/^ORG 0\n/, "ORG $0100\nJP CP_ENTRY\nDS 13\n");
  const serviceStart = parts[4].indexOf("HS_SCBEG:\n");
  assert.notEqual(serviceStart, -1, "native core omitted the host service tail");
  parts[4] = parts[4].slice(0, serviceStart);
  const atomSource = `${parts.join("\n")}\n${await readFile(join(nativeRoot, "cpm22-adapter.asm"), "utf8")}`;
  return `${atomSource.split(/\r\n|\n|\r/).map(translateAtomLineToAzm).join("\n")}\n.end\n`;
}

async function build() {
  const temporary = await mkdtemp(join(tmpdir(), "atom-cpm22-"));
  try {
    const sourcePath = join(temporary, "atom-cpm22.asm");
    await writeFile(sourcePath, await linkedSource());
    const interfacePath = join(temporary, "cpm22.asmi");
    await writeFile(interfacePath, [
      "extern CP_BDOS",
      "out A",
      "clobbers BC,DE,HL,carry,zero,sign,parity,halfCarry",
      "end",
      "",
    ].join("\n"));
    const result = await compile(sourcePath, {
      emitBin: true,
      emitHex: false,
      emitD8m: true,
      emitLst: false,
      registerContracts: "strict",
      registerContractsInterfaces: [interfacePath],
      symbolCase: "insensitive",
    });
    const errors = result.diagnostics.filter(({ severity }) => severity === "error");
    if (errors.length !== 0) {
      throw new Error(errors.map(({ sourceName, line, column, message }) =>
        `${sourceName}:${line}:${column}: ${message}`).join("\n"));
    }
    const binary = result.artifacts.find(({ kind }) => kind === "bin");
    const debugMap = result.artifacts.find(({ kind }) => kind === "d8m");
    assert.equal(binary?.kind, "bin");
    assert.equal(debugMap?.kind, "d8m");
    const symbols = Object.fromEntries(debugMap.json.symbols.flatMap((symbol) => {
      const value = symbol.address ?? symbol.value;
      return value === undefined ? [] : [[symbol.name.toUpperCase(), value]];
    }));
    assert.ok(symbols.CP_RESIDENT_END <= 0x4000, "CP/M Atom resident exceeds its 16 KiB partition");
    assert.equal(binary.bytes.length, symbols.CP_RESIDENT_END - 0x100);
    const adapterCodeBytes = symbols.CP_ADAPTER_CODE_END - symbols.CP_ADAPTER_CODE_START;
    const adapterImmutableBytes = symbols.CP_ADAPTER_IMMUTABLE_END - symbols.CP_ADAPTER_IMMUTABLE_START;
    const outputAdapterCodeBytes = symbols.CP_OUTPUT_CODE_END - symbols.CP_OUTPUT_CODE_START;
    const adapterWorkspaceBytes =
      symbols.CP_ADAPTER_WORKSPACE1_END - symbols.CP_ADAPTER_WORKSPACE1_START +
      symbols.CP_ADAPTER_WORKSPACE2_END - symbols.CP_ADAPTER_WORKSPACE2_START;
    return {
      bytes: binary.bytes,
      report: {
        format: "atom-cpm22-census",
        version: 1,
        nativeCoreHead: "23afbf6cffe0311059e2af7b8db31ee8559bc121",
        loadAddress: 0x100,
        entryAddress: symbols.CP_ENTRY,
        returnAddress: symbols.CP_RETURN,
        residentEnd: symbols.CP_RESIDENT_END,
        residentBytes: binary.bytes.length,
        nativeCoreResidentBytes: 12396,
        relocationHeaderBytes: 16,
        replacedHostStubBytes: 8,
        adapterResidentBytes: binary.bytes.length - 16 - (12396 - 8),
        adapterCodeBytes,
        adapterImmutableBytes,
        adapterWorkspaceBytes,
        outputAdapterCodeBytes,
        sourceBytes: 0x1000,
        symbolBytes: 0x3000,
        pendingBytes: 0x1000,
        outputBytes: 0x4780,
        sourceProbeBytes: 0x80,
        stackBytes: 0x0c00,
        representativeGeneratedBytes: 34,
        representativeInstructions: 65205,
        representativeTStates: 1046209,
        representativeCommandInstructions: 109140,
        representativeCommandTStates: 1723975,
        representativeStackHighWaterBytes: 32,
        representativeBdosCalls: 16,
        sha256: createHash("sha256").update(binary.bytes).digest("hex"),
      },
    };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

const built = await build();
const renderedReport = `${JSON.stringify(built.report, undefined, 2)}\n`;
if (process.argv.includes("--check")) {
  assert.deepEqual(new Uint8Array(await readFile(outputPath)), built.bytes);
  assert.equal(await readFile(reportPath, "utf8"), renderedReport);
} else {
  await writeFile(outputPath, built.bytes);
  await writeFile(reportPath, renderedReport);
}
