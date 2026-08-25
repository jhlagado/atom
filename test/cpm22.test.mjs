import assert from "node:assert/strict";
import test from "node:test";

import { readCpm22File } from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import {
  expectedMultipartProgram,
  expectedRepresentativeProgram,
  representativeSource,
  runCpm22Atom,
} from "./cpm22-support.mjs";

const multipartParts = [
  Buffer.from("ORG $100\r\nJP START", "ascii"),
  Buffer.from("START:\r\nRET\r\n", "ascii"),
];

async function runMultipart(plan, parts = multipartParts, options = {}) {
  const names = options.names ?? parts.map((_, index) => `P${index}.ASM`);
  return runCpm22Atom(
    typeof plan === "string" ? Buffer.from(plan, "ascii") : plan,
    options.priorOutput,
    {
      sourceName: options.planName ?? "BUILD.LST",
      outputName: options.outputName ?? "MADE.COM",
      command: options.command ?? "ATOM BUILD.LST MADE.COM @",
      installSource: options.installPlan,
      initializeMemory: options.initializeMemory,
      files: [
        ...names.map((name, index) => [name, parts[index]]),
        ...(options.files ?? []),
      ],
    },
  );
}

function sourceListAtLength(target) {
  const widths = [];
  function choose(remaining) {
    if (remaining === 0) return true;
    for (let width = Math.min(11, remaining); width >= 4; width -= 1) {
      if (choose(remaining - width)) {
        widths.push(width);
        return true;
      }
    }
    return false;
  }
  assert.equal(choose(target), true, `cannot construct a ${target}-byte source list`);
  const names = widths.map((width, index) => {
    const stemLength = width - 3;
    const stem = `${index.toString(36).toUpperCase()}${"X".repeat(8)}`.slice(0, stemLength);
    return `${stem}.A`;
  });
  const plan = Buffer.from(`${names.join("\n")}\n`, "ascii");
  assert.equal(plan.length, target);
  return { names, plan };
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
  assert.equal(result.atomInstructions, result.census.representativeInstructions);
  assert.equal(result.atomCycles, result.census.representativeTStates);
  assert.equal(result.commandInstructions, result.census.representativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.representativeCommandTStates);
  assert.equal(0xe400 - result.atomMinimumSp, result.census.representativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.representativeBdosCalls);
  assert.equal(result.atomSourceSequentialReads, result.census.representativeSourceSequentialReads);
  assert.equal(result.atomRandomReadRecords.length, result.census.representativeSourceRandomReads);
  assert.deepEqual(result.atomBdosCalls, [
    15, 15, 15, 26, 20, 20, 33, 33,
    19, 22, 26, 21, 16,
    19, 23, 23, 19, 9,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 9,
  ]);
  assert.deepEqual(result.atomRandomReadRecords, [0, 1]);
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
  assert.equal(result.atomSourceSequentialReads, result.census.namedRepresentativeSourceSequentialReads);
  assert.equal(result.atomRandomReadRecords.length, result.census.namedRepresentativeSourceRandomReads);
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
    ["ATOM INPUT.ASM", "Usage: ATOM [SOURCE OUTPUT.COM [@]]"],
    ["ATOM INPUT.ASM OUTPUT.COM EXTRA", "Usage: ATOM [SOURCE OUTPUT.COM [@]]"],
    ["ATOM INPUT.ASM OUTPUT.COM @@", "Usage: ATOM [SOURCE OUTPUT.COM [@]]"],
    ["ATOM INPUT.ASM OUTPUT.COM @ EXTRA", "Usage: ATOM [SOURCE OUTPUT.COM [@]]"],
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

test("a trailing @ assembles ordered source-list parts without changing two-name mode", async () => {
  const expected = await expectedMultipartProgram(multipartParts);
  const result = await runMultipart("P0.ASM\r\nP1.ASM\r\n");
  assert.equal(
    result.atomTranscript,
    "ATOM BUILD.LST MADE.COM @\r\r\n\r\nMADE.COM written\r\n\r\nA>",
  );
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.deepEqual(result.atomRandomReadRecords, [0, 0]);
  assert.equal(result.atomInstructions, result.census.multipartRepresentativeInstructions);
  assert.equal(result.atomCycles, result.census.multipartRepresentativeTStates);
  assert.equal(result.commandInstructions, result.census.multipartRepresentativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.multipartRepresentativeCommandTStates);
  assert.equal(0xe400 - result.atomMinimumSp, result.census.multipartRepresentativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.multipartRepresentativeBdosCalls);
  assert.equal(result.atomPlanSequentialReads, result.census.multipartRepresentativePlanReads);
  assert.equal(
    result.atomSourceSequentialReads,
    result.census.multipartRepresentativeSourceSequentialReads,
  );
  assert.equal(
    result.atomRandomReadRecords.length,
    result.census.multipartRepresentativeSourceRandomReads,
  );
  assert.deepEqual(result.atomBdosCalls, [
    15, 15, 15, 26, 20,
    15, 26, 20, 15, 26, 20,
    15, 26, 20,
    15, 26, 33, 15, 26, 33,
    19, 22, 26, 21, 16,
    19, 23, 23, 19, 9,
    2, 2, 2, 2, 2, 2, 2, 2, 9,
  ]);
  assert.equal(result.runOutput(), "MADE\r\r\n\r\nA>");
  assert.ok(result.atomMinimumSp >= 0xd800);
  assert.equal(result.returnSp, (result.entrySp + 2) & 0xffff);

  const ordinary = await runCpm22Atom(representativeSource, undefined, {
    sourceName: "BUILD.LST",
    outputName: "MADE.COM",
  });
  assert.match(ordinary.atomTranscript, /MADE\.COM written/);
});

test("source-list diagnostics retain the exact part ordinal and local offset", async () => {
  const parts = [
    Buffer.from("ORG $100\r\n", "ascii"),
    Buffer.from("; second part\r\n", "ascii"),
    Buffer.from("NOT_AN_INSTRUCTION\r\n", "ascii"),
  ];
  const prior = Uint8Array.from([0xc9]);
  const result = await runMultipart("P0.ASM\nP1.ASM\nP2.ASM\n", parts, {
    priorOutput: prior,
  });
  assert.match(result.atomTranscript, /Atom error 02 02 0000/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "MADE.$$$"), undefined);
});

