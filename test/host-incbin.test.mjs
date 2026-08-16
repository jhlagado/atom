import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  assembleAtomProject,
  assembleResolvedAtomProject,
  materializeAtomGeneration,
  renderAtomArtifacts,
  resolveAtomProject,
} from "../src/host/index.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

async function projectRoot(t, files) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-incbin-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  for (const [name, contents] of Object.entries(files)) {
    const destination = path.join(root, name);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, contents);
  }
  return root;
}

test("INCBIN snapshots one confined binary and preserves native addresses", async (t) => {
  const source = [
    "ORG 4000H",
    "JR AFTER",
    'DATA: INCBIN "assets/payload.bin"',
    "AFTER:",
    "LD HL,DATA",
    "",
  ].join("\n");
  const root = await projectRoot(t, {
    "main.asm": source,
    "assets/payload.bin": Uint8Array.from([0xde, 0xad, 0xbe]),
  });
  const project = await resolveAtomProject({ root, entry: "main.asm" });
  const part = project.parts[0];
  assert.equal(decoder.decode(part.originalBytes), source);
  assert.equal(part.compilerBytes.length, part.originalBytes.length);
  assert.match(decoder.decode(part.compilerBytes), /^DATA: DS 3,0\s*$/m);
  assert.deepEqual(part.binaryIncludes.map(({ logicalIdentity, line, bytes }) => ({
    logicalIdentity,
    line,
    bytes: [...bytes],
  })), [{ logicalIdentity: "assets/payload.bin", line: 3, bytes: [0xde, 0xad, 0xbe] }]);

  await fs.writeFile(path.join(root, "assets/payload.bin"), Uint8Array.from([1, 2, 3]));
  const assembled = await assembleResolvedAtomProject(project, {
    target: { start: 0x4000, capacity: 0x100 },
  });
  assert.deepEqual([...materializeAtomGeneration(assembled.generation).bytes], [
    0x18, 0x03, 0xde, 0xad, 0xbe, 0x21, 0x02, 0x40,
  ]);
  assert.equal(assembled.generation.finalCursor, 0x4008);
});

test("INCBIN bytes retain their source line in listings and D8", async (t) => {
  const root = await projectRoot(t, {
    "main.asm": 'ORG 4000H\nPAYLOAD: INCBIN "payload.bin"\nNOP\n',
    "payload.bin": Uint8Array.from([0x00, 0xff, 0x42]),
  });
  const result = await assembleAtomProject({
    root,
    entry: "main.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
  const artifacts = renderAtomArtifacts(result);
  assert.deepEqual([...artifacts.bin], [0x00, 0xff, 0x42, 0x00]);
  assert.match(artifacts.listing, /4000  00 FF 42\s+main\.asm:2\s+PAYLOAD: INCBIN "payload\.bin"/);
  assert.deepEqual(artifacts.d8.files["main.asm"].segments, [
    {
      start: 0x4000,
      end: 0x4003,
      lstLine: 2,
      line: 2,
      column: 1,
      kind: "data",
      confidence: "high",
    },
    {
      start: 0x4003,
      end: 0x4004,
      lstLine: 3,
      line: 3,
      column: 1,
      kind: "code",
      confidence: "high",
    },
  ]);
});

test("INCBIN rejects malformed, escaping, missing, and oversized inputs", async (t) => {
  const cases = [
    ['INCBIN payload.bin\n', {}, "preprocessing", "invalid-incbin"],
    ['INCBIN "café.bin"\n', {}, "preprocessing", "invalid-incbin"],
    ['INCBIN "../payload.bin"\n', {}, "dependency", "root-escape"],
    ['INCBIN "missing.bin"\n', {}, "dependency", "missing-source"],
    ['INCBIN "large.bin"\n', { "large.bin": new Uint8Array(0x10000) }, "preprocessing", "incbin-size"],
  ];
  for (const [source, files, category, code] of cases) {
    const root = await projectRoot(t, { "main.asm": source, ...files });
    await assert.rejects(
      () => resolveAtomProject({ root, entry: "main.asm" }),
      (error) => error?.category === category && error?.code === code && error?.location?.line === 1,
      source,
    );
  }

  const inactive = await projectRoot(t, {
    "main.asm": '%IF 0\nINCBIN "missing.bin"\n%ENDIF\nNOP\n',
  });
  const result = await assembleAtomProject({
    root: inactive,
    entry: "main.asm",
    target: { start: 0x4000, capacity: 1 },
  });
  assert.deepEqual([...materializeAtomGeneration(result.generation).bytes], [0x00]);

  const boundary = await projectRoot(t, {
    "main.asm": 'INCBIN "empty.bin"\nINCBIN "maximum.bin"\n',
    "empty.bin": new Uint8Array(0),
    "maximum.bin": new Uint8Array(0xffff),
  });
  const project = await resolveAtomProject({ root: boundary, entry: "main.asm" });
  assert.deepEqual(project.parts[0].binaryIncludes.map(({ bytes }) => bytes.length), [0, 0xffff]);
});

test("the native bridge fails closed when supplied INCBIN metadata disagrees with DS", async () => {
  for (const [source, bytes] of [
    ["DS 1,0\n", [1, 2]],
    ["DS 2,0\n", [1]],
  ]) {
    const sourceBytes = encoder.encode(source);
    await assert.rejects(
      () => assembleResolvedAtomProject({
        parts: [{
          ordinal: 0,
          bank: 0,
          logicalIdentity: "main.asm",
          originalBytes: sourceBytes,
          compilerBytes: sourceBytes,
          binaryIncludes: [{ offset: 0, line: 1, bytes: Uint8Array.from(bytes) }],
        }],
      }, { target: { start: 0x4000, capacity: 4 } }),
      (error) => error?.category === "output" &&
        error?.code === "sink" &&
        error?.diagnostic?.line === 1,
      source,
    );
  }
});
