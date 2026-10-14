import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import {
  readCpm22File,
} from "@jhlagado/debug80-runtime/platforms/cpm22/filesystem";
import {
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
        memory.fill(0x69, cpmCensus.workspaceStartAddress, 0xe400);
      },
      beforeBdos({ memory }) {
        memory.set(bdos, 6); // Keep real BDOS callable after the admission check.
      },
    });
    assert.equal(result.returnA, 1);
    assert.equal(result.returnSp, result.entrySp);
    assert.match(result.atomTranscript, /Insufficient transient memory/);
    assert.deepEqual(result.outputFile.bytes, prior);
    assert.deepEqual(
      result.memory.slice(cpmCensus.workspaceStartAddress, 0xe400),
      new Uint8Array(0xe400 - cpmCensus.workspaceStartAddress).fill(0x69),
    );
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
  assert.ok(result.atomMinimumSp >= result.census.stackFloorAddress, "Atom crossed its stack floor");
  assert.equal(result.returnSp, 0xe400, "Atom reached warm boot with an unbalanced private stack");
  assert.equal(result.returnA, 0);
  assert.equal(result.runOutput(), "OUTPUT\r\r\nHello from native Atom\r\n\r\nA>");
});

test("CP/M runtime arenas and the output window work without COM initialisation", async () => {
  assert.equal(cpmCensus.loadedImageEnd, cpmCensus.residentBytes + 0x100);
  assert.ok(cpmCensus.loadedImageEnd <= cpmCensus.workspaceStartAddress);
  assert.equal(cpmCensus.loadedRecordBytes, Math.ceil(cpmCensus.residentBytes / 128) * 128);
  assert.equal(cpmCensus.loadedRecordPaddingBytes, cpmCensus.loadedRecordBytes - cpmCensus.residentBytes);
  assert.ok(0x100 + cpmCensus.loadedRecordBytes <= cpmCensus.workspaceStartAddress);
  assert.ok(cpmCensus.materializerScratchEnd <= cpmCensus.materializerWindowStart);
  assert.notEqual(cpmCensus.hexDmaAddress, cpmCensus.materializerRecordAddress);
  assert.ok(cpmCensus.hexDmaAddress + 128 <= cpmCensus.materializerWindowStart);
  assert.equal(cpmCensus.materializerFcbAddress, cpmCensus.partOrderAddress);
  assert.equal(cpmCensus.hexDmaAddress, cpmCensus.sourceCacheAddress);
  assert.equal(cpmCensus.materializerWindowStart, cpmCensus.sourceCacheAddress + 128);

  const expected = await expectedRepresentativeProgram();
  const result = await runCpm22Atom(representativeSource, undefined, {
    beforeAtomEntry(memory) {
      memory.fill(
        0xa5,
        cpmCensus.loadedImageEnd,
        cpmCensus.materializerWindowStart + cpmCensus.materializerWindowBytes,
      );
    },
  });

  assert.equal(result.returnA, 0);
  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(
    result.outputFile?.bytes.slice(0, expected.bytes.length),
    expected.bytes,
  );
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
      if (extension === "$$B" && call === 21) spoolWrites += 1;
      if (extension === "$$B" && call === 20) spoolReads += 1;
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

test("CP/M writes canonical ASO with a distant forward patch", async () => {
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
          if (extension !== "$$B") return;
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
    assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined, vector.name);
  }
});

