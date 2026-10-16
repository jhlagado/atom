#!/usr/bin/env node

// Generate the record figures and tables in docs/records.md from the source
// and from a real trace of one small program.
//
// Every field offset is checked against the EQU that defines it in src/z80, and
// every byte shown comes from the assembler's own memory during the trace, so
// the page cannot drift from the code. The prose between the generated blocks
// is written by hand.
//
//   node scripts/generate-records-doc.mjs           write the figures and blocks
//   node scripts/generate-records-doc.mjs --check   fail if anything is stale

import assert from "node:assert/strict";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { assembleResolvedAtomProject } from "../src/host/index.mjs";
import { line, rect, strip, svg, text, caption } from "./figures/toolkit.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = join(repositoryRoot, "src/z80");
const pagePath = join(repositoryRoot, "docs/records.md");
const figureRoot = join(repositoryRoot, "docs/images/records");
const check = process.argv.includes("--check");

// The worked example: one forward reference, one backward jump.
export const EXAMPLE = [
  "        ORG $100",
  "START:  LD A,(COUNT)",
  "        JR START",
  "COUNT:  DB 5",
  "",
].join("\n");

// ---------- the source's own definitions ----------

async function readEquates() {
  const values = new Map();
  for (const name of (await readdir(sourceRoot)).filter((file) => file.endsWith(".asm"))) {
    for (const sourceLine of (await readFile(join(sourceRoot, name), "utf8")).split("\n")) {
      const match = /^([A-Za-z][A-Za-z0-9]*)\s+EQU\s+(\$[0-9A-Fa-f]+|\d+)\b/.exec(sourceLine);
      if (match) values.set(match[1], match[2].startsWith("$") ? parseInt(match[2].slice(1), 16) : Number(match[2]));
    }
  }
  return values;
}

// Names for the values in one block of EQUs, such as the token kinds.
async function namesBetween(file, first, last) {
  const names = new Map();
  let active = false;
  for (const sourceLine of (await readFile(join(sourceRoot, file), "utf8")).split("\n")) {
    const match = /^([A-Za-z][A-Za-z0-9]*)\s+EQU\s+(\$[0-9A-Fa-f]+|\d+)\b/.exec(sourceLine);
    if (!match) continue;
    if (match[1] === first) active = true;
    if (active) {
      const value = match[2].startsWith("$") ? parseInt(match[2].slice(1), 16) : Number(match[2]);
      if (!names.has(value)) names.set(value, match[1]);
    }
    if (match[1] === last) break;
  }
  return names;
}

