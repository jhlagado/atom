import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { parseIntelHex } from "@jhlagado/debug80-runtime";

function run(command, arguments_, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, arguments_, { ...options, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (status, signal) => resolve({ status, signal, stdout, stderr }));
  });
}

test("the packed desktop CLI installs offline and assembles without AZM or an Atom checkout", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-package-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  const packageDirectory = path.join(temporary, "package");
  const installDirectory = path.join(temporary, "install");
  const projectDirectory = path.join(temporary, "project");
  await fs.mkdir(packageDirectory);
  await fs.mkdir(projectDirectory);

  const packed = await run("npm", ["pack", "--pack-destination", packageDirectory, "--json"], { cwd: process.cwd() });
  assert.equal(packed.status, 0, packed.stderr);
  const [census] = JSON.parse(packed.stdout);
  const archive = path.join(packageDirectory, census.filename);
  const installed = await run("npm", [
    "install",
    "--offline",
    "--ignore-scripts",
    "--prefix",
    installDirectory,
    archive,
  ], { cwd: temporary });
  assert.equal(installed.status, 0, installed.stderr);
  const installedAtom = path.join(installDirectory, "node_modules", "atom-z80");
  await assert.rejects(fs.access(path.join(installDirectory, "node_modules", "@jhlagado", "azm")));
  await assert.rejects(fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "azm")));
  await fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "debug80-runtime"));
  await fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "z80-tool-services"));
  const metadata = JSON.parse(await fs.readFile(path.join(installedAtom, "package.json"), "utf8"));
  assert.equal(metadata.license, "GPL-3.0-only");
  assert.equal(metadata.private, undefined);
  assert.deepEqual(metadata.exports["./native-builder"], {
    types: "./scripts/native-object-harness-builder.d.mts",
    import: "./scripts/native-object-harness-builder.mjs",
  });
  await fs.access(path.join(installedAtom, "scripts", "native-object-harness-builder.mjs"));
  await fs.access(path.join(installedAtom, "scripts", "native-object-harness-builder.d.mts"));
  await fs.access(path.join(installedAtom, "docs", "phase-6-report.md"));
  await fs.access(path.join(installedAtom, "docs", "phase-11-report.md"));
  await fs.access(path.join(installedAtom, "docs", "language-reference.md"));
  await fs.access(path.join(installedAtom, "docs", "azm-to-atom.md"));
  await fs.access(path.join(installedAtom, "docs", "codebase", "index.md"));
  await fs.access(path.join(installedAtom, "examples", "hello", "main.asm"));
  await fs.access(path.join(installedAtom, "native", "atom.asm"));
  await fs.access(path.join(installedAtom, "native", "atom-00.asm"));

  await fs.writeFile(path.join(projectDirectory, "legacy.asm"), [
    ".org 0x4000",
    "START:",
    "_loop: ld a,LSB(0x1234)",
    "       jr nz,_loop",
    ".end",
    "",
  ].join("\n"));
  const converter = path.join(installDirectory, "node_modules", ".bin", "azm-to-atom");
  const converted = await run(converter, ["legacy.asm"], { cwd: projectDirectory });
  assert.equal(converted.status, 0, converted.stderr);
  assert.equal(await fs.readFile(path.join(projectDirectory, "legacy.atom.asm"), "utf8"), [
    "ORG $4000",
    "START:",
    ".loop: LD a,LOW($1234)",
    "       JR nz,.loop",
    "",
    "",
  ].join("\n"));
  await fs.writeFile(path.join(projectDirectory, "unsupported.asm"), '.include "lib.asm"\n');
  const unsupported = await run(converter, ["unsupported.asm"], { cwd: projectDirectory });
  assert.equal(unsupported.status, 1);
  assert.match(unsupported.stderr, /^unsupported\.asm:1:1: AZM directive \.INCLUDE has no Atom equivalent/m);
  await assert.rejects(fs.access(path.join(projectDirectory, "unsupported.atom.asm")));

  await fs.writeFile(path.join(projectDirectory, "main.asm"), [
    "%define DEBUG 1",
    "ORG 4000H",
    "%if DEBUG",
    "START: LD A,42",
    "%endif",
    "JR START",
    "",
  ].join("\n"));
  const executable = path.join(installDirectory, "node_modules", ".bin", "atom");
  const assembled = await run(executable, [
    "main.asm",
    "build/main.bin",
    "build/main.hex",
    "build/main.d8.json",
  ], { cwd: projectDirectory });
  assert.equal(assembled.status, 0, assembled.stderr);
  assert.match(assembled.stdout, /Atom assembled 1 part\(s\), 4 byte\(s\)/);
  assert.deepEqual(await fs.readFile(path.join(projectDirectory, "build", "main.bin")), Buffer.from([0x3e, 42, 0x18, 0xfc]));
  await fs.access(path.join(projectDirectory, "build", "main.hex"));
  await fs.access(path.join(projectDirectory, "build", "main.d8.json"));
  await assert.rejects(fs.access(path.join(projectDirectory, "build", "main.nobj")));
  await assert.rejects(fs.access(path.join(projectDirectory, "build", "main.lst")));

  await fs.writeFile(path.join(projectDirectory, "payload.bin"), Buffer.from([0xde, 0xad, 0xbe, 0xef]));
  await fs.writeFile(path.join(projectDirectory, "binary.asm"), 'ORG 4100H\nPAYLOAD: INCBIN "payload.bin"\n');
  const included = await run(executable, ["binary.asm"], { cwd: projectDirectory });
  assert.equal(included.status, 0, included.stderr);
  assert.deepEqual(
    await fs.readFile(path.join(projectDirectory, "build", "binary.bin")),
    Buffer.from([0xde, 0xad, 0xbe, 0xef]),
  );

  await fs.writeFile(path.join(projectDirectory, "program.asm"), "RET\n");
  const com = await run(executable, ["--target", "cpm22", "program.asm", "build/program.com"], {
    cwd: projectDirectory,
  });
  assert.equal(com.status, 0, com.stderr);
  assert.deepEqual(await fs.readFile(path.join(projectDirectory, "build", "program.com")), Buffer.from([0xc9]));

  await fs.writeFile(path.join(projectDirectory, "bad.asm"), "LD BC,A\n");
  const rejected = await run(executable, ["bad.asm"], { cwd: projectDirectory });
  assert.equal(rejected.status, 1);
  assert.match(rejected.stderr, /^bad\.asm:1:1: Atom rejected a source statement/m);
  await assert.rejects(fs.access(path.join(projectDirectory, "build", "bad.bin")));

  const selfHosted = await run(executable, ["self-host"], { cwd: projectDirectory });
  assert.equal(selfHosted.status, 0, selfHosted.stderr);
  assert.match(selfHosted.stdout, /Atom assembled 6 part\(s\), 12396 byte\(s\)/);
  const selfHostBinary = await fs.readFile(path.join(projectDirectory, "build", "atom.bin"));
  const installedCore = JSON.parse(await fs.readFile(path.join(installedAtom, "assets", "native-core.json"), "utf8"));
  const expectedSelfHost = parseIntelHex(installedCore.hexText).memory.slice(0, installedCore.symbols.AtomHostResidentEnd);
  assert.deepEqual(selfHostBinary, Buffer.from(expectedSelfHost));
  const customizedSelfHost = await run(executable, ["self-host", "--target", "cpm22"], { cwd: projectDirectory });
  assert.equal(customizedSelfHost.status, 2);
  assert.match(customizedSelfHost.stderr, /self-host does not accept project, target, or definition options/);

  const corePath = path.join(installedAtom, "assets", "native-core.json");
  const core = JSON.parse(await fs.readFile(corePath, "utf8"));
  core.symbols.AtomAssemble ^= 1;
  await fs.writeFile(corePath, `${JSON.stringify(core, null, 2)}\n`);
  const corrupted = await run(executable, ["main.asm"], { cwd: projectDirectory });
  assert.equal(corrupted.status, 1);
  assert.match(corrupted.stderr, /native Atom core symbol map failed its SHA-256 check/);
});
