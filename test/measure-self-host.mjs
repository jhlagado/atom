import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { compile } from "@jhlagado/azm";
import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleResolvedAtomProject,
  createSelfHostedAtomCore,
  loadNativeAtomCore,
  materializeAtomGeneration,
  resolveAtomProject,
  translateResolvedAtomProjectToAzm,
} from "../src/host/index.mjs";

const ledger = JSON.parse(await fs.readFile("native/atom-symbols.json", "utf8"));
const source = Object.freeze({ mapping: ledger.symbols, statistics: ledger.statistics });
const project = await resolveAtomProject({ root: path.resolve("native"), entry: "atom.asm" });
const limits = { maxInstructions: 200_000_000, maxCycles: 2_000_000_000 };
const options = { target: { start: 0, capacity: 0x4000 }, ...limits };
const first = await assembleResolvedAtomProject(project, options);
const firstImage = materializeAtomGeneration(first.generation);
const selfHostedCore = createSelfHostedAtomCore(source, first.generation);
const second = await assembleResolvedAtomProject(project, { ...options, nativeCore: selfHostedCore });
const secondImage = materializeAtomGeneration(second.generation);
assert.deepEqual(secondImage.bytes, firstImage.bytes);

const summarizeExecution = (execution) => ({
  instructions: execution.instructions,
  cycles: execution.cycles,
  serviceCalls: execution.serviceCalls,
  finalSp: execution.finalSp,
  returnPc: execution.returnPc,
  sourcePages: execution.sourcePages,
});

const pinned = await loadNativeAtomCore();
const pinnedImage = parseIntelHex(pinned.hexText).memory.slice(0, pinned.residentExtentBytes);
assert.deepEqual(firstImage.bytes, pinnedImage);

const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "atom-measure-self-host-"));
let oracleInitializedBytes;
try {
  const oraclePath = path.join(temporary, "atom.asm");
  await fs.writeFile(oraclePath, translateResolvedAtomProjectToAzm(project));
  const oracle = await compile(oraclePath, {
    emitBin: false,
    emitHex: true,
    emitD8m: false,
    emitLst: false,
    symbolCase: "insensitive",
    registerContracts: "strict",
  });
  assert.deepEqual(oracle.diagnostics.filter(({ severity }) => severity === "error"), []);
  const oracleHex = oracle.artifacts.find(({ kind }) => kind === "hex");
  const oracleProgram = parseIntelHex(oracleHex.text);
  assert.deepEqual(oracleProgram.memory.slice(0, firstImage.bytes.length), firstImage.bytes);
  oracleInitializedBytes = oracleProgram.writeRanges.reduce((sum, range) => sum + range.end - range.start, 0);
  assert.equal(
    oracleInitializedBytes,
    first.generation.images.reduce((sum, operation) => sum + operation.bytes.length, 0),
  );
} finally {
  await fs.rm(temporary, { recursive: true, force: true });
}

console.log(JSON.stringify({
  labels: {
    native: "Measured from the checked self-host source under the pinned native core.",
    equivalence: "Measured by byte comparison against the pinned AZM core, translated AZM source, and a second Atom generation.",
  },
  source: {
    statements: source.statistics.statements,
    sourceParts: source.statistics.sourceParts,
    sourceBytes: source.statistics.sourceBytes,
    checkedParts: project.parts.length,
    checkedBytes: project.parts.reduce((sum, part) => sum + part.compilerBytes.length, 0),
    globalSymbols: source.statistics.globalSymbols,
    privateSymbols: source.statistics.privateSymbols,
  },
  native: {
    codeAndTables: selfHostedCore.codeBytes,
    linkedResidentExtent: selfHostedCore.residentExtentBytes,
    physicalMarginBelow16KiB: 0x4000 - selfHostedCore.residentExtentBytes,
    initializedBytes: first.generation.images.length,
    reservedBytes: firstImage.bytes.length - first.generation.images.length,
    patchRecords: first.generation.patches.length,
    declaredSymbols: first.generation.symbols.length,
  },
  firstGeneration: summarizeExecution(first.execution),
  secondGeneration: summarizeExecution(second.execution),
  oracleInitializedBytes,
  equivalence: {
    pinnedAzmCore: true,
    translatedAzmSource: true,
    secondAtomGeneration: true,
  },
  limits,
}, null, 2));
