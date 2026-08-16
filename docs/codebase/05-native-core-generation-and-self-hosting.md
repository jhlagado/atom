# Chapter 5 — Native core generation and self-hosting

[← Host execution, artifacts, and interfaces](04-host-execution-artifacts-and-interfaces.md) | [Verification and maintenance →](06-verification-and-maintenance.md)

Atom keeps one readable Z80 implementation and derives two checked products
from it: the pinned native image used by the Mac package and an Atom-syntax
source form that the native assembler can assemble. The generators are part of
the correctness boundary because the readable source uses AZM facilities that
Atom deliberately omits.

The self-host proof compares complete initialized-address sets and resident
bytes across AZM and two Atom generations. It does not rely on two
hand-maintained assembler implementations.

## Readable source and link entry

The native implementation is maintained under `asm/`. Its link entry is
`atom-host-runtime.asm`, which:

- sets origin zero;
- enables the completed subsystem modes;
- includes the nine native modules in link order;
- defines six fail-closed host sink stubs; and
- ends the AZM translation unit.

The readable files use AZM's `.include`, `.if`, `.equ`, `.org`, `.db`, `.dw`,
`.ds`, `.routine`, `.expectout`, and `.end` forms. `.routine` and `.expectout`
are proof annotations. They affect AZM's register-contract analysis and emit no
native byte.

Atom source uses bare assembler directives, has no native include mechanism,
and limits symbols to eight significant characters. The self-host generator
therefore performs deterministic mechanical rewrites rather than requiring the
readable implementation to use the smallest source representation.

## Building the pinned core

`scripts/generate-native-core.mjs` calls AZM's programmatic compile API on
`asm/atom-host-runtime.asm` with HEX, D8 symbols, and strict register contracts
enabled.

Generation fails when AZM reports any error. On success, the script extracts:

- Intel HEX text;
- every address or value in the D8 symbol table;
- a SHA-256 of the HEX text; and
- a second SHA-256 covering the HEX and the sorted symbol map.

The rendered object becomes `assets/native-core.json`. The checked asset is
part of the npm package and is the image loaded by `loadNativeAtomCore()`.

The normal commands are:

```sh
npm run build:native-core
npm run verify:native-core
```

The first command rewrites the asset. The second assembles the source afresh
and compares the complete rendered JSON with the checked file. The release gate
uses the check form so an unreviewed generated diff cannot be hidden by a test
that consumes stale bytes.

## Building Atom-valid source

`buildSelfHostSource()` in `src/host/self-host/build-self-host-source.mjs`
starts from the same link entry. It recursively reads the AZM include closure
inside the `asm/` root and performs these transformations:

1. remove ordinary comments and blank lines;
2. evaluate the fixed link-time `.if`, `.else`, and `.endif` conditions;
3. flatten every `.include` exactly once at its source position;
4. preserve `.routine` and `.expectout` as `;@` proof comments and remove `.end`;
5. omit link-configuration equates already fixed by the generator;
6. convert AZM dotted directives to Atom's bare `EQU`, `ORG`, `DB`, `DW`, and
   `DS` forms;
7. convert one-byte AZM quoted literals to explicit numeric bytes where needed;
8. assign every declared global and private symbol a unique short Atom name;
9. rewrite exact identifier occurrences outside strings and numeric literals;
   and
10. split the result at line boundaries into source parts no larger than the
    selected page budget.

Global names use a two-letter module prefix and a semantic stem, such as
`PR_PARSE` and `TK_RESET`. Private names use a dot plus a semantic stem and may
be reused under different global labels. Allocation is case-insensitive and
adds a deterministic base-36 suffix only when two stems collide in one scope.
The mapping records the readable original, exact short name, module, privacy,
and private scope. It never resolves a collision by silent truncation.

The default maximum generated part size is 20 KiB, below the 24 KiB native
source-page limit. The current source produces five generated content parts.
`scripts/generate-self-host-source.mjs` also writes a sixth entry part:

```asm
%INCLUDE "ATOM-00.ATM"
%INCLUDE "ATOM-01.ATM"
%INCLUDE "ATOM-02.ATM"
%INCLUDE "ATOM-03.ATM"
%INCLUDE "ATOM-04.ATM"
```

The host resolver orders those dependencies before `atom.atm`, so the checked
self-host project presented to the native driver has six parts. The empty
entry still has its own identity and descriptor.

`native/atom-symbols.json` retains generator statistics and the complete
original-to-short symbol map. It lets the proof recover the original ABI symbol
names from the generated assembly's declarations.

The generated source is managed by:

```sh
npm run build:self-host-source
npm run verify:self-host-source
```

