import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createStatementsHarness } from "./statements-support.mjs";

const h = await createStatementsHarness();
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2g-memory.json", "utf8"));

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
