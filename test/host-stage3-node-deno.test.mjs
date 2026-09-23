import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/verify-stage3-node-deno.mjs", import.meta.url));

function run() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [script], {
      cwd: fileURLToPath(new URL("..", import.meta.url)),
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

test("Stage 3 Node and Deno Atom CLI results are identical", async () => {
  const result = await run();
  assert.equal(result.status, 0, result.stderr);
  const record = JSON.parse(result.stdout);
  assert.equal(record.schema, "z80-portable-conformance-v1");
  assert.equal(record.profile, "atom-bare-host-stage3-v1");
  assert.equal(record.result, "identical");
  assert.deepEqual(record.hosts[0].outputs, record.hosts[1].outputs);
  assert.equal(record.hosts[0].stdout, record.hosts[1].stdout);
  assert.equal(record.hosts[0].stderr, record.hosts[1].stderr);
  assert.match(record.hosts[0].stdout, /<workspace>\/build\/main\.bin/);
});
