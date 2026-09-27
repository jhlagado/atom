import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  CPM22_FILESYSTEM_DIRECTORY_ENTRIES,
  CPM22_FILESYSTEM_DIRECTORY_ENTRY_BYTES,
  CPM22_FILESYSTEM_SYSTEM_BYTES,
  readCpm22File,
} from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import {
  expectedMultipartProgram,
  expectedRepresentativeProgram,
  representativeSource,
  runCpm22Atom,
} from "./cpm22-support.mjs";
import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
  writeIntelHex,
} from "../src/host/index.mjs";
import { createAsoWriter, readAsoOperations } from "../src/host/artifacts/aso-stream.mjs";
import { createFlatImageAtomSink } from "../src/host/harness/flat-image-atom-sink.mjs";

const multipartParts = [
  Buffer.from("ORG $100\r\nJP START", "ascii"),
  Buffer.from("START:\r\nRET\r\n", "ascii"),
];
const cpmCensus = JSON.parse(await readFile(
  new URL("../proofs/cpm22-census.json", import.meta.url),
  "utf8",
));

async function expectedImageForSource(source, identity) {
  const sourceBytes = Uint8Array.from(source);
  const assembly = await assembleResolvedAtomProject({
    parts: [{
      ordinal: 0,
      bank: 0,
      originalBytes: sourceBytes,
      compilerBytes: sourceBytes,
      logicalIdentity: identity,
    }],
  }, { target: { start: 0x100, capacity: 0xff00 } });
  return materializeAtomGeneration(assembly.generation);
}

function referenceAsoFile(events) {
  const chunks = [];
  const begin = events[0];
  const writer = createAsoWriter({
    origin: begin.origin,
    fill: begin.fill,
    write: (chunk) => chunks.push(chunk.slice()),
  });
  for (const event of events.slice(1)) {
    if (event.kind === "commit") writer.commit(event);
    else writer[event.kind](event.address, event.bytes);
  }
  const logical = Buffer.concat(chunks);
  const padding = (128 - logical.length % 128) % 128;
  return Uint8Array.from(Buffer.concat([logical, Buffer.alloc(padding, 0x1a)]));
}

test("CP/M rejects an insufficient transient area before touching private arenas", async () => {
  for (const boundary of [0x8000, 0xe3ff]) {
    let bdos;
    const prior = new Uint8Array(128).fill(0xa5);
    const result = await runCpm22Atom(representativeSource, prior, {
      beforeAtomEntry(memory) {
        bdos = memory.slice(6, 8);
        memory[6] = boundary & 0xff;
        memory[7] = boundary >>> 8;
        memory.fill(0x69, 0x5000, 0xe400);
      },
      beforeBdos({ memory }) {
        memory.set(bdos, 6); // Keep real BDOS callable after the admission check.
      },
    });
    assert.equal(result.returnA, 1);
    assert.equal(result.returnSp, result.entrySp);
    assert.match(result.atomTranscript, /Insufficient transient memory/);
    assert.deepEqual(result.outputFile.bytes, prior);
    assert.deepEqual(result.memory.slice(0x5000, 0xe400), new Uint8Array(0x9400).fill(0x69));
    assert.deepEqual(result.atomBdosCalls, [9]);
  }
});

test("CP/M admits the exact boundary and warm boots with the old CCP return address destroyed", async () => {
  for (const boundary of [0xe400, 0xe401]) {
    let bdos;
    const result = await runCpm22Atom(representativeSource, undefined, {
      beforeAtomEntry(memory, registers) {
        bdos = memory.slice(6, 8);
        memory[6] = boundary & 0xff;
        memory[7] = boundary >>> 8;
        memory[registers.sp] = 0xff;
        memory[registers.sp + 1] = 0xff;
      },
      beforeBdos({ memory }) { memory.set(bdos, 6); },
    });
    assert.equal(result.returnA, 0);
    assert.equal(result.returnSp, 0xe400);
    assert.equal(result.runOutput(), "OUTPUT\r\r\nHello from native Atom\r\n\r\nA>");
  }
});

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
  assert.equal(result.returnSp, 0xe400, "Atom reached warm boot with an unbalanced private stack");
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
    22, 15, 26, 33, 26, 33, 26, 21, 16,
    22, 15, 26, 20, 26, 20, 16, 26, 21, 16,
    19, 19, 23, 23, 19, 9,
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

