import assert from "node:assert/strict";
import test from "node:test";

let profileModule;
try {
  profileModule = await import("../src/host/atom/source-profile.mjs");
} catch {
  profileModule = {};
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function snapshot(source, logicalIdentity = "main.asm") {
  return Object.freeze({ logicalIdentity, originalBytes: encoder.encode(source) });
}

function profile() {
  assert.equal(typeof profileModule.createAtomSourceProfile, "function");
  return profileModule.createAtomSourceProfile();
}

function inspectEntry(source, definitions = {}) {
  return profile().inspectEntry(snapshot(source), { definitions });
}

function inspectDependency(source, state, logicalIdentity = "lib.asm") {
  return profile().inspectDependency(snapshot(source, logicalIdentity), state);
}

function assertPreprocessingError(action, code) {
  assert.throws(action, (error) => {
    assert.equal(error?.name, "SourcePreparationError");
    assert.equal(error?.category, "preprocessing");
    assert.equal(error?.code, code);
    assert.equal(typeof error?.location?.offset, "number");
    return true;
  });
}

test("directives and definitions are case-insensitive and includes retain source order", () => {
  const result = inspectEntry([
    "%DeFiNe Debug %1",
    "%IF debug",
    "%InClUdE \"lib/a.asm\"",
    "%eLsE",
    "%include \"lib/b.asm\"",
    "%EnDiF",
    "NOP",
    "",
  ].join("\n"));

  assert.deepEqual(result.dependencies.map(({ specifier }) => specifier), ["lib/a.asm"]);
  assert.equal(result.state.definitions.DEBUG, 1);
  assert.equal(Object.isFrozen(result.state), true);
  assert.equal(Object.isFrozen(result.state.definitions), true);
});

test("Intel suffix conditions select the same branches as prefix spellings", () => {
  for (const [prefix, suffix] of [
    ["$FFFF", "0FFFFH"],
    ["%01110111", "01110111B"],
  ]) {
    const inspectCondition = (value) => inspectEntry([
      `%if ${value}`,
      "%include \"selected.asm\"",
      "%else",
      "%include \"inactive.asm\"",
      "%endif",
      "NOP",
      "",
    ].join("\n"));
    const prefixResult = inspectCondition(prefix);
    const suffixResult = inspectCondition(suffix);
    assert.deepEqual(
      suffixResult.dependencies.map(({ specifier }) => specifier),
      prefixResult.dependencies.map(({ specifier }) => specifier),
      suffix,
    );
    assert.deepEqual(
      suffixResult.dependencies.map(({ specifier }) => specifier),
      ["selected.asm"],
      suffix,
    );
  }
});

test("project definitions precede source definitions and duplicates always fail", () => {
  const accepted = inspectEntry("%if PROJECT\nNOP\n%endif\n", { project: 1 });
  assert.equal(accepted.state.definitions.PROJECT, 1);
  assertPreprocessingError(
    () => inspectEntry("%define DEBUG %1\n", { debug: 1 }),
    "duplicate-definition",
  );
  assertPreprocessingError(
    () => inspectEntry("%define DEBUG %1\n%define debug %1\n"),
    "duplicate-definition",
  );
});

test("entry definitions close before include, conditional, or ordinary source", () => {
  for (const source of [
    "%include \"a.asm\"\n%define LATE %1\n",
    "%if %1\n%endif\n%define LATE %1\n",
    "NOP\n%define LATE %1\n",
  ]) assertPreprocessingError(() => inspectEntry(source), "define-outside-entry-header");
});

test("imported parts may test but cannot add frozen definitions", () => {
  const entry = inspectEntry("%define DEBUG %1\nNOP\n");
  const dependency = inspectDependency("%if debug\nNOP\n%endif\n", entry.state);
  assert.match(decoder.decode(dependency.compilerBytes), /NOP/);
  assertPreprocessingError(
    () => inspectDependency("%define LOCAL %1\nNOP\n", entry.state),
    "define-in-dependency",
  );
});

test("undefined conditions and extra condition tokens fail", () => {
  assertPreprocessingError(() => inspectEntry("%if MISSING\n%endif\n"), "undefined-definition");
  assertPreprocessingError(() => inspectEntry("%if %1 extra\n%endif\n"), "invalid-value");
});

test("unknown, unmatched, duplicate, and unterminated conditionals fail", () => {
  for (const [source, code] of [
    ["%wat VALUE\n", "unknown-directive"],
    ["%else\n", "unmatched-else"],
    ["%endif\n", "unmatched-endif"],
    ["%if %1\n%else\n%else\n%endif\n", "duplicate-else"],
    ["%if %1\n", "unterminated-conditional"],
  ]) assertPreprocessingError(() => inspectEntry(source), code);
});

test("directive names require a delimiter", () => {
  assertPreprocessingError(() => inspectEntry("%if1\n%endif\n"), "invalid-directive");
  assertPreprocessingError(() => inspectEntry("%include\"a.asm\"\n"), "invalid-directive");
});

test("an include-selecting conditional closes before ordinary Atom source", () => {
  assertPreprocessingError(
    () => inspectEntry("%if %1\n%include \"a.asm\"\nNOP\n%endif\n"),
    "header-conditional-crosses-body",
  );
  assertPreprocessingError(
    () => inspectEntry("%if %0\nNOP\n%endif\n%include \"late.asm\"\n"),
    "include-outside-header",
  );
});

test("include and define are illegal after ordinary source even when inactive", () => {
  assertPreprocessingError(
    () => inspectEntry("NOP\n%if %0\n%include \"hidden.asm\"\n%endif\n"),
    "include-outside-header",
  );
  assertPreprocessingError(
    () => inspectEntry("NOP\n%if %0\n%define HIDDEN %1\n%endif\n"),
    "define-outside-entry-header",
  );
});

test("directive recognition does not steal binary literals, remainder, or comments", () => {
  const source = "%1\nLD A,%1\nA % B\n; %if DEBUG\n";
  const result = inspectEntry(source);
  assert.equal(decoder.decode(result.compilerBytes), source);
  assert.deepEqual(result.dependencies, []);
});

test("entry inspection owns a frozen copy of project definitions", () => {
  const definitions = { DEBUG: 1 };
  const result = inspectEntry("NOP\n", definitions);
  definitions.DEBUG = 0;
  definitions.LATE = 1;
  assert.deepEqual(result.state.definitions, { DEBUG: 1 });
});
