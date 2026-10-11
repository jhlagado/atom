import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test, { describe } from "node:test";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  ATOM_VERSION,
  MemoryNamedObjectServices,
  NAMED_OBJECT_OPERATION,
  NAMED_OBJECT_STATUS,
  assembleAtomProject,
  assembleResolvedAtomProject,
  createMemoryAtomSink,
  createNamedObjectAtomAdapter,
  createTriptychWasmExecutionAdapter,
  materializeAtomGeneration,
  materializeAtomNobj,
  parseAtomNobj,
  publishAtomArtifacts,
  publishAtomOutputFiles,
  renderAtomArtifacts,
  resolveAtomProject,
  writeAtomCom,
} from "../src/host/index.mjs";
import { createFlatImageAtomSink } from "../src/host/harness/flat-image-atom-sink.mjs";
import { createZ80Runtime, } from "@jhlagado/z80-runtime";
import {
  MemoryNamedObjectProvider,
} from "@jhlagado/z80-tool-services";
import { readFile } from "node:fs/promises";
import { createAsoWriter, readAsoOperations } from "../src/host/artifacts/aso-stream.mjs";
import { buildNativeObjectHarness } from "../src/host/build/object-harness-builder.mjs";

test("the WASM image reader rejects addresses outside Z80 memory and missing EOF", () => {
  const { parseImage } = createTriptychWasmExecutionAdapter({ TriptychCpu: class {} });
  const complete = ":0100000000FF\n:00000001FF\n";
  assert.deepEqual(parseImage(complete).writeRanges, [{ start: 0, end: 1 }]);
  assert.throws(() => parseImage(":0200000480007A\n:00000001FF\n"), /address exceeds Z80 space/);
  assert.throws(() => parseImage(":0100000000FF\n"), /missing Intel HEX end record/);
});

