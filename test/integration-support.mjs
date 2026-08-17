import assert from "node:assert/strict";
import fs from "node:fs";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const pair = (high, low) => ((high & 0xff) << 8) | (low & 0xff);
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2e.json", "utf8"));

const PROOF_SYMBOLS = Object.freeze({
  AtomIntegrationProofSourceStart: 0x8000,
  AtomIntegrationSourceBefore: 0x8000,
  AtomIntegrationSource: 0x8001,
  AtomIntegrationSourceLimit: 0x8201,
  AtomIntegrationSourceAfter: 0x8201,
  AtomIntegrationProofSourceEnd: 0x8202,
  AtomIntegrationProofRecordStart: 0x8202,
  AtomIntegrationRecordBefore: 0x8202,
  AtomIntegrationRecord: 0x8203,
  AtomIntegrationRecordAfter: 0x820d,
  AtomIntegrationProofRecordEnd: 0x820e,
  AtomIntegrationProofOutputStart: 0x820e,
  AtomIntegrationOutputBefore: 0x820e,
  AtomIntegrationOutput: 0x820f,
  AtomIntegrationOutputAfter: 0x8213,
  AtomIntegrationProofOutputEnd: 0x8214,
  AtomIntegrationProofKeyStart: 0x8214,
  AtomIntegrationKeyBefore: 0x8214,
  AtomIntegrationKey: 0x8215,
  AtomIntegrationKeyAfter: 0x821b,
  AtomIntegrationProofKeyEnd: 0x821c,
  AtomIntegrationProofSymbolStart: 0x9000,
  AtomIntegrationSymbolBefore: 0x9000,
  AtomIntegrationSymbolArena: 0x9001,
  AtomIntegrationSymbolLimit: 0x9081,
  AtomIntegrationSymbolAfter: 0x9081,
  AtomIntegrationProofSymbolEnd: 0x9082,
  AtomIntegrationProofPendingStart: 0x9100,
  AtomIntegrationPendingBefore: 0x9100,
  AtomIntegrationPendingArena: 0x9101,
  AtomIntegrationPendingLimit: 0x9131,
  AtomIntegrationPendingAfter: 0x9131,
  AtomIntegrationProofPendingEnd: 0x9132,
});

export const PATCH_KIND = Object.freeze({ BYTE: 1, WORD: 2, RELATIVE: 3, DISPLACEMENT: 4 });

