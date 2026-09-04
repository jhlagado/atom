import assert from "node:assert/strict";
import test from "node:test";

import { runNamedObjectConformance } from "@jhlagado/z80-tool-services";

import {
  assembleResolvedAtomProject,
  createNamedObjectAtomAdapter,
  MemoryNamedObjectServices,
  NAMED_OBJECT_OPERATION,
  NAMED_OBJECT_STATUS,
  NamedObjectClient,
} from "../src/host/index.mjs";

const encoder = new TextEncoder();

test("Atom's compatibility surface passes the shared named-object vectors", () => {
  assert.equal(Object.isFrozen(NAMED_OBJECT_OPERATION), true);
  assert.equal(Object.isFrozen(NAMED_OBJECT_STATUS), true);
  assert.deepEqual(runNamedObjectConformance({
    create: (objects, options) => new MemoryNamedObjectServices(objects, options),
  }), { vectors: 4, assertions: 29 });
});

function project(source) {
  const bytes = encoder.encode(source);
  return {
    parts: [{
      ordinal: 0,
      bank: 0,
      logicalIdentity: "source/0.asm",
      originalBytes: bytes,
      compilerBytes: bytes,
      binaryIncludes: [],
    }],
  };
}

test("named-object ABI keeps binary bytes, independent readers, and tentative generations", () => {
  const provider = new MemoryNamedObjectServices(new Map([
    ["binary", Uint8Array.from([0x00, 0x1a, 0x7f, 0x80, 0xff])],
    ["output", encoder.encode("old")],
  ]));
  const client = new NamedObjectClient(provider);
  const first = client.openRead("binary");
  const second = client.openRead("binary");
  assert.equal(first.status, 0);
  assert.equal(second.status, 0);
  assert.deepEqual([...client.read(first.handle, 3).bytes], [0x00, 0x1a, 0x7f]);
  assert.deepEqual([...client.read(second.handle, 1).bytes], [0x00]);

  const writer = client.beginWrite("output");
  assert.equal(writer.status, 0);
  assert.equal(client.write(writer.handle, Uint8Array.from([0x80, 0xff])).status, 0);
  assert.deepEqual([...provider.bytes("output")], [...encoder.encode("old")]);
  assert.equal(client.abort(writer.handle).status, 0);
  assert.deepEqual([...provider.bytes("output")], [...encoder.encode("old")]);

  const replacement = client.beginWrite("output");
  assert.equal(client.write(replacement.handle, Uint8Array.from([0x00, 0x1a, 0xff])).status, 0);
  assert.equal(client.commit(replacement.handle).status, 0);
  assert.deepEqual([...provider.bytes("output")], [0x00, 0x1a, 0xff]);
  assert.equal(client.commit(replacement.handle).status, NAMED_OBJECT_STATUS.invalid);
});

test("a failed named-object read leaves its cursor unchanged", () => {
  let failRead = true;
  const provider = new MemoryNamedObjectServices(new Map([["source", encoder.encode("AB")]]), {
    fail({ operation }) {
      if (operation === NAMED_OBJECT_OPERATION.read && failRead) {
        failRead = false;
        return NAMED_OBJECT_STATUS.storage;
      }
      return 0;
    },
  });
  const client = new NamedObjectClient(provider);
  const opened = client.openRead("source");
  assert.equal(client.read(opened.handle, 1).status, NAMED_OBJECT_STATUS.storage);
  const retried = client.read(opened.handle, 1);
  assert.equal(retried.status, 0);
  assert.deepEqual([...retried.bytes], [0x41]);
});

test("Atom assembles through named objects and publishes one patched flat image", async () => {
  const source = [
    "ORG 4000H",
    "JR Later",
    "DS 2",
    "Later:",
    "DB 0,1AH,7FH,80H,0FFH",
    "",
  ].join("\n");
  const provider = new MemoryNamedObjectServices(new Map([
    ["source/0.asm", encoder.encode(source)],
    ["build/program.bin", encoder.encode("old")],
  ]));
  const toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  const result = await assembleResolvedAtomProject(project(source), {
    target: { start: 0x4000, capacity: 0x100 },
    toolProfile,
  });

  assert.equal(result.core.residentExtentBytes, 12_400);
  assert.deepEqual([...provider.bytes("build/program.bin")], [
    0x18, 0x02, 0x00, 0x00, 0x00, 0x1a, 0x7f, 0x80, 0xff,
  ]);
  assert.deepEqual(result.execution.serviceTrace.map(({ method }) => method), [
    "begin", "image", "image", "patch-byte", "image", "image", "image", "image", "image", "commit",
  ]);
  assert.equal(provider.openHandleCount, 0);
});

