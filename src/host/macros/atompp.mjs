// ATOMPP expands macros before Atom assembles the result. Atom itself has no
// macros. ATOMPP reads .mac source and writes plain Atom source, marking with
// %LINE where each output line came from, so Atom's errors name the .mac file
// and line.
//
//   %MACRO NAME a,b    defines NAME with parameters a and b, up to %ENDM.
//   NAME 1,(IX+2)      expands NAME. %a and %b in its body become 1 and (IX+2).
//   %@                 in a body becomes the expansion's number, which makes
//                      labels such as .L%@ unique to each expansion.
//   %REPT n            repeats the lines up to %ENDR n times.
//   %INCLUDE "x.mac"   reads macros and source from another .mac file.
//
// Every other % directive, and %INCLUDE of any other file, passes to Atom.
// Lines inside an expansion report the macro's own lines.

import { MNEMONICS } from "../abi.mjs";
import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const RESERVED = new Set([
  ...MNEMONICS.filter((name) => name !== null),
  "ORG", "DB", "DW", "DS", "ALIGN", "CSTR", "PSTR", "ISTR", "INCBIN", "EQU",
]);
const IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*$/;
const MAX_DEPTH = 32;
// Atom captures at most 64 bytes of a directive line.
const MAX_MARKER = 64;

function fail(code, text, at) {
  const diagnostic = { logicalIdentity: at.file, line: at.line, column: 1 };
  throw new AtomAssemblyError("macro", code, `${at.file}:${at.line}:1: ${text}`, { text, diagnostic });
}

// Split a line into code and comment. A semicolon inside quotes is code.
// AF' names a register, not the start of a quote.
function splitComment(line) {
  let quote = null;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (quote) {
      if (character === "\\") index += 1;
      else if (character === quote) quote = null;
    } else if (character === ";") {
      return [line.slice(0, index), line.slice(index)];
    } else if (character === "'" && /AF$/i.test(line.slice(0, index))) {
      continue;
    } else if (character === "'" || character === '"') {
      quote = character;
    }
  }
  return [line, ""];
}

// Split macro arguments at commas outside quotes and parentheses.
function splitArguments(text, at) {
  const result = [];
  let quote = null;
  let depth = 0;
  let start = 0;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quote) {
      if (character === "\\") index += 1;
      else if (character === quote) quote = null;
    } else if (character === "'" && /AF$/i.test(text.slice(start, index).trim())) {
      continue;
    } else if (character === "'" || character === '"') {
      quote = character;
    } else if (character === "(") {
      depth += 1;
    } else if (character === ")") {
      depth -= 1;
      if (depth < 0) fail("argument", "unbalanced parentheses in macro arguments", at);
    } else if (character === "," && depth === 0) {
      result.push(text.slice(start, index).trim());
      start = index + 1;
    }
  }
  if (quote || depth !== 0) fail("argument", "unclosed quote or parenthesis in macro arguments", at);
  const last = text.slice(start).trim();
  if (last || result.length) result.push(last);
  return result;
}

// A number in Atom's spellings: decimal, $hex, %binary, or an H or B suffix.
function parseCount(text, at) {
  const value = text.trim();
  let match;
  let number;
  if ((match = /^\$([0-9A-F]+)$/i.exec(value))) number = parseInt(match[1], 16);
  else if ((match = /^%([01]+)$/.exec(value))) number = parseInt(match[1], 2);
  else if ((match = /^([0-9][0-9A-F]*)H$/i.exec(value))) number = parseInt(match[1], 16);
  else if ((match = /^([01]+)B$/i.exec(value))) number = parseInt(match[1], 2);
  else if (/^[0-9]+$/.test(value)) number = parseInt(value, 10);
  if (number === undefined || number > 0xffff) fail("count", `%REPT needs a count from 0 to 65535, not ${value || "nothing"}`, at);
  return number;
}

// The directive at the start of a line: its keyword and the rest.
function directive(code) {
  const match = /^\s*%([A-Za-z]+)\b(.*)$/.exec(code);
  return match && { keyword: match[1].toUpperCase(), rest: match[2] };
}

// Collect a block's lines up to its closing directive, counting nested blocks
// that open with the same directive.
function collect(items, start, open, close, at) {
  let depth = 1;
  for (let index = start; index < items.length; index += 1) {
    const found = directive(splitComment(items[index].text)[0]);
    if (found?.keyword === open) depth += 1;
    if (found?.keyword === close && --depth === 0) return index;
  }
  return fail("unclosed", `%${open} has no %${close}`, at);
}

