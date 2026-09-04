import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("the native-core verification command self-hosts with AZM imports forbidden", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const artifact = new URL("../assets/native-core.json", import.meta.url);
  const before = await readFile(artifact);
  const result = spawnSync(process.execPath, [
    "--experimental-loader", fileURLToPath(new URL("./fixtures/reject-azm-loader.mjs", import.meta.url)),
    "scripts/generate-native-core.mjs", "--check",
  ], { cwd: root, encoding: "utf8", timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  assert.deepEqual(await readFile(artifact), before, "verification must not rewrite its reference");
});
