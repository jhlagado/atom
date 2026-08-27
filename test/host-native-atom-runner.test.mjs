import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleAtomProject,
  assembleResolvedAtomProject,
  createMemoryAtomSink,
  loadNativeAtomCore,
  materializeAtomGeneration,
  NATIVE_ATOM_LIMITS,
  writeIntelHex,
} from "../src/host/index.mjs";
import { NATIVE_HOST_FILES } from "./native-host-case.mjs";

const encoder = new TextEncoder();

async function projectRoot(t, files) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-native-host-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  for (const [name, source] of Object.entries(files)) {
    const destination = path.join(root, name);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, source);
  }
  return root;
}

function resolvedParts(sources) {
  return {
    parts: sources.map((source, ordinal) => {
      const bytes = source instanceof Uint8Array ? source : encoder.encode(source);
      return {
        ordinal,
        bank: 0,
        logicalIdentity: `part-${ordinal}.asm`,
        originalBytes: bytes,
        compilerBytes: bytes,
      };
    }),
  };
}

async function assemblyError(action, category, code) {
  let captured;
  await assert.rejects(action, (error) => {
    captured = error;
    assert.equal(error?.name, "AtomAssemblyError");
    assert.equal(error?.category, category);
    assert.equal(error?.code, code);
    return true;
  });
  return captured;
}

test("the Mac host resolves, masks, and executes one project through native Atom", async (t) => {
  const root = await projectRoot(t, NATIVE_HOST_FILES);

  const result = await assembleAtomProject({
    root,
    entry: "main.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
  assert.deepEqual(result.project.parts.map(({ logicalIdentity }) => logicalIdentity), ["lib.asm", "main.asm"]);
  assert.deepEqual(result.project.bankArray, [0, 0]);
  assert.deepEqual(result.generation.images.map(({ address, bytes }) => [address, bytes]), [
    [0x4000, [0x3e]],
    [0x4001, [0x03]],
    [0x4002, [0x18]],
    [0x4003, [0x00]],
    [0x4004, [0x41]],
    [0x4005, [0x01]],
    [0x4006, [0x00]],
    [0x4007, [0x40]],
    [0x4008, [0xff]],
    [0x4009, [0xff]],
  ]);
  assert.deepEqual(
    result.generation.patches.map(({ bank, address, bytes }) => ({ bank, address, bytes })),
    [{ bank: 0, address: 0x4003, bytes: [0x02] }],
  );
  assert.equal(result.generation.finalCursor, 0x400a);
  assert.equal(result.generation.highWater, 0x400a);
  assert.equal(result.generation.remaining, 0xf6);
  assert.deepEqual(Array.from(materializeAtomGeneration(result.generation).bytes), [
    0x3e, 0x03, 0x18, 0x02, 0x41, 0x01, 0x00, 0x40, 0xff, 0xff,
  ]);
  assert.deepEqual(result.execution.serviceTrace.map(({ method }) => method), [
    "begin",
    ...Array(6).fill("image"),
    "patch-byte",
    ...Array(4).fill("image"),
    "commit",
  ]);
  assert.equal(result.native.status, 0);
  assert.equal(result.native.carry, 0);
  assert.equal(result.execution.returnPc, 0xfffe);
  assert.equal(result.execution.finalSp, 0xfeff);
  assert.equal(result.core.codeBytes, 11_682);
  assert.equal(result.core.residentExtentBytes, 12_396);
  const proof = JSON.parse(await fs.readFile("proofs/phase-4.json", "utf8"));
  assert.equal(result.execution.instructions, proof.integrationExecution.measuredInstructions);
  assert.equal(result.execution.cycles, proof.integrationExecution.measuredCycles);
  assert.equal(result.execution.serviceCalls, proof.integrationExecution.serviceCalls);
  assert.ok(result.execution.instructions <= proof.integrationExecution.maxInstructions);
  assert.ok(result.execution.cycles <= proof.integrationExecution.maxCycles);

  assert.throws(() => {
    result.generation.images[0].bytes[0] = 0;
  }, TypeError);
  const materialized = materializeAtomGeneration(result.generation);
  materialized.bytes[0] = 0;
  assert.equal(materializeAtomGeneration(result.generation).bytes[0], 0x3e);
});

test("native diagnostics retain logical source, byte offset, line, column, and symbol", async (t) => {
  const source = [
    "%define TAKE 1",
    "%if TAKE",
    "ORG 4000H",
    "LD HL,Missing",
    "%endif",
    "",
  ].join("\n");
  const root = await projectRoot(t, { "main.asm": source });
  const error = await assemblyError(
    () => assembleAtomProject({ root, entry: "main.asm", target: { start: 0x4000, capacity: 0x100 } }),
    "source",
    "undefined-symbol",
  );
  assert.equal(error.symbol, "MISSING");
  assert.deepEqual(error.diagnostic, {
    logicalIdentity: "main.asm",
    ordinal: 0,
    offset: source.indexOf("Missing"),
    line: 4,
    column: 7,
  });
  assert.deepEqual(error.sink.lifecycle, ["begin", "image", "image", "image", "abort"]);
  assert.equal(error.sink.generation, undefined);
  assert.equal(error.native.part, 0);
  assert.equal(error.native.offset, source.indexOf("Missing"));
});

test("an error in an included part is attributed to that physical source identity", async (t) => {
  const root = await projectRoot(t, {
    "bad.asm": "LD BC,A\n",
    "main.asm": "%include \"bad.asm\"\nNOP\n",
  });
  const error = await assemblyError(
    () => assembleAtomProject({ root, entry: "main.asm", target: { start: 0x4000, capacity: 0x100 } }),
    "source",
    "statement",
  );
  assert.deepEqual(error.diagnostic, {
    logicalIdentity: "bad.asm",
    ordinal: 0,
    offset: 0,
    line: 1,
    column: 1,
  });
});

test("the integrated boundary rejects nonzero placement before starting native Atom", async (t) => {
  const root = await projectRoot(t, { "main.asm": "NOP\n" });
  await assert.rejects(
    () => assembleAtomProject({ root, entry: "main.asm", placement: { defaultBank: 1, banks: {} } }),
    (error) => {
      assert.equal(error?.name, "SourcePreparationError");
      assert.equal(error?.code, "bank-capacity");
      return true;
    },
  );
});

test("host sink rejection returns through native failure and aborts the generation", async () => {
  const base = createMemoryAtomSink();
  const sink = Object.freeze({
    begin: (value) => base.begin(value),
    image: () => 1,
    patch: (value) => base.patch(value),
    commit: (value) => base.commit(value),
    abort: () => base.abort(),
    snapshot: () => base.snapshot(),
  });
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
      target: { start: 0x4000, capacity: 0x100 },
      sink,
    }),
    "output",
    "sink",
  );
  assert.deepEqual(error.execution.serviceTrace, [
    { method: "begin", status: 0 },
    { method: "image", status: 1 },
    { method: "abort", status: 0 },
  ]);
  assert.deepEqual(error.sink.lifecycle, ["begin", "abort"]);
  assert.equal(error.sink.open, false);
});

