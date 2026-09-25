export const MNEMONICS = Object.freeze([
  null,
  "NOP", "DI", "EI", "SCF", "CCF", "CPL", "DAA", "EXX", "HALT",
  "RLCA", "RRCA", "RLA", "RRA", "NEG", "RRD", "RLD", "LDI", "LDIR",
  "LDD", "LDDR", "CPI", "CPIR", "CPD", "CPDR", "INI", "INIR", "IND",
  "INDR", "OUTI", "OTIR", "OUTD", "OTDR", "RETI", "RETN",
  "RET", "EX", "IM", "RST", "INC", "DEC", "PUSH", "POP", "LD", "IN",
  "OUT", "BIT", "RES", "SET", "RLC", "RRC", "RL", "RR", "SLA", "SRA",
  "SLL", "SLS", "SRL", "ADD", "ADC", "SUB", "SBC", "AND", "XOR", "OR",
  "CP", "JP", "CALL", "JR", "DJNZ",
]);

export const M = Object.freeze(Object.fromEntries(
  MNEMONICS.flatMap((name, ordinal) => name === null ? [] : [[name, ordinal]]),
));

export const O = Object.freeze({
  B: 0, C: 1, D: 2, E: 3, H: 4, L: 5, MEM_HL: 6, A: 7,
  BC: 8, DE: 9, HL: 10, SP: 11, AF: 15,
  IX: 16, IY: 17,
  IXH: 20, IXL: 21, IYH: 28, IYL: 29,
  I: 32, R: 33,
  MEM_BC: 40, MEM_DE: 41,
  INDEX_IX: 48, INDEX_IY: 49, MEM_ABS: 50,
  IMM8: 51, IMM16: 52, PORT_C: 53, REL8: 54, ZERO: 55,
  MEM_IX: 56, MEM_IY: 57, MEM_SP: 58, AF_PRIME: 59,
  NZ: 64, Z: 65, NC: 66, CC: 67, PO: 68, PE: 69, P: 70, MM: 71,
  BIT0: 72, BIT1: 73, BIT2: 74, BIT3: 75,
  BIT4: 76, BIT5: 77, BIT6: 78, BIT7: 79,
  RST0: 80, RST8: 81, RST16: 82, RST24: 83,
  RST32: 84, RST40: 85, RST48: 86, RST56: 87,
  IM0: 88, IM1: 89, IM2: 90,
  NONE: 255,
});

export function instruction(mnemonic, operands = [], values = []) {
  const record = new Uint8Array(10);
  record.fill(O.NONE, 1, 4);
  record[0] = typeof mnemonic === "number" ? mnemonic : M[mnemonic.toUpperCase()];
  for (let index = 0; index < Math.min(3, operands.length); index += 1) {
    record[1 + index] = operands[index];
    const value = values[index] ?? 0;
    record[4 + index * 2] = value & 0xff;
    record[5 + index * 2] = (value >>> 8) & 0xff;
  }
  return record;
}

const RADIX40 = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";

export function radix40Code(character) {
  return RADIX40.indexOf(character.toUpperCase());
}

export function packRadix40(text) {
  if (text.length < 1 || text.length > 8) return undefined;
  const codes = [...text].map(radix40Code);
  if (codes.some((code) => code < 1)) return undefined;
  const words = [];
  for (let offset = 0; offset < 6; offset += 3) {
    words.push((codes[offset] ?? 0) * 1600 + (codes[offset + 1] ?? 0) * 40 + (codes[offset + 2] ?? 0));
  }
  words.push((codes[6] ?? 0) * 40 + (codes[7] ?? 0));
  return words;
}
