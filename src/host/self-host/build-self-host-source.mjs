import fs from "node:fs/promises";
import path from "node:path";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";

const encoder = new TextEncoder();

function fail(code, message, details = {}) {
  throw new AtomAssemblyError("self-host-source", code, message, details);
}

function stripComment(line) {
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (quoted && escaped) {
      escaped = false;
    } else if (quoted && character === "\\") {
      escaped = true;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (!quoted && character === ";") {
      return line.slice(0, index);
    }
  }
  return line;
}

function decodeQuotedByte(body) {
  if (body.length === 1 && body.charCodeAt(0) <= 0x7f) return body.charCodeAt(0);
  const escapes = new Map([
    ["0", 0],
    ["n", 0x0a],
    ["r", 0x0d],
    ["t", 0x09],
    ['"', 0x22],
    ["\\", 0x5c],
  ]);
  if (body.length === 2 && body[0] === "\\" && escapes.has(body[1])) return escapes.get(body[1]);
  const hex = /^\\x([0-9A-Fa-f]{2})$/.exec(body);
  return hex === null ? undefined : Number.parseInt(hex[1], 16);
}

function normalizeCharacterLiterals(line) {
  return line.replace(/"((?:\\.|[^"\\])*)"/g, (quoted, body) => {
    const value = decodeQuotedByte(body);
    return value === undefined ? quoted : `$${value.toString(16).toUpperCase().padStart(2, "0")}`;
  });
}

function normalizeDirective(line) {
  let match = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s*:?\s*\.equ\s+(.+)$/i.exec(line);
  if (match !== null) return `${match[1]} EQU ${match[2].trim()}`;
  match = /^\s*([_A-Za-z][_A-Za-z0-9]*\s*:)\s*\.(org|db|dw|ds)\b(.*)$/i.exec(line);
  if (match !== null) return `${match[1]} ${match[2].toUpperCase()}${match[3]}`.trimEnd();
  match = /^\s*\.(org|db|dw|ds)\b(.*)$/i.exec(line);
  if (match !== null) return `${match[1].toUpperCase()}${match[2]}`.trimEnd();
  return line.trim();
}

const MODULES = Object.freeze([
  [/^Atom(?:Encoder|Encode|Instr|Op|Form|Ld|Im|Rotate|Alu|Rule|Opcode|Recognition|Recognize|Pack|Radix40|Mnemonic|Search|Validation|Validate|Is|Store|Encoded|Prefix|Scratch|Core)/, "EN"],
  [/^Atom(?:Symbol|Pending|Status)/, "SY"],
  [/^Atom(?:Tokenizer|Token)/, "TK"],
  [/^AtomExpression/, "EX"],
  [/^AtomPatch/, "PT"],
  [/^AtomParser/, "PR"],
  [/^AtomOutput/, "OU"],
  [/^Atom(?:Statement|Directive)/, "ST"],
  [/^Atom(?:Driver|Assemble|Finish)/, "DR"],
  [/^Atom(?:Host|Sink)/, "HS"],
]);

const MODULE_WORDS = Object.freeze({
  EN: /^(?:AtomEncoder|AtomEncode|AtomInstr|AtomOp|AtomForm|AtomMnemonic)/,
  SY: /^(?:AtomSymbol|AtomPending)/,
  TK: /^(?:AtomTokenizer|AtomToken)/,
  EX: /^AtomExpression/,
  PT: /^AtomPatch/,
  PR: /^AtomParser/,
  OU: /^AtomOutput/,
  ST: /^(?:AtomStatement|AtomDirective)/,
  DR: /^AtomDriver/,
  HS: /^(?:AtomHost|AtomSink)/,
  AT: /^Atom/,
});

