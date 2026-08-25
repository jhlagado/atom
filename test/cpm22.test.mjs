import assert from "node:assert/strict";
import test from "node:test";

import { readCpm22File } from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import {
  expectedRepresentativeProgram,
  representativeSource,
  runCpm22Atom,
} from "./cpm22-support.mjs";

test("native Atom assembles and runs a byte-identical COM through real CP/M BDOS", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom();
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.ok(result.outputFile, "Atom did not publish OUTPUT.COM");
  assert.equal(expected.base, 0x100);
  assert.deepEqual(result.outputFile.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.ok(result.atomMinimumSp >= 0xd800, "Atom crossed its $D800 stack floor");
  assert.equal(result.returnSp, (result.entrySp + 2) & 0xffff, "Atom returned with an unbalanced stack");
  assert.equal(result.atomInstructions, result.census.representativeInstructions);
  assert.equal(result.atomCycles, result.census.representativeTStates);
  assert.equal(result.commandInstructions, result.census.representativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.representativeCommandTStates);
  assert.equal(0xe400 - result.atomMinimumSp, result.census.representativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.representativeBdosCalls);
  assert.deepEqual(result.atomBdosCalls, [
    15, 15, 15, 26, 20, 26, 20, 16,
    19, 22, 26, 21, 16,
    19, 23, 23, 19, 9,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 9,
  ]);
  assert.equal(result.runOutput(), "OUTPUT\r\r\nHello from native Atom\r\n\r\nA>");
});

test("a rejected assembly preserves an earlier OUTPUT.COM and removes its temp", async () => {
  const prior = Uint8Array.from([0xc9]);
  const result = await runCpm22Atom(Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"), prior);
  assert.match(result.atomTranscript, /Atom error 02 00 000A/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(
    (await import("@jhlagado/debug80-runtime/platforms/cpm22/filesystem"))
      .readCpm22File(result.finalDisk, "OUTPUT.$$$"),
    undefined,
  );
});

test("command-tail filenames select a different source and output COM", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "HELLO.ASM",
    outputName: "MADE.COM",
  });
  assert.equal(
    result.atomTranscript,
    "ATOM HELLO.ASM MADE.COM\r\r\n\r\nMADE.COM written\r\n\r\nA>",
  );
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.equal(result.atomInstructions, result.census.namedRepresentativeInstructions);
  assert.equal(result.atomCycles, result.census.namedRepresentativeTStates);
  assert.equal(result.commandInstructions, result.census.namedRepresentativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.namedRepresentativeCommandTStates);
  assert.equal(result.atomBdosCalls.length, result.census.namedRepresentativeBdosCalls);
  assert.equal(result.runOutput(), "MADE\r\r\nHello from native Atom\r\n\r\nA>");
});

test("command-tail parsing accepts maximum 8.3 names, lowercase, and extra spaces", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "ABCDEFGH.XYZ",
    outputName: "OUT12345.COM",
    command: "ATOM   abcdefgh.xyz   out12345.com   ",
  });
  assert.match(result.atomTranscript, /OUT12345\.COM written/);
  assert.ok(result.outputFile);
});

test("command-tail parsing accepts CP/M-safe punctuation", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "A$#@!-^{.ASM",
    outputName: "O%&'()~{.COM",
  });
  assert.match(result.atomTranscript, /O%&'\(\)~\{\.COM written/);
  assert.ok(result.outputFile);
});

test("command-tail parsing rejects every reserved punctuation class", async () => {
  for (const punctuation of ["*", "+", ",", "/", ":", ";", "<", "=", ">", "?", "[", "\\", "]", "_"]) {
    const command = `ATOM A${punctuation}B.ASM MADE.COM`;
    const result = await runCpm22Atom(representativeSource, undefined, { command });
    assert.match(result.atomTranscript, /Invalid source name/, command);
    assert.equal(result.outputFile, undefined, command);
  }
});

test("a blank command tail retains INPUT.ASM and OUTPUT.COM defaults", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, {
    command: "ATOM     ",
  });
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.ok(result.outputFile);
});

