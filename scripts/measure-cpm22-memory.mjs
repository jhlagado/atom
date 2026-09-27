// Run the real CP/M command path; these observations are not a stack bound.
import assert from "node:assert/strict";
import { runCpm22Atom } from "../test/cpm22-support.mjs";

const cases = [
  ["expression nesting", `ORG $100\r\nDB ${"(".repeat(15)}1${")".repeat(15)}\r\n`, 0],
  ["expression overflow", `ORG $100\r\nDB ${"(".repeat(17)}1${")".repeat(17)}\r\n`, 1],
  ["forward word patch", "ORG $100\r\nJP NEXT\r\nDS 256,0\r\nNEXT: RET\r\n", 0],
  ["undefined symbol", "ORG $100\r\nJP MISSING\r\n", 1],
  ["relative range error", "ORG $100\r\nJR NEXT\r\nDS 256,0\r\nNEXT: RET\r\n", 1],
  ["full output window", "ORG $100\r\nDS $4780,0\r\n", 0],
  ["output overflow", "ORG $100\r\nDS $4781,0\r\n", 1],
];
const measurements = [];
const expectedImages = new Map([
  ["expression nesting", Uint8Array.of(1)],
  ["forward word patch", Uint8Array.from([0xc3, 0x03, 0x02, ...new Array(256).fill(0), 0xc9])],
  ["full output window", new Uint8Array(0x4780)],
]);
const expectedErrors = new Map([
  ["expression overflow", "02 INPUT.ASM:2:1"],
  ["undefined symbol", "03 INPUT.ASM:2:4"],
  ["relative range error", "02 INPUT.ASM:4:1"],
  ["output overflow", "02 INPUT.ASM:2:1"],
]);
for (const [name, source, status] of cases) {
  const prior = Uint8Array.from({ length: 128 }, (_, index) => index ^ 0xa5);
  const result = await runCpm22Atom(Buffer.from(source, "ascii"), prior);
  assert.equal(result.returnA, status, `${name}: unexpected result`);
  assert.equal(result.returnSp, (result.entrySp + 2) & 0xffff, `${name}: stack return`);
  assert.ok(result.atomMinimumSp >= 0xd800, `${name}: stack reservation exceeded`);
  assert.ok(result.outputFile, `${name}: output file disappeared`);
  if (status !== 0) {
    assert.deepEqual(result.outputFile.bytes, prior);
    assert.equal(result.atomTranscript, `ATOM\r\r\n\r\nAtom error ${expectedErrors.get(name)}\r\n\r\nA>`);
  } else {
    const expected = expectedImages.get(name);
    assert.deepEqual(result.outputFile.bytes.slice(0, expected.length), expected);
    assert.equal(result.outputFile.records, Math.ceil(expected.length / 128));
    assert.equal(result.atomTranscript, "ATOM\r\r\n\r\nOUTPUT.COM written\r\n\r\nA>");
  }
  measurements.push({
    name,
    status,
    observedStackBytes: 0xe400 - result.atomMinimumSp,
    instructions: result.atomInstructions,
    tStates: result.atomCycles,
    sequentialWrites: result.atomBdosCalls.filter((call) => call === 21).length,
    randomReads: result.atomBdosCalls.filter((call) => call === 33).length,
  });
}
console.log(JSON.stringify({
  evidence: "Measured on the bundled CP/M emulator fixture, not a worst-case stack proof",
  measurements,
}, null, 2));
