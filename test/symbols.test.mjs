import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { packRadix40 } from "../src/abi.mjs";
import { createSymbolHarness } from "./symbol-support.mjs";

const h = await createSymbolHarness();
const s = h.symbols;
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2a-memory.json", "utf8"));
const proofManifest = JSON.parse(fs.readFileSync("proofs/phase-2a.json", "utf8"));

const STATUS = Object.freeze({
  OK: 0,
  NOT_FOUND: 1,
  DUPLICATE: 2,
  SYMBOL_CAPACITY: 3,
  PRIVATE_NO_SCOPE: 4,
  UNDEFINED_PRIVATE: 5,
  PENDING_CAPACITY: 6,
  PENDING_INVARIANT: 7,
  ALREADY_DEFINED: 8,
});

function expectedKey(payload, privateName = false) {
  const bytes = packRadix40(payload).flatMap((word) => [word & 0xff, word >>> 8]);
  if (privateName) bytes[5] |= 0x80;
  return bytes;
}

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in s, `missing proof symbol ${value}`);
  return s[value];
}

test("Phase 2a memory profile covers all 64 KiB without gaps or overlap", () => {
  const regions = memoryProfile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(regions[0].startAddress, 0);
  for (let index = 0; index < regions.length; index += 1) {
    const region = regions[index];
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
  }
  assert.equal(regions.at(-1).endAddress, memoryProfile.addressSpaceBytes);
  for (const extent of memoryProfile.extents) {
    assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
  }
});

test("symbol records remain eight bytes and pending records remain six", () => {
  assert.equal(s.AtomSymbolRecordBytes, 8);
  assert.equal(s.AtomPendingRecordBytes, 6);
  assert.equal(s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart, 727);
  assert.equal(s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart, 20);
});

test("private prefix is syntax, case folding is exact, and limits are atomic", () => {
  h.reset();
  const globalUpper = h.pack("ABCDEFGH");
  const globalMixed = h.pack("aBcDeFgH");
  const localUpper = h.pack(".ABCDEFGH");
  const localMixed = h.pack(".aBcDeFgH");
  assert.deepEqual(globalUpper.key, expectedKey("ABCDEFGH"));
  assert.deepEqual(globalMixed.key, globalUpper.key);
  assert.deepEqual(localUpper.key, expectedKey("ABCDEFGH", true));
  assert.deepEqual(localMixed.key, localUpper.key);
  assert.notDeepEqual(localUpper.key, globalUpper.key);

  assert.deepEqual(h.pack("_GLOBAL").key, expectedKey("_GLOBAL"));
  for (const invalid of ["", ".", "ABCDEFGHI", ".ABCDEFGHI", "A-B"]) {
    const result = h.pack(invalid);
    assert.equal(result.carry, 1, invalid);
    assert.deepEqual(result.key, Array(6).fill(0xa5), `${invalid}: destination changed`);
  }
});

test("every private payload length retains all eight significant characters", () => {
  h.reset();
  for (let length = 1; length <= 8; length += 1) {
    const payload = "Ab3_".repeat(2).slice(0, length);
    const result = h.pack(`.${payload}`);
    assert.equal(result.carry, 0, payload);
    assert.deepEqual(result.key, expectedKey(payload, true), payload);
  }
});

test("private symbols require a global scope and are reused after eviction", () => {
  h.reset();
  const local = h.pack(".loop").key;
  let result = h.declare(local, 0x1234);
  assert.equal(result.status, STATUS.PRIVATE_NO_SCOPE);
  assert.equal(result.carry, 1);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), s.AtomSymbolArenaLimit);

  assert.equal(h.advanceScope().status, STATUS.OK);
  result = h.declare(local, 0x1234);
  assert.equal(result.status, STATUS.OK);
  const firstPointer = result.ix;
  assert.equal(firstPointer, s.AtomSymbolArenaLimit - 8);
  assert.equal(h.word(firstPointer + 6), 0x1234);

  assert.equal(h.advanceScope().status, STATUS.OK);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
  result = h.declare(local, 0x5678);
  assert.equal(result.status, STATUS.OK);
  assert.equal(result.ix, firstPointer, "evicted private slot was not reused");
  assert.equal(h.word(result.ix + 6), 0x5678);
});