test("CP/M COMMIT publishes a reserved extent after backward ORG", async () => {
  const source = Buffer.from(
    "ORG $100\r\nDS $81\r\nORG $100\r\nDB $A5\r\n",
    "ascii",
  );
  const result = await runCpm22Atom(source);

  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.equal(result.outputFile?.records, 2);
  assert.equal(result.outputFile?.bytes.length, 256);
  assert.deepEqual(
    result.outputFile?.bytes.slice(0, 129),
    Uint8Array.of(0xa5, ...new Uint8Array(128)),
  );
  assert.equal(result.returnA, 0);
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

test("CP/M COM, BIN and HEX materialize the same Node image and addresses", async () => {
  const source = Buffer.from([
    "ORG 100H",
    "START: JP TARGET",
    "DS 3",
    "ORG 110H",
    "TARGET: DB 7",
    "",
  ].join("\r\n"), "ascii");
  const expected = await expectedImageForSource(source, "CROSS.ASM");
  const directSink = createFlatImageAtomSink();
  const directAssembly = await assembleResolvedAtomProject({
    parts: [{
      ordinal: 0,
      bank: 0,
      originalBytes: source,
      compilerBytes: source,
      logicalIdentity: "CROSS.ASM",
    }],
  }, { target: { start: 0x100, capacity: 0xff00 }, sink: directSink });
  const directImage = directSink.snapshot().materialized;
  const directBytes = directImage.bytes.subarray(0, directImage.end - 0x100);
  assert.equal(directAssembly.generation.highWater, directImage.end);
  assert.deepEqual(directBytes, expected.bytes, "Node flat sink differs from the generation renderer");

  for (const extension of ["COM", "BIN", "HEX"]) {
    const result = await runCpm22Atom(source, undefined, {
      sourceName: "CROSS.ASM",
      outputName: `CROSS.${extension}`,
    });
    const physical = result.outputFile?.bytes ?? new Uint8Array();
    const padding = physical.indexOf(0x1a);
    const logical = extension === "HEX"
      ? Buffer.from(physical.slice(0, padding < 0 ? physical.length : padding)).toString("ascii")
      : physical.subarray(0, expected.bytes.length);

    if (extension === "HEX") {
      assert.equal(logical, writeIntelHex({
        base: 0x100,
        end: directImage.end,
        bytes: directBytes,
      }, { lineEnding: "\r\n" }));
    } else {
      assert.deepEqual(logical, directBytes, extension);
      assert.ok(physical.length >= directBytes.length, `${extension} image was truncated`);
    }
    assert.equal(result.returnA, 0, extension);
  }
});

test("CP/M materializes large Intel HEX through bounded ASO replay windows", async () => {
  const source = Buffer.from("ORG $100\r\nDS $5000,$A5\r\n", "ascii");
  const expectedImage = await expectedImageForSource(source, "LARGE.ASM");
  const expectedHex = writeIntelHex(expectedImage, { lineEnding: "\r\n" });
  let spoolWrites = 0;
  let spoolReads = 0;
  let outputWrites = 0;
  let randomOutputOperations = 0;
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "LARGE.ASM",
    outputName: "LARGE.HEX",
    beforeBdos({ call, fcb, memory }) {
      const extension = String.fromCharCode(
        memory[fcb + 9] & 0x7f,
        memory[fcb + 10] & 0x7f,
        memory[fcb + 11] & 0x7f,
      );
      if (extension === "BAK" && call === 21) spoolWrites += 1;
      if (extension === "BAK" && call === 20) spoolReads += 1;
      if (extension === "$$$" && call === 21) outputWrites += 1;
      if (extension === "$$$" && (call === 33 || call === 34))
        randomOutputOperations += 1;
    },
  });
  const physical = result.outputFile?.bytes ?? new Uint8Array();
  const padding = physical.indexOf(0x1a);
  const text = Buffer.from(physical.slice(0, padding < 0 ? physical.length : padding)).toString("ascii");

  assert.match(result.atomTranscript, /LARGE\.HEX written/);
  assert.equal(expectedImage.bytes.length, 0x5000);
  assert.equal(text, expectedHex);
  assert.ok(spoolWrites > 0, "HEX assembly did not spool ordered operations");
  assert.ok(spoolReads >= 3, "HEX materialization did not replay across windows");
  assert.ok(outputWrites > 1, "HEX output did not flush sequential records");
  assert.equal(randomOutputOperations, 0);
  assert.equal(result.returnA, 0);
});

test("CP/M HEX handles empty, one-byte, exact-window, and short-tail images", async () => {
  const lengths = [0, 1, cpmCensus.materializerWindowBytes, cpmCensus.materializerWindowBytes + 1];
  for (const length of lengths) {
    const source = Buffer.from(
      length === 0 ? "ORG $100\r\n" : `ORG $100\r\nDS ${length},$A5\r\n`,
      "ascii",
    );
    const expected = await expectedImageForSource(source, "BOUNDARY.ASM");
    const result = await runCpm22Atom(source, undefined, {
      sourceName: "BOUNDARY.ASM",
      outputName: "BOUNDARY.HEX",
    });
    const physical = result.outputFile?.bytes ?? new Uint8Array();
    const padding = physical.indexOf(0x1a);
    const text = Buffer.from(physical.slice(0, padding < 0 ? physical.length : padding)).toString("ascii");
    assert.equal(expected.bytes.length, length);
    assert.equal(text, writeIntelHex(expected, { lineEnding: "\r\n" }), `length ${length}`);
    assert.equal(result.returnA, 0, `length ${length}`);
  }
});

