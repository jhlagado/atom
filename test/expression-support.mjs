import assert from "node:assert/strict";
import fs from "node:fs";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const pair = (high, low) => ((high & 0xff) << 8) | (low & 0xff);
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2d.json", "utf8"));

const PROOF_SYMBOLS = Object.freeze({
  AtomExpressionProofSourceStart: 0x8000,
  AtomExpressionSourceBefore: 0x8000,
  AtomExpressionSource: 0x8001,
  AtomExpressionSourceLimit: 0x8201,
  AtomExpressionSourceAfter: 0x8201,
  AtomExpressionProofSourceEnd: 0x8202,
  AtomExpressionProofKeyStart: 0x8202,
  AtomExpressionProofKeyBefore: 0x8202,
  AtomExpressionProofKey: 0x8203,
  AtomExpressionProofKeyAfter: 0x8209,
  AtomExpressionProofKeyEnd: 0x820a,
  AtomExpressionProofSymbolStart: 0x9000,
  AtomExpressionSymbolBefore: 0x9000,
  AtomExpressionSymbolArena: 0x9001,
  AtomExpressionSymbolLimit: 0x9081,
  AtomExpressionSymbolAfter: 0x9081,
  AtomExpressionProofSymbolEnd: 0x9082,
  AtomExpressionProofPendingStart: 0x9100,
  AtomExpressionPendingBefore: 0x9100,
  AtomExpressionPendingArena: 0x9101,
  AtomExpressionPendingLimit: 0x9131,
  AtomExpressionPendingAfter: 0x9131,
  AtomExpressionProofPendingEnd: 0x9132,
});

export const EXPRESSION = Object.freeze({
  RESOLVED: 0,
  UNRESOLVED: 1,
  LEXICAL: 2,
  EXPECTED_PRIMARY: 3,
  EXPECTED_RIGHT: 4,
  DIVIDE_ZERO: 5,
  RANGE: 6,
  FORWARD_FORM: 7,
  CAPACITY: 8,
  SYMBOL: 9,
  INTERNAL: 10,
});

