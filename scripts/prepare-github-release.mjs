#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function option(name) {
  const index = process.argv.indexOf(name);
  if (index === -1 || index + 1 === process.argv.length) {
    throw new Error("usage: prepare-github-release.mjs --tag <tag> --commit <commit> --output <directory>");
  }
  return process.argv[index + 1];
}

const allowedArguments = new Set(["--tag", "--commit", "--output"]);
for (let index = 2; index < process.argv.length; index += 2) {
  if (!allowedArguments.has(process.argv[index]) || index + 1 >= process.argv.length) {
    throw new Error("usage: prepare-github-release.mjs --tag <tag> --commit <commit> --output <directory>");
  }
}

const tag = option("--tag");
const commit = option("--commit");
const outputDirectory = path.resolve(option("--output"));
const metadata = JSON.parse(await readFile(path.join(repositoryRoot, "package.json"), "utf8"));
const census = JSON.parse(await readFile(path.join(repositoryRoot, "proofs", "cpm22-census.json"), "utf8"));
const sourceImage = path.join(repositoryRoot, "assets", "atom-cpm22.com");
const bytes = await readFile(sourceImage);
const sha256 = createHash("sha256").update(bytes).digest("hex");

assert.equal(tag, `v${metadata.version}`, `release tag must be v${metadata.version}`);
assert.match(commit, /^[0-9a-f]{40}$/, "release commit must be a complete lowercase Git commit");
assert.equal(metadata.license, "GPL-3.0-only");
assert.equal(census.format, "atom-cpm22-census");
assert.equal(bytes.length, census.residentBytes, "ATOM.COM byte count differs from its checked census");
assert.equal(sha256, census.sha256, "ATOM.COM digest differs from its checked census");

const manifest = {
  format: "atom-cpm22-release",
  version: 1,
  release: metadata.version,
  tag,
  platform: "CP/M 2.2",
  artifact: {
    file: "ATOM.COM",
    bytes: bytes.length,
    sha256,
    loadAddress: census.loadAddress,
    entryAddress: census.entryAddress,
  },
  source: {
    repository: "https://github.com/jhlagado/atom",
    commit,
  },
  build: {
    assembler: "ATOM",
    nativeCoreHead: census.nativeCoreHead,
  },
  license: metadata.license,
};

const manifestText = `${JSON.stringify(manifest, null, 2)}\n`;
const manifestSha256 = createHash("sha256").update(manifestText).digest("hex");
const checksums = [
  `${sha256}  ATOM.COM`,
  `${manifestSha256}  ATOM.manifest.json`,
  "",
].join("\n");

await mkdir(outputDirectory, { recursive: true });
await copyFile(sourceImage, path.join(outputDirectory, "ATOM.COM"));
await writeFile(path.join(outputDirectory, "ATOM.manifest.json"), manifestText);
await writeFile(path.join(outputDirectory, "SHA256SUMS"), checksums);

process.stdout.write(`Prepared Atom ${metadata.version} CP/M release in ${outputDirectory}\n`);
