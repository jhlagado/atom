/**
 * Create an Atom execution adapter backed by Triptych's WASM CPU binding.
 *
 * This module deliberately depends on an injected `TriptychCpu` constructor.
 * Atom therefore does not acquire a Triptych, Rust or browser dependency; a
 * host chooses the machine implementation at the edge.  The returned surface
 * is the same small adapter used by the native Atom runner, so service calls
 * remain in the host runner rather than leaking into the CPU implementation.
 */

const HEX_DIGITS = /^[0-9a-fA-F]+$/;

const checkedByte = (value, name) => {
  if (!Number.isInteger(value) || value < 0 || value > 0xff) {
    throw new TypeError(`${name} must be an 8-bit value`);
  }
  return value;
};

const checkedWord = (value, name) => {
  if (!Number.isInteger(value) || value < 0 || value > 0xffff) {
    throw new TypeError(`${name} must be a 16-bit value`);
  }
  return value;
};

const parseHexByte = (text, offset) => {
  const pair = text.slice(offset, offset + 2);
  if (pair.length !== 2 || !HEX_DIGITS.test(pair)) {
    throw new TypeError("invalid Intel HEX byte");
  }
  return Number.parseInt(pair, 16);
};

const parseIntelHex = (hexText) => {
  if (typeof hexText !== "string") {
    throw new TypeError("execution image must be Intel HEX text");
  }
  const memory = new Uint8Array(0x10000);
  const written = new Uint8Array(memory.length);
  let upper = 0;
  let ended = false;
  for (const [lineNumber, rawLine] of hexText.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (line === "") continue;
    if (ended || !line.startsWith(":")) {
      throw new TypeError(`invalid Intel HEX record at line ${lineNumber + 1}`);
    }
    if ((line.length - 1) % 2 !== 0) {
      throw new TypeError(`odd Intel HEX record at line ${lineNumber + 1}`);
    }
    const byteCount = parseHexByte(line, 1);
    const expectedLength = 1 + (byteCount + 5) * 2;
    if (line.length !== expectedLength) {
      throw new TypeError(`invalid Intel HEX length at line ${lineNumber + 1}`);
    }
    let checksum = 0;
    for (let offset = 1; offset < line.length; offset += 2) {
      checksum = (checksum + parseHexByte(line, offset)) & 0xff;
    }
    if (checksum !== 0) {
      throw new TypeError(`invalid Intel HEX checksum at line ${lineNumber + 1}`);
    }
    const address = (parseHexByte(line, 3) << 8) | parseHexByte(line, 5);
    const type = parseHexByte(line, 7);
    const dataStart = 9;
    if (type === 0x00) {
      const start = upper + address;
      if (start + byteCount > memory.length) {
        throw new TypeError(`Intel HEX data crosses 64 KiB at line ${lineNumber + 1}`);
      }
      for (let index = 0; index < byteCount; index += 1) {
        const value = parseHexByte(line, dataStart + index * 2);
        const at = start + index;
        if (written[at] !== 0 && memory[at] !== value) {
          throw new TypeError(`conflicting Intel HEX data at $${at.toString(16)}`);
        }
        memory[at] = value;
        written[at] = 1;
      }
    } else if (type === 0x01) {
      if (byteCount !== 0 || address !== 0) {
        throw new TypeError("invalid Intel HEX end record");
      }
      ended = true;
    } else if (type === 0x02) {
      if (byteCount !== 2) throw new TypeError("invalid Intel HEX segment record");
      upper = ((parseHexByte(line, dataStart) << 8) | parseHexByte(line, dataStart + 2)) << 4;
    } else if (type === 0x04) {
      if (byteCount !== 2) throw new TypeError("invalid Intel HEX linear record");
      upper = ((parseHexByte(line, dataStart) << 8) | parseHexByte(line, dataStart + 2)) << 16;
      if (upper > 0xffff) throw new TypeError("Intel HEX address exceeds Z80 space");
    } else if (type !== 0x03 && type !== 0x05) {
      throw new TypeError(`unsupported Intel HEX record type ${type}`);
    }
  }
  const writeRanges = [];
  let start;
  for (let address = 0; address <= memory.length; address += 1) {
    if (address < memory.length && written[address] !== 0) {
      start ??= address;
    } else if (start !== undefined) {
      writeRanges.push({ start, end: address });
      start = undefined;
    }
  }
  return { memory, writeRanges };
};

