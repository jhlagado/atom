import fs from "node:fs/promises";
import path from "node:path";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const encoder = new TextEncoder();

function fail(code, message, details = {}) {
  throw new AtomAssemblyError("self-host-source", code, message, details);
}

function stripComment(line) {
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (quoted && escaped) {
      escaped = false;
    } else if (quoted && character === "\\") {
      escaped = true;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (!quoted && character === ";") {
      return line.slice(0, index);
    }
  }
  return line;
}

function decodeQuotedByte(body) {
  if (body.length === 1 && body.charCodeAt(0) <= 0x7f) return body.charCodeAt(0);
  const escapes = new Map([
    ["0", 0],
    ["n", 0x0a],
    ["r", 0x0d],
    ["t", 0x09],
    ['"', 0x22],
    ["\\", 0x5c],
  ]);
  if (body.length === 2 && body[0] === "\\" && escapes.has(body[1])) return escapes.get(body[1]);
  const hex = /^\\x([0-9A-Fa-f]{2})$/.exec(body);
  return hex === null ? undefined : Number.parseInt(hex[1], 16);
}

function normalizeCharacterLiterals(line) {
  return line.replace(/"((?:\\.|[^"\\])*)"/g, (quoted, body) => {
    const value = decodeQuotedByte(body);
    return value === undefined ? quoted : `$${value.toString(16).toUpperCase().padStart(2, "0")}`;
  });
}

function normalizeDirective(line) {
  let match = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s*:?\s*\.equ\s+(.+)$/i.exec(line);
  if (match !== null) return `${match[1]} EQU ${match[2].trim()}`;
  match = /^\s*([_A-Za-z][_A-Za-z0-9]*\s*:)\s*\.(org|db|dw|ds)\b(.*)$/i.exec(line);
  if (match !== null) return `${match[1]} ${match[2].toUpperCase()}${match[3]}`.trimEnd();
  match = /^\s*\.(org|db|dw|ds)\b(.*)$/i.exec(line);
  if (match !== null) return `${match[1].toUpperCase()}${match[2]}`.trimEnd();
  return line.trim();
}

function shortOrdinal(prefix, ordinal) {
  const digits = ordinal.toString(36).toUpperCase().padStart(7, "0");
  if (digits.length !== 7) fail("symbol-count", "self-host symbol ordinal exceeds seven base-36 digits");
  return `${prefix}${digits}`;
}

function definitionName(line) {
  const label = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s*:/.exec(line);
  if (label !== null) return label[1];
  const equate = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s+EQU\b/i.exec(line);
  return equate?.[1];
}

function buildSymbolMap(lines) {
  const map = new Map();
  let globals = 0;
  let privates = 0;
  for (const line of lines) {
    const name = definitionName(line);
    if (name === undefined) continue;
    const canonical = name.toUpperCase();
    if (map.has(canonical)) continue;
    const isPrivate = name.startsWith("_");
    const short = isPrivate
      ? `_${shortOrdinal("L", privates)}`
      : shortOrdinal("G", globals);
    if (isPrivate) privates += 1;
    else globals += 1;
    map.set(canonical, Object.freeze({ original: name, short, private: isPrivate }));
  }
  return Object.freeze({ map, globals, privates });
}

