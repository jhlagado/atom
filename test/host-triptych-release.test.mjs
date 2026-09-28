import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");

test("the current Atom release has a verified Triptych launch image", async () => {
  const packageJson = JSON.parse(
    await readFile(join(repositoryRoot, "package.json"), "utf8"),
  );
  const version = packageJson.version;
  const releaseDirectory = join(repositoryRoot, "site", "releases", version);
  const descriptor = JSON.parse(
    await readFile(join(releaseDirectory, "system.json"), "utf8"),
  );
  const diskContents = JSON.parse(
    await readFile(join(releaseDirectory, "disk-contents.json"), "utf8"),
  );
  const image = await readFile(join(releaseDirectory, descriptor.image.asset));
  const resident = image.subarray(0, 16_384);
  const page = await readFile(join(repositoryRoot, "site", "index.html"), "utf8");
  const atomCom = await readFile(join(repositoryRoot, "assets", "atom-cpm22.com"));
  const helloAsm = await readFile(join(repositoryRoot, "examples/cpm/hello.asm"));
  const helloCom = Buffer.from([
    0x11, 0x09, 0x01, 0x0e, 0x09, 0xcd, 0x05, 0x00, 0xc9,
    ...Buffer.from("HELLO FROM ATOM\r\n$", "ascii"),
  ]);

  assert.equal(descriptor.schema, "triptych-external-system-v1");
  assert.equal(descriptor.name, `Atom ${version} for CP/M`);
  assert.equal(descriptor.profile, "triptych-cpu-v0.1-2m-n04");
  assert.equal(descriptor.workDisk, "copy-image");
  assert.deepEqual(descriptor.workDrives, ["B"]);
  assert.equal(image.length, 2_097_152);
  assert.equal(image.length, descriptor.image.bytes);
  assert.equal(hash(image), descriptor.image.sha256);
  assert.equal(
    hash(resident),
    "61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e",
  );
  assert.equal(diskContents.format, "atom-triptych-disk-contents-v1");
  assert.equal(diskContents.release, version);
  assert.deepEqual(
    diskContents.files.map(({ name }) => name),
    ["ATOM.COM", "HELLO.ASM", "HELLO.COM", "EDIT.COM"],
  );
  assert.deepEqual(diskContents.files[0], {
    name: "ATOM.COM",
    bytes: atomCom.length,
    sha256: hash(atomCom),
    source: "assets/atom-cpm22.com",
  });
  assert.deepEqual(diskContents.files[1], {
    name: "HELLO.ASM",
    bytes: helloAsm.length,
    sha256: hash(helloAsm),
    source: "examples/cpm/hello.asm",
  });
  assert.deepEqual(diskContents.files[2], {
    name: "HELLO.COM",
    bytes: helloCom.length,
    sha256: hash(helloCom),
    assembledFrom: "HELLO.ASM",
    assembler: "Atom",
  });
  assert.deepEqual(diskContents.files[3], {
    name: "EDIT.COM",
    bytes: 5_513,
    sha256: "6be83f6edb9ee92387c7b3817f473fbbc389a58ab1a20d9a2a6101e695fb77c4",
    source: {
      repository: "https://github.com/jhlagado/edit.git",
      revision: "dbbda081b58077c98b509625176739bd9c5608ec",
      license: "GPL-3.0-or-later",
    },
  });
  assert.match(page, new RegExp("releases/" + version.replaceAll(".", "\\.") + "/ATOM\\.COM"));
  assert.match(page, new RegExp("releases/" + version.replaceAll(".", "\\.") + "/atom\\.img"));
  assert.match(page, /jhlagado\.github\.io\/triptych\//);
  assert.match(page, /HELLO\.ASM/);
  assert.match(page, /EDIT\.COM/);
});
