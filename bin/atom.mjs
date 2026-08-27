#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import {
  assembleAtomProject,
  publishAtomOutputFiles,
  renderAtomArtifacts,
  writeAtomCom,
} from "../src/host/index.mjs";
import { parseAtomPreprocessorValue } from "../src/host/atom/literals.mjs";
import { ATOM_VERSION } from "../src/host/package-metadata.mjs";

const usage = `Usage: atom [options] <input.asm> [output...]
       atom --project <project.json> [output...]
       atom self-host [output...]

Options:
  -p, --project <file>     Node project file
  -t, --target <name>      Target profile: generic or cpm22
  -DNAME[=value]           Host preprocessor definition (default value: 1)
  -h, --help               Show this help
  -V, --version            Show the Atom version

Output suffixes: .bin .hex .com .nobj .lst .d8.json
With no output, Atom writes build/<input>.bin.
`;

function optionValue(arguments_, index, name) {
  const value = arguments_[index + 1];
  if (value === undefined) throw new Error(`${name} requires a value`);
  return value;
}

function numberValue(text, name) {
  try {
    return parseAtomPreprocessorValue(String(text));
  } catch {
    throw new Error(`${name} has an invalid 16-bit number: ${text}`);
  }
}

function addDefinition(definitions, definition) {
  const separator = definition.indexOf("=");
  const name = separator < 0 ? definition : definition.slice(0, separator);
  const value = separator < 0 ? "1" : definition.slice(separator + 1);
  if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) throw new Error(`invalid definition name: ${name}`);
  definitions[name] = numberValue(value, `definition ${name}`);
}

function parseArguments(arguments_) {
  const options = { definitions: Object.create(null), positional: [] };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "-h" || argument === "--help") return { help: true };
    if (argument === "-V" || argument === "--version") return { version: true };
    if (argument === "-p" || argument === "--project") options.project = optionValue(arguments_, index++, argument);
    else if (argument === "-t" || argument === "--target") options.target = optionValue(arguments_, index++, argument);
    else if (argument === "-D") addDefinition(options.definitions, optionValue(arguments_, index++, argument));
    else if (argument.startsWith("-D")) addDefinition(options.definitions, argument.slice(2));
    else if (argument.startsWith("-")) throw new Error(`unknown option: ${argument}`);
    else options.positional.push(argument);
  }
  return options;
}

function targetProfile(name) {
  if (name === undefined || name.toLowerCase() === "generic") {
    return Object.freeze({ name: "generic", start: 0, capacity: 0xffff });
  }
  if (name.toLowerCase() === "cpm22") {
    return Object.freeze({ name: "cpm22", start: 0x100, capacity: 0xfeff, entryAddress: 0x100 });
  }
  throw new Error(`unknown target profile: ${name}`);
}

function outputFormat(filename) {
  const lower = filename.toLowerCase();
  if (lower.endsWith(".d8.json")) return "d8";
  for (const format of ["nobj", "bin", "hex", "com", "lst"]) {
    if (lower.endsWith(`.${format}`)) return format;
  }
  throw new Error(`output path has no recognized format suffix: ${filename}`);
}

function validateOutputs(filenames, baseDirectory) {
  const formats = new Set();
  const paths = new Set();
  return filenames.map((filename) => {
    const format = outputFormat(filename);
    if (formats.has(format)) throw new Error(`output format is repeated: ${format}`);
    formats.add(format);
    const selectedPath = path.resolve(baseDirectory, filename);
    const key = process.platform === "win32" ? selectedPath.toLowerCase() : selectedPath;
    if (paths.has(key)) throw new Error(`output path is repeated: ${filename}`);
    paths.add(key);
    return Object.freeze({ format, path: selectedPath });
  });
}

function contentBase(generation) {
  const addresses = generation.images.map(({ address }) => address);
  for (const event of generation.layout ?? []) {
    if (event.kind === "reserve" && event.count !== 0) addresses.push(event.address);
  }
  return addresses.length === 0 ? generation.finalCursor : Math.min(...addresses);
}

function projectDefinitions(value) {
  if (value === undefined) return Object.create(null);
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("project definitions must be an object");
  }
  const definitions = Object.create(null);
  for (const [name, definition] of Object.entries(value)) {
    if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(name)) throw new Error(`invalid project definition name: ${name}`);
    definitions[name] = numberValue(definition, `project definition ${name}`);
  }
  return definitions;
}