const WORD_ABBREVIATIONS = Object.freeze({
  Address: "ADR",
  After: "AFT",
  Before: "BEF",
  Begin: "BEG",
  Build: "BLD",
  Byte: "B",
  Bytes: "B",
  Capacity: "CAP",
  Check: "CHK",
  Classify: "CLS",
  Character: "CHAR",
  Code: "C",
  Commit: "CMT",
  Configuration: "CFG",
  Count: "CNT",
  Current: "CUR",
  Declare: "DECL",
  Deferred: "DEFR",
  Descriptor: "DESC",
  Destination: "DST",
  Directive: "DIR",
  End: "END",
  Error: "ERR",
  Expected: "EXP",
  Expression: "EXPR",
  Failure: "FAIL",
  Finish: "FIN",
  Global: "GLBL",
  High: "HI",
  Instruction: "INS",
  Internal: "INT",
  Length: "LEN",
  Limit: "LIM",
  Local: "LOC",
  Low: "LO",
  Mnemonic: "MNEM",
  Next: "NEXT",
  Offset: "OFF",
  Operand: "OP",
  Operator: "OPER",
  Output: "OUT",
  Parse: "PARSE",
  Parser: "PARS",
  Part: "PART",
  Pointer: "PTR",
  Published: "PUB",
  Record: "REC",
  Reference: "REF",
  Remaining: "REM",
  Resident: "RES",
  Require: "REQ",
  Reset: "RESET",
  Resolve: "RSLV",
  Result: "RES",
  Source: "SRC",
  Start: "BEG",
  Status: "STAT",
  Symbol: "SYM",
  Token: "TOK",
  Value: "VAL",
  Workspace: "WORK",
  Word: "W",
});

const NAME_OVERRIDES = Object.freeze({
  AtomAssemble: "DR_ASM",
  AtomEncoderCoreStart: "EN_COREB",
  AtomEncoderCoreEnd: "EN_COREE",
  AtomEncoderCodeStart: "EN_CODEB",
  AtomEncoderCodeEnd: "EN_CODEE",
  AtomExpressionParse: "EX_PARSE",
  AtomHostResidentEnd: "HS_REND",
  AtomOutputResolveSymbol: "OU_RSLV",
  AtomParserParse: "PR_PARSE",
  AtomParserParsePublished: "PR_PUB",
  AtomRadix40Character: "EN_R40CH",
  AtomRadix40Pack: "EN_R40PK",
  AtomRecognizeMnemonic: "EN_RECOG",
  AtomSymbolFind: "SY_FIND",
  AtomTokenizerReset: "TK_RESET",
});

const PHRASE_ABBREVIATIONS = Object.freeze({
  CoreStart: "CBEG",
  CoreEnd: "CEND",
  CodeStart: "CBEG",
  CodeEnd: "CEND",
  WorkspaceStart: "WBEG",
  WorkspaceEnd: "WEND",
});

function moduleName(name) {
  const bare = name.replace(/^_/, "");
  for (const [pattern, module] of MODULES) {
    if (pattern.test(bare)) return module;
  }
  return "AT";
}

function camelWords(text) {
  return text.match(/[A-Z]+(?=[A-Z][a-z]|[0-9]|$)|[A-Z]?[a-z]+|[0-9]+/g) ?? [];
}

function semanticStem(name, module, maximum) {
  const bare = name.replace(/^_/, "");
  let body = bare.replace(MODULE_WORDS[module], "");
  if (body === bare) body = bare.replace(/^Atom/, "");
  const phrase = PHRASE_ABBREVIATIONS[body];
  if (phrase !== undefined) return phrase.slice(0, maximum);
  const words = camelWords(body);
  const pieces = words.map((word) => WORD_ABBREVIATIONS[word] ?? word.toUpperCase());
  let compressed = pieces.join("");
  if (compressed.length > maximum && pieces.length > 1) {
    compressed = `${pieces.slice(0, -1).map((piece) => piece[0]).join("")}${pieces.at(-1)}`;
  }
  const stem = compressed.replace(/[^A-Z0-9_]/g, "").slice(0, maximum);
  return stem === "" ? "NAME".slice(0, maximum) : stem;
}

function allocateShort(base, maximum, used) {
  if (!used.has(base)) {
    used.add(base);
    return base;
  }
  for (let ordinal = 1; ordinal < 36 * 36; ordinal += 1) {
    const suffix = ordinal.toString(36).toUpperCase();
    const candidate = `${base.slice(0, maximum - suffix.length)}${suffix}`;
    if (!used.has(candidate)) {
      used.add(candidate);
      return candidate;
    }
  }
  fail("symbol-collision", `cannot allocate an exact short name from ${base}`);
}

function definition(line) {
  const label = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s*:/.exec(line);
  if (label !== null) return { name: label[1], label: true };
  const equate = /^\s*([_A-Za-z][_A-Za-z0-9]*)\s+EQU\b/i.exec(line);
  return equate === null ? undefined : { name: equate[1], label: false };
}

