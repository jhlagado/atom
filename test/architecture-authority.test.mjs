import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const document = (name) =>
  fs.readFileSync(new URL(`../docs/${name}`, import.meta.url), "utf8");

test("Atom owns its portable architecture boundary", () => {
  const architecture = document("architecture.md");

  assert.match(architecture, /This document defines Atom's ownership/);
  assert.match(architecture, /native Z80 assembler inside a host-managed build/);
  assert.match(architecture, /AtomSourceReadByte/);
  assert.match(architecture, /Debug80 Runtime/);
  assert.match(architecture, /Filesystem access,[\s\S]*Streaming tokenization/);
});

test("source preparation has no serialized ordering format", () => {
  const preparation = fs.readFileSync(
    new URL("../docs/codebase/02-host-source-preparation.md", import.meta.url),
    "utf8",
  );

  assert.match(preparation, /preparation does not write an\s+intermediate file/);
  assert.match(preparation, /at most 255\s+parts/);
  assert.match(preparation, /deterministic depth-first postorder/);
});

test("public Atom reference docs avoid historical proof vocabulary", () => {
  const publicReference = document("language-reference.md");

  assert.doesNotMatch(publicReference, /\bAZM\b|oracle|spelling/i);
  assert.match(publicReference, /literal forms/);
  assert.match(publicReference, /complete Z80 instruction set/);
});

test("desktop integration uses the standalone package boundary", () => {
  const integration = fs.readFileSync(
    new URL("../docs/codebase/04-host-execution-artifacts-and-interfaces.md", import.meta.url),
    "utf8",
  );

  assert.match(integration, /`assembleAtomProject\(\)` is the complete filesystem-to-generation entry/);
  assert.match(integration, /A tool such as Debug80 can import `atom-z80`/);
  assert.doesNotMatch(integration, /packages\/atom|node_modules\/atom-z80/);
});