function replaceIdentifiers(line, symbols) {
  let output = "";
  let index = 0;
  while (index < line.length) {
    const character = line[index];
    if (character === '"') {
      let end = index + 1;
      let escaped = false;
      while (end < line.length) {
        const candidate = line[end];
        if (escaped) escaped = false;
        else if (candidate === "\\") escaped = true;
        else if (candidate === '"') { end += 1; break; }
        end += 1;
      }
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (character >= "0" && character <= "9") {
      let end = index + 1;
      while (end < line.length && /[A-Za-z0-9]/.test(line[end])) end += 1;
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (character === "$" || character === "%") {
      const pattern = character === "$" ? /[0-9A-Fa-f]/ : /[01]/;
      let end = index + 1;
      while (end < line.length && pattern.test(line[end])) end += 1;
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (/[A-Za-z_]/.test(character)) {
      let end = index + 1;
      while (end < line.length && /[A-Za-z0-9_]/.test(line[end])) end += 1;
      const token = line.slice(index, end);
      output += symbols.get(token.toUpperCase())?.short ?? token;
      index = end;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

function chunkLines(lines, maximumBytes) {
  const chunks = [];
  let current = [];
  let currentBytes = 0;
  for (const line of lines) {
    const bytes = encoder.encode(`${line}\n`).length;
    if (bytes > maximumBytes) fail("line-capacity", "one self-host source line exceeds the part capacity");
    if (current.length > 0 && currentBytes + bytes > maximumBytes) {
      chunks.push(current.join("\n") + "\n");
      current = [];
      currentBytes = 0;
    }
    current.push(line);
    currentBytes += bytes;
  }
  if (current.length > 0) chunks.push(current.join("\n") + "\n");
  return chunks;
}

export async function buildSelfHostSource({
  root,
  entry = "atom-host-runtime.asm",
  conditionalDefinitions = {
    AtomExpressionDeferredMode: 1,
    AtomParserExpressionMode: 1,
    AtomParserOutputMode: 1,
    AtomSymbolOutputMode: 1,
    AtomParserStatementMode: 1,
    AtomSymbolStatementMode: 1,
    AtomDriverMode: 1,
  },
  maximumPartBytes = 20 * 1024,
} = {}) {
  if (typeof root !== "string") fail("root", "self-host source root is required");
  if (!Number.isInteger(maximumPartBytes) || maximumPartBytes < 1 || maximumPartBytes > 0x6000) {
    fail("part-capacity", "self-host source part capacity is outside 1..24576");
  }
  const definitions = new Map(Object.entries(conditionalDefinitions).map(([name, value]) => [name.toUpperCase(), value]));
  const visited = new Set();
  const flattened = [];

  async function include(relativeName, importer) {
    const physical = path.resolve(importer === undefined ? root : path.dirname(importer), relativeName);
    const relative = path.relative(path.resolve(root), physical);
    if (relative.startsWith("..") || path.isAbsolute(relative)) fail("root-escape", `self-host include escapes root: ${relativeName}`);
    if (visited.has(physical)) fail("repeated-include", `self-host source repeats include ${relativeName}`);
    visited.add(physical);
    let text;
    try {
      text = await fs.readFile(physical, "utf8");
    } catch (cause) {
      fail("missing-source", `cannot read self-host source ${relativeName}`, { cause });
    }
    const conditionals = [];
    const active = () => conditionals.length === 0 || conditionals.at(-1).active;
    for (const raw of text.split(/\r\n|\n|\r/)) {
      const code = stripComment(raw).trim();
      if (code === "") continue;
      let match = /^\.if\s+([_A-Za-z][_A-Za-z0-9]*)$/i.exec(code);
      if (match !== null) {
        const parentActive = active();
        const value = definitions.get(match[1].toUpperCase());
        if (value === undefined) fail("condition", `unknown self-host condition ${match[1]}`);
        conditionals.push({ parentActive, selected: value !== 0, active: parentActive && value !== 0, elseSeen: false });
        continue;
      }
      if (/^\.else$/i.test(code)) {
        const state = conditionals.at(-1);
        if (state === undefined || state.elseSeen) fail("condition", "invalid self-host .else");
        state.elseSeen = true;
        state.active = state.parentActive && !state.selected;
        continue;
      }
      if (/^\.endif$/i.test(code)) {
        if (conditionals.pop() === undefined) fail("condition", "unmatched self-host .endif");
        continue;
      }
      if (!active()) continue;
      match = /^\.include\s+"([^"]+)"$/i.exec(code);
      if (match !== null) {
        await include(match[1], physical);
        continue;
      }
      if (/^\.(?:routine|expectout)\b/i.test(code) || /^\.end$/i.test(code)) continue;
      const configEquate = /^([_A-Za-z][_A-Za-z0-9]*)\s*:\s*\.equ\b/i.exec(code);
      if (configEquate !== null && definitions.has(configEquate[1].toUpperCase())) continue;
      flattened.push(normalizeDirective(normalizeCharacterLiterals(code)));
    }
    if (conditionals.length !== 0) fail("condition", `unterminated self-host condition in ${relativeName}`);
  }

  await include(entry, undefined);
  const { map, globals, privates } = buildSymbolMap(flattened);
  const translated = flattened.map((line) => replaceIdentifiers(line, map));
  const chunks = chunkLines(translated, maximumPartBytes);
  if (chunks.length > 16) fail("part-count", `self-host source requires ${chunks.length} parts; native limit is 16`);
  const parts = chunks.map((text, ordinal) => {
    const bytes = encoder.encode(text);
    return Object.freeze({
      ordinal,
      bank: 0,
      logicalIdentity: `self/atom-${ordinal.toString().padStart(2, "0")}.asm`,
      originalBytes: bytes,
      compilerBytes: bytes,
    });
  });
  const mapping = Object.freeze([...map.values()].map((value) => value));
  return Object.freeze({
    project: Object.freeze({ parts: Object.freeze(parts) }),
    mapping,
    statistics: Object.freeze({
      inputFiles: visited.size,
      statements: translated.length,
      sourceBytes: parts.reduce((sum, part) => sum + part.compilerBytes.length, 0),
      parts: parts.length,
      globalSymbols: globals,
      privateSymbols: privates,
    }),
  });
}
