import assert from "node:assert/strict";
import fs from "node:fs";

import { compile } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const addressOf = (symbol) => symbol.address ?? symbol.value;
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2g.json", "utf8"));

export async function createStatementsHarness() {
  const assembled = await compile("asm/statements-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: "strict",
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `statement proof assembly failed: ${JSON.stringify(errors)}`);
  const hex = assembled.artifacts.find(({ kind }) => kind === "hex");
  const d8m = assembled.artifacts.find(({ kind }) => kind === "d8m");
  assert.equal(hex?.kind, "hex");
  assert.equal(d8m?.kind, "d8m");
  const symbols = Object.fromEntries(d8m.json.symbols.flatMap((symbol) => {
    const value = addressOf(symbol);
    return value === undefined ? [] : [[symbol.name, value]];
  }));
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomTokenizerReset);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutable = [
    [symbols.AtomEncoderCoreStart, symbols.AtomEncoderCoreEnd],
    [symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd],
    [symbols.AtomTokenizerCodeStart, symbols.AtomTokenizerCodeEnd],
    [symbols.AtomExpressionCodeStart, symbols.AtomExpressionCodeEnd],
    [symbols.AtomPatchCodeStart, symbols.AtomPatchCodeEnd],
    [symbols.AtomParserCodeStart, symbols.AtomParserCodeEnd],
  ].map(([start, end]) => ({ start, bytes: pristine.slice(start, end) }));
  const statistics = {};
  let sourceBytes = new Uint8Array();

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    sourceBytes = new Uint8Array();
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
    const budget = manifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    let instructions = 0;
    let cycles = 0;
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
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
        (entry === "AtomParserParsePublished" && inside(address, symbols.AtomStatementRecord, symbols.AtomStatementRecord + 10)) ||
        (address > STACK_BEFORE && address < STACK_AFTER);
      if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
    }
    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      instructions,
      cycles,
    };
  }

  function installSource(source) {
    const bytes = new TextEncoder().encode(source);
    memory.fill(0xa5, symbols.AtomStatementSource, symbols.AtomStatementSourceLimit);
    memory.set(bytes, symbols.AtomStatementSource);
    sourceBytes = bytes.slice();
    const result = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = 7;
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
