import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const executable = fileURLToPath(new URL("../bin/atom.mjs", import.meta.url));

function run(arguments_, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [executable, ...arguments_], {
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (status) => resolve({ status, stdout, stderr }));
  });
}

async function workspace(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-cli-v1-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  return root;
}

test("CLI v1 defaults to one trimmed BIN and publishes only named formats", async (t) => {
  const root = await workspace(t);
  await fs.writeFile(path.join(root, "main.asm"), "ORG 4000H\nDB 1,2,3\n");
  const defaultBuild = await run(["main.asm"], root);
  assert.equal(defaultBuild.status, 0, defaultBuild.stderr);
  assert.deepEqual(await fs.readFile(path.join(root, "build", "main.bin")), Buffer.from([1, 2, 3]));
  assert.deepEqual(await fs.readdir(path.join(root, "build")), ["main.bin"]);

  const selected = await run([
    "main.asm",
    "out/program.bin",
    "out/program.hex",
    "out/program.nobj",
    "out/program.lst",
    "out/program.d8.json",
  ], root);
  assert.equal(selected.status, 0, selected.stderr);
  assert.deepEqual((await fs.readdir(path.join(root, "out"))).sort(), [
    "program.bin",
    "program.d8.json",
    "program.hex",
    "program.lst",
    "program.nobj",
  ]);
  assert.deepEqual(await fs.readFile(path.join(root, "out", "program.bin")), Buffer.from([1, 2, 3]));

  const selectedWithOption = await run(["-o", "option/program.hex", "main.asm"], root);
  assert.equal(selectedWithOption.status, 0, selectedWithOption.stderr);
  assert.deepEqual(await fs.readdir(path.join(root, "option")), ["program.hex"]);
  assert.match(await fs.readFile(path.join(root, "option", "program.hex"), "utf8"), /01/);
});

test("CLI version follows package metadata", async (t) => {
  const root = await workspace(t);
  const metadata = JSON.parse(await fs.readFile(new URL("../package.json", import.meta.url), "utf8"));
  const result = await run(["--version"], root);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${metadata.version}\n`);
});

test("CLI v1 validates positive output selection and rejects removed switches", async (t) => {
  const root = await workspace(t);
  await fs.writeFile(path.join(root, "main.asm"), "NOP\n");
  for (const [arguments_, message] of [
    [["main.asm", "a.bin", "b.bin"], /output format is repeated/],
    [["main.asm", "output"], /recognized format suffix/],
    [["--origin", "4000H", "main.asm"], /unknown option/],
    [["--no-bin", "main.asm"], /unknown option/],
    [["--hex", "main.asm"], /unknown option/],
  ]) {
    const result = await run(arguments_, root);
    assert.equal(result.status, 2);
    assert.match(result.stderr, message);
  }
});

test("CLI v1 project files are Node-only defaults overridden by command outputs and definitions", async (t) => {
  const root = await workspace(t);
  await fs.mkdir(path.join(root, "src"));
  await fs.writeFile(path.join(root, "src", "main.asm"), "%IF DEBUG\nDB 7\n%ELSE\nDB 9\n%ENDIF\n");
  await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
    assembler: "atom",
    entry: "src/main.asm",
    outputs: ["build/project.bin"],
    definitions: { DEBUG: 0 },
  }));
  const configured = await run(["--project", "atom.json"], root);
  assert.equal(configured.status, 0, configured.stderr);
  assert.deepEqual(await fs.readFile(path.join(root, "build", "project.bin")), Buffer.from([9]));

  const overridden = await run(["--project", "atom.json", "-DDEBUG=1", "--output", "build/override.hex"], root);
  assert.equal(overridden.status, 0, overridden.stderr);
  assert.match(await fs.readFile(path.join(root, "build", "override.hex"), "utf8"), /07/);
});

test("CLI v1 project files reject non-Atom assembler flavours", async (t) => {
  const root = await workspace(t);
  await fs.mkdir(path.join(root, "src"));
  await fs.writeFile(path.join(root, "src", "main.asm"), "NOP\n");
  await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
    assembler: "azm",
    entry: "src/main.asm",
  }));

  const result = await run(["--project", "atom.json"], root);

  assert.equal(result.status, 2);
  assert.match(result.stderr, /Atom projects must set assembler to atom/);
  await assert.rejects(fs.access(path.join(root, "build", "main.bin")));

  await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
    assembler: "auto",
    entry: "src/main.asm",
  }));

  const ambiguous = await run(["--project", "atom.json"], root);

  assert.equal(ambiguous.status, 2);
  assert.match(ambiguous.stderr, /src\/main\.asm does not select an assembler from its filename/);
  await assert.rejects(fs.access(path.join(root, "build", "main.bin")));
});

test("CLI v1 project files fall back to BIN when no positive output is configured", async (t) => {
  const root = await workspace(t);
  await fs.mkdir(path.join(root, "src"));
  await fs.writeFile(path.join(root, "src", "tool.asm"), "ORG 4000H\nDB 4,5,6\n");
  await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
    entry: "src/tool.asm",
  }));

  const result = await run(["--project", "atom.json"], root);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(await fs.readFile(path.join(root, "build", "tool.bin")), Buffer.from([4, 5, 6]));
  assert.deepEqual(await fs.readdir(path.join(root, "build")), ["tool.bin"]);
});

test("CLI v1 output suffix selection is case-insensitive", async (t) => {
  const root = await workspace(t);
  await fs.writeFile(path.join(root, "main.asm"), "ORG 4000H\nDB 1\n");

  const result = await run(["main.asm", "out/PROGRAM.BIN", "out/PROGRAM.D8.JSON"], root);

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual((await fs.readdir(path.join(root, "out"))).sort(), [
    "PROGRAM.BIN",
    "PROGRAM.D8.JSON",
  ]);
  assert.deepEqual(await fs.readFile(path.join(root, "out", "PROGRAM.BIN")), Buffer.from([1]));
});

test("CLI v1 renders a validated CP/M COM", async (t) => {
  const root = await workspace(t);
  await fs.writeFile(path.join(root, "main.asm"), "RET\n");
  const result = await run(["--target", "cpm22", "main.asm", "program.com"], root);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(await fs.readFile(path.join(root, "program.com")), Buffer.from([0xc9]));

  const implicit = await run(["main.asm", "implicit.com"], root);
  assert.equal(implicit.status, 0, implicit.stderr);
  assert.deepEqual(await fs.readFile(path.join(root, "implicit.com")), Buffer.from([0xc9]));

  await fs.writeFile(path.join(root, "wrong.asm"), "ORG 200H\nRET\n");
  const rejected = await run(["wrong.asm", "wrong.com"], root);
  assert.equal(rejected.status, 2);
  assert.match(rejected.stderr, /COM output requires load and entry address/);
  await assert.rejects(fs.access(path.join(root, "wrong.com")));

  const explicitGeneric = await run(["--target", "generic", "main.asm", "generic.com"], root);
  assert.equal(explicitGeneric.status, 2);
  assert.match(explicitGeneric.stderr, /COM output requires load and entry address/);
  await assert.rejects(fs.access(path.join(root, "generic.com")));
});
