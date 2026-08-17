import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";
import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleResolvedAtomProject,
  createSelfHostedAtomCore,
  materializeAtomGeneration,
  resolveAtomProject,
  translateResolvedAtomProjectToAzm,
} from "../src/host/index.mjs";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const nativeRoot = path.join(repositoryRoot, "native");
const ledgerPath = path.join(nativeRoot, "atom-symbols.json");
const outputPath = path.join(repositoryRoot, "assets", "native-core.json");

function artifact(result, kind) {
  const selected = result.artifacts.find((candidate) => candidate.kind === kind);
  if (selected === undefined) throw new Error(`AZM omitted the ${kind} artifact`);
  return selected;
}

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

async function strictOracle(project, ledger, generation, materialized, core) {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-native-core-"));
  try {
    const oraclePath = path.join(temporary, "atom-native-core.asm");
    await fs.writeFile(oraclePath, translateResolvedAtomProjectToAzm(project));
    const result = await compile(oraclePath, {
      emitBin: false,
      emitHex: true,
      emitD8m: true,
      emitLst: false,
      symbolCase: "insensitive",
      registerContracts: "strict",
    });
    const errors = result.diagnostics.filter(({ severity }) => severity === "error");
    if (errors.length !== 0) {
      throw new Error(`strict-contract translated native core failed to assemble:\n${JSON.stringify(errors, null, 2)}`);
    }
    const oracleProgram = parseIntelHex(artifact(result, "hex").text);
    const atomAddresses = generation.images.flatMap((operation) =>
      operation.bytes.map((_byte, index) => operation.address + index));
    assert.deepEqual(initializedAddresses(oracleProgram), atomAddresses, "Atom and AZM initialized different native addresses");
    assert.deepEqual(
      oracleProgram.memory.slice(materialized.base, materialized.end),
      materialized.bytes,
      "Atom and AZM produced different native bytes",
    );

    const oracleSymbols = new Map(artifact(result, "d8m").json.symbols.flatMap((symbol) => {
      const value = symbol.address ?? symbol.value;
      return value === undefined ? [] : [[symbol.name.toUpperCase(), value]];
    }));
    for (const item of ledger.symbols) {
      if (item.private) continue;
      const value = oracleSymbols.get(item.short.toUpperCase());
      if (!Number.isInteger(value)) throw new Error(`strict AZM oracle omitted ${item.short}`);
      assert.equal(value, core.symbols[item.original], `${item.short} has a different Atom and AZM value`);
    }
  } finally {
    await fs.rm(temporary, { recursive: true, force: true });
  }
}

async function buildArtifact() {
  const ledger = await readLedger();
  const project = await resolveAtomProject({ root: nativeRoot, entry: "atom.asm" });
  const first = await assembleResolvedAtomProject(project, {
    target: { start: 0, capacity: 0x4000 },
    maxInstructions: 200_000_000,
    maxCycles: 2_000_000_000,
  });
  const core = createSelfHostedAtomCore({ mapping: ledger.symbols }, first.generation);
  const materialized = materializeAtomGeneration(first.generation);
  await strictOracle(project, ledger, first.generation, materialized, core);

  const hexText = sparseIntelHex(first.generation);
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
