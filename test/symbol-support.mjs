import assert from "node:assert/strict";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const RETURN_SLOT = 0xfefe;
const RETURN_SENTINEL = 0x80fe;

const PROOF_SYMBOLS = Object.freeze({
  AtomSymbolProofDataStart: 0x8000,
  AtomSymbolProofKeyBefore: 0x8000,
  AtomSymbolProofKey: 0x8001,
  AtomSymbolProofKeyAfter: 0x8007,
  AtomSymbolProofTextBefore: 0x8008,
  AtomSymbolProofText: 0x8009,
  AtomSymbolProofTextAfter: 0x8013,
  AtomSymbolProofDataEnd: 0x8014,
  AtomSymbolArenaBefore: 0x9000,
  AtomSymbolArena: 0x9001,
  AtomSymbolArenaLimit: 0x9041,
  AtomSymbolArenaAfter: 0x9041,
  AtomSymbolArenaProofEnd: 0x9042,
  AtomPendingArenaBefore: 0x9100,
  AtomPendingArena: 0x9101,
  AtomPendingArenaLimit: 0x9119,
  AtomPendingArenaAfter: 0x9119,
  AtomPendingArenaProofEnd: 0x911a,
});

const pair = (high, low) => ((high & 0xff) << 8) | (low & 0xff);