async function loadBuild(options) {
  const selfHost = options.positional[0] === "self-host";
  if (selfHost) {
    if (options.project !== undefined || options.target !== undefined || Object.keys(options.definitions).length !== 0) {
      throw new Error("self-host does not accept project, target, or definition options");
    }
    return {
      root: fileURLToPath(new URL("../native", import.meta.url)),
      entry: "atom.asm",
      target: Object.freeze({ name: "self-host", start: 0, capacity: 0x4000, entryAddress: 0 }),
      definitions: Object.create(null),
      outputs: validateOutputs(
        options.positional.slice(1).length === 0 ? ["build/atom.bin"] : options.positional.slice(1),
        process.cwd(),
      ),
    };
  }

  if (options.project !== undefined) {
    if (options.positional.length !== 0 && options.positional[0].toLowerCase().endsWith(".asm")) {
      throw new Error("--project and a positional input are mutually exclusive");
    }
    const projectPath = path.resolve(options.project);
    const root = path.dirname(projectPath);
    const project = JSON.parse(await fs.readFile(projectPath, "utf8"));
    if (typeof project.entry !== "string" || project.entry.length === 0) throw new Error("project entry is required");
    const outputNames = options.positional.length === 0 ? (project.outputs ?? []) : options.positional;
    if (!Array.isArray(outputNames) || outputNames.some((item) => typeof item !== "string")) {
      throw new Error("project outputs must be an array of paths");
    }
    const defaults = outputNames.length === 0
      ? [`build/${path.basename(project.entry, path.extname(project.entry))}.bin`]
      : outputNames;
    return {
      root,
      entry: project.entry,
      target: targetProfile(options.target ?? project.target),
      definitions: { ...projectDefinitions(project.definitions), ...options.definitions },
      outputs: validateOutputs(defaults, root),
    };
  }

  if (options.positional.length === 0) throw new Error("input source is required");
  const [entry, ...requestedOutputs] = options.positional;
  const root = process.cwd();
  const stem = path.basename(entry, path.extname(entry));
  return {
    root,
    entry,
    target: targetProfile(options.target),
    definitions: options.definitions,
    outputs: validateOutputs(requestedOutputs.length === 0 ? [`build/${stem}.bin`] : requestedOutputs, root),
  };
}

function selectedBytes(selection, artifacts, materialized, entryAddress) {
  switch (selection.format) {
    case "bin": return artifacts.bin;
    case "hex": return artifacts.hex;
    case "com": return writeAtomCom(materialized, { entryAddress });
    case "nobj": return artifacts.nobj;
    case "lst": return artifacts.listing;
    case "d8": return artifacts.d8Text;
    default: throw new Error(`unsupported output format: ${selection.format}`);
  }
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(usage);
      return 0;
    }
    if (options.version) {
      process.stdout.write(`${ATOM_VERSION}\n`);
      return 0;
    }
    const build = await loadBuild(options);
    const result = await assembleAtomProject({
      root: build.root,
      entry: build.entry,
      definitions: build.definitions,
      target: { start: build.target.start, capacity: build.target.capacity },
    });
    const base = contentBase(result.generation);
    const requestsCom = build.outputs.some(({ format }) => format === "com");
    const entryAddress = build.target.entryAddress ?? (requestsCom ? 0x100 : base);
    const artifacts = renderAtomArtifacts(result, { base, entryAddress });
    const materialized = Object.freeze({ base, end: base + artifacts.bin.length, bytes: artifacts.bin });
    const committed = await publishAtomOutputFiles(build.outputs.map((selection) => ({
      path: selection.path,
      bytes: selectedBytes(selection, artifacts, materialized, entryAddress),
    })));
    process.stdout.write(`Atom assembled ${result.project.parts.length} part(s), ${artifacts.bin.length} byte(s).\n`);
    for (const filename of committed) process.stdout.write(`${filename}\n`);
    return 0;
  } catch (error) {
    const location = error?.diagnostic;
    const prefix = location === undefined
      ? "atom"
      : `${location.logicalIdentity}:${location.line}:${location.column}`;
    process.stderr.write(`${prefix}: ${error.message}\n`);
    return error?.category === undefined ? 2 : 1;
  }
}

process.exitCode = await main();
