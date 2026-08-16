# Atom Phase 11 host-backed binary inclusion

The Mac command now accepts `INCBIN "PATH"` as a whole-file binary inclusion.
The path is relative to the containing source file and passes through the same
project-root, symlink, exact-case, and snapshot checks used for source input.

## Architecture

Filesystem work remains outside the Z80 assembler. The Atom composition layer
replaces an active `INCBIN` line with an equal-length initialized `DS` line and
retains the binary snapshot with that source part. Native assembly therefore
calculates labels, branches, output capacity, and the final cursor from the
exact binary length.

The Mac output bridge substitutes the snapshot during IMAGE calls attributed
to that line. It compares the number of native IMAGE bytes with the snapshot
length before commit. Too many or too few bytes abort the tentative generation.
The existing six-call sink ABI and NOBJ IMAGE format remain unchanged.

Listings retain the original `INCBIN` source. D8 records its half-open output
range as high-confidence data attached to the original file and line. The
binary path does not become an anonymous Atom source part.

## Limits and measured cost

The current spelling includes one complete file and accepts no offset or
length operands. A file may contain Measured 0 through 65,535 bytes, bounded by
the native 16-bit target capacity. Inactive conditional source causes no binary
read.

This checkpoint changes host code only. Native code growth is Measured 0 bytes:

| Item | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 11,968 |
| Fixed workspace | Measured | 531 |
| Linked resident extent | Measured | 12,499 |
| Physical margin below 16 KiB | Measured | 3,885 |

The bridge still receives one IMAGE call per included byte because lowering
uses the native initialized `DS` path. This costs execution time but no resident
Z80 code or workspace.

## Proof

The focused proof covers exact binary bytes, labels and a forward branch across
the binary, filesystem mutation after snapshot, root escape, missing input,
malformed syntax, the 65,535-byte boundary, inactive conditional source,
listing text, D8 range classification, and injected bridge-count disagreement.

`INCBIN` itself changes no native instruction. The current compressed-core
proof covers Measured 12,499 resident bytes and Measured 12,126 initialized
addresses, and byte identity across the pinned core, translated AZM build, and
two Atom generations.

The Atom-local suite passes Measured 266 of 266 tests. Package-census values are
stored outside the archive in `proofs/phase-11.json` and
`proofs/package-census.json` to avoid a self-referential packaged size field.
