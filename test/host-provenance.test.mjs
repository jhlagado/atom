import assert from "node:assert/strict";
import test from "node:test";

import { resolveSourceProject } from "../src/host/project-preparation/index.mjs";

const encoder = new TextEncoder();

function location(logicalIdentity, offset) {
  return { logicalIdentity, offset, line: offset + 1, column: 1 };
}

test("resolved parts expose complete immutable provenance and identity offsets", async () => {
  const sources = new Map([
    ["main.asm", Object.freeze({
      physicalPath: "/project/main.asm",
      dependencyIdentity: "/project/main.asm",
      logicalIdentity: "main.asm",
      originalBytes: encoder.encode("% A\n"),
    })],
    ["lib/a.asm", Object.freeze({
      physicalPath: "/project/lib/a.asm",
      dependencyIdentity: "/project/lib/a.asm",
      logicalIdentity: "lib/a.asm",
      originalBytes: encoder.encode("% B\n"),
    })],
  ]);
  const dependencyLocation = location("main.asm", 0);
  const reader = {
    async resolveEntry(name) { return sources.get(name); },
    async resolveDependency(_importer, name) { return sources.get(name); },
  };
  const profile = {
    inspectEntry(input) {
      return {
        state: undefined,
        compilerBytes: Uint8Array.from(
          input.originalBytes,
          (byte, offset) => (offset < 2 ? 0x20 : byte),
        ),
        dependencies: [{ specifier: "lib/a.asm", location: dependencyLocation }],
        maskedRanges: [{ start: 0, end: 2 }],
      };
    },
    inspectDependency(input) {
      return {
        compilerBytes: Uint8Array.from(
          input.originalBytes,
          (byte, offset) => (offset < 2 ? 0x20 : byte),
        ),
        dependencies: [],
        maskedRanges: [{ start: 0, end: 2 }],
      };
    },
  };

  const result = await resolveSourceProject({
    reader,
    entry: "main.asm",
    profile,
    placement: { defaultBank: 3, banks: { "lib/a.asm": 7 } },
  });
  const dependency = result.parts[0];
  const entry = result.parts[1];

  assert.deepEqual(dependency.provenance, {
    logicalIdentity: "lib/a.asm",
    diagnosticName: "lib/a.asm",
    physicalPath: "/project/lib/a.asm",
    ordinal: 0,
    bank: 7,
    originalByteLength: 4,
    maskedRanges: [{ start: 0, end: 2 }],
    dependencyLocations: [],
    includeStack: [{
      from: "main.asm",
      to: "lib/a.asm",
      location: dependencyLocation,
    }],
  });
  assert.deepEqual(entry.provenance, {
    logicalIdentity: "main.asm",
    diagnosticName: "main.asm",
    physicalPath: "/project/main.asm",
    ordinal: 1,
    bank: 3,
    originalByteLength: 4,
    maskedRanges: [{ start: 0, end: 2 }],
    dependencyLocations: [dependencyLocation],
    includeStack: [],
  });

  for (const part of result.parts) {
    assert.equal(part.compilerBytes.length, part.originalBytes.length);
    assert.equal(Object.isFrozen(part), true);
    assert.equal(Object.isFrozen(part.provenance), true);
    assert.equal(Object.isFrozen(part.provenance.maskedRanges), true);
    assert.equal(Object.isFrozen(part.provenance.dependencyLocations), true);
    assert.equal(Object.isFrozen(part.provenance.includeStack), true);
  }
  assert.equal(dependency.compilerBytes[0], 0x20);
  assert.equal(dependency.originalBytes[0], "%".charCodeAt(0));
  assert.equal(dependency.compilerBytes[2], "B".charCodeAt(0));
  assert.equal(dependency.originalBytes[2], "B".charCodeAt(0));
  assert.equal(Object.isFrozen(result.parts), true);
  assert.equal(Object.isFrozen(result.bankArray), true);

  dependencyLocation.offset = 99;
  assert.equal(dependency.provenance.includeStack[0].location.offset, 0);
  assert.equal(entry.provenance.dependencyLocations[0].offset, 0);
});

test("resolver rejects a profile that changes source length", async () => {
  const originalBytes = encoder.encode("NOP\n");
  const snapshot = Object.freeze({
    physicalPath: "/project/main.asm",
    dependencyIdentity: "/project/main.asm",
    logicalIdentity: "main.asm",
    originalBytes,
  });
  await assert.rejects(
    () => resolveSourceProject({
      reader: { async resolveEntry() { return snapshot; } },
      entry: "main.asm",
      profile: {
        inspectEntry() {
          return {
            state: undefined,
            compilerBytes: encoder.encode("NOP"),
            dependencies: [],
            maskedRanges: [],
          };
        },
        inspectDependency() { throw new Error("unreachable"); },
      },
    }),
    (error) => error?.category === "dependency" && error?.code === "source-length-changed",
  );
});
