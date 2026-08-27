import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const repository = path.resolve(packageRoot, "../..");
const expected = {
  branch: "main",
  azmTree: "c75c76e2f0de66592917679de0974bb64fcbdd55",
  runtimeTree: "7372ed452ce4acc20eeaf44d7af4351e3780c84d",
  toolServicesTree: "cb7d24ed9ad40bfa4f3823eb075c7d7547f01da2",
};

function git(...args) {
  return execFileSync("git", ["-C", repository, ...args], { encoding: "utf8" }).trim();
}

const actual = {
  branch: git("branch", "--show-current"),
  head: git("rev-parse", "HEAD"),
  azmTree: git("rev-parse", "HEAD:packages/azm"),
  runtimeTree: git("rev-parse", "HEAD:packages/debug80-runtime"),
  toolServicesTree: git("rev-parse", "HEAD:packages/z80-tool-services"),
  dependencyWorktree: git(
    "status",
    "--porcelain",
    "--",
    "packages/azm",
    "packages/debug80-runtime",
    "packages/z80-tool-services",
  ),
};

assert.equal(actual.branch, expected.branch, "Debug80 dependency branch drifted");
assert.equal(actual.azmTree, expected.azmTree, "AZM source tree drifted from the reviewed oracle");
assert.equal(actual.runtimeTree, expected.runtimeTree, "Debug80 runtime source tree drifted from the reviewed emulator");
assert.equal(actual.toolServicesTree, expected.toolServicesTree, "Z80 tool-services source tree drifted from the reviewed ABI");
assert.equal(actual.dependencyWorktree, "", "AZM, Debug80 runtime, or Z80 tool services has uncommitted source changes");

console.log(JSON.stringify({ repository, ...actual }, null, 2));
