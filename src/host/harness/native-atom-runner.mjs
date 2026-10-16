import {
  invokeOneByteStatus,
  materializeTargetImage,
  renderTargetBinary,
  Z80_RESIDENT_SOURCE_PART_CAPACITY,
} from "@jhlagado/z80-tool-services";

import { AtomAssemblyError } from "../atom-assembly-error.mjs";
import { DIAGNOSTIC_BASE, formatDiagnostic } from "../diagnostics.mjs";

const DIAGNOSTIC_OUTPUT = 2;
const OUTPUT_STATUS_CAPACITY = 1;
import { loadNativeAtomCore } from "../core/native-atom-core.mjs";
import {
  ATOM_TOOL_SERVICE,
  createAtomToolServiceGateway,
} from "../providers/tool-service-gateway.mjs";
import { createDebug80ExecutionAdapter } from "./z80-execution-adapter.mjs";

// The core occupies the first 16 KiB. Its build descriptor, symbol arena and
// pending-reference arena occupy separate RAM regions. Source parts are served
// on request through tkOpen and tkRead, so no source sits in Z80 memory.
// Output bytes go to the host sink, so assembled addresses do not name this RAM.
const BUILD_DESCRIPTOR = 0x4000;
const SYMBOL_START = 0x4100;
const SYMBOL_END = 0xa000;
const PENDING_START = 0xa000;
const PENDING_END = 0xd000;
const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0xfffe;
const DEFAULT_NATIVE_MEMORY_LAYOUT = Object.freeze({
  symbolStart: SYMBOL_START,
  symbolEnd: SYMBOL_END,
  pendingStart: PENDING_START,
  pendingEnd: PENDING_END,
});

export const NATIVE_ATOM_LIMITS = Object.freeze({
  sourceParts: Z80_RESIDENT_SOURCE_PART_CAPACITY,
  sourceBytes: 0xffff,
  symbolBytes: SYMBOL_END - SYMBOL_START,
  pendingBytes: PENDING_END - PENDING_START,
  targetBanks: 1,
});

export const ATOM_HOST_SINK_STATUS = Object.freeze({
  LIFECYCLE: 0xe0,
  BANK: 0xe1,
  IMAGE_ORDER: 0xe2,
  PATCH_TARGET: 0xe3,
  TARGET_RANGE: 0xe4,
  BINARY_INCLUDE: 0xe5,
  HOST_EXCEPTION: 0xef,
});

const word = (memory, address) => memory[address] | (memory[address + 1] << 8);
const writeWord = (memory, address, value) => {
  memory[address] = value & 0xff;
  memory[address + 1] = value >>> 8;
};
const pair = (high, low) => ((high << 8) | low) & 0xffff;
const frozenBytes = (bytes) => Object.freeze(Array.from(bytes));

const RUNNER_SYMBOL_NAMES = Object.freeze([
  "AtomAssemble",
  "AtomDriverDescriptorPendingEnd",
  "AtomDriverDescriptorPendingStart",
  "AtomDriverDescriptorSymbolEnd",
  "AtomDriverDescriptorSymbolStart",
  "AtomDriverDescriptorTargetBytes",
  "AtomDriverDescriptorTargetStart",
  "AtomDiagnosticSymbol",
  "AtomDiagnosticValue",
  "AtomDriverDetail",
  "AtomDriverMessage",
  "AtomDriverRelatedLine",
  "AtomDriverRelatedOffset",
  "AtomDriverRelatedPart",
  "AtomDriverStatusConfiguration",
  "AtomDriverStatusOk",
  "AtomDriverStatusOutput",
  "AtomDriverStatusSource",
  "AtomDriverStatusUndefined",
  "AtomDriverUndefinedSymbol",
  "AtomHostResidentEnd",
  "AtomOutputCursor",
  "AtomOutputFlags",
  "AtomOutputReserve",
  "AtomOutputStatusCapacity",
  "AtomOutputSetOrigin",
  "AtomSinkAbort",
  "AtomSinkBegin",
  "AtomSinkCommit",
  "AtomSinkImageByte",
  "AtomSinkPatchByte",
  "AtomSinkPatchWord",
  "AtomSourceReadByte",
  "AtomStatementDetail",
  "AtomStatementErrorLine",
  "AtomStatementErrorOffset",
  "AtomStatementErrorPart",
  "AtomStatementStatusOutput",
  "AtomSymbolDeclare",
  "AtomSymbolDeclareGlobalLabel",
  "AtomSymbolFlagPrivate",
  "AtomSymbolNameBytes",
  "AtomSymbolNameHighMask",
  "AtomSymbolRecordBytes",
  "AtomTokenizerReset",
]);

const RUNNER_CODE_SYMBOL_NAMES = Object.freeze([
  "AtomAssemble",
  "AtomBinaryOpen",
  "AtomBinaryRead",
  "AtomSourceOpenPart",
  "AtomOutputReserve",
  "AtomOutputSetOrigin",
  "AtomSinkAbort",
  "AtomSinkBegin",
  "AtomSinkCommit",
  "AtomSinkImageByte",
  "AtomSinkPatchByte",
  "AtomSinkPatchWord",
  "AtomSourceReadByte",
  "AtomSymbolDeclare",
  "AtomSymbolDeclareGlobalLabel",
  "AtomTokenizerReset",
]);

const RUNNER_STATE_SYMBOL_WIDTHS = Object.freeze([
  ["AtomDriverDetail", 1],
  ["AtomDriverUndefinedSymbol", 2],
  ["AtomOutputCursor", 2],
  ["AtomOutputFlags", 1],
  ["AtomStatementDetail", 1],
  ["AtomStatementErrorOffset", 2],
  ["AtomStatementErrorPart", 1],
]);

function fail(code, message, details = {}) {
  throw new AtomAssemblyError("configuration", code, message, details);
}

function integer(value, name, minimum, maximum) {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    fail(
      "invalid-option",
      `${name} must be an integer from ${minimum} through ${maximum}`,
    );
  }
  return value;
}

