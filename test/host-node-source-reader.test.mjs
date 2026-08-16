import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

let api;
try {
  api = await import("../src/host/source-packager/index.mjs");
} catch {
  api = {};
}

const decoder = new TextDecoder();

function readerFactory() {
  assert.equal(
    typeof api.createNodeSourceReader,
    "function",
    "createNodeSourceReader export is missing",
  );
  return api.createNodeSourceReader;
}

async function temporaryDirectory(t, prefix = "atom-source-reader-") {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), prefix));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  return directory;
}

async function write(root, relativePath, contents) {
  const physicalPath = path.join(root, relativePath);
  await fs.mkdir(path.dirname(physicalPath), { recursive: true });
  await fs.writeFile(physicalPath, contents);
  return physicalPath;
}

async function assertDependencyError(action, code) {
  await assert.rejects(action, (error) => {
    assert.equal(error?.name, "SourcePackagerError");
    assert.ok(["project", "dependency"].includes(error?.category));
    assert.equal(error?.code, code);
    return true;
  });
}

test("reader returns physical, dependency, logical, and byte identities", async (t) => {
  const root = await temporaryDirectory(t);
  const mainPath = await write(root, "src/main.asm", "%include \"../lib/a.asm\"\nNOP\n");
  const dependencyPath = await write(root, "lib/a.asm", "LD A,1\n");
  const reader = await readerFactory()(root);

  const main = await reader.resolveEntry("src/main.asm");
  const dependency = await reader.resolveDependency(main, "../lib/a.asm");

  assert.equal(main.physicalPath, await fs.realpath(mainPath));
  assert.equal(main.dependencyIdentity, await fs.realpath(mainPath));
  assert.equal(main.logicalIdentity, "src/main.asm");
  assert.equal(decoder.decode(main.originalBytes), "%include \"../lib/a.asm\"\nNOP\n");
  assert.equal(dependency.physicalPath, await fs.realpath(dependencyPath));
  assert.equal(dependency.dependencyIdentity, await fs.realpath(dependencyPath));
  assert.equal(dependency.logicalIdentity, "lib/a.asm");
  assert.equal(decoder.decode(dependency.originalBytes), "LD A,1\n");
  assert.equal(Object.isFrozen(main), true);
  assert.equal(Object.isFrozen(dependency), true);
});

test("reader rejects absolute paths and lexical root escapes", async (t) => {
  const root = await temporaryDirectory(t);
  await write(root, "main.asm", "NOP\n");
  const reader = await readerFactory()(root);
  const main = await reader.resolveEntry("main.asm");

  await assertDependencyError(
    () => reader.resolveEntry(path.join(root, "main.asm")),
    "root-escape",
  );
  await assertDependencyError(
    () => reader.resolveDependency(main, "../../outside.asm"),
    "root-escape",
  );
});

test("reader rejects a symlink whose real target escapes the project root", async (t) => {
  const root = await temporaryDirectory(t, "atom-source-root-");
  const outside = await temporaryDirectory(t, "atom-source-outside-");
  const secret = await write(outside, "secret.asm", "HALT\n");
  await fs.symlink(secret, path.join(root, "escape.asm"));
  const reader = await readerFactory()(root);

  await assertDependencyError(() => reader.resolveEntry("escape.asm"), "root-escape");
});

test("reader rejects case-conflicting physical spelling on every host filesystem", async (t) => {
  const root = await temporaryDirectory(t);
  await write(root, "Lib/Main.asm", "NOP\n");
  const reader = await readerFactory()(root);

  await assertDependencyError(() => reader.resolveEntry("lib/Main.asm"), "identity-alias");
  await assertDependencyError(() => reader.resolveEntry("Lib/main.asm"), "identity-alias");
});

test("different in-root aliases have one canonical dependency and logical identity", async (t) => {
  const root = await temporaryDirectory(t);
  const target = await write(root, "lib/a.asm", "NOP\n");
  await fs.symlink(target, path.join(root, "alias.asm"));
  const reader = await readerFactory()(root);

  const direct = await reader.resolveEntry("lib/a.asm");
  const alias = await reader.resolveEntry("alias.asm");

  assert.strictEqual(alias, direct);
  assert.equal(alias.dependencyIdentity, await fs.realpath(target));
  assert.equal(alias.logicalIdentity, "lib/a.asm");
});

test("relocating a project preserves logical identities and source bytes", async (t) => {
  const firstRoot = await temporaryDirectory(t, "atom-source-first-");
  const secondRoot = await temporaryDirectory(t, "atom-source-second-");
  await write(firstRoot, "src/main.asm", "NOP\n");
  await write(secondRoot, "src/main.asm", "NOP\n");

  const first = await (await readerFactory()(firstRoot)).resolveEntry("src/main.asm");
  const second = await (await readerFactory()(secondRoot)).resolveEntry("src/main.asm");

  assert.notEqual(first.physicalPath, second.physicalPath);
  assert.equal(first.logicalIdentity, second.logicalIdentity);
  assert.deepEqual(first.originalBytes, second.originalBytes);
});

test("reader snapshots each dependency once and ignores later filesystem mutation", async (t) => {
  const root = await temporaryDirectory(t);
  const mainPath = await write(root, "main.asm", "NOP\n");
  let readCount = 0;
  const filesystem = {
    realpath: (...args) => fs.realpath(...args),
    readdir: (...args) => fs.readdir(...args),
    async readFile(...args) {
      readCount += 1;
      return fs.readFile(...args);
    },
  };
  const reader = await readerFactory()(root, { filesystem });

  const first = await reader.resolveEntry("main.asm");
  await fs.writeFile(mainPath, "HALT\n");
  const second = await reader.resolveEntry("main.asm");

  assert.strictEqual(second, first);
  assert.equal(readCount, 1);
  assert.equal(decoder.decode(second.originalBytes), "NOP\n");
});

test("reader reports missing sources with dependency identity context", async (t) => {
  const root = await temporaryDirectory(t);
  await write(root, "main.asm", "NOP\n");
  const reader = await readerFactory()(root);
  const main = await reader.resolveEntry("main.asm");

  await assertDependencyError(
    () => reader.resolveDependency(main, "missing.asm"),
    "missing-source",
  );
});
