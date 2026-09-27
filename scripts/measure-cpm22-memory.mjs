// Run the real CP/M command path; these observations are not a stack bound.
import assert from "node:assert/strict";
import { runCpm22Atom } from "../test/cpm22-support.mjs";

const cases = [
  ["expression nesting", `ORG $100\r\nDB ${"(".repeat(15)}1${")".repeat(15)}\r\n`, 0],
  ["expression overflow", `ORG $100\r\nDB ${"(".repeat(17)}1${")".repeat(17)}\r\n`, 1],
  ["forward word patch", "ORG $100\r\nJP NEXT\r\nDS 256,0\r\nNEXT: RET\r\n", 0],
  ["undefined symbol", "ORG $100\r\nJP MISSING\r\n", 1],
  ["relative range error", "ORG $100\r\nJR NEXT\r\nDS 256,0\r\nNEXT: RET\r\n", 1],
  ["full target extent", "ORG $100\r\nDS $FF00,0\r\n", 0, { freshDisk: true }],
  ["target overflow", "ORG $100\r\nDS $FF01,0\r\n", 1],
];
const measurements = [];
const expectedImages = new Map([
  ["expression nesting", Uint8Array.of(1)],
  ["forward word patch", Uint8Array.from([0xc3, 0x03, 0x02, ...new Array(256).fill(0), 0xc9])],
  ["full target extent", new Uint8Array(0xff00)],
]);
const expectedErrors = new Map([
  ["expression overflow", "02 INPUT.ASM:2:1"],
  ["undefined symbol", "03 INPUT.ASM:2:4"],
  ["relative range error", "02 INPUT.ASM:4:1"],
  ["target overflow", "02 INPUT.ASM:2:1"],
]);
for (const [name, source, status, options] of cases) {
  const prior = status === 0
    ? undefined
    : Uint8Array.from({ length: 128 }, (_, index) => index ^ 0xa5);
  const fileCalls = new Map();
  const result = await runCpm22Atom(Buffer.from(source, "ascii"), prior, {
    ...options,
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
  assert.equal(result.returnA, status, `${name}: unexpected result`);
  assert.equal(result.returnSp, 0xe400, `${name}: private stack balance at warm boot`);
  assert.ok(result.atomMinimumSp >= 0xd800, `${name}: stack reservation exceeded`);
  assert.ok(result.outputFile, `${name}: output file disappeared`);
  if (status !== 0) {
    assert.deepEqual(result.outputFile.bytes, prior);
    assert.equal(result.atomTranscript, `ATOM INPUT.ASM OUTPUT.COM\r\r\n\r\nAtom error ${expectedErrors.get(name)}\r\n\r\nA>`);
  } else {
    const expected = expectedImages.get(name);
    assert.deepEqual(result.outputFile.bytes.slice(0, expected.length), expected);
    assert.equal(result.outputFile.records, Math.ceil(expected.length / 128));
    assert.equal(result.atomTranscript, "ATOM INPUT.ASM OUTPUT.COM\r\r\n\r\nOUTPUT.COM written\r\n\r\nA>");
  }
  const windowRecords = result.census.materializerWindowBytes / 128;
  const materializerPasses = status === 0 && result.outputFile
    ? Math.ceil(result.outputFile.records / windowRecords)
    : 0;
  const spoolReadCalls = fileCalls.get("20:BAK") ?? 0;
  measurements.push({
    name,
    status,
    observedStackBytes: 0xe400 - result.atomMinimumSp,
    instructions: result.atomInstructions,
    tStates: result.atomCycles,
    warmBootInstructions: result.warmBootInstructions,
    warmBootTStates: result.warmBootCycles,
    sequentialWrites: result.atomBdosCalls.filter((call) => call === 21).length,
    randomReads: result.atomBdosCalls.filter((call) => call === 33).length,
    materializer: {
      windowBytes: result.census.materializerWindowBytes,
      passes: materializerPasses,
      spoolSequentialRecordWrites: fileCalls.get("21:BAK") ?? 0,
      spoolSequentialRecordReads: Math.max(0, spoolReadCalls - materializerPasses),
      spoolSequentialReadCallsIncludingEof: spoolReadCalls,
      outputSequentialRecordWrites: fileCalls.get("21:$$$") ?? 0,
      outputRandomRecordReads: fileCalls.get("33:$$$") ?? 0,
      outputRandomRecordWrites: fileCalls.get("34:$$$") ?? 0,
    },
  });
}
console.log(JSON.stringify({
  evidence: "Measured on the bundled CP/M emulator fixture, not a worst-case stack proof",
  measurements,
}, null, 2));
