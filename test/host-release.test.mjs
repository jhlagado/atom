import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const productDocuments = [
  "README.md",
  "docs/command-line.md",
  "docs/language-reference.md",
  "docs/architecture.md",
  "docs/limits.md",
  "docs/tec-1-deployment.md",
  "docs/release-checklist.md",
  "docs/phase-7-report.md",
  "examples/hello/README.md",
];

test("the product documentation, release gate, license, and measured account agree", async () => {
  for (const filename of productDocuments) {
    const source = await fs.readFile(filename, "utf8");
    for (const match of source.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
      const target = match[1];
      if (/^[a-z]+:/i.test(target) || target.startsWith("#")) continue;
      const pathname = target.split("#", 1)[0];
      await fs.access(path.resolve(path.dirname(filename), pathname));
    }
  }

  const metadata = JSON.parse(await fs.readFile("package.json", "utf8"));
  assert.equal(metadata.license, "GPL-3.0-only");
  assert.equal(metadata.publishConfig.access, "public");
  assert.equal(metadata.scripts.prepublishOnly, "npm run release:check");
  assert.match(metadata.scripts["release:check"], /npm test/);
  assert.ok(metadata.files.includes("examples"));

  const license = await fs.readFile("LICENSE", "utf8");
  assert.match(license, /GNU GENERAL PUBLIC LICENSE/);

  const native = await loadNativeAtomCore();
  const phase7 = JSON.parse(await fs.readFile("proofs/phase-7.json", "utf8"));
  assert.equal(phase7.native.codeAndTables, native.codeBytes);
  assert.equal(phase7.native.linkedResidentExtent, native.residentExtentBytes);
  assert.equal(phase7.native.physicalMarginBelow16KiB, 0x4000 - native.residentExtentBytes);
});
