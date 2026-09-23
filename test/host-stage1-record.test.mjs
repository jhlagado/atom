import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/generate-stage1-record.mjs", import.meta.url));

const run = (command, arguments_) => new Promise((resolve, reject) => {
  const child = spawn(command, arguments_, { cwd: fileURLToPath(new URL("..", import.meta.url)), stdio: ["ignore", "pipe", "pipe"] });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.on("error", reject);
  child.on("close", (status) => resolve({ status, stdout, stderr }));
});

test("the Stage 1 Atom result is reproducible under Node and Deno", async () => {
  const node = await run(process.execPath, [script, "--check"]);
  assert.equal(node.status, 0, node.stderr);
  assert.equal(node.stdout, "stage-1 Atom conformance record: ok\n");

  const deno = await run("deno", ["run", "-A", script, "--check"]);
  assert.equal(deno.status, 0, deno.stderr);
  assert.equal(deno.stdout, "stage-1 Atom conformance record: ok\n");

  const record = JSON.parse(await readFile(new URL("../proofs/stage-1-atom-host.json", import.meta.url), "utf8"));
  assert.equal(record.schema, "z80-portable-conformance-v1");
  assert.equal(record.profile, "atom-bare-host-v1");
  assert.equal(record.diagnostic, null);
  assert.deepEqual(record.artifact.bytes, [0x3e, 0x2a, 0x76]);
  assert.deepEqual(record.provenance.compatibleHosts, ["node", "deno"]);
});
