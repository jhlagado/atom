# Chapter 1 — Orientation and repository layout

[Manual](index.md) | [Host source preparation →](02-host-source-preparation.md)

Atom is a single-pass Z80 assembler whose authoritative assembler core is
written in Z80 assembly. The installed Mac command runs that core through
Debug80. Node supplies services that do not belong in the resident assembler:
filesystem access, conditional preprocessing, dependency discovery, binary
input, artifact rendering, and durable publication.

That split produces one build path with two execution domains:

```text
PROJECT ENTRY (.ATM)
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
CONTENT-ADDRESSED ARTIFACT BUNDLE
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
| Orders source parts and writes SP1 plans | Manages global and private symbol scope |
| Implements the output sink | Decides when IMAGE and PATCH operations occur |
| Renders NOBJ, BIN, HEX, listing, and D8 | Performs final undefined-symbol checks |
| Publishes a complete artifact generation | Begins, commits, or aborts one output generation |

The same native core can run behind a Mac adapter or a future TEC-1 operating
adapter. Native code contains no path, filesystem, dependency-graph, Intel HEX,
listing, or D8 logic.

## A small build from end to end

Consider an entry file with one dependency and one forward reference:

```asm
%INCLUDE "LIB/DEVICE.ATM"

ORG 4000H
START:
    LD A,DEVICEID
    JR .DONE
    DB 0
.DONE:
    DW START
```

The host resolves `LIB/DEVICE.ATM` relative to the importer and emits the
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
  asm/                 HANDWRITTEN Z80 CORE AND DIRECT PROOF IMAGES
  assets/              PINNED GENERATED NATIVE CORE
  bin/                 INSTALLED COMMAND-LINE ENTRY
  docs/                PRODUCT, ABI, PHASE, AND ENGINEERING DOCUMENTATION
  examples/            SHIPPED SOURCE PROJECTS
  proofs/              FROZEN CENSUSES, MEMORY MAPS, AND MEASUREMENTS
  scripts/             GENERATORS AND RELEASE CHECKS
  native/              CHECKED ATOM-SYNTAX FORM OF THE NATIVE CORE
  src/                 HOST IMPLEMENTATION AND GENERATED-TABLE INPUTS
  test/                NATIVE, HOST, DIFFERENTIAL, PACKAGE, AND SELF-HOST PROOFS
  package.json         PACKAGE EXPORT, COMMAND, DEPENDENCIES, AND TEST LANES
```

The package uses JavaScript ESM and requires Node 20 or later. AZM and Debug80
Runtime are local development dependencies. The published package bundles
Debug80 Runtime but omits AZM; AZM remains the independent development oracle
used to build and verify the pinned native image.

## Native source layout

`asm/atom-host-runtime.asm` is the linked Mac-host image. It selects the full
configuration and includes the native modules in dependency order:

```text
atom-encoder.asm
atom-symbols.asm
atom-tokenizer.asm
atom-expression.asm
atom-patch.asm
atom-parser.asm
atom-output.asm
atom-statements.asm
atom-driver.asm
host sink stubs
```

The order is both a link order and a useful reading order. The encoder and
symbols establish records used by later modules. The tokenizer and expression
evaluator feed the parser. The output layer connects parsed instructions and
pending records to the sink. The statement layer drives individual source
lines, and the driver controls the complete multipart generation.

The direct proof files such as `encoder-proof.asm`, `symbol-proof.asm`, and
`driver-proof.asm` link smaller configurations around one subsystem. They are
not alternative implementations. Each proof supplies a controlled memory map,
entry point, guards, and adapter state for direct runtime tests.

## Measured native account

The current pinned strict-contract image divides into these measured ranges:

| Native module | Code and immutable bytes | Fixed workspace bytes |
| --- | ---: | ---: |
| Encoder, validation, recognition, and tables | 3,348 | 6 |
| Symbols and pending references | 730 | 22 |
| Tokenizer | 1,360 | 30 |
| Expression evaluator | 1,922 | 297 |
| Patch-field locator | 67 | 0 |
| Operand parser | 2,067 | 98 |
| Output and patch submission | 467 | 22 |
| Statements and directives | 1,370 | 47 |
| Multipart driver | 619 | 9 |
| Fail-closed host sink stubs | 18 | 0 |
| **Total** | **11,968** | **531** |