// Each record's fields, with the EQU that must hold its offset or size.
const RECORDS = [
  {
    id: "token", title: "Token record", size: ["tkRecLen", 11], where: "tkRecord",
    writer: "the tokenizer (tkNext)", readers: "the statement layer, expressions and the parser",
    fields: [
      ["kind", 0, 1, "tkKindAt", "Token kind: name, number, punctuation, end of line"],
      ["part", 1, 1, "tkPartAt", "Source part the token came from"],
      ["offset", 2, 2, "tkOffAt", "Byte offset of the token in its part"],
      ["line", 4, 2, "tkLineAt", "Line of the token in its part, counting from one"],
      ["lexeme", 6, 2, "tkLexAt", "Address of the token's text in the lexeme buffer"],
      ["length", 8, 1, "tkLenAt", "Length of that text in bytes"],
      ["value", 9, 2, "tkValAt", "A number's value"],
    ],
  },
  {
    id: "symbol", title: "Symbol record", size: ["syRecLen", 8], where: "the symbol arena",
    writer: "the symbol table (syRef, syDecl, syLabel)", readers: "expressions, the output layer and the driver",
    fields: [
      ["name", 0, 6, "syKeyLen", "Three RADIX-40 words. The top bits of byte 5 are flags: private $80, defined $40, signed $20"],
      ["value", 6, 2, "syValLo", "The value once defined. Until then, where the name was first used"],
    ],
  },
  {
    id: "instruction", title: "Instruction record", size: [null, 10], where: "prRec, then the caller's destination",
    writer: "the parser (prCommit)", readers: "form validation and the encoder",
    fields: [
      ["mnemonic", 0, 1, "enMnem", "Mnemonic number from mnemonic.asm"],
      ["operand 0", 1, 1, "enOp0", "Class of the first operand"],
      ["operand 1", 2, 1, "enOp1", "Class of the second operand"],
      ["operand 2", 3, 1, "enOp2", "Class of the third operand, or enNone"],
      ["value 0", 4, 2, "enVal0", "First operand's value"],
      ["value 1", 6, 2, "enVal1", "Second operand's value"],
      ["value 2", 8, 2, "enVal2", "Third operand's value"],
    ],
  },
  {
    id: "build", title: "Build reference", size: ["prRawLen", 15], where: "prRawRef",
    writer: "the parser, for an operand naming a later symbol", readers: "refBind",
    fields: [
      ["key", 0, 6, "prBKey", "The symbol's packed name"],
      ["addend", 6, 1, "prBAdd", "Signed amount added to the symbol"],
      ["operand", 7, 1, "prBOper", "Which operand refers to the symbol"],
      ["kind", 8, 1, "prBKind", "How to patch: byte, word, relative, LOW or HIGH"],
      ["field", 9, 1, "prBField", "Offset of the patched bytes in the instruction"],
      ["part", 10, 1, "prBPart", "Source part of the reference"],
      ["source", 11, 2, "prBSrc", "Source offset of the reference"],
      ["line", 13, 2, "prBLine", "Source line of the reference"],
    ],
  },
  {
    id: "public", title: "Public reference", size: ["prPubLen", 11], where: "prPubRef",
    writer: "refBind, once the symbol has a record", readers: "refCheck and refQueue",
    fields: [
      ["symbol", 0, 2, "prRSym", "Address of the symbol's record"],
      ["addend", 2, 1, "prRAdd", "Signed amount added to the symbol"],
      ["operand", 3, 1, "prROper", "Which operand refers to the symbol"],
      ["kind", 4, 1, "prRKind", "How to patch, with the anchor flag $80"],
      ["field", 5, 1, "prRField", "Offset of the patched bytes in the instruction"],
      ["part", 6, 1, "prRPart", "Source part of the reference"],
      ["source", 7, 2, "prRSrc", "Source offset of the reference"],
      ["line", 9, 2, "prRLine", "Source line of the reference"],
    ],
  },
  {
    id: "pending", title: "Pending record", size: ["syRefLen", 11], where: "the pending arena",
    writer: "refQueue, through syAdd", readers: "outFixUp, when the symbol is defined",
    fields: [
      ["symbol", 0, 2, null, "Address of the symbol's record"],
      ["address", 2, 2, null, "Address of the bytes to patch"],
      ["kind", 4, 1, null, "How to patch, in the low three bits. $80 marks the anchor"],
      ["addend", 5, 1, null, "Signed amount added to the symbol"],
      ["part", 6, 1, "syPart", "Source part of the reference"],
      ["source", 7, 2, "sySrcOff", "Source offset of the reference"],
      ["line", 9, 2, "syLine", "Source line of the reference"],
    ],
  },
  {
    id: "descriptor", title: "Build descriptor", size: ["drDscLen", 12], where: "the host's memory, passed in IX",
    writer: "the host", readers: "the driver (drAsm)",
    fields: [
      ["symbols", 0, 2, "drSymBeg", "Start of the symbol arena"],
      ["symbols end", 2, 2, "drSymEnd", "End of the symbol arena"],
      ["pending", 4, 2, "drRefBeg", "Start of the pending arena"],
      ["pending end", 6, 2, "drRefEnd", "End of the pending arena"],
      ["origin", 8, 2, "drOutBeg", "First output address"],
      ["capacity", 10, 2, "drOutCap", "Output capacity in bytes"],
    ],
  },
];

function checkRecords(equates) {
  for (const record of RECORDS) {
    const [sizeName, size] = record.size;
    if (sizeName) assert.equal(equates.get(sizeName), size, `${record.id}: ${sizeName} is not ${size}`);
    let next = 0;
    for (const [name, offset, width, equate] of record.fields) {
      assert.equal(offset, next, `${record.id}: ${name} does not follow the previous field`);
      // syKeyLen is a length that ends at the value, not an offset.
      if (equate === "syKeyLen") assert.equal(equates.get(equate), width, `${record.id}: ${equate}`);
      else if (equate) assert.equal(equates.get(equate), offset, `${record.id}: ${equate} is not ${offset}`);
      next = offset + width;
    }
    assert.equal(next, size, `${record.id}: fields do not fill the record`);
  }
}

