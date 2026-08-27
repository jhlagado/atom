import assert from "node:assert/strict";
import fs from "node:fs";
import { isBuiltin } from "node:module";
import path from "node:path";
import test from "node:test";

const sourceDirectory = "../z80-tool-services/source-preparation";

function assertNeutralImports(source, name) {
  assert.doesNotMatch(source, /\bimport\s*\(/, `${name} uses dynamic import`);
  const sourcePath = path.resolve(sourceDirectory, name);
  const neutralRoot = path.resolve(sourceDirectory);
  const pattern = /(?:\bfrom\s*|\bimport\s*(?:\(\s*)?)(["'])([^"']+)\1/g;
  for (const match of source.matchAll(pattern)) {
    const specifier = match[2];
    if (isBuiltin(specifier)) continue;
    assert.equal(specifier.startsWith("."), true, `${name} imports external package ${specifier}`);
    const target = path.resolve(path.dirname(sourcePath), specifier);
    const relative = path.relative(neutralRoot, target);
    assert.equal(
      relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative),
      true,
      `${name} imports outside neutral project-preparation: ${specifier}`,
    );
  }
}

test("neutral host modules do not import Atom implementation", () => {
  assert.equal(fs.existsSync(sourceDirectory), true, "neutral source directory is missing");

  for (const name of fs.readdirSync(sourceDirectory)) {
    if (!name.endsWith(".mjs")) continue;
    const source = fs.readFileSync(`${sourceDirectory}/${name}`, "utf8");
    assertNeutralImports(source, name);
  }
});

test("neutral import proof rejects dynamic Atom imports", () => {
  assert.throws(
    () => assertNeutralImports('await import("../atom/source-profile.mjs")', "dynamic.mjs"),
    /uses dynamic import/,
  );
});

test("project-preparation errors retain a frozen structured diagnostic", async () => {
  let api;
  try {
    api = await import("@jhlagado/z80-tool-services/source-preparation");
  } catch {
    api = {};
  }

  assert.equal(typeof api.SourcePreparationError, "function", "SourcePreparationError export is missing");

  const location = {
    logicalIdentity: "src/main.asm",
    offset: 17,
    line: 3,
    column: 5,
  };
  const error = new api.SourcePreparationError(
    "dependency",
    "missing-source",
    "cannot open dependency",
    location,
  );

  assert.equal(error.name, "SourcePreparationError");
  assert.equal(error.message, "cannot open dependency");
  assert.equal(error.category, "dependency");
  assert.equal(error.code, "missing-source");
  assert.deepEqual(error.location, location);
  assert.equal(Object.isFrozen(error.location), true);
  location.offset = 99;
  assert.equal(error.location.offset, 17);
});

test("the public Atom API exposes preparation failures", async () => {
  const api = await import("../src/host/index.mjs");
  assert.equal(api.SourcePreparationError.name, "SourcePreparationError");
});
