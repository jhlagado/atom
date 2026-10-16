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
} from "../index.mjs";
import {
  joinNativeCoreModules,
  readAssemblyModule,
  readNativeCoreModules,
  nativeSourceServices,
  setNativeCoreOrigin,
} from "./z80-source-layout.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../../..");
const nativeRoot = join(repositoryRoot, "src", "z80");
const fixedWorkspacePrefixes = new Set(["en", "sy", "tk", "ex", "pr", "out", "st", "dr", "obj"]);
const gatewayBegin = ";@@ATOM_OBJECT_GATEWAY_BEGIN@@";
const gatewayEnd = ";@@ATOM_OBJECT_GATEWAY_END@@";

function originSource(origin) {
  assert.ok(Number.isInteger(origin) && origin >= 0 && origin <= 0xffff, "invalid native harness origin");
  return `ORG $${origin.toString(16).toUpperCase().padStart(4, "0")}`;
}

function markAdapterWorkspace(adapterText) {
  const startMatch = /^objCfg:[ \t]+DW[ \t]+0(?:[ \t]*;.*)?$/m.exec(adapterText);
  assert.notEqual(startMatch, null, "native adapter workspace start changed");
  const start = startMatch.index;
  const endMatch = /^objEnd:(?:[ \t]*;.*)?$/m.exec(adapterText.slice(start));
  assert.notEqual(endMatch, null, "native adapter workspace end changed");
  const end = start + endMatch.index;
  return `${adapterText.slice(0, start)}objRamLo:\n${adapterText.slice(start, end)}objRamHi:\n${adapterText.slice(end)}`;
}