function nativeCoreOption(value, parseImage) {
  if (
    value === null ||
    typeof value !== "object" ||
    typeof value.hexText !== "string" ||
    value.symbols === null ||
    typeof value.symbols !== "object" ||
    !Array.isArray(value.codeRanges) ||
    !Number.isInteger(value.codeBytes) ||
    !Number.isInteger(value.residentExtentBytes)
  ) {
    fail("invalid-native-core", "supplied native Atom core is incomplete");
  }
  for (const name of RUNNER_SYMBOL_NAMES) {
    if (
      !Number.isInteger(value.symbols[name]) ||
      value.symbols[name] < 0 ||
      value.symbols[name] > 0xffff
    ) {
      fail(
        "invalid-native-core",
        `supplied native Atom core has no valid ${name}`,
      );
    }
  }
  if (
    value.residentExtentBytes !== value.symbols.AtomHostResidentEnd ||
    value.residentExtentBytes < 0 ||
    value.residentExtentBytes > 0x4000
  ) {
    fail(
      "invalid-native-core",
      "supplied native Atom core has an invalid resident extent",
    );
  }
  let codeBytes = 0;
  let previousEnd = 0;
  for (const range of value.codeRanges) {
    if (
      range === null ||
      typeof range !== "object" ||
      !Number.isInteger(range.start) ||
      !Number.isInteger(range.end) ||
      range.start < previousEnd ||
      range.end < range.start ||
      range.end > value.residentExtentBytes
    ) {
      fail(
        "invalid-native-core",
        "supplied native Atom core has an invalid code range",
      );
    }
    codeBytes += range.end - range.start;
    previousEnd = range.end;
  }
  if (codeBytes !== value.codeBytes) {
    fail(
      "invalid-native-core",
      "supplied native Atom core code-byte total does not match its ranges",
    );
  }
  let program;
  try {
    program = parseImage(value.hexText);
  } catch (cause) {
    fail(
      "invalid-native-core",
      "supplied native Atom core has invalid Intel HEX",
      { cause },
    );
  }
  const initialized = new Uint8Array(value.residentExtentBytes);
  for (const range of program.writeRanges) {
    if (
      range.start < 0 ||
      range.end < range.start ||
      range.end > value.residentExtentBytes
    ) {
      fail(
        "invalid-native-core",
        "supplied native Atom core HEX writes outside its resident extent",
      );
    }
    initialized.fill(1, range.start, range.end);
  }
  for (const range of value.codeRanges) {
    for (let address = range.start; address < range.end; address += 1) {
      if (initialized[address] === 0) {
        fail(
          "invalid-native-core",
          "supplied native Atom core HEX does not initialize every code byte",
        );
      }
    }
  }
  const inCode = (address) =>
    value.codeRanges.some(
      (range) => address >= range.start && address < range.end,
    );
  for (const name of RUNNER_CODE_SYMBOL_NAMES) {
    if (
      !inCode(value.symbols[name]) ||
      initialized[value.symbols[name]] === 0
    ) {
      fail(
        "invalid-native-core",
        `supplied native Atom core has an invalid code entry ${name}`,
      );
    }
  }
  for (const [name, width] of RUNNER_STATE_SYMBOL_WIDTHS) {
    if (value.symbols[name] + width > value.residentExtentBytes) {
      fail(
        "invalid-native-core",
        `supplied native Atom core has an invalid state address ${name}`,
      );
    }
  }
  return Object.freeze({
    ...value,
    symbols: Object.freeze({ ...value.symbols }),
    codeRanges: Object.freeze(
      value.codeRanges.map((range) =>
        Object.freeze({
          start: range.start,
          end: range.end,
        }),
      ),
    ),
  });
}

// Front-end failure messages from src/host/diagnostics.mjs.
const MESSAGE = Object.freeze({
  directive: 72,
  include: 73,
  includeCycle: 74,
  includeDepth: 75,
  tooManyFiles: 76,
  includeLost: 77,
  sourceTooLong: 78,
  sourceLost: 79,
});

// Write the project's definitions into the front end's table: a length byte,
// the upper-case name padded with spaces to 17 bytes and a 16-bit value.
function seedDefinitions(memory, symbols, definitions) {
  const entries = Object.entries(definitions);
  if (entries.length > symbols.AtomFrontDefinitionCapacity) {
    fail("definition-capacity", `Atom accepts at most ${symbols.AtomFrontDefinitionCapacity} definitions`);
  }
  entries.forEach(([name, value], index) => {
    const upper = name.toUpperCase();
    if (!/^[A-Z][A-Z0-9_]{0,16}$/.test(upper)) fail("invalid-definition", `invalid definition name ${name}`);
    if (!Number.isInteger(value) || value < 0 || value > 0xffff) {
      fail("invalid-definition", `definition ${name} must be a number from 0 through 65535`);
    }
    const record = symbols.AtomFrontDefinitions + index * 20;
    memory[record] = upper.length;
    for (let at = 0; at < 17; at += 1) memory[record + 1 + at] = at < upper.length ? upper.charCodeAt(at) : 0x20;
    memory[record + 18] = value & 0xff;
    memory[record + 19] = value >>> 8;
  });
  memory[symbols.AtomFrontDefinitionCount] = entries.length;
}

function snapshotProject(project) {
  // Copy caller-owned bytes before execution. Original and preprocessed source
  // have equal lengths so a native byte offset still locates the original text.
  if (
    project === null ||
    typeof project !== "object" ||
    !Array.isArray(project.parts)
  ) {
    fail(
      "invalid-project",
      "resolved Atom project must contain an ordered parts array",
    );
  }
  if (
    project.parts.length < 1 ||
    project.parts.length > NATIVE_ATOM_LIMITS.sourceParts
  ) {
    fail(
      "part-capacity",
      "resolved Atom project exceeds the native 255-part limit",
    );
  }
  const parts = project.parts.map((part, ordinal) => {
    if (
      part === null ||
      typeof part !== "object" ||
      part.ordinal !== ordinal ||
      part.bank !== 0 ||
      typeof part.logicalIdentity !== "string" ||
      !(part.originalBytes instanceof Uint8Array) ||
      !((part.compilerBytes ?? part.originalBytes) instanceof Uint8Array) ||
      part.originalBytes.length !== (part.compilerBytes ?? part.originalBytes).length
    ) {
      fail(
        "invalid-part",
        `resolved Atom source part ${ordinal} is not a flat, equal-length native part`,
      );
    }
    if (part.originalBytes.length > NATIVE_ATOM_LIMITS.sourceBytes) {
      fail(
        "source-capacity",
        `resolved Atom source part ${ordinal} exceeds Atom's 16-bit source-offset range`,
      );
    }
    return Object.freeze({
      ordinal,
      bank: 0,
      logicalIdentity: part.logicalIdentity,
      originalBytes: part.originalBytes.slice(),
      compilerBytes: part.originalBytes.slice(),
      physicalPath: part.physicalPath,
    });
  });
  // INCBIN files are read when the core reaches them, through the resolver's
  // reader, so the source is never scanned for them in advance.
  // Included files are opened when the front end reaches them.
  return Object.freeze({
    parts: Object.freeze(parts),
    readBinary:
      typeof project.readBinary === "function" ? project.readBinary : undefined,
    openFile:
      typeof project.openFile === "function" ? project.openFile : undefined,
    definitions: Object.freeze({ ...(project.definitions ?? {}) }),
  });
}

