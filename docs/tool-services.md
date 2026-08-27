# Atom tool-service boundary

Atom reaches files, output publication, and a human-facing console through a
private tool-service boundary. This boundary belongs to Atom and its
development environments. It is not part of Atom assembly language, a CP/M
BIOS extension, or an interface inherited by assembled programs.

The resident assembler keeps its compact existing entries:

- source-byte read;
- generation begin;
- IMAGE byte;
- PATCH byte and word;
- commit; and
- abort.

These entries are a compiler-facing adapter. A provider may retain a complete
image, append an addressed object stream, or translate the operations into
transactional files. The adapter shape is intentionally not forced to match
Nucleus's compiler-host vector. Both compilers share the meanings of source,
binary object, console, commit, and abort operations without paying for an
identical resident call sequence.

## Providers

The Node profile routes the source and publication entries through one private
gateway in `src/host/providers/tool-service-gateway.mjs`. Node path handling, dependency
discovery, filesystem descriptors, rendering, and artifact-set publication
remain outside the Z80 core. The gateway also defines optional console read,
console write, successful exit, and failed exit operations for a direct-host
tool profile. Console output is separate from IMAGE and PATCH data.

The CP/M profile links the compact entries to an adapter that uses only the
public BDOS entry at `$0005`. FCBs, DMA addresses, records, temporary names, and
backup names stay inside that adapter. Source text treats `$1A` as logical EOF,
but binary output retains all eight bits. Console text uses standard CP/M
console operations and should be treated as seven-bit ASCII.

Debug80's normal CP/M profile does not intercept this boundary or BDOS. It
boots the real guest CCP and BDOS, whose BIOS reaches Debug80's ideal terminal
and disk devices. A direct Debug80-hosted Atom run instead selects the private
Node gateway explicitly; it does not intercept arbitrary BIOS calls, BDOS
calls, or memory accesses.

The named-object profile routes those same compact callbacks through the common
16-byte request. It keeps one source handle live, reads source through a
128-byte cache, and publishes one flat binary object transactionally. Gaps
before IMAGE bytes and the final logical high-water mark are written as zeroes;
PATCH bytes seek into already written data and then restore the append cursor.
The source and output selectors are separate, so a small machine can read its
ordinary project filesystem and use a different transactional output store.

TECM8 provides the common request beneath private selector `$91` for its
bounded transactional store. Atom's host and Z80 adapters use the same service
meanings without changing the assembler core. The Z80 proof assembles through
two selectors, exercises gap filling and forward patches, injects a poisoned
write, and runs all 255 source ordinals while keeping only one source handle
open. Installing the ordinary TEC-FS read provider, resolver, launcher, and RAM
map remains deployment work.

## Contract

Success returns carry clear and status zero. Failure returns carry set and a
nonzero status. The stack returns to its entry depth. IX and IY are preserved
across the private boundary unless a published client entry explicitly allows
otherwise. Buffers and request values are valid only during the synchronous
call, and the provider retains no Z80 pointer after return.

Source, IMAGE, PATCH, stored objects, and emitted machine code are
byte-transparent. EOF is separate from every byte value. A failed read does
not advance its cursor. IMAGE and PATCH retain their original order. A failed
write or commit cannot replace the preceding committed generation; abort
discards the tentative generation.

Assembled programs receive none of Atom's source, spool, dependency, or
publication capabilities. They contain only the instructions and data selected
by the source program.

## Size

The Node gateway adds no resident Z80 bytes. The native core remains 12,396
bytes, including its existing 24-byte fail-closed service-stub tail.

The Z80 named-object composition is Measured 13,515 resident bytes: the
12,396-byte core with its memory fallback and fail-closed sink tail replaced by the
adapter. The measured adapter delta is 1,115 bytes, leaving 2,873 bytes below a
16 KiB boundary. Its caller supplies 399 bytes of always-visible workspace: a
16-byte request, a 255-byte copied-name area, and a 128-byte transfer cache.
The workspace is not part of the resident image.

For an immutable expansion bank, the harness builder separates the image into
12,770 bytes of code and tables and 741 bytes of fixed state. The fixed state
joins the 399-byte service workspace in common RAM; the bank remains unchanged
during a proved multipart assembly.

The CP/M provider preserves IX and IY around BDOS with one shared wrapper. The
linked transient is Measured 14,660 bytes, leaving 1,084 bytes below its
resident boundary. Its adapter account is Measured 2,261 bytes: 1,897 code
bytes, 257 immutable bytes, and 107 writable bytes. The separate multipart
workspace holds the include graph, filenames, source descriptors, and resolver
state.
