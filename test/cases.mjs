import { instruction, M, O } from "../src/abi.mjs";

const IMM8 = [0, 1, 127, 128, 255];
const IMM16 = [0, 1, 0x7fff, 0x8000, 0xffff];
const DISP8 = [-128, -1, 0, 1, 127];

const hex = (value, width = 2) => `$${(value >>> 0).toString(16).toUpperCase().padStart(width, "0")}`;
const indexed = (family, displacement) =>
  `(${family}${displacement < 0 ? "-" : "+"}${Math.abs(displacement)})`;

const reg8 = [
  ["B", O.B], ["C", O.C], ["D", O.D], ["E", O.E],
  ["H", O.H], ["L", O.L], ["A", O.A],
];
const reg16 = [["BC", O.BC], ["DE", O.DE], ["HL", O.HL], ["SP", O.SP]];
const index16 = [["IX", O.IX], ["IY", O.IY]];
const halves = [["IXH", O.IXH], ["IXL", O.IXL], ["IYH", O.IYH], ["IYL", O.IYL]];
const conditions = [
  ["NZ", O.NZ], ["Z", O.Z], ["NC", O.NC], ["C", O.CC],
  ["PO", O.PO], ["PE", O.PE], ["P", O.P], ["M", O.MM],
];
const relativeConditions = conditions.slice(0, 4);

function add(cases, source, mnemonic, operands = [], values = [], tags = []) {
  cases.push({ source, record: instruction(mnemonic, operands, values), tags });
}

