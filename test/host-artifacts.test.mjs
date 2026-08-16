import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  assembleResolvedAtomProject,
  parseAtomNobj,
  publishAtomArtifacts,
  renderAtomArtifacts,
} from "../src/host/index.mjs";

const encoder = new TextEncoder();

function project(source, identity = "main.asm") {
  const bytes = encoder.encode(source);
  return {
    parts: [{
      ordinal: 0,
      bank: 0,
      logicalIdentity: identity,
      originalBytes: bytes,
      compilerBytes: bytes,
    }],
  };
}

async function render(source) {
  const input = project(source);
  const assembled = await assembleResolvedAtomProject(input, {
    target: { start: 0x4000, capacity: 0x100 },
  });
  return { input, assembled, artifacts: renderAtomArtifacts({ project: input, ...assembled }) };
}

test("artifact renderers preserve final patches, gaps, source lines, symbols, and checksums", async () => {
  const source = [
    "ORG 4000H",
    "START: JR LATER",
    "DS 2",
    "VALUE EQU 42",
    "LATER: LD A,VALUE",
    "",
  ].join("\n");
  const { artifacts } = await render(source);

  assert.deepEqual(Array.from(artifacts.bin), [0x18, 0x02, 0, 0, 0x3e, 0x2a]);
  assert.equal(artifacts.hex, ":06400000180200003E2A38\n:00000001FF\n");
  assert.match(artifacts.listing, /4000  18 02\s+main\.asm:2\s+START: JR LATER/);
  assert.match(artifacts.listing, /4002  <2 reserved>\s+main\.asm:3\s+DS 2/);
  assert.match(artifacts.listing, /VALUE\s+=002A main\.asm:4/);
  assert.deepEqual(artifacts.d8.fileList, ["main.asm"]);
  assert.deepEqual(artifacts.d8.symbols.map(({ name, kind }) => [name, kind]), [
    ["LATER", "label"],
    ["START", "label"],
    ["VALUE", "constant"],
  ]);
  assert.deepEqual(artifacts.d8.segments, [{ start: 0x4000, end: 0x4006 }]);

  const parsed = parseAtomNobj(artifacts.nobj);
  assert.equal(parsed.version, "0.2");
  assert.equal(parsed.imageRecords, 2);
  assert.equal(parsed.patchRecords, 1);
  assert.equal(parsed.entryAddress, 0x4000);
  const damaged = artifacts.nobj.slice();
  damaged[24] ^= 1;
  assert.throws(() => parseAtomNobj(damaged), /CRC/);
});

test("two native assemblies render byte-identical artifact sets", async () => {
  const source = "ORG 4000H\nLOOP: DJNZ LOOP\nDW LOOP\n";
  const left = (await render(source)).artifacts;
  const right = (await render(source)).artifacts;
  assert.deepEqual(left.nobj, right.nobj);
  assert.deepEqual(left.bin, right.bin);
  assert.equal(left.hex, right.hex);
  assert.equal(left.listing, right.listing);
  assert.equal(left.d8Text, right.d8Text);
});

test("artifact publication selects one complete immutable generation", async (t) => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "atom-artifacts-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const destination = path.join(directory, "program.atom");
  const first = (await render("ORG 4000H\nDB 1\n")).artifacts;
  const second = (await render("ORG 4000H\nDB 2\n")).artifacts;
  const published = await publishAtomArtifacts(destination, "program", first);
  assert.deepEqual(await fs.readFile(path.join(published.current, "program.bin")), Buffer.from([1]));
  const manifest = JSON.parse(await fs.readFile(path.join(published.current, "manifest.json"), "utf8"));
  assert.equal(manifest.format, "atom-artifact-set");
  assert.equal(manifest.generation, published.generation);

  const injected = {
    ...fs,
    async rename(source, target) {
      if (path.basename(source).startsWith(".current-")) {
        const error = new Error("injected pointer failure");
        error.code = "EIO";
        throw error;
      }
      return fs.rename(source, target);
    },
  };
  await assert.rejects(
    () => publishAtomArtifacts(destination, "program", second, { filesystem: injected }),
    (error) => error?.category === "publication" && error?.code === "generation-publish",
  );
  assert.deepEqual(await fs.readFile(path.join(published.current, "program.bin")), Buffer.from([1]));
  assert.deepEqual((await fs.readdir(destination)).filter((name) => name.startsWith(".current-")), []);

  const republished = await publishAtomArtifacts(destination, "program", second);
  assert.notEqual(republished.generation, published.generation);
  assert.deepEqual(await fs.readFile(path.join(republished.current, "program.bin")), Buffer.from([2]));

  await fs.writeFile(path.join(published.generationDirectory, "program.bin"), Buffer.from([9]));
  await assert.rejects(
    () => publishAtomArtifacts(destination, "program", first),
    (error) => error?.category === "publication" && error?.code === "generation-conflict",
  );
  assert.deepEqual(await fs.readFile(path.join(republished.current, "program.bin")), Buffer.from([2]));
});

test("an empty assembly still renders a valid empty flat Atom object", async () => {
  const { artifacts } = await render("ORG 4000H\n");
  assert.equal(artifacts.bin.length, 0);
  assert.equal(artifacts.hex, ":00000001FF\n");
  assert.equal(parseAtomNobj(artifacts.nobj).imageRecords, 0);
});

test("D8 retains distinct identities for reused private symbols after native eviction", async () => {
  const { artifacts } = await render([
    "ORG 4000H",
    "FIRST:",
    "_LOOP: NOP",
    "SECOND:",
    "_LOOP: NOP",
    "",
  ].join("\n"));
  const locals = artifacts.d8.symbols.filter(({ name }) => name === "_LOOP");
  assert.deepEqual(locals.map(({ address }) => address), [0x4000, 0x4001]);
  assert.equal(new Set(locals.map(({ identity }) => identity)).size, 2);
  assert.ok(locals.every(({ scope }) => scope === "local"));
});
