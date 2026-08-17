import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { validCases, invalidCases } from "./cases.mjs";
import { azmBytes, azmRejects } from "./support.mjs";
import { createParserHarness, PARSER_STATUS } from "./parser-support.mjs";

const h = await createParserHarness({ contracts: process.env.ATOM_PARSER_CONTRACTS ?? "strict" });
const census = JSON.parse(fs.readFileSync("proofs/azm-form-census.json", "utf8"));
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2c-memory.json", "utf8"));
const valid = validCases();
const invalid = invalidCases().filter(({ source }) => azmRejects(source));

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing parser proof symbol ${value}`);
  return h.symbols[value];
}

test("Phase 2c memory profile covers exactly 64 KiB without gaps or overlap", () => {
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

test("native parser emits the exact encoder record and AZM bytes for every supported form", () => {
  for (const [index, item] of valid.entries()) {
    const parsed = h.parse(item.source);
    assert.equal(parsed.carry, 0, `${index}: ${item.source} status=${parsed.status}`);
    assert.equal(parsed.status, PARSER_STATUS.OK, `${index}: ${item.source}`);
    assert.equal(parsed.ix, h.symbols.AtomParserRecord, `${index}: destination ${item.source}`);
    assert.deepEqual(parsed.record, Array.from(item.record), `${index}: record ${item.source}`);
    const encoded = h.encodeParsed(item.source);
    assert.equal(encoded.carry, 0, `${index}: encode ${item.source}`);
    assert.deepEqual(encoded.bytes, azmBytes(item.source), `${index}: bytes ${item.source}`);
  }
  assert.equal(valid.length, census.caseCount);
});

test("case-insensitive spellings preserve every parsed record and byte encoding", () => {
  const swapCase = (source) => source.replace(/[A-Za-z]/g, (char, index) => index % 2 ? char.toUpperCase() : char.toLowerCase());
  for (const [index, item] of valid.entries()) {
    const source = swapCase(item.source);
    const parsed = h.parse(source);
    assert.equal(parsed.carry, 0, `${index}: ${source} status=${parsed.status}`);
    assert.deepEqual(parsed.record, Array.from(item.record), `${index}: record ${source}`);
    const encoded = h.encodeParsed(source);
    assert.deepEqual(encoded.bytes, azmBytes(item.source), `${index}: bytes ${source}`);
  }
});

test("AZM-rejected form space is rejected atomically", () => {
  for (const [index, item] of invalid.entries()) {
    const parsed = h.parse(item.source);
    assert.equal(parsed.carry, 1, `${index}: parser accepted ${item.source}`);
    assert.notEqual(parsed.status, PARSER_STATUS.OK, `${index}: ${item.source}`);
    assert.deepEqual(parsed.record, parsed.before, `${index}: partial record for ${item.source}`);
  }
  assert.equal(invalid.length, 526);
});

test("concrete grammar and range failures are explicit and atomic", () => {
  const cases = [
    ["", PARSER_STATUS.EOF, 0],
    ["NOPE", PARSER_STATUS.UNKNOWN_MNEMONIC, 1],
    ["LD A,", PARSER_STATUS.EXPECTED_OPERAND, 1],
    ["LD A B", PARSER_STATUS.EXPECTED_DELIMITER, 1],
    ["LD A,B,C,D", PARSER_STATUS.TOO_MANY_OPERANDS, 1],
    ["LD Q,A", PARSER_STATUS.INVALID_FORM, 1],
    ["LD A,$10000", PARSER_STATUS.LEXICAL, 1],
    ["LD A,$100", PARSER_STATUS.VALUE_RANGE, 1],
    ["LD A,(IX+128)", PARSER_STATUS.VALUE_RANGE, 1],
    ["LD A,(IY-129)", PARSER_STATUS.VALUE_RANGE, 1],
    ["JR $3F81", PARSER_STATUS.RELATIVE_RANGE, 1],
    ["JR $4082", PARSER_STATUS.RELATIVE_RANGE, 1],
  ];
  for (const [source, status, carry] of cases) {
    const parsed = h.parse(source);
    assert.equal(parsed.carry, carry, source);
    assert.equal(parsed.status, status, source);
    assert.deepEqual(parsed.record, parsed.before, source);
  }
});

test("all indexed-zero aliases and current-address relative boundaries are exact", () => {
  const zeroDisplacement = valid.filter(({ source }) => /\(I[XY]\+0\)/.test(source));
  assert.equal(zeroDisplacement.length, 484);
  for (const item of zeroDisplacement) {
    for (const source of [
      item.source.replace(/\(I([XY])\+0\)/g, "(I$1)"),
      item.source.replace(/\(I([XY])\+0\)/g, "(I$1-0)"),
    ]) {
      const parsed = h.parse(source);
      assert.equal(parsed.carry, 0, source);
      assert.deepEqual(parsed.record, Array.from(item.record), source);
      const encoded = h.encodeParsed(source);
      assert.deepEqual(encoded.bytes, azmBytes(source), source);
    }
  }
  for (const [source, expected] of [["JR $3F82", -128], ["JR $4081", 127]]) {
    const parsed = h.parse(source, { address: 0x4000 });
    assert.equal(parsed.carry, 0, source);
    assert.equal(((parsed.record[4] | (parsed.record[5] << 8)) << 16) >> 16, expected, source);
  }
});
