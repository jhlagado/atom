import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";

import {
  NATIVE_CORE_MODULES,
  setNativeCoreOrigin,
} from "../src/host/build/z80-source-layout.mjs";
import { MNEMONICS } from "../src/host/abi.mjs";

const instructionNames = new Set(MNEMONICS.filter(Boolean));

function instructionMnemonic(line) {
  const statement = line.trimStart()
    .replace(/^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*:\s*/, "")
    .trimStart();
  const mnemonic = /^([A-Za-z]+)\b/.exec(statement)?.[1]?.toUpperCase();
  return instructionNames.has(mnemonic) ? mnemonic : undefined;
}

function assertInstructionExplanation(line, location) {
  if (instructionMnemonic(line) !== undefined) {
    assert.match(line, /\s;\s+\S/, `${location} needs an inline instruction explanation`);
  }
}

const KEY_NAMES = Object.freeze({
  AtomAssemble: "DR_ASM",
  AtomEncoderCodeStart: "EN_CODEB",
  AtomHostResidentEnd: "HS_REND",
  AtomOutputResolveSymbol: "OU_RSLV",
  AtomParserParse: "PR_PARSE",
  AtomRadix40Pack: "EN_R40PK",
  AtomSymbolFind: "SY_FIND",
  AtomTokenizerReset: "TK_RESET",
});

test("native origin replacement accepts and preserves source indentation", () => {
  const original = "    ORG 0\n    NOP\n";
  const modules = new Map([["encoder.asm", original]]);
  const result = setNativeCoreOrigin(modules, "ORG $0100\nJP ENTRY\nDS 13");

  assert.equal(modules.get("encoder.asm"), original);
  assert.equal(result.get("encoder.asm"), "    ORG $0100\n    JP ENTRY\n    DS 13\n    NOP\n");
});

test("inline instruction commentary also covers label-prefixed instructions", () => {
  assert.throws(
    () => assertInstructionExplanation("ENTRY: NOP", "sample.asm:1"),
    /sample\.asm:1 needs an inline instruction explanation/,
  );
  assert.doesNotThrow(() => assertInstructionExplanation("ENTRY: NOP ; No operation."));
  assert.throws(
    () => assertInstructionExplanation("    ENTRY: NOP", "sample.asm:2"),
    /sample\.asm:2 needs an inline instruction explanation/,
  );
  assert.doesNotThrow(() => assertInstructionExplanation("    ENTRY: NOP ; No operation."));
  assert.doesNotThrow(() => assertInstructionExplanation("DATA: DB 1"));
});

test("maintained Z80 source follows the readable layout convention", async () => {
  const names = (await fs.readdir("src/z80")).filter((name) => name.endsWith(".asm"));
  for (const name of names) {
    assert.match(name, /^[a-z0-9]{1,8}\.asm$/, `${name} is not an 8.3-compatible source name`);
    const lines = (await fs.readFile(`src/z80/${name}`, "utf8")).split("\n");
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index];
      assert.doesNotMatch(line, /\t/, `${name}:${index + 1} contains a tab`);
      if (line === "" || line.startsWith(";")) continue;
      assertInstructionExplanation(line, `${name}:${index + 1}`);
      if (/^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*:(?:\s|$)/.test(line)) continue;
      if (/^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*\s+EQU\s/.test(line)) continue;
      assert.match(line, /^ {4}\S/, `${name}:${index + 1} must indent non-label assembly by four spaces`);
      assert.doesNotMatch(line, /^ {5}/, `${name}:${index + 1} uses more than four leading spaces`);
    }

    for (let index = 0; index < lines.length; index += 1) {
      if (!lines[index].startsWith(";@ROUTINE")) continue;
      let cursor = index + 1;
      assert.match(lines[cursor] ?? "", /^; /, `${name}:${index + 1} needs a routine summary`);
      while ((lines[cursor] ?? "").startsWith("; ")) cursor += 1;
      assert.equal(lines[cursor], "", `${name}:${index + 1} needs one blank line before its entry label`);
      cursor += 1;
      assert.match(lines[cursor] ?? "", /^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*:$/, `${name}:${index + 1} needs a standalone entry label`);
      assert.notEqual(lines[cursor + 1], "", `${name}:${cursor + 1} separates its label from its body`);
    }
  }
});

