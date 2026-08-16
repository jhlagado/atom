import { SourcePackagerError } from "./errors.mjs";

const encoder = new TextEncoder();

export const NODE_SOURCE_LIMITS = Object.freeze({
  maxParts: 255,
  maxDepth: 64,
  maxLogicalPathBytes: 255,
  maxRetainedPathBytes: 64 * 1024,
  maxBank: 255,
});

function fail(code, message, location) {
  throw new SourcePackagerError("dependency", code, message, location);
}

function positiveLimit(value, name, maximum = Number.MAX_SAFE_INTEGER) {
  if (!Number.isInteger(value) || value < 1 || value > maximum) {
    fail("invalid-limit", `${name} must be a positive bounded integer`);
  }
  return value;
}

function normalizeLimits(limits = NODE_SOURCE_LIMITS) {
  return Object.freeze({
    maxParts: positiveLimit(limits.maxParts ?? NODE_SOURCE_LIMITS.maxParts, "maxParts", 255),
    maxDepth: positiveLimit(limits.maxDepth ?? NODE_SOURCE_LIMITS.maxDepth, "maxDepth", 255),
    maxLogicalPathBytes: positiveLimit(
      limits.maxLogicalPathBytes ?? NODE_SOURCE_LIMITS.maxLogicalPathBytes,
      "maxLogicalPathBytes",
      255,
    ),
    maxRetainedPathBytes: positiveLimit(
      limits.maxRetainedPathBytes ?? NODE_SOURCE_LIMITS.maxRetainedPathBytes,
      "maxRetainedPathBytes",
    ),
    maxBank: limits.maxBank ?? NODE_SOURCE_LIMITS.maxBank,
  });
}

function validateSnapshot(snapshot, location) {
  if (
    snapshot === null ||
    typeof snapshot !== "object" ||
    typeof snapshot.dependencyIdentity !== "string" ||
    typeof snapshot.logicalIdentity !== "string" ||
    !(snapshot.originalBytes instanceof Uint8Array)
  ) {
    fail("invalid-snapshot", "source reader returned an invalid snapshot", location);
  }
  return snapshot;
}

function validateInspection(inspection, entry, location) {
  if (
    inspection === null ||
    typeof inspection !== "object" ||
    !(inspection.compilerBytes instanceof Uint8Array) ||
    !Array.isArray(inspection.dependencies) ||
    !Array.isArray(inspection.maskedRanges) ||
    (entry && !("state" in inspection))
  ) {
    fail("invalid-profile", "source profile returned an invalid part", location);
  }
  for (const dependency of inspection.dependencies) {
    if (
      dependency === null ||
      typeof dependency !== "object" ||
      typeof dependency.specifier !== "string" ||
      dependency.location === null ||
      typeof dependency.location !== "object"
    ) {
      fail("invalid-profile", "source profile returned an invalid dependency", location);
    }
  }
  return inspection;
}

function withLocation(error, location) {
  if (error instanceof SourcePackagerError) {
    if (error.location !== undefined) return error;
    return new SourcePackagerError(error.category, error.code, error.message, location);
  }
  return error;
}

function frozenPart(snapshot, inspection) {
  return Object.freeze({
    physicalPath: snapshot.physicalPath,
    dependencyIdentity: snapshot.dependencyIdentity,
    logicalIdentity: snapshot.logicalIdentity,
    originalBytes: snapshot.originalBytes,
    compilerBytes: inspection.compilerBytes,
    dependencies: Object.freeze(inspection.dependencies.map((dependency) => Object.freeze({
      specifier: dependency.specifier,
      location: Object.freeze({ ...dependency.location }),
    }))),
    maskedRanges: Object.freeze(inspection.maskedRanges.map((range) => Object.freeze({ ...range }))),
  });
}

