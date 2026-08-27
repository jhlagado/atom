import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { createZ80Runtime } from "@jhlagado/debug80-runtime";
import {
  MemoryNamedObjectProvider,
  NAMED_OBJECT_OPERATION,
  NAMED_OBJECT_STATUS,
} from "@jhlagado/z80-tool-services";
import { buildNativeObjectHarness } from "../scripts/native-object-harness-builder.mjs";

const encoder = new TextEncoder();
const SOURCE_SELECTOR = 0x90;
const OUTPUT_SELECTOR = 0x91;
const CONFIG = 0x3600;
const PART_TABLE = 0x3700;
const PART_NAMES = 0x3a00;
const OUTPUT_NAME = 0x3b00;
const BUILD = 0x3b20;
const DESCRIPTORS = 0x3b40;
const COMMON_WORKSPACE = 0x4200;
const SYMBOLS = 0x5000;
const PENDING = 0x8000;
const STACK = 0xeff0;
const RETURN_SENTINEL = 0xfffe;

const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const putWord = (memory, address, value) => {
  memory[address] = value & 0xff;
  memory[address + 1] = value >>> 8;
};

async function checkedHarness() {
  const [bytes, census] = await Promise.all([
    readFile(new URL("../assets/atom-object-harness.bin", import.meta.url)),
    readFile(new URL("../proofs/native-object-harness-census.json", import.meta.url), "utf8").then(JSON.parse),
  ]);
  return { bytes: new Uint8Array(bytes), census };
}

function sourceName(ordinal) {
  return Uint8Array.of(ordinal);
}

async function initializeAt(workspace) {
  const { bytes, census } = await checkedHarness();
  const initialMemory = new Uint8Array(0x10000);
  initialMemory.set(bytes);
  const runtime = createZ80Runtime({ memory: initialMemory, startAddress: 0 }, 0);
  const memory = runtime.hardware.memory;
  memory[CONFIG + 6] = 1;
  putWord(memory, CONFIG + 7, workspace);
  memory[STACK] = RETURN_SENTINEL & 0xff;
  memory[STACK + 1] = RETURN_SENTINEL >>> 8;
  runtime.cpu.ix = CONFIG;
  runtime.cpu.sp = STACK;
  runtime.cpu.pc = census.adapterInitEntry;
  for (let count = 0; runtime.cpu.pc !== RETURN_SENTINEL && count < 100; count += 1) runtime.step();
  assert.equal(runtime.cpu.pc, RETURN_SENTINEL);
  return { status: runtime.cpu.a, carry: runtime.cpu.flags.C };
}

