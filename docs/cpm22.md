# Native Atom on CP/M 2.2

Atom has a native CP/M 2.2 transient program for the ideal Debug80 platform.
The checked image is [`assets/atom-cpm22.com`](../assets/atom-cpm22.com). It
loads one source file, runs the ordinary Z80 Atom core inside CP/M, and
publishes a COM file through real BDOS calls. Debug80 supplies the disk and
terminal below the BIOS; it does not intercept BDOS or replace the assembler
with host code.

With no arguments, Atom retains the original `INPUT.ASM` and `OUTPUT.COM`
defaults:

```text
A>ATOM

OUTPUT.COM written
A>OUTPUT
Hello from native Atom
```

Two arguments select another source and output:

```text
A>ATOM HELLO.ASM MADE.COM

MADE.COM written
A>MADE
Hello from native Atom
```

The command accepts either no arguments or exactly two current-drive names.
Each field follows CP/M's 8.3 lengths and uses letters, digits, or
`$#@!%&'()-^{}~`; the CCP canonicalises lowercase input. The output extension
must be `.COM`. Drive prefixes, wildcards, empty fields, extra arguments, and
reserved punctuation receive a specific diagnostic. Debug80's ideal CP/M
machine currently exposes only drive A, so drive prefixes add no useful reach
and are rejected.

The adapter treats `$1A` as text EOF. The selected source may contain at most
65,535 logical bytes. Host preprocessing, `%INCLUDE`, `INCBIN`, and multipart
source plans remain outside this increment.

## Retained design

The adapter scans the source once to establish its logical length. During
assembly, `AtomSourceReadByte` uses one 128-byte cache and CP/M random-record
reads. Random access is required because expression lookahead can cross an
arbitrary run of spaces and string emission rereads bytes from an earlier
record. A forward-only record buffer would change accepted programs.

The adapter retains the target image in TPA. IMAGE calls write sequential or
placed bytes into that image; PATCH calls replace bytes directly. For an output
named `NAME.COM`, commit uses `NAME.$$$` and `NAME.BAK`. Before reading the
source, the adapter checks that neither auxiliary file exists and that the
source is not the output, temporary, or backup file. CP/M 2.2 runs one program
at a time, so successful preflight reserves both names until Atom returns.
Commit closes the temporary file, moves an existing output to the backup name,
renames the temporary file, and then deletes the backup. Abort removes the
temporary file and restores the backup when publication had reached that stage.

This arrangement keeps compilation failure atomic without adding a second
object parser. Gaps made by `ORG` or uninitialised `DS` retain zero bytes, which
matches the flat host materialisation. The final CP/M record may contain bytes
beyond the logical COM length; CP/M 2.2 records do not carry an exact final-byte
count, and those bytes lie after the program image.

The measured TPA map is:

| Range | Bytes | Use |
| --- | ---: | --- |
| `$0100..$3670` | 13,681 | relocation header, native Atom, adapter code and resident state |
| `$4000..$407F` | 128 | source random-record cache |
| `$4080..$4FFF` | 3,968 | unallocated TPA |
| `$5000..$7FFF` | 12,288 | 1,536 simultaneous eight-byte symbols |
| `$8000..$8FFF` | 4,096 | 585 complete seven-byte pending records |
| `$9000..$D77F` | 18,304 | flat output image |
| `$D780..$D7FF` | 128 | unallocated TPA |
| `$D800..$E3FF` | 3,072 | stack allocation |

The linked image contains the 12,396-byte native core account, a 16-byte COM
entry and relocation header, and 1,282 CP/M-specific resident bytes after the
eight host-service stub bytes and five bytes of the memory-backed source
fallback have been replaced. The adapter increment divides into 985 code bytes,
185 immutable bytes, and 112 resident writable bytes. The
command-tail path uses 283 code bytes. The complete output portion uses 370
code bytes, including dynamic FCB construction and rollback. The complete
source portion uses 125 code bytes and a 128-byte cache. The cache key overlays
the output cursor because the first value is dead before commit initializes the
second. The 18,304-byte output image is non-resident workspace in TPA, not part
of the COM file.

Against the fixed-name baseline, the filename increment added 491 code bytes
and 119 immutable bytes while removing 132 workspace bytes, for a net resident
increase of 478 bytes. One input FCB becomes the rename FCB after source reads
finish, and one work FCB is rebuilt for temporary and backup operations. That
increment did not change generated programs, runtime support, source capacity,
output capacity, or stack allocation.