test("a failed internal spool read preserves the existing COM and removes both temps", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedReadFailure = false;
  let restoredBdosEntry = false;
  let readerClosedAfterFailure = false;
  let replayWindowWasPrepared = false;
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,0\r\n", "ascii"),
    prior,
    {
      beforeAtomEntry(memory) {
        memory.fill(
          0xa5,
          cpmCensus.materializerWindowStart,
          cpmCensus.materializerWindowStart + cpmCensus.materializerWindowBytes,
        );
      },
      beforeBdos({ call, fcb, memory }) {
        let injectedThisCall = false;
        const extension = String.fromCharCode(
          memory[fcb + 9] & 0x7f,
          memory[fcb + 10] & 0x7f,
          memory[fcb + 11] & 0x7f,
        );
        if (call === 20 && extension === "$$B" && !injectedReadFailure) {
          replayWindowWasPrepared =
            memory[cpmCensus.materializerWindowStart] === 0 &&
            memory[cpmCensus.materializerWindowStart + 0x5000 - 1] === 0;
          originalBdosEntry = memory.slice(5, 8);
          memory.set([0x3e, 0x01, 0xc9], 5); // Return a sequential-read failure.
          injectedReadFailure = true;
          injectedThisCall = true;
        }
        if (
          injectedReadFailure && call === 16 &&
          fcb === cpmCensus.materializerFcbAddress
        ) {
          readerClosedAfterFailure = true;
        }
        if (injectedReadFailure && !restoredBdosEntry && !injectedThisCall) {
          memory.set(originalBdosEntry, 5);
          restoredBdosEntry = true;
        }
      },
    },
  );

  assert.equal(injectedReadFailure, true);
  assert.equal(readerClosedAfterFailure, true, "hsAbort must close the replay reader FCB");
  assert.equal(replayWindowWasPrepared, true, "ASO replay must start only after the output window is initialized");
  assert.equal(restoredBdosEntry, true);
  assert.equal(result.returnA, 1);
  assert.equal(result.returnSp, 0xe400);
  assert.match(result.atomTranscript, /OUTPUT\.COM: could not write the output/);
  assert.doesNotMatch(result.atomTranscript, /INPUT\.ASM:\d/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined);
});

test("a failed materialized-output write preserves the old COM and removes the spool", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  let originalBdosEntry;
  let injectedWriteFailure = false;
  let restoredBdosEntry = false;
  const closedFcbAddresses = [];
  const result = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $5000,$41\r\n", "ascii"),
    prior,
    {
      beforeBdos({ call, fcb, memory }) {
        if (call === 16) closedFcbAddresses.push(fcb);
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
  assert.equal(result.returnSp, 0xe400);
  assert.ok(
    !closedFcbAddresses.includes(cpmCensus.binaryIncludeFcbAddress),
    "replay data must not turn the reclaimed binary FCB into a live handle",
  );
  assert.match(result.atomTranscript, /OUTPUT\.COM: could not write the output/);
  assert.doesNotMatch(result.atomTranscript, /binary read failed/);
  assert.doesNotMatch(result.atomTranscript, /INPUT\.ASM:\d/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined);
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
  assert.equal(result.returnSp, 0xe400);
  assert.match(result.atomTranscript, /OUTPUT\.COM: could not write the output/);
  assert.doesNotMatch(result.atomTranscript, /INPUT\.ASM:\d/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined);
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
  assert.equal(result.returnSp, 0xe400);
  assert.match(result.atomTranscript, /OUTPUT\.COM: could not write the output/);
  assert.doesNotMatch(result.atomTranscript, /INPUT\.ASM:\d/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined);
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
  assert.doesNotMatch(result.atomTranscript, /BROKEN\.ASM:131:1: /);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "BROKEN.$$$"), undefined);
  assert.deepEqual(
    result.memory.slice(result.census.asoRecordAddress, result.census.asoRecordAddress + 8),
    Uint8Array.of(0x41, 0x53, 0x4f, 0x01, 0x00, 0x01, 0x00, 0x01),
  );
});

test("CP/M diagnostics identify the failing included file, not its importer", async () => {
  const result = await runMultipart([
    Buffer.from("ORG $100\r\nDB 1\r\n", "ascii"),
    Buffer.from("ORG $100\r\n  NOT_AN_INSTRUCTION\r\n", "ascii"),
  ]);
  assert.match(result.atomTranscript, /P1\.ASM:2:3: /);
  assert.equal(result.outputFile, undefined);
});

