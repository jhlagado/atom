import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceDirectory = path.join(repositoryRoot, "examples", "hello");
const expected = Buffer.from([
  0x41, 0x54, 0x4f, 0x4d, 0x00,
  0x06, 0x03,
  0x10, 0xfe,
  0x18, 0x04,
  0xaa, 0xaa, 0x00, 0x00,
  0x05, 0x40, 0x00, 0x40,
]);

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

const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-example-"));
try {
  const project = path.join(temporary, "hello");
  await fs.cp(sourceDirectory, project, { recursive: true });
  const result = await run(process.execPath, [
    path.join(repositoryRoot, "bin", "atom.mjs"),
    "--origin",
    "4000H",
    "main.asm",
  ], { cwd: project });
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Atom assembled 2 part\(s\), 19 byte\(s\)\./);

  const current = path.join(project, "build", "main.atom", "current");
  assert.deepEqual(await fs.readFile(path.join(current, "main.bin")), expected);
  assert.equal(await fs.readFile(path.join(current, "main.hex"), "utf8"), [
    ":1040000041544F4D00060310FE1804AAAA000005F3",
    ":034010004000402D",
    ":00000001FF",
    "",
  ].join("\n"));

  const listing = await fs.readFile(path.join(current, "main.lst"), "utf8");
  assert.match(listing, /layout\.asm:5\s+DB "ATOM",0/);
  assert.match(listing, /main\.asm:11\s+DJNZ \.LOOP/);
  assert.match(listing, /400D  <2 reserved>\s+main\.asm:15\s+DS 2/);

  const d8 = JSON.parse(await fs.readFile(path.join(current, "main.d8.json"), "utf8"));
  assert.deepEqual(d8.fileList, ["layout.asm", "main.asm"]);
  assert.deepEqual(d8.segments, [{ start: 0x4000, end: 0x4013 }]);
  assert.deepEqual(
    d8.symbols.map(({ name }) => name),
    [".LOOP", "BUFFER", "COUNT", "DONE", "MESSAGE", "START"],
  );

  const manifest = JSON.parse(await fs.readFile(path.join(current, "manifest.json"), "utf8"));
  assert.equal(manifest.format, "atom-artifact-set");
  assert.deepEqual(manifest.artifacts.map(({ name }) => name), [
    "main.nobj",
    "main.bin",
    "main.hex",
    "main.lst",
    "main.d8.json",
  ]);
  for (const artifact of manifest.artifacts) {
    const bytes = await fs.readFile(path.join(current, artifact.name));
    assert.equal(bytes.length, artifact.bytes, artifact.name);
    assert.equal(createHash("sha256").update(bytes).digest("hex"), artifact.sha256, artifact.name);
  }
  process.stdout.write("Atom hello example verified: 2 parts, 19 exact bytes, all artifacts present.\n");
} finally {
  await fs.rm(temporary, { recursive: true, force: true });
}
