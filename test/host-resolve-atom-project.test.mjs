import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

let atomApi;
try {
  atomApi = await import("../src/host/resolve-atom-project.mjs");
} catch {
  atomApi = {};
}

const fixtureRoot = fileURLToPath(new URL("fixtures/project-preparation/diamond/", import.meta.url));
const encoder = new TextEncoder();
const decoder = new TextDecoder();

function resolveAtomProject(request) {
  assert.equal(typeof atomApi.resolveAtomProject, "function", "resolveAtomProject export is missing");
  return atomApi.resolveAtomProject(request);
}

async function temporaryRoot(t, prefix = "atom-resolve-project-") {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  return root;
}

async function copyDiamond(t) {
  const root = await temporaryRoot(t);
  await fs.cp(fixtureRoot, root, { recursive: true });
  const displayPath = path.join(root, "display.asm");
  const display = await fs.readFile(displayPath, "utf8");
  await fs.writeFile(displayPath, display.replaceAll("\n", "\r\n"));
  return root;
}

async function writeProject(t, files) {
  const root = await temporaryRoot(t);
  for (const [logicalIdentity, contents] of Object.entries(files)) {
    const destination = path.join(root, logicalIdentity);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.writeFile(destination, contents);
  }
  return root;
}

function placement() {
  return {
    defaultBank: 0,
    banks: {
      "display.asm": 1,
      "hardware.asm": 2,
    },
  };
}

function byteArray(bytes) {
  return [...bytes];
}

function portableProvenance(part) {
  const { physicalPath: _physicalPath, ...portable } = part.provenance;
  return portable;
}

function assertMaskAndOffsetIdentity(part) {
  assert.equal(part.compilerBytes.length, part.originalBytes.length, part.logicalIdentity);
  const masked = new Uint8Array(part.originalBytes.length);
  for (const { start, end } of part.maskedRanges) masked.fill(1, start, end);
  for (let offset = 0; offset < part.originalBytes.length; offset += 1) {
    const original = part.originalBytes[offset];
    const compiler = part.compilerBytes[offset];
    if (original === 0x0a || original === 0x0d) {
      assert.equal(compiler, original, `${part.logicalIdentity}:${offset}: newline moved`);
    } else if (masked[offset] === 1) {
      assert.equal(compiler, 0x20, `${part.logicalIdentity}:${offset}: masked byte is not space`);
    } else {
      assert.equal(compiler, original, `${part.logicalIdentity}:${offset}: active byte changed`);
    }
  }
}

function maskLineNumbers(originalBytes, selectedLines) {
  const bytes = originalBytes.slice();
  const selected = new Set(selectedLines);
  let line = 1;
  for (let offset = 0; offset < bytes.length; offset += 1) {
    if (bytes[offset] === 0x0a) {
      line += 1;
    } else if (bytes[offset] !== 0x0d && selected.has(line)) {
      bytes[offset] = 0x20;
    }
  }
  return bytes;
}

function compilerBoundary(parts) {
  const compilerStream = [];
  const attribution = [];
  const records = parts.map((part) => {
    for (let offset = 0; offset < part.compilerBytes.length; offset += 1) {
      compilerStream.push(part.compilerBytes[offset]);
      attribution.push([part.logicalIdentity, offset]);
    }
    return {
      ordinal: part.ordinal,
      bank: part.bank,
      logicalIdentity: part.logicalIdentity,
      originalByteLength: part.provenance.originalByteLength,
    };
  });
  return { records, compilerStream, attribution };
}

async function explicitDiamondParts(root) {
  const specifications = [
    ["hardware.asm", 2, []],
    ["display.asm", 1, [1, 2, 3]],
    ["input.asm", 0, [1, 2, 3, 4, 5]],
    ["main.asm", 0, [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 14]],
  ];
  return Promise.all(specifications.map(async ([logicalIdentity, bank, maskedLines], ordinal) => {
    const originalBytes = Uint8Array.from(await fs.readFile(path.join(root, logicalIdentity)));
    return {
      ordinal,
      bank,
      logicalIdentity,
      originalBytes,
      compilerBytes: maskLineNumbers(originalBytes, maskedLines),
      provenance: { originalByteLength: originalBytes.length },
    };
  }));
}

async function assertHostError(action, category, code) {
  await assert.rejects(action, (error) => {
    assert.equal(error?.name, "SourcePreparationError");
    assert.equal(error?.category, category);
    assert.equal(error?.code, code);
    return true;
  });
}

