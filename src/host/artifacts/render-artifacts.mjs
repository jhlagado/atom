import { materializeAtomGeneration } from "../native-atom-runner.mjs";
import { writeAtomNobj } from "./atom-nobj.mjs";

const decoder = new TextDecoder("utf-8", { fatal: false });

const hex4 = (value) => value.toString(16).toUpperCase().padStart(4, "0");
const hex2 = (value) => value.toString(16).toUpperCase().padStart(2, "0");

function intelRecord(address, type, bytes) {
  const values = [bytes.length, address >>> 8, address & 0xff, type, ...bytes];
  const checksum = (-values.reduce((sum, byte) => sum + byte, 0)) & 0xff;
  return `:${values.map(hex2).join("")}${hex2(checksum)}`;
}

export function writeIntelHex(materialized, { lineEnding = "\n" } = {}) {
  const lines = [];
  for (let offset = 0; offset < materialized.bytes.length; offset += 16) {
    lines.push(intelRecord(materialized.base + offset, 0, [...materialized.bytes.slice(offset, offset + 16)]));
  }
  lines.push(":00000001FF");
  return `${lines.join(lineEnding)}${lineEnding}`;
}

export function writeAtomCom(materialized, { entryAddress = 0x100 } = {}) {
  if (materialized.base !== 0x100 || entryAddress !== 0x100) {
    throw new RangeError("COM output requires load and entry address $0100");
  }
  if (materialized.end > 0x10000 || materialized.bytes.length > 0xff00) {
    throw new RangeError("COM output exceeds the 65,280-byte CP/M address range");
  }
  return materialized.bytes;
}

function sourceLines(project) {
  return project.parts.flatMap((part) => {
    const text = decoder.decode(part.originalBytes);
    const lines = text.split(/\r\n|\n|\r/);
    if (lines.at(-1) === "") lines.pop();
    return lines.map((source, index) => ({
      part,
      source,
      line: index + 1,
      key: `${part.ordinal}:${index + 1}`,
    }));
  });
}

function finalByteMap(generation, fill) {
  const bytes = new Map();
  for (const operation of generation.images) {
    for (let index = 0; index < operation.bytes.length; index += 1) {
      bytes.set(operation.address + index, operation.bytes[index]);
    }
  }
  for (const operation of generation.patches) {
    for (let index = 0; index < operation.bytes.length; index += 1) {
      bytes.set(operation.address + index, operation.bytes[index]);
    }
  }
  for (const event of generation.layout ?? []) {
    if (event.kind !== "reserve") continue;
    for (let index = 0; index < event.count; index += 1) {
      if (!bytes.has(event.address + index)) bytes.set(event.address + index, fill);
    }
  }
  return bytes;
}

function sourceLine(project, source) {
  const part = project.parts[source?.ordinal];
  if (part === undefined || source === undefined) return "";
  return decoder.decode(part.originalBytes).split(/\r\n|\n|\r/)[source.line - 1] ?? "";
}

function imageKind(project, source) {
  const statement = sourceLine(project, source).replace(
    /^\s*(?:(?:\.[_A-Za-z][_A-Za-z0-9]*|[_A-Za-z][_A-Za-z0-9]*)\s*:\s*)?/,
    "",
  );
  return /^(?:DB|DW|CSTR|PSTR|ISTR|ALIGN|INCBIN)\b/i.test(statement) ? "data" : "code";
}

function sourceRanges(project, generation, fill) {
  const final = finalByteMap(generation, fill);
  const byLine = new Map();
  const add = (source, address, length, kind) => {
    if (source === undefined || length === 0) return;
    const key = `${source.ordinal}:${source.line}`;
    const ranges = byLine.get(key) ?? [];
    const previous = ranges.at(-1);
    if (previous !== undefined && previous.kind === kind && previous.address + previous.length === address) {
      previous.length += length;
    } else {
      ranges.push({ address, length, kind });
    }
    byLine.set(key, ranges);
  };
  for (const operation of generation.images) {
    add(operation.source, operation.address, operation.bytes.length, imageKind(project, operation.source));
  }
  for (const event of generation.layout ?? []) {
    if (event.kind === "reserve") add(event.source, event.address, event.count, "directive");
    if (event.kind === "org") add(event.source, event.address, 0, "directive");
  }
  return { byLine, final };
}

function classifySymbol(symbol, project) {
  const line = sourceLine(project, symbol.source);
  if (line === "") return "unknown";
  return /\bEQU\b/i.test(line) ? "constant" : "label";
}

function uniqueSymbols(generation, project) {
  const found = new Map();
  for (const symbol of generation.symbols ?? []) {
    const source = symbol.source;
    const key = `${symbol.name}\0${source?.ordinal ?? -1}\0${source?.offset ?? -1}\0${symbol.value}`;
    if (!found.has(key)) found.set(key, Object.freeze({ ...symbol, kind: classifySymbol(symbol, project) }));
  }
  return [...found.values()].sort((left, right) =>
    (left.name < right.name ? -1 : left.name > right.name ? 1 : 0) ||
    (left.source?.ordinal ?? 0) - (right.source?.ordinal ?? 0) ||
    (left.source?.offset ?? 0) - (right.source?.offset ?? 0),
  );
}

