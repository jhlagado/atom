import * as nodeFilesystem from "node:fs/promises";
import path from "node:path";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

let transactionOrdinal = 0;

function fail(code, message, cause) {
  throw new AtomAssemblyError("publication", code, message, { cause });
}

function bytesOf(value) {
  if (value instanceof Uint8Array) return value;
  if (typeof value === "string") return new TextEncoder().encode(value);
  fail("artifact-value", "artifact content must be bytes or text");
}

async function exists(filesystem, target) {
  try {
    await filesystem.access(target);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

export async function publishAtomOutputFiles(outputs, { filesystem = nodeFilesystem } = {}) {
  if (!Array.isArray(outputs) || outputs.length === 0) {
    fail("empty-output", "at least one output file is required");
  }
  transactionOrdinal += 1;
  const tag = `.atom-${process.pid}-${transactionOrdinal}`;
  const seen = new Set();
  const entries = outputs.map((output) => {
    const target = path.resolve(output.path);
    const key = process.platform === "win32" ? target.toLowerCase() : target;
    if (seen.has(key)) fail("duplicate-output", `output path is repeated: ${output.path}`);
    seen.add(key);
    return {
      target,
      directory: path.dirname(target),
      temporary: `${target}${tag}.tmp`,
      backup: `${target}${tag}.bak`,
      bytes: bytesOf(output.bytes),
      backedUp: false,
      published: false,
    };
  });

  try {
    for (const entry of entries) {
      await filesystem.mkdir(entry.directory, { recursive: true });
      const handle = await filesystem.open(entry.temporary, "wx");
      try {
        await handle.writeFile(entry.bytes);
        await handle.sync();
      } finally {
        await handle.close();
      }
    }
    for (const entry of entries) {
      if (await exists(filesystem, entry.target)) {
        await filesystem.rename(entry.target, entry.backup);
        entry.backedUp = true;
      }
    }
    for (const entry of entries) {
      await filesystem.rename(entry.temporary, entry.target);
      entry.published = true;
    }
    for (const entry of entries) {
      if (entry.backedUp) await filesystem.rm(entry.backup, { force: true });
    }
  } catch (cause) {
    for (const entry of [...entries].reverse()) {
      try {
        if (entry.published) await filesystem.rm(entry.target, { force: true });
        if (entry.backedUp) await filesystem.rename(entry.backup, entry.target);
        await filesystem.rm(entry.temporary, { force: true });
      } catch { /* preserve the first failure */ }
    }
    fail("output-transaction", "cannot publish the requested Atom outputs", cause);
  }

  return Object.freeze(entries.map(({ target }) => target));
}
