import { SourcePreparationError } from "../project-preparation/errors.mjs";

const definitionPattern = /^[A-Za-z][A-Za-z0-9_]*$/;

function fail(code, message, location) {
  throw new SourcePreparationError("preprocessing", code, message, location);
}

export function canonicalAtomDefinitionName(name, location) {
  if (typeof name !== "string" || !definitionPattern.test(name)) {
    fail("invalid-definition-name", "invalid preprocessor definition name", location);
  }
  return name.toUpperCase();
}

function finishNumeric(value, location) {
  if (!Number.isSafeInteger(value) || value < 0 || value > 0xffff) {
    fail("value-range", "preprocessor value is outside 0 through 65535", location);
  }
  return value;
}

function definitionValue(definitions, name) {
  if (definitions instanceof Map) return definitions.get(name);
  if (definitions !== null && typeof definitions === "object" && Object.hasOwn(definitions, name)) {
    return definitions[name];
  }
  return undefined;
}

export function parseAtomPreprocessorValue(source, definitions = {}, location) {
  if (typeof source !== "string" || source.length === 0) {
    fail("invalid-value", "preprocessor value is empty", location);
  }

  let match;
  if (/^[0-9]+$/.test(source)) return finishNumeric(Number.parseInt(source, 10), location);
  if ((match = /^\$([0-9A-Fa-f]+)$/.exec(source)) !== null) {
    return finishNumeric(Number.parseInt(match[1], 16), location);
  }
  if ((match = /^%([01]+)$/.exec(source)) !== null) {
    return finishNumeric(Number.parseInt(match[1], 2), location);
  }
  if ((match = /^([0-9][0-9A-Fa-f]*)[Hh]$/.exec(source)) !== null) {
    return finishNumeric(Number.parseInt(match[1], 16), location);
  }
  if ((match = /^([01]+)[Bb]$/.exec(source)) !== null) {
    return finishNumeric(Number.parseInt(match[1], 2), location);
  }
  if (definitionPattern.test(source)) {
    const name = source.toUpperCase();
    const value = definitionValue(definitions, name);
    if (value === undefined) {
      fail("undefined-definition", `undefined preprocessor name ${source}`, location);
    }
    return finishNumeric(value, location);
  }
  fail("invalid-value", "invalid preprocessor value", location);
}
