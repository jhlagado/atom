#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { buildSelfHostSource } from "../src/host/self-host/build-self-host-source.mjs";

const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const destination = path.join(repository, "self-host");
const check = process.argv.includes("--check");

const source = await buildSelfHostSource({ root: path.join(repository, "asm") });
const decoder = new TextDecoder();
const expected = new Map();
for (const part of source.project.parts) {
  const name = path.basename(part.logicalIdentity);
  expected.set(name, decoder.decode(part.compilerBytes));
}
expected.set("atom.asm", [
  "; Generated Atom-syntax entry point. Do not edit by hand.",
  ...source.project.parts.map((part) => `%include "${path.basename(part.logicalIdentity)}"`),
  "",
].join("\n"));
expected.set("atom-symbols.json", `${JSON.stringify({
  format: "atom-self-host-symbol-map",
  version: 1,
  statistics: source.statistics,
  symbols: source.mapping,
}, null, 2)}\n`);
const existing = await fs.readdir(destination).catch((error) => {
  if (error?.code === "ENOENT") return [];
  throw error;
});
const managed = existing.filter((name) =>
  /^atom-\d\d\.asm$/.test(name) || name === "atom.asm" || name === "atom-symbols.json");
const unexpected = managed.filter((name) => !expected.has(name));

if (check) {
  const stale = unexpected.slice();
  for (const [name, contents] of expected) {
    let actual;
    try {
      actual = await fs.readFile(path.join(destination, name), "utf8");
    } catch {
      stale.push(name);
      continue;
    }
    if (actual !== contents) stale.push(name);
  }
  if (stale.length !== 0) {
    process.stderr.write(`stale generated self-host source: ${stale.join(", ")}\n`);
    process.exitCode = 1;
  }
} else {
  await fs.mkdir(destination, { recursive: true });
  await Promise.all([...expected].map(([name, contents]) => fs.writeFile(path.join(destination, name), contents)));
  await Promise.all(unexpected.map((name) => fs.rm(path.join(destination, name))));
  process.stdout.write(`generated ${source.statistics.parts} Atom source parts (${source.statistics.sourceBytes} bytes)\n`);
}
