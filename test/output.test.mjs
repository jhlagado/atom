import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createOutputHarness } from "./output-support.mjs";
import { azmBytes } from "./support.mjs";

const h = await createOutputHarness();
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2f-memory.json", "utf8"));

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing output proof symbol ${value}`);
  return h.symbols[value];
}

test("Phase 2f memory profile covers exactly 64 KiB without gaps or overlap", () => {
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
    } else if (extent.start !== undefined) {
      assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
    }
  }
});

test("emits one Nucleus-model image operation for each instruction byte", () => {
  h.reset();
  const parsed = h.parse("LD A,$42");
  assert.equal(parsed.carry, 0);
  const emitted = h.emit();
  assert.equal(emitted.carry, 0);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0x4000, bytes: [0x3e] },
    { kind: 1, bank: 0, address: 0x4001, bytes: [0x42] },
  ]);
});

test("Nucleus image operations preserve every AZM-supported instruction byte", () => {
  for (const [index, item] of validCases().entries()) {
    h.reset();
    const parsed = h.parse(item.source);
    assert.equal(parsed.carry, 0, `${index}: ${item.source}`);
    const emitted = h.emit();
    assert.equal(emitted.carry, 0, `${index}: ${item.source}`);
    const bytes = h.operations().filter(({ kind }) => kind === 1).map((operation) => operation.bytes[0]);
    assert.deepEqual(bytes, azmBytes(item.source), `${index}: ${item.source}`);
  }
});

test("emits every Z80 instruction length and advances the target cursor", () => {
  for (const [source, bytes] of [
    ["NOP", [0x00]],
    ["LD A,$42", [0x3e, 0x42]],
    ["LD HL,$1234", [0x21, 0x34, 0x12]],
    ["LD (IX+1),$42", [0xdd, 0x36, 0x01, 0x42]],
  ]) {
    h.reset({ capacity: bytes.length });
    assert.equal(h.parse(source).carry, 0, source);
    const emitted = h.emit();
    assert.equal(emitted.carry, 0, source);
    assert.deepEqual(h.operations(), bytes.map((byte, offset) => ({
      kind: 1,
      bank: 0,
      address: 0x4000 + offset,
      bytes: [byte],
    })), source);
    assert.deepEqual(h.outputState(), { cursor: 0x4000 + bytes.length, remaining: 0 }, source);
  }
});

test("rejects output and pending capacity before the first image operation", () => {
  h.reset({ capacity: 3 });
  assert.equal(h.parse("LD (IX+1),$42").carry, 0);
  let emitted = h.emit();
  assert.equal(emitted.carry, 1);
  assert.equal(emitted.status, 1);
  assert.deepEqual(h.operations(), []);
  assert.deepEqual(h.outputState(), { cursor: 0x4000, remaining: 3 });

  h.reset({ pendingBytes: 11 });
  assert.equal(h.parse("LD (IX+Disp),Forward").carry, 0);
  emitted = h.emit();
  assert.equal(emitted.carry, 1);
  assert.equal(emitted.status, 6);
  assert.deepEqual(h.operations(), []);
  assert.deepEqual(h.pendingRecords(), []);
  assert.deepEqual(h.outputState(), { cursor: 0x4000, remaining: 0x100 });
});

test("sink failure retains only accepted uncommitted image operations", () => {
  for (let call = 1; call <= 4; call += 1) {
    h.reset();
    assert.equal(h.parse("LD (IX+Disp),Forward").carry, 0);
    h.failSinkAfter(call);
    const emitted = h.emit();
    assert.equal(emitted.carry, 1, `call ${call}`);
    assert.equal(emitted.status, 0xe1, `call ${call}`);
    assert.equal(h.operations().length, call - 1, `call ${call}`);
    assert.deepEqual(h.pendingRecords(), [], `call ${call}`);
    assert.deepEqual(h.outputState(), { cursor: 0x4000 + call - 1, remaining: 0x100 - call + 1 }, `call ${call}`);
  }
});

test("proof spool reserves one byte below, exactly at, and above an image operation", () => {
  for (const { available, carry, status, cursor } of [
    { available: 6, carry: 1, status: 0xe2, cursor: 0x4000 },
    { available: 7, carry: 0, status: 0, cursor: 0x4001 },
    { available: 8, carry: 0, status: 0, cursor: 0x4001 },
  ]) {
    h.reset();
    assert.equal(h.parse("NOP").carry, 0);
    h.setLogAvailable(available);
    const logCursor = h.logCursor();
    const emitted = h.emit();
    assert.equal(emitted.carry, carry, `available ${available}`);
    assert.equal(emitted.status, status, `available ${available}`);
    assert.equal(h.outputState().cursor, cursor, `available ${available}`);
    if (carry) assert.equal(h.logCursor(), logCursor, `available ${available}`);
    assert.equal(h.memory[h.symbols.AtomOutputLogAfter], 0xa5, `available ${available}`);
  }
});

test("proof spool reserves one byte below, exactly at, and above a word patch", () => {
  for (const { available, carry, status, pending } of [
    { available: 7, carry: 1, status: 0xe2, pending: 1 },
    { available: 8, carry: 0, status: 0, pending: 0 },
    { available: 9, carry: 0, status: 0, pending: 0 },
  ]) {
    h.reset();
    assert.equal(h.parse("JP Forward").carry, 0);
    assert.equal(h.emit().carry, 0);
    const declared = h.declare("Forward", 0x1234);
    assert.equal(declared.carry, 0);
    h.setLogAvailable(available);
    const logCursor = h.logCursor();
    const resolved = h.resolve(declared.ix);
    assert.equal(resolved.carry, carry, `available ${available}`);
    assert.equal(resolved.status, status, `available ${available}`);
    assert.equal(h.pendingRecords().length, pending, `available ${available}`);
    if (carry) assert.equal(h.logCursor(), logCursor, `available ${available}`);
    assert.equal(h.memory[h.symbols.AtomOutputLogAfter], 0xa5, `available ${available}`);
  }
});

test("queues both unresolved fields only after every image byte succeeds", () => {
  h.reset();
  assert.equal(h.parse("LD (IX+Disp),Forward").carry, 0);
  const emitted = h.emit();
  assert.equal(emitted.carry, 0);
  assert.deepEqual(h.operations().map(({ bytes }) => bytes[0]), [0xdd, 0x36, 0x00, 0x00]);
  assert.equal(h.pendingRecords().length, 2);
  assert.deepEqual(h.pendingRecords().map((record) => [record[2] | (record[3] << 8), record[4], record[5]]), [
    [0x4002, 0xb8 | 4, 0],
    [0x4003, 0xb8 | 1, 0],
  ]);
});

test("pending peek returns exact metadata without reclaiming the record", () => {
  h.reset();
  assert.equal(h.parse("JP Forward+5").carry, 0);
  assert.equal(h.emit().carry, 0);
  const before = h.pendingRecords();
  const symbol = before[0][0] | (before[0][1] << 8);
  const peeked = h.pendingPeek(symbol);
  assert.equal(peeked.carry, 0);
  assert.equal(peeked.de, 0x4001);
  assert.equal(peeked.b, 0xb8 | 2);
  assert.equal(peeked.c, 5);
  assert.deepEqual(h.pendingRecords(), before);
  const missing = h.pendingPeek(0x1234);
  assert.equal(missing.carry, 1);
  assert.equal(missing.status, 1);
  assert.deepEqual(h.pendingRecords(), before);
});

test("resolves byte, word, relative, and displacement patches through Nucleus sinks", () => {
  for (const { source, value, patch } of [
    { source: "ADD A,Forward+5", value: 0x20, patch: { address: 0x4001, bytes: [0x25] } },
    { source: "JP Forward-1", value: 0x1234, patch: { address: 0x4001, bytes: [0x33, 0x12] } },
    { source: "JR Forward", value: 0x4005, patch: { address: 0x4001, bytes: [0x03] } },
    { source: "LD A,(IX+Forward-2)", value: 0, patch: { address: 0x4002, bytes: [0xfe] } },
  ]) {
    h.reset();
    assert.equal(h.parse(source).carry, 0, source);
    assert.equal(h.emit().carry, 0, source);
    assert.equal(h.pendingRecords().length, 1, source);
    const declared = h.declare("Forward", value);
    assert.equal(declared.carry, 0, source);
    const resolved = h.resolve(declared.ix);
    assert.equal(resolved.carry, 0, source);
    assert.deepEqual(h.operations().at(-1), { kind: 2, bank: 0, ...patch }, source);
    assert.deepEqual(h.pendingRecords(), [], source);
  }
});

test("retains the current pending record after range or patch-sink failure", () => {
  for (const { source, value, status } of [
    { source: "ADD A,Forward-1", value: 0, status: 3 },
    { source: "ADD A,Forward", value: 256, status: 3 },
    { source: "LD A,(IX+Forward)", value: 128, status: 3 },
    { source: "JR Forward", value: 0x4082, status: 4 },
    { source: "JP Forward+1", value: 0xffff, status: 3 },
  ]) {
    h.reset();
    assert.equal(h.parse(source).carry, 0, source);
    assert.equal(h.emit().carry, 0, source);
    const declared = h.declare("Forward", value);
    const before = h.pendingRecords();
    const operationCount = h.operations().length;
    const resolved = h.resolve(declared.ix);
    assert.equal(resolved.carry, 1, source);
    assert.equal(resolved.status, status, source);
    assert.deepEqual(h.pendingRecords(), before, source);
    assert.equal(h.operations().length, operationCount, source);
  }

  h.reset();
  assert.equal(h.parse("JP Forward").carry, 0);
  assert.equal(h.emit().carry, 0);
  const declared = h.declare("Forward", 0x1234);
  const before = h.pendingRecords();
  h.failSinkAfter(1);
  const resolved = h.resolve(declared.ix);
  assert.equal(resolved.carry, 1);
  assert.equal(resolved.status, 0xe1);
  assert.deepEqual(h.pendingRecords(), before);
  assert.equal(h.operations().filter(({ kind }) => kind === 2).length, 0);
});

test("drains both fields for one symbol and preserves patch resolution order", () => {
  h.reset();
  assert.equal(h.parse("LD (IX+Same),Same+1").carry, 0);
  assert.equal(h.emit().carry, 0);
  const declared = h.declare("Same", 3);
  assert.equal(h.resolve(declared.ix).carry, 0);
  assert.deepEqual(h.operations().filter(({ kind }) => kind === 2), [
    { kind: 2, bank: 0, address: 0x4002, bytes: [3] },
    { kind: 2, bank: 0, address: 0x4003, bytes: [4] },
  ]);
  assert.deepEqual(h.pendingRecords(), []);
});

test("patch ranges match the concrete parser at every accepted boundary", () => {
  for (const { source, value, byte } of [
    { source: "ADD A,Forward", value: 0, byte: 0x00 },
    { source: "ADD A,Forward", value: 255, byte: 0xff },
    { source: "LD A,(IX+Forward-128)", value: 0, byte: 0x80 },
    { source: "LD A,(IX+Forward-1)", value: 0, byte: 0xff },
    { source: "LD A,(IX+Forward)", value: 0, byte: 0x00 },
    { source: "LD A,(IX+Forward+127)", value: 0, byte: 0x7f },
  ]) {
    h.reset();
    assert.equal(h.parse(source).carry, 0, source);
    assert.equal(h.emit().carry, 0, source);
    const declared = h.declare("Forward", value);
    assert.equal(h.resolve(declared.ix).carry, 0, source);
    assert.deepEqual(h.operations().at(-1).bytes, [byte], source);
  }

  for (const { target, byte } of [
    { target: 0x3f82, byte: 0x80 },
    { target: 0x4002, byte: 0x00 },
    { target: 0x4081, byte: 0x7f },
  ]) {
    h.reset();
    assert.equal(h.parse("JR Forward").carry, 0);
    assert.equal(h.emit().carry, 0);
    const declared = h.declare("Forward", target);
    assert.equal(h.resolve(declared.ix).carry, 0);
    assert.deepEqual(h.operations().at(-1).bytes, [byte]);
  }

  for (const { source, value, bytes } of [
    { source: "JP Forward-1", value: 0, bytes: [0xff, 0xff] },
    { source: "JP Forward", value: 0xffff, bytes: [0xff, 0xff] },
  ]) {
    h.reset();
    assert.equal(h.parse(source).carry, 0, source);
    assert.equal(h.emit().carry, 0, source);
    const declared = h.declare("Forward", value);
    assert.equal(h.resolve(declared.ix).carry, 0, source);
    assert.deepEqual(h.operations().at(-1).bytes, bytes, source);
  }
});

test("relative patch rejects the first target outside each signed boundary", () => {
  for (const target of [0x3f81, 0x4082]) {
    h.reset();
    assert.equal(h.parse("JR Forward").carry, 0);
    assert.equal(h.emit().carry, 0);
    const declared = h.declare("Forward", target);
    const before = h.pendingRecords();
    const resolved = h.resolve(declared.ix);
    assert.equal(resolved.carry, 1);
    assert.equal(resolved.status, 4);
    assert.deepEqual(h.pendingRecords(), before);
  }
});

test("relative base wraps exactly after a patch byte at $FFFF", () => {
  h.reset({ address: 0xfffe, capacity: 2 });
  assert.equal(h.parse("JR Forward", { address: 0xfffe }).carry, 0);
  assert.equal(h.emit().carry, 0);
  const declared = h.declare("Forward", 0);
  assert.equal(h.resolve(declared.ix).carry, 0);
  assert.deepEqual(h.operations(), [
    { kind: 1, bank: 0, address: 0xfffe, bytes: [0x18] },
    { kind: 1, bank: 0, address: 0xffff, bytes: [0x00] },
    { kind: 2, bank: 0, address: 0xffff, bytes: [0x00] },
  ]);
  assert.deepEqual(h.outputState(), { cursor: 0, remaining: 0 });
});

test("symbol definition order controls append-only patch order", () => {
  h.reset();
  assert.equal(h.parse("JP First", { address: 0x4000 }).carry, 0);
  assert.equal(h.emit().carry, 0);
  assert.equal(h.parse("JP Second", { address: 0x4003 }).carry, 0);
  assert.equal(h.emit().carry, 0);

  let declared = h.declare("Second", 0x5100);
  assert.equal(h.resolve(declared.ix).carry, 0);
  declared = h.declare("First", 0x5000);
  assert.equal(h.resolve(declared.ix).carry, 0);
  assert.deepEqual(h.operations().filter(({ kind }) => kind === 2), [
    { kind: 2, bank: 0, address: 0x4004, bytes: [0x00, 0x51] },
    { kind: 2, bank: 0, address: 0x4001, bytes: [0x00, 0x50] },
  ]);
});