// ---------- the trace ----------

async function runExample() {
  const bytes = Buffer.from(EXAMPLE, "latin1");
  return assembleResolvedAtomProject({
    parts: [{ ordinal: 0, bank: 0, originalBytes: bytes, compilerBytes: bytes, logicalIdentity: "EXAMPLE.ASM" }],
  }, { target: { start: 0x100, capacity: 0xff00 }, trace: true });
}

const hex2 = (value) => value.toString(16).toUpperCase().padStart(2, "0");
const hex4 = (value) => `$${value.toString(16).toUpperCase().padStart(4, "0")}`;
const word = (bytes, at) => bytes[at] | (bytes[at + 1] << 8);
const RADIX40 = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
function packedName(bytes) {
  const third = bytes[4] | ((bytes[5] & 7) << 8);
  const codes = [word(bytes, 0), word(bytes, 2)].flatMap((value) => [Math.floor(value / 1600), Math.floor(value / 40) % 40, value % 40]);
  codes.push(Math.floor(third / 40), third % 40);
  return codes.map((code) => RADIX40[code] ?? "?").join("").trimEnd();
}

// ---------- figures ----------

const CW = 46;
// One record as a row of byte cells, offsets above and field names below.
// Names alternate between two rows so short neighbouring fields never touch.
function recordRow({ x, y, record, bytes, highlight = [] }) {
  const out = [];
  const cells = [...bytes].map((value, index) => ({
    v: hex2(value),
    hi: record.fields.some(([name, offset, width]) => highlight.includes(name) && index >= offset && index < offset + width),
  }));
  out.push(strip({ x, y, cells, cw: CW, ch: 30 }));
  [...bytes].forEach((_, index) => out.push(text("dim", x + index * CW + CW / 2, y - 7, `+${index}`, "middle")));
  record.fields.forEach(([name, offset, width], index) => {
    const left = x + offset * CW + 4;
    const right = x + (offset + width) * CW - 4;
    const lower = y + 30 + (index % 2 === 0 ? 20 : 36);
    out.push(line("rule", left, y + 35, right, y + 35));
    out.push(text(highlight.includes(name) ? "nb" : "ns", (left + right) / 2, lower, name, "middle"));
  });
  return out.join("\n");
}

function figure({ id, title, desc, height, body }) {
  return [`records-${id}.svg`, svg({ title, desc, height, book: "blue", body })];
}

