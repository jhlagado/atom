# Atom Phase 6 self-hosting report

## Result

**Measured: pass.** The checked Atom-syntax source under `self-host/` assembles
to the same 13,103-byte resident image as the AZM build. That Atom-produced
image then runs as the assembler and produces the same bytes again. A separate
translation of the checked source into AZM syntax also produces the same
image.

The native size did not grow in this phase. Code and immutable tables remain
**Measured: 12,553 bytes**. The linked resident image, including 550 bytes of
fixed workspace, is **Measured: 13,103 bytes**, leaving **Measured: 3,281
bytes** in the 16 KiB bank.

## Source representation

The maintained implementation remains the readable AZM source in `asm/`.
`npm run build:self-host-source` generates the checked Atom source. The
project design assigns these mechanical changes to the host:

- flatten the AZM include closure in deterministic order;
- select the configured `.if` branches;
- remove AZM proof annotations and comments;
- convert dotted directives and character constants to Atom syntax;
- replace source identifiers with exact case-insensitive names that fit Atom's
  eight-significant-character symbol format; and
- split the stream into source parts that fit the 24 KiB input window.

The generated form contains **Measured: 7,151 statements** from **Measured: 13
input files**. Its five code-bearing parts occupy **Measured: 94,088 bytes**.
The checked `%include` entry adds one small masked part, for **Measured: 94,261
bytes across six parts** at the native boundary. The symbol map records
**Measured: 814 global names and 405 private names**. Atom itself performs no
renaming and still diagnoses an overlength source name.

`npm run verify:self-host-source` regenerates the representation in memory and
fails if any checked file differs. The npm package includes the generated
source, so an installed command can assemble it without the development AZM
dependency.

The generated source increases host package storage only and consumes no
additional Z80 resident bytes. The non-packaged Phase 6 proof artifact records
the exact unpacked-byte and entry census. Compressed archive size is an
observation of the checkpoint npm toolchain rather than a release invariant.

## Byte-identity proof

The proof compares three complete builds:

1. The pinned AZM-built core runs Atom over the checked Atom source.
2. The first Atom-produced image runs the same checked source again.
3. The host translates the checked Atom source into AZM syntax and invokes AZM
   in case-insensitive mode.

All three produce **Measured: 13,103 identical bytes**, comprising **Measured:
12,727 initialized bytes and 376 reserved bytes**. The native stream applies
**Measured: 2,132 PATCH records** and reports **Measured: 1,219 declarations**.
The proof compares the whole resident extent, not a digest or a selected set of
instructions.

Both native generations execute **Measured: 149,600,757 Z80 instructions and
1,367,047,684 T-states**, with **Measured: 14,861 host service calls**. At 4
MHz, the native instruction count corresponds to **Projected: at least 341.8
seconds**, before filesystem and output-service time. The Mac proof completes
much faster because Debug80 runs the Z80 model on the host processor.

## Source paging boundary

The Mac adapter retains one 24 KiB source window and copies each ordered part
into that window before `AtomTokenizerReset`. Debug80 marks the complete source
window read-only to CPU writes. Full-window comparisons, including the `$A5`
padding after each part, run before replacement and after the final return;
direct host writes install the next page. The native driver still consumes
ordered source descriptors and has no filesystem code.

This proves the assembler and its source representation. It does not yet
provide the TEC-1 operating adapter that reads each source part from storage.
That adapter belongs to the next deployment phase.

The complete battery passes **Measured: 241 of 241 tests**. AZM's strict
register-contract check also passes for the linked native image.

## Reproduction

```sh
npm run verify:self-host-source
npm run verify:native-core
npm test
npm run measure:self-host
atom --self-host
```
