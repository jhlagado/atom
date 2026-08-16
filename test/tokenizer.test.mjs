import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { M } from "../src/abi.mjs";
import { createTokenizerHarness, TOKEN, TOKEN_STATUS } from "./tokenizer-support.mjs";

const h = await createTokenizerHarness();
const memoryProfile = JSON.parse(fs.readFileSync("proofs/phase-2b-memory.json", "utf8"));

function resolve(value) {
  if (typeof value === "number") return value;
  assert.ok(value in h.symbols, `missing tokenizer proof symbol ${value}`);
  return h.symbols[value];
}

function first(source, options) {
  h.reset(source, options);
  return h.next(`first token of ${JSON.stringify(String(source).slice(0, 40))}`);
}

test("Phase 2b memory profile covers exactly 64 KiB without gaps or overlap", () => {
  const regions = memoryProfile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(regions[0].startAddress, 0);
  for (let index = 0; index < regions.length; index += 1) {
    const region = regions[index];
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
  }
  assert.equal(regions.at(-1).endAddress, memoryProfile.addressSpaceBytes);
  for (const extent of memoryProfile.extents) {
    assert.equal(resolve(extent.end) - resolve(extent.start), extent.exactBytes, `${extent.name}: extent drift`);
  }
  assert.equal(h.symbols.AtomTokenRecordBytes, 9);
});

test("mixed-case instruction source composes directly with mnemonic recognition", () => {
  const source = "  lD a,(Ix-$80) ; note\r\n.Again: dB \"A\\n\", %1010 << 1\n";
  const result = h.tokenize(source, { part: 19 });
  assert.equal(result.error, undefined);
  const tokens = result.tokens;
  assert.deepEqual(tokens.map(({ kind }) => kind), [
    TOKEN.NAME, TOKEN.NAME, TOKEN.COMMA, TOKEN.LEFT_PAREN, TOKEN.NAME,
    TOKEN.MINUS, TOKEN.NUMBER, TOKEN.RIGHT_PAREN, TOKEN.EOL,
    TOKEN.NAME, TOKEN.COLON, TOKEN.NAME, TOKEN.STRING, TOKEN.COMMA,
    TOKEN.NUMBER, TOKEN.LEFT_SHIFT, TOKEN.NUMBER, TOKEN.EOL, TOKEN.EOF,
  ]);
  assert.deepEqual(tokens.map(({ lexeme }) => lexeme), [
    "lD", "a", ",", "(", "Ix", "-", "$80", ")", "\r\n",
    ".Again", ":", "dB", "\"A\\n\"", ",", "%1010", "<<", "1", "\n", "",
  ]);
  assert.ok(tokens.every(({ part }) => part === 19));
  assert.equal(tokens[6].value, 0x80);
  assert.equal(tokens[14].value, 10);
  const mnemonic = h.recognize(tokens[0]);
  assert.equal(mnemonic.carry, 0);
  assert.equal(mnemonic.status, M.LD);
});

test("comments and blank lines disappear while a final non-empty line gets one synthetic EOL", () => {
  const source = "; first\n\n  NOP ; trailing";
  const { tokens, error } = h.tokenize(source);
  assert.equal(error, undefined);
  assert.deepEqual(tokens.map(({ kind }) => kind), [TOKEN.NAME, TOKEN.EOL, TOKEN.EOF]);
  assert.deepEqual(tokens.map(({ lexeme }) => lexeme), ["NOP", "", ""]);
  assert.equal(tokens[0].offset, source.indexOf("NOP"));
  assert.equal(tokens[1].offset, source.length);
  assert.equal(tokens[2].offset, source.length);
});

