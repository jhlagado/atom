import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { parseIntelHex } from "@jhlagado/z80-runtime";

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

test("packing restores linked and installed dependencies after interruptions and copy failures", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-pack-recovery-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  for (const linked of [false, true]) {
    const root = path.join(temporary, linked ? "linked" : "installed");
    const scope = path.join(root, "node_modules", "@jhlagado");
    const services = path.join(scope, "z80-tool-services");
    const source = linked ? path.join(root, "services-source") : services;
    await fs.mkdir(path.join(root, "scripts"), { recursive: true });
    await fs.mkdir(path.join(source, "native"), { recursive: true });
    const runtime = path.join(scope, "z80-runtime");
    await fs.mkdir(runtime, { recursive: true });
    await fs.writeFile(path.join(runtime, "package.json"), JSON.stringify({ files: ["core.js", "core.js.map", "README.md", "LICENSE"] }));
    await fs.writeFile(path.join(runtime, "core.js"), "export const value = 42;\n//# sourceMappingURL=core.js.map\n");
    await fs.writeFile(path.join(runtime, "core.js.map"), "{}");
    await fs.writeFile(path.join(runtime, "README.md"), "development notes");
    await fs.writeFile(path.join(runtime, "LICENSE"), "runtime licence");
    if (linked) await fs.symlink(source, services, "dir");
    const manifest = '{"name":"pack-probe"}\n';
    await fs.writeFile(path.join(root, "package.json"), manifest);
    await fs.writeFile(path.join(source, "package.json"), JSON.stringify({ files: ["native", "LICENSE"] }));
    await fs.writeFile(path.join(source, "LICENSE"), "licence notice");
    await fs.writeFile(path.join(source, "native", "core.asm"), "RET\n");
    await fs.writeFile(path.join(source, "native", "report.md"), "development report");
    const script = path.join(root, "scripts", "bundled-dependencies.mjs");
    await fs.copyFile(path.resolve("scripts/bundled-dependencies.mjs"), script);
    const prepare = await run(process.execPath, [script, "prepare"]);
    assert.equal(prepare.status, 0, prepare.stderr);
    await assert.rejects(fs.access(path.join(services, "native", "report.md")));
    assert.equal(await fs.readFile(path.join(services, "LICENSE"), "utf8"), "licence notice");
    await assert.rejects(fs.access(path.join(runtime, "core.js.map")));
    await assert.rejects(fs.access(path.join(runtime, "README.md")));
    assert.equal(await fs.readFile(path.join(runtime, "core.js"), "utf8"), "export const value = 42;\n");
    // An interrupted preparation can leave the original manifest and a recovery marker.
    await fs.writeFile(path.join(root, "package.json"), manifest);
    const repeated = await run(process.execPath, [script, "prepare"]);
    assert.notEqual(repeated.status, 0);
    await fs.access(path.join(root, "node_modules", ".atom-pack-dependency-links.json"));
    // Model an interruption after the dependency was restored but before marker removal.
    await fs.rm(services, { recursive: true });
    await fs.rename(path.join(scope, ".atom-pack-z80-tool-services-backup"), services);
    await fs.writeFile(path.join(root, "package.json"), manifest);
    for (let attempt = 0; attempt < 2; attempt++) {
      const cleanup = await run(process.execPath, [script, "cleanup"]);
      assert.equal(cleanup.status, 0, cleanup.stderr);
    }
    assert.equal((await fs.lstat(services)).isSymbolicLink(), linked);
    await fs.access(path.join(runtime, "core.js.map"));
    await fs.access(path.join(runtime, "README.md"));
    assert.match(await fs.readFile(path.join(runtime, "core.js"), "utf8"), /sourceMappingURL/);
    assert.equal(await fs.readFile(path.join(services, "native", "report.md"), "utf8"), "development report");
    await fs.writeFile(path.join(source, "package.json"), JSON.stringify({ files: ["missing"] }));
    const failed = await run(process.execPath, [script, "prepare"]);
    assert.notEqual(failed.status, 0);
    assert.equal(await fs.readFile(path.join(root, "package.json"), "utf8"), manifest);
    await fs.access(path.join(services, "native", "core.asm"));
    await assert.rejects(fs.access(path.join(scope, ".atom-pack-z80-tool-services-backup")));
    await assert.rejects(fs.access(path.join(root, "node_modules", ".atom-pack-dependency-links.json")));
  }
});

