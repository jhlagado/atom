import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { createHash } from "node:crypto";
import {
  assembleResolvedAtomProject,
  createDebug80ExecutionAdapter,
  createTriptychWasmExecutionAdapter,
  loadNativeAtomCore,
  materializeAtomGeneration,
} from "../src/host/index.mjs";

const require = createRequire(import.meta.url);
const modulePath =
  process.env.TRIPTYCH_WASM_MODULE ??
  "../triptych/dist/wasm/triptych_host_wasm.js";
const { TriptychCpu } = require(modulePath);

const source = new TextEncoder().encode(
  "ORG 4000H\n" +
    "START: LD A,42\n" +
    "       DB 42\n",
);
const project = {
  parts: [
    {
      ordinal: 0,
      bank: 0,
      logicalIdentity: "main.asm",
      originalBytes: source,
      compilerBytes: source,
    },
  ],
};
const target = { start: 0x4000, capacity: 0x100 };
const core = await loadNativeAtomCore();

const run = (executionAdapter) =>
  assembleResolvedAtomProject(project, {
    nativeCore: core,
    executionAdapter,
    target,
  });

const reference = await run(createDebug80ExecutionAdapter());
const triptych = await run(createTriptychWasmExecutionAdapter({ TriptychCpu }));
const referenceBytes = materializeAtomGeneration(reference.generation).bytes;
const triptychBytes = materializeAtomGeneration(triptych.generation).bytes;

assert.deepEqual(Array.from(triptychBytes), Array.from(referenceBytes));
assert.deepEqual(
  triptych.generation.images.map(({ address, bytes }) => [address, [...bytes]]),
  reference.generation.images.map(({ address, bytes }) => [address, [...bytes]]),
);
assert.deepEqual(
  triptych.generation.patches.map(({ address, bytes }) => [address, [...bytes]]),
  reference.generation.patches.map(({ address, bytes }) => [address, [...bytes]]),
);
assert.deepEqual(
  triptych.execution.serviceTrace.map(({ method, status }) => [method, status]),
  reference.execution.serviceTrace.map(({ method, status }) => [method, status]),
);
assert.deepEqual(
  { status: triptych.native.status, carry: triptych.native.carry },
  { status: reference.native.status, carry: reference.native.carry },
);

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
console.log(
  JSON.stringify(
    {
      profile: "atom-bare-host-triptych-wasm-v1",
      source: "ORG 4000H / LD A,42 / DB 42",
      artifact: {
        bytes: triptychBytes.length,
        sha256: sha256(triptychBytes),
      },
      triptych: {
        instructions: triptych.execution.instructions,
        cycles: triptych.execution.cycles,
        serviceCalls: triptych.execution.serviceCalls,
      },
      reference: {
        instructions: reference.execution.instructions,
        cycles: reference.execution.cycles,
        serviceCalls: reference.execution.serviceCalls,
      },
      result: "pass",
    },
    null,
    2,
  ),
);
