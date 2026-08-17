import { MNEMONICS } from "../../abi.mjs";
import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const mnemonicNames = new Set(MNEMONICS.filter((name) => name !== null));
const directiveNames = new Map([
  ["ALIGN", "ALIGN"],
  ["CSTR", "CSTR"],
  ["DB", "DB"],
  ["DS", "DS"],
  ["DW", "DW"],
  ["ISTR", "ISTR"],
  ["ORG", "ORG"],
  ["PSTR", "PSTR"],
]);
const unsupportedDirectives = new Set([
  "ADDR", "BINFROM", "BINTO", "BYTE", "CONTRACTS", "ELSE", "ENDIF",
  "ENDTYPE", "ENDUNION", "ENUM", "FIELD", "IF", "IMPORT", "INCLUDE",
  "RCIGNORE", "TYPE", "TYPEALIAS", "UNION", "WORD",
]);
const atomEscapeNames = new Set(["0", "n", "r", "t", "'", '"', "\\"]);

function locationDetails(sourceName, line, column) {
  return {
    sourceName,
    line,
    column,
    diagnostic: { logicalIdentity: sourceName, line, column },
  };
}

function fail(context, code, message, column = context.column) {
  throw new AtomAssemblyError(
    "translation",
    code,
    message,
    locationDetails(context.sourceName, context.line, column),
  );
}

function isApostropheRegister(line, index) {
  return /[A-Za-z0-9_]/.test(line[index - 1] ?? "");
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
    } else if (
      quote === "" &&
      (character === '"' || (character === "'" && !isApostropheRegister(line, index)))
    ) {
      quote = character;
    } else if (quote === "" && character === ";") {
      return { source: line.slice(0, index), comment: line.slice(index), commentColumn: index + 1 };
    }
  }
  return { source: line, comment: "", commentColumn: line.length + 1 };
}

function decodedQuotedLength(source, start, context) {
  const quote = source[start];
  let length = 0;
  for (let index = start + 1; index < source.length; index += 1) {
    const character = source[index];
    if (character === quote) return { end: index + 1, length };
    if (character.charCodeAt(0) > 0x7f || (character.charCodeAt(0) < 0x20 && character !== "\t")) {
      fail(context, "source-character", "non-ASCII quoted text cannot be represented safely by Atom", context.column + index);
    }
    if (character !== "\\") {
      length += 1;
      continue;
    }
    const escaped = source[index + 1];
    if (escaped === undefined) fail(context, "unterminated-string", "unterminated quoted value", context.column + start);
    if (escaped === "x") {
      if (!/^[0-9A-Fa-f]{2}$/.test(source.slice(index + 2, index + 4))) {
        fail(context, "escape", "AZM hexadecimal escape cannot be represented by Atom", context.column + index);
      }
      index += 3;
      length += 1;
      continue;
    }
    if (!atomEscapeNames.has(escaped)) {
      fail(context, "escape", `AZM escape \\${escaped} cannot be represented by Atom`, context.column + index);
    }
    index += 1;
    length += 1;
  }
  fail(context, "unterminated-string", "unterminated quoted value", context.column + start);
}

function doubleQuotedByteToAtom(source, start, end) {
  let payload = source.slice(start + 1, end - 1);
  payload = payload.replace(/(^|[^\\])'/g, "$1\\'");
  return `'${payload}'`;
}

function checkedAtomName(name, context, column, { localAllowed = true } = {}) {
  if (name.startsWith("@")) {
    fail(context, "export", "AZM exported declarations have no Atom equivalent", column);
  }
  if (/[.$?]/.test(name)) {
    fail(context, "symbol-spelling", `AZM symbol ${name} cannot be represented by Atom`, column);
  }
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) {
    fail(context, "symbol-spelling", `invalid AZM symbol ${name}`, column);
  }
  if (name.startsWith("_")) {
    if (!localAllowed) fail(context, "local-declaration", "AZM local syntax is valid only for labels", column);
    const payload = name.slice(1);
    if (payload.length < 1 || payload.length > 8) {
      fail(context, "symbol-length", `AZM local ${name} exceeds Atom's eight-character limit`, column);
    }
    return `.${payload}`;
  }
  if (name.length > 8) {
    fail(context, "symbol-length", `AZM symbol ${name} exceeds Atom's eight-character limit`, column);
  }
  return name;
}

