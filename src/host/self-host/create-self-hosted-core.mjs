import { AtomAssemblyError } from "../atom-assembly-error.mjs";
import { writeIntelHex } from "../artifacts/render-artifacts.mjs";
import { materializeAtomGeneration } from "../native-atom-runner.mjs";

const CODE_RANGE_NAMES = Object.freeze([
  ["AtomEncoderCoreStart", "AtomEncoderCoreEnd"],
  ["AtomSymbolCodeStart", "AtomSymbolCodeEnd"],
  ["AtomTokenizerCodeStart", "AtomTokenizerCodeEnd"],
  ["AtomExpressionCodeStart", "AtomExpressionCodeEnd"],
  ["AtomPatchCodeStart", "AtomPatchCodeEnd"],
  ["AtomParserCodeStart", "AtomParserCodeEnd"],
  ["AtomOutputCodeStart", "AtomOutputCodeEnd"],
  ["AtomStatementCodeStart", "AtomStatementCodeEnd"],
  ["AtomDriverCodeStart", "AtomDriverCodeEnd"],
  ["AtomHostServiceCodeStart", "AtomHostServiceCodeEnd"],
]);

function fail(code, message, details = {}) {
  throw new AtomAssemblyError("self-host-core", code, message, details);
}

export function createSelfHostedAtomCore(source, generation) {
  if (source === null || typeof source !== "object" || !Array.isArray(source.mapping)) {
    fail("source", "self-host source and symbol mapping are required");
  }
  if (generation === null || typeof generation !== "object" || !Array.isArray(generation.symbols)) {
    fail("generation", "self-host generation and declared symbols are required");
  }
  const globalShortNames = new Set(source.mapping
    .filter((item) => !item.private)
    .map((item) => item.short.toUpperCase()));
  const declarations = new Map();
  for (const declaration of generation.symbols) {
    const canonical = declaration.name.toUpperCase();
    if (!globalShortNames.has(canonical)) continue;
    const previous = declarations.get(canonical);
    if (previous !== undefined && previous !== declaration.value) {
      fail("ambiguous-symbol", `self-host symbol ${declaration.name} has conflicting values`);
    }
    declarations.set(canonical, declaration.value);
  }
  const symbols = {};
  for (const item of source.mapping) {
    if (item.private) continue;
    const value = declarations.get(item.short.toUpperCase());
    if (value === undefined) fail("missing-symbol", `self-host generation omits ${item.short} (${item.original})`);
    symbols[item.original] = value;
  }
  if (!Number.isInteger(symbols.AtomHostResidentEnd)) {
    fail("missing-symbol", "self-host generation omits AtomHostResidentEnd");
  }
  const codeRanges = CODE_RANGE_NAMES.map(([startName, endName]) => {
    const start = symbols[startName];
    const end = symbols[endName];
    if (!Number.isInteger(start) || !Number.isInteger(end) || end < start) {
      fail("code-range", `self-host generation has an invalid ${startName}/${endName} range`);
    }
    return Object.freeze({ start, end });
  });
  const materialized = materializeAtomGeneration(generation);
  if (materialized.base !== 0 || materialized.end !== symbols.AtomHostResidentEnd) {
    fail("resident-extent", "self-host generation does not cover the resident Atom extent");
  }
  return Object.freeze({
    source: "Atom self-host generation",
    hexText: writeIntelHex(materialized),
    symbols: Object.freeze(symbols),
    codeRanges: Object.freeze(codeRanges),
    codeBytes: codeRanges.reduce((sum, range) => sum + range.end - range.start, 0),
    residentExtentBytes: symbols.AtomHostResidentEnd,
  });
}