test("the packed desktop CLI installs offline and assembles without AZM or an Atom checkout", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-package-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  const packageDirectory = path.join(temporary, "package");
  const installDirectory = path.join(temporary, "install");
  const projectDirectory = path.join(temporary, "project");
  await fs.mkdir(packageDirectory);
  await fs.mkdir(projectDirectory);

  const servicesPath = path.resolve("node_modules/@jhlagado/z80-tool-services");
  const servicesRoot = await fs.realpath(servicesPath);
  const servicesWasLink = (await fs.lstat(servicesPath)).isSymbolicLink();
  const packed = await run("npm", ["pack", "--pack-destination", packageDirectory, "--json"], { cwd: process.cwd() });
  assert.equal(packed.status, 0, packed.stderr);
  assert.equal(await fs.realpath(servicesPath), servicesRoot);
  assert.equal((await fs.lstat(servicesPath)).isSymbolicLink(), servicesWasLink);
  const [census] = JSON.parse(packed.stdout);
  assert.ok(census.files.every(({ path: name }) => !name.endsWith(".map")));
  assert.ok(census.files.every(({ path: name }) => !(name.includes("node_modules/") && name.endsWith(".md"))));
  assert.ok(census.files.every(({ path: name }) => name !== "src/z80/atom-symbols.json"));
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
  await fs.access(path.join(installedAtom, "AUTHORSHIP.md"));
  const nativeFiles = await fs.readdir(path.join(installedAtom, "node_modules", "@jhlagado", "z80-tool-services", "native"));
  assert.ok(nativeFiles.every((name) => !name.endsWith(".md")), "native bundle contains development documentation");
  await assert.rejects(fs.access(path.join(installDirectory, "node_modules", "@jhlagado", "azm")));
  await assert.rejects(fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "azm")));
  await assert.rejects(fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "debug80-runtime")));
  await fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "z80-runtime"));
  await fs.access(path.join(installedAtom, "node_modules", "@jhlagado", "z80-tool-services"));
  const metadata = JSON.parse(await fs.readFile(path.join(installedAtom, "package.json"), "utf8"));
  assert.equal(metadata.license, "GPL-3.0-only");
  assert.equal(metadata.private, undefined);
  const consumer = createRequire(path.join(installDirectory, "package.json"));
  const cpmImage = await fs.readFile(consumer.resolve("atom-z80/cpm22/image"));
  const cpmCensus = JSON.parse(await fs.readFile(consumer.resolve("atom-z80/cpm22/census"), "utf8"));
  assert.equal(cpmCensus.format, "atom-cpm22-census");
  assert.equal(cpmImage.length, cpmCensus.residentBytes);
  assert.equal(createHash("sha256").update(cpmImage).digest("hex"), cpmCensus.sha256);
  assert.deepEqual(cpmImage, await fs.readFile(path.resolve("assets/atom-cpm22.com")));
  assert.deepEqual(metadata.exports["./native-builder"], {
    types: "./src/host/build/object-harness-builder.d.mts",
    import: "./src/host/build/object-harness-builder.mjs",
  });
  const builderProbe = path.join(installDirectory, "verify-native-builder.mjs");
  await fs.writeFile(builderProbe, [
    'import { createHash } from "node:crypto";',
    'import { buildNativeObjectHarness } from "atom-z80/native-builder";',
    'import { assembleResolvedAtomProject, materializeAtomGeneration } from "atom-z80";',
    'const source = new TextEncoder().encode("LD A,42\\nRET\\n");',
    'const assembled = await assembleResolvedAtomProject({ parts: [{ ordinal: 0, bank: 0, logicalIdentity: "probe.asm", originalBytes: source, compilerBytes: source }] }, { target: { start: 0, capacity: 3 } });',
    "const built = await buildNativeObjectHarness();",
    'process.stdout.write(JSON.stringify({ length: built.bytes.length, sha256: createHash("sha256").update(built.bytes).digest("hex"), assembled: [...materializeAtomGeneration(assembled.generation).bytes] }));',
    "",
  ].join("\n"));
  const probedBuilder = await run(process.execPath, [builderProbe], { cwd: installDirectory });
  assert.equal(probedBuilder.status, 0, probedBuilder.stderr);
  const builtHarness = JSON.parse(probedBuilder.stdout);
  const installedHarness = await fs.readFile(path.join(installedAtom, "assets", "atom-object-harness.bin"));
  assert.deepEqual(builtHarness, {
    length: installedHarness.length,
    sha256: createHash("sha256").update(installedHarness).digest("hex"),
    assembled: [0x3e, 42, 0xc9],
  });

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
  assert.match(rejected.stderr, /^bad\.asm:1:1: operands are not valid for this instruction$/m);
  await assert.rejects(fs.access(path.join(projectDirectory, "build", "bad.bin")));

  const selfHosted = await run(executable, ["self-host"], { cwd: projectDirectory });
  assert.equal(selfHosted.status, 0, selfHosted.stderr);
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

