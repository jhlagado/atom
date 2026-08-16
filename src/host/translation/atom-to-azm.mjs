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

export function translateAtomLineToAzm(line) {
  if (typeof line !== "string") fail("line", "Atom source line must be text");
  const [source, comment] = splitComment(line);
  const colonEquate = /^(\s*)((?:\.[_A-Za-z][_A-Za-z0-9]*)|(?:[_A-Za-z][_A-Za-z0-9]*))(\s*:\s*)EQU\b(.*)$/i.exec(source);
  if (colonEquate !== null) {
    return `${colonEquate[1]}${colonEquate[2]}${colonEquate[3]}.equ${colonEquate[4]}${comment}`;
  }
  const equate = /^(\s*)((?:\.[_A-Za-z][_A-Za-z0-9]*)|(?:[_A-Za-z][_A-Za-z0-9]*))(\s+)EQU\b(.*)$/i.exec(source);
  if (equate !== null) {
    return `${equate[1]}${equate[2]}: .equ${equate[4]}${comment}`;
  }
  const directive = /^(\s*(?:(?:\.[_A-Za-z][_A-Za-z0-9]*|[_A-Za-z][_A-Za-z0-9]*)\s*:\s*)?)(ORG|DB|DW|DS|CSTR|PSTR|ISTR)\b(.*)$/i.exec(source);
  if (directive !== null) {
    return `${directive[1]}.${directive[2].toLowerCase()}${directive[3]}${comment}`;
  }
  return line;
}

export function translateResolvedAtomProjectToAzm(project) {
  if (project === null || typeof project !== "object" || !Array.isArray(project.parts)) {
    fail("project", "resolved Atom project must contain ordered parts");
  }
  const output = [];
  for (const [index, part] of project.parts.entries()) {
    if (
      part?.ordinal !== index ||
      typeof part.logicalIdentity !== "string" ||
      !(part.compilerBytes instanceof Uint8Array)
    ) {
      fail("part", `resolved Atom part ${index} is invalid`);
    }
    let text;
    try {
      text = decoder.decode(part.compilerBytes);
    } catch (cause) {
      fail("encoding", `Atom part ${part.logicalIdentity} is not UTF-8`, { cause });
    }
    output.push(`; Atom source part ${index}: ${part.logicalIdentity}`);
    for (const line of text.split(/\r\n|\n|\r/)) output.push(translateAtomLineToAzm(line));
  }
  output.push("            .end", "");
  return output.join("\n");
}
