import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// core.asm owns the core's link order for every platform build.
const includePattern = /^[ \t]*%INCLUDE[ \t]+"([A-Za-z0-9_]{1,8}\.asm)"[ \t]*(?:;[^\r\n]*)?$/gmi;
export const NATIVE_CORE_MODULES = Object.freeze(
  [...readFileSync(new URL("../../z80/core.asm", import.meta.url), "utf8")
    .matchAll(includePattern)].map((match) => match[1]),
);
assert.ok(NATIVE_CORE_MODULES.length > 0, "core.asm must include the core modules");

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

const sourceReadContract = ";@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY";

export async function readNativeCoreModules(nativeRoot) {
  return new Map(await Promise.all(NATIVE_CORE_MODULES.map(async (name) => [
    name,
    await readAssemblyModule(nativeRoot, name),
  ])));
}

// The core sets no origin. A platform build places its own before the core.
export function setNativeCoreOrigin(modules, originLine) {
  const result = new Map(modules);
  const first = NATIVE_CORE_MODULES[0];
  result.set(first, `${originLine}\n${result.get(first)}`);
  return result;
}

// host.asm supplies the memory-backed tkRead. A platform build that omits
// it binds the core's source service to its own reader.
export function nativeSourceRead(target) {
  assert.match(target, /^[A-Za-z_.$?@][A-Za-z0-9_.$?@]*$/, "invalid source-read target label");
  return `${sourceReadContract}\ntkRead: ; Read a source byte through the linked platform adapter.\nJP ${target} ; Return directly from the adapter to the tokenizer.\n`;
}

export function joinNativeCoreModules(modules) {
  return NATIVE_CORE_MODULES
    .map((name) => {
      assert.ok(modules.has(name), `native source omitted ${name}`);
      return modules.get(name);
    })
    .join("\n");
}
