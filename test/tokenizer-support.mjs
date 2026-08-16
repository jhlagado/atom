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
const proofManifest = JSON.parse(fs.readFileSync("proofs/phase-2b.json", "utf8"));

export const TOKEN = Object.freeze({
  EOF: 0,
  EOL: 1,
  NAME: 2,
  DIRECTIVE: 3,
  NUMBER: 4,
  STRING: 5,
  COMMA: 6,
  COLON: 7,
  LEFT_PAREN: 8,
  RIGHT_PAREN: 9,
  PLUS: 10,
  MINUS: 11,
  STAR: 12,
  SLASH: 13,
  PERCENT: 14,
  AMPERSAND: 15,
  CARET: 16,
  PIPE: 17,
  TILDE: 18,
  APOSTROPHE: 19,
  LEFT_SHIFT: 20,
  RIGHT_SHIFT: 21,
  CURRENT: 22,
});

export const TOKEN_STATUS = Object.freeze({
  INVALID_BYTE: 1,
  NAME_TOO_LONG: 2,
  INVALID_NUMBER: 3,
  NUMBER_OVERFLOW: 4,
  UNTERMINATED_STRING: 5,
  INVALID_ESCAPE: 6,
  STRING_TOO_LONG: 7,
  BAD_SOURCE_RANGE: 8,
  UNPROCESSED_DIRECTIVE: 9,
});

