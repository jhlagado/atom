import assert from "node:assert/strict";
import test from "node:test";

import { readCpm22File } from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import {
  expectedMultipartProgram,
  expectedRepresentativeProgram,
  representativeSource,
  runCpm22Atom,
} from "./cpm22-support.mjs";
import { writeIntelHex } from "../src/host/index.mjs";

const multipartParts = [
  Buffer.from("ORG $100\r\nJP START", "ascii"),
  Buffer.from("START:\r\nRET\r\n", "ascii"),
];

async function runMultipart(parts = multipartParts, options = {}) {
  const names = options.names ?? parts.map((_, index) => `P${index}.ASM`);
  const source = options.source ?? Buffer.from(
    `${names.map((name) => `%INCLUDE "${name}"`).join("\r\n")}\r\n`,
    "ascii",
  );
  return runCpm22Atom(
    source,
    options.priorOutput,
    {
      sourceName: options.sourceName ?? "BUILD.ASM",
      outputName: options.outputName ?? "MADE.COM",
      command: options.command ?? "ATOM BUILD.ASM MADE.COM",
      installSource: options.installSource,
      initializeMemory: options.initializeMemory,
      files: [
        ...names.map((name, index) => [name, parts[index]]),
        ...(options.files ?? []),
      ],
    },
  );
}

test("native Atom assembles and runs a byte-identical COM through real CP/M BDOS", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom();
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.ok(result.outputFile, "Atom did not publish OUTPUT.COM");
  assert.equal(expected.base, 0x100);
  assert.deepEqual(result.outputFile.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.ok(result.atomMinimumSp >= 0xd800, "Atom crossed its $D800 stack floor");
  assert.equal(result.returnSp, (result.entrySp + 2) & 0xffff, "Atom returned with an unbalanced stack");
  assert.equal(result.returnA, 0);
  assert.equal(result.atomInstructions, result.census.representativeInstructions);
  assert.equal(result.atomCycles, result.census.representativeTStates);
  assert.equal(result.commandInstructions, result.census.representativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.representativeCommandTStates);
  assert.equal(0xe400 - result.atomMinimumSp, result.census.representativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.representativeBdosCalls);
  assert.equal(result.atomRandomReadRecords.length, result.census.representativeSourceRandomReads);
  assert.deepEqual(result.atomBdosCalls, [
    15, 15, 15, 26, 33, 26, 33,
    15, 26, 33, 26, 33,
    15, 26, 33, 26, 33,
    15, 26, 33, 26, 33,
    19, 22, 26, 21, 16,
    19, 23, 23, 19, 9,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 9,
  ]);
  assert.deepEqual(result.atomRandomReadRecords, [0, 1, 0, 1, 0, 1, 0, 1]);
  assert.equal(result.runOutput(), "OUTPUT\r\r\nHello from native Atom\r\n\r\nA>");
});

test("the CP/M publication path preserves representative eight-bit binary bytes", async () => {
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB 0,$1A,$7F,$80,$FF\r\n", "ascii"),
  );
  assert.deepEqual(
    result.outputFile?.bytes.slice(0, 5),
    Uint8Array.of(0x00, 0x1a, 0x7f, 0x80, 0xff),
  );
});

test("native Atom publishes a selected raw BIN", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "HELLO.ASM",
    outputName: "HELLO.BIN",
  });

  assert.match(result.atomTranscript, /HELLO\.BIN written/);
  assert.deepEqual(
    result.outputFile?.bytes.slice(0, expected.bytes.length),
    expected.bytes,
  );
  assert.equal(result.returnA, 0);
});

test("native Atom publishes checksummed Intel HEX", async () => {
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "HELLO.ASM",
    outputName: "HELLO.HEX",
  });
  const physical = result.outputFile?.bytes ?? new Uint8Array();
  const padding = physical.indexOf(0x1a);
  const text = Buffer.from(physical.slice(0, padding < 0 ? physical.length : padding)).toString("ascii");

  assert.match(result.atomTranscript, /HELLO\.HEX written/);
  assert.equal(text, writeIntelHex(expected, { lineEnding: "\r\n" }));
  assert.equal(result.returnA, 0);
});

test("a rejected assembly preserves an earlier OUTPUT.COM and removes its temp", async () => {
  const prior = Uint8Array.from([0xc9]);
  const result = await runCpm22Atom(Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"), prior);
  assert.match(result.atomTranscript, /Atom error 02 00 000A/);
  assert.equal(result.returnA, 1);
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
  assert.equal(result.atomRandomReadRecords.length, result.census.namedRepresentativeSourceRandomReads);
  assert.equal(result.runOutput(), "MADE\r\r\nHello from native Atom\r\n\r\nA>");
});

test("one native source argument derives ASM input and COM output names", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "HELLO.ASM",
    outputName: "HELLO.COM",
    command: "ATOM HELLO",
  });
  assert.match(result.atomTranscript, /HELLO\.COM written/);
  assert.ok(result.outputFile);
  assert.equal(result.returnA, 0);
});