function targetOptions(target = {}) {
  if (target === null || typeof target !== "object" || Array.isArray(target)) {
    fail("invalid-option", "target must be an object");
  }
  const start = integer(target.start ?? 0, "target.start", 0, 0xffff);
  const capacity = integer(
    target.capacity ?? 0xffff - start,
    "target.capacity",
    0,
    0xffff,
  );
  if (start + capacity > 0x10000) {
    fail(
      "target-range",
      "target start plus capacity exceeds Atom's non-wrapping native range",
    );
  }
  return Object.freeze({ start, capacity });
}

function memoryAddress(value, name) {
  return integer(value, name, 0, 0xffff);
}

function range(start, end, name) {
  if (start >= end) fail("memory-map", `${name} start must be below its end`);
  return Object.freeze({ start, end, name });
}

function assertNonOverlapping(ranges) {
  const ordered = [...ranges].sort(
    (left, right) => left.start - right.start || left.end - right.end,
  );
  for (let index = 1; index < ordered.length; index += 1) {
    const previous = ordered[index - 1];
    const current = ordered[index];
    if (previous.end > current.start) {
      fail("memory-map", `${previous.name} overlaps ${current.name}`);
    }
  }
}

function nativeMemoryLayout(option = {}, { core }) {
  if (option === null || typeof option !== "object" || Array.isArray(option)) {
    fail("invalid-option", "nativeMemoryLayout must be an object");
  }
  const layout = Object.freeze({
    symbolStart: memoryAddress(
      option.symbolStart ?? DEFAULT_NATIVE_MEMORY_LAYOUT.symbolStart,
      "nativeMemoryLayout.symbolStart",
    ),
    symbolEnd: memoryAddress(
      option.symbolEnd ?? DEFAULT_NATIVE_MEMORY_LAYOUT.symbolEnd,
      "nativeMemoryLayout.symbolEnd",
    ),
    pendingStart: memoryAddress(
      option.pendingStart ?? DEFAULT_NATIVE_MEMORY_LAYOUT.pendingStart,
      "nativeMemoryLayout.pendingStart",
    ),
    pendingEnd: memoryAddress(
      option.pendingEnd ?? DEFAULT_NATIVE_MEMORY_LAYOUT.pendingEnd,
      "nativeMemoryLayout.pendingEnd",
    ),
  });
  assertNonOverlapping([
    range(0, core.residentExtentBytes, "native Atom resident core"),
    range(
      BUILD_DESCRIPTOR,
      BUILD_DESCRIPTOR + core.symbols.AtomDriverDescriptorBytes,
      "native Atom build descriptor",
    ),
    range(layout.symbolStart, layout.symbolEnd, "native Atom symbol arena"),
    range(layout.pendingStart, layout.pendingEnd, "native Atom pending arena"),
    range(STACK_BEFORE, STACK_AFTER + 1, "native Atom host stack canary"),
  ]);
  return layout;
}

function inTarget(target, address, length) {
  return (
    address >= target.start &&
    address + length <= target.start + target.capacity
  );
}

export function createMemoryAtomSink() {
  // IMAGE records arrive in ascending order. PATCH records correct bytes that
  // already exist, once per byte. COMMIT publishes the generation only after
  // assembly succeeds, while ABORT discards the provisional records.
  let open = false;
  let target;
  let descriptor;
  let images = [];
  let patches = [];
  let imageEnd;
  let imageAddresses = new Set();
  let patchAddresses = new Set();
  let generation;
  let failure;
  const lifecycle = [];

  const reject = (status, code, message) => {
    failure = Object.freeze({ status, code, message });
    return status;
  };

  const sink = {
    begin(context) {
      lifecycle.push("begin");
      if (open)
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-open",
          "a generation is already open",
        );
      open = true;
      target = context.target;
      descriptor = context.descriptor;
      images = [];
      patches = [];
      imageEnd = undefined;
      imageAddresses = new Set();
      patchAddresses = new Set();
      generation = undefined;
      failure = undefined;
      return 0;
    },
    image(operation) {
      lifecycle.push("image");
      if (!open)
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "IMAGE requires an open generation",
        );
      if (operation.bank !== 0)
        return reject(
          ATOM_HOST_SINK_STATUS.BANK,
          "bank",
          "native Atom output is flat bank zero",
        );
      if (!inTarget(target, operation.address, operation.bytes.length)) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "image-range",
          "IMAGE lies outside the target range",
        );
      }
      if (imageEnd !== undefined && operation.address < imageEnd) {
        return reject(
          ATOM_HOST_SINK_STATUS.IMAGE_ORDER,
          "image-order",
          "IMAGE records descend or overlap",
        );
      }
      const bytes = frozenBytes(operation.bytes);
      images.push(
        Object.freeze({
          bank: 0,
          address: operation.address,
          bytes,
          ...(operation.source === undefined
            ? {}
            : { source: operation.source }),
        }),
      );
      for (let offset = 0; offset < bytes.length; offset += 1)
        imageAddresses.add(operation.address + offset);
      imageEnd = operation.address + bytes.length;
      return 0;
    },
    patch(operation) {
      lifecycle.push("patch");
      if (!open)
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "PATCH requires an open generation",
        );
      if (operation.bank !== 0)
        return reject(
          ATOM_HOST_SINK_STATUS.BANK,
          "bank",
          "native Atom output is flat bank zero",
        );
      if (!inTarget(target, operation.address, operation.bytes.length)) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "patch-range",
          "PATCH lies outside the target range",
        );
      }
      for (let offset = 0; offset < operation.bytes.length; offset += 1) {
        const address = operation.address + offset;
        if (!imageAddresses.has(address) || patchAddresses.has(address)) {
          return reject(
            ATOM_HOST_SINK_STATUS.PATCH_TARGET,
            "patch-target",
            "PATCH does not name one unpatched IMAGE byte",
          );
        }
      }
      const bytes = frozenBytes(operation.bytes);
      patches.push(
        Object.freeze({
          bank: 0,
          address: operation.address,
          bytes,
          ...(operation.source === undefined
            ? {}
            : { source: operation.source }),
        }),
      );
      for (let offset = 0; offset < bytes.length; offset += 1)
        patchAddresses.add(operation.address + offset);
      return 0;
    },
    commit(context) {
      lifecycle.push("commit");
      if (!open)
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "COMMIT requires an open generation",
        );
      if (
        context.descriptor !== descriptor ||
        context.remaining < 0 ||
        context.remaining > target.capacity
      ) {
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "commit-state",
          "COMMIT state differs from the open generation",
        );
      }
      if (
        context.finalCursor < target.start ||
        context.finalCursor > target.start + target.capacity ||
        context.highWater < target.start ||
        context.highWater > target.start + target.capacity
      ) {
        return reject(
          ATOM_HOST_SINK_STATUS.TARGET_RANGE,
          "commit-range",
          "logical output extent lies outside the target range",
        );
      }
      generation = Object.freeze({
        target,
        finalCursor: context.finalCursor,
        highWater: context.highWater,
        remaining: context.remaining,
        images: Object.freeze(images.slice()),
        patches: Object.freeze(patches.slice()),
      });
      open = false;
      return 0;
    },
    abort() {
      lifecycle.push("abort");
      if (!open)
        return reject(
          ATOM_HOST_SINK_STATUS.LIFECYCLE,
          "generation-closed",
          "ABORT requires an open generation",
        );
      open = false;
      images = [];
      patches = [];
      imageAddresses.clear();
      patchAddresses.clear();
      return 0;
    },
    snapshot() {
      return Object.freeze({
        open,
        lifecycle: Object.freeze(lifecycle.slice()),
        generation,
        failure,
      });
    },
  };
  return Object.freeze(sink);
}

