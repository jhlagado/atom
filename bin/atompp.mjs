#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

import { readCliOptionValue } from "@jhlagado/z80-tool-services";

import { expandAtomMacros } from "../src/host/index.mjs";

const decoder = new TextDecoder("utf-8", { fatal: true });

const usage = `Usage: atompp [options] <input.mac>

Expands macros and writes Atom source. Assemble the result with atom.

Options:
  -o, --output <file>   Output .asm file (default: input name with .asm)
  --stdout              Write the expanded source to standard output
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
      output = readCliOptionValue(arguments_, index, argument, "file");
      index += 1;
    } else if (argument.startsWith("-")) throw new Error(`unknown option: ${argument}`);
    else if (input === undefined) input = argument;
    else throw new Error(`unexpected argument: ${argument}`);
  }
  if (input === undefined) throw new Error("input source is required");
  if (stdout && output !== undefined) throw new Error("--stdout cannot be combined with --output");
  return { input, output, stdout };
}

// Name a file as the user would: relative to the working directory, with
// forward slashes, so %LINE markers stay short and portable.
const display = (file) => path.relative(process.cwd(), file).split(path.sep).join("/");

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`atompp: ${error.message}\n\n${usage}`);
    return 2;
  }
  if (options.help) {
    process.stdout.write(usage);
    return 0;
  }

  const input = path.resolve(options.input);
  const output = options.stdout
    ? undefined
    : path.resolve(options.output ?? path.join(path.dirname(input), `${path.basename(input, path.extname(input))}.asm`));
  if (output === input) {
    process.stderr.write("atompp: input and output paths must differ\n");
    return 2;
  }

  try {
    const source = decoder.decode(await fs.readFile(input));
    const expanded = await expandAtomMacros(source, {
      name: display(input),
      include: async (importer, specifier) => {
        const file = path.resolve(path.dirname(path.resolve(importer)), specifier);
        return { name: display(file), text: decoder.decode(await fs.readFile(file)) };
      },
    });
    if (output === undefined) {
      process.stdout.write(expanded.text);
    } else {
      await fs.writeFile(output, expanded.text);
      process.stdout.write(`Expanded ${options.input} to ${display(output)}.\n`);
    }
    return 0;
  } catch (error) {
    process.stderr.write(error.category === "macro" ? `${error.message}\n` : `atompp: ${error.message}\n`);
    return 1;
  }
}

process.exitCode = await main();
