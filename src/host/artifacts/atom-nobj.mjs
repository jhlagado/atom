import {
  materializeTargetImage,
  renderTargetBinary,
} from "@jhlagado/z80-tool-services";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const KIND = Object.freeze({ begin: 1, image: 2, patch: 3, map: 4, commit: 5 });
const MAX_DATA_BYTES = 0xfffc;

function fail(code, message) {
  throw new AtomAssemblyError("artifact", code, message);
}

function u16(bytes, value) {
  bytes.push(value & 0xff, value >>> 8);
}

function record(kind, payload) {
  if (payload.length > 0xffff) fail("nobj-record", "NOBJ record payload exceeds 65,535 bytes");
  return Uint8Array.from([kind, payload.length & 0xff, payload.length >>> 8, ...payload]);
}

function concatenate(chunks) {
  const result = new Uint8Array(chunks.reduce((sum, chunk) => sum + chunk.length, 0));
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

export function crc16CcittFalse(bytes) {
  let crc = 0xffff;
  for (const byte of bytes) {
    crc ^= byte << 8;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 0x8000) === 0 ? (crc << 1) & 0xffff : ((crc << 1) ^ 0x1021) & 0xffff;
    }
  }
  return crc;
}

function coalesce(operations) {
  const runs = [];
  for (const operation of operations) {
    const previous = runs.at(-1);
    if (
      previous !== undefined &&
      previous.bank === operation.bank &&
      previous.address + previous.bytes.length === operation.address &&
      previous.bytes.length + operation.bytes.length <= MAX_DATA_BYTES
    ) {
      previous.bytes.push(...operation.bytes);
    } else {
      runs.push({ bank: operation.bank, address: operation.address, bytes: [...operation.bytes] });
    }
  }
  return runs;
}

function imageLike(kind, operation) {
  const payload = [operation.bank];
  u16(payload, operation.address);
  payload.push(...operation.bytes);
  return record(kind, payload);
}

export function writeAtomNobj(generation, project, { fill = 0, entryAddress = generation.target.start } = {}) {
  if (!Number.isInteger(fill) || fill < 0 || fill > 0xff) fail("nobj-option", "NOBJ fill must be a byte");
  if (!Number.isInteger(entryAddress) || entryAddress < 0 || entryAddress > 0xffff) {
    fail("nobj-option", "NOBJ entry address must be a 16-bit address");
  }
  if (generation.target.capacity < 1) fail("nobj-capacity", "NOBJ requires a nonempty target region");
  if (project.parts.length < 1 || project.parts.length > 0xff) fail("nobj-parts", "NOBJ part count is outside 1..255");

  const beginPayload = [0x4e, 0x4f, 0x42, 0x4a, 0, 2, 0];
  u16(beginPayload, 0);
  beginPayload.push(1, fill);
  u16(beginPayload, generation.target.start);
  u16(beginPayload, generation.target.capacity);

  const records = [record(KIND.begin, beginPayload)];
  for (const operation of coalesce(generation.images)) records.push(imageLike(KIND.image, operation));
  for (const operation of coalesce(generation.patches)) records.push(imageLike(KIND.patch, operation));

  const usedLength = generation.highWater - generation.target.start;
  const mapPayload = [0x41, 0, 0];
  u16(mapPayload, entryAddress);
  u16(mapPayload, usedLength);
  u16(mapPayload, generation.finalCursor);
  mapPayload.push(project.parts.length, ...project.parts.map(({ bank }) => bank));
  records.push(record(KIND.map, mapPayload));

  const recordCount = records.length + 1;
  const commitPrefix = [KIND.commit, 7, 0];
  u16(commitPrefix, recordCount);
  commitPrefix.push(0);
  u16(commitPrefix, entryAddress);
  const covered = concatenate([...records, Uint8Array.from(commitPrefix)]);
  const crc = crc16CcittFalse(covered);
  return concatenate([covered, Uint8Array.from([crc & 0xff, crc >>> 8])]);
}

export function parseAtomNobj(bytes) {
  const decoded = decodeAtomNobj(bytes);
  return atomNobjSummary(decoded);
}

function atomNobjSummary(decoded) {
  return Object.freeze({
    version: "0.2",
    recordCount: decoded.records.length,
    imageRecords: decoded.images.length,
    patchRecords: decoded.patches.length,
    entryAddress: decoded.entryAddress,
    crc16: decoded.crc16,
  });
}

