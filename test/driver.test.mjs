import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { packRadix40 } from "../src/abi.mjs";
import { createDriverHarness } from "./driver-support.mjs";
import { referenceBytes } from "./reference-fixtures.mjs";

const h = await createDriverHarness();
const STATUS = Object.freeze({
  OK: 0,
  CONFIGURATION: 1,
  SOURCE: 2,
  UNDEFINED: 3,
  OUTPUT: 4,
  INTERNAL: 5,
});
const CONFIG = Object.freeze({
  PART_COUNT: 1,
  TABLE_RANGE: 2,
  PART_ORDINAL: 3,
  SOURCE_RANGE: 4,
  SYMBOL_RANGE: 5,
  PENDING_RANGE: 6,
  OUTPUT_RANGE: 7,
});

function packedName(name) {
  const payload = name.startsWith(".") ? name.slice(1) : name;
  return packRadix40(payload).flatMap((value) => [value & 0xff, value >>> 8]);
}

test("native driver assembles ordered parts and commits one generation", () => {
  const parts = [
    "Value EQU $42\nJR Start\n",
    "Start: LD A,Value\n",
  ];
  const result = h.assemble(parts);
  assert.equal(result.status, STATUS.OK);
  assert.equal(result.carry, 0);
  assert.deepEqual(h.finalBytes(), referenceBytes(parts.join("")));
  assert.deepEqual(h.finalBytes(), [0x18, 0x00, 0x3e, 0x42]);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 1,
    aborted: 0,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: h.symbols.AtomDriverBuildDescriptor,
    cursor: 0x4004,
    remaining: 0xfc,
  });
});

test("private scope crosses a source-part boundary and closes only at a global label", () => {
  const parts = [
    "Routine:\nJR .Later\n",
    ".Later: NOP\n",
    "Next: LD HL,Routine\n",
  ];
  const result = h.assemble(parts);
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), referenceBytes(parts.join("")));
  assert.deepEqual(h.finalBytes(), [0x18, 0x00, 0x00, 0x21, 0x00, 0x40]);
});

test("resolved forward references reclaim diagnostic anchors before finalization", () => {
  const result = h.assemble(["DW Target\n", "Target: DB 1\n"]);
  assert.equal(result.status, STATUS.OK);
  assert.equal(h.memory[h.symbols.AtomPendingNext] | (h.memory[h.symbols.AtomPendingNext + 1] << 8), h.symbols.AtomDriverPendingArena);
  const finish = h.finish("AtomAssembleFinish after commit");
  assert.equal(finish.status, 0);
  assert.equal(finish.carry, 0);
});

test("undefined global reports its exact source part, offset, and packed name", () => {
  const result = h.assemble(["NOP\n", "LD HL,Missing+1\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusUndefined);
  assert.equal(result.part, 1);
  assert.equal(result.offset, 6);
  assert.equal(result.ix, result.undefinedSymbol);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName("Missing"));
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 0,
    aborted: 1,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
  });
});

test("undefined diagnostics retain the maximum native part ordinal", () => {
  const parts = Array.from({ length: 255 }, () => "");
  parts[254] = "DB Missing\n";
  const result = h.assemble(parts, { label: "AtomAssemble undefined part 254" });
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.part, 254);
  assert.equal(result.offset, 3);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName("Missing"));
});

test("a diagnostic anchor remains exact after pending-list hole filling", () => {
  const source = "DW Resolved\nDW Missing\nResolved:\n";
  const result = h.assemble([source]);
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 15);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName("Missing"));
});

