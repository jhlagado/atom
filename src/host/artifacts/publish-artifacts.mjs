import { createHash } from "node:crypto";
import * as nodeFilesystem from "node:fs/promises";
import path from "node:path";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

let temporaryOrdinal = 0;

function fail(code, message, cause) {
  throw new AtomAssemblyError("publication", code, message, { cause });
}

function validateName(name) {
  if (typeof name !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) {
    fail("artifact-name", "artifact base name must be a portable filename");
  }
}

function bytesOf(value) {
  if (value instanceof Uint8Array) return value;
  if (typeof value === "string") return new TextEncoder().encode(value);
  fail("artifact-value", "artifact content must be bytes or text");
}

async function syncDirectory(filesystem, directory) {
  const handle = await filesystem.open(directory, "r");
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
}

function artifactFiles(baseName, artifacts) {
  return [
    [`${baseName}.nobj`, artifacts.nobj],
    [`${baseName}.bin`, artifacts.bin],
    [`${baseName}.hex`, artifacts.hex],
    [`${baseName}.lst`, artifacts.listing],
    [`${baseName}.d8.json`, artifacts.d8Text],
  ].map(([name, value]) => [name, bytesOf(value)]);
}

function generationDigest(files) {
  const hash = createHash("sha256");
  for (const [name, bytes] of files) {
    hash.update(name, "utf8");
    hash.update(Uint8Array.from([0]));
    hash.update(bytes);
  }
  return hash.digest("hex");
}

async function verifyGeneration(filesystem, generation, files, digest) {
  try {
    for (const [name, expected] of files) {
      const actual = Uint8Array.from(await filesystem.readFile(path.join(generation, name)));
      if (actual.length !== expected.length || actual.some((byte, index) => byte !== expected[index])) {
        fail("generation-conflict", `existing artifact generation ${digest} has different bytes`);
      }
    }
    const manifest = JSON.parse(await filesystem.readFile(path.join(generation, "manifest.json"), "utf8"));
    if (manifest?.format !== "atom-artifact-set" || manifest?.generation !== digest) {
      fail("generation-conflict", `existing artifact generation ${digest} has an invalid manifest`);
    }
  } catch (cause) {
    if (cause instanceof AtomAssemblyError) throw cause;
    fail("generation-conflict", `existing artifact generation ${digest} cannot be verified`, cause);
  }
}

export async function publishAtomArtifacts(
  destination,
  baseName,
  artifacts,
  { filesystem = nodeFilesystem } = {},
) {
  validateName(baseName);
  const files = artifactFiles(baseName, artifacts);
  const digest = generationDigest(files);
  const bundle = path.resolve(destination);
  const generations = path.join(bundle, "generations");
  const generation = path.join(generations, digest);
  temporaryOrdinal += 1;
  const temporary = path.join(generations, `.tmp-${process.pid}-${temporaryOrdinal}`);
  const currentTemporary = path.join(bundle, `.current-${process.pid}-${temporaryOrdinal}`);
  let ownsTemporary = false;
  let ownsCurrentTemporary = false;

  try {
    await filesystem.mkdir(generations, { recursive: true });
    try {
      await filesystem.mkdir(temporary);
      ownsTemporary = true;
      const manifest = [];
      for (const [name, bytes] of files) {
        const target = path.join(temporary, name);
        const handle = await filesystem.open(target, "wx");
        try {
          await handle.writeFile(bytes);
          await handle.sync();
        } finally {
          await handle.close();
        }
        manifest.push({
          name,
          bytes: bytes.length,
          sha256: createHash("sha256").update(bytes).digest("hex"),
        });
      }
      const manifestBytes = new TextEncoder().encode(`${JSON.stringify({
        format: "atom-artifact-set",
        version: 1,
        generation: digest,
        artifacts: manifest,
      }, null, 2)}\n`);
      const manifestHandle = await filesystem.open(path.join(temporary, "manifest.json"), "wx");
      try {
        await manifestHandle.writeFile(manifestBytes);
        await manifestHandle.sync();
      } finally {
        await manifestHandle.close();
      }
      await syncDirectory(filesystem, temporary);
      try {
        await filesystem.rename(temporary, generation);
        ownsTemporary = false;
        await syncDirectory(filesystem, generations);
      } catch (error) {
        if (error?.code !== "EEXIST" && error?.code !== "ENOTEMPTY") throw error;
        await filesystem.rm(temporary, { recursive: true, force: true });
        ownsTemporary = false;
      }
      await verifyGeneration(filesystem, generation, files, digest);
    } catch (cause) {
      if (cause instanceof AtomAssemblyError) throw cause;
      fail("generation-write", "cannot stage the Atom artifact generation", cause);
    }

    try {
      await filesystem.symlink(path.join("generations", digest), currentTemporary, "dir");
      ownsCurrentTemporary = true;
      await filesystem.rename(currentTemporary, path.join(bundle, "current"));
      ownsCurrentTemporary = false;
      await syncDirectory(filesystem, bundle);
    } catch (cause) {
      fail("generation-publish", "cannot atomically select the Atom artifact generation", cause);
    }
  } catch (error) {
    if (ownsCurrentTemporary) {
      try { await filesystem.unlink(currentTemporary); } catch { /* preserve original failure */ }
    }
    if (ownsTemporary) {
      try { await filesystem.rm(temporary, { recursive: true, force: true }); } catch { /* preserve original failure */ }
    }
    throw error;
  }

  const current = path.join(bundle, "current");
  return Object.freeze({
    bundle,
    generation: digest,
    generationDirectory: generation,
    current,
    paths: Object.freeze({
      nobj: path.join(current, `${baseName}.nobj`),
      bin: path.join(current, `${baseName}.bin`),
      hex: path.join(current, `${baseName}.hex`),
      listing: path.join(current, `${baseName}.lst`),
      d8: path.join(current, `${baseName}.d8.json`),
      manifest: path.join(current, "manifest.json"),
    }),
  });
}
