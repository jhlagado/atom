import path from "node:path";

import {
  OutputPublicationError,
  publishArtifactGeneration,
} from "@jhlagado/z80-tool-services";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

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

function artifactFiles(baseName, artifacts) {
  return [
    { name: `${baseName}.nobj`, bytes: bytesOf(artifacts.nobj) },
    { name: `${baseName}.bin`, bytes: bytesOf(artifacts.bin) },
    { name: `${baseName}.hex`, bytes: bytesOf(artifacts.hex) },
    { name: `${baseName}.lst`, bytes: bytesOf(artifacts.listing) },
    { name: `${baseName}.d8.json`, bytes: bytesOf(artifacts.d8Text) },
  ];
}

export async function publishAtomArtifacts(
  destination,
  baseName,
  artifacts,
  { filesystem } = {},
) {
  validateName(baseName);
  const files = artifactFiles(baseName, artifacts);
  let published;
  try {
    published = await publishArtifactGeneration(destination, files, {
      filesystem,
      tagPrefix: "atom",
      manifest: (generation, manifestArtifacts) => ({
        name: "manifest.json",
        bytes: `${JSON.stringify({
          format: "atom-artifact-set",
          version: 1,
          generation,
          artifacts: manifestArtifacts,
        }, null, 2)}\n`,
      }),
      verifyManifest: (generation, manifest) =>
        manifest?.format === "atom-artifact-set" &&
        manifest?.generation === generation,
    });
  } catch (error) {
    if (error instanceof OutputPublicationError) {
      const message = error.code === "generation-write"
        ? "cannot stage the Atom artifact generation"
        : error.code === "generation-publish"
          ? "cannot atomically select the Atom artifact generation"
          : error.message;
      fail(error.code, message, error.cause);
    }
    throw error;
  }

  return Object.freeze({
    bundle: published.bundle,
    generation: published.generation,
    generationDirectory: published.generationDirectory,
    current: published.current,
    paths: Object.freeze({
      nobj: path.join(published.current, `${baseName}.nobj`),
      bin: path.join(published.current, `${baseName}.bin`),
      hex: path.join(published.current, `${baseName}.hex`),
      listing: path.join(published.current, `${baseName}.lst`),
      d8: path.join(published.current, `${baseName}.d8.json`),
      manifest: path.join(published.current, "manifest.json"),
    }),
  });
}
