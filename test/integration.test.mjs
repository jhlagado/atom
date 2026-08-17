import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createIntegrationHarness, PATCH_KIND } from "./integration-support.mjs";
import { azmBytes } from "./support.mjs";

const h = await createIntegrationHarness({ contracts: process.env.ATOM_INTEGRATION_CONTRACTS ?? "strict" });
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2e-memory.json", "utf8"));
const STATUS = Object.freeze({
  OK: 0,
  INVALID_FORM: 9,
  EXPRESSION: 13,
  UNPATCHABLE: 14,
  SYMBOL: 15,
  PART_CAPACITY: 17,
});
const OP = Object.freeze({ INDEX_IX: 48, INDEX_IY: 49, MEM_ABS: 50, IMM8: 51, IMM16: 52, REL8: 54, NONE: 255 });

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing integration proof symbol ${value}`);
  return h.symbols[value];
}

test("Phase 2e memory profile covers exactly 64 KiB without gaps or overlap", () => {
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
    assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
  }
});

test("expression-enabled parser preserves every concrete record and AZM byte", () => {
  for (const [index, item] of validCases().entries()) {
    h.reset();
    const parsed = h.parse(item.source);
    assert.equal(parsed.carry, 0, `${index}: ${item.source} status=${parsed.status}`);
    assert.deepEqual(parsed.record, Array.from(item.record), `${index}: record ${item.source}`);
    assert.deepEqual(parsed.references, [], `${index}: references ${item.source}`);
    const encoded = h.encodeParsed(item.source);
    assert.deepEqual(encoded.bytes, azmBytes(item.source), `${index}: bytes ${item.source}`);
  }
});

test("resolved global expressions flow through normalization, validation, and encoding", () => {
  h.reset();
  assert.equal(h.declare("Value", 17).carry, 0);
  assert.equal(h.declare("Table", 0x2000).carry, 0);
  assert.equal(h.declare("Target", 0x4070).carry, 0);
  assert.equal(h.declare("Disp", 3).carry, 0);
  const cases = [
    ["LD A,vAlUe+1", "LD A,18"],
    ["LD HL,Value*2", "LD HL,34"],
    ["LD A,(Table+2)", "LD A,($2002)"],
    ["LD (Table-1),HL", "LD ($1FFF),HL"],
    ["JR Target+1", "JR $4071"],
    ["LD (IX+Disp*2),$10+2", "LD (IX+6),18"],
    ["LD HL,$+2", "LD HL,$4002"],
    ["RST 4*2", "RST 8"],
    ["BIT 1+1,A", "BIT 2,A"],
    ["IM 1+1", "IM 2"],
  ];
  for (const [source, oracle] of cases) {
    const parsed = h.parse(source, { address: 0x4000 });
    assert.equal(parsed.carry, 0, source);
    assert.deepEqual(parsed.references, [], source);
    assert.deepEqual(h.encodeParsed(source).bytes, azmBytes(oracle), source);
  }
});

test("patch locator identifies every patchable field in the complete form census", () => {
  const expectedKind = new Map([
    [OP.INDEX_IX, PATCH_KIND.DISPLACEMENT],
    [OP.INDEX_IY, PATCH_KIND.DISPLACEMENT],
    [OP.MEM_ABS, PATCH_KIND.WORD],
    [OP.IMM8, PATCH_KIND.BYTE],
    [OP.IMM16, PATCH_KIND.WORD],
    [OP.REL8, PATCH_KIND.RELATIVE],
  ]);
  h.reset();
  let patchable = 0;
  let rejected = 0;
  for (const item of validCases()) {
    for (let operand = 0; operand < 3; operand += 1) {
      const klass = item.record[1 + operand];
      h.setRecord(item.record);
      const located = h.locate(operand);
      if (!expectedKind.has(klass)) {
        assert.equal(located.carry, 1, `${item.source}: operand ${operand}`);
        rejected += 1;
        continue;
      }
      patchable += 1;
      assert.equal(located.carry, 0, `${item.source}: operand ${operand}`);
      assert.equal(located.status, expectedKind.get(klass), `${item.source}: kind operand ${operand}`);

      const zero = Uint8Array.from(item.record);
      zero[4 + operand * 2] = 0;
      zero[5 + operand * 2] = 0;
      h.setRecord(zero);
      const before = h.encodeParsed(`${item.source}: zero`).bytes;
      const changed = Uint8Array.from(zero);
      changed[4 + operand * 2] = 0x5a;
      changed[5 + operand * 2] = expectedKind.get(klass) === PATCH_KIND.WORD ? 0xa5 : 0;
      h.setRecord(changed);
      const after = h.encodeParsed(`${item.source}: changed`).bytes;
      const differences = after.flatMap((byte, offset) => byte === before[offset] ? [] : [offset]);
      const expectedOffsets = expectedKind.get(klass) === PATCH_KIND.WORD
        ? [located.b, located.b + 1]
        : [located.b];
      assert.deepEqual(differences, expectedOffsets, `${item.source}: field operand ${operand}`);
    }
  }
  assert.equal(patchable, 2805);
  assert.equal(rejected, 7530);
});

test("forward expressions publish exact metadata only after full-form validation", () => {
  const cases = [
    ["JP Forward+5", [{ addend: 5, operand: 0, kind: PATCH_KIND.WORD, offset: 1, sourceOffset: 3 }]],
    ["JR Forward-3", [{ addend: -3, operand: 0, kind: PATCH_KIND.RELATIVE, offset: 1, sourceOffset: 3 }]],
    ["ADD A,Forward", [{ addend: 0, operand: 0, kind: PATCH_KIND.BYTE, offset: 1, sourceOffset: 6 }]],
    ["LD A,(Forward+2)", [{ addend: 2, operand: 1, kind: PATCH_KIND.WORD, offset: 1, sourceOffset: 6 }]],
    ["LD (IX+Disp),Forward", [
      { addend: 0, operand: 0, kind: PATCH_KIND.DISPLACEMENT, offset: 2, sourceOffset: 7 },
      { addend: 0, operand: 1, kind: PATCH_KIND.BYTE, offset: 3, sourceOffset: 13 },
    ]],
  ];
  for (const [source, expected] of cases) {
    h.reset();
    const parsed = h.parse(source, { part: 15 });
    assert.equal(parsed.carry, 0, source);
    assert.equal(parsed.references.length, expected.length, source);
    assert.deepEqual(parsed.references.map(({ symbol: _symbol, part, rawKind: _rawKind, ...reference }) => ({ ...reference, part })),
      expected.map((reference) => ({ ...reference, part: 15 })), source);
    assert.deepEqual(parsed.references.map(({ kind, rawKind }) => rawKind),
      expected.map(({ kind }) => 0xf8 | kind), `${source}: diagnostic anchors`);
    assert.equal(parsed.afterGlobalEnd, parsed.beforeGlobalEnd + expected.length * 8, source);
    assert.equal(parsed.references.every(({ symbol }) => symbol >= h.symbols.AtomIntegrationSymbolArena), true, source);
  }

  h.reset();
  const same = h.parse("LD (IX+Same),Same+1");
  assert.equal(same.carry, 0);
  assert.equal(same.references.length, 2);
  assert.equal(same.references[0].symbol, same.references[1].symbol);
  assert.equal(same.afterGlobalEnd, same.beforeGlobalEnd + 8);
});

test("two-field pending handoff is exact and capacity failure is atomic", () => {
  h.reset();
  let parsed = h.parse("LD (IX+Disp),Forward");
  assert.equal(parsed.carry, 0);
  let queued = h.queueReferences(0x4000);
  assert.equal(queued.carry, 0);
  assert.equal(queued.status, 0);
  assert.deepEqual(h.pendingRecords(), [
    [parsed.references[0].symbol & 0xff, parsed.references[0].symbol >>> 8, 0x02, 0x40, 0xb8 | PATCH_KIND.DISPLACEMENT, 0],
    [parsed.references[1].symbol & 0xff, parsed.references[1].symbol >>> 8, 0x03, 0x40, 0xb8 | PATCH_KIND.BYTE, 0],
  ]);

  h.reset({ pendingBytes: 11 });
  parsed = h.parse("LD (IY+Disp),Forward");
  assert.equal(parsed.carry, 0);
  const before = h.pendingRecords();
  queued = h.queueReferences(0x5000);
  assert.equal(queued.carry, 1);
  assert.equal(queued.status, 6);
  assert.deepEqual(h.pendingRecords(), before);
});

test("invalid or unpatchable forward forms publish neither records nor metadata", () => {
  for (const [source, status] of [
    ["INC Forward", STATUS.INVALID_FORM],
    ["BIT Forward,A", STATUS.UNPATCHABLE],
    ["RST Forward", STATUS.UNPATCHABLE],
    ["LD A,Forward*2", STATUS.EXPRESSION],
  ]) {
    h.reset();
    const parsed = h.parse(source);
    assert.equal(parsed.carry, 1, source);
    assert.equal(parsed.status, status, source);
    assert.deepEqual(parsed.record, parsed.before, source);
    assert.deepEqual(parsed.references, [], source);
    assert.equal(parsed.afterGlobalEnd, parsed.beforeGlobalEnd, source);
    assert.equal(parsed.afterLocalBegin, parsed.beforeLocalBegin, source);
  }
});

test("symbol publication preflight is atomic and private scope remains exact", () => {
  h.reset({ symbolBytes: 8 });
  let parsed = h.parse("LD (IX+First),Second");
  assert.equal(parsed.carry, 1);
  assert.equal(parsed.status, STATUS.SYMBOL);
  assert.equal(parsed.error.symbolStatus, 3);
  assert.equal(parsed.afterGlobalEnd, parsed.beforeGlobalEnd);
  assert.deepEqual(parsed.references, []);
  assert.deepEqual(parsed.record, parsed.before);

  h.reset();
  parsed = h.parse("JR .Later");
  assert.equal(parsed.carry, 1);
  assert.equal(parsed.status, STATUS.EXPRESSION);
  assert.equal(parsed.afterLocalBegin, parsed.beforeLocalBegin);
  assert.equal(h.advanceScope().carry, 0);
  parsed = h.parse("JR .lAtEr-1");
  assert.equal(parsed.carry, 0);
  assert.equal(parsed.references.length, 1);
  assert.equal(parsed.references[0].addend, -1);
  assert.equal(parsed.afterLocalBegin, parsed.beforeLocalBegin - 8);
});

test("forward-reference part ordinals stop exactly at the native capacity", () => {
  h.reset();
  let parsed = h.parse("JP Forward", { part: 15 });
  assert.equal(parsed.carry, 0);
  assert.equal(parsed.references.length, 1);
  assert.equal(parsed.references[0].part, 15);
  assert.equal(parsed.references[0].rawKind, 0xf8 | PATCH_KIND.WORD);

  h.reset();
  parsed = h.parse("JP Forward", { part: 16 });
  assert.equal(parsed.carry, 1);
  assert.equal(parsed.status, STATUS.PART_CAPACITY);
  assert.equal(parsed.error.part, 16);
  assert.equal(parsed.error.offset, 3);
  assert.deepEqual(parsed.record, parsed.before);
  assert.deepEqual(parsed.references, []);
  assert.equal(parsed.afterGlobalEnd, parsed.beforeGlobalEnd);
  assert.equal(parsed.afterLocalBegin, parsed.beforeLocalBegin);
});
