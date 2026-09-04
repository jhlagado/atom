import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  assembleAtomProject,
  translateAzmSourceToAtom,
} from "../src/host/index.mjs";

function run(command, arguments_, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, arguments_, { ...options, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (status, signal) => resolve({ status, signal, stdout, stderr }));
  });
}

function translated(source) {
  return translateAzmSourceToAtom(source, { sourceName: "input.asm" });
}

function translationError(source, code, line = 1, column = 1) {
  assert.throws(
    () => translated(source),
    (error) => {
      assert.equal(error?.name, "AtomAssemblyError");
      assert.equal(error.category, "translation");
      assert.equal(error.code, code);
      assert.deepEqual(error.diagnostic, { logicalIdentity: "input.asm", line, column });
      return true;
    },
  );
}

test("AZM-to-Atom translation maps the strict common language", () => {
  assert.equal(translated([
    ".org 0x4000",
    "BASE .equ 0x4000",
    "LIMIT: .equ 0b100",
    "MASK .equ $0F+0FH+%1+1B",
    "LETTER .equ \"A\"",
    "START:",
    "_loop: ld a,LSB(BASE)+MSB (0x1234)",
    "        ex af,af' ; KEEP COMMENT",
    "        jr nz,_loop",
    "DATA: .db \"LSB(X);\",'A',0b10 ; BYTES",
    "      .dw START",
    "      .ds 2,$FF",
    "      .align 8",
    "      .cstr \"OK\"",
    "      .pstr \"P\"",
    "      .istr \"I\"",
    ".routine in a out hl",
    ".expectout de",
    ".end",
    "; TRAILING COMMENT",
    "",
  ].join("\n")), [
    "ORG $4000",
    "BASE EQU $4000",
    "LIMIT: EQU %100",
    "MASK EQU $0F+0FH+%1+1B",
    "LETTER EQU 'A'",
    "START:",
    ".loop: LD a,LOW(BASE)+HIGH ($1234)",
    "        EX af,af' ; KEEP COMMENT",
    "        JR nz,.loop",
    "DATA: DB \"LSB(X);\",'A',%10 ; BYTES",
    "      DW START",
    "      DS 2,$FF",
    "      ALIGN 8",
    "      CSTR \"OK\"",
    "      PSTR \"P\"",
    "      ISTR \"I\"",
    ";@ROUTINE in a out hl",
    ";@EXPECTOUT de",
    "",
    "; TRAILING COMMENT",
    "",
  ].join("\n"));
});

test("AZM-to-Atom translation rejects every unsupported language boundary", () => {
  for (const source of [
    '.include "lib.asm"',
    '.import "lib.asm"',
    ".if DEBUG",
    ".else",
    ".endif",
    ".contracts strict",
    '.rcignore stack "reason"',
    "Thing .enum A,B",
    "Thing .type",
    "Thing .typealias byte",
    ".binfrom $4000",
    ".binto $4100",
  ]) translationError(source, "unsupported-directive");

  translationError("op move(dst reg8)\nend\n", "op");
  translationError("@PUBLIC: nop\n", "export");
  translationError("TOO_LONG_NAME: nop\n", "symbol-length");
  translationError("START: nop\nVALUE .equ LATER\nLATER: nop\n", "forward-equate", 2, 12);
  translationError("START: nop\nSTART: ret\n", "case-collision", 2, 1);
  translationError("ld a,_loop\n", "private-scope", 1, 6);
  translationError(".db 'AB'\n", "string-form", 1, 5);
  translationError("VALUE .equ \"TEXT\"\n", "string-equate", 1, 12);
  translationError(".db \"\\q\"\n", "escape", 1, 6);
  translationError(".ds Sprite\n", "typed-storage");
  translationError("ld hl,sizeof(Sprite)\n", "layout-expression", 1, 7);
  translationError("ld a,Mode.Read\n", "qualified-symbol", 1, 6);
  translationError("ld a,1 \\ inc a\n", "instruction-chain", 1, 8);
  translationError("FancyOp a,b\n", "unsupported-statement");
  translationError(".end\nnop\n", "content-after-end", 2, 1);
});

test("converted Atom source has the specified instruction, data and string bytes", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "azm-to-atom-differential-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const azmSource = [
    ".org 0x4000",
    "BASE .equ 0x4000",
    "START:",
    "_loop: ld a,LSB(BASE+2)",
    "       inc a",
    "       jr nz,_loop",
    "DATA: .db \"AZM\",0b10,'Z'",
    "      .dw START,MSB(0x1234)",
    "      .ds 2,$5A",
    "      .align 16",
    "      .cstr \"OK\"",
    "      .pstr \"P\"",
    "      .istr \"I\"",
    ".end",
    "",
  ].join("\n");
  const azmPath = path.join(root, "program.asm");
  const atomPath = path.join(root, "program.atom.asm");
  await fs.writeFile(azmPath, azmSource);
  await fs.writeFile(atomPath, translateAzmSourceToAtom(azmSource, { sourceName: "program.asm" }));

  const assembled = await assembleAtomProject({
    root,
    entry: "program.atom.asm",
    target: { start: 0x4000, capacity: 0x100 },
  });
  const atomBytes = new Map();
  for (const operation of [...assembled.generation.images, ...assembled.generation.patches]) {
    operation.bytes.forEach((byte, index) => atomBytes.set(operation.address + index, byte));
  }
  // LD A,2; INC A; JR NZ,-5; data and words; filled reservation;
  // already-aligned address $4010; CSTR "OK", PSTR "P", ISTR "I".
  const expected = [
    0x3e, 2, 0x3c, 0x20, 0xfb,
    0x41, 0x5a, 0x4d, 2, 0x5a, 0, 0x40, 0x12, 0,
    0x5a, 0x5a, 0x4f, 0x4b, 0, 1, 0x50, 0xc9,
  ];
  assert.deepEqual([...atomBytes.keys()], expected.map((_, index) => 0x4000 + index));
  assert.deepEqual([...atomBytes.values()], expected);
});

test("azm-to-atom CLI writes .atom.asm once and reports positioned failures", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "azm-to-atom-cli-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  await fs.writeFile(path.join(root, "main.asm"), ".org 0x4000\nSTART: nop\n.end\n");
  const executable = path.resolve("bin/azm-to-atom.mjs");
  const first = await run(executable, ["main.asm"], { cwd: root });
  assert.equal(first.status, 0, first.stderr);
  assert.equal(await fs.readFile(path.join(root, "main.atom.asm"), "utf8"), "ORG $4000\nSTART: NOP\n\n");
  const second = await run(executable, ["main.asm"], { cwd: root });
  assert.equal(second.status, 1);
  assert.match(second.stderr, /EEXIST/);

  await fs.writeFile(path.join(root, "bad.asm"), "START: nop\n.include \"x.asm\"\n");
  const bad = await run(executable, ["--stdout", "bad.asm"], { cwd: root });
  assert.equal(bad.status, 1);
  assert.equal(bad.stdout, "");
  assert.match(bad.stderr, /^bad\.asm:2:1: AZM directive \.INCLUDE has no Atom equivalent/m);
});