function relocateFixedWorkspace(sourceText, workspaceOrigin, imageOrigin) {
  const code = [];
  const workspace = [];
  const found = new Set();
  let active;
  for (const line of sourceText.split("\n")) {
    const codeLine = line.replace(/;.*$/, "").trimEnd();
    const start = /^([a-z]{2,3})RamLo:$/.exec(codeLine);
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
    if (codeLine === `${active}RamHi:`) active = undefined;
  }
  assert.equal(active, undefined, "unterminated fixed workspace");
  assert.deepEqual(found, fixedWorkspacePrefixes, "native fixed-workspace markers changed");
  const workspaceSource = `${originSource(workspaceOrigin)}\n${workspace.join("\n")}\n`;
  if (workspaceOrigin >= imageOrigin) return `${code.join("\n")}\n${workspaceSource}`;

  // ATOM's IMAGE stream is ascending. Emit low RAM before the high ROM bank.
  // These eight literal EQU declarations size the native workspace; moving
  // them emits no bytes and does not evaluate code-address expressions.
  const required = new Set(["tkRecLen", "exValLen", "exValCap", "exOpLen", "exOpCap", "prRefCap", "prRawLen", "prPubLen"]);
  const constants = [];
  const remainder = code.filter((line) => {
    const match = /^([A-Za-z_][A-Za-z0-9_]*)[ \t]+EQU[ \t]+(.*)$/.exec(line);
    if (match === null || !required.has(match[1])) return true;
    const literal = match[2].replace(/;.*$/, "").trim();
    assert.match(literal, /^\d+$/, `workspace constant ${match[1]} is no longer a literal`);
    required.delete(match[1]);
    constants.push(line);
    return false;
  });
  assert.equal(required.size, 0, "native workspace size constants changed");
  return `${constants.join("\n")}\n${workspaceSource}\n${remainder.join("\n")}\n`;
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
  const sourceReadLabel = sourceReadTarget ?? "objFetch";
  let modules = await readNativeCoreModules(nativeRoot);
  modules = setNativeCoreOrigin(modules, originSource(origin));
  const core = `${joinNativeCoreModules(modules)}\n${nativeSourceServices({ open: "objNext", read: sourceReadLabel, binaryOpen: "objNoBin", binaryRead: "objNoBin" })}`;

  const [sharedAbi, adapterText] = await Promise.all([
    readFile(fileURLToPath(import.meta.resolve("@jhlagado/z80-tool-services/native/z80-tool-services-v1.asmi")), "utf8"),
    readAssemblyModule(nativeRoot, "nobj.asm"),
  ]);
  assert.equal(adapterText.split(gatewayBegin).length, 2, "native adapter must contain one gateway start marker");
  assert.equal(adapterText.split(gatewayEnd).length, 2, "native adapter must contain one gateway end marker");
  const gatewayStart = adapterText.indexOf(gatewayBegin) + gatewayBegin.length;
  const gatewayFinish = adapterText.indexOf(gatewayEnd, gatewayStart);
  assert.ok(gatewayFinish >= gatewayStart, "native adapter gateway markers are out of order");
  const checkedGateway = adapterText.slice(gatewayStart, gatewayFinish);
  const replacementGateway = gatewaySource === undefined ? checkedGateway : `\n${gatewaySource}\n`;
  let adapter = `${adapterText.slice(0, gatewayStart)}${replacementGateway}${adapterText.slice(gatewayFinish)}`;
  if (workspaceOrigin !== undefined) adapter = markAdapterWorkspace(adapter);
  let atomSource = `${preludeSource === undefined ? "" : `${preludeSource}\n`}${core}\n${sharedAbi}\n${adapter}${postludeSource === undefined ? "" : `\n${postludeSource}`}\nnpEnd:\n`;
  if (workspaceOrigin !== undefined) atomSource = relocateFixedWorkspace(atomSource, workspaceOrigin, imageOrigin);
  return {
    sourceReadTarget: sourceReadLabel,
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
  // Atom names are case-insensitive. Look them up as the source spells them.
  const values = new Map(debugMap.symbols.flatMap((entry) => {
    const value = entry.address ?? entry.value;
    return value === undefined ? [] : [[entry.name.toUpperCase(), value]];
  }));
  const symbol = (name) => values.get(name.toUpperCase());
  const residentBytes = symbol("npEnd") - imageOrigin;
  assert.ok(residentBytes <= 0x4000, "named-object harness exceeds one 16 KiB bank");
  let bytes;
  let workspaceBytes;
  let fixedWorkspace;
  if (workspaceOrigin === undefined) {
    assert.equal(materialized.end, symbol("npEnd"));
    bytes = materialized.bytes.slice(imageOrigin, symbol("npEnd"));
    assert.equal(bytes.length, residentBytes);
  } else {
    bytes = materialized.bytes.slice(imageOrigin, symbol("npEnd"));
    const workspaceEnd = symbol("objRamHi");
    // The first area's workspace starts the relocated block.
    assert.equal(Math.min(...[...fixedWorkspacePrefixes].map((prefix) => symbol(`${prefix}RamLo`))), workspaceOrigin);
    assert.ok(workspaceEnd > workspaceOrigin, "native fixed workspace is empty");
    assert.ok(
      symbol("npEnd") <= workspaceOrigin || workspaceEnd <= imageOrigin,
      "native code and fixed workspace overlap",
    );
    workspaceBytes = materialized.bytes.slice(workspaceOrigin, workspaceEnd);
    fixedWorkspace = {
      fixedWorkspaceStart: workspaceOrigin,
      fixedWorkspaceEnd: workspaceEnd,
      fixedWorkspaceBytes: workspaceEnd - workspaceOrigin,
      nativeCoreFixedWorkspaceBytes: symbol("objRamLo") - workspaceOrigin,
      adapterFixedWorkspaceBytes: workspaceEnd - symbol("objRamLo"),
      workspaceSha256: createHash("sha256").update(workspaceBytes).digest("hex"),
    };
  }
  const nativeCoreBytes = workspaceOrigin === undefined
    ? (await loadNativeAtomCore()).residentExtentBytes
    : symbol("drEnd") - origin;
  const proofSymbols = Object.fromEntries([
    "drDetail",
    "stDetail",
    "stAtPart",
    "stAtOff",
    "tkStatus",
    "objXfer",
  ].map((name) => [name, symbol(name)]));
  return {
    bytes,
    debugMap,
    report: {
      format: "atom-native-object-harness-census",
      version: 1,
      loadAddress: imageOrigin,
      ...(imageOrigin === origin ? {} : { coreOrigin: origin }),
      assembleEntry: symbol("drAsm"),
      adapterInitEntry: symbol("objInit"),
      gatewayEntry: symbol("objGate"),
      sourceReadEntry: symbol("objFetch"),
      configuredSourceReadEntry: symbol(linked.sourceReadTarget),
      residentEnd: symbol("npEnd"),
      residentBytes,
      nativeCoreResidentBytes: nativeCoreBytes,
      adapterResidentDeltaBytes: symbol("objEnd") - origin - nativeCoreBytes,
      platformPreludeBytes: origin - imageOrigin,
      platformPostludeBytes: symbol("npEnd") - symbol("objEnd"),
      commonWorkspaceBytes: symbol("objSpace"),
      transferBufferBytes: symbol("objChunk"),
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