test("global and private name limits are exact, case preserving, and failure atomic", () => {
  for (const name of ["A", "abcdefgh", "_", "_abcdefg", ".A", ".abcdefgh"]) {
    const token = first(name);
    assert.equal(token.carry, 0, name);
    assert.equal(token.record.kind, TOKEN.NAME, name);
    assert.equal(h.lexeme(token.record), name, name);
  }

  for (const name of ["abcdefghi", "_abcdefgh", ".abcdefghi"]) {
    h.reset("NOP");
    const previous = h.next().record.bytes;
    h.reset(name);
    const before = h.record().bytes;
    const rejected = h.next(name);
    assert.equal(rejected.carry, 1, name);
    assert.equal(rejected.status, TOKEN_STATUS.NAME_TOO_LONG, name);
    assert.deepEqual(rejected.record.bytes, before, name);
    assert.notDeepEqual(previous, [], name);
    assert.deepEqual(h.errorPosition(), { status: TOKEN_STATUS.NAME_TOO_LONG, part: 7, offset: 0 });
  }

  const lonePrivate = first(".");
  assert.equal(lonePrivate.carry, 1);
  assert.equal(lonePrivate.status, TOKEN_STATUS.INVALID_BYTE);
});

test("ASCII classifiers are exhaustive and return exact hexadecimal values", () => {
  for (let byte = 0; byte <= 0xff; byte += 1) {
    const char = String.fromCharCode(byte);
    const letter = /[A-Za-z]/.test(char);
    const nameStart = letter || char === "_";
    const nameByte = nameStart || /[0-9]/.test(char);
    const digit = /^[0-9A-Fa-f]$/.test(char) ? Number.parseInt(char, 16) : undefined;

    assert.equal(h.classify("AtomTokenIsLetter", byte).carry, Number(letter), `letter ${byte}`);
    assert.equal(h.classify("AtomTokenIsNameStart", byte).carry, Number(nameStart), `start ${byte}`);
    assert.equal(h.classify("AtomTokenIsNameByte", byte).carry, Number(nameByte), `name ${byte}`);
    const hex = h.classify("AtomTokenHexDigit", byte);
    assert.equal(hex.carry, Number(digit !== undefined), `hex ${byte}`);
    if (digit !== undefined) assert.equal(hex.status, digit, `hex value ${byte}`);
  }
});

test("decimal, hexadecimal, binary, current-location, and percent boundaries are exact", () => {
  for (const [source, value] of [
    ["0", 0], ["1", 1], ["255", 255], ["256", 256], ["32767", 32767],
    ["32768", 32768], ["65535", 65535], ["$0", 0], ["$ff", 255],
    ["$FFFF", 65535], ["%0", 0], ["%1", 1], ["%1111111111111111", 65535],
  ]) {
    const result = first(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.record.kind, TOKEN.NUMBER, source);
    assert.equal(result.record.value, value, source);
    assert.equal(h.lexeme(result.record), source, source);
  }

  assert.equal(first("$").record.kind, TOKEN.CURRENT);
  assert.equal(first("%").record.kind, TOKEN.PERCENT);

  for (const source of ["65536", "$10000", "%11111111111111111"]) {
    const result = first(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.NUMBER_OVERFLOW, source);
  }
  for (const source of ["$G", "$1G", "%102", "12A", "0x10"]) {
    const result = first(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.INVALID_NUMBER, source);
  }
});

test("Intel suffix literals match prefix spellings with exact 16-bit boundaries", () => {
  for (const [source, value] of [
    ["0H", 0], ["00h", 0], ["0FFFFH", 0xffff], ["0ffffh", 0xffff],
    ["0B", 0], ["000b", 0], ["01110111B", 0x77], ["01110111b", 0x77],
  ]) {
    const result = first(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.record.kind, TOKEN.NUMBER, source);
    assert.equal(result.record.value, value, source);
    assert.equal(h.lexeme(result.record), source, source);
  }
  assert.equal(first("0FFFFH").record.value, first("$FFFF").record.value);
  assert.equal(first("01110111B").record.value, first("%01110111").record.value);
  assert.equal(first("FFFFH").record.kind, TOKEN.NAME);

  for (const [source, status] of [
    ["10000H", TOKEN_STATUS.NUMBER_OVERFLOW],
    ["11111111111111111B", TOKEN_STATUS.NUMBER_OVERFLOW],
    ["12B", TOKEN_STATUS.INVALID_NUMBER],
    ["102B", TOKEN_STATUS.INVALID_NUMBER],
    ["0FG", TOKEN_STATUS.INVALID_NUMBER],
    ["0x10", TOKEN_STATUS.INVALID_NUMBER],
  ]) {
    h.reset("NOP");
    const prior = h.next().record.bytes;
    h.reset(source);
    const before = h.record().bytes;
    const cursorBefore = h.memory[h.symbols.AtomTokenSourceCursor] |
      (h.memory[h.symbols.AtomTokenSourceCursor + 1] << 8);
    const result = h.next(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, status, source);
    assert.deepEqual(result.record.bytes, before, source);
    assert.equal(
      h.memory[h.symbols.AtomTokenSourceCursor] |
        (h.memory[h.symbols.AtomTokenSourceCursor + 1] << 8),
      cursorBefore,
      `${source}: source cursor changed on failure`,
    );
    assert.notDeepEqual(prior, [], source);
    assert.deepEqual(h.errorPosition(), { status, part: 7, offset: 0 }, source);
  }
});