function readU16(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function decodeAtomNobj(bytes) {
  if (!(bytes instanceof Uint8Array)) fail("nobj-input", "NOBJ input must be bytes");
  let cursor = 0;
  const records = [];
  while (cursor < bytes.length) {
    if (cursor + 3 > bytes.length) fail("nobj-truncated", "NOBJ ends inside a record header");
    const start = cursor;
    const kind = bytes[cursor];
    const length = bytes[cursor + 1] | (bytes[cursor + 2] << 8);
    cursor += 3;
    if (cursor + length > bytes.length) fail("nobj-truncated", "NOBJ ends inside a record payload");
    records.push({ kind, start, payload: bytes.slice(cursor, cursor + length) });
    cursor += length;
  }
  if (records.length < 3 || records[0].kind !== KIND.begin || records.at(-1).kind !== KIND.commit) {
    fail("nobj-sequence", "NOBJ lacks its BEGIN or terminal COMMIT");
  }
  if (records.slice(0, -1).some(({ kind }) => kind === KIND.commit)) {
    fail("nobj-sequence", "NOBJ COMMIT must be terminal");
  }
  const begin = records[0].payload;
  if (
    begin.length !== 15 ||
    String.fromCharCode(...begin.slice(0, 4)) !== "NOBJ" ||
    begin[4] !== 0 ||
    begin[5] !== 2
  ) {
    fail("nobj-version", "NOBJ is not the Atom flat-image profile 0.2");
  }
  if (begin[6] !== 0 || readU16(begin, 7) !== 0 || begin[9] !== 1) {
    fail("nobj-profile", "NOBJ BEGIN is not the Atom flat bank-zero profile");
  }
  const imageFill = begin[10];
  const imageBase = readU16(begin, 11);
  const imageCapacity = readU16(begin, 13);
  if (imageCapacity === 0 || imageBase + imageCapacity > 0x10000) {
    fail("nobj-capacity", "NOBJ image region is invalid");
  }

  let phase = KIND.image;
  const images = [];
  const patches = [];
  for (const item of records.slice(1, -2)) {
    if (item.kind === KIND.patch) phase = KIND.patch;
    if ((item.kind !== KIND.image && item.kind !== KIND.patch) || item.kind < phase) {
      fail("nobj-sequence", "NOBJ image and patch records are out of order");
    }
    if (item.payload.length < 4) fail("nobj-record", "NOBJ image or patch record is empty");
    const operation = Object.freeze({
      bank: item.payload[0],
      address: readU16(item.payload, 1),
      bytes: item.payload.slice(3),
    });
    if (item.kind === KIND.image) images.push(operation);
    else patches.push(operation);
  }
  const map = records.at(-2);
  if (map.kind !== KIND.map || map.payload[0] !== 0x41) fail("nobj-map", "NOBJ lacks the Atom flat map");
  const partCount = map.payload[9];
  if (
    map.payload.length !== 10 + partCount ||
    map.payload[1] !== 0 ||
    map.payload[2] !== 0 ||
    partCount === 0 ||
    map.payload.slice(10).some((bank) => bank !== 0)
  ) {
    fail("nobj-map", "NOBJ Atom flat map is invalid");
  }
  const entryAddress = readU16(map.payload, 3);
  const usedLength = readU16(map.payload, 5);
  const finalCursor = readU16(map.payload, 7);
  if (
    usedLength > imageCapacity ||
    finalCursor < imageBase ||
    finalCursor > imageBase + imageCapacity
  ) {
    fail("nobj-map", "NOBJ Atom output extent is invalid");
  }
  const commit = records.at(-1).payload;
  if (commit.length !== 7) fail("nobj-commit", "NOBJ COMMIT has the wrong length");
  const count = readU16(commit, 0);
  if (count !== records.length) fail("nobj-commit", "NOBJ COMMIT record count is wrong");
  if (commit[2] !== 0 || readU16(commit, 3) !== entryAddress) {
    fail("nobj-commit", "NOBJ COMMIT entry differs from MAP");
  }
  const storedCrc = readU16(commit, 5);
  if (crc16CcittFalse(bytes.slice(0, bytes.length - 2)) !== storedCrc) {
    fail("nobj-crc", "NOBJ COMMIT CRC is wrong");
  }
  let targetImage;
  try {
    targetImage = materializeTargetImage({
      geometry: {
        bankCount: 1,
        imageBase,
        imageCapacity,
        imageFill,
        entryBank: 0,
        entryAddress,
      },
      banks: [{ usedLength }],
      images,
      patches,
      patchPolicy: "image",
    });
  } catch (cause) {
    fail("nobj-image", cause instanceof Error ? cause.message : "NOBJ image is invalid");
  }
  return Object.freeze({
    records,
    images,
    patches,
    imageBase,
    imageCapacity,
    imageFill,
    usedLength,
    finalCursor,
    entryAddress,
    crc16: storedCrc,
    targetImage,
  });
}

/** Validate and materialize a stored Atom NOBJ generation. */
export function materializeAtomNobj(bytes) {
  const decoded = decodeAtomNobj(bytes);
  const materialized = renderTargetBinary(decoded.targetImage);
  return Object.freeze({
    parsed: atomNobjSummary(decoded),
    targetImage: decoded.targetImage,
    base: decoded.imageBase,
    end: decoded.imageBase + decoded.usedLength,
    bytes: materialized,
  });
}
