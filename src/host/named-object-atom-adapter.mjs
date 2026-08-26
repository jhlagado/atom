import {
  NAMED_OBJECT_STATUS,
  NamedObjectClient,
} from "./named-object-services.mjs";

const frozen = (bytes) => Object.freeze(Array.from(bytes));

/**
 * Adapt Atom's compact source/sink callbacks to named-object ABI 1. The output
 * object is a flat target image whose byte zero corresponds to target.start.
 */
export function createNamedObjectAtomAdapter({ provider, sourceNames, outputName }) {
  if (!Array.isArray(sourceNames) || sourceNames.length < 1 || sourceNames.some((name) => typeof name !== "string" || name.length < 1)) {
    throw new TypeError("Atom named-object adapter requires nonempty sourceNames");
  }
  if (typeof outputName !== "string" || outputName.length < 1) {
    throw new TypeError("Atom named-object adapter requires outputName");
  }
  const client = new NamedObjectClient(provider);
  let sourceHandle = 0;
  let sourcePart = -1;
  let sourceCursor = 0;
  let outputHandle = 0;
  let target;
  let outputCursor = 0;
  let highWater = 0;
  let images = [];
  let patches = [];
  let initialized = new Set();
  let patched = new Set();
  let generation;
  let failure;
  const lifecycle = [];

  const reject = (status, code) => {
    failure ??= Object.freeze({ status, code });
    return status;
  };
  const closeSource = () => {
    if (sourceHandle === 0) return NAMED_OBJECT_STATUS.success;
    const result = client.close(sourceHandle);
    if (result.status === 0) {
      sourceHandle = 0;
      sourcePart = -1;
      sourceCursor = 0;
    }
    return result.status;
  };
  const write = (bytes) => {
    const result = client.write(outputHandle, bytes);
    if (result.status !== 0 || result.result !== bytes.length) {
      return reject(result.status || NAMED_OBJECT_STATUS.storage, "object-write");
    }
    outputCursor += bytes.length;
    return NAMED_OBJECT_STATUS.success;
  };
  const fillTo = (end) => {
    const zeros = new Uint8Array(256);
    while (outputCursor < end) {
      const count = Math.min(zeros.length, end - outputCursor);
      const status = write(zeros.subarray(0, count));
      if (status !== 0) return status;
    }
    return NAMED_OBJECT_STATUS.success;
  };

  const sourceRead = ({ part, offset }) => {
    if (!Number.isInteger(part) || part < 0 || part >= sourceNames.length || !Number.isInteger(offset) || offset < 0 || offset > 0xffff) {
      return undefined;
    }
    if (part !== sourcePart) {
      if (closeSource() !== 0) return undefined;
      const opened = client.openRead(sourceNames[part]);
      if (opened.status !== 0) return undefined;
      sourceHandle = opened.handle;
      sourcePart = part;
      sourceCursor = 0;
    }
    if (offset !== sourceCursor) {
      const sought = client.seek(sourceHandle, offset);
      if (sought.status !== 0) return undefined;
      sourceCursor = offset;
    }
    const read = client.read(sourceHandle, 1);
    if (read.status !== 0 || read.result !== 1) return undefined;
    sourceCursor += 1;
    return read.bytes[0];
  };

  const sink = Object.freeze({
    begin(context) {
      lifecycle.push("begin");
      if (outputHandle !== 0 || context?.target === undefined) {
        return reject(NAMED_OBJECT_STATUS.invalid, "begin-state");
      }
      const opened = client.beginWrite(outputName);
      if (opened.status !== 0) return reject(opened.status, "object-begin");
      outputHandle = opened.handle;
      target = Object.freeze({ ...context.target });
      outputCursor = 0;
      highWater = target.start;
      images = [];
      patches = [];
      initialized = new Set();
      patched = new Set();
      generation = undefined;
      failure = undefined;
      return NAMED_OBJECT_STATUS.success;
    },
    image(operation) {
      lifecycle.push("image");
      if (outputHandle === 0 || operation.bank !== 0 || operation.address < target.start) {
        return reject(NAMED_OBJECT_STATUS.invalid, "image-state");
      }
      const offset = operation.address - target.start;
      if (offset < outputCursor || offset + operation.bytes.length > target.capacity) {
        return reject(NAMED_OBJECT_STATUS.capacity, "image-range");
      }
      let status = fillTo(offset);
      if (status !== 0) return status;
      status = write(Uint8Array.from(operation.bytes));
      if (status !== 0) return status;
      for (let index = 0; index < operation.bytes.length; index += 1) initialized.add(operation.address + index);
      highWater = Math.max(highWater, operation.address + operation.bytes.length);
      images.push(Object.freeze({ ...operation, bytes: frozen(operation.bytes) }));
      return NAMED_OBJECT_STATUS.success;
    },
    patch(operation) {
      lifecycle.push("patch");
      if (outputHandle === 0 || operation.bank !== 0 || operation.bytes.length < 1) {
        return reject(NAMED_OBJECT_STATUS.invalid, "patch-state");
      }
      for (let index = 0; index < operation.bytes.length; index += 1) {
        const address = operation.address + index;
        if (!initialized.has(address) || patched.has(address)) {
          return reject(NAMED_OBJECT_STATUS.invalid, "patch-target");
        }
      }
      const end = outputCursor;
      let result = client.seek(outputHandle, operation.address - target.start);
      if (result.status !== 0) return reject(result.status, "patch-seek");
      outputCursor = operation.address - target.start;
      const status = write(Uint8Array.from(operation.bytes));
      if (status !== 0) return status;
      result = client.seek(outputHandle, end);
      if (result.status !== 0) return reject(result.status, "patch-restore");
      outputCursor = end;
      for (let index = 0; index < operation.bytes.length; index += 1) patched.add(operation.address + index);
      patches.push(Object.freeze({ ...operation, bytes: frozen(operation.bytes) }));
      return NAMED_OBJECT_STATUS.success;
    },
    commit(context) {
      lifecycle.push("commit");
      if (outputHandle === 0 || context.highWater < target.start || context.highWater > target.start + target.capacity) {
        return reject(NAMED_OBJECT_STATUS.invalid, "commit-state");
      }
      const status = fillTo(context.highWater - target.start);
      if (status !== 0) return status;
      highWater = context.highWater;
      const closed = closeSource();
      if (closed !== 0) return reject(closed, "source-close");
      const committed = client.commit(outputHandle);
      if (committed.status !== 0) return reject(committed.status, "object-commit");
      outputHandle = 0;
      generation = Object.freeze({
        target,
        finalCursor: context.finalCursor,
        remaining: context.remaining,
        highWater,
        images: Object.freeze(images.slice()),
        patches: Object.freeze(patches.slice()),
      });
      return NAMED_OBJECT_STATUS.success;
    },
    abort() {
      lifecycle.push("abort");
      closeSource();
      if (outputHandle === 0) return reject(NAMED_OBJECT_STATUS.invalid, "abort-state");
      const aborted = client.abort(outputHandle);
      outputHandle = 0;
      return aborted.status;
    },
    snapshot() {
      return Object.freeze({
        open: outputHandle !== 0,
        lifecycle: Object.freeze(lifecycle.slice()),
        generation,
        failure,
      });
    },
  });

  return Object.freeze({ sourceRead, sink });
}