describe("CLI", () => {
  const executable = fileURLToPath(new URL("../bin/atom.mjs", import.meta.url));

  function run(arguments_, cwd) {
    return new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [executable, ...arguments_], {
        cwd,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let stdout = "";
      let stderr = "";
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");
      child.stdout.on("data", (chunk) => { stdout += chunk; });
      child.stderr.on("data", (chunk) => { stderr += chunk; });
      child.on("error", reject);
      child.on("close", (status) => resolve({ status, stdout, stderr }));
    });
  }

  async function workspace(t) {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-cli-"));
    t.after(() => fs.rm(root, { recursive: true, force: true }));
    return root;
  }

  test("CLI defaults to one trimmed BIN and publishes only named formats", async (t) => {
    const root = await workspace(t);
    await fs.writeFile(path.join(root, "main.asm"), "ORG 4000H\nDB 1,2,3\n");
    const defaultBuild = await run(["main.asm"], root);
    assert.equal(defaultBuild.status, 0, defaultBuild.stderr);
    assert.deepEqual(await fs.readFile(path.join(root, "build", "main.bin")), Buffer.from([1, 2, 3]));
    assert.deepEqual(await fs.readdir(path.join(root, "build")), ["main.bin"]);

    const selected = await run([
      "main.asm",
      "out/program.bin",
      "out/program.hex",
      "out/program.lst",
      "out/program.d8.json",
    ], root);
    assert.equal(selected.status, 0, selected.stderr);
    assert.deepEqual((await fs.readdir(path.join(root, "out"))).sort(), [
      "program.bin",
      "program.d8.json",
      "program.hex",
      "program.lst",
    ]);
    assert.deepEqual(await fs.readFile(path.join(root, "out", "program.bin")), Buffer.from([1, 2, 3]));

    const selectedWithOption = await run(["-o", "option/program.hex", "main.asm"], root);
    assert.equal(selectedWithOption.status, 0, selectedWithOption.stderr);
    assert.deepEqual(await fs.readdir(path.join(root, "option")), ["program.hex"]);
    assert.match(await fs.readFile(path.join(root, "option", "program.hex"), "utf8"), /01/);
  });

  test("CLI validates positive output selection and rejects removed switches", async (t) => {
    const root = await workspace(t);
    await fs.writeFile(path.join(root, "main.asm"), "NOP\n");
    for (const [arguments_, message] of [
      [["main.asm", "a.bin", "b.bin"], /output format is repeated/],
      [["main.asm", "output"], /recognized format suffix/],
      [["main.asm", "output.nobj"], /recognized format suffix/],
      [["--origin", "4000H", "main.asm"], /unknown option/],
      [["--no-bin", "main.asm"], /unknown option/],
      [["--hex", "main.asm"], /unknown option/],
    ]) {
      const result = await run(arguments_, root);
      assert.equal(result.status, 2);
      assert.match(result.stderr, message);
    }
  });

  test("a failed flat-output assembly preserves the prior BIN", async (t) => {
    const root = await workspace(t);
    await fs.mkdir(path.join(root, "build"));
    const previous = Buffer.from([0x3e, 0x2a, 0xc9]);
    await fs.writeFile(path.join(root, "build", "main.bin"), previous);
    await fs.writeFile(path.join(root, "main.asm"), "LD BC,A\n");

    const result = await run(["main.asm"], root);

    assert.notEqual(result.status, 0);
    assert.deepEqual(await fs.readFile(path.join(root, "build", "main.bin")), previous);
    assert.deepEqual(await fs.readdir(path.join(root, "build")), ["main.bin"]);
  });

  test("CLI project files are Node-only defaults overridden by command outputs and definitions", async (t) => {
    const root = await workspace(t);
    await fs.mkdir(path.join(root, "src"));
    await fs.writeFile(path.join(root, "src", "main.asm"), "%IF DEBUG\nDB 7\n%ELSE\nDB 9\n%ENDIF\n");
    await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
      assembler: "atom",
      entry: "src/main.asm",
      outputs: ["build/project.bin"],
      definitions: { DEBUG: 0 },
    }));
    const configured = await run(["--project", "atom.json"], root);
    assert.equal(configured.status, 0, configured.stderr);
    assert.deepEqual(await fs.readFile(path.join(root, "build", "project.bin")), Buffer.from([9]));

    const overridden = await run(["--project", "atom.json", "-DDEBUG=1", "--output", "build/override.hex"], root);
    assert.equal(overridden.status, 0, overridden.stderr);
    assert.match(await fs.readFile(path.join(root, "build", "override.hex"), "utf8"), /07/);
  });

  test("CLI project files reject non-Atom assembler flavours", async (t) => {
    const root = await workspace(t);
    await fs.mkdir(path.join(root, "src"));
    await fs.writeFile(path.join(root, "src", "main.asm"), "NOP\n");
    await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
      assembler: "azm",
      entry: "src/main.asm",
    }));

    const result = await run(["--project", "atom.json"], root);

    assert.equal(result.status, 2);
    assert.match(result.stderr, /Atom projects must set assembler to atom/);
    await assert.rejects(fs.access(path.join(root, "build", "main.bin")));

    await fs.writeFile(path.join(root, "atom.json"), JSON.stringify({
      assembler: "auto",
      entry: "src/main.asm",
    }));

    const ambiguous = await run(["--project", "atom.json"], root);

    assert.equal(ambiguous.status, 2);
    assert.match(ambiguous.stderr, /src\/main\.asm does not select an assembler from its filename/);
    await assert.rejects(fs.access(path.join(root, "build", "main.bin")));
  });

  test("CLI renders a validated CP/M COM", async (t) => {
    const root = await workspace(t);
    await fs.writeFile(path.join(root, "main.asm"), "RET\n");
    const result = await run(["--target", "cpm22", "main.asm", "program.com"], root);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(await fs.readFile(path.join(root, "program.com")), Buffer.from([0xc9]));

    const implicit = await run(["main.asm", "implicit.com"], root);
    assert.equal(implicit.status, 0, implicit.stderr);
    assert.deepEqual(await fs.readFile(path.join(root, "implicit.com")), Buffer.from([0xc9]));

    await fs.writeFile(path.join(root, "wrong.asm"), "ORG 200H\nRET\n");
    const rejected = await run(["wrong.asm", "wrong.com"], root);
    assert.equal(rejected.status, 2);
    assert.match(rejected.stderr, /COM output requires load and entry address/);
    await assert.rejects(fs.access(path.join(root, "wrong.com")));

    const explicitGeneric = await run(["--target", "generic", "main.asm", "generic.com"], root);
    assert.equal(explicitGeneric.status, 2);
    assert.match(explicitGeneric.stderr, /COM output requires load and entry address/);
    await assert.rejects(fs.access(path.join(root, "generic.com")));
  });
});