export async function createIntegrationHarness({ proofManifest = manifest } = {}) {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.atm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), symbols.AtomParserParse);
  const memory = runtime.hardware.memory;
  for (const [name, value] of [
    ["AtomIntegrationSourceBefore", 0x3c], ["AtomIntegrationSourceAfter", 0xc3],
    ["AtomIntegrationRecordBefore", 0x69], ["AtomIntegrationRecordAfter", 0x96],
    ["AtomIntegrationOutputBefore", 0x5a], ["AtomIntegrationOutputAfter", 0xa5],
    ["AtomIntegrationKeyBefore", 0xa6], ["AtomIntegrationKeyAfter", 0x6a],
    ["AtomIntegrationSymbolBefore", 0x39], ["AtomIntegrationSymbolAfter", 0x93],
    ["AtomIntegrationPendingBefore", 0x4b], ["AtomIntegrationPendingAfter", 0xb4],
  ]) memory[symbols[name]] = value;
  const pristine = memory.slice();
  const immutable = core.codeRanges.map(({ start, end }) => ({ start, bytes: pristine.slice(start, end) }));
  const statistics = {};
  let sourceBytes = new Uint8Array();
  let restartCount = 0;

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    sourceBytes = new Uint8Array();
    restartCount += 1;
    for (const [start, end] of [
      [symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd],
      [symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd],
      [symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd],
      [symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd],
      [symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd],
    ]) {
      for (let address = start; address < end; address += 1) {
        memory[address] = (restartCount * 73 + address * 29) & 0xff;
      }
    }
  }

  function execute(entry, setup = () => {}, label = entry) {
    setup(memory, symbols, runtime.cpu);
    memory[STACK_BEFORE] = 0x87;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x78;
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const before = memory.slice();
    let instructions = 0;
    let cycles = 0;
    const recent = [];
    const budget = proofManifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      recent.push(runtime.cpu.pc);
      if (recent.length > 16) recent.shift();
      const step = runtime.step();
      instructions += 1;
      cycles += step.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return; recent=${recent.map((pc) => pc.toString(16)).join(" ")}`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.equal(memory[STACK_BEFORE], 0x87, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x78, `${label}: stack overrun`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    }
    for (const [name, expected] of [
      ["AtomIntegrationSourceBefore", 0x3c], ["AtomIntegrationSourceAfter", 0xc3],
      ["AtomIntegrationRecordBefore", 0x69], ["AtomIntegrationRecordAfter", 0x96],
      ["AtomIntegrationOutputBefore", 0x5a], ["AtomIntegrationOutputAfter", 0xa5],
      ["AtomIntegrationKeyBefore", 0xa6], ["AtomIntegrationKeyAfter", 0x6a],
      ["AtomIntegrationSymbolBefore", 0x39], ["AtomIntegrationSymbolAfter", 0x93],
      ["AtomIntegrationPendingBefore", 0x4b], ["AtomIntegrationPendingAfter", 0xb4],
    ]) assert.equal(memory[symbols[name]], expected, `${label}: ${name} changed`);
    assert.deepEqual(memory.slice(symbols.AtomIntegrationSource, symbols.AtomIntegrationSource + sourceBytes.length), sourceBytes, `${label}: source changed`);

    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;

    const inside = (address, start, end) => address >= start && address < end;
    for (let address = 0; address < memory.length; address += 1) {
      const allowed =
        inside(address, symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd) ||
        inside(address, symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd) ||
        inside(address, symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd) ||
        inside(address, symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd) ||
        inside(address, symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd) ||
        (entry === "AtomPackSymbol" && inside(address, symbols.AtomIntegrationKey, symbols.AtomIntegrationKey + 6)) ||
        (["AtomSymbolDeclare", "AtomParserParse"].includes(entry) && inside(address, symbols.AtomIntegrationSymbolArena, symbols.AtomIntegrationSymbolLimit)) ||
        (entry === "AtomParserParse" && inside(address, symbols.AtomIntegrationRecord, symbols.AtomIntegrationRecord + 10)) ||
        (entry === "AtomEncode" && inside(address, symbols.AtomIntegrationOutput, symbols.AtomIntegrationOutput + 4)) ||
        (entry === "AtomParserQueueReferences" && inside(address, symbols.AtomIntegrationPendingArena, symbols.AtomIntegrationPendingLimit)) ||
        (address > STACK_BEFORE && address < STACK_AFTER);
      if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
    }
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      hl: pair(runtime.cpu.h, runtime.cpu.l),
      ix: runtime.cpu.ix,
      de: pair(runtime.cpu.d, runtime.cpu.e),
      b: runtime.cpu.b,
      instructions,
      cycles,
    };
  }

  function loadSource(source, part = 7) {
    const bytes = new TextEncoder().encode(source);
    assert.ok(bytes.length <= symbols.AtomIntegrationSourceLimit - symbols.AtomIntegrationSource);
    memory.fill(0xa5, symbols.AtomIntegrationSource, symbols.AtomIntegrationSourceLimit);
    memory.set(bytes, symbols.AtomIntegrationSource);
    sourceBytes = bytes.slice();
    const reset = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = part;
      cpu.h = names.AtomIntegrationSource >>> 8;
      cpu.l = names.AtomIntegrationSource & 0xff;
      const end = names.AtomIntegrationSource + bytes.length;
      cpu.d = end >>> 8;
      cpu.e = end & 0xff;
    }, `reset ${JSON.stringify(source.slice(0, 60))}`);
    assert.equal(reset.carry, 0);
  }

  function pack(name) {
    const bytes = new TextEncoder().encode(name);
    memory.fill(0xa5, symbols.AtomIntegrationSource, symbols.AtomIntegrationSourceLimit);
    memory.set(bytes, symbols.AtomIntegrationSource);
    sourceBytes = bytes.slice();
    const result = execute("AtomPackSymbol", (_memory, names, cpu) => {
      cpu.h = names.AtomIntegrationSource >>> 8;
      cpu.l = names.AtomIntegrationSource & 0xff;
      cpu.b = bytes.length;
      cpu.d = names.AtomIntegrationKey >>> 8;
      cpu.e = names.AtomIntegrationKey & 0xff;
    }, `pack ${name}`);
    assert.equal(result.carry, 0, name);
    return Array.from(memory.slice(symbols.AtomIntegrationKey, symbols.AtomIntegrationKey + 6));
  }

  function references() {
    const count = memory[symbols.AtomParserReferenceCount];
    return Array.from({ length: count }, (_, index) => {
      const start = symbols.AtomParserReferences + index * 9;
      const rawKind = memory[start + 4];
      return {
        symbol: memory[start] | (memory[start + 1] << 8),
        addend: (memory[start + 2] << 24) >> 24,
        operand: memory[start + 3],
        kind: rawKind & symbols.AtomPendingKindMask,
        rawKind,
        offset: memory[start + 5],
        part: memory[start + 6],
        sourceOffset: memory[start + 7] | (memory[start + 8] << 8),
      };
    });
  }

  return {
    symbols,
    memory,
    statistics,
    execute,
    reset({ symbolBytes = 128, pendingBytes = 48 } = {}) {
      restart();
      let result = execute("AtomSymbolReset", (_memory, names, cpu) => {
        cpu.h = names.AtomIntegrationSymbolArena >>> 8;
        cpu.l = names.AtomIntegrationSymbolArena & 0xff;
        const end = names.AtomIntegrationSymbolArena + symbolBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomPendingReset", (_memory, names, cpu) => {
        cpu.h = names.AtomIntegrationPendingArena >>> 8;
        cpu.l = names.AtomIntegrationPendingArena & 0xff;
        const end = names.AtomIntegrationPendingArena + pendingBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
    },
    parse(source, { address = 0x4000, part = 7 } = {}) {
      loadSource(source, part);
      memory.fill(0xa5, symbols.AtomIntegrationRecord, symbols.AtomIntegrationRecord + 10);
      const before = Array.from(memory.slice(symbols.AtomIntegrationRecord, symbols.AtomIntegrationRecord + 10));
      const beforeGlobalEnd = memory[symbols.AtomSymbolGlobalEnd] | (memory[symbols.AtomSymbolGlobalEnd + 1] << 8);
      const beforeLocalBegin = memory[symbols.AtomSymbolLocalBegin] | (memory[symbols.AtomSymbolLocalBegin + 1] << 8);
      const result = execute("AtomParserParse", (_memory, names, cpu) => {
        cpu.b = address >>> 8;
        cpu.c = address & 0xff;
        cpu.d = names.AtomIntegrationRecord >>> 8;
        cpu.e = names.AtomIntegrationRecord & 0xff;
      }, `parse ${JSON.stringify(source.slice(0, 80))}`);
      return {
        ...result,
        before,
        record: Array.from(memory.slice(symbols.AtomIntegrationRecord, symbols.AtomIntegrationRecord + 10)),
        references: references(),
        error: {
          status: memory[symbols.AtomParserErrorStatus],
          part: memory[symbols.AtomParserErrorPart],
          offset: memory[symbols.AtomParserErrorOffset] | (memory[symbols.AtomParserErrorOffset + 1] << 8),
          expressionStatus: memory[symbols.AtomParserExpressionStatus],
          symbolStatus: memory[symbols.AtomParserSymbolStatus],
        },
        beforeGlobalEnd,
        afterGlobalEnd: memory[symbols.AtomSymbolGlobalEnd] | (memory[symbols.AtomSymbolGlobalEnd + 1] << 8),
        beforeLocalBegin,
        afterLocalBegin: memory[symbols.AtomSymbolLocalBegin] | (memory[symbols.AtomSymbolLocalBegin + 1] << 8),
      };
    },
    declare(name, value) {
      const key = pack(name);
      memory.set(key, symbols.AtomIntegrationKey);
      return execute("AtomSymbolDeclare", (_memory, names, cpu) => {
        cpu.h = names.AtomIntegrationKey >>> 8;
        cpu.l = names.AtomIntegrationKey & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      }, `declare ${name}=$${value.toString(16)}`);
    },
    advanceScope() {
      return execute("AtomSymbolAdvanceScope");
    },
    encodeParsed(label = "parsed record") {
      memory.fill(0xa5, symbols.AtomIntegrationOutput, symbols.AtomIntegrationOutput + 4);
      const result = execute("AtomEncode", (_memory, names, cpu) => {
        cpu.ix = names.AtomIntegrationRecord;
        cpu.d = names.AtomIntegrationOutput >>> 8;
        cpu.e = names.AtomIntegrationOutput & 0xff;
      }, `encode ${label}`);
      return { ...result, bytes: Array.from(memory.slice(symbols.AtomIntegrationOutput, symbols.AtomIntegrationOutput + result.status)) };
    },
    locate(operand) {
      return execute("AtomPatchLocate", (_memory, names, cpu) => {
        cpu.ix = names.AtomIntegrationRecord;
        cpu.a = operand;
      }, `locate operand ${operand}`);
    },
    queueReferences(base = 0x4000) {
      return execute("AtomParserQueueReferences", (_memory, _names, cpu) => {
        cpu.d = base >>> 8;
        cpu.e = base & 0xff;
      }, `queue references at $${base.toString(16)}`);
    },
    pendingRecords() {
      const end = memory[symbols.AtomPendingNext] | (memory[symbols.AtomPendingNext + 1] << 8);
      const count = (end - symbols.AtomIntegrationPendingArena) / 6;
      return Array.from({ length: count }, (_, index) => Array.from(memory.slice(
        symbols.AtomIntegrationPendingArena + index * 6,
        symbols.AtomIntegrationPendingArena + (index + 1) * 6,
      )));
    },
    setRecord(record) {
      memory.set(record, symbols.AtomIntegrationRecord);
    },
  };
}
