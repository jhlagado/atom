# Internal ASO Spool Format

Status: ASO v1 specification and the Node streaming codec are implemented.
CP/M uses this operation stream as a temporary spool while producing COM, BIN
or HEX. It is not a selectable final output. Its bounded reader replays the
spool through 33,280-byte output windows; binary windows are appended as
records and HEX windows are converted by the shared checksum writer. The Node
CLI applies ordered operations directly for BIN/COM/HEX-only builds. Its flat
sink keeps a target-sized byte array and a two-bit-per-address validation map;
at the 65,535-byte Node target limit those typed arrays total 81,919 bytes,
before JavaScript object overhead and the final HEX string. The native CP/M
materialiser and Node flat-image sink now produce matching COM, BIN and HEX
logical outputs for a forward-patched image with a sparse gap.

The shared valid and invalid vectors are in `test/fixtures/aso-v1.json`.
`test/aso-stream.test.mjs` checks the Node codec in
`src/host/artifacts/aso-stream.mjs`, including chunk boundaries, failed writes
and exact optional CP/M padding. CP/M tests compare emitted valid streams
byte-for-byte with that codec, including record boundaries, forward patches,
failure cleanup and the `$10000` endpoint. The CP/M materialiser also checks
the internal spool before publication, including empty streams and IMAGE ends
against the committed high-water mark. Emulator tests do not establish
physical floppy performance.

ASO records the output operations of a successful ATOM assembly in their
original order. A host can apply those operations to RAM or to a random-access
file. The same operation contract applies on Node and CP/M. The CP/M build uses
the serialized stream temporarily because it produces output through bounded
memory windows.

This format is for one flat 16-bit Z80 address space. It is not a relocatable object format. A PATCH contains final replacement bytes, not a symbol name or an expression for a later linker. Source filenames, diagnostics, listings and D8 mappings are outside ASO v1.

## 1. Operation contract

The required ATOM host boundary has four observable stages:

```text
BEGIN(target origin, fill)
IMAGE(address, bytes)       zero or more, in output order
PATCH(address, bytes)       zero or more, interleaved with IMAGE
COMMIT(final cursor, high-water mark)  or ABORT
```

ATOM publishes IMAGE and PATCH during assembly. `ORG` and uninitialised `DS` change the logical cursor but do not publish separate host operations. The native output layer tracks the target interval, current cursor and greatest reached endpoint. At COMMIT, the Z80 ABI passes the descriptor in `IX`, the final cursor in `HL`, remaining capacity in `DE`, and the low word of high water in `BC`. Bits 0 and 1 of `A` distinguish a final cursor or high-water endpoint of `$10000` from address zero. CP/M COM, BIN, HEX and ASO use the `$FF00`-byte target capacity from origin `$0100`.

The explicit geometry contract is now implemented and measured. Both values are mathematical endpoints so `$10000` remains distinct from zero. Hosts do not infer high water from IMAGE, `ORG` or `DS` callbacks and do not equate it with the final cursor. ASO v1 records explicit IMAGE addresses and the final geometry. It does not require `ORG`, `DS` or SEEK records in the file.

The host MUST preserve the order of IMAGE and PATCH calls. For canonical ASO bytes, the writer combines consecutive IMAGE bytes into the longest contiguous run of at most 128 bytes. It flushes the run when it reaches 128 bytes, the next IMAGE address is not contiguous or any other operation occurs. An IMAGE call longer than the remaining run space is split at that boundary. A writer holds at most one pending run. It MUST NOT collect all IMAGE calls and then all PATCH calls.

ABORT produces no successful ASO artifact. An unresolved symbol, range error or failed output service prevents COMMIT and hence prevents the END record. An implementation MUST publish a new artifact only after the whole operation succeeds. Temporary output is removed after failure and an existing destination is preserved.

The operation stream is canonical. The bytes below define the internal spool
encoding. Platform-specific materialisers use the same ordering and final
geometry.

## 2. Address and image rules

