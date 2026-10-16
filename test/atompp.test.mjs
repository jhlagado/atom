import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import {
  assembleAtomProject,
  expandAtomMacros,
  materializeAtomGeneration,
} from "../src/host/index.mjs";

const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const run = promisify(execFile);

const LIBRARY = [
  "; Shared macros.",
  "%MACRO SAVE",
  "    PUSH BC",
  "    PUSH DE",
  "%ENDM",
  "",
  "%MACRO WAIT n",
  "    LD   B,%n",
  ".w%@: DJNZ .w%@",
  "%ENDM",
  "",
].join("\n");

const files = { "lib.mac": LIBRARY };
const include = async (_importer, specifier) => ({ name: specifier, text: files[specifier] });

async function project(t, contents) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "atompp-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  for (const [name, text] of Object.entries(contents)) await fs.writeFile(path.join(root, name), text);
  return root;
}

// Expand a .mac source and assemble the result.
async function assemble(t, source) {
  const { text } = await expandAtomMacros(source, { name: "prog.mac", include });
  const root = await project(t, { "prog.asm": text });
  return assembleAtomProject({ root, entry: "prog.asm", target: { start: 0x100, capacity: 64 } });
}

test("macros expand with parameters, unique labels and repeats", async () => {
  const { text, macros, expansions } = await expandAtomMacros([
    '%INCLUDE "lib.mac"',
    "    ORG $100",
    "Start:",
    "    SAVE",
    "    WAIT 10",
    "%REPT 2",
    "    NOP",
    "%ENDR",
    "Done: WAIT 3 ; pause",
    "    RET",
    "",
  ].join("\n"), { name: "prog.mac", include });
  assert.equal(macros, 2);
  assert.equal(expansions, 3);
  assert.equal(text, [
    '%LINE "prog.mac",1',
    ';INCLUDE "lib.mac"',
    '%LINE "lib.mac",1',
    "; Shared macros.",
    ...Array(9).fill(""),
    '%LINE "prog.mac",2',
    "    ORG $100",
    "Start:",
    "; SAVE",
    '%LINE "lib.mac",3',
    "    PUSH BC",
    "    PUSH DE",
    '%LINE "prog.mac",5',
    "; WAIT 10",
    '%LINE "lib.mac",8',
    "    LD   B,10",
    ".w2: DJNZ .w2",
    '%LINE "prog.mac",6',
    ";REPT 2",
    "    NOP",
    '%LINE "prog.mac",7',
    "    NOP",
    ";ENDR",
    "Done: ; WAIT 3 ; pause",
    '%LINE "lib.mac",8',
    "    LD   B,3",
    ".w3: DJNZ .w3",
    '%LINE "prog.mac",10',
    "    RET",
    "",
  ].join("\n"));
});

test("expanded source assembles, and Atom's errors name the .mac lines", async (t) => {
  const built = await assemble(t, '%INCLUDE "lib.mac"\n    ORG $100\nStart: WAIT 2\n    RET\n');
  assert.deepEqual([...materializeAtomGeneration(built.generation).bytes], [0x06, 0x02, 0x10, 0xfe, 0xc9]);
  await assert.rejects(
    () => assemble(t, '%INCLUDE "lib.mac"\n    ORG $100\nStart: WAIT HL\n'),
    (error) => error.message === "lib.mac:8:5: operands are not valid for this instruction",
  );
  await assert.rejects(
    () => assemble(t, '%INCLUDE "lib.mac"\n    ORG $100\nStart: WAIT 1\n    LD BC,A\n'),
    (error) => error.message === "prog.mac:4:5: operands are not valid for this instruction",
  );
});

test("arguments split at top-level commas and keep quotes and parentheses", async () => {
  const { text } = await expandAtomMacros([
    "%MACRO PUT where,what",
    "    LD %where,%what",
    "%ENDM",
    "%MACRO TEXT s,t",
    "    DB %s,%t",
    "%ENDM",
    "    PUT (IX+2),'A'",
    '    TEXT "a,b",\';\'',
    "    PUT AF',%1010",
  ].join("\n"), { name: "args.mac" });
  const body = text.split("\n").filter((line) => /^ {4}(LD|DB)/.test(line));
  assert.deepEqual(body, ["    LD (IX+2),'A'", '    DB "a,b",\';\'', "    LD AF',%1010"]);
});

test("Atom's own directives pass through unchanged", async () => {
  const source = '%DEFINE FAST 1\n%IF FAST\n%INCLUDE "fast.asm"\n%ENDIF\n';
  const { text } = await expandAtomMacros(source, { name: "x.mac" });
  assert.equal(text, `%LINE "x.mac",1\n${source}`);
});

test("malformed macro source is reported at its line", async () => {
  for (const [source, message] of [
    ["%MACRO TWICE\n%ENDM\n%MACRO twice\n%ENDM\n", "x.mac:3:1: macro twice is already defined"],
    ["%MACRO LD\n%ENDM\n", "x.mac:1:1: LD is an instruction or directive"],
    ["%MACRO OPEN\nNOP\n", "x.mac:1:1: %MACRO has no %ENDM"],
    ["%ENDM\n", "x.mac:1:1: %ENDM without %MACRO"],
    ["%REPT 2\nNOP\n", "x.mac:1:1: %REPT has no %ENDR"],
    ["%REPT LOTS\n%ENDR\n", "x.mac:1:1: %REPT needs a count from 0 to 65535, not LOTS"],
    ["%MACRO M a,a\n%ENDM\n", "x.mac:1:1: duplicate macro parameter a"],
    ["%MACRO OUTER\n%MACRO INNER\n%ENDM\n%ENDM\n", "x.mac:1:1: a macro cannot be defined inside another"],
    ["%MACRO M a\n%ENDM\n M 1,2\n", "x.mac:3:1: M takes 1 argument(s), not 2"],
    ["L%@: NOP\n", "x.mac:1:1: %@ is only meaningful inside a macro"],
    ['%LINE "y",1\n', "x.mac:1:1: %LINE is written by ATOMPP, not read by it"],
    ["%MACRO LOOP\n LOOP\n%ENDM\n LOOP\n", "x.mac:2:1: macros nest more than 32 deep"],
  ]) {
    await assert.rejects(
      () => expandAtomMacros(source, { name: "x.mac" }),
      (error) => error.category === "macro" && error.message === message,
      message,
    );
  }
});

test("the atompp command writes the expanded file beside its input", async (t) => {
  const root = await project(t, { "lib.mac": LIBRARY, "prog.mac": '%INCLUDE "lib.mac"\n    ORG $100\nGo: WAIT 4\n' });
  const command = path.join(repository, "bin", "atompp.mjs");
  const { stdout } = await run(process.execPath, [command, "prog.mac"], { cwd: root });
  assert.equal(stdout, "Expanded prog.mac to prog.asm.\n");
  assert.match(await fs.readFile(path.join(root, "prog.asm"), "utf8"), /^%LINE "lib\.mac",8\n {4}LD {3}B,4$/m);
  const failed = await run(process.execPath, [command, "missing.mac"], { cwd: root }).catch((error) => error);
  assert.equal(failed.code, 1);
});