During this migration checkpoint, changes belong in `asm/` or the generator.
The checked files under `native/` are the permanent Atom representation but are
not yet the editing authority. See `docs/self-hosting.md` for the authority
flip and removal sequence.

## First Atom generation

The self-host proof resolves `native/atom.atm` through the ordinary host
source packager and calls `assembleResolvedAtomProject()` with origin zero and
a 16 KiB target.

The pinned AZM-built native core assembles all six parts. The resulting
generation contains IMAGE and PATCH operations, symbol declarations, layout
events, execution measurements, and a complete 12,499-byte materialized image.

The proof compares that image with the memory initialized by the pinned core's
Intel HEX through `AtomHostResidentEnd`. Equality establishes that native Atom
reproduces the code, immutable tables, fixed workspace image, and sink stubs
built independently by AZM.

## Recovering a runnable self-hosted core

`createSelfHostedAtomCore()` accepts the source generator's symbol mapping and
the first Atom generation. It selects declarations whose short names correspond
to generated global symbols, maps them back to original names, and requires all
entry and range symbols needed by the runner.

The helper reconstructs the ten immutable code ranges, materializes the first
generation, writes it as Intel HEX, and returns the same structural core shape
accepted by `assembleResolvedAtomProject({ nativeCore })`.

It also checks that:

- every required generated global has exactly one value;
- every code start and end is present and ordered;
- the materialized image begins at zero; and
- its end equals `AtomHostResidentEnd`.

The native runner then repeats its full replacement-core validation before
execution.

## Second Atom generation

The first-generation core assembles the same checked source again. The proof
compares the second materialized image with the first and compares the complete
execution record as well.

This step proves that the bytes emitted by Atom are themselves executable as
the assembler core and reproduce the same result. It catches errors that a
simple byte comparison with the pinned image could miss if, for example, the
wrong symbol map or entry address were attached to otherwise equal bytes.

## Independent AZM translation

`translateResolvedAtomProjectToAzm()` supplies a separate oracle path. It joins
the already prepared Atom parts into one temporary AZM source while preserving
part markers and performs the syntax rewrites needed by AZM:

- bare Atom directives become dotted AZM directives;
- both accepted `EQU` shapes become AZM equates;
- `LOW()` becomes `LSB()`;
- `HIGH()` becomes `MSB()`; and
- one terminal `.end` is appended.

The translator respects quoted text and semicolon comments while rewriting.
It operates on `compilerBytes`, so host directives have already been masked and
`INCBIN` has already been lowered.

AZM assembles the translated source with case-insensitive symbols. The proof
compares both:

- the exact initialized address set; and
- every resident byte through the Atom image extent.

The address-set comparison distinguishes initialized zero bytes from
uninitialized reservations. A flat byte comparison alone could treat both as
the same fill value.

## Current measured self-host build

The checked measurement records:

| Observation | Measured value |
| --- | ---: |
| Readable input files | 13 |
| Flattened native statements | 7,290 |
| Generated content parts | 5 |
| Checked resolver parts, including entry | 6 |
| Checked source bytes | 102,331 |
| Generated global symbols | 861 |
| Generated private symbols | 422 |
| Initialized resident bytes | 12,126 |
| Reserved resident bytes | 373 |
| Forward PATCH records | 2,008 |
| Declared symbols | 1,283 |
| Linked resident extent | 12,499 bytes |

The first generation currently executes 98,912,641 instructions and
1,056,608,830 T-states. Those values are measurements pinned by the self-host
proof, not generic performance limits.

## Authority of each comparison

The self-host lane has three distinct authorities:

| Comparison | Faults it can expose |
| --- | --- |
| First Atom image versus pinned AZM image | Native parsing, symbols, encoding, directives, placement, patches, or output differ from the development build |
| Second Atom generation versus first | Atom-emitted core, recovered symbols, ranges, or entry cannot reproduce the assembler |
| Translated Atom source versus AZM | Atom and AZM disagree on initialized addresses or resident bytes for the exact self-host source |

All three are required. Passing one does not imply the others.

## Package self-host command

The installed command exposes the first-generation build as:

```sh
atom --self-host
```

It resolves the checked source shipped in the package, assembles it with the
shipped native core, and publishes `atom.bin` beside the other artifacts. The
package test installs a packed archive offline in an unrelated directory,
verifies that AZM is absent, runs this command, and compares the binary with the
installed pinned core.

This installed-path proof checks packaging as well as self-assembly: required
source parts, native asset, bundled Debug80 Runtime, package exports, and CLI
paths must all survive the npm archive.
