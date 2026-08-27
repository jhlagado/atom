# Chapter 4 — Host execution, artifacts, and interfaces

[← Native Z80 assembly pipeline](03-native-z80-assembly-pipeline.md) | [Native core generation and self-hosting →](05-native-core-generation-and-self-hosting.md)

The Mac host takes the prepared source parts, executes the pinned native core,
captures its logical output, renders user artifacts, and publishes a complete
generation. These operations are separate modules so tests and tool consumers
can stop at the boundary they need.

The normal high-level sequence is:

```js
const assembled = await assembleAtomProject(BUILD_OPTIONS);
const artifacts = renderAtomArtifacts(assembled, ARTIFACT_OPTIONS);
const publication = await publishAtomArtifacts(DESTINATION, BASENAME, artifacts);
```

Debug80 or another tool can use the first two calls in process and retain every
artifact in memory. Filesystem publication is optional.

## Pinned native core

`src/host/core/native-atom-core.mjs` loads `assets/native-core.json`. The checked
artifact contains:

- Intel HEX for the linked native image;
- the native-core symbol map;
- a SHA-256 of the HEX text;
- a SHA-256 covering the HEX and symbol map together; and
- the readable source identity used to generate it.

The loader checks both digests, every required entry symbol, and the one-bank
resident limit. It derives the immutable code ranges for the encoder, symbols,
tokenizer, expressions, patch locator, parser, output, statements, driver, and
host stubs. `loadNativeAtomCore()` caches the validated promise so repeated
builds in one process do not reopen the asset.

The native runner also validates a caller-supplied replacement core. That path
is used by the second self-host generation. It parses the HEX before execution,
checks that writes stay inside the resident extent, proves every declared code
byte is initialized, verifies code entries and state addresses, and recomputes
the code-byte total from the supplied ranges.

## Programmatic assembly entry

`assembleAtomProject()` is the complete filesystem-to-generation entry:

```js
import { assembleAtomProject } from "atom-z80";

const result = await assembleAtomProject({
  root: "/ABSOLUTE/PROJECT/ROOT",
  entry: "src/main.asm",
  definitions: { DEBUG: 1 },
  placement: { defaultBank: 0, banks: {} },
  target: { start: 0x4000, capacity: 0x2000 },
});
```

The optional execution controls are `maxInstructions`, `maxCycles`, and a
custom sink. The default budgets are 200,000,000 instructions and
2,000,000,000 T-states. `limits` may lower project-preparation capacities, but this
entry caps parts at 255 and banks at zero to match the native driver.

The function returns the resolved `project` together with:

```text
generation   COMMITTED IMAGE, PATCH, LAYOUT, SYMBOL, AND TARGET DATA
execution    INSTRUCTION, CYCLE, SERVICE, SOURCE-READ, STACK, AND RETURN OBSERVATIONS
native       DRIVER STATUS AND NESTED NATIVE STATUS FIELDS
core         CODE-BYTE AND RESIDENT-EXTENT MEASUREMENTS
```

`assembleResolvedAtomProject()` is the lower-level entry for an already
prepared ordered project. It is used by self-host tests and can be used by an
operating adapter that constructs the same part shape without Node filesystem
preparation.

The package currently exposes these functions directly rather than through a
versioned `createAtomAssembler()` facade. Consumers should use the package root
exports and avoid importing private files below `src/host/`.

## AZM source conversion

`translateAzmSourceToAtom()` is the strict, in-memory migration entry:

```js
import { translateAzmSourceToAtom } from "atom-z80";

const atomSource = translateAzmSourceToAtom(azmSource, {
  sourceName: "source/main.asm",
});
```

The converter recognizes the Z80 instruction set and the shared assembler
directives. It translates underscore locals, byte functions, numeric prefixes,
proof annotations, and directive forms. It also enforces Atom's symbol and
immediate-equate constraints before returning the LF-normalized text.

Unsupported AZM constructs throw `AtomAssemblyError` with category
`translation`, a stable code, and a one-based source diagnostic. The converter
does not guess at imports, conditional assembly, ops, layouts, exports, or
string equates. This rule keeps conversion separate from the project preparation
and prevents a syntax rewrite from silently changing output bytes.

`bin/azm-to-atom.mjs` adds filesystem policy around the pure function. It reads
the complete input first, refuses to overwrite a destination, and writes no
partial output after a translation failure. The installed converter has no AZM
runtime dependency.

## Native proof memory map

`src/host/harness/native-atom-runner.mjs` uses a fixed 64 KiB Mac proof map:

| Region | Address | Bytes |
| --- | --- | ---: |
| Linked core, workspace, and sink stubs | `$0000..$306C` | 12,396 |
| Free space below descriptor boundary | `$306C..$4000` | 3,988 |
| Build descriptor | `$4000..$400F` | 15 |
| Free descriptor gap | `$400F..$4100` | 241 |
| Symbol arena | `$4100..$7500` | 13,312 |
| Pending arena | `$7500..$8800` | 4,864 |
| Free arena gap | `$8800..$9000` | 2,048 |
| Maximum part descriptors | `$9000..$94FB` | 1,275 |
| Host-free memory below proof stack | `$94FB..$FE00` | 26,885 |
| Proof stack | `$FE00..$FF00` | 256 |
| Reserved top page | `$FF00..$10000` | 256 |

