import assert from "node:assert/strict";
import fs from "node:fs";

import { compile } from "@jhlagado/azm";
import { createZ80Runtime, parseIntelHex } from "@jhlagado/debug80-runtime";

const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0x80fe;
const addressOf = (symbol) => symbol.address ?? symbol.value;
const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const writeWord = (memory, address, value) => {
  memory[address] = value & 0xff;
  memory[address + 1] = value >>> 8;
};
const manifest = JSON.parse(fs.readFileSync("proofs/phase-3.json", "utf8"));

export async function createDriverHarness() {
  const assembled = await compile("asm/driver-proof.asm", {
    emitHex: true,
    emitD8m: true,
    registerContracts: "strict",
  });
  const errors = assembled.diagnostics.filter(({ severity }) => severity === "error");
  assert.deepEqual(errors, [], `driver proof assembly failed: ${JSON.stringify(errors)}`);
  const hex = assembled.artifacts.find(({ kind }) => kind === "hex");
  const d8m = assembled.artifacts.find(({ kind }) => kind === "d8m");
  assert.equal(hex?.kind, "hex");
  assert.equal(d8m?.kind, "d8m");
  const symbols = Object.fromEntries(d8m.json.symbols.flatMap((symbol) => {
    const value = addressOf(symbol);
    return value === undefined ? [] : [[symbol.name, value]];
  }));
  const runtime = createZ80Runtime(parseIntelHex(hex.text), symbols.AtomAssemble);
  const memory = runtime.hardware.memory;
  const pristine = memory.slice();
  const immutable = [
    [symbols.AtomEncoderCoreStart, symbols.AtomEncoderCoreEnd],
    [symbols.AtomSymbolCodeStart, symbols.AtomSymbolCodeEnd],
    [symbols.AtomTokenizerCodeStart, symbols.AtomTokenizerCodeEnd],
    [symbols.AtomExpressionCodeStart, symbols.AtomExpressionCodeEnd],
    [symbols.AtomPatchCodeStart, symbols.AtomPatchCodeEnd],
    [symbols.AtomParserCodeStart, symbols.AtomParserCodeEnd],
    [symbols.AtomOutputCodeStart, symbols.AtomOutputCodeEnd],
    [symbols.AtomStatementCodeStart, symbols.AtomStatementCodeEnd],
    [symbols.AtomDriverCodeStart, symbols.AtomDriverCodeEnd],
    [symbols.AtomDriverProofAdapterStart, symbols.AtomDriverProofAdapterEnd],
  ].map(([start, end]) => ({ start, bytes: pristine.slice(start, end) }));
  const workspace = [
    [symbols.AtomEncoderWorkspaceStart, symbols.AtomEncoderWorkspaceEnd],
    [symbols.AtomSymbolWorkspaceStart, symbols.AtomSymbolWorkspaceEnd],
    [symbols.AtomTokenizerWorkspaceStart, symbols.AtomTokenizerWorkspaceEnd],
    [symbols.AtomExpressionWorkspaceStart, symbols.AtomExpressionWorkspaceEnd],
    [symbols.AtomParserWorkspaceStart, symbols.AtomParserWorkspaceEnd],
    [symbols.AtomOutputWorkspaceStart, symbols.AtomOutputWorkspaceEnd],
    [symbols.AtomStatementWorkspaceStart, symbols.AtomStatementWorkspaceEnd],
    [symbols.AtomDriverWorkspaceStart, symbols.AtomDriverWorkspaceEnd],
    [symbols.AtomDriverProofAdapterWorkspaceStart, symbols.AtomDriverProofAdapterWorkspaceEnd],
  ];
  const statistics = {};
  const fullMemoryAudited = new Set();
  let sourceSnapshot = new Uint8Array();
  let descriptorSnapshot = new Uint8Array();

  function restart() {
    memory.set(pristine);
    runtime.reset();
    runtime.cpu.halted = false;
    sourceSnapshot = memory.slice(symbols.AtomDriverSource, symbols.AtomDriverSourceLimit);
    descriptorSnapshot = memory.slice(symbols.AtomDriverBuildDescriptor, symbols.AtomDriverDescriptorAfter);
  }

  const inside = (address, start, end) => address >= start && address < end;

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
    const budget = manifest.executionBudgets[entry];
    assert.ok(budget, `missing execution budget for ${entry}`);
    let instructions = 0;
    let cycles = 0;
    const recent = [];
    while (runtime.cpu.pc !== RETURN_SENTINEL && instructions < budget.maxInstructions && cycles <= budget.maxCycles) {
      recent.push(runtime.cpu.pc);
      if (recent.length > 16) recent.shift();
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

    const auditKey = [entry, runtime.cpu.a, memory[symbols.AtomDriverProofBegan], memory[symbols.AtomDriverProofCommitted], memory[symbols.AtomDriverProofAborted]].join(":");
    if (!fullMemoryAudited.has(auditKey)) {
      for (let address = 0; address < memory.length; address += 1) {
        const allowed = workspace.some(([start, end]) => inside(address, start, end)) ||
          (entry === "AtomAssemble" && inside(address, symbols.AtomDriverSymbolArena, symbols.AtomDriverSymbolLimit)) ||
          (entry === "AtomAssemble" && inside(address, symbols.AtomDriverPendingArena, symbols.AtomDriverPendingLimit)) ||
          (entry === "AtomAssemble" && inside(address, symbols.AtomDriverProofLog, symbols.AtomDriverProofLogLimit)) ||
          (address > STACK_BEFORE && address < STACK_AFTER);
        if (!allowed) assert.equal(memory[address], before[address], `${label}: unexpected write at $${address.toString(16).padStart(4, "0")}`);
      }
      fullMemoryAudited.add(auditKey);
    }

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
    writeWord(memory, build + symbols.AtomDriverDescriptorPendingEnd, options.pendingEnd ?? (symbols.AtomDriverPendingArena + (options.pendingBytes ?? 96)));
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
    const reset = execute("AtomProofDriverReset");
    assert.equal(reset.carry, 0);
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
