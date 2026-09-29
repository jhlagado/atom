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
sourceScenario.id = proof.scenario.id;
sourceScenario.expectedInitialDriveSha256 = proof.scenario.initialDriveSha256;
sourceScenario.initialFiles = [
  ...(sourceScenario.initialFiles ?? []).filter(
    ({ name }) => name.toUpperCase() !== "ATOM.COM",
  ),
  {
    name: "ATOM.COM",
    encoding: "generated-bytes",
    bytes: atom.length,
    fillByte: 0,
    patches: [{ offset: 0, bytes: [...atom] }],
  },
];
for (const session of sourceScenario.sessions) {
  session.expectedDriveSha256 = proof.scenario.driveSha256;
}

const temporaryDirectory = await mkdtemp(path.join(os.tmpdir(), "atom-triptych-cpm-"));
try {
  const scenarioPath = path.join(temporaryDirectory, "scenario.json");
  await writeFile(scenarioPath, `${JSON.stringify(sourceScenario)}\n`);
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
  assert.equal(observed.id, proof.scenario.id);
  assert.equal(observed.systemCcp, proof.triptych.ccp);
  assert.equal(observed.systemBdos, proof.triptych.bdos);
  assert.equal(observed.initialDriveSha256, proof.scenario.initialDriveSha256);
  assert.deepEqual(
    observed.sessions.map(({ id, transcriptBytes, transcriptSha256, driveSha256, terminal }) => ({
      id,
      transcriptBytes,
      transcriptSha256,
      driveSha256,
      screenSha256: terminal.screenSha256,
    })),
    proof.scenario.sessions,
  );
  process.stdout.write(
    `Triptych CP/M proof passed: Atom ${atom.length} bytes; ${observed.sessions.length} sessions.\n`,
  );
} finally {
  await rm(temporaryDirectory, { recursive: true, force: true });
}
