// Read an Atom program as a list of statements, in the order Atom assembles
// it. %INCLUDE is a module import: each file is read once, after the files it
// includes, exactly as the assembler orders its parts.

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";

const INCLUDE = /^\s*%INCLUDE\s+"([^"]+)"/i;

// Split a line into its code and its comment. A semicolon inside a quoted
// character or string does not start a comment. AF' is a register name, not
// the start of a quote.
export function splitComment(line) {
  let quote = null;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (ch === quote) quote = null;
    } else if (ch === ";") {
      return { code: line.slice(0, i), comment: line.slice(i + 1) };
    } else if (ch === "'" && /AF$/i.test(line.slice(0, i))) {
      continue;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
    }
  }
  return { code: line, comment: "" };
}

// Split operands at top-level commas, leaving commas inside quotes alone.
function splitOperands(text) {
  const out = [];
  let quote = null;
  let start = 0;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quote) {
      if (ch === quote) quote = null;
    } else if (ch === "'" && /AF$/i.test(text.slice(start, i).trim())) {
      continue;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
    } else if (ch === ",") {
      out.push(text.slice(start, i).trim());
      start = i + 1;
    }
  }
  const last = text.slice(start).trim();
  if (last || out.length) out.push(last);
  return out;
}

// One statement per source line that carries a label, an instruction or a
// contract annotation.
//   { file, line, label, global, op, args, note }
// label is the name defined at the start of the line. global is true for a
// label without a leading period. op is the upper-case mnemonic or directive.
// note is a ;@ annotation such as "ROUTINE IN A OUT HL".
export function parseLine(text, file, line) {
  const { code, comment } = splitComment(text.replace(/\r$/, ""));
  const statement = { file, line, label: null, global: false, op: null, args: [], note: null };
  if (/^@/.test(comment) && !code.trim()) statement.note = comment.slice(1).trim();
  let rest = code;
  const labelled = /^([.A-Za-z_][A-Za-z0-9_]*):/.exec(rest);
  if (labelled) {
    statement.label = labelled[1];
    statement.global = !labelled[1].startsWith(".");
    rest = rest.slice(labelled[0].length);
  } else {
    const equate = /^([A-Za-z_][A-Za-z0-9_]*)\s+(EQU)\b/i.exec(rest);
    if (equate) {
      statement.label = equate[1];
      rest = rest.slice(equate[1].length);
    }
  }
  const body = rest.trim();
  if (body) {
    const space = body.search(/\s/);
    statement.op = (space < 0 ? body : body.slice(0, space)).toUpperCase();
    statement.args = space < 0 ? [] : splitOperands(body.slice(space + 1));
  }
  return statement.label || statement.op || statement.note ? statement : null;
}

// Read the program rooted at root, following %INCLUDE depth first.
export function readProgram(root) {
  const dir = dirname(root);
  const seen = new Set();
  const statements = [];
  const visit = (name) => {
    const key = name.toLowerCase();
    if (seen.has(key)) return;
    seen.add(key);
    const lines = readFileSync(join(dir, name), "latin1").split("\n");
    const own = [];
    lines.forEach((text, index) => {
      const include = INCLUDE.exec(text);
      if (include) {
        visit(include[1]);
        return;
      }
      const statement = parseLine(text, name, index + 1);
      if (statement) own.push(statement);
    });
    statements.push(...own);
  };
  visit(root.slice(dir.length).replace(/^[\\/]/, ""));
  return statements;
}