describe("Artifacts", () => {
  const encoder = new TextEncoder();

  function project(source, identity = "main.asm") {
    const bytes = encoder.encode(source);
    return {
      parts: [{
        ordinal: 0,
        bank: 0,
        logicalIdentity: identity,
        originalBytes: bytes,
        compilerBytes: bytes,
      }],
    };
  }

  async function render(source) {
    const input = project(source);
    const assembled = await assembleResolvedAtomProject(input, {
      target: { start: 0x4000, capacity: 0x100 },
    });
    return { input, assembled, artifacts: renderAtomArtifacts({ project: input, ...assembled }) };
  }

  test("artifact renderers preserve final patches, gaps, source lines, symbols, and checksums", async () => {
    const source = [
      "ORG 4000H",
      "START: JR LATER ; EQU defines constants, while this label marks code.",
      "DS 2",
      "VALUE EQU 42",
      "LATER: LD A,VALUE",
      "",
    ].join("\n");
    const { artifacts } = await render(source);

    assert.deepEqual(Array.from(artifacts.bin), [0x18, 0x02, 0, 0, 0x3e, 0x2a]);
    assert.equal(artifacts.hex, ":06400000180200003E2A38\n:00000001FF\n");
    assert.match(artifacts.listing, /4000  18 02\s+main\.asm:2\s+START: JR LATER/);
    assert.match(artifacts.listing, /4002  <2 reserved>\s+main\.asm:3\s+DS 2/);
    assert.match(artifacts.listing, /VALUE\s+=002A main\.asm:4/);
    assert.deepEqual(artifacts.d8.fileList, ["main.asm"]);
    assert.deepEqual(artifacts.d8.symbols.map(({ name, kind }) => [name, kind]), [
      ["LATER", "label"],
      ["START", "label"],
      ["VALUE", "constant"],
    ]);
    assert.deepEqual(artifacts.d8.segments, [{ start: 0x4000, end: 0x4006 }]);
    assert.equal(artifacts.d8.generator.version, ATOM_VERSION);

    const parsed = parseAtomNobj(artifacts.nobj);
    assert.equal(parsed.version, "0.2");
    assert.equal(parsed.imageRecords, 2);
    assert.equal(parsed.patchRecords, 1);
    assert.equal(parsed.entryAddress, 0x4000);
    assert.deepEqual(materializeAtomNobj(artifacts.nobj).bytes, artifacts.bin);
    const damaged = artifacts.nobj.slice();
    damaged[24] ^= 1;
    assert.throws(() => parseAtomNobj(damaged), /CRC/);
  });

  test("artifact publication selects one complete immutable generation", async (t) => {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), "atom-artifacts-"));
    t.after(() => fs.rm(directory, { recursive: true, force: true }));
    const destination = path.join(directory, "program.atom");
    const first = (await render("ORG 4000H\nDB 1\n")).artifacts;
    const second = (await render("ORG 4000H\nDB 2\n")).artifacts;
    const published = await publishAtomArtifacts(destination, "program", first);
    assert.deepEqual(await fs.readFile(path.join(published.current, "program.bin")), Buffer.from([1]));
    const manifest = JSON.parse(await fs.readFile(path.join(published.current, "manifest.json"), "utf8"));
    assert.equal(manifest.format, "atom-artifact-set");
    assert.equal(manifest.generation, published.generation);

    const injected = {
      ...fs,
      async rename(source, target) {
        if (path.basename(source).startsWith(".current-")) {
          const error = new Error("injected pointer failure");
          error.code = "EIO";
          throw error;
        }
        return fs.rename(source, target);
      },
    };
    await assert.rejects(
      () => publishAtomArtifacts(destination, "program", second, { filesystem: injected }),
      (error) => error?.category === "publication" && error?.code === "generation-publish",
    );
    assert.deepEqual(await fs.readFile(path.join(published.current, "program.bin")), Buffer.from([1]));
    assert.deepEqual((await fs.readdir(destination)).filter((name) => name.startsWith(".current-")), []);

    const republished = await publishAtomArtifacts(destination, "program", second);
    assert.notEqual(republished.generation, published.generation);
    assert.deepEqual(await fs.readFile(path.join(republished.current, "program.bin")), Buffer.from([2]));

    await fs.writeFile(path.join(published.generationDirectory, "program.bin"), Buffer.from([9]));
    await assert.rejects(
      () => publishAtomArtifacts(destination, "program", first),
      (error) => error?.category === "publication" && error?.code === "generation-conflict",
    );
    assert.deepEqual(await fs.readFile(path.join(republished.current, "program.bin")), Buffer.from([2]));
  });

  test("selected flat outputs may begin at the first emitted address and COM validates $0100", async () => {
    const input = project("ORG 100H\nDB 1,2,3\n");
    const assembled = await assembleResolvedAtomProject(input, {
      target: { start: 0, capacity: 0xffff },
    });
    const artifacts = renderAtomArtifacts({ project: input, ...assembled }, { base: 0x100, entryAddress: 0x100 });
    assert.deepEqual(artifacts.bin, Uint8Array.of(1, 2, 3));
    assert.equal(artifacts.hex, ":03010000010203F6\n:00000001FF\n");
    assert.strictEqual(
      writeAtomCom({ base: 0x100, end: 0x103, bytes: artifacts.bin }, { entryAddress: 0x100 }),
      artifacts.bin,
    );
    assert.throws(
      () => writeAtomCom({ base: 0, end: 3, bytes: artifacts.bin }, { entryAddress: 0x100 }),
      /load and entry address/,
    );
  });

  test("flat-image sink retains the exclusive $10000 endpoint", async () => {
    const input = project("ORG 0FFFFH\nDB 5AH\n");
    const target = { start: 0xffff, capacity: 1 };
    const expected = await assembleResolvedAtomProject(input, { target });
    const sink = createFlatImageAtomSink();
    const actual = await assembleResolvedAtomProject(input, { target, sink });

    assert.equal(actual.generation.finalCursor, 0x10000);
    assert.equal(actual.generation.highWater, 0x10000);
    assert.equal(sink.snapshot().materialized.end, 0x10000);
    assert.deepEqual(
      sink.snapshot().materialized.bytes,
      materializeAtomGeneration(expected.generation).bytes,
    );
  });

  test("selected output publication stages every file and rolls back a failed replacement", async (t) => {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), "atom-selected-"));
    t.after(() => fs.rm(directory, { recursive: true, force: true }));
    const binary = path.join(directory, "program.bin");
    const listing = path.join(directory, "program.lst");
    await publishAtomOutputFiles([
      { path: binary, bytes: Uint8Array.of(1) },
      { path: listing, bytes: "first\n" },
    ]);
    assert.deepEqual(await fs.readFile(binary), Buffer.from([1]));
    assert.equal(await fs.readFile(listing, "utf8"), "first\n");

    const injected = {
      ...fs,
      async rename(source, target) {
        if (source.endsWith(".tmp") && target === listing) throw Object.assign(new Error("injected"), { code: "EIO" });
        return fs.rename(source, target);
      },
    };
    await assert.rejects(
      () => publishAtomOutputFiles([
        { path: binary, bytes: Uint8Array.of(2) },
        { path: listing, bytes: "second\n" },
      ], { filesystem: injected }),
      (error) => error?.category === "publication" && error?.code === "output-transaction",
    );
    assert.deepEqual(await fs.readFile(binary), Buffer.from([1]));
    assert.equal(await fs.readFile(listing, "utf8"), "first\n");
  });

  test("D8 retains distinct identities for reused private symbols after native eviction", async () => {
    const { artifacts } = await render([
      "ORG 4000H",
      "FIRST:",
      ".LOOP: NOP",
      "SECOND:",
      ".LOOP: NOP",
      "",
    ].join("\n"));
    const locals = artifacts.d8.symbols.filter(({ name }) => name === ".LOOP");
    assert.deepEqual(locals.map(({ address }) => address), [0x4000, 0x4001]);
    assert.equal(new Set(locals.map(({ identity }) => identity)).size, 2);
    assert.ok(locals.every(({ scope }) => scope === "local"));
  });
});

