import assert from "node:assert/strict";
import test from "node:test";
import { createDriverHarness } from "./driver-support.mjs";

const h = await createDriverHarness();

function assemble(source, expected, options = {}) {
  assert.equal(h.assemble([source], options).status, 0, source);
  assert.deepEqual(h.finalBytes(options.address ?? 0x4000), expected, source);
}

function patches() {
  return h.operations().filter(({ kind }) => kind === 2);
}

test("image emission preserves all instruction lengths", () => {
  for (const [source, bytes] of [
    ["NOP", [0]],
    ["LD A,42", [0x3e, 42]],
    ["LD HL,$1234", [0x21, 0x34, 0x12]],
    ["LD (IX+3),42", [0xdd, 0x36, 3, 42]],
  ]) {
    assemble(source, bytes);
    assert.equal(h.lifecycle().cursor, 0x4000 + bytes.length);
  }
});

test("byte, word, relative and displacement references patch exact output fields", () => {
  for (const [source, bytes, patch] of [
    ["ADD A,Value+5\nValue EQU $20", [0xc6, 0x25], [0x25]],
    ["JP Value-1\nValue EQU $1234", [0xc3, 0x33, 0x12], [0x33, 0x12]],
    ["JR Target\nDB 1,2,3\nTarget:", [0x18, 3, 1, 2, 3], [3]],
    ["LD A,(IX+Value-2)\nValue EQU 0", [0xdd, 0x7e, 0xfe], [0xfe]],
  ]) {
    assemble(source, bytes);
    assert.deepEqual(patches().at(-1).bytes, patch);
  }
});

test("two unresolved instruction fields retain the patch order", () => {
  assemble("LD (IX+Same),Same+1\nSame EQU 3", [0xdd, 0x36, 3, 4]);
  assert.deepEqual(patches(), [
    { kind: 2, bank: 0, address: 0x4002, bytes: [3] },
    { kind: 2, bank: 0, address: 0x4003, bytes: [4] },
  ]);
});

test("symbol definition order controls patch order", () => {
  const source = "JP First\nJP Second\nSecond EQU $5100\nFirst EQU $5000";
  assemble(source, [0xc3, 0, 0x50, 0xc3, 0, 0x51]);
  assert.deepEqual(patches().map(({ address }) => address), [0x4004, 0x4001]);
});

test("relative branches accept both signed endpoints and reject their neighbours", () => {
  for (const target of [0x3f81, 0x3f82, 0x4081, 0x4082]) {
    const source = `JR Target\nTarget EQU ${target}`;
    const result = h.assemble([source]);
    const valid = target === 0x3f82 || target === 0x4081;
    assert.equal(result.status === 0, valid, source);
    if (valid) {
      assert.deepEqual(h.finalBytes(), [0x18, (target - 0x4002) & 255]);
    } else {
      assert.equal(h.lifecycle().aborted, 1);
    }
  }
});

test("byte and displacement patch limits reject overflow without committing", () => {
  for (const [instruction, value, valid] of [
    ["ADD A,Value", 255, true],
    ["ADD A,Value", 256, false],
    ["LD A,(IX+Value)", 127, true],
    ["LD A,(IX+Value)", 128, false],
    ["LD A,(IX+Value-128)", 0, true],
    ["LD A,(IX+Value-129)", 0, false],
  ]) {
    const result = h.assemble([`${instruction}\nValue EQU ${value}`]);
    assert.equal(result.status === 0, valid, instruction);
    assert.equal(h.lifecycle().committed, valid ? 1 : 0);
  }
});

test("exact output capacity succeeds and insufficient capacity aborts", () => {
  for (const capacity of [2, 3, 4]) {
    const result = h.assemble(["LD HL,$1234"], { capacity });
    assert.equal(result.status === 0, capacity >= 3);
    if (capacity >= 3) {
      assert.deepEqual(h.finalBytes(), [0x21, 0x34, 0x12]);
    } else {
      assert.equal(h.lifecycle().aborted, 1);
    }
  }
});

test("relative patch base wraps after a byte at FFFF", () => {
  assemble("JR Target\nTarget EQU 0", [0x18, 0], { address: 0xfffe, capacity: 2 });
  assert.deepEqual(h.operations().at(-1), { kind: 2, bank: 0, address: 0xffff, bytes: [0] });
  assert.equal(h.lifecycle().geometryFlags, 3);
});

test("image and patch failures retain only accepted uncommitted operations", () => {
  for (const [source, failAfter, count] of [
    ["LD HL,$1234", 2, 1],
    ["JR Target\nTarget:", 3, 2],
  ]) {
    const result = h.assemble([source], { failAfter });
    assert.notEqual(result.status, 0);
    assert.equal(h.lifecycle().committed, 0);
    assert.equal(h.lifecycle().aborted, 1);
    assert.equal(h.operations().length, count);
  }
});
