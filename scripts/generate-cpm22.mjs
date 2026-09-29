import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { assembleCpmAtomSource } from "./cpm22-atom-source.mjs";
import {
  joinNativeCoreModules,
  readNativeCoreModules,
  replaceNativeSourceRead,
  setNativeCoreOrigin,
} from "../src/host/build/z80-source-layout.mjs";
import { loadNativeAtomCore } from "../src/host/index.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "src", "z80");
const outputPath = join(repositoryRoot, "assets", "atom-cpm22.com");
const reportPath = join(repositoryRoot, "proofs", "cpm22-census.json");
const finalImageModulePath = fileURLToPath(import.meta.resolve(
  "@jhlagado/z80-tool-services/native/cpm22-final-image.asm",
));

async function linkedSource() {
  let modules = await readNativeCoreModules(nativeRoot);
  modules = setNativeCoreOrigin(modules, "ORG $0100\nJP CP_ENTRY\nDS 13");
  modules = replaceNativeSourceRead(modules, "CP_SOURCE_READ_BYTE");
  const core = joinNativeCoreModules(modules, { includeHostServices: false });
  const adapter = await readFile(join(nativeRoot, "cpm22.asm"), "utf8");
  const preprocessorMarker = ";@@ATOM_CPM_PREPROCESSOR@@";
  assert.equal(adapter.split(preprocessorMarker).length, 2, "CP/M adapter must contain one preprocessor module marker");
  const asoMarker = ";@@ATOM_CPM_ASO_WRITER@@";
  assert.equal(adapter.split(asoMarker).length, 2, "CP/M adapter must contain one ASO writer module marker");
  const asoOverlayMarker = ";@@ATOM_CPM_ASO_OVERLAY@@";
  assert.equal(adapter.split(asoOverlayMarker).length, 2, "CP/M adapter must contain one ASO overlay marker");
  const marker = ";@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@";
  assert.equal(adapter.split(marker).length, 2, "CP/M adapter must contain one final-image module marker");
  const asoModule = await readFile(join(nativeRoot, "aso.asm"), "utf8");
  const matModule = await readFile(join(nativeRoot, "mat.asm"), "utf8");
  const preprocessorModule = await readFile(join(nativeRoot, "cpprep.asm"), "utf8");
  const withPreprocessor = adapter.replace(preprocessorMarker, () => preprocessorModule);
  const withHooks = withPreprocessor.replace(asoMarker, "");
  const finalImageModule = await readFile(finalImageModulePath, "utf8");
  const withFinalImage = withHooks.replace(marker, () => finalImageModule);
  const overlay = `CP_ASO_OVERLAY_BEGIN:\n${asoModule}\n${matModule}\nCP_ASO_OVERLAY_END:\n`;
  const linkedAdapter = withFinalImage.replace(asoOverlayMarker, () => overlay);
  const atomSource = `${core}\n${linkedAdapter}`;
  return atomSource;
}

