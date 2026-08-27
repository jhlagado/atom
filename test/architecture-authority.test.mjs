import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const specification = (name) =>
  fs.readFileSync(
    new URL(`../../../docs/specifications/${name}`, import.meta.url),
    "utf8",
  );

const repositoryFile = (path) =>
  fs.readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");

test("Atom architecture records the implemented TEC-native profile", () => {
  const architecture = specification("atom-platform-architecture.md");
  const boundary = specification("tool-service-boundary.md");

  assert.match(
    architecture,
    /TEC-native profiles are\s+implemented and proved under emulation/,
  );
  assert.match(
    architecture,
    /current CP\/M and TEC profiles implement leading\s+`%INCLUDE`/,
  );
  assert.match(
    boundary,
    /ordinary TEC-FS catalogue files through Atom's Z80-native\s+read provider/,
  );
  assert.match(boundary, /Atom\s+\| TEC native\s+\|/);
  assert.doesNotMatch(boundary, /Atom launcher is not installed/);
});

test("source preparation has no serialized ordering format", () => {
  const preparation = specification("z80-source-preparation.md");

  assert.match(preparation, /writes no intermediate ordering file/);
  assert.match(preparation, /canonical one-byte catalogue identities/);
  assert.match(preparation, /up to 255 source parts/);
  assert.doesNotMatch(
    preparation,
    /\bSP1\b|source plan|flat ordered manifest/i,
  );
});

test("public Atom reference docs avoid historical proof vocabulary", () => {
  const publicReference = repositoryFile("packages/atom/docs/language-reference.md");

  assert.doesNotMatch(publicReference, /\bAZM\b|oracle|spelling/i);
  assert.match(publicReference, /literal forms/);
  assert.match(publicReference, /proof suite/);
});

test("Debug80 packaging docs describe the bundled Atom runtime", () => {
  const strategy = repositoryFile("apps/debug80-vscode/docs/regression-test-strategy.md");

  assert.match(strategy, /bundled Atom assembler runtime/);
  assert.match(strategy, /assets\/native-core\.json/);
  assert.doesNotMatch(strategy, /node_modules\/atom-z80|node_modules\/@jhlagado\/azm/);
});

test("filesystem path resolution remains provider-local", () => {
  const abi = specification("z80-tool-services-abi-v1.md");
  const boundary = specification("tool-service-boundary.md");

  assert.match(abi, /deliberately\s+has no `resolvePath` operation/);
  assert.match(
    boundary,
    /Path resolution is not a shared named-object operation/,
  );
});

test("migration status does not overclaim native conditional preparation", () => {
  const migration = specification("atom-first-class-migration.md");

  assert.match(
    migration,
    /current CP\/M and TEC native profiles\s+recognize leading `%INCLUDE` only/,
  );
  assert.match(migration, /Nucleus is undergoing an architectural rewrite/);
  assert.doesNotMatch(
    migration,
    /TEC include resolver, launcher, final memory map[^.]*remain/,
  );
});
