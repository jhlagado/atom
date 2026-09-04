import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assembleResolvedAtomProject,
  loadNativeAtomCore,
  materializeAtomGeneration,
  writeAtomD8,
} from "../src/host/index.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const nativeRoot = join(repositoryRoot, "native");
const fixedWorkspacePrefixes = new Set(["EN", "SY", "TK", "EX", "PR", "OU", "ST", "DR", "NA"]);
const unavailableGateway = [
  "; Fail-closed transport replaced by a concrete platform binding.",
  ";@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY",
  "NA_GATE:",
  "LD   A,ZT_UNAV",
  "SCF",
  "RET",
].join("\n");

function originSource(origin) {
  assert.ok(Number.isInteger(origin) && origin >= 0 && origin <= 0xffff, "invalid native harness origin");
  return `ORG $${origin.toString(16).toUpperCase().padStart(4, "0")}`;
}

function markAdapterWorkspace(adapterText) {
  const start = adapterText.indexOf("NA_CFG: DW 0\n");
  const end = adapterText.indexOf("NA_REND:\n", start);
  assert.notEqual(start, -1, "native adapter workspace start changed");
  assert.notEqual(end, -1, "native adapter workspace end changed");
  return `${adapterText.slice(0, start)}NA_WBEG:\n${adapterText.slice(start, end)}NA_WEND:\n${adapterText.slice(end)}`;
}

function relocateFixedWorkspace(sourceText, workspaceOrigin, imageOrigin) {
  const code = [];
  const workspace = [];
  const found = new Set();
  let active;
  for (const line of sourceText.split("\n")) {
    const start = /^([A-Z][A-Z0-9]*)_WBEG:$/.exec(line);
    if (active === undefined && start !== null && fixedWorkspacePrefixes.has(start[1])) {
      active = start[1];
      assert.ok(!found.has(active), `duplicate ${active} fixed workspace`);
      found.add(active);
    }
    if (active === undefined) {
      code.push(line);
      continue;
    }
    workspace.push(line);
    if (line === `${active}_WEND:`) active = undefined;
  }
  assert.equal(active, undefined, "unterminated fixed workspace");
  assert.deepEqual(found, fixedWorkspacePrefixes, "native fixed-workspace markers changed");
  const workspaceSource = `${originSource(workspaceOrigin)}\n${workspace.join("\n")}\n`;
  if (workspaceOrigin >= imageOrigin) return `${code.join("\n")}\n${workspaceSource}`;

  // ATOM's IMAGE stream is ascending. Emit low RAM before the high ROM bank.
  // These eight literal EQU declarations size the native workspace; moving
  // them emits no bytes and does not evaluate code-address expressions.
  const required = new Set(["TK_RECB", "EX_VALB", "EX_VCAP", "EX_OPERB", "EX_OCAP", "PR_RCAP", "PR_BRB", "PR_PRB"]);
  const constants = [];
  const remainder = code.filter((line) => {
    const match = /^([A-Z_]+) EQU (.*)$/.exec(line);
    if (match === null || !required.has(match[1])) return true;
    assert.match(match[2], /^\d+$/, `workspace constant ${match[1]} is no longer a literal`);
    required.delete(match[1]);
    constants.push(line);
    return false;
  });
  assert.equal(required.size, 0, "native workspace size constants changed");
  return `${constants.join("\n")}\n${workspaceSource}\n${remainder.join("\n")}\n`;
}

function sourceReadTargetSource(target) {
  const label = target ?? "NA_SREAD";
  assert.match(label, /^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*$/, "invalid source-read target label");
  return { label, source: `TK_SREAD:\nJP ${label}\n` };
}