function figures(trace) {
  const tokens = trace.filter((event) => event.stage === "token");
  const number = tokens.find((event) => event.bytes[0] === 4);
  const instruction = trace.find((event) => event.stage === "instruction" && event.references.length === 1);
  const resolve = trace.find((event) => event.stage === "resolve" && event.pending.length === 1);
  const symbols = trace.find((event) => event.stage === "symbols").records;
  const count = symbols.find((record) => packedName(record.bytes) === "COUNT");
  const byId = Object.fromEntries(RECORDS.map((record) => [record.id, record]));
  const out = [];

  out.push(figure({
    id: "token", height: 150,
    title: "The token record for $100",
    desc: "Eleven bytes: kind 4 for a number, part 0, offset 12, line 1, the lexeme's address and length, and the value $0100 stored low byte first.",
    body: [caption(60, 22, "TOKEN RECORD  $100  LINE 1"), recordRow({ x: 60, y: 46, record: byId.token, bytes: number.bytes, highlight: ["value"] })].join("\n"),
  }));
  out.push(figure({
    id: "symbol", height: 150,
    title: "The symbol record for COUNT",
    desc: `Eight bytes: COUNT packed into three RADIX-40 words with the defined flag set in byte 5, then the value ${hex4(word(count.bytes, 6))}.`,
    body: [caption(60, 22, `SYMBOL RECORD  COUNT  AT ${hex4(count.address)}`), recordRow({ x: 60, y: 46, record: byId.symbol, bytes: count.bytes, highlight: ["value"] })].join("\n"),
  }));
  out.push(figure({
    id: "instruction", height: 270,
    title: "LD A,(COUNT) as an instruction record and its reference",
    desc: "The ten-byte record holds the mnemonic, the operand classes and a zero placeholder where COUNT's address will go. The eleven-byte public reference points at COUNT's symbol record and says to patch a word at offset 1 of the instruction.",
    body: [
      caption(60, 22, "INSTRUCTION RECORD  LD A,(COUNT)"),
      recordRow({ x: 60, y: 46, record: byId.instruction, bytes: instruction.bytes, highlight: ["value 1"] }),
      caption(60, 152, "PUBLIC REFERENCE"),
      recordRow({ x: 60, y: 176, record: byId.public, bytes: instruction.references[0], highlight: ["symbol", "field"] }),
    ].join("\n"),
  }));
  out.push(figure({
    id: "pending", height: 150,
    title: "The pending record waiting for COUNT",
    desc: `Eleven bytes: COUNT's record address, the patch address ${hex4(word(resolve.pending[0], 2))}, a word patch with the anchor flag, addend 0 and the reference's source position and line.`,
    body: [caption(60, 22, "PENDING RECORD  UNTIL COUNT IS DEFINED"), recordRow({ x: 60, y: 46, record: byId.pending, bytes: resolve.pending[0], highlight: ["address"] })].join("\n"),
  }));

  const before = [0x3a, 0x00, 0x00, 0x18, 0xfb, 0x05];
  out.push(figure({
    id: "patch", height: 230,
    title: "COUNT's address patched into the output",
    desc: "The output bytes from $0100 before and after COUNT is defined. The two placeholder bytes at $0101 become 05 01, little-endian $0105.",
    body: [
      caption(60, 22, "IMAGE  AS EMITTED"),
      strip({ x: 60, y: 50, cells: before.map((value, index) => ({ v: hex2(value), hi: index === 1 || index === 2 })), base: 0x100, cw: 64 }),
      text("ns", 60 + 6 * 64 + 16, 70, "LD A,($0000)  JR START  DB 5"),
      caption(60, 132, "AFTER PATCH  $0101"),
      strip({ x: 60, y: 160, cells: before.map((value, index) => ({ v: hex2(index === 1 ? 0x05 : index === 2 ? 0x01 : value), hi: index === 1 || index === 2 })), base: 0x100, cw: 64 }),
      text("ns", 60 + 6 * 64 + 16, 180, "LD A,($0105)  JR START  DB 5"),
    ].join("\n"),
  }));
  return out;
}

// ---------- tables ----------

