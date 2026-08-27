import { SourcePreparationError } from "./errors.mjs";

function fail(code, message) {
  throw new SourcePreparationError("project", code, message);
}

function validateBank(bank, limits) {
  if (!Number.isInteger(bank) || bank < 0 || bank > 255) {
    fail("invalid-bank", "source bank must be an integer from 0 through 255");
  }
  if (bank > limits.maxBank) {
    fail("bank-capacity", "source bank exceeds the host limit");
  }
  return bank;
}

function freezeLocation(location) {
  return Object.freeze({ ...location });
}

function freezeEdge(edge) {
  return Object.freeze({
    from: edge.from,
    to: edge.to,
    location: freezeLocation(edge.location),
  });
}

export async function joinSourcePlacement({
  parts,
  reader,
  placement = { defaultBank: 0, banks: {} },
  limits,
}) {
  if (placement === null || typeof placement !== "object" || Array.isArray(placement)) {
    fail("invalid-placement", "placement must be an object");
  }
  const mappings = placement.banks ?? {};
  if (mappings === null || typeof mappings !== "object" || Array.isArray(mappings)) {
    fail("invalid-placement", "placement banks must be a path-keyed object");
  }

  const defaultBank = Object.hasOwn(placement, "defaultBank")
    ? validateBank(placement.defaultBank, limits)
    : undefined;
  const reachable = new Map(parts.map((part) => [part.dependencyIdentity, part]));
  const selected = new Map();

  for (const [specifier, value] of Object.entries(mappings)) {
    const bank = validateBank(value, limits);
    let snapshot;
    try {
      snapshot = await reader.resolveEntry(specifier);
    } catch (error) {
      if (error instanceof SourcePreparationError && error.code === "missing-source") {
        fail("nonexistent-placement", `placement source does not exist: ${specifier}`);
      }
      throw error;
    }
    if (!reachable.has(snapshot.dependencyIdentity)) {
      fail("unreachable-placement", `placement source is not in the resolved graph: ${specifier}`);
    }
    const prior = selected.get(snapshot.dependencyIdentity);
    if (prior !== undefined && prior !== bank) {
      fail("conflicting-placement", `source has conflicting bank assignments: ${specifier}`);
    }
    selected.set(snapshot.dependencyIdentity, bank);
  }

  const placedParts = parts.map((part, ordinal) => {
    const assigned = selected.get(part.dependencyIdentity);
    const bank = assigned ?? defaultBank;
    if (bank === undefined) {
      fail("missing-placement", `source has no bank assignment: ${part.logicalIdentity}`);
    }
    const provenance = Object.freeze({
      logicalIdentity: part.logicalIdentity,
      diagnosticName: part.logicalIdentity,
      physicalPath: part.physicalPath,
      ordinal,
      bank,
      originalByteLength: part.originalBytes.length,
      maskedRanges: Object.freeze(part.maskedRanges.map((range) => Object.freeze({ ...range }))),
      dependencyLocations: Object.freeze(
        part.dependencies.map((dependency) => freezeLocation(dependency.location)),
      ),
      includeStack: Object.freeze(part.includeStack.map(freezeEdge)),
    });
    return Object.freeze({ ...part, ordinal, bank, provenance });
  });

  return Object.freeze({
    parts: Object.freeze(placedParts),
    bankArray: Object.freeze(placedParts.map((part) => part.bank)),
  });
}