test("source-list part boundaries cannot join tokens", async () => {
  const result = await runMultipart("P0.ASM\nP1.ASM\n", [
    Buffer.from("ORG $100\nLD", "ascii"),
    Buffer.from("A,1\n", "ascii"),
  ]);
  assert.match(result.atomTranscript, /Atom error 02 00 0009/);
  assert.equal(result.outputFile, undefined);
});

test("source lists distinguish missing plans, missing parts, and malformed records", async () => {
  const prior = Uint8Array.from([0x00, 0xc9]);
  const missingPlan = await runMultipart("P0.ASM\n", multipartParts, {
    installPlan: false,
    priorOutput: prior,
  });
  assert.match(missingPlan.atomTranscript, /BUILD\.LST read failed/);
  assert.deepEqual(missingPlan.outputFile?.bytes.slice(0, prior.length), prior);

  const missingPart = await runMultipart("MISSING.ASM\n", [], {
    names: [],
    priorOutput: prior,
  });
  assert.match(missingPart.atomTranscript, /MISSING\.ASM read failed/);
  assert.deepEqual(missingPart.outputFile?.bytes.slice(0, prior.length), prior);

  for (const plan of ["\x1a", "\n", "TOOLONGGG.ASM\n", "A..ASM\n", "A:BAD.ASM\n"]) {
    const malformed = await runMultipart(plan, [], { names: [], priorOutput: prior });
    assert.match(malformed.atomTranscript, /Invalid plan/, JSON.stringify(plan));
    assert.deepEqual(malformed.outputFile?.bytes.slice(0, prior.length), prior);
  }
});

test("source lists accept LF, CRLF, final-name EOF, text EOF, and lowercase names", async () => {
  for (const plan of [
    "p0.asm\np1.asm\n",
    "P0.ASM\r\nP1.ASM\r\n",
    "P0.ASM\nP1.ASM",
    "P0.ASM\nP1.ASM\x1aignored.invalid\n",
  ]) {
    const result = await runMultipart(plan);
    assert.match(result.atomTranscript, /MADE\.COM written/, JSON.stringify(plan));
    assert.ok(result.outputFile);
  }
});

