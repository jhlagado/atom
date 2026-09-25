import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { ATOM_VERSION, loadNativeAtomCore } from "../src/host/index.mjs";

const codebaseDocuments = [
  "docs/codebase/index.md",
  "docs/codebase/01-orientation-and-repository-layout.md",
  "docs/codebase/02-host-source-preparation.md",
  "docs/codebase/03-native-z80-assembly-pipeline.md",
  "docs/codebase/04-host-execution-artifacts-and-interfaces.md",
  "docs/codebase/05-native-core-generation-and-self-hosting.md",
  "docs/codebase/06-verification-and-maintenance.md",
  "docs/codebase/native-source-map.md",
];

const productDocuments = [
  "README.md",
  "docs/index.md",
  "docs/command-line.md",
  "docs/cpm22.md",
  "docs/language-reference.md",
  "docs/architecture.md",
  "docs/assembly-style.md",
  "docs/atom-object-format.md",
  "docs/azm-to-atom.md",
  "docs/limits.md",
  "docs/release-checklist.md",
  ...codebaseDocuments,
  "examples/hello/README.md",
];

function assemblyCode(source) {
  return source
    .replace(/"(?:\\.|[^"\\])*"/g, "\"\"")
    .replace(/;.*/g, "");
}

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

  const documentation = [
    "README.md",
    ...(await fs.readdir("docs", { withFileTypes: true }))
      .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
      .map((entry) => path.join("docs", entry.name)),
    ...codebaseDocuments,
    "examples/hello/README.md",
  ];
  for (const filename of documentation) {
    const source = await fs.readFile(filename, "utf8");
    for (const match of source.matchAll(/```asm\s*\n([\s\S]*?)```/g)) {
      assert.doesNotMatch(assemblyCode(match[1]), /[a-z]/, `${filename} has a lowercase assembly example`);
    }
  }
  for (const filename of ["examples/hello/layout.asm", "examples/hello/main.asm", "examples/hello/release-layout.asm"]) {
    assert.doesNotMatch(assemblyCode(await fs.readFile(filename, "utf8")), /[a-z]/, `${filename} is not uppercase`);
  }

  const metadata = JSON.parse(await fs.readFile("package.json", "utf8"));
  assert.equal(metadata.license, "GPL-3.0-only");
  assert.equal(ATOM_VERSION, metadata.version);
  assert.equal(metadata.publishConfig.access, "public");
  assert.equal(metadata.scripts.prepublishOnly, "npm run release:check");
  assert.match(metadata.scripts["release:check"], /npm test/);
  assert.ok(metadata.files.includes("examples"));
  assert.ok(metadata.files.includes("docs/codebase"));
  for (const kind of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
    assert.equal(metadata[kind]?.["@jhlagado/azm"], undefined, `AZM returned as a ${kind} entry`);
  }

  const license = await fs.readFile("LICENSE", "utf8");
  assert.match(license, /GNU GENERAL PUBLIC LICENSE/);

  const native = await loadNativeAtomCore();
  const selfHost = JSON.parse(await fs.readFile("proofs/phase-6.json", "utf8"));
  assert.equal(selfHost.native.codeAndTables, native.codeBytes);
  assert.equal(selfHost.native.linkedResidentExtent, native.residentExtentBytes);
  assert.equal(selfHost.native.physicalMarginBelow16KiB, 0x4000 - native.residentExtentBytes);
});
