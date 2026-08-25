import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = join(repositoryRoot, "proofs", "cpm22-output-candidates.json");

const candidates = {
  randomRecord: `
.org 0
SET_DMA: .equ $f000
READ_RANDOM: .equ $f003
WRITE_RANDOM: .equ $f006
WRITE_SEQUENTIAL: .equ $f009
CLOSE_TEMP: .equ $f00c
CODE_START:
IMAGE_BYTE:
    push af
    ld de,(CURSOR)
GAP_LOOP:
    ld a,h
    cp d
    jr nz,GAP_BYTE
    ld a,l
    cp e
    jr z,STORE_BYTE
GAP_BYTE:
    xor a
    call APPEND
    inc de
    jr GAP_LOOP
STORE_BYTE:
    pop af
    call APPEND
    inc de
    ld (CURSOR),de
    xor a
    ret
APPEND:
    push hl
    ld hl,(BUFFER_POINTER)
    ld (hl),a
    inc hl
    ld (BUFFER_POINTER),hl
    ld hl,BUFFER_COUNT
    inc (hl)
    jr nz,APPEND_DONE
    call FLUSH_RECORD
APPEND_DONE:
    pop hl
    ret
PATCH_BYTE:
    push af
    call FLUSH_PARTIAL
    ld de,$0100
    or a
    sbc hl,de
    ld a,l
    and $7f
    ld (BYTE_INDEX),a
    add hl,hl
    ld a,h
    rra
    ld (FCB_RANDOM),a
    ld a,0
    rra
    ld (FCB_RANDOM+1),a
    ld de,BUFFER
    call SET_DMA
    call READ_RANDOM
    pop af
    ld hl,BUFFER
    ld a,(BYTE_INDEX)
    ld e,a
    ld d,0
    add hl,de
    ld (hl),a
    call WRITE_RANDOM
    ret
PATCH_WORD:
    push hl
    ld a,l
    ex de,hl
    call PATCH_BYTE
    ex de,hl
    inc hl
    pop de
    ld a,d
    jp PATCH_BYTE
COMMIT:
    call FLUSH_PARTIAL
    jp CLOSE_TEMP
FLUSH_PARTIAL:
    ld a,(BUFFER_COUNT)
    or a
    ret z
FLUSH_RECORD:
    call WRITE_SEQUENTIAL
    ld hl,BUFFER
    ld (BUFFER_POINTER),hl
    xor a
    ld (BUFFER_COUNT),a
    ret
CODE_END:
WORK_START:
CURSOR: .dw $0100
BUFFER_POINTER: .dw BUFFER
BUFFER_COUNT: .db 0
BYTE_INDEX: .db 0
FCB_RANDOM: .ds 3
BUFFER: .ds 128
WORK_END:
.end
`,
  nobjMaterializer: `
.org 0
WRITE_SEQUENTIAL: .equ $f000
READ_RECORD_HEADER: .equ $f003
READ_BANK_ADDRESS: .equ $f006
READ_STREAM_BYTE: .equ $f009
VALIDATE_FLAT_MAP: .equ $f00c
VALIDATE_CRC_AND_PUBLISH: .equ $f00f
CODE_START:
IMAGE_BYTE:
    push af
    ld a,1
    call RECORD_BEGIN
    ld a,c
    call STREAM_BYTE
    ld a,l
    call STREAM_BYTE
    ld a,h
    call STREAM_BYTE
    pop af
    jp STREAM_BYTE
PATCH_BYTE:
    push af
    ld a,2
    call RECORD_BEGIN
    ld a,c
    call STREAM_BYTE
    ld a,l
    call STREAM_BYTE
    ld a,h
    call STREAM_BYTE
    pop af
    jp STREAM_BYTE
PATCH_WORD:
    push hl
    ld a,2
    call RECORD_BEGIN
    ld a,c
    call STREAM_BYTE
    ld a,e
    call STREAM_BYTE
    ld a,d
    call STREAM_BYTE
    pop hl
    ld a,l
    call STREAM_BYTE
    ld a,h
    jp STREAM_BYTE
RECORD_BEGIN:
    call STREAM_BYTE
    xor a
    call STREAM_BYTE
    ld a,4
    jp STREAM_BYTE
STREAM_BYTE:
    push af
    call CRC_UPDATE
    pop af
    ld hl,(BUFFER_POINTER)
    ld (hl),a
    inc hl
    ld (BUFFER_POINTER),hl
    ld hl,BUFFER_COUNT
    inc (hl)
    ret nz
    jp WRITE_SEQUENTIAL
CRC_UPDATE:
    xor h
    ld b,8
CRC_BIT:
    add hl,hl
    jr nc,CRC_NEXT
    ld a,l
    xor $21
    ld l,a
    ld a,h
    xor $10
    ld h,a
CRC_NEXT:
    djnz CRC_BIT
    ret
MATERIALIZE:
    call READ_RECORD_HEADER
    cp 1
    jr z,MATERIALIZE_IMAGE
    cp 2
    jr z,MATERIALIZE_PATCH
    cp 3
    jr z,MATERIALIZE_MAP
    cp 4
    jr z,MATERIALIZE_COMMIT
    scf
    ret
MATERIALIZE_IMAGE:
MATERIALIZE_PATCH:
    call READ_BANK_ADDRESS
MATERIALIZE_BYTES:
    call READ_STREAM_BYTE
    ld (de),a
    inc de
    dec bc
    ld a,b
    or c
    jr nz,MATERIALIZE_BYTES
    jr MATERIALIZE
MATERIALIZE_MAP:
    call VALIDATE_FLAT_MAP
    jr MATERIALIZE
MATERIALIZE_COMMIT:
    jp VALIDATE_CRC_AND_PUBLISH
CODE_END:
WORK_START:
CRC: .dw 0
BUFFER_POINTER: .dw BUFFER
BUFFER_COUNT: .db 0
RECORD_REMAINING: .dw 0
BUFFER: .ds 128
WORK_END:
.end
`,
};

