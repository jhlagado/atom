import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";

import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleResolvedAtomProject,
  createSelfHostedAtomCore,
  loadNativeAtomCore,
  materializeAtomGeneration,
  resolveAtomProject,
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
  sourceReads: execution.sourceReads,
});

const pinned = await loadNativeAtomCore();
const pinnedProgram = parseIntelHex(pinned.hexText);
const pinnedImage = pinnedProgram.memory.slice(0, pinned.residentExtentBytes);
assert.deepEqual(firstImage.bytes, pinnedImage);

const pinnedAddresses = pinnedProgram.writeRanges.flatMap(({ start, end }) =>
  Array.from({ length: end - start }, (_value, index) => start + index));
const addresses = generation => generation.images.flatMap(operation =>
  operation.bytes.map((_byte, index) => operation.address + index));
assert.deepEqual(addresses(first.generation), pinnedAddresses);
assert.deepEqual(addresses(second.generation), pinnedAddresses);
const secondCore = createSelfHostedAtomCore(source, second.generation);
assert.deepEqual(secondCore.symbols, selfHostedCore.symbols);

console.log(JSON.stringify({
  labels: {
    native: "Measured from the checked self-host source under the pinned native core.",
    equivalence: "Measured by exact byte and initialized-address comparison against the pinned core and a second ATOM generation, including recovered ABI symbols.",
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
  pinnedInitializedBytes: pinnedAddresses.length,
  equivalence: {
    pinnedCore: true,
    initializedAddresses: true,
    recoveredSymbols: true,
    secondAtomGeneration: true,
  },
  limits,
}, null, 2));