test("Atom composition resolves, masks, places, snapshots, and relocates one diamond", async (t) => {
  const firstRoot = await copyDiamond(t);
  const secondRoot = await copyDiamond(t);
  const request = {
    root: firstRoot,
    entry: "main.asm",
    definitions: {},
    placement: placement(),
  };
  const first = await resolveAtomProject(request);
  const second = await resolveAtomProject({ ...request, root: secondRoot, placement: placement() });

  assert.deepEqual(first.parts.map((part) => [part.logicalIdentity, part.ordinal, part.bank]), [
    ["hardware.asm", 0, 2],
    ["display.asm", 1, 1],
    ["input.asm", 2, 0],
    ["main.asm", 3, 0],
  ]);
  assert.deepEqual(first.bankArray, [2, 1, 0, 0]);
  assert.equal(first.parts.filter((part) => part.logicalIdentity === "hardware.asm").length, 1);
  assert.equal(first.state.definitions.DEBUG, 1);

  for (const part of first.parts) {
    assertMaskAndOffsetIdentity(part);
    assert.equal(Object.isFrozen(part), true);
    assert.equal(Object.isFrozen(part.provenance), true);
    assert.equal(Object.isFrozen(part.dependencies), true);
    assert.equal(Object.isFrozen(part.maskedRanges), true);
  }
  assert.equal(Object.isFrozen(first), true);
  assert.equal(Object.isFrozen(first.parts), true);
  assert.equal(Object.isFrozen(first.state), true);
  assert.equal(Object.isFrozen(first.state.definitions), true);

  const display = first.parts.find((part) => part.logicalIdentity === "display.asm");
  assert.ok(byteArray(display.originalBytes).includes(0x0d), "display fixture did not exercise CRLF");
  const main = first.parts.find((part) => part.logicalIdentity === "main.asm");
  const instructionOffset = decoder.decode(main.originalBytes).indexOf("LD A,0FFFFH");
  assert.ok(instructionOffset > 0);
  assert.equal(
    decoder.decode(main.compilerBytes.slice(instructionOffset, instructionOffset + 11)),
    "LD A,0FFFFH",
  );
  assert.equal(main.provenance.diagnosticName, "main.asm");
  assert.equal(main.provenance.originalByteLength, main.originalBytes.length);
  assert.deepEqual(main.provenance.dependencyLocations.map((location) => location.logicalIdentity), [
    "main.asm",
    "main.asm",
  ]);

  assert.deepEqual(second.parts.map((part) => part.logicalIdentity), first.parts.map((part) => part.logicalIdentity));
  assert.deepEqual(
    second.parts.map((part) => byteArray(part.compilerBytes)),
    first.parts.map((part) => byteArray(part.compilerBytes)),
  );
  assert.deepEqual(second.parts.map(portableProvenance), first.parts.map(portableProvenance));
  assert.notEqual(second.parts[0].physicalPath, first.parts[0].physicalPath);

  const explicit = await explicitDiamondParts(firstRoot);
  assert.deepEqual(compilerBoundary(first.parts), compilerBoundary(explicit));

  const originalSnapshots = first.parts.map((part) => byteArray(part.originalBytes));
  const compilerSnapshots = first.parts.map((part) => byteArray(part.compilerBytes));
  await Promise.all(first.parts.map((part) => fs.writeFile(part.physicalPath, "MUTATED\n")));
  assert.deepEqual(first.parts.map((part) => byteArray(part.originalBytes)), originalSnapshots);
  assert.deepEqual(first.parts.map((part) => byteArray(part.compilerBytes)), compilerSnapshots);
});

test("Atom composition snapshots mutable project configuration before filesystem work", async (t) => {
  const root = await copyDiamond(t);
  const definitions = { HOST: 7 };
  const selectedPlacement = placement();
  const limits = {
    maxParts: 4,
    maxDepth: 3,
    maxLogicalPathBytes: 12,
    maxRetainedPathBytes: 43,
    maxBank: 2,
  };
  const pending = resolveAtomProject({
    root,
    entry: "main.asm",
    definitions,
    placement: selectedPlacement,
    limits,
  });
  definitions.HOST = 9;
  selectedPlacement.defaultBank = 9;
  selectedPlacement.banks["hardware.asm"] = 9;
  limits.maxParts = 1;

  const result = await pending;
  assert.equal(result.state.definitions.HOST, 7);
  assert.deepEqual(result.bankArray, [2, 1, 0, 0]);
  assert.equal(result.parts.length, 4);
});