function transformCode(source, context, {
  dataBytes = false,
  collectReferences = false,
  state,
} = {}) {
  let output = "";
  const references = [];
  for (let index = 0; index < source.length;) {
    const character = source[index];
    if (character === '"' || (character === "'" && !isApostropheRegister(source, index))) {
      const quoted = decodedQuotedLength(source, index, context);
      if (character === "'" && quoted.length !== 1) {
        fail(
          context,
          "string-form",
          dataBytes
            ? "multi-byte single-quoted AZM strings have no Atom equivalent"
            : "Atom character literals must decode to exactly one byte",
          context.column + index,
        );
      }
      if (character === '"' && !dataBytes) {
        if (quoted.length !== 1) {
          fail(context, "string-form", "AZM quoted-byte expression must decode to one byte for Atom", context.column + index);
        }
        output += doubleQuotedByteToAtom(source, index, quoted.end);
      } else {
        output += source.slice(index, quoted.end);
      }
      index = quoted.end;
      continue;
    }
    if (character === "\\") {
      fail(context, "instruction-chain", "AZM chained instructions have no Atom source form", context.column + index);
    }
    const previous = source[index - 1] ?? "";
    const prefixedNumeric = /^(\$[0-9A-Fa-f]+|%[01]+)/.exec(source.slice(index));
    if (prefixedNumeric !== null && !/[A-Za-z0-9_]/.test(previous)) {
      output += prefixedNumeric[1];
      index += prefixedNumeric[1].length;
      continue;
    }
    const numeric = /^(0[xX][0-9A-Fa-f]+|0[bB][01]+)/.exec(source.slice(index));
    if (numeric !== null && !/[A-Za-z0-9_]/.test(previous)) {
      const text = numeric[1];
      output += text[1].toLowerCase() === "x" ? `$${text.slice(2)}` : `%${text.slice(2)}`;
      index += text.length;
      continue;
    }
    const suffixNumeric = /^(?:[0-9][0-9A-Fa-f]*[Hh]|[01]+[Bb]|[0-9]+)/.exec(source.slice(index));
    if (suffixNumeric !== null) {
      const text = suffixNumeric[0];
      if (/[A-Za-z0-9_]/.test(source[index + text.length] ?? "")) {
        fail(context, "number", `AZM number ${source.slice(index).split(/[^A-Za-z0-9_]/, 1)[0]} cannot be represented by Atom`, context.column + index);
      }
      output += text;
      index += text.length;
      continue;
    }
    if (/[A-Za-z_]/.test(character)) {
      const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(source.slice(index));
      const name = match[0];
      const next = source[index + name.length] ?? "";
      if (next === "." || next === "$" || next === "?") {
        fail(context, "qualified-symbol", `AZM symbol ${source.slice(index).split(/[\s,()+\-*/%&|^<>]/, 1)[0]} cannot be represented by Atom`, context.column + index);
      }
      const functionCall = source.slice(index + name.length).match(/^\s*\(/) !== null;
      const upper = name.toUpperCase();
      if ((upper === "LSB" || upper === "MSB") && functionCall) {
        output += upper === "LSB" ? "LOW" : "HIGH";
      } else if ((upper === "SIZEOF" || upper === "OFFSET") && functionCall) {
        fail(context, "layout-expression", `AZM ${name}() has no Atom equivalent`, context.column + index);
      } else {
        const translated = checkedAtomName(name, context, context.column + index);
        if (translated.startsWith(".") && state?.currentGlobal === undefined) {
          fail(context, "private-scope", "AZM local reference appears before a global label", context.column + index);
        }
        output += translated;
        if (collectReferences) references.push({ name: translated, column: context.column + index });
      }
      index += name.length;
      continue;
    }
    if (character === "@" || character === "?" || character === ".") {
      fail(context, "symbol-spelling", `AZM source token ${character} cannot be represented by Atom`, context.column + index);
    }
    if (character === "$" && /[G-Zg-z_?]/.test(source[index + 1] ?? "")) {
      fail(context, "symbol-spelling", "AZM dollar-prefixed symbols have no Atom equivalent", context.column + index);
    }
    if ((character === "<" && source[index + 1] !== "<") || (character === ">" && source[index + 1] !== ">")) {
      fail(context, "layout-expression", "AZM layout casts have no Atom equivalent", context.column + index);
    }
    const code = character.charCodeAt(0);
    if (code > 0x7f || (code < 0x20 && character !== "\t")) {
      fail(context, "source-character", "AZM source character cannot be represented by Atom", context.column + index);
    }
    output += character;
    index += 1;
  }
  return { text: output, references };
}

function statementHead(statement) {
  const dotted = /^\.([A-Za-z][A-Za-z0-9_]*)\b/.exec(statement);
  if (dotted !== null) return { name: dotted[1].toUpperCase(), dotted: true, length: dotted[0].length };
  const bare = /^([A-Za-z][A-Za-z0-9_]*)\b/.exec(statement);
  return bare === null ? undefined : { name: bare[1].toUpperCase(), dotted: false, length: bare[0].length };
}

function declarationKey(name, state, context, column) {
  const upper = name.toUpperCase();
  if (!upper.startsWith(".")) return upper;
  if (state.currentGlobal === undefined) {
    fail(context, "private-scope", "AZM local label appears before a global label", column);
  }
  return `${state.currentGlobal}:${upper}`;
}

function recordDeclaration(name, state, context, column, { changesScope = false } = {}) {
  const key = declarationKey(name, state, context, column);
  if (state.declarations.has(key)) {
    fail(context, "case-collision", `declaration ${name} collides in Atom's case-insensitive symbol table`, column);
  }
  state.declarations.add(key);
  if (changesScope && !name.startsWith(".")) state.currentGlobal = name.toUpperCase();
}

function equateReferencesAreResolved(references, state, context) {
  for (const reference of references) {
    const key = reference.name.startsWith(".")
      ? state.currentGlobal === undefined ? undefined : `${state.currentGlobal}:${reference.name.toUpperCase()}`
      : reference.name.toUpperCase();
    if (key === undefined || !state.declarations.has(key)) {
      fail(
        context,
        "forward-equate",
        `AZM equate reference ${reference.name} is not already resolved; Atom does not support forward EQU`,
        reference.column,
      );
    }
  }
}

function translateEquate(name, separator, operand, context, state, nameColumn, operandColumn) {
  const translatedName = checkedAtomName(name, context, nameColumn, { localAllowed: false });
  if (operand.trimStart().startsWith('"')) {
    const quoteOffset = operand.length - operand.trimStart().length;
    const quoted = decodedQuotedLength(operand, quoteOffset, { ...context, column: operandColumn });
    if (quoted.length > 1) {
      fail(
        context,
        "string-equate",
        "AZM string-valued equates have no Atom equivalent",
        operandColumn + quoteOffset,
      );
    }
  }
  const transformed = transformCode(
    operand,
    { ...context, column: operandColumn },
    { collectReferences: true, state },
  );
  equateReferencesAreResolved(transformed.references, state, context);
  recordDeclaration(translatedName, state, context, nameColumn);
  return `${translatedName}${separator}EQU${transformed.text}`;
}

function translateStatement(statement, context, state) {
  const equate = /^(@?[A-Za-z_.$?][A-Za-z0-9_.$?]*)(\s+)(?:\.equ|equ)\b(.*)$/i.exec(statement);
  if (equate !== null) {
    return translateEquate(
      equate[1],
      equate[2],
      equate[3],
      context,
      state,
      context.column,
      context.column + statement.length - equate[3].length,
    );
  }
  if (/^@?[A-Za-z_.$?][A-Za-z0-9_.$?]*\s+\.(?:enum|type|typealias|union)\b/i.test(statement)) {
    fail(context, "unsupported-directive", "AZM typed or enumerated declarations have no Atom equivalent");
  }

  const head = statementHead(statement);
  if (head === undefined) fail(context, "statement", "AZM statement cannot be represented by Atom");
  const operand = statement.slice(head.length);
  if (head.name === "ROUTINE" || head.name === "EXPECTOUT") {
    if (!head.dotted) fail(context, "statement", `AZM ${head.name} directive must be dotted`);
    return `;@${head.name}${operand}`;
  }
  if (head.name === "END") {
    if (operand.trim() !== "") fail(context, "end", "AZM END must not have an operand");
    state.ended = true;
    return "";
  }
  if (head.name === "OP" || head.name === "ENDOP") {
    fail(context, "op", "AZM ops have no Atom equivalent");
  }
  if (unsupportedDirectives.has(head.name) || (head.dotted && !directiveNames.has(head.name))) {
    fail(context, "unsupported-directive", `AZM directive ${head.dotted ? "." : ""}${head.name} has no Atom equivalent`);
  }
  if (directiveNames.has(head.name)) {
    if (head.dotted === false && !/^[A-Z]+$/.test(statement.slice(0, head.length))) {
      fail(context, "directive-spelling", "bare AZM directive aliases must be uppercase");
    }
    if (head.name === "DS" && /^\s*[A-Za-z_][A-Za-z0-9_]*(?:\s*\[[^\]]*\])?\s*(?:,|$)/.test(operand)) {
      fail(context, "typed-storage", "AZM typed DS operands have no unambiguous Atom equivalent");
    }
    const transformed = transformCode(
      operand,
      { ...context, column: context.column + head.length },
      { dataBytes: ["DB", "CSTR", "PSTR", "ISTR"].includes(head.name), state },
    );
    return `${directiveNames.get(head.name)}${transformed.text}`;
  }
  if (!mnemonicNames.has(head.name)) {
    fail(context, "unsupported-statement", `AZM statement ${statement.slice(0, head.length)} is not an Atom instruction or directive`);
  }
  const transformed = transformCode(
    operand,
    { ...context, column: context.column + head.length },
    { state },
  );
  return `${head.name}${transformed.text}`;
}

