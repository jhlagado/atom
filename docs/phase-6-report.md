# Atom Phase 6 self-hosting report

## Result

**Measured: pass.** The checked Atom-syntax source under `native/` assembles
to the same 12,101-byte resident image as the AZM build. That Atom-produced
image then runs as the assembler and produces the same bytes again. A separate
translation of the checked source into AZM syntax also produces the same
image.

The current native account is **Measured: 11,648 bytes** of code and immutable
tables. The linked resident image, including 453 bytes of fixed workspace, is
**Measured: 12,101 bytes**, leaving **Measured: 4,283
bytes** in the 16 KiB bank.

## Source representation

The checked `.asm` files are now the implementation authority. They contain
collision-checked semantic names that fit Atom's eight-significant-character
format and retain AZM proof annotations as `;@` comments. They are the only
native implementation retained in the repository.

The source contains **Measured: 7,153 statements**. Its five code-bearing parts
occupy **Measured: 101,177 bytes**. The checked `%INCLUDE` entry adds one small
masked part, for **Measured: 101,326
bytes across six parts** at the native boundary. The symbol map records
**Measured: 872 global names and 440 private names**. Atom itself performs no
renaming and still diagnoses an overlength source name.

`npm run verify:native-source` assembles these parts with Atom, translates the
same prepared bytes to AZM, applies strict register contracts, and compares the
initialized address set and complete resident image. The npm package includes
the authoritative source, so an installed command can assemble it without the
development AZM dependency.

The native source increases host package storage only and consumes no
additional Z80 resident bytes. The non-packaged Phase 6 proof artifact records
the exact unpacked-byte and entry census. Compressed archive size is an
observation of the checkpoint npm toolchain rather than a release invariant.

## Byte-identity proof

The proof compares three complete builds:

1. The pinned Atom-built core runs Atom over the checked Atom source.
2. The first Atom-produced image runs the same checked source again.
3. The host translates the checked Atom source into AZM syntax and invokes AZM
   in case-insensitive mode.

All three produce **Measured: 12,101 identical bytes**, comprising **Measured:
11,750 initialized bytes and 351 reserved bytes**. The native stream applies
**Measured: 1,929 PATCH records** and reports **Measured: 1,312 declarations**.
The proof compares the whole resident extent, not a digest or a selected set of
instructions.

Both native generations execute **Measured: 99,498,360 Z80 instructions and
1,060,106,568 T-states**, with **Measured: 13,681 host service calls**. At 4
MHz, the cycle count corresponds to **Projected: at least 265.0
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

The complete battery passes **Measured: 277 of 277 tests**. AZM's strict
register-contract check also passes for the translated `.asm` native image.

## Reproduction

```sh
npm run verify:native-source
npm run verify:native-core
npm test
npm run measure:self-host
atom --self-host
```
