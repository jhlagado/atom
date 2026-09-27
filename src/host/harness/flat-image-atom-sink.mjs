import { AtomAssemblyError } from "../atom-assembly-error.mjs";
import { ATOM_HOST_SINK_STATUS } from "./native-atom-runner.mjs";

function fail(code, message) {
  throw new AtomAssemblyError("configuration", code, message);
}

function byte(value) {
  if (!Number.isInteger(value) || value < 0 || value > 0xff) {
    fail("invalid-fill", "flat-image fill must be a byte");
  }
  return value;
}

function inTarget(target, address, length) {
  return address >= target.start &&
    address + length <= target.start + target.capacity;
}

/**
 * Materialize ordered IMAGE/PATCH callbacks directly into one flat image.
 * State byte 1 means IMAGE has initialized an address; state byte 2 means a
 * later PATCH has replaced it. This preserves sink validation without keeping
 * per-byte operation objects or address sets.
 */
export function createFlatImageAtomSink({ fill = 0 } = {}) {
  const fillByte = byte(fill);
  let open = false;
  let target;
  let descriptor;
  let image = new Uint8Array();
  let state = new Uint8Array();
  let imageEnd;
  let firstImageAddress;
  let generation;
  let materialized;
  let failure;

  const reject = (status, code, message) => {
    failure = Object.freeze({ status, code, message });
    return status;
  };

  const sink = {
    begin(context) {
      if (open) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-open",
          "a generation is already open",
        );
      }
      open = true;
      target = context.target;
      descriptor = context.descriptor;
      image = new Uint8Array(target.capacity).fill(fillByte);
      state = new Uint8Array(Math.ceil(target.capacity / 4));
      imageEnd = undefined;
      firstImageAddress = undefined;
      generation = undefined;
      materialized = undefined;
      failure = undefined;
      return 0;
    },
    image(operation) {
      if (!open) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "IMAGE requires an open generation",
        );
      }
      if (operation.bank !== 0) {
        return reject(
          ATOM_HOST_SINK_STATUS.BANK,
          "bank",
          "native Atom output is flat bank zero",
        );
      }
      if (!inTarget(target, operation.address, operation.bytes.length)) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "image-range",
          "IMAGE lies outside the target range",
        );
      }
      if (imageEnd !== undefined && operation.address < imageEnd) {
        return reject(
          ATOM_HOST_SINK_STATUS.IMAGE_ORDER,
          "image-order",
          "IMAGE records descend or overlap",
        );
      }
      const offset = operation.address - target.start;
      image.set(operation.bytes, offset);
      for (let index = 0; index < operation.bytes.length; index += 1) {
        const slot = offset + index;
        const shift = (slot & 3) << 1;
        const byteIndex = slot >>> 2;
        state[byteIndex] = (state[byteIndex] & ~(3 << shift)) | (1 << shift);
      }
      imageEnd = operation.address + operation.bytes.length;
      firstImageAddress ??= operation.address;
      return 0;
    },
    patch(operation) {
      if (!open) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "PATCH requires an open generation",
        );
      }
      if (operation.bank !== 0) {
        return reject(
          ATOM_HOST_SINK_STATUS.BANK,
          "bank",
          "native Atom output is flat bank zero",
        );
      }
      if (!inTarget(target, operation.address, operation.bytes.length)) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "patch-range",
          "PATCH lies outside the target range",
        );
      }
      const offset = operation.address - target.start;
      for (let index = 0; index < operation.bytes.length; index += 1) {
        const slot = offset + index;
        const shift = (slot & 3) << 1;
        if (((state[slot >>> 2] >>> shift) & 3) !== 1) {
          return reject(
            ATOM_HOST_SINK_STATUS.PATCH_TARGET,
            "patch-target",
            "PATCH does not name one unpatched IMAGE byte",
          );
        }
      }
      image.set(operation.bytes, offset);
      for (let index = 0; index < operation.bytes.length; index += 1) {
        const slot = offset + index;
        const shift = (slot & 3) << 1;
        const byteIndex = slot >>> 2;
        state[byteIndex] = (state[byteIndex] & ~(3 << shift)) | (2 << shift);
      }
      return 0;
    },
    commit(context) {
      if (!open) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "COMMIT requires an open generation",
        );
      }
      if (
        context.descriptor !== descriptor ||
        context.remaining < 0 ||
        context.remaining > target.capacity
      ) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "commit-state",
          "COMMIT state differs from the open generation",
        );
      }
      const targetEnd = target.start + target.capacity;
      if (
        context.finalCursor < target.start ||
        context.finalCursor > targetEnd ||
        context.highWater < target.start ||
        context.highWater > targetEnd
      ) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "commit-range",
          "logical output extent lies outside the target range",
        );
      }
      const end = Math.max(
        context.finalCursor,
        context.highWater,
        imageEnd ?? target.start,
      );
      generation = Object.freeze({
        target,
        finalCursor: context.finalCursor,
        highWater: context.highWater,
        remaining: context.remaining,
        firstImageAddress,
      });
      materialized = Object.freeze({
        base: target.start,
        end,
        bytes: image.subarray(0, end - target.start),
      });
      open = false;
      state = new Uint8Array();
      return 0;
    },
    abort() {
      if (!open) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "ABORT requires an open generation",
        );
      }
      open = false;
      image = new Uint8Array();
      state = new Uint8Array();
      generation = undefined;
      materialized = undefined;
      return 0;
    },
    snapshot() {
      return Object.freeze({
        open,
        generation,
        materialized,
        failure,
      });
    },
  };
  return Object.freeze(sink);
}