test("a thrown host service is converted to failure so native Atom can abort", async () => {
  const base = createMemoryAtomSink();
  const cause = new Error("injected host exception");
  const sink = Object.freeze({
    begin: (value) => base.begin(value),
    image: () => { throw cause; },
    patch: (value) => base.patch(value),
    commit: (value) => base.commit(value),
    abort: () => base.abort(),
    snapshot: () => base.snapshot(),
  });
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
      target: { start: 0x4000, capacity: 0x100 },
      sink,
    }),
    "output",
    "sink",
  );
  assert.equal(error.cause, cause);
  assert.deepEqual(error.execution.serviceTrace.map(({ status }) => status), [0, 0xef, 0]);
  assert.equal(error.sink.open, false);
});

test("descending ORG output is rejected by the append-only host sink", async () => {
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts([
      "ORG 4001H\nDB 1\nORG 4000H\nDB 2\n",
    ]), { target: { start: 0x4000, capacity: 0x100 } }),
    "output",
    "sink",
  );
  assert.equal(error.sink.failure.code, "image-order");
  assert.equal(error.sink.open, false);
});

test("commit rejects an out-of-range final cursor even when no IMAGE exposed it", async () => {
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(["ORG 4101H\n"]), {
      target: { start: 0x4000, capacity: 0x100 },
    }),
    "output",
    "sink",
  );
  assert.equal(error.message, "ORG lies outside the target range");
  assert.deepEqual(error.execution.serviceTrace.map(({ method }) => method), ["begin", "commit", "abort"]);
  assert.equal(error.sink.open, false);
});