export function materializeAtomGeneration(
  generation,
  { fill = 0, base: requestedBase } = {},
) {
  integer(fill, "fill", 0, 0xff);
  if (generation === null || typeof generation !== "object") {
    fail("invalid-generation", "Atom generation is missing");
  }
  const base = requestedBase ?? generation.target.start;
  integer(base, "materialization base", 0, 0xffff);
  let end = Math.max(
    base,
    generation.finalCursor,
    generation.highWater ?? generation.finalCursor,
  );
  for (const operation of generation.images)
    end = Math.max(end, operation.address + operation.bytes.length);
  const capacity = generation.target.start + generation.target.capacity - base;
  if (capacity < 1 || capacity > 0xffff) {
    fail(
      "materialization-base",
      "Atom materialization base lies outside the target range",
    );
  }
  const canonicalImages = [...generation.images].sort(
    (left, right) => left.bank - right.bank || left.address - right.address,
  );
  try {
    const targetImage = materializeTargetImage({
      geometry: {
        bankCount: 1,
        imageBase: base,
        imageCapacity: capacity,
        imageFill: fill,
        entryBank: 0,
        entryAddress: base,
      },
      banks: [{ usedLength: end - base }],
      images: canonicalImages,
      patches: generation.patches,
      patchPolicy: "image",
    });
    return Object.freeze({
      base,
      end,
      bytes: renderTargetBinary(targetImage),
      targetImage,
    });
  } catch (cause) {
    fail("invalid-generation", "Atom generation cannot be materialized", {
      cause,
    });
  }
}

const RADIX40 = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";

// Global names in symbol-table order: each record is added when its name is
// first seen, as a definition or a forward reference. ATOM.COM's symbol file
// uses this order, so Node's does too.
function globalSymbolOrder(memory, symbols) {
  const names = [];
  const end = word(memory, symbols.AtomSymbolGlobalEnd);
  for (let pointer = word(memory, symbols.AtomSymbolArenaBase); pointer < end; pointer += symbols.AtomSymbolRecordBytes) {
    const name = unpackPackedSymbol(memory, pointer, symbols);
    if (name !== undefined) names.push(name);
  }
  return Object.freeze(names);
}

// The global symbol records' bytes, in table order, for traces.
function globalSymbolRecords(memory, symbols) {
  const records = [];
  const end = word(memory, symbols.AtomSymbolGlobalEnd);
  for (let pointer = word(memory, symbols.AtomSymbolArenaBase); pointer < end; pointer += symbols.AtomSymbolRecordBytes) {
    records.push(Object.freeze({ address: pointer, bytes: memory.slice(pointer, pointer + symbols.AtomSymbolRecordBytes) }));
  }
  return Object.freeze(records);
}

function unpackPackedSymbol(memory, pointer, symbols) {
  if (pointer < 0 || pointer + symbols.AtomSymbolNameBytes > memory.length)
    return undefined;
  const first = word(memory, pointer);
  const second = word(memory, pointer + 2);
  const third =
    memory[pointer + 4] |
    ((memory[pointer + 5] & symbols.AtomSymbolNameHighMask) << 8);
  const triplet = (value) => [
    Math.floor(value / 1600),
    Math.floor(value / 40) % 40,
    value % 40,
  ];
  const codes = [
    ...triplet(first),
    ...triplet(second),
    Math.floor(third / 40),
    third % 40,
  ];
  if (codes.some((code) => code < 0 || code >= RADIX40.length))
    return undefined;
  const name = codes
    .map((code) => RADIX40[code])
    .join("")
    .trimEnd();
  return (memory[pointer + 5] & symbols.AtomSymbolFlagPrivate) === 0
    ? name
    : `.${name}`;
}

function unpackSymbol(memory, pointer, symbols, layout) {
  if (
    pointer < layout.symbolStart ||
    pointer + symbols.AtomSymbolRecordBytes > layout.symbolEnd
  )
    return undefined;
  return unpackPackedSymbol(memory, pointer, symbols);
}

// The core reports each position's line. The column is found by stepping back
// from the offset to the start of its line, so no part is rescanned.
function sourcePosition(part, offset, line) {
  const bounded = Math.min(offset, part.originalBytes.length);
  let start = bounded;
  while (start > 0 && part.originalBytes[start - 1] !== 0x0a && part.originalBytes[start - 1] !== 0x0d) {
    start -= 1;
  }
  const column = bounded - start + 1;
  return Object.freeze({
    logicalIdentity: part.logicalIdentity,
    ordinal: part.ordinal,
    offset,
    line,
    column,
  });
}

function uniqueDeclarations(declarations) {
  const unique = new Map();
  for (const declaration of declarations) {
    const key = `${declaration.name}\0${declaration.value}\0${declaration.source?.ordinal ?? -1}\0${declaration.source?.offset ?? -1}`;
    if (!unique.has(key)) unique.set(key, declaration);
  }
  return Object.freeze([...unique.values()]);
}

