import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

// Historical oracle outputs are data, not executable assembler dependencies.
// An unrecorded request must fail; never obtain its answer from ATOM itself.
const fixture = JSON.parse(readFileSync(new URL("./fixtures/historical-assembly.json", import.meta.url), "utf8"));
assert.equal(fixture.format, "atom-historical-reference-v1");
assert.equal(createHash("sha256").update(JSON.stringify(fixture.records)).digest("hex"), fixture.recordsSha256);
const records = new Map(fixture.records);
assert.equal(records.size, fixture.records.length, "duplicate historical source keys");

function lookup(source) {
  const key = `${fixture.sourceWrapper.prefix}${source}${fixture.sourceWrapper.suffix}`;
  assert.ok(records.has(key), `No reviewed reference fixture for ${JSON.stringify(source)}`);
  return records.get(key);
}

export function referenceBytes(source) {
  const bytes = lookup(source);
  assert.notEqual(bytes, null, `Historical reference rejected ${source}`);
  return bytes.slice();
}

export function referenceRejects(source) {
  return lookup(source) === null;
}
