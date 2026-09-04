import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { assembleCpmAtomSource } from "./cpm22-atom-source.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "native");
const outputPath = join(repositoryRoot, "assets", "atom-cpm22.com");
const reportPath = join(repositoryRoot, "proofs", "cpm22-census.json");
const finalImageModulePath = fileURLToPath(import.meta.resolve(
  "@jhlagado/z80-tool-services/native/cpm22-final-image.asm",
));

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
  const adapter = await readFile(join(nativeRoot, "cpm22-adapter.asm"), "utf8");
  const marker = ";@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@";
  assert.equal(adapter.split(marker).length, 2, "CP/M adapter must contain one final-image module marker");
  const linkedAdapter = adapter.replace(marker, await readFile(finalImageModulePath, "utf8"));
  const atomSource = `${parts.join("\n")}\n${linkedAdapter}`;
  return atomSource;
}

async function build() {
  const { bytes, symbols } = await assembleCpmAtomSource(await linkedSource(), { base: 0x100 });
  assert.ok(symbols.CP_RESIDENT_END <= 0x4000, "CP/M Atom resident exceeds its 16 KiB partition");
  assert.equal(bytes.length, symbols.CP_RESIDENT_END - 0x100);
  const adapterCodeBytes = symbols.CP_ADAPTER_CODE_END - symbols.CP_ADAPTER_CODE_START;
  const adapterImmutableBytes = symbols.CP_ADAPTER_IMMUTABLE_END - symbols.CP_ADAPTER_IMMUTABLE_START;
  const outputAdapterCodeBytes = symbols.CP_OUTPUT_CODE_END - symbols.CP_OUTPUT_CODE_START;
  const commandTailCodeBytes = symbols.CP_COMMAND_CODE_END - symbols.CP_COMMAND_CODE_START;
  const sourceAdapterCodeBytes = symbols.CP_SOURCE_CODE_END - symbols.CP_SOURCE_CODE_START;
  const adapterWorkspaceBytes =
    symbols.CP_ADAPTER_WORKSPACE1_END - symbols.CP_ADAPTER_WORKSPACE1_START +
    symbols.CP_ADAPTER_WORKSPACE2_END - symbols.CP_ADAPTER_WORKSPACE2_START;
  return {
    bytes,
    report: {
      format: "atom-cpm22-census",
      version: 6,
      nativeCoreHead: "23afbf6cffe0311059e2af7b8db31ee8559bc121",
      loadAddress: 0x100,
      entryAddress: symbols.CP_ENTRY,
      returnAddress: symbols.CP_RETURN,
      inputFcbAddress: symbols.CP_INPUT_FCB,
      sourceCacheAddress: symbols.CP_SOURCE_CACHE,
      partOrderAddress: symbols.CP_PART_ORDER,
      partOrderEndAddress: symbols.CP_PART_ORDER_END,
      partNamesAddress: symbols.CP_PART_NAMES,
      partNamesEndAddress: symbols.CP_PART_NAMES_END,
      partDescriptorsAddress: symbols.CP_PART_DESCRIPTORS,
      partDescriptorsEndAddress: symbols.CP_PART_DESCRIPTORS_END,
      resolverStateAddress: symbols.CP_NAME_COUNT,
      resolverWorkspaceEndAddress: symbols.CP_NEXT_VALUE + 1,
      sourceCacheKeyAddress: symbols.CP_SOURCE_CACHE_KEY,
      sourceReadAddress: symbols.CP_SOURCE_READ_BYTE,
      sourceCacheMissAddress: symbols.CP_RAW_CACHE_MISS,
      residentEnd: symbols.CP_RESIDENT_END,
      residentBytes: bytes.length,
      residentCapacityBytes: symbols.CP_SOURCE_CACHE - 0x100,
      residentHeadroomBytes: symbols.CP_SOURCE_CACHE - symbols.CP_RESIDENT_END,
      singleSourceBaselineResidentBytes: 13681,
      multipartResidentDeltaBytes: bytes.length - 13681,
      nativeCoreResidentBytes: 12396,
      relocationHeaderBytes: 16,
      replacedHostStubBytes: 8,
      replacedSourceFallbackBytes: 5,
      adapterResidentBytes: bytes.length - 16 - (12396 - 8 - 5),
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
      partOrderBytes: 0x100,
      partNameBytes: 0xff * 11,
      partDescriptorBytes: 0xff * 5,
      resolverStateBytes: 12,
      multipartWorkspaceBytes: 0x100 + 0xff * 11 + 0xff * 5 + 12,
      sourceExecutionWorkspaceBytes: 0x80 + 0x100 + 0xff * 11 + 0xff * 5 + 12,
      symbolBytes: 0x3000,
      pendingBytes: 0x1000,
      outputBytes: 0x4780,
      stackBytes: 0x0c00,
      representativeGeneratedBytes: 34,
      representativeInstructions: 147583,
      representativeTStates: 1820876,
      representativeCommandInstructions: 196866,
      representativeCommandTStates: 2584966,
      representativeStackHighWaterBytes: 32,
      representativeBdosCalls: 43,
      representativeSourceRandomReads: 8,
      namedRepresentativeInstructions: 151360,
      namedRepresentativeTStates: 1859519,
      namedRepresentativeCommandInstructions: 203649,
      namedRepresentativeCommandTStates: 2648789,
      namedRepresentativeBdosCalls: 41,
      namedRepresentativeSourceRandomReads: 8,
      includeRepresentativePartCount: 3,
      includeRepresentativeInstructions: 198630,
      includeRepresentativeTStates: 2325153,
      includeRepresentativeCommandInstructions: 250919,
      includeRepresentativeCommandTStates: 3114423,
      includeRepresentativeStackHighWaterBytes: 32,
      includeRepresentativeBdosCalls: 60,
      includeRepresentativeSourceRandomReads: 13,
      largeRepresentativeSourceBytes: 16535,
      largeRepresentativeInstructions: 4228091,
      largeRepresentativeTStates: 41169864,
      largeRepresentativeCommandInstructions: 4280540,
      largeRepresentativeCommandTStates: 41960471,
      largeRepresentativeBdosCalls: 1066,
      largeRepresentativeSourceRandomReads: 520,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    },
  };
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
