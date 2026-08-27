import assert from "node:assert/strict";
import test from "node:test";

import {
  SourcePreparationError,
  resolveSourceProject,
} from "@jhlagado/z80-tool-services/source-preparation";

const encoder = new TextEncoder();

function source(name, identity = name) {
  return Object.freeze({
    physicalPath: `/project/${name}`,
    dependencyIdentity: identity,
    logicalIdentity: name,
    originalBytes: encoder.encode(`${name}\n`),
  });
}

function fixture(graph, aliases = {}) {
  const sources = new Map(Object.keys(graph).map((name) => [name, source(name)]));
  for (const [name, value] of Object.entries(aliases)) sources.set(name, value);
  const reader = Object.freeze({
    async resolveEntry(name) {
      const found = sources.get(name);
      if (found === undefined) {
        throw new SourcePreparationError("dependency", "missing-source", name);
      }
      return found;
    },
    async resolveDependency(_importer, name) {
      const found = sources.get(name);
      if (found === undefined) {
        throw new SourcePreparationError("dependency", "missing-source", name);
      }
      return found;
    },
  });
  const inspect = (input, entry) => ({
    ...(entry ? { state: Object.freeze({}) } : {}),
    compilerBytes: input.originalBytes,
    dependencies: (graph[input.logicalIdentity] ?? []).map((specifier, offset) => ({
      specifier,
      location: { logicalIdentity: input.logicalIdentity, offset, line: 1, column: offset + 1 },
    })),
    maskedRanges: [],
  });
  return {
    reader,
    profile: Object.freeze({
      inspectEntry(input) { return inspect(input, true); },
      inspectDependency(input) { return inspect(input, false); },
    }),
  };
}

async function resolve(graph, placement, aliases) {
  const { reader, profile } = fixture(graph, aliases);
  return resolveSourceProject({ reader, entry: "main.asm", profile, placement });
}

async function assertPlacementError(action, code) {
  await assert.rejects(action, (error) => {
    assert.equal(error?.name, "SourcePreparationError");
    assert.equal(error?.category, "project");
    assert.equal(error?.code, code);
    return true;
  });
}

test("path-keyed placement follows a part while unrelated order changes", async () => {
  const placement = { defaultBank: 0, banks: { "lib/hardware.asm": 255 } };
  const first = await resolve({
    "main.asm": ["lib/display.asm", "lib/input.asm"],
    "lib/display.asm": ["lib/hardware.asm"],
    "lib/input.asm": [],
    "lib/hardware.asm": [],
  }, placement);
  const second = await resolve({
    "main.asm": ["lib/input.asm", "lib/display.asm"],
    "lib/display.asm": ["lib/hardware.asm"],
    "lib/input.asm": [],
    "lib/hardware.asm": [],
  }, placement);

  assert.deepEqual(first.parts.map((part) => [part.logicalIdentity, part.ordinal, part.bank]), [
    ["lib/hardware.asm", 0, 255],
    ["lib/display.asm", 1, 0],
    ["lib/input.asm", 2, 0],
    ["main.asm", 3, 0],
  ]);
  assert.deepEqual(second.parts.map((part) => [part.logicalIdentity, part.ordinal, part.bank]), [
    ["lib/input.asm", 0, 0],
    ["lib/hardware.asm", 1, 255],
    ["lib/display.asm", 2, 0],
    ["main.asm", 3, 0],
  ]);
  assert.deepEqual(first.bankArray, [255, 0, 0, 0]);
  assert.deepEqual(second.bankArray, [0, 255, 0, 0]);
});

test("placement accepts explicit bank zero and the maximum bank", async () => {
  const result = await resolve(
    { "main.asm": ["a.asm"], "a.asm": [] },
    { banks: { "main.asm": 255, "a.asm": 0 } },
  );
  assert.deepEqual(result.bankArray, [0, 255]);
});

test("placement requires every part when there is no default", async () => {
  await assertPlacementError(
    () => resolve(
      { "main.asm": ["a.asm"], "a.asm": [] },
      { banks: { "main.asm": 1 } },
    ),
    "missing-placement",
  );
});

test("placement rejects out-of-range banks and caller bank limits", async () => {
  await assertPlacementError(
    () => resolve({ "main.asm": [] }, { defaultBank: 256, banks: {} }),
    "invalid-bank",
  );

  const { reader, profile } = fixture({ "main.asm": [] });
  await assertPlacementError(
    () => resolveSourceProject({
      reader,
      entry: "main.asm",
      profile,
      placement: { defaultBank: 2, banks: {} },
      limits: { maxBank: 1 },
    }),
    "bank-capacity",
  );
});

test("placement rejects conflicting aliases for one source", async () => {
  const canonical = source("lib/a.asm", "same-file");
  const alias = Object.freeze({ ...canonical, logicalIdentity: "lib/a.asm" });
  await assertPlacementError(
    () => resolve(
      { "main.asm": ["lib/a.asm"], "lib/a.asm": [] },
      { defaultBank: 0, banks: { "lib/a.asm": 1, "alias.asm": 2 } },
      { "lib/a.asm": canonical, "alias.asm": alias },
    ),
    "conflicting-placement",
  );
});

test("placement distinguishes unreachable and nonexistent mapping paths", async () => {
  await assertPlacementError(
    () => resolve(
      { "main.asm": [], "unused.asm": [] },
      { defaultBank: 0, banks: { "unused.asm": 1 } },
    ),
    "unreachable-placement",
  );
  await assertPlacementError(
    () => resolve(
      { "main.asm": [] },
      { defaultBank: 0, banks: { "missing.asm": 1 } },
    ),
    "nonexistent-placement",
  );
});
