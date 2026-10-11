import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  loadNativeAtomCore,
  assembleResolvedAtomProject,
  materializeAtomGeneration,
} from "../src/host/index.mjs";
import {
  joinNativeCoreModules,
  readAssemblyModule,
  readNativeCoreModules,
  replaceNativeSourceRead,
  setNativeCoreOrigin,
} from "../src/host/build/z80-source-layout.mjs";
import { DIAGNOSTIC_MESSAGES, DIAGNOSTIC_STACK_OVERFLOW } from "../src/host/diagnostics.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "src", "z80");
const outputPath = join(repositoryRoot, "assets", "atom-cpm22.com");
const reportPath = join(repositoryRoot, "proofs", "cpm22-census.json");

const finalImageModulePath = fileURLToPath(import.meta.resolve(
  "@jhlagado/z80-tool-services/native/cpm22-final-image.asm",
));

// Each marker line in cpm22.asm is replaced by the named module's text.
export const CPM22_SPLICES = Object.freeze([
  { marker: ";@@ATOM_CPM_PREPROCESSOR@@", modules: ["cpprep.asm"] },
  { marker: ";@@ATOM_CPM_ASO_WRITER@@", modules: [] },
  { marker: ";@@ATOM_CPM_MESSAGES@@", modules: ["cpmsg.asm"] },
  { marker: ";@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@", external: finalImageModulePath },
  { marker: ";@@ATOM_CPM_ASO_OVERLAY@@", modules: ["aso.asm", "mat.asm"], begin: "ASO_CBEG:", end: "ASO_CEND:" },
]);

export async function linkCpm22Source() {
  let modules = await readNativeCoreModules(nativeRoot);
  modules = setNativeCoreOrigin(modules, "ORG $0100\nJP CP_ENTRY\nDS 13");
  modules = replaceNativeSourceRead(modules, "SRC_READ");
  const core = joinNativeCoreModules(modules, { includeHostServices: false });
  let adapter = await readAssemblyModule(nativeRoot, "cpm22.asm");
  for (const splice of CPM22_SPLICES) {
    assert.equal(adapter.split(splice.marker).length, 2, `CP/M adapter must contain one ${splice.marker} marker`);
    let text;
    if (splice.external !== undefined) {
      text = await readFile(splice.external, "utf8");
    } else {
      const parts = await Promise.all(splice.modules.map((name) => readAssemblyModule(nativeRoot, name)));
      text = parts.join("\n");
      if (splice.begin !== undefined) text = `${splice.begin}\n${text}\n${splice.end}\n`;
    }
    adapter = adapter.replace(splice.marker, () => text);
  }
  return `${core}\n${adapter}`;
}

// Private link-time preparation for the CP/M adapter and its shared renderer.
// Atom keeps eight significant characters per name. Atom's own labels fit,
// so this pass only aliases the longer ZTS_ names the external Z80 Tool
// Services HEX writer defines and expects. Names change, not expressions or
// opcodes. Quoted bytes and comments survive.
const tokens = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|;.*|\$[0-9a-f]+|\b[0-9][a-z0-9]*\b|\.?[a-z_][a-z0-9_]*/gi;
const identifier = /^\.?[a-z_][a-z0-9_]*$/i;