Against that immediately preceding filename build, the cached reader adds nine
adapter code bytes and replaces five additional native fallback bytes. The net
resident increase is four bytes. Immutable data, resident workspace, generated
programs, runtime support, output capacity, symbol capacity, pending capacity,
and stack allocation remain unchanged. The logical source limit rises by
61,439 bytes. Source execution storage changes from a 4,096-byte part plus a
128-byte overflow probe to one 128-byte cache, a net reduction of 4,096 bytes.

## Output-path comparison

Three output paths were considered against the same Atom sink contract.

| Path | Evidence | Resident result | Workspace result |
| --- | --- | ---: | ---: |
| In-TPA image, then sequential COM write | Measured complete implementation | 1,282-byte complete adapter increment; 370 output-specific code bytes | 18,304-byte image |
| Sequential COM plus random-record patching | Measured lower-bound Z80 kernel; complete total remains a hypothesis | 142-byte kernel; estimated 850–1,050-byte complete adapter | 137-byte kernel workspace |
| NOBJ spools plus separate materializer | Measured lower-bound Z80 kernel; complete total remains a hypothesis | 165-byte kernel; estimated 1,250–1,800-byte complete producer and materializer | 135-byte kernel workspace plus disk spools |

The lower-bound kernels are reproducible with
`npm run measure:cpm22-output-candidates`. They exclude the common source
loader, diagnostics, filenames, rollback rename, and interface text, so they
are not presented as complete adapter measurements. Random-record output also
needs gap creation, buffered sequential writes, patch read-modify-write,
cross-record word patches, close and recovery paths. NOBJ additionally needs
complete framing, record ordering, CRC, validation, and a materializer before a
COM can run.

The in-TPA design is the smallest complete resident implementation measured in
this increment. The random-record and NOBJ totals remain hypotheses because
their kernels omit the filename and transactional paths now measured in the
retained adapter. Random-record output remains the next candidate when output
capacity warrants a complete second prototype. NOBJ remains useful when the
stored patchable object is itself a deliverable, but it is not the smallest
measured route to one flat CP/M COM.

## Proof account

The representative program contains a forward reference and produces a
34-byte COM. With the default command, transient entry through the final `RET`
uses 78,098 instructions and 1,166,365 T-states. CCP command load through the
return tail uses 123,179 instructions and 1,862,629 T-states. The named command
`ATOM HELLO.ASM MADE.COM` uses 79,420 instructions and 1,178,809 T-states in
the transient, or 127,507 instructions and 1,900,253 T-states from the CCP.
The measured stack high-water mark remains 32 bytes below `$E400`.

The default success path makes 29 BDOS calls; the named path makes 27 because
its printed output name is two characters shorter. Both paths perform two
auxiliary-name open probes, one source open, one DMA selection, two sequential
source reads, two random source reads, one temporary delete and create, one
sequential output write, one output close, two backup deletes, two renames, and
console output. CP/M has no operating-system-side open handle, so the adapter
may abandon the read-only source FCB after its last random read; only written
files require close processing.

The 16,535-byte representative source uses 1,856,634 transient instructions,
18,501,010 T-states, 284 BDOS calls, and 130 random-record cache fills. CCP load
through return uses 1,904,881 instructions and 19,223,791 T-states. The
proof compares the published logical COM bytes with the checked Mac Atom
result, executes the selected COM under CP/M, and checks its terminal output.

Capacity proofs accept 65,535 source bytes and 18,304 target bytes exactly. The
next source byte fails before assembly. The next target byte receives Atom's
ordinary capacity diagnostic. Filename proofs cover both length boundaries,
lowercase canonicalisation, spacing, safe and reserved punctuation, wrong
arity, missing files, source/output collisions, and pre-existing auxiliary
files. A malformed named source reports its driver status, source part, and
logical byte offset, calls abort, removes the selected temporary file, and
preserves the earlier output. Strict AZM register contracts cover the linked
source. Record-boundary proofs cover 127, 128, and 129 bytes. Separate cases
accept 4,095, 4,096, and 4,097 bytes across the retired source limit. The suite
also covers CP/M text EOF, forward lookahead followed by backward rereading,
long string rereading, multiple commands in one session, and exact cache record
ordinals. The execution proof checks the restored caller stack and the `$D800`
stack floor.

`npm run build:cpm22` regenerates the COM and
[`proofs/cpm22-census.json`](../proofs/cpm22-census.json). `npm run
verify:cpm22` checks both files. `npm run measure:cpm22` repeats the guest
execution account.