test("leaked line-start host directives fail without stealing percent expressions", () => {
  for (const [source, offset] of [
    ["%include \"lib.asm\"", 0],
    ["  \t%IF DEBUG", 3],
  ]) {
    h.reset(source);
    const before = h.record().bytes;
    const result = h.next(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.UNPROCESSED_DIRECTIVE, source);
    assert.deepEqual(result.record.bytes, before, source);
    assert.deepEqual(h.errorPosition(), {
      status: TOKEN_STATUS.UNPROCESSED_DIRECTIVE,
      part: 7,
      offset,
    });
  }

  h.reset("NOP\n%endif");
  assert.equal(h.next().record.kind, TOKEN.NAME);
  assert.equal(h.next().record.kind, TOKEN.EOL);
  const leaked = h.next("directive after EOL");
  assert.equal(leaked.carry, 1);
  assert.equal(leaked.status, TOKEN_STATUS.UNPROCESSED_DIRECTIVE);
  assert.deepEqual(h.errorPosition(), {
    status: TOKEN_STATUS.UNPROCESSED_DIRECTIVE,
    part: 7,
    offset: 4,
  });

  let result = h.tokenize("%1\nLD A,%1\nA % B\n");
  assert.equal(result.error, undefined);
  assert.deepEqual(result.tokens.map(({ kind, lexeme }) => [kind, lexeme]), [
    [TOKEN.NUMBER, "%1"], [TOKEN.EOL, "\n"],
    [TOKEN.NAME, "LD"], [TOKEN.NAME, "A"], [TOKEN.COMMA, ","],
    [TOKEN.NUMBER, "%1"], [TOKEN.EOL, "\n"],
    [TOKEN.NAME, "A"], [TOKEN.PERCENT, "%"], [TOKEN.NAME, "B"],
    [TOKEN.EOL, "\n"], [TOKEN.EOF, ""],
  ]);
});

test("strings preserve raw payload and validate every supported escape", () => {
  for (const source of ["\"\"", "\"A\"", "\"\\n\"", "\"\\x41\"", "\"\\\"\"", "\"\\\\\""]) {
    const result = first(source);
    assert.equal(result.carry, 0, source);
    assert.equal(result.record.kind, TOKEN.STRING, source);
    assert.equal(result.record.length, source.length, source);
    assert.equal(h.lexeme(result.record), source, source);
  }

  for (const source of ["\"\\q\"", "\"\\x4G\""]) {
    const result = first(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.INVALID_ESCAPE, source);
  }
  for (const source of ["\"A", "\"A\n\""]) {
    const result = first(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.UNTERMINATED_STRING, source);
  }
});

test("raw string length accepts 254 and 255 bytes and rejects 256 atomically", () => {
  for (const rawLength of [254, 255]) {
    const source = `"${"A".repeat(rawLength - 2)}"`;
    const result = first(source);
    assert.equal(result.carry, 0, `${rawLength} bytes`);
    assert.equal(result.record.length, rawLength);
  }
  const source = `"${"A".repeat(254)}"`;
  h.reset(source);
  const before = h.record().bytes;
  const result = h.next("256-byte string");
  assert.equal(result.carry, 1);
  assert.equal(result.status, TOKEN_STATUS.STRING_TOO_LONG);
  assert.deepEqual(result.record.bytes, before);
});

