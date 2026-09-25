import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const document = (name) =>
  fs.readFileSync(new URL(`../docs/${name}`, import.meta.url), "utf8");

test("Atom owns its portable architecture boundary", () => {
  const architecture = document("codebase.md");

  assert.match(architecture, /Z80 assembler core and the operating code around it/);
  assert.match(architecture, /Host responsibilities[\s\S]*Z80 responsibilities/);
  assert.match(architecture, /same core on the processor/);
  assert.match(architecture, /Debug80/);
});

test("source preparation has no serialized ordering format", () => {
  const preparation = document("codebase.md");

  assert.match(preparation, /depth-first postorder/);
  assert.match(preparation, /Every file remains a distinct source part/);
  assert.doesNotMatch(preparation, /source plan|manifest/i);
});

test("public Atom reference docs avoid historical proof vocabulary", () => {
  const publicReference = document("language-reference.md");

  assert.doesNotMatch(publicReference, /\bAZM\b|oracle|spelling/i);
  assert.match(publicReference, /literal forms/);
  assert.match(publicReference, /complete Z80 instruction set/);
});

test("desktop integration uses the standalone package boundary", () => {
  const integration = document("programming-api.md");

  assert.match(integration, /import \{ assembleAtomProject, renderAtomArtifacts \} from "atom-z80"/);
  assert.match(integration, /Import these functions from `atom-z80`/);
  assert.doesNotMatch(integration, /packages\/atom|node_modules\/atom-z80/);
});
