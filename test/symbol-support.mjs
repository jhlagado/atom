import assert from "node:assert/strict";

import { compile } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const RETURN_SLOT = 0xfefe;
const RETURN_SENTINEL = 0x80fe;

const addressOf = (symbol) => symbol.address ?? symbol.value;
const pair = (high, low) => ((high & 0xff) << 8) | (low & 0xff);

export async function createSymbolHarness({ contracts = "strict" } = {}) {
  const assembled = await compile("asm/symbol-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: contracts,
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `symbol prototype assembly failed: ${JSON.stringify(errors)}`);
  const hex = assembled.artifacts.find(({ kind }) => kind === "hex");
  const d8m = assembled.artifacts.find(({ kind }) => kind === "d8m");
  assert.equal(hex?.kind, "hex");
  assert.equal(d8m?.kind, "d8m");

  const symbols = Object.fromEntries(
    d8m.json.symbols.flatMap((symbol) => {
      const value = addressOf(symbol);
      return value === undefined ? [] : [[symbol.name, value]];
    }),
  );
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomSymbolReset);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutableCode = pristine.slice(symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd);
  const fullMemoryAudited = new Set();
  const statistics = {};

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
  }

  function execute(entry, setup = () => {}, label = entry) {
    setup(memory, symbols, runtime.cpu);
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
    assert.deepEqual(
      memory.slice(symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd),
      immutableCode,
      `${label}: symbol code changed`,
    );
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
    if (!fullMemoryAudited.has(entry)) {
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
          ["AtomSymbolDeclare", "AtomSymbolReference"].includes(entry) &&
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
      fullMemoryAudited.add(entry);
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
