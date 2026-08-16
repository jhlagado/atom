import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  parseSourcePlan,
  writeSourcePlanAtomically,
} from "../src/host/source-packager/index.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const plan = Object.freeze({
  records: Object.freeze([{ bank: 0, logicalIdentity: "main.asm" }]),
});

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "atom-plan-writer-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const destination = path.join(directory, "sources.sp1");
  await fs.writeFile(destination, "old");
  return { directory, destination };
}

async function assertPreserved(directory, destination) {
  assert.equal(await fs.readFile(destination, "utf8"), "old");
  assert.deepEqual((await fs.readdir(directory)).sort(), ["sources.sp1"]);
}

test("atomic writer replaces an existing plan with validated exact bytes", async (t) => {
  const { directory, destination } = await fixture(t);
  const bytes = await writeSourcePlanAtomically(destination, plan);

  assert.deepEqual(Uint8Array.from(await fs.readFile(destination)), bytes);
  assert.deepEqual(parseSourcePlan(bytes), plan);
  assert.deepEqual(await fs.readdir(directory), ["sources.sp1"]);
});

test("serialization or validation failure occurs before a temporary file opens", async (t) => {
  const { directory, destination } = await fixture(t);
  let opens = 0;
  const filesystem = {
    open: async () => { opens += 1; throw new Error("must not open"); },
  };
  await assert.rejects(
    () => writeSourcePlanAtomically(destination, { records: [] }, { filesystem }),
    (error) => error?.category === "plan",
  );
  assert.equal(opens, 0);
  await assertPreserved(directory, destination);
});

test("write failure preserves the prior plan and removes only its temp", async (t) => {
  const { directory, destination } = await fixture(t);
  const filesystem = {
    open: async (...args) => {
      const handle = await fs.open(...args);
      return {
        async writeFile() { throw new Error("write failed"); },
        sync: () => handle.sync(),
        close: () => handle.close(),
      };
    },
    rename: (...args) => fs.rename(...args),
    unlink: (...args) => fs.unlink(...args),
  };
  await assert.rejects(
    () => writeSourcePlanAtomically(destination, plan, { filesystem }),
    (error) => error?.category === "output" && error?.code === "plan-write-failed",
  );
  await assertPreserved(directory, destination);
});

test("rename failure preserves the prior plan and removes only its temp", async (t) => {
  const { directory, destination } = await fixture(t);
  const filesystem = {
    open: (...args) => fs.open(...args),
    async rename() { throw new Error("rename failed"); },
    unlink: (...args) => fs.unlink(...args),
  };
  await assert.rejects(
    () => writeSourcePlanAtomically(destination, plan, { filesystem }),
    (error) => error?.category === "output" && error?.code === "plan-rename-failed",
  );
  await assertPreserved(directory, destination);
});

test("exclusive-open failure never deletes a temporary path the writer did not create", async (t) => {
  const { directory, destination } = await fixture(t);
  let foreignPath;
  const filesystem = {
    async open(tempPath) {
      foreignPath = tempPath;
      await fs.writeFile(tempPath, "foreign");
      const error = new Error("already exists");
      error.code = "EEXIST";
      throw error;
    },
    rename: (...args) => fs.rename(...args),
    unlink: (...args) => fs.unlink(...args),
  };

  await assert.rejects(
    () => writeSourcePlanAtomically(destination, plan, { filesystem }),
    (error) => error?.category === "output" && error?.code === "plan-write-failed",
  );
  assert.equal(await fs.readFile(foreignPath, "utf8"), "foreign");
  assert.equal(await fs.readFile(destination, "utf8"), "old");
  assert.deepEqual((await fs.readdir(directory)).sort(), [path.basename(foreignPath), "sources.sp1"].sort());
});

test("writer validates the exact serialized bytes before opening output", async (t) => {
  const { directory, destination } = await fixture(t);
  let opens = 0;
  const filesystem = {
    async open(tempPath, flags) {
      opens += 1;
      assert.equal(flags, "wx");
      assert.equal(path.dirname(tempPath), directory);
      return fs.open(tempPath, flags);
    },
    rename: (...args) => fs.rename(...args),
    unlink: (...args) => fs.unlink(...args),
  };
  const bytes = await writeSourcePlanAtomically(destination, plan, { filesystem });
  assert.equal(opens, 1);
  assert.equal(decoder.decode(bytes), "SP1 1\nP 0 main.asm\nEND\n");
  assert.deepEqual(parseSourcePlan(encoder.encode(decoder.decode(bytes))), plan);
});
