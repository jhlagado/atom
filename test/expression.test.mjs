import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { referenceBytes } from "./reference-fixtures.mjs";
import { createExpressionHarness, EXPRESSION } from "./expression-support.mjs";

const h = await createExpressionHarness({ contracts: process.env.ATOM_EXPRESSION_CONTRACTS ?? "strict" });
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2d-memory.json", "utf8"));

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing expression proof symbol ${value}`);
  return h.symbols[value];
}

test("Phase 2d memory profile covers exactly 64 KiB without gaps or overlap", () => {
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

function referenceWord(expression) {
  const bytes = referenceBytes(`LD HL,${expression}`);
  assert.equal(bytes[0], 0x21, expression);
  return bytes[1] | (bytes[2] << 8);
}

test("precedence, associativity, unary operations, and current address match the frozen reference", () => {
  const cases = [
    ["0", 0], ["65535", 65535], ["-1", 0xffff], ["-32768", 0x8000],
    ["1+2*3", 7], ["(1+2)*3", 9], ["20-5-3", 12],
    ["100/5/2", 10], ["100%9", 1], ["-7/3", 0xfffe], ["-7%3", 0xffff],
    ["1|2^3&6", 1], ["1<<5+2", 128], ["256>>4", 16],
    ["~1&$FF", 254], ["255*257", 65535], ["65535/255", 257],
    ["$+2", 0x4002], ["+(2+3)", 5], ["~~0", 0],
  ];
  for (const [source, expected] of cases) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.RESOLVED, source);
    assert.equal(result.hl, expected, source);
    assert.equal(result.hl, referenceWord(source), `AZM ${source}`);
    assert.equal(result.delimiter, 1, source);
  }
});

test("forward keys and concrete arithmetic safely reuse the expression workspace", () => {
  h.reset();
  for (const [source, status, value] of [
    ["Forward+5", EXPRESSION.UNRESOLVED, 5],
    ["6*7", EXPRESSION.RESOLVED, 42],
    ["Forward-3", EXPRESSION.UNRESOLVED, -3],
    ["100/4", EXPRESSION.RESOLVED, 25],
  ]) {
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, status, source);
    assert.equal((result.hl << 16) >> 16, value, source);
  }
});

test("all concrete operators accept nested whitespace and stop before delimiters", () => {
  h.reset();
  let result = h.evaluate(" 1 + ( 2 * 3 ) , 9 ");
  assert.equal(result.carry, 0);
  assert.equal(result.hl, 7);
  assert.equal(result.delimiter, 6);

  h.reset();
  result = h.evaluate("($10 << 2) | (%11 ^ 1)");
  assert.equal(result.carry, 0);
  assert.equal(result.hl, 66);
  assert.equal(result.hl, referenceWord("($10 << 2) | (%11 ^ 1)"));
});

test("LOW and HIGH are case-insensitive byte functions matching the frozen reference", () => {
  for (const [source, oracle] of [
    ["LOW($1234)", "LSB($1234)"],
    ["hIgH($1234)", "MSB($1234)"],
    ["LOW(1+$12FF)", "LSB(1+$12FF)"],
    ["HIGH(-1)", "MSB(-1)"],
    ["HIGH(LOW($1234))", "MSB(LSB($1234))"],
  ]) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.RESOLVED, source);
    assert.equal(result.hl, referenceWord(oracle), source);
  }
});

test("LOW and HIGH retain one forward affine symbol for byte patching", () => {
  for (const [source, transform, addend] of [
    ["LOW(Target)", 2, 0],
    ["HIGH(Target+5)", 3, 5],
    ["low(5+Target)", 2, 5],
  ]) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.UNRESOLVED, source);
    assert.equal((result.hl << 16) >> 16, addend, source);
    assert.equal(h.memory[h.symbols.AtomExpressionResultUnresolved], transform, source);
  }

  for (const [source, status] of [
    ["LOW()", EXPRESSION.EXPECTED_PRIMARY],
    ["LOW(Target)+1", EXPRESSION.FORWARD_FORM],
    ["HIGH(LOW(Target))", EXPRESSION.FORWARD_FORM],
  ]) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, status, source);
    assert.equal(result.afterGlobalEnd, result.beforeGlobalEnd, source);
  }
});

test("boundary-partitioned concrete arithmetic is byte-identical to the frozen reference", () => {
  const values = [0, 1, 2, 7, 127, 128, 255, 256, 32767, 32768, 65534, 65535];
  const cases = new Set();
  for (const left of values) {
    for (const right of values) {
      if (left + right <= 65535) cases.add(`${left}+${right}`);
      if (left - right >= -32768) cases.add(`${left}-${right}`);
      if (left * right <= 65535) cases.add(`${left}*${right}`);
      if (right !== 0) {
        cases.add(`${left}/${right}`);
        cases.add(`${left} % ${right}`);
      }
      cases.add(`${left}&${right}`);
      cases.add(`${left}^${right}`);
      cases.add(`${left}|${right}`);
    }
    for (const count of [0, 1, 7, 8, 15]) {
      if (left * 2 ** count <= 65535) cases.add(`${left}<<${count}`);
      cases.add(`${left}>>${count}`);
    }
  }
  for (const source of cases) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.RESOLVED, source);
    assert.equal(result.hl, referenceWord(source), source);
  }
});

test("signed boundary partitions are byte-identical to the frozen reference", () => {
  const values = [-32768, -255, -2, -1, 0, 1, 2, 255, 32767];
  const cases = new Set();
  for (const left of values) {
    for (const right of values) {
      for (const [operator, value] of [["+", left + right], ["-", left - right], ["*", left * right]]) {
        if (value >= -32768 && value <= 65535) cases.add(`(${left})${operator}(${right})`);
      }
      if (right !== 0) {
        cases.add(`(${left})/(${right})`);
        cases.add(`(${left}) % (${right})`);
      }
      for (const operator of ["&", "^", "|"]) cases.add(`(${left})${operator}(${right})`);
    }
    for (const count of [0, 1, 7, 15]) {
      const shifted = left * 2 ** count;
      if (shifted >= -32768 && shifted <= 65535) cases.add(`(${left})<<${count}`);
      cases.add(`(${left})>>${count}`);
    }
  }
  assert.equal(cases.size, 660);
  for (const source of cases) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.RESOLVED, source);
    assert.equal(result.hl, referenceWord(source), source);
  }
});

test("defined global and private symbols resolve case-insensitively", () => {
  h.reset();
  assert.equal(h.declare("Base", 0x1234).carry, 0);
  let result = h.evaluate("bAsE + 2");
  assert.equal(result.carry, 0);
  assert.equal(result.status, EXPRESSION.RESOLVED);
  assert.equal(result.hl, 0x1236);

  assert.equal(h.advanceScope().carry, 0);
  assert.equal(h.declare(".Local", 0x2345).carry, 0);
  result = h.evaluate(".lOcAl-1");
  assert.equal(result.carry, 0);
  assert.equal(result.hl, 0x2344);
});

test("affine forward symbols publish only after a complete valid expression", () => {
  for (const [source, addend] of [
    ["Forward", 0], ["Forward+5", 5], ["5+Forward", 5],
    ["Forward-5", -5], ["Forward+(2*3)", 6],
  ]) {
    h.reset();
    const result = h.evaluate(source, { part: 19 });
    assert.equal(result.carry, 0, source);
    assert.equal(result.status, EXPRESSION.UNRESOLVED, source);
    assert.equal((result.hl << 16) >> 16, addend, source);
    assert.equal(result.afterGlobalEnd, result.beforeGlobalEnd + 8, source);
    assert.ok(result.ix >= h.symbols.AtomExpressionSymbolArena, source);
  }

  h.reset();
  let result = h.evaluate("Forward+2+3");
  assert.equal(result.carry, 0);
  assert.equal((result.hl << 16) >> 16, 5);
  const record = result.ix;
  result = h.evaluate("forward-(-5)");
  assert.equal(result.carry, 0);
  assert.equal(result.ix, record);
  assert.equal((result.hl << 16) >> 16, 5);
  assert.equal(result.afterGlobalEnd, result.beforeGlobalEnd, "repeat reference inserted a record");
  assert.equal(h.declare("FORWARD", 0x5000).carry, 0);
  result = h.evaluate("Forward+5");
  assert.equal(result.carry, 0);
  assert.equal(result.status, EXPRESSION.RESOLVED);
  assert.equal(result.hl, 0x5005);

  for (const [source, status] of [
    ["New+", EXPRESSION.EXPECTED_PRIMARY],
    ["New*2", EXPRESSION.FORWARD_FORM],
    ["New+Other", EXPRESSION.FORWARD_FORM],
    ["New+128", EXPRESSION.RANGE],
    ["New-129", EXPRESSION.RANGE],
  ]) {
    h.reset();
    const result = h.evaluate(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, status, source);
    assert.equal(result.afterGlobalEnd, result.beforeGlobalEnd, `${source}: symbol leaked`);
    assert.equal(result.afterLocalBegin, result.beforeLocalBegin, `${source}: private symbol leaked`);
  }
});

test("private forward references require an active global scope", () => {
  h.reset();
  let result = h.evaluate(".Later");
  assert.equal(result.carry, 1);
  assert.equal(result.status, EXPRESSION.SYMBOL);
  assert.equal(result.error.symbolStatus, 4);
  assert.equal(result.afterLocalBegin, result.beforeLocalBegin);

  assert.equal(h.advanceScope().carry, 0);
  result = h.evaluate(".Later-1");
  assert.equal(result.carry, 0);
  assert.equal(result.status, EXPRESSION.UNRESOLVED);
  assert.equal((result.hl << 16) >> 16, -1);
  assert.equal(result.afterLocalBegin, result.beforeLocalBegin - 8);
});

test("unresolved results queue the exact seven-byte pending record", () => {
  h.reset();
  const result = h.evaluate("Target-3");
  assert.equal(result.carry, 0);
  assert.equal(result.status, EXPRESSION.UNRESOLVED);
  const queued = h.queue(result.ix, -3, 0x4567, 2, 0xff);
  assert.equal(queued.carry, 0);
  assert.deepEqual(h.pendingRecord(), [result.ix & 0xff, result.ix >>> 8, 0x67, 0x45, 2, 0xfd, 0xff]);
});

test("range, divide, syntax, lexical, and nesting failures are distinct and positioned", () => {
  const cases = [
    ["1/0", EXPRESSION.DIVIDE_ZERO, 1],
    ["1 % 0", EXPRESSION.DIVIDE_ZERO, 2],
    ["1+", EXPRESSION.EXPECTED_PRIMARY, 2],
    ["(1+2", EXPRESSION.EXPECTED_RIGHT, 4],
    ["65535+1", EXPRESSION.RANGE, 7],
    ["-32769", EXPRESSION.RANGE, 6],
    ["1<<24", EXPRESSION.RANGE, 1],
    ["65535*65535", EXPRESSION.RANGE, 5],
    ["1+$10000", EXPRESSION.LEXICAL, 2],
  ];
  for (const [source, status, offset] of cases) {
    h.reset();
    const result = h.evaluate(source, { part: 23 });
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, status, source);
    assert.equal(result.error.part, 23, source);
    assert.equal(result.error.offset, offset, source);
    assert.equal(result.afterGlobalEnd, result.beforeGlobalEnd, source);
  }

  h.reset();
  const nested = `${"(".repeat(17)}1${")".repeat(17)}`;
  const result = h.evaluate(nested);
  assert.equal(result.carry, 1);
  assert.equal(result.status, EXPRESSION.CAPACITY);
  assert.ok(h.memory[h.symbols.AtomExpressionValueDepth] <= 16);
  assert.ok(h.memory[h.symbols.AtomExpressionOperatorDepth] <= 16);
  h.reset();
  const recovered = h.evaluate("1+2");
  assert.equal(recovered.carry, 0);
  assert.equal(recovered.hl, 3);
});