async function linkedSource({
  origin,
  imageOrigin,
  gatewaySource,
  sourceReadTarget,
  workspaceOrigin,
  preludeSource,
  postludeSource,
}) {
  const parts = await Promise.all(
    ["atom-00.asm", "atom-01.asm", "atom-02.asm", "atom-03.asm", "atom-04.asm"]
      .map((name) => readFile(join(nativeRoot, name), "utf8")),
  );
  assert.match(parts[0], /^ORG 0\n/);
  parts[0] = parts[0].replace(/^ORG 0/, originSource(origin));

  const sourceReadStart = parts[1].indexOf("TK_SREAD:\n");
  const sourceReadEnd = parts[1].indexOf(
    ";@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY",
    sourceReadStart,
  );
  assert.notEqual(sourceReadStart, -1, "native core omitted the source-read entry");
  assert.notEqual(sourceReadEnd, -1, "native core omitted the source-read boundary");
  const sourceRead = sourceReadTargetSource(sourceReadTarget);
  parts[1] = `${parts[1].slice(0, sourceReadStart)}${sourceRead.source}${parts[1].slice(sourceReadEnd)}`;

  const serviceStart = parts[4].indexOf("HS_SCBEG:\n");
  assert.notEqual(serviceStart, -1, "native core omitted the host service tail");
  parts[4] = parts[4].slice(0, serviceStart);

  const [sharedAbi, adapterText] = await Promise.all([
    readFile(fileURLToPath(import.meta.resolve("@jhlagado/z80-tool-services/native/z80-tool-services-v1.asmi")), "utf8"),
    readFile(join(nativeRoot, "named-object-adapter.asm"), "utf8"),
  ]);
  assert.ok(adapterText.includes(unavailableGateway), "native adapter gateway seam changed");
  let adapter = adapterText.replace(unavailableGateway, gatewaySource ?? unavailableGateway);
  if (workspaceOrigin !== undefined) adapter = markAdapterWorkspace(adapter);
  let atomSource = `${preludeSource === undefined ? "" : `${preludeSource}\n`}${parts.join("\n")}\n${sharedAbi}\n${adapter}${postludeSource === undefined ? "" : `\n${postludeSource}`}\nNP_END:\n`;
  if (workspaceOrigin !== undefined) atomSource = relocateFixedWorkspace(atomSource, workspaceOrigin, imageOrigin);
  return {
    sourceReadTarget: sourceRead.label,
    sourceText: atomSource,
  };
}

// The linked source exceeds one native 16-bit source part. Split only between
// lines; ATOM retains label scope across the ordered parts of one assembly.
function sourceProject(sourceText) {
  const parts = [];
  let lines = [];
  let size = 0;
  const flush = () => {
    if (lines.length === 0) return;
    const bytes = new TextEncoder().encode(lines.join(""));
    parts.push({
      ordinal: parts.length,
      bank: 0,
      logicalIdentity: `atom-object-harness-${parts.length}.asm`,
      originalBytes: bytes,
      compilerBytes: bytes,
    });
    lines = [];
    size = 0;
  };
  for (const line of sourceText.split(/\r\n|\n|\r/)) {
    const text = `${line}\n`;
    const length = Buffer.byteLength(text);
    assert.ok(length <= 0xffff, "native harness source line exceeds one ATOM part");
    if (size + length > 0xffff) flush();
    lines.push(text);
    size += length;
  }
  flush();
  return { parts };
}

