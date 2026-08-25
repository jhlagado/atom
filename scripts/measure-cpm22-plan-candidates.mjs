import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { compile } from "@jhlagado/azm";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputPath = join(repositoryRoot, "proofs", "cpm22-plan-candidates.json");

const common = `
.org 0
READ_BYTE: .equ $f000
PARSE_TEXT_NAME: .equ $f003
PARSE_FCB_NAME: .equ $f006
EXPECT_EOL: .equ $f009
EXPECT_EOF: .equ $f00c
CODE_START:
`;

const candidates = {
  sp1: `${common}
PARSE:
    call READ_BYTE
    cp 'S'
    jp nz,FAIL
    call READ_BYTE
    cp 'P'
    jp nz,FAIL
    call READ_BYTE
    cp '1'
    jp nz,FAIL
    call READ_BYTE
    cp ' '
    jp nz,FAIL
    call READ_BYTE
    sub '0'
    jp c,FAIL
    cp 10
    jr nc,FAIL
    or a
    jr z,FAIL
    ld b,a
    ld c,1
COUNT_MORE:
    call READ_BYTE
    sub '0'
    jr c,COUNT_DONE
    cp 10
    jr nc,COUNT_DONE
    ld d,a
    inc c
    ld a,c
    cp 4
    jr nc,FAIL
    ld a,b
    add a,a
    ld e,a
    add a,a
    add a,a
    add a,e
    add a,d
    jr c,FAIL
    ld b,a
    jr COUNT_MORE
COUNT_DONE:
    add a,'0'
    call EXPECT_EOL
    jr c,FAIL
    ld a,b
    ld (COUNT),a
    ld (REMAINING),a
PART_LOOP:
    call READ_BYTE
    cp 'P'
    jr nz,FAIL
    call READ_BYTE
    cp ' '
    jr nz,FAIL
    call READ_BYTE
    cp '0'
    jr nz,FAIL
    call READ_BYTE
    cp ' '
    jr nz,FAIL
    call PARSE_TEXT_NAME
    jr c,FAIL
    ld hl,REMAINING
    dec (hl)
    jr nz,PART_LOOP
    call READ_BYTE
    cp 'E'
    jr nz,FAIL
    call READ_BYTE
    cp 'N'
    jr nz,FAIL
    call READ_BYTE
    cp 'D'
    jr nz,FAIL
    call READ_BYTE
    jr c,SUCCESS
    call EXPECT_EOL
    jr c,FAIL
    call EXPECT_EOF
    jr c,FAIL
SUCCESS:
    xor a
    ret
FAIL:
    scf
    ret
CODE_END:
WORK_START:
COUNT: .db 0
REMAINING: .db 0
WORK_END:
.end
`,
  lineManifest: `${common}
PARSE:
    xor a
    ld (COUNT),a
PART_LOOP:
    call READ_BYTE
    jr c,END_FILE
    call PARSE_TEXT_NAME
    jr c,FAIL
    ld hl,COUNT
    inc (hl)
    jr nz,PART_LOOP
FAIL:
    scf
    ret
END_FILE:
    ld a,(COUNT)
    or a
    jr z,FAIL
    ret
CODE_END:
WORK_START:
COUNT: .db 0
WORK_END:
.end
`,
  binaryFcb: `${common}
PARSE:
    call READ_BYTE
    cp 'M'
    jr nz,FAIL
    call READ_BYTE
    cp 'P'
    jr nz,FAIL
    call READ_BYTE
    cp 1
    jr nz,FAIL
    call READ_BYTE
    or a
    jr z,FAIL
    ld (COUNT),a
    ld b,a
PART_LOOP:
    push bc
    call PARSE_FCB_NAME
    pop bc
    jr c,FAIL
    djnz PART_LOOP
    call EXPECT_EOF
    jr c,FAIL
    xor a
    ret
FAIL:
    scf
    ret
CODE_END:
WORK_START:
COUNT: .db 0
WORK_END:
.end
`,
};

async function measure(name, source) {
  const temporary = await mkdtemp(join(tmpdir(), `atom-cpm22-plan-${name}-`));
  try {
    const sourcePath = join(temporary, `${name}.asm`);
    await writeFile(sourcePath, source);
    const result = await compile(sourcePath, {
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
    const symbols = Object.fromEntries(
      map.json.symbols.flatMap((symbol) => {
        const value = symbol.address ?? symbol.value;
        return value === undefined ? [] : [[symbol.name, value]];
      }),
    );
    return {
      parserKernelBytes: symbols.CODE_END - symbols.CODE_START,
      parserWorkspaceBytes: symbols.WORK_END - symbols.WORK_START,
    };
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

const result = {
  format: "atom-cpm22-plan-candidate-measurement",
  version: 1,
  boundary:
    "representation-specific Z80 parser kernel; excludes common command selection, BDOS record input, CP/M filename validation, source preflight, descriptor construction, diagnostics, and source switching",
  commonWorkspace: {
    sourceCacheBytes: 128,
    planCacheBytes: 128,
    maximumDescriptorBytes: 1275,
    planFcbBytes: 36,
    planStateBytes: 4,
    multipartFeatureBytes: 1443,
    totalSourceExecutionBytes: 1571,
  },
  sp1: {
    classification: "Measured parser kernel; existing host format and codec",
    ...(await measure("sp1", candidates.sp1)),
    additionalHostCodecBytes: 0,
  },
  lineManifest: {
    classification:
      "Measured parser kernel; one CP/M 8.3 filename per logical line, physical or text EOF after the final name",
    ...(await measure("line-manifest", candidates.lineManifest)),
    additionalHostCodecBytes: 0,
  },
  binaryFcb: {
    classification: "Measured parser kernel; new CP/M-only binary format",
    ...(await measure("binary-fcb", candidates.binaryFcb)),
    additionalHostCodecBytes: "required, not prototyped",
  },
};

const rendered = `${JSON.stringify(result, undefined, 2)}\n`;
if (process.argv.includes("--check")) {
  assert.equal(await readFile(outputPath, "utf8"), rendered);
} else {
  await writeFile(outputPath, rendered);
  console.log(rendered.trimEnd());
}
