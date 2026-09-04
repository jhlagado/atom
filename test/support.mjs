import assert from "node:assert/strict";
import fs from "node:fs";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const STACK_RETURN_SLOT = 0xfefe;
const RETURN_SENTINEL = 0x80fe;
const proofManifest = JSON.parse(fs.readFileSync("proofs/phase-1.json", "utf8"));
const PROOF_SYMBOLS = Object.freeze({
  AtomHarnessInputBefore: 0x7fff,
  AtomHarnessInput: 0x8000,
  AtomHarnessInputAfter: 0x800a,
  AtomHarnessOutputBefore: 0x800f,
  AtomHarnessOutput: 0x8010,
  AtomHarnessOutputAfter: 0x8017,
  AtomHarnessTextBefore: 0x801f,
  AtomHarnessText: 0x8020,
  AtomHarnessTextAfter: 0x8029,
});

function hex(value, width = 4) {
  return `$${value.toString(16).padStart(width, "0").toUpperCase()}`;
}

function pair(high, low) {
  return ((high & 0xff) << 8) | (low & 0xff);
}

export async function createHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.asm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const program = parseIntelHex(core.hexText);
  const runtime = createZ80Runtime(program, symbols.AtomEncode);
  const memory = runtime.hardware.memory;
  memory[symbols.AtomHarnessOutputBefore] = 0x3c;
  memory.fill(0xa5, symbols.AtomHarnessOutput, symbols.AtomHarnessOutput + 7);
  memory[symbols.AtomHarnessOutputAfter] = 0xc3;
  memory[symbols.AtomHarnessInputBefore] = 0x5a;
  memory[symbols.AtomHarnessInputAfter] = 0xa5;
  memory[symbols.AtomHarnessTextBefore] = 0x69;
  memory[symbols.AtomHarnessTextAfter] = 0x96;
  const pristineMemory = memory.slice();
  const fullMemoryAudited = new Set();
  let invocation = 0;

  function resetMachine() {
    memory.set(pristineMemory);
    runtime.reset();
    runtime.cpu.halted = false;
  }

  const statistics = {};

  function executeUntil(entry, stopPc, label) {
    const budget = proofManifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    let instructions = 0;
    let cycles = 0;
    const recentPcs = [];
    while (
      runtime.cpu.pc !== stopPc &&
      instructions < budget.maxInstructions &&
      cycles <= budget.maxCycles
    ) {
      recentPcs.push(runtime.cpu.pc);
      if (recentPcs.length > 16) recentPcs.shift();
      const result = runtime.step();
      cycles += result.cycles ?? 0;
      instructions += 1;
    }
    assert.equal(
      runtime.cpu.pc,
      stopPc,
      `${label} exceeded budget: PC=${hex(runtime.cpu.pc)} SP=${hex(runtime.cpu.sp)} ` +
        `instructions=${instructions} cycles=${cycles} recent=${recentPcs.map((pc) => hex(pc)).join(" ")}`,
    );
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    const observed = statistics[entry] ?? {
      instructions: 0,
      cycles: 0,
      instructionCase: "",
      cycleCase: "",
    };
    if (instructions > observed.instructions) {
      observed.instructions = instructions;
      observed.instructionCase = label;
    }
    if (cycles > observed.cycles) {
      observed.cycles = cycles;
      observed.cycleCase = label;
    }
    statistics[entry] = observed;
    return { instructions, cycles, recentPcs };
  }

  function direct(entry, setup, label = entry) {
    resetMachine();
    invocation += 1;
    for (let address = symbols.AtomEncoderWorkspaceStart; address < symbols.AtomEncoderWorkspaceEnd; address += 1) {
      memory[address] = (invocation * 73 + address * 29) & 0xff;
    }
    setup(memory, symbols, runtime.cpu);
    const inputBefore = memory.slice(symbols.AtomHarnessInput, symbols.AtomHarnessInput + 10);
    const textBefore = memory.slice(symbols.AtomHarnessText, symbols.AtomHarnessText + 9);
    const immutableBefore = core.codeRanges.map(({ start, end }) => memory.slice(start, end));
    const beforeExecution = memory.slice();
    const iyBefore = runtime.cpu.iy;
    const ixBefore = runtime.cpu.ix;
    const cBefore = runtime.cpu.c;
    memory[STACK_RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[STACK_RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    runtime.cpu.sp = STACK_RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const execution = executeUntil(entry, RETURN_SENTINEL, label);

    assert.equal(runtime.cpu.sp, STACK_RETURN_SLOT + 2, `${label}: stack was not balanced`);
    assert.equal(runtime.cpu.iy, iyBefore, `${label}: IY was not preserved`);
    if (entry !== "AtomRadix40Pack" && entry !== "AtomRecognizeMnemonic") {
      assert.equal(runtime.cpu.ix, ixBefore, `${label}: IX was not preserved`);
    }
    if (entry === "AtomFormLength") {
      assert.equal(runtime.cpu.c, cBefore, `${label}: C was not preserved`);
    }
    assert.equal(memory[symbols.AtomHarnessOutputBefore], 0x3c, `${label}: output underrun`);
    assert.equal(memory[symbols.AtomHarnessOutputAfter], 0xc3, `${label}: output overrun`);
    assert.equal(memory[symbols.AtomHarnessInputBefore], 0x5a, `${label}: input underrun`);
    assert.equal(memory[symbols.AtomHarnessInputAfter], 0xa5, `${label}: input overrun`);
    assert.equal(memory[symbols.AtomHarnessTextBefore], 0x69, `${label}: text underrun`);
    assert.equal(memory[symbols.AtomHarnessTextAfter], 0x96, `${label}: text overrun`);
    for (const [index, { start, end }] of core.codeRanges.entries()) {
      assert.deepEqual(
        memory.slice(start, end),
        immutableBefore[index],
        `${label}: resident code or immutable data changed`,
      );
    }
    assert.deepEqual(
      memory.slice(symbols.AtomHarnessInput, symbols.AtomHarnessInput + 10),
      inputBefore,
      `${label}: parsed input record changed`,
    );
    assert.deepEqual(
      memory.slice(symbols.AtomHarnessText, symbols.AtomHarnessText + 9),
      textBefore,
      `${label}: source text changed`,
    );
    if (!fullMemoryAudited.has(entry)) {
      for (let address = 0; address < memory.length; address += 1) {
        const allowedWorkspace =
          address >= symbols.AtomEncoderWorkspaceStart && address < symbols.AtomEncoderWorkspaceEnd;
        const allowedOutput =
          address >= symbols.AtomHarnessOutput && address < symbols.AtomHarnessOutput + 7;
        const allowedStack = address >= 0xfe00 && address < 0xff00;
        if (!allowedWorkspace && !allowedOutput && !allowedStack) {
          assert.equal(
            memory[address],
            beforeExecution[address],
            `${label}: unexpected write at ${hex(address)}`,
          );
        }
      }
      fullMemoryAudited.add(entry);
    }

    return {
      value: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      de: pair(runtime.cpu.d, runtime.cpu.e),
      ix: runtime.cpu.ix,
      iy: runtime.cpu.iy,
      sp: runtime.cpu.sp,
      pc: runtime.cpu.pc,
      output: Array.from(memory.slice(symbols.AtomHarnessOutput, symbols.AtomHarnessOutput + 7)),
      inputBefore: Array.from(inputBefore),
      inputAfter: Array.from(memory.slice(symbols.AtomHarnessInput, symbols.AtomHarnessInput + 10)),
      textBefore: Array.from(textBefore),
      textAfter: Array.from(memory.slice(symbols.AtomHarnessText, symbols.AtomHarnessText + 9)),
      ...execution,
    };
  }

  const copyRecord = (record) => (target, names, cpu) => {
    target.set(record, names.AtomHarnessInput);
    cpu.ix = names.AtomHarnessInput;
    cpu.iy = 0x6d92;
    cpu.c = 0x3d;
  };

  return {
    symbols,
    memory,
    proofManifest,
    statistics,
    encode(record) {
      const output = symbols.AtomHarnessOutput;
      return direct(
        "AtomEncode",
        (target, names, cpu) => {
          copyRecord(record)(target, names, cpu);
          cpu.d = output >>> 8;
          cpu.e = output & 0xff;
        },
        `AtomEncode ${Buffer.from(record).toString("hex")}`,
      );
    },
    length(record) {
      return direct("AtomFormLength", copyRecord(record), `AtomFormLength ${Buffer.from(record).toString("hex")}`);
    },
    pack(text) {
      const bytes = new TextEncoder().encode(text);
      const output = symbols.AtomHarnessOutput;
      return direct(
        "AtomRadix40Pack",
        (target, names, cpu) => {
          target.fill(0, names.AtomHarnessText, names.AtomHarnessText + 9);
          target.set(bytes.slice(0, 9), names.AtomHarnessText);
          cpu.h = names.AtomHarnessText >>> 8;
          cpu.l = names.AtomHarnessText & 0xff;
          cpu.b = bytes.length;
          cpu.d = output >>> 8;
          cpu.e = output & 0xff;
          cpu.ix = 0x4b71;
          cpu.iy = 0x6d92;
        },
        `AtomRadix40Pack ${JSON.stringify(text)}`,
      );
    },
    recognize(text) {
      const bytes = new TextEncoder().encode(text);
      return direct(
        "AtomRecognizeMnemonic",
        (target, names, cpu) => {
          target.fill(0, names.AtomHarnessText, names.AtomHarnessText + 9);
          target.set(bytes.slice(0, 9), names.AtomHarnessText);
          cpu.h = names.AtomHarnessText >>> 8;
          cpu.l = names.AtomHarnessText & 0xff;
          cpu.b = bytes.length;
          cpu.ix = 0x4b71;
          cpu.iy = 0x6d92;
        },
        `AtomRecognizeMnemonic ${JSON.stringify(text)}`,
      );
    },
  };
}

export function extent(symbols, start, end) {
  return symbols[end] - symbols[start];
}
