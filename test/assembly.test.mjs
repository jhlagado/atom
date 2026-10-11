// Exercise complete native assembly, including references and output transactions.
// Failures must retain source diagnostics and permit the next generation to begin.

import assert from "node:assert/strict";
import test from "node:test";

import { packRadix40 } from "../src/host/abi.mjs";
import { createDriverHarness } from "./driver-support.mjs";
import { validCases, invalidCases } from "./cases.mjs";
import { referenceRejects, referenceBytes } from "./reference-fixtures.mjs";

const h = await createDriverHarness();
const STATUS = Object.freeze({
  OK: 0,
  CONFIGURATION: 1,
  SOURCE: 2,
  UNDEFINED: 3,
  OUTPUT: 4,
  INTERNAL: 5,
});
const CONFIG = Object.freeze({
  PART_COUNT: 1,
  TABLE_RANGE: 2,
  PART_ORDINAL: 3,
  SOURCE_RANGE: 4,
  SYMBOL_RANGE: 5,
  PENDING_RANGE: 6,
  OUTPUT_RANGE: 7,
});

function packedName(name) {
  const payload = name.startsWith(".") ? name.slice(1) : name;
  return packRadix40(payload).flatMap((value) => [value & 0xff, value >>> 8]);
}

test("native driver assembles ordered parts and commits one generation", () => {
  const parts = [
    "Value EQU $42\nJR Start\n",
    "Start: LD A,Value\n",
  ];
  const result = h.assemble(parts);
  assert.equal(result.status, STATUS.OK);
  assert.equal(result.carry, 0);
  assert.deepEqual(h.finalBytes(), referenceBytes(parts.join("")));
  assert.deepEqual(h.finalBytes(), [0x18, 0x00, 0x3e, 0x42]);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 1,
    aborted: 0,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: h.symbols.AtomDriverBuildDescriptor,
    cursor: 0x4004,
    remaining: 0xfc,
    highWater: 0x4004,
    geometryFlags: 0,
  });
});

test("COMMIT carries explicit 17-bit cursor and high-water endpoints", () => {
  let result = h.assemble(["DB 42H\n"], { address: 0xffff, capacity: 1 });
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(
    {
      cursor: h.lifecycle().cursor,
      highWater: h.lifecycle().highWater,
      remaining: h.lifecycle().remaining,
      geometryFlags: h.lifecycle().geometryFlags,
    },
    { cursor: 0, highWater: 0, remaining: 0, geometryFlags: 3 },
  );

  result = h.assemble(
    ["ORG 0FFFFH\nDS 1\nORG 1\n"],
    { address: 1, capacity: 0xffff },
  );
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(
    {
      cursor: h.lifecycle().cursor,
      highWater: h.lifecycle().highWater,
      remaining: h.lifecycle().remaining,
      geometryFlags: h.lifecycle().geometryFlags,
    },
    { cursor: 1, highWater: 0, remaining: 0xfffe, geometryFlags: 2 },
  );
});

test("private scope crosses a source-part boundary and closes only at a global label", () => {
  const parts = [
    "Routine:\nJR .Later\n",
    ".Later: NOP\n",
    "Next: LD HL,Routine\n",
  ];
  const result = h.assemble(parts);
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), referenceBytes(parts.join("")));
  assert.deepEqual(h.finalBytes(), [0x18, 0x00, 0x00, 0x21, 0x00, 0x40]);
});

test("resolved forward references reclaim diagnostic anchors before finalization", () => {
  const result = h.assemble(["DW Target\n", "Target: DB 1\n"]);
  assert.equal(result.status, STATUS.OK);
  assert.equal(h.memory[h.symbols.AtomPendingNext] | (h.memory[h.symbols.AtomPendingNext + 1] << 8), h.symbols.AtomDriverPendingArena);
  const finish = h.finish("AtomAssembleFinish after commit");
  assert.equal(finish.status, 0);
  assert.equal(finish.carry, 0);
});

test("undefined global reports its exact source part, offset, and packed name", () => {
  const result = h.assemble(["NOP\n", "LD HL,Missing+1\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusUndefined);
  assert.equal(result.part, 1);
  assert.equal(result.offset, 6);
  assert.equal(result.ix, result.undefinedSymbol);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName("Missing"));
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 0,
    aborted: 1,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
    highWater: 0,
    geometryFlags: 0,
  });
});

