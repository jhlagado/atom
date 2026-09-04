import assert from "node:assert/strict";
import test from "node:test";
import { assembleCpmAtomSource, prepareCpmAtomSource } from "../scripts/cpm22-atom-source.mjs";

const textOf = ({ project }) => project.parts.map(({ compilerBytes }) =>
  new TextDecoder().decode(compilerBytes)).join("");

test("CP/M link aliases avoid all existing identifiers and preserve quoted bytes and comments", () => {
  const source = `ORG 0
Q0000000: DB 1
LONG_GLOBAL_NAME: DB "LONG_GLOBAL_NAME",'Q' ; LONG_GLOBAL_NAME
DW long_global_name,Q0000001
Q0000001: DB $FACE,0FACEH
`;
  const prepared = prepareCpmAtomSource(source);
  assert.equal(prepared.aliases.get("LONG_GLOBAL_NAME"), "Q0000002");
  assert.match(textOf(prepared), /Q0000002: DB "LONG_GLOBAL_NAME",'Q' ; LONG_GLOBAL_NAME/);
  assert.match(textOf(prepared), /DW Q0000002,Q0000001/);
  assert.match(textOf(prepared), /DB \$FACE,0FACEH/);
  assert.deepEqual(prepareCpmAtomSource(source), prepared);
});

test("CP/M link preparation retains exact bytes and restores long global symbol names", async () => {
  const result = await assembleCpmAtomSource(`ORG $100
LONG_ENTRY_POINT: LD HL,LONG_DATA_LABEL
JP LONG_ENTRY_POINT
LONG_DATA_LABEL: DB 'A',LOW(LONG_ENTRY_POINT),HIGH(LONG_ENTRY_POINT)
`, { base: 0x100 });
  assert.deepEqual([...result.bytes], [0x21, 6, 1, 0xc3, 0, 1, 65, 0, 1]);
  assert.equal(result.symbols.LONG_ENTRY_POINT, 0x100);
  assert.equal(result.symbols.LONG_DATA_LABEL, 0x106);
});

test("CP/M link preparation resolves chained forward name aliases without evaluating expressions", async () => {
  const result = await assembleCpmAtomSource(`ORG 0
FIRST_ALIAS EQU SECOND_ALIAS
SECOND_ALIAS EQU WORKSPACE_LABEL
LD HL,FIRST_ALIAS
WORKSPACE_LABEL: DB 7
OFFSET EQU WORKSPACE_LABEL+1
DW SECOND_ALIAS,OFFSET
`);
  assert.deepEqual([...result.bytes], [0x21, 3, 0, 7, 3, 0, 4, 0]);
  assert.equal(result.symbols.FIRST_ALIAS, 3);
  assert.equal(result.symbols.SECOND_ALIAS, 3);
  assert.equal(result.symbols.OFFSET, 4);
});

test("CP/M link aliases preserve independent local-label scopes", async () => {
  const result = await assembleCpmAtomSource(`ORG 0
FORWARD_ALIAS EQU SECOND
FIRST: JR .LONG_LOCAL_LABEL
.LONG_LOCAL_LABEL: DB 1
SECOND: JR .LONG_LOCAL_LABEL
.LONG_LOCAL_LABEL: DB 2
DW FORWARD_ALIAS
`);
  assert.deepEqual([...result.bytes], [0x18, 0, 1, 0x18, 0, 2, 3, 0]);
});

test("CP/M link preparation rejects unresolved and cyclic aliases", () => {
  for (const source of ["UNKNOWN_ALIAS EQU MISSING", "FIRST EQU SECOND\nSECOND EQU FIRST", "SELF EQU SELF"]) {
    assert.throws(() => prepareCpmAtomSource(source), /unresolved CP\/M link aliases/);
  }
});

test("CP/M native assembly still rejects duplicate declarations and missing operands", async () => {
  for (const source of [
    "ORG 0\nDUPLICATE_NAME: DB 1\nDUPLICATE_NAME: DB 2",
    "ORG 0\nALIAS EQU TARGET\nALIAS EQU TARGET\nTARGET: DB 0",
    "ORG 0\nLD HL,UNDEFINED_NAME",
  ]) await assert.rejects(assembleCpmAtomSource(source));
});

test("CP/M link parts split only at complete lines and count UTF-8 bytes", () => {
  const line = `;${"é".repeat(32766)}\n`;
  const prepared = prepareCpmAtomSource(`${line}ORG 0\nDB 7`);
  assert.equal(prepared.project.parts.length, 2);
  assert.equal(prepared.project.parts[0].compilerBytes.length, 65534);
  assert.equal(textOf(prepared), `${line}ORG 0\nDB 7\n`);
  for (const [ordinal, part] of prepared.project.parts.entries()) {
    assert.equal(part.ordinal, ordinal);
    assert.equal(part.logicalIdentity, `cpm-link-${ordinal}.asm`);
    assert.deepEqual(part.originalBytes, part.compilerBytes);
  }
  assert.equal(prepareCpmAtomSource(`;${"x".repeat(65533)}`).project.parts[0].compilerBytes.length, 65535);
  assert.throws(() => prepareCpmAtomSource(`;${"x".repeat(65534)}`), /line exceeds one ATOM part/);
});
