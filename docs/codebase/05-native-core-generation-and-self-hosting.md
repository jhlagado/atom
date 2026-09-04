# Chapter 5 — Native core generation and self-hosting

[← Host execution, artifacts, and interfaces](04-host-execution-artifacts-and-interfaces.md) | [Verification and maintenance →](06-verification-and-maintenance.md)

Atom keeps one authoritative Z80 implementation in `.asm` and derives the
pinned native image used by the desktop package. Core generation executes two
ATOM generations over the same prepared source and compares their results.

The self-host proof compares complete initialized-address sets and resident
bytes against the pinned image and across two ATOM generations. Recovered host
ABI symbols must also agree. No second assembler runs in this build path.

## Native source and link entry

The native implementation is maintained under `native/`. Its link entry is
`atom.asm`, whose `%INCLUDE` header orders five source parts. Those parts set
origin zero, contain the nine native modules in link order, and finish with six
fail-closed host sink entries.

The source uses Atom's bare directives and eight-character symbols. Comments
beginning with `;@ROUTINE` and `;@EXPECTOUT` retain register-contract metadata.
Atom ignores those comments. They retain ABI documentation; native-core
generation does not perform static register-contract analysis.

## Building the pinned core

`scripts/generate-native-core.mjs` resolves `native/atom.asm`, runs the checked
core over the ordered parts, and recovers the long host ABI names through
`native/atom-symbols.json`. The newly emitted core then assembles the same
prepared parts again.

Generation fails unless both ATOM generations produce the same initialized
address set, every resident byte and recovered ABI symbol. On success, the
script records:

- Intel HEX text;
- every recovered global ABI address or value;
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

## Relocatable native object harness

`scripts/native-object-harness-builder.mjs` composes the core with the shared
named-object adapter. Its two platform choices are explicit: the link origin
and the gateway implementation that carries requests to the operating
environment. `scripts/generate-native-object-harness.mjs` calls the builder at
origin zero with a fail-closed gateway to produce the checked package asset.

For an immutable-bank profile, the builder also accepts a common-RAM workspace
origin. The TEC proof places 12,770 bytes of code and tables at
`$8000..$B1E1`, and 741 bytes of fixed state at `$1800..$1AE4`. It then executes
a complete multipart assembly through independent source and output providers
with the bank marked read-only. This is a link-time layout choice, not a runtime
relocation table.

The gateway binding, 399-byte service workspace, symbol arena, pending arena,
descriptors, source-name table, and stack remain platform-owned parts of the
final memory map. A launcher must initialize the fixed-state image in common
RAM before entering the assembler.

## Native source ledger

The five content parts remain below the 65,535-byte per-part logical-offset
limit. The sixth file is the entry and dependency header:

```asm
%INCLUDE "atom-00.asm"
%INCLUDE "atom-01.asm"
%INCLUDE "atom-02.asm"
%INCLUDE "atom-03.asm"
%INCLUDE "atom-04.asm"
```

The host resolver orders those dependencies before `atom.asm`, so the checked
self-host project presented to the native driver has six parts. The empty
entry still has its own identity and descriptor.

`native/atom-symbols.json` records the complete original-to-short migration and
the fixed names required by the host runner. It lets core generation recover
long ABI names from the declarations emitted by native Atom. Global names use
a two-letter module prefix and a semantic stem, such as `PR_PARSE` and
`TK_RESET`. Private names use a dot plus a semantic stem and may be reused under
different global labels.

The authoritative source is managed by:

```sh
npm run build:native-core
npm run verify:native-source
```

Changes belong in `native/*.asm`. No bootstrap source generator or second native
implementation remains in the repository.

## First Atom generation

The self-host proof resolves `native/atom.asm` through the ordinary host
project preparation and calls `assembleResolvedAtomProject()` with origin zero and
a 16 KiB target.

The pinned Atom-built native core assembles all six parts. The resulting
generation contains IMAGE and PATCH operations, symbol declarations, layout
events, execution measurements, and a complete 12,396-byte materialized image.

The proof compares that image with the memory initialized by the pinned core's
Intel HEX through `AtomHostResidentEnd`. Equality establishes that native Atom
reproduces the code, immutable tables, fixed workspace image, and sink stubs
checked into the package.

## Recovering a runnable self-hosted core

`createSelfHostedAtomCore()` accepts the checked symbol ledger and
the first Atom generation. It selects declarations whose short names correspond
to ledger globals, maps them back to original names, and requires all
entry and range symbols needed by the runner.

The helper reconstructs the ten immutable code ranges, materializes the first
generation, writes it as Intel HEX, and returns the same structural core shape
accepted by `assembleResolvedAtomProject({ nativeCore })`.

It also checks that:

- every required ledger global has exactly one value;
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

## Retired core comparison

Core generation formerly invoked an AZM translation and strict register check.
That mandatory comparison has been removed after the earlier equivalence
proofs. The source converter remains available, but it is not a bootstrap
dependency. Other historical tests and the object/CP/M builders still require
migration before the entire release gate is ATOM-only.

The two-generation check retains the initialized-address comparison. It
distinguishes initialized zero bytes from uninitialized reservations, which a
flat byte comparison alone would treat as the same fill value. It does not
replace whole-program static register analysis.

## Current measured self-host build

The checked measurement records:

| Observation | Measured value |
| --- | ---: |
| Flattened native statements | 7,166 |
| Native content parts | 5 |
| Checked resolver parts, including entry | 6 |
| Checked source bytes | 101,641 |
| Ledger global symbols | 876 |
| Ledger private symbols | 440 |
| Initialized resident bytes | 11,789 |
| Reserved resident bytes | 607 |
| Forward PATCH records | 1,938 |
| Declared symbols | 1,315 |
| Linked resident extent | 12,396 bytes |

The first generation currently executes 101,840,573 instructions and
1,086,338,471 T-states. Those values are measurements pinned by the self-host
proof, not generic performance limits.

## Authority of each comparison

The self-host lane has three distinct checks:

| Comparison | Faults it can expose |
| --- | --- |
| First ATOM image versus pinned image | Source and checked bytes or initialized address sets have drifted |
| Second ATOM generation versus first | ATOM-emitted core cannot reproduce the assembler's bytes and write coverage |
| Recovered ABI symbols across generations | Entry addresses, ranges or named values differ despite matching bytes |

All three are required. Passing one does not imply the others.

## Package self-host command

The installed command exposes the first-generation build as:

```sh
atom self-host
```

It resolves the checked source shipped in the package, assembles it with the
shipped native core, and publishes `atom.bin` beside the other artifacts. The
package test installs a packed archive offline in an unrelated directory,
verifies that AZM is absent, runs this command, and compares the binary with the
installed pinned core.

This installed-path proof checks packaging as well as self-assembly: required
source parts, native asset, bundled Debug80 Runtime, package exports, and CLI
paths must all survive the npm archive.
