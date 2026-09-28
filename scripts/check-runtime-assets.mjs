import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import { loadNativeAtomCore } from "../src/host/core/native-atom-core.mjs";

// Packing consumes checked assets. Rebuilding and proving them belongs to the
// native development/release gate, not npm's pack lifecycle.
await loadNativeAtomCore();
for (const [image, report, format] of [
  ["atom-object-harness.bin", "native-object-harness-census.json", "atom-native-object-harness-census"],
  ["atom-cpm22.com", "cpm22-census.json", "atom-cpm22-census"],
]) {
  const bytes = await readFile(new URL(`../assets/${image}`, import.meta.url));
  const census = JSON.parse(await readFile(new URL(`../proofs/${report}`, import.meta.url), "utf8"));
  assert.equal(census.format, format, `${report}: unexpected format`);
  assert.equal(bytes.length, census.residentBytes, `${image}: byte count differs from census`);
  assert.equal(createHash("sha256").update(bytes).digest("hex"), census.sha256,
    `${image}: SHA-256 differs from census`);
}
// Keep stdout available for npm pack --json.
console.error("Bundled native core, object harness and CP/M image integrity verified.");
