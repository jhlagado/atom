# ASO: ATOM Serialized Operations

Status: design specification / implementation roadmap

ASO is a compact, chronological serialization of the output operations produced by ATOM. It is intended to preserve ATOM's single-pass character on small systems, especially CP/M, without requiring the complete assembled image to coexist in RAM with the assembler.

ASO means **ATOM Serialized Operations**. The conventional filename suffix is `.aso`.

This document deliberately separates two ideas:

1. the ATOM core produces logical output operations (`IMAGE`, `PATCH`, reservation/cursor movement and final metadata); and
2. a host chooses how those operations are consumed.

ASO is one host policy: serialize the operations to a sequential file. It is not the only bounded-memory policy. A CP/M host may instead materialize the same operations directly into a random-access `.COM` file on disk.

## 1. Motivation

The current CP/M implementation materializes the output image in RAM. This is simple and fast, but the assembler and the assembled program compete for the same transient memory. A small-system assembler should not impose that restriction when the output medium itself can hold the image.

Classic CP/M `ASM` avoided this problem by writing Intel HEX and leaving final materialization to `LOAD`. ATOM can retain the same useful separation while remaining single-pass: forward references become later `PATCH` operations rather than requiring a second pass over source.

The design goals are therefore:

- single-pass source processing;
- chronological output;
- bounded working memory;
- no requirement for garbage collection or dynamic allocation;
- no global sorting or regrouping of records;
- no requirement to retain the complete output image;
- straightforward implementation in Z80 assembly, C, Rust, JavaScript or similar languages;
- efficient sequential writing on floppy-based systems;
- efficient materialization either later or directly during assembly.

## 2. Non-goals

ASO v1 is not a relocatable linker object format. It does not provide public/external symbols, sections, libraries, linker relocation expressions or separate compilation.

A `PATCH` is a final correction already computed by ATOM. It carries replacement bytes, not a symbol name or an unresolved relocation expression.

ASO is also not intended to preserve source-level diagnostics. Undefined symbols remain an assembler error; a successful ASO file contains only resolved output operations.

## 3. Fundamental streaming invariant

A conforming ASO writer MUST be implementable without retaining the complete output image and without retaining previously emitted ASO records.

A conforming ASO reader/materializer MUST be implementable with bounded working memory. It MAY use random access to the destination medium when applying patches.

Records MUST preserve the semantic order of ATOM output operations. A writer MUST NOT collect all IMAGE operations and all PATCH operations and then emit them in separate groups.

Local buffering is permitted. In particular, adjacent IMAGE bytes MAY be combined into a single IMAGE record, provided that doing so does not move an IMAGE operation across an intervening PATCH or other semantically significant operation.

This is the principal distinction between ASO and the existing Atom NOBJ 0.2 renderer, whose artifact construction groups IMAGE and PATCH records.

## 4. Conceptual operation stream

A typical assembly may produce:

```text
BEGIN
IMAGE  $0100  3E 01 CA 00 00
IMAGE  $0105  21 00 00
PATCH  $0103  37 01
IMAGE  $0108  ...
PATCH  $0106  52 01
END
```

The stream should be understood as instructions to an output host:

- `IMAGE address, bytes`: establish these bytes in the output image;
- `PATCH address, bytes`: replace bytes at an address established earlier;
- reservations/cursor movement: advance the logical image without necessarily supplying initialized bytes;
- `END`: assembly completed successfully and the stream is complete.

The exact treatment of reservations, holes and fill bytes is part of the v1 binary-format work below.

## 5. Output policies

The ATOM core should not depend on a particular materialization policy. At least three useful host policies exist.

### 5.1 RAM materialization

```text
ATOM -> IMAGE/PATCH -> RAM image -> output file
```

This is the simplest and usually fastest policy. It remains valuable where the complete output comfortably fits alongside ATOM. It should not be removed merely because bounded-memory alternatives exist.

### 5.2 Direct disk materialization

```text
ATOM -> IMAGE/PATCH -> random-access COM file
```

The destination file is the materialized image. IMAGE operations normally extend/write the file sequentially. PATCH operations seek to an earlier destination record and overwrite the affected bytes.

The final file size need not be known in advance. The file grows as the logical high-water mark advances.

For a CP/M `.COM` file loaded at `$0100`, target address `A` maps to file offset:

```text
offset = A - $0100
```

A direct materializer therefore does not require an image-sized RAM allocation. A minimal implementation can operate with approximately one CP/M logical record (128 bytes) plus parser/state storage.

A practical implementation SHOULD use a larger cache when memory permits. A 1K-4K recent-output cache can absorb many short-range forward-reference patches without causing floppy seeks. The cache is an optimization only; correctness MUST NOT depend on its size.

### 5.3 ASO serialization

```text
ATOM -> IMAGE/PATCH -> program.ASO
program.ASO -> LOAD -> program.COM
```

This preserves the operation stream as an artifact. The ASO writer performs sequential output only. A later small materializer replays the stream.

ASO is useful for slow media, staging, transport, debugging and systems where assembly and final materialization should be separate operations. It is not required merely to obtain bounded-memory assembly: direct disk materialization provides that property too.

## 6. Bounded-memory ASO materialization on CP/M

An ASO-to-COM utility can keep the ASO input strictly sequential while treating the COM output as random access.

For IMAGE, it writes the corresponding output bytes. For PATCH, it computes the COM file offset, selects the relevant CP/M random record, reads that record into a small buffer, modifies the affected byte(s), writes the record back and resumes sequential ASO input.

A patch crossing a 128-byte record boundary touches two output records. No complete program image is required in memory.