describe("Binary includes", () => {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  async function projectRoot(t, files) {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-incbin-"));
    t.after(() => fs.rm(root, { recursive: true, force: true }));
    for (const [name, contents] of Object.entries(files)) {
      const destination = path.join(root, name);
      await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.writeFile(destination, contents);
    }
    return root;
  }

  test("INCBIN snapshots one confined binary and preserves native addresses", async (t) => {
    const source = [
      "ORG 4000H",
      "JR AFTER",
      'DATA: INCBIN "assets/payload.bin"',
      "AFTER:",
      "LD HL,DATA",
      "",
    ].join("\n");
    const root = await projectRoot(t, {
      "main.asm": source,
      "assets/payload.bin": Uint8Array.from([0xde, 0xad, 0xbe]),
    });
    const project = await resolveAtomProject({ root, entry: "main.asm" });
    const part = project.parts[0];
    assert.equal(decoder.decode(part.originalBytes), source);
    assert.equal(part.compilerBytes.length, part.originalBytes.length);
    assert.match(decoder.decode(part.compilerBytes), /^DATA: DS 3,0\s*$/m);
    assert.deepEqual(part.binaryIncludes.map(({ logicalIdentity, line, bytes }) => ({
      logicalIdentity,
      line,
      bytes: [...bytes],
    })), [{ logicalIdentity: "assets/payload.bin", line: 3, bytes: [0xde, 0xad, 0xbe] }]);

    await fs.writeFile(path.join(root, "assets/payload.bin"), Uint8Array.from([1, 2, 3]));
    const assembled = await assembleResolvedAtomProject(project, {
      target: { start: 0x4000, capacity: 0x100 },
    });
    assert.deepEqual([...materializeAtomGeneration(assembled.generation).bytes], [
      0x18, 0x03, 0xde, 0xad, 0xbe, 0x21, 0x02, 0x40,
    ]);
    assert.equal(assembled.generation.finalCursor, 0x4008);
  });

  test("INCBIN rejects malformed, escaping, missing, and oversized inputs", async (t) => {
    const cases = [
      ['INCBIN payload.bin\n', {}, "preprocessing", "invalid-incbin"],
      ['INCBIN "café.bin"\n', {}, "preprocessing", "invalid-incbin"],
      ['INCBIN "../payload.bin"\n', {}, "dependency", "root-escape"],
      ['INCBIN "missing.bin"\n', {}, "dependency", "missing-source"],
      ['INCBIN "payload.bin", LENGTH\n', { "payload.bin": Uint8Array.of(1) }, "preprocessing", "invalid-incbin-count"],
      ['INCBIN "payload.bin", 2\n', { "payload.bin": Uint8Array.of(1) }, "preprocessing", "incbin-size"],
      ['INCBIN "large.bin"\n', { "large.bin": new Uint8Array(0x10000) }, "preprocessing", "incbin-size"],
    ];
    for (const [source, files, category, code] of cases) {
      const root = await projectRoot(t, { "main.asm": source, ...files });
      await assert.rejects(
        () => resolveAtomProject({ root, entry: "main.asm" }),
        (error) => error?.category === category && error?.code === code && error?.location?.line === 1,
        source,
      );
    }

    const inactive = await projectRoot(t, {
      "main.asm": '%IF 0\nINCBIN "missing.bin"\n%ENDIF\nNOP\n',
    });
    const result = await assembleAtomProject({
      root: inactive,
      entry: "main.asm",
      target: { start: 0x4000, capacity: 1 },
    });
    assert.deepEqual([...materializeAtomGeneration(result.generation).bytes], [0x00]);

    const boundary = await projectRoot(t, {
      "main.asm": 'INCBIN "empty.bin"\nINCBIN "maximum.bin"\n',
      "empty.bin": new Uint8Array(0),
      "maximum.bin": new Uint8Array(0xffff),
    });
    const project = await resolveAtomProject({ root: boundary, entry: "main.asm" });
    assert.deepEqual(project.parts[0].binaryIncludes.map(({ bytes }) => bytes.length), [0, 0xffff]);

    const countedPrefix = await projectRoot(t, {
      "main.asm": 'INCBIN "large.bin", 3\n',
      "large.bin": new Uint8Array(0x10000).fill(0x5a),
    });
    const prefixProject = await resolveAtomProject({ root: countedPrefix, entry: "main.asm" });
    assert.deepEqual([...prefixProject.parts[0].binaryIncludes[0].bytes], [0x5a, 0x5a, 0x5a]);
  });
});

