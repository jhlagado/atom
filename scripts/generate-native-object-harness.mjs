import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { buildNativeObjectHarness } from "./native-object-harness-builder.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const outputPath = join(repositoryRoot, "assets", "atom-object-harness.bin");
const reportPath = join(repositoryRoot, "proofs", "native-object-harness-census.json");
const built = await buildNativeObjectHarness();
const renderedReport = `${JSON.stringify(built.report, undefined, 2)}\n`;
if (process.argv.includes("--check")) {
  assert.deepEqual(new Uint8Array(await readFile(outputPath)), built.bytes);
  assert.equal(await readFile(reportPath, "utf8"), renderedReport);
} else {
  await writeFile(outputPath, built.bytes);
  await writeFile(reportPath, renderedReport);
}