test("Atom composition rejects dependency, preprocessing, and placement failures", async (t) => {
  const cases = [
    {
      name: "repeated import",
      files: {
        "main.asm": "%include \"a.asm\"\n%include \"./a.asm\"\nNOP\n",
        "a.asm": "NOP\n",
      },
      category: "dependency",
      code: "repeated-dependency",
    },
    {
      name: "missing source",
      files: { "main.asm": "%include \"missing.asm\"\nNOP\n" },
      category: "dependency",
      code: "missing-source",
    },
    {
      name: "root escape",
      files: { "main.asm": "%include \"../outside.asm\"\nNOP\n" },
      category: "dependency",
      code: "root-escape",
    },
    {
      name: "case alias",
      files: { "main.asm": "%include \"LIB.asm\"\nNOP\n", "lib.asm": "NOP\n" },
      category: "dependency",
      code: "identity-alias",
    },
    {
      name: "cycle",
      files: { "main.asm": "%include \"a.asm\"\nNOP\n", "a.asm": "%include \"main.asm\"\nNOP\n" },
      category: "dependency",
      code: "dependency-cycle",
    },
    {
      name: "unknown directive",
      files: { "main.asm": "%wat 1\nNOP\n" },
      category: "preprocessing",
      code: "unknown-directive",
    },
    {
      name: "undefined condition",
      files: { "main.asm": "%if MISSING\nNOP\n%endif\n" },
      category: "preprocessing",
      code: "undefined-definition",
    },
    {
      name: "conditional imbalance",
      files: { "main.asm": "%if 1\nNOP\n" },
      category: "preprocessing",
      code: "unterminated-conditional",
    },
  ];

  for (const item of cases) {
    await t.test(item.name, async (t) => {
      const root = await writeProject(t, item.files);
      await assertHostError(
        () => resolveAtomProject({ root, entry: "main.asm" }),
        item.category,
        item.code,
      );
    });
  }

  await t.test("invalid placement", async (t) => {
    const root = await writeProject(t, { "main.asm": "NOP\n", "unused.asm": "NOP\n" });
    await assertHostError(
      () => resolveAtomProject({
        root,
        entry: "main.asm",
        placement: { defaultBank: 0, banks: { "unused.asm": 1 } },
      }),
      "project",
      "unreachable-placement",
    );
  });
});

test("Atom composition selects only active includes", async (t) => {
  const root = await writeProject(t, {
    "main.asm": "%define TAKE_A 0\n%if TAKE_A\n%include \"missing.asm\"\n%else\n%include \"selected.asm\"\n%endif\nNOP\n",
    "selected.asm": "LD A,01110111B\n",
  });
  const project = await resolveAtomProject({ root, entry: "main.asm" });
  assert.deepEqual(project.parts.map((part) => part.logicalIdentity), ["selected.asm", "main.asm"]);
});

test("Atom composition enforces every graph and placement capacity at the boundary", async (t) => {
  const root = await copyDiamond(t);
  const logicalPathBytes = ["hardware.asm", "display.asm", "input.asm", "main.asm"]
    .map((name) => encoder.encode(name).length);
  const retainedPathBytes = logicalPathBytes.reduce((total, length) => total + length, 0);
  const exact = {
    maxParts: 4,
    maxDepth: 3,
    maxLogicalPathBytes: Math.max(...logicalPathBytes),
    maxRetainedPathBytes: retainedPathBytes,
    maxBank: 2,
  };
  const request = { root, entry: "main.asm", placement: placement() };
  const project = await resolveAtomProject({ ...request, limits: exact });
  assert.equal(project.parts.length, 4);
  assert.equal(project.retainedPathBytes, retainedPathBytes);

  for (const [field, code] of [
    ["maxParts", "part-capacity"],
    ["maxDepth", "depth-capacity"],
    ["maxLogicalPathBytes", "path-capacity"],
    ["maxRetainedPathBytes", "retained-path-capacity"],
    ["maxBank", "bank-capacity"],
  ]) {
    await assertHostError(
      () => resolveAtomProject({ ...request, limits: { ...exact, [field]: exact[field] - 1 } }),
      field === "maxBank" ? "project" : "dependency",
      code,
    );
  }
});

test("preprocessing failure returns no project and leaves the filesystem unchanged", async (t) => {
  const root = await writeProject(t, { "main.asm": "%if UNKNOWN\nNOP\n%endif\n" });
  const marker = path.join(root, "unrelated.txt");
  await fs.writeFile(marker, "unchanged\n");
  let project;

  await assertHostError(async () => {
    project = await resolveAtomProject({ root, entry: "main.asm" });
  }, "preprocessing", "undefined-definition");

  assert.equal(project, undefined);
  assert.equal(await fs.readFile(marker, "utf8"), "unchanged\n");
  assert.deepEqual((await fs.readdir(root)).sort(), ["main.asm", "unrelated.txt"]);
});
