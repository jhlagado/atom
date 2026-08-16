import { spawn } from "node:child_process";
import path from "node:path";
import process from "node:process";
import test from "node:test";
import assert from "node:assert/strict";

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

test("the shipped hello project passes through the complete Mac CLI", async () => {
  const result = await run(process.execPath, [path.resolve("scripts/verify-example.mjs")]);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /2 parts, 19 exact bytes/);
});