All addresses are absolute Z80 addresses. `origin` lies in `0..$FFFF`. A byte can be written at `$FFFF`; the exclusive end of an image may therefore be `$10000`. `finalCursor` and `highWater` are mathematical values in `origin..$10000`, not wrapping 16-bit counters.

The logical flat image covers `[origin, highWater)`. Every byte in that interval not supplied by IMAGE or changed by PATCH has the header's `fill` value. The first byte of a BIN file corresponds to `origin`. A COM materialiser requires `origin = $0100`, so address `A` maps to file offset `A - $0100`. Intel HEX uses the absolute addresses. The temporary spool must be materialised to create a COM file.

IMAGE ranges are nonempty, ascend and do not overlap. Gaps between them are permitted. A PATCH applies to an address below the end of an IMAGE already encountered. It may replace a byte in an intervening fill gap. This slightly wider reader rule avoids an image-sized initialisation bitmap; ATOM's own output path only patches bytes for which it emitted IMAGE. A later PATCH to the same byte replaces the earlier value. A PATCH may not address a future byte.

`highWater` is the maximum of `origin`, every IMAGE end, every reservation end and every `ORG` destination reached during assembly. It can exceed the last IMAGE end. `finalCursor` is the position after the final source statement and may be below `highWater` after a backward `ORG`. Neither value may be below `origin`. No IMAGE may end beyond `highWater`.

For a CP/M BIN or COM file, BDOS stores complete 128-byte records. Bytes after the logical end in the last physical record are padding, not part of the logical image. Exact cross-platform comparisons use `[origin, highWater)`. A materialiser MUST make its own padding policy explicit; it MUST NOT report record padding as assembled bytes.

## 3. ASO v1 bytes

An ASO v1 file has a seven-byte header, zero or more IMAGE and PATCH records and one END record. Multi-byte integers are little-endian. No field has an implicit alignment requirement.

| Item | Bytes | Meaning |
| --- | --- | --- |
| Header | `41 53 4F 01 origin:u16 fill:u8` | ASCII `ASO`, version 1, target origin and gap fill |
| IMAGE | `01 address:u16 length:u8 data:length` | Establish 1..128 consecutive bytes |
| PATCH | `02 address:u16 length:u8 data:length` | Replace 1 or 2 consecutive bytes |
| END | `00 highWater:u24 finalCursor:u24` | Successful completion and final geometry |

An `u24` endpoint has a value in `0..$10000`. Values with a nonzero top byte are valid only when the three bytes are `00 00 01`, meaning exactly `$10000`. IMAGE and PATCH addresses remain `u16` because their first byte cannot be at `$10000`.

Version 1 has no flags, entry-address field, source map, symbol table, record count or checksum. A COM entry is `$0100` by platform convention. Other entry addresses are supplied outside ASO.

Assign a new version byte to any later revision. Decoding v1 MUST reject unknown versions and record kinds. A v1 file contains no checksum, so byte changes can survive parsing when the altered file remains syntactically valid. Adding a checksum requires a new version and a separate measurement of CP/M code and I/O costs.

IMAGE addresses are explicit. Omitting them would require a cursor-change record for gaps and `ORG`, adding another parser state and record kind. The two address bytes keep v1 simple and make output ordering locally checkable. The 128-byte IMAGE maximum bounds the writer's pending run to one CP/M logical record's worth of data, though an unaligned run can cross a physical record boundary. PATCH length is limited to the one- and two-byte corrections ATOM currently publishes.

There is no encoded record for a reservation. Its effect appears in END's `highWater` and in the fill bytes between IMAGE ranges. This preserves the final flat image, not a transcript of every source-level cursor movement.

## 4. Writer and reader rules

A writer MUST:

1. write the header before accepting output records;
2. emit each IMAGE or PATCH in call order using the canonical adjacent-IMAGE rule above;
3. reject an IMAGE outside the 16-bit target, below `origin`, descending or overlapping an earlier IMAGE;
4. reject a PATCH below `origin`, beyond the greatest preceding IMAGE end or across `$10000`;
5. write END only after ATOM reports a successful COMMIT with no unresolved references;
6. check `origin <= finalCursor <= highWater <= $10000` and that `highWater` includes every IMAGE byte;
7. discard a tentative artifact on ABORT or write failure.

