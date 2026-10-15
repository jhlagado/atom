import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readdirSync } from "node:fs";
import test from "node:test";

import { checkFigure } from "../scripts/figures/check.mjs";

// docs/records.md and its figures are generated from the source and from a
// trace of the real assembler. A record change that is not regenerated fails.
test("the record page and figures match the source and the assembler", () => {
  execFileSync(process.execPath, ["scripts/generate-records-doc.mjs", "--check"], { stdio: "pipe" });
});

test("the record figures pass the geometry lint", () => {
  const directory = "docs/images/records";
  for (const name of readdirSync(directory).filter((file) => file.endsWith(".svg"))) {
    assert.deepEqual(checkFigure(`${directory}/${name}`), [], name);
  }
});
