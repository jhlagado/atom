import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleResolvedAtomProject,
  createSelfHostedAtomCore,
  materializeAtomGeneration,
  resolveAtomProject,
} from "../src/host/index.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const nativeRoot = path.join(repositoryRoot, "native");
const ledgerPath = path.join(nativeRoot, "atom-symbols.json");
const outputPath = path.join(repositoryRoot, "assets", "native-core.json");

function intelRecord(address, bytes) {
  const values = [bytes.length, address >>> 8, address & 0xff, 0, ...bytes];
  const checksum = (-values.reduce((sum, byte) => sum + byte, 0)) & 0xff;
  return `:${[...values, checksum].map((byte) => byte.toString(16).toUpperCase().padStart(2, "0")).join("")}`;
}

function sparseIntelHex(generation) {
  const final = new Map();
  for (const operation of generation.images) {
    for (let index = 0; index < operation.bytes.length; index += 1) {
      final.set(operation.address + index, operation.bytes[index]);
    }
  }
  for (const operation of generation.patches) {
    for (let index = 0; index < operation.bytes.length; index += 1) {
      final.set(operation.address + index, operation.bytes[index]);
    }
  }
  const addresses = [...final.keys()].sort((left, right) => left - right);
  const lines = [];
  for (let index = 0; index < addresses.length;) {
    const start = addresses[index];
    const bytes = [];
    while (
      index < addresses.length &&
      addresses[index] === start + bytes.length &&
      bytes.length < 16
    ) {
      bytes.push(final.get(addresses[index]));
      index += 1;
    }
    lines.push(intelRecord(start, bytes));
  }
  lines.push(":00000001FF");
  return `${lines.join("\n")}\n`;
}

function initializedAddresses(program) {
  return program.writeRanges.flatMap(({ start, end }) =>
    Array.from({ length: end - start }, (_value, index) => start + index));
}

async function readLedger() {
  const ledger = JSON.parse(await fs.readFile(ledgerPath, "utf8"));
  if (
    ledger?.format !== "atom-native-symbol-ledger" ||
    ledger?.version !== 2 ||
    !Array.isArray(ledger.symbols)
  ) {
    throw new Error("native/atom-symbols.json is not an Atom native symbol ledger version 2");
  }
  return ledger;
}

async function buildArtifact() {
  const ledger = await readLedger();
  const project = await resolveAtomProject({ root: nativeRoot, entry: "atom.asm" });
  const options = {
    target: { start: 0, capacity: 0x4000 },
    maxInstructions: 200_000_000,
    maxCycles: 2_000_000_000,
  };
  const first = await assembleResolvedAtomProject(project, options);
  const core = createSelfHostedAtomCore({ mapping: ledger.symbols }, first.generation);
  const materialized = materializeAtomGeneration(first.generation);

  const hexText = sparseIntelHex(first.generation);
  // Execute the newly emitted core, not just the checked-in seed. Sparse HEX
  // preserves write coverage as well as values; recovered symbols pin the ABI.
  const second = await assembleResolvedAtomProject(project, { ...options, nativeCore: core });
  const secondCore = createSelfHostedAtomCore({ mapping: ledger.symbols }, second.generation);
  assert.equal(sparseIntelHex(second.generation), hexText, "native ATOM generations differ in bytes or write coverage");
  assert.deepEqual(secondCore.symbols, core.symbols, "native ATOM generations differ in ABI symbols");
  const parsed = parseIntelHex(hexText);
  assert.deepEqual(initializedAddresses(parsed), first.generation.images.flatMap((operation) =>
    operation.bytes.map((_byte, index) => operation.address + index)));
  assert.deepEqual(parsed.memory.slice(0, materialized.end), materialized.bytes);

  const symbols = Object.fromEntries(Object.entries(core.symbols)
    .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0));
  const artifactSha256 = createHash("sha256")
    .update(hexText, "utf8")
    .update("\0", "utf8")
    .update(JSON.stringify(symbols), "utf8")
    .digest("hex");
  return {
    format: "atom-native-core",
    version: 1,
    source: "native/atom.asm",
    hexSha256: createHash("sha256").update(hexText, "utf8").digest("hex"),
    artifactSha256,
    hexText,
    symbols,
  };
}

const rendered = `${JSON.stringify(await buildArtifact(), null, 2)}\n`;
if (process.argv.includes("--check")) {
  let committed;
  try {
    committed = await fs.readFile(outputPath, "utf8");
  } catch {
    committed = undefined;
  }
  if (committed !== rendered) {
    process.stderr.write("assets/native-core.json is stale; run npm run build:native-core\n");
    process.exitCode = 1;
  }
} else {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  await fs.writeFile(outputPath, rendered, "utf8");
}