A reader MUST perform the same range, ordering and endpoint checks while reading. Two consecutive contiguous IMAGE records are non-canonical unless the first is 128 bytes long; the reader MUST reject them. It MUST also reject a missing END, truncated header or record, zero or excessive length, unknown kind, wrong version, invalid endpoint and malformed post-END padding. It MUST NOT treat physical end-of-file as a successful END.

END terminates the logical ASO stream. The Node codec writes no bytes after it. On a CP/M record-oriented spool, a writer MAY pad the last 128-byte record with `$1A`. A reader accepts either no trailing bytes or exactly the number of `$1A` bytes needed to finish that one record. All other trailing content is invalid. `$1A` inside an IMAGE or PATCH payload is ordinary data because the record length determines its boundary.

An ASO reader need not track which individual earlier bytes came from IMAGE. The bounded rule is that PATCH lies below the greatest preceding IMAGE end. The reader stores that endpoint rather than an output-sized bitmap. A direct materialiser must fill gaps before applying a patch into them.

An ASO writer needs fixed state for the header, one pending IMAGE run, the previous IMAGE end and record I/O. It does not need earlier records or the complete target image. A reader needs fixed record buffers and a small amount of geometry state. The destination medium may be random access for PATCH.

## 5. Byte-exact examples

Spaces and line breaks in these examples separate bytes for reading; they are not part of a file.

### Interleaved patch and later image

```text
41 53 4F 01 00 01 00             header: origin $0100, fill $00
01 00 01 03 3E 00 00             IMAGE $0100: 3E 00 00
02 01 01 01 01                   PATCH $0101: 01
01 05 01 01 C9                   IMAGE $0105: C9
00 06 01 00 06 01 00             END: highWater $0106, cursor $0106
```

The logical BIN bytes are `3E 01 00 00 00 C9`. The two-byte gap before the last IMAGE uses the fill value. Moving PATCH after the later IMAGE would produce the same final bytes here but a different ASO file and would violate operation order.

### Reservation, backward cursor and no IMAGE

```text
41 53 4F 01 00 01 FF             header: origin $0100, fill $FF
00 04 01 00 02 01 00             END: highWater $0104, cursor $0102
```

The logical BIN bytes are `FF FF FF FF`. The final cursor does not shorten the image already reserved.

### PATCH across a CP/M record boundary

```text
41 53 4F 01 00 01 00             header: origin $0100, fill $00
01 7F 01 02 00 00                IMAGE $017F: 00 00
02 7F 01 02 34 12                PATCH $017F: 34 12
00 81 01 00 81 01 00             END: highWater $0181, cursor $0181
```

The logical image contains 129 bytes. Bytes 0..126 are zero, byte 127 is `$34` and byte 128 is `$12`. A CP/M materialiser must update two distinct output records.

### Last address in Z80 memory

```text
41 53 4F 01 FE FF 00             header: origin $FFFE, fill $00
01 FE FF 02 AA BB                IMAGE $FFFE: AA BB
00 00 00 01 00 00 01             END: highWater $10000, cursor $10000
```

The logical BIN bytes are `AA BB`. A 16-bit wrapped END value of zero is invalid.

### PATCH into a filled gap

```text
41 53 4F 01 00 01 FF             header: origin $0100, fill $FF
01 03 01 01 00                   IMAGE $0103: 00
02 01 01 01 55                   PATCH $0101: 55
00 04 01 00 04 01 00             END: highWater $0104, cursor $0104
```

The logical BIN bytes are `FF 55 FF 00`. This is valid ASO even though the current ATOM core would not issue that PATCH. It tests the bounded reader rule independently of the producer.

### Malformed-file vectors

In the table, `H` means the exact seven bytes `41 53 4F 01 00 01 00`. Concatenating `H` and the listed suffix gives the complete file unless the row supplies a complete file directly. The parser rejects each file. It need not use the wording in the last column for a user-facing diagnostic.