function translateSourceLine(lineText, context, state) {
  const { source, comment } = splitComment(lineText);
  const leading = /^\s*/.exec(source)[0];
  let statement = source.slice(leading.length).trimEnd();
  if (statement === "") return `${source}${comment}`;
  if (state.ended) fail(context, "content-after-end", "AZM source contains a statement after END", leading.length + 1);

  const colonEquate = /^(@?[A-Za-z_.$?][A-Za-z0-9_.$?]*):(\s*)(?:\.equ|equ)\b(.*)$/i.exec(statement);
  if (colonEquate !== null) {
    const translated = translateEquate(
      colonEquate[1],
      ": ",
      colonEquate[3],
      { ...context, column: leading.length + 1 },
      state,
      leading.length + 1,
      leading.length + 1 + statement.length - colonEquate[3].length,
    );
    return `${leading}${translated}${comment === "" ? "" : ` ${comment}`}`;
  }

  let labelOutput = "";
  const label = /^(@?[A-Za-z_.$?][A-Za-z0-9_.$?]*):(.*)$/.exec(statement);
  if (label !== null) {
    const translated = checkedAtomName(label[1], context, leading.length + 1);
    recordDeclaration(translated, state, context, leading.length + 1, { changesScope: true });
    labelOutput = `${translated}:`;
    statement = label[2].trimStart();
    if (statement === "") return `${leading}${labelOutput}${comment === "" ? "" : ` ${comment}`}`;
  }

  const translatedStatement = translateStatement(
    statement,
    { ...context, column: leading.length + labelOutput.length + (labelOutput === "" ? 1 : 2) },
    state,
  );
  const body = labelOutput === ""
    ? translatedStatement
    : translatedStatement === "" ? labelOutput : `${labelOutput} ${translatedStatement}`;
  if (body === "") return comment === "" ? "" : `${leading}${comment}`;
  return `${leading}${body}${comment === "" ? "" : ` ${comment}`}`;
}

export function translateAzmSourceToAtom(source, { sourceName = "<azm-source>" } = {}) {
  if (typeof source !== "string") {
    throw new AtomAssemblyError("translation", "source", "AZM source must be text");
  }
  if (typeof sourceName !== "string" || sourceName.length === 0) {
    throw new AtomAssemblyError("translation", "source-name", "AZM source name must be non-empty text");
  }
  const state = { currentGlobal: undefined, declarations: new Set(), ended: false };
  const trailingNewline = /(?:\r\n|\n|\r)$/.test(source);
  const lines = source.split(/\r\n|\n|\r/);
  if (trailingNewline) lines.pop();
  const translated = lines.map((lineText, index) => translateSourceLine(
    lineText,
    { sourceName, line: index + 1, column: 1 },
    state,
  ));
  return `${translated.join("\n")}${trailingNewline ? "\n" : ""}`;
}