test("CP/M writes canonical ASO with a forward patch beyond the former image window", async () => {
  const laterImage = new Uint8Array(128).fill(0x5a);
  const source = Buffer.from(
    `ORG $100\r\nJP DEST\r\nDS $5000\r\nDB ${Array.from(laterImage, () => "$5A").join(",")}\r\nDEST:\r\nRET\r\n`,
    "ascii",
  );
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "LARGE.ASM",
    outputName: "LARGE.ASO",
  });
  const expectedEvents = [
    { kind: "begin", origin: 0x100, fill: 0 },
    { kind: "image", address: 0x100, bytes: Uint8Array.of(0xc3, 0, 0) },
    { kind: "image", address: 0x5103, bytes: laterImage },
    { kind: "patch", address: 0x101, bytes: Uint8Array.of(0x83, 0x51) },
    { kind: "image", address: 0x5183, bytes: Uint8Array.of(0xc9) },
    { kind: "commit", highWater: 0x5184, finalCursor: 0x5184 },
  ];

  assert.match(result.atomTranscript, /LARGE\.ASO written/);
  assert.equal(result.returnA, 0);
  assert.ok(expectedEvents.at(-1).highWater - 0x100 > 0x4780);
  assert.equal(result.outputFile?.records, 2);
  assert.deepEqual([...readAsoOperations([result.outputFile.bytes])], expectedEvents);
  assert.deepEqual(result.outputFile?.bytes, referenceAsoFile(expectedEvents));
});

test("CP/M automatically materializes a COM larger than the old RAM window", async () => {
  const imageLength = 0x5000;
  const source = Buffer.from(`ORG $100\r\nDS $${imageLength.toString(16)}\r\n`, "ascii");
  const fileCalls = new Map();
  const result = await runCpm22Atom(source, Uint8Array.of(0xc9), {
    sourceName: "LARGE.ASM",
    outputName: "LARGE.COM",
    beforeBdos({ call, fcb, memory }) {
      if (![20, 21, 33, 34].includes(call)) return;
      const extension = String.fromCharCode(
        memory[fcb + 9] & 0x7f,
        memory[fcb + 10] & 0x7f,
        memory[fcb + 11] & 0x7f,
      );
      const key = `${call}:${extension}`;
      fileCalls.set(key, (fileCalls.get(key) ?? 0) + 1);
    },
  });

  assert.match(result.atomTranscript, /LARGE\.COM written/);
  assert.equal(result.returnA, 0);
  assert.equal(result.outputFile?.bytes.length, imageLength);
  assert.deepEqual(result.outputFile?.bytes, new Uint8Array(imageLength));
  assert.equal(readCpm22File(result.finalDisk, "LARGE.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "LARGE.BAK"), undefined);
  const outputRecords = Math.ceil(imageLength / 128);
  const passes = Math.ceil(outputRecords / (result.census.materializerWindowBytes / 128));
  const spoolWrites = fileCalls.get("21:BAK");
  assert.ok(spoolWrites > 0);
  assert.equal(fileCalls.get("20:BAK"), (spoolWrites + 1) * passes);
  assert.equal(fileCalls.get("21:$$$"), outputRecords);
  assert.equal(fileCalls.get("34:$$$"), undefined);
  assert.equal(result.atomBdosCalls.includes(34), false);
});

test("CP/M materializes a large BIN and applies a PATCH across replay windows", async () => {
  const windowBytes = cpmCensus.materializerWindowBytes;
  const patchAddress = 0x100 + windowBytes - 1;
  const targetAddress = patchAddress + 2;
  const source = Buffer.from([
    "ORG $100",
    "DB 0",
    `ORG $${patchAddress.toString(16)}`,
    "DW DEST",
    "DEST:",
    "DB $A5",
    "",
  ].join("\r\n"), "ascii");
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "WINDOW.ASM",
    outputName: "WINDOW.BIN",
  });

  assert.match(result.atomTranscript, /WINDOW\.BIN written/);
  assert.equal(result.returnA, 0);
  assert.equal(result.outputFile?.bytes.length, windowBytes + 128);
  assert.equal(result.outputFile?.bytes[0], 0);
  assert.deepEqual(
    result.outputFile?.bytes.slice(windowBytes - 1, windowBytes + 2),
    Uint8Array.of(targetAddress & 0xff, targetAddress >>> 8, 0xa5),
  );
  assert.equal(result.atomBdosCalls.includes(34), false);
});

