import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const execute = promisify(execFile);
const script = path.resolve("scripts/prepare-github-release.mjs");
const commit = "0123456789abcdef0123456789abcdef01234567";

test("the GitHub release contains the checked CP/M executable and provenance", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-release-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));
  const output = path.join(temporary, "release");

  await execute(process.execPath, [script, "--tag", "v0.3.0", "--commit", commit, "--output", output]);

  const executable = await fs.readFile(path.join(output, "ATOM.COM"));
  const checkedExecutable = await fs.readFile("assets/atom-cpm22.com");
  assert.deepEqual(executable, checkedExecutable);

  const manifestText = await fs.readFile(path.join(output, "ATOM.manifest.json"), "utf8");
  const manifest = JSON.parse(manifestText);
  const executableSha256 = createHash("sha256").update(executable).digest("hex");
  assert.deepEqual(manifest, {
    format: "atom-cpm22-release",
    version: 2,
    release: "0.3.0",
    tag: "v0.3.0",
    platform: "CP/M 2.2",
    artifact: {
      file: "ATOM.COM",
      bytes: 15316,
      sha256: executableSha256,
      loadAddress: 0x100,
      entryAddress: 12671,
    },
    source: {
      repository: "https://github.com/jhlagado/atom",
      commit,
    },
    build: {
      assembler: "ATOM",
    },
    license: "GPL-3.0-only",
  });

  const manifestSha256 = createHash("sha256").update(manifestText).digest("hex");
  assert.equal(await fs.readFile(path.join(output, "SHA256SUMS"), "utf8"), [
    `${executableSha256}  ATOM.COM`,
    `${manifestSha256}  ATOM.manifest.json`,
    "",
  ].join("\n"));
});

test("release preparation rejects a tag which differs from the package version", async (t) => {
  const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-release-tag-"));
  t.after(() => fs.rm(temporary, { recursive: true, force: true }));

  await assert.rejects(
    execute(process.execPath, [
      script,
      "--tag", "v9.9.9",
      "--commit", commit,
      "--output", path.join(temporary, "release"),
    ]),
    /release tag must be v0\.3\.0/,
  );
});
