import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import {
  assembleAtomProject,
  loadNativeAtomCore,
  NATIVE_ATOM_LIMITS,
} from "../src/host/index.mjs";
import { NATIVE_HOST_FILES } from "./native-host-case.mjs";

const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-host-measure-"));
let result;
try {
  for (const [name, source] of Object.entries(NATIVE_HOST_FILES)) {
    await fs.writeFile(path.join(root, name), source);
  }
  result = await assembleAtomProject({
    root,
    entry: "main.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
} finally {
  await fs.rm(root, { recursive: true, force: true });
}

const core = await loadNativeAtomCore();
const workspaceBytes = [
  ["AtomEncoderWorkspaceStart", "AtomEncoderWorkspaceEnd"],
  ["AtomSymbolWorkspaceStart", "AtomSymbolWorkspaceEnd"],
  ["AtomTokenizerWorkspaceStart", "AtomTokenizerWorkspaceEnd"],
  ["AtomExpressionWorkspaceStart", "AtomExpressionWorkspaceEnd"],
  ["AtomParserWorkspaceStart", "AtomParserWorkspaceEnd"],
  ["AtomOutputWorkspaceStart", "AtomOutputWorkspaceEnd"],
  ["AtomStatementWorkspaceStart", "AtomStatementWorkspaceEnd"],
  ["AtomDriverWorkspaceStart", "AtomDriverWorkspaceEnd"],
].reduce((sum, [start, end]) => sum + core.symbols[end] - core.symbols[start], 0);

console.log(JSON.stringify({
  labels: {
    resident: "Measured in the strict-contract Atom Mac host image.",
    execution: "Measured for the two-part host-preprocessed integration program.",
  },
  native: {
    codeAndTables: core.codeBytes,
    fixedWorkspace: workspaceBytes,
    linkedResidentExtent: core.residentExtentBytes,
    codeMarginTo16KiB: 0x4000 - core.codeBytes,
    physicalMarginTo16KiB: 0x4000 - core.residentExtentBytes,
    hostServiceStubs: core.symbols.AtomHostServiceCodeEnd - core.symbols.AtomHostServiceCodeStart,
  },
  hostSource: {
    maxPartBytes: NATIVE_ATOM_LIMITS.sourceBytes,
    residentZ80Bytes: 0,
  },
  callerOwnedRam: {
    symbolBytes: NATIVE_ATOM_LIMITS.symbolBytes,
    pendingBytes: NATIVE_ATOM_LIMITS.pendingBytes,
    descriptorBytesAtMaximumParts: core.symbols.AtomDriverDescriptorBytes +
      NATIVE_ATOM_LIMITS.sourceParts * core.symbols.AtomDriverPartDescriptorBytes,
  },
  execution: result.execution,
  output: {
    imageRecords: result.generation.images.length,
    patchRecords: result.generation.patches.length,
    initializedBytes: result.generation.images.reduce((sum, operation) => sum + operation.bytes.length, 0),
    finalCursor: result.generation.finalCursor,
  },
}, null, 2));