describe("Native execution", () => {
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
        const bytes =
          source instanceof Uint8Array ? source : encoder.encode(source);
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
      () =>
        assembleAtomProject({
          root,
          entry: "main.asm",
          target: { start: 0x4000, capacity: 0x100 },
        }),
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
    assert.deepEqual(error.sink.lifecycle, [
      "begin",
      "image",
      "image",
      "image",
      "abort",
    ]);
    assert.equal(error.sink.generation, undefined);
    assert.equal(error.native.part, 0);
    assert.equal(error.native.offset, source.indexOf("Missing"));
  });

  test("an error in an included part is attributed to that physical source identity", async (t) => {
    const root = await projectRoot(t, {
      "bad.asm": "LD BC,A\n",
      "main.asm": '%include "bad.asm"\nNOP\n',
    });
    const error = await assemblyError(
      () =>
        assembleAtomProject({
          root,
          entry: "main.asm",
          target: { start: 0x4000, capacity: 0x100 },
        }),
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

  test("a thrown host service is converted to failure so native Atom can abort", async () => {
    const base = createMemoryAtomSink();
    const cause = new Error("injected host exception");
    const sink = Object.freeze({
      begin: (value) => base.begin(value),
      image: () => {
        throw cause;
      },
      patch: (value) => base.patch(value),
      commit: (value) => base.commit(value),
      abort: () => base.abort(),
      snapshot: () => base.snapshot(),
    });
    const error = await assemblyError(
      () =>
        assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
          target: { start: 0x4000, capacity: 0x100 },
          sink,
        }),
      "output",
      "sink",
    );
    assert.equal(error.cause, cause);
    assert.deepEqual(
      error.execution.serviceTrace.map(({ status }) => status),
      [0, 0xef, 0],
    );
    assert.equal(error.sink.open, false);
  });

  test("native memory layout rejects overlapping arenas", async () => {
    await assemblyError(
      () =>
        assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
          target: { start: 0, capacity: 1 },
          nativeMemoryLayout: {
            symbolStart: 0x4100,
            symbolEnd: 0xa100,
          },
        }),
      "configuration",
      "memory-map",
    );
  });

  test("runtime budget failure discards an open host generation", async () => {
    const base = createMemoryAtomSink();
    const error = await assemblyError(
      () =>
        assembleResolvedAtomProject(resolvedParts(["NOP\n"]), {
          target: { start: 0x4000, capacity: 0x100 },
          maxInstructions: 240,
          sink: base,
        }),
      "runtime",
      "budget",
    );
    assert.equal(error.sink.open, false);
    assert.deepEqual(error.sink.lifecycle, ["begin", "abort"]);
  });
});

