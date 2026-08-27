# Chapter 2 — Host source preparation

[← Orientation and repository layout](01-orientation-and-repository-layout.md) | [Native Z80 assembly pipeline →](03-native-z80-assembly-pipeline.md)

Host preparation turns a filesystem entry into an ordered array of immutable
source-part descriptions. It resolves dependencies, evaluates host
conditionals, masks host-owned syntax, snapshots binary inputs, assigns source
ordinals, and retains enough provenance for native diagnostics and later
artifacts.

The native assembler receives the resulting ordered parts through its source
service. It does not read a
manifest, open a path, evaluate a host conditional, or concatenate files.

## Composition entry point

`resolveAtomProject()` in `src/host/application/resolve-atom-project.mjs` is the Atom-specific
preparation entry:

```js
const project = await resolveAtomProject({
  root: "/ABSOLUTE/PROJECT/ROOT",
  entry: "src/main.asm",
  definitions: { DEBUG: 1 },
  placement: {
    defaultBank: 0,
    banks: {},
  },
});
```

The function snapshots its definitions, placement, and limits before the first
filesystem wait. It then constructs a Node source reader, runs the neutral
resolver with Atom's source profile, and lowers every active `INCBIN` after the
source graph and ordinals are fixed.

The returned project contains:

- `parts`, in native compilation order;
- `bankArray`, indexed by source-part ordinal;
- the frozen `%DEFINE` state established by the entry;
- the total retained logical-path byte count; and
- original, compiler, dependency, binary-input, and provenance data for every
  part.

`assembleAtomProject()` calls this function with the native limits: at most 255
parts and bank zero.

## Source reader and three identities

`createNodeSourceReader()` in the shared `source-preparation` package opens the
project root through `realpath()` and keeps three source identities separate:

| Identity | Meaning |
| --- | --- |
| `physicalPath` | Canonical host path that was opened |
| `dependencyIdentity` | Canonical identity used for graph deduplication and cycle detection |
| `logicalIdentity` | Normalized project-relative path used in diagnostics, listings, D8 maps, and placement |

An include specifier resolves relative to the importing file. The reader
rejects absolute paths, lexical `..` escapes, symlink targets outside the
project root, missing files, and a requested path whose case conflicts with the
physical directory entry. These checks occur before the source enters the
compiler.

The reader snapshots each physical file once. A later read of the same
dependency identity returns the existing snapshot, so a filesystem mutation
during one preparation run cannot change that build's source bytes.

`originalBytes` remains a `Uint8Array`. Its surrounding record is frozen, but
JavaScript cannot freeze the individual array elements. Callers therefore
treat prepared byte arrays as read-only. The native runner takes its own copies
before execution.

## Neutral dependency resolution

`resolveSourceProject()` in the same package owns graph traversal. The resolver
accepts a reader and a language profile rather than importing Atom syntax. It
validates every reader snapshot and profile result before adding it to the
graph.

Traversal is deterministic depth-first postorder:

```text
main.asm INCLUDES display.asm, input.asm
display.asm INCLUDES hardware.asm
input.asm INCLUDES hardware.asm

ORDERED PARTS:
  hardware.asm
  display.asm
  input.asm
  main.asm
```

The shared dependency appears once. Dependencies precede their importer, and
sibling order follows the source. A repeated dependency from the same importer
is an error rather than textual repetition. A cycle retains the complete active
edge sequence and the location of each `%INCLUDE` that formed it.

The resolver enforces part count, graph depth, path length, retained path bytes,
and bank ordinal before publication. Boundary tests accept each exact limit and
reject its first excess value.

## Language profile boundary

The neutral resolver calls two profile methods:

```js
profile.inspectEntry(entrySnapshot, configuration)
profile.inspectDependency(dependencySnapshot, entryState)
```

Each result supplies equal-length compiler bytes, dependency references, and
masked ranges. The entry result also supplies frozen state passed to every
dependency. `createAtomSourceProfile()` implements these methods by calling
`inspectAtomSource()` with the appropriate entry flag.

This profile seam lets another Z80 tool preserve its own directive syntax while
reusing path confinement, graph traversal, placement, and provenance. Atom's
`%` syntax and masking remain in `src/host/atom/`.

## Directive recognition

`directives.mjs` scans source as bytes rather than decoding the whole file. A
host directive begins when `%` is the first non-space byte on a line and an
ASCII letter follows it. This condition leaves two native expression uses
alone:

```asm
LD A,%101010
DB 7 % 3
```

Directive and definition names are case-insensitive. The profile accepts:

```asm
%DEFINE DEBUG 1
%IF DEBUG
%INCLUDE "lib/debug.asm"
%ELSE
%INCLUDE "lib/release.asm"
%ENDIF
```

