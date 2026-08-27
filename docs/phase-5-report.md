# Atom Phase 5 Mac CLI and artifact report

## Result

**Measured: pass.** The packed Atom command installs offline on the Mac and
assembles a project without AZM, an Atom source checkout, or a neighbouring
Debug80 checkout. One invocation publishes NOBJ, raw binary, Intel HEX,
listing, D8 map, and artifact metadata as a single selected generation.

The installed package contains a pinned native core and the Debug80 Z80 runtime.
The core loader verifies the committed HEX text with SHA-256 before execution.
AZM remains the development oracle used to regenerate and check that asset.

The npm archive is **Measured: 206,272 bytes compressed and 1,046,940 bytes
unpacked**, with 231 entries. This host-package size is independent of the Z80
resident account.

## Native size

Phase 5 changes only host code and packaged data. The native account is
unchanged from Phase 4.

| Native account | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 12,508 |
| Fixed workspace | Measured | 550 |
| Linked resident extent | Measured | 13,058 |
| Physical margin below 16 KiB | Measured | 3,326 |

The package archive and host files do not consume the Z80 resident bank. The
eventual TEC operating adapter remains outside this measurement.

## Artifact evidence

The renderer proof starts with a forward `JR`, an uninitialized `DS` gap, an
`EQU`, and a later label. It verifies the patched binary, Intel HEX checksum,
listing source lines, label and constant entries in D8, and the NOBJ record
counts and CRC. An empty image also produces a valid Atom object and EOF-only
Intel HEX file.

Two fresh native runs produce byte-identical NOBJ and binary arrays and
identical HEX, listing, and D8 text. Sorting uses code-point order rather than
the host locale.

The D8 JSON uses the Debug80 `d8-debug-map` version 1 schema. It records each
logical source part, source line, generated address range, global or private
scope, and label or constant value. Listings read original unmasked source
bytes while their gutters use final patched bytes. Reused private spellings
receive distinct source-based identities after the native table evicts their
earlier scopes.

## Publication evidence

Artifact sets use content-addressed immutable directories. The publisher
synchronizes every artifact and its metadata file, renames the complete
generation into place, then atomically renames a temporary symlink over `current`. A
fault injected at the pointer rename leaves every path through the previous
`current` generation unchanged. A later successful publication selects all
files from the new generation together.

The publisher verifies an existing generation before reuse. The artifact
metadata records the generation digest and a SHA-256 plus byte count for each
artifact.

## Package evidence

The package proof runs `npm pack`, installs the resulting archive into a fresh
temporary prefix with npm's offline mode, and launches the installed `atom`
binary from an unrelated temporary project. The proof checks that AZM is
absent, the bundled Debug80 runtime is present, all six published files are
readable through `current`, and the emitted binary is exact. A second invalid
source reports `bad.asm:1:1` and publishes no bundle.

## Object-format boundary

Atom's object stream is the flat Atom profile 0.2 described in
[`atom-object-format.md`](atom-object-format.md). It retains NOBJ framing,
IMAGE/PATCH records, final-byte patch semantics, record count, and CRC. Its MAP
does not reuse the Nucleus 0.1 runtime map because arbitrary assembly source
does not declare Nucleus vector, initialized-data, BSS, or stack regions.

## Remaining work

Phase 6 must translate the complete Atom source dialect into AZM source,
compare output bytes automatically, and prove that Atom assembles its own
native source. The first self-assembly attempt will also reveal whether Atom's
current directive and expression subset covers every construct in its checked
source.

## Reproduction

```sh
npm run verify:native-core
npm test
npm run measure:host-native
npm pack
```