test("the host retains DS high water across a later backward ORG", async () => {
  const result = await assembleResolvedAtomProject(resolvedParts([
    "ORG 4000H\nDS 4\nORG 4000H\nDB 1\n",
  ]), { target: { start: 0x4000, capacity: 0x100 } });
  assert.equal(result.generation.finalCursor, 0x4001);
  assert.equal(result.generation.highWater, 0x4004);
  assert.deepEqual(Array.from(materializeAtomGeneration(result.generation).bytes), [1, 0, 0, 0]);
});

test("an intermediate out-of-range ORG remains a failure after the cursor returns", async () => {
  const source = "ORG 4101H\nORG 4000H\n";
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts([source]), {
      target: { start: 0x4000, capacity: 0x100 },
    }),
    "output",
    "sink",
  );
  assert.equal(error.message, "ORG lies outside the target range");
  assert.deepEqual(error.diagnostic, {
    logicalIdentity: "part-0.asm",
    ordinal: 0,
    offset: 0,
    line: 1,
    column: 1,
  });
  assert.deepEqual(error.execution.serviceTrace.map(({ method }) => method), ["begin", "commit", "abort"]);
});

test("an intermediate out-of-range DS reservation retains its directive position", async () => {
  const source = "ORG 40FFH\nDS 2\nORG 4000H\n";
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts([source]), {
      target: { start: 0x4000, capacity: 0x100 },
    }),
    "output",
    "sink",
  );
  assert.equal(error.message, "DS reservation lies outside the target range");
  assert.deepEqual(error.diagnostic, {
    logicalIdentity: "part-0.asm",
    ordinal: 0,
    offset: source.indexOf("DS"),
    line: 2,
    column: 1,
  });
});

test("the memory sink rejects a second patch to one IMAGE byte", () => {
  const sink = createMemoryAtomSink();
  assert.equal(sink.begin({ descriptor: 0x4000, target: { start: 0x4000, capacity: 0x100 } }), 0);
  assert.equal(sink.image({ bank: 0, address: 0x4000, bytes: [0] }), 0);
  assert.equal(sink.patch({ bank: 0, address: 0x4000, bytes: [1] }), 0);
  assert.notEqual(sink.patch({ bank: 0, address: 0x4000, bytes: [2] }), 0);
  assert.equal(sink.snapshot().failure.code, "patch-target");
  assert.equal(sink.abort(), 0);
});

test("native source offsets accept 65,535 bytes and reject one byte more", async () => {
  const exact = new Uint8Array(NATIVE_ATOM_LIMITS.sourceBytes).fill(0x20);
  const result = await assembleResolvedAtomProject(resolvedParts([exact]), {
    target: { start: 0, capacity: 0 },
    maxInstructions: 8_000_000,
  });
  assert.equal(result.native.status, 0);
  assert.deepEqual(result.generation.images, []);

  const excess = new Uint8Array(NATIVE_ATOM_LIMITS.sourceBytes + 1).fill(0x20);
  await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts([excess]), { target: { start: 0, capacity: 0 } }),
    "configuration",
    "source-capacity",
  );
});

test("the Mac adapter streams ordered source parts larger than 24 KiB", async () => {
  const comment = `;${"x".repeat(13_000)}\n`;
  const result = await assembleResolvedAtomProject(resolvedParts([comment, `${comment}NOP\n`]), {
    target: { start: 0x4000, capacity: 0x100 },
  });
  assert.ok(result.execution.sourceReads > 26_000);
  assert.equal("sourcePages" in result.execution, false);
  assert.deepEqual(Array.from(materializeAtomGeneration(result.generation).bytes), [0]);
});

test("the host rejects a native source read outside the resolved part", async () => {
  const core = await loadNativeAtomCore();
  const resident = parseIntelHex(core.hexText).memory.slice(0, core.residentExtentBytes);
  resident.set([
    0x3e, 0x00,
    0x21, 0xff, 0xff,
    0xcd, core.symbols.AtomSourceReadByte & 0xff, core.symbols.AtomSourceReadByte >>> 8,
    0xc9,
  ], core.symbols.AtomAssemble);
  const readingCore = {
    ...core,
    hexText: writeIntelHex({ base: 0, bytes: resident }),
  };
  await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
      target: { start: 0, capacity: 1 },
      nativeCore: readingCore,
    }),
    "runtime",
    "source-read",
  );
});