`%DEFINE` binds one immutable 16-bit value. It does not replace source text and
does not create an assembler symbol. Project definitions are loaded first.
Source definitions are permitted only in the entry file's leading definition
header, and duplicate names fail even when their values match. Dependencies
receive the frozen entry state and cannot add definitions.

`parseAtomPreprocessorValue()` accepts decimal, `$` hexadecimal, `%` binary,
digit-led Intel hexadecimal with `H`, Intel binary with `B`, and a defined name.
The result must be in `0..65535`. `%IF` treats zero as false and every other
value as true.

## Headers and body conditionals

An active `%INCLUDE` creates an import-once graph edge. Includes are restricted
to the leading header of each part. A conditional that selects dependencies
must close before ordinary Atom source begins. These rules let the resolver
construct the complete graph without interpreting arbitrary assembler body
text.

Body `%IF` blocks may select ordinary source lines. They may not introduce a
dependency or definition. Conditional nesting must balance within one part; a
conditional cannot begin in one file and end in another.

Inactive includes cause no filesystem read. Directive structure is still
checked in inactive branches, which catches unmatched `%ELSE`, repeated
`%ELSE`, and unmatched or missing `%ENDIF` without selecting the branch's
dependency.

## Equal-length masking

The profile starts with a copy of `originalBytes`. It replaces every non-newline
byte on a host directive or inactive line with ASCII space. CR and LF bytes
remain unchanged:

```text
ORIGINAL:  %IF DEBUG\r\n
COMPILER:            \r\n
```

The compiler buffer has exactly the same length as the original buffer. A
native part ordinal and byte offset therefore identify the same source line and
column in both representations. No source-map translation is required for
preprocessor diagnostics.

`maskedRanges` records the half-open spans changed by the profile. The part's
provenance later carries those spans beside dependency locations and the active
include stack.

## Binary inclusion

`INCBIN` is assembler syntax with host-owned filesystem semantics. It is
processed after source ordering and placement because it emits bytes in the
native statement stream but requires a host file read.

For an active line:

```asm
FONT: INCBIN "ASSETS/FONT.BIN"
```

`lowerAtomBinaryIncludes()` performs four operations:

1. recognize the complete directive while preserving an optional label prefix;
2. resolve and snapshot the binary through the same confined source reader;
3. replace the source line with an equal-length `DS COUNT,0` line; and
4. retain the binary bytes, logical identity, source offset, line, and column
   beside the part.

The replacement must fit inside the original line extent. One binary may have
0 through 65,535 bytes. The binary is not a source part and does not enter the
dependency graph.

During native execution, `DS COUNT,0` advances labels and performs the ordinary
target-capacity checks. The host output bridge recognizes IMAGE bytes attributed
to that source line and substitutes the binary snapshot. It verifies that the
number of native bytes matches the snapshot before commit.

Inactive conditional lines are already spaces, so they trigger neither
`INCBIN` recognition nor a binary read.

## Placement

`joinSourcePlacement()` runs after dependency order is known. Placement maps
canonical source identities to bank ordinals. It rejects invalid banks,
conflicting aliases, paths outside the resolved graph, and missing assignments
when there is no default.

Native Atom currently forces every part to bank zero. The general join retains
the field so a later operating adapter can support wider placement. Placement
is carried directly on each prepared part; preparation does not write an
intermediate file.

## Prepared part shape

After placement and binary lowering, each part carries the information needed
by the remaining build:

```text
ordinal and bank
physical, dependency, and logical identities
original source bytes
equal-length compiler bytes
direct dependency records
masked and transformed ranges
binary snapshots
include-stack provenance
diagnostic name and source byte length
```

The native runner requires ordinal order, bank zero, equal original/compiler
lengths, and no part larger than the 65,535-byte logical-offset range. It takes
another immutable snapshot before execution. Source bytes remain in host
memory and are returned through `AtomSourceReadByte`.

## Changing source preparation

The owner of a change follows the kind of fact it affects:

- Path resolution, physical identity, and root confinement belong in
  `node-source-reader.mjs`.
- Graph order, deduplication, cycles, and graph capacities belong in
  `resolver.mjs`.
- Bank assignment belongs in `placement.mjs`.
- `%` directive grammar, conditional state, and masking belong in
  `atom/directives.mjs`.
- Preprocessor numeric spelling belongs in `atom/literals.mjs`.
- `INCBIN` recognition, snapshotting, and lowering belong in
  `atom/incbin.mjs`.
- The Atom-specific sequence connecting those pieces belongs in
  `application/resolve-atom-project.mjs`.

Every preparation change needs both a focused boundary test and a composed
`resolveAtomProject()` test. A change that affects native positions also needs
an included-file diagnostic or artifact-provenance discriminator.
