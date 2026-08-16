import { SourcePackagerError } from "./errors.mjs";

const encoder = new TextEncoder();
const decoder = new TextDecoder("ascii");

export const SOURCE_PLAN_WIRE_LIMITS = Object.freeze({
  maxParts: 255,
  maxPathBytes: 255,
  maxBank: 255,
});

function fail(code, message) {
  throw new SourcePackagerError("plan", code, message);
}

function normalizeLimit(value, name, minimum) {
  if (!Number.isInteger(value) || value < minimum || value > 255) {
    fail("invalid-limit", `${name} must be an integer from ${minimum} through 255`);
  }
  return value;
}

function normalizeLimits(limits = SOURCE_PLAN_WIRE_LIMITS) {
  return Object.freeze({
    maxParts: normalizeLimit(limits.maxParts ?? 255, "maxParts", 1),
    maxPathBytes: normalizeLimit(limits.maxPathBytes ?? 255, "maxPathBytes", 1),
    maxBank: normalizeLimit(limits.maxBank ?? 255, "maxBank", 0),
  });
}

function parseCount(text) {
  if (!/^[1-9][0-9]{0,2}$/.test(text)) fail("invalid-count", "invalid SP1 part count");
  const count = Number(text);
  if (count > 255) fail("invalid-count", "SP1 part count exceeds 255");
  return count;
}

function parseBank(text, limits) {
  if (!/^(?:0|[1-9][0-9]{0,2})$/.test(text)) fail("invalid-bank", "invalid SP1 bank");
  const bank = Number(text);
  if (bank > 255) fail("invalid-bank", "SP1 bank exceeds 255");
  if (bank > limits.maxBank) fail("bank-capacity", "SP1 bank exceeds the host limit");
  return bank;
}

function validatePath(logicalIdentity, limits) {
  if (
    typeof logicalIdentity !== "string" ||
    logicalIdentity.length === 0 ||
    logicalIdentity.length > 255 ||
    !/^[A-Za-z0-9._/-]+$/.test(logicalIdentity)
  ) {
    fail("invalid-path", "invalid SP1 logical path");
  }

  const components = logicalIdentity.split("/");
  if (components.some((component) => component === "" || component === "." || component === "..")) {
    fail("invalid-path", "invalid SP1 logical path component");
  }
  if (logicalIdentity.length > limits.maxPathBytes) {
    fail("path-capacity", "SP1 logical path exceeds the host limit");
  }
  return logicalIdentity;
}

function decodeLines(bytes) {
  if (!(bytes instanceof Uint8Array)) fail("invalid-plan", "SP1 input must be bytes");
  for (const byte of bytes) {
    if (byte > 0x7f) fail("non-ascii", "SP1 contains a non-ASCII byte");
  }
  for (let index = 0; index < bytes.length; index += 1) {
    if (bytes[index] === 0x0d && bytes[index + 1] !== 0x0a) {
      fail("invalid-newline", "SP1 contains a lone carriage return");
    }
  }

  const normalized = decoder.decode(bytes).replaceAll("\r\n", "\n");
  const lines = normalized.split("\n");
  if (lines.at(-1) === "") lines.pop();
  return lines;
}

function validateRecord(record, limits) {
  if (record === null || typeof record !== "object") fail("invalid-record", "invalid SP1 record");
  const bank = record.bank;
  if (!Number.isInteger(bank) || bank < 0 || bank > 255) {
    fail("invalid-bank", "invalid SP1 bank");
  }
  if (bank > limits.maxBank) fail("bank-capacity", "SP1 bank exceeds the host limit");
  return Object.freeze({
    bank,
    logicalIdentity: validatePath(record.logicalIdentity, limits),
  });
}

export function parseSourcePlan(bytes, requestedLimits) {
  const limits = normalizeLimits(requestedLimits);
  const lines = decodeLines(bytes);
  const header = lines[0];
  if (typeof header !== "string" || !header.startsWith("SP1 ")) {
    fail("invalid-header", "missing SP1 header");
  }

  const count = parseCount(header.slice(4));
  if (count > limits.maxParts) fail("part-capacity", "SP1 part count exceeds the host limit");

  const records = [];
  for (let index = 0; index < count; index += 1) {
    const line = lines[index + 1];
    if (line === undefined || line === "END") fail("count-mismatch", "SP1 record count is too small");
    const match = /^P ([^ ]+) (.*)$/.exec(line);
    if (match === null) fail("invalid-record", "invalid SP1 part record");
    records.push(Object.freeze({
      bank: parseBank(match[1], limits),
      logicalIdentity: validatePath(match[2], limits),
    }));
  }

  const endIndex = count + 1;
  const end = lines[endIndex];
  if (end !== "END") {
    if (typeof end === "string" && end.startsWith("P ")) {
      fail("count-mismatch", "SP1 record count is too large");
    }
    fail("missing-end", "SP1 END terminator is missing");
  }
  if (lines.length !== endIndex + 1) fail("trailing-data", "SP1 has trailing data");

  return Object.freeze({ records: Object.freeze(records) });
}

export function serializeSourcePlan(plan, requestedLimits) {
  const limits = normalizeLimits(requestedLimits);
  if (plan === null || typeof plan !== "object" || !Array.isArray(plan.records)) {
    fail("invalid-plan", "SP1 plan must contain a records array");
  }
  const count = plan.records.length;
  if (count < 1 || count > 255) fail("invalid-count", "invalid SP1 part count");
  if (count > limits.maxParts) fail("part-capacity", "SP1 part count exceeds the host limit");

  const records = plan.records.map((record) => validateRecord(record, limits));
  const text = [
    `SP1 ${records.length}`,
    ...records.map(({ bank, logicalIdentity }) => `P ${bank} ${logicalIdentity}`),
    "END",
    "",
  ].join("\n");
  const bytes = encoder.encode(text);
  parseSourcePlan(bytes, limits);
  return bytes;
}
