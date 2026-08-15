import assert from "node:assert/strict";
import fs from "node:fs";

import { compile } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const addressOf = (symbol) => symbol.address ?? symbol.value;
const pair = (high, low) => ((high & 0xff) << 8) | (low & 0xff);
const manifest = JSON.parse(fs.readFileSync("proofs/phase-2c.json", "utf8"));

export const PARSER_STATUS = Object.freeze({
  OK: 0,
  EOF: 1,
  LEXICAL: 2,
  EXPECTED_MNEMONIC: 3,
  UNKNOWN_MNEMONIC: 4,
  EXPECTED_OPERAND: 5,
  UNKNOWN_OPERAND: 6,
  EXPECTED_DELIMITER: 7,
  TOO_MANY_OPERANDS: 8,
  INVALID_FORM: 9,
  VALUE_RANGE: 10,
  RELATIVE_RANGE: 11,
  INTERNAL: 12,
});

export async function createParserHarness({ contracts = "strict" } = {}) {
  const assembled = await compile("asm/parser-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: contracts,
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `parser proof assembly failed: ${JSON.stringify(errors)}`);
  const hex = assembled.artifacts.find(({ kind }) => kind === "hex");
  const d8m = assembled.artifacts.find(({ kind }) => kind === "d8m");
  assert.equal(hex?.kind, "hex");
  assert.equal(d8m?.kind, "d8m");

  const symbols = Object.fromEntries(d8m.json.symbols.flatMap((symbol) => {
    const value = addressOf(symbol);
    return value === undefined ? [] : [[symbol.name, value]];
  }));
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomParserParse);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutable = [
    [symbols.AtomEncoderCoreStart, symbols.AtomEncoderCoreEnd],
    [symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd],
    [symbols.AtomTokenizerCodeStart, symbols.AtomTokenizerCodeEnd],
    [symbols.AtomParserCodeStart, symbols.AtomParserCodeEnd],
  ].map(([start, end]) => ({ start, bytes: pristine.slice(start, end) }));
  const fullMemoryAudited = new Set();
  const statistics = {};
  let sourceBytes = new Uint8Array();

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    sourceBytes = new Uint8Array();
  }

  function execute(entry, setup = () => {}, label = entry) {
    setup(memory, symbols, runtime.cpu);
    memory[STACK_BEFORE] = 0xa6;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x6a;
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const before = memory.slice();
    let instructions = 0;
    let cycles = 0;
    const recent = [];
    const budget = manifest.executionBudgets[entry];
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      recent.push(runtime.cpu.pc);
      if (recent.length > 16) recent.shift();
      const result = runtime.step();
      instructions += 1;
      cycles += result.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return; recent=${recent.map((pc) => pc.toString(16)).join(" ")}`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.equal(memory[STACK_BEFORE], 0xa6, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x6a, `${label}: stack overrun`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);

    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    }
    assert.equal(memory[symbols.AtomParserSourceBefore], 0x3c, `${label}: source underrun`);
    assert.equal(memory[symbols.AtomParserSourceAfter], 0xc3, `${label}: source overrun`);
    assert.deepEqual(memory.slice(symbols.AtomParserSource, symbols.AtomParserSource + sourceBytes.length), sourceBytes, `${label}: source changed`);
    assert.equal(memory[symbols.AtomParserRecordBefore], 0x69, `${label}: record underrun`);
    assert.equal(memory[symbols.AtomParserRecordAfter], 0x96, `${label}: record overrun`);
    assert.equal(memory[symbols.AtomParserOutputBefore], 0x5a, `${label}: output underrun`);
    assert.equal(memory[symbols.AtomParserOutputAfter], 0xa5, `${label}: output overrun`);

    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;

    if (!fullMemoryAudited.has(entry)) {
      for (let address = 0; address < memory.length; address += 1) {
        const inRange = (start, end) => address >= start && address < end;
        const allowed =
          inRange(symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd) ||
          inRange(symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd) ||
          inRange(symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd) ||
          (entry === "AtomParserParse" && inRange(symbols.AtomParserRecord, symbols.AtomParserRecord + 10)) ||
          (entry === "AtomEncode" && inRange(symbols.AtomParserOutput, symbols.AtomParserOutput + 4)) ||
          (address > STACK_BEFORE && address < STACK_AFTER);
        if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
      }
      fullMemoryAudited.add(entry);
    }

    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      de: pair(runtime.cpu.d, runtime.cpu.e),
      instructions,
      cycles,
    };
  }

  function load(source, part = 7) {
    restart();
    const bytes = new TextEncoder().encode(source);
    assert.ok(bytes.length <= symbols.AtomParserSourceLimit - symbols.AtomParserSource);
    memory.fill(0xa5, symbols.AtomParserSource, symbols.AtomParserSourceLimit);
    memory.set(bytes, symbols.AtomParserSource);
    sourceBytes = bytes.slice();
    const reset = execute("AtomTokenizerReset", (_memory, names, cpu) => {
      cpu.a = part;
      cpu.h = names.AtomParserSource >>> 8;
      cpu.l = names.AtomParserSource & 0xff;
      const end = names.AtomParserSource + bytes.length;
      cpu.d = end >>> 8;
      cpu.e = end & 0xff;
    }, `reset ${JSON.stringify(source.slice(0, 48))}`);
    assert.equal(reset.carry, 0);
  }

  return {
    symbols,
    memory,
    manifest,
    statistics,
    parse(source, { address = 0x4000, part = 7 } = {}) {
      load(source, part);
      memory.fill(0xa5, symbols.AtomParserRecord, symbols.AtomParserRecord + 10);
      const before = Array.from(memory.slice(symbols.AtomParserRecord, symbols.AtomParserRecord + 10));
      const result = execute("AtomParserParse", (_memory, names, cpu) => {
        cpu.b = address >>> 8;
        cpu.c = address & 0xff;
        cpu.d = names.AtomParserRecord >>> 8;
        cpu.e = names.AtomParserRecord & 0xff;
      }, `parse ${JSON.stringify(source.slice(0, 80))}`);
      return {
        ...result,
        before,
        record: Array.from(memory.slice(symbols.AtomParserRecord, symbols.AtomParserRecord + 10)),
        error: {
          status: memory[symbols.AtomParserErrorStatus],
          part: memory[symbols.AtomParserErrorPart],
          offset: memory[symbols.AtomParserErrorOffset] | (memory[symbols.AtomParserErrorOffset + 1] << 8),
        },
      };
    },
    encodeParsed(label = "parsed record") {
      memory.fill(0xa5, symbols.AtomParserOutput, symbols.AtomParserOutput + 4);
      const result = execute("AtomEncode", (_memory, names, cpu) => {
        cpu.ix = names.AtomParserRecord;
        cpu.d = names.AtomParserOutput >>> 8;
        cpu.e = names.AtomParserOutput & 0xff;
      }, `encode ${label}`);
      return { ...result, bytes: Array.from(memory.slice(symbols.AtomParserOutput, symbols.AtomParserOutput + result.status)) };
    },
  };
}
