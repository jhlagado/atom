# Chapter 1 — Orientation and repository layout

[Manual](index.md) | [Host source preparation →](02-host-source-preparation.md)

Atom is a single-pass Z80 assembler whose authoritative assembler core is
written in Z80 assembly. The installed desktop command runs that core through
Debug80. Node supplies services that do not belong in the resident assembler:
filesystem access, conditional preprocessing, dependency discovery, binary
input, artifact rendering, and durable publication.

That split produces one build path with two execution domains:

```text
PROJECT ENTRY (.ASM)
        |
        v
NODE SOURCE READER AND ATOM PREPROCESSOR
        |  ORDERED, EQUAL-LENGTH SOURCE PARTS
        v
NATIVE ATOM CORE RUNNING IN DEBUG80
        |  IMAGE, PATCH, LAYOUT, AND SYMBOL EVENTS
        v
NODE ARTIFACT RENDERERS
        |  NOBJ, BIN, HEX, LISTING, D8
        v
SELECTED OUTPUT FILES
```

Dependency discovery and assembly are separate build stages. They are not two
assembler passes. Once the prepared parts reach `AtomAssemble`, the Z80 core
reads them in order and never returns to earlier source. Forward references are
kept in a resident pending list and produce final-byte PATCH records when their
symbols are defined.

## The governing boundary

The host and native halves exchange source descriptors and output operations.
They do not share responsibility for language semantics.

| Host or operating adapter | Native Z80 core |
| --- | --- |
| Reads files and confines paths to a project root | Tokenizes prepared source bytes |
| Resolves `%INCLUDE` dependencies | Packs and resolves case-insensitive symbols |
| Evaluates `%DEFINE`, `%IF`, `%ELSE`, and `%ENDIF` | Parses expressions, operands, and statements |
| Snapshots and lowers `INCBIN` | Encodes the complete claimed Z80 instruction set |
| Orders source parts and assigns source ordinals | Manages global and private symbol scope |
| Implements the output sink | Decides when IMAGE and PATCH operations occur |
| Renders NOBJ, BIN, HEX, listing, and D8 | Performs final undefined-symbol checks |
| Publishes selected output files | Begins, commits, or aborts one output generation |

The same native core runs behind the desktop adapter and the native CP/M
adapter, and can later run behind a TEC-1 operating adapter. Native code
contains no path, filesystem, dependency-graph, Intel HEX, listing, or D8 logic.

## A small build from end to end

Consider an entry file with one dependency and one forward reference:

```asm
%INCLUDE "lib/device.asm"

ORG 4000H
START:
    LD A,DEVICEID
    JR .DONE
    DB 0
.DONE:
    DW START
```

The host resolves `lib/device.asm` relative to the importer and emits the
dependency before the entry. It replaces the `%INCLUDE` line with spaces while
preserving the line ending and total byte count. Each file remains a separate
source part with its own logical identity.

`AtomAssemble` resets the caller-owned symbol and pending arenas, opens an
output generation, and assembles each part. The tokenizer supplies names,
numbers, punctuation, strings, EOL, and EOF records. The statement layer
recognizes `ORG`, labels, instructions, and data. The parser classifies the
instruction operands and calls the encoder. If `.DONE` has not yet been
defined, Atom emits the `JR` opcode and a placeholder displacement as IMAGE
bytes, then records the patch address and symbol pointer. Defining `.DONE`
submits the final displacement as a PATCH and removes the pending record.

After the last part, the driver checks for unresolved symbols and validates the
last private scope. A successful commit returns one logical generation to the
host. The renderers derive NOBJ, flat binary, Intel HEX, a listing, and a D8 map
from that generation and the retained original source.

## Repository shape

The top-level repository is deliberately direct:

```text
atom/
  assets/              PINNED GENERATED NATIVE CORE
  bin/                 INSTALLED COMMAND-LINE ENTRY
  docs/                PRODUCT, ABI, PHASE, AND ENGINEERING DOCUMENTATION
  examples/            SHIPPED SOURCE PROJECTS
  proofs/              FROZEN CENSUSES, MEMORY MAPS, AND MEASUREMENTS
  scripts/             NATIVE-CORE AND RELEASE CHECKS
  native/              AUTHORITATIVE ATOM-SYNTAX NATIVE CORE AND SYMBOL LEDGER
  src/                 HOST IMPLEMENTATION AND GENERATED-TABLE INPUTS
  test/                NATIVE, HOST, DIFFERENTIAL, PACKAGE, AND SELF-HOST PROOFS
  package.json         PACKAGE EXPORT, COMMAND, DEPENDENCIES, AND TEST LANES
```

The package uses JavaScript ESM and requires Node 20 or later. Debug80 Runtime
and Z80 Tool Services are pinned standalone dependencies, bundled in the
published package. AZM is not a dependency. Development verification compares
ATOM output with the checked images and independently captured reference data.

## Native source layout

`native/atom.asm` is the linked-core entry. Its five ordered parts contain
the native modules in dependency order:

