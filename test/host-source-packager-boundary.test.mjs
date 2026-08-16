import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const sourceDirectory = "src/host/source-packager";

test("neutral host modules do not import Atom implementation", () => {
  assert.equal(fs.existsSync(sourceDirectory), true, "neutral source directory is missing");

  for (const name of fs.readdirSync(sourceDirectory)) {
    if (!name.endsWith(".mjs")) continue;
    const source = fs.readFileSync(`${sourceDirectory}/${name}`, "utf8");
    assert.doesNotMatch(
      source,
      /from\s+["'][^"']*(?:\/atom\/|atom-token|atom-parser)/i,
      `${name} imports Atom implementation`,
    );
  }
});

test("source-packager errors retain a frozen structured diagnostic", async () => {
  let api;
  try {
    api = await import("../src/host/source-packager/index.mjs");
  } catch {
    api = {};
  }

  assert.equal(typeof api.SourcePackagerError, "function", "SourcePackagerError export is missing");

  const location = {
    logicalIdentity: "src/main.asm",
    offset: 17,
    line: 3,
    column: 5,
  };
  const error = new api.SourcePackagerError(
    "dependency",
    "missing-source",
    "cannot open dependency",
    location,
  );

  assert.equal(error.name, "SourcePackagerError");
  assert.equal(error.message, "cannot open dependency");
  assert.equal(error.category, "dependency");
  assert.equal(error.code, "missing-source");
  assert.deepEqual(error.location, location);
  assert.equal(Object.isFrozen(error.location), true);
  location.offset = 99;
  assert.equal(error.location.offset, 17);
});