export function prepareCpmAtomSource(source, name = "cpm-link") {
  const lines = source.split(/\r\n|\n|\r/);
  const used = new Set(lines.flatMap((line) => (line.match(tokens) ?? [])
    .filter((token) => identifier.test(token)).map((token) => token.toUpperCase())));
  const aliases = new Map();
  let ordinal = 0;
  for (const original of [...used].sort()) {
    if (original.replace(/^\./, "").length <= 8) continue;
    let short;
    do {
      const suffix = (ordinal++).toString(36).toUpperCase().padStart(7, "0");
      short = `${original.startsWith(".") ? "." : ""}Q${suffix}`;
    } while (used.has(short));
    used.add(short);
    aliases.set(original, short);
  }
  const known = new Set();
  const pending = [];
  const prepared = [];
  const declare = (symbol) => {
    known.add(symbol);
    let progress;
    do {
      progress = false;
      for (let index = 0; index < pending.length; index += 1) {
        const item = pending[index];
        if (!known.has(item.target)) continue;
        prepared.push(item.line);
        known.add(item.symbol);
        pending.splice(index, 1);
        index -= 1;
        progress = true;
      }
    } while (progress);
  };
  for (const sourceLine of lines) {
    const line = sourceLine.replace(tokens, (token) => aliases.get(token.toUpperCase()) ?? token);
    // The shared renderer's pure-name EQU aliases precede their workspace
    // labels. Defer only those aliases; ATOM itself evaluates every expression.
    const alias = /^\s*([a-z_][a-z0-9_]*)\s+EQU\s+([a-z_][a-z0-9_]*)\s*(?:;.*)?$/i.exec(line);
    if (alias !== null && !known.has(alias[2].toUpperCase())) {
      pending.push({ line, symbol: alias[1].toUpperCase(), target: alias[2].toUpperCase() });
      continue;
    }
    prepared.push(line);
    const declaration = /^\s*([a-z_][a-z0-9_]*)(?:\s*:|\s+EQU\b)/i.exec(line);
    if (declaration !== null) declare(declaration[1].toUpperCase());
  }
  assert.equal(pending.length, 0, `unresolved CP/M link aliases: ${pending.map(({ line }) => line).join("; ")}`);
  const parts = [];
  let chunk = "";
  let size = 0;
  const flush = () => {
    if (size === 0) return;
    const bytes = new TextEncoder().encode(chunk);
    parts.push({
      ordinal: parts.length,
      bank: 0,
      logicalIdentity: `${name}-${parts.length}.asm`,
      originalBytes: bytes,
      compilerBytes: bytes,
    });
    chunk = "";
    size = 0;
  };
  for (const line of prepared) {
    const text = `${line}\n`;
    const length = Buffer.byteLength(text);
    assert.ok(length <= 0xffff, "CP/M link source line exceeds one ATOM part");
    if (size + length > 0xffff) flush();
    chunk += text;
    size += length;
  }
  flush();
  return { project: { parts }, aliases };
}

export async function assembleCpmAtomSource(source, { name = "cpm-link", base = 0 } = {}) {
  const { project, aliases } = prepareCpmAtomSource(source, name);
  const result = await assembleResolvedAtomProject(project, {
    target: { start: base, capacity: Math.min(0xffff, 0x10000 - base) },
    maxInstructions: 600_000_000,
    maxCycles: 6_000_000_000,
  }).catch((cause) => {
    const location = cause.diagnostic;
    const part = project.parts[location?.ordinal];
    if (part === undefined) throw cause;
    const line = new TextDecoder().decode(part.originalBytes).split("\n")[location.line - 1];
    throw new Error(`${location.logicalIdentity}:${location.line}: ${cause.message}\n> ${line}`, { cause });
  });
  const reverse = new Map([...aliases].map(([original, short]) => [short, original]));
  const symbols = Object.fromEntries(result.generation.symbols.map(({ name: symbol, value }) => [
    reverse.get(symbol.toUpperCase()) ?? symbol.toUpperCase(), value,
  ]));
  return { bytes: materializeAtomGeneration(result.generation, { base }).bytes, symbols };
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
    "; MSG_IDX holds one sentence number per message number. MSG_TEXT holds",
    "; the sentences in order, each ended by 0. Bytes 1, 2 and 3 inside a",
    "; sentence stand for the symbol name, the signed value and the related",
    "; line.",
    "",
    asmComment(`MSG_NUM     EQU     ${DIAGNOSTIC_MESSAGES.length}`, "Message numbers in MSG_IDX."),
    asmComment(`MSG_STACK   EQU     ${DIAGNOSTIC_STACK_OVERFLOW}`, "The stack-overflow message."),
    "",
    "MSG_IDX: ; Map each diagnostic number to its stored sentence.",
  ];
  for (let start = 0; start < index.length; start += 16) {
    const end = Math.min(start + 15, index.length - 1);
    lines.push(asmComment(`    DB   ${index.slice(start, start + 16).join(",")}`, `Sentence indices for messages ${start}-${end}.`));
  }
  lines.push("MSG_TEXT: ; Zero-terminated sentences with argument marker bytes.");
  sentences.forEach((sentence, ordinal) => {
    lines.push(...dbLines(encodeSentence(sentence), ordinal));
  });
  lines.push("MSG_TEND: ; First byte after the diagnostic text table.");
  return `${lines.join("\n")}\n`;
}