export function validCases() {
  const cases = [];

  for (const name of [
    "NOP", "DI", "EI", "SCF", "CCF", "CPL", "DAA", "EXX", "HALT",
    "RLCA", "RRCA", "RLA", "RRA", "NEG", "RRD", "RLD", "LDI", "LDIR",
    "LDD", "LDDR", "CPI", "CPIR", "CPD", "CPDR", "INI", "INIR", "IND",
    "INDR", "OUTI", "OTIR", "OUTD", "OTDR", "RETI", "RETN",
  ]) add(cases, name, name);

  add(cases, "RET", "RET");
  for (const [name, code] of conditions) add(cases, `RET ${name}`, "RET", [code]);

  for (const [source, operands] of [
    ["EX AF,AF'", [O.AF, O.AF_PRIME]],
    ["EX DE,HL", [O.DE, O.HL]],
    ["EX (SP),HL", [O.MEM_SP, O.HL]],
    ["EX (SP),IX", [O.MEM_SP, O.IX]],
    ["EX (SP),IY", [O.MEM_SP, O.IY]],
  ]) add(cases, source, "EX", operands);

  for (let mode = 0; mode <= 2; mode += 1) add(cases, `IM ${mode}`, "IM", [O.IM0 + mode]);
  for (let vector = 0; vector <= 56; vector += 8) {
    add(cases, `RST ${vector}`, "RST", [O.RST0 + vector / 8]);
  }

  for (const mnemonic of ["INC", "DEC"]) {
    for (const [name, code] of [...reg8, ...reg16, ...index16, ...halves, ["(HL)", O.MEM_HL]]) {
      add(cases, `${mnemonic} ${name}`, mnemonic, [code]);
    }
    for (const [family, code] of [["IX", O.INDEX_IX], ["IY", O.INDEX_IY]]) {
      for (const displacement of DISP8) {
        add(cases, `${mnemonic} ${indexed(family, displacement)}`, mnemonic, [code], [displacement]);
      }
    }
  }

  for (const mnemonic of ["PUSH", "POP"]) {
    for (const [name, code] of [...reg16.slice(0, 3), ["AF", O.AF], ...index16]) {
      add(cases, `${mnemonic} ${name}`, mnemonic, [code]);
    }
  }

  for (const [targetName, target] of reg8) {
    for (const [sourceName, source] of reg8) {
      add(cases, `LD ${targetName},${sourceName}`, "LD", [target, source], [], ["ld"]);
    }
    for (const value of IMM8) {
      add(cases, `LD ${targetName},${hex(value)}`, "LD", [target, O.IMM8], [0, value], ["ld"]);
    }
    add(cases, `LD ${targetName},(HL)`, "LD", [target, O.MEM_HL], [], ["ld"]);
  }
  for (const value of IMM16) {
    add(cases, `LD A,(${hex(value, 4)})`, "LD", [O.A, O.MEM_ABS], [0, value], ["ld"]);
    add(cases, `LD (${hex(value, 4)}),A`, "LD", [O.MEM_ABS, O.A], [value, 0], ["ld"]);
  }
  for (const [memory, code] of [["(BC)", O.MEM_BC], ["(DE)", O.MEM_DE]]) {
    add(cases, `LD A,${memory}`, "LD", [O.A, code], [], ["ld"]);
    add(cases, `LD ${memory},A`, "LD", [code, O.A], [], ["ld"]);
  }
  add(cases, "LD A,I", "LD", [O.A, O.I], [], ["ld"]);
  add(cases, "LD A,R", "LD", [O.A, O.R], [], ["ld"]);
  add(cases, "LD I,A", "LD", [O.I, O.A], [], ["ld"]);
  add(cases, "LD R,A", "LD", [O.R, O.A], [], ["ld"]);

  for (const family of ["IX", "IY"]) {
    const familyHalves = halves.filter(([name]) => name.startsWith(family));
    const compatible = [...reg8.filter(([name]) => name !== "H" && name !== "L"), ...familyHalves];
    for (const [targetName, target] of compatible) {
      for (const [sourceName, source] of compatible) {
        if (!familyHalves.some(([, code]) => code === target) && !familyHalves.some(([, code]) => code === source)) continue;
        add(cases, `LD ${targetName},${sourceName}`, "LD", [target, source], [], ["ld", "index-half"]);
      }
    }
  }

  for (const [targetName, target] of reg16) {
    for (const value of IMM16) {
      add(cases, `LD ${targetName},${hex(value, 4)}`, "LD", [target, O.IMM16], [0, value], ["ld"]);
      add(cases, `LD ${targetName},(${hex(value, 4)})`, "LD", [target, O.MEM_ABS], [0, value], ["ld"]);
      add(cases, `LD (${hex(value, 4)}),${targetName}`, "LD", [O.MEM_ABS, target], [value, 0], ["ld"]);
    }
  }
  for (const [targetName, target] of index16) {
    for (const value of IMM16) {
      add(cases, `LD ${targetName},${hex(value, 4)}`, "LD", [target, O.IMM16], [0, value], ["ld"]);
      add(cases, `LD ${targetName},(${hex(value, 4)})`, "LD", [target, O.MEM_ABS], [0, value], ["ld"]);
      add(cases, `LD (${hex(value, 4)}),${targetName}`, "LD", [O.MEM_ABS, target], [value, 0], ["ld"]);
    }
  }
  for (const [sourceName, source] of [["HL", O.HL], ["IX", O.IX], ["IY", O.IY]]) {
    add(cases, `LD SP,${sourceName}`, "LD", [O.SP, source], [], ["ld"]);
  }
  add(cases, "LD HL,DE", "LD", [O.HL, O.DE], [], ["ld", "azm-legacy"]);
  add(cases, "LD BC,DE", "LD", [O.BC, O.DE], [], ["ld", "azm-legacy"]);

  for (const [sourceName, source] of reg8) add(cases, `LD (HL),${sourceName}`, "LD", [O.MEM_HL, source], [], ["ld"]);
  for (const value of IMM8) add(cases, `LD (HL),${hex(value)}`, "LD", [O.MEM_HL, O.IMM8], [0, value], ["ld"]);
  for (const [family, indexedCode] of [["IX", O.INDEX_IX], ["IY", O.INDEX_IY]]) {
    for (const displacement of DISP8) {
      const memory = indexed(family, displacement);
      for (const [registerName, register] of reg8) {
        add(cases, `LD ${registerName},${memory}`, "LD", [register, indexedCode], [0, displacement], ["ld"]);
        add(cases, `LD ${memory},${registerName}`, "LD", [indexedCode, register], [displacement, 0], ["ld"]);
      }
      for (const value of IMM8) {
        add(cases, `LD ${memory},${hex(value)}`, "LD", [indexedCode, O.IMM8], [displacement, value], ["ld"]);
      }
    }
  }

  add(cases, "IN (C)", "IN", [O.PORT_C]);
  for (const [name, code] of reg8) add(cases, `IN ${name},(C)`, "IN", [code, O.PORT_C]);
  for (const value of IMM8) add(cases, `IN A,(${hex(value)})`, "IN", [O.A, O.IMM8], [0, value]);
  for (const [name, code] of reg8) add(cases, `OUT (C),${name}`, "OUT", [O.PORT_C, code]);
  add(cases, "OUT (C),0", "OUT", [O.PORT_C, O.ZERO]);
  for (const value of IMM8) add(cases, `OUT (${hex(value)}),A`, "OUT", [O.IMM8, O.A], [value, 0]);

  for (const mnemonic of ["BIT", "RES", "SET"]) {
    for (let bit = 0; bit < 8; bit += 1) {
      const bitCode = O.BIT0 + bit;
      for (const [name, code] of [...reg8, ["(HL)", O.MEM_HL]]) {
        add(cases, `${mnemonic} ${bit},${name}`, mnemonic, [bitCode, code]);
      }
      for (const [family, indexedCode] of [["IX", O.INDEX_IX], ["IY", O.INDEX_IY]]) {
        for (const displacement of DISP8) {
          const memory = indexed(family, displacement);
          add(cases, `${mnemonic} ${bit},${memory}`, mnemonic, [bitCode, indexedCode], [0, displacement]);
          if (mnemonic !== "BIT") {
            for (const [destinationName, destination] of reg8) {
              add(cases, `${mnemonic} ${bit},${memory},${destinationName}`, mnemonic, [bitCode, indexedCode, destination], [0, displacement]);
            }
          }
        }
      }
    }
  }

  for (const mnemonic of ["RLC", "RRC", "RL", "RR", "SLA", "SRA", "SLL", "SLS", "SRL"]) {
    for (const [name, code] of [...reg8, ["(HL)", O.MEM_HL]]) add(cases, `${mnemonic} ${name}`, mnemonic, [code]);
    for (const [family, indexedCode] of [["IX", O.INDEX_IX], ["IY", O.INDEX_IY]]) {
      for (const displacement of DISP8) {
        const memory = indexed(family, displacement);
        add(cases, `${mnemonic} ${memory}`, mnemonic, [indexedCode], [displacement]);
        for (const [destinationName, destination] of reg8) {
          add(cases, `${mnemonic} ${memory},${destinationName}`, mnemonic, [indexedCode, destination], [displacement]);
        }
      }
    }
  }

  for (const mnemonic of ["ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR", "CP"]) {
    const acceptsUnary = !["ADD", "ADC", "SBC"].includes(mnemonic);
    const sources = [...reg8, ["(HL)", O.MEM_HL], ...halves];
    for (const [name, code] of sources) {
      if (acceptsUnary) add(cases, `${mnemonic} ${name}`, mnemonic, [code]);
      add(cases, `${mnemonic} A,${name}`, mnemonic, [code], [], ["source-alias"]);
    }
    for (const value of IMM8) {
      if (acceptsUnary) add(cases, `${mnemonic} ${hex(value)}`, mnemonic, [O.IMM8], [value]);
      add(cases, `${mnemonic} A,${hex(value)}`, mnemonic, [O.IMM8], [value], ["source-alias"]);
    }
    for (const [family, indexedCode] of [["IX", O.INDEX_IX], ["IY", O.INDEX_IY]]) {
      for (const displacement of DISP8) {
        const memory = indexed(family, displacement);
        if (acceptsUnary) add(cases, `${mnemonic} ${memory}`, mnemonic, [indexedCode], [displacement]);
        add(cases, `${mnemonic} A,${memory}`, mnemonic, [indexedCode], [displacement], ["source-alias"]);
      }
    }
  }
  for (const [sourceName, source] of reg16) add(cases, `ADD HL,${sourceName}`, "ADD", [O.HL, source]);
  for (const [targetName, target] of index16) {
    for (const [sourceName, source] of [["BC", O.BC], ["DE", O.DE], [targetName, target], ["SP", O.SP]]) {
      add(cases, `ADD ${targetName},${sourceName}`, "ADD", [target, source]);
    }
  }
  for (const mnemonic of ["ADC", "SBC"]) {
    for (const [sourceName, source] of reg16) add(cases, `${mnemonic} HL,${sourceName}`, mnemonic, [O.HL, source]);
  }

  for (const value of IMM16) add(cases, `JP ${hex(value, 4)}`, "JP", [O.IMM16], [value]);
  for (const [name, code] of conditions) {
    for (const value of IMM16) add(cases, `JP ${name},${hex(value, 4)}`, "JP", [code, O.IMM16], [0, value]);
  }
  for (const [source, code] of [["(HL)", O.MEM_HL], ["(IX)", O.MEM_IX], ["(IY)", O.MEM_IY]]) add(cases, `JP ${source}`, "JP", [code]);
  for (const value of IMM16) add(cases, `CALL ${hex(value, 4)}`, "CALL", [O.IMM16], [value]);
  for (const [name, code] of conditions) {
    for (const value of IMM16) add(cases, `CALL ${name},${hex(value, 4)}`, "CALL", [code, O.IMM16], [0, value]);
  }
  for (const displacement of DISP8) {
    const target = (0x4002 + displacement) & 0xffff;
    add(cases, `JR ${hex(target, 4)}`, "JR", [O.REL8], [displacement]);
    add(cases, `DJNZ ${hex(target, 4)}`, "DJNZ", [O.REL8], [displacement]);
    for (const [name, code] of relativeConditions) add(cases, `JR ${name},${hex(target, 4)}`, "JR", [code, O.REL8], [0, displacement]);
  }

  return cases;
}

