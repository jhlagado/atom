export const NAMED_OBJECT_ABI_VERSION = 1;
export const NAMED_OBJECT_REQUEST_SIZE = 16;

export const NAMED_OBJECT_REQUEST = Object.freeze({
  size: 0,
  abi: 1,
  operation: 2,
  flags: 3,
  handle: 4,
  pointer: 6,
  length: 8,
  offset: 10,
  result: 14,
});

export const NAMED_OBJECT_OPERATION = Object.freeze({
  openRead: 0,
  beginWrite: 1,
  read: 2,
  write: 3,
  rewind: 4,
  seek: 5,
  close: 6,
  commit: 7,
  abort: 8,
});

export const NAMED_OBJECT_STATUS = Object.freeze({
  success: 0,
  invalid: 1,
  unavailable: 2,
  notFound: 3,
  capacity: 4,
  access: 5,
  storage: 6,
  conflict: 7,
  cancelled: 8,
  unsupported: 9,
});

const word = (memory, at) => memory[at] | (memory[at + 1] << 8);
const putWord = (memory, at, value) => {
  memory[at] = value & 0xff;
  memory[at + 1] = value >>> 8;
};
const dword = (memory, at) => word(memory, at) + word(memory, at + 2) * 0x10000;
const inRange = (memory, pointer, length) =>
  Number.isInteger(pointer) && Number.isInteger(length) &&
  pointer >= 0 && length >= 0 && pointer + length <= memory.length;
const keyFor = (bytes) => Buffer.from(bytes).toString("hex");
const frozenBytes = (bytes) => Uint8Array.from(bytes);

/**
 * Reference in-memory implementation of named-object ABI 1. It models the
 * same transactional generations and bounded handles as the TEC-FS provider;
 * callers still use the exact 16-byte request block used by Z80 providers.
 */
export class MemoryNamedObjectServices {
  #objects = new Map();
  #handles = new Map();
  #nextHandle = 1;
  #maxHandles;
  #maxObjectBytes;
  #fail;