test("the CP/M reader applies a PATCH whose payload crosses an ASO record boundary", async () => {
  const prefix = new Uint8Array(110).fill(0xaa);
  const source = Buffer.from([
    "ORG $100",
    `DB ${Array.from(prefix, (byte) => `$${byte.toString(16)}`).join(",")}`,
    "DW TARGET",
    "ORG $200",
    "TARGET: DB $C9",
    "",
  ].join("\r\n"), "ascii");
  const spoolRecords = [];
  const result = await runCpm22Atom(source, undefined, {
    outputName: "PATCH.BIN",
    beforeBdos({ call, fcb, memory }) {
      if (call !== 21) return;
      const extension = String.fromCharCode(
        memory[fcb + 9] & 0x7f,
        memory[fcb + 10] & 0x7f,
        memory[fcb + 11] & 0x7f,
      );
      if (extension === "BAK") {
        const recordAddress = cpmCensus.asoRecordAddress;
        spoolRecords.push(memory.slice(recordAddress, recordAddress + 128));
      }
    },
  });

  assert.match(result.atomTranscript, /PATCH\.BIN written/);
  assert.equal(result.returnA, 0);
  const spool = Buffer.concat(spoolRecords.map((record) => Buffer.from(record)));
  let cursor = 7;
  let patchDataOffset;
  while (cursor < spool.length) {
    const kind = spool[cursor];
    if (kind === 0) break;
    const length = spool[cursor + 3];
    if (kind === 2) patchDataOffset = cursor + 4;
    cursor += 4 + length;
  }
  assert.equal(patchDataOffset, 127);
  assert.equal(patchDataOffset % 128, 127);
  const events = [...readAsoOperations([spool])];
  assert.deepEqual(events.find((event) => event.kind === "patch"), {
    kind: "patch", address: 0x16e, bytes: Uint8Array.of(0x00, 0x02),
  });
  assert.equal(result.outputFile?.bytes.length, 384);
  assert.deepEqual(result.outputFile?.bytes.slice(0, 112),
    Uint8Array.from([...prefix, 0x00, 0x02]));
  assert.equal(result.outputFile?.bytes[255], 0);
  assert.equal(result.outputFile?.bytes[256], 0xc9);
});

test("CP/M rejects an IMAGE endpoint beyond ASO high water", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let corrupted = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB $AA\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        if (corrupted || call !== 21) return;
        if (String.fromCharCode(memory[fcb + 9], memory[fcb + 10], memory[fcb + 11]) !== "BAK") return;
        memory[cpmCensus.asoRecordAddress + 8] = 0x10;
        corrupted = true;
      },
    },
  );

  assert.equal(corrupted, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("CP/M validates an empty ASO stream before publishing an empty image", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let corrupted = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        if (corrupted || call !== 21) return;
        if (String.fromCharCode(memory[fcb + 9], memory[fcb + 10], memory[fcb + 11]) !== "BAK") return;
        memory[cpmCensus.asoRecordAddress] ^= 1;
        corrupted = true;
      },
    },
  );

  assert.equal(corrupted, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("CP/M rejects malformed ASO versions, records, geometry, padding, and EOF", async () => {
  const header = [0x41, 0x53, 0x4f, 1, 0, 1, 0];
  const image = [1, 0, 1, 1, 0xaa];
  const end = [0, 1, 1, 0, 1, 1, 0];
  const endAt181 = [0, 0x81, 0x01, 0, 0x81, 0x01, 0];
  const endAt103 = [0, 3, 1, 0, 3, 1, 0];
  const endAt1c8 = [0, 0xc8, 1, 0, 0xc8, 1, 0];
  const valid = [...header, ...image, ...end];
  const adjacentImageEnd = [0, 2, 1, 0, 2, 1, 0];
  const beyondEndpoint = [0, 1, 1, 1, 1, 1, 0];
  const repeatedPatch = [2, 0, 1, 1, 0xbb];
  const extraRecordStream = [
    ...header,
    ...image,
    ...Array.from({ length: 21 }, () => repeatedPatch).flat(),
    ...endAt1c8,
  ];
  const afterEnd = new Uint8Array(129).fill(0x1a);
  afterEnd.set(extraRecordStream);
  afterEnd[128] = 0;
  const vectors = [
    { name: "version", bytes: [0x41, 0x53, 0x4f, 2, 0, 1, 0, ...image, ...end] },
    { name: "kind", bytes: [...header, 3, ...end] },
    { name: "zero IMAGE", bytes: [...header, 1, 0, 1, 0, ...end] },
    {
      name: "oversized IMAGE with all payload bytes present",
      bytes: [...header, 1, 0, 1, 129, ...new Array(129).fill(0xaa), ...endAt181],
      sourceBytes: Buffer.from(`ORG $100\r\nDB ${new Array(129).fill("$AA").join(",")}\r\n`, "ascii"),
      recordCount: 2,
    },
    { name: "IMAGE below origin", bytes: [...header, 1, 0xff, 0, 1, 0xaa, ...end] },
    { name: "overlapping IMAGE", bytes: [...header, ...image, ...image, ...end] },
    {
      name: "non-canonical adjacent IMAGE",
      bytes: [...header, ...image, 1, 1, 1, 1, 0xbb, ...adjacentImageEnd],
      sourceBytes: Buffer.from("ORG $100\r\nDB $AA,$BB\r\n", "ascii"),
    },
    { name: "PATCH before IMAGE", bytes: [...header, 2, 0, 1, 1, 0xbb, ...image, ...end] },
    {
      name: "PATCH length above two",
      bytes: [...header, 1, 0, 1, 3, 0xaa, 0xaa, 0xaa, 2, 0, 1, 3, 0, 0, 0, ...endAt103],
      sourceBytes: Buffer.from("ORG $100\r\nDB $AA,$AA,$AA\r\n", "ascii"),
    },
    { name: "high-water above $10000", bytes: [...header, ...image, ...beyondEndpoint] },
    { name: "final cursor above high-water", bytes: [...header, ...image, 0, 1, 1, 0, 2, 1, 0] },
    { name: "IMAGE end above committed high-water", bytes: [...header, 1, 1, 1, 1, 0xaa, ...end] },
    { name: "non-padding byte after END", bytes: [...valid, 0] },
    {
      name: "non-EOF second physical record after END",
      bytes: afterEnd,
      sourceBytes: Buffer.from(`ORG $100\r\nDB ${new Array(200).fill("$AA").join(",")}\r\n`, "ascii"),
      recordCount: 2,
    },
  ];
  const prior = Uint8Array.of(0xc9, 0x76);
  const priorRecord = new Uint8Array(128).fill(0x1a);
  priorRecord.set(prior);

  for (const vector of vectors) {
    let spoolRecords = 0;
    const result = await runCpm22Atom(
      vector.sourceBytes ?? Buffer.from("ORG $100\r\nDB $AA\r\n", "ascii"),
      prior,
      {
        beforeBdos({ call, fcb, memory }) {
          if (call !== 21) return;
          const extension = String.fromCharCode(
            memory[fcb + 9] & 0x7f,
            memory[fcb + 10] & 0x7f,
            memory[fcb + 11] & 0x7f,
          );
          if (extension !== "BAK") return;
          const recordAddress = cpmCensus.asoRecordAddress;
          const vectorOffset = spoolRecords * 128;
          memory.fill(0x1a, recordAddress, recordAddress + 128);
          memory.set(vector.bytes.slice(vectorOffset, vectorOffset + 128), recordAddress);
          spoolRecords += 1;
        },
      },
    );

    assert.equal(spoolRecords, vector.recordCount ?? 1, vector.name);
    assert.equal(result.returnA, 1, vector.name);
    assert.deepEqual(result.outputFile?.bytes, priorRecord, vector.name);
    assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined, vector.name);
    assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined, vector.name);
  }
});

