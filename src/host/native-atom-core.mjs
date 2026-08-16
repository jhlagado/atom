import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";

import { AtomAssemblyError } from "./atom-assembly-error.mjs";

const sourcePath = fileURLToPath(new URL("../../asm/atom-host-runtime.asm", import.meta.url));
let cachedCore;

const addressOf = (symbol) => symbol.address ?? symbol.value;

function artifact(result, kind) {
  const selected = result.artifacts.find((candidate) => candidate.kind === kind);
  if (selected === undefined) {
    throw new AtomAssemblyError("bootstrap", "missing-artifact", `AZM did not produce the Atom ${kind} artifact`);
  }
  return selected;
}

async function assembleNativeAtomCore() {
  const result = await compile(sourcePath, {
    emitHex: true,
    emitD8m: true,
    registerContracts: "strict",
  });
  const errors = result.diagnostics.filter(({ severity }) => severity === "error");
  if (errors.length !== 0) {
    throw new AtomAssemblyError(
      "bootstrap",
      "native-core-assembly",
      "AZM could not assemble the strict-contract Atom host core",
      { diagnostics: Object.freeze(errors.map((error) => Object.freeze({ ...error }))) },
    );
  }

  const hex = artifact(result, "hex");
  const d8m = artifact(result, "d8m");
  const symbols = Object.freeze(Object.fromEntries(d8m.json.symbols.flatMap((symbol) => {
    const value = addressOf(symbol);
    return value === undefined ? [] : [[symbol.name, value]];
  })));
  const required = [
    "AtomAssemble",
    "AtomHostResidentEnd",
    "AtomSinkBegin",
    "AtomSinkImageByte",
    "AtomSinkPatchByte",
    "AtomSinkPatchWord",
    "AtomSinkCommit",
    "AtomSinkAbort",
  ];
  for (const name of required) {
    if (symbols[name] === undefined) {
      throw new AtomAssemblyError("bootstrap", "missing-symbol", `native Atom core omits ${name}`);
    }
  }
  if (symbols.AtomHostResidentEnd > 0x4000) {
    throw new AtomAssemblyError("bootstrap", "resident-capacity", "native Atom host core exceeds one 16 KiB bank");
  }

  const codeNames = [
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
  ];
  const codeRanges = Object.freeze(codeNames.map(([startName, endName]) => Object.freeze({
    start: symbols[startName],
    end: symbols[endName],
  })));
  const codeBytes = codeRanges.reduce((sum, { start, end }) => sum + end - start, 0);

  return Object.freeze({
    sourcePath,
    hexText: hex.text,
    symbols,
    codeRanges,
    codeBytes,
    residentExtentBytes: symbols.AtomHostResidentEnd,
  });
}

export function loadNativeAtomCore() {
  cachedCore ??= assembleNativeAtomCore();
  return cachedCore;
}