test("source-list mode accepts trailing command spaces and rejects publication-name parts", async () => {
  const spaced = await runMultipart("P0.ASM\nP1.ASM\n", multipartParts, {
    command: "ATOM BUILD.LST MADE.COM @   ",
  });
  assert.match(spaced.atomTranscript, /MADE\.COM written/);

  for (const sourceName of ["MADE.COM", "MADE.$$$", "MADE.BAK"]) {
    const source = Buffer.from("ORG $100\nRET\n", "ascii");
    const result = await runMultipart(`${sourceName}\n`, [source], { names: [sourceName] });
    assert.match(
      result.atomTranscript,
      sourceName === "MADE.COM" ? /Source\/output conflict/ : /Temp\/backup file exists/,
      sourceName,
    );
    assert.deepEqual(
      readCpm22File(result.finalDisk, sourceName)?.bytes.slice(0, source.length),
      Uint8Array.from(source),
      sourceName,
    );
  }
});

test("duplicate source-list entries remain distinct ordered parts", async () => {
  const shared = Buffer.from("; shared comment", "ascii");
  const tail = Buffer.from("ORG $100\r\nRET\r\n", "ascii");
  const result = await runMultipart("SHARED.ASM\nSHARED.ASM\nTAIL.ASM\n", [shared, tail], {
    names: ["SHARED.ASM", "TAIL.ASM"],
  });
  assert.match(result.atomTranscript, /MADE\.COM written/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, 1), Uint8Array.from([0xc9]));
});

test("source-list bytes cross exact 127, 128, and 129-byte record boundaries", async () => {
  for (const length of [127, 128, 129]) {
    const { names, plan } = sourceListAtLength(length);
    const parts = names.map((_, index) =>
      Buffer.from(index === names.length - 1 ? "ORG $100\nRET\n" : "; part", "ascii"),
    );
    const result = await runMultipart(plan, parts, { names });
    assert.match(result.atomTranscript, /MADE\.COM written/, `${length} bytes`);
    assert.deepEqual(result.outputFile?.bytes.slice(0, 1), Uint8Array.from([0xc9]));
  }
});

