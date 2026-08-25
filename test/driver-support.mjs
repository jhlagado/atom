import assert from "node:assert/strict";
import fs from "node:fs";

import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

import { loadNativeAtomCore } from "../src/host/index.mjs";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const writeWord = (memory, address, value) => {
  memory[address] = value & 0xff;
  memory[address + 1] = value >>> 8;
};
const manifest = JSON.parse(fs.readFileSync("proofs/phase-3.json", "utf8"));

const PROOF_SYMBOLS = Object.freeze({
  AtomDriverProofAdapterWorkspaceStart: 0x6000,
  AtomDriverProofLogNext: 0x6000,
  AtomDriverProofFailAfter: 0x6002,
  AtomDriverProofFailBegin: 0x6003,
  AtomDriverProofFailCommit: 0x6004,
  AtomDriverProofOpen: 0x6005,
  AtomDriverProofBegan: 0x6006,
  AtomDriverProofCommitted: 0x6007,
  AtomDriverProofAborted: 0x6008,
  AtomDriverProofBeginDescriptor: 0x6009,
  AtomDriverProofCommitDescriptor: 0x600b,
  AtomDriverProofCommitCursor: 0x600d,
  AtomDriverProofCommitRemaining: 0x600f,
  AtomDriverProofAdapterWorkspaceEnd: 0x6018,
  AtomDriverProofSourceStart: 0x8000,
  AtomDriverSourceBefore: 0x8000,
  AtomDriverSource: 0x8001,
  AtomDriverSourceLimit: 0x8301,
  AtomDriverSourceAfter: 0x8301,
  AtomDriverProofSourceEnd: 0x8302,
  AtomDriverProofDescriptorStart: 0x8302,
  AtomDriverDescriptorBefore: 0x8302,
  AtomDriverBuildDescriptor: 0x8303,
  AtomDriverPartDescriptors: 0x8312,
  AtomDriverDescriptorAfter: 0x880d,
  AtomDriverProofDescriptorEnd: 0x880e,
  AtomDriverProofSymbolStart: 0x9000,
  AtomDriverSymbolBefore: 0x9000,
  AtomDriverSymbolArena: 0x9001,
  AtomDriverSymbolLimit: 0x9101,
  AtomDriverSymbolAfter: 0x9101,
  AtomDriverProofSymbolEnd: 0x9102,
  AtomDriverProofPendingStart: 0x9200,
  AtomDriverPendingBefore: 0x9200,
  AtomDriverPendingArena: 0x9201,
  AtomDriverPendingLimit: 0x9271,
  AtomDriverPendingAfter: 0x9271,
  AtomDriverProofPendingEnd: 0x9272,
  AtomDriverProofLogStart: 0x9400,
  AtomDriverLogBefore: 0x9400,
  AtomDriverProofLog: 0x9401,
  AtomDriverProofLogLimit: 0x9801,
  AtomDriverLogAfter: 0x9801,
  AtomDriverProofLogEnd: 0x9802,
});

