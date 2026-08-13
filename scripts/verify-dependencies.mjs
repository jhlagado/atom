import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import path from "node:path";

const repository = path.resolve("../debug80");
const expected = {
  branch: "main",
  azmTree: "049b9e22fb1448bbb1619406e3ea13a124286ce4",
  runtimeTree: "a921abc89dcbd88211dd008e705b69d646cfb9bb",
};

function git(...args) {
  return execFileSync("git", ["-C", repository, ...args], { encoding: "utf8" }).trim();
}

const actual = {
  branch: git("branch", "--show-current"),
  head: git("rev-parse", "HEAD"),
  azmTree: git("rev-parse", "HEAD:packages/azm"),
  runtimeTree: git("rev-parse", "HEAD:packages/debug80-runtime"),
  dependencyWorktree: git("status", "--porcelain", "--", "packages/azm", "packages/debug80-runtime"),
};

assert.equal(actual.branch, expected.branch, "Debug80 dependency branch drifted");
assert.equal(actual.azmTree, expected.azmTree, "AZM source tree drifted from the reviewed oracle");
assert.equal(actual.runtimeTree, expected.runtimeTree, "Debug80 runtime source tree drifted from the reviewed emulator");
assert.equal(actual.dependencyWorktree, "", "AZM or Debug80 runtime has uncommitted source changes");

console.log(JSON.stringify({ repository, ...actual }, null, 2));
