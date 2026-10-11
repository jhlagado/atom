import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// The assembly entry point owns link order for both native and platform builds.
const includePattern = /^[ \t]*%INCLUDE[ \t]+"([A-Za-z0-9_]{1,8}\.asm)"[ \t]*(?:;[^\r\n]*)?$/gmi;
export const NATIVE_CORE_MODULES = Object.freeze(
  [...readFileSync(new URL("../../z80/atom.asm", import.meta.url), "utf8")
    .matchAll(includePattern)].map((match) => match[1]),
);
assert.ok(NATIVE_CORE_MODULES.length > 0, "native entry point must include its modules");

// Platform builders need flat text before replacing service routines and link
// markers. Expand the same small module manifests that ATOM reads itself.
export async function readAssemblyModule(nativeRoot, name, parents = []) {
  assert.match(name, /^[A-Za-z0-9_]{1,8}\.asm$/i, "assembly module must have an 8.3 filename");
  assert.ok(!parents.includes(name), `assembly include cycle: ${[...parents, name].join(" -> ")}`);
  const source = await readFile(join(nativeRoot, name), "utf8");
  const includes = [...source.matchAll(includePattern)];
  const fragments = await Promise.all(includes.map((match) =>
    readAssemblyModule(nativeRoot, match[1], [...parents, name])));
  let result = "";
  let position = 0;
  for (const [index, match] of includes.entries()) {
    result += source.slice(position, match.index) + fragments[index];
    position = match.index + match[0].length;
  }
  return result + source.slice(position);
}

const sourceReadBegin = ";@@ATOM_SOURCE_READ_BEGIN@@";
const sourceReadEnd = ";@@ATOM_SOURCE_READ_END@@";
const sourceReadContract = ";@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY";

export async function readNativeCoreModules(nativeRoot) {
  return new Map(await Promise.all(NATIVE_CORE_MODULES.map(async (name) => [
    name,
    await readAssemblyModule(nativeRoot, name),
  ])));
}

export function setNativeCoreOrigin(modules, originLine) {
  const result = new Map(modules);
  const encoder = result.get("encoder.asm");
  // Match the directive independently of its explanatory source comment.
  const originPattern = /^[ \t]*ORG[ \t]+0[ \t]*(?:;[^\r\n]*)?$/gm;
  const defaultOrigins = [...encoder.matchAll(originPattern)];
  assert.equal(defaultOrigins.length, 1, "native encoder must contain one default origin");
  const indent = defaultOrigins[0][0].match(/^[ \t]*/)[0];
  const replacement = originLine
    .split("\n")
    .map((line) => `${indent}${line.trimStart()}`)
    .join("\n");
  result.set("encoder.asm", encoder.replace(originPattern, replacement));
  return result;
}

export function replaceNativeSourceRead(modules, target) {
  assert.match(target, /^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*$/, "invalid source-read target label");
  const result = new Map(modules);
  const tokenizer = result.get("token.asm");
  assert.equal(tokenizer.split(sourceReadBegin).length, 2, "native tokenizer must contain one source-read start marker");
  assert.equal(tokenizer.split(sourceReadEnd).length, 2, "native tokenizer must contain one source-read end marker");
  const start = tokenizer.indexOf(sourceReadBegin) + sourceReadBegin.length;
  const end = tokenizer.indexOf(sourceReadEnd, start);
  assert.ok(end >= start, "native tokenizer source-read markers are out of order");
  const replacement = `\n${sourceReadContract}\nTK_SREAD: ; Read a source byte through the linked platform adapter.\nJP ${target} ; Return directly from the adapter to the tokenizer.\n`;
  result.set("token.asm", `${tokenizer.slice(0, start)}${replacement}${tokenizer.slice(end)}`);
  return result;
}

export function joinNativeCoreModules(modules, { includeHostServices = true } = {}) {
  return NATIVE_CORE_MODULES
    .filter((name) => includeHostServices || name !== "host.asm")
    .map((name) => {
      assert.ok(modules.has(name), `native source omitted ${name}`);
      return modules.get(name);
    })
    .join("\n");
}