export function invalidCases() {
  const cases = [];
  const bad = (source, mnemonic, operands = [], values = []) =>
    cases.push({ source, record: instruction(mnemonic, operands, values) });

  bad("NOP A", "NOP", [O.A]);
  bad("RET Q", "RET", [O.IMM8]);
  bad("EX BC,DE", "EX", [O.BC, O.DE]);
  for (const mode of [-1, 3, 255]) bad(`IM ${mode}`, "IM", [O.IMM8], [mode]);
  for (const vector of [1, 7, 9, 55, 57, 255]) bad(`RST ${vector}`, "RST", [O.IMM8], [vector]);
  bad("INC (BC)", "INC", [O.MEM_BC]);
  bad("DEC 1", "DEC", [O.IMM8], [1]);
  bad("PUSH A", "PUSH", [O.A]);
  bad("POP IXH", "POP", [O.IXH]);
  bad("IN B,($12)", "IN", [O.B, O.IMM8], [0, 0x12]);
  bad("IN IXH,(C)", "IN", [O.IXH, O.PORT_C]);
  bad("OUT ($12),B", "OUT", [O.IMM8, O.B], [0x12, 0]);
  bad("OUT (C),1", "OUT", [O.PORT_C, O.IMM8], [0, 1]);
  bad("BIT 8,A", "BIT", [O.IMM8, O.A], [8]);
  bad("BIT 1,(IX+0),A", "BIT", [O.BIT1, O.INDEX_IX, O.A]);
  bad("RES 1,A,B", "RES", [O.BIT1, O.A, O.B]);
  bad("RLC A,B", "RLC", [O.A, O.B]);
  bad("ADD BC,DE", "ADD", [O.BC, O.DE]);
  bad("ADC IX,BC", "ADC", [O.IX, O.BC]);
  bad("SUB HL,BC", "SUB", [O.HL, O.BC]);
  bad("JP (BC)", "JP", [O.MEM_BC]);
  bad("JP PO,(HL)", "JP", [O.PO, O.MEM_HL]);
  bad("CALL (HL)", "CALL", [O.MEM_HL]);
  bad("JR PO,$4002", "JR", [O.PO, O.REL8]);
  bad("DJNZ Z,$4002", "DJNZ", [O.Z, O.REL8]);

  const ldOperands = [
    ...reg8, ...reg16, ...index16, ...halves,
    ["I", O.I], ["R", O.R], ["(BC)", O.MEM_BC], ["(DE)", O.MEM_DE],
    ["(HL)", O.MEM_HL], ["(IX+1)", O.INDEX_IX], ["(IY-1)", O.INDEX_IY],
    ["($1234)", O.MEM_ABS], ["$12", O.IMM8],
  ];
  for (const [leftName, left] of ldOperands) {
    for (const [rightName, rightInitial] of ldOperands) {
      let right = rightInitial;
      if (right === O.IMM8 && ([O.BC, O.DE, O.HL, O.SP, O.IX, O.IY].includes(left))) right = O.IMM16;
      const source = `LD ${leftName},${rightName}`;
      const record = instruction("LD", [left, right], [left === O.INDEX_IX ? 1 : left === O.INDEX_IY ? -1 : 0, right === O.INDEX_IX ? 1 : right === O.INDEX_IY ? -1 : right === O.MEM_ABS ? 0x1234 : right === O.IMM8 || right === O.IMM16 ? 0x12 : 0]);
      cases.push({ source, record, matrix: true });
    }
  }
  return cases;
}