test("globals survive scope changes while private names do not leak", () => {
  h.reset();
  const global = h.pack("Routine").key;
  const local = h.pack(".again").key;
  const globalResult = h.declare(global, 0x4000);
  assert.equal(globalResult.status, STATUS.OK);
  assert.equal(globalResult.ix, s.AtomSymbolArena);
  assert.equal(h.advanceScope().status, STATUS.OK);
  assert.equal(h.declare(local, 0x4010).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
  const foundGlobal = h.find(h.pack("rOuTiNe").key);
  assert.equal(foundGlobal.status, STATUS.OK);
  assert.equal(foundGlobal.ix, globalResult.ix);
  assert.equal(h.find(local).status, STATUS.NOT_FOUND);
});

test("duplicate and capacity failures do not publish partial records", () => {
  h.reset({ symbolBytes: 16 });
  const one = h.pack("ONE").key;
  const two = h.pack("TWO").key;
  const three = h.pack("THREE").key;
  assert.equal(h.declare(one, 1).status, STATUS.OK);
  const duplicateBefore = h.symbolArena();
  const duplicate = h.declare(one, 0xffff);
  assert.equal(duplicate.status, STATUS.DUPLICATE);
  assert.deepEqual(h.symbolArena(), duplicateBefore);
  assert.equal(h.declare(two, 2).status, STATUS.OK);
  const fullBefore = h.symbolArena();
  const globalEndBefore = h.stateWord("AtomSymbolGlobalEnd");
  const rejected = h.declare(three, 3);
  assert.equal(rejected.status, STATUS.SYMBOL_CAPACITY);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), globalEndBefore);
  assert.deepEqual(h.symbolArena(), fullBefore);
});

test("opposite-growing global and private records meet at the exact boundary", () => {
  h.reset({ symbolBytes: 16 });
  assert.equal(h.declare(h.pack("GLOBAL").key, 0x1000).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
  assert.equal(h.declare(h.pack(".LOCAL").key, 0x1001).status, STATUS.OK);
  const before = h.symbolArena();
  const result = h.reference(h.pack("EXTRA").key);
  assert.equal(result.status, STATUS.SYMBOL_CAPACITY);
  assert.deepEqual(h.symbolArena(), before);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), s.AtomSymbolArena + 8);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), s.AtomSymbolArena + 8);
});

test("symbol capacity checks one byte below, at, and above one record", () => {
  const key = expectedKey("BOUND");
  for (const [bytes, firstStatus] of [[7, STATUS.SYMBOL_CAPACITY], [8, STATUS.OK], [9, STATUS.OK]]) {
    h.reset({ symbolBytes: bytes });
    const before = h.symbolArena();
    const result = h.declare(key, 0x2222);
    assert.equal(result.status, firstStatus, `${bytes} bytes`);
    if (firstStatus === STATUS.SYMBOL_CAPACITY) assert.deepEqual(h.symbolArena(), before);
    else assert.equal(h.word(result.ix + 6), 0x2222);
  }
});

test("an unresolved private blocks scope eviction until it is defined", () => {
  h.reset();
  assert.equal(h.advanceScope().status, STATUS.OK);
  const local = h.pack(".later").key;
  const reference = h.reference(local);
  assert.equal(reference.status, STATUS.OK);
  assert.equal(h.symbolRecord(reference.ix)[5] & 0x40, 0);
  const before = h.symbolArena();
  const beginBefore = h.stateWord("AtomSymbolLocalBegin");
  const blocked = h.advanceScope();
  assert.equal(blocked.status, STATUS.UNDEFINED_PRIVATE);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), beginBefore);
  assert.deepEqual(h.symbolArena(), before);
  assert.equal(h.declare(local, 0x3456).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
});

test("global-label declaration validates and commits scope as one transaction", () => {
  h.reset({ symbolBytes: 16 });
  assert.equal(h.advanceScope().status, STATUS.OK);
  const local = h.pack(".later").key;
  const global = h.pack("NEXT").key;
  assert.equal(h.reference(local).status, STATUS.OK);
  const blockedArena = h.symbolArena();
  const blockedGlobalEnd = h.stateWord("AtomSymbolGlobalEnd");
  const blockedLocalBegin = h.stateWord("AtomSymbolLocalBegin");
  const blocked = h.declareGlobalLabel(global, 0x4567);
  assert.equal(blocked.status, STATUS.UNDEFINED_PRIVATE);
  assert.deepEqual(h.symbolArena(), blockedArena);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), blockedGlobalEnd);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), blockedLocalBegin);

  assert.equal(h.declare(local, 0x2345).status, STATUS.OK);
  const committed = h.declareGlobalLabel(global, 0x4567);
  assert.equal(committed.status, STATUS.OK);
  assert.equal(committed.ix, s.AtomSymbolArena);
  assert.equal(h.word(committed.ix + 6), 0x4567);
  assert.equal(h.stateWord("AtomSymbolGlobalEnd"), s.AtomSymbolArena + 8);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), s.AtomSymbolArena + 16);

  const duplicateArena = h.symbolArena();
  assert.equal(h.declareGlobalLabel(global, 0x9999).status, STATUS.DUPLICATE);
  assert.deepEqual(h.symbolArena(), duplicateArena);
  assert.equal(h.declareGlobalLabel(local, 0x9999).status, STATUS.PRIVATE_NO_SCOPE);
  assert.deepEqual(h.symbolArena(), duplicateArena);
});

