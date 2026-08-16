import assert from "node:assert/strict";
import test from "node:test";

import { createAtomSourceProfile } from "../src/host/atom/source-profile.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function inspect(source, logicalIdentity = "main.asm") {
  const originalBytes = encoder.encode(source);
  const result = createAtomSourceProfile().inspectEntry(
    { logicalIdentity, originalBytes },
    { definitions: {} },
  );
  return { ...result, originalBytes };
}

test("masking preserves length and every LF or CRLF byte", () => {
  for (const newline of ["\n", "\r\n"]) {
    const source = [
      "%if %0",
      "  LD A,$FF",
      "%else",
      "\tNOP ; active",
      "%endif",
      "HALT",
      "",
    ].join(newline);
    const result = inspect(source);
    assert.equal(result.compilerBytes.length, result.originalBytes.length);
    for (let offset = 0; offset < result.originalBytes.length; offset += 1) {
      const original = result.originalBytes[offset];
      if (original === 0x0a || original === 0x0d) {
        assert.equal(result.compilerBytes[offset], original, `newline at ${offset}`);
      }
    }
    const lines = decoder.decode(result.compilerBytes).split(newline);
    assert.match(lines[0], /^\s+$/);
    assert.match(lines[1], /^\s+$/);
    assert.match(lines[2], /^\s+$/);
    assert.equal(lines[3], "\tNOP ; active");
    assert.match(lines[4], /^\s+$/);
    assert.equal(lines[5], "HALT");
  }
});

test("nested conditions mask only inactive ordinary lines", () => {
  const source = [
    "%if %1",
    "OUTER",
    "%if %0",
    "HIDDEN_A",
    "%else",
    "INNER",
    "%endif",
    "%else",
    "HIDDEN_B",
    "%endif",
    "TAIL",
    "",
  ].join("\n");
  const result = inspect(source);
  const output = decoder.decode(result.compilerBytes);
  assert.match(output, /OUTER/);
  assert.match(output, /INNER/);
  assert.match(output, /TAIL/);
  assert.doesNotMatch(output, /HIDDEN_A|HIDDEN_B|%if|%else|%endif/);
});

test("inactive includes create no dependency while directive structure is still checked", () => {
  const result = inspect("%if %0\n%include \"unused.asm\"\n%endif\nNOP\n");
  assert.deepEqual(result.dependencies, []);
  assert.throws(
    () => inspect("%if %0\n%else\n%else\n%endif\n"),
    (error) => error?.code === "duplicate-else",
  );
});

test("masked ranges and dependency locations use original byte offsets", () => {
  const source = "\t %include \"lib.asm\"\n%if %0\nHIDDEN\n%endif\nNOP\n";
  const result = inspect(source);
  assert.deepEqual(result.dependencies, [{
    specifier: "lib.asm",
    location: { logicalIdentity: "main.asm", offset: 2, line: 1, column: 3 },
  }]);
  assert.deepEqual(result.maskedRanges, [
    { start: 0, end: 20 },
    { start: 21, end: 27 },
    { start: 28, end: 34 },
    { start: 35, end: 41 },
  ]);
});
