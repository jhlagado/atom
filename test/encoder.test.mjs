import assert from "node:assert/strict";
import test from "node:test";

import { MNEMONICS, O, packRadix40 } from "../src/abi.mjs";
import { invalidCases, systematicInvalidRecords, validCases } from "./cases.mjs";
import { referenceBytes, referenceRejects } from "./reference-fixtures.mjs";
import { createHarness, extent } from "./support.mjs";

const harness = await createHarness();

test("assembles inside the Phase 1 review and reject gates", () => {
  const { symbols } = harness;
  const core = extent(symbols, "AtomEncoderCoreStart", "AtomEncoderCoreEnd");
  assert.equal(core, 3_132, "resident extent drifted from the reviewed strict-contract build");
  assert.ok(core <= 3_500, `review gate crossed: ${core}`);
  assert.ok(core <= 5_000, `reject gate crossed: ${core}`);
  assert.equal(extent(symbols, "AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd"), 6);
});

test("RADIX-40 packing is exact, case-insensitive, bounded, and atomic", () => {
  const accepted = ["A", "abc", "AbC123_x", "_LOCAL", "LDIR", "12345678"];
  for (const name of accepted) {
    const expectedWords = packRadix40(name);
    assert.ok(expectedWords, name);
    const expected = expectedWords.flatMap((word) => [word & 0xff, word >>> 8]);
    const result = harness.pack(name);
    assert.equal(result.carry, 0, name);
    assert.equal(result.de, harness.symbols.AtomHarnessOutput + 6, `${name}: wrong destination exit`);
    assert.deepEqual(result.output.slice(0, 6), expected, name);
    assert.equal(result.output[6], 0xa5, `${name}: overran six-byte destination`);
  }
  for (const name of ["", "ABCDEFGHI", "A-B", "A.B", "A B", "é"]) {
    const result = harness.pack(name);
    assert.equal(result.carry, 1, name);
    assert.equal(result.value, 0, name);
    assert.equal(result.de, harness.symbols.AtomHarnessOutput, `${name}: failure changed destination`);
    assert.deepEqual(result.output, Array(7).fill(0xa5), `${name}: failure was not atomic`);
  }
});

test("recognizes every mnemonic through mixed case and rejects non-mnemonics", () => {
  for (let ordinal = 1; ordinal < MNEMONICS.length; ordinal += 1) {
    const name = MNEMONICS[ordinal];
    const variants = [name, name.toLowerCase(), [...name].map((c, i) => i % 2 ? c.toLowerCase() : c).join("")];
    for (const variant of variants) {
      const result = harness.recognize(variant);
      assert.equal(result.carry, 0, variant);
      assert.equal(result.value, ordinal, variant);
    }
  }
  for (const name of ["", "NOPE", "LDIRS", "ABCDEFGH", "A-B", "1234", "_LD"]) {
    const result = harness.recognize(name);
    assert.equal(result.carry, 1, name);
    assert.equal(result.value, 0, name);
  }
});

test("native encoder is byte-identical to the frozen reference for the enumerated full valid space", () => {
  const cases = validCases();
  assert.ok(cases.length > 3_000, `case generator unexpectedly small: ${cases.length}`);
  for (const { source, record } of cases) {
    const expected = referenceBytes(source);
    const length = harness.length(record);
    assert.equal(length.carry, 0, `${source}: formLength rejected valid form`);
    assert.equal(length.value, expected.length, `${source}: wrong formLength`);

    const actual = harness.encode(record);
    assert.equal(actual.carry, 0, `${source}: native encoder rejected valid form`);
    assert.equal(actual.value, expected.length, `${source}: wrong native length`);
    assert.equal(actual.de, harness.symbols.AtomHarnessOutput + expected.length, `${source}: wrong DE exit`);
    assert.deepEqual(actual.output.slice(0, expected.length), expected, source);
    assert.deepEqual(
      actual.output.slice(expected.length),
      Array(7 - expected.length).fill(0xa5),
      `${source}: commit crossed encoded length`,
    );
  }
});

test("formLength ignores every concrete value in every valid and rejected record", () => {
  const patterns = [
    [0, 0, 0, 0, 0, 0],
    [0xff, 0xff, 0xff, 0xff, 0xff, 0xff],
    [0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55],
    [0x00, 0x80, 0x7f, 0xff, 0x01, 0xfe],
  ];
  const rejected = invalidCases().filter(({ source }) => referenceRejects(source));
  for (const { source, record } of [...validCases(), ...rejected]) {
    const expected = harness.length(record);
    for (const pattern of patterns) {
      const changed = record.slice();
      changed.set(pattern, 4);
      const actual = harness.length(changed);
      assert.equal(actual.carry, expected.carry, source);
      assert.equal(actual.value, expected.value, source);
    }
  }
});