This is a test and Mac execution map, not a proposed TEC-1 RAM layout. A TEC
adapter must choose its own symbol, pending, descriptor, source-service state,
and stack regions.

## Source snapshots and byte service

The runner validates and snapshots every prepared part before constructing Z80
memory. It requires:

- one through 255 parts in ordinal order;
- bank zero;
- matching original and compiler byte lengths;
- at most 65,535 bytes in each part; and
- structurally valid `INCBIN` metadata.

Each native descriptor records start zero and end equal to the part length.
When execution reaches `AtomSourceReadByte`, A selects the part and HL selects
the logical offset. The runner returns the byte from the immutable snapshot and
rejects an unknown part or out-of-range offset. Source occupies no emulated Z80
page. The runner still checks the complete descriptor interval and every
immutable native code or table range after execution.

## Calling the Z80 core

The runner writes the build descriptor and part descriptors, installs stack
canaries around a sentinel return address, sets `SP`, `PC`, and `IX`, and steps
the Debug80 runtime until the sentinel PC is reached.

The loop stops with a structured failure when:

- the instruction or cycle budget is exhausted;
- the CPU halts before returning;
- the native core returns through the wrong PC or with an unbalanced stack;
- either stack canary changes;
- descriptors, code, or immutable tables change; or
- the sink lifecycle cannot be closed safely.

Execution statistics retain the instruction count, T-states, service count,
service trace, source-read count, final SP, and return PC.

The source-read entry has a linked memory-backed implementation for direct
native harnesses and hardware configurations that keep a part in memory. The
Mac runner intercepts the entry before that fallback executes.

## Host sink interception

The linked core ends with six Z80 sink stubs. Each stub returns `$FF` with carry
set when it executes normally, so missing host interception fails closed. The
runner intercepts the entry PC before executing the stub, reads the documented
register arguments, calls the JavaScript sink, pops the native return address,
and resumes with status in A and carry.

| Native entry | JavaScript sink method | Logical operation |
| --- | --- | --- |
| `AtomSinkBegin` | `begin()` | Open one tentative generation |
| `AtomSinkImageByte` | `image()` | Append one initialized byte |
| `AtomSinkPatchByte` | `patch()` | Append one final replacement byte |
| `AtomSinkPatchWord` | `patch()` | Append one final little-endian replacement word |
| `AtomSinkCommit` | `commit()` | Validate and retain the generation |
| `AtomSinkAbort` | `abort()` | Discard tentative operations |

A JavaScript exception becomes host status `$EF`, allowing the native driver to
take its normal failure and abort path. The runner retains the original
exception as the cause of the resulting `AtomAssemblyError`.

The loop also records entry to `AtomOutputSetOrigin`, `AtomOutputReserve`, and
the symbol declaration routines. The resulting records add layout and source
symbol metadata without changing native control flow or output bytes.

## Memory sink

`createMemoryAtomSink()` implements the default append-only adapter. It
maintains a lifecycle, tentative IMAGE and PATCH arrays, written-address sets,
and one committed generation.

The sink checks:

- exactly one open generation;
- bank zero;
- target range for every operation;
- monotonically increasing, non-overlapping IMAGE addresses;
- PATCH targets that name an earlier IMAGE byte; and
- at most one PATCH per initialized address.

Commit verifies the original descriptor identity, remaining capacity, final
cursor, and logical high-water mark. Success freezes the operation arrays and
closes the generation. Abort clears all tentative operations.

The generation retains byte payloads as frozen arrays of numbers. This avoids
the false impression that a frozen object also freezes a contained
`Uint8Array`. `materializeAtomGeneration()` allocates a new `Uint8Array`, fills
the logical range, applies IMAGE records, then applies PATCH records.

## `INCBIN` bridge

The source-preparation phase retains one binary snapshot keyed by source part
and line. When the native core submits an IMAGE byte from the lowered `DS` line,
the runner substitutes the next byte from that snapshot. Native output
capacity, label positions, and IMAGE count still come from the Z80 core.

Commit fails when the native line emits too many or too few bytes. The bridge
also retains the original `INCBIN` source location for that failure. This check
prevents a stale lowering rule from silently shifting later addresses or
truncating binary data.

## Diagnostics

Host preparation throws `SourcePreparationError` with category, code, message, and
an optional source location. Native execution, artifact creation, and
publication throw `AtomAssemblyError` with the same broad machine-readable
shape plus details appropriate to the boundary.

Native source failures are reconstructed from the original source part:

```text
lib/device.asm:14:9: UNDEFINED SYMBOL PORTBASE
```

The diagnostic carries logical identity, ordinal, exact byte offset, one-based
line, and one-based byte column. Undefined-symbol failures also unpack the exact
RADIX-40 name from the native symbol record.

