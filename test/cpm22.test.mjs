import assert from "node:assert/strict";
import test from "node:test";

import { expectedRepresentativeProgram, runCpm22Atom } from "./cpm22-support.mjs";

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
  assert.equal(0xe400 - result.atomMinimumSp, result.census.representativeStackHighWaterBytes);
  assert.equal(result.atomBdosCalls.length, result.census.representativeBdosCalls);
  assert.deepEqual(result.atomBdosCalls, [
    15, 26, 20, 26, 20, 16,
    19, 22, 26, 21, 16,
    19, 23, 23, 19, 9,
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