test("command-tail parsing reports exact usage and filename diagnostics", async () => {
  for (const [command, diagnostic] of [
    ["ATOM INPUT.ASM", "Usage: ATOM [SOURCE OUTPUT.COM]"],
    ["ATOM INPUT.ASM OUTPUT.COM EXTRA", "Usage: ATOM [SOURCE OUTPUT.COM]"],
    ["ATOM TOOLONGGG.ASM MADE.COM", "Invalid source name"],
    ["ATOM INPUT.ASMX MADE.COM", "Invalid source name"],
    ["ATOM .ASM MADE.COM", "Invalid source name"],
    ["ATOM INPUT. MADE.COM", "Invalid source name"],
    ["ATOM IN*.ASM MADE.COM", "Invalid source name"],
    ["ATOM A:INPUT.ASM MADE.COM", "Invalid source name"],
    ["ATOM INPUT.ASM TOOLONGGG.COM", "Invalid output name"],
    ["ATOM INPUT.ASM MADE.COMX", "Invalid output name"],
    ["ATOM INPUT.ASM .COM", "Invalid output name"],
    ["ATOM INPUT.ASM MADE.", "Invalid output name"],
    ["ATOM INPUT.ASM MADE", "Invalid output name"],
    ["ATOM INPUT.ASM MADE.BIN", "Invalid output name"],
    ["ATOM INPUT.ASM M?.COM", "Invalid output name"],
  ]) {
    const result = await runCpm22Atom(representativeSource, undefined, {
      command,
    });
    assert.equal(
      result.atomTranscript,
      `${command.toUpperCase()}\r\r\n\r\n${diagnostic}\r\n\r\nA>`,
      command,
    );
    assert.equal(result.outputFile, undefined, command);
  }
});

test("pre-existing transaction files are preserved and block publication", async () => {
  const prior = Uint8Array.from([0xc9]);
  const sentinel = Uint8Array.from([1, 2, 3, 4]);
  for (const auxiliaryName of ["MADE.$$$", "MADE.BAK"]) {
    const result = await runCpm22Atom(representativeSource, prior, {
      sourceName: "HELLO.ASM",
      outputName: "MADE.COM",
      files: [[auxiliaryName, sentinel]],
    });
    assert.match(result.atomTranscript, /Temp\/backup file exists/);
    assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
    assert.deepEqual(
      readCpm22File(result.finalDisk, auxiliaryName)?.bytes.slice(0, sentinel.length),
      sentinel,
    );
  }
});

test("source names cannot collide with output publication files", async () => {
  for (const sourceName of ["MADE.COM", "MADE.$$$", "MADE.BAK"]) {
    const result = await runCpm22Atom(representativeSource, undefined, {
      sourceName,
      outputName: "MADE.COM",
    });
    assert.match(result.atomTranscript, /Source\/output conflict/);
    const preserved = readCpm22File(result.finalDisk, sourceName);
    assert.ok(preserved, `${sourceName} must be preserved`);
    assert.deepEqual(
      Buffer.from(preserved.bytes.slice(0, representativeSource.length)),
      representativeSource,
    );
    assert.equal(result.outputFile === undefined, sourceName !== "MADE.COM");
  }
});

test("named rollback preserves an earlier output and removes the selected temp", async () => {
  const prior = Uint8Array.from([0xc9]);
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"),
    prior,
    { sourceName: "BROKEN.ASM", outputName: "MADE.COM" },
  );
  assert.match(result.atomTranscript, /Atom error 02 00 000A/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "MADE.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "MADE.BAK"), undefined);
});

test("a missing selected source names the failed file and publishes nothing", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "MISSING.ASM",
    outputName: "MADE.COM",
    installSource: false,
  });
  assert.match(result.atomTranscript, /MISSING\.ASM read failed/);
  assert.equal(result.outputFile, undefined);
});

test("the CP/M source buffer accepts 4096 bytes and rejects the next byte", async () => {
  const prefix = Buffer.from("ORG $100\r\nRET\r\n;", "ascii");
  const exact = Buffer.concat([prefix, Buffer.alloc(4096 - prefix.length, 0x78)]);
  const accepted = await runCpm22Atom(exact);
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  const prior = Uint8Array.from([0xc9]);
  const rejected = await runCpm22Atom(Buffer.concat([exact, Buffer.from("x")]), prior);
  assert.match(rejected.atomTranscript, /INPUT\.ASM read failed/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("the CP/M target accepts 18,304 bytes and rejects the next byte atomically", async () => {
  const exact = Buffer.from("ORG $100\r\nDS $4780,0\r\n", "ascii");
  const accepted = await runCpm22Atom(exact);
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  assert.ok(accepted.outputFile);
  assert.equal(accepted.outputFile.records, 143);
  const prior = Uint8Array.from([0xc9]);
  const rejected = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $4781,0\r\n", "ascii"),
    prior,
  );
  assert.match(rejected.atomTranscript, /Atom error 02 00 000A/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});
