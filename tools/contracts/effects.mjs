// What one Z80 instruction does to registers, flags, the stack and control
// flow. The checker works on units: the eight-bit registers, the halves of IX
// and IY, and the five flags a contract can name. N is never part of a
// contract, so it is not tracked.

export const REGS = ["A", "B", "C", "D", "E", "H", "L", "IXH", "IXL", "IYH", "IYL"];
export const FLAGS = ["CF", "ZF", "SF", "PF", "HF"];
export const UNITS = [...REGS, ...FLAGS];

const ALL = FLAGS;
const NO_CARRY = ["ZF", "SF", "PF", "HF"];
const PAIRS = {
  BC: ["B", "C"],
  DE: ["D", "E"],
  HL: ["H", "L"],
  IX: ["IXH", "IXL"],
  IY: ["IYH", "IYL"],
};
const REG8 = new Set(["A", "B", "C", "D", "E", "H", "L"]);
const CONDITIONS = { NZ: "ZF", Z: "ZF", NC: "CF", C: "CF", PO: "PF", PE: "PF", P: "SF", M: "SF" };
const DATA = new Set(["DB", "DW", "DS", "DEFB", "DEFW", "DEFS", "DEFM", "CSTR", "PSTR", "ISTR", "INCBIN"]);
const DIRECTIVES = new Set(["EQU", "ORG", "ALIGN", "END"]);

// The units a contract word names.
export function contractUnits(word) {
  const name = word.toUpperCase();
  if (PAIRS[name]) return PAIRS[name];
  if (name === "AF") return ["A", ...ALL];
  if (name === "F") return ALL;
  if (REG8.has(name)) return [name];
  return { CARRY: ["CF"], ZERO: ["ZF"], SIGN: ["SF"], PARITY: ["PF"], HALFCARRY: ["HF"] }[name] ?? null;
}

// Classify one operand.
//   { kind: "reg", units }      a register or register pair
//   { kind: "mem", reads, key } a memory operand; key names an absolute cell
//   { kind: "imm", text }       a number, a label or an expression
export function operand(text) {
  const name = text.toUpperCase().replace(/\s+/g, "");
  if (REG8.has(name)) return { kind: "reg", units: [name], name };
  if (PAIRS[name]) return { kind: "reg", units: PAIRS[name], name };
  if (name === "AF") return { kind: "reg", units: ["A", "F"], name };
  if (name === "AF'") return { kind: "reg", units: [], name };
  if (name === "SP" || name === "I" || name === "R") return { kind: "reg", units: [], name };
  const inner = /^\((.*)\)$/.exec(text.trim());
  if (inner) {
    const body = inner[1].trim();
    const upper = body.toUpperCase().replace(/\s+/g, "");
    if (PAIRS[upper]) return { kind: "mem", reads: PAIRS[upper], name: `(${upper})` };
    if (upper === "SP") return { kind: "mem", reads: [], name: "(SP)" };
    if (upper === "C") return { kind: "mem", reads: ["C"], name: "(C)" };
    const indexed = /^(IX|IY)([+-].*)?$/.exec(upper);
    if (indexed) return { kind: "mem", reads: PAIRS[indexed[1]], name: "(IDX)" };
    return { kind: "mem", reads: [], key: body, name: "(NN)" };
  }
  return { kind: "imm", text: text.trim() };
}

