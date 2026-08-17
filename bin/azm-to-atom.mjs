#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import { translateAzmSourceToAtom } from "../src/host/index.mjs";

const decoder = new TextDecoder("utf-8", { fatal: true });

const usage = `Usage: azm-to-atom [options] <input.asm>

Options:
  -o, --output <file>   Output .asm file (default: input name with .atom.asm)
  --stdout              Write converted source to standard output
  -h, --help            Show this help
`;

function parseArguments(arguments_) {
  let input;
  let output;
  let stdout = false;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "-h" || argument === "--help") return { help: true };
    if (argument === "--stdout") stdout = true;
    else if (argument === "-o" || argument === "--output") {
      output = arguments_[index += 1];
      if (output === undefined) throw new Error(`${argument} requires a file`);
    } else if (argument.startsWith("-")) throw new Error(`unknown option: ${argument}`);
    else if (input === undefined) input = argument;
    else throw new Error(`unexpected argument: ${argument}`);
  }
  if (input === undefined) throw new Error("input source is required");
  if (stdout && output !== undefined) throw new Error("--stdout cannot be combined with --output");
  return { input, output, stdout };
}

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`azm-to-atom: ${error.message}\n\n${usage}`);
    return 2;
  }
  if (options.help) {
    process.stdout.write(usage);
    return 0;
  }

  const input = path.resolve(options.input);
  const output = options.stdout
    ? undefined
    : path.resolve(options.output ?? path.join(
      path.dirname(input),
      `${path.basename(input, path.extname(input))}.atom.asm`,
    ));
  if (output === input) {
    process.stderr.write("azm-to-atom: input and output paths must differ\n");
    return 2;
  }

  try {
    const source = decoder.decode(await fs.readFile(input));
    const translated = translateAzmSourceToAtom(source, { sourceName: options.input });
    if (output === undefined) {
      process.stdout.write(translated);
    } else {
      await fs.writeFile(output, translated, { flag: "wx" });
      process.stdout.write(`Converted ${options.input} to ${output}.\n`);
    }
    return 0;
  } catch (error) {
    const location = error?.diagnostic;
    const prefix = location === undefined
      ? "azm-to-atom"
      : `${location.logicalIdentity}:${location.line}:${location.column}`;
    process.stderr.write(`${prefix}: ${error.message}\n`);
    return 1;
  }
}

process.exitCode = await main();
