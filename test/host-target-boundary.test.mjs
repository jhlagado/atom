import assert from "node:assert/strict";
import test from "node:test";
import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
  materializeAtomNobj,
  writeAtomNobj,
} from "../src/host/index.mjs";
import { createDriverHarness } from "./driver-support.mjs";

function assemble(source, target) {
  const bytes = new TextEncoder().encode(source);
  return assembleResolvedAtomProject({ parts: [{
    ordinal: 0, bank: 0, logicalIdentity: "boundary.asm",
    originalBytes: bytes, compilerBytes: bytes,
  }] }, { target });
}

test("native descriptor accepts an exclusive end of 10000 but not 10001", async () => {
  const h = await createDriverHarness();
  for (const [address, capacity] of [[0xffff, 1], [0xfffe, 2], [1, 0xffff]]) {
    const result = h.validate([""], { address, capacity });
    assert.equal(result.status, 0);
    assert.equal(result.carry, 0);
  }
  const result = h.assemble([""], { address: 0xffff, capacity: 2 });
  assert.equal(result.status, 1);
  assert.equal(result.driverDetail, 7);
  assert.equal(h.lifecycle().began, 0);
});

test("final-byte IMAGE, instruction, reservation and patch retain a mathematical end", async () => {
  for (const [source, start, expected] of [
    ["DB 42H\n", 0xffff, [0x42]],
    ["LD A,42H\n", 0xfffe, [0x3e, 0x42]],
    ["DS 2\nDS 0\n", 0xfffe, [0, 0]],
    ["DB Value\nValue EQU 42H\n", 0xffff, [0x42]],
    ["DW Value\nValue EQU 1234H\n", 0xfffe, [0x34, 0x12]],
  ]) {
    const result = await assemble(source, { start, capacity: 0x10000 - start });
    assert.equal(result.generation.finalCursor, 0x10000, source);
    assert.equal(result.generation.highWater, 0x10000, source);
    assert.equal(result.generation.remaining, 0, source);
    assert.deepEqual([...materializeAtomGeneration(result.generation).bytes], expected, source);
    const nobj = writeAtomNobj(result.generation, { parts: [{ bank: 0 }] });
    assert.deepEqual([...materializeAtomNobj(nobj).bytes], expected, source);
    assert.equal(result.execution.finalSp, 0xfeff);
    assert.equal(result.execution.returnPc, 0xfffe);
  }
});

test("ORG gaps do not require remaining capacity to reach zero at the endpoint", async () => {
  const result = await assemble("ORG 0FFFFH\nDB 7\nDS 0\n", { start: 0xff00, capacity: 0x100 });
  assert.equal(result.generation.finalCursor, 0x10000);
  assert.equal(result.generation.highWater, 0x10000);
  assert.equal(result.generation.remaining, 0xff);
  const bytes = materializeAtomGeneration(result.generation).bytes;
  assert.equal(bytes.length, 0x100);
  assert.deepEqual([...bytes.slice(0, -1)], Array(0xff).fill(0));
  assert.equal(bytes[0xff], 7);
});

test("wrapped writes, reservations and explicit ORG zero never publish a generation", async () => {
  for (const tail of ["DB 8\n", "DS 1\n", "ORG 0\n"]) {
    await assert.rejects(
      () => assemble(`ORG 0FFFFH\nDB 7\n${tail}`, { start: 0xff00, capacity: 0x100 }),
      (error) => {
        assert.equal(error.category, "output");
        assert.equal(error.sink.open, false);
        assert.equal(error.execution.serviceTrace.filter(({ method }) => method === "abort").length, 1);
        assert.ok(!error.execution.serviceTrace.some(({ method, status }) => method === "commit" && status === 0));
        assert.equal(error.diagnostic.line, 3);
        return true;
      },
    );
  }
});

test("host descriptor rejects overflow and does not reinterpret capacity zero", async () => {
  await assert.rejects(() => assemble("", { start: 0xffff, capacity: 2 }), { code: "target-range" });
  await assert.rejects(() => assemble("", { start: 0, capacity: 0x10000 }));
  const result = await assemble("", { start: 0xffff, capacity: 0 });
  assert.equal(result.generation.finalCursor, 0xffff);
  assert.equal(result.generation.remaining, 0);
});

test("native labels remain words even when the host extent ends at 10000", async () => {
  const result = await assemble("DB 7\nEnd:\n", { start: 0xffff, capacity: 1 });
  assert.equal(result.generation.symbols.find(({ name }) => name.toUpperCase() === "END").value, 0);
  assert.equal(result.generation.highWater, 0x10000);
});
