#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const triptychRoot = path.resolve(
  process.env.TRIPTYCH_ROOT ?? path.resolve(repositoryRoot, "../triptych"),
);
const proof = JSON.parse(
  await readFile(path.join(repositoryRoot, "proofs/triptych-cpm.json"), "utf8"),
);
const census = JSON.parse(
  await readFile(path.join(repositoryRoot, "proofs/cpm22-census.json"), "utf8"),
);
const atom = await readFile(path.join(repositoryRoot, "assets/atom-cpm22.com"));
const atomSha256 = createHash("sha256").update(atom).digest("hex");
assert.equal(atom.length, proof.atom.bytes, "Atom COM size differs from the Triptych proof");
assert.equal(atom.length, census.residentBytes, "Atom COM size differs from its census");
assert.equal(atomSha256, proof.atom.sha256, "Atom COM differs from the Triptych proof");

const revision = execFileSync("git", ["rev-parse", "HEAD"], {
  cwd: triptychRoot,
  encoding: "utf8",
}).trim();
assert.equal(revision, proof.triptych.revision, "Triptych revision differs from the proof");
const trackedStatus = execFileSync(
  "git",
  ["status", "--porcelain", "--untracked-files=no"],
  { cwd: triptychRoot, encoding: "utf8" },
);
assert.equal(
  trackedStatus,
  "",
  "Triptych tracked files differ from the pinned revision",
);

const taggedAtom = execFileSync(
  "git",
  ["show", `v${proof.taggedRelease.version}:assets/atom-cpm22.com`],
  { cwd: repositoryRoot, encoding: "buffer" },
);
const taggedAtomSha256 = createHash("sha256").update(taggedAtom).digest("hex");
assert.equal(
  taggedAtom.length,
  proof.taggedRelease.bytes,
  "tagged Atom COM size differs from the Triptych proof",
);
assert.equal(
  taggedAtomSha256,
  proof.taggedRelease.sha256,
  "tagged Atom COM differs from the Triptych proof",
);
const taggedDiskContents = JSON.parse(
  await readFile(
    path.join(
      repositoryRoot,
      "site",
      "releases",
      proof.taggedRelease.version,
      "disk-contents.json",
    ),
    "utf8",
  ),
);
assert.deepEqual(
  taggedDiskContents.files.find(({ name }) => name === "ATOM.COM"),
  {
    name: "ATOM.COM",
    bytes: taggedAtom.length,
    sha256: taggedAtomSha256,
    source: "assets/atom-cpm22.com",
  },
  "versioned Triptych inventory differs from its tagged Atom COM",
);

const run = (command, arguments_, options = {}) =>
  execFileSync(command, arguments_, {
    cwd: triptychRoot,
    encoding: "utf8",
    maxBuffer: 8 * 1024 * 1024,
    ...options,
  });

run("npm", ["run", "build:wasm-host"]);

const sourceScenario = JSON.parse(
  await readFile(
    path.join(triptychRoot, "test/bdos/scenarios/triptych-bdos-atom-compile.json"),
    "utf8",
  ),
);

const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "atom-triptych-cpm-"));
try {
  async function proveCom(comBytes, expected, filename) {
    const scenario = structuredClone(sourceScenario);
    scenario.id = expected.id;
    scenario.expectedInitialDriveSha256 = expected.initialDriveSha256;
    scenario.initialFiles = [
      ...(scenario.initialFiles ?? []).filter(
        ({ name }) => name.toUpperCase() !== "ATOM.COM",
      ),
      {
        name: "ATOM.COM",
        encoding: "generated-bytes",
        bytes: comBytes.length,
        fillByte: 0,
        patches: [{ offset: 0, bytes: [...comBytes] }],
      },
    ];
    for (const session of scenario.sessions) {
      session.expectedDriveSha256 = expected.driveSha256;
    }

    const scenarioPath = path.join(temporaryDirectory, filename);
    await writeFile(scenarioPath, `${JSON.stringify(scenario)}\n`);
    const output = run(
      process.execPath,
      ["tools/prove-wasm-host.mjs", "--cpm-headless-only"],
      {
        env: {
          ...process.env,
          TRIPTYCH_CPM_SCENARIO: scenarioPath,
        },
      },
    );
    const report = JSON.parse(output);
    assert.equal(report.status, "passed");
    assert.equal(report.host, proof.triptych.host);
    const [observed] = report.cpm.scenarios;
    assert.equal(observed.id, expected.id);
    assert.equal(observed.systemCcp, proof.triptych.ccp);
    assert.equal(observed.systemBdos, proof.triptych.bdos);
    assert.equal(observed.initialDriveSha256, expected.initialDriveSha256);
    assert.deepEqual(
      observed.sessions.map(({ id, transcriptBytes, transcriptSha256, driveSha256, terminal }) => ({
        id,
        transcriptBytes,
        transcriptSha256,
        driveSha256,
        screenSha256: terminal.screenSha256,
      })),
      expected.sessions,
    );
    return observed.sessions.length;
  }

  const currentSessions = await proveCom(atom, proof.scenario, "current.json");
  const taggedSessions = await proveCom(
    taggedAtom,
    proof.taggedRelease.scenario,
    "tagged-release.json",
  );
  process.stdout.write(
    `Triptych CP/M proof passed: tagged v${proof.taggedRelease.version} COM (${taggedAtom.length} bytes, ${taggedSessions} sessions) and current Atom (${atom.length} bytes, ${currentSessions} sessions).\n`,
  );
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
