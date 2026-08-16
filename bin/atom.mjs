#!/usr/bin/env node

import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  assembleAtomProject,
  publishAtomArtifacts,
  renderAtomArtifacts,
} from "../src/host/index.mjs";
import { parseAtomPreprocessorValue } from "../src/host/atom/literals.mjs";

const usage = `Usage: atom [options] <entry.asm>
       atom --self-host [options]

Options:
  -o, --output <dir>       Artifact bundle (default: build/<entry>.atom)
  --root <dir>             Project root (default: current directory)
  --origin <number>        Initial target address (default: 0)
  --capacity <number>      Target byte capacity (default: to $FFFF)
  --entry <number>         Published entry address (default: origin)
  --fill <number>          Gap and reservation fill byte (default: 0)
  --self-host              Assemble the checked Atom source shipped in this package
  -DNAME[=value]           Host preprocessor definition (default value: 1)
  -h, --help               Show this help

Numbers accept decimal, $FFFF, %1010, 0FFFFH, and 1010B spellings.
`;

function optionValue(arguments_, index, name) {
  const value = arguments_[index + 1];
  if (value === undefined) throw new Error(`${name} requires a value`);
  return value;
}

function numberValue(text, name) {
  try {
    return parseAtomPreprocessorValue(text);
  } catch {
    throw new Error(`${name} has an invalid 16-bit number: ${text}`);
  }
}

function parseArguments(arguments_) {
  const options = { definitions: Object.create(null) };
  let entry;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "-h" || argument === "--help") return { help: true };
    if (argument === "-o" || argument === "--output") options.output = optionValue(arguments_, index++, argument);
    else if (argument === "--root") options.root = optionValue(arguments_, index++, argument);
    else if (argument === "--origin") options.origin = numberValue(optionValue(arguments_, index++, argument), argument);
    else if (argument === "--capacity") options.capacity = numberValue(optionValue(arguments_, index++, argument), argument);
    else if (argument === "--entry") options.entryAddress = numberValue(optionValue(arguments_, index++, argument), argument);
    else if (argument === "--fill") options.fill = numberValue(optionValue(arguments_, index++, argument), argument);
    else if (argument === "--self-host") options.selfHost = true;
    else if (argument.startsWith("-D")) {
      const definition = argument === "-D" ? optionValue(arguments_, index++, argument) : argument.slice(2);
      const separator = definition.indexOf("=");
      const name = separator < 0 ? definition : definition.slice(0, separator);
      const value = separator < 0 ? "1" : definition.slice(separator + 1);
      if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) throw new Error(`invalid definition name: ${name}`);
      options.definitions[name] = numberValue(value, `definition ${name}`);
    } else if (argument.startsWith("-")) throw new Error(`unknown option: ${argument}`);
    else if (entry === undefined) entry = argument;
    else throw new Error(`unexpected argument: ${argument}`);
  }
  if (options.selfHost && entry !== undefined) throw new Error("--self-host does not accept an entry source");
  if (entry === undefined && !options.selfHost) throw new Error("entry source is required");
  if (options.selfHost) entry = "atom.asm";
  return { ...options, entry };
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`atom: ${error.message}\n\n${usage}`);
    return 2;
  }
  if (options.help) {
    process.stdout.write(usage);
    return 0;
  }
  const selfHostBuildOptions = ["root", "origin", "capacity", "entryAddress", "fill"];
  if (
    options.selfHost &&
    (selfHostBuildOptions.some((name) => options[name] !== undefined) || Object.keys(options.definitions).length !== 0)
  ) {
    process.stderr.write("atom: --self-host accepts only -o/--output\n");
    return 2;
  }
  const root = options.selfHost
    ? fileURLToPath(new URL("../self-host", import.meta.url))
    : path.resolve(options.root ?? process.cwd());
  const origin = options.origin ?? 0;
  const capacity = options.capacity ?? (options.selfHost ? 0x4000 : 0xffff - origin);
  if ((options.fill ?? 0) > 0xff) {
    process.stderr.write("atom: --fill must be a byte from 0 through 255\n");
    return 2;
  }
  const stem = path.basename(options.entry, path.extname(options.entry));
  const destination = path.resolve(options.output ?? path.join(
    options.selfHost ? process.cwd() : root,
    "build",
    `${stem}.atom`,
  ));
  try {
    const result = await assembleAtomProject({
      root,
      entry: options.entry,
      definitions: options.definitions,
      target: { start: origin, capacity },
    });
    const artifacts = renderAtomArtifacts(result, {
      fill: options.fill ?? 0,
      entryAddress: options.entryAddress ?? origin,
    });
    const publication = await publishAtomArtifacts(destination, stem, artifacts);
    process.stdout.write(`Atom assembled ${result.project.parts.length} part(s), ${artifacts.bin.length} byte(s).\n`);
    process.stdout.write(`Artifacts: ${publication.current}\n`);
    return 0;
  } catch (error) {
    const location = error?.diagnostic;
    const prefix = location === undefined
      ? "atom"
      : `${location.logicalIdentity}:${location.line}:${location.column}`;
    process.stderr.write(`${prefix}: ${error.message}\n`);
    return 1;
  }
}

process.exitCode = await main();