test("a malformed internal ASO spool never replaces an existing COM", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let corrupted = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB $3E,$2A,$C9\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        if (corrupted || call !== 21) return;
        if (String.fromCharCode(memory[fcb + 9], memory[fcb + 10], memory[fcb + 11]) !== "BAK") return;
        memory[cpmCensus.asoRecordAddress] ^= 1;
        corrupted = true;
      },
    },
  );

  assert.equal(corrupted, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a malformed internal ASO spool never replaces an existing HEX file", async () => {
  const prior = Uint8Array.of(0x3a, 0x30, 0x30, 0x30, 0x30);
  let corrupted = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB $3E,$2A,$C9\r\n", "ascii"),
    prior,
    {
      outputName: "OUTPUT.HEX",
      beforeBdos({ call, fcb, memory }) {
        if (corrupted || call !== 21) return;
        if (String.fromCharCode(memory[fcb + 9], memory[fcb + 10], memory[fcb + 11]) !== "BAK") return;
        memory[cpmCensus.asoRecordAddress] ^= 1;
        corrupted = true;
      },
    },
  );

  assert.equal(corrupted, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a failed internal spool read preserves the existing COM and removes both temps", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedReadFailure = false;
  let restoredBdosEntry = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,0\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        const extension = String.fromCharCode(
          memory[fcb + 9] & 0x7f,
          memory[fcb + 10] & 0x7f,
          memory[fcb + 11] & 0x7f,
        );
        if (call === 20 && extension === "BAK" && !injectedReadFailure) {
          originalBdosEntry = memory.slice(5, 8);
          memory.set([0x3e, 0x01, 0xc9], 5); // Return a sequential-read failure.
          injectedReadFailure = true;
        } else if (injectedReadFailure && !restoredBdosEntry) {
          memory.set(originalBdosEntry, 5);
          restoredBdosEntry = true;
        }
      },
    },
  );

  assert.equal(injectedReadFailure, true);
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a failed materialized-output write preserves the old COM and removes the spool", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedWriteFailure = false;
  let restoredBdosEntry = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,0\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        const extension = String.fromCharCode(
          memory[fcb + 9] & 0x7f,
          memory[fcb + 10] & 0x7f,
          memory[fcb + 11] & 0x7f,
        );
        if (call === 21 && extension === "$$$" && !injectedWriteFailure) {
          originalBdosEntry = memory.slice(5, 8);
          memory.set([0x3e, 0x01, 0xc9], 5); // Fail the first output-temp record.
          injectedWriteFailure = true;
        } else if (injectedWriteFailure && !restoredBdosEntry) {
          memory.set(originalBdosEntry, 5);
          restoredBdosEntry = true;
        }
      },
    },
  );

  assert.equal(injectedWriteFailure, true);
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a failed materialized-output close preserves the old COM and removes both temps", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedCloseFailure = false;
  let restoredBdosEntry = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,0\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        const extension = String.fromCharCode(
          memory[fcb + 9] & 0x7f,
          memory[fcb + 10] & 0x7f,
          memory[fcb + 11] & 0x7f,
        );
        if (call === 16 && extension === "$$$" && !injectedCloseFailure) {
          originalBdosEntry = memory.slice(5, 8);
          memory.set([0x3e, 0xff, 0xc9], 5);
          injectedCloseFailure = true;
        } else if (injectedCloseFailure && !restoredBdosEntry) {
          memory.set(originalBdosEntry, 5);
          restoredBdosEntry = true;
        }
      },
    },
  );

  assert.equal(injectedCloseFailure, true);
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a failed output rename restores the prior COM and removes the materialized temp", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedRenameFailure = false;
  let restoredBdosEntry = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,0\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        const targetName = String.fromCharCode(
          ...memory.slice(fcb + 17, fcb + 28).map((byte) => byte & 0x7f),
        );
        if (call === 23 && targetName === "OUTPUT  COM" && !injectedRenameFailure) {
          originalBdosEntry = memory.slice(5, 8);
          memory.set([0x3e, 0xff, 0xc9], 5);
          injectedRenameFailure = true;
        } else if (injectedRenameFailure && !restoredBdosEntry) {
          memory.set(originalBdosEntry, 5);
          restoredBdosEntry = true;
        }
      },
    },
  );

  assert.equal(injectedRenameFailure, true);
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("CP/M pads an ASO stream with exactly one complete final record", async () => {
  const bytes = Uint8Array.from({ length: 110 }, (_, index) => index);
  const source = Buffer.from(
    `ORG $100\r\nDB ${Array.from(bytes, (byte) => `$${byte.toString(16)}`).join(",")}\r\n`,
    "ascii",
  );
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "BOUNDARY.ASM",
    outputName: "BOUNDARY.ASO",
  });
  const events = [
    { kind: "begin", origin: 0x100, fill: 0 },
    { kind: "image", address: 0x100, bytes },
    { kind: "commit", highWater: 0x16e, finalCursor: 0x16e },
  ];

  assert.match(result.atomTranscript, /BOUNDARY\.ASO written/);
  assert.equal(result.outputFile?.records, 1);
  assert.equal(readAsoOperations([result.outputFile.bytes]).next().value.kind, "begin");
  assert.deepEqual([...readAsoOperations([result.outputFile.bytes])], events);
  assert.deepEqual(result.outputFile?.bytes, referenceAsoFile(events));
});

