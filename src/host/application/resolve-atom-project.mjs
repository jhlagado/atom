import {
  selectConcreteZ80AssemblerFlavour,
  Z80_ASSEMBLER_FLAVOUR,
} from "@jhlagado/z80-tool-services";
import { createNodeSourceReader } from "@jhlagado/z80-tool-services/source-preparation";

// Copy caller-owned settings before asynchronous source reads can yield.
function snapshotRecord(value) {
  if (value instanceof Map) return Object.freeze(Object.fromEntries(value));
  if (value === null || typeof value !== "object" || Array.isArray(value)) return value;
  return Object.freeze({ ...value });
}

// Open the entry file. Atom's own front end reads it as a stream and asks for
// each included or INCBIN file when it reaches it, so nothing is read here
// beyond the entry, and no source text is scanned.
export async function resolveAtomProject({
  root,
  entry,
  assembler,
  definitions = {},
}) {
  const selectedAssembler = selectConcreteZ80AssemblerFlavour({
    requested: assembler,
    defaultFlavour: Z80_ASSEMBLER_FLAVOUR.atom,
    sourcePath: entry,
  });
  if (selectedAssembler !== Z80_ASSEMBLER_FLAVOUR.atom) {
    throw new TypeError("Atom projects must set assembler to atom");
  }
  const reader = await createNodeSourceReader(root);
  const file = await reader.resolveEntry(entry);
  const open = (importer, specifier) => reader.resolveDependency(importer, specifier);
  return Object.freeze({
    parts: Object.freeze([Object.freeze({
      ordinal: 0,
      bank: 0,
      logicalIdentity: file.logicalIdentity,
      originalBytes: file.originalBytes,
      compilerBytes: file.originalBytes,
      physicalPath: file.physicalPath,
    })]),
    definitions: snapshotRecord(definitions),
    openFile: open,
    readBinary: open,
  });
}
