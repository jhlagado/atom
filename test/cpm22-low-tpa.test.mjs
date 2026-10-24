import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  cpmLayout,
  expectedRepresentativeProgram,
  representativeSource,
  runCpm22Atom,
} from "./cpm22-support.mjs";

// TEC-OS keeps CP/M 2.2 in ROM and gives programs $0100-$B405, with the BDOS
// entry at $B406. These runs move the vector at $0006 there before ATOM.COM
// starts and restore the real one for each BDOS call, so nothing above $B405
// may change while Atom runs. The emulated system's CCP begins at $E400.
const tecOsBdos = 0xb406;
const ccpBase = 0xe400;
const cpmCensus = JSON.parse(await readFile(
  new URL("../proofs/cpm22-census.json", import.meta.url),
  "utf8",
));
const tecOs = cpmLayout(cpmCensus, tecOsBdos);
const tecOsCensus = cpmCensus.layouts.find(({ bdosAddress }) => bdosAddress === tecOsBdos);

async function runAtTecOs(source, prior, options = {}) {
  let bdos;
  let above;
  const result = await runCpm22Atom(source, prior, {
    ...options,
    beforeAtomEntry(memory) {
      bdos = memory.slice(6, 8);
      memory[6] = tecOsBdos & 0xff;
      memory[7] = tecOsBdos >>> 8;
      memory.fill(0x69, tecOsBdos, ccpBase);
    },
    beforeBdos({ memory }) { memory.set(bdos, 6); },
    afterAtomReturn(memory) { above = memory.slice(tecOsBdos, ccpBase); },
  });
  assert.deepEqual(above, new Uint8Array(ccpBase - tecOsBdos).fill(0x69), "Atom wrote above the TEC-OS TPA");
  assert.ok(result.atomMinimumSp >= tecOs.stackFloorAddress, "Atom crossed its stack floor");
  assert.equal(result.returnSp, tecOsBdos, "Atom reached warm boot with an unbalanced private stack");
  return result;
}

test("the census records the TEC-OS layout ATOM.COM computes", () => {
  assert.ok(cpmCensus.minimumBdosAddress < tecOsBdos);
  assert.equal(tecOsCensus.stackFloorAddress, tecOs.stackFloorAddress);
  assert.equal(tecOsCensus.materializerWindowBytes, tecOs.materializerWindowBytes);
  assert.equal(
    tecOsCensus.symbolBytes + tecOsCensus.pendingBytes,
    tecOs.stackFloorAddress - cpmCensus.arenaStartAddress,
  );
});

test("ATOM.COM assembles a byte-identical COM with BDOS at $B406", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runAtTecOs(representativeSource);
  assert.equal(result.returnA, 0);
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(result.outputFile.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.equal(result.runOutput(), "OUTPUT\r\r\nHello from native Atom\r\n\r\nA>");
});

test("ATOM.COM replays a BIN across its smaller TEC-OS windows", async () => {
  const windowBytes = tecOs.materializerWindowBytes;
  const patchAddress = 0x100 + windowBytes - 1;
  const targetAddress = patchAddress + 2;
  const source = Buffer.from([
    "ORG $100",
    "DB 0",
    `ORG $${patchAddress.toString(16)}`,
    "DW DEST",
    "DEST:",
    "DB $A5",
    "",
  ].join("\r\n"), "ascii");
  const result = await runAtTecOs(source, undefined, {
    sourceName: "WINDOW.ASM",
    outputName: "WINDOW.BIN",
  });
  assert.equal(result.returnA, 0);
  assert.match(result.atomTranscript, /WINDOW\.BIN written/);
  assert.equal(result.outputFile.bytes.length, windowBytes + 128);
  assert.deepEqual(
    result.outputFile.bytes.slice(windowBytes - 1, windowBytes + 2),
    Uint8Array.of(targetAddress & 0xff, targetAddress >>> 8, 0xa5),
  );
});

test("ATOM.COM reports out of memory when the TEC-OS arenas fill", async () => {
  const capacity = tecOsCensus.pendingReferences;
  const source = (references) => Buffer.from([
    "ORG $100",
    ...Array.from({ length: references }, () => "DW TARGET"),
    "TARGET: RET",
    "",
  ].join("\r\n"), "ascii");

  const fits = await runAtTecOs(source(capacity));
  assert.equal(fits.returnA, 0);
  assert.match(fits.atomTranscript, /OUTPUT\.COM written/);

  const prior = new Uint8Array(128).fill(0xa5);
  const full = await runAtTecOs(source(capacity + 1), prior);
  assert.equal(full.returnA, 1);
  assert.match(
    full.atomTranscript,
    new RegExp(`INPUT\\.ASM:${capacity + 2}:1: out of memory: too many forward references\\r\\n`),
  );
  assert.deepEqual(full.outputFile.bytes, prior);
});
