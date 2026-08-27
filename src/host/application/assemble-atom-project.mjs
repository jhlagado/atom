import { resolveAtomProject } from "./resolve-atom-project.mjs";
import { assembleResolvedAtomProject, NATIVE_ATOM_LIMITS } from "../harness/native-atom-runner.mjs";
import { AtomAssemblyError } from "../atom-assembly-error.mjs";

export async function assembleAtomProject({
  root,
  entry,
  definitions = {},
  placement = { defaultBank: 0, banks: {} },
  limits = {},
  target,
  maxInstructions,
  maxCycles,
  sink,
}) {
  if (limits === null || typeof limits !== "object" || Array.isArray(limits)) {
    throw new AtomAssemblyError("configuration", "invalid-limits", "native Atom limits must be an object");
  }
  const project = await resolveAtomProject({
    root,
    entry,
    definitions,
    placement,
    limits: {
      ...limits,
      maxParts: Math.min(limits.maxParts ?? NATIVE_ATOM_LIMITS.sourceParts, NATIVE_ATOM_LIMITS.sourceParts),
      maxBank: 0,
    },
  });
  const assembled = await assembleResolvedAtomProject(project, {
    target,
    maxInstructions,
    maxCycles,
    sink,
  });
  return Object.freeze({ project, ...assembled });
}
