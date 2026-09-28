#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const systemAsset =
  "library-retained-61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e.bin";
const systemSha256 =
  "61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e";
const systemProfile = "triptych-cpu-v0.1-2m-n04";
const triptychUrl = "https://jhlagado.github.io/triptych/";

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 === process.argv.length) return undefined;
  return process.argv[index + 1];
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function run(command, args, cwd) {
  const output = execFileSync(command, args, {
    cwd,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
  process.stdout.write(output);
  return output;
}

async function writeImmutable(path, bytes) {
  try {
    const existing = await readFile(path);
    assert.deepEqual(existing, bytes, `${path} already exists with different content`);
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    await writeFile(path, bytes, { flag: "wx" });
  }
}

const packageJson = JSON.parse(
  await readFile(join(repositoryRoot, "package.json"), "utf8"),
);
const census = JSON.parse(
  await readFile(join(repositoryRoot, "proofs/cpm22-census.json"), "utf8"),
);
const version = packageJson.version;
const triptychRoot = resolve(
  option("--triptych-root") ??
    process.env.TRIPTYCH_ROOT ??
    resolve(repositoryRoot, "../triptych"),
);
const releaseDirectory = join(repositoryRoot, "site", "releases", version);
const temporaryDirectory = await mkdtemp(join(tmpdir(), "atom-triptych-release-"));

try {
  const sourceCom = await readFile(join(repositoryRoot, "assets/atom-cpm22.com"));
  assert.equal(sourceCom.length, census.residentBytes);
  assert.equal(sha256(sourceCom), census.sha256, "ATOM.COM differs from its checked census");

  const exampleSourceName = "examples/cpm/hello.asm";
  const exampleSourcePath = join(repositoryRoot, exampleSourceName);
  const exampleSource = await readFile(exampleSourcePath);
  const exampleComPath = join(temporaryDirectory, "HELLO.COM");
  run(
    process.execPath,
    [join(repositoryRoot, "bin/atom.mjs"), exampleSourceName, exampleComPath],
    repositoryRoot,
  );
  const exampleCom = await readFile(exampleComPath);

  const editRoot = join(triptychRoot, "third_party/edit");
  const editComPath = join(editRoot, "EDIT.COM");
  const editCom = await readFile(editComPath);
  const editManifestBytes = await readFile(join(editRoot, "manifest.json"));
  const editManifest = JSON.parse(editManifestBytes.toString("utf8"));
  const editOrigin = JSON.parse(await readFile(join(editRoot, "PROVENANCE.json"), "utf8"));
  const editRelease = JSON.parse(
    await readFile(join(editRoot, "release.provenance.json"), "utf8"),
  );
  const editSha256 = "6be83f6edb9ee92387c7b3817f473fbbc389a58ab1a20d9a2a6101e695fb77c4";
  const editRevision = "dbbda081b58077c98b509625176739bd9c5608ec";
  assert.equal(editManifest.format, "edit-build-manifest-v1");
  assert.equal(editManifest.artifact, "EDIT.COM");
  assert.equal(editManifest.version, "0.2.0");
  assert.equal(editManifest.bytes, 5_513);
  assert.equal(editManifest.sha256, editSha256);
  assert.equal(editOrigin.repository, "https://github.com/jhlagado/edit.git");
  assert.equal(editOrigin.revision, editRevision);
  assert.equal(editOrigin.license, "GPL-3.0-or-later");
  assert.equal(editOrigin.bytes, editCom.length);
  assert.equal(editOrigin.sha256, editSha256);
  assert.equal(editRelease.schema, "triptych-release-provenance-v1");
  assert.equal(editRelease.repository, editOrigin.repository);
  assert.equal(editRelease.revision, editRevision);
  assert.equal(editRelease.bytes, editCom.length);
  assert.equal(editRelease.sha256, editSha256);
  assert.equal(editRelease.manifestSha256, sha256(editManifestBytes));
  assert.equal(editCom.length, 5_513);
  assert.equal(sha256(editCom), editSha256, "EDIT.COM differs from its verified release");

  const systemPath = join(triptychRoot, "distribution/disk-library", systemAsset);
  const system = await readFile(systemPath);
  assert.equal(system.length, 16_384, "Triptych N04 resident image must be 16 KiB");
  assert.equal(sha256(system), systemSha256, "Triptych resident image differs from its pin");

  const imagePath = join(temporaryDirectory, "atom.img");
  run(
    "cargo",
    [
      "run",
      "--locked",
      "-p",
      "triptych-cpm-cli",
      "--",
      "format",
      "triptych-cpm-2m-v1",
      systemPath,
      imagePath,
    ],
    triptychRoot,
  );
  const diskFiles = [
    { name: "ATOM.COM", path: join(repositoryRoot, "assets/atom-cpm22.com"), bytes: sourceCom },
    { name: "HELLO.ASM", path: exampleSourcePath, bytes: exampleSource },
    { name: "HELLO.COM", path: exampleComPath, bytes: exampleCom },
    { name: "EDIT.COM", path: editComPath, bytes: editCom },
  ];
  for (const file of diskFiles) {
    run(
      "cargo",
      [
        "run",
        "--locked",
        "-p",
        "triptych-cpm-cli",
        "--",
        "import",
        imagePath,
        file.path,
        file.name,
      ],
      triptychRoot,
    );
  }

  const listing = run(
    "cargo",
    ["run", "--locked", "-p", "triptych-cpm-cli", "--", "list", imagePath],
    triptychRoot,
  );
  for (const file of diskFiles) {
    const expectedRecords = Math.ceil(file.bytes.length / 128);
    const expectedRecordBytes = expectedRecords * 128;
    assert.match(
      listing,
      new RegExp(
        `${file.name.replaceAll(".", "\\.")}\\s+${expectedRecords}\\s+${expectedRecordBytes}`,
      ),
    );
    const exportedPath = join(temporaryDirectory, file.name + ".exported");
    run(
      "cargo",
      [
        "run",
        "--locked",
        "-p",
        "triptych-cpm-cli",
        "--",
        "export",
        imagePath,
        file.name,
        exportedPath,
      ],
      triptychRoot,
    );
    const exported = await readFile(exportedPath);
    assert.equal(
      exported.length,
      Math.ceil(file.bytes.length / 128) * 128,
      `${file.name} must occupy complete CP/M records`,
    );
    assert.deepEqual(
      exported.subarray(0, file.bytes.length),
      file.bytes,
      `${file.name} payload differs`,
    );
    assert.ok(
      exported.subarray(file.bytes.length).every((byte) => byte === 0x1a),
      `${file.name} record padding must use the text EOF byte`,
    );
  }

  const image = await readFile(imagePath);
  assert.equal(image.length, 2_097_152, "Triptych image must be exactly 2 MiB");
  assert.deepEqual(image.subarray(0, system.length), system);

  const imageSha256 = sha256(image);
  const diskContents = {
    format: "atom-triptych-disk-contents-v1",
    release: version,
    files: [
      {
        name: "ATOM.COM",
        bytes: sourceCom.length,
        sha256: sha256(sourceCom),
        source: "assets/atom-cpm22.com",
      },
      {
        name: "HELLO.ASM",
        bytes: exampleSource.length,
        sha256: sha256(exampleSource),
        source: "examples/cpm/hello.asm",
      },
      {
        name: "HELLO.COM",
        bytes: exampleCom.length,
        sha256: sha256(exampleCom),
        assembledFrom: "HELLO.ASM",
        assembler: "Atom",
      },
      {
        name: "EDIT.COM",
        bytes: editCom.length,
        sha256: editSha256,
        source: {
          repository: editOrigin.repository,
          revision: editRevision,
          license: editOrigin.license,
        },
      },
    ],
  };
  const diskContentsBytes = Buffer.from(JSON.stringify(diskContents, null, 2) + "\n");
  const descriptor = {
    schema: "triptych-external-system-v1",
    name: "Atom " + version + " for CP/M",
    instruction: "Switch to B: for the writable work disk, then type ATOM ? for help.",
    profile: systemProfile,
    image: {
      asset: "atom.img",
      bytes: image.length,
      sha256: imageSha256,
    },
    workDisk: "copy-image",
    workDrives: ["B"],
  };
  const descriptorBytes = Buffer.from(JSON.stringify(descriptor, null, 2) + "\n");
  await mkdir(releaseDirectory, { recursive: true });
  await writeImmutable(join(releaseDirectory, "atom.img"), image);
  await writeImmutable(join(releaseDirectory, "system.json"), descriptorBytes);
  await writeImmutable(join(releaseDirectory, "disk-contents.json"), diskContentsBytes);

  const descriptorUrl =
    "https://jhlagado.github.io/atom/releases/" + version + "/system.json";
  const launchUrl = new URL(triptychUrl);
  launchUrl.searchParams.set("system", descriptorUrl);
  const page = [
    "<!doctype html>",
    '<html lang="en">',
    "<head>",
    '  <meta charset="utf-8">',
    '  <meta name="viewport" content="width=device-width, initial-scale=1">',
    "  <title>Atom for CP/M</title>",
    '  <meta name="description" content="Download Atom for CP/M or run it in Triptych.">',
    "  <style>",
    "    body{max-width:42rem;margin:3rem auto;padding:0 1rem;",
    "      font:1.1rem/1.6 system-ui,sans-serif;color:#18212b}",
    "    h1{line-height:1.15}a{color:#075f9c}li{margin:.7rem 0}",
    "  </style>",
    "</head>",
    "<body>",
    "  <main>",
    "    <h1>Atom for CP/M</h1>",
    "    <p>Atom " + version + " is available for CP/M and as a Triptych disk.</p>",
    "    <ul>",
    '      <li><a href="releases/' + version + '/ATOM.COM">Download ATOM.COM</a>',
    "          for a CP/M system.</li>",
    '      <li><a href="' + launchUrl.href + '">Run Atom in Triptych</a>.</li>',
    '      <li><a href="releases/' + version + '/atom.img">Download the',
    "          2 MiB Triptych disk image</a>.</li>",
    "    </ul>",
    "    <p>The disk includes ATOM.COM, EDIT.COM, and a HELLO.ASM example with its assembled HELLO.COM.</p>",
    "    <ul>",
    '      <li><a href="https://github.com/jhlagado/atom/releases/tag/v' + version + '">',
    "          Release notes and checksums</a>.</li>",
    "    </ul>",
    "    <p>In Triptych, switch to B: before running Atom. Drive B is the writable work disk.</p>",
    "  </main>",
    "</body>",
    "</html>",
    "",
  ].join("\n");
  await mkdir(join(repositoryRoot, "site"), { recursive: true });
  await writeFile(join(repositoryRoot, "site/index.html"), page);

  process.stdout.write(
    JSON.stringify(
      {
        version,
        triptychRoot,
        triptychCommit: execFileSync("git", ["rev-parse", "HEAD"], {
          cwd: triptychRoot,
          encoding: "utf8",
        }).trim(),
        profile: systemProfile,
        com: { bytes: sourceCom.length, sha256: sha256(sourceCom) },
        diskFiles: diskContents.files,
        image: {
          path: "site/releases/" + version + "/atom.img",
          bytes: image.length,
          sha256: imageSha256,
        },
        descriptor: "site/releases/" + version + "/system.json",
        diskContents: "site/releases/" + version + "/disk-contents.json",
        triptychLaunchUrl: launchUrl.href,
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
