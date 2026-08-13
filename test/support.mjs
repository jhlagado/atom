import assert from "node:assert/strict";

import { compile, compileSource } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const addressOf = (symbol) => symbol.address ?? symbol.value;

export async function createHarness() {
  const assembled = await compile("asm/encoder-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: "off",
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `native harness failed to assemble: ${JSON.stringify(errors)}`);
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
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomHarnessEntry);
  const memory = runtime.hardware.memory;

  function run(entry, setup = () => {}) {
    memory.fill(0xa5, symbols.AtomHarnessOutput, symbols.AtomHarnessOutput + 7);
    memory[symbols.AtomHarnessLength] = 0xa5;
    memory[symbols.AtomHarnessCarry] = 0xa5;
    setup(memory, symbols);
    runtime.cpu.pc = symbols[entry];
    runtime.cpu.halted = false;
    let instructions = 0;
    let cycles = 0;
    while (!runtime.isHalted() && instructions < 4_000) {
      const result = runtime.step();
      cycles += result.cycles ?? 0;
      instructions += 1;
    }
    assert.equal(runtime.isHalted(), true, `${entry} exceeded execution budget`);
    return {
      value: memory[symbols.AtomHarnessLength],
      carry: memory[symbols.AtomHarnessCarry],
      output: Array.from(memory.slice(symbols.AtomHarnessOutput, symbols.AtomHarnessOutput + 7)),
      instructions,
      cycles,
    };
  }

  return {
    symbols,
    memory,
    encode(record) {
      return run("AtomHarnessEntry", (target, names) => {
        target.set(record, names.AtomHarnessInput);
      });
    },
    length(record) {
      return run("AtomHarnessLengthEntry", (target, names) => {
        target.set(record, names.AtomHarnessInput);
      });
    },
    pack(text) {
      const bytes = new TextEncoder().encode(text);
      return run("AtomHarnessPackEntry", (target, names) => {
        target[names.AtomHarnessTextLength] = bytes.length;
        target.fill(0, names.AtomHarnessText, names.AtomHarnessText + 9);
        target.set(bytes.slice(0, 9), names.AtomHarnessText);
      });
    },
    recognize(text) {
      const bytes = new TextEncoder().encode(text);
      return run("AtomHarnessRecognizeEntry", (target, names) => {
        target[names.AtomHarnessTextLength] = bytes.length;
        target.fill(0, names.AtomHarnessText, names.AtomHarnessText + 9);
        target.set(bytes.slice(0, 9), names.AtomHarnessText);
      });
    },
  };
}

export function azmBytes(source) {
  const result = compileSource(`.org $4000\n${source}\n.end\n`, {
    entryName: `<differential:${source}>`,
  });
  const errors = result.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `AZM rejected valid case ${source}: ${JSON.stringify(errors)}`);
  return Array.from(result.bytes);
}

export function azmRejects(source) {
  const result = compileSource(`.org $4000\n${source}\n.end\n`, {
    entryName: `<negative:${source}>`,
  });
  return result.diagnostics.some(({ severity }) => severity === "error");
}

export function extent(symbols, start, end) {
  return symbols[end] - symbols[start];
}