test("release preparation writes checked COM files and rejects a mismatched version", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-release-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  const metadata = JSON.parse(await fs.readFile("package.json", "utf8"));
  const tag = `v${metadata.version}`;
  const commit = "0123456789abcdef0123456789abcdef01234567";
  const script = path.resolve("scripts/prepare-github-release.mjs");
  const args = [script, "--tag", tag, "--commit", commit, "--output", temporary];
  const prepared = await run(process.execPath, args);
  assert.equal(prepared.status, 0, prepared.stderr);
  const image = await fs.readFile(path.join(temporary, "ATOM.COM"));
  assert.deepEqual(image, await fs.readFile("assets/atom-cpm22.com"));
  const manifestBytes = await fs.readFile(path.join(temporary, "ATOM.manifest.json"));
  const manifest = JSON.parse(manifestBytes);
  assert.equal(manifest.tag, tag);
  assert.equal(manifest.source.commit, commit);
  assert.equal(manifest.artifact.bytes, image.length);
  assert.equal(manifest.build.assembler, "ATOM");
  const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
  assert.equal(manifest.artifact.sha256, digest(image));
  assert.equal(await fs.readFile(path.join(temporary, "SHA256SUMS"), "utf8"),
    `${digest(image)}  ATOM.COM\n${digest(manifestBytes)}  ATOM.manifest.json\n`);
  args[2] = "v9.9.9";
  const rejected = await run(process.execPath, args);
  assert.equal(rejected.status, 1);
  assert.ok(rejected.stderr.includes(`release tag must be ${tag}`));
});

test("Pages preparation verifies downloads and preserves immutable release files", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-pages-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  const metadata = JSON.parse(await fs.readFile("package.json", "utf8"));
  const release = path.join(temporary, "official");
  const prepared = await run(process.execPath, [
    path.resolve("scripts/prepare-github-release.mjs"),
    "--tag", `v${metadata.version}`,
    "--commit", "0123456789abcdef0123456789abcdef01234567",
    "--output", release,
  ]);
  assert.equal(prepared.status, 0, prepared.stderr);
  const site = path.join(temporary, "site");
  const target = path.join(site, "releases", metadata.version);
  await fs.mkdir(target, { recursive: true });
  const recipes = (await fs.readdir("site/releases"))
    .filter((name) => /^\d+\.\d+\.\d+$/.test(name))
    .sort((left, right) => left.localeCompare(right, "en", { numeric: true }));
  const recipe = path.resolve("site/releases", recipes.at(-1));
  await fs.copyFile(path.join(recipe, "atom.img"), path.join(target, "atom.img"));
  const descriptor = JSON.parse(await fs.readFile(path.join(recipe, "system.json"), "utf8"));
  descriptor.name = `Atom ${metadata.version} for CP/M`;
  await fs.writeFile(path.join(target, "system.json"), JSON.stringify(descriptor));
  const contents = JSON.parse(await fs.readFile(path.join(recipe, "disk-contents.json"), "utf8"));
  contents.release = metadata.version;
  await fs.writeFile(path.join(target, "disk-contents.json"), JSON.stringify(contents));
  const tools = path.join(temporary, "bin");
  await fs.mkdir(tools);
  const gh = path.join(tools, "gh");
  await fs.writeFile(gh, [
    `#!${process.execPath}`,
    'const fs = require("node:fs");',
    'const path = require("node:path");',
    'const destination = process.argv[process.argv.indexOf("--dir") + 1];',
    'for (const name of ["ATOM.COM", "ATOM.manifest.json", "SHA256SUMS"]) {',
    '  fs.copyFileSync(path.join(process.env.ATOM_TEST_RELEASE_DIR, name), path.join(destination, name));',
    '}',
    '',
  ].join("\n"), { mode: 0o755 });
  const options = { env: {
    ...process.env,
    PATH: `${tools}${path.delimiter}${process.env.PATH}`,
    ATOM_TEST_RELEASE_DIR: release,
  } };
  const args = [path.resolve("scripts/materialize-pages-releases.mjs"), "--site", site];
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const materialized = await run(process.execPath, args, options);
    assert.equal(materialized.status, 0, materialized.stderr);
    // The second pass must work from retained files without GitHub access.
    await fs.writeFile(gh, `#!${process.execPath}\nprocess.exit(1);\n`);
  }
  const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
  const checksums = await fs.readFile(path.join(target, "PAGES-SHA256SUMS"), "utf8");
  for (const line of checksums.trim().split("\n")) {
    const [expected, name] = line.split("  ");
    assert.equal(digest(await fs.readFile(path.join(target, name))), expected, name);
  }
  await fs.appendFile(path.join(target, "ATOM.manifest.json"), " ");
  const rejected = await run(process.execPath, args, options);
  assert.equal(rejected.status, 1, "corrupt retained release must be rejected");
  assert.deepEqual(await fs.readFile(path.join(target, "ATOM.COM")), await fs.readFile("assets/atom-cpm22.com"));
});