test("failed CP/M ASO assembly preserves the old file and removes its written spool", async () => {
  const prior = Uint8Array.of(0x41, 0x53, 0x4f, 0x01, 0x55);
  const lines = ["ORG $100", ...Array(260).fill("DB $5A"), "NOT_AN_INSTRUCTION"];
  const result = await runCpm22Atom(Buffer.from(`${lines.join("\r\n")}\r\n`, "ascii"), prior, {
    sourceName: "BROKEN.ASM",
    outputName: "BROKEN.ASO",
  });

  assert.match(result.atomTranscript, /Atom error 02 BROKEN\.ASM:262:1/);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "BROKEN.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "BROKEN.BAK"), undefined);
});

test("an internal spool ownership flag survives reuse of its assembly run buffer", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB 0\r\nNOT_AN_INSTRUCTION\r\n", "ascii"),
    prior,
  );

  assert.match(result.atomTranscript, /Atom error 02 INPUT\.ASM:3:1/);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});

test("a failed full ASO IMAGE flush stops before the next byte can overrun its run buffer", async () => {
  const prior = Uint8Array.of(0x41, 0x53, 0x4f, 0x01, 0x55);
  const lines = ["ORG $100", ...Array(129).fill("DB $5A"), "NOT_AN_INSTRUCTION"];
  let originalBdosEntry;
  let injectedWriteFailure = false;
  let restoredBdosEntry = false;
  const result = await runCpm22Atom(Buffer.from(`${lines.join("\r\n")}\r\n`, "ascii"), prior, {
    sourceName: "BROKEN.ASM",
    outputName: "BROKEN.ASO",
    beforeBdos({ call, memory }) {
      if (call === 21 && !injectedWriteFailure) {
        originalBdosEntry = memory.slice(5, 8);
        memory.set([0x3e, 0x01, 0xc9], 5); // Return a write error from BDOS.
        injectedWriteFailure = true;
      } else if (injectedWriteFailure && !restoredBdosEntry) {
        memory.set(originalBdosEntry, 5);
        restoredBdosEntry = true;
      }
    },
  });

  assert.equal(injectedWriteFailure, true);
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.doesNotMatch(result.atomTranscript, /Atom error 02 BROKEN\.ASM:131:1/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "BROKEN.$$$"), undefined);
  assert.deepEqual(
    result.memory.slice(result.census.asoRecordAddress, result.census.asoRecordAddress + 8),
    Uint8Array.of(0x41, 0x53, 0x4f, 0x01, 0x00, 0x01, 0x00, 0x01),
  );
});