test("current-scope private undefined references report their exact token", () => {
  const result = h.assemble(["Routine:\n", "DW .Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.part, 1);
  assert.equal(result.offset, 3);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName(".Missing"));
});

test("descriptor failures are preflighted before sink begin", () => {
  const cases = [
    [[], { partCount: 0 }, CONFIG.PART_COUNT],
    [[""], { partsPointer: 0xfffc }, CONFIG.TABLE_RANGE],
    [["NOP\n"], { ordinals: [1] }, CONFIG.PART_ORDINAL],
    [["NOP\n"], { reversedSourceIndex: 0 }, CONFIG.SOURCE_RANGE],
    [[""], { symbolStart: 0x9100, symbolEnd: 0x90ff }, CONFIG.SYMBOL_RANGE],
    [[""], { pendingStart: 0x9300, pendingEnd: 0x92ff }, CONFIG.PENDING_RANGE],
    [[""], { address: 0xfff0, capacity: 0x20 }, CONFIG.OUTPUT_RANGE],
  ];
  for (const [parts, options, detail] of cases) {
    const result = h.assemble(parts, { ...options, label: `AtomAssemble config ${detail}` });
    assert.equal(result.status, STATUS.CONFIGURATION, JSON.stringify(options));
    assert.equal(result.driverDetail, detail, JSON.stringify(options));
    assert.deepEqual(h.lifecycle(), {
      open: 0,
      began: 0,
      committed: 0,
      aborted: 0,
      beginDescriptor: 0,
      commitDescriptor: 0,
      cursor: 0,
      remaining: 0,
      highWater: 0,
      geometryFlags: 0,
    });
    assert.deepEqual(h.operations(), []);
  }
});

test("part EOF cannot join tokens across adjacent parts", () => {
  const result = h.assemble(["Start", ": NOP\n"]);
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 0);
  assert.equal(h.lifecycle().aborted, 1);
});

test("begin failure does not abort a generation that never opened", () => {
  const result = h.assemble(["NOP\n"], { failBegin: true });
  assert.equal(result.status, STATUS.OUTPUT);
  assert.equal(result.driverDetail, 0xe0);
  assert.equal(result.part, 0);
  assert.deepEqual(h.operations(), []);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 0,
    committed: 0,
    aborted: 0,
    beginDescriptor: 0,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
    highWater: 0,
    geometryFlags: 0,
  });
});

test("image and patch sink failures abort while preserving the source diagnostic", () => {
  let result = h.assemble(["NOP\nLD A,1\n"], { failAfter: 2, label: "AtomAssemble image failure" });
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusOutput);
  assert.equal(result.statementDetail, 0xe1);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 4);
  assert.equal(h.lifecycle().aborted, 1);
  assert.deepEqual(h.operations(), [{ kind: 1, bank: 0, address: 0x4000, bytes: [0x00] }]);

  result = h.assemble(["JR Later\nLater:\n"], { failAfter: 3, label: "AtomAssemble patch failure" });
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusOutput);
  assert.equal(result.statementDetail, 0xe1);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 9);
  assert.equal(h.lifecycle().aborted, 1);
});

test("commit failure is followed by one abort and retains the adapter status", () => {
  const result = h.assemble(["NOP\n"], { failCommit: true });
  assert.equal(result.status, STATUS.OUTPUT);
  assert.equal(result.driverDetail, 0xe3);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 0,
    aborted: 1,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
    highWater: 0,
    geometryFlags: 0,
  });
});

test("the native driver can begin a clean generation after an aborted one", () => {
  const failed = h.assemble(["Missing: LD A,Unknown\n"]);
  assert.equal(failed.status, STATUS.UNDEFINED);
  const result = h.assembleAgain(["NOP\n"], { label: "AtomAssemble after abort without runtime restart" });
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [0x00]);
  assert.equal(h.lifecycle().committed, 1);
});


test("complete assembly handles arithmetic precedence and signed word boundaries", () => {
  for (const expression of [
    "0", "65535", "-1", "-32768", "1+2*3", "(1+2)*3", "20-5-3",
    "100/5/2", "100%9", "-7/3", "-7%3", "1|2^3&6", "1<<5+2", "256>>4",
    "~1&$FF", "255*257", "65535/255", "$+2", "+(2+3)", "~~0",
  ]) {
    const source = `LD HL,${expression}`;
    assert.equal(h.assemble([`Value EQU ${expression}\nLD HL,Value`]).status, STATUS.OK, source);
    assert.deepEqual(h.finalBytes(), referenceBytes(source), source);
  }
});

