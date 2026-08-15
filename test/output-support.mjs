import assert from "node:assert/strict";
import fs from "node:fs";

import { compile } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const addressOf = (symbol) => symbol.address ?? symbol.value;
const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2f.json", "utf8"));

export async function createOutputHarness({ contracts = "strict", auditEveryCall = false } = {}) {
  const assembled = await compile("asm/output-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: contracts,
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `output proof assembly failed: ${JSON.stringify(errors)}`);
  const hex = assembled.artifacts.find(({ kind }) => kind === "hex");
  const d8m = assembled.artifacts.find(({ kind }) => kind === "d8m");
  assert.equal(hex?.kind, "hex");
  assert.equal(d8m?.kind, "d8m");
  const symbols = Object.fromEntries(d8m.json.symbols.flatMap((symbol) => {
    const value = addressOf(symbol);
    return value === undefined ? [] : [[symbol.name, value]];
  }));
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomOutputReset);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutable = [
    [symbols.AtomEncoderCoreStart, symbols.AtomEncoderCoreEnd],
    [symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd],
    [symbols.AtomTokenizerCodeStart, symbols.AtomTokenizerCodeEnd],
    [symbols.AtomExpressionCodeStart, symbols.AtomExpressionCodeEnd],
    [symbols.AtomPatchCodeStart, symbols.AtomPatchCodeEnd],
    [symbols.AtomParserCodeStart, symbols.AtomParserCodeEnd],
    [symbols.AtomOutputCodeStart, symbols.AtomOutputCodeEnd],
    [symbols.AtomOutputProofAdapterStart, symbols.AtomOutputProofAdapterEnd],
  ].map(([start, end]) => ({ start, bytes: pristine.slice(start, end) }));
  const statistics = {};
  const audited = new Set();
  let sourceBytes = new Uint8Array();

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    sourceBytes = new Uint8Array();
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
    const budget = manifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      const step = runtime.step();
      instructions += 1;
      cycles += step.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.equal(memory[STACK_BEFORE], 0x87, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x78, `${label}: stack overrun`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    }
    for (const [name, expected] of [
      ["AtomOutputSourceBefore", 0x3c], ["AtomOutputSourceAfter", 0xc3],
      ["AtomOutputRecordBefore", 0x69], ["AtomOutputRecordAfter", 0x96],
      ["AtomOutputKeyBefore", 0xa6], ["AtomOutputKeyAfter", 0x6a],
      ["AtomOutputSymbolBefore", 0x39], ["AtomOutputSymbolAfter", 0x93],
      ["AtomOutputPendingBefore", 0x4b], ["AtomOutputPendingAfter", 0xb4],
      ["AtomOutputLogBefore", 0x5a], ["AtomOutputLogAfter", 0xa5],
    ]) assert.equal(memory[symbols[name]], expected, `${label}: ${name} changed`);
    assert.deepEqual(memory.slice(symbols.AtomOutputSource, symbols.AtomOutputSource + sourceBytes.length), sourceBytes, `${label}: source changed`);

    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;

    const outputSpecialPath = entry === "AtomOutputResolveSymbol" ||
      (entry === "AtomOutputEmitInstruction" && (runtime.cpu.flags.C || memory[symbols.AtomParserReferenceCount] > 0));
    if (auditEveryCall || outputSpecialPath || !audited.has(entry)) {
      const inside = (address, start, end) => address >= start && address < end;
      for (let address = 0; address < memory.length; address += 1) {
        const allowed =
          inside(address, symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd) ||
          inside(address, symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd) ||
          inside(address, symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd) ||
          inside(address, symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd) ||
          inside(address, symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd) ||
          inside(address, symbols.AtomOutputWorkspaceStart, symbols.AtomOutputWorkspaceEnd) ||
          inside(address, symbols.AtomOutputProofAdapterWorkspaceStart, symbols.AtomOutputProofAdapterWorkspaceEnd) ||
          (entry === "AtomPackSymbol" && inside(address, symbols.AtomOutputKey, symbols.AtomOutputKey + 6)) ||
          (["AtomSymbolDeclare", "AtomParserParse"].includes(entry) && inside(address, symbols.AtomOutputSymbolArena, symbols.AtomOutputSymbolLimit)) ||
          (entry === "AtomParserParse" && inside(address, symbols.AtomOutputRecord, symbols.AtomOutputRecord + 10)) ||
          (["AtomOutputEmitInstruction", "AtomOutputResolveSymbol"].includes(entry) && inside(address, symbols.AtomOutputPendingArena, symbols.AtomOutputPendingLimit)) ||
          (["AtomOutputEmitInstruction", "AtomOutputResolveSymbol"].includes(entry) && inside(address, symbols.AtomOutputProofLog, symbols.AtomOutputProofLogLimit)) ||
          (address > STACK_BEFORE && address < STACK_AFTER);
        if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
      }
      audited.add(entry);
    }
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      de: (runtime.cpu.d << 8) | runtime.cpu.e,
      hl: (runtime.cpu.h << 8) | runtime.cpu.l,
      b: runtime.cpu.b,
      c: runtime.cpu.c,
      instructions,
      cycles,
    };
  }

  function loadSource(source, part = 7) {
    const bytes = new TextEncoder().encode(source);
    memory.fill(0xa5, symbols.AtomOutputSource, symbols.AtomOutputSourceLimit);
    memory.set(bytes, symbols.AtomOutputSource);
    sourceBytes = bytes.slice();
    const result = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = part;
      cpu.h = names.AtomOutputSource >>> 8;
      cpu.l = names.AtomOutputSource & 0xff;
      const end = names.AtomOutputSource + bytes.length;
      cpu.d = end >>> 8;
      cpu.e = end & 0xff;
    });
    assert.equal(result.carry, 0);
  }

  function pack(name) {
    const bytes = new TextEncoder().encode(name);
    memory.fill(0xa5, symbols.AtomOutputSource, symbols.AtomOutputSourceLimit);
    memory.set(bytes, symbols.AtomOutputSource);
    sourceBytes = bytes.slice();
    const result = execute("AtomPackSymbol", (_memory, names, cpu) => {
      cpu.h = names.AtomOutputSource >>> 8;
      cpu.l = names.AtomOutputSource & 0xff;
      cpu.b = bytes.length;
      cpu.d = names.AtomOutputKey >>> 8;
      cpu.e = names.AtomOutputKey & 0xff;
    });
    assert.equal(result.carry, 0, name);
  }

  return {
    symbols,
    memory,
    statistics,
    execute,
    reset({ symbolBytes = 128, pendingBytes = 48, address = 0x4000, capacity = 0x100 } = {}) {
      restart();
      let result = execute("AtomSymbolReset", (_memory, names, cpu) => {
        cpu.h = names.AtomOutputSymbolArena >>> 8;
        cpu.l = names.AtomOutputSymbolArena & 0xff;
        const end = names.AtomOutputSymbolArena + symbolBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomPendingReset", (_memory, names, cpu) => {
        cpu.h = names.AtomOutputPendingArena >>> 8;
        cpu.l = names.AtomOutputPendingArena & 0xff;
        const end = names.AtomOutputPendingArena + pendingBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomProofSinkReset");
      assert.equal(result.carry, 0);
      result = execute("AtomOutputReset", (_memory, _names, cpu) => {
        cpu.h = address >>> 8;
        cpu.l = address & 0xff;
        cpu.d = capacity >>> 8;
        cpu.e = capacity & 0xff;
      });
      assert.equal(result.carry, 0);
    },
    parse(source, { address = 0x4000, part = 7 } = {}) {
      loadSource(source, part);
      memory.fill(0xa5, symbols.AtomOutputRecord, symbols.AtomOutputRecord + 10);
      return execute("AtomParserParse", (_memory, names, cpu) => {
        cpu.b = address >>> 8;
        cpu.c = address & 0xff;
        cpu.d = names.AtomOutputRecord >>> 8;
        cpu.e = names.AtomOutputRecord & 0xff;
      });
    },
    declare(name, value) {
      pack(name);
      return execute("AtomSymbolDeclare", (_memory, names, cpu) => {
        cpu.h = names.AtomOutputKey >>> 8;
        cpu.l = names.AtomOutputKey & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      });
    },
    emit() {
      return execute("AtomOutputEmitInstruction", (_memory, names, cpu) => {
        cpu.ix = names.AtomOutputRecord;
      });
    },
    resolve(symbol) {
      return execute("AtomOutputResolveSymbol", (_memory, _names, cpu) => {
        cpu.ix = symbol;
      });
    },
    pendingPeek(symbol) {
      return execute("AtomPendingPeek", (_memory, _names, cpu) => {
        cpu.ix = symbol;
      });
    },
    failSinkAfter(calls) {
      memory[symbols.AtomOutputProofFailAfter] = calls;
    },
    outputState() {
      return {
        cursor: word(memory, symbols.AtomOutputCursor),
        remaining: word(memory, symbols.AtomOutputRemaining),
      };
    },
    pendingRecords() {
      const end = word(memory, symbols.AtomPendingNext);
      const count = (end - symbols.AtomOutputPendingArena) / 6;
      return Array.from({ length: count }, (_, index) => Array.from(memory.slice(
        symbols.AtomOutputPendingArena + index * 6,
        symbols.AtomOutputPendingArena + (index + 1) * 6,
      )));
    },
    operations() {
      const end = word(memory, symbols.AtomOutputProofLogNext);
      const result = [];
      let cursor = symbols.AtomOutputProofLog;
      while (cursor < end) {
        const length = word(memory, cursor + 4);
        result.push({
          kind: memory[cursor],
          bank: memory[cursor + 1],
          address: word(memory, cursor + 2),
          bytes: Array.from(memory.slice(cursor + 6, cursor + 6 + length)),
        });
        cursor += 6 + length;
      }
      return result;
    },
  };
}
