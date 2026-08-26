# Atom architecture

Atom is a native Z80 assembler inside a host-managed build. On the Mac, Node
provides filesystem and artifact services while Debug80 executes the same Z80
core that is intended for the TEC-1.

```text
entry.asm
   |
   v
host resolver and preprocessor
   |  ordered, equal-length source parts
   v
native Atom core running in Debug80
   |  append-only IMAGE and final-byte PATCH records
   v
host renderers and atomic publisher
   |
   +-- NOBJ  +-- binary  +-- Intel HEX  +-- listing  +-- D8 map
```

Dependency discovery followed by assembly is a two-stage build, not a
two-pass assembler. The native parser advances through the prepared source in
one semantic pass. Token lookahead and token emission may reread bytes through
the source service; there is no second symbol-resolution pass. Forward
references are held in a resident pending list, and their final bytes are
emitted as PATCH records when the symbol becomes known.

## Responsibility boundary

| Host or operating adapter | Native Z80 core |
| --- | --- |
| Filesystem access, path confinement, and `INCBIN` snapshots | Streaming tokenization |
| `%INCLUDE`, `%DEFINE`, and conditional masking | Case-insensitive symbols and private scope |
| Dependency graph, ordering, and SP1 plan | Expression parsing and validation |
| Loading each ordered source part | Labels, equates, data, placement, alignment, and string directives |
| NOBJ storage and output sink implementation | Complete Z80 instruction encoding |
| Binary, HEX, listing, and D8 rendering | Forward-reference and patch decisions |
| Atomic artifact publication | Final undefined-symbol check and lifecycle control |

This boundary follows Nucleus: language processing remains deterministic and
filesystem-free on the Z80, while the operating layer supplies ordered bytes
and durable output services. The common host resolver is currently maintained
inside Atom and has a clean extraction seam for a later Debug80 package.

## Source preparation

The resolver canonicalizes project-relative paths, confines physical reads to
the project root, detects diamonds and cycles, and emits dependencies before
their importer in deterministic depth-first postorder. Every selected file is
a distinct source part. Atom preprocessing produces a compiler buffer of the
same byte length as the original buffer, so native offsets map directly back to
the original filename, line, and byte column. The Atom composition layer lowers
an active `INCBIN` line to an equal-length initialized reservation and retains
the snapshotted binary beside that source part. The Mac output bridge
substitutes the binary bytes while the native cursor and labels advance by the
same measured length.

SP1 is the portable, line-oriented source-plan format. It records only ordered
logical paths and bank ordinals. The compiler does not parse SP1; an operating
adapter uses it to load the source descriptors consumed by `AtomAssemble`.

## Native assembly and output

`AtomAssemble` receives a 15-byte build descriptor followed by one five-byte
descriptor per part. It validates every source interval, symbol and pending
arena, ordinal, and target range before opening an output generation. It then
resets state, assembles the ordered parts, performs final undefined-symbol and
private-scope checks, and calls commit. Any failure after begin calls abort
exactly once.

IMAGE bytes are emitted in ascending order. A forward reference initially
emits placeholder IMAGE bytes and later emits a PATCH carrying final bytes,
never a symbol name. The output adapter can therefore append both streams to
sequential storage. `ORG` and uninitialized `DS` remain layout events; the Mac
renderer materializes their gaps only when it creates a flat image.

The current output profile is flat bank zero. Atom NOBJ 0.2 retains NOBJ's
append-only framing, record counts, final-byte patches, and CRC without
claiming Nucleus-specific runtime-map fields.

## Mac execution

The npm package contains the pinned native core and the Debug80 runtime. AZM is
used only in development to regenerate the image and to provide the independent
oracle. The package loader checks the core digest and structural coverage before
execution. Debug80 marks native code read-only and intercepts the source-read
entry plus six fail-closed sink entry points. Those compact entries reach the
private Atom provider dispatch. Only this direct-host profile uses that route;
it does not intercept arbitrary Z80 calls or memory.

For `INCBIN`, the bridge replaces only IMAGE bytes attributed to the lowered
source line. It checks that the native byte count and snapshotted binary length
match before commit. Any mismatch aborts the tentative generation.

Prepared source remains in immutable JavaScript snapshots. The tokenizer calls
`AtomSourceReadByte` with a part ordinal and 16-bit logical offset; the Mac
runner returns one byte without copying the part into emulated Z80 memory. The
native driver remains unaware of the filesystem and processes only ordered
descriptors.

The publisher writes a content-addressed immutable generation, synchronizes it,
then changes `current` with one atomic rename. A failed build or publication
does not select a partial artifact set.

## CP/M execution

The native CP/M build relocates the same Atom core to `$0110` behind a
sixteen-byte transient-program header. Its adapter scans source files through
BDOS to establish their logical lengths, then supplies `AtomSourceReadByte`
through a 128-byte random-record cache. It retains the flat image in TPA for
direct patching and writes a temporary COM only after native commit. No
Debug80 hook intercepts BDOS calls. A shared adapter wrapper preserves IX and
IY around the public `$0005` entry because CP/M standardizes only the 8080
register set.

With no arguments, this profile reads `INPUT.ASM` and writes `OUTPUT.COM`.
`ATOM SOURCE OUTPUT.COM` selects another pair of current-drive 8.3 names. The
same command followed by `@` treats `SOURCE` as a plain source plan containing
one CP/M 8.3 name per line. The adapter validates the command tail, reserves
the output's temporary and backup names, and preflights every listed source
before native assembly begins. It derives the ordinary five-byte source
descriptors and reparses the plan as the native driver advances through up to
255 parts. Each part retains the 65,535-byte ABI boundary and exact diagnostic
ordinal and offset.

The CP/M plan contains an order, not a dependency graph. It has no SP1 header,
path hierarchy, bank field, preprocessing, or host codec. The output limit
remains 18,304 bytes under the target map. The [Native Atom on CP/M 2.2
report](cpm22.md) contains the measured map, representation comparison, and
output-path comparison.

## Self-hosting

The authoritative Atom-syntax representation is checked under `native/`.
Collision-checked semantic names and their former long ABI names are recorded
in `native/atom-symbols.json`. The proof runs three complete builds: the pinned
image assembles the `.asm` source, the resulting Atom image assembles it again,
and the same prepared `.asm` parts are translated for an independent strict-AZM
build.
All initialized addresses and all 12,396 resident bytes must agree.

`npm run build:native-core` starts from `native/atom.asm`. Every subsystem proof
calls the checked core, and the repository contains no second native
implementation. [The self-hosting design](self-hosting.md) records the authority
and equivalence checks.