test("native question-mark help returns success without assembling", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, { command: "ATOM ?" });
  assert.match(result.atomTranscript, /Usage: ATOM \[SOURCE \[OUTPUT\]\]/);
  assert.equal(result.outputFile, undefined);
  assert.equal(result.returnA, 0);
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
    ["ATOM INPUT.ASM OUTPUT.COM EXTRA", "Usage: ATOM [SOURCE [OUTPUT]]"],
    ["ATOM INPUT.ASM OUTPUT.COM @", "Usage: ATOM [SOURCE [OUTPUT]]"],
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
    ["ATOM INPUT.ASM MADE.OBJ", "Invalid output name"],
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
    assert.equal(result.returnA, 2, command);
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

test("%INCLUDE assembles dependencies before the root source", async () => {
  const expected = await expectedMultipartProgram(multipartParts);
  const result = await runMultipart();
  assert.equal(
    result.atomTranscript,
    "ATOM BUILD.ASM MADE.COM\r\r\n\r\nMADE.COM written\r\n\r\nA>",
  );
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.equal(result.atomInstructions, result.census.includeRepresentativeInstructions);
  assert.equal(result.atomCycles, result.census.includeRepresentativeTStates);
  assert.equal(result.atomBdosCalls.length, result.census.includeRepresentativeBdosCalls);
  assert.equal(result.atomRandomReadRecords.length, result.census.includeRepresentativeSourceRandomReads);
});

test("nested includes deduplicate a diamond and preserve sibling order", async () => {
  const result = await runCpm22Atom(
    Buffer.from('%INCLUDE "A.ASM"\r\n%INCLUDE "B.ASM"\r\nDB 4\r\n', "ascii"),
    undefined,
    {
      files: [
        ["A.ASM", Buffer.from('%INCLUDE "C.ASM"\r\nDB 2\r\n', "ascii")],
        ["B.ASM", Buffer.from('%INCLUDE "C.ASM"\r\nDB 3\r\n', "ascii")],
        ["C.ASM", Buffer.from("ORG $100\r\nDB 1\r\n", "ascii")],
      ],
    },
  );
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, 4), Uint8Array.of(1, 2, 3, 4));
});

test("include failures are diagnosed before output publication", async () => {
  const prior = Uint8Array.of(0xc9);
  for (const [source, files, diagnostic] of [
    ['%INCLUDE "MISSING.ASM"\r\n', [], /read failed/],
    ['%INCLUDE MISSING.ASM\r\n', [], /Invalid %INCLUDE/],
    ['NOP\r\n%INCLUDE "LATE.ASM"\r\n', [["LATE.ASM", Buffer.from("RET\r\n")]], /Invalid %INCLUDE/],
    ['%INCLUDE "A.ASM"\r\n', [["A.ASM", Buffer.from('%INCLUDE "INPUT.ASM"\r\n')]], /Include cycle/],
  ]) {
    const result = await runCpm22Atom(Buffer.from(source, "ascii"), prior, { files });
    assert.match(result.atomTranscript, diagnostic, source);
    assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior, source);
  }
});

test("an included source cannot be the selected output", async () => {
  const sourceBytes = Buffer.from("ORG $100\r\nRET\r\n", "ascii");
  const result = await runCpm22Atom(
    Buffer.from('%INCLUDE "OUTPUT.COM"\r\n', "ascii"),
    undefined,
    { files: [["OUTPUT.COM", sourceBytes]] },
  );
  assert.match(result.atomTranscript, /Source\/output conflict/);
  assert.deepEqual(
    Buffer.from(result.outputFile?.bytes.slice(0, sourceBytes.length) ?? []),
    sourceBytes,
  );
});

test("include names are case-insensitive and repeated imports assemble once", async () => {
  const result = await runCpm22Atom(
    Buffer.from('%include "part.asm"\n%INCLUDE "PART.ASM"\r\nDB 2\r\n', "ascii"),
    undefined,
    { files: [["PART.ASM", Buffer.from("ORG $100\r\nDB 1\r\n", "ascii")]] },
  );
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, 2), Uint8Array.of(1, 2));
});

test("include part boundaries cannot join tokens", async () => {
  const result = await runMultipart([
    Buffer.from("ORG $100\r\nLD", "ascii"),
    Buffer.from("A,1\r\n", "ascii"),
  ]);
  assert.match(result.atomTranscript, /Atom error/);
  assert.equal(result.outputFile, undefined);
});

test("native include resolution uses an eight-bit part ABI beyond the old 16-part limit", async () => {
  const names = Array.from({ length: 40 }, (_, index) => `S${index.toString().padStart(3, "0")}.ASM`);
  const files = names.map((name) => [name, Buffer.from(";\r\n", "ascii")]);
  const source = Buffer.from(`${names.map((name) => `%INCLUDE "${name}"`).join("\r\n")}\r\n`, "ascii");
  const accepted = await runCpm22Atom(source, undefined, { files });
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  assert.equal(accepted.census.maximumSourceParts, 255);
  assert.equal(accepted.census.partOrderBytes, 256);
  assert.equal(accepted.census.partNameBytes, 255 * 11);
  assert.equal(accepted.census.partDescriptorBytes, 255 * 5);
});