test("CP/M ASO preserves the $10000 endpoint and a backward final cursor", async () => {
  const endpoint = await runCpm22Atom(
    Buffer.from("ORG $FFFE\r\nDB $AA,$BB\r\n", "ascii"),
    undefined,
    { sourceName: "EDGE.ASM", outputName: "EDGE.ASO" },
  );
  const endpointEvents = [
    { kind: "begin", origin: 0x100, fill: 0 },
    { kind: "image", address: 0xfffe, bytes: Uint8Array.of(0xaa, 0xbb) },
    { kind: "commit", highWater: 0x10000, finalCursor: 0x10000 },
  ];
  assert.match(endpoint.atomTranscript, /EDGE\.ASO written/);
  assert.deepEqual([...readAsoOperations([endpoint.outputFile.bytes])], endpointEvents);
  assert.deepEqual(endpoint.outputFile?.bytes, referenceAsoFile(endpointEvents));

  const backward = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDB $11\r\nDS $1000\r\nORG $110\r\nDB $22\r\n", "ascii"),
    undefined,
    { sourceName: "BACK.ASM", outputName: "BACK.ASO" },
  );
  const backwardEvents = [...readAsoOperations([backward.outputFile.bytes])];
  assert.deepEqual(backwardEvents.at(-1), {
    kind: "commit", highWater: 0x1101, finalCursor: 0x111,
  });
  assert.deepEqual(backward.outputFile?.bytes, referenceAsoFile(backwardEvents));
});

test("a rejected assembly preserves an earlier OUTPUT.COM and removes its temp", async () => {
  const prior = Uint8Array.from([0xc9]);
  const result = await runCpm22Atom(Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"), prior);
  assert.match(result.atomTranscript, /Atom error 02 INPUT\.ASM:2:1/);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(
    (await import("@jhlagado/debug80-runtime/platforms/cpm22/filesystem"))
      .readCpm22File(result.finalDisk, "OUTPUT.$$$"),
    undefined,
  );
});

test("CP/M diagnostics use the source filename and one-based byte column", async () => {
  const source = Buffer.from("; header\r\nORG $100\n  NOT_AN_INSTRUCTION\r", "ascii");
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "MIXED.ASM",
    outputName: "MIXED.COM",
  });
  assert.match(result.atomTranscript, /Atom error 02 MIXED\.ASM:3:3/);
  assert.equal(result.outputFile, undefined);
});

test("CP/M diagnostics identify the failing included file, not its importer", async () => {
  const result = await runMultipart([
    Buffer.from("ORG $100\r\nDB 1\r\n", "ascii"),
    Buffer.from("ORG $100\r\n  NOT_AN_INSTRUCTION\r\n", "ascii"),
  ]);
  assert.match(result.atomTranscript, /Atom error 02 P1\.ASM:2:3/);
  assert.equal(result.outputFile, undefined);
});

test("CP/M diagnostics retain undefined-symbol status and decimal positions", async () => {
  const undefinedSymbol = await runCpm22Atom(
    Buffer.from("ORG $100\r\nJP MISSING\r\n", "ascii"),
  );
  assert.match(undefinedSymbol.atomTranscript, /Atom error 03 INPUT\.ASM:2:4/);

  const manyLines = await runCpm22Atom(
    Buffer.from(`${"\n".repeat(123)}NOT_AN_INSTRUCTION\n`, "ascii"),
  );
  assert.match(manyLines.atomTranscript, /Atom error 02 INPUT\.ASM:124:1/);

  const wideLine = await runCpm22Atom(
    Buffer.from(`ORG $100\r\n${" ".repeat(130)}NOT_AN_INSTRUCTION\r\n`, "ascii"),
  );
  assert.match(wideLine.atomTranscript, /Atom error 02 INPUT\.ASM:2:131/);
});

test("CP/M diagnostics ignore filename attribute bits", async () => {
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"),
    undefined,
    {
      prepareDiskImage(image) {
        const marked = image.slice();
        for (let index = 0; index < CPM22_FILESYSTEM_DIRECTORY_ENTRIES; index += 1) {
          const entry = CPM22_FILESYSTEM_SYSTEM_BYTES + index * CPM22_FILESYSTEM_DIRECTORY_ENTRY_BYTES;
          if (marked[entry] !== 0) continue;
          const name = String.fromCharCode(...marked.slice(entry + 1, entry + 12)).trimEnd();
          if (name !== "INPUT   ASM") continue;
          marked[entry + 9] |= 0x80;
          return marked;
        }
        assert.fail("INPUT.ASM directory entry not found");
      },
    },
  );
  assert.match(result.atomTranscript, /Atom error 02 INPUT\.ASM:2:1/);
});