test("current-scope private undefined references report their exact token", () => {
  const result = h.assemble(["Routine:\n", "DW .Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  assert.equal(result.part, 1);
  assert.equal(result.offset, 3);
  assert.deepEqual(h.undefinedKey(result.undefinedSymbol), packedName(".Missing"));
});

test("descriptor failures are preflighted before sink begin", () => {
  const cases = [
    [[], { partCount: 0 }, CONFIG.PART_COUNT],
    [[""], { partsPointer: 0xfffc }, CONFIG.TABLE_RANGE],
    [["NOP\n"], { ordinals: [1] }, CONFIG.PART_ORDINAL],
    [["NOP\n"], { reversedSourceIndex: 0 }, CONFIG.SOURCE_RANGE],
    [[""], { symbolStart: 0x9100, symbolEnd: 0x90ff }, CONFIG.SYMBOL_RANGE],
    [[""], { pendingStart: 0x9300, pendingEnd: 0x92ff }, CONFIG.PENDING_RANGE],
    [[""], { address: 0xfff0, capacity: 0x20 }, CONFIG.OUTPUT_RANGE],
  ];
  for (const [parts, options, detail] of cases) {
    const result = h.assemble(parts, { ...options, label: `AtomAssemble config ${detail}` });
    assert.equal(result.status, STATUS.CONFIGURATION, JSON.stringify(options));
    assert.equal(result.driverDetail, detail, JSON.stringify(options));
    assert.deepEqual(h.lifecycle(), {
      open: 0,
      began: 0,
      committed: 0,
      aborted: 0,
      beginDescriptor: 0,
      commitDescriptor: 0,
      cursor: 0,
      remaining: 0,
    });
    assert.deepEqual(h.operations(), []);
  }
});

test("descriptor capacities pass exactly at one and 255 parts", () => {
  let result = h.assemble([""]);
  assert.equal(result.status, STATUS.OK);
  const parts = Array.from({ length: 255 }, (_, index) => index === 254 ? "NOP\n" : "");
  const validation = h.validate(parts, { label: "AtomDriverValidateDescriptor 255 parts" });
  assert.equal(validation.status, STATUS.OK);
  result = h.assemble(parts, {
    label: "AtomAssemble 255 parts",
  });
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [0x00]);
});

test("final scan accepts an exactly full 32-record global symbol arena", () => {
  const source = Array.from({ length: 32 }, (_, index) => `S${index} EQU ${index}`).join("\n") + "\n";
  const result = h.assemble([source], { label: "AtomAssemble 32 definitions" });
  assert.equal(result.status, STATUS.OK);
  const globalEnd = h.memory[h.symbols.AtomSymbolGlobalEnd] | (h.memory[h.symbols.AtomSymbolGlobalEnd + 1] << 8);
  assert.equal(globalEnd, h.symbols.AtomDriverSymbolLimit);
  const finish = h.finish("AtomAssembleFinish 32 definitions");
  assert.equal(finish.status, 0);
  assert.equal(finish.carry, 0);
});

test("part EOF cannot join tokens across adjacent parts", () => {
  const result = h.assemble(["Start", ": NOP\n"]);
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 0);
  assert.equal(h.lifecycle().aborted, 1);
});

test("begin failure does not abort a generation that never opened", () => {
  const result = h.assemble(["NOP\n"], { failBegin: true });
  assert.equal(result.status, STATUS.OUTPUT);
  assert.equal(result.driverDetail, 0xe0);
  assert.equal(result.part, 0);
  assert.deepEqual(h.operations(), []);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 0,
    committed: 0,
    aborted: 0,
    beginDescriptor: 0,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
  });
});

test("image and patch sink failures abort while preserving the source diagnostic", () => {
  let result = h.assemble(["NOP\nLD A,1\n"], { failAfter: 2, label: "AtomAssemble image failure" });
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusOutput);
  assert.equal(result.statementDetail, 0xe1);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 4);
  assert.equal(h.lifecycle().aborted, 1);
  assert.deepEqual(h.operations(), [{ kind: 1, bank: 0, address: 0x4000, bytes: [0x00] }]);

  result = h.assemble(["JR Later\nLater:\n"], { failAfter: 3, label: "AtomAssemble patch failure" });
  assert.equal(result.status, STATUS.SOURCE);
  assert.equal(result.driverDetail, h.symbols.AtomStatementStatusOutput);
  assert.equal(result.statementDetail, 0xe1);
  assert.equal(result.part, 0);
  assert.equal(result.offset, 9);
  assert.equal(h.lifecycle().aborted, 1);
});

