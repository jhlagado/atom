#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const mode = process.argv.includes("--update") ? "update" : "check";
const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const censusPath = path.join(packageRoot, "proofs", "package-census.json");

function fail(message) {
  process.stderr.write(`package-census: ${message}\n`);
  process.exit(1);
}

const packed = spawnSync("npm", ["pack", "--dry-run", "--json"], {
  cwd: packageRoot,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
});

if (packed.status !== 0) {
  process.stderr.write(packed.stderr);
  fail(`npm pack --dry-run failed with status ${packed.status}`);
}

let census;
try {
  [census] = JSON.parse(packed.stdout);
} catch (error) {
  process.stderr.write(packed.stdout);
  process.stderr.write(packed.stderr);
  fail(`npm pack --dry-run did not return JSON: ${error.message}`);
}

const observed = Object.freeze({
  format: "atom-package-census",
  version: 1,
  package: `${census.name}@${census.version}`,
  unpackedBytes: census.unpackedSize,
  entries: census.entryCount,
});

if (mode === "update") {
  fs.writeFileSync(censusPath, `${JSON.stringify(observed, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(observed, null, 2)}\n`);
  process.exit(0);
}

const expected = JSON.parse(fs.readFileSync(censusPath, "utf8"));
for (const field of ["format", "version", "package", "unpackedBytes", "entries"]) {
  if (expected[field] !== observed[field]) {
    process.stderr.write(`package-census: expected ${JSON.stringify(expected, null, 2)}\n`);
    process.stderr.write(`package-census: observed ${JSON.stringify(observed, null, 2)}\n`);
    fail(`package census drifted at ${field}; run npm run update:package-census after packaged files are frozen`);
  }
}

process.stdout.write(`${JSON.stringify(observed, null, 2)}\n`);
