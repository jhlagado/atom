import assert from "node:assert/strict";
import test from "node:test";

let literals;
try {
  literals = await import("../src/host/atom/literals.mjs");
} catch {
  literals = {};
}

function parse(source, definitions) {
  assert.equal(typeof literals.parseAtomPreprocessorValue, "function");
  return literals.parseAtomPreprocessorValue(source, definitions);
}

test("preprocessor values accept every settled numeric spelling", () => {
  for (const [source, value] of [
    ["0", 0], ["65535", 0xffff], ["$FFFF", 0xffff], ["$ffff", 0xffff],
    ["%0", 0], ["%1", 1], ["%01110111", 0x77],
    ["0FFFFH", 0xffff], ["0ffffh", 0xffff],
    ["01110111B", 0x77], ["01110111b", 0x77],
  ]) assert.equal(parse(source), value, source);
});

test("preprocessor values resolve case-insensitive names", () => {
  const definitions = Object.freeze({ DEBUG: 1, FEATURE: 0xffff });
  assert.equal(parse("debug", definitions), 1);
  assert.equal(parse("Feature", definitions), 0xffff);
});

test("digit-led malformed and overflowing values fail as complete tokens", () => {
  for (const source of [
    "65536", "$10000", "%2", "%10102", "10000H", "12B", "0FFFFG",
    "+1", "-1", "1+1", "1 2", "", " 1", "1 ",
  ]) {
    assert.throws(
      () => parse(source),
      (error) => error?.category === "preprocessing" &&
        ["invalid-value", "value-range"].includes(error?.code),
      source,
    );
  }
});

test("a letter-led suffix spelling is a name, not a hexadecimal literal", () => {
  assert.equal(parse("FFFFH", { FFFFH: 7 }), 7);
  assert.throws(
    () => parse("FFFFH"),
    (error) => error?.category === "preprocessing" && error?.code === "undefined-definition",
  );
});