test("native source census matches the checked content and root include parts", async () => {
  const ledger = JSON.parse(await fs.readFile("src/z80/atom-symbols.json", "utf8"));
  const parts = await Promise.all(NATIVE_CORE_MODULES.map((name) => fs.readFile(`src/z80/${name}`, "utf8")));
  const root = await fs.readFile("src/z80/atom.asm", "utf8");
  const bytes = parts.reduce((sum, text) => sum + Buffer.byteLength(text), 0);
  // The historical census calls all nonblank source records statements,
  // including labels and register-contract annotations.
  assert.equal(ledger.statistics.statements, parts.reduce((sum, text) => sum + text.split("\n").filter(line => line.trim()).length, 0));
  assert.equal(ledger.statistics.sourceBytes, bytes);
  assert.equal(ledger.statistics.checkedBytes, bytes + Buffer.byteLength(root));
});

test("the authoritative native symbol ledger is exact, scoped, and readable", async () => {
  const ledger = JSON.parse(await fs.readFile("src/z80/atom-symbols.json", "utf8"));
  assert.equal(ledger.format, "atom-native-symbol-ledger");
  assert.equal(ledger.version, 2);
  assert.equal(ledger.symbols.length, 1317);

  const globalNames = new Set();
  const privateNames = new Set();
  const privateShortScopes = new Map();
  for (const symbol of ledger.symbols) {
    assert.match(symbol.module, /^(?:AT|DR|EN|EX|HS|OU|PR|PT|ST|SY|TK)$/);
    assert.doesNotMatch(symbol.short, /^(?:G|\.L)[0-9]{7}$/);
    if (symbol.private) {
      assert.match(symbol.short, /^\.[A-Z0-9_]{1,8}$/);
      assert.equal(typeof symbol.scope, "string");
      const scoped = `${symbol.scope}\0${symbol.short.toUpperCase()}`;
      assert.equal(privateNames.has(scoped), false, `duplicate private short name ${symbol.short} in ${symbol.scope}`);
      privateNames.add(scoped);
      const scopes = privateShortScopes.get(symbol.short) ?? new Set();
      scopes.add(symbol.scope);
      privateShortScopes.set(symbol.short, scopes);
    } else {
      assert.match(symbol.short, /^[A-Z]{2}_[A-Z0-9_]{1,5}$/);
      const canonical = symbol.short.toUpperCase();
      assert.equal(globalNames.has(canonical), false, `duplicate global short name ${symbol.short}`);
      globalNames.add(canonical);
    }
  }
  assert.equal(globalNames.size, ledger.statistics.globalSymbols);
  assert.equal(privateNames.size, ledger.statistics.privateSymbols);
  assert.ok([...privateShortScopes.values()].some((scopes) => scopes.size > 1), "private short names should be reusable across global scopes");

  const byOriginal = new Map(ledger.symbols.filter((symbol) => !symbol.private).map((symbol) => [symbol.original, symbol.short]));
  for (const [original, short] of Object.entries(KEY_NAMES)) assert.equal(byOriginal.get(original), short);
});

test("reviewed private-name collisions remain distinct within one scope", async () => {
  const ledger = JSON.parse(await fs.readFile("src/z80/atom-symbols.json", "utf8"));
  const byOriginal = new Map(ledger.symbols.map((symbol) => [symbol.original, symbol]));
  for (const [scope, firstOriginal, firstShort, secondOriginal, secondShort] of [
    ["ATOMVALIDATEFORM", "_AtomValidateAlu16", ".VA16", "_AtomValidateAdd16", ".VA161"],
    ["ATOMTOKENSCANBASED", "_AtomTokenScanBinaryDigit", ".SBDIGIT", "_AtomTokenScanBasedDigit", ".SBDIGIT1"],
  ]) {
    const first = byOriginal.get(firstOriginal);
    const second = byOriginal.get(secondOriginal);
    assert.deepEqual([first.scope, first.short], [scope, firstShort]);
    assert.deepEqual([second.scope, second.short], [scope, secondShort]);
    assert.notEqual(first.short, second.short);
  }
});