// Expand a .mac source to Atom source. include(importer, specifier) returns
// { name, text } for an included .mac file.
export async function expandAtomMacros(text, { name = "input.mac", include } = {}) {
  const eol = /\r\n/.test(text) ? "\r\n" : "\n";
  const macros = new Map();
  const output = [];
  const including = [];
  let expansions = 0;
  let next = null;

  // Write one line, marking where it came from when that is not the line
  // after the previous one.
  const emit = (line, at) => {
    if (next === null || next.file !== at.file || next.line !== at.line) {
      const marker = `%LINE "${at.file}",${at.line}`;
      if (marker.length > MAX_MARKER || at.file.includes('"')) {
        fail("name", `the file name ${at.file} is too long for a %LINE marker`, at);
      }
      output.push(marker);
    }
    output.push(line);
    next = { file: at.file, line: at.line + 1 };
  };

  const lines = (source, file) =>
    source.replace(/(\r\n|\n|\r)$/, "").split(/\r\n|\n|\r/).map((line, index) => ({ text: line, file, line: index + 1 }));

  // Replace %parameter and %@ in a line of an expansion.
  const substitute = (line, scope, at) =>
    line.replace(/%@|%([A-Za-z_][A-Za-z0-9_]*)/g, (whole, parameter) => {
      if (whole === "%@") return String(scope.id);
      return scope?.values.get(parameter.toUpperCase()) ?? whole;
    });

  async function run(items, scope, depth) {
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      const at = { file: item.file, line: item.line };
      if (!scope && splitComment(item.text)[0].includes("%@")) {
        fail("unique", "%@ is only meaningful inside a macro", at);
      }
      const text = scope ? substitute(item.text, scope, at) : item.text;
      const [code, comment] = splitComment(text);
      const found = directive(code);

      if (found?.keyword === "MACRO") {
        if (scope) fail("nested", "a macro cannot be defined inside an expansion", at);
        const end = collect(items, index + 1, "MACRO", "ENDM", at);
        if (end !== collect(items, index + 1, "\0", "ENDM", at)) fail("nested", "a macro cannot be defined inside another", at);
        const header = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(.*)$/.exec(found.rest.trim());
        if (!header) fail("macro", "%MACRO needs a name", at);
        const macroName = header[1].toUpperCase();
        if (RESERVED.has(macroName)) fail("macro", `${header[1]} is an instruction or directive`, at);
        if (macros.has(macroName)) fail("macro", `macro ${header[1]} is already defined`, at);
        const params = header[2].trim() === "" ? [] : header[2].split(",").map((p) => p.trim());
        const seen = new Set();
        for (const param of params) {
          if (!IDENTIFIER.test(param)) fail("macro", `invalid macro parameter ${param || "(empty)"}`, at);
          if (seen.has(param.toUpperCase())) fail("macro", `duplicate macro parameter ${param}`, at);
          seen.add(param.toUpperCase());
        }
        macros.set(macroName, { name: header[1], params, body: items.slice(index + 1, end) });
        // Blank lines keep the rest of the file on its own line numbers.
        for (let skip = index; skip <= end; skip += 1) emit("", items[skip]);
        index = end;
        continue;
      }
      if (found?.keyword === "ENDM") fail("unopened", "%ENDM without %MACRO", at);
      if (found?.keyword === "ENDR") fail("unopened", "%ENDR without %REPT", at);
      if (found?.keyword === "LINE") fail("line", "%LINE is written by ATOMPP, not read by it", at);

      if (found?.keyword === "REPT") {
        const end = collect(items, index + 1, "REPT", "ENDR", at);
        const count = parseCount(found.rest.split(";")[0], at);
        emit(`;${text.trim().slice(1)}`, at);
        for (let pass = 0; pass < count; pass += 1) await run(items.slice(index + 1, end), scope, depth);
        emit(`;${items[end].text.trim().slice(1)}`, items[end]);
        index = end;
        continue;
      }

      if (found?.keyword === "INCLUDE") {
        const specifier = /^\s*"([^"]+)"\s*$/.exec(found.rest)?.[1];
        if (specifier && /\.mac$/i.test(specifier)) {
          if (!include) fail("include", `cannot read ${specifier}: no include reader was given`, at);
          const file = await include(item.file, specifier);
          if (including.includes(file.name) || file.name === name) fail("include", `${specifier} includes itself`, at);
          emit(`;${text.trim().slice(1)}`, at);
          including.push(file.name);
          await run(lines(file.text, file.name), null, depth);
          including.pop();
          continue;
        }
      }

      const call = /^(\s*)((?:\.?[A-Za-z_][A-Za-z0-9_]*):)?(\s*)([A-Za-z_][A-Za-z0-9_]*)(.*)$/.exec(code);
      const macro = !found && call && macros.get(call[4].toUpperCase());
      if (macro) {
        if (depth >= MAX_DEPTH) fail("depth", `macros nest more than ${MAX_DEPTH} deep`, at);
        const values = splitArguments(call[5].trim(), at);
        if (values.length !== macro.params.length) {
          fail("argument", `${macro.name} takes ${macro.params.length} argument(s), not ${values.length}`, at);
        }
        // The call's line keeps its label and shows the call as a comment.
        const shown = code.trim().slice(call[2]?.length ?? 0).trim();
        emit(`${call[2] ? `${call[1]}${call[2]} ` : ""}; ${shown}${comment ? ` ${comment}` : ""}`, at);
        expansions += 1;
        const parameters = new Map(macro.params.map((param, n) => [param.toUpperCase(), values[n]]));
        await run(macro.body, { values: parameters, id: expansions }, depth + 1);
        continue;
      }
      emit(text, at);
    }
  }

  await run(lines(text, name), null, 0);
  return { text: `${output.join(eol)}${eol}`, macros: macros.size, expansions };
}
