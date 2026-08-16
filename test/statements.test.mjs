import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createStatementsHarness } from "./statements-support.mjs";
import { azmBytes } from "./support.mjs";

const h = await createStatementsHarness();
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2g-memory.json", "utf8"));
const STATUS = Object.freeze({
  OK: 0,
  NOT_FOUND: 1,
  DUPLICATE: 2,
  SYMBOL_CAPACITY: 3,
  PRIVATE_NO_SCOPE: 4,
  UNDEFINED_PRIVATE: 5,
  PENDING_INVARIANT: 7,
});
const STATEMENT = Object.freeze({
  OK: 0,
  EXPECTED: 2,
  DIRECTIVE: 3,
  EQUATE: 4,
  SYMBOL: 5,
  INSTRUCTION: 6,
  OUTPUT: 7,
});

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing statement proof symbol ${value}`);
  return h.symbols[value];
}

test("Phase 2g memory profile covers exactly 64 KiB without gaps or overlap", () => {
  const regions = memoryProfile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(regions[0].startAddress, 0);
  for (const [index, region] of regions.entries()) {
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
  }
  assert.equal(regions.at(-1).endAddress, memoryProfile.addressSpaceBytes);
  for (const extent of memoryProfile.extents) {
    if (extent.sum) {
      const total = extent.sum.reduce((sum, [start, end]) => sum + resolve(end) - resolve(start), 0);
      assert.equal(total, extent.exactBytes, `${extent.name}: extent drift`);
    } else {
      assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
    }
  }
});

test("published mnemonic continuation preserves the existing parser record", () => {
  const item = validCases().find(({ source }) => source === "LD A,$01");
  assert.ok(item);
  const parsed = h.parsePublished(item.source);
  assert.equal(parsed.carry, 0);
  assert.deepEqual(h.record(), Array.from(item.record));
  const execution = JSON.parse(fs.readFileSync("proofs/phase-2g.json", "utf8")).executionBudgets;
  for (const [entry, observed] of Object.entries(h.statistics)) {
    assert.equal(observed.instructions, execution[entry].measuredInstructions, `${entry}: measured instruction drift`);
    assert.equal(observed.cycles, execution[entry].measuredCycles, `${entry}: measured cycle drift`);
  }
});

test("global label declaration closes private scope atomically", () => {
  h.reset();
  const first = h.pack("First").key;
  assert.equal(h.declareGlobalLabel(first, 0x4000).status, STATUS.OK);
  const local = h.pack(".Done").key;
  assert.equal(h.declare(local, 0x4001).status, STATUS.OK);
  const localPointer = h.find(local).ix;
  const second = h.pack("Second").key;
  assert.equal(h.declareGlobalLabel(second, 0x4010).status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
  assert.equal(h.find(first).status, STATUS.OK);
  assert.equal(h.find(second).status, STATUS.OK);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), h.symbols.AtomStatementSymbolLimit);
  assert.ok(localPointer >= h.stateWord("AtomSymbolGlobalEnd"));
});

test("global label transaction preserves scope and records on every preflight failure", () => {
  h.reset();
  const first = h.pack("First").key;
  assert.equal(h.declareGlobalLabel(first, 0x4000).status, STATUS.OK);
  const local = h.pack(".Forward").key;
  assert.equal(h.reference(local).status, STATUS.OK);
  const second = h.pack("Second").key;
  let beforeArena = h.symbolArena();
  let beforeBegin = h.stateWord("AtomSymbolLocalBegin");
  let beforeGlobal = h.stateWord("AtomSymbolGlobalEnd");
  let result = h.declareGlobalLabel(second, 0x4010);
  assert.equal(result.status, STATUS.UNDEFINED_PRIVATE);
  assert.deepEqual(h.symbolArena(), beforeArena);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), beforeBegin);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), beforeGlobal);

  assert.equal(h.declare(local, 0x4002).status, STATUS.OK);
  beforeArena = h.symbolArena();
  beforeBegin = h.stateWord("AtomSymbolLocalBegin");
  result = h.declareGlobalLabel(first, 0x5000);
  assert.equal(result.status, STATUS.DUPLICATE);
  assert.deepEqual(h.symbolArena(), beforeArena);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), beforeBegin);
});

test("global label capacity uses the post-eviction gap at exact boundaries", () => {
  for (const [bytes, expected] of [[7, STATUS.SYMBOL_CAPACITY], [8, STATUS.OK], [9, STATUS.OK]]) {
    h.reset({ symbolBytes: bytes });
    const key = h.pack("Bound").key;
    const before = h.symbolArena();
    const result = h.declareGlobalLabel(key, 0x4000);
    assert.equal(result.status, expected, `${bytes} bytes`);
    if (expected === STATUS.SYMBOL_CAPACITY) assert.deepEqual(h.symbolArena(), before);
  }

  h.reset({ symbolBytes: 16 });
  assert.equal(h.declareGlobalLabel(h.pack("First").key, 0x4000).status, STATUS.OK);
  const local = h.pack(".Local").key;
  assert.equal(h.declare(local, 0x4001).status, STATUS.OK);
  assert.equal(h.declareGlobalLabel(h.pack("Second").key, 0x4010).status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), h.symbols.AtomStatementSymbolArena + 16);
});

test("stale private pending state blocks a global label without mutation", () => {
  h.reset();
  assert.equal(h.declareGlobalLabel(h.pack("First").key, 0x4000).status, STATUS.OK);
  const local = h.pack(".Target").key;
  const reference = h.reference(local);
  assert.equal(reference.status, STATUS.OK);
  assert.equal(h.pendingAdd(reference.ix, 0x5001).status, STATUS.OK);
  assert.equal(h.declare(local, 0x4100).status, STATUS.OK);
  const beforeArena = h.symbolArena();
  const beforePending = h.pendingArena();
  const beforeBegin = h.stateWord("AtomSymbolLocalBegin");
  const result = h.declareGlobalLabel(h.pack("Second").key, 0x4200);
  assert.equal(result.status, STATUS.PENDING_INVARIANT);
  assert.deepEqual(h.symbolArena(), beforeArena);
  assert.deepEqual(h.pendingArena(), beforePending);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), beforeBegin);
});

test("statement-mode scope advance validates and evicts a defined private", () => {
  h.reset();
  assert.equal(h.advanceScope().status, STATUS.OK);
  const local = h.pack(".Local").key;
  assert.equal(h.declare(local, 0x4000).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
});

test("statement path assembles blank lines, labels, and instructions", () => {
  let result = h.assemble("; comment\n\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.operations(), []);

  result = h.assemble("Start:\n  LD A,$42\n.Loop: DJNZ .Loop\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x3e, 0x42, 0x10, 0xfe]);
  assert.deepEqual(h.outputState(), { cursor: 0x4004, remaining: 0xfc });

  result = h.assemble("aGaIn: jR AgAiN\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x18, 0xfe]);
});

test("forward global references resolve to append-only patch bytes", () => {
  const result = h.assemble("JR Later\nNOP\nLater:\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0x4000, bytes: [0x18] },
    { kind: 1, bank: 0, address: 0x4001, bytes: [0x00] },
    { kind: 1, bank: 0, address: 0x4002, bytes: [0x00] },
    { kind: 2, bank: 0, address: 0x4001, bytes: [0x01] },
  ]);
  assert.deepEqual(h.finalBytes(), [0x18, 0x01, 0x00]);
});

test("statement integration is byte-identical to AZM for every supported instruction form", () => {
  for (const [index, item] of validCases().entries()) {
    const result = h.assemble(`${item.source}\n`);
    assert.equal(result.status, STATEMENT.OK, `${index}: ${item.source}`);
    assert.deepEqual(h.finalBytes(), azmBytes(item.source), `${index}: ${item.source}`);
  }
});

test("a private label before the first global is rejected without output", () => {
  const result = h.assemble(".Local: NOP\n");
  assert.equal(result.status, STATEMENT.SYMBOL);
  assert.equal(result.detail, STATUS.PRIVATE_NO_SCOPE);
  assert.deepEqual(h.operations(), []);
  assert.deepEqual(h.outputState(), { cursor: 0x4000, remaining: 0x100 });
});

test("unknown statements and invalid instructions retain their nested category", () => {
  for (const source of ["Unknown thing\n", "CSTX \"A\"\n", "PSTX \"A\"\n", "ISTX \"A\"\n", "ALIXY 4\n", "ALIGNX 4\n"]) {
    const result = h.assemble(source);
    assert.equal(result.status, STATEMENT.EXPECTED, source);
    assert.deepEqual(h.operations(), []);
  }

  const result = h.assemble("LD BC,A\n");
  assert.equal(result.status, STATEMENT.INSTRUCTION);
  assert.deepEqual(h.operations(), []);
});

test("bare EQU is case-insensitive and byte-identical to AZM", () => {
  const source = "Value eQu $42\nLD A,vAlUe\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), azmBytes("Value EQU $42\nLD A,Value\n"));
  assert.deepEqual(h.finalBytes(), [0x3e, 0x42]);
});

test("colon EQU is an equate, not an address label, and matches AZM", () => {
  const source = "Value: eQu 100\nLD A,VALUE\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), azmBytes("Value: .equ 100\nLD A,Value\n"));
  assert.equal(h.find(h.pack("Value").key).status, STATUS.OK);
});

test("colon EQU preserves private scope and resolves earlier references", () => {
  const source = "Routine:\n.Local: EQU 3\nLD A,Forward\nValue: EQU 4\nForward: EQU $42\nLD B,.LOCAL\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x3e, 0x42, 0x06, 3]);
});

test("malformed and duplicate colon EQU forms publish nothing new", () => {
  let result = h.assemble("Value: EQU Missing+1\n");
  assert.equal(result.status, STATEMENT.EQUATE);
  assert.equal(h.find(h.pack("Value").key).status, STATUS.NOT_FOUND);

  result = h.assemble("Value EQU 1\nValue: EQU 2\n");
  assert.equal(result.status, STATEMENT.SYMBOL);
  const found = h.find(h.pack("Value").key);
  assert.equal(found.status, STATUS.OK);
  assert.equal(h.memory[found.ix + 6] | (h.memory[found.ix + 7] << 8), 1);
});

test("global EQU leaves the current private scope open", () => {
  const source = "Routine:\n.Local EQU 3\nValue EQU 4\nLD A,.local\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x3e, 0x03]);
  assert.equal(h.find(h.pack(".LOCAL").key).status, STATUS.OK);
});

test("a later EQU resolves an earlier instruction patch", () => {
  const result = h.assemble("LD A,Value\nValue EQU $42\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0x4000, bytes: [0x3e] },
    { kind: 1, bank: 0, address: 0x4001, bytes: [0x00] },
    { kind: 2, bank: 0, address: 0x4001, bytes: [0x42] },
  ]);
  assert.deepEqual(h.finalBytes(), [0x3e, 0x42]);
});

test("EQU accepts the proved expression domain and word boundaries", () => {
  const source = [
    "Low EQU -32768",
    "High EQU 65535",
    "Calc EQU ((2+3)*4)|1",
    "LD HL,Low",
    "LD DE,High",
    "LD A,Calc",
    "",
  ].join("\n");
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), azmBytes(source));
});

test("forward-dependent and malformed EQU publish no declaration", () => {
  let result = h.assemble("Alpha EQU Beta+1\nBeta EQU 16\n");
  assert.equal(result.status, STATEMENT.EQUATE);
  assert.equal(result.detail, 1);
  assert.equal(h.find(h.pack("Alpha").key).status, STATUS.NOT_FOUND);
  assert.equal(h.find(h.pack("Beta").key).status, STATUS.NOT_FOUND);
  assert.deepEqual(h.operations(), []);

  result = h.assemble("Value EQU 1,2\n");
  assert.equal(result.status, STATEMENT.EQUATE);
  assert.equal(h.find(h.pack("Value").key).status, STATUS.NOT_FOUND);
  assert.deepEqual(h.operations(), []);
});

test("private EQU requires a global scope and duplicate EQU is atomic", () => {
  let result = h.assemble(".Value EQU 1\n");
  assert.equal(result.status, STATEMENT.SYMBOL);
  assert.equal(result.detail, STATUS.PRIVATE_NO_SCOPE);

  result = h.assemble("Value EQU 1\nValue EQU 2\n");
  assert.equal(result.status, STATEMENT.SYMBOL);
  assert.equal(result.detail, STATUS.DUPLICATE);
  const found = h.find(h.pack("Value").key);
  assert.equal(found.status, STATUS.OK);
  assert.equal(h.memory[found.ix + 6] | (h.memory[found.ix + 7] << 8), 1);
});

test("bare ORG, DB, and DW are case-insensitive and match AZM", () => {
  const source = "oRg $5000\ndB 1,$FF,-1,256\ndW $1234,-1\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(0x5000), [1, 0xff, 0xff, 0, 0x34, 0x12, 0xff, 0xff]);
  assert.deepEqual(h.finalBytes(0x5000), azmBytes("ORG $5000\nDB 1,$FF,-1,256\nDW $1234,-1\n"));
});

test("DB decodes the tokenizer's one byte-string encoding", () => {
  const source = 'DB "A\\n\\x42",0,"\\\\\\\""\n';
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x41, 0x0a, 0x42, 0, 0x5c, 0x22]);
  assert.deepEqual(h.finalBytes(), azmBytes("DB $41,$0A,$42,0,$5C,$22\n"));

  const failed = h.assemble('DB "ABC"\n', { capacity: 2 });
  assert.equal(failed.status, STATEMENT.OUTPUT);
  assert.deepEqual(h.operations(), []);
});

test("character literals compose with expressions and instruction operands", () => {
  const source = "DB 'A','a'+1,';'\nLD A,'A'\nEX AF,AF'\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x41, 0x62, 0x3b, 0x3e, 0x41, 0x08]);
  assert.deepEqual(h.finalBytes().slice(0, 2), azmBytes("DB 'A','a'+1"));
  assert.deepEqual(h.finalBytes().slice(3, 5), azmBytes("LD A,'A'"));
  assert.deepEqual(h.finalBytes().slice(5), azmBytes("EX AF,AF'"));
});

test("LOW and HIGH patch forward data and instruction bytes exactly", () => {
  const source = [
    "ORG 4000H",
    "DB LOW(TARGET),HIGH(TARGET)",
    "DW LOW(TARGET),HIGH(TARGET)",
    "LD A,LOW(TARGET)",
    "LD HL,HIGH(TARGET)",
    "TARGET:",
    "NOP",
    "",
  ].join("\n");
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [
    0x0b, 0x40, 0x0b, 0, 0x40, 0,
    0x3e, 0x0b, 0x21, 0x40, 0, 0,
  ]);
  const low = azmBytes("LD A,LSB(400BH)")[1];
  const high = azmBytes("LD A,MSB(400BH)")[1];
  assert.deepEqual(h.finalBytes().slice(0, 6), [low, high, low, 0, high, 0]);
  assert.deepEqual(h.finalBytes().slice(6), [
    ...azmBytes("LD A,LSB(400BH)"),
    ...azmBytes("LD HL,MSB(400BH)"),
    ...azmBytes("NOP"),
  ]);
});

test("forward byte functions reject contexts whose range rule cannot be retained", () => {
  for (const source of [
    "JR LOW(TARGET)\nTARGET:\n",
    "LD A,(IX+HIGH(TARGET))\nTARGET:\n",
    "DB LOW(TARGET)+1\nTARGET:\n",
  ]) {
    const result = h.assemble(source);
    assert.notEqual(result.status, STATEMENT.OK, source);
    assert.deepEqual(h.operations(), [], source);
  }
});

test("CSTR, PSTR, and ISTR are case-insensitive and byte-identical to AZM", () => {
  const source = 'cStR "OK"\nPsTr "AB"\nISTR "OK"\nISTR ""\n';
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x4f, 0x4b, 0, 2, 0x41, 0x42, 0x4f, 0xcb]);
  assert.deepEqual(h.finalBytes(), azmBytes('.cstr "OK"\n.pstr "AB"\n.istr "OK"\n.istr ""\n'));

  assert.equal(h.assemble('PSTR "A\\n"\n').status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [2, 0x41, 0x0a]);
});

test("string directives preflight exact capacity and reject extra operands atomically", () => {
  for (const [source, capacity, status, bytes] of [
    ['CSTR "A"\n', 1, STATEMENT.OUTPUT, []],
    ['CSTR "A"\n', 2, STATEMENT.OK, [0x41, 0]],
    ['PSTR "AB"\n', 2, STATEMENT.OUTPUT, []],
    ['PSTR "AB"\n', 3, STATEMENT.OK, [2, 0x41, 0x42]],
    ['ISTR "A"\n', 0, STATEMENT.OUTPUT, []],
    ['ISTR "A"\n', 1, STATEMENT.OK, [0xc1]],
    ['ISTR ""\n', 0, STATEMENT.OK, []],
    ['CSTR "A",1\n', 16, STATEMENT.DIRECTIVE, []],
    ['PSTR "A" "B"\n', 16, STATEMENT.DIRECTIVE, []],
  ]) {
    const result = h.assemble(source, { capacity });
    assert.equal(result.status, status, source);
    assert.deepEqual(h.operations(), bytes.map((byte, index) => ({
      kind: 1, bank: 0, address: 0x4000 + index, bytes: [byte],
    })), source);
  }
});

test("labels compose with all three string directives", () => {
  const source = 'C: CSTR "A"\nP: PSTR "BC"\nI: ISTR "D"\nDW C,P,I\n';
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x41, 0, 2, 0x42, 0x43, 0xc4, 0x00, 0x40, 0x02, 0x40, 0x05, 0x40]);
});

test("labels compose with DB, DW, and uninitialized DS reservations", () => {
  const source = [
    "ORG $4100",
    "Start: DB 1,2",
    "Words: DW Start,Words",
    "Gap: DS 2",
    "After: DB $FF",
    "",
  ].join("\n");
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(0x4100), [1, 2, 0x00, 0x41, 0x02, 0x41, 0, 0, 0xff]);
  assert.deepEqual(h.finalBytes(0x4100), azmBytes(source));
  assert.deepEqual(h.outputState(), { cursor: 0x4109, remaining: 0xf7 });
});

test("each data-list expression sees its own current output address", () => {
  const source = "ORG $4000\nDB $,$\nDW $,$\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(), [0x00, 0x01, 0x02, 0x40, 0x04, 0x40]);
  assert.deepEqual(h.finalBytes(), azmBytes(source));
});

test("DS supports zero, trailing reservations, and an optional fill byte", () => {
  let result = h.assemble("ORG $5000\nDB 1\nDS 3\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(0x5000), [1]);
  assert.deepEqual(h.outputState(), { cursor: 0x5004, remaining: 0xfc });

  result = h.assemble("ORG $5000\nDS 0,$AA\nDS 3,$AA\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(0x5000), [0xaa, 0xaa, 0xaa]);
  assert.deepEqual(h.finalBytes(0x5000), azmBytes("ORG $5000\nDS 0,$AA\nDS 3,$AA\n"));
});

test("ALIGN emits AZM-compatible initialized zero padding", () => {
  const source = "ORG 0101H\nDB 0AAH\nALIGN 4\nALIGNED:\nDB 055H\nALIGN 6\nDB 066H\n";
  const result = h.assemble(source);
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.finalBytes(0x0101), azmBytes(source.replaceAll(/\b(ORG|DB|ALIGN)\b/g, (name) => `.${name.toLowerCase()}`)));
  assert.deepEqual(h.finalBytes(0x0101), [0xaa, 0, 0, 0x55, 0, 0, 0, 0x66]);
  const aligned = h.find(h.pack("ALIGNED").key);
  assert.equal(aligned.status, STATUS.OK);
  assert.equal(h.memory[aligned.ix + 6] | (h.memory[aligned.ix + 7] << 8), 0x0104);
});

test("ALIGN validates resolution, positivity, delimiter, and capacity atomically", () => {
  for (const source of ["ALIGN 0\n", "ALIGN -1\n", "ALIGN MISSING\n", "ALIGN 4,0\n"]) {
    const result = h.assemble(source);
    assert.equal(result.status, STATEMENT.DIRECTIVE, source);
    assert.deepEqual(h.operations(), [], source);
  }

  const result = h.assemble("DB 1\nALIGN 4\n", { address: 0x4000, capacity: 2 });
  assert.equal(result.status, STATEMENT.OUTPUT);
  assert.deepEqual(h.finalBytes(), [1]);

  const maximum = h.assemble("ALIGN 65535\n", { address: 0, capacity: 0 });
  assert.equal(maximum.status, STATEMENT.OK);
  assert.deepEqual(h.operations(), []);
});

test("forward DB and DW expressions publish exact truncating and word patches", () => {
  const result = h.assemble("DB Byte+1\nDW Word\nByte EQU -1\nWord:\n");
  assert.equal(result.status, STATEMENT.OK);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0x4000, bytes: [0] },
    { kind: 1, bank: 0, address: 0x4001, bytes: [0] },
    { kind: 1, bank: 0, address: 0x4002, bytes: [0] },
    { kind: 2, bank: 0, address: 0x4000, bytes: [0] },
    { kind: 2, bank: 0, address: 0x4001, bytes: [3, 0x40] },
  ]);
  assert.deepEqual(h.finalBytes(), [0, 3, 0x40]);
});

test("directive resolution and capacity failures preserve preflight atomicity", () => {
  let result = h.assemble("ORG Forward\n");
  assert.equal(result.status, STATEMENT.DIRECTIVE);
  assert.deepEqual(h.operations(), []);
  assert.equal(h.find(h.pack("Forward").key).status, STATUS.NOT_FOUND);

  result = h.assemble("DB Forward\n", { pendingBytes: 5 });
  assert.equal(result.status, STATEMENT.SYMBOL);
  assert.deepEqual(h.operations(), []);
  assert.equal(h.find(h.pack("Forward").key).status, STATUS.NOT_FOUND);

  result = h.assemble("DW Forward\n", { capacity: 1 });
  assert.equal(result.status, STATEMENT.OUTPUT);
  assert.deepEqual(h.operations(), []);
  assert.equal(h.find(h.pack("Forward").key).status, STATUS.NOT_FOUND);
});

test("empty lists, trailing commas, and unresolved DS operands are rejected", () => {
  for (const source of ["DB\n", "DW 1,\n", "DS Forward\n", "DS 2,Forward\n"]) {
    const result = h.assemble(source);
    assert.equal(result.status, STATEMENT.DIRECTIVE, source);
  }
});

test("dot-prefixed words are private symbols, never assembler directives", () => {
  for (const source of [".org $4000\n", ".db 1\n", ".dw 1\n", ".ds 1\n", ".equ 1\n"]) {
    const result = h.assemble(source);
    assert.equal(result.status, STATEMENT.EXPECTED, source);
    assert.deepEqual(h.operations(), []);
  }
});

test("directive output helpers return directly and enforce exact capacities", () => {
  h.resetAssembly({ pendingBytes: 5, capacity: 2 });
  assert.equal(h.pendingCheckCapacity().carry, 1);
  assert.equal(h.outputCheckCapacity(2).carry, 0);
  assert.equal(h.outputCheckCapacity(3).carry, 1);
  assert.deepEqual(h.outputState(), { cursor: 0x4000, remaining: 2 });
  assert.equal(h.outputEmitWord(0x1234).carry, 0);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0x4000, bytes: [0x34] },
    { kind: 1, bank: 0, address: 0x4001, bytes: [0x12] },
  ]);

  h.resetAssembly({ capacity: 1 });
  assert.equal(h.outputEmitWord(0x1234).carry, 1);
  assert.deepEqual(h.operations(), []);
  assert.equal(h.outputEmitByte(0x56).carry, 0);
  assert.deepEqual(h.operations(), [{ kind: 1, bank: 0, address: 0x4000, bytes: [0x56] }]);

  h.resetAssembly({ capacity: 4 });
  assert.equal(h.outputReserve(3).carry, 0);
  assert.deepEqual(h.outputState(), { cursor: 0x4003, remaining: 1 });
  assert.equal(h.outputSetOrigin(0x5000).carry, 0);
  assert.deepEqual(h.outputState(), { cursor: 0x5000, remaining: 1 });
});

test("Phase 2g measured public-entry execution matches the pinned observations", () => {
  const execution = JSON.parse(fs.readFileSync("proofs/phase-2g.json", "utf8")).executionBudgets;
  for (const [entry, budget] of Object.entries(execution)) {
    const observed = h.statistics[entry];
    assert.ok(observed, `${entry}: no runtime observation`);
    assert.equal(observed.instructions, budget.measuredInstructions, `${entry}: measured instruction drift`);
    assert.equal(observed.cycles, budget.measuredCycles, `${entry}: measured cycle drift`);
    assert.ok(observed.instructions <= budget.maxInstructions, `${entry}: instruction budget exceeded`);
    assert.ok(observed.cycles <= budget.maxCycles, `${entry}: cycle budget exceeded`);
  }
});
