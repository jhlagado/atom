import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  assembleAtomProject,
  translateAtomLineToAzm,
  translateResolvedAtomProjectToAzm,
  translateAzmSourceToAtom,
} from "../src/host/index.mjs";

test("Atom-to-AZM translation changes only concrete assembler directives", () => {
  assert.equal(translateAtomLineToAzm("Value EQU 42 ; constant"), "Value: .equ 42 ; constant");
  assert.equal(translateAtomLineToAzm("  label: DB 1,\";\" ; data"), "  label: .db 1,\";\" ; data");
  assert.equal(translateAtomLineToAzm("ORG 4000H"), ".org 4000H");
  assert.equal(translateAtomLineToAzm("DW Target"), ".dw Target");
  assert.equal(translateAtomLineToAzm("DS 4"), ".ds 4");
  assert.equal(translateAtomLineToAzm(".LOOP EQU 2"), "_LOOP: .equ 2");
  assert.equal(translateAtomLineToAzm("VALUE: EQU 2"), "VALUE: .equ 2");
  assert.equal(translateAtomLineToAzm(".DATA: DB 1"), "_DATA: .db 1");
  assert.equal(translateAtomLineToAzm("JR NZ,.LOOP"), "JR NZ,_LOOP");
  assert.equal(translateAtomLineToAzm(";@ROUTINE IN A OUT HL"), ".routine IN A OUT HL");
  assert.equal(translateAtomLineToAzm(";@EXPECTOUT DE"), ".expectout DE");
  assert.equal(translateAtomLineToAzm('TEXT: CSTR "A;B" ; data'), 'TEXT: .cstr "A;B" ; data');
  assert.equal(translateAtomLineToAzm("DB ';' ; semicolon"), ".db ';' ; semicolon");
  assert.equal(translateAtomLineToAzm("ALIGN 16"), ".align 16");
  assert.equal(translateAtomLineToAzm("LD A,LOW(Target)+HIGH (Other)"), "LD A,LSB(Target)+MSB (Other)");
  assert.equal(translateAtomLineToAzm('DB "LOW(X)",LOW(X) ; HIGH(Y)'), '.db "LOW(X)",LSB(X) ; HIGH(Y)');
  assert.equal(translateAtomLineToAzm("LD A,%1010 ; binary"), "LD A,%1010 ; binary");
});

test("a preprocessed multipart Atom program preserves exact bytes and translation boundaries", async (t) => {
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
  const atomBytes = new Map();
  for (const operation of assembled.generation.images) {
    operation.bytes.forEach((byte, index) => atomBytes.set(operation.address + index, byte));
  }
  for (const operation of assembled.generation.patches) {
    operation.bytes.forEach((byte, index) => atomBytes.set(operation.address + index, byte));
  }
  // LD A,2; JR NZ,-4; RET; CALL $4000; DB "A",10; DW $4005.
  // The final DS 3 reserves addresses without initializing them.
  const expected = [0x3e, 2, 0x20, 0xfc, 0xc9, 0xcd, 0, 0x40, 0x41, 10, 5, 0x40];
  assert.deepEqual([...atomBytes.keys()], expected.map((_, index) => 0x4000 + index));
  assert.deepEqual([...atomBytes.values()], expected);
  assert.match(translated, /; Atom source part 0: lib\.asm/);
  assert.match(translated, /; Atom source part 1: main\.asm/);
  assert.doesNotMatch(translated, /%include|%if|%define/);

  // Also exercise the translated text, so lost or changed statements cannot
  // pass merely because the original ATOM source still assembles correctly.
  await fs.writeFile(path.join(root, "roundtrip.asm"), translateAzmSourceToAtom(translated));
  const roundtrip = await assembleAtomProject({
    root,
    entry: "roundtrip.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
  const roundtripBytes = new Map();
  for (const operation of [...roundtrip.generation.images, ...roundtrip.generation.patches]) {
    operation.bytes.forEach((byte, index) => roundtripBytes.set(operation.address + index, byte));
  }
  assert.deepEqual([...roundtripBytes], expected.map((byte, index) => [0x4000 + index, byte]));
});
