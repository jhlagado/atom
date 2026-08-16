import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { compile } from "@jhlagado/azm";
import { parseIntelHex } from "@jhlagado/debug80-runtime";

import {
  assembleAtomProject,
  translateAtomLineToAzm,
  translateResolvedAtomProjectToAzm,
} from "../src/host/index.mjs";

test("Atom-to-AZM translation changes only concrete assembler directives", () => {
  assert.equal(translateAtomLineToAzm("Value EQU 42 ; constant"), "Value: .equ 42 ; constant");
  assert.equal(translateAtomLineToAzm("  label: DB 1,\";\" ; data"), "  label: .db 1,\";\" ; data");
  assert.equal(translateAtomLineToAzm("ORG 4000H"), ".org 4000H");
  assert.equal(translateAtomLineToAzm("DW Target"), ".dw Target");
  assert.equal(translateAtomLineToAzm("DS 4"), ".ds 4");
  assert.equal(translateAtomLineToAzm(".LOOP EQU 2"), ".LOOP: .equ 2");
  assert.equal(translateAtomLineToAzm("VALUE: EQU 2"), "VALUE: .equ 2");
  assert.equal(translateAtomLineToAzm(".DATA: DB 1"), ".DATA: .db 1");
  assert.equal(translateAtomLineToAzm('TEXT: CSTR "A;B" ; data'), 'TEXT: .cstr "A;B" ; data');
  assert.equal(translateAtomLineToAzm("DB ';' ; semicolon"), ".db ';' ; semicolon");
  assert.equal(translateAtomLineToAzm("ALIGN 16"), ".align 16");
  assert.equal(translateAtomLineToAzm("LD A,LOW(Target)+HIGH (Other)"), "LD A,LSB(Target)+MSB (Other)");
  assert.equal(translateAtomLineToAzm('DB "LOW(X)",LOW(X) ; HIGH(Y)'), '.db "LOW(X)",LSB(X) ; HIGH(Y)');
  assert.equal(translateAtomLineToAzm("LD A,%1010 ; binary"), "LD A,%1010 ; binary");
});

test("a complete preprocessed multipart Atom program is byte-identical through AZM", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "atom-azm-differential-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await fs.writeFile(path.join(root, "lib.asm"), [
    "ORG 4000H",
    "CONST EQU 2",
    "ROUTINE:",
    ".LOOP: LD A,CONST",
    "JR NZ,.LOOP",
    "RET",
    "",
  ].join("\n"));
  await fs.writeFile(path.join(root, "main.asm"), [
    "%define DEBUG 1",
    "%include \"lib.asm\"",
    "%if DEBUG",
    "START: CALL ROUTINE",
    "%else",
    "START: NOP",
    "%endif",
    "DB \"A\",%1010",
    "DW START",
    "DS 3",
    "",
  ].join("\n"));

  const assembled = await assembleAtomProject({
    root,
    entry: "main.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
  const translated = translateResolvedAtomProjectToAzm(assembled.project);
  const azmPath = path.join(root, "translated.asm");
  await fs.writeFile(azmPath, translated);
  const oracle = await compile(azmPath, {
    emitBin: false,
    emitHex: true,
    emitD8m: false,
    emitLst: false,
    symbolCase: "insensitive",
  });
  const errors = oracle.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, []);
  const hex = oracle.artifacts.find(({ kind }) => kind === "hex");
  assert.notEqual(hex, undefined);
  const oracleProgram = parseIntelHex(hex.text);
  const atomBytes = new Map();
  for (const operation of assembled.generation.images) {
    operation.bytes.forEach((byte, index) => atomBytes.set(operation.address + index, byte));
  }
  for (const operation of assembled.generation.patches) {
    operation.bytes.forEach((byte, index) => atomBytes.set(operation.address + index, byte));
  }
  const oracleAddresses = oracleProgram.writeRanges.flatMap(({ start, end }) =>
    Array.from({ length: end - start }, (_, index) => start + index),
  );
  assert.deepEqual([...atomBytes.keys()], oracleAddresses);
  assert.deepEqual([...atomBytes.values()], oracleAddresses.map((address) => oracleProgram.memory[address]));
  assert.match(translated, /; Atom source part 0: lib\.asm/);
  assert.match(translated, /; Atom source part 1: main\.asm/);
  assert.doesNotMatch(translated, /%include|%if|%define/);
});