async function build() {
  const nativeCore = await loadNativeAtomCore();
  const { bytes, symbols } = await assembleCpmAtomSource(await linkedSource(), { base: 0x100 });
  assert.equal(
    symbols.CP_ASO_OVERLAY_BEGIN,
    symbols.CP_RESIDENT_END,
    "CP/M ASO code must follow the low resident image without a gap",
  );
  assert.ok(
    symbols.CP_ASO_OVERLAY_END <= symbols.CP_WORKSPACE_START,
    "CP/M ASO code exceeds the loaded-code area",
  );
  assert.equal(
    symbols.CP_PART_ORDER & 0xff,
    0,
    "CP/M part-order table must begin on a page boundary",
  );
  assert.equal(
    symbols.CP_PART_ORDER_END - symbols.CP_PART_ORDER,
    256,
    "CP/M part-order table must occupy one complete page",
  );
  assert.equal(
    symbols.CP_SOURCE_CACHE & 0xff,
    0,
    "CP/M source cache must begin at offset zero for RES 7,L indexing",
  );
  assert.equal(
    symbols.CP_SOURCE_CACHE_END - symbols.CP_SOURCE_CACHE,
    128,
    "CP/M source cache must occupy one 128-byte record",
  );
  assert.ok(
    symbols.CP_PART_ORDER_END <= symbols.CP_SOURCE_CACHE &&
      symbols.CP_SOURCE_CACHE_END <= symbols.CP_PART_NAMES &&
      symbols.CP_PART_NAMES_END <= symbols.CP_PART_DESCRIPTORS &&
      symbols.CP_PART_DESCRIPTORS_END <= symbols.CP_SYMBOL_START &&
      symbols.CP_SYMBOL_END <= symbols.CP_PENDING_START &&
      symbols.CP_PENDING_END <= symbols.CP_ASO_FCB,
    "CP/M runtime data regions overlap or are out of order",
  );
  assert.equal(
    symbols.CP_MAT_FCB,
    symbols.CP_PART_ORDER,
    "CP/M materializer must reuse the dead part-order page only after assembly",
  );
  assert.equal(
    symbols.CP_MAT_RECORD,
    symbols.CP_MAT_FCB + 36,
    "CP/M materializer FCB and ASO record buffer must be contiguous",
  );
  assert.equal(
    symbols.CP_MAT_STATE,
    symbols.CP_MAT_RECORD + 128,
    "CP/M parser state must follow its 128-byte input record",
  );
  assert.ok(
    symbols.CP_MAT_SCRATCH_END <= symbols.CP_SOURCE_CACHE,
    "CP/M replay state must fit below the reusable source-cache page",
  );
  assert.equal(
    symbols.CP_MAT_WINDOW,
    symbols.CP_SOURCE_CACHE_END,
    "CP/M output window must begin after the reclaimed 128-byte HEX DMA page",
  );
  assert.equal(
    symbols.ZTS_CPM_FINAL_DMA,
    symbols.CP_SOURCE_CACHE,
    "HEX output must use the dead source-cache page, not the replay input record",
  );
  assert.ok(
    symbols.ZTS_CPM_FINAL_DMA + 128 <= symbols.CP_MAT_WINDOW,
    "HEX DMA buffer must remain disjoint from the output replay window",
  );
  assert.ok(
    symbols.CP_ASO_OVERLAY_END <= symbols.CP_OUTPUT_END,
    "CP/M loaded code exceeds the output-memory ceiling",
  );
  assert.ok(
    symbols.CP_OUTPUT_END - symbols.CP_MAT_WINDOW >= 128,
    "CP/M ASO materializer has no complete output record window",
  );
  assert.equal(
    (symbols.CP_OUTPUT_END - symbols.CP_MAT_WINDOW) % 128,
    0,
    "CP/M ASO output window must contain complete sequential records",
  );
  assert.equal(bytes.length, symbols.CP_ASO_OVERLAY_END - 0x100);
  const loadedRecordBytes = Math.ceil(bytes.length / 128) * 128;
  assert.ok(
    0x100 + loadedRecordBytes <= symbols.CP_WORKSPACE_START,
    "CP/M record padding must not overlap the uninitialised workspace",
  );
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
      version: 14,
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
      binaryIncludeFcbAddress: symbols.CP_BIN_FCB,
      resolverStateAddress: symbols.CP_NAME_COUNT,
      resolverWorkspaceEndAddress: symbols.CP_NEXT_VALUE + 1,
      sourceCacheKeyAddress: symbols.CP_SOURCE_CACHE_KEY,
      sourceReadAddress: symbols.CP_SOURCE_READ_BYTE,
      sourceCacheMissAddress: symbols.CP_RAW_CACHE_MISS,
      residentEnd: symbols.CP_RESIDENT_END,
      residentBytes: bytes.length,
      lowResidentBytes: symbols.CP_RESIDENT_END - 0x100,
      minimumBdosAddress: 0xe400,
      minimumTransientProgramBytes: 0xe300,
      asoOverlayStart: symbols.CP_ASO_OVERLAY_BEGIN,
      asoOverlayEnd: symbols.CP_ASO_OVERLAY_END,
      asoOverlayBytes: symbols.CP_ASO_OVERLAY_END - symbols.CP_ASO_OVERLAY_BEGIN,
      materializerScratchStart: symbols.CP_MAT_FCB,
      materializerScratchEnd: symbols.CP_MAT_SCRATCH_END,
      materializerScratchBytes: symbols.CP_MAT_SCRATCH_END - symbols.CP_MAT_FCB,
      materializerFcbAddress: symbols.CP_MAT_FCB,
      materializerRecordAddress: symbols.CP_MAT_RECORD,
      hexDmaAddress: symbols.ZTS_CPM_FINAL_DMA,
      workspaceStartAddress: symbols.CP_WORKSPACE_START,
      workspaceEndAddress: symbols.CP_ASO_RECORD + 128,
      materializerWindowStart: symbols.CP_MAT_WINDOW,
      materializerWindowBytes: symbols.CP_OUTPUT_END - symbols.CP_MAT_WINDOW,
      materializerPolicy: "sequential-window-replay",
      measuredFullTargetOutputBytes: 0xff00,
      measuredFullTargetOutputRecords: 510,
      measuredFullTargetMaterializerPasses: 2,
      measuredFullTargetAsoSpoolRecordsWritten: 527,
      measuredFullTargetAsoSpoolRecordsRead: 1054,
      measuredFullTargetAsoReadCallsIncludingEof: 1056,
      measuredFullTargetSequentialOutputWrites: 510,
      measuredFullTargetRandomOutputReads: 0,
      measuredFullTargetRandomOutputWrites: 0,
      measuredFullTargetInstructions: 15239336,
      measuredFullTargetTStates: 162788510,
      measuredFullTargetCommandInstructions: 15312000,
      measuredFullTargetCommandTStates: 163891952,
      measuredFullTargetStackHighWaterBytes: 30,
      asoRunAddress: symbols.CP_ASO_RUN,
      asoRecordAddress: symbols.CP_ASO_RECORD,
      loadedImageEnd: symbols.CP_ASO_OVERLAY_END,
      loadedImageCapacityBytes: symbols.CP_WORKSPACE_START - 0x100,
      loadedImageHeadroomBytes: symbols.CP_WORKSPACE_START - symbols.CP_ASO_OVERLAY_END,
      loadedRecordBytes,
      loadedRecordPaddingBytes: loadedRecordBytes - bytes.length,
      singleSourceBaselineResidentBytes: 13681,
      multipartResidentDeltaBytes: symbols.CP_RESIDENT_END - 0x100 - 13681,
      nativeCoreResidentBytes: nativeCore.residentExtentBytes,
      relocationHeaderBytes: 16,
      replacedHostStubBytes: 8,
      replacedSourceFallbackBytes: 5,
      adapterResidentBytes: symbols.CP_RESIDENT_END - 0x100 - 16 - (nativeCore.residentExtentBytes - 8 - 5),
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
      asoTargetCapacityBytes: 0xff00,
      asoFcbBytes: 36,
      asoImageRunBytes: 128,
      asoRecordBufferBytes: 128,
      asoFixedBufferBytes: 36 + 128 + 128,
      automaticComBinHexUsesAsoSpool: true,
      stackBytes: 0x0c00,
      representativeGeneratedBytes: 34,
      representativeInstructions: 236722,
      representativeTStates: 2321191,
      representativeCommandInstructions: 315103,
      representativeCommandTStates: 3479436,
      representativeStackHighWaterBytes: 32,
      representativeBdosCalls: 63,
      representativeSourceRandomReads: 12,
      namedRepresentativeInstructions: 241333,
      namedRepresentativeTStates: 2371029,
      namedRepresentativeCommandInstructions: 319394,
      namedRepresentativeCommandTStates: 3526600,
      namedRepresentativeBdosCalls: 61,
      namedRepresentativeSourceRandomReads: 12,
      includeRepresentativePartCount: 3,
      includeRepresentativeInstructions: 295484,
      includeRepresentativeTStates: 2876898,
      includeRepresentativeCommandInstructions: 373545,
      includeRepresentativeCommandTStates: 4032469,
      includeRepresentativeStackHighWaterBytes: 32,
      includeRepresentativeBdosCalls: 82,
      includeRepresentativeSourceRandomReads: 17,
      largeRepresentativeSourceBytes: 16535,
      largeRepresentativeInstructions: 7600761,
      largeRepresentativeTStates: 76493747,
      largeRepresentativeCommandInstructions: 7678982,
      largeRepresentativeCommandTStates: 77650655,
      largeRepresentativeBdosCalls: 1598,
      largeRepresentativeSourceRandomReads: 780,
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