async function build() {
  const nativeCore = await loadNativeAtomCore();
  const { bytes, symbols } = await assembleCpmAtomSource(await linkCpm22Source(), { base: 0x100 });
  assert.equal(
    symbols.ASO_CBEG,
    symbols.CP_REND,
    "CP/M ASO code must follow the low resident image without a gap",
  );
  assert.ok(
    symbols.ASO_CEND <= symbols.CP_WORK,
    "CP/M ASO code exceeds the loaded-code area",
  );
  assert.equal(
    symbols.INC_ORD & 0xff,
    0,
    "CP/M part-order table must begin on a page boundary",
  );
  assert.equal(
    symbols.INC_OEND - symbols.INC_ORD,
    256,
    "CP/M part-order table must occupy one complete page",
  );
  assert.equal(
    symbols.SRC_PAGE & 0xff,
    0,
    "CP/M source cache must begin at offset zero for RES 7,L indexing",
  );
  assert.equal(
    symbols.SRC_PEND - symbols.SRC_PAGE,
    128,
    "CP/M source cache must occupy one 128-byte record",
  );
  assert.ok(
    symbols.INC_OEND <= symbols.SRC_PAGE &&
      symbols.SRC_PEND <= symbols.INC_LIST &&
      symbols.INC_LEND <= symbols.INC_DESC &&
      symbols.INC_DEND <= symbols.CP_SYMB &&
      symbols.CP_SYME <= symbols.CP_PENDB &&
      symbols.CP_PENDE <= symbols.ASO_FCB,
    "CP/M runtime data regions overlap or are out of order",
  );
  assert.equal(
    symbols.MAT_FCB,
    symbols.INC_ORD,
    "CP/M materializer must reuse the dead part-order page only after assembly",
  );
  assert.equal(
    symbols.MAT_REC,
    symbols.MAT_FCB + 36,
    "CP/M materializer FCB and ASO record buffer must be contiguous",
  );
  assert.equal(
    symbols.MAT_VARS,
    symbols.MAT_REC + 128,
    "CP/M parser state must follow its 128-byte input record",
  );
  assert.ok(
    symbols.MAT_VEND <= symbols.SRC_PAGE,
    "CP/M replay state must fit below the reusable source-cache page",
  );
  assert.equal(
    symbols.MAT_WIN,
    symbols.SRC_PEND,
    "CP/M output window must begin after the reclaimed 128-byte HEX DMA page",
  );
  assert.equal(
    symbols.ZTS_CPM_FINAL_DMA,
    symbols.SRC_PAGE,
    "HEX output must use the dead source-cache page, not the replay input record",
  );
  assert.ok(
    symbols.ZTS_CPM_FINAL_DMA + 128 <= symbols.MAT_WIN,
    "HEX DMA buffer must remain disjoint from the output replay window",
  );
  assert.ok(
    symbols.ASO_CEND <= symbols.MAT_WEND,
    "CP/M loaded code exceeds the output-memory ceiling",
  );
  assert.ok(
    symbols.MAT_WEND - symbols.MAT_WIN >= 128,
    "CP/M ASO materializer has no complete output record window",
  );
  assert.equal(
    (symbols.MAT_WEND - symbols.MAT_WIN) % 128,
    0,
    "CP/M ASO output window must contain complete sequential records",
  );
  assert.ok(
    symbols.MAT_WEND + 128 <= symbols.CP_SFLR,
    "CP/M output window must stay at least one record below the stack floor",
  );
  assert.equal(
    symbols.MAT_WEND - symbols.MAT_WIN,
    33_280,
    "CP/M output window must keep its 260-record size",
  );
  assert.equal(bytes.length, symbols.ASO_CEND - 0x100);
  const loadedRecordBytes = Math.ceil(bytes.length / 128) * 128;
  assert.ok(
    0x100 + loadedRecordBytes <= symbols.CP_WORK,
    "CP/M record padding must not overlap the uninitialised workspace",
  );
  const adapterCodeBytes = symbols.CP_CODEE - symbols.CP_CODEB;
  const adapterImmutableBytes = symbols.CP_IMME - symbols.CP_IMMB;
  const outputAdapterCodeBytes = symbols.PUB_CEND - symbols.PUB_CBEG;
  const commandTailCodeBytes = symbols.CMD_CEND - symbols.CMD_CBEG;
  const sourceAdapterCodeBytes = symbols.SRC_CEND - symbols.SRC_CBEG;
  const adapterWorkspaceBytes =
    symbols.CP_WS1E - symbols.CP_WS1B +
    symbols.CP_WS2E - symbols.CP_WS2B;
  return {
    bytes,
    report: {
      format: "atom-cpm22-census",
      version: 14,
      loadAddress: 0x100,
      entryAddress: symbols.CP_ENTRY,
      returnAddress: symbols.CP_EXIT,
      inputFcbAddress: symbols.SRC_FCB,
      sourceCacheAddress: symbols.SRC_PAGE,
      partOrderAddress: symbols.INC_ORD,
      partOrderEndAddress: symbols.INC_OEND,
      partNamesAddress: symbols.INC_LIST,
      partNamesEndAddress: symbols.INC_LEND,
      partDescriptorsAddress: symbols.INC_DESC,
      partDescriptorsEndAddress: symbols.INC_DEND,
      binaryIncludeFcbAddress: symbols.BIN_FCB,
      resolverStateAddress: symbols.INC_NCNT,
      resolverWorkspaceEndAddress: symbols.SRC_TMP + 1,
      sourceCacheKeyAddress: symbols.SRC_KEY,
      sourceReadAddress: symbols.SRC_READ,
      sourceCacheMissAddress: symbols.SRC_MISS,
      residentEnd: symbols.CP_REND,
      residentBytes: bytes.length,
      lowResidentBytes: symbols.CP_REND - 0x100,
      minimumBdosAddress: 0xe400,
      minimumTransientProgramBytes: 0xe300,
      asoOverlayStart: symbols.ASO_CBEG,
      asoOverlayEnd: symbols.ASO_CEND,
      asoOverlayBytes: symbols.ASO_CEND - symbols.ASO_CBEG,
      materializerScratchStart: symbols.MAT_FCB,
      materializerScratchEnd: symbols.MAT_VEND,
      materializerScratchBytes: symbols.MAT_VEND - symbols.MAT_FCB,
      materializerFcbAddress: symbols.MAT_FCB,
      materializerRecordAddress: symbols.MAT_REC,
      hexDmaAddress: symbols.ZTS_CPM_FINAL_DMA,
      workspaceStartAddress: symbols.CP_WORK,
      workspaceEndAddress: symbols.ASO_REC + 128,
      materializerWindowStart: symbols.MAT_WIN,
      materializerWindowBytes: symbols.MAT_WEND - symbols.MAT_WIN,
      materializerPolicy: "sequential-window-replay",
      asoRunAddress: symbols.ASO_RUN,
      asoRecordAddress: symbols.ASO_REC,
      loadedImageEnd: symbols.ASO_CEND,
      loadedImageCapacityBytes: symbols.CP_WORK - 0x100,
      loadedImageHeadroomBytes: symbols.CP_WORK - symbols.ASO_CEND,
      loadedRecordBytes,
      loadedRecordPaddingBytes: loadedRecordBytes - bytes.length,
      nativeCoreResidentBytes: nativeCore.residentExtentBytes,
      relocationHeaderBytes: 16,
      replacedHostStubBytes: 8,
      replacedSourceFallbackBytes: 5,
      adapterResidentBytes: symbols.CP_REND - 0x100 - 16 - (nativeCore.residentExtentBytes - 8 - 5),
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
      stackBytes: symbols.CP_STACK - symbols.CP_SFLR,
      stackFloorAddress: symbols.CP_SFLR,
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
