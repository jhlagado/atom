import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

const dependencies = [
  {
    name: "@jhlagado/azm",
    minimum: [0, 3, 9],
    upperExclusive: [0, 4, 0],
  },
  {
    name: "@jhlagado/debug80-runtime",
    minimum: [0, 3, 0],
    upperExclusive: [0, 4, 0],
  },
  {
    name: "@jhlagado/z80-tool-services",
    minimum: [0, 1, 0],
    upperExclusive: [0, 2, 0],
  },
];

const compare = (left, right) => {
  for (let index = 0; index < 3; index += 1) {
    const difference = left[index] - right[index];
    if (difference !== 0) return difference;
  }
  return 0;
};

const parseVersion = (name, version) => {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(version);
  assert.ok(match, `${name} has an invalid package version: ${version}`);
  return match.slice(1).map(Number);
};

const resolved = [];
for (const dependency of dependencies) {
  const manifest = require.resolve(`${dependency.name}/package.json`);
  const metadata = JSON.parse(await readFile(manifest, "utf8"));
  const version = parseVersion(dependency.name, metadata.version);
  assert.ok(
    compare(version, dependency.minimum) >= 0 &&
      compare(version, dependency.upperExclusive) < 0,
    `${dependency.name} ${metadata.version} is outside Atom's supported release range`,
  );
  resolved.push({ name: dependency.name, version: metadata.version, manifest });
}

console.log(JSON.stringify({ dependencies: resolved }, null, 2));
