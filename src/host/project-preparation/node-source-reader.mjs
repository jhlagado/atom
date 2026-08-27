import * as nodeFilesystem from "node:fs/promises";
import path from "node:path";

import { SourcePreparationError } from "./errors.mjs";

function dependencyFailure(code, message) {
  throw new SourcePreparationError("dependency", code, message);
}

function projectFailure(code, message) {
  throw new SourcePreparationError("project", code, message);
}

function isAbsoluteOnAnyHost(specifier) {
  return path.isAbsolute(specifier) || /^[A-Za-z]:[\\/]/.test(specifier) || specifier.startsWith("\\\\");
}

function isInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (
    relative !== ".." &&
    !relative.startsWith(`..${path.sep}`) &&
    !path.isAbsolute(relative)
  );
}

async function verifyPhysicalSpelling(filesystem, root, candidate) {
  const relative = path.relative(root, candidate);
  let current = root;
  for (const component of relative.split(path.sep).filter(Boolean)) {
    let entries;
    try {
      entries = await filesystem.readdir(current);
    } catch {
      dependencyFailure("missing-source", `cannot read source path ${candidate}`);
    }
    if (entries.includes(component)) {
      current = path.join(current, component);
      continue;
    }
    const folded = entries.find((entry) => entry.toLowerCase() === component.toLowerCase());
    if (folded !== undefined) {
      dependencyFailure(
        "identity-alias",
        `source path case ${component} conflicts with physical spelling ${folded}`,
      );
    }
    dependencyFailure("missing-source", `cannot open source path ${candidate}`);
  }
}

export async function createNodeSourceReader(root, { filesystem = nodeFilesystem } = {}) {
  let realRoot;
  try {
    realRoot = await filesystem.realpath(root);
    await filesystem.readdir(realRoot);
  } catch {
    projectFailure("invalid-root", `cannot open project root ${root}`);
  }

  const snapshots = new Map();

  async function resolve(baseDirectory, specifier) {
    if (typeof specifier !== "string" || specifier.length === 0 || specifier.includes("\0")) {
      dependencyFailure("missing-source", "source specifier is empty or invalid");
    }
    if (isAbsoluteOnAnyHost(specifier)) {
      dependencyFailure("root-escape", `absolute source path is forbidden: ${specifier}`);
    }

    const requestedPath = path.resolve(baseDirectory, specifier);
    if (!isInside(realRoot, requestedPath)) {
      dependencyFailure("root-escape", `source path escapes the project root: ${specifier}`);
    }
    await verifyPhysicalSpelling(filesystem, realRoot, requestedPath);

    let physicalPath;
    try {
      physicalPath = await filesystem.realpath(requestedPath);
    } catch {
      dependencyFailure("missing-source", `cannot open source path ${specifier}`);
    }
    if (!isInside(realRoot, physicalPath)) {
      dependencyFailure("root-escape", `source target escapes the project root: ${specifier}`);
    }

    const cached = snapshots.get(physicalPath);
    if (cached !== undefined) return cached;

    let originalBytes;
    try {
      originalBytes = Uint8Array.from(await filesystem.readFile(physicalPath));
    } catch {
      dependencyFailure("missing-source", `cannot read source path ${specifier}`);
    }
    const logicalIdentity = path.relative(realRoot, physicalPath).split(path.sep).join("/");
    if (logicalIdentity.length === 0 || logicalIdentity.startsWith("../")) {
      dependencyFailure("root-escape", `source target has no project identity: ${specifier}`);
    }

    const snapshot = Object.freeze({
      physicalPath,
      dependencyIdentity: physicalPath,
      logicalIdentity,
      originalBytes,
    });
    snapshots.set(physicalPath, snapshot);
    return snapshot;
  }

  return Object.freeze({
    root: realRoot,
    resolveEntry(specifier) {
      return resolve(realRoot, specifier);
    },
    resolveDependency(importer, specifier) {
      if (
        importer === null ||
        typeof importer !== "object" ||
        typeof importer.physicalPath !== "string" ||
        !isInside(realRoot, importer.physicalPath)
      ) {
        dependencyFailure("invalid-importer", "dependency importer is not a project source snapshot");
      }
      return resolve(path.dirname(importer.physicalPath), specifier);
    },
  });
}