async function measure(name, source) {
  const temporary = await mkdtemp(join(tmpdir(), `atom-cpm22-${name}-`));
  try {
    const path = join(temporary, `${name}.asm`);
    await writeFile(path, source);
    const result = await compile(path, {
      emitBin: true,
      emitD8m: true,
      emitHex: false,
      emitLst: false,
      registerContracts: "off",
    });
    const errors = result.diagnostics.filter(({ severity }) => severity === "error");
    assert.deepEqual(errors, []);
    const map = result.artifacts.find(({ kind }) => kind === "d8m");
    assert.equal(map?.kind, "d8m");
    const symbols = Object.fromEntries(map.json.symbols.flatMap((symbol) => {
      const value = symbol.address ?? symbol.value;
      return value === undefined ? [] : [[symbol.name, value]];
    }));
    return {
      codeBytes: symbols.CODE_END - symbols.CODE_START,
      workspaceBytes: symbols.WORK_END - symbols.WORK_START,
    };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

const result = {
  format: "atom-cpm22-output-candidate-measurement",
  version: 1,
  boundary: "output-specific Z80 kernel; excludes common source loading, diagnostics, FCB names, rollback rename, and user interface",
  inTpaComplete: {
    classification: "Measured complete retained adapter",
    outputCodeBytes: 233,
    outputImageWorkspaceBytes: 18304,
  },
  randomRecord: {
    classification: "Measured lower-bound kernel",
    ...await measure("random-record", candidates.randomRecord),
    completeResidentHypothesisBytes: [850, 1050],
  },
  nobjMaterializer: {
    classification: "Measured lower-bound kernel",
    ...await measure("nobj-materializer", candidates.nobjMaterializer),
    completeResidentHypothesisBytes: [1250, 1800],
  },
};

const rendered = `${JSON.stringify(result, undefined, 2)}\n`;
if (process.argv.includes("--check")) {
  assert.equal(await readFile(outputPath, "utf8"), rendered);
} else {
  await writeFile(outputPath, rendered);
  console.log(rendered.trimEnd());
}