function nativeFailure(
  result,
  project,
  memory,
  symbols,
  memoryLayout,
  sinkState,
  execution,
  cause,
  bridgeFailure,
) {
  const part = project.parts[result.part];
  const diagnostic =
    bridgeFailure?.diagnostic ??
    (part === undefined ? undefined : sourcePosition(part, result.offset, result.line));
  const relatedPart = result.relatedPart === 0xff ? undefined : project.parts[result.relatedPart];
  const relatedDiagnostic = relatedPart === undefined
    ? undefined
    : sourcePosition(relatedPart, result.relatedOffset, result.relatedLine);
  const symbol = result.diagnosticSymbol === 0
    ? undefined
    : unpackSymbol(memory, result.diagnosticSymbol, symbols, memoryLayout);
  const native = Object.freeze({ ...result });
  const located = (text) => diagnostic === undefined
    ? text
    : `${diagnostic.logicalIdentity}:${diagnostic.line}:${diagnostic.column}: ${text}`;
  const text = formatDiagnostic(result.message, {
    symbol,
    value: result.diagnosticValue,
    relatedLine: relatedDiagnostic?.line,
  });
  const common = {
    native,
    diagnostic,
    relatedDiagnostic,
    messageNumber: result.message,
    sink: sinkState,
    execution,
    cause,
  };
  if (result.status === symbols.AtomDriverStatusUndefined) {
    return new AtomAssemblyError("source", "undefined-symbol", located(text), {
      ...common,
      text,
      symbol: symbol ?? "?",
    });
  }
  if (result.status === symbols.AtomDriverStatusConfiguration) {
    return new AtomAssemblyError("native", "descriptor", text, { ...common, text });
  }
  // The host bridge and the sink describe their own failures; prefer their
  // wording whenever one of them rejected an output operation.
  const hostFailure = bridgeFailure?.message ?? sinkState.failure?.message;
  const sinkRejected =
    result.status === symbols.AtomDriverStatusOutput ||
    result.message === DIAGNOSTIC_OUTPUT ||
    (result.driverDetail === symbols.AtomStatementStatusOutput && hostFailure !== undefined);
  if (sinkRejected) {
    const sinkText = hostFailure ?? text;
    return new AtomAssemblyError("output", "sink", located(sinkText), {
      ...common,
      text: sinkText,
    });
  }
  if (result.message === DIAGNOSTIC_BASE.output + OUTPUT_STATUS_CAPACITY) {
    return new AtomAssemblyError("output", "sink", located(text), { ...common, text });
  }
  if (result.status === symbols.AtomDriverStatusSource) {
    return new AtomAssemblyError("source", "statement", located(text), {
      ...common,
      text,
      ...(symbol === undefined ? {} : { symbol }),
    });
  }
  if (result.status === symbols.AtomDriverStatusSourceService) {
    const code = SOURCE_SERVICE_CODES.get(result.message);
    if (code !== undefined) return new AtomAssemblyError("source", code, located(text), { ...common, text });
  }
  return new AtomAssemblyError("native", "internal", located(text), { ...common, text });
}

// The front end's failures are faults in the source project, not in Atom.
const SOURCE_SERVICE_CODES = new Map([
  [MESSAGE.directive, "directive"],
  [MESSAGE.include, "include"],
  [MESSAGE.includeCycle, "dependency-cycle"],
  [MESSAGE.includeDepth, "include-depth"],
  [MESSAGE.tooManyFiles, "source-capacity"],
  [MESSAGE.includeLost, "missing-source"],
  [MESSAGE.sourceTooLong, "source-too-long"],
  [MESSAGE.sourceLost, "source-read"],
]);

function invokeService(runtime, kind, action, trace) {
  const { status, cause } = invokeOneByteStatus(action, {
    success: 0,
    invalid: ATOM_HOST_SINK_STATUS.HOST_EXCEPTION,
    exception: ATOM_HOST_SINK_STATUS.HOST_EXCEPTION,
  });
  trace.push(Object.freeze({ method: kind, status }));
  const { cpu } = runtime;
  // A service entry replaces a native CALL target. Pop that return address and
  // supply A and carry just as the linked Z80 adapter would before RET.
  const returnAddress = word(runtime.hardware.memory, cpu.sp);
  cpu.sp = (cpu.sp + 2) & 0xffff;
  cpu.pc = returnAddress;
  cpu.a = status;
  cpu.flags.C = status === 0 ? 0 : 1;
  return cause;
}