const readState = (machine) => {
  const state = machine.cpu_state();
  const flags = state.flags();
  return {
    a: state.a(),
    c: state.c(),
    d: state.d(),
    e: state.e(),
    h: state.h(),
    l: state.l(),
    ix: state.ix(),
    sp: state.sp(),
    pc: state.pc(),
    halted: state.halted(),
    flags: {
      S: flags.s() ? 1 : 0,
      Z: flags.z() ? 1 : 0,
      Y: flags.y() ? 1 : 0,
      H: flags.h() ? 1 : 0,
      X: flags.x() ? 1 : 0,
      P: flags.p() ? 1 : 0,
      N: flags.n() ? 1 : 0,
      C: flags.c() ? 1 : 0,
    },
  };
};

const installState = (machine, cpu) => {
  machine.set_execution_cpu_field("a", checkedByte(cpu.a, "A"));
  machine.set_execution_cpu_field("c", checkedByte(cpu.c, "C"));
  machine.set_execution_cpu_field("d", checkedByte(cpu.d, "D"));
  machine.set_execution_cpu_field("e", checkedByte(cpu.e, "E"));
  machine.set_execution_cpu_field("h", checkedByte(cpu.h, "H"));
  machine.set_execution_cpu_field("l", checkedByte(cpu.l, "L"));
  machine.set_execution_cpu_field("ix", checkedWord(cpu.ix, "IX"));
  machine.set_execution_cpu_field("sp", checkedWord(cpu.sp, "SP"));
  machine.set_execution_cpu_field("pc", checkedWord(cpu.pc, "PC"));
  machine.set_execution_cpu_field("halted", cpu.halted ? 1 : 0);
  for (const flag of ["s", "z", "y", "h", "x", "p", "n", "c"]) {
    machine.set_execution_cpu_field(
      `f.${flag}`,
      cpu.flags[flag.toUpperCase()] ? 1 : 0,
    );
  }
};

export const createTriptychWasmExecutionAdapter = ({
  TriptychCpu,
  bootRom = new Uint8Array(256),
} = {}) => {
  if (typeof TriptychCpu !== "function") {
    throw new TypeError("TriptychCpu constructor is required");
  }
  if (!(bootRom instanceof Uint8Array) || bootRom.length !== 256) {
    throw new TypeError("bootRom must contain exactly 256 bytes");
  }
  return Object.freeze({
    parseImage: parseIntelHex,
    create({ hexText, entry, romRanges: _romRanges }) {
      checkedWord(entry, "execution entry");
      const image = parseIntelHex(hexText);
      const machine = new TriptychCpu(bootRom);
      machine.disable_boot_rom_for_execution();
      // Keep the runner's mutable memory in ordinary JS-owned storage.  A
      // wasm-bindgen `Uint8Array::view` can be detached when the module grows
      // its linear memory for a later host allocation; a detached view would
      // make the runner observe `undefined` bytes.  Synchronise at the
      // instruction boundary instead, which is slower but deterministic and
      // keeps this adapter suitable for conformance rather than production
      // bulk execution.
      const memory = image.memory.slice();
      machine.write_ram(0, memory);
      const cpu = readState(machine);
      // Triptych deliberately exposes its machine reset state (A=$FF, C=1,
      // SP=$FFFF).  Atom's existing execution seam starts a freshly-created
      // core with the reference harness's zeroed general state; normalize the
      // fields that the runner can observe before handing control over.
      cpu.a = 0;
      cpu.c = 0;
      cpu.d = 0;
      cpu.e = 0;
      cpu.h = 0;
      cpu.l = 0;
      cpu.ix = 0;
      cpu.sp = 0;
      cpu.pc = entry;
      for (const flag of Object.keys(cpu.flags)) cpu.flags[flag] = 0;
      installState(machine, cpu);
      return {
        hardware: { memory },
        cpu,
        step() {
          machine.write_ram(0, memory);
          installState(machine, cpu);
          const cycles = machine.step(false);
          memory.set(machine.read_ram(0, 0x10000));
          Object.assign(cpu, readState(machine));
          return { cycles };
        },
        isHalted() {
          return cpu.halted;
        },
      };
    },
  });
};
