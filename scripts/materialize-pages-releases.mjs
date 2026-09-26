#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const siteRoot = resolve(option("--site") ?? join(repositoryRoot, "site"));

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 === process.argv.length) return undefined;
  return process.argv[index + 1];
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

async function writeImmutable(path, bytes) {
  try {
    const existing = await readFile(path);
    assert.deepEqual(existing, bytes, path + " already exists with different content");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
    await writeFile(path, bytes, { flag: "wx" });
  }
}

function verifyChecksums(directory, bytes) {
  const lines = bytes.toString("utf8").trimEnd().split("\n");
  const expected = new Map();
  for (const line of lines) {
    const match = /^([a-f0-9]{64})  ([A-Za-z0-9._-]+)$/.exec(line);
    assert.ok(match, "malformed SHA256SUMS entry: " + line);
    assert.ok(!expected.has(match[2]), "duplicate checksum entry: " + match[2]);
    expected.set(match[2], match[1]);
  }
  for (const name of ["ATOM.COM", "ATOM.manifest.json"]) {
    assert.ok(expected.has(name), "release checksums omit " + name);
    assert.equal(
      sha256(directory.get(name)),
      expected.get(name),
      name + " does not match its release checksum",
    );
  }
}

const releasesDirectory = join(siteRoot, "releases");
const entries = await readdir(releasesDirectory, { withFileTypes: true });
const versions = entries
  .filter((entry) => entry.isDirectory() && /^\d+\.\d+\.\d+$/.test(entry.name))
  .map((entry) => entry.name)
  .sort((left, right) => {
    const a = left.split(".").map(Number);
    const b = right.split(".").map(Number);
    for (let index = 0; index < 3; index++) {
      if (a[index] !== b[index]) return a[index] - b[index];
    }
    return 0;
  });
assert.ok(versions.length > 0, "site/releases contains no versioned Atom images");

const temporaryRoot = await mkdtemp(join(tmpdir(), "atom-pages-releases-"));
try {
  for (const version of versions) {
    const tag = "v" + version;
    const target = join(releasesDirectory, version);
    const systemBytes = await readFile(join(target, "system.json"));
    const descriptor = JSON.parse(systemBytes.toString("utf8"));
    assert.equal(descriptor.schema, "triptych-external-system-v1");
    assert.equal(descriptor.name, "Atom " + version + " for CP/M");
    assert.equal(descriptor.profile, "triptych-cpu-v0.1-2m-n04");
    assert.equal(descriptor.image.asset, "atom.img");

    const image = await readFile(join(target, descriptor.image.asset));
    assert.equal(image.length, descriptor.image.bytes);
    assert.equal(image.length, 2_097_152);
    assert.equal(sha256(image), descriptor.image.sha256);

    const downloadDirectory = join(temporaryRoot, version);
    await mkdir(downloadDirectory, { recursive: true });
    execFileSync(
      "gh",
      [
        "release",
        "download",
        tag,
        "--repo",
        "jhlagado/atom",
        "--dir",
        downloadDirectory,
        "--pattern",
        "ATOM.COM",
        "--pattern",
        "ATOM.manifest.json",
        "--pattern",
        "SHA256SUMS",
      ],
      { cwd: repositoryRoot, stdio: "inherit" },
    );

    const officialFiles = new Map();
    for (const name of ["ATOM.COM", "ATOM.manifest.json", "SHA256SUMS"]) {
      officialFiles.set(name, await readFile(join(downloadDirectory, name)));
    }
    const manifest = JSON.parse(officialFiles.get("ATOM.manifest.json").toString("utf8"));
    assert.equal(manifest.format, "atom-cpm22-release");
    assert.equal(manifest.release, version);
    assert.equal(manifest.tag, tag);
    assert.equal(manifest.artifact.file, "ATOM.COM");
    assert.equal(manifest.artifact.bytes, officialFiles.get("ATOM.COM").length);
    assert.equal(manifest.artifact.sha256, sha256(officialFiles.get("ATOM.COM")));
    verifyChecksums(officialFiles, officialFiles.get("SHA256SUMS"));

    for (const [name, bytes] of officialFiles) {
      await writeImmutable(join(target, name), bytes);
    }
    const pagesChecksums = Buffer.from(
      [
        sha256(officialFiles.get("ATOM.COM")) + "  ATOM.COM",
        sha256(officialFiles.get("ATOM.manifest.json")) + "  ATOM.manifest.json",
        sha256(officialFiles.get("SHA256SUMS")) + "  SHA256SUMS",
        sha256(image) + "  atom.img",
        sha256(systemBytes) + "  system.json",
        "",
      ].join("\n"),
    );
    await writeImmutable(join(target, "PAGES-SHA256SUMS"), pagesChecksums);

    process.stdout.write(
      version + ": COM " + manifest.artifact.bytes + " bytes; disk " + sha256(image) + "\n",
    );
  }
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}