function buildSymbolMap(lines) {
  const globalsByName = new Map();
  const privatesByScope = new Map();
  const globalsUsed = new Set();
  const privateUsed = new Map();
  const mapping = [];
  let currentScope;
  for (const line of lines) {
    const found = definition(line);
    if (found === undefined) continue;
    const { name } = found;
    const canonical = name.toUpperCase();
    const isPrivate = name.startsWith("_");
    if (!isPrivate && found.label) currentScope = canonical;
    const module = moduleName(name);
    if (isPrivate) {
      if (currentScope === undefined) fail("private-scope", `private name ${name} has no preceding global label`);
      const scoped = privatesByScope.get(currentScope) ?? new Map();
      if (scoped.has(canonical)) fail("duplicate-private", `private name ${name} is defined twice in ${currentScope}`);
      const used = privateUsed.get(currentScope) ?? new Set();
      const short = `.${allocateShort(semanticStem(name, module, 8), 8, used)}`;
      const record = Object.freeze({ original: name, short, private: true, module, scope: currentScope });
      scoped.set(canonical, record);
      privatesByScope.set(currentScope, scoped);
      privateUsed.set(currentScope, used);
      mapping.push(record);
    } else {
      if (globalsByName.has(canonical)) fail("duplicate-global", `global name ${name} is defined twice`);
      const base = NAME_OVERRIDES[name] ?? `${module}_${semanticStem(name, module, 5)}`;
      const short = allocateShort(base, 8, globalsUsed);
      const record = Object.freeze({ original: name, short, private: false, module });
      globalsByName.set(canonical, record);
      mapping.push(record);
    }
  }
  return Object.freeze({
    globalsByName,
    privatesByScope,
    mapping: Object.freeze(mapping),
    globals: globalsByName.size,
    privates: mapping.length - globalsByName.size,
  });
}

