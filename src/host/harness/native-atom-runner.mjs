import {
  MemorySourceByteProvider,
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

// The core occupies the first 16 KiB. Its build descriptor, symbol arena,
// pending-reference arena and source descriptors occupy separate RAM regions.
// Output bytes go to the host sink, so assembled addresses do not name this RAM.
const BUILD_DESCRIPTOR = 0x4000;
const SYMBOL_START = 0x4100;
const SYMBOL_END = 0xa000;
const PENDING_START = 0xa000;
const PENDING_END = 0xd000;
const PART_DESCRIPTORS = 0xd000;
const STACK_BEFORE = 0xfe00;
const RETURN_SLOT = 0xfefd;
const STACK_AFTER = 0xfeff;
const RETURN_SENTINEL = 0xfffe;
const DEFAULT_NATIVE_MEMORY_LAYOUT = Object.freeze({
  symbolStart: SYMBOL_START,
  symbolEnd: SYMBOL_END,
  pendingStart: PENDING_START,
  pendingEnd: PENDING_END,
  partDescriptors: PART_DESCRIPTORS,
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
  "AtomDriverDescriptorParts",
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
  "AtomDriverPartDescriptorBytes",
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
      !(part.compilerBytes instanceof Uint8Array) ||
      part.originalBytes.length !== part.compilerBytes.length
    ) {
      fail(
        "invalid-part",
        `resolved Atom source part ${ordinal} is not a flat, equal-length native part`,
      );
    }
    if (part.compilerBytes.length > NATIVE_ATOM_LIMITS.sourceBytes) {
      fail(
        "source-capacity",
        `resolved Atom source part ${ordinal} exceeds Atom's 16-bit source-offset range`,
      );
    }
    const binaryIncludes = part.binaryIncludes ?? [];
    if (!Array.isArray(binaryIncludes)) {
      fail(
        "invalid-part",
        `resolved Atom source part ${ordinal} has invalid binary includes`,
      );
    }
    const sourceLines = new Set();
    const frozenIncludes = binaryIncludes.map((include) => {
      if (
        include === null ||
        typeof include !== "object" ||
        !Number.isInteger(include.offset) ||
        include.offset < 0 ||
        include.offset >= part.originalBytes.length ||
        !Number.isInteger(include.line) ||
        include.line < 1 ||
        !(include.bytes instanceof Uint8Array) ||
        include.bytes.length > 0xffff ||
        sourceLines.has(include.line)
      ) {
        fail(
          "invalid-part",
          `resolved Atom source part ${ordinal} has an invalid binary include`,
        );
      }
      sourceLines.add(include.line);
      return Object.freeze({
        offset: include.offset,
        line: include.line,
        bytes: include.bytes.slice(),
      });
    });
    return Object.freeze({
      ordinal,
      bank: 0,
      logicalIdentity: part.logicalIdentity,
      originalBytes: part.originalBytes.slice(),
      compilerBytes: part.compilerBytes.slice(),
      binaryIncludes: Object.freeze(frozenIncludes),
    });
  });
  return Object.freeze({
    parts: Object.freeze(parts),
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

function nativeMemoryLayout(
  option = {},
  { core, partCount, partDescriptorBytes },
) {
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
    partDescriptors: memoryAddress(
      option.partDescriptors ?? DEFAULT_NATIVE_MEMORY_LAYOUT.partDescriptors,
      "nativeMemoryLayout.partDescriptors",
    ),
  });
  const partDescriptorEnd =
    layout.partDescriptors + partCount * partDescriptorBytes;
  if (partDescriptorEnd > STACK_BEFORE) {
    fail(
      "memory-map",
      "native Atom part descriptors overlap the host stack canary",
    );
  }
  assertNonOverlapping([
    range(0, core.residentExtentBytes, "native Atom resident core"),
    range(
      BUILD_DESCRIPTOR,
      BUILD_DESCRIPTOR + core.symbols.AtomDriverDescriptorBytes,
      "native Atom build descriptor",
    ),
    range(layout.symbolStart, layout.symbolEnd, "native Atom symbol arena"),
    range(layout.pendingStart, layout.pendingEnd, "native Atom pending arena"),
    range(
      layout.partDescriptors,
      partDescriptorEnd,
      "native Atom part descriptors",
    ),
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

function sourcePosition(part, offset) {
  let line = 1;
  let column = 1;
  const bounded = Math.min(offset, part.originalBytes.length);
  for (let index = 0; index < bounded; index += 1) {
    const byte = part.originalBytes[index];
    if (byte === 0x0a) {
      line += 1;
      column = 1;
    } else if (byte !== 0x0d) {
      column += 1;
    }
  }
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
    (part === undefined ? undefined : sourcePosition(part, result.offset));
  const relatedPart = result.relatedPart === 0xff ? undefined : project.parts[result.relatedPart];
  const relatedDiagnostic = relatedPart === undefined
    ? undefined
    : sourcePosition(relatedPart, result.relatedOffset);
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
  return new AtomAssemblyError("native", "internal", located(text), { ...common, text });
}

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
  const memoryLayout = nativeMemoryLayout(options.nativeMemoryLayout, {
    core,
    partCount: snapshot.parts.length,
    partDescriptorBytes: symbols.AtomDriverPartDescriptorBytes,
  });
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
  memory.fill(
    0xa5,
    memoryLayout.partDescriptors,
    memoryLayout.partDescriptors +
      snapshot.parts.length * symbols.AtomDriverPartDescriptorBytes,
  );
  for (const part of snapshot.parts) {
    const descriptor =
      memoryLayout.partDescriptors +
      part.ordinal * symbols.AtomDriverPartDescriptorBytes;
    memory[descriptor] = part.ordinal;
    writeWord(memory, descriptor + 1, 0);
    writeWord(memory, descriptor + 3, part.compilerBytes.length);
  }
  memory[BUILD_DESCRIPTOR] = snapshot.parts.length;
  writeWord(
    memory,
    BUILD_DESCRIPTOR + symbols.AtomDriverDescriptorParts,
    memoryLayout.partDescriptors,
  );
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
  const partDescriptorsBefore = memory.slice(
    memoryLayout.partDescriptors,
    memoryLayout.partDescriptors +
      snapshot.parts.length * symbols.AtomDriverPartDescriptorBytes,
  );

  memory[STACK_BEFORE] = 0x87;
  memory[RETURN_SLOT] = RETURN_SENTINEL & 0xff;
  memory[RETURN_SLOT + 1] = RETURN_SENTINEL >>> 8;
  memory[STACK_AFTER] = 0x78;
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
  const defaultSourceProvider = new MemorySourceByteProvider(
    snapshot.parts.map((part) => ({
      ordinal: part.ordinal,
      bytes: part.compilerBytes,
    })),
  );
  const binaryIncludes = new Map();
  for (const part of snapshot.parts) {
    for (const include of part.binaryIncludes) {
      binaryIncludes.set(`${part.ordinal}:${include.line}`, {
        bytes: include.bytes,
        index: 0,
        diagnostic: sourcePosition(part, include.offset),
      });
    }
  }
  let sourceReads = 0;
  const currentDiagnostic = () => {
    const ordinal = memory[symbols.AtomStatementErrorPart];
    const part = snapshot.parts[ordinal];
    return part === undefined
      ? undefined
      : sourcePosition(part, word(memory, symbols.AtomStatementErrorOffset));
  };
  // A 16-bit zero can mean address zero or the exclusive endpoint $10000.
  // The native output flags distinguish the endpoint from an ordinary cursor.
  const logicalCursor = (cursor, endpoint) => endpoint ? 0x10000 : cursor;
  const toolServices = createAtomToolServiceGateway({
    sink,
    sourceRead:
      profile?.sourceRead ??
      (({ part, offset }) => {
        const value = defaultSourceProvider.read(part, offset);
        if (value === undefined) {
          throw runtimeFailure(
            "source-read",
            "native Atom requested a source byte outside the resolved part",
          );
        }
        sourceReads += 1;
        return value;
      }),
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
          const source = currentDiagnostic();
          const binary = binaryIncludes.get(
            `${source?.ordinal}:${source?.line}`,
          );
          if (binary !== undefined && binary.index >= binary.bytes.length) {
            bridgeFailure ??= Object.freeze({
              message:
                "INCBIN emitted more bytes than its resolved binary input",
              diagnostic: binary.diagnostic,
            });
            return ATOM_HOST_SINK_STATUS.BINARY_INCLUDE;
          }
          const byte =
            binary === undefined ? runtime.cpu.a : binary.bytes[binary.index++];
          return toolServices.dispatch(ATOM_TOOL_SERVICE.image, {
            bank: runtime.cpu.c,
            address,
            bytes: Object.freeze([byte]),
            source,
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
          const incompleteBinary = [...binaryIncludes.values()].find(
            ({ bytes, index }) => index !== bytes.length,
          );
          if (incompleteBinary !== undefined) {
            bridgeFailure ??= Object.freeze({
              message:
                "INCBIN emitted fewer bytes than its resolved binary input",
              diagnostic: incompleteBinary.diagnostic,
            });
            return ATOM_HOST_SINK_STATUS.BINARY_INCLUDE;
          }
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
  while (runtime.cpu.pc !== RETURN_SENTINEL) {
    if (runtime.cpu.pc === symbols.AtomSourceReadByte) {
      const offset = pair(runtime.cpu.h, runtime.cpu.l);
      const response = toolServices.dispatch(ATOM_TOOL_SERVICE.sourceRead, {
        part: runtime.cpu.a,
        offset,
      });
      if (response.status !== 0 || response.value === undefined) {
        throw runtimeFailure(
          "source-read",
          "native Atom tool services rejected a source byte",
        );
      }
      const returnAddress = word(memory, runtime.cpu.sp);
      runtime.cpu.sp = (runtime.cpu.sp + 2) & 0xffff;
      runtime.cpu.pc = returnAddress;
      runtime.cpu.a = response.value;
      runtime.cpu.flags.C = 0;
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
      partDescriptorsBefore.every(
        (byte, index) => memory[memoryLayout.partDescriptors + index] === byte,
      ),
      "native Atom changed part descriptor bytes",
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
    undefinedSymbol: word(memory, symbols.AtomDriverUndefinedSymbol),
    message: memory[symbols.AtomDriverMessage],
    relatedPart: memory[symbols.AtomDriverRelatedPart],
    relatedOffset: word(memory, symbols.AtomDriverRelatedOffset),
    diagnosticSymbol: word(memory, symbols.AtomDiagnosticSymbol),
    diagnosticValue: (word(memory, symbols.AtomDiagnosticValue) << 16) >> 16,
  });
  if (result.carry !== 0 || result.status !== symbols.AtomDriverStatusOk) {
    throw nativeFailure(
      result,
      snapshot,
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
    execution,
    native: result,
    core: Object.freeze({
      codeBytes: core.codeBytes,
      residentExtentBytes: core.residentExtentBytes,
    }),
    memoryLayout,
  });
}
