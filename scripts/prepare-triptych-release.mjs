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

  const systemPath = join(triptychRoot, "distribution/disk-library", systemAsset);
  const system = await readFile(systemPath);
  assert.equal(system.length, 16_384, "Triptych N04 resident image must be 16 KiB");
  assert.equal(sha256(system), systemSha256, "Triptych resident image differs from its pin");

  const imagePath = join(temporaryDirectory, "atom.img");
  const exportedPath = join(temporaryDirectory, "ATOM.exported");

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
      join(repositoryRoot, "assets/atom-cpm22.com"),
      "ATOM.COM",
    ],
    triptychRoot,
  );

  const listing = run(
    "cargo",
    ["run", "--locked", "-p", "triptych-cpm-cli", "--", "list", imagePath],
    triptychRoot,
  );
  assert.match(listing, /ATOM\.COM\s+120\s+15360/);

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
      "ATOM.COM",
      exportedPath,
    ],
    triptychRoot,
  );

  const image = await readFile(imagePath);
  const exported = await readFile(exportedPath);
  const releaseCom = sourceCom;
  assert.equal(image.length, 2_097_152, "Triptych image must be exactly 2 MiB");
  assert.deepEqual(image.subarray(0, system.length), system);
  assert.equal(exported.length, Math.ceil(releaseCom.length / 128) * 128);
  assert.deepEqual(exported.subarray(0, releaseCom.length), releaseCom);
  assert.ok(
    exported.subarray(releaseCom.length).every((byte) => byte === 0x1a),
    "CP/M file-record padding must use the text EOF byte",
  );

  const imageSha256 = sha256(image);
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
        com: { bytes: releaseCom.length, sha256: sha256(releaseCom) },
        image: {
          path: "site/releases/" + version + "/atom.img",
          bytes: image.length,
          sha256: imageSha256,
        },
        descriptor: "site/releases/" + version + "/system.json",
        triptychLaunchUrl: launchUrl.href,
      },
      null,
      2,
    ) + "\n",
  );
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