describe("Named object adapter", () => {
  const encoder = new TextEncoder();

  function project(source) {
    const bytes = encoder.encode(source);
    return {
      parts: [{
        ordinal: 0,
        bank: 0,
        logicalIdentity: "source/0.asm",
        originalBytes: bytes,
        compilerBytes: bytes,
        binaryIncludes: [],
      }],
    };
  }

  test("Atom assembles through named objects and publishes one patched flat image", async () => {
    const source = [
      "ORG 4000H",
      "JR Later",
      "DS 2",
      "Later:",
      "DB 0,1AH,7FH,80H,0FFH",
      "",
    ].join("\n");
    const provider = new MemoryNamedObjectServices(new Map([
      ["source/0.asm", encoder.encode(source)],
      ["build/program.bin", encoder.encode("old")],
    ]));
    const toolProfile = createNamedObjectAtomAdapter({
      provider,
      sourceNames: ["source/0.asm"],
      outputName: "build/program.bin",
    });
    const result = await assembleResolvedAtomProject(project(source), {
      target: { start: 0x4000, capacity: 0x100 },
      toolProfile,
    });

    assert.deepEqual([...provider.bytes("build/program.bin")], [
      0x18, 0x02, 0x00, 0x00, 0x00, 0x1a, 0x7f, 0x80, 0xff,
    ]);
    assert.deepEqual(result.execution.serviceTrace.map(({ method }) => method), [
      "begin", "image", "image", "patch-byte", "image", "image", "image", "image", "image", "commit",
    ]);
    assert.equal(provider.openHandleCount, 0);
  });

  test("Atom abort preserves the prior named object and a later build succeeds", async () => {
    const bad = "ORG 4000H\nLD BC,A\n";
    const good = "ORG 4000H\nDB 80H,0FFH\n";
    const provider = new MemoryNamedObjectServices(new Map([
      ["source/0.asm", encoder.encode(bad)],
      ["build/program.bin", Uint8Array.from([1, 2, 3])],
    ]));
    let toolProfile = createNamedObjectAtomAdapter({
      provider,
      sourceNames: ["source/0.asm"],
      outputName: "build/program.bin",
    });
    await assert.rejects(
      () => assembleResolvedAtomProject(project(bad), {
        target: { start: 0x4000, capacity: 0x100 },
        toolProfile,
      }),
      (error) => error?.category === "source",
    );
    assert.deepEqual([...provider.bytes("build/program.bin")], [1, 2, 3]);
    assert.equal(provider.openHandleCount, 0);

    provider.seed("source/0.asm", encoder.encode(good));
    toolProfile = createNamedObjectAtomAdapter({
      provider,
      sourceNames: ["source/0.asm"],
      outputName: "build/program.bin",
    });
    await assembleResolvedAtomProject(project(good), {
      target: { start: 0x4000, capacity: 0x100 },
      toolProfile,
    });
    assert.deepEqual([...provider.bytes("build/program.bin")], [0x80, 0xff]);
  });
});

