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
gateway in `src/host/tool-service-gateway.mjs`. Node path handling, dependency
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

TECM8, MON3, and TEC-FS providers remain deployment work. They may replace the
transport below the adapter without changing Atom's source language or native
core.

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

The CP/M provider now preserves IX and IY around BDOS with one shared 12-byte
wrapper. The linked transient is 14,145 bytes, with 1,983 bytes free below the
`$4000` source cache. The CP/M-specific resident account is 1,746 bytes:
1,433 code bytes, 206 immutable bytes, and 107 writable bytes. No capacity or
generated-program byte changed.