export async function createExpressionHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.asm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), symbols.AtomExpressionParse);
  const memory = runtime.hardware.memory;
  for (const [name, value] of [
    ["AtomExpressionSourceBefore", 0x3c], ["AtomExpressionSourceAfter", 0xc3],
    ["AtomExpressionProofKeyBefore", 0xa6], ["AtomExpressionProofKeyAfter", 0x6a],
    ["AtomExpressionSymbolBefore", 0x69], ["AtomExpressionSymbolAfter", 0x96],
    ["AtomExpressionPendingBefore", 0x5a], ["AtomExpressionPendingAfter", 0xa5],
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
    memory[STACK_BEFORE] = 0xa9;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x9a;
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const before = memory.slice();
    let instructions = 0;
    let cycles = 0;
    const recent = [];
    const budget = manifest.executionBudgets[entry];
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
    assert.equal(memory[STACK_BEFORE], 0xa9, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x9a, `${label}: stack overrun`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    for (const region of immutable) assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    for (const [name, expected] of [
      ["AtomExpressionSourceBefore", 0x3c], ["AtomExpressionSourceAfter", 0xc3],
      ["AtomExpressionProofKeyBefore", 0xa6], ["AtomExpressionProofKeyAfter", 0x6a],
      ["AtomExpressionSymbolBefore", 0x69], ["AtomExpressionSymbolAfter", 0x96],
      ["AtomExpressionPendingBefore", 0x5a], ["AtomExpressionPendingAfter", 0xa5],
    ]) assert.equal(memory[symbols[name]], expected, `${label}: ${name} changed`);
    assert.deepEqual(memory.slice(symbols.AtomExpressionSource, symbols.AtomExpressionSource + sourceBytes.length), sourceBytes, `${label}: source changed`);

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
        (entry === "AtomPackSymbol" && inside(address, symbols.AtomExpressionProofKey, symbols.AtomExpressionProofKey + 6)) ||
        (["AtomSymbolDeclare", "AtomExpressionParse"].includes(entry) && inside(address, symbols.AtomExpressionSymbolArena, symbols.AtomExpressionSymbolLimit)) ||
        (entry === "AtomExpressionQueue" && inside(address, symbols.AtomExpressionPendingArena, symbols.AtomExpressionPendingLimit)) ||
        (address > STACK_BEFORE && address < STACK_AFTER);
      if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
    }
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      hl: pair(runtime.cpu.h, runtime.cpu.l),
      ix: runtime.cpu.ix,
      instructions,
      cycles,
    };
  }

  function loadSource(source, part = 7) {
    const bytes = new TextEncoder().encode(source);
    assert.ok(bytes.length <= symbols.AtomExpressionSourceLimit - symbols.AtomExpressionSource);
    memory.fill(0xa5, symbols.AtomExpressionSource, symbols.AtomExpressionSourceLimit);
    memory.set(bytes, symbols.AtomExpressionSource);
    sourceBytes = bytes.slice();
    let result = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = part;
      cpu.h = names.AtomExpressionSource >>> 8;
      cpu.l = names.AtomExpressionSource & 0xff;
      const end = names.AtomExpressionSource + bytes.length;
      cpu.d = end >>> 8;
      cpu.e = end & 0xff;
    }, `reset ${JSON.stringify(source.slice(0, 60))}`);
    assert.equal(result.carry, 0);
    result = execute("AtomTokenizerNext", undefined, `first token ${JSON.stringify(source.slice(0, 60))}`);
    assert.equal(result.carry, 0);
  }

  function pack(name) {
    const bytes = new TextEncoder().encode(name);
    memory.fill(0, symbols.AtomExpressionSource, symbols.AtomExpressionSourceLimit);
    memory.set(bytes, symbols.AtomExpressionSource);
    sourceBytes = bytes.slice();
    memory.fill(0xa5, symbols.AtomExpressionProofKey, symbols.AtomExpressionProofKey + 6);
    const result = execute("AtomPackSymbol", (_memory, names, cpu) => {
      cpu.h = names.AtomExpressionSource >>> 8;
      cpu.l = names.AtomExpressionSource & 0xff;
      cpu.b = bytes.length;
      cpu.d = names.AtomExpressionProofKey >>> 8;
      cpu.e = names.AtomExpressionProofKey & 0xff;
    }, `pack ${name}`);
    assert.equal(result.carry, 0, name);
    return Array.from(memory.slice(symbols.AtomExpressionProofKey, symbols.AtomExpressionProofKey + 6));
  }

  return {
    symbols,
    memory,
    statistics,
    execute,
    reset() {
      restart();
      let result = execute("AtomSymbolReset", (_memory, names, cpu) => {
        cpu.h = names.AtomExpressionSymbolArena >>> 8;
        cpu.l = names.AtomExpressionSymbolArena & 0xff;
        cpu.d = names.AtomExpressionSymbolLimit >>> 8;
        cpu.e = names.AtomExpressionSymbolLimit & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomPendingReset", (_memory, names, cpu) => {
        cpu.h = names.AtomExpressionPendingArena >>> 8;
        cpu.l = names.AtomExpressionPendingArena & 0xff;
        cpu.d = names.AtomExpressionPendingLimit >>> 8;
        cpu.e = names.AtomExpressionPendingLimit & 0xff;
      });
      assert.equal(result.carry, 0);
    },
    evaluate(source, { address = 0x4000, part = 7 } = {}) {
      loadSource(source, part);
      const beforeGlobalEnd = memory[symbols.AtomSymbolGlobalEnd] | (memory[symbols.AtomSymbolGlobalEnd + 1] << 8);
      const beforeLocalBegin = memory[symbols.AtomSymbolLocalBegin] | (memory[symbols.AtomSymbolLocalBegin + 1] << 8);
      const result = execute("AtomExpressionParse", (_memory, _names, cpu) => {
        cpu.b = address >>> 8;
        cpu.c = address & 0xff;
      }, `expression ${JSON.stringify(source)}`);
      return {
        ...result,
        delimiter: memory[symbols.AtomTokenRecord],
        error: {
          status: memory[symbols.AtomExpressionErrorStatus],
          part: memory[symbols.AtomExpressionErrorPart],
          offset: memory[symbols.AtomExpressionErrorOffset] | (memory[symbols.AtomExpressionErrorOffset + 1] << 8),
          symbolStatus: memory[symbols.AtomExpressionSymbolStatus],
        },
        beforeGlobalEnd,
        afterGlobalEnd: memory[symbols.AtomSymbolGlobalEnd] | (memory[symbols.AtomSymbolGlobalEnd + 1] << 8),
        beforeLocalBegin,
        afterLocalBegin: memory[symbols.AtomSymbolLocalBegin] | (memory[symbols.AtomSymbolLocalBegin + 1] << 8),
      };
    },
    declare(name, value) {
      const key = pack(name);
      memory.set(key, symbols.AtomExpressionProofKey);
      return execute("AtomSymbolDeclare", (_memory, names, cpu) => {
        cpu.h = names.AtomExpressionProofKey >>> 8;
        cpu.l = names.AtomExpressionProofKey & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      }, `declare ${name}=$${value.toString(16)}`);
    },
    advanceScope() {
      return execute("AtomSymbolAdvanceScope");
    },
    queue(symbol, addend, patch, kind) {
      return execute("AtomExpressionQueue", (_memory, _names, cpu) => {
        cpu.ix = symbol;
        cpu.h = addend < 0 ? 0xff : 0;
        cpu.l = addend & 0xff;
        cpu.d = patch >>> 8;
        cpu.e = patch & 0xff;
        cpu.b = kind;
      }, `queue symbol=$${symbol.toString(16)} addend=${addend}`);
    },
    pendingRecord(index = 0) {
      const start = symbols.AtomExpressionPendingArena + index * 6;
      return Array.from(memory.slice(start, start + 6));
    },
  };
}