A one-record cache is sufficient for correctness. Larger caches improve performance by retaining recently written output and reducing physical disk repositioning.

This distinction is important:

```text
ASO input   : sequential access only
COM output  : mostly sequential writes plus occasional random patch writes
```

## 7. ASO v1 binary-format direction

The v1 encoding should be intentionally smaller and less general than NOBJ. The implementation target includes Z80 assembly under CP/M, so every field must justify its cost in code, RAM and file size.

The proposed file identity is:

```text
41 53 4F 01
 A  S  O v1
```

All multi-byte integers are little-endian.

The minimum required semantic record kinds are:

```text
END
IMAGE
PATCH
```

The final numeric encoding of these record kinds and the precise record framing MUST be settled before implementation is declared conforming.

A candidate framing is:

```text
HEADER:  41 53 4F 01
IMAGE:   kind length address data...
PATCH:   kind length address data...
END:     kind
```

However, the implementation should not freeze this framing until the following question has been evaluated: whether sequential IMAGE records need to carry an address at all. If the reader maintains the logical cursor, omitting redundant IMAGE addresses may make both the file and the Z80 decoder smaller. Explicit addresses may instead be desirable for recovery, validation and ORG handling.

The same review must settle:

- representation of `ORG`/cursor changes;
- representation of uninitialized `DS`/reserved regions;
- fill-byte semantics when materializing a flat BIN/COM image;
- maximum IMAGE run length;
- maximum PATCH length (likely naturally small, but the format should not depend on that assumption without saying so);
- whether END carries final cursor/high-water metadata;
- whether v1 needs an integrity check, and whether its implementation cost is justified on CP/M;
- behavior on malformed, truncated or out-of-range records.

These are format decisions, not reasons to abandon the streaming model.

## 8. Ordering rules

The following rules are normative for ASO regardless of the final compact framing:

1. The header occurs first.
2. Output records occur in ATOM host-operation order.
3. A PATCH MUST NOT be moved earlier or later merely to group it with other patches.
4. IMAGE operations MAY be coalesced only across adjacent IMAGE operations whose combination is semantically identical to replaying them separately.
5. A PATCH may target output produced earlier in the stream. ASO v1 need not support a patch to output that has not yet logically been established.
6. END occurs exactly once after successful assembly.
7. A writer MUST NOT emit a successful END while unresolved references remain.

## 9. Relationship to the existing NOBJ profile

The repository currently documents and implements an Atom-specific NOBJ 0.2 flat profile. That format uses the Nucleus-derived record envelope and metadata and emits grouped IMAGE records followed by grouped PATCH records.

ASO should supersede NOBJ as ATOM's small-system streaming artifact rather than simply renaming the existing format. The existing NOBJ implementation may remain during migration for compatibility, but new small-system work should target ASO's chronological bounded-memory model.

Node should not use JavaScript's dynamic-memory facilities as a requirement of artifact generation. A Node ASO writer should follow the same streaming discipline expected of Z80, C and Rust implementations.

## 10. CP/M command-line direction

The exact switch spelling is an implementation decision, but the intended user workflows are:

```text
; convenient materialized output
ATOM FOO.ASM -> FOO.COM

; persistent serialized operations
ATOM FOO.ASM -> FOO.ASO
LOAD FOO.ASO -> FOO.COM
```

The CP/M host should be able to choose RAM materialization or cached direct-disk materialization without changing assembler semantics.

The desktop/Node CLI should ultimately expose `.aso` as an output suffix and should generate it from the chronological operation stream rather than from a globally reorganized artifact model.

## 11. Implementation roadmap

### Phase 1 - freeze ASO v1 framing

Choose the smallest record encoding that correctly represents IMAGE, PATCH, cursor/ORG/reservation behavior and successful completion. Write byte-exact examples and malformed-input cases.

### Phase 2 - Node reference implementation

Implement an ASO writer and parser/materializer. The writer should consume operations chronologically and avoid global sorting/regrouping. Use this as the executable reference for the binary specification.

### Phase 3 - CP/M direct COM materializer

Replace or supplement the image-sized RAM output policy with a disk-backed output policy using CP/M random-record I/O and a bounded cache. Measure 128-byte, 1K, 2K and 4K cache choices against representative assemblies where practical.

### Phase 4 - CP/M ASO writer

Add sequential `.ASO` emission. The writer should require only bounded record buffering.

### Phase 5 - CP/M LOAD utility

Implement a small `LOAD`-style ASO materializer. It should read ASO sequentially and construct a `.COM` using bounded RAM and random access only on the output file.

### Phase 6 - retire or retain NOBJ deliberately

Once ASO covers the required Atom workflows, decide whether `.nobj` remains as a compatibility/export format or is deprecated in favor of `.aso`.

## 12. Acceptance criteria

The architecture is successful when all of the following are true:

- ATOM can assemble an output image larger than the RAM left after ATOM itself is resident, subject to target address-space and filesystem limits rather than an image-sized buffer;
- the CP/M direct materializer uses bounded memory;
- the ASO writer uses bounded memory and sequential output;
- ASO IMAGE and PATCH records retain semantic operation order;
- a small ASO loader can reproduce the same final image as RAM materialization;
- Node, CP/M and any future C/Rust implementation agree on byte-exact ASO test vectors;
- unresolved references prevent successful completion rather than leaking unresolved relocation state into ASO.

## 13. Design principle

ATOM's output abstraction should make the destination policy independent of assembly semantics.

The assembler produces operations. A host may apply them to RAM, apply them to a random-access file, or serialize them as ASO. The most constrained implementation should define the baseline architecture; richer hosts may optimize it, but should not make the format depend on facilities unavailable to small systems.
