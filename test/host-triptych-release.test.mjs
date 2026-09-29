import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
const publishedVersion = "0.3.3";

test("the published Atom 0.3.3 release has a verified Triptych launch image", async () => {
  const releaseDirectory = join(repositoryRoot, "site", "releases", publishedVersion);
  const descriptor = JSON.parse(
    await readFile(join(releaseDirectory, "system.json"), "utf8"),
  );
  const diskContents = JSON.parse(
    await readFile(join(releaseDirectory, "disk-contents.json"), "utf8"),
  );
  const image = await readFile(join(releaseDirectory, descriptor.image.asset));
  const resident = image.subarray(0, 16_384);
  const page = await readFile(join(repositoryRoot, "site", "index.html"), "utf8");
  assert.equal(descriptor.schema, "triptych-external-system-v1");
  assert.equal(descriptor.name, `Atom ${publishedVersion} for CP/M`);
  assert.equal(descriptor.profile, "triptych-cpu-v0.1-2m-n04");
  assert.equal(descriptor.workDisk, "copy-image");
  assert.deepEqual(descriptor.workDrives, ["B"]);
  assert.equal(image.length, 2_097_152);
  assert.equal(image.length, descriptor.image.bytes);
  assert.equal(hash(image), descriptor.image.sha256);
  assert.equal(
    hash(image),
    "49114217071c037001defa01c1b20ca2a517099cf2d117a99f9c0d197ddbfcb0",
  );
  assert.equal(
    hash(resident),
    "61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e",
  );
  assert.equal(diskContents.format, "atom-triptych-disk-contents-v1");
  assert.equal(diskContents.release, publishedVersion);
  assert.deepEqual(
    diskContents.files.map(({ name }) => name),
    ["ATOM.COM", "HELLO.ASM", "HELLO.COM", "EDIT.COM"],
  );
  assert.deepEqual(diskContents.files, [
    {
      name: "ATOM.COM",
      bytes: 17_641,
      sha256: "e2c4a71aca52659ce8ebac87fba9aedd40384ccb858d7d4642cba89137c163ca",
      source: "assets/atom-cpm22.com",
    },
    {
      name: "HELLO.ASM",
      bytes: 680,
      sha256: "88f28c6bf8a8d84a76de243ad8ddd17bb2cb812416055eebc358baaaffba8952",
      source: "examples/cpm/hello.asm",
    },
    {
      name: "HELLO.COM",
      bytes: 27,
      sha256: "55627adc5e7fc6700b1d639bea60af6b6c078c5983702a37f8b75ecf21c4cd58",
      assembledFrom: "HELLO.ASM",
      assembler: "Atom",
    },
    {
      name: "EDIT.COM",
      bytes: 5_513,
      sha256: "6be83f6edb9ee92387c7b3817f473fbbc389a58ab1a20d9a2a6101e695fb77c4",
      source: {
        repository: "https://github.com/jhlagado/edit.git",
        revision: "dbbda081b58077c98b509625176739bd9c5608ec",
        license: "GPL-3.0-or-later",
      },
    },
  ]);
  assert.match(page, new RegExp("releases/" + publishedVersion.replaceAll(".", "\\.") + "/ATOM\\.COM"));
  assert.match(page, new RegExp("releases/" + publishedVersion.replaceAll(".", "\\.") + "/atom\\.img"));
  assert.match(page, /jhlagado\.github\.io\/triptych\//);
  assert.match(page, /HELLO\.ASM/);
  assert.match(page, /EDIT\.COM/);
});
