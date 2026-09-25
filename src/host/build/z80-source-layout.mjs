import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const NATIVE_CORE_MODULES = Object.freeze([
  "encoder.asm",
  "symbols.asm",
  "token.asm",
  "tokdisp.asm",
  "expr.asm",
  "exprmath.asm",
  "patch.asm",
  "parser.asm",
  "forms.asm",
  "output.asm",
  "stmts.asm",
  "driver.asm",
  "host.asm",
]);

const sourceReadBegin = ";@@ATOM_SOURCE_READ_BEGIN@@";
const sourceReadEnd = ";@@ATOM_SOURCE_READ_END@@";
const sourceReadContract = ";@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY";

export async function readNativeCoreModules(nativeRoot) {
  return new Map(await Promise.all(NATIVE_CORE_MODULES.map(async (name) => [
    name,
    await readFile(join(nativeRoot, name), "utf8"),
  ])));
}

export function setNativeCoreOrigin(modules, originLine) {
  const result = new Map(modules);
  const encoder = result.get("encoder.asm");
  const defaultOrigins = [...encoder.matchAll(/^[ \t]*ORG[ \t]+0[ \t]*$/gm)];
  assert.equal(defaultOrigins.length, 1, "native encoder must contain one default origin");
  const indent = defaultOrigins[0][0].match(/^[ \t]*/)[0];
  const replacement = originLine
    .split("\n")
    .map((line) => `${indent}${line.trimStart()}`)
    .join("\n");
  result.set("encoder.asm", encoder.replace(/^[ \t]*ORG[ \t]+0[ \t]*$/m, replacement));
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
  const replacement = `\n${sourceReadContract}\nTK_SREAD:\nJP ${target}\n`;
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
