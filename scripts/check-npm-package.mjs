import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execute = promisify(execFile);
const root = fileURLToPath(new URL("../", import.meta.url));
const temporary = await mkdtemp(path.join(os.tmpdir(), "atom-publish-check-"));
const started = performance.now();
const run = (command, args, cwd) => execute(command, args, {
  cwd, encoding: "utf8", timeout: 60_000, maxBuffer: 4 * 1024 * 1024,
});

try {
  const archiveDirectory = path.join(temporary, "archive");
  const consumer = path.join(temporary, "consumer");
  await mkdir(archiveDirectory);
  await mkdir(consumer);
  // npm pack runs asset integrity and dependency bundling, but never the
  // prepublishOnly hook. This therefore cannot recurse into publish:check.
  // Leave pack uncapped: killing npm mid-hook could interrupt its manifest
  // restoration. The smoke itself has a bounded runtime below.
  let packed;
  try {
    packed = await promisify(execFile)("npm",
      ["pack", "--json", "--pack-destination", archiveDirectory],
      { cwd: root, encoding: "utf8", maxBuffer: 4 * 1024 * 1024 });
  } catch (error) {
    // If npm pack fails before postpack, undo only links and manifest changes
    // created by the package preparation hook.
    await run(process.execPath, ["scripts/bundled-dependencies.mjs", "cleanup"], root);
    throw error;
  }
  const [metadata] = JSON.parse(packed.stdout);
  await run("npm", [
    "install", "--offline", "--ignore-scripts", "--no-audit", "--no-fund",
    "--prefix", consumer, path.join(archiveDirectory, metadata.filename),
  ], temporary);

  const installed = path.join(consumer, "node_modules", "atom-z80");
  const cli = path.join(installed, "bin", "atom.mjs");
  const packageManifest = JSON.parse(await readFile(path.join(installed, "package.json"), "utf8"));
  assert.equal(packageManifest.bin?.atom, "bin/atom.mjs", "installed atom command mapping is missing");
  const commandShim = path.join(consumer, "node_modules", ".bin",
    process.platform === "win32" ? "atom.cmd" : "atom");
  await readFile(commandShim);
  const help = await run(process.execPath, [cli, "--help"], consumer);
  assert.match(help.stdout, /Usage: atom/);
  const version = await run(process.execPath, [cli, "--version"], consumer);
  assert.ok(version.stdout.includes(metadata.version), "installed CLI version differs from package");

  await writeFile(path.join(consumer, "main.asm"),
    "ORG 100H\nSTART: LD A,42\nJR DONE\nDB 0\nDONE: RET\n");
  const outputs = ["program.bin", "program.hex", "program.com", "program.d8.json"];
  await run(process.execPath, [cli, "main.asm", ...outputs], consumer);
  const expected = Buffer.from([0x3e, 42, 0x18, 1, 0, 0xc9]);
  assert.deepEqual(await readFile(path.join(consumer, "program.bin")), expected);
  assert.deepEqual(await readFile(path.join(consumer, "program.com")), expected);
  assert.match(await readFile(path.join(consumer, "program.hex"), "utf8"), /:00000001FF/);
  JSON.parse(await readFile(path.join(consumer, "program.d8.json"), "utf8"));

  // Import through the installed package's public export in the consumer
  // directory, with no relative route back into this repository.
  await writeFile(path.join(consumer, "api.mjs"), [
    'import assert from "node:assert/strict";',
    'import { assembleAtomProject, materializeAtomGeneration } from "atom-z80";',
    'const result = await assembleAtomProject({ root: process.cwd(), entry: "main.asm" });',
    'const image = materializeAtomGeneration(result.generation);',
    'assert.deepEqual([...image.bytes.slice(0x100, 0x106)], [62,42,24,1,0,201]);',
  ].join("\n"));
  await run(process.execPath, ["api.mjs"], consumer);

  await writeFile(path.join(consumer, "bad.asm"), "LD BC,A\n");
  await assert.rejects(run(process.execPath, [cli, "bad.asm", "program.bin"], consumer),
    (error) => error.code === 1 && /bad\.asm:1:1:/.test(error.stderr));
  assert.deepEqual(await readFile(path.join(consumer, "program.bin")), expected,
    "a rejected build replaced the earlier output");
  console.log(`npm package verified: offline install, CLI, API, outputs and errors (${((performance.now() - started) / 1000).toFixed(1)}s).`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
