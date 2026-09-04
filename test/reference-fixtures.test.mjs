import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { referenceBytes, referenceRejects } from "./reference-fixtures.mjs";

test("the independent historical reference corpus retains its reviewed identity and coverage", () => {
  const fixture = JSON.parse(readFileSync(new URL("./fixtures/historical-assembly.json", import.meta.url), "utf8"));
  assert.equal(fixture.recordsSha256, "cbc3d0f619e767a7c5f96abc06502a6fa5f818480acda4bb4a883a5820a33aba");
  assert.equal(fixture.provenance.sourceRevision, "7e00661666fe8362276aa934598dce8fb82add5a");
  assert.deepEqual(fixture.provenance.oracle, {
    package: "@jhlagado/azm",
    version: "0.3.9",
    compiledTreeSha256: "7eac1bb9af4af9d566470ef207492fbafcd04bb6915b176f2a4a7cdaf8f98d67",
  });
  assert.deepEqual(fixture.sourceWrapper, { prefix: ".org $4000\n", suffix: "\n.end\n" });
  assert.equal(fixture.records.length, 6788);
  assert.equal(fixture.records.filter(([, bytes]) => bytes === null).length, 526);
  for (const [source, bytes] of fixture.records) {
    assert.ok(source.startsWith(fixture.sourceWrapper.prefix));
    assert.ok(source.endsWith(fixture.sourceWrapper.suffix));
    if (bytes !== null) {
      assert.ok(Array.isArray(bytes));
      assert.ok(bytes.every(byte => Number.isInteger(byte) && byte >= 0 && byte <= 255));
    }
  }
});

test("reference requests return independent data and cannot silently generate new answers", () => {
  assert.deepEqual(referenceBytes("NOP"), [0]);
  assert.deepEqual(referenceBytes("EX AF,AF'"), [8]);
  assert.equal(referenceRejects("LD IXH,H"), true);
  assert.equal(referenceRejects("LD A,IXH"), false);
  const bytes = referenceBytes("NOP");
  bytes[0] = 255;
  assert.deepEqual(referenceBytes("NOP"), [0]);
  assert.throws(() => referenceBytes("LD IXH,H"), /Historical reference rejected/);
  assert.throws(() => referenceBytes("UNRECORDED CASE"), /No reviewed reference fixture/);
  assert.throws(() => referenceRejects("UNRECORDED CASE"), /No reviewed reference fixture/);
});