  constructor(initialObjects = new Map(), options = {}) {
    this.#maxHandles = options.maxHandles ?? 8;
    this.#maxObjectBytes = options.maxObjectBytes ?? 0xffff;
    this.#fail = options.fail;
    if (!Number.isInteger(this.#maxHandles) || this.#maxHandles < 1 || this.#maxHandles > 0xffff) {
      throw new RangeError("maxHandles must be in the range 1..65535");
    }
    if (!Number.isInteger(this.#maxObjectBytes) || this.#maxObjectBytes < 0 || this.#maxObjectBytes > 0xffff) {
      throw new RangeError("maxObjectBytes must be in the range 0..65535");
    }
    for (const [name, bytes] of initialObjects) this.seed(name, bytes);
  }

  get openHandleCount() {
    return this.#handles.size;
  }

  seed(name, bytes) {
    const encoded = typeof name === "string" ? new TextEncoder().encode(name) : Uint8Array.from(name);
    if (encoded.length < 1 || encoded.length > 255 || bytes.length > this.#maxObjectBytes) {
      throw new RangeError("named object is outside provider capacity");
    }
    this.#objects.set(keyFor(encoded), frozenBytes(bytes));
  }

  bytes(name) {
    const encoded = typeof name === "string" ? new TextEncoder().encode(name) : Uint8Array.from(name);
    const bytes = this.#objects.get(keyFor(encoded));
    return bytes === undefined ? undefined : frozenBytes(bytes);
  }

  dispatch(memory, request) {
    if (!inRange(memory, request, NAMED_OBJECT_REQUEST_SIZE)) return NAMED_OBJECT_STATUS.invalid;
    putWord(memory, request + NAMED_OBJECT_REQUEST.result, 0);
    if (
      memory[request + NAMED_OBJECT_REQUEST.size] !== NAMED_OBJECT_REQUEST_SIZE ||
      memory[request + NAMED_OBJECT_REQUEST.abi] !== NAMED_OBJECT_ABI_VERSION ||
      memory[request + NAMED_OBJECT_REQUEST.flags] !== 0
    ) return NAMED_OBJECT_STATUS.invalid;

    const operation = memory[request + NAMED_OBJECT_REQUEST.operation];
    const handle = word(memory, request + NAMED_OBJECT_REQUEST.handle);
    const pointer = word(memory, request + NAMED_OBJECT_REQUEST.pointer);
    const length = word(memory, request + NAMED_OBJECT_REQUEST.length);
    const offset = dword(memory, request + NAMED_OBJECT_REQUEST.offset);
    const injected = this.#fail?.({ operation, handle, pointer, length, offset });
    if (injected !== undefined && injected !== 0) {
      const state = this.#handles.get(handle);
      if (operation === NAMED_OBJECT_OPERATION.write && state?.mode === "write") state.poisoned = true;
      return injected;
    }

    switch (operation) {
      case NAMED_OBJECT_OPERATION.openRead:
      case NAMED_OBJECT_OPERATION.beginWrite:
        if (handle !== 0 || offset !== 0 || length < 1 || length > 255 || !inRange(memory, pointer, length)) {
          return NAMED_OBJECT_STATUS.invalid;
        }
        return this.#open(memory, request, operation, pointer, length);
      case NAMED_OBJECT_OPERATION.read:
      case NAMED_OBJECT_OPERATION.write:
        if (offset !== 0 || !inRange(memory, pointer, length)) return NAMED_OBJECT_STATUS.invalid;
        return this.#transfer(memory, request, operation, handle, pointer, length);
      case NAMED_OBJECT_OPERATION.rewind:
      case NAMED_OBJECT_OPERATION.close:
      case NAMED_OBJECT_OPERATION.commit:
      case NAMED_OBJECT_OPERATION.abort:
        if (pointer !== 0 || length !== 0 || offset !== 0) return NAMED_OBJECT_STATUS.invalid;
        return this.#terminal(operation, handle);
      case NAMED_OBJECT_OPERATION.seek:
        if (pointer !== 0 || length !== 0) return NAMED_OBJECT_STATUS.invalid;
        return this.#seek(handle, offset);
      default:
        return NAMED_OBJECT_STATUS.invalid;
    }
  }

  #allocate(state) {
    if (this.#handles.size >= this.#maxHandles) return 0;
    for (let count = 0; count < 0xffff; count += 1) {
      const candidate = this.#nextHandle;
      this.#nextHandle = candidate === 0xffff ? 1 : candidate + 1;
      if (!this.#handles.has(candidate)) {
        this.#handles.set(candidate, state);
        return candidate;
      }
    }
    return 0;
  }

  #open(memory, request, operation, pointer, length) {
    const name = memory.slice(pointer, pointer + length);
    const key = keyFor(name);
    let state;
    if (operation === NAMED_OBJECT_OPERATION.openRead) {
      const bytes = this.#objects.get(key);
      if (bytes === undefined) return NAMED_OBJECT_STATUS.notFound;
      state = { mode: "read", bytes, cursor: 0 };
    } else {
      if ([...this.#handles.values()].some((item) => item.mode === "write" && item.key === key)) {
        return NAMED_OBJECT_STATUS.conflict;
      }
      state = { mode: "write", key, bytes: new Uint8Array(0), cursor: 0, poisoned: false };
    }
    const handle = this.#allocate(state);
    if (handle === 0) return NAMED_OBJECT_STATUS.capacity;
    putWord(memory, request + NAMED_OBJECT_REQUEST.handle, handle);
    return NAMED_OBJECT_STATUS.success;
  }

  #transfer(memory, request, operation, handle, pointer, length) {
    const state = this.#handles.get(handle);
    if (state === undefined || state.poisoned) return NAMED_OBJECT_STATUS.invalid;
    if (operation === NAMED_OBJECT_OPERATION.read) {
      const count = Math.min(length, state.bytes.length - state.cursor);
      memory.set(state.bytes.subarray(state.cursor, state.cursor + count), pointer);
      state.cursor += count;
      putWord(memory, request + NAMED_OBJECT_REQUEST.result, count);
      return NAMED_OBJECT_STATUS.success;
    }
    if (state.mode !== "write") return NAMED_OBJECT_STATUS.access;
    const end = state.cursor + length;
    if (end > this.#maxObjectBytes) {
      state.poisoned = true;
      return NAMED_OBJECT_STATUS.capacity;
    }
    if (end > state.bytes.length) {
      const expanded = new Uint8Array(end);
      expanded.set(state.bytes);
      state.bytes = expanded;
    }
    state.bytes.set(memory.subarray(pointer, pointer + length), state.cursor);
    state.cursor = end;
    putWord(memory, request + NAMED_OBJECT_REQUEST.result, length);
    return NAMED_OBJECT_STATUS.success;
  }

  #seek(handle, offset) {
    const state = this.#handles.get(handle);
    if (state === undefined || state.poisoned) return NAMED_OBJECT_STATUS.invalid;
    if (offset > state.bytes.length) return NAMED_OBJECT_STATUS.unsupported;
    state.cursor = offset;
    return NAMED_OBJECT_STATUS.success;
  }