test("negative differential rejects invalid forms without committing bytes", () => {
  const candidates = invalidCases();
  let rejected = 0;
  for (const { source, record, matrix } of candidates) {
    const oracleRejected = referenceRejects(source);
    if (!oracleRejected && matrix) continue;
    assert.equal(oracleRejected, true, `${source}: malformed negative fixture is accepted by AZM`);
    rejected += 1;
    const length = harness.length(record);
    assert.equal(length.carry, 1, `${source}: formLength accepted rejected AZM form`);
    assert.equal(length.value, 0, `${source}: invalid length was nonzero`);
    const encoded = harness.encode(record);
    assert.equal(encoded.carry, 1, `${source}: encoder accepted rejected AZM form`);
    assert.equal(encoded.value, 0, `${source}: invalid encoding length was nonzero`);
    assert.equal(encoded.de, harness.symbols.AtomHarnessOutput, `${source}: rejection changed DE`);
    assert.deepEqual(encoded.output, Array(7).fill(0xa5), `${source}: rejection committed output`);
  }
  assert.ok(rejected > 500, `negative space unexpectedly small: ${rejected}`);
});

test("index-half collision rules have explicit discriminators", () => {
  const fixtures = [
    ["LD A,IXH", [O.A, O.IXH], true],
    ["LD IXH,IXL", [O.IXH, O.IXL], true],
    ["LD IXH,H", [O.IXH, O.H], false],
    ["LD H,IXH", [O.H, O.IXH], false],
    ["LD IXH,IYH", [O.IXH, O.IYH], false],
    ["LD H,(IX+1)", [O.H, O.INDEX_IX], true],
  ];
  for (const [source, operands, valid] of fixtures) {
    assert.equal(referenceRejects(source), !valid, source);
    const record = new Uint8Array([43, ...operands, 255, 0, 0, 1, 0, 0, 0]);
    const result = harness.length(record);
    assert.equal(result.carry, valid ? 0 : 1, source);
  }
});

test("validator rejects every unknown ordinal, operand-class hole, and hidden trailing operand", () => {
  for (const record of systematicInvalidRecords()) {
    const label = Buffer.from(record).toString("hex");
    const length = harness.length(record);
    assert.equal(length.carry, 1, `${label}: formLength accepted malformed record`);
    assert.equal(length.value, 0, `${label}: malformed length was nonzero`);
    const encoded = harness.encode(record);
    assert.equal(encoded.carry, 1, `${label}: encoder accepted malformed record`);
    assert.equal(encoded.de, harness.symbols.AtomHarnessOutput, `${label}: rejection changed DE`);
    assert.deepEqual(encoded.output, Array(7).fill(0xa5), `${label}: rejection committed bytes`);
  }
});

test("RADIX-40 exhausts ASCII classification, short arithmetic, and every field position", () => {
  for (let code = 0; code < 128; code += 1) {
    const text = String.fromCharCode(code);
    const expectedWords = packRadix40(text);
    const result = harness.pack(text);
    assert.equal(result.carry, expectedWords ? 0 : 1, `ASCII ${code}`);
    if (expectedWords) {
      const expected = expectedWords.flatMap((word) => [word & 0xff, word >>> 8]);
      assert.deepEqual(result.output.slice(0, 6), expected, `ASCII ${code}`);
    }
  }

  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";
  for (const first of alphabet) {
    for (const second of alphabet) {
      const text = first + second;
      const expected = packRadix40(text).flatMap((word) => [word & 0xff, word >>> 8]);
      const result = harness.pack(text);
      assert.equal(result.carry, 0, text);
      assert.deepEqual(result.output.slice(0, 6), expected, text);
    }
  }

  for (let position = 0; position < 8; position += 1) {
    for (const character of alphabet) {
      const text = `${"A".repeat(position)}${character}${"Z".repeat(7 - position)}`;
      const expected = packRadix40(text).flatMap((word) => [word & 0xff, word >>> 8]);
      const result = harness.pack(text);
      assert.equal(result.carry, 0, text);
      assert.deepEqual(result.output.slice(0, 6), expected, text);
    }
  }
});

test("measured public-entry execution remains inside the named proof budgets", () => {
  for (const [entry, budget] of Object.entries(harness.proofManifest.executionBudgets)) {
    const observed = harness.statistics[entry];
    assert.ok(observed, `${entry}: no runtime observation`);
    assert.ok(
      observed.instructions <= budget.maxInstructions,
      `${entry}: ${observed.instructions} instructions for ${observed.instructionCase}`,
    );
    assert.ok(
      observed.cycles <= budget.maxCycles,
      `${entry}: ${observed.cycles} cycles for ${observed.cycleCase}`,
    );
  }
});