export function writeAtomListing(project, generation, { fill = 0 } = {}) {
  const { byLine, final } = sourceRanges(project, generation, fill);
  const output = [];
  let listingLine = 0;
  for (const item of sourceLines(project)) {
    const ranges = byLine.get(item.key) ?? [];
    const initialized = ranges.filter(({ kind }) => kind !== "directive");
    const reservation = ranges.find(({ kind }) => kind === "directive");
    const addresses = initialized.flatMap(({ address, length }) => Array.from({ length }, (_, index) => address + index));
    const chunks = [];
    for (let index = 0; index < addresses.length; index += 8) chunks.push(addresses.slice(index, index + 8));
    if (chunks.length === 0) chunks.push(reservation === undefined ? [] : [reservation]);
    for (let index = 0; index < chunks.length; index += 1) {
      const chunk = chunks[index];
      const reserved = chunk.length === 1 && typeof chunk[0] === "object" ? chunk[0] : undefined;
      const gutter = reserved !== undefined
        ? `${hex4(reserved.address)}  <${reserved.length} reserved>`.padEnd(29)
        : chunk.length === 0
        ? "                  "
        : `${hex4(chunk[0])}  ${chunk.map((address) => hex2(final.get(address) ?? fill)).join(" ").padEnd(23)}`;
      const identity = index === 0 ? `${item.part.logicalIdentity}:${item.line}`.padEnd(24) : "".padEnd(24);
      output.push(`${gutter}  ${identity}${index === 0 ? item.source : ""}`.trimEnd());
      listingLine += 1;
    }
  }
  output.push("", "Symbols:");
  for (const symbol of uniqueSymbols(generation, project)) {
    const value = symbol.kind === "constant" ? `=${hex4(symbol.value)}` : hex4(symbol.value);
    const where = symbol.source === undefined ? "" : ` ${symbol.source.logicalIdentity}:${symbol.source.line}`;
    output.push(`${symbol.name.padEnd(12)} ${value}${where}`);
  }
  return `${output.join("\n")}\n`;
}

export function writeAtomD8(
  project,
  generation,
  { entryAddress = generation.target.start, fill = 0, base = generation.target.start } = {},
) {
  const { byLine } = sourceRanges(project, generation, fill);
  const listingLines = new Map();
  let listingCursor = 1;
  for (const item of sourceLines(project)) {
    listingLines.set(item.key, listingCursor);
    const ranges = byLine.get(item.key) ?? [];
    const initializedBytes = ranges
      .filter(({ kind }) => kind !== "directive")
      .reduce((sum, range) => sum + range.length, 0);
    listingCursor += Math.max(1, Math.ceil(initializedBytes / 8));
  }
  const symbols = uniqueSymbols(generation, project).map((symbol) => ({
    name: symbol.name,
    ...(symbol.source === undefined ? {} : {
      identity: `${symbol.source.logicalIdentity}#${symbol.source.offset}:${symbol.name}`,
    }),
    kind: symbol.kind,
    ...(symbol.kind === "constant" ? { value: symbol.value } : { address: symbol.value }),
    ...(symbol.source === undefined ? {} : {
      file: symbol.source.logicalIdentity,
      line: symbol.source.line,
      scope: symbol.name.startsWith(".") ? "local" : "global",
      visibility: symbol.name.startsWith(".") ? "local" : "source",
      sourceUnit: symbol.source.logicalIdentity,
    }),
  }));
  const files = Object.fromEntries(project.parts.map((part) => {
    const fileSymbols = symbols
      .filter(({ file }) => file === part.logicalIdentity)
      .map(({ file: _file, ...symbol }) => symbol);
    const segments = [];
    for (const [key, ranges] of byLine) {
      if (!key.startsWith(`${part.ordinal}:`)) continue;
      const line = Number(key.slice(key.indexOf(":") + 1));
      for (const range of ranges) segments.push({
        start: range.address,
        end: range.address + range.length,
        lstLine: listingLines.get(key),
        line,
        column: 1,
        kind: range.kind,
        confidence: "high",
      });
    }
    segments.sort((left, right) => left.start - right.start || left.line - right.line);
    return [part.logicalIdentity, {
      ...(fileSymbols.length === 0 ? {} : { symbols: fileSymbols }),
      ...(segments.length === 0 ? {} : { segments }),
    }];
  }));
  const topSegments = generation.highWater > base
    ? [{ start: base, end: generation.highWater }]
    : [{ start: base, end: base }];
  return {
    format: "d8-debug-map",
    version: 1,
    arch: "z80",
    addressWidth: 16,
    endianness: "little",
    files,
    segments: topSegments,
    fileList: project.parts.map(({ logicalIdentity }) => logicalIdentity),
    symbols,
    generator: {
      name: "atom",
      tool: "atom",
      version: "0.1.0",
      inputs: { entry: project.parts.at(-1)?.logicalIdentity },
      entryAddress,
    },
  };
}

export function renderAtomArtifacts(result, options = {}) {
  const fill = options.fill ?? 0;
  const entryAddress = options.entryAddress ?? result.generation.target.start;
  const materialized = materializeAtomGeneration(result.generation, { fill, base: options.base });
  const d8 = writeAtomD8(result.project, result.generation, { fill, entryAddress, base: materialized.base });
  return Object.freeze({
    nobj: writeAtomNobj(result.generation, result.project, { fill, entryAddress }),
    bin: materialized.bytes,
    hex: writeIntelHex(materialized, { lineEnding: options.lineEnding ?? "\n" }),
    listing: writeAtomListing(result.project, result.generation, { fill }),
    d8,
    d8Text: `${JSON.stringify(d8, null, 2)}\n`,
  });
}
