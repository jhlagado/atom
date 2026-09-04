import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("the object-harness verification rebuilds the pinned image without AZM", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const artifacts = ["assets/atom-object-harness.bin", "proofs/native-object-harness-census.json"];
  const before = await Promise.all(artifacts.map((name) => readFile(new URL(`../${name}`, import.meta.url))));
  const result = spawnSync(process.execPath, [
    "--experimental-loader", fileURLToPath(new URL("./fixtures/reject-azm-loader.mjs", import.meta.url)),
    "scripts/generate-native-object-harness.mjs", "--check",
  ], { cwd: root, encoding: "utf8", timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  const after = await Promise.all(artifacts.map((name) => readFile(new URL(`../${name}`, import.meta.url))));
  assert.deepEqual(after, before, "verification must not rewrite its references");
});
