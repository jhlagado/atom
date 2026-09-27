import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createAsoWriter, readAsoOperations } from "../src/host/artifacts/aso-stream.mjs";

const vectors = JSON.parse(await readFile(new URL("./fixtures/aso-v1.json", import.meta.url)));
const unhex = (hex) => Uint8Array.from(Buffer.from(hex.replaceAll(/\s/g, ""), "hex"));
const decode = (bytes) => [...readAsoOperations([bytes])];
const join = (chunks) => Uint8Array.from(Buffer.concat(chunks));
function encode(events, bytewise = false) {
  const chunks = [];
  const { origin, fill } = events[0];
  const writer = createAsoWriter({ origin, fill, write: (chunk) => chunks.push(chunk) });
  for (const event of events.slice(1)) {
    if (event.kind === "commit") writer.commit(event);
    else if (event.kind === "image" && bytewise) {
      for (let i = 0; i < event.bytes.length; i += 1) {
        writer.image(event.address + i, event.bytes.subarray(i, i + 1));
      }
    } else writer[event.kind](event.address, event.bytes);
  }
  return join(chunks);
}
function materialize(events) {
  const begin = events[0];
  const end = events.at(-1);
  assert.equal(end.kind, "commit");
  const result = new Uint8Array(end.highWater - begin.origin).fill(begin.fill);
  for (const event of events.slice(1, -1)) result.set(event.bytes, event.address - begin.origin);
  return result;
}

test("ASO v1 shared vectors encode and decode byte-exactly at every input split", () => {
  for (const vector of vectors.valid) {
    const bytes = unhex(vector.hex);
    const expectedEvents = decode(bytes);
    assert.equal(expectedEvents[0].origin, vector.origin);
    assert.deepEqual(expectedEvents.at(-1), {
      kind: "commit", highWater: vector.highWater, finalCursor: vector.finalCursor,
    });
    const expected = join([new Uint8Array(vector.zeroPrefix ?? 0), unhex(vector.image)]);
    assert.deepEqual(materialize(expectedEvents), expected, vector.name);
    assert.deepEqual(encode(expectedEvents), bytes, vector.name);
    assert.deepEqual(encode(expectedEvents, true), bytes, vector.name);
    for (let split = 0; split <= bytes.length; split += 1) {
      assert.deepEqual([...readAsoOperations([bytes.slice(0, split), bytes.slice(split)])], expectedEvents);
    }
    assert.deepEqual([...readAsoOperations(Array.from(bytes, (value) => Uint8Array.of(value)))], expectedEvents);
  }
});

test("ASO v1 rejects shared malformed vectors and every truncation before END", () => {
  for (const [name, hex] of vectors.invalid) assert.throws(() => decode(unhex(hex)), /ASO:/, name);
  for (const vector of vectors.valid) {
    const bytes = unhex(vector.hex);
    for (let length = 0; length < bytes.length; length += 1) {
      assert.throws(() => decode(bytes.slice(0, length)), /ASO:/, `${vector.name} truncated at ${length}`);
    }
  }
});

test("ASO accepts only exact optional CP/M record padding and commits after validation", () => {
  for (const vector of vectors.valid) {
    const bytes = unhex(vector.hex);
    const padding = new Uint8Array((128 - bytes.length % 128) % 128).fill(0x1a);
    assert.deepEqual(decode(join([bytes, padding])), decode(bytes));
    assert.throws(() => decode(join([bytes, padding, Uint8Array.of(0x1a)])), /padding/);
    const seen = [];
    assert.throws(() => {
      for (const event of readAsoOperations([bytes, Uint8Array.of(0)])) seen.push(event.kind);
    }, /padding/);
    assert.ok(!seen.includes("commit"));
  }
});

test("ASO canonical IMAGE packing preserves interleaved patches beyond the CP/M RAM limit", () => {
  const chunks = [];
  const writer = createAsoWriter({ origin: 0x100, write(chunk) {
    assert.ok(chunk.length <= 132);
    chunks.push(chunk);
  } });
  const expected = new Uint8Array(0x8000);
  for (let i = 0; i < expected.length; i += 1) {
    expected[i] = i & 255;
    writer.image(0x100 + i, Uint8Array.of(expected[i]));
    if (i === 255) {
      writer.patch(0x17f, Uint8Array.of(0x34, 0x12));
      expected.set([0x34, 0x12], 127);
    }
  }
  writer.patch(0x101, Uint8Array.of(0xab));
  writer.patch(0x101, Uint8Array.of(0xcd)); // Latest replacement wins.
  expected[1] = 0xcd;
  writer.commit({ highWater: 0x8100, finalCursor: 0x8000 });
  const events = [...readAsoOperations(chunks)];
  assert.equal(events[3].kind, "patch");
  assert.equal(events[4].kind, "image");
  assert.deepEqual(materialize(events), expected);
  assert.deepEqual(encode(events, true), join(chunks));
  assert.equal(events.filter((event) => event.kind === "image").length, 256);
});

