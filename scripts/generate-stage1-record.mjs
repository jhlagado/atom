import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

import {
  ATOM_VERSION,
  assembleResolvedAtomProject,
  renderAtomArtifacts,
} from "../src/host/index.mjs";

const proofUrl = new URL("../proofs/stage-1-atom-host.json", import.meta.url);
const source = [
  "ORG 4000H",
  "START: LD A,2AH",
  "HALT",
  "",
].join("\n");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

const canonicalRecord = async () => {
  const originalBytes = new TextEncoder().encode(source);
  const project = {
    parts: [{
      ordinal: 0,
      bank: 0,
      logicalIdentity: "stage1.asm",
      originalBytes,
      compilerBytes: originalBytes,
    }],
  };
  const assembled = await assembleResolvedAtomProject(project, {
    target: { start: 0x4000, capacity: 0x100 },
  });
  const artifacts = renderAtomArtifacts({ project, ...assembled });
  const { execution, generation } = assembled;
  return {
    schema: "z80-portable-conformance-v1",
    profile: "atom-bare-host-v1",
    source: {
      logicalIdentity: "stage1.asm",
      sha256: sha256(originalBytes),
    },
    artifact: {
      kind: "flat-binary",
      base: generation.target.start,
      end: generation.highWater,
      bytes: [...artifacts.bin],
      sha256: sha256(artifacts.bin),
    },
    diagnostic: null,
    execution: {
      status: "committed",
      instructions: execution.instructions,
      cycles: execution.cycles,
      serviceCalls: execution.serviceCalls,
      sourceReads: execution.sourceReads,
      returnPc: execution.returnPc,
      finalSp: execution.finalSp,
      finalCursor: generation.finalCursor,
      highWater: generation.highWater,
    },
    provenance: {
      assembler: "atom",
      atomVersion: ATOM_VERSION,
      executionSubstrate: "debug80-reference",
      compatibleHosts: ["node", "deno"],
    },
  };
};

const expected = `${JSON.stringify(await canonicalRecord(), null, 2)}\n`;
if (process.argv.includes("--check")) {
  const actual = await readFile(proofUrl, "utf8");
  if (actual !== expected) {
    throw new Error("Stage 1 Atom conformance record is stale; run npm run build:stage1-record");
  }
  process.stdout.write("stage-1 Atom conformance record: ok\n");
} else {
  await writeFile(proofUrl, expected);
  process.stdout.write("stage-1 Atom conformance record: written\n");
}
