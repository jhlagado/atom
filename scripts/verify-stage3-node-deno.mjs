import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const executable = path.join(repositoryRoot, "bin", "atom.mjs");
const outputNames = ["main.bin", "main.hex", "main.lst", "main.d8.json", "main.nobj"];
const source = [
  "%IF DEBUG",
  "ORG 4000H",
  "VALUE: DB 2",
  "%ELSE",
  "ORG 4000H",
  "VALUE: DB 3",
  "%ENDIF",
  "START: LD A,(VALUE)",
  "HALT",
  "",
].join("\n");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

function run(command, arguments_, cwd) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, arguments_, { cwd, stdio: ["ignore", "pipe", "pipe"] });
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

function normalize(text, root) {
  const variants = new Set([root]);
  if (root.startsWith("/private/")) variants.add(root.slice("/private".length));
  else variants.add(`/private${root}`);
  return [...variants]
    .sort((left, right) => right.length - left.length)
    .reduce((value, variant) => value.replaceAll(variant, "<workspace>"), text);
}

async function runHost(host, root) {
  await writeFile(path.join(root, "main.asm"), source, "utf8");
  await mkdir(path.join(root, "build"));
  const command = host === "node" ? process.execPath : "deno";
  const prefix = host === "node" ? [executable] : ["run", "-A", executable];
  const result = await run(command, [
    ...prefix,
    "-DDEBUG=1",
    "main.asm",
    ...outputNames.map((name) => path.join("build", name)),
  ], root);
  assert.equal(result.signal, null, `${host} terminated by signal`);
  assert.equal(result.status, 0, `${host} failed:\n${result.stderr}`);
  const outputs = [];
  for (const name of outputNames) {
    const bytes = await readFile(path.join(root, "build", name));
    outputs.push(Object.freeze({ name, size: bytes.length, sha256: sha256(bytes) }));
  }
  return Object.freeze({
    host,
    stdout: normalize(result.stdout, root),
    stderr: normalize(result.stderr, root),
    outputs: Object.freeze(outputs),
  });
}

function compare(left, right) {
  assert.equal(left.stdout, right.stdout, "Node and Deno stdout differ");
  assert.equal(left.stderr, right.stderr, "Node and Deno stderr differ");
  assert.deepEqual(left.outputs, right.outputs, "Node and Deno artifacts differ");
}

const temporary = await mkdtemp(path.join(os.tmpdir(), "atom-stage3-node-deno-"));
const nodeRoot = path.join(temporary, "node");
const denoRoot = path.join(temporary, "deno");
await Promise.all([mkdir(nodeRoot), mkdir(denoRoot)]);
try {
  const [nodeResult, denoResult] = await Promise.all([
    runHost("node", nodeRoot),
    runHost("deno", denoRoot),
  ]);
  compare(nodeResult, denoResult);
  const record = {
    schema: "z80-portable-conformance-v1",
    profile: "atom-bare-host-stage3-v1",
    source: { logicalIdentity: "main.asm", sha256: sha256(new TextEncoder().encode(source)) },
    hosts: [nodeResult, denoResult],
    result: "identical",
  };
  process.stdout.write(`${JSON.stringify(record, null, 2)}\n`);
} finally {
  await rm(temporary, { recursive: true, force: true });
}