```text
encoder
symbols and pending references
tokenizer
expression evaluator
patch locator
operand parser
output
statements and directives
multipart driver
host sink stubs
```

The order is both a link order and a useful reading order. The encoder and
symbols establish records used by later modules. The tokenizer and expression
evaluator feed the parser. The output layer connects parsed instructions and
pending records to the sink. The statement layer drives individual source
lines, and the driver controls the complete multipart generation.

Every subsystem proof executes the checked core with controlled guards, entry
points, and caller-owned state. Atom retains no second native implementation or
standalone subsystem link.

## Measured native account

The current pinned native image divides into these measured ranges:

| Native module | Code and immutable bytes | Fixed workspace bytes |
| --- | ---: | ---: |
| Encoder, validation, recognition, and tables | 3,132 | 6 |
| Symbols and pending references | 732 | 20 |
| Tokenizer and source-service fallback | 1,376 | 286 |
| Expression evaluator | 1,877 | 263 |
| Patch-field locator | 67 | 0 |
| Operand parser | 2,048 | 92 |
| Output and patch submission | 467 | 14 |
| Statements and directives | 1,358 | 24 |
| Multipart driver | 617 | 9 |
| Fail-closed host sink stubs | 8 | 0 |
| **Total** | **11,682** | **714** |

The linked resident extent is measured at 12,396 bytes, leaving 3,988 bytes
below a 16 KiB boundary. Host-backed source occupies no Z80 source page;
caller-owned symbol, pending, descriptor, and stack storage remain separate
accounts. The values above come from
`assets/native-core.json` and the workspace symbols used by
`test/measure-host-native.mjs`.

## Host source layout

The host implementation is divided by responsibility:

1. `@jhlagado/z80-tool-services/source-preparation` provides the shared
   language-neutral source reader, dependency resolver, placement join, and
   provenance records.
2. `src/host/atom/` implements Atom preprocessing, numeric syntax, and
   host-backed `INCBIN` lowering.
3. `src/host/core/` loads and validates the pinned Z80 image.
4. `src/host/harness/` executes that image or adapts its compact callbacks to
   the named-object service.
5. `src/host/providers/` implements the Node and named-object service
   providers below those harnesses.
6. `src/host/application/` composes Atom preparation and execution into the
   public assembly entry.
7. `src/host/artifacts/` materializes and publishes NOBJ, binary, HEX, listing,
   and D8 output.
8. `src/host/self-host/` and `src/host/translation/` support the independent
   self-host and AZM comparison paths.

`src/host/application/assemble-atom-project.mjs` composes preparation and
execution into the main programmatic entry. `bin/atom.mjs` adds argument
parsing, rendering, and publication.

## Generated and hand-edited files

The implementation under `native/` is hand-edited. Generated descriptions and
the pinned image have explicit rebuild checks:

| Generated file | Generator | Drift check |
| --- | --- | --- |
| `assets/native-core.json` | `scripts/generate-native-core.mjs` using two executable ATOM generations | `npm run verify:native-source` |
| `assets/atom-object-harness.bin` | `scripts/generate-native-object-harness.mjs` using the shared ABI constants and strict contracts | `npm run verify:native-object` |

Native changes belong in `native/*.asm`, followed by
`npm run build:native-core`. Editing `assets/native-core.json` directly only
creates drift that the release gate rejects.

## Reading routes

The best entry point depends on the change:

- For source dependency or conditional behaviour, begin in
  `src/host/application/resolve-atom-project.mjs`, then follow the Atom source profile into
  the shared `source-preparation` resolver.
- For a lexical problem, use `native/atom-symbols.json` to map
  `AtomTokenizerNext` to `TK_NEXT`, locate it under `native/`, and read
  `test/tokenizer.test.mjs` beside it.
- For expressions or forward arithmetic, begin at `AtomExpressionParseDeferred`
  and the pending-reference rules in `docs/symbolic-parser-abi.md`.
- For an instruction form, begin with the operand record in `src/abi.mjs`, then
  follow `AtomParserParse`, `AtomValidateForm`, and `AtomEncode`.
- For labels or capacity, locate the `SY_` entries under `native/` and read the
  relevant arena boundary tests.
- For a directive, begin at the `ST_` implementation of `AtomAssemblePart`.
- For forward patches or output lifecycle, begin at the `OU_` and `DR_`
  implementations under `native/` and `createMemoryAtomSink()`.
- For an artifact issue, begin in `src/host/artifacts/` and the corresponding
  `host-artifacts` or publication tests.
- For the installed command, begin in `bin/atom.mjs` and trace its calls through
  the public host index.
- For a self-host mismatch, begin with the checked native source and core
  generator, then compare the
  pinned-image, first-generation and second-generation checks in
  `test/host-self-host.test.mjs`.

Atom is small enough to follow one behaviour through every boundary. A change
is complete when the source preparation, native ABI, logical output,
user-facing artifact, and corresponding proof represent the same behaviour.