The linked resident extent is measured at 12,499 bytes, leaving 3,885 bytes
below a 16 KiB boundary. Caller-owned source, symbol, pending, descriptor, and
stack storage are separate accounts. The values above come from
`assets/native-core.json` and the workspace symbols used by
`test/measure-host-native.mjs`.

## Host source layout

The host implementation has five main responsibilities:

1. `src/host/source-packager/` provides the language-neutral source reader,
   dependency resolver, placement join, provenance records, and SP1 format.
2. `src/host/atom/` implements Atom preprocessing, numeric syntax, and
   host-backed `INCBIN` lowering.
3. `native-atom-core.mjs` and `native-atom-runner.mjs` load and execute the
   pinned Z80 image through Debug80 Runtime.
4. `src/host/artifacts/` materializes and publishes NOBJ, binary, HEX, listing,
   and D8 output.
5. `src/host/self-host/` and `src/host/translation/` support the independent
   self-host and AZM comparison paths.

`assemble-atom-project.mjs` composes the first three responsibilities into the
main programmatic entry. `bin/atom.mjs` adds argument parsing, rendering, and
publication.

## Generated and hand-edited files

The readable implementation under `asm/` is hand-edited. Several checked files
are generated from it or from shared JavaScript descriptions:

| Generated file | Generator | Drift check |
| --- | --- | --- |
| `asm/atom-mnemonics.inc` | `src/generate-mnemonics.mjs` | `npm run generate` followed by the worktree diff |
| `asm/atom-operands.inc` | `src/generate-mnemonics.mjs` | `npm run generate` followed by the worktree diff |
| `assets/native-core.json` | `scripts/generate-native-core.mjs` using strict AZM | `npm run verify:native-core` |
| `native/atom-00.atm` through `atom-04.atm` | `scripts/generate-self-host-source.mjs` | `npm run verify:self-host-source` |
| `native/atom.atm` and `atom-symbols.json` | `scripts/generate-self-host-source.mjs` | `npm run verify:self-host-source` |

Changes belong in the generator or readable source, followed by regeneration.
Editing a generated file directly only creates drift that the release gate will
reject.

## Reading routes

The best entry point depends on the change:

- For source dependency or conditional behaviour, begin in
  `resolve-atom-project.mjs`, then follow the Atom source profile into
  `source-packager/resolver.mjs`.
- For a lexical problem, begin at `AtomTokenizerNext` in
  `asm/atom-tokenizer.asm` and read `test/tokenizer.test.mjs` beside it.
- For expressions or forward arithmetic, begin at `AtomExpressionParseDeferred`
  and the pending-reference rules in `docs/symbolic-parser-abi.md`.
- For an instruction form, begin with the operand record in `src/abi.mjs`, then
  follow `AtomParserParse`, `AtomValidateForm`, and `AtomEncode`.
- For labels or capacity, begin in `asm/atom-symbols.asm` and the relevant
  arena boundary tests.
- For a directive, begin in `AtomAssemblePart` and
  `asm/atom-statements.asm`.
- For forward patches or output lifecycle, begin in `asm/atom-output.asm`,
  `asm/atom-driver.asm`, and `createMemoryAtomSink()`.
- For an artifact issue, begin in `src/host/artifacts/` and the corresponding
  `host-artifacts` or publication tests.
- For the installed command, begin in `bin/atom.mjs` and trace its calls through
  the public host index.
- For a self-host mismatch, begin with the source generator, then compare the
  first-generation, second-generation, and translated-AZM checks in
  `test/host-self-host.test.mjs`.

Atom is small enough to follow one behaviour through every boundary. A change
is complete when the source preparation, native ABI, logical output,
user-facing artifact, and corresponding proof represent the same behaviour.
