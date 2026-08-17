import assert from "node:assert/strict";
import fs from "node:fs";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2g.json", "utf8"));

const PROOF_SYMBOLS = Object.freeze({
  AtomStatementProofAdapterWorkspaceStart: 0x6000,
  AtomStatementProofLogNext: 0x6000,
  AtomStatementProofFailAfter: 0x6002,
  AtomStatementProofAdapterWorkspaceEnd: 0x600a,
  AtomStatementProofSourceStart: 0x8000,
  AtomStatementSourceBefore: 0x8000,
  AtomStatementSource: 0x8001,
  AtomStatementSourceLimit: 0x8081,
  AtomStatementSourceAfter: 0x8081,
  AtomStatementProofSourceEnd: 0x8082,
  AtomStatementProofRecordStart: 0x8082,
  AtomStatementRecordBefore: 0x8082,
  AtomStatementRecord: 0x8083,
  AtomStatementRecordAfter: 0x808d,
  AtomStatementProofRecordEnd: 0x808e,
  AtomStatementProofSymbolStart: 0x9000,
  AtomStatementSymbolBefore: 0x9000,
  AtomStatementSymbolArena: 0x9001,
  AtomStatementSymbolLimit: 0x9081,
  AtomStatementSymbolAfter: 0x9081,
  AtomStatementProofSymbolEnd: 0x9082,
  AtomStatementProofPendingStart: 0x9100,
  AtomStatementPendingBefore: 0x9100,
  AtomStatementPendingArena: 0x9101,
  AtomStatementPendingLimit: 0x9131,
  AtomStatementPendingAfter: 0x9131,
  AtomStatementProofPendingEnd: 0x9132,
  AtomStatementProofLogStart: 0x9200,
  AtomStatementLogBefore: 0x9200,
  AtomStatementProofLog: 0x9201,
  AtomStatementProofLogLimit: 0x9301,
  AtomStatementLogAfter: 0x9301,
  AtomStatementProofLogEnd: 0x9302,
});