export function systematicInvalidRecords() {
  const none = O.NONE;
  const records = [];
  for (const ordinal of [0, ...Array.from({ length: 186 }, (_, index) => index + 70)]) {
    records.push(new Uint8Array([ordinal, none, none, none, 0, 0, 0, 0, 0, 0]));
  }

  const incClasses = new Set([
    O.B, O.C, O.D, O.E, O.H, O.L, O.MEM_HL, O.A,
    O.BC, O.DE, O.HL, O.SP, O.IX, O.IY, O.IXH, O.IXL, O.IYH, O.IYL,
    O.INDEX_IX, O.INDEX_IY,
  ]);
  for (let operandClass = 0; operandClass < 256; operandClass += 1) {
    if (!incClasses.has(operandClass)) {
      records.push(new Uint8Array([M.INC, operandClass, none, none, 0, 0, 0, 0, 0, 0]));
    }
  }

  const hidden = new Map();
  for (const { record } of validCases()) {
    if (record[3] !== none) continue;
    const optionalIndexedDestination =
      (record[0] === M.RES || record[0] === M.SET) &&
      (record[2] === O.INDEX_IX || record[2] === O.INDEX_IY);
    if (optionalIndexedDestination) continue;
    const changed = record.slice();
    changed[3] = O.B;
    hidden.set(Buffer.from(changed).toString("hex"), changed);
  }
  records.push(...hidden.values());
  return records;
}

export const boundaries = { IMM8, IMM16, DISP8 };