async function runProject(sources, options = {}) {
  const harness = options.harness ?? await checkedHarness();
  const { bytes } = harness;
  const census = harness.report ?? harness.census;
  const loadAddress = census.loadAddress ?? 0;
  const commonWorkspace = options.commonWorkspace ?? COMMON_WORKSPACE;
  const symbolStart = options.symbolStart ?? SYMBOLS;
  const symbolEnd = options.symbolEnd ?? PENDING;
  const pendingStart = options.pendingStart ?? PENDING;
  const pendingEnd = options.pendingEnd ?? 0x9000;
  const stack = options.stack ?? STACK;
  const initialSources = new Map(sources.map((source, ordinal) => [sourceName(ordinal), encoder.encode(source)]));
  const sourceOperations = [];
  const outputOperations = [];
  const sourceDelegate = new MemoryNamedObjectProvider(initialSources, { maxHandles: 8 });
  const outputDelegate = new MemoryNamedObjectProvider(
    new Map([["out", options.priorOutput ?? Uint8Array.of(0x99)]]),
    {
      maxHandles: 8,
      fail: options.failOutput,
    },
  );
  const instrument = (delegate, operations) => ({
    dispatch(memory, request) {
      operations.push(memory[request + 2]);
      return delegate.dispatch(memory, request);
    },
    abortAll() {
      delegate.abortAll();
    },
  });
  const providers = new Map([
    [SOURCE_SELECTOR, instrument(sourceDelegate, sourceOperations)],
    [OUTPUT_SELECTOR, instrument(outputDelegate, outputOperations)],
  ]);

  const initialMemory = new Uint8Array(0x10000);
  initialMemory.set(bytes, loadAddress);
  if (harness.workspaceBytes !== undefined) {
    initialMemory.set(harness.workspaceBytes, census.fixedWorkspaceStart);
  }
  const residentBefore = initialMemory.slice(loadAddress, census.residentEnd);
  const runtime = createZ80Runtime(
    { memory: initialMemory, startAddress: loadAddress },
    loadAddress,
    undefined,
    options.romRanges === undefined ? undefined : { romRanges: options.romRanges },
  );
  const memory = runtime.hardware.memory;

  memory[CONFIG + 0] = SOURCE_SELECTOR;
  memory[CONFIG + 1] = OUTPUT_SELECTOR;
  putWord(memory, CONFIG + 2, PART_TABLE);
  putWord(memory, CONFIG + 4, OUTPUT_NAME);
  memory[CONFIG + 6] = 3;
  putWord(memory, CONFIG + 7, commonWorkspace);
  memory.set(encoder.encode("out"), OUTPUT_NAME);

  for (let ordinal = 0; ordinal < sources.length; ordinal += 1) {
    memory[PART_NAMES + ordinal] = ordinal;
    putWord(memory, PART_TABLE + ordinal * 3, PART_NAMES + ordinal);
    memory[PART_TABLE + ordinal * 3 + 2] = 1;
    const sourceLength = encoder.encode(sources[ordinal]).length;
    const descriptor = DESCRIPTORS + ordinal * 5;
    memory[descriptor] = ordinal;
    putWord(memory, descriptor + 1, 0);
    putWord(memory, descriptor + 3, sourceLength);
  }

  memory[BUILD] = sources.length;
  putWord(memory, BUILD + 1, DESCRIPTORS);
  putWord(memory, BUILD + 3, symbolStart);
  putWord(memory, BUILD + 5, symbolEnd);
  putWord(memory, BUILD + 7, pendingStart);
  putWord(memory, BUILD + 9, pendingEnd);
  putWord(memory, BUILD + 11, 0x100);
  putWord(memory, BUILD + 13, 0x4000);

  let instructions = 0;
  let cycles = 0;
  let gatewayCalls = 0;
  const adapterTrace = [];
  const invoke = (entry, setup, maximum = 20_000_000) => {
    memory[stack] = RETURN_SENTINEL & 0xff;
    memory[stack + 1] = RETURN_SENTINEL >>> 8;
    runtime.cpu.sp = stack;
    runtime.cpu.pc = entry;
    setup(runtime.cpu);
    for (let count = 0; runtime.cpu.pc !== RETURN_SENTINEL && count < maximum; count += 1) {
      if (runtime.cpu.pc === census.symbols.NA_TRANS) {
        adapterTrace.push({ entry: "transfer", operation: runtime.cpu.a, count: runtime.cpu.b });
      }
      if (runtime.cpu.pc === census.gatewayEntry) {
        const request = (runtime.cpu.h << 8) | runtime.cpu.l;
        const provider = providers.get(runtime.cpu.c);
        const ix = runtime.cpu.ix;
        const iy = runtime.cpu.iy;
        const status = provider?.dispatch(memory, request) ?? NAMED_OBJECT_STATUS.unavailable;
        const returnAddress = word(memory, runtime.cpu.sp);
        runtime.cpu.sp = (runtime.cpu.sp + 2) & 0xffff;
        runtime.cpu.pc = returnAddress;
        runtime.cpu.a = status;
        runtime.cpu.flags.C = status === 0 ? 0 : 1;
        assert.equal(runtime.cpu.ix, ix, "gateway changed IX");
        assert.equal(runtime.cpu.iy, iy, "gateway changed IY");
        gatewayCalls += 1;
        continue;
      }
      const step = runtime.step();
      instructions += 1;
      cycles += step.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, "native object harness did not return");
    assert.equal(runtime.cpu.sp, stack + 2, "native object harness unbalanced the stack");
    return { status: runtime.cpu.a, carry: runtime.cpu.flags.C };
  };

  const initialized = invoke(census.adapterInitEntry, (cpu) => {
    cpu.ix = CONFIG;
  });
  assert.deepEqual(initialized, { status: 0, carry: 0 });
  const result = invoke(census.assembleEntry, (cpu) => {
    cpu.ix = BUILD;
  });
  return {
    result,
    diagnostic: {
      driverDetail: memory[census.symbols.DR_DETAI],
      statementDetail: memory[census.symbols.ST_DETAI],
      tokenizerStatus: memory[census.symbols.TK_ESTAT],
      part: memory[census.symbols.ST_EPART],
      offset: word(memory, census.symbols.ST_EOFF),
    },
    output: outputDelegate.bytes("out"),
    sourceOperations,
    outputOperations,
    sourceOpenHandles: sourceDelegate.openHandleCount,
    outputOpenHandles: outputDelegate.openHandleCount,
    gatewayCalls,
    adapterTrace,
    instructions,
    cycles,
    census,
    residentUnchanged: Buffer.from(memory.slice(loadAddress, census.residentEnd)).equals(residentBefore),
  };
}

