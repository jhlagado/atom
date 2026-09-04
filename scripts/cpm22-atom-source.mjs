import assert from "node:assert/strict";
import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
} from "../src/host/index.mjs";

// Private link-time preparation for the CP/M adapter and its shared renderer.
// Names change, not expressions or opcodes. Quoted bytes and comments survive.
const tokens = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|;.*|\$[0-9a-f]+|\b[0-9][a-z0-9]*\b|\.?[a-z_][a-z0-9_]*/gi;
const identifier = /^\.?[a-z_][a-z0-9_]*$/i;

export function prepareCpmAtomSource(source, name = "cpm-link") {
  const lines = source.split(/\r\n|\n|\r/);
  const used = new Set(lines.flatMap((line) => (line.match(tokens) ?? [])
    .filter((token) => identifier.test(token)).map((token) => token.toUpperCase())));
  const aliases = new Map();
  let ordinal = 0;
  for (const original of [...used].sort()) {
    if (original.replace(/^\./, "").length <= 8) continue;
    let short;
    do {
      const suffix = (ordinal++).toString(36).toUpperCase().padStart(7, "0");
      short = `${original.startsWith(".") ? "." : ""}Q${suffix}`;
    } while (used.has(short));
    used.add(short);
    aliases.set(original, short);
  }
  const known = new Set();
  const pending = [];
  const prepared = [];
  const declare = (symbol) => {
    known.add(symbol);
    let progress;
    do {
      progress = false;
      for (let index = 0; index < pending.length; index += 1) {
        const item = pending[index];
        if (!known.has(item.target)) continue;
        prepared.push(item.line);
        known.add(item.symbol);
        pending.splice(index, 1);
        index -= 1;
        progress = true;
      }
    } while (progress);
  };
  for (const sourceLine of lines) {
    const line = sourceLine.replace(tokens, (token) => aliases.get(token.toUpperCase()) ?? token);
    // The shared renderer's pure-name EQU aliases precede their workspace
    // labels. Defer only those aliases; ATOM itself evaluates every expression.
    const alias = /^\s*([a-z_][a-z0-9_]*)\s+EQU\s+([a-z_][a-z0-9_]*)\s*(?:;.*)?$/i.exec(line);
    if (alias !== null && !known.has(alias[2].toUpperCase())) {
      pending.push({ line, symbol: alias[1].toUpperCase(), target: alias[2].toUpperCase() });
      continue;
    }
    prepared.push(line);
    const declaration = /^\s*([a-z_][a-z0-9_]*)(?:\s*:|\s+EQU\b)/i.exec(line);
    if (declaration !== null) declare(declaration[1].toUpperCase());
  }
  assert.equal(pending.length, 0, `unresolved CP/M link aliases: ${pending.map(({ line }) => line).join("; ")}`);
  const parts = [];
  let chunk = "";
  let size = 0;
  const flush = () => {
    if (size === 0) return;
    const bytes = new TextEncoder().encode(chunk);
    parts.push({
      ordinal: parts.length,
      bank: 0,
      logicalIdentity: `${name}-${parts.length}.asm`,
      originalBytes: bytes,
      compilerBytes: bytes,
    });
    chunk = "";
    size = 0;
  };
  for (const line of prepared) {
    const text = `${line}\n`;
    const length = Buffer.byteLength(text);
    assert.ok(length <= 0xffff, "CP/M link source line exceeds one ATOM part");
    if (size + length > 0xffff) flush();
    chunk += text;
    size += length;
  }
  flush();
  return { project: { parts }, aliases };
}

export async function assembleCpmAtomSource(source, { name = "cpm-link", base = 0 } = {}) {
  const { project, aliases } = prepareCpmAtomSource(source, name);
  const result = await assembleResolvedAtomProject(project, {
    target: { start: base, capacity: 0xffff - base },
    maxInstructions: 300_000_000,
    maxCycles: 3_000_000_000,
  }).catch((cause) => {
    const location = cause.diagnostic;
    const part = project.parts[location?.ordinal];
    if (part === undefined) throw cause;
    const line = new TextDecoder().decode(part.originalBytes).split("\n")[location.line - 1];
    throw new Error(`${location.logicalIdentity}:${location.line}: ${cause.message}\n> ${line}`, { cause });
  });
  const reverse = new Map([...aliases].map(([original, short]) => [short, original]));
  const symbols = Object.fromEntries(result.generation.symbols.map(({ name: symbol, value }) => [
    reverse.get(symbol.toUpperCase()) ?? symbol.toUpperCase(), value,
  ]));
  return { bytes: materializeAtomGeneration(result.generation, { base }).bytes, symbols };
}
