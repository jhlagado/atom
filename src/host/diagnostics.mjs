// Atom's diagnostic messages, shared by the Node host and the CP/M program.
//
// When an assembly fails, the native core's DR_DIAG routine reduces its nested
// status codes to one message number and publishes up to three arguments:
//
//   %S  the symbol whose record address is in AT_DSYM
//   %D  the signed sixteen-bit value in AT_DVAL
//   %L  the line of the related location in DR_RPART/DR_ROFF
//
// Message numbers are dense. Each subsystem's status codes map to a block
// that starts at the base below. driver.asm defines the same bases.
// npm run build generates src/z80/cpmsg.asm from this list.

export const DIAGNOSTIC_BASE = Object.freeze({
  tokenizer: 13,
  expression: 25,
  symbol: 36,
  parser: 46,
  output: 64,
});

const INTERNAL = "internal error in Atom; please report it";

// Index = message number.
export const DIAGNOSTIC_MESSAGES = Object.freeze([
  // 0-12: driver, statement and CP/M messages.
  INTERNAL,
  "undefined symbol %S",
  "could not write the output",
  "invalid build description",
  "expected a label, instruction or directive",
  "unknown instruction or directive",
  "unexpected text after the operands",
  "strings are only allowed in DB",
  "expected a quoted string",
  "% directive is not allowed here",
  "relative jump to %S is out of range (offset %D); %S is on line %L",
  "value of %S (%D) is out of range for this operand",
  "stack overflow",

  // 13-24: tokenizer statuses TK_S*.
  INTERNAL,
  "invalid character",
  "name is longer than 8 characters",
  "malformed number",
  "number does not fit in 16 bits",
  "unterminated string",
  "unsupported escape sequence",
  "string is too long",
  INTERNAL,
  "% directive is not allowed here",
  "unterminated character constant",
  "invalid character constant",

  // 25-35: expression statuses EX_S*.
  INTERNAL,
  "value uses a symbol that is not defined yet",
  INTERNAL,
  "expected a value",
  "missing closing parenthesis",
  "division by zero",
  "value is out of range",
  "a forward reference here must be one symbol plus or minus a small number",
  "expression is too complex",
  INTERNAL,
  INTERNAL,

  // 36-45: symbol statuses SY_S*.
  INTERNAL,
  "symbol not found",
  "symbol is already defined",
  "too many symbols",
  "private label used before any global label",
  "private label %S is not defined before this global label",
  "too many forward references",
  INTERNAL,
  INTERNAL,
  INTERNAL,

  // 46-63: parser statuses PR_S*.
  INTERNAL,
  INTERNAL,
  INTERNAL,
  "expected an instruction",
  "unknown instruction",
  "expected an operand",
  "this operand cannot be used in brackets",
  "expected a comma or the end of the line",
  "too many operands",
  "operands are not valid for this instruction",
  "value is out of range for this operand",
  "relative jump is out of range (offset %D)",
  INTERNAL,
  INTERNAL,
  "this operand cannot refer to a symbol defined later",
  INTERNAL,
  "too many forward references in one instruction",
  "too many forward references",

  // 64-68: output statuses OU_S*.
  INTERNAL,
  "program does not fit in the output range",
  INTERNAL,
  "value %D is out of range for this operand",
  "relative jump is out of range (offset %D)",
]);

export const DIAGNOSTIC_STACK_OVERFLOW = 12;

// Expand a message template. `arguments_` supplies the symbol name, the value
// and the related line; a missing argument leaves a readable placeholder.
export function formatDiagnostic(number, { symbol, value, relatedLine } = {}) {
  const template = DIAGNOSTIC_MESSAGES[number] ?? INTERNAL;
  return template.replace(/%([SDL])/g, (_match, code) => {
    if (code === "S") return symbol ?? "?";
    if (code === "D") return value === undefined ? "?" : String(value);
    return relatedLine === undefined ? "?" : String(relatedLine);
  });
}
