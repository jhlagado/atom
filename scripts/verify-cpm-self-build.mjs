#!/usr/bin/env node

// Build ATOM.COM on CP/M from the files in src/z80 and require the result to
// match assets/atom-cpm22.com. The sources need more space than an 8-inch
// floppy, so this runs on a Triptych 2 MB disk. It needs a Triptych checkout
// with its CP/M tool and WASM host built (npm run build:wasm-browser).

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const triptychRoot = resolve(process.env.TRIPTYCH_ROOT ?? resolve(repositoryRoot, "../triptych"));
const systemAsset =
  "library-retained-61dd21e3f89be888e3530ec3b414691c343f7ad2c29aa15fac4ff2510c3a5a3e.bin";
const bootstrapAsset = "dist/wasm-browser/bootstrap-triptych-cpm-2m-n04-v1.bin";
const command = "ATOM CPM22 NEWATOM.COM";

function triptychCpm(...args) {
  return execFileSync("cargo", ["run", "--quiet", "--locked", "-p", "triptych-cpm-cli", "--", ...args], {
    cwd: triptychRoot,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "inherit"],
  });
}

const { TriptychCpu } = createRequire(import.meta.url)(join(triptychRoot, "dist/wasm/triptych_host_wasm.js"));
const temporaryDirectory = await mkdtemp(join(tmpdir(), "atom-cpm-self-build-"));
try {
  const image = join(temporaryDirectory, "atom.img");
  triptychCpm("format", "triptych-cpm-2m-v1", join(triptychRoot, "distribution/disk-library", systemAsset), image);
  const atomCom = await readFile(join(repositoryRoot, "assets/atom-cpm22.com"));
  triptychCpm("import", image, join(repositoryRoot, "assets/atom-cpm22.com"), "ATOM.COM");
  const sources = (await readdir(join(repositoryRoot, "src/z80"))).filter((name) => name.endsWith(".asm"));
  for (const name of sources) {
    triptychCpm("import", image, join(repositoryRoot, "src/z80", name), name.toUpperCase());
  }

  const cpu = new TriptychCpu(new Uint8Array(await readFile(join(triptychRoot, bootstrapAsset))));
  cpu.install_drive(0, new Uint8Array(await readFile(image)), true);
  const transcript = () => Buffer.from(cpu.serial_output()).toString("latin1");
  const runUntil = (done, slices, description) => {
    for (let slice = 0; slice < slices; slice += 1) {
      cpu.run_slice(50_000, 500_000);
      if (done()) return;
    }
    throw new Error(`timed out waiting for ${description}: ${JSON.stringify(transcript().slice(-300))}`);
  };
  runUntil(() => transcript().endsWith("A>"), 10_000, "the CP/M prompt");
  const start = transcript().length;
  cpu.enqueue_serial_input(new TextEncoder().encode(`${command}\r`));
  runUntil(() => transcript().slice(start).endsWith("\r\nA>"), 2_000_000, command);
  const reply = transcript().slice(start);
  assert.match(reply, /NEWATOM\.COM written/, `CP/M build failed: ${JSON.stringify(reply)}`);

  const finished = join(temporaryDirectory, "finished.img");
  await writeFile(finished, cpu.export_drive(0));
  const exported = join(temporaryDirectory, "NEWATOM.COM");
  triptychCpm("export", finished, "NEWATOM.COM", exported);
  const built = await readFile(exported);
  // CP/M stores whole 128-byte records, so the file ends in padding.
  assert.equal(built.length, Math.ceil(atomCom.length / 128) * 128);
  assert.deepEqual(built.subarray(0, atomCom.length), atomCom, "CP/M-built ATOM.COM differs from the Node build");
  console.log(`ATOM.COM built on CP/M from ${sources.length} source files matches assets/atom-cpm22.com.`);
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