test("native named-object harness assembles parts, fills gaps, patches, and commits", async () => {
  const run = await runProject([
    "ORG $100\nJR LATER\nDS 2\n",
    "LATER:\nDB $A5,0,$1A,$7F,$80,$FF\n",
  ]);
  assert.deepEqual(run.result, { status: 0, carry: 0 }, JSON.stringify({ diagnostic: run.diagnostic, sourceOperations: run.sourceOperations, outputOperations: run.outputOperations, adapterTrace: run.adapterTrace }));
  assert.deepEqual([...run.output], [0x18, 0x02, 0x00, 0x00, 0xa5, 0x00, 0x1a, 0x7f, 0x80, 0xff]);
  assert.equal(run.sourceOpenHandles, 0);
  assert.equal(run.outputOpenHandles, 0);
  assert.equal(run.outputOperations[0], NAMED_OBJECT_OPERATION.beginWrite);
  assert.equal(run.outputOperations.at(-1), NAMED_OBJECT_OPERATION.commit);
  assert.ok(run.outputOperations.includes(NAMED_OBJECT_OPERATION.seek));
  assert.ok(run.sourceOperations.includes(NAMED_OBJECT_OPERATION.read));
  assert.ok(run.census.residentBytes <= 0x4000);
});

test("native named-object harness separates fixed workspace from a 16 KiB ROM bank", async () => {
  const harness = await buildNativeObjectHarness({
    origin: 0x8100,
    imageOrigin: 0x8000,
    workspaceOrigin: 0x1800,
    preludeSource: [
      "ORG $8000",
      ";@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY",
      "PL_ENTRY:",
      "JP NA_INIT",
    ].join("\n"),
  });
  assert.equal(harness.report.loadAddress, 0x8000);
  assert.equal(harness.report.coreOrigin, 0x8100);
  assert.equal(harness.report.residentBytes, 13_026);
  assert.equal(harness.report.residentEnd, 0xb2e2);
  assert.equal(harness.report.fixedWorkspaceStart, 0x1800);
  assert.equal(harness.report.fixedWorkspaceEnd, 0x1ae5);
  assert.equal(harness.report.fixedWorkspaceBytes, 741);
  assert.equal(harness.report.nativeCoreFixedWorkspaceBytes, 714);
  assert.equal(harness.report.adapterFixedWorkspaceBytes, 27);
  assert.equal(harness.debugMap.format, "d8-debug-map");
  assert.ok(Object.keys(harness.debugMap.files).length > 0);
  const run = await runProject([
    "ORG $100\nJR LATER\n",
    "LATER:\nDB $5A\n",
  ], {
    harness,
    commonWorkspace: 0x1b00,
    symbolStart: 0x4000,
    symbolEnd: 0x5000,
    pendingStart: 0x5000,
    pendingEnd: 0x5800,
    stack: 0x7ff0,
    romRanges: [{ start: 0x8000, end: 0xb2e1 }],
  });
  assert.deepEqual(run.result, { status: 0, carry: 0 });
  assert.deepEqual([...run.output], [0x18, 0x00, 0x5a]);
  assert.equal(run.sourceOpenHandles, 0);
  assert.equal(run.outputOpenHandles, 0);
  assert.equal(run.residentUnchanged, true);
});

test("native named-object harness validates its complete common workspace range", async () => {
  assert.deepEqual(await initializeAt(0xfe71), { status: 0, carry: 0 });
  assert.deepEqual(await initializeAt(0xfe72), { status: NAMED_OBJECT_STATUS.invalid, carry: 1 });
});

test("native named-object harness aborts a poisoned output without replacing it", async () => {
  let fail = true;
  const prior = Uint8Array.of(0xde, 0xad);
  const run = await runProject(["ORG $100\nDB 1\n"], {
    priorOutput: prior,
    failOutput({ operation }) {
      if (operation === NAMED_OBJECT_OPERATION.write && fail) {
        fail = false;
        return NAMED_OBJECT_STATUS.storage;
      }
      return undefined;
    },
  });
  assert.equal(run.result.carry, 1);
  assert.deepEqual([...run.output], [...prior]);
  assert.equal(run.outputOperations.at(-1), NAMED_OBJECT_OPERATION.abort);
  assert.equal(run.sourceOpenHandles, 0);
  assert.equal(run.outputOpenHandles, 0);
});

test("native named-object harness accepts the complete 255-part driver domain", async () => {
  const sources = Array.from({ length: 255 }, () => "\n");
  sources[0] = "ORG $100\n";
  sources[254] = "DB $5A\n";
  const run = await runProject(sources);
  assert.deepEqual(run.result, { status: 0, carry: 0 }, JSON.stringify({ diagnostic: run.diagnostic, sourceOperations: run.sourceOperations.slice(0, 20), outputOperations: run.outputOperations }));
  assert.deepEqual([...run.output], [0x5a]);
  assert.equal(run.sourceOperations.filter((operation) => operation === NAMED_OBJECT_OPERATION.openRead).length, 255);
  assert.equal(run.sourceOpenHandles, 0);
  assert.equal(run.outputOpenHandles, 0);
});
