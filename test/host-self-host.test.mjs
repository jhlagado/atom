import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleResolvedAtomProject,
  createSelfHostedAtomCore,
  loadNativeAtomCore,
  materializeAtomGeneration,
  resolveAtomProject,
} from "../src/host/index.mjs";

const SELF_HOST_BUDGETS = Object.freeze({
  maxInstructions: 200_000_000,
  maxCycles: 2_000_000_000,
});

test("checked Atom source rebuilds the pinned core and then rebuilds itself byte-identically", async () => {
  const proof = JSON.parse(await fs.readFile("proofs/phase-6.json", "utf8"));
  const ledger = JSON.parse(await fs.readFile("native/atom-symbols.json", "utf8"));
  const source = Object.freeze({ mapping: ledger.symbols, statistics: ledger.statistics });
  const project = await resolveAtomProject({
    root: path.resolve("native"),
    entry: "atom.asm",
  });
  assert.deepEqual(project.parts.map(({ logicalIdentity }) => logicalIdentity), [
    "atom-00.asm",
    "atom-01.asm",
    "atom-02.asm",
    "atom-03.asm",
    "atom-04.asm",
    "atom.asm",
  ]);

  const options = {
    target: { start: 0, capacity: 0x4000 },
    ...SELF_HOST_BUDGETS,
  };
  const first = await assembleResolvedAtomProject(project, options);
  const firstImage = materializeAtomGeneration(first.generation);
  const pinned = await loadNativeAtomCore();
  const pinnedProgram = parseIntelHex(pinned.hexText);
  const pinnedImage = pinnedProgram.memory.slice(0, pinned.residentExtentBytes);
  assert.equal(firstImage.base, 0);
  assert.equal(firstImage.end, pinned.residentExtentBytes);
  assert.deepEqual(firstImage.bytes, pinnedImage);

  const selfHostedCore = createSelfHostedAtomCore(source, first.generation);
  const second = await assembleResolvedAtomProject(project, { ...options, nativeCore: selfHostedCore });
  assert.deepEqual(materializeAtomGeneration(second.generation).bytes, firstImage.bytes);
  assert.deepEqual(second.execution, first.execution);
  assert.equal(selfHostedCore.codeBytes, pinned.codeBytes);
  assert.equal(selfHostedCore.residentExtentBytes, pinned.residentExtentBytes);

  const atomInitializedAddresses = first.generation.images.flatMap((operation) =>
    operation.bytes.map((_byte, index) => operation.address + index));
  const pinnedInitializedAddresses = pinnedProgram.writeRanges.flatMap(({ start, end }) =>
    Array.from({ length: end - start }, (_value, index) => start + index));
  assert.deepEqual(pinnedInitializedAddresses, atomInitializedAddresses);
  assert.deepEqual(second.generation.images.map(({ address, bytes }) => [address, bytes.length]),
    first.generation.images.map(({ address, bytes }) => [address, bytes.length]));
  const secondCore = createSelfHostedAtomCore(source, second.generation);
  assert.deepEqual(secondCore.symbols, selfHostedCore.symbols);

  assert.deepEqual(source.statistics, {
    statements: 7166,
    sourceBytes: 101492,
    sourceParts: 5,
    checkedParts: 6,
    checkedBytes: 101641,
    globalSymbols: 876,
    privateSymbols: 440,
  });
  assert.equal(first.generation.images.length, proof.native.initializedBytes);
  assert.equal(first.generation.patches.length, proof.native.patchRecords);
  assert.ok(first.execution.instructions <= SELF_HOST_BUDGETS.maxInstructions);
  assert.ok(first.execution.cycles <= SELF_HOST_BUDGETS.maxCycles);
  assert.equal(first.execution.instructions, proof.execution.instructions);
  assert.equal(first.execution.cycles, proof.execution.cycles);
  assert.equal(first.execution.serviceCalls, proof.execution.serviceCalls);
  assert.equal(first.execution.sourceReads, proof.execution.sourceReads);
  assert.equal(firstImage.bytes.length, proof.native.linkedResidentExtent);
});

test("a malformed replacement native core is rejected before execution", async () => {
  const bytes = new TextEncoder().encode("NOP\n");
  const project = {
    parts: [{ ordinal: 0, bank: 0, logicalIdentity: "bad-core.asm", originalBytes: bytes, compilerBytes: bytes }],
  };
  const rejectsCore = (nativeCore) => assert.rejects(
    () => assembleResolvedAtomProject(project, { target: { start: 0, capacity: 1 }, nativeCore }),
    (error) => error?.name === "AtomAssemblyError" && error.category === "configuration" && error.code === "invalid-native-core",
  );
  await rejectsCore({});

  const valid = await loadNativeAtomCore();
  const accepted = await assembleResolvedAtomProject(project, { target: { start: 0, capacity: 1 }, nativeCore: valid });
  assert.deepEqual(Array.from(materializeAtomGeneration(accepted.generation).bytes), [0]);
  await rejectsCore({ ...valid, hexText: "" });
  const [firstRecord, ...remainingRecords] = valid.hexText.trimEnd().split("\n");
  assert.match(firstRecord, /^:/);
  await rejectsCore({ ...valid, hexText: `${remainingRecords.join("\n")}\n` });
  await rejectsCore({
    ...valid,
    hexText: valid.hexText.replace(":00000001FF", ":0140000000BF\n:00000001FF"),
  });
});