test("CP/M diagnostics retain undefined-symbol status and decimal positions", async () => {
  const undefinedSymbol = await runCpm22Atom(
    Buffer.from("ORG $100\r\nJP MISSING\r\n", "ascii"),
  );
  assert.match(undefinedSymbol.atomTranscript, /INPUT\.ASM:2:4: /);

  const manyLines = await runCpm22Atom(
    Buffer.from(`${"\n".repeat(123)}NOT_AN_INSTRUCTION\n`, "ascii"),
  );
  assert.match(manyLines.atomTranscript, /INPUT\.ASM:124:1: /);

  const wideLine = await runCpm22Atom(
    Buffer.from(`ORG $100\r\n${" ".repeat(130)}NOT_AN_INSTRUCTION\r\n`, "ascii"),
  );
  assert.match(wideLine.atomTranscript, /INPUT\.ASM:2:131: /);
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
    ["ATOM ?", "Invalid source name"],
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
  for (const auxiliaryName of ["MADE.$$$", "MADE.$$B"]) {
    const result = await runCpm22Atom(representativeSource, prior, {
      sourceName: "HELLO.ASM",
      outputName: "MADE.COM",
      files: [[auxiliaryName, sentinel]],
    });
    assert.match(result.atomTranscript, new RegExp(`${auxiliaryName.replaceAll("$", "\\$")} exists: erase it first`));
    assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
    assert.deepEqual(
      readCpm22File(result.finalDisk, auxiliaryName)?.bytes.slice(0, sentinel.length),
      sentinel,
    );
  }
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

test("CP/M filters nested conditional assembly and evaluates Atom numeric forms", async () => {
  const source = Buffer.from([
    "%DEFINE TARGET 0FFFFH",
    "%DEFINE ENABLED 1",
    "%DEFINE HEXVAL $2A",
    "%DEFINE COPY HEXVAL",
    "ORG $100",
    "DB 1",
    "%IF target",
    "DB 2",
    "%ELSE",
    "DB 3",
    "%ENDIF",
    "%IF 0",
    "%IF UNDEFINED",
    "DB 4",
    "%ENDIF",
    "%ELSE",
    "DB 5",
    "%ENDIF",
    "%IF ENABLED",
    "DB 6",
    "%ENDIF",
    "%IF 01110111B",
    "DB 7",
    "%ENDIF",
    "%IF %101",
    "DB 8",
    "%ENDIF",
    "%IF copy",
    "DB 9",
    "%ENDIF",
    "",
  ].join("\r\n"), "ascii");
  const result = await runCpm22Atom(source);

  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  assert.deepEqual(result.outputFile?.bytes.slice(0, 7), Uint8Array.of(1, 2, 5, 6, 7, 8, 9));
});

test("CP/M rejects malformed and unsupported conditional directives before output", async () => {
  const sources = [
    "%ELSE\r\n",
    "%ELSE EXTRA\r\n",
    "%ENDIF\r\n",
    "%ENDIF EXTRA\r\n",
    "%IF\r\n%ENDIF\r\n",
    "%IF 1\r\n%ELSE\r\n%ELSE\r\n%ENDIF\r\n",
    "%IF 1\r\nDB 1\r\n",
    "%DEFINE VALUE\r\n",
    "%DEFINE VALUE 1 EXTRA\r\n",
    "%DEFINE VALUE 1\r\n%DEFINE value 1\r\n",
    "%IF 1 2\r\n%ENDIF\r\n",
    "%IF 10000H\r\n%ENDIF\r\n",
    "%IF 2B\r\n%ENDIF\r\n",
    "%UNKNOWN\r\n",
    "%DEFINE ABCDEFGHIJKLMNOPQR 1\r\n",
    "ORG $100\r\n%DEFINE LATE 1\r\n",
    `${Array.from({ length: 17 }, () => "%IF 1").join("\r\n")}\r\n${Array.from({ length: 17 }, () => "%ENDIF").join("\r\n")}\r\n`,
  ];

  for (const source of sources) {
    const result = await runCpm22Atom(Buffer.from(source, "ascii"));
    assert.ok(
      /Invalid source directive/.test(result.atomTranscript),
      `Expected rejection for ${JSON.stringify(source)}; received ${JSON.stringify(result.atomTranscript.slice(0, 96))}`,
    );
    assert.equal(result.outputFile, undefined);
  }
});

test("CP/M INCBIN handles consecutive counts and a binary record boundary", async () => {
  const payload = Uint8Array.from({ length: 129 }, (_, index) => (index * 37) & 0xff);
  const result = await runCpm22Atom(
    Buffer.from([
      "ORG $100",
      'FIRST: INCBIN "DATA.BIN", 5',
      'SECOND: INCBIN "DATA.BIN", 101B',
      'CROSSING: INCBIN "DATA.BIN", $0081',
      "RET",
      "",
    ].join("\r\n"), "ascii"),
    undefined,
    { files: [["DATA.BIN", payload]] },
  );

  assert.match(result.atomTranscript, /OUTPUT\.COM written/);
  const expected = Buffer.concat([
    Buffer.from(payload.subarray(0, 5)),
    Buffer.from(payload.subarray(0, 5)),
    Buffer.from(payload),
    Buffer.from([0xc9]),
  ]);
  assert.deepEqual(result.outputFile?.bytes.slice(0, expected.length), Uint8Array.from(expected));
});

test("CP/M INCBIN rejects missing counts and protects a prior output on late EOF", async () => {
  const missingCount = await runCpm22Atom(
    Buffer.from('ORG $100\r\nINCBIN "DATA.BIN"\r\nRET\r\n', "ascii"),
    Uint8Array.of(0xc9),
    { files: [["DATA.BIN", Uint8Array.of(1)]] },
  );
  assert.match(missingCount.atomTranscript, /INPUT\.ASM:2:1\s+Invalid INCBIN/);
  assert.equal(missingCount.outputFile?.bytes[0], 0xc9);

  const incomplete = await runCpm22Atom(
    Buffer.from('ORG $100\r\nINCBIN "DATA.BIN", 129\r\nRET\r\n', "ascii"),
    Uint8Array.of(0xc9),
    { files: [["DATA.BIN", new Uint8Array(128).fill(0x5a)]] },
  );
  assert.match(incomplete.atomTranscript, /INPUT\.ASM:2:1: DATA\.BIN binary read failed/);
  assert.deepEqual(incomplete.outputFile?.bytes.slice(0, 1), Uint8Array.of(0xc9));
  assert.equal(readCpm22File(incomplete.finalDisk, "OUTPUT.$$$"), undefined);
});

test("include part boundaries cannot join tokens", async () => {
  const result = await runMultipart([
    Buffer.from("ORG $100\r\nLD", "ascii"),
    Buffer.from("A,1\r\n", "ascii"),
  ]);
  assert.match(result.atomTranscript, /\.ASM:\d+:\d+: /);
  assert.equal(result.outputFile, undefined);
});

test("the CP/M source reader accepts 65,535 bytes and rejects the next byte", async () => {
  const exact = Buffer.alloc(65_535, 0x78);
  exact[0] = 0x3b;
  const accepted = await runCpm22Atom(exact);
  assert.match(accepted.atomTranscript, /OUTPUT\.COM written/);
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
  assert.ok(accepted.atomMinimumSp >= accepted.census.stackFloorAddress);
  assert.equal(fileCalls.get("33:$$$"), undefined);
  assert.equal(fileCalls.get("34:$$$"), undefined);
  assert.equal(accepted.atomBdosCalls.includes(34), false);
  const prior = Uint8Array.from([0xc9]);
  const rejected = await runCpm22Atom(
    Buffer.from("ORG $100\r\nDS $FF01,0\r\n", "ascii"),
    prior,
  );
  assert.match(rejected.atomTranscript, /INPUT\.ASM:2:1: /);
  assert.deepEqual(rejected.outputFile?.bytes.slice(0, prior.length), prior);
});

test("disk full during large COM materialization preserves the prior destination", async () => {
  const prior = Uint8Array.of(0xc9, 0x76);
  const source = Buffer.from("ORG $100\r\nDS $FF00,0\r\n", "ascii");
  const result = await runCpm22Atom(source, prior);

  assert.match(result.atomTranscript, /OUTPUT\.COM: could not write the output/);
  assert.doesNotMatch(result.atomTranscript, /INPUT\.ASM:\d/);
  assert.equal(result.returnA, 1);
  assert.equal(result.returnSp, 0xe400);
  assert.deepEqual(result.outputFile?.bytes.slice(0, prior.length), prior);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$$"), undefined);
  assert.equal(readCpm22File(result.finalDisk, "OUTPUT.$$B"), undefined);
});