test("literal spellings, characters, strings and comments survive complete assembly", () => {
  const source = " ; comment\nDB 42,2AH,$2A,%101010,'*'\nDB \"A\\n\\t\\\\\\\"\" ;tail\n";
  assert.equal(h.assemble([source]).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [42, 42, 42, 42, 42, 65, 10, 9, 92, 34]);
});

test("global equates preserve private scope and private names are reused by each routine", () => {
  const source = "First:\n.local: DB 1\nValue: EQU 7\nDW .local\nSecond:\n.local: DB Value\nDW .local\n";
  assert.equal(h.assemble([source]).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [1, 0, 0x40, 7, 3, 0x40]);
});

test("data lists evaluate their own address and resolved symbol differences", () => {
  const source = "Start: DB LOW($),LOW($),LOW($)\nEnd: DW End-Start\n";
  assert.equal(h.assemble([source]).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [0, 1, 2, 3, 0]);
});

test("data and instruction forward references resolve LOW and HIGH transforms", () => {
  const source = "DB LOW(Target),HIGH(Target)\nLD A,LOW(Target+1)\nTarget: NOP\n";
  assert.equal(h.assemble([source]).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [4, 0x40, 0x3e, 5, 0]);
});

test("string directives encode termination, length and final-bit conventions", () => {
  assert.equal(h.assemble(['CSTR "AB"\nPSTR "CD"\nISTR "EF"\n']).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [65, 66, 0, 2, 67, 68, 69, 198]);
});

test("ORG, ALIGN and initialized and uninitialized reservations produce correct geometry", () => {
  assert.equal(h.assemble(['DB 1\nDS 2,$AA\nALIGN 8\nDS 2\nDB 9\n']).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [1, 0xaa, 0xaa, 0, 0, 0, 0, 0, 0, 0, 9]);
  assert.equal(h.lifecycle().cursor, 0x400b);
  assert.equal(h.assemble(['ORG $4002\nDB 1\nORG $4000\nDB 2\n']).status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [2, 0, 1]);
});

test("source errors abort without committing and a subsequent build succeeds", () => {
  for (const source of [
    "LD A,256", "DB 1,", "DW", "DS Missing", "Value EQU Missing",
    "Value EQU 1\nValue EQU 2", ".local: NOP", "First:\nDW .missing\nNext: NOP",
    "LD IXH,H", "DB 1/0", "ALIGN 0", 'DB "\\q"',
  ]) {
    const failed = h.assemble([source]);
    assert.notEqual(failed.status, STATUS.OK, source);
    assert.equal(h.lifecycle().committed, 0, source);
    assert.equal(h.lifecycle().aborted, 1, source);
    assert.equal(h.assembleAgain(['NOP']).status, STATUS.OK, source);
    assert.deepEqual(h.finalBytes(), [0], source);
  }
});

test("symbol and pending-reference capacity fail at the first incomplete record", () => {
  for (const [source, option, size] of [
    ["Name EQU 1\nDB Name", "symbolBytes", 8],
    ["DW Target\nTarget: NOP", "pendingBytes", 9],
  ]) {
    for (const bytes of [size - 1, size, size + 1]) {
      const result = h.assemble([source], { [option]: bytes });
      assert.equal(result.status === STATUS.OK, bytes >= size, `${option}=${bytes}`);
      assert.equal(h.lifecycle().committed, bytes >= size ? 1 : 0);
    }
  }
});

test("all historical instruction vectors assemble from mixed-case source", () => {
  for (const { source } of validCases()) {
    const variants = [
      source,
      source.toLowerCase(),
      source.replace(/[A-Z]/g, (c, offset) => offset % 2 ? c.toLowerCase() : c),
    ];
    for (const variant of variants) {
      assert.equal(h.assemble([variant]).status, STATUS.OK, variant);
      assert.deepEqual(h.finalBytes(), referenceBytes(source), variant);
    }
  }
});

test("historically rejected instructions fail through complete assembly", () => {
  for (const { source } of invalidCases()) {
    if (!referenceRejects(source)) continue;
    assert.notEqual(h.assemble([source]).status, STATUS.OK, source);
    assert.equal(h.lifecycle().committed, 0, source);
  }
});