// Describe one statement.
//   reads, writes   units read and written
//   moves           [to, from] exact copies, taken from the state before
//   push, pop       the units of one stack word, high then low
//   exTop           the pair exchanged with the stack top
//   store, load     [key, units] for absolute memory cells
//   stack           "unknown" when SP moves, "fresh" when it is loaded
//   memWrite        true when memory or a port is written
//   constant        written units whose new value does not depend on reads
//   flow            next, jump, branch, call, callIf, ret, retIf,
//                   indirect, stop
//   target, cond    the jump or call target and its flag
export function effects(op, args) {
  const e = { reads: [], writes: [], moves: [], flow: "next" };
  if (!op || DIRECTIVES.has(op)) return e;
  if (DATA.has(op)) return { ...e, flow: "stop" };
  const a = args.map(operand);
  const [x, y] = a;
  const reads = (...units) => e.reads.push(...units.flat());
  const writes = (...units) => e.writes.push(...units.flat());
  const readOperand = (o) => {
    if (!o) return;
    if (o.kind === "reg") reads(o.units.filter((u) => u !== "F"));
    if (o.kind === "reg" && o.units.includes("F")) reads(ALL);
    if (o.kind === "mem") reads(o.reads);
  };
  const writeTarget = (o) => {
    if (o?.kind === "reg") writes(o.units);
    if (o?.kind === "mem") {
      readOperand(o);
      e.memWrite = true;
    }
  };
  const condition = (text) => CONDITIONS[text?.toUpperCase()];

  switch (op) {
    case "LD": {
      readOperand(y);
      if (x.kind === "mem") {
        readOperand(x);
        e.memWrite = true;
        if (x.key && y.kind === "reg") e.store = [x.key, y.units];
        break;
      }
      if (x.name === "SP") {
        readOperand(y);
        e.stack = "fresh";
        break;
      }
      if (x.kind === "reg") writes(x.units);
      if (x.name === "A" && (y.name === "I" || y.name === "R")) writes(NO_CARRY);
      if (x.kind === "reg" && y.kind === "reg" && x.units.length === y.units.length && y.units.length) {
        x.units.forEach((unit, i) => e.moves.push([unit, y.units[i]]));
      }
      if (x.kind === "reg" && y.kind === "mem" && y.key) e.load = [y.key, x.units];
      break;
    }
    case "PUSH":
      readOperand(x);
      e.push = x.units.includes("F") ? ["A", "F"] : x.units;
      break;
    case "POP":
      e.pop = x.units;
      writes(x.units.flatMap((u) => (u === "F" ? ALL : [u])));
      break;
    case "EX":
      if (x.name === "DE") {
        reads("D", "E", "H", "L");
        writes("D", "E", "H", "L");
        e.moves.push(["D", "H"], ["E", "L"], ["H", "D"], ["L", "E"]);
      } else if (x.name === "AF") {
        reads("A", ALL);
        writes("A", ALL);
      } else if (x.name === "(SP)") {
        readOperand(y);
        writes(y.units);
        e.exTop = y.units;
      }
      break;
    case "EXX":
      reads("B", "C", "D", "E", "H", "L");
      writes("B", "C", "D", "E", "H", "L");
      break;
    case "ADD":
    case "ADC":
    case "SBC":
      if (a.length === 2 && x.kind === "reg" && x.units.length === 2) {
        reads(x.units);
        readOperand(y);
        writes(x.units);
        writes(op === "ADD" ? ["CF", "HF"] : ALL);
        if (op !== "ADD") reads("CF");
        break;
      }
    // Fall through: eight-bit arithmetic on A.
    case "SUB":
    case "AND":
    case "OR":
    case "XOR":
    case "CP": {
      const source = a.length === 2 ? y : x;
      // XOR A, SUB A and CP A give the same result whatever A holds.
      const self = source.name === "A" && (op === "XOR" || op === "SUB" || op === "CP");
      if (!self) reads("A");
      if (!self) readOperand(source);
      if (op === "ADC" || op === "SBC") reads("CF");
      // OR A and AND A only set flags from A.
      const keep = source.name === "A" && (op === "OR" || op === "AND");
      if (op !== "CP" && !keep) writes("A");
      writes(ALL);
      if (op === "AND" || op === "OR" || op === "XOR") e.constant = ["CF", "HF"];
      if (self) e.constant = op === "SUB" || op === "XOR" ? ["A", ...ALL] : ALL;
      break;
    }
    case "INC":
    case "DEC":
      if (x.kind === "reg" && x.units.length === 2) {
        reads(x.units);
        writes(x.units);
      } else if (x.name === "SP") {
        e.stack = "unknown";
      } else {
        readOperand(x);
        writeTarget(x);
        writes(NO_CARRY);
      }
      break;
    case "NEG":
      reads("A");
      writes("A", ALL);
      break;
    case "CPL":
      reads("A");
      writes("A", "HF");
      break;
    case "DAA":
      reads("A", "CF", "HF");
      writes("A", ALL);
      break;
    case "SCF":
      writes("CF", "HF");
      e.constant = ["CF", "HF"];
      break;
    case "CCF":
      reads("CF");
      writes("CF", "HF");
      break;
    case "RLCA":
    case "RRCA":
    case "RLA":
    case "RRA":
      reads("A");
      if (op === "RLA" || op === "RRA") reads("CF");
      writes("A", "CF", "HF");
      break;
    case "RLC":
    case "RRC":
    case "RL":
    case "RR":
    case "SLA":
    case "SRA":
    case "SRL":
    case "SLL": {
      const target = a[a.length - 1];
      readOperand(target);
      if (op === "RL" || op === "RR") reads("CF");
      writeTarget(target);
      writes(ALL);
      break;
    }
    case "BIT":
      readOperand(y);
      writes(NO_CARRY);
      break;
    case "SET":
    case "RES":
      readOperand(y);
      writeTarget(y);
      break;
    case "RLD":
    case "RRD":
      e.memWrite = true;
      reads("A", "H", "L");
      writes("A", NO_CARRY);
      break;
    case "LDI":
    case "LDD":
    case "LDIR":
    case "LDDR":
      e.memWrite = true;
      reads("B", "C", "D", "E", "H", "L");
      writes("B", "C", "D", "E", "H", "L", "PF", "HF");
      break;
    case "CPI":
    case "CPD":
    case "CPIR":
    case "CPDR":
      reads("A", "B", "C", "H", "L");
      writes("B", "C", "H", "L", NO_CARRY);
      break;
    case "IN":
      if (a.length === 2) {
        readOperand(y);
        writes(x.units);
        if (y.name === "(C)") writes(NO_CARRY);
      }
      break;
    case "OUT":
      e.memWrite = true;
      readOperand(x);
      readOperand(y);
      break;
    case "INI":
    case "IND":
    case "INIR":
    case "INDR":
    case "OUTI":
    case "OUTD":
    case "OTIR":
    case "OTDR":
      e.memWrite = true;
      reads("B", "C", "H", "L");
      writes("B", "H", "L", ALL);
      break;
    case "DJNZ":
      reads("B");
      writes("B");
      e.flow = "branch";
      e.target = args[0];
      break;
    case "JP":
    case "JR":
      if (a.length === 2) {
        reads(condition(args[0]));
        e.flow = "branch";
        e.target = args[1];
        e.cond = args[0].toUpperCase();
      } else if (x.kind === "mem") {
        readOperand(x);
        e.flow = "indirect";
      } else {
        e.flow = "jump";
        e.target = args[0];
      }
      break;
    case "CALL":
      if (a.length === 2) {
        reads(condition(args[0]));
        e.flow = "callIf";
        e.target = args[1];
        e.cond = args[0].toUpperCase();
      } else {
        e.flow = "call";
        e.target = args[0];
      }
      break;
    case "RST":
      e.flow = "call";
      e.target = args[0];
      break;
    case "RET":
      if (a.length === 1) {
        reads(condition(args[0]));
        e.flow = "retIf";
        e.cond = args[0].toUpperCase();
      } else {
        e.flow = "ret";
      }
      break;
    case "RETI":
    case "RETN":
      e.flow = "ret";
      break;
    case "NOP":
    case "HALT":
    case "DI":
    case "EI":
    case "IM":
      break;
    default:
      throw new Error(`no effects for ${op} ${args.join(",")}`);
  }
  e.reads = [...new Set(e.reads.filter(Boolean))];
  e.writes = [...new Set(e.writes.filter((u) => u && u !== "F"))];
  return e;
}