describe("ASO stream", async () => {
  const vectors = JSON.parse(await readFile(new URL("./fixtures/aso-v1.json", import.meta.url)));
  const unhex = (hex) => Uint8Array.from(Buffer.from(hex.replaceAll(/\s/g, ""), "hex"));
  const decode = (bytes) => [...readAsoOperations([bytes])];
  const join = (chunks) => Uint8Array.from(Buffer.concat(chunks));
  function encode(events, bytewise = false) {
    const chunks = [];
    const { origin, fill } = events[0];
    const writer = createAsoWriter({ origin, fill, write: (chunk) => chunks.push(chunk) });
    for (const event of events.slice(1)) {
      if (event.kind === "commit") writer.commit(event);
      else if (event.kind === "image" && bytewise) {
        for (let i = 0; i < event.bytes.length; i += 1) {
          writer.image(event.address + i, event.bytes.subarray(i, i + 1));
        }
      } else writer[event.kind](event.address, event.bytes);
    }
    return join(chunks);
  }
  function materialize(events) {
    const begin = events[0];
    const end = events.at(-1);
    assert.equal(end.kind, "commit");
    const result = new Uint8Array(end.highWater - begin.origin).fill(begin.fill);
    for (const event of events.slice(1, -1)) result.set(event.bytes, event.address - begin.origin);
    return result;
  }

  test("ASO v1 shared vectors encode and decode byte-exactly at every input split", () => {
    for (const vector of vectors.valid) {
      const bytes = unhex(vector.hex);
      const expectedEvents = decode(bytes);
      assert.equal(expectedEvents[0].origin, vector.origin);
      assert.deepEqual(expectedEvents.at(-1), {
        kind: "commit", highWater: vector.highWater, finalCursor: vector.finalCursor,
      });
      const expected = join([new Uint8Array(vector.zeroPrefix ?? 0), unhex(vector.image)]);
      assert.deepEqual(materialize(expectedEvents), expected, vector.name);
      assert.deepEqual(encode(expectedEvents), bytes, vector.name);
      assert.deepEqual(encode(expectedEvents, true), bytes, vector.name);
      for (let split = 0; split <= bytes.length; split += 1) {
        assert.deepEqual([...readAsoOperations([bytes.slice(0, split), bytes.slice(split)])], expectedEvents);
      }
      assert.deepEqual([...readAsoOperations(Array.from(bytes, (value) => Uint8Array.of(value)))], expectedEvents);
    }
  });

  test("ASO v1 rejects shared malformed vectors and every truncation before END", () => {
    for (const [name, hex] of vectors.invalid) assert.throws(() => decode(unhex(hex)), /ASO:/, name);
    for (const vector of vectors.valid) {
      const bytes = unhex(vector.hex);
      for (let length = 0; length < bytes.length; length += 1) {
        assert.throws(() => decode(bytes.slice(0, length)), /ASO:/, `${vector.name} truncated at ${length}`);
      }
    }
  });

  test("ASO invalid calls and I/O failures poison the tentative writer", () => {
    for (const invalid of [
      (w) => w.image(0x100, new Uint8Array()),
      (w) => w.image(0xffff, Uint8Array.of(1, 2)),
      (w) => w.image(0xff, Uint8Array.of(1)),
      (w) => w.image(0x100, Uint8Array.of(1)), // Prior image ends at $102.
      (w) => w.patch(0x102, Uint8Array.of(1)),
      (w) => w.patch(0x100, Uint8Array.of(1, 2, 3)),
      (w) => w.commit({ highWater: 0x101, finalCursor: 0x101 }),
      (w) => w.commit({ highWater: 0x102, finalCursor: 0x103 }),
      (w) => w.commit({ highWater: 0x10001, finalCursor: 0x102 }),
    ]) {
      const chunks = [];
      const writer = createAsoWriter({ origin: 0x100, write: (bytes) => chunks.push(bytes) });
      writer.image(0x100, Uint8Array.of(0, 0));
      assert.throws(() => invalid(writer), /ASO:/);
      assert.throws(() => writer.commit({ highWater: 0x102, finalCursor: 0x102 }), /closed/);
      assert.throws(() => decode(join(chunks)), /missing END/);
    }
    let calls = 0;
    const writer = createAsoWriter({ origin: 0x100, write() {
      if (++calls === 2) throw new Error("disk full");
    } });
    writer.image(0x100, Uint8Array.of(0));
    assert.throws(() => writer.commit({ highWater: 0x101, finalCursor: 0x101 }), /disk full/);
    assert.throws(() => writer.commit({ highWater: 0x101, finalCursor: 0x101 }), /closed/);
    const aborted = createAsoWriter({ origin: 0, write() {} });
    aborted.abort();
    assert.throws(() => aborted.image(0, Uint8Array.of(1)), /closed/);
  });
});