export async function buildNativeObjectHarness({
  origin = 0,
  imageOrigin = origin,
  workspaceOrigin,
  preludeSource,
  postludeSource,
  gatewaySource,
  sourceReadTarget,
  registerContractsProfile,
  registerContractsInterfaces = [],
} = {}) {
  assert.ok(registerContractsProfile === undefined && registerContractsInterfaces.length === 0,
    "ATOM does not support AZM static register-contract options");
  originSource(imageOrigin);
  assert.ok(imageOrigin <= origin, "native harness image origin follows its core origin");
  if (workspaceOrigin !== undefined) originSource(workspaceOrigin);
  const linked = await linkedSource({
    origin,
    imageOrigin,
    gatewaySource,
    sourceReadTarget,
    workspaceOrigin,
    preludeSource,
    postludeSource,
  });
  const project = sourceProject(linked.sourceText);
  const result = await assembleResolvedAtomProject(project, {
    target: { start: 0, capacity: 0xffff },
    maxInstructions: 250_000_000,
    maxCycles: 2_500_000_000,
  }).catch((cause) => {
    const location = cause.diagnostic;
    const part = project.parts[location?.ordinal];
    if (part === undefined) throw cause;
    const line = new TextDecoder().decode(part.originalBytes).split("\n")[location.line - 1];
    throw new Error(`${location.logicalIdentity}:${location.line}: ${cause.message}\n> ${line}`, { cause });
  });
  const debugMap = writeAtomD8(project, result.generation);
  const materialized = materializeAtomGeneration(result.generation, { base: 0 });
  const symbols = Object.fromEntries(debugMap.symbols.flatMap((symbol) => {
    const value = symbol.address ?? symbol.value;
    return value === undefined ? [] : [[symbol.name.toUpperCase(), value]];
  }));
  const residentBytes = symbols.NP_END - imageOrigin;
  assert.ok(residentBytes <= 0x4000, "named-object harness exceeds one 16 KiB bank");
  let bytes;
  let workspaceBytes;
  let fixedWorkspace;
  if (workspaceOrigin === undefined) {
    assert.equal(materialized.end, symbols.NP_END);
    bytes = materialized.bytes.slice(imageOrigin, symbols.NP_END);
    assert.equal(bytes.length, residentBytes);
  } else {
    bytes = materialized.bytes.slice(imageOrigin, symbols.NP_END);
    const workspaceEnd = symbols.NA_WEND;
    assert.equal(symbols.EN_WBEG, workspaceOrigin);
    assert.ok(workspaceEnd > workspaceOrigin, "native fixed workspace is empty");
    assert.ok(
      symbols.NP_END <= workspaceOrigin || workspaceEnd <= imageOrigin,
      "native code and fixed workspace overlap",
    );
    workspaceBytes = materialized.bytes.slice(workspaceOrigin, workspaceEnd);
    fixedWorkspace = {
      fixedWorkspaceStart: workspaceOrigin,
      fixedWorkspaceEnd: workspaceEnd,
      fixedWorkspaceBytes: workspaceEnd - workspaceOrigin,
      nativeCoreFixedWorkspaceBytes: symbols.NA_WBEG - workspaceOrigin,
      adapterFixedWorkspaceBytes: workspaceEnd - symbols.NA_WBEG,
      workspaceSha256: createHash("sha256").update(workspaceBytes).digest("hex"),
    };
  }
  const nativeCoreBytes = workspaceOrigin === undefined
    ? (await loadNativeAtomCore()).residentExtentBytes
    : symbols.DR_CEND - origin;
  const proofSymbols = Object.fromEntries([
    "DR_DETAI",
    "ST_DETAI",
    "ST_EPART",
    "ST_EOFF",
    "TK_ESTAT",
    "NA_TRANS",
  ].map((name) => [name, symbols[name]]));
  return {
    bytes,
    debugMap,
    report: {
      format: "atom-native-object-harness-census",
      version: 1,
      loadAddress: imageOrigin,
      ...(imageOrigin === origin ? {} : { coreOrigin: origin }),
      assembleEntry: symbols.DR_ASM,
      adapterInitEntry: symbols.NA_INIT,
      gatewayEntry: symbols.NA_GATE,
      sourceReadEntry: symbols.NA_SREAD,
      configuredSourceReadEntry: symbols[linked.sourceReadTarget],
      residentEnd: symbols.NP_END,
      residentBytes,
      nativeCoreResidentBytes: nativeCoreBytes,
      adapterResidentDeltaBytes: symbols.NA_REND - origin - nativeCoreBytes,
      platformPreludeBytes: origin - imageOrigin,
      platformPostludeBytes: symbols.NP_END - symbols.NA_REND,
      commonWorkspaceBytes: symbols.NA_WLEN,
      transferBufferBytes: symbols.NA_XLEN,
      maximumSourceParts: 255,
      sourceNameTableBytes: 255 * 3,
      maximumObjectNameBytes: 255,
      maximumSourceObjectBytes: 65_535,
      maximumOutputObjectBytes: 65_535,
      sha256: createHash("sha256").update(bytes).digest("hex"),
      symbols: proofSymbols,
      ...fixedWorkspace,
    },
    ...(workspaceBytes === undefined ? {} : { workspaceBytes }),
  };
}
