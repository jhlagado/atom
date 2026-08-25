import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { AtomAssemblyError } from "./atom-assembly-error.mjs";

const artifactPath = fileURLToPath(new URL("../../assets/native-core.json", import.meta.url));
let cachedCore;

function bootstrap(code, message, details = {}) {
  throw new AtomAssemblyError("bootstrap", code, message, details);
}

async function readNativeAtomCore() {
  let artifact;
  try {
    artifact = JSON.parse(await fs.readFile(artifactPath, "utf8"));
  } catch (cause) {
    bootstrap("native-core-artifact", "the pinned native Atom core cannot be read", { cause });
  }
  if (artifact?.format !== "atom-native-core" || artifact?.version !== 1) {
    bootstrap("native-core-format", "the pinned native Atom core has an unsupported format");
  }
  if (typeof artifact.hexText !== "string" || artifact.symbols === null || typeof artifact.symbols !== "object") {
    bootstrap("native-core-format", "the pinned native Atom core is incomplete");
  }
  const digest = createHash("sha256").update(artifact.hexText, "utf8").digest("hex");
  if (digest !== artifact.hexSha256) {
    bootstrap("native-core-integrity", "the pinned native Atom core failed its SHA-256 check");
  }
  const artifactDigest = createHash("sha256")
    .update(artifact.hexText, "utf8")
    .update("\0", "utf8")
    .update(JSON.stringify(artifact.symbols), "utf8")
    .digest("hex");
  if (artifactDigest !== artifact.artifactSha256) {
    bootstrap("native-core-integrity", "the pinned native Atom core symbol map failed its SHA-256 check");
  }

  const symbols = Object.freeze({ ...artifact.symbols });
  const required = [
    "AtomAssemble",
    "AtomHostResidentEnd",
    "AtomSinkBegin",
    "AtomSinkImageByte",
    "AtomSinkPatchByte",
    "AtomSinkPatchWord",
    "AtomSinkCommit",
    "AtomSinkAbort",
    "AtomSourceReadByte",
  ];
  for (const name of required) {
    if (!Number.isInteger(symbols[name])) bootstrap("missing-symbol", `native Atom core omits ${name}`);
  }
  if (symbols.AtomHostResidentEnd > 0x4000) {
    bootstrap("resident-capacity", "native Atom host core exceeds one 16 KiB bank");
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
    artifactPath,
    source: artifact.source,
    hexSha256: digest,
    artifactSha256: artifactDigest,
    hexText: artifact.hexText,
    symbols,
    codeRanges,
    codeBytes,
    residentExtentBytes: symbols.AtomHostResidentEnd,
  });
}

export function loadNativeAtomCore() {
  cachedCore ??= readNativeAtomCore();
  return cachedCore;
}
