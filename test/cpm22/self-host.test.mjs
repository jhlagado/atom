import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

import {
  assembleResolvedAtomProject,
  materializeAtomGeneration,
} from "../../src/host/index.mjs";
import {
  joinNativeCoreModules,
  readNativeCoreModules,
  setNativeCoreOrigin,
} from "../../src/host/build/z80-source-layout.mjs";
import { prepareCpmAtomSource } from "../../scripts/cpm22-atom-source.mjs";
import { runCpm22Atom } from "../cpm22-support.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

function removeComments(source) {
  return source
    .split(/\r\n|\n|\r/)
    .map((line) => {
      let quote;
      let escaped = false;
      for (let index = 0; index < line.length; index += 1) {
        const character = line[index];
        if (escaped) {
          escaped = false;
          continue;
        }
        if (quote !== undefined) {
          if (character === "\\") escaped = true;
          else if (character === quote) quote = undefined;
          continue;
        }
        if (character === "'" || character === '"') quote = character;
        else if (character === ";") return line.slice(0, index).trimEnd();
      }
      return line.trimEnd();
    })
    .filter((line) => line.trim().length > 0)
    .join("\n");
}

test("the CP/M resident Atom assembles its core byte-identically", async () => {
  const modules = setNativeCoreOrigin(
    await readNativeCoreModules(join(repositoryRoot, "src", "z80")),
    "ORG $0100",
  );
  const compactSource = removeComments(joinNativeCoreModules(modules));
  const prepared = prepareCpmAtomSource(compactSource, "cpm-self-host");
  assert.ok(prepared.project.parts.length > 0);
  assert.ok(prepared.project.parts.length < 0xff);

  const partNames = prepared.project.parts.map((_part, ordinal) => {
    const suffix = ordinal.toString(36).toUpperCase().padStart(2, "0");
    return `S${suffix}.ASM`;
  });
  const source = Buffer.from(
    `${partNames.map((name) => `%INCLUDE "${name}"`).join("\r\n")}\r\n`,
    "ascii",
  );
  const files = prepared.project.parts.map((part, ordinal) => [
    partNames[ordinal],
    Buffer.from(part.compilerBytes),
  ]);

  const expectedAssembly = await assembleResolvedAtomProject(prepared.project, {
    target: { start: 0x100, capacity: 0xff00 },
  });
  const expected = materializeAtomGeneration(expectedAssembly.generation);
  const result = await runCpm22Atom(source, undefined, {
    sourceName: "BUILD.ASM",
    outputName: "CORE.BIN",
    command: "ATOM BUILD.ASM CORE.BIN",
    files,
    freshDisk: true,
    maximumSteps: 600_000_000,
  });

  assert.match(result.atomTranscript, /CORE\.BIN written/);
  assert.equal(result.returnA, 0);
  assert.ok(result.outputFile);
  assert.deepEqual(
    result.outputFile.bytes.subarray(0, expected.bytes.length),
    expected.bytes,
  );
  assert.equal(result.outputFile.records, Math.ceil(expected.bytes.length / 128));
});
