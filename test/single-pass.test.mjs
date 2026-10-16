import assert from "node:assert/strict";
import test from "node:test";

import { assembleResolvedAtomProject } from "../src/host/index.mjs";
import { runCpm22Atom } from "./cpm22-support.mjs";

// Atom reads its source once. Each byte passes through the source service
// exactly once, whatever the tokenizer, the expression parser or a string
// directive does with it.

const encoder = new TextEncoder();

function project(sources) {
  return {
    parts: sources.map((source, ordinal) => {
      const bytes = encoder.encode(source);
      return {
        ordinal,
        bank: 0,
        logicalIdentity: `part${ordinal}.asm`,
        originalBytes: bytes,
        compilerBytes: bytes,
      };
    }),
  };
}

test("every source byte is read exactly once", async () => {
  const sources = [
    [
      "; Names, numbers, comments and both line endings.\r\n",
      "        ORG $4000\r\n",
      "START:  LD A,%1010 ; binary\r\n",
      "        LD HL,0FFFFH\n",
      "        LD A,LOW (TARGET)\n",
      "        LD B,HIGH(START)+1\n",
      "LOW     EQU 1\n",
      "HIGH    EQU 2\n",
      "        LD DE,LOW+HIGH\n",
      ".loop:  DJNZ .loop\n",
    ].join(""),
    [
      "        DB \"A\\x41\\n\",'B',LOW(TARGET)\n",
      "        CSTR \"zero\" ; terminated\n",
      "        PSTR \"len\"\n",
      "        ISTR \"top\"\n",
      "TARGET: DW START\n",
      "        DB 1", // The part ends without a line ending.
    ].join(""),
  ];
  const input = project(sources);
  const assembled = await assembleResolvedAtomProject(input, {
    target: { start: 0x4000, capacity: 0x100 },
  });
  const bytes = input.parts.reduce((sum, part) => sum + part.compilerBytes.length, 0);
  assert.equal(assembled.execution.sourceReads, bytes);
});

test("ATOM.COM reads each source record once, through includes and conditions", async () => {
  // Every file spans several 128-byte records. The root and A include files
  // mid-record, C is included twice, and a false condition hides an include.
  const filler = (label, lines) =>
    Array.from({ length: lines }, (_, index) => `${label}${index}: DB ${index & 0xff} ; padding`).join("\r\n");
  const root = [
    "%DEFINE FULL 1",
    '%INCLUDE "A.ASM"',
    "%IF FULL",
    '%INCLUDE "B.ASM"',
    "%ELSE",
    '%INCLUDE "MISSING.ASM"',
    "%ENDIF",
    filler("R", 20),
    'DB "done",0',
    "",
  ].join("\r\n");
  const files = [
    ["A.ASM", ['%INCLUDE "C.ASM"', filler("A", 15), ""].join("\r\n")],
    ["B.ASM", ['%INCLUDE "C.ASM"', filler("B", 15), ""].join("\r\n")],
    ["C.ASM", ["ORG $100", filler("C", 15), ""].join("\r\n")],
  ].map(([name, text]) => [name, Buffer.from(text, "ascii")]);

  const reads = new Map();
  const result = await runCpm22Atom(Buffer.from(root, "ascii"), undefined, {
    files,
    beforeBdos({ call, fcb, memory }) {
      if (call !== 33) return;
      const name = String.fromCharCode(...memory.slice(fcb + 1, fcb + 12)).trim();
      if (!name.endsWith("ASM")) return;
      const key = `${name}:${memory[fcb + 33] | (memory[fcb + 34] << 8)}`;
      reads.set(key, (reads.get(key) ?? 0) + 1);
    },
  });
  assert.match(result.atomTranscript, /OUTPUT\.COM written/, result.atomTranscript);
  const repeated = [...reads].filter(([, count]) => count > 1);
  assert.deepEqual(repeated, [], "a source record was read more than once");
  const expected = [["INPUT", root.length], ...files.map(([n, b]) => [n.split(".")[0], b.length])];
  for (const [base, length] of expected) {
    for (let record = 0; record < Math.ceil(length / 128); record += 1) {
      const key = [...reads.keys()].find((k) => k.startsWith(base) && k.endsWith(`:${record}`));
      assert.ok(key, `${base} record ${record} was never read`);
    }
  }
});
