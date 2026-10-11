import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { readFile, writeFile } from "node:fs/promises";
import { buildNativeObjectHarness } from "../src/host/build/object-harness-builder.mjs";
import { buildCpm22 } from "./generate-cpm22.mjs";

const check = process.argv.includes("--check");
// The builders load the checked core once per process. Rebuild it separately
// so the object and CP/M stages cannot retain an older image in that cache.
const core = spawnSync(process.execPath, [
  fileURLToPath(new URL("./generate-native-core.mjs", import.meta.url)),
  ...(check ? ["--check"] : []),
], { stdio: "inherit" });
if (core.error) throw core.error;
if (core.status !== 0) throw new Error("Native core build failed");
const built = await buildNativeObjectHarness();
const imagePath = new URL("../assets/atom-object-harness.bin", import.meta.url);
const reportPath = new URL("../proofs/native-object-harness-census.json", import.meta.url);
const report = `${JSON.stringify(built.report, undefined, 2)}\n`;
if (check) {
  assert.deepEqual(new Uint8Array(await readFile(imagePath)), built.bytes);
  assert.equal(await readFile(reportPath, "utf8"), report);
} else {
  await writeFile(imagePath, built.bytes);
  await writeFile(reportPath, report);
}
await buildCpm22({ check });
