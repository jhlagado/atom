import { createAtomSourceProfile } from "./atom/source-profile.mjs";
import { lowerAtomBinaryIncludes } from "./atom/incbin.mjs";
import {
  createNodeSourceReader,
  resolveSourceProject,
} from "./source-packager/index.mjs";

function snapshotRecord(value) {
  if (value instanceof Map) return Object.freeze(Object.fromEntries(value));
  if (value === null || typeof value !== "object" || Array.isArray(value)) return value;
  return Object.freeze({ ...value });
}

function snapshotPlacement(placement) {
  if (placement === null || typeof placement !== "object" || Array.isArray(placement)) {
    return placement;
  }
  return Object.freeze({
    ...placement,
    ...(Object.hasOwn(placement, "banks")
      ? { banks: snapshotRecord(placement.banks) }
      : {}),
  });
}

export async function resolveAtomProject({
  root,
  entry,
  definitions = {},
  placement = { defaultBank: 0, banks: {} },
  limits,
}) {
  const configuration = Object.freeze({ definitions: snapshotRecord(definitions) });
  const frozenPlacement = snapshotPlacement(placement);
  const frozenLimits = snapshotRecord(limits);
  const reader = await createNodeSourceReader(root);
  const project = await resolveSourceProject({
    reader,
    entry,
    profile: createAtomSourceProfile(),
    configuration,
    placement: frozenPlacement,
    limits: frozenLimits,
  });
  return lowerAtomBinaryIncludes(project, reader);
}
