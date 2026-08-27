import { SourcePreparationError } from "../project-preparation/errors.mjs";
import {
  canonicalAtomDefinitionName,
  parseAtomPreprocessorValue,
} from "./literals.mjs";

function fail(code, message, location) {
  throw new SourcePreparationError("preprocessing", code, message, location);
}

function linesOf(bytes) {
  const lines = [];
  let start = 0;
  let line = 1;
  while (start < bytes.length) {
    let newline = start;
    while (newline < bytes.length && bytes[newline] !== 0x0a) newline += 1;
    const contentEnd = newline > start && bytes[newline - 1] === 0x0d
      ? newline - 1
      : newline;
    const newlineEnd = newline < bytes.length ? newline + 1 : newline;
    lines.push(Object.freeze({ start, contentEnd, newlineEnd, line }));
    start = newlineEnd;
    line += 1;
  }
  return lines;
}

function ascii(bytes, start, end, location) {
  let text = "";
  for (let offset = start; offset < end; offset += 1) {
    const byte = bytes[offset];
    if (byte > 0x7f) fail("invalid-directive", "host directive is not ASCII", location);
    text += String.fromCharCode(byte);
  }
  return text;
}

function trimHorizontal(text) {
  return text.replace(/^[ \t]+|[ \t]+$/g, "");
}

function trimComment(text) {
  const comment = text.indexOf(";");
  return trimHorizontal(comment < 0 ? text : text.slice(0, comment));
}

function locationFor(input, line, offset) {
  return Object.freeze({
    logicalIdentity: input.logicalIdentity,
    offset,
    line: line.line,
    column: offset - line.start + 1,
  });
}

function directiveAt(input, line) {
  const bytes = input.originalBytes;
  let marker = line.start;
  while (marker < line.contentEnd && (bytes[marker] === 0x20 || bytes[marker] === 0x09)) {
    marker += 1;
  }
  const first = bytes[marker];
  if (marker === line.contentEnd || first === 0x3b) {
    return Object.freeze({ kind: "empty" });
  }
  const next = bytes[marker + 1];
  if (
    first !== 0x25 ||
    next === undefined ||
    !((next >= 0x41 && next <= 0x5a) || (next >= 0x61 && next <= 0x7a))
  ) {
    return Object.freeze({ kind: "ordinary" });
  }

  const location = locationFor(input, line, marker);
  let nameEnd = marker + 1;
  while (nameEnd < line.contentEnd) {
    const byte = bytes[nameEnd];
    if (!((byte >= 0x41 && byte <= 0x5a) || (byte >= 0x61 && byte <= 0x7a))) break;
    nameEnd += 1;
  }
  if (
    nameEnd < line.contentEnd &&
    bytes[nameEnd] !== 0x20 &&
    bytes[nameEnd] !== 0x09 &&
    bytes[nameEnd] !== 0x3b
  ) {
    fail("invalid-directive", "host directive name is not delimited", location);
  }
  const name = ascii(bytes, marker + 1, nameEnd, location).toLowerCase();
  const argumentsText = trimHorizontal(ascii(bytes, nameEnd, line.contentEnd, location));
  return Object.freeze({ kind: "directive", name, argumentsText, location });
}

function maskLine(compilerBytes, maskedRanges, line) {
  for (let offset = line.start; offset < line.contentEnd; offset += 1) {
    compilerBytes[offset] = 0x20;
  }
  if (line.contentEnd > line.start) {
    maskedRanges.push(Object.freeze({ start: line.start, end: line.contentEnd }));
  }
}

function parseNoArguments(directive) {
  if (trimComment(directive.argumentsText) !== "") {
    fail("unexpected-directive-arguments", `%${directive.name} takes no arguments`, directive.location);
  }
}

function parseInclude(directive) {
  const text = trimComment(directive.argumentsText);
  const match = /^"([^"\r\n]+)"$/.exec(text);
  if (match === null) fail("invalid-include", "invalid %include path", directive.location);
  return match[1];
}

function parseDefinition(directive, definitions) {
  const text = trimComment(directive.argumentsText);
  const match = /^([A-Za-z][A-Za-z0-9_]*)[ \t]+([^ \t]+)$/.exec(text);
  if (match === null) fail("invalid-define", "invalid %define", directive.location);
  const name = canonicalAtomDefinitionName(match[1], directive.location);
  if (Object.hasOwn(definitions, name)) {
    fail("duplicate-definition", `duplicate preprocessor name ${match[1]}`, directive.location);
  }
  definitions[name] = parseAtomPreprocessorValue(match[2], definitions, directive.location);
}

