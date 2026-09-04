import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { access, cp, mkdir, mkdtemp, readFile, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

test("the CP/M builder reproduces its checked image and census without AZM", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const paths = ["assets/atom-cpm22.com", "proofs/cpm22-census.json"];
  const before = await Promise.all(paths.map((path) => readFile(new URL(`../${path}`, import.meta.url))));
  const result = spawnSync(process.execPath, [
    "--experimental-loader", fileURLToPath(new URL("./fixtures/reject-azm-loader.mjs", import.meta.url)),
    "scripts/generate-cpm22.mjs", "--check",
  ], { cwd: root, encoding: "utf8", timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  const after = await Promise.all(paths.map((path) => readFile(new URL(`../${path}`, import.meta.url))));
  assert.deepEqual(after, before, "verification must not rewrite its references");
});

test("CP/M output-candidate sizes reproduce with AZM imports forbidden", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const artifact = new URL("../proofs/cpm22-output-candidates.json", import.meta.url);
  const before = await readFile(artifact);
  const result = spawnSync(process.execPath, [
    "--experimental-loader", fileURLToPath(new URL("./fixtures/reject-azm-loader.mjs", import.meta.url)),
    "scripts/measure-cpm22-output-candidates.mjs", "--check",
  ], { cwd: root, encoding: "utf8", timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
  assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  assert.deepEqual(await readFile(artifact), before);
});

test("the CP/M build uses installed tool services without a sibling source checkout", async () => {
  const root = fileURLToPath(new URL("../", import.meta.url));
  const temporary = await mkdtemp(join(tmpdir(), "atom-cpm-isolated-"));
  const isolated = join(temporary, "atom");
  try {
    await mkdir(isolated);
    for (const path of ["package.json", "scripts", "src", "native", "assets", "proofs"]) {
      await cp(join(root, path), join(isolated, path), { recursive: true });
    }
    // Reuse installed dependencies only. The source checkout has no siblings.
    await symlink(join(root, "node_modules"), join(isolated, "node_modules"), "dir");
    await assert.rejects(access(join(temporary, "z80-tool-services")), { code: "ENOENT" });
    const result = spawnSync(process.execPath, [
      "--experimental-loader", fileURLToPath(new URL("./fixtures/reject-azm-loader.mjs", import.meta.url)),
      "scripts/generate-cpm22.mjs", "--check",
    ], { cwd: isolated, encoding: "utf8", timeout: 180_000, maxBuffer: 4 * 1024 * 1024 });
    assert.equal(result.status, 0, result.error?.message || result.stderr || result.stdout);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});