test("source-list capacity accepts 255 parts within its exact descriptor workspace", async () => {
  const acceptedPlan = `${"EMPTY.ASM\n".repeat(254)}TAIL.ASM\n`;
  const accepted = await runMultipart(acceptedPlan, [
    Buffer.from("; empty", "ascii"),
    Buffer.from("ORG $100\nRET\n", "ascii"),
  ], {
    names: ["EMPTY.ASM", "TAIL.ASM"],
    initializeMemory(memory) {
      memory[0x45fb] = 0xa5;
      memory[0x4628] = 0x5a;
    },
  });
  assert.match(accepted.atomTranscript, /MADE\.COM written/);
  assert.deepEqual(accepted.outputFile?.bytes.slice(0, 1), Uint8Array.from([0xc9]));
  assert.equal(accepted.memory[0x45fb], 0xa5);
  assert.equal(accepted.memory[0x4628], 0x5a);
  assert.equal(accepted.memory[0x4100], 0);
  assert.equal(accepted.memory[0x45f6], 254);

  const prior = Uint8Array.from([0x00, 0xc9]);
  const rejected = await runMultipart(`${"EMPTY.ASM\n".repeat(255)}TAIL.ASM\n`, [
    Buffer.from("; empty", "ascii"),
    Buffer.from("ORG $100\nRET\n", "ascii"),
  ], { names: ["EMPTY.ASM", "TAIL.ASM"], priorOutput: prior });
  assert.match(rejected.atomTranscript, /Invalid plan/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("each source-list part retains the exact 65,535-byte source boundary", async () => {
  const exact = Buffer.alloc(65_535, 0x78);
  exact[0] = 0x3b;
  const accepted = await runMultipart("BIG.ASM\nTAIL.ASM\n", [
    exact,
    Buffer.from("ORG $100\nRET\n", "ascii"),
  ], { names: ["BIG.ASM", "TAIL.ASM"] });
  assert.match(accepted.atomTranscript, /MADE\.COM written/);
  assert.deepEqual(accepted.outputFile?.bytes.slice(0, 1), Uint8Array.from([0xc9]));

  const prior = Uint8Array.from([0xc9]);
  const rejected = await runMultipart("BIG.ASM\nTAIL.ASM\n", [
    Buffer.concat([exact, Buffer.from("x")]),
    Buffer.from("ORG $100\nRET\n", "ascii"),
  ], { names: ["BIG.ASM", "TAIL.ASM"], priorOutput: prior });
  assert.match(rejected.atomTranscript, /BIG\.ASM read failed/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("a combined source-list build exceeds one complete 16-bit source part", async () => {
  const first = Buffer.alloc(33_000, 0x78);
  const second = Buffer.alloc(33_000, 0x79);
  first[0] = 0x3b;
  second[0] = 0x3b;
  const result = await runMultipart("FIRST.ASM\nSECOND.ASM\nMAIN.ASM\n", [
    first,
    second,
    representativeSource,
  ], { names: ["FIRST.ASM", "SECOND.ASM", "MAIN.ASM"] });
  const expected = await expectedRepresentativeProgram();
  assert.equal(first.length + second.length + representativeSource.length > 65_535, true);
  assert.match(result.atomTranscript, /MADE\.COM written/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.bytes.length), expected.bytes);
  assert.equal(result.atomInstructions, result.census.combinedRepresentativeInstructions);
  assert.equal(result.atomCycles, result.census.combinedRepresentativeTStates);
  assert.equal(result.commandInstructions, result.census.combinedRepresentativeCommandInstructions);
  assert.equal(result.commandCycles, result.census.combinedRepresentativeCommandTStates);
  assert.equal(0xe400 - result.atomMinimumSp, result.census.combinedRepresentativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.combinedRepresentativeBdosCalls);
  assert.equal(result.atomPlanSequentialReads, result.census.combinedRepresentativePlanReads);
  assert.equal(
    result.atomSourceSequentialReads,
    result.census.combinedRepresentativeSourceSequentialReads,
  );
  assert.equal(
    result.atomRandomReadRecords.length,
    result.census.combinedRepresentativeSourceRandomReads,
  );
  assert.ok(result.atomMinimumSp >= 0xd800);
  assert.equal(result.returnSp, (result.entrySp + 2) & 0xffff);
});

test("source-list commands reset plan, source, and publication state sequentially", async () => {
  const single = Buffer.from("ORG $100\nLD A,42\nRET\n", "ascii");
  const result = await runMultipart("P0.ASM\nP1.ASM\n", multipartParts, {
    files: [["SINGLE.ASM", single]],
  });
  assert.match(result.atomTranscript, /MADE\.COM written/);
  assert.equal(
    result.runCommand("ATOM SINGLE.ASM SINGLE.COM"),
    "ATOM SINGLE.ASM SINGLE.COM\r\r\n\r\nSINGLE.COM written\r\n\r\nA>",
  );
  assert.deepEqual(
    result.readCurrentFile("SINGLE.COM")?.bytes.slice(0, 3),
    Uint8Array.from([0x3e, 42, 0xc9]),
  );
  assert.match(result.runCommand("ATOM BUILD.LST BAD.BIN @"), /Invalid output name/);
  assert.equal(
    result.runCommand("ATOM BUILD.LST NEXT.COM @"),
    "ATOM BUILD.LST NEXT.COM @\r\r\n\r\nNEXT.COM written\r\n\r\nA>",
  );
  assert.ok(result.readCurrentFile("NEXT.COM"));
});

test("the CP/M source reader accepts 65,535 bytes and rejects the next byte", async () => {
  const exact = Buffer.alloc(65_535, 0x78);
  exact[0] = 0x3b;
  const accepted = await runCpm22Atom(exact);
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  assert.equal(accepted.atomRandomReadRecords.length, 512);
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
  assert.deepEqual(lookahead.atomRandomReadRecords, [0, 1, 2, 0, 1, 2]);
  assert.deepEqual(
    lookahead.atomSourceCacheMisses.map(({ key }) => key),
    [0, 0x80, 0x100, 0, 0x80, 0x100],
  );

  const string = await runCpm22Atom(
    Buffer.from(`ORG $100\r\nDB "${"A".repeat(200)}"\r\n`, "ascii"),
  );
  assert.deepEqual(string.outputFile?.bytes.slice(0, 200), new Uint8Array(200).fill(0x41));
  assert.deepEqual(string.atomRandomReadRecords, [0, 1, 0, 1, 0, 1]);
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
  assert.equal(result.atomSourceSequentialReads, result.census.largeRepresentativeSourceSequentialReads);
  assert.equal(result.atomRandomReadRecords.length, result.census.largeRepresentativeSourceRandomReads);
  assert.equal(result.atomRandomReadRecords.length, 130);
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