test("Atom abort preserves the prior named object and a later build succeeds", async () => {
  const bad = "ORG 4000H\nLD BC,A\n";
  const good = "ORG 4000H\nDB 80H,0FFH\n";
  const provider = new MemoryNamedObjectServices(new Map([
    ["source/0.asm", encoder.encode(bad)],
    ["build/program.bin", Uint8Array.from([1, 2, 3])],
  ]));
  let toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  await assert.rejects(
    () => assembleResolvedAtomProject(project(bad), {
      target: { start: 0x4000, capacity: 0x100 },
      toolProfile,
    }),
    (error) => error?.category === "source",
  );
  assert.deepEqual([...provider.bytes("build/program.bin")], [1, 2, 3]);
  assert.equal(provider.openHandleCount, 0);

  provider.seed("source/0.asm", encoder.encode(good));
  toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  await assembleResolvedAtomProject(project(good), {
    target: { start: 0x4000, capacity: 0x100 },
    toolProfile,
  });
  assert.deepEqual([...provider.bytes("build/program.bin")], [0x80, 0xff]);
});

test("a poisoned output generation aborts without replacing the committed object", async () => {
  const source = "ORG 4000H\nDB 1,2,3\n";
  let writes = 0;
  const provider = new MemoryNamedObjectServices(new Map([
    ["source/0.asm", encoder.encode(source)],
    ["build/program.bin", Uint8Array.from([9])],
  ]), {
    fail({ operation }) {
      if (operation === NAMED_OBJECT_OPERATION.write && ++writes === 2) return NAMED_OBJECT_STATUS.storage;
      return 0;
    },
  });
  const toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  await assert.rejects(
    () => assembleResolvedAtomProject(project(source), {
      target: { start: 0x4000, capacity: 0x100 },
      toolProfile,
    }),
    (error) => error?.category === "output",
  );
  assert.deepEqual([...provider.bytes("build/program.bin")], [9]);
  assert.equal(provider.openHandleCount, 0);
});

test("Atom retains an uninitialized high-water extent after a backward ORG", async () => {
  const source = "ORG 4000H\nDS 4\nORG 4000H\n";
  const provider = new MemoryNamedObjectServices(new Map([
    ["source/0.asm", encoder.encode(source)],
  ]));
  const toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  const result = await assembleResolvedAtomProject(project(source), {
    target: { start: 0x4000, capacity: 0x100 },
    toolProfile,
  });
  assert.equal(result.generation.finalCursor, 0x4000);
  assert.equal(result.generation.highWater, 0x4004);
  assert.deepEqual([...provider.bytes("build/program.bin")], [0, 0, 0, 0]);
});

test("a failed named-object commit preserves the preceding Atom image", async () => {
  const source = "ORG 4000H\nDB 1\n";
  const provider = new MemoryNamedObjectServices(new Map([
    ["source/0.asm", encoder.encode(source)],
    ["build/program.bin", Uint8Array.from([9])],
  ]), {
    fail({ operation }) {
      return operation === NAMED_OBJECT_OPERATION.commit ? NAMED_OBJECT_STATUS.storage : 0;
    },
  });
  const toolProfile = createNamedObjectAtomAdapter({
    provider,
    sourceNames: ["source/0.asm"],
    outputName: "build/program.bin",
  });
  await assert.rejects(
    () => assembleResolvedAtomProject(project(source), {
      target: { start: 0x4000, capacity: 0x100 },
      toolProfile,
    }),
    (error) => error?.category === "output",
  );
  assert.deepEqual([...provider.bytes("build/program.bin")], [9]);
  assert.equal(provider.openHandleCount, 0);
});