test("pending references are bounded, reclaimed, and return exact metadata", () => {
  h.reset({ pendingBytes: 12 });
  const key = h.pack("FORWARD").key;
  const symbol = h.reference(key);
  assert.equal(symbol.status, STATUS.OK);
  assert.equal(h.pendingAdd(symbol.ix, 0x5001, 2, 0x11).status, STATUS.OK);
  assert.equal(h.pendingAdd(symbol.ix, 0x6002, 3, 0x22).status, STATUS.OK);
  const before = h.pendingArena();
  const nextBefore = h.stateWord("AtomPendingNext");
  const full = h.pendingAdd(symbol.ix, 0x7003, 4, 0x33);
  assert.equal(full.status, STATUS.PENDING_CAPACITY);
  assert.equal(h.stateWord("AtomPendingNext"), nextBefore);
  assert.deepEqual(h.pendingArena(), before);

  assert.equal(h.declare(key, 0x4242).status, STATUS.OK);
  const taken = [h.pendingTake(symbol.ix), h.pendingTake(symbol.ix)]
    .map(({ de, bc }) => [de, bc >>> 8, bc & 0xff])
    .sort(([left], [right]) => left - right);
  assert.deepEqual(taken, [[0x5001, 2, 0x11], [0x6002, 3, 0x22]]);
  assert.equal(h.pendingTake(symbol.ix).status, STATUS.NOT_FOUND);
  assert.equal(h.stateWord("AtomPendingNext"), s.AtomPendingArena);
  assert.equal(h.pendingAdd(symbol.ix, 0x8004, 1, 0).status, STATUS.ALREADY_DEFINED);
});

test("pending capacity checks one byte below, at, and above one record", () => {
  const key = expectedKey("PATCH");
  for (const [bytes, firstStatus] of [[5, STATUS.PENDING_CAPACITY], [6, STATUS.OK], [7, STATUS.OK]]) {
    h.reset({ pendingBytes: bytes });
    const symbol = h.reference(key);
    const before = h.pendingArena();
    const result = h.pendingAdd(symbol.ix, 0x6111, 2, 3);
    assert.equal(result.status, firstStatus, `${bytes} bytes`);
    if (firstStatus === STATUS.PENDING_CAPACITY) assert.deepEqual(h.pendingArena(), before);
    else assert.equal(h.stateWord("AtomPendingNext"), s.AtomPendingArena + 6);
  }
});

test("pending peek and capacity preflight publish no state", () => {
  h.reset({ pendingBytes: 6 });
  const symbol = h.reference(h.pack("PEEK").key);
  const emptyArena = h.pendingArena();
  assert.equal(h.pendingCheckCapacity().status, STATUS.OK);
  assert.deepEqual(h.pendingArena(), emptyArena);
  assert.equal(h.stateWord("AtomPendingNext"), s.AtomPendingArena);

  assert.equal(h.pendingAdd(symbol.ix, 0x6112, 5, 0x7a).status, STATUS.OK);
  const fullArena = h.pendingArena();
  const fullNext = h.stateWord("AtomPendingNext");
  const peeked = h.pendingPeek(symbol.ix);
  assert.equal(peeked.status, STATUS.OK);
  assert.deepEqual([peeked.de, peeked.bc >>> 8, peeked.bc & 0xff], [0x6112, 5, 0x7a]);
  assert.deepEqual(h.pendingArena(), fullArena);
  assert.equal(h.stateWord("AtomPendingNext"), fullNext);

  assert.equal(h.pendingCheckCapacity().status, STATUS.PENDING_CAPACITY);
  assert.deepEqual(h.pendingArena(), fullArena);
  assert.equal(h.stateWord("AtomPendingNext"), fullNext);
});

test("defined private symbols cannot be evicted with stale pending entries", () => {
  h.reset();
  assert.equal(h.advanceScope().status, STATUS.OK);
  const key = h.pack(".target").key;
  const symbol = h.reference(key);
  assert.equal(h.pendingAdd(symbol.ix, 0x3333, 1, 0).status, STATUS.OK);
  assert.equal(h.declare(key, 0x4444).status, STATUS.OK);
  const beginBefore = h.stateWord("AtomSymbolLocalBegin");
  const blocked = h.advanceScope();
  assert.equal(blocked.status, STATUS.PENDING_INVARIANT);
  assert.equal(h.stateWord("AtomSymbolLocalBegin"), beginBefore);
  assert.equal(h.pendingTake(symbol.ix).status, STATUS.OK);
  assert.equal(h.advanceScope().status, STATUS.OK);
});

test("measured public-entry execution remains inside Phase 2a budgets", () => {
  for (const [entry, budget] of Object.entries(proofManifest.executionBudgets)) {
    const observed = h.statistics[entry];
    assert.ok(observed, `${entry}: no runtime observation`);
    assert.ok(observed.instructions <= budget.maxInstructions, `${entry}: instruction budget exceeded`);
    assert.ok(observed.cycles <= budget.maxCycles, `${entry}: cycle budget exceeded`);
  }
});