test("ASO invalid calls and I/O failures poison the tentative writer", () => {
  for (const invalid of [
    (w) => w.image(0x100, new Uint8Array()),
    (w) => w.image(0xffff, Uint8Array.of(1, 2)),
    (w) => w.image(0xff, Uint8Array.of(1)),
    (w) => w.image(0x100, Uint8Array.of(1)), // Prior image ends at $102.
    (w) => w.patch(0x102, Uint8Array.of(1)),
    (w) => w.patch(0x100, Uint8Array.of(1, 2, 3)),
    (w) => w.commit({ highWater: 0x101, finalCursor: 0x101 }),
    (w) => w.commit({ highWater: 0x102, finalCursor: 0x103 }),
    (w) => w.commit({ highWater: 0x10001, finalCursor: 0x102 }),
  ]) {
    const chunks = [];
    const writer = createAsoWriter({ origin: 0x100, write: (bytes) => chunks.push(bytes) });
    writer.image(0x100, Uint8Array.of(0, 0));
    assert.throws(() => invalid(writer), /ASO:/);
    assert.throws(() => writer.commit({ highWater: 0x102, finalCursor: 0x102 }), /closed/);
    assert.throws(() => decode(join(chunks)), /missing END/);
  }
  let calls = 0;
  const writer = createAsoWriter({ origin: 0x100, write() {
    if (++calls === 2) throw new Error("disk full");
  } });
  writer.image(0x100, Uint8Array.of(0));
  assert.throws(() => writer.commit({ highWater: 0x101, finalCursor: 0x101 }), /disk full/);
  assert.throws(() => writer.commit({ highWater: 0x101, finalCursor: 0x101 }), /closed/);
  const aborted = createAsoWriter({ origin: 0, write() {} });
  aborted.abort();
  assert.throws(() => aborted.image(0, Uint8Array.of(1)), /closed/);
});

test("ASO reader rejects record sizes and canonical violations even with a valid END", () => {
  const header = unhex("41534f01000100");
  const end = unhex("00000300000300");
  for (const [record, message] of [
    [join([unhex("01000181"), new Uint8Array(129)]), /length/],
    [unhex("01000102000002000103000000"), /length/],
    [unhex("01000101000101010100"), /canonical/],
    [unhex("0100010200000202010100"), /PATCH/],
  ]) assert.throws(() => decode(join([header, record, end])), message);
});

test("ASO malformed COMMIT arguments poison the writer", () => {
  for (const geometry of [undefined, null, { get highWater() { throw new Error("bad getter"); } }]) {
    const writer = createAsoWriter({ origin: 0x100, write() {} });
    writer.image(0x100, Uint8Array.of(0));
    assert.throws(() => writer.commit(geometry));
    assert.throws(() => writer.commit({ highWater: 0x101, finalCursor: 0x101 }), /closed/);
  }
});

test("ASO coalesces a bulk IMAGE across a partial run and fails closed during END", () => {
  const chunks = [];
  const writer = createAsoWriter({ origin: 0x100, write: (chunk) => chunks.push(chunk) });
  writer.image(0x100, new Uint8Array(17));
  writer.image(0x111, new Uint8Array(255));
  writer.commit({ highWater: 0x210, finalCursor: 0x210 });
  assert.deepEqual(decode(join(chunks)).filter((e) => e.kind === "image").map((e) => e.bytes.length),
    [128, 128, 16]);
  const tentative = [];
  const broken = createAsoWriter({ origin: 0, write(chunk) {
    if (chunk[0] === 0) throw new Error("END write failed");
    tentative.push(chunk);
  } });
  assert.throws(() => broken.commit({ highWater: 0, finalCursor: 0 }), /END write failed/);
  assert.throws(() => broken.commit({ highWater: 0, finalCursor: 0 }), /closed/);
  assert.throws(() => decode(join(tentative)), /missing END/);
});

test("ASO closes input iterators on rejection and consumer cancellation", () => {
  for (const invalid of [false, true]) {
    let closed = false;
    function* source() {
      try {
        yield invalid ? Uint8Array.of(0) : unhex(vectors.valid[0].hex);
      } finally { closed = true; }
    }
    if (invalid) assert.throws(() => [...readAsoOperations(source())]);
    else for (const event of readAsoOperations(source())) { assert.equal(event.kind, "begin"); break; }
    assert.equal(closed, true);
  }
});

test("ASO disallows asynchronous and reentrant output callbacks", () => {
  assert.throws(() => createAsoWriter({ origin: 0, write: () => Promise.resolve() }), /asynchronous/);
  let writer;
  writer = createAsoWriter({ origin: 0, write() { if (writer) writer.abort(); } });
  assert.throws(() => writer.image(0, new Uint8Array(128)), /reentrant/);
  assert.throws(() => writer.commit({ highWater: 128, finalCursor: 128 }), /closed/);
});
