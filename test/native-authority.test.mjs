import assert from "node:assert/strict";
import test from "node:test";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { MNEMONICS } from "../src/abi.mjs";
import { loadNativeAtomCore } from "../src/host/index.mjs";
import { invalidCases, systematicInvalidRecords, validCases } from "./cases.mjs";
import { azmBytes, azmRejects } from "./support.mjs";

const INPUT = 0x8000;
const OUTPUT = 0x8010;
const TEXT = 0x8020;
const STACK_RETURN = 0xfefe;
const RETURN_SENTINEL = 0x80fe;

const pair = (high, low) => ((high << 8) | low) & 0xffff;

async function createCheckedCoreHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.atm");
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), core.symbols.AtomEncode);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  let invocation = 0;

  function invoke(entry, setup, label) {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    invocation += 1;
    memory.fill(0xa5, OUTPUT - 1, OUTPUT + 8);
    memory.fill(0, INPUT, INPUT + 10);
    memory.fill(0, TEXT, TEXT + 9);
    for (
      let address = core.symbols.AtomEncoderWorkspaceStart;
      address < core.symbols.AtomEncoderWorkspaceEnd;
      address += 1
    ) {
      memory[address] = (invocation * 73 + address * 29) & 0xff;
    }
    setup(runtime.cpu, memory);
    const inputBefore = memory.slice(INPUT, INPUT + 10);
    const codeBefore = core.codeRanges.map(({ start, end }) => memory.slice(start, end));
    memory[STACK_RETURN] = RETURN_SENTINEL & 0xff;
    memory[STACK_RETURN + 1] = RETURN_SENTINEL >>> 8;
    runtime.cpu.sp = STACK_RETURN;
    runtime.cpu.pc = core.symbols[entry];
    let instructions = 0;
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < 2_000) {
      runtime.step();
      instructions += 1;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return`);
    assert.equal(runtime.cpu.sp, STACK_RETURN + 2, `${label}: unbalanced stack`);
    assert.equal(memory[OUTPUT - 1], 0xa5, `${label}: output underrun`);
    assert.equal(memory[OUTPUT + 7], 0xa5, `${label}: output overrun`);
    assert.deepEqual(memory.slice(INPUT, INPUT + 10), inputBefore, `${label}: input changed`);
    for (const [index, { start, end }] of core.codeRanges.entries()) {
      assert.deepEqual(memory.slice(start, end), codeBefore[index], `${label}: native code changed`);
    }
    return {
      value: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      de: pair(runtime.cpu.d, runtime.cpu.e),
      output: Array.from(memory.slice(OUTPUT, OUTPUT + 7)),
    };
  }

  const recordSetup = (record) => (cpu, target) => {
    target.set(record, INPUT);
    cpu.ix = INPUT;
    cpu.iy = 0x6d92;
    cpu.c = 0x3d;
  };

  return {
    core,
    length(record) {
      return invoke("AtomFormLength", recordSetup(record), `AtomFormLength ${Buffer.from(record).toString("hex")}`);
    },
    encode(record) {
      return invoke("AtomEncode", (cpu, target) => {
        recordSetup(record)(cpu, target);
        cpu.d = OUTPUT >>> 8;
        cpu.e = OUTPUT & 0xff;
      }, `AtomEncode ${Buffer.from(record).toString("hex")}`);
    },
    recognize(text) {
      const bytes = new TextEncoder().encode(text);
      return invoke("AtomRecognizeMnemonic", (cpu, target) => {
        target.set(bytes, TEXT);
        cpu.h = TEXT >>> 8;
        cpu.l = TEXT & 0xff;
        cpu.b = bytes.length;
        cpu.ix = 0x4b71;
        cpu.iy = 0x6d92;
      }, `AtomRecognizeMnemonic ${JSON.stringify(text)}`);
    },
  };
}

const harness = await createCheckedCoreHarness();

test("the authoritative .atm encoder matches AZM across the complete claimed space", () => {
  for (const { source, record } of validCases()) {
    const expected = azmBytes(source);
    const length = harness.length(record);
    assert.equal(length.carry, 0, `${source}: form length rejected a valid form`);
    assert.equal(length.value, expected.length, `${source}: form length differs`);
    const encoded = harness.encode(record);
    assert.equal(encoded.carry, 0, `${source}: encoder rejected a valid form`);
    assert.equal(encoded.value, expected.length, `${source}: encoded length differs`);
    assert.equal(encoded.de, OUTPUT + expected.length, `${source}: destination exit differs`);
    assert.deepEqual(encoded.output.slice(0, expected.length), expected, source);
    assert.deepEqual(encoded.output.slice(expected.length), Array(7 - expected.length).fill(0xa5), source);
  }

  for (const { source, record, matrix } of invalidCases()) {
    const rejected = azmRejects(source);
    if (!rejected && matrix) continue;
    assert.equal(rejected, true, `${source}: invalid fixture is accepted by AZM`);
    assert.equal(harness.length(record).carry, 1, `${source}: form length accepted an invalid form`);
    const encoded = harness.encode(record);
    assert.equal(encoded.carry, 1, `${source}: encoder accepted an invalid form`);
    assert.equal(encoded.de, OUTPUT, `${source}: invalid form changed the destination`);
    assert.deepEqual(encoded.output, Array(7).fill(0xa5), source);
  }

  for (const record of systematicInvalidRecords()) {
    assert.equal(harness.length(record).carry, 1, Buffer.from(record).toString("hex"));
    const encoded = harness.encode(record);
    assert.equal(encoded.carry, 1, Buffer.from(record).toString("hex"));
    assert.equal(encoded.de, OUTPUT);
    assert.deepEqual(encoded.output, Array(7).fill(0xa5));
  }
});

test("the authoritative .atm mnemonic recognizer covers every ordinal and case", () => {
  for (let ordinal = 1; ordinal < MNEMONICS.length; ordinal += 1) {
    const name = MNEMONICS[ordinal];
    for (const spelling of [name, name.toLowerCase(), [...name].map((character, index) =>
      index % 2 === 0 ? character : character.toLowerCase()).join("")]) {
      const result = harness.recognize(spelling);
      assert.equal(result.carry, 0, spelling);
      assert.equal(result.value, ordinal, spelling);
    }
  }
  for (const name of ["", "NOPE", "LDIRS", "ABCDEFGH", "A-B", "1234", "_LD"]) {
    const result = harness.recognize(name);
    assert.equal(result.carry, 1, name);
    assert.equal(result.value, 0, name);
  }
});