describe("Native object builder", () => {
  const encoder = new TextEncoder();
  const SOURCE_SELECTOR = 0x90;
  const OUTPUT_SELECTOR = 0x91;
  const CONFIG = 0x3800;
  const PART_TABLE = 0x3900;
  const PART_NAMES = 0x3c00;
  const OUTPUT_NAME = 0x3d00;
  const BUILD = 0x3d20;
  const DESCRIPTORS = 0x3d40;
  const COMMON_WORKSPACE = 0x4400;
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
    // The test's fixed tables begin at CONFIG; the harness code must end below it.
    assert.ok(loadAddress >= CONFIG || census.residentEnd <= CONFIG, "harness code overlaps the test tables");
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
    putWord(memory, BUILD + 11, options.targetStart ?? 0x100);
    putWord(memory, BUILD + 13, options.targetCapacity ?? 0x4000);

    const invoke = (entry, setup, maximum = 20_000_000) => {
      memory[stack] = RETURN_SENTINEL & 0xff;
      memory[stack + 1] = RETURN_SENTINEL >>> 8;
      runtime.cpu.sp = stack;
      runtime.cpu.pc = entry;
      setup(runtime.cpu);
      for (let count = 0; runtime.cpu.pc !== RETURN_SENTINEL && count < maximum; count += 1) {
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
          continue;
        }
        runtime.step();
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
      census,
      residentUnchanged: Buffer.from(memory.slice(loadAddress, census.residentEnd)).equals(residentBefore),
    };
  }

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
    assert.equal(harness.report.fixedWorkspaceStart, 0x1800);
    assert.equal(harness.debugMap.format, "d8-debug-map");
    assert.ok(Object.keys(harness.debugMap.files).length > 0);
    const run = await runProject([
      "ORG $100\nJR LATER\n",
      "LATER:\nDB $5A\n",
    ], {
      harness,
      commonWorkspace: 0x1c00,
      symbolStart: 0x4000,
      symbolEnd: 0x5000,
      pendingStart: 0x5000,
      pendingEnd: 0x5800,
      stack: 0x7ff0,
      romRanges: [{ start: 0x8000, end: harness.report.residentEnd }],
    });
    assert.deepEqual(run.result, { status: 0, carry: 0 });
    assert.deepEqual([...run.output], [0x18, 0x00, 0x5a]);
    assert.equal(run.sourceOpenHandles, 0);
    assert.equal(run.outputOpenHandles, 0);
    assert.equal(run.residentUnchanged, true);
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
});

describe("Source projects", () => {
  async function project(t, files) {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-project-"));
    t.after(() => fs.rm(root, { recursive: true, force: true }));
    for (const [name, contents] of Object.entries(files)) {
      await fs.mkdir(path.dirname(path.join(root, name)), { recursive: true });
      await fs.writeFile(path.join(root, name), contents);
    }
    return root;
  }

  test("includes deduplicate a diamond and conditionals keep original source positions", async (t) => {
    const root = await project(t, {
      "main.asm": '%define ACTIVE 1\r\n%if ACTIVE\r\n%include "a.asm"\r\n%include "b.asm"\r\n%else\r\n%include "missing.asm"\r\n%endif\r\nRET\r\n',
      "a.asm": '%include "common;part.asm" ; Dependency shared by both branches.\nDB 2\n',
      "b.asm": '%include "common;part.asm"\nDB 3\n',
      "common;part.asm": 'ORG $4000\nDB 1\n',
    });
    const result = await assembleAtomProject({ root, entry: "main.asm", target: { start: 0x4000, capacity: 16 } });
    assert.deepEqual(result.project.parts.map(({ logicalIdentity }) => logicalIdentity), ["common;part.asm", "a.asm", "b.asm", "main.asm"]);
    assert.deepEqual([...materializeAtomGeneration(result.generation).bytes], [1, 2, 3, 0xc9]);
    for (const part of result.project.parts) {
      assert.equal(part.compilerBytes.length, part.originalBytes.length);
      for (let offset = 0; offset < part.originalBytes.length; offset += 1) {
        if ([10, 13].includes(part.originalBytes[offset])) assert.equal(part.compilerBytes[offset], part.originalBytes[offset]);
      }
    }
  });

  test("projects reject dependency escapes, cycles and invalid preprocessing", async (t) => {
    for (const [files, code] of [
      [{ "main.asm": '%include "../outside.asm"\n' }, "root-escape"],
      [{ "main.asm": '%include "a.asm"\n', "a.asm": '%include "main.asm"\n' }, "dependency-cycle"],
      [{ "main.asm": '%include "missing.asm"\n' }, "missing-source"],
      [{ "main.asm": '%if MISSING\nNOP\n%endif\n' }, "undefined-definition"],
      [{ "main.asm": '%if 1\nNOP\n' }, "unterminated-conditional"],
      [{ "main.asm": '%define V 1\n%define v 2\n' }, "duplicate-definition"],
    ]) {
      const root = await project(t, files);
      await assert.rejects(() => resolveAtomProject({ root, entry: "main.asm" }), (error) => error.code === code, code);
    }
    const root = await project(t, { "main.asm": '%include "escape.asm"\n' });
    const outside = await fs.mkdtemp(path.join(os.tmpdir(), "atom-outside-"));
    t.after(() => fs.rm(outside, { recursive: true, force: true }));
    await fs.writeFile(path.join(outside, "part.asm"), "NOP\n");
    await fs.symlink(path.join(outside, "part.asm"), path.join(root, "escape.asm"));
    await assert.rejects(() => resolveAtomProject({ root, entry: "main.asm" }), (error) => error.code === "root-escape");
  });
});
