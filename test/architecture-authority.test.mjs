import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const document = (name) =>
  fs.readFileSync(new URL(`../docs/${name}`, import.meta.url), "utf8");

test("Atom owns its portable architecture boundary", () => {
  const architecture = document("architecture.md");
  const services = document("tool-services.md");

  assert.match(architecture, /This document defines Atom's ownership/);
  assert.match(architecture, /native Z80 assembler inside a host-managed build/);
  assert.match(architecture, /AtomSourceReadByte/);
  assert.match(architecture, /Debug80 Runtime/);
  assert.match(services, /Assembled programs receive none of Atom's/);
  assert.match(services, /Node path handling,[\s\S]*remain outside the Z80 core/);
});

test("source preparation has no serialized ordering format", () => {
  const preparation = document("host-source-preparation.md");

  assert.match(preparation, /no\s+intermediate file is written or read/);
  assert.match(preparation, /accepts 1 through 255 parts/);
  assert.match(preparation, /deterministic depth-first postorder/);
});

test("public Atom reference docs avoid historical proof vocabulary", () => {
  const publicReference = document("language-reference.md");

  assert.doesNotMatch(publicReference, /\bAZM\b|oracle|spelling/i);
  assert.match(publicReference, /literal forms/);
  assert.match(publicReference, /proof suite/);
});

test("desktop integration uses the standalone package boundary", () => {
  const integration = document("desktop-host-integration.md");

  assert.match(integration, /`assembleAtomProject` is the complete Node-to-Z80 assembly entry/);
  assert.match(integration, /Debug80 uses the same package API/);
  assert.doesNotMatch(integration, /packages\/atom|node_modules\/atom-z80/);
});
