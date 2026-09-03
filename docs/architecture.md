# Atom architecture

This document defines Atom's ownership and lifecycle boundaries. Host products
may integrate the public package, but their repositories do not govern Atom's
language, native core, or build model.

Atom is a native Z80 assembler inside a host-managed build. In the desktop
profile, Node provides filesystem and artifact services while Debug80 executes
the same Z80 core used by native Z80 profiles.

```text
entry.asm
   |
   v
host resolver and preprocessor
   |  ordered, equal-length source parts
   v
native Atom core running in Debug80 Runtime
   |  append-only IMAGE and final-byte PATCH records
   v
host renderers and transactional publisher
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
| Dependency graph and deterministic ordering | Expression parsing and validation |
| Loading each ordered source part | Labels, equates, data, placement, alignment, and string directives |
| NOBJ storage and output sink implementation | Complete Z80 instruction encoding |
| Binary, HEX, listing, and D8 rendering | Forward-reference and patch decisions |
| Transactional output publication | Final undefined-symbol check and lifecycle control |

Language processing remains deterministic and filesystem-free on the Z80,
while the operating layer supplies ordered bytes and durable output services.
The host resolver comes from the shared Z80 tool-services source-preparation
boundary; Atom supplies only its language profile and composition.

## Source preparation

The resolver canonicalizes project-relative paths, confines physical reads to
the project root, detects diamonds and cycles, and emits dependencies before
their importer in deterministic depth-first postorder. Every selected file is
a distinct source part. Atom preprocessing produces a compiler buffer of the
same byte length as the original buffer, so native offsets map directly back to
the original filename, line, and byte column. The Atom composition layer lowers
an active `INCBIN` line to an equal-length initialized reservation and retains
the snapshotted binary beside that source part. The desktop output bridge
substitutes the binary bytes while the native cursor and labels advance by the
same measured length.

The prepared parts carry their logical identities, bank assignments, and
ordinals directly into the host adapter. `AtomAssemble` sees only the source
descriptor array and the byte service; it does not parse project metadata.

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
sequential storage. `ORG` and uninitialized `DS` remain layout events; the
desktop renderer materializes their gaps only when it creates a flat image.

The current output profile is flat bank zero. Atom NOBJ 0.2 retains NOBJ's
append-only framing, record counts, final-byte patches, and CRC without
claiming Nucleus-specific runtime-map fields.

## Desktop execution

The npm package contains the pinned native core and the Debug80 runtime. The
package loader checks the core digest and structural coverage before execution.
Debug80 marks native code read-only and intercepts the source-read
entry plus six fail-closed sink entry points. Those compact entries reach the
private Atom provider dispatch. Only this direct-host profile uses that route;
it does not intercept arbitrary Z80 calls or memory.

For `INCBIN`, the bridge replaces only IMAGE bytes attributed to the lowered
source line. It checks that the native byte count and snapshotted binary length
match before commit. Any mismatch aborts the tentative generation.

Prepared source remains in immutable JavaScript snapshots. The tokenizer calls
`AtomSourceReadByte` with a part ordinal and 16-bit logical offset; the desktop
runner returns one byte without copying the part into emulated Z80 memory. The
native driver remains unaware of the filesystem and processes only ordered
descriptors.

The CLI stages every positively selected output before replacing any target.
If a replacement fails, it restores the preceding files from transaction
backups. The programming API also retains the content-addressed immutable
generation publisher for consumers that want one atomic `current` pointer over
a complete artifact family.

## CP/M execution

The native CP/M build relocates the same Atom core to `$0110` behind a
sixteen-byte transient-program header. Its adapter scans source files through
BDOS to establish their logical lengths, then supplies `AtomSourceReadByte`
through a 128-byte random-record cache. It retains the flat image in TPA for
direct patching and writes a temporary output only after native commit. BIN
and COM use the patched bytes directly; HEX is rendered into 128-byte output
records after all patches have been applied. No
Debug80 hook intercepts BDOS calls. A shared adapter wrapper preserves IX and
IY around the public `$0005` entry because CP/M standardizes only the 8080
register set.

With no arguments, this profile reads `INPUT.ASM` and writes `OUTPUT.COM`.
`ATOM SOURCE` derives `.ASM` and `.COM` names; `ATOM SOURCE OUTPUT` selects
another pair of current-drive 8.3 names. The output suffix may be `.COM`,
`.BIN`, or `.HEX`. The root and its included files use
leading `%INCLUDE` directives with quoted
current-drive 8.3 names. The provider resolves the graph, imports each file
once, rejects cycles, and emits dependencies before importers. It validates the
command tail, reserves the output's temporary and backup names, and preflights
every source before native assembly begins. The resulting ordinary five-byte
descriptors support up to 255 parts. Each part retains the 65,535-byte ABI
boundary and exact diagnostic ordinal and offset.

The native profile has no path hierarchy, bank field, project JSON, conditional
engine, or host codec. The output limit remains 18,304 bytes under the target
map. The [Native Atom on CP/M 2.2 report](cpm22.md) contains the measured map,
resolver rules, and output contract.

## Self-hosting

The authoritative Atom source is checked under `native/`. Collision-checked
semantic names are recorded in `native/atom-symbols.json`. The proof runs two
complete native builds: the checked image assembles the source, then the
resulting Atom image assembles it again. All initialized addresses and all
12,396 resident bytes must agree.

`npm run build:native-core` starts from `native/atom.asm`. Every subsystem proof
calls the checked core, and the repository contains no second native
implementation. [The self-hosting design](self-hosting.md) records the authority
and equivalence checks.