test("the CP/M source reader accepts 65,535 bytes and rejects the next byte", async () => {
  const exact = Buffer.alloc(65_535, 0x78);
  exact[0] = 0x3b;
  const accepted = await runCpm22Atom(exact);
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  assert.equal(accepted.atomRandomReadRecords.length, 2_048);
  assert.deepEqual(accepted.atomRandomReadRecords.slice(-2), [510, 511]);
  const prior = Uint8Array.from([0xc9]);
  const rejected = await runCpm22Atom(Buffer.concat([exact, Buffer.from("x")]), prior);
  assert.match(rejected.atomTranscript, /INPUT\.ASM read failed/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("the source reader preserves exact CP/M record and text EOF boundaries", async () => {
  for (const length of [127, 128, 129]) {
    const source = Buffer.alloc(length, 0x78);
    source[0] = 0x3b;
    const result = await runCpm22Atom(source);
    assert.match(result.atomTranscript, /OUTPUT\.COM written/, `${length} bytes`);
  }
  const terminated = await runCpm22Atom(
    Buffer.from("ORG $100\r\nRET\r\n\x1aNOT_AN_INSTRUCTION\r\n", "ascii"),
  );
  assert.match(terminated.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(terminated.outputFile?.bytes.slice(0, 1), Uint8Array.from([0xc9]));
});

test("the source reader accepts sources below, at, and above the retired 4 KiB limit", async () => {
  for (const length of [4095, 4096, 4097]) {
    const source = Buffer.alloc(length, 0x78);
    source[0] = 0x3b;
    const result = await runCpm22Atom(source);
    assert.match(result.atomTranscript, /OUTPUT\.COM written/, `${length} bytes`);
  }
});

test("the random-record cache supports forward lookahead and backward token rereads", async () => {
  const lookahead = await runCpm22Atom(
    Buffer.from(`ORG $100\r\nDB LOW${" ".repeat(300)}($1234)\r\n`, "ascii"),
  );
  assert.deepEqual(lookahead.outputFile?.bytes.slice(0, 1), Uint8Array.from([0x34]));
  assert.deepEqual(lookahead.atomRandomReadRecords, [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2]);
  assert.deepEqual(
    lookahead.atomSourceCacheMisses.map(({ key }) => key),
    [0, 0x80, 0x100, 0, 0x80, 0x100, 0, 0x80, 0x100, 0, 0x80, 0x100, 0, 0x80, 0x100],
  );

  const string = await runCpm22Atom(
    Buffer.from(`ORG $100\r\nDB "${"A".repeat(200)}"\r\n`, "ascii"),
  );
  assert.deepEqual(string.outputFile?.bytes.slice(0, 200), new Uint8Array(200).fill(0x41));
  assert.deepEqual(string.atomRandomReadRecords, [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]);
});

test("a malformed source beyond 4 KiB retains its exact offset and rolls back", async () => {
  const prefix = Buffer.from(`;${"x".repeat(4998)}\r\n`, "ascii");
  assert.equal(prefix.length, 0x1389);
  const prior = Uint8Array.from([0xc9]);
  const result = await runCpm22Atom(
    Buffer.concat([prefix, Buffer.from("NOT_AN_INSTRUCTION\r\n", "ascii")]),
    prior,
  );
  assert.match(result.atomTranscript, /Atom error 02 00 1389/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.ok(result.atomMinimumSp >= 0xd800);
});

test("a 16 KiB source assembles through selected files with a measured cache walk", async () => {
  const padding = Buffer.from(`;${"x".repeat(16_381)}\r\n`, "ascii");
  const source = Buffer.concat([padding, representativeSource]);
  assert.equal(source.length, 16_535);
  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "LARGE.ASM",
    outputName: "LARGE.COM",
  });
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.equal(result.atomInstructions, result.census.largeRepresentativeInstructions);
  assert.equal(result.atomCycles, result.census.largeRepresentativeTStates);
  assert.equal(result.atomBdosCalls.length, result.census.largeRepresentativeBdosCalls);
  assert.equal(result.atomRandomReadRecords.length, result.census.largeRepresentativeSourceRandomReads);
  assert.equal(result.atomRandomReadRecords.length, 520);
  assert.deepEqual(result.atomRandomReadRecords.slice(-4), [126, 127, 128, 129]);
  assert.equal(0xe400 - result.atomMinimumSp, 32);
});

test("two Atom commands in one CP/M session reset their source and output state", async () => {
  const second = Buffer.from("ORG $100\r\nLD A,42\r\nRET\r\n", "ascii");
  const result = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "FIRST.ASM",
    outputName: "FIRST.COM",
    files: [["SECOND.ASM", second]],
  });
  assert.match(result.atomTranscript, /FIRST\.COM written/);
  assert.equal(
    result.runCommand("ATOM SECOND.ASM SECOND.COM"),
    "ATOM SECOND.ASM SECOND.COM\r\r\n\r\nSECOND.COM written\r\n\r\nA>",
  );
  assert.deepEqual(
    result.readCurrentFile("SECOND.COM")?.bytes.slice(0, 3),
    Uint8Array.from([0x3e, 42, 0xc9]),
  );
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
