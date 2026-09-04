import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { assembleCpmAtomSource } from "./cpm22-atom-source.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = join(repositoryRoot, "proofs", "cpm22-output-candidates.json");
const censusPath = join(repositoryRoot, "proofs", "cpm22-census.json");

const candidates = {
  randomRecord: `
ORG 0
SET_DMA EQU $f000
READ_RANDOM EQU $f003
WRITE_RANDOM EQU $f006
WRITE_SEQUENTIAL EQU $f009
CLOSE_TEMP EQU $f00c
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
CURSOR: DW $0100
BUFFER_POINTER: DW BUFFER
BUFFER_COUNT: DB 0
BYTE_INDEX: DB 0
FCB_RANDOM: DS 3
BUFFER: DS 128
WORK_END:
`,
  nobjMaterializer: `
ORG 0
WRITE_SEQUENTIAL EQU $f000
READ_RECORD_HEADER EQU $f003
READ_BANK_ADDRESS EQU $f006
READ_STREAM_BYTE EQU $f009
VALIDATE_FLAT_MAP EQU $f00c
VALIDATE_CRC_AND_PUBLISH EQU $f00f
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
CRC: DW 0
BUFFER_POINTER: DW BUFFER
BUFFER_COUNT: DB 0
RECORD_REMAINING: DW 0
BUFFER: DS 128
WORK_END:
`,
};

async function measure(name, source) {
  const { symbols } = await assembleCpmAtomSource(source, { name });
  return {
    codeBytes: symbols.CODE_END - symbols.CODE_START,
    workspaceBytes: symbols.WORK_END - symbols.WORK_START,
  };
}

const census = JSON.parse(await readFile(censusPath, "utf8"));
const result = {
  format: "atom-cpm22-output-candidate-measurement",
  version: 2,
  boundary: "output-specific Z80 kernel; excludes common source loading, diagnostics, FCB names, rollback rename, and user interface",
  inTpaComplete: {
    classification: "Measured complete retained adapter",
    outputCodeBytes: census.outputAdapterCodeBytes,
    outputImageWorkspaceBytes: census.outputBytes,
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