test("native part capacity accepts 255 and rejects 256", async () => {
  const maximum = Array.from({ length: 255 }, () => "");
  maximum[254] = "DB Missing\n";
  const undefinedError = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(maximum), {
      target: { start: 0, capacity: 2 },
    }),
    "source",
    "undefined-symbol",
  );
  assert.equal(undefinedError.native.part, 254);
  assert.equal(undefinedError.diagnostic.ordinal, 254);
  const result = await assembleResolvedAtomProject(resolvedParts(Array.from({ length: 255 }, () => "")), {
    target: { start: 0, capacity: 0 },
  });
  assert.equal(result.native.status, 0);
  await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(Array.from({ length: 256 }, () => "")), { target: { start: 0, capacity: 0 } }),
    "configuration",
    "part-capacity",
  );
});

test("two fresh native runs are byte-for-byte and operation-for-operation deterministic", async () => {
  const project = resolvedParts(["ORG 4000H\nDW Later\nLater: DB 1\n"]);
  const first = await assembleResolvedAtomProject(project, { target: { start: 0x4000, capacity: 0x100 } });
  const second = await assembleResolvedAtomProject(project, { target: { start: 0x4000, capacity: 0x100 } });
  assert.deepEqual(second.generation, first.generation);
  assert.deepEqual(second.execution, first.execution);
  assert.deepEqual(
    Array.from(materializeAtomGeneration(second.generation).bytes),
    Array.from(materializeAtomGeneration(first.generation).bytes),
  );
});

test("the linked service entries fail closed when host interception is absent", async () => {
  const core = await loadNativeAtomCore();
  const entries = [
    "AtomSinkBegin",
    "AtomSinkImageByte",
    "AtomSinkPatchByte",
    "AtomSinkPatchWord",
    "AtomSinkCommit",
    "AtomSinkAbort",
  ];
  assert.equal(new Set(entries.map((name) => core.symbols[name])).size, entries.length);

  for (const entry of entries) {
    const runtime = createZ80Runtime(parseIntelHex(core.hexText), core.symbols[entry]);
    const memory = runtime.hardware.memory;
    memory[0xf000] = 0xfe;
    memory[0xf001] = 0xff;
    runtime.cpu.a = 0x42;
    runtime.cpu.flags.C = 0;
    runtime.cpu.sp = 0xf000;
    runtime.cpu.pc = core.symbols[entry];
    for (let instructions = 0; runtime.cpu.pc !== 0xfffe && instructions < 12; instructions += 1) runtime.step();
    assert.equal(runtime.cpu.pc, 0xfffe, entry);
    assert.equal(runtime.cpu.sp, 0xf002, entry);
    assert.equal(runtime.cpu.a, 0xff, entry);
    assert.equal(runtime.cpu.flags.C, 1, entry);
  }
});

test("the Phase 4 host memory profile covers exactly 64 KiB", async () => {
  const core = await loadNativeAtomCore();
  const profile = JSON.parse(await fs.readFile("proofs/phase-4-memory.json", "utf8"));
  const resolve = (value) => typeof value === "number" ? value : core.symbols[value];
  const regions = profile.regions.map((region) => ({
    ...region,
    startAddress: resolve(region.start),
    endAddress: resolve(region.end),
  }));
  assert.equal(regions[0].startAddress, 0);
  for (const [index, region] of regions.entries()) {
    assert.equal(region.endAddress - region.startAddress, region.exactBytes, `${region.name}: extent drift`);
    if (index > 0) assert.equal(regions[index - 1].endAddress, region.startAddress, `${region.name}: gap or overlap`);
  }
  assert.equal(regions.at(-1).endAddress, profile.addressSpaceBytes);
  for (const extent of profile.extents) {
    const total = extent.sum
      ? extent.sum.reduce((sum, [start, end]) => sum + resolve(end) - resolve(start), 0)
      : resolve(extent.end) - resolve(extent.start);
    assert.equal(total, extent.exactBytes, `${extent.name}: extent drift`);
  }
});

test("runtime budget failure discards an open host generation", async () => {
  const base = createMemoryAtomSink();
  const error = await assemblyError(
    () => assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
      target: { start: 0x4000, capacity: 0x100 },
      maxInstructions: 225,
      sink: base,
    }),
    "runtime",
    "budget",
  );
  assert.equal(error.sink.open, false);
  assert.deepEqual(error.sink.lifecycle, ["begin", "abort"]);
});