test("punctuation is complete for the Phase 2b expression surface", () => {
  const source = ", : ( ) + - * / & ^ | ~ ' << >> $ %\n";
  const { tokens, error } = h.tokenize(source);
  assert.equal(error, undefined);
  assert.deepEqual(tokens.map(({ kind }) => kind), [
    TOKEN.COMMA, TOKEN.COLON, TOKEN.LEFT_PAREN, TOKEN.RIGHT_PAREN,
    TOKEN.PLUS, TOKEN.MINUS, TOKEN.STAR, TOKEN.SLASH, TOKEN.AMPERSAND,
    TOKEN.CARET, TOKEN.PIPE, TOKEN.TILDE, TOKEN.APOSTROPHE,
    TOKEN.LEFT_SHIFT, TOKEN.RIGHT_SHIFT, TOKEN.CURRENT, TOKEN.PERCENT,
    TOKEN.EOL, TOKEN.EOF,
  ]);
});

test("the narrower-than-AZM lexical boundary is explicit", () => {
  for (const source of ["0x10", "0b10"]) {
    const result = first(source);
    assert.equal(result.carry, 1, source);
    assert.equal(result.status, TOKEN_STATUS.INVALID_NUMBER, source);
  }

  let result = h.tokenize("'A'");
  assert.equal(result.error, undefined);
  assert.deepEqual(result.tokens.map(({ kind }) => kind), [
    TOKEN.APOSTROPHE, TOKEN.NAME, TOKEN.APOSTROPHE, TOKEN.EOL, TOKEN.EOF,
  ]);

  result = h.tokenize("A.B");
  assert.equal(result.error, undefined);
  assert.deepEqual(result.tokens.map(({ kind, lexeme }) => [kind, lexeme]), [
    [TOKEN.NAME, "A"], [TOKEN.NAME, ".B"], [TOKEN.EOL, ""], [TOKEN.EOF, ""],
  ]);

  for (const source of ["?A", "[0]", "<byte>A"]) {
    const rejected = first(source);
    assert.equal(rejected.carry, 1, source);
    assert.equal(rejected.status, TOKEN_STATUS.INVALID_BYTE, source);
  }
});

test("malformed shifts, bare CR, and arbitrary bytes retain the prior token record", () => {
  for (const source of ["<", ">", "\r", Uint8Array.of(0), Uint8Array.of(0x7f), Uint8Array.of(0xff)]) {
    h.reset(source);
    const before = h.record().bytes;
    const result = h.next(`invalid ${JSON.stringify(source)}`);
    assert.equal(result.carry, 1);
    assert.equal(result.status, TOKEN_STATUS.INVALID_BYTE);
    assert.deepEqual(result.record.bytes, before);
    assert.deepEqual(h.errorPosition(), { status: TOKEN_STATUS.INVALID_BYTE, part: 7, offset: 0 });
  }
});

test("reset rejects a reversed interval without changing established tokenizer state", () => {
  h.reset("NOP", { part: 23 });
  const state = Array.from(h.memory.slice(h.symbols.AtomTokenizerWorkspaceStart, h.symbols.AtomTokenizerWorkspaceEnd));
  const result = h.resetRange(h.symbols.AtomTokenizerSource + 1, h.symbols.AtomTokenizerSource, 99);
  assert.equal(result.carry, 1);
  assert.equal(result.status, TOKEN_STATUS.BAD_SOURCE_RANGE);
  assert.deepEqual(
    Array.from(h.memory.slice(h.symbols.AtomTokenizerWorkspaceStart, h.symbols.AtomTokenizerWorkspaceEnd)),
    state,
  );
});

test("empty and exact-buffer-end parts terminate without reading either canary", () => {
  let result = h.reset("");
  assert.equal(result.carry, 0);
  result = h.next("empty EOF");
  assert.equal(result.record.kind, TOKEN.EOF);

  const source = " ".repeat(h.symbols.AtomTokenizerSourceLimit - h.symbols.AtomTokenizerSource);
  result = h.reset(source);
  assert.equal(result.carry, 0);
  result = h.next("full-buffer EOF");
  assert.equal(result.record.kind, TOKEN.EOF);
});