export async function resolveSourceProject({
  reader,
  entry,
  profile,
  configuration,
  limits: requestedLimits,
}) {
  const limits = normalizeLimits(requestedLimits);
  if (
    reader === null ||
    typeof reader !== "object" ||
    typeof reader.resolveEntry !== "function" ||
    profile === null ||
    typeof profile !== "object" ||
    typeof profile.inspectEntry !== "function" ||
    typeof profile.inspectDependency !== "function"
  ) {
    fail("invalid-project", "resolver requires a source reader and profile");
  }

  const identities = new Map();
  const visited = new Set();
  const visiting = new Map();
  const nodeStack = [];
  const edgeStack = [];
  const parts = [];
  let retainedPathBytes = 0;

  function register(snapshot, location) {
    const known = identities.get(snapshot.dependencyIdentity);
    if (known !== undefined) {
      if (known !== snapshot.logicalIdentity) {
        fail(
          "identity-alias",
          `dependency identity has conflicting logical names ${known} and ${snapshot.logicalIdentity}`,
          location,
        );
      }
      return;
    }

    const pathBytes = encoder.encode(snapshot.logicalIdentity).length;
    if (pathBytes > limits.maxLogicalPathBytes) {
      fail("path-capacity", "logical source path exceeds the host limit", location);
    }
    if (identities.size + 1 > limits.maxParts) {
      fail("part-capacity", "source graph exceeds the host part limit", location);
    }
    if (retainedPathBytes + pathBytes > limits.maxRetainedPathBytes) {
      fail("retained-path-capacity", "source graph exceeds the retained-path limit", location);
    }
    retainedPathBytes += pathBytes;
    identities.set(snapshot.dependencyIdentity, snapshot.logicalIdentity);
  }

  async function resolveDependency(importer, reference) {
    try {
      return validateSnapshot(
        await reader.resolveDependency(importer, reference.specifier),
        reference.location,
      );
    } catch (error) {
      throw withLocation(error, reference.location);
    }
  }

  async function visit(snapshot, inspection, state, depth, incomingEdge) {
    if (depth > limits.maxDepth) {
      fail("depth-capacity", "source graph exceeds the dependency-depth limit", incomingEdge?.location);
    }
    if (visited.has(snapshot.dependencyIdentity)) return;

    const activeIndex = visiting.get(snapshot.dependencyIdentity);
    if (activeIndex !== undefined) {
      const cycle = Object.freeze([
        ...edgeStack.slice(activeIndex),
        incomingEdge,
      ].map((edge) => Object.freeze({ ...edge })));
      const error = new SourcePackagerError(
        "dependency",
        "dependency-cycle",
        "source dependency cycle",
        incomingEdge.location,
      );
      error.cycle = cycle;
      throw error;
    }

    visiting.set(snapshot.dependencyIdentity, nodeStack.length);
    nodeStack.push(snapshot);
    if (incomingEdge !== undefined) edgeStack.push(incomingEdge);

    const directDependencies = new Set();
    for (const reference of inspection.dependencies) {
      const dependency = await resolveDependency(snapshot, reference);
      register(dependency, reference.location);
      if (directDependencies.has(dependency.dependencyIdentity)) {
        fail("repeated-dependency", "source repeats one direct dependency", reference.location);
      }
      directDependencies.add(dependency.dependencyIdentity);

      const edge = Object.freeze({
        from: snapshot.logicalIdentity,
        to: dependency.logicalIdentity,
        location: Object.freeze({ ...reference.location }),
      });
      if (depth + 1 > limits.maxDepth) {
        fail("depth-capacity", "source graph exceeds the dependency-depth limit", reference.location);
      }
      if (visited.has(dependency.dependencyIdentity)) continue;
      const dependencyActiveIndex = visiting.get(dependency.dependencyIdentity);
      if (dependencyActiveIndex !== undefined) {
        const cycle = Object.freeze([
          ...edgeStack.slice(dependencyActiveIndex),
          edge,
        ].map((cycleEdge) => Object.freeze({ ...cycleEdge })));
        const error = new SourcePackagerError(
          "dependency",
          "dependency-cycle",
          "source dependency cycle",
          reference.location,
        );
        error.cycle = cycle;
        throw error;
      }
      const dependencyInspection = validateInspection(
        await profile.inspectDependency(dependency, state),
        false,
        reference.location,
      );
      await visit(dependency, dependencyInspection, state, depth + 1, edge);
    }

    if (incomingEdge !== undefined) edgeStack.pop();
    nodeStack.pop();
    visiting.delete(snapshot.dependencyIdentity);
    visited.add(snapshot.dependencyIdentity);
    parts.push(frozenPart(snapshot, inspection));
  }

  let entrySnapshot;
  try {
    entrySnapshot = validateSnapshot(await reader.resolveEntry(entry));
  } catch (error) {
    throw withLocation(error, undefined);
  }
  register(entrySnapshot);
  const entryInspection = validateInspection(
    await profile.inspectEntry(entrySnapshot, configuration),
    true,
  );
  await visit(entrySnapshot, entryInspection, entryInspection.state, 1);

  return Object.freeze({
    parts: Object.freeze(parts),
    state: entryInspection.state,
    retainedPathBytes,
  });
}