export async function createSymbolHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.atm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), symbols.AtomSymbolReset);
  const memory = runtime.hardware.memory;
  memory[symbols.AtomSymbolArenaBefore] = 0x3c;
  memory[symbols.AtomSymbolArenaAfter] = 0xc3;
  memory[symbols.AtomPendingArenaBefore] = 0x69;
  memory[symbols.AtomPendingArenaAfter] = 0x96;
  memory[symbols.AtomSymbolProofKeyBefore] = 0xa6;
  memory[symbols.AtomSymbolProofKeyAfter] = 0x6a;
  memory[symbols.AtomSymbolProofTextBefore] = 0xc5;
  memory[symbols.AtomSymbolProofTextAfter] = 0x5c;
  const pristine = memory.slice();
  const immutableCode = core.codeRanges.map(({ start, end }) => pristine.slice(start, end));
  const statistics = {};
  let restartCount = 0;

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    restartCount += 1;
    for (const [start, end] of [
      [symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd],
      [symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd],
    ]) {
      for (let address = start; address < end; address += 1) {
        memory[address] = (restartCount * 73 + address * 29) & 0xff;
      }
    }
  }

  function execute(entry, setup = () => {}, label = entry) {
    runtime.cpu.iy = 0x6d92;
    setup(memory, symbols, runtime.cpu);
    const preservedIy = runtime.cpu.iy;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const beforeExecution = memory.slice();
    let instructions = 0;
    let cycles = 0;
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < 10_000) {
      const result = runtime.step();
      cycles += result.cycles ?? 0;
      instructions += 1;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    if (entry !== "AtomSymbolDeclareGlobalLabel") {
      assert.equal(runtime.cpu.iy, preservedIy, `${label}: IY changed`);
    }
    for (const [index, { start, end }] of core.codeRanges.entries()) {
      assert.deepEqual(memory.slice(start, end), immutableCode[index], `${label}: native code changed`);
    }
    assert.equal(memory[symbols.AtomSymbolArenaBefore], 0x3c, `${label}: symbol underrun`);
    assert.equal(memory[symbols.AtomSymbolArenaAfter], 0xc3, `${label}: symbol overrun`);
    assert.equal(memory[symbols.AtomPendingArenaBefore], 0x69, `${label}: pending underrun`);
    assert.equal(memory[symbols.AtomPendingArenaAfter], 0x96, `${label}: pending overrun`);
    assert.equal(memory[symbols.AtomSymbolProofKeyBefore], 0xa6, `${label}: key underrun`);
    assert.equal(memory[symbols.AtomSymbolProofKeyAfter], 0x6a, `${label}: key overrun`);
    assert.equal(memory[symbols.AtomSymbolProofTextBefore], 0xc5, `${label}: text underrun`);
    assert.equal(memory[symbols.AtomSymbolProofTextAfter], 0x5c, `${label}: text overrun`);
    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) {
      observed.instructions = instructions;
      observed.instructionCase = label;
    }
    if (cycles > observed.cycles) {
      observed.cycles = cycles;
      observed.cycleCase = label;
    }
    statistics[entry] = observed;
    const allowed = (address) => {
      if (address >= 0xfe00 && address < 0xff00) return true;
      if (address >= symbols.AtomSymbolWorkspaceStart && address < symbols.AtomSymbolWorkspaceEnd) return true;
      if (
        entry === "AtomPackSymbol" &&
        address >= symbols.AtomEncoderWorkspaceStart &&
        address < symbols.AtomEncoderWorkspaceEnd
      ) return true;
      if (
        entry === "AtomPackSymbol" &&
        address >= symbols.AtomSymbolProofKey &&
        address < symbols.AtomSymbolProofKey + 6
      ) return true;
      if (
        ["AtomSymbolDeclare", "AtomSymbolReference", "AtomSymbolDeclareGlobalLabel"].includes(entry) &&
        address >= symbols.AtomSymbolArena &&
        address < symbols.AtomSymbolArenaLimit
      ) return true;
      if (
        ["AtomPendingAdd", "AtomPendingTake"].includes(entry) &&
        address >= symbols.AtomPendingArena &&
        address < symbols.AtomPendingArenaLimit
      ) return true;
      return false;
    };
    for (let address = 0; address < memory.length; address += 1) {
      if (!allowed(address)) {
        assert.equal(
          memory[address],
          beforeExecution[address],
          `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`,
        );
      }
    }
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      de: pair(runtime.cpu.d, runtime.cpu.e),
      bc: pair(runtime.cpu.b, runtime.cpu.c),
      instructions,
      cycles,
    };
  }

  function setKey(key) {
    assert.equal(key.length, 6);
    memory.set(key, symbols.AtomSymbolProofKey);
  }

  return {
    symbols,
    memory,
    statistics,
    restart,
    execute,
    reset({ symbolBytes = 64, pendingBytes = 24 } = {}) {
      restart();
      let result = execute("AtomSymbolReset", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolArena >>> 8;
        cpu.l = names.AtomSymbolArena & 0xff;
        const end = names.AtomSymbolArena + symbolBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomPendingReset", (_target, names, cpu) => {
        cpu.h = names.AtomPendingArena >>> 8;
        cpu.l = names.AtomPendingArena & 0xff;
        const end = names.AtomPendingArena + pendingBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      return result;
    },
    pack(text) {
      const bytes = new TextEncoder().encode(text);
      memory.fill(0, symbols.AtomSymbolProofText, symbols.AtomSymbolProofText + 10);
      memory.set(bytes.slice(0, 10), symbols.AtomSymbolProofText);
      memory.fill(0xa5, symbols.AtomSymbolProofKey, symbols.AtomSymbolProofKey + 6);
      const result = execute("AtomPackSymbol", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolProofText >>> 8;
        cpu.l = names.AtomSymbolProofText & 0xff;
        cpu.b = bytes.length;
        cpu.d = names.AtomSymbolProofKey >>> 8;
        cpu.e = names.AtomSymbolProofKey & 0xff;
      }, `AtomPackSymbol ${JSON.stringify(text)}`);
      return {
        ...result,
        key: Array.from(memory.slice(symbols.AtomSymbolProofKey, symbols.AtomSymbolProofKey + 6)),
      };
    },
    find(key) {
      setKey(key);
      return execute("AtomSymbolFind", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolProofKey >>> 8;
        cpu.l = names.AtomSymbolProofKey & 0xff;
      });
    },
    declare(key, value) {
      setKey(key);
      return execute("AtomSymbolDeclare", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolProofKey >>> 8;
        cpu.l = names.AtomSymbolProofKey & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      });
    },
    reference(key) {
      setKey(key);
      return execute("AtomSymbolReference", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolProofKey >>> 8;
        cpu.l = names.AtomSymbolProofKey & 0xff;
      });
    },
    declareGlobalLabel(key, value) {
      setKey(key);
      return execute("AtomSymbolDeclareGlobalLabel", (_target, names, cpu) => {
        cpu.h = names.AtomSymbolProofKey >>> 8;
        cpu.l = names.AtomSymbolProofKey & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      });
    },
    advanceScope() {
      return execute("AtomSymbolAdvanceScope");
    },
    pendingAdd(symbol, patch, kind, aux) {
      return execute("AtomPendingAdd", (_target, _names, cpu) => {
        cpu.ix = symbol;
        cpu.d = patch >>> 8;
        cpu.e = patch & 0xff;
        cpu.b = kind;
        cpu.c = aux;
      });
    },
    pendingTake(symbol) {
      return execute("AtomPendingTake", (_target, _names, cpu) => {
        cpu.ix = symbol;
      });
    },
    pendingPeek(symbol) {
      return execute("AtomPendingPeek", (_target, _names, cpu) => {
        cpu.ix = symbol;
      });
    },
    pendingCheckCapacity() {
      return execute("AtomPendingCheckCapacity");
    },
    word(address) {
      return memory[address] | (memory[address + 1] << 8);
    },
    stateWord(name) {
      return this.word(symbols[name]);
    },
    symbolRecord(address) {
      return Array.from(memory.slice(address, address + 8));
    },
    symbolArena() {
      return Array.from(memory.slice(symbols.AtomSymbolArena, symbols.AtomSymbolArenaLimit));
    },
    pendingArena() {
      return Array.from(memory.slice(symbols.AtomPendingArena, symbols.AtomPendingArenaLimit));
    },
  };
}