| File bytes | Reason |
| --- | --- |
| `41 53 58 01 00 01 00` | Wrong magic |
| `41 53 4F 02 00 01 00` | Unknown version |
| `H` | Missing END |
| `H 03` | Unknown record kind |
| `H 01 00 01 00` | Zero-length IMAGE |
| `H 02 00 01 01 7F` | PATCH before any IMAGE |
| `H 01 00 01 02 AA BB 01 01 01 01 CC` | Overlapping IMAGE |
| `H 01 00 01 01 AA 01 01 01 01 BB` | Non-canonical adjacent IMAGE |
| `H 01 00 01 01 AA 02 00 01 02 12` | Truncated two-byte PATCH |
| `41 53 4F 01 FE FF 00 01 FF FF 02 AA BB` | IMAGE crosses `$10000` |
| `H 01 00 01 01 AA 00 00 01 00 00 01 00` | END below last IMAGE |
| `H 01 00 01 01 AA 00 01 01 00 02 01 00` | Final cursor exceeds high-water mark |
| `H 00 01 00 01 00 01 00` | High-water mark exceeds `$10000` |
| `H 00 00 01 00 00 01 00 00` | Unexpected byte after END |

The last vector has an otherwise valid empty image followed by `$00`. A single `$1A` in that position is also invalid: CP/M padding must complete precisely one 128-byte record and contain only `$1A`.

## 6. Materialisation policies

### Node

The normal Node path should consume the live ordered operation stream. It must
not reconstruct ASO from separate, globally collected IMAGE and PATCH arrays.
A Node materialiser may use RAM for the final image, but it implements the same
geometry and operation rules. RAM is a destination policy, not an alternate
assembly model.

Listings and D8 maps need source-position data that ASO v1 intentionally omits. A host may observe provenance alongside the operation stream for those optional outputs. It must not change ASO ordering or turn source metadata into a dependency of BIN, COM or HEX generation.

### CP/M automatic BIN or COM

The native assembler writes the ordered IMAGE and PATCH operations to an
internal `NAME.BAK` ASO spool. After COMMIT, it creates `NAME.$$$` and replays
the spool once for each output window. Each window is initialised to the ASO
fill byte, then the reader validates and applies all intersecting IMAGE and
PATCH bytes in their original order. The completed window is appended to the
output using sequential BDOS record writes. A PATCH crossing a window boundary
is therefore applied in both passes at its respective byte positions; a PATCH
crossing an ASO physical-record boundary is parsed by the sequential byte
reader. No random output-record operations are used.

The measured window is 33,280 bytes (260 CP/M records). A full `$FF00` logical
COM or BIN image uses two spool scans, followed by 510 sequential output
writes. For a dense full-range ASO stream, the bundled emulator measures 527
spool record writes, 1,054 successful spool reads plus two EOF probes, and 510
output writes. These are logical BDOS operations, not physical floppy seeks or
sector latency. The spool and output temporary file coexist, so free disk
space can limit output even when the address range is valid. Failure removes
both temporaries where possible and preserves the old destination.

COM and BIN use the same flat image bytes, gap fill and `$0100..$10000` target
range; COM adds no file header. CP/M records are 128 bytes and the final record
is padded with zeroes. This padding is not part of the logical ASO image. HEX
uses absolute target addresses and writes its records and EOF marker
sequentially, with CP/M `$1A` padding outside the logical HEX text.

### CP/M spool and replay

The CP/M spool writer appends canonical records to a temporary file using
sequential BDOS record writes. It keeps a 128-byte IMAGE run, one 128-byte
physical-record buffer and a 36-byte FCB, for 292 bytes of fixed writer
buffers. It pads the last physical record with `$1A`, writes END only after
successful COMMIT, and replays the spool only after it has closed
successfully. A failed assembly removes the temporary spool and preserves the
prior destination.

