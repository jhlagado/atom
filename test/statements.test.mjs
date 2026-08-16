import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createStatementsHarness } from "./statements-support.mjs";

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
  const local = h.pack("_Done").key;
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
  const local = h.pack("_Forward").key;
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
  const local = h.pack("_Local").key;
  assert.equal(h.declare(local, 0x4001).status, STATUS.OK);
  assert.equal(h.declareGlobalLabel(h.pack("Second").key, 0x4010).status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), h.symbols.AtomStatementSymbolArena + 16);
});

test("stale private pending state blocks a global label without mutation", () => {
  h.reset();
  assert.equal(h.declareGlobalLabel(h.pack("First").key, 0x4000).status, STATUS.OK);
  const local = h.pack("_Target").key;
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
  const local = h.pack("_Local").key;
  assert.equal(h.declare(local, 0x4000).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
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
