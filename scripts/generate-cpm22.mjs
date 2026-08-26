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
  const sourceReadStart = parts[1].indexOf("TK_SREAD:\n");
  const sourceReadEnd = parts[1].indexOf(
    ";@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY",
    sourceReadStart,
  );
  assert.notEqual(sourceReadStart, -1, "native core omitted the source-read entry");
  assert.notEqual(sourceReadEnd, -1, "native core omitted the source-read boundary");
  parts[1] = `${parts[1].slice(0, sourceReadStart)}TK_SREAD:\nJP CP_SOURCE_READ_BYTE\n${parts[1].slice(sourceReadEnd)}`;
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
      "extern CP_BDOS_ENTRY",
      "out A",
      "clobbers BC,DE,HL,IX,IY,carry,zero,sign,parity,halfCarry",
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
    const commandTailCodeBytes = symbols.CP_COMMAND_CODE_END - symbols.CP_COMMAND_CODE_START;
    const sourceAdapterCodeBytes = symbols.CP_SOURCE_CODE_END - symbols.CP_SOURCE_CODE_START;
    const adapterWorkspaceBytes =
      symbols.CP_ADAPTER_WORKSPACE1_END - symbols.CP_ADAPTER_WORKSPACE1_START +
      symbols.CP_ADAPTER_WORKSPACE2_END - symbols.CP_ADAPTER_WORKSPACE2_START;
    return {
      bytes: binary.bytes,
      report: {
        format: "atom-cpm22-census",
        version: 4,
        nativeCoreHead: "23afbf6cffe0311059e2af7b8db31ee8559bc121",
        loadAddress: 0x100,
        entryAddress: symbols.CP_ENTRY,
        returnAddress: symbols.CP_RETURN,
        inputFcbAddress: symbols.CP_INPUT_FCB,
        sourceCacheAddress: symbols.CP_SOURCE_CACHE,
        planCacheAddress: symbols.CP_PLAN_CACHE,
        partDescriptorsAddress: symbols.CP_PART_DESCRIPTORS,
        partDescriptorsEndAddress: symbols.CP_PART_DESCRIPTORS_END,
        planFcbAddress: symbols.CP_PLAN_FCB,
        planStateAddress: symbols.CP_PLAN_POINTER,
        planWorkspaceEndAddress: symbols.CP_PLAN_LINE_END + 1,
        sourceCacheKeyAddress: symbols.CP_SOURCE_CACHE_KEY,
        sourceReadAddress: symbols.CP_SOURCE_READ_BYTE,
        sourceCacheMissAddress: symbols.CP_SOURCE_CACHE_MISS,
        residentEnd: symbols.CP_RESIDENT_END,
        residentBytes: binary.bytes.length,
        residentCapacityBytes: symbols.CP_SOURCE_CACHE - 0x100,
        residentHeadroomBytes: symbols.CP_SOURCE_CACHE - symbols.CP_RESIDENT_END,
        singleSourceBaselineResidentBytes: 13681,
        multipartResidentDeltaBytes: binary.bytes.length - 13681,
        nativeCoreResidentBytes: 12396,
        relocationHeaderBytes: 16,
        replacedHostStubBytes: 8,
        replacedSourceFallbackBytes: 5,
        adapterResidentBytes: binary.bytes.length - 16 - (12396 - 8 - 5),
        adapterCodeBytes,
        adapterImmutableBytes,
        adapterWorkspaceBytes,
        outputAdapterCodeBytes,
        commandTailCodeBytes,
        sourceAdapterCodeBytes,
        sourceCapacityBytes: 0xffff,
        sourceCacheBytes: 0x80,
        maximumSourceParts: 0xff,
        maximumDescribedSourceBytes: 0xff * 0xffff,
        planCacheBytes: 0x80,
        partDescriptorBytes: 0xff * 5,
        planFcbBytes: 36,
        planStateBytes: 4,
        multipartWorkspaceBytes: 0x80 + 0xff * 5 + 36 + 4,
        sourceExecutionWorkspaceBytes: 0x80 + 0x80 + 0xff * 5 + 36 + 4,
        symbolBytes: 0x3000,
        pendingBytes: 0x1000,
        outputBytes: 0x4780,
        stackBytes: 0x0c00,
        representativeGeneratedBytes: 34,
        representativeInstructions: 117340,
        representativeTStates: 1530287,
        representativeCommandInstructions: 163949,
        representativeCommandTStates: 2251215,
        representativeStackHighWaterBytes: 32,
        representativeBdosCalls: 29,
        representativeSourceSequentialReads: 2,
        representativeSourceRandomReads: 2,
        namedRepresentativeInstructions: 118650,
        namedRepresentativeTStates: 1542566,
        namedRepresentativeCommandInstructions: 168265,
        namedRepresentativeCommandTStates: 2288674,
        namedRepresentativeBdosCalls: 27,
        namedRepresentativeSourceSequentialReads: 2,
        namedRepresentativeSourceRandomReads: 2,
        multipartRepresentativeSourceBytes: 31,
        multipartRepresentativeGeneratedBytes: 4,
        multipartRepresentativeInstructions: 130764,
        multipartRepresentativeTStates: 1660154,
        multipartRepresentativeCommandInstructions: 180650,
        multipartRepresentativeCommandTStates: 2408600,
        multipartRepresentativeStackHighWaterBytes: 32,
        multipartRepresentativeBdosCalls: 39,
        multipartRepresentativePlanReads: 2,
        multipartRepresentativeSourceSequentialReads: 2,
        multipartRepresentativeSourceRandomReads: 2,
        combinedRepresentativeSourceBytes: 66151,
        combinedRepresentativeGeneratedBytes: 34,
        combinedRepresentativeInstructions: 7624728,
        combinedRepresentativeTStates: 74698444,
        combinedRepresentativeCommandInstructions: 7674614,
        combinedRepresentativeCommandTStates: 75446890,
        combinedRepresentativeStackHighWaterBytes: 32,
        combinedRepresentativeBdosCalls: 1075,
        combinedRepresentativePlanReads: 2,
        combinedRepresentativeSourceSequentialReads: 518,
        combinedRepresentativeSourceRandomReads: 518,
        largeRepresentativeSourceBytes: 16535,
        largeRepresentativeInstructions: 1957177,
        largeRepresentativeTStates: 19455918,
        largeRepresentativeCommandInstructions: 2006952,
        largeRepresentativeCommandTStates: 20203363,
        largeRepresentativeBdosCalls: 284,
        largeRepresentativeSourceSequentialReads: 130,
        largeRepresentativeSourceRandomReads: 130,
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
