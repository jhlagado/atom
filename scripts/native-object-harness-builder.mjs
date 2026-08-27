import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";

import { translateAtomLineToAzm } from "../src/host/translation/atom-to-azm.mjs";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const monorepoRoot = resolve(repositoryRoot, "../..");
const nativeRoot = join(repositoryRoot, "native");
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

async function linkedSource({ origin, gatewaySource }) {
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
  parts[1] = `${parts[1].slice(0, sourceReadStart)}TK_SREAD:\nJP NA_SREAD\n${parts[1].slice(sourceReadEnd)}`;

  const serviceStart = parts[4].indexOf("HS_SCBEG:\n");
  assert.notEqual(serviceStart, -1, "native core omitted the host service tail");
  parts[4] = parts[4].slice(0, serviceStart);

  const [sharedAbi, adapterText] = await Promise.all([
    readFile(join(monorepoRoot, "packages", "z80-tool-services", "native", "z80-tool-services-v1.asmi"), "utf8"),
    readFile(join(nativeRoot, "named-object-adapter.asm"), "utf8"),
  ]);
  assert.ok(adapterText.includes(unavailableGateway), "native adapter gateway seam changed");
  const adapter = adapterText.replace(unavailableGateway, gatewaySource ?? unavailableGateway);
  const atomSource = `${parts.join("\n")}\n${sharedAbi}\n${adapter}`;
  return `${atomSource.split(/\r\n|\n|\r/).map(translateAtomLineToAzm).join("\n")}\n.end\n`;
}

export async function buildNativeObjectHarness({
  origin = 0,
  gatewaySource,
  registerContractsInterfaces = [],
} = {}) {
  const sourceText = await linkedSource({ origin, gatewaySource });
  const temporary = await mkdtemp(join(tmpdir(), "atom-object-harness-"));
  try {
    const sourcePath = join(temporary, "atom-object-harness.asm");
    await writeFile(sourcePath, sourceText);
    const result = await compile(sourcePath, {
      emitBin: true,
      emitHex: false,
      emitD8m: true,
      emitLst: false,
      registerContracts: "strict",
      registerContractsInterfaces,
      symbolCase: "insensitive",
    });
    const errors = result.diagnostics.filter(({ severity }) => severity === "error");
    if (errors.length !== 0) {
      throw new Error(errors.map(({ sourceName, line, column, message }) =>
        `${sourceName}:${line}:${column}: ${message}\n> ${sourceText.split("\n")[line - 1] ?? ""}`).join("\n"));
    }
    const binary = result.artifacts.find(({ kind }) => kind === "bin");
    const debugMap = result.artifacts.find(({ kind }) => kind === "d8m");
    assert.equal(binary?.kind, "bin");
    assert.equal(debugMap?.kind, "d8m");
    const symbols = Object.fromEntries(debugMap.json.symbols.flatMap((symbol) => {
      const value = symbol.address ?? symbol.value;
      return value === undefined ? [] : [[symbol.name.toUpperCase(), value]];
    }));
    const residentBytes = symbols.NA_REND - origin;
    assert.ok(residentBytes <= 0x4000, "named-object harness exceeds one 16 KiB bank");
    assert.equal(binary.bytes.length, residentBytes);
    const nativeCoreBytes = 12_396;
    const proofSymbols = Object.fromEntries([
      "DR_DETAI",
      "ST_DETAI",
      "ST_EPART",
      "ST_EOFF",
      "TK_ESTAT",
      "NA_TRANS",
    ].map((name) => [name, symbols[name]]));
    return {
      bytes: binary.bytes,
      report: {
        format: "atom-native-object-harness-census",
        version: 1,
        loadAddress: origin,
        assembleEntry: symbols.DR_ASM,
        adapterInitEntry: symbols.NA_INIT,
        gatewayEntry: symbols.NA_GATE,
        sourceReadEntry: symbols.NA_SREAD,
        residentEnd: symbols.NA_REND,
        residentBytes,
        nativeCoreResidentBytes: nativeCoreBytes,
        adapterResidentDeltaBytes: residentBytes - nativeCoreBytes,
        commonWorkspaceBytes: symbols.NA_WLEN,
        transferBufferBytes: symbols.NA_XLEN,
        maximumSourceParts: 255,
        sourceNameTableBytes: 255 * 3,
        maximumObjectNameBytes: 255,
        maximumSourceObjectBytes: 65_535,
        maximumOutputObjectBytes: 65_535,
        sha256: createHash("sha256").update(binary.bytes).digest("hex"),
        symbols: proofSymbols,
      },
    };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}