export async function createTokenizerHarness({ contracts = "strict" } = {}) {
  const assembled = await compile("asm/tokenizer-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: contracts,
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `tokenizer proof assembly failed: ${JSON.stringify(errors)}`);
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
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomTokenizerReset);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutable = [
    [symbols.AtomEncoderCoreStart, symbols.AtomEncoderCoreEnd],
    [symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd],
    [symbols.AtomTokenizerCodeStart, symbols.AtomTokenizerCodeEnd],
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

  function tokenRecord() {
    const start = symbols.AtomTokenRecord;
    const bytes = Array.from(memory.slice(start, start + symbols.AtomTokenRecordBytes));
    return {
      bytes,
      kind: bytes[0],
      part: bytes[1],
      offset: bytes[2] | (bytes[3] << 8),
      pointer: bytes[4] | (bytes[5] << 8),
      length: bytes[6],
      value: bytes[7] | (bytes[8] << 8),
    };
  }

  function execute(entry, setup = () => {}, label = entry) {
    setup(memory, symbols, runtime.cpu);
    memory[STACK_BEFORE] = 0xa6;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x6a;
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    runtime.cpu.iy = 0x6d92;
    const beforeExecution = memory.slice();
    let instructions = 0;
    let cycles = 0;
    const recentPcs = [];
    const budget = proofManifest.executionBudgets[entry];
    const maxInstructions = budget?.maxInstructions ?? 30_000;
    const maxCycles = budget?.maxCycles ?? 400_000;
    while (
      runtime.cpu.pc !== RETURN_SENTINEL &&
      instructions < maxInstructions &&
      cycles <= maxCycles
    ) {
      recentPcs.push(runtime.cpu.pc);
      if (recentPcs.length > 16) recentPcs.shift();
      const result = runtime.step();
      cycles += result.cycles ?? 0;
      instructions += 1;
    }
    assert.equal(
      runtime.cpu.pc,
      RETURN_SENTINEL,
      `${label}: did not return; recent=${recentPcs.map((pc) => pc.toString(16)).join(" ")}`,
    );
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.equal(memory[STACK_BEFORE], 0xa6, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x6a, `${label}: stack overrun`);
    if (budget) {
      assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
      assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    }
    assert.equal(runtime.cpu.iy, 0x6d92, `${label}: IY changed`);
    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: code changed`);
    }
    assert.equal(memory[symbols.AtomTokenizerSourceBefore], 0x3c, `${label}: source underrun`);
    assert.equal(memory[symbols.AtomTokenizerSourceAfter], 0xc3, `${label}: source overrun`);
    assert.deepEqual(
      memory.slice(symbols.AtomTokenizerSource, symbols.AtomTokenizerSource + sourceBytes.length),
      sourceBytes,
      `${label}: source changed`,
    );

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
      for (let address = 0; address < memory.length; address += 1) {
        const allowedWorkspace =
          address >= symbols.AtomTokenizerWorkspaceStart && address < symbols.AtomTokenizerWorkspaceEnd;
        const allowedEncoderWorkspace =
          entry === "AtomRecognizeMnemonic" &&
          address >= symbols.AtomEncoderWorkspaceStart && address < symbols.AtomEncoderWorkspaceEnd;
        const allowedStack = address > STACK_BEFORE && address < STACK_AFTER;
        if (!allowedWorkspace && !allowedEncoderWorkspace && !allowedStack) {
          assert.equal(memory[address], beforeExecution[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
        }
      }
      fullMemoryAudited.add(entry);
    }

    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      sp: runtime.cpu.sp,
      instructions,
      cycles,
      record: tokenRecord(),
    };
  }

  function loadSource(source) {
    const bytes = typeof source === "string" ? new TextEncoder().encode(source) : Uint8Array.from(source);
    assert.ok(bytes.length <= symbols.AtomTokenizerSourceLimit - symbols.AtomTokenizerSource);
    memory.fill(0xa5, symbols.AtomTokenizerSource, symbols.AtomTokenizerSourceLimit);
    memory.set(bytes, symbols.AtomTokenizerSource);
    sourceBytes = bytes.slice();
    return bytes;
  }

  return {
    symbols,
    memory,
    proofManifest,
    statistics,
    restart,
    execute,
    record: tokenRecord,
    reset(source, { part = 7 } = {}) {
      restart();
      const bytes = loadSource(source);
      const result = execute("AtomTokenizerReset", (_target, names, cpu) => {
        cpu.a = part;
        cpu.h = names.AtomTokenizerSource >>> 8;
        cpu.l = names.AtomTokenizerSource & 0xff;
        const end = names.AtomTokenizerSource + bytes.length;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      }, `AtomTokenizerReset part=${part} bytes=${bytes.length}`);
      assert.equal(result.carry, 0);
      assert.equal(result.status, 0);
      return result;
    },
    resetRange(start, end, part = 7) {
      return execute("AtomTokenizerReset", (_target, _names, cpu) => {
        cpu.a = part;
        cpu.h = start >>> 8;
        cpu.l = start & 0xff;
        cpu.d = end >>> 8;
        cpu.e = end & 0xff;
      }, `AtomTokenizerReset $${start.toString(16)}..$${end.toString(16)}`);
    },
    next(label = "AtomTokenizerNext") {
      const before = tokenRecord().bytes;
      const result = execute("AtomTokenizerNext", undefined, label);
      if (result.carry) assert.deepEqual(result.record.bytes, before, `${label}: failed token was published`);
      return result;
    },
    recognize(record) {
      return execute("AtomRecognizeMnemonic", (_target, _names, cpu) => {
        cpu.h = record.pointer >>> 8;
        cpu.l = record.pointer & 0xff;
        cpu.b = record.length;
      }, `AtomRecognizeMnemonic token@${record.offset}`);
    },
    classify(entry, value) {
      return execute(entry, (_target, _names, cpu) => {
        cpu.a = value;
      }, `${entry} $${value.toString(16).padStart(2, "0")}`);
    },
    lexeme(record) {
      return new TextDecoder().decode(memory.slice(record.pointer, record.pointer + record.length));
    },
    errorPosition() {
      return {
        status: memory[symbols.AtomTokenErrorStatus],
        part: memory[symbols.AtomTokenErrorPart],
        offset: pair(memory[symbols.AtomTokenErrorOffset + 1], memory[symbols.AtomTokenErrorOffset]),
      };
    },
    tokenize(source, options) {
      this.reset(source, options);
      const tokens = [];
      while (tokens.length < 2048) {
        const result = this.next(`AtomTokenizerNext token=${tokens.length}`);
        if (result.carry) return { tokens, error: result };
        tokens.push({ ...result.record, lexeme: this.lexeme(result.record) });
        if (result.record.kind === TOKEN.EOF) return { tokens };
      }
      assert.fail("tokenizer did not reach EOF");
    },
  };
}
