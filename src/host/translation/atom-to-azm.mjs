// Convert prepared Atom source to historical AZM syntax for external comparisons.
// This translation does not invoke an assembler and is outside production builds.

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const decoder = new TextDecoder("utf-8", { fatal: true });

function fail(code, message, details = {}) {
  throw new AtomAssemblyError("translation", code, message, details);
}

function splitComment(line) {
  let quote = "";
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (quote !== "" && escaped) {
      escaped = false;
    } else if (quote !== "" && character === "\\") {
      escaped = true;
    } else if (character === quote) {
      quote = "";
    } else if (quote === "" && (character === '"' || character === "'")) {
      quote = character;
    } else if (quote === "" && character === ";") {
      return [line.slice(0, index), line.slice(index)];
    }
  }
  return [line, ""];
}

function translateByteFunctions(source) {
  let output = "";
  let quote = "";
  let escaped = false;
  for (let index = 0; index < source.length;) {
    const character = source[index];
    if (quote !== "") {
      output += character;
      index += 1;
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = "";
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      output += character;
      index += 1;
      continue;
    }
    const previous = index === 0 ? "" : source[index - 1];
    const match = /^(LOW|HIGH)(?=\s*\()/i.exec(source.slice(index));
    if (match !== null && !/[._A-Za-z0-9]/.test(previous)) {
      output += match[1].length === 3 ? "LSB" : "MSB";
      index += match[1].length;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

function translatePrivateIdentifiers(source) {
  let output = "";
  let quote = "";
  let escaped = false;
  for (let index = 0; index < source.length;) {
    const character = source[index];
    if (quote !== "") {
      output += character;
      index += 1;
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === quote) quote = "";
      continue;
    }
    if (character === '"' || character === "'") {
      quote = character;
      output += character;
      index += 1;
      continue;
    }
    if (character === "." && /[A-Za-z_]/.test(source[index + 1] ?? "")) {
      output += "_";
      index += 1;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

export function translateAtomLineToAzm(line) {
  if (typeof line !== "string") fail("line", "Atom source line must be text");
  const proofAnnotation = /^\s*;@(ROUTINE|EXPECTOUT)\b(.*)$/i.exec(line);
  if (proofAnnotation !== null) {
    return `.${proofAnnotation[1].toLowerCase()}${proofAnnotation[2]}`;
  }
  const [rawSource, comment] = splitComment(line);
  const source = translateByteFunctions(translatePrivateIdentifiers(rawSource));
  const colonEquate = /^(\s*)((?:\.[_A-Za-z][_A-Za-z0-9]*)|(?:[_A-Za-z][_A-Za-z0-9]*))(\s*:\s*)EQU\b(.*)$/i.exec(source);
  if (colonEquate !== null) {
    return `${colonEquate[1]}${colonEquate[2]}${colonEquate[3]}.equ${colonEquate[4]}${comment}`;
  }
  const equate = /^(\s*)((?:\.[_A-Za-z][_A-Za-z0-9]*)|(?:[_A-Za-z][_A-Za-z0-9]*))(\s+)EQU\b(.*)$/i.exec(source);
  if (equate !== null) {
    return `${equate[1]}${equate[2]}: .equ${equate[4]}${comment}`;
  }
  const directive = /^(\s*(?:(?:\.[_A-Za-z][_A-Za-z0-9]*|[_A-Za-z][_A-Za-z0-9]*)\s*:\s*)?)(ORG|DB|DW|DS|CSTR|PSTR|ISTR|ALIGN)\b(.*)$/i.exec(source);
  if (directive !== null) {
    return `${directive[1]}.${directive[2].toLowerCase()}${directive[3]}${comment}`;
  }
  return `${source}${comment}`;
}

// Translate the source an assembly read, as the core saw it: directive lines
// are comments and inactive branches are blank. With the result's segments,
// each stretch of each file appears in the order Atom assembled it, so an
// included file sits where its %INCLUDE was.
export function translateResolvedAtomProjectToAzm(project) {
  if (project === null || typeof project !== "object" || !Array.isArray(project.parts)) {
    fail("project", "resolved Atom project must contain ordered parts");
  }
  project.parts.forEach((part, index) => {
    if (
      part?.ordinal !== index ||
      typeof part.logicalIdentity !== "string" ||
      !(part.compilerBytes instanceof Uint8Array)
    ) {
      fail("part", `resolved Atom part ${index} is invalid`);
    }
    try {
      decoder.decode(part.compilerBytes);
    } catch (cause) {
      fail("encoding", `Atom part ${part.logicalIdentity} is not UTF-8`, { cause });
    }
  });
  const segments = project.segments ??
    project.parts.map((part, index) => ({ part: index, start: 0, end: part.compilerBytes.length }));
  const output = [];
  for (const { part, start, end } of segments) {
    const bytes = project.parts[part]?.compilerBytes;
    if (bytes === undefined || !(start >= 0 && start <= end && end <= bytes.length)) {
      fail("segment", "Atom source segment is outside its part");
    }
    // A file resumed after an include begins with the end of its %INCLUDE line.
    let text = decoder.decode(bytes.subarray(start, end)).replace(/(\r\n|\n|\r)$/, "");
    if (start > 0) text = text.replace(/^(\r\n|\n|\r)/, "");
    output.push(`; Atom source part ${part}: ${project.parts[part].logicalIdentity}`);
    for (const line of text.split(/\r\n|\n|\r/)) output.push(translateAtomLineToAzm(line));
  }
  output.push("            .end", "");
  return output.join("\n");
}