function parseCondition(directive, definitions, evaluate) {
  const text = trimComment(directive.argumentsText);
  if (text.length === 0 || /[ \t]/.test(text)) {
    fail("invalid-value", "invalid %if condition", directive.location);
  }
  if (!evaluate && /^[A-Za-z][A-Za-z0-9_]*$/.test(text)) return false;
  return parseAtomPreprocessorValue(text, definitions, directive.location) !== 0;
}

function projectDefinitions(configuration) {
  const source = configuration?.definitions ?? {};
  if (source === null || typeof source !== "object") {
    fail("invalid-definitions", "project definitions must be an object or Map");
  }
  const entries = source instanceof Map ? [...source.entries()] : Object.entries(source);
  const definitions = Object.create(null);
  for (const [spelling, rawValue] of entries) {
    const name = canonicalAtomDefinitionName(spelling);
    if (Object.hasOwn(definitions, name)) {
      fail("duplicate-definition", `duplicate project definition ${spelling}`);
    }
    const value = typeof rawValue === "number"
      ? rawValue
      : parseAtomPreprocessorValue(rawValue, definitions);
    if (!Number.isInteger(value) || value < 0 || value > 0xffff) {
      fail("value-range", `project definition ${spelling} is outside 0 through 65535`);
    }
    definitions[name] = value;
  }
  return definitions;
}

function active(stack) {
  return stack.length === 0 || stack.at(-1).branchActive;
}

export function inspectAtomSource(input, { entry, configuration, state } = {}) {
  if (
    input === null ||
    typeof input !== "object" ||
    typeof input.logicalIdentity !== "string" ||
    !(input.originalBytes instanceof Uint8Array)
  ) {
    fail("invalid-source", "Atom profile requires a logical source and bytes");
  }

  const definitions = entry
    ? projectDefinitions(configuration)
    : Object.assign(Object.create(null), state?.definitions ?? {});
  const compilerBytes = input.originalBytes.slice();
  const dependencies = [];
  const maskedRanges = [];
  const stack = [];
  let headerOpen = true;
  let definitionsOpen = entry === true;

  for (const line of linesOf(input.originalBytes)) {
    const item = directiveAt(input, line);
    if (item.kind === "empty") {
      if (!active(stack)) maskLine(compilerBytes, maskedRanges, line);
      continue;
    }
    if (item.kind === "ordinary") {
      if (headerOpen && stack.some((frame) => frame.hasInclude)) {
        fail(
          "header-conditional-crosses-body",
          "an include-selecting conditional must close before Atom source",
          locationFor(input, line, line.start),
        );
      }
      headerOpen = false;
      definitionsOpen = false;
      if (!active(stack)) maskLine(compilerBytes, maskedRanges, line);
      continue;
    }

    maskLine(compilerBytes, maskedRanges, line);
    switch (item.name) {
      case "define":
        if (!entry) fail("define-in-dependency", "%define is forbidden in dependencies", item.location);
        if (!definitionsOpen) {
          fail("define-outside-entry-header", "%define is outside the entry definition header", item.location);
        }
        parseDefinition(item, definitions);
        break;
      case "include": {
        definitionsOpen = false;
        if (!headerOpen) fail("include-outside-header", "%include is outside the source header", item.location);
        const specifier = parseInclude(item);
        for (const frame of stack) frame.hasInclude = true;
        if (active(stack)) {
          dependencies.push(Object.freeze({ specifier, location: item.location }));
        }
        break;
      }
      case "if": {
        definitionsOpen = false;
        const parentActive = active(stack);
        const conditionTrue = parseCondition(item, definitions, parentActive);
        stack.push({
          parentActive,
          conditionTrue,
          branchActive: parentActive && conditionTrue,
          elseSeen: false,
          hasInclude: false,
          location: item.location,
        });
        break;
      }
      case "else": {
        parseNoArguments(item);
        const frame = stack.at(-1);
        if (frame === undefined) fail("unmatched-else", "unmatched %else", item.location);
        if (frame.elseSeen) fail("duplicate-else", "duplicate %else", item.location);
        frame.elseSeen = true;
        frame.branchActive = frame.parentActive && !frame.conditionTrue;
        break;
      }
      case "endif":
        parseNoArguments(item);
        if (stack.length === 0) fail("unmatched-endif", "unmatched %endif", item.location);
        stack.pop();
        break;
      default:
        fail("unknown-directive", `unknown host directive %${item.name}`, item.location);
    }
  }

  if (stack.length !== 0) {
    fail("unterminated-conditional", "unterminated %if", stack.at(-1).location);
  }

  const frozenDefinitions = Object.freeze({ ...definitions });
  return Object.freeze({
    compilerBytes,
    dependencies: Object.freeze(dependencies),
    maskedRanges: Object.freeze(maskedRanges),
    ...(entry ? { state: Object.freeze({ definitions: frozenDefinitions }) } : {}),
  });
}