function layoutTables() {
  return RECORDS.map((record) => [
    `### ${record.title}`,
    "",
    `${record.size[1]} bytes in ${record.where}. Written by ${record.writer}. Read by ${record.readers}.`,
    "",
    "| Offset | Size | Field | Meaning |",
    "| ---: | ---: | --- | --- |",
    ...record.fields.map(([name, offset, width, equate, meaning]) =>
      `| ${offset} | ${width} | ${name}${equate ? ` (\`${equate}\`)` : ""} | ${meaning} |`),
    "",
  ].join("\n")).join("\n");
}

async function traceTables(result) {
  const kinds = await namesBetween("tokcore.asm", "tkEof", "tkHere");
  const classes = await namesBetween("insrec.asm", "enRegB", "enNone");
  const mnemonics = await namesBetween("mnemonic.asm", "mneNop", "mneLast");
  const sourceLines = EXAMPLE.split("\n");
  const lexeme = (event) => {
    const bytes = event.bytes;
    if (bytes[0] === 1) return "end of line";
    const at = word(bytes, 2);
    const textAt = EXAMPLE.slice(at, at + bytes[6]);
    return bytes[0] === 4 ? `${textAt} = ${hex4(word(bytes, 7))}` : `\`${textAt}\``;
  };
  const tokens = result.trace.filter((event) => event.stage === "token");
  const instructions = result.trace.filter((event) => event.stage === "instruction");
  const resolves = result.trace.filter((event) => event.stage === "resolve");
  const symbols = result.trace.find((event) => event.stage === "symbols").records;
  const bytesOf = (bytes) => [...bytes].map(hex2).join(" ");
  const operand = (value) => classes.get(value) ?? String(value);
  return [
    "```asm",
    EXAMPLE.trimEnd(),
    "```",
    "",
    "**Tokens.** Each line becomes a run of tokens ending in an end of line.",
    "",
    "| Line | Kind | Text |",
    "| ---: | --- | --- |",
    ...tokens.map((event) => `| ${event.source.line} | \`${kinds.get(event.bytes[0]) ?? event.bytes[0]}\` | ${lexeme(event)} |`),
    "",
    "**Instruction records.** The parser commits one per instruction.",
    "",
    "| Line | Bytes | Mnemonic | Operands | References |",
    "| ---: | --- | --- | --- | ---: |",
    ...instructions.map((event) => `| ${event.source.line} | \`${bytesOf(event.bytes)}\` | \`${mnemonics.get(event.bytes[0]) ?? event.bytes[0]}\` | ${[1, 2, 3].map((index) => `\`${operand(event.bytes[index])}\``).join(", ")} | ${event.references.length} |`),
    "",
    "**Public reference** for `LD A,(COUNT)`: " + instructions.filter((event) => event.references.length).map((event) => `\`${bytesOf(event.references[0])}\``).join(", ") + ".",
    "",
    "**Definitions.** Each label resolves the pending records for its symbol.",
    "",
    "| Line | Symbol record | Pending records |",
    "| ---: | --- | --- |",
    ...resolves.map((event) => `| ${event.source.line} | ${hex4(event.symbol)} | ${event.pending.length ? event.pending.map((record) => `\`${bytesOf(record)}\``).join("<br>") : "none"} |`),
    "",
    "**Output.** IMAGE operations emit bytes as each line is assembled, and PATCH operations fill in later.",
    "",
    "| Operation | Address | Bytes | Line |",
    "| --- | --- | --- | ---: |",
    ...result.generation.images.map((image) => `| IMAGE | ${hex4(image.address)} | ${(image.bytes ?? [image.value]).map(hex2).join(" ")} | ${image.source?.line ?? ""} |`),
    ...result.generation.patches.map((patch) => `| PATCH | ${hex4(patch.address)} | ${patch.bytes.map(hex2).join(" ")} | ${patch.source?.line ?? ""} |`),
    "",
    "**Symbols** at the end, in table order.",
    "",
    "| Record | Bytes | Name | Value |",
    "| --- | --- | --- | --- |",
    ...symbols.map((record) => `| ${hex4(record.address)} | \`${bytesOf(record.bytes)}\` | ${packedName(record.bytes)} | ${hex4(word(record.bytes, 6))} |`),
    "",
  ].join("\n");
}

// ---------- page ----------

function replaceBlock(page, name, content) {
  const begin = `<!-- generated:${name} -->`;
  const end = `<!-- end:${name} -->`;
  const start = page.indexOf(begin);
  const finish = page.indexOf(end);
  assert.ok(start >= 0 && finish > start, `docs/records.md lacks the ${name} block`);
  return `${page.slice(0, start + begin.length)}\n${content.trimEnd()}\n${page.slice(finish)}`;
}

const equates = await readEquates();
checkRecords(equates);
const result = await runExample();
let page = await readFile(pagePath, "utf8");
page = replaceBlock(page, "layouts", layoutTables());
page = replaceBlock(page, "trace", await traceTables(result));
const svgs = figures(result.trace);

if (check) {
  assert.equal(await readFile(pagePath, "utf8"), page, "docs/records.md is stale: run node scripts/generate-records-doc.mjs");
  for (const [name, content] of svgs) {
    assert.equal(await readFile(join(figureRoot, name), "utf8"), content, `${name} is stale`);
  }
  console.log(`docs/records.md and ${svgs.length} figures are current.`);
} else {
  await writeFile(pagePath, page);
  await mkdir(figureRoot, { recursive: true });
  for (const [name, content] of svgs) await writeFile(join(figureRoot, name), content);
  console.log(`Wrote docs/records.md and ${svgs.length} figures.`);
}
