import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  loadNativeAtomCore,
  assembleResolvedAtomProject,
  materializeAtomGeneration,
  resolveAtomProject,
} from "../src/host/index.mjs";
import { DIAGNOSTIC_MESSAGES, DIAGNOSTIC_STACK_OVERFLOW } from "../src/host/diagnostics.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "src", "z80");
const outputPath = join(repositoryRoot, "assets", "atom-cpm22.com");
const reportPath = join(repositoryRoot, "proofs", "cpm22-census.json");

// Node assembles exactly the files CP/M reads: cpm22.asm and its includes.
export async function assembleCpm22Source() {
  const project = await resolveAtomProject({ root: nativeRoot, entry: "cpm22.asm" });
  const result = await assembleResolvedAtomProject(project, {
    target: { start: 0x100, capacity: 0xff00 },
    maxInstructions: 600_000_000,
    maxCycles: 6_000_000_000,
  });
  // Atom reports names in uppercase. Look them up as the source spells them.
  const values = new Map(result.generation.symbols.map(({ name, value }) => [name.toUpperCase(), value]));
  const symbol = (name) => {
    const value = values.get(name.toUpperCase());
    assert.notEqual(value, undefined, `CP/M build has no symbol ${name}`);
    return value;
  };
  return { bytes: materializeAtomGeneration(result.generation, { base: 0x100 }).bytes, symbol };
}

const ARGUMENT = Object.freeze({ S: 1, D: 2, L: 3 });

function encodeSentence(text) {
  const pieces = [];
  let literal = "";
  const flush = () => {
    // Keep each quoted piece short enough for a 78-column DB line.
    for (let start = 0; start < literal.length; start += 60) {
      pieces.push(`"${literal.slice(start, start + 60)}"`);
    }
    literal = "";
  };
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === "%" && ARGUMENT[text[index + 1]] !== undefined) {
      flush();
      pieces.push(String(ARGUMENT[text[index + 1]]));
      index += 1;
      continue;
    }
    if (character === '"' || character.charCodeAt(0) > 0x7e || character.charCodeAt(0) < 0x20) {
      throw new Error(`message contains an unsupported character: ${text}`);
    }
    literal += character;
  }
  flush();
  pieces.push("0");
  return pieces;
}

function asmComment(code, comment) {
  return `${code.padEnd(80)}; ${comment}`;
}

// Split one DB list across lines that fit in 78 columns.
function dbLines(pieces, sentence) {
  const lines = [];
  let current = "";
  for (const piece of pieces) {
    const next = current === "" ? piece : `${current},${piece}`;
    if (`    DB   ${next}`.length > 78 && current !== "") {
      lines.push(`    DB   ${current}`);
      current = piece;
    } else {
      current = next;
    }
  }
  if (current !== "") lines.push(`    DB   ${current}`);
  return lines.map((line, index) => asmComment(line, `${index === 0 ? "Diagnostic" : "Continue diagnostic"} sentence ${sentence}.`));
}

export function renderCpmMessages() {
  const sentences = [...new Set(DIAGNOSTIC_MESSAGES)];
  if (sentences.length > 255) throw new Error("too many distinct messages");
  const index = DIAGNOSTIC_MESSAGES.map((text) => sentences.indexOf(text));
  const lines = [
    "; Atom diagnostic messages for CP/M. Generated from",
    "; src/host/diagnostics.mjs by npm run build.",
    "; Edit the messages there and rebuild.",
    ";",
    "; msgIdx holds one sentence number per message number. msgText holds",
    "; the sentences in order, each ended by 0. Bytes 1, 2 and 3 inside a",
    "; sentence stand for the symbol name, the signed value and the related",
    "; line.",
    "",
    asmComment(`msgNum      EQU     ${DIAGNOSTIC_MESSAGES.length}`, "Message numbers in msgIdx."),
    asmComment(`msgOver     EQU     ${DIAGNOSTIC_STACK_OVERFLOW}`, "The stack-overflow message."),
    "",
    "msgIdx: ; Map each diagnostic number to its stored sentence.",
  ];
  for (let start = 0; start < index.length; start += 16) {
    const end = Math.min(start + 15, index.length - 1);
    lines.push(asmComment(`    DB   ${index.slice(start, start + 16).join(",")}`, `Sentence indices for messages ${start}-${end}.`));
  }
  lines.push("msgText: ; Zero-terminated sentences with argument marker bytes.");
  sentences.forEach((sentence, ordinal) => {
    lines.push(...dbLines(encodeSentence(sentence), ordinal));
  });
  lines.push("msgEnd: ; First byte after the diagnostic text table.");
  return `${lines.join("\n")}\n`;
}

