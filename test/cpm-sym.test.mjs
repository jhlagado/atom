import assert from "node:assert/strict";
import test from "node:test";

import { runCpm22Atom } from "./cpm22-support.mjs";
import { assembleResolvedAtomProject, writeAtomSym } from "../src/host/index.mjs";

const source = Buffer.from([
  "ORG 100H",
  "START: JP MAIN",
  "LIMIT EQU 300",
  "MAIN: LD HL,DATA",
  ".loop: JR .loop",
  "DATA: DB 1",
  "",
].join("\r\n"), "ascii");

async function nodeSym(bytes) {
  const result = await assembleResolvedAtomProject({
    parts: [{ ordinal: 0, bank: 0, originalBytes: bytes, compilerBytes: bytes, logicalIdentity: "SYMS.ASM" }],
  }, { target: { start: 0x100, capacity: 0xff00 } });
  return writeAtomSym(result.generation);
}

// CP/M text ends at the first ^Z, and the file is padded to whole records.
const text = (bytes) => {
  const end = bytes.indexOf(0x1a);
  return Buffer.from(bytes.subarray(0, end < 0 ? bytes.length : end)).toString("latin1");
};

test("ATOM.COM writes the same symbol file as Node", async () => {
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "SYMS.ASM",
    outputName: "SYMS.COM",
    command: "ATOM SYMS SYMS.COM SYMS.SYM",
  });
  assert.match(result.atomTranscript, /SYMS\.COM written/);
  const written = result.readCurrentFile("SYMS.SYM");
  assert.ok(written, "SYMS.SYM was not written");
  assert.equal(written.bytes.length % 128, 0);
  assert.equal(text(written.bytes), text(Buffer.from(await nodeSym(source), "latin1")));
  assert.match(text(written.bytes), /^0100 START\r\n/m);
  assert.match(text(written.bytes), /^012C LIMIT\r\n/m);
  assert.doesNotMatch(text(written.bytes), /LOOP/, "private labels stay out of the file");
  assert.equal(result.readCurrentFile("SYMS.$$S"), undefined);
});

test("the symbol file type defaults to SYM", async () => {
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "SYMS.ASM",
    outputName: "SYMS.COM",
    command: "ATOM SYMS SYMS.COM DEBUG",
  });
  assert.match(result.atomTranscript, /SYMS\.COM written/);
  assert.ok(result.readCurrentFile("DEBUG.SYM"));
});

test("a failed build leaves no symbol file or work file", async () => {
  const broken = Buffer.from("ORG 100H\r\nSTART: JP MISSING\r\n", "ascii");
  const result = await runCpm22Atom(broken, undefined, {
    sourceName: "SYMS.ASM",
    outputName: "SYMS.COM",
    command: "ATOM SYMS SYMS.COM SYMS.SYM",
  });
  assert.match(result.atomTranscript, /undefined symbol MISSING/);
  assert.equal(result.readCurrentFile("SYMS.SYM"), undefined);
  assert.equal(result.readCurrentFile("SYMS.$$S"), undefined);
});

test("a symbol file may not replace the source, or have another type", async () => {
  for (const [sourceName, third, message] of [
    ["SYMS.SYM", "SYMS.SYM", /conflict/i],
    ["SYMS.ASM", "SYMS.TXT", /Invalid output name/],
    ["SYMS.ASM", "SYMS.COM", /Invalid output name/],
  ]) {
    const result = await runCpm22Atom(source, undefined, {
      sourceName,
      outputName: "SYMS.COM",
      command: `ATOM ${sourceName} SYMS.COM ${third}`,
    });
    assert.match(result.atomTranscript, message, third);
    assert.equal(result.outputFile, undefined, third);
  }
});

test("a late publication failure removes the symbol work file and keeps the old one", async () => {
  const priorSym = Buffer.from("0000 OLD\r\n\x1a", "latin1");
  let originalBdosEntry;
  let injected = false;
  let restored = false;
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "SYMS.ASM",
    outputName: "SYMS.COM",
    command: "ATOM SYMS SYMS.COM SYMS.SYM",
    files: [["SYMS.SYM", priorSym]],
    // Fail the rename that would publish SYMS.COM, after SYMS.$$S is written.
    beforeBdos({ call, fcb, memory }) {
      const target = String.fromCharCode(...memory.slice(fcb + 17, fcb + 28).map((byte) => byte & 0x7f));
      if (call === 23 && target === "SYMS    COM" && !injected) {
        originalBdosEntry = memory.slice(5, 8);
        memory.set([0x3e, 0xff, 0xc9], 5);
        injected = true;
      } else if (injected && !restored) {
        memory.set(originalBdosEntry, 5);
        restored = true;
      }
    },
  });
  assert.equal(injected, true);
  assert.match(result.atomTranscript, /SYMS\.COM: could not write the output/);
  assert.equal(result.readCurrentFile("SYMS.$$S"), undefined);
  assert.equal(text(result.readCurrentFile("SYMS.SYM").bytes), "0000 OLD\r\n");
});