  #terminal(operation, handle) {
    const state = this.#handles.get(handle);
    if (state === undefined) return NAMED_OBJECT_STATUS.invalid;
    switch (operation) {
      case NAMED_OBJECT_OPERATION.rewind:
        if (state.poisoned) return NAMED_OBJECT_STATUS.invalid;
        state.cursor = 0;
        return NAMED_OBJECT_STATUS.success;
      case NAMED_OBJECT_OPERATION.close:
        if (state.mode !== "read") return NAMED_OBJECT_STATUS.access;
        this.#handles.delete(handle);
        return NAMED_OBJECT_STATUS.success;
      case NAMED_OBJECT_OPERATION.commit:
        if (state.mode !== "write" || state.poisoned) return NAMED_OBJECT_STATUS.invalid;
        this.#objects.set(state.key, frozenBytes(state.bytes));
        this.#handles.delete(handle);
        return NAMED_OBJECT_STATUS.success;
      case NAMED_OBJECT_OPERATION.abort:
        if (state.mode !== "write") return NAMED_OBJECT_STATUS.access;
        this.#handles.delete(handle);
        return NAMED_OBJECT_STATUS.success;
      default:
        return NAMED_OBJECT_STATUS.invalid;
    }
  }
}

/** Small synchronous client for providers implementing named-object ABI 1. */
export class NamedObjectClient {
  #provider;
  #memory = new Uint8Array(0x200);
  #request = 0x20;
  #buffer = 0x100;

  constructor(provider) {
    if (typeof provider?.dispatch !== "function") throw new TypeError("named-object provider requires dispatch()");
    this.#provider = provider;
  }

  #call(operation, { handle = 0, bytes, length = 0, offset = 0 } = {}) {
    const request = this.#request;
    this.#memory.fill(0, request, request + NAMED_OBJECT_REQUEST_SIZE);
    this.#memory[request + NAMED_OBJECT_REQUEST.size] = NAMED_OBJECT_REQUEST_SIZE;
    this.#memory[request + NAMED_OBJECT_REQUEST.abi] = NAMED_OBJECT_ABI_VERSION;
    this.#memory[request + NAMED_OBJECT_REQUEST.operation] = operation;
    putWord(this.#memory, request + NAMED_OBJECT_REQUEST.handle, handle);
    if (bytes !== undefined) {
      if (bytes.length > 0x100) throw new RangeError("named-object transfer exceeds client buffer");
      this.#memory.set(bytes, this.#buffer);
      putWord(this.#memory, request + NAMED_OBJECT_REQUEST.pointer, this.#buffer);
      putWord(this.#memory, request + NAMED_OBJECT_REQUEST.length, bytes.length);
    } else if (length !== 0) {
      if (length > 0x100) throw new RangeError("named-object transfer exceeds client buffer");
      putWord(this.#memory, request + NAMED_OBJECT_REQUEST.pointer, this.#buffer);
      putWord(this.#memory, request + NAMED_OBJECT_REQUEST.length, length);
    }
    putWord(this.#memory, request + NAMED_OBJECT_REQUEST.offset, offset & 0xffff);
    putWord(this.#memory, request + NAMED_OBJECT_REQUEST.offset + 2, Math.floor(offset / 0x10000));
    const status = this.#provider.dispatch(this.#memory, request);
    return {
      status,
      handle: word(this.#memory, request + NAMED_OBJECT_REQUEST.handle),
      result: word(this.#memory, request + NAMED_OBJECT_REQUEST.result),
      bytes: this.#memory.slice(this.#buffer, this.#buffer + word(this.#memory, request + NAMED_OBJECT_REQUEST.result)),
    };
  }

  openRead(name) {
    return this.#call(NAMED_OBJECT_OPERATION.openRead, { bytes: new TextEncoder().encode(name) });
  }
  beginWrite(name) {
    return this.#call(NAMED_OBJECT_OPERATION.beginWrite, { bytes: new TextEncoder().encode(name) });
  }
  read(handle, length) {
    return this.#call(NAMED_OBJECT_OPERATION.read, { handle, length });
  }
  write(handle, bytes) {
    return this.#call(NAMED_OBJECT_OPERATION.write, { handle, bytes });
  }
  seek(handle, offset) {
    return this.#call(NAMED_OBJECT_OPERATION.seek, { handle, offset });
  }
  close(handle) {
    return this.#call(NAMED_OBJECT_OPERATION.close, { handle });
  }
  commit(handle) {
    return this.#call(NAMED_OBJECT_OPERATION.commit, { handle });
  }
  abort(handle) {
    return this.#call(NAMED_OBJECT_OPERATION.abort, { handle });
  }
}
