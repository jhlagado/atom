#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  readCliOptionValue,
  splitPositiveOutputArguments,
  validatePositiveOutputSelections,
} from "@jhlagado/z80-tool-services";

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
  -o, --output <file>      Output file; may be repeated
  -t, --target <name>      Target profile: generic or cpm22
  -DNAME[=value]           Host preprocessor definition (default value: 1)
  -h, --help               Show this help
  -V, --version            Show the Atom version

Output suffixes: .bin .hex .com .nobj .lst .d8.json
With no output, Atom writes build/<input>.bin.
`;

const ATOM_OUTPUT_FORMATS = Object.freeze([
  { format: "d8", suffix: ".d8.json" },
  { format: "nobj", suffix: ".nobj" },
  { format: "bin", suffix: ".bin" },
  { format: "hex", suffix: ".hex" },
  { format: "com", suffix: ".com" },
  { format: "lst", suffix: ".lst" },
]);

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
  const options = { definitions: Object.create(null), optionOutputs: [], positional: [] };
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "-h" || argument === "--help") return { help: true };
    if (argument === "-V" || argument === "--version") return { version: true };
    if (argument === "-p" || argument === "--project") options.project = readCliOptionValue(arguments_, index++, argument);
    else if (argument === "-o" || argument === "--output") options.optionOutputs.push(readCliOptionValue(arguments_, index++, argument));
    else if (argument === "-t" || argument === "--target") options.target = readCliOptionValue(arguments_, index++, argument);
    else if (argument === "-D") addDefinition(options.definitions, readCliOptionValue(arguments_, index++, argument));
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

function targetProfileForOutputs(requestedTarget, outputs) {
  if (requestedTarget === undefined && outputs.some(({ format }) => format === "com")) {
    return targetProfile("cpm22");
  }
  return targetProfile(requestedTarget);
}

function validateOutputs(filenames, baseDirectory) {
  return validatePositiveOutputSelections({
    filenames,
    formats: ATOM_OUTPUT_FORMATS,
    baseDirectory,
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
    const split = splitPositiveOutputArguments({
      positionals: options.positional,
      optionOutputs: options.optionOutputs,
    });
    if (options.project !== undefined || options.target !== undefined || Object.keys(options.definitions).length !== 0) {
      throw new Error("self-host does not accept project, target, or definition options");
    }
    return {
      root: fileURLToPath(new URL("../native", import.meta.url)),
      entry: "atom.asm",
      target: Object.freeze({ name: "self-host", start: 0, capacity: 0x4000, entryAddress: 0 }),
      definitions: Object.create(null),
      outputs: validateOutputs(
        split.outputPaths.length === 0 ? ["build/atom.bin"] : split.outputPaths,
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
    const split = splitPositiveOutputArguments({
      positionals: ["project", ...options.positional],
      optionOutputs: options.optionOutputs,
    });
    const outputNames = split.outputPaths.length === 0 ? (project.outputs ?? []) : split.outputPaths;
    if (!Array.isArray(outputNames) || outputNames.some((item) => typeof item !== "string")) {
      throw new Error("project outputs must be an array of paths");
    }
    const defaults = outputNames.length === 0
      ? [`build/${path.basename(project.entry, path.extname(project.entry))}.bin`]
      : outputNames;
    const outputs = validateOutputs(defaults, root);
    return {
      root,
      entry: project.entry,
      assembler: project.assembler,
      target: targetProfileForOutputs(options.target ?? project.target, outputs),
      definitions: { ...projectDefinitions(project.definitions), ...options.definitions },
      outputs,
    };
  }

  if (options.positional.length === 0) throw new Error("input source is required");
  const split = splitPositiveOutputArguments({
    positionals: options.positional,
    optionOutputs: options.optionOutputs,
  });
  const entry = split.input;
  if (entry === undefined) throw new Error("input source is required");
  const root = process.cwd();
  const stem = path.basename(entry, path.extname(entry));
  const outputs = validateOutputs(split.outputPaths.length === 0 ? [`build/${stem}.bin`] : split.outputPaths, root);
  return {
    root,
    entry,
    target: targetProfileForOutputs(options.target, outputs),
    definitions: options.definitions,
    outputs,
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
      assembler: build.assembler,
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