COM, BIN and HEX now use an internal `NAME.BAK` ASO spool and replay it into
`NAME.$$$` before publication. The reader validates the header, records,
geometry, END, padding and physical EOF on every pass. Empty output still gets
a validation pass. A malformed spool or failed disk operation removes the
temporary files where possible and leaves the previous destination in place.
Measured with ATOM and the bundled CP/M emulator, `ATOM.COM` is 21,185 bytes.
It contains the 19,245-byte resident image followed immediately by 1,940 bytes
of spool writer and materialiser code. Writable arenas occupy `$5400` to
`$AD40` but are not part of the COM payload. CP/M stores the payload in 166
records (21,248 bytes); 63 bytes pad the final record. Loaded records end at
`$5400`, where the uninitialised workspace begins.

After successful assembly, the materialiser reuses the dead part-order page
for its FCB and parser state. The source-cache page at `$5500` becomes its HEX
DMA buffer; the replay window begins at `$5580` and ends at `$D780`, for 33,280
bytes (260 CP/M records). That keeps the DMA buffer separate from the ASO
input record and from the output window. The output window overwrites
assembly-only tables and arenas, which are no longer needed after a successful
assembly. Source errors are reported before that handover with their numeric
status and source `filename:line:column`; later storage failures report status
`04` and the selected output filename, without inventing a source location.

BDOS at `$E400` leaves a 58,112-byte transient program area from `$0100`; the
current check rejects a smaller area. A dense `$FF00` image takes two spool
scans, 527 sequential spool writes, 1,054 successful spool reads plus two EOF
probes, and 510 sequential output writes. It makes no random output-record
reads or writes in the emulator. These are logical BDOS operations, not
physical floppy transfers or latency. Peak observed stack use is 30 bytes,
not a worst-case stack proof. The spool and output temporary file coexist, so
available disk space can limit the output.

### Intel HEX

CP/M HEX now uses the same ASO spool and bounded replay windows as COM and BIN.
Each window is converted to addressed records with the shared checksum writer;
the final partial window is kept at its exact logical length. The output keeps
the established record width, CRLF endings and EOF record, then receives CP/M
record padding. Empty, one-byte, exact-window and short-tail images are tested,
as is a 20 KiB image whose bytes match the Node HEX renderer. A malformed spool
leaves an existing destination untouched.

The output is still subject to available disk space: unlike the compact ASO
spool, Intel HEX text is several times larger than the binary image. The
emulator's sequential BDOS-call measurements do not establish physical floppy
latency.

## 7. Implementation order and acceptance

Output changes are implemented in independently proved steps. Current status:

1. **Complete:** executable byte-exact valid and invalid vectors and the Node streaming writer/reader.
2. **Complete:** the ordered native output contract and explicit high-water result at COMMIT, including forward reservations, backward `ORG` and the `$10000` endpoint.
3. **Complete:** a CP/M internal spool writer that emits canonical operations sequentially and pads CP/M records. It is checked byte-for-byte against the Node codec and tested with a logical image beyond the old RAM window.
4. **Complete:** CP/M COM/BIN automatically spool and materialise through bounded sequential windows. Tests cover the `$FF00` range, empty and one-byte images, images one byte below, at and above the 33,280-byte window, late patches to earlier windows, PATCH payloads crossing a window, malformed streams, injected read/write/close/rename failures, disk-full rollback and prior-output preservation. The memory extent, stack observation and record traffic are measured.
5. **Complete:** CP/M HEX replays ASO windows through the shared HEX writer. Tests cover multi-window output, checksums, record padding, spool validation and preservation of an earlier destination.
6. **Complete:** Node CLI BIN/COM/HEX-only builds apply ordered IMAGE/PATCH callbacks directly to one flat target buffer. Builds requesting listing or D8, and existing programming-API calls, retain the full generation path and its metadata. A shared forward-patch/gap fixture matches across the Node flat sink, Node generation renderer and CP/M COM/BIN/HEX outputs.

The measured CP/M implementation uses sequential window replay. The lower-bound
random-record candidate remains a separate size estimate, not a complete
implementation or a measurement of physical floppy performance.

The CP/M output RAM limit is removed. This does not promise that a resulting
COM file will run on every CP/M machine: the destination machine's TPA remains
a separate load-time limit. Source-part limits, filesystem capacity, disk
space and the Z80 target address space remain separate constraints too.
