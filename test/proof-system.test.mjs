import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import test from "node:test";

import { validCases } from "./cases.mjs";
import { createHarness } from "./support.mjs";

const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-1-memory.json", "utf8"));
const formCensus = JSON.parse(fs.readFileSync("proofs/azm-form-census.json", "utf8"));
const harness = await createHarness();

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in harness.symbols, `missing proof symbol ${value}`);
  return harness.symbols[value];
}

test("strict proof memory profile covers exactly 64 KiB without gaps or overlaps", () => {
  const regions = memoryProfile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(memoryProfile.addressSpaceBytes, 0x10000);
  assert.equal(regions[0].startAddress, 0);
  for (let index = 0; index < regions.length; index += 1) {
    const region = regions[index];
    assert.ok(region.endAddress > region.startAddress, `${region.name}: empty or reversed`);
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) {
      assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
    }
  }
  assert.equal(regions.at(-1).endAddress, 0x10000);

  for (const extent of memoryProfile.extents) {
    assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
  }
});

test("generated valid corpus exactly matches the frozen AZM form census", () => {
  const cases = validCases();
  const counts = {};
  for (const { source } of cases) {
    const mnemonic = source.trim().split(/\s+/)[0].toUpperCase();
    counts[mnemonic] = (counts[mnemonic] ?? 0) + 1;
  }
  const canonical = cases
    .map(({ source, record }) => `${source}\t${Buffer.from(record).toString("hex")}`)
    .sort()
    .join("\n");
  const hash = crypto.createHash("sha256").update(canonical).digest("hex");
  assert.equal(cases.length, formCensus.caseCount);
  assert.equal(Object.keys(counts).length, formCensus.mnemonicCount);
  assert.deepEqual(counts, formCensus.countsByMnemonic);
  assert.equal(hash, formCensus.canonicalSourceRecordSha256);
});