test("CP/M diagnostics retain the raw offset when the source cannot be reopened", async () => {
  let changed = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nNOT_AN_INSTRUCTION\r\n", "ascii"),
    undefined,
    {
      beforeBdos({ call, fcb, memory, output }) {
        if (changed || call !== 15 || !output.includes("Atom error 02 ")) return;
        memory[fcb + 1] = "Z".charCodeAt(0);
        changed = true;
      },
    },
  );
  assert.equal(changed, true);
  assert.match(result.atomTranscript, /Atom error 02 ZNPUT\.ASM:byte 000A/);
  assert.equal(result.returnA, 1);
  assert.equal(result.returnSp, 0xe400);
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

test("one native source argument with or without ASM derives a COM output", async () => {
  for (const command of ["ATOM HELLO.ASM", "ATOM HELLO"]) {
    const result = await runCpm22Atom(representativeSource, undefined, {
      sourceName: "HELLO.ASM",
      outputName: "HELLO.COM",
      command,
    });
    assert.match(result.atomTranscript, /HELLO\.COM written/);
    assert.ok(result.outputFile);
    assert.equal(result.returnA, 0);
  }
});

test("native question-mark help returns success without assembling", async () => {
  const result = await runCpm22Atom(representativeSource, undefined, { command: "ATOM ?" });
  assert.match(result.atomTranscript, /Usage: ATOM \[SOURCE \[OUTPUT\]\]/);
  assert.equal(result.outputFile, undefined);
  assert.equal(result.returnA, 0);
});

test("bare and question-mark help clear carry left set by BDOS output", async () => {
  for (const command of ["ATOM", "ATOM ?"]) {
    let originalBdos;
    let injected = false;
    let restored = false;
    const result = await runCpm22Atom(representativeSource, undefined, {
      command,
      installSource: false,
      beforeBdos({ call, memory }) {
        if (call === 9 && !injected) {
          originalBdos = memory.slice(5, 8);
          memory.set([0x37, 0xc9, 0x00], 5); // Return carry set from console output.
          injected = true;
        }
      },
      afterAtomReturn(memory) {
        if (injected) {
          memory.set(originalBdos, 5);
          restored = true;
        }
      },
    });

    assert.equal(injected, true);
    assert.equal(restored, true);
    assert.deepEqual(result.atomBdosCalls, [9]);
    assert.equal(result.outputFile, undefined);
    assert.equal(result.returnA, 0);
  }
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

test("bare Atom and a blank command tail show successful help without file I/O", async () => {
  for (const command of ["ATOM", "ATOM     "]) {
    const result = await runCpm22Atom(representativeSource, undefined, {
      command,
      installSource: false,
    });
    assert.match(result.atomTranscript, /Usage: ATOM \[SOURCE \[OUTPUT\]\]/);
    assert.equal(result.outputFile, undefined);
    assert.equal(result.returnA, 0);
    assert.deepEqual(result.atomBdosCalls, [9]);
  }
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
  assert.match(result.atomTranscript, /Atom error 02 BROKEN\.ASM:2:1/);
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
  assert.match(result.atomTranscript, /Atom error 02 INPUT\.ASM:2:1/);
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

test("the CP/M target accepts the full $FF00-byte COM and rejects its next byte", async () => {
  const exact = Buffer.from("ORG $100\r\nDS $FF00,0\r\n", "ascii");
  const fileCalls = new Map();
  const accepted = await runCpm22Atom(exact, undefined, {
    freshDisk: true,
    beforeBdos({ call, fcb, memory }) {
      if (![20, 21, 33, 34].includes(call)) return;
      const extension = String.fromCharCode(
        memory[fcb + 9] & 0x7f,
        memory[fcb + 10] & 0x7f,
        memory[fcb + 11] & 0x7f,
      );
      const key = `${call}:${extension}`;
      fileCalls.set(key, (fileCalls.get(key) ?? 0) + 1);
    },
  });
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
  assert.ok(accepted.outputFile);
  assert.equal(accepted.outputFile.records, 510);
  assert.equal(accepted.outputFile.bytes.length, 0xff00);
  assert.equal(accepted.atomInstructions, accepted.census.measuredFullTargetInstructions);
  assert.equal(accepted.atomCycles, accepted.census.measuredFullTargetTStates);
  assert.equal(
    0xe400 - accepted.atomMinimumSp,
    accepted.census.measuredFullTargetStackHighWaterBytes,
  );
  assert.equal(fileCalls.get("21:BAK"), accepted.census.measuredFullTargetAsoSpoolRecordsWritten);
  assert.equal(fileCalls.get("20:BAK"), accepted.census.measuredFullTargetAsoReadCallsIncludingEof);
  assert.equal(fileCalls.get("21:$$$"), accepted.census.measuredFullTargetSequentialOutputWrites);
  assert.equal(fileCalls.get("33:$$$"), undefined);
  assert.equal(fileCalls.get("34:$$$"), undefined);
  assert.equal(accepted.atomBdosCalls.includes(34), false);
  const prior = Uint8Array.from([0xc9]);
  const rejected = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $FF01,0\r\n", "ascii"),
    prior,
  );
  assert.match(rejected.atomTranscript, /Atom error 02 INPUT\.ASM:2:1/);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("disk full during large COM materialization preserves the prior destination", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  const source = Buffer.from("ORG $100\r\nDS $FF00,0\r\n", "ascii");
  const result = await runCpm22Atom(source, prior);

  assert.match(result.atomTranscript, /Atom error 04 INPUT\.ASM:2:1/);
  assert.equal(result.returnA, 1);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.BAK"), undefined);
});
