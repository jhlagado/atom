// ASO v1 stream primitives. The caller owns tentative files and publication.
// write() must be synchronous and throw on failure. No full image is retained.
const LIMIT = 0x10000;
const integer = (value, minimum, maximum, name) => {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error(`ASO: invalid ${name}`);
  }
};
const endpoint = (value) => [value & 255, (value >>> 8) & 255, value >>> 16];
const bytesRequired = (bytes) => {
  if (!(bytes instanceof Uint8Array)) throw new Error("ASO: expected byte array");
};

export function createAsoWriter({ origin, fill = 0, write }) {
  integer(origin, 0, 0xffff, "origin");
  integer(fill, 0, 255, "fill");
  if (typeof write !== "function") throw new Error("ASO: missing writer");
  const pending = new Uint8Array(128);
  let count = 0;
  let start = origin;
  let imageEnd = origin;
  let open = true;
  let busy = false;
  function emit(bytes) {
    const result = write(bytes);
    if (result?.then !== undefined) throw new Error("ASO: asynchronous writer");
  }
  function record(kind, address, bytes) {
    const result = new Uint8Array(4 + bytes.length);
    result.set([kind, address & 255, address >>> 8, bytes.length]);
    result.set(bytes, 4);
    emit(result);
  }
  function flush() {
    if (count === 0) return;
    record(1, start, pending.subarray(0, count));
    count = 0;
  }
  function operation(action) {
    if (busy) throw new Error("ASO: reentrant writer call");
    if (!open) throw new Error("ASO: writer is closed");
    busy = true;
    try { action(); } catch (error) {
      open = false;
      count = 0;
      throw error;
    } finally {
      busy = false;
    }
  }
  emit(Uint8Array.of(0x41, 0x53, 0x4f, 1, origin & 255, origin >>> 8, fill));
  return Object.freeze({
    image(address, bytes) {
      operation(() => {
        bytesRequired(bytes);
        integer(address, origin, 0xffff, "IMAGE address");
        integer(bytes.length, 1, LIMIT - address, "IMAGE length");
        if (address < imageEnd) throw new Error("ASO: descending or overlapping IMAGE");
        if (count !== 0 && address !== imageEnd) flush();
        for (const value of bytes) {
          if (count === 0) start = address;
          pending[count++] = value;
          address += 1;
          if (count === 128) flush();
        }
        imageEnd = address;
      });
    },
    patch(address, bytes) {
      operation(() => {
        bytesRequired(bytes);
        integer(address, origin, 0xffff, "PATCH address");
        integer(bytes.length, 1, 2, "PATCH length");
        if (address + bytes.length > imageEnd) throw new Error("ASO: PATCH precedes IMAGE");
        flush();
        record(2, address, bytes);
      });
    },
    commit(geometry) {
      operation(() => {
        const { highWater, finalCursor } = geometry;
        integer(highWater, imageEnd, LIMIT, "high-water mark");
        integer(finalCursor, origin, highWater, "final cursor");
        flush();
        emit(Uint8Array.from([0, ...endpoint(highWater), ...endpoint(finalCursor)]));
        open = false;
      });
    },
    abort() {
      if (busy) throw new Error("ASO: reentrant writer call");
      open = false;
      count = 0;
    },
  });
}

// Yield tentative operations. Only the final commit event authorises publication.
export function* readAsoOperations(chunks) {
  const iterator = chunks[Symbol.iterator]();
  let exhausted = false;
  const tracked = { next() {
    const next = iterator.next();
    exhausted = Boolean(next.done);
    return next;
  } };
  try {
    yield* readRecords(tracked);
  } finally {
    if (!exhausted) iterator.return?.();
  }
}

function* readRecords(iterator) {
  let chunk = new Uint8Array();
  let index = 0;
  let offset = 0;
  function byte(required = true) {
    while (index === chunk.length) {
      const next = iterator.next();
      if (next.done) {
        if (required) throw new Error("ASO: truncated stream or missing END");
        return undefined;
      }
      bytesRequired(next.value);
      chunk = next.value;
      index = 0;
    }
    offset += 1;
    return chunk[index++];
  }
  const word = () => byte() | (byte() << 8);
  const end = () => word() | (byte() << 16);
  for (const expected of [0x41, 0x53, 0x4f, 1]) {
    if (byte() !== expected) throw new Error("ASO: invalid magic or version");
  }
  const origin = word();
  const fill = byte();
  let imageEnd = origin;
  let previousKind = 0;
  let previousLength = 0;
  yield { kind: "begin", origin, fill };
  for (;;) {
    const kind = byte();
    if (kind === 0) {
      const highWater = end();
      const finalCursor = end();
      integer(highWater, imageEnd, LIMIT, "high-water mark");
      integer(finalCursor, origin, highWater, "final cursor");
      const padding = (128 - (offset % 128)) % 128;
      let trailing = 0;
      for (let value = byte(false); value !== undefined; value = byte(false)) {
        trailing += 1;
        if (value !== 0x1a || trailing > padding) throw new Error("ASO: invalid trailing padding");
      }
      if (trailing !== 0 && trailing !== padding) throw new Error("ASO: incomplete trailing padding");
      yield { kind: "commit", highWater, finalCursor };
      return;
    }
    if (kind !== 1 && kind !== 2) throw new Error("ASO: unknown record kind");
    const address = word();
    const length = byte();
    integer(address, origin, 0xffff, "record address");
    integer(length, 1, kind === 1 ? 128 : 2, "record length");
    if (address + length > LIMIT) throw new Error("ASO: record exceeds address space");
    if (kind === 1) {
      if (address < imageEnd) throw new Error("ASO: descending or overlapping IMAGE");
      if (previousKind === 1 && previousLength < 128 && address === imageEnd) {
        throw new Error("ASO: non-canonical adjacent IMAGE");
      }
      imageEnd = address + length;
    } else if (address + length > imageEnd) {
      throw new Error("ASO: PATCH precedes IMAGE");
    }
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i += 1) bytes[i] = byte();
    yield { kind: kind === 1 ? "image" : "patch", address, bytes };
    previousKind = kind;
    previousLength = length;
  }
}
