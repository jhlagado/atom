import assert from "node:assert/strict";
import fs from "node:fs/promises";
import test from "node:test";

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

test("the authoritative native symbol ledger is exact, scoped, and readable", async () => {
  const ledger = JSON.parse(await fs.readFile("native/atom-symbols.json", "utf8"));
  assert.equal(ledger.format, "atom-native-symbol-ledger");
  assert.equal(ledger.version, 2);
  assert.equal(ledger.symbols.length, 1316);

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
  const ledger = JSON.parse(await fs.readFile("native/atom-symbols.json", "utf8"));
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
