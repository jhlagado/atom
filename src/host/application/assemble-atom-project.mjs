import { resolveAtomProject } from "./resolve-atom-project.mjs";
import { assembleResolvedAtomProject, NATIVE_ATOM_LIMITS } from "../harness/native-atom-runner.mjs";
import { AtomAssemblyError } from "../atom-assembly-error.mjs";

export async function assembleAtomProject({
  root,
  entry,
  assembler,
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
  // Open the entry. Included files are opened as the front end reaches them,
  // and the project reports every file the assembly read.
  const entryProject = await resolveAtomProject({ root, entry, assembler, definitions });
  const assembled = await assembleResolvedAtomProject(entryProject, {
    target,
    maxInstructions,
    maxCycles,
    sink,
  });
  if (assembled.parts.length > Math.min(limits.maxParts ?? NATIVE_ATOM_LIMITS.sourceParts, NATIVE_ATOM_LIMITS.sourceParts)) {
    throw new AtomAssemblyError("configuration", "part-capacity", "the project reads more source files than its limit");
  }
  return Object.freeze({ project: Object.freeze({ parts: assembled.parts, segments: assembled.segments }), ...assembled });
}