Equal-length preprocessing and `INCBIN` lowering make this mapping direct. The
runner does not need a transformed-to-original offset table.

## Artifact rendering

`renderAtomArtifacts()` receives the resolved project and committed generation.
It returns every current artifact in memory:

```js
const artifacts = renderAtomArtifacts(result, {
  fill: 0,
  entryAddress: 0x4000,
});

// artifacts.nobj    Uint8Array
// artifacts.bin     Uint8Array
// artifacts.hex     string
// artifacts.listing string
// artifacts.d8      object
// artifacts.d8Text  string
```

The selected fill byte supplies gaps and uninitialized reservations in flat
BIN and HEX output. It does not convert native `DS` into IMAGE records or alter
the canonical logical generation.

### Atom NOBJ

`atom-nobj.mjs` writes Atom's flat NOBJ profile 0.2:

```text
BEGIN IMAGE* PATCH* MAP COMMIT
```

Adjacent logical operations are coalesced without changing order. The flat MAP
records entry, used length, final cursor, part count, and part banks. COMMIT
contains record count, entry, and CRC-16/CCITT-FALSE. `parseAtomNobj()` checks
framing, version, record order, map revision, record count, and CRC.

NOBJ is the closest artifact to the native streaming result. BIN and HEX are
materialized launch views.

### Binary and Intel HEX

`materializeAtomGeneration()` selects a range from target start through the
largest final cursor, high-water mark, or IMAGE end. It fills the range, copies
IMAGE bytes, and overwrites patched addresses with their final bytes.

`writeIntelHex()` emits 16-byte data records followed by the standard EOF
record. It consumes the materialized contiguous image rather than the sparse
logical operation stream.

### Listing

`writeAtomListing()` reads `originalBytes`, not masked compiler text. It groups
IMAGE and layout events by source part and line, applies final patched bytes,
and writes up to eight bytes per listing row. `DS` reservations receive an
address and `<COUNT reserved>` gutter. The trailer contains sorted labels and
constants with their source identities.

### D8 map

`writeAtomD8()` derives file segments from the same line-grouped operations.
It records source files, line and listing positions, code/data/directive kinds,
global or local scope, symbol visibility, entry address, and the overall target
segment. `INCBIN` retains the original source line as a data segment.

The D8 map is a host artifact. The resident assembler emits no mapping schema
and carries no file path.

## Artifact publication

`publishAtomArtifacts()` writes one content-addressed immutable generation. Its
digest covers each artifact name and byte sequence in a fixed order. A new
temporary directory receives:

```text
BASENAME.NOBJ
BASENAME.BIN
BASENAME.HEX
BASENAME.LST
BASENAME.D8.JSON
MANIFEST.JSON
```

Each file is synchronized before the directory is synchronized and renamed to
its digest. If the digest directory already exists, the publisher verifies
every byte and its manifest before reuse. It then creates a temporary symlink
and atomically renames that link over `current`.

A failed build never calls publication. A staging or promotion failure leaves
the previous `current` generation selected. Old successful generations are
retained; automatic pruning is not implemented.

## Command-line entry

`bin/atom.mjs` is a thin filesystem-facing wrapper. It:

1. parses command arguments and `-D` definitions;
2. chooses the root, target, entry, definitions, and requested output paths;
3. calls `assembleAtomProject()`;
4. renders the requested artifact formats;
5. stages every selected file before replacing any previous output; and
6. prints one success summary or one positioned failure.

The normal command shape is:

```sh
atom src/main.asm build/main.bin
```

`atom self-host` selects the checked source shipped in the package and fixes the
proof target. It accepts only positive output paths.

Command misuse returns status 2. A failed build or publication returns status
1. A successful published build returns status 0.

## Tool integration

A tool such as Debug80 can import `atom-z80`, call
`assembleAtomProject()` in process, validate `artifacts.d8` through its normal
D8 parser, and load `artifacts.hex` or `artifacts.bin`. It does not need to run
the CLI or parse terminal output. It should retain ownership of application
publication and launch policy.

Tools request files by selecting from the rendered in-memory artifact set:

```js
import {
  assembleAtomProject,
  publishAtomOutputFiles,
  renderAtomArtifacts,
} from "atom-z80";

const result = await assembleAtomProject({
  root: PROJECT_ROOT,
  entry: "src/main.asm",
  target: { start: 0, capacity: 0xffff },
});
const artifacts = renderAtomArtifacts(result, {
  base: 0x4000,
  entryAddress: 0x4000,
});

await publishAtomOutputFiles([
  { path: "build/main.hex", bytes: artifacts.hex },
  { path: "build/main.d8.json", bytes: artifacts.d8Text },
]);
```

That call publishes exactly the two selected paths. BIN, listing, NOBJ, and COM
bytes remain available in memory when the caller needs them.

The current package root exports both high-level and advanced functions. A
future stable host facade can wrap these calls in a versioned assembler object
and tagged result union without changing the native core or the logical output
boundary described here.