export async function createDriverHarness() {
  const core = await loadNativeAtomCore();
  assert.equal(core.source, "native/atom.asm");
  const symbols = Object.freeze({ ...core.symbols, ...PROOF_SYMBOLS });
  const runtime = createZ80Runtime(parseIntelHex(core.hexText), symbols.AtomAssemble);
  const memory = runtime.hardware.memory;
  for (const [name, value] of [
    ["AtomDriverSourceBefore", 0x3c], ["AtomDriverSourceAfter", 0xc3],
    ["AtomDriverDescriptorBefore", 0x69], ["AtomDriverDescriptorAfter", 0x96],
    ["AtomDriverSymbolBefore", 0x39], ["AtomDriverSymbolAfter", 0x93],
    ["AtomDriverPendingBefore", 0x4b], ["AtomDriverPendingAfter", 0xb4],
    ["AtomDriverLogBefore", 0x5a], ["AtomDriverLogAfter", 0xa5],
  ]) memory[symbols[name]] = value;
  const pristine = memory.slice();
  const immutable = core.codeRanges.map(({ start, end }) => ({ start, bytes: pristine.slice(start, end) }));
  const workspace = [
    [symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd],
    [symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd],
    [symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd],
    [symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd],
    [symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd],
    [symbols.AtomOutputWorkspaceStart, symbols.AtomOutputWorkspaceEnd],
    [symbols.AtomStatementWorkspaceStart, symbols.AtomStatementWorkspaceEnd],
    [symbols.AtomDriverWorkspaceStart, symbols.AtomDriverWorkspaceEnd],
  ];
  const statistics = {};
  let sourceSnapshot = new Uint8Array();
  let descriptorSnapshot = new Uint8Array();
  let restartCount = 0;
  let interceptedWrites = null;

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    restartCount += 1;
    for (const [start, end] of [...workspace, [symbols.AtomDriverProofAdapterWorkspaceStart, symbols.AtomDriverProofAdapterWorkspaceEnd]]) {
      for (let address = start; address < end; address += 1) {
        memory[address] = (restartCount * 73 + address * 29) & 0xff;
      }
    }
    sourceSnapshot = memory.slice(symbols.AtomDriverSource, symbols.AtomDriverSourceLimit);
    descriptorSnapshot = memory.slice(symbols.AtomDriverBuildDescriptor, symbols.AtomDriverDescriptorAfter);
  }

  const inside = (address, start, end) => address >= start && address < end;

  function resetAdapter() {
    memory.fill(0, symbols.AtomDriverProofAdapterWorkspaceStart, symbols.AtomDriverProofAdapterWorkspaceEnd);
    writeWord(memory, symbols.AtomDriverProofLogNext, symbols.AtomDriverProofLog);
  }

  function writeServiceByte(address, value) {
    assert.ok(interceptedWrites, "sink write outside an executing native entry");
    memory[address] = value;
    interceptedWrites.add(address);
  }

  function writeServiceWord(address, value) {
    writeServiceByte(address, value & 0xff);
    writeServiceByte(address + 1, value >>> 8);
  }

  function appendOperation(kind, bank, address, bytes) {
    if (memory[symbols.AtomDriverProofOpen] === 0) return 0xef;
    let failAfter = memory[symbols.AtomDriverProofFailAfter];
    if (failAfter !== 0) {
      failAfter -= 1;
      writeServiceByte(symbols.AtomDriverProofFailAfter, failAfter);
      if (failAfter === 0) return 0xe1;
    }
    const next = word(memory, symbols.AtomDriverProofLogNext);
    const required = 6 + bytes.length;
    if (next > symbols.AtomDriverProofLogLimit || symbols.AtomDriverProofLogLimit - next < required) return 0xe2;
    for (const [offset, value] of [kind, bank, address & 0xff, address >>> 8, bytes.length, 0, ...bytes].entries()) {
      writeServiceByte(next + offset, value);
    }
    writeServiceWord(symbols.AtomDriverProofLogNext, next + required);
    return 0;
  }

  function returnFromService(status) {
    const returnAddress = word(memory, runtime.cpu.sp);
    runtime.cpu.sp = (runtime.cpu.sp + 2) & 0xffff;
    runtime.cpu.pc = returnAddress;
    runtime.cpu.a = status;
    runtime.cpu.flags.C = status === 0 ? 0 : 1;
  }

  function interceptService() {
    const { cpu } = runtime;
    let status;
    if (cpu.pc === symbols.AtomSinkBegin) {
      if (memory[symbols.AtomDriverProofFailBegin] !== 0) {
        status = 0xe0;
      } else if (memory[symbols.AtomDriverProofOpen] !== 0) {
        status = 0xef;
      } else {
        writeServiceWord(symbols.AtomDriverProofBeginDescriptor, cpu.ix);
        writeServiceByte(symbols.AtomDriverProofOpen, 1);
        writeServiceByte(symbols.AtomDriverProofBegan, (memory[symbols.AtomDriverProofBegan] + 1) & 0xff);
        status = 0;
      }
    } else if (cpu.pc === symbols.AtomSinkImageByte) {
      status = appendOperation(1, cpu.c, (cpu.h << 8) | cpu.l, [cpu.a]);
    } else if (cpu.pc === symbols.AtomSinkPatchByte) {
      status = appendOperation(2, cpu.c, (cpu.h << 8) | cpu.l, [cpu.a]);
    } else if (cpu.pc === symbols.AtomSinkPatchWord) {
      status = appendOperation(2, cpu.c, (cpu.d << 8) | cpu.e, [cpu.l, cpu.h]);
    } else if (cpu.pc === symbols.AtomSinkCommit) {
      if (memory[symbols.AtomDriverProofOpen] === 0) {
        status = 0xef;
      } else if (memory[symbols.AtomDriverProofFailCommit] !== 0) {
        status = 0xe3;
      } else {
        writeServiceWord(symbols.AtomDriverProofCommitDescriptor, cpu.ix);
        writeServiceWord(symbols.AtomDriverProofCommitCursor, (cpu.h << 8) | cpu.l);
        writeServiceWord(symbols.AtomDriverProofCommitRemaining, (cpu.d << 8) | cpu.e);
        writeServiceByte(symbols.AtomDriverProofOpen, 0);
        writeServiceByte(symbols.AtomDriverProofCommitted, 1);
        status = 0;
      }
    } else if (cpu.pc === symbols.AtomSinkAbort) {
      if (memory[symbols.AtomDriverProofOpen] === 0) {
        status = 0xef;
      } else {
        writeServiceByte(symbols.AtomDriverProofOpen, 0);
        writeServiceByte(symbols.AtomDriverProofAborted, (memory[symbols.AtomDriverProofAborted] + 1) & 0xff);
        status = 0;
      }
    } else {
      return false;
    }
    returnFromService(status);
    return true;
  }

  function execute(entry, setup = () => {}, label = entry) {
    assert.ok(symbols[entry] !== undefined, `missing driver proof entry ${entry}`);
    setup(memory, symbols, runtime.cpu);
    memory[STACK_BEFORE] = 0x87;
    memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
    memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
    memory[STACK_AFTER] = 0x78;
    const before = memory.slice();
    runtime.cpu.sp = RETURN_SLOT;
    runtime.cpu.pc = symbols[entry];
    const serviceWrites = new Set();
    interceptedWrites = serviceWrites;
    const budget = manifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    let instructions = 0;
    let cycles = 0;
    const recent = [];
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      recent.push(runtime.cpu.pc);
      if (recent.length > 16) recent.shift();
      if (interceptService()) continue;
      const step = runtime.step();
      instructions += 1;
      cycles += step.cycles ?? 0;
    }
    assert.equal(runtime.cpu.pc, RETURN_SENTINEL, `${label}: did not return; recent ${recent.map((pc) => pc.toString(16)).join(" ")}`);
    assert.equal(runtime.cpu.sp, RETURN_SLOT + 2, `${label}: unbalanced stack`);
    assert.ok(instructions <= budget.maxInstructions, `${label}: instruction budget exceeded`);
    assert.ok(cycles <= budget.maxCycles, `${label}: cycle budget exceeded`);
    assert.equal(memory[STACK_BEFORE], 0x87, `${label}: stack underrun`);
    assert.equal(memory[STACK_AFTER], 0x78, `${label}: stack overrun`);
    assert.equal(memory[symbols.AtomDriverSourceBefore], 0x3c, `${label}: source-before canary`);
    assert.equal(memory[symbols.AtomDriverSourceAfter], 0xc3, `${label}: source-after canary`);
    assert.equal(memory[symbols.AtomDriverDescriptorBefore], 0x69, `${label}: descriptor-before canary`);
    assert.equal(memory[symbols.AtomDriverDescriptorAfter], 0x96, `${label}: descriptor-after canary`);
    assert.equal(memory[symbols.AtomDriverSymbolBefore], 0x39, `${label}: symbol-before canary`);
    assert.equal(memory[symbols.AtomDriverSymbolAfter], 0x93, `${label}: symbol-after canary`);
    assert.equal(memory[symbols.AtomDriverPendingBefore], 0x4b, `${label}: pending-before canary`);
    assert.equal(memory[symbols.AtomDriverPendingAfter], 0xb4, `${label}: pending-after canary`);
    assert.equal(memory[symbols.AtomDriverLogBefore], 0x5a, `${label}: log-before canary`);
    assert.equal(memory[symbols.AtomDriverLogAfter], 0xa5, `${label}: log-after canary`);
    assert.deepEqual(memory.slice(symbols.AtomDriverSource, symbols.AtomDriverSourceLimit), sourceSnapshot, `${label}: source changed`);
    assert.deepEqual(memory.slice(symbols.AtomDriverBuildDescriptor, symbols.AtomDriverDescriptorAfter), descriptorSnapshot, `${label}: descriptor changed`);
    for (const region of immutable) {
      assert.deepEqual(memory.slice(region.start, region.start + region.bytes.length), region.bytes, `${label}: immutable bytes changed`);
    }

    for (let address = 0; address < memory.length; address += 1) {
      const allowed = workspace.some(([start, end]) => inside(address, start, end)) ||
        serviceWrites.has(address) ||
        (entry === "AtomAssemble" && inside(address, symbols.AtomDriverSymbolArena, symbols.AtomDriverSymbolLimit)) ||
        (entry === "AtomAssemble" && inside(address, symbols.AtomDriverPendingArena, symbols.AtomDriverPendingLimit)) ||
        (address > STACK_BEFORE && address < STACK_AFTER);
      if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
    }
    interceptedWrites = null;

    const observed = statistics[entry] ?? { instructions: 0, cycles: 0, instructionCase: "", cycleCase: "" };
    if (instructions > observed.instructions) Object.assign(observed, { instructions, instructionCase: label });
    if (cycles > observed.cycles) Object.assign(observed, { cycles, cycleCase: label });
    statistics[entry] = observed;
    return {
      status: runtime.cpu.a,
      carry: runtime.cpu.flags.C,
      ix: runtime.cpu.ix,
      instructions,
      cycles,
      driverDetail: memory[symbols.AtomDriverDetail],
      statementDetail: memory[symbols.AtomStatementDetail],
      part: memory[symbols.AtomStatementErrorPart],
      offset: word(memory, symbols.AtomStatementErrorOffset),
      undefinedSymbol: word(memory, symbols.AtomDriverUndefinedSymbol),
    };
  }

  function installBuild(parts, options = {}) {
    const encoded = parts.map((part) => part instanceof Uint8Array ? part : new TextEncoder().encode(part));
    memory.fill(0xa5, symbols.AtomDriverSource, symbols.AtomDriverSourceLimit);
    memory.fill(0xa5, symbols.AtomDriverBuildDescriptor, symbols.AtomDriverDescriptorAfter);
    let sourceCursor = symbols.AtomDriverSource;
    const descriptorBase = options.partsPointer ?? symbols.AtomDriverPartDescriptors;
    for (const [index, bytes] of encoded.entries()) {
      assert.ok(sourceCursor + bytes.length <= symbols.AtomDriverSourceLimit, "driver proof source capacity");
      memory.set(bytes, sourceCursor);
      const descriptor = descriptorBase + index * symbols.AtomDriverPartDescriptorBytes;
      memory[descriptor] = options.ordinals?.[index] ?? index;
      writeWord(memory, descriptor + 1, sourceCursor);
      writeWord(memory, descriptor + 3, sourceCursor + bytes.length);
      sourceCursor += bytes.length;
    }
    if (options.reversedSourceIndex !== undefined) {
      const descriptor = descriptorBase + options.reversedSourceIndex * symbols.AtomDriverPartDescriptorBytes;
      const start = word(memory, descriptor + 1);
      writeWord(memory, descriptor + 3, start - 1);
    }

    const build = symbols.AtomDriverBuildDescriptor;
    memory[build] = options.partCount ?? encoded.length;
    writeWord(memory, build + symbols.AtomDriverDescriptorParts, descriptorBase);
    writeWord(memory, build + symbols.AtomDriverDescriptorSymbolStart, options.symbolStart ?? symbols.AtomDriverSymbolArena);
    writeWord(memory, build + symbols.AtomDriverDescriptorSymbolEnd, options.symbolEnd ?? (symbols.AtomDriverSymbolArena + (options.symbolBytes ?? 256)));
    writeWord(memory, build + symbols.AtomDriverDescriptorPendingStart, options.pendingStart ?? symbols.AtomDriverPendingArena);
    writeWord(memory, build + symbols.AtomDriverDescriptorPendingEnd, options.pendingEnd ?? (symbols.AtomDriverPendingArena + (options.pendingBytes ?? 112)));
    writeWord(memory, build + symbols.AtomDriverDescriptorTargetStart, options.address ?? 0x4000);
    writeWord(memory, build + symbols.AtomDriverDescriptorTargetBytes, options.capacity ?? 0x100);
    sourceSnapshot = memory.slice(symbols.AtomDriverSource, symbols.AtomDriverSourceLimit);
    descriptorSnapshot = memory.slice(symbols.AtomDriverBuildDescriptor, symbols.AtomDriverDescriptorAfter);
  }

  function operations() {
    const result = [];
    let cursor = symbols.AtomDriverProofLog;
    const end = word(memory, symbols.AtomDriverProofLogNext);
    while (cursor < end) {
      const kind = memory[cursor];
      const bank = memory[cursor + 1];
      const address = word(memory, cursor + 2);
      const length = word(memory, cursor + 4);
      result.push({ kind, bank, address, bytes: Array.from(memory.slice(cursor + 6, cursor + 6 + length)) });
      cursor += 6 + length;
    }
    assert.equal(cursor, end, "misaligned driver proof log");
    return result;
  }

  function runAssemble(parts, options, resetMachine) {
    if (resetMachine) restart();
    resetAdapter();
    installBuild(parts, options);
    memory[symbols.AtomDriverProofFailBegin] = options.failBegin ? 1 : 0;
    memory[symbols.AtomDriverProofFailCommit] = options.failCommit ? 1 : 0;
    memory[symbols.AtomDriverProofFailAfter] = options.failAfter ?? 0;
    return execute("AtomAssemble", (_memory, names, cpu) => {
      cpu.ix = names.AtomDriverBuildDescriptor;
    }, options.label ?? `AtomAssemble ${JSON.stringify(parts)}`);
  }

  return {
    symbols,
    memory,
    statistics,
    restart,
    assemble(parts, options = {}) {
      return runAssemble(parts, options, true);
    },
    assembleAgain(parts, options = {}) {
      return runAssemble(parts, options, false);
    },
    validate(parts, options = {}) {
      restart();
      installBuild(parts, options);
      memory[symbols.AtomDriverDescriptor] = symbols.AtomDriverBuildDescriptor & 0xff;
      memory[symbols.AtomDriverDescriptor + 1] = symbols.AtomDriverBuildDescriptor >>> 8;
      return execute("AtomDriverValidateDescriptor", () => {}, options.label ?? "AtomDriverValidateDescriptor");
    },
    finish(label = "AtomAssembleFinish") {
      return execute("AtomAssembleFinish", () => {}, label);
    },
    operations,
    finalBytes(start = 0x4000) {
      const bytes = new Map();
      for (const operation of operations()) {
        for (const [offset, byte] of operation.bytes.entries()) bytes.set((operation.address + offset) & 0xffff, byte);
      }
      const addresses = [...bytes.keys()].filter((address) => address >= start).sort((left, right) => left - right);
      if (addresses.length === 0) return [];
      const end = addresses.at(-1) + 1;
      return Array.from({ length: end - start }, (_, offset) => bytes.get(start + offset) ?? 0);
    },
    lifecycle() {
      return {
        open: memory[symbols.AtomDriverProofOpen],
        began: memory[symbols.AtomDriverProofBegan],
        committed: memory[symbols.AtomDriverProofCommitted],
        aborted: memory[symbols.AtomDriverProofAborted],
        beginDescriptor: word(memory, symbols.AtomDriverProofBeginDescriptor),
        commitDescriptor: word(memory, symbols.AtomDriverProofCommitDescriptor),
        cursor: word(memory, symbols.AtomDriverProofCommitCursor),
        remaining: word(memory, symbols.AtomDriverProofCommitRemaining),
      };
    },
    undefinedKey(pointer) {
      if (pointer === 0) return [];
      const key = Array.from(memory.slice(pointer, pointer + 6));
      key[5] &= symbols.AtomSymbolNameHighMask;
      return key;
    },
  };
}
