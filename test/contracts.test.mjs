import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { checkProgram } from "../tools/contracts/check.mjs";

// Check a small program and return its findings as "kind routine" strings.
function check(source) {
  const dir = mkdtempSync(join(tmpdir(), "atom-contracts-"));
  try {
    writeFileSync(join(dir, "main.asm"), source.replace(/^\n/, ""));
    return checkProgram(join(dir, "main.asm")).findings.map((f) => `${f.kind} ${f.routine}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test("a register saved on the stack or in another register is kept", () => {
  assert.deepEqual(
    check(`
;@ROUTINE IN A OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
keeps:
    PUSH BC
    LD   B,A
    LD   C,4
    ADD  A,C
    LD   L,A
    LD   H,0
    LD   A,B
    POP  BC
    RET
`),
    [],
  );
});

test("a write to a kept register is reported", () => {
  assert.deepEqual(
    check(`
;@ROUTINE OUT A
leaks:
    LD   B,3
    LD   A,B
    RET
`),
    ["changes leaks"],
  );
});

test("a call that clobbers a register the caller still needs is a conflict", () => {
  assert.deepEqual(
    check(`
;@ROUTINE CLOBBERS B
outer:
    LD   B,8
.loop:
    CALL inner
    DJNZ .loop
    RET

;@ROUTINE CLOBBERS B
inner:
    LD   B,0
    RET
`),
    ["conflict outer"],
  );
});

test("a register read before it is written must be an input", () => {
  assert.deepEqual(
    check(`
;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
reads:
    LD   A,E
    ADD  A,1
    RET
`),
    ["input reads"],
  );
});

test("OR A to clear carry does not read A", () => {
  assert.deepEqual(
    check(`
;@ROUTINE IN HL,DE OUT HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
diff:
    OR   A
    SBC  HL,DE
    RET
`),
    [],
  );
});

test("outputs need not survive a return with carry set", () => {
  assert.deepEqual(
    check(`
;@ROUTINE OUT HL,CARRY CLOBBERS A,ZERO,SIGN,PARITY,HALFCARRY
outer:
    CALL inner
    RET  C
    LD   HL,0
    RET

;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
inner:
    LD   HL,1
    SCF
    RET
`),
    [],
  );
});

test("an expected output the callee does not return is reported", () => {
  assert.deepEqual(
    check(`
;@ROUTINE CLOBBERS A,HL
outer:
;@EXPECTOUT HL
    CALL inner
    LD   A,L
    RET

;@ROUTINE CLOBBERS HL
inner:
    LD   HL,1
    RET
`),
    ["expect outer"],
  );
});

test("Atom's own source can be checked", () => {
  for (const root of ["cpm22.asm", "atom.asm", "nobj.asm"]) {
    const result = checkProgram(join(dirname(fileURLToPath(import.meta.url)), "..", "src", "z80", root));
    assert.ok(result.routines > 20, `${root} has routines`);
  }
});