export async function createStatementsHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.atm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), symbols.AtomTokenizerReset);
  const memory = runtime.hardware.memory;
  for (const [name, value] of [
    ["AtomStatementSourceBefore", 0x3c], ["AtomStatementSourceAfter", 0xc3],
    ["AtomStatementRecordBefore", 0x69], ["AtomStatementRecordAfter", 0x96],
    ["AtomStatementSymbolBefore", 0x39], ["AtomStatementSymbolAfter", 0x93],
    ["AtomStatementPendingBefore", 0x4b], ["AtomStatementPendingAfter", 0xb4],
    ["AtomStatementLogBefore", 0x5a], ["AtomStatementLogAfter", 0xa5],
  ]) memory[symbols[name]] = value;
  const pristine = memory.slice();
  const immutable = core.codeRanges.map(({ start, end }) => ({ start, bytes: pristine.slice(start, end) }));
  const statistics = {};
  let sourceBytes = new Uint8Array();
  let restartCount = 0;
  let interceptedWrites = null;

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
      [symbols.AtomOutputWorkspaceStart, symbols.AtomOutputWorkspaceEnd],
      [symbols.AtomStatementWorkspaceStart, symbols.AtomStatementWorkspaceEnd],
      [symbols.AtomStatementProofAdapterWorkspaceStart, symbols.AtomStatementProofAdapterWorkspaceEnd],
    ]) {
      for (let address = start; address < end; address += 1) {
        memory[address] = (restartCount * 73 + address * 29) & 0xff;
      }
    }
  }

  function resetSink() {
    memory[symbols.AtomStatementProofLogNext] = symbols.AtomStatementProofLog & 0xff;
    memory[symbols.AtomStatementProofLogNext + 1] = symbols.AtomStatementProofLog >>> 8;
    memory[symbols.AtomStatementProofFailAfter] = 0;
  }

  function appendOperation(kind, bank, address, bytes) {
    const writeByte = (target, value) => {
      assert.ok(interceptedWrites, "sink write outside an executing native entry");
      memory[target] = value;
      interceptedWrites.add(target);
    };
    let failAfter = memory[symbols.AtomStatementProofFailAfter];
    if (failAfter !== 0) {
      failAfter -= 1;
      writeByte(symbols.AtomStatementProofFailAfter, failAfter);
      if (failAfter === 0) return 0xe1;
    }
    const next = word(memory, symbols.AtomStatementProofLogNext);
    const required = 6 + bytes.length;
    if (next > symbols.AtomStatementProofLogLimit || symbols.AtomStatementProofLogLimit - next < required) return 0xe2;
    for (const [offset, value] of [kind, bank, address & 0xff, address >>> 8, bytes.length, 0, ...bytes].entries()) {
      writeByte(next + offset, value);
    }
    const end = next + required;
    writeByte(symbols.AtomStatementProofLogNext, end & 0xff);
    writeByte(symbols.AtomStatementProofLogNext + 1, end >>> 8);
    return 0;
  }

  function interceptService() {
    const { cpu } = runtime;
    let status;
    if (cpu.pc === symbols.AtomSinkImageByte) {
      status = appendOperation(1, cpu.c, (cpu.h << 8) | cpu.l, [cpu.a]);
    } else if (cpu.pc === symbols.AtomSinkPatchByte) {
      status = appendOperation(2, cpu.c, (cpu.h << 8) | cpu.l, [cpu.a]);
    } else if (cpu.pc === symbols.AtomSinkPatchWord) {
      status = appendOperation(2, cpu.c, (cpu.d << 8) | cpu.e, [cpu.l, cpu.h]);
    } else {
      return false;
    }
    const returnAddress = word(memory, cpu.sp);
    cpu.sp = (cpu.sp + 2) & 0xffff;
    cpu.pc = returnAddress;
    cpu.a = status;
    cpu.flags.C = status === 0 ? 0 : 1;
    return true;
  }

  function execute(entry, setup = () => {}, label = entry) {
    assert.ok(symbols[entry] !== undefined, `missing statement proof entry ${entry}`);
    setup(memory, symbols, runtime.cpu);
    memory[STACK_BEFORE] = 0x87;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x78;
    const before = memory.slice();
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const serviceWrites = new Set();
    interceptedWrites = serviceWrites;
    const budget = manifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    let instructions = 0;
    let cycles = 0;
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      if (interceptService()) continue;
      const step = runtime.step();
      instructions += 1;
      cycles += step.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    assert.equal(memory[STACK_BEFORE], 0x87, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x78, `${label}: stack overrun`);
    assert.equal(memory[symbols.AtomStatementSourceBefore], 0x3c, `${label}: source-before canary`);
    assert.equal(memory[symbols.AtomStatementSourceAfter], 0xc3, `${label}: source-after canary`);
    assert.equal(memory[symbols.AtomStatementRecordBefore], 0x69, `${label}: record-before canary`);
    assert.equal(memory[symbols.AtomStatementRecordAfter], 0x96, `${label}: record-after canary`);
    assert.equal(memory[symbols.AtomStatementSymbolBefore], 0x39, `${label}: symbol-before canary`);
    assert.equal(memory[symbols.AtomStatementSymbolAfter], 0x93, `${label}: symbol-after canary`);
    assert.equal(memory[symbols.AtomStatementPendingBefore], 0x4b, `${label}: pending-before canary`);
    assert.equal(memory[symbols.AtomStatementPendingAfter], 0xb4, `${label}: pending-after canary`);
    assert.equal(memory[symbols.AtomStatementLogBefore], 0x5a, `${label}: log-before canary`);
    assert.equal(memory[symbols.AtomStatementLogAfter], 0xa5, `${label}: log-after canary`);
    assert.deepEqual(memory.slice(symbols.AtomStatementSource, symbols.AtomStatementSource + sourceBytes.length), sourceBytes, `${label}: source changed`);
    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    }
    const inside = (address, start, end) => address >= start && address < end;
    for (let address = 0; address < memory.length; address += 1) {
      const allowed =
        inside(address, symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd) ||
        inside(address, symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd) ||
        inside(address, symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd) ||
        inside(address, symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd) ||
        inside(address, symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd) ||
        inside(address, symbols.AtomOutputWorkspaceStart, symbols.AtomOutputWorkspaceEnd) ||
        inside(address, symbols.AtomStatementWorkspaceStart, symbols.AtomStatementWorkspaceEnd) ||
        serviceWrites.has(address) ||
        (entry === "AtomPackSymbol" && inside(address, symbols.AtomStatementRecord, symbols.AtomStatementRecord + 6)) ||
        (["AtomSymbolDeclare", "AtomSymbolReference", "AtomSymbolDeclareGlobalLabel"].includes(entry) &&
          inside(address, symbols.AtomStatementSymbolArena, symbols.AtomStatementSymbolLimit)) ||
        (entry === "AtomPendingAdd" && inside(address, symbols.AtomStatementPendingArena, symbols.AtomStatementPendingLimit)) ||
        (entry === "AtomAssemblePart" && inside(address, symbols.AtomStatementSymbolArena, symbols.AtomStatementSymbolLimit)) ||
        (entry === "AtomAssemblePart" && inside(address, symbols.AtomStatementPendingArena, symbols.AtomStatementPendingLimit)) ||
        (entry === "AtomParserParsePublished" && inside(address, symbols.AtomStatementRecord, symbols.AtomStatementRecord + 10)) ||
        (address > STACK_BEFORE && address < STACK_AFTER);
      if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
    }
    interceptedWrites = null;
    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      detail: symbols.AtomStatementDetail === undefined ? undefined : memory[symbols.AtomStatementDetail],
      instructions,
      cycles,
    };
  }

  function installSource(source, part = 7) {
    const bytes = new TextEncoder().encode(source);
    memory.fill(0xa5, symbols.AtomStatementSource, symbols.AtomStatementSourceLimit);
    memory.set(bytes, symbols.AtomStatementSource);
    sourceBytes = bytes.slice();
    const result = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = part;
      cpu.h = names.AtomStatementSource >>> 8;
      cpu.l = names.AtomStatementSource & 0xff;
      const end = names.AtomStatementSource + bytes.length;
      cpu.d = end >>> 8;
      cpu.e = end & 0xff;
    });
    assert.equal(result.carry, 0);
  }

  return {
    symbols,
    memory,
    statistics,
    reset({ symbolBytes = 128, pendingBytes = 48 } = {}) {
      restart();
      let result = execute("AtomSymbolReset", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementSymbolArena >>> 8;
        cpu.l = names.AtomStatementSymbolArena & 0xff;
        const end = names.AtomStatementSymbolArena + symbolBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
      result = execute("AtomPendingReset", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementPendingArena >>> 8;
        cpu.l = names.AtomStatementPendingArena & 0xff;
        const end = names.AtomStatementPendingArena + pendingBytes;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      });
      assert.equal(result.carry, 0);
    },
    resetAssembly({ symbolBytes = 128, pendingBytes = 48, address = 0x4000, capacity = 0x100 } = {}) {
      this.reset({ symbolBytes, pendingBytes });
      resetSink();
      const result = execute("AtomOutputReset", (_memory, _names, cpu) => {
        cpu.h = address >>> 8;
        cpu.l = address & 0xff;
        cpu.d = capacity >>> 8;
        cpu.e = capacity & 0xff;
      });
      assert.equal(result.carry, 0);
    },
    pack(name) {
      const bytes = new TextEncoder().encode(name);
      memory.fill(0xa5, symbols.AtomStatementSource, symbols.AtomStatementSourceLimit);
      memory.set(bytes, symbols.AtomStatementSource);
      sourceBytes = bytes.slice();
      memory.fill(0xa5, symbols.AtomStatementRecord, symbols.AtomStatementRecord + 6);
      const result = execute("AtomPackSymbol", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementSource >>> 8;
        cpu.l = names.AtomStatementSource & 0xff;
        cpu.b = bytes.length;
        cpu.d = names.AtomStatementRecord >>> 8;
        cpu.e = names.AtomStatementRecord & 0xff;
      }, `AtomPackSymbol ${name}`);
      return { ...result, key: Array.from(memory.slice(symbols.AtomStatementRecord, symbols.AtomStatementRecord + 6)) };
    },
    find(key) {
      memory.set(key, symbols.AtomStatementRecord);
      return execute("AtomSymbolFind", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementRecord >>> 8;
        cpu.l = names.AtomStatementRecord & 0xff;
      });
    },
    declare(key, value) {
      memory.set(key, symbols.AtomStatementRecord);
      return execute("AtomSymbolDeclare", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementRecord >>> 8;
        cpu.l = names.AtomStatementRecord & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      });
    },
    reference(key) {
      memory.set(key, symbols.AtomStatementRecord);
      return execute("AtomSymbolReference", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementRecord >>> 8;
        cpu.l = names.AtomStatementRecord & 0xff;
      });
    },
    declareGlobalLabel(key, value) {
      memory.set(key, symbols.AtomStatementRecord);
      return execute("AtomSymbolDeclareGlobalLabel", (_memory, names, cpu) => {
        cpu.h = names.AtomStatementRecord >>> 8;
        cpu.l = names.AtomStatementRecord & 0xff;
        cpu.d = value >>> 8;
        cpu.e = value & 0xff;
      });
    },
    advanceScope() {
      return execute("AtomSymbolAdvanceScope");
    },
    pendingAdd(symbol, patch, kind = 1, aux = 0) {
      return execute("AtomPendingAdd", (_memory, _names, cpu) => {
        cpu.ix = symbol;
        cpu.d = patch >>> 8;
        cpu.e = patch & 0xff;
        cpu.b = kind;
        cpu.c = aux;
      });
    },
    stateWord(name) {
      return word(memory, symbols[name]);
    },
    symbolArena() {
      return Array.from(memory.slice(symbols.AtomStatementSymbolArena, symbols.AtomStatementSymbolLimit));
    },
    pendingArena() {
      return Array.from(memory.slice(symbols.AtomStatementPendingArena, symbols.AtomStatementPendingLimit));
    },
    assemblePart(source, { part = 7 } = {}) {
      installSource(source, part);
      return execute("AtomAssemblePart", () => {}, `AtomAssemblePart ${JSON.stringify(source)}`);
    },
    assemble(source, options = {}) {
      this.resetAssembly(options);
      return this.assemblePart(source, options);
    },
    operations() {
      const operations = [];
      let cursor = symbols.AtomStatementProofLog;
      const end = word(memory, symbols.AtomStatementProofLogNext);
      while (cursor < end) {
        const kind = memory[cursor];
        const bank = memory[cursor + 1];
        const address = word(memory, cursor + 2);
        const length = word(memory, cursor + 4);
        operations.push({ kind, bank, address, bytes: Array.from(memory.slice(cursor + 6, cursor + 6 + length)) });
        cursor += 6 + length;
      }
      assert.equal(cursor, end, "misaligned statement proof log");
      return operations;
    },
    finalBytes(start = 0x4000) {
      const bytes = new Map();
      for (const operation of this.operations()) {
        for (const [offset, byte] of operation.bytes.entries()) bytes.set((operation.address + offset) & 0xffff, byte);
      }
      const addresses = [...bytes.keys()].filter((address) => address >= start).sort((left, right) => left - right);
      if (addresses.length === 0) return [];
      const end = addresses.at(-1) + 1;
      return Array.from({ length: end - start }, (_, offset) => bytes.get(start + offset) ?? 0);
    },
    outputState() {
      return {
        cursor: word(memory, symbols.AtomOutputCursor),
        remaining: word(memory, symbols.AtomOutputRemaining),
      };
    },
    pendingCheckCapacity() {
      return execute("AtomPendingCheckCapacity");
    },
    outputCheckCapacity(count) {
      return execute("AtomOutputCheckCapacity", (_memory, _names, cpu) => {
        cpu.h = count >>> 8;
        cpu.l = count & 0xff;
      });
    },
    outputEmitByte(value) {
      return execute("AtomOutputEmitByte", (_memory, _names, cpu) => {
        cpu.a = value;
      });
    },
    outputEmitWord(value) {
      return execute("AtomOutputEmitWord", (_memory, _names, cpu) => {
        cpu.h = value >>> 8;
        cpu.l = value & 0xff;
      });
    },
    outputReserve(count) {
      return execute("AtomOutputReserve", (_memory, _names, cpu) => {
        cpu.h = count >>> 8;
        cpu.l = count & 0xff;
      });
    },
    outputSetOrigin(address) {
      return execute("AtomOutputSetOrigin", (_memory, _names, cpu) => {
        cpu.h = address >>> 8;
        cpu.l = address & 0xff;
      });
    },
    parsePublished(source, { address = 0x4000 } = {}) {
      restart();
      installSource(source);
      let token = execute("AtomTokenizerNext");
      assert.equal(token.carry, 0);
      const mnemonic = execute("AtomRecognizeMnemonic", (_memory, names, cpu) => {
        const lexeme = _memory[names.AtomTokenRecord + names.AtomTokenLexemeOffset] |
          (_memory[names.AtomTokenRecord + names.AtomTokenLexemeOffset + 1] << 8);
        cpu.h = lexeme >>> 8;
        cpu.l = lexeme & 0xff;
        cpu.b = _memory[names.AtomTokenRecord + names.AtomTokenLengthOffset];
      });
      assert.equal(mnemonic.carry, 0);
      token = execute("AtomTokenizerNext");
      assert.equal(token.carry, 0);
      memory.fill(0xa5, symbols.AtomStatementRecord, symbols.AtomStatementRecord + 10);
      return execute("AtomParserParsePublished", (_memory, names, cpu) => {
        cpu.a = mnemonic.status;
        cpu.b = address >>> 8;
        cpu.c = address & 0xff;
        cpu.d = names.AtomStatementRecord >>> 8;
        cpu.e = names.AtomStatementRecord & 0xff;
      });
    },
    record() {
      return Array.from(memory.slice(symbols.AtomStatementRecord, symbols.AtomStatementRecord + 10));
    },
  };
}