test("commit failure is followed by one abort and retains the adapter status", () => {
  const result = h.assemble(["NOP\n"], { failCommit: true });
  assert.equal(result.status, STATUS.OUTPUT);
  assert.equal(result.driverDetail, 0xe3);
  assert.deepEqual(h.lifecycle(), {
    open: 0,
    began: 1,
    committed: 0,
    aborted: 1,
    beginDescriptor: h.symbols.AtomDriverBuildDescriptor,
    commitDescriptor: 0,
    cursor: 0,
    remaining: 0,
  });
});

test("finalization distinguishes missing diagnostic metadata from source undefined", () => {
  let result = h.assemble(["DW Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  const pendingKind = h.symbols.AtomDriverPendingArena + 4;
  h.memory[pendingKind] &= h.symbols.AtomPendingKindMask;
  result = h.finish("AtomAssembleFinish missing anchor");
  assert.equal(result.status, h.symbols.AtomStatementStatusInternal);
  assert.equal(result.carry, 1);
  assert.equal(result.undefinedSymbol, 0);

  result = h.assemble(["DW Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  h.memory[h.symbols.AtomDriverPendingArena] = 1;
  h.memory[h.symbols.AtomDriverPendingArena + 1] = 0;
  result = h.finish("AtomAssembleFinish invalid symbol pointer");
  assert.equal(result.status, h.symbols.AtomStatementStatusInternal);
  assert.equal(result.carry, 1);

  result = h.assemble(["DW Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  h.memory[result.undefinedSymbol + 5] |= h.symbols.AtomSymbolFlagDefined;
  result = h.finish("AtomAssembleFinish stale defined anchor");
  assert.equal(result.status, h.symbols.AtomStatementStatusInternal);
  assert.equal(result.carry, 1);

  result = h.assemble(["DW Missing\n"]);
  assert.equal(result.status, STATUS.UNDEFINED);
  h.memory[h.symbols.AtomPendingNext] = h.symbols.AtomDriverPendingArena & 0xff;
  h.memory[h.symbols.AtomPendingNext + 1] = h.symbols.AtomDriverPendingArena >>> 8;
  result = h.finish("AtomAssembleFinish undefined without pending metadata");
  assert.equal(result.status, h.symbols.AtomStatementStatusInternal);
  assert.equal(result.carry, 1);
});

test("the native driver can begin a clean generation after an aborted one", () => {
  const failed = h.assemble(["Missing: LD A,Unknown\n"]);
  assert.equal(failed.status, STATUS.UNDEFINED);
  const result = h.assembleAgain(["NOP\n"], { label: "AtomAssemble after abort without runtime restart" });
  assert.equal(result.status, STATUS.OK);
  assert.deepEqual(h.finalBytes(), [0x00]);
  assert.equal(h.lifecycle().committed, 1);
});

test("Phase 3 memory profile covers exactly 64 KiB without gaps or overlap", () => {
  const profile = JSON.parse(fs.readFileSync("proofs/phase-3-memory.json", "utf8"));
  const resolve = (value) => typeof value === "number" ? value : h.symbols[value];
  const regions = profile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(regions[0].startAddress, 0);
  for (const [index, region] of regions.entries()) {
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
  }
  assert.equal(regions.at(-1).endAddress, profile.addressSpaceBytes);
  for (const extent of profile.extents) {
    const total = extent.sum
      ? extent.sum.reduce((sum, [start, end]) => sum + resolve(end) - resolve(start), 0)
      : resolve(extent.end) - resolve(extent.start);
    assert.equal(total, extent.exactBytes, `${extent.name}: extent drift`);
  }
});

test("Phase 3 measured public-entry execution matches pinned observations", () => {
  const execution = JSON.parse(fs.readFileSync("proofs/phase-3.json", "utf8")).executionBudgets;
  for (const [entry, budget] of Object.entries(execution)) {
    const observed = h.statistics[entry];
    assert.ok(observed, `${entry}: no runtime observation`);
    assert.equal(observed.instructions, budget.measuredInstructions, `${entry}: measured instruction drift`);
    assert.equal(observed.cycles, budget.measuredCycles, `${entry}: measured cycle drift`);
    assert.ok(observed.instructions <= budget.maxInstructions, `${entry}: instruction budget exceeded`);
    assert.ok(observed.cycles <= budget.maxCycles, `${entry}: cycle budget exceeded`);
  }
});