export async function assembleResolvedAtomProject(project, options = {}) {
  const snapshot = snapshotProject(project);
  const target = targetOptions(options.target);
  const maxInstructions = integer(
    options.maxInstructions ?? 200_000_000,
    "maxInstructions",
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const maxCycles = integer(
    options.maxCycles ?? 2_000_000_000,
    "maxCycles",
    1,
    Number.MAX_SAFE_INTEGER,
  );
  const executionAdapter =
    options.executionAdapter ?? createDebug80ExecutionAdapter();
  if (
    executionAdapter === null ||
    typeof executionAdapter.parseImage !== "function" ||
    typeof executionAdapter.create !== "function"
  ) {
    fail(
      "invalid-execution-adapter",
      "execution adapter requires parseImage() and create()",
    );
  }
  const core =
    options.nativeCore === undefined
      ? await loadNativeAtomCore()
      : nativeCoreOption(options.nativeCore, executionAdapter.parseImage);
  const symbols = core.symbols;
  if (core.residentExtentBytes > BUILD_DESCRIPTOR) {
    fail(
      "memory-map",
      "native Atom resident extent overlaps its host descriptor region",
    );
  }
  const memoryLayout = nativeMemoryLayout(options.nativeMemoryLayout, { core });
  const romRanges = [
    ...core.codeRanges.map(({ start, end }) => ({ start, end: end - 1 })),
  ];
  const runtime = executionAdapter.create({
    hexText: core.hexText,
    entry: symbols.AtomAssemble,
    romRanges,
  });
  const memory = runtime.hardware.memory;
  const immutable = core.codeRanges.map(({ start, end }) => ({
    start,
    bytes: memory.slice(start, end),
  }));

  memory.fill(
    0xa5,
    BUILD_DESCRIPTOR,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorBytes,
  );
  memory.fill(0xa5, memoryLayout.symbolStart, memoryLayout.symbolEnd);
  memory.fill(0xa5, memoryLayout.pendingStart, memoryLayout.pendingEnd);
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorSymbolStart,
    memoryLayout.symbolStart,
  );
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorSymbolEnd,
    memoryLayout.symbolEnd,
  );
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorPendingStart,
    memoryLayout.pendingStart,
  );
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorPendingEnd,
    memoryLayout.pendingEnd,
  );
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorTargetStart,
    target.start,
  );
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorTargetBytes,
    target.capacity,
  );
  const buildDescriptorBefore = memory.slice(
    BUILD_DESCRIPTOR,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorBytes,
  );

  memory[STACK_BEFORE] = 0x87;
  memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
  memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
  memory[STACK_AFTER] = 0x78;

  // The front end streams the project's files. Reset it, then give it the
  // project's definitions, as a root %DEFINE would.
  const files = [...snapshot.parts];
  runtime.cpu.sp = RETURN_SLOT;
  runtime.cpu.pc = symbols.AtomFrontStart;
  runtime.cpu.halted = false;
  for (let steps = 0; runtime.cpu.pc !== RETURN_SENTINEL; steps += 1) {
    if (steps > 100_000) fail("front-start", "native Atom front end did not start");
    runtime.step();
  }
  seedDefinitions(memory, symbols, snapshot.definitions);
  memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
  memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
  runtime.cpu.sp = RETURN_SLOT;
  runtime.cpu.pc = symbols.AtomAssemble;
  runtime.cpu.ix = BUILD_DESCRIPTOR;
  runtime.cpu.halted = false;

  const profile = options.toolProfile;
  if (
    profile !== undefined &&
    (typeof profile?.sourceRead !== "function" || profile?.sink === undefined)
  ) {
    fail(
      "invalid-tool-profile",
      "Atom tool profile requires sourceRead() and sink",
    );
  }
  const sink = profile?.sink ?? options.sink ?? createMemoryAtomSink();
  for (const method of [
    "begin",
    "image",
    "patch",
    "commit",
    "abort",
    "snapshot",
  ]) {
    if (typeof sink?.[method] !== "function")
      fail("invalid-sink", `Atom sink omits ${method}()`);
  }
  const serviceTrace = [];
  let serviceException;
  let bridgeFailure;
  let instructions = 0;
  let cycles = 0;
  const layout = [];
  const declaredSymbols = [];
  // With options.trace, copy each record as the core produces it: every token,
  // every committed instruction with its references, and the pending arena
  // each time a definition resolves it.
  const trace = options.trace === true ? [] : undefined;
  let tokenSeen = false;
  let lastToken;
  const traceRecord = (stage, fields) => trace.push(Object.freeze({ stage, source: currentDiagnostic(), ...fields }));
  const traceAt = (pc) => {
    if (pc === symbols.AtomTokenizerNext) {
      // tkNext publishes into the record, so it holds the previous token. The
      // core enters tkNext more than once per token, so keep each one once.
      const bytes = memory.slice(symbols.AtomTokenRecord, symbols.AtomTokenRecord + symbols.AtomTokenRecordBytes);
      if (tokenSeen && bytes.some((byte) => byte !== 0) && !bytes.every((byte, index) => byte === lastToken?.[index])) {
        traceRecord("token", { bytes });
        lastToken = bytes;
      }
      tokenSeen = true;
    } else if (pc === symbols.AtomParserCommit) {
      const count = memory[symbols.AtomParserReferenceCount];
      const references = [];
      for (let index = 0; index < count; index += 1) {
        const at = symbols.AtomParserReferences + index * symbols.AtomParserPublicReferenceBytes;
        references.push(memory.slice(at, at + symbols.AtomParserPublicReferenceBytes));
      }
      traceRecord("instruction", { bytes: memory.slice(symbols.AtomParserScratch, symbols.AtomParserScratch + 10), references });
    } else if (pc === symbols.AtomOutputResolveSymbol) {
      const records = [];
      const next = word(memory, symbols.AtomPendingNext);
      for (let at = word(memory, symbols.AtomPendingArenaBase); at < next; at += symbols.AtomPendingRecordBytes) {
        records.push(memory.slice(at, at + symbols.AtomPendingRecordBytes));
      }
      traceRecord("resolve", { symbol: runtime.cpu.ix, pending: records });
    }
  };
  let sourceReads = 0;
  const currentDiagnostic = () => {
    const ordinal = memory[symbols.AtomStatementErrorPart];
    const part = files[ordinal];
    return part === undefined
      ? undefined
      : sourcePosition(
          part,
          word(memory, symbols.AtomStatementErrorOffset),
          word(memory, symbols.AtomStatementErrorLine),
        );
  };
  // A 16-bit zero can mean address zero or the exclusive endpoint $10000.
  // The native output flags distinguish the endpoint from an ordinary cursor.
  const logicalCursor = (cursor, endpoint) => endpoint ? 0x10000 : cursor;
  const toolServices = createAtomToolServiceGateway({
    sink,
    sourceRead:
      profile?.sourceRead ??
      (({ part, offset }) => files[part]?.originalBytes[offset]),
  });
  const serviceAt = new Map([
    [
      symbols.AtomSinkBegin,
      Object.freeze({
        kind: "begin",
        action: () =>
          toolServices.dispatch(ATOM_TOOL_SERVICE.begin, {
            descriptor: runtime.cpu.ix,
            target,
          }).status,
      }),
    ],
    [
      symbols.AtomSinkImageByte,
      Object.freeze({
        kind: "image",
        action: () => {
          const address = pair(runtime.cpu.h, runtime.cpu.l);
          return toolServices.dispatch(ATOM_TOOL_SERVICE.image, {
            bank: runtime.cpu.c,
            address,
            bytes: Object.freeze([runtime.cpu.a]),
            source: currentDiagnostic(),
          }).status;
        },
      }),
    ],
    [
      symbols.AtomSinkPatchByte,
      Object.freeze({
        kind: "patch-byte",
        action: () =>
          toolServices.dispatch(ATOM_TOOL_SERVICE.patch, {
            bank: runtime.cpu.c,
            address: pair(runtime.cpu.h, runtime.cpu.l),
            bytes: Object.freeze([runtime.cpu.a]),
            source: currentDiagnostic(),
          }).status,
      }),
    ],
    [
      symbols.AtomSinkPatchWord,
      Object.freeze({
        kind: "patch-word",
        action: () =>
          toolServices.dispatch(ATOM_TOOL_SERVICE.patch, {
            bank: runtime.cpu.c,
            address: pair(runtime.cpu.d, runtime.cpu.e),
            bytes: Object.freeze([runtime.cpu.l, runtime.cpu.h]),
            source: currentDiagnostic(),
          }).status,
      }),
    ],
    [
      symbols.AtomSinkCommit,
      Object.freeze({
        kind: "commit",
        action: () => {
          if (bridgeFailure !== undefined)
            return ATOM_HOST_SINK_STATUS.TARGET_RANGE;
          const geometryFlags = runtime.cpu.a;
          return toolServices.dispatch(ATOM_TOOL_SERVICE.commit, {
            descriptor: runtime.cpu.ix,
            finalCursor: logicalCursor(
              pair(runtime.cpu.h, runtime.cpu.l),
              (geometryFlags & 1) !== 0,
            ),
            remaining: pair(runtime.cpu.d, runtime.cpu.e),
            highWater: logicalCursor(
              pair(runtime.cpu.b, runtime.cpu.c),
              (geometryFlags & 2) !== 0,
            ),
          }).status;
        },
      }),
    ],
    [
      symbols.AtomSinkAbort,
      Object.freeze({
        kind: "abort",
        action: () => toolServices.dispatch(ATOM_TOOL_SERVICE.abort).status,
      }),
    ],
  ]);

  const runtimeFailure = (code, message) => {
    let sinkState;
    try {
      sinkState = sink.snapshot();
      if (sinkState.open) {
        sink.abort();
        sinkState = sink.snapshot();
      }
    } catch (cause) {
      return new AtomAssemblyError("runtime", code, message, {
        execution: Object.freeze({
          instructions,
          cycles,
          maxInstructions,
          maxCycles,
        }),
        cause,
      });
    }
    return new AtomAssemblyError("runtime", code, message, {
      execution: Object.freeze({
        instructions,
        cycles,
        maxInstructions,
        maxCycles,
      }),
      sink: sinkState,
    });
  };

  // Intercept host-service entries, but execute parser and encoder instructions
  // on the emulated Z80. The sentinel is reached by the core's final RET.
  // Parts are supplied in order, each from offset zero. A part ends where the
  // source service reports that no byte remains.
  let binary;
  // The byte tkRead returned for each offset: the source as the core saw it.
  // Segments record the order the core read each stretch of each file.
  let pendingRead;
  const segments = [];
  const returnFromService = () => {
    const returnAddress = word(memory, runtime.cpu.sp);
    runtime.cpu.sp = (runtime.cpu.sp + 2) & 0xffff;
    runtime.cpu.pc = returnAddress;
  };
  let rootNext = 0;
  const identities = new Map(files.map((file) => [file.physicalPath ?? file, file.ordinal]));
  const setCarry = (carry) => {
    runtime.cpu.flags.C = carry ? 1 : 0;
  };
  while (runtime.cpu.pc !== RETURN_SENTINEL) {
    if (runtime.cpu.pc === symbols.AtomSourceReadByte) {
      pendingRead = {
        returnPc: word(memory, runtime.cpu.sp),
        returnSp: (runtime.cpu.sp + 2) & 0xffff,
        part: runtime.cpu.a,
        offset: pair(runtime.cpu.h, runtime.cpu.l),
      };
    } else if (
      pendingRead !== undefined &&
      runtime.cpu.pc === pendingRead.returnPc &&
      runtime.cpu.sp === pendingRead.returnSp
    ) {
      const { part, offset } = pendingRead;
      const bytes = files[part]?.compilerBytes;
      if (!runtime.cpu.flags.C && bytes !== undefined) {
        bytes[offset] = runtime.cpu.a;
        const last = segments.at(-1);
        if (last?.part === part && last.end === offset) last.end += 1;
        else segments.push({ part, start: offset, end: offset + 1 });
      }
      pendingRead = undefined;
    }
    if (runtime.cpu.pc === symbols.AtomFileOpen) {
      // B=0 asks for the next root. Otherwise the B bytes at HL name a file
      // relative to the one being read.
      if (runtime.cpu.b === 0) {
        const root = snapshot.parts[rootNext];
        if (root !== undefined) rootNext += 1;
        runtime.cpu.a = root === undefined ? 0 : root.ordinal;
        setCarry(root === undefined);
      } else {
        const name = pair(runtime.cpu.h, runtime.cpu.l);
        const specifier = String.fromCharCode(...memory.slice(name, name + runtime.cpu.b));
        const importer = files[memory[symbols.AtomFrontPart]];
        let opened;
        try {
          if (snapshot.openFile !== undefined && importer !== undefined) {
            opened = await snapshot.openFile(importer, specifier);
          }
        } catch (error) {
          serviceException ??= error;
          opened = undefined;
        }
        const known = opened === undefined ? undefined : identities.get(opened.physicalPath ?? opened);
        if (opened === undefined) {
          runtime.cpu.a = MESSAGE.includeLost;
          setCarry(true);
        } else if (known !== undefined) {
          runtime.cpu.a = known;
          setCarry(false);
        } else if (files.length >= NATIVE_ATOM_LIMITS.sourceParts) {
          runtime.cpu.a = MESSAGE.tooManyFiles;
          setCarry(true);
        } else {
          const ordinal = files.length;
          files.push(Object.freeze({
            ordinal,
            bank: 0,
            logicalIdentity: opened.logicalIdentity,
            originalBytes: opened.originalBytes,
            compilerBytes: opened.originalBytes.slice(),
            physicalPath: opened.physicalPath,
          }));
          identities.set(opened.physicalPath ?? opened, ordinal);
          runtime.cpu.a = ordinal;
          setCarry(false);
        }
      }
      returnFromService();
      continue;
    }
    if (runtime.cpu.pc === symbols.AtomFileStart) {
      const file = files[runtime.cpu.a];
      const tooLong = file !== undefined && file.originalBytes.length > NATIVE_ATOM_LIMITS.sourceBytes;
      runtime.cpu.a = file === undefined ? MESSAGE.sourceLost : tooLong ? MESSAGE.sourceTooLong : 0;
      setCarry(file === undefined || tooLong);
      returnFromService();
      continue;
    }
    if (runtime.cpu.pc === symbols.AtomFileRead) {
      // The file's length marks its end. Each byte comes through the tool
      // services, so a named-object profile supplies its own source.
      const part = runtime.cpu.a;
      const offset = pair(runtime.cpu.h, runtime.cpu.l);
      const file = files[part];
      if (file === undefined) {
        runtime.cpu.a = MESSAGE.sourceLost;
        setCarry(true);
      } else if (offset >= file.originalBytes.length) {
        runtime.cpu.a = 0;
        setCarry(true);
      } else {
        const response = toolServices.dispatch(ATOM_TOOL_SERVICE.sourceRead, { part, offset });
        const ok = response.status === 0 && response.value !== undefined;
        if (ok) sourceReads += 1;
        runtime.cpu.a = ok ? response.value : MESSAGE.sourceLost;
        setCarry(!ok);
      }
      returnFromService();
      continue;
    }
    if ((runtime.cpu.pc === symbols.AtomFilePark || runtime.cpu.pc === symbols.AtomFileBack)) {
      returnFromService();
      continue;
    }
    if (runtime.cpu.pc === symbols.AtomBinaryOpen) {
      // INCBIN names a file relative to the part that contains it.
      const name = pair(runtime.cpu.h, runtime.cpu.l);
      const specifier = String.fromCharCode(
        ...memory.slice(name, name + runtime.cpu.b),
      );
      const part = files[memory[symbols.AtomTokenSourcePart]];
      binary = undefined;
      try {
        if (snapshot.readBinary !== undefined && part !== undefined) {
          const file = await snapshot.readBinary(part, specifier);
          binary = { bytes: file.originalBytes, index: 0 };
        }
      } catch {
        binary = undefined;
      }
      // A file too long for a 16-bit length needs an explicit count.
      const length = binary?.bytes.length ?? 0;
      runtime.cpu.a = binary === undefined || length > 0xffff ? 1 : 0;
      runtime.cpu.h = (length >>> 8) & 0xff;
      runtime.cpu.l = length & 0xff;
      runtime.cpu.flags.C = binary === undefined ? 1 : 0;
      returnFromService();
      continue;
    }
    if (runtime.cpu.pc === symbols.AtomBinaryRead) {
      const byte = binary?.bytes[binary.index];
      if (byte !== undefined) binary.index += 1;
      runtime.cpu.a = byte ?? 1;
      runtime.cpu.flags.C = byte === undefined ? 1 : 0;
      returnFromService();
      continue;
    }
    if (runtime.cpu.pc === symbols.AtomOutputSetOrigin) {
      const address = pair(runtime.cpu.h, runtime.cpu.l);
      const source = currentDiagnostic();
      layout.push(Object.freeze({ kind: "org", address, count: 0, source }));
    } else if (runtime.cpu.pc === symbols.AtomOutputReserve) {
      const cursor = logicalCursor(
        word(memory, symbols.AtomOutputCursor),
        (memory[symbols.AtomOutputFlags] & 1) !== 0,
      );
      const count = pair(runtime.cpu.h, runtime.cpu.l);
      layout.push(
        Object.freeze({
          kind: "reserve",
          address: cursor,
          count,
          source: currentDiagnostic(),
        }),
      );
    } else if (
      runtime.cpu.pc === symbols.AtomSymbolDeclare ||
      runtime.cpu.pc === symbols.AtomSymbolDeclareGlobalLabel
    ) {
      const name = unpackPackedSymbol(
        memory,
        pair(runtime.cpu.h, runtime.cpu.l),
        symbols,
      );
      if (name !== undefined) {
        declaredSymbols.push(
          Object.freeze({
            name,
            value: pair(runtime.cpu.d, runtime.cpu.e),
            source: currentDiagnostic(),
          }),
        );
      }
    }
    if (trace !== undefined) traceAt(runtime.cpu.pc);
    const service = serviceAt.get(runtime.cpu.pc);
    if (service !== undefined) {
      const cause = invokeService(
        runtime,
        service.kind,
        service.action,
        serviceTrace,
      );
      serviceException ??= cause;
      continue;
    }
    if (instructions >= maxInstructions || cycles > maxCycles) {
      throw runtimeFailure(
        "budget",
        "native Atom exceeded its execution budget",
      );
    }
    if (runtime.cpu.halted) {
      throw runtimeFailure("halt", "native Atom halted before returning");
    }
    const step = runtime.step();
    instructions += 1;
    cycles += step.cycles ?? 0;
  }

  const sinkState = sink.snapshot();
  const execution = Object.freeze({
    instructions,
    cycles,
    serviceCalls: serviceTrace.length,
    serviceTrace: Object.freeze(serviceTrace),
    finalSp: runtime.cpu.sp,
    returnPc: runtime.cpu.pc,
    sourceReads,
  });
  // A successful status alone cannot prove a valid return. Check the stack,
  // caller descriptors and immutable resident bytes on both success and error.
  const invariants = [
    [
      runtime.cpu.sp === RETURN_SLOT + 2,
      "native Atom returned with an unbalanced stack",
    ],
    [
      memory[STACK_BEFORE] === 0x87,
      "native Atom crossed the lower stack canary",
    ],
    [
      memory[STACK_AFTER] === 0x78,
      "native Atom crossed the upper stack canary",
    ],
    [
      buildDescriptorBefore.every(
        (byte, index) => memory[BUILD_DESCRIPTOR + index] === byte,
      ),
      "native Atom changed build descriptor bytes",
    ],
    [
      immutable.every(({ start, bytes }) =>
        bytes.every((byte, index) => memory[start + index] === byte),
      ),
      "native Atom changed immutable code or tables",
    ],
  ];
  const broken = invariants.find(([ok]) => !ok);
  if (broken !== undefined) {
    throw new AtomAssemblyError("native", "memory-invariant", broken[1], {
      execution,
      sink: sinkState,
    });
  }

  const result = Object.freeze({
    status: runtime.cpu.a,
    carry: runtime.cpu.flags.C,
    driverDetail: memory[symbols.AtomDriverDetail],
    statementDetail: memory[symbols.AtomStatementDetail],
    parserSymbolStatus: memory[symbols.AtomParserSymbolStatus],
    part: memory[symbols.AtomStatementErrorPart],
    offset: word(memory, symbols.AtomStatementErrorOffset),
    line: word(memory, symbols.AtomStatementErrorLine),
    undefinedSymbol: word(memory, symbols.AtomDriverUndefinedSymbol),
    message: memory[symbols.AtomDriverMessage],
    relatedPart: memory[symbols.AtomDriverRelatedPart],
    relatedOffset: word(memory, symbols.AtomDriverRelatedOffset),
    relatedLine: word(memory, symbols.AtomDriverRelatedLine),
    diagnosticSymbol: word(memory, symbols.AtomDiagnosticSymbol),
    diagnosticValue: (word(memory, symbols.AtomDiagnosticValue) << 16) >> 16,
  });
  if (result.carry !== 0 || result.status !== symbols.AtomDriverStatusOk) {
    throw nativeFailure(
      result,
      { parts: files },
      memory,
      symbols,
      memoryLayout,
      sinkState,
      execution,
      serviceException,
      bridgeFailure,
    );
  }
  if (sinkState.open || sinkState.generation === undefined) {
    throw new AtomAssemblyError(
      "output",
      "missing-generation",
      "native Atom returned without one committed host generation",
      {
        execution,
        sink: sinkState,
      },
    );
  }
  return Object.freeze({
    generation: Object.freeze({
      ...sinkState.generation,
      layout: Object.freeze(layout.slice()),
      symbols: uniqueDeclarations(declaredSymbols),
      symbolOrder: globalSymbolOrder(memory, symbols),
    }),
    ...(trace === undefined ? {} : { trace: Object.freeze([...trace, Object.freeze({ stage: "symbols", records: globalSymbolRecords(memory, symbols) })]) }),
    parts: Object.freeze(files.slice()),
    segments: Object.freeze(segments.map((segment) => Object.freeze(segment))),
    execution,
    native: result,
    core: Object.freeze({
      codeBytes: core.codeBytes,
      residentExtentBytes: core.residentExtentBytes,
    }),
    memoryLayout,
  });
}