function replaceIdentifiers(line, globalsByName, privates) {
  if (line.trimStart().startsWith(";")) return line;
  let output = "";
  let index = 0;
  while (index < line.length) {
    const character = line[index];
    if (character === '"') {
      let end = index + 1;
      let escaped = false;
      while (end < line.length) {
        const candidate = line[end];
        if (escaped) escaped = false;
        else if (candidate === "\\") escaped = true;
        else if (candidate === '"') { end += 1; break; }
        end += 1;
      }
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (character >= "0" && character <= "9") {
      let end = index + 1;
      while (end < line.length && /[A-Za-z0-9]/.test(line[end])) end += 1;
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (character === "$" || character === "%") {
      const pattern = character === "$" ? /[0-9A-Fa-f]/ : /[01]/;
      let end = index + 1;
      while (end < line.length && pattern.test(line[end])) end += 1;
      output += line.slice(index, end);
      index = end;
      continue;
    }
    if (/[A-Za-z_]/.test(character)) {
      let end = index + 1;
      while (end < line.length && /[A-Za-z0-9_]/.test(line[end])) end += 1;
      const token = line.slice(index, end);
      const canonical = token.toUpperCase();
      const replacement = token.startsWith("_")
        ? privates?.get(canonical)
        : globalsByName.get(canonical);
      output += replacement?.short ?? token;
      index = end;
      continue;
    }
    output += character;
    index += 1;
  }
  return output;
}

function chunkLines(lines, maximumBytes) {
  const chunks = [];
  let current = [];
  let currentBytes = 0;
  for (const line of lines) {
    const bytes = encoder.encode(`${line}\n`).length;
    if (bytes > maximumBytes) fail("line-capacity", "one self-host source line exceeds the part capacity");
    if (current.length > 0 && currentBytes + bytes > maximumBytes) {
      chunks.push(current.join("\n") + "\n");
      current = [];
      currentBytes = 0;
    }
    current.push(line);
    currentBytes += bytes;
  }
  if (current.length > 0) chunks.push(current.join("\n") + "\n");
  return chunks;
}

export async function buildSelfHostSource({
  root,
  entry = "atom-host-runtime.asm",
  conditionalDefinitions = {
    AtomExpressionDeferredMode: 1,
    AtomParserExpressionMode: 1,
    AtomParserOutputMode: 1,
    AtomSymbolOutputMode: 1,
    AtomParserStatementMode: 1,
    AtomSymbolStatementMode: 1,
    AtomDriverMode: 1,
  },
  maximumPartBytes = 20 * 1024,
} = {}) {
  if (typeof root !== "string") fail("root", "self-host source root is required");
  if (!Number.isInteger(maximumPartBytes) || maximumPartBytes < 1 || maximumPartBytes > 0x6000) {
    fail("part-capacity", "self-host source part capacity is outside 1..24576");
  }
  const definitions = new Map(Object.entries(conditionalDefinitions).map(([name, value]) => [name.toUpperCase(), value]));
  const visited = new Set();
  const flattened = [];

  async function include(relativeName, importer) {
    const physical = path.resolve(importer === undefined ? root : path.dirname(importer), relativeName);
    const relative = path.relative(path.resolve(root), physical);
    if (relative.startsWith("..") || path.isAbsolute(relative)) fail("root-escape", `self-host include escapes root: ${relativeName}`);
    if (visited.has(physical)) fail("repeated-include", `self-host source repeats include ${relativeName}`);
    visited.add(physical);
    let text;
    try {
      text = await fs.readFile(physical, "utf8");
    } catch (cause) {
      fail("missing-source", `cannot read self-host source ${relativeName}`, { cause });
    }
    const conditionals = [];
    const active = () => conditionals.length === 0 || conditionals.at(-1).active;
    for (const raw of text.split(/\r\n|\n|\r/)) {
      const code = stripComment(raw).trim();
      if (code === "") continue;
      let match = /^\.if\s+([_A-Za-z][_A-Za-z0-9]*)$/i.exec(code);
      if (match !== null) {
        const parentActive = active();
        const value = definitions.get(match[1].toUpperCase());
        if (value === undefined) fail("condition", `unknown self-host condition ${match[1]}`);
        conditionals.push({ parentActive, selected: value !== 0, active: parentActive && value !== 0, elseSeen: false });
        continue;
      }
      if (/^\.else$/i.test(code)) {
        const state = conditionals.at(-1);
        if (state === undefined || state.elseSeen) fail("condition", "invalid self-host .else");
        state.elseSeen = true;
        state.active = state.parentActive && !state.selected;
        continue;
      }
      if (/^\.endif$/i.test(code)) {
        if (conditionals.pop() === undefined) fail("condition", "unmatched self-host .endif");
        continue;
      }
      if (!active()) continue;
      match = /^\.include\s+"([^"]+)"$/i.exec(code);
      if (match !== null) {
        await include(match[1], physical);
        continue;
      }
      match = /^\.(routine|expectout)\b(.*)$/i.exec(code);
      if (match !== null) {
        flattened.push(`;@${match[1].toUpperCase()}${match[2].toUpperCase()}`);
        continue;
      }
      if (/^\.end$/i.test(code)) continue;
      const configEquate = /^([_A-Za-z][_A-Za-z0-9]*)\s*:\s*\.equ\b/i.exec(code);
      if (configEquate !== null && definitions.has(configEquate[1].toUpperCase())) continue;
      flattened.push(normalizeDirective(normalizeCharacterLiterals(code)));
    }
    if (conditionals.length !== 0) fail("condition", `unterminated self-host condition in ${relativeName}`);
  }

  await include(entry, undefined);
  const { globalsByName, privatesByScope, mapping, globals, privates } = buildSymbolMap(flattened);
  let currentScope;
  const translated = flattened.map((line) => {
    const found = definition(line);
    if (found !== undefined && !found.name.startsWith("_") && found.label) {
      currentScope = found.name.toUpperCase();
    }
    return replaceIdentifiers(line, globalsByName, privatesByScope.get(currentScope));
  });
  const chunks = chunkLines(translated, maximumPartBytes);
  if (chunks.length > 16) fail("part-count", `self-host source requires ${chunks.length} parts; native limit is 16`);
  const parts = chunks.map((text, ordinal) => {
    const bytes = encoder.encode(text);
    return Object.freeze({
      ordinal,
      bank: 0,
      logicalIdentity: `native/atom-${ordinal.toString().padStart(2, "0")}.atm`,
      originalBytes: bytes,
      compilerBytes: bytes,
    });
  });
  return Object.freeze({
    project: Object.freeze({ parts: Object.freeze(parts) }),
    mapping,
    statistics: Object.freeze({
      inputFiles: visited.size,
      statements: translated.length,
      sourceBytes: parts.reduce((sum, part) => sum + part.compilerBytes.length, 0),
      parts: parts.length,
      globalSymbols: globals,
      privateSymbols: privates,
    }),
  });
}