async function build() {
  const nativeCore = await loadNativeAtomCore();
  const { bytes, symbol } = await assembleCpm22Source();
  assert.equal(
    symbol("asoBeg"),
    symbol("cpResEnd"),
    "CP/M spool and replay code must follow the resident adapter without a gap",
  );
  assert.ok(
    symbol("asoEnd") <= symbol("cpWork"),
    "CP/M spool and replay code exceeds the loaded-code area",
  );
  assert.ok(
    symbol("srcPgEnd") <= symbol("srcCache"),
    "CP/M source state must fit its page",
  );
  assert.equal(
    symbol("srcCache") & 0xff,
    0,
    "CP/M source cache must begin at offset zero for RES 7,L indexing",
  );
  assert.equal(
    symbol("srcCEnd") - symbol("srcCache"),
    128,
    "CP/M source cache must occupy one 128-byte record",
  );
  assert.ok(
    symbol("srcCEnd") <= symbol("incNames") &&
      symbol("incNEnd") <= symbol("srcSaves") &&
      symbol("incEnd") <= symbol("binRamLo") &&
      symbol("binRamHi") <= symbol("asoFcb") &&
      symbol("asoRec") + 128 <= symbol("feRamLo") &&
      symbol("feRamLo") <= symbol("feRamHi"),
    "CP/M runtime data regions overlap or are out of order",
  );
  assert.equal(
    symbol("matFcb"),
    symbol("srcPage"),
    "CP/M materializer must reuse the source page only after assembly",
  );
  assert.equal(
    symbol("matRec"),
    symbol("matFcb") + 36,
    "CP/M materializer FCB and ASO record buffer must be contiguous",
  );
  assert.equal(
    symbol("matVars"),
    symbol("matRec") + 128,
    "CP/M parser state must follow its 128-byte input record",
  );
  assert.ok(
    symbol("matVEnd") <= symbol("srcCache"),
    "CP/M replay state must fit below the reusable source-cache page",
  );
  assert.equal(
    symbol("matWin"),
    symbol("srcCEnd"),
    "CP/M output window must begin after the reclaimed 128-byte HEX DMA page",
  );
  assert.ok(
    symbol("srcCache") + 128 <= symbol("matWin"),
    "HEX DMA buffer must remain disjoint from the output replay window",
  );
  assert.equal(symbol("cpStkLen"), 0x200, "CP/M private stack must hold 512 bytes");
  const minimumBdosAddress = symbol("feRamHi") + symbol("cpStkLen");
  // The entry code puts the stack below BDOS and gives a quarter of the rest
  // to pending references. Record the result for TEC-OS and a 64K system.
  const layout = (bdos) => {
    const stackFloor = bdos - symbol("cpStkLen");
    const arenaBytes = stackFloor - symbol("feRamHi");
    const pendingBytes = arenaBytes >>> 2;
    return {
      bdosAddress: bdos,
      stackFloorAddress: stackFloor,
      symbolBytes: arenaBytes - pendingBytes,
      pendingBytes,
      symbols: Math.floor((arenaBytes - pendingBytes) / 8),
      pendingReferences: Math.floor(pendingBytes / 11),
      materializerWindowBytes: (stackFloor - symbol("matWin")) & ~0x7f,
    };
  };
  assert.equal(bytes.length, symbol("asoEnd") - 0x100);
  const loadedRecordBytes = Math.ceil(bytes.length / 128) * 128;
  assert.ok(
    0x100 + loadedRecordBytes <= symbol("cpWork"),
    "CP/M record padding must not overlap the uninitialised workspace",
  );
  const adapterCodeBytes = symbol("cpEnd") - symbol("cpBeg");
  const adapterImmutableBytes = symbol("cpImmEnd") - symbol("cpImmBeg");
  const outputAdapterCodeBytes = symbol("pubEnd") - symbol("pubBeg");
  const commandTailCodeBytes = symbol("cmdEnd") - symbol("cmdBeg");
  const sourceAdapterCodeBytes = symbol("srcEnd") - symbol("srcBeg");
  const adapterWorkspaceBytes =
    symbol("cpFcbEnd") - symbol("cpFcbBeg") +
    symbol("cpRunEnd") - symbol("cpRunBeg");
  return {
    bytes,
    report: {
      format: "atom-cpm22-census",
      version: 16,
      loadAddress: 0x100,
      entryAddress: symbol("cpEntry"),
      returnAddress: symbol("cpExit"),
      inputFcbAddress: symbol("srcFcb"),
      sourceCacheAddress: symbol("srcCache"),
      sourcePageAddress: symbol("srcPage"),
      partNamesAddress: symbol("incNames"),
      partNamesEndAddress: symbol("incNEnd"),
      binaryIncludeFcbAddress: symbol("binFcb"),
      sourceCacheKeyAddress: symbol("srcKey"),
      sourceReadAddress: symbol("tkRead"),
      sourceCacheMissAddress: symbol("srcMiss"),
      residentEnd: symbol("cpResEnd"),
      residentBytes: bytes.length,
      lowResidentBytes: symbol("cpResEnd") - 0x100,
      minimumBdosAddress,
      minimumTransientProgramBytes: minimumBdosAddress - 0x100,
      spoolCodeStart: symbol("asoBeg"),
      spoolCodeEnd: symbol("asoEnd"),
      spoolCodeBytes: symbol("asoEnd") - symbol("asoBeg"),
      materializerScratchStart: symbol("matFcb"),
      materializerScratchEnd: symbol("matVEnd"),
      materializerScratchBytes: symbol("matVEnd") - symbol("matFcb"),
      materializerFcbAddress: symbol("matFcb"),
      materializerRecordAddress: symbol("matRec"),
      hexDmaAddress: symbol("srcCache"),
      workspaceStartAddress: symbol("cpWork"),
      workspaceEndAddress: symbol("feRamHi"),
      arenaStartAddress: symbol("feRamHi"),
      pendingArenaDivisor: 4,
      materializerWindowStart: symbol("matWin"),
      materializerPolicy: "sequential-window-replay",
      asoRunAddress: symbol("asoRun"),
      asoRecordAddress: symbol("asoRec"),
      loadedImageEnd: symbol("asoEnd"),
      loadedImageCapacityBytes: symbol("cpWork") - 0x100,
      loadedImageHeadroomBytes: symbol("cpWork") - symbol("asoEnd"),
      loadedRecordBytes,
      loadedRecordPaddingBytes: loadedRecordBytes - bytes.length,
      nativeCoreResidentBytes: nativeCore.residentExtentBytes,
      relocationHeaderBytes: 16,
      replacedHostStubBytes: 8,
      replacedSourceFallbackBytes: 8,
      adapterResidentBytes: symbol("cpResEnd") - 0x100 - 16 - (nativeCore.residentExtentBytes - 8 - 8),
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
      layouts: [layout(0xb406), layout(0xe406)],
      asoTargetCapacityBytes: 0xff00,
      asoFcbBytes: 36,
      asoImageRunBytes: 128,
      asoRecordBufferBytes: 128,
      asoFixedBufferBytes: 36 + 128 + 128,
      automaticComBinHexUsesAsoSpool: true,
      stackBytes: symbol("cpStkLen"),
      sha256: createHash("sha256").update(bytes).digest("hex"),
    },
  };
}

export async function buildCpm22({ check = false } = {}) {
  const messagesPath = join(nativeRoot, "cpmsg.asm");
  const messages = renderCpmMessages();
  if (check) assert.equal(await readFile(messagesPath, "utf8"), messages, "CP/M messages are stale: run npm run build");
  else await writeFile(messagesPath, messages);
  const built = await build();
  const renderedReport = `${JSON.stringify(built.report, undefined, 2)}\n`;
  if (check) {
    assert.deepEqual(new Uint8Array(await readFile(outputPath)), built.bytes);
    assert.equal(await readFile(reportPath, "utf8"), renderedReport);
  } else {
    await writeFile(outputPath, built.bytes);
    await writeFile(reportPath, renderedReport);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await buildCpm22({ check: process.argv.includes("--check") });
}
