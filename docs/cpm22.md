# Native Atom on CP/M 2.2

Atom has a native CP/M 2.2 transient program for the ideal Debug80 platform.
The checked image is [`assets/atom-cpm22.com`](../assets/atom-cpm22.com). It
loads one source file or an ordered source list, runs the ordinary Z80 Atom
core inside CP/M, and publishes a COM file through real BDOS calls. Debug80
supplies the disk and terminal below the BIOS; it does not intercept BDOS or
replace the assembler with host code.

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

An `@` after the two names treats the first file as a source plan:

```text
A>TYPE BUILD.LST
DECLS.ASM
MAIN.ASM
A>ATOM BUILD.LST PROGRAM.COM @

PROGRAM.COM written
```

The command accepts no arguments, exactly two current-drive names, or two names
followed by `@`. Each field follows CP/M's 8.3 lengths and uses letters,
digits, or `$#@!%&'()-^{}~`; the CCP canonicalises lowercase input. The output
extension must be `.COM`. Drive prefixes, wildcards, empty fields, extra
arguments, and reserved punctuation receive a specific diagnostic. Debug80's
ideal CP/M machine currently exposes only drive A, so drive prefixes add no
useful reach and are rejected.

The source-plan format contains one current-drive CP/M 8.3 source name per
logical line. It accepts LF or CRLF, lowercase names, physical EOF after the
final name, and CP/M text EOF (`$1A`). It has no header, blank lines, comments,
drive prefixes, wildcards, or trailing fields. A plan contains 1–255 entries;
each occurrence is a distinct logical part, so repeated filenames are legal.
The adapter also treats `$1A` as EOF in each source. Every part may contain at
most 65,535 logical bytes.

This CP/M plan is deliberately smaller than the portable SP1 host format. It
does not perform dependency discovery, `%INCLUDE`, conditional preprocessing,
or `INCBIN` expansion. A build tool may write the ordered list, or a programmer
may maintain it directly.

## Retained design

Before Atom opens an output generation, the adapter reads the complete plan,
opens and scans every listed source, and writes the native five-byte descriptor
array. Missing files, malformed plans, excess parts, and oversized source parts
therefore leave an earlier COM untouched. The adapter then rewinds the plan and
reopens each preflighted source as the native driver advances to its ordinal.
CP/M is single-tasking, so the files cannot change between those two reads.

During assembly, `AtomSourceReadByte` uses one 128-byte cache and CP/M
random-record reads. Random access is required because expression lookahead can
cross an arbitrary run of spaces and string emission rereads bytes from an
earlier record. A forward-only record buffer would change accepted programs.
The native driver resets the tokenizer at each part boundary. Tokens cannot
join across files, while private-label scope and forward references retain the
ordinary multipart semantics. Diagnostics report the exact zero-based part
ordinal and offset within that part.

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
| `$0100..$3834` | 14,133 | relocation header, native Atom, adapter code and resident state |
| `$3835..$3FFF` | 1,995 | free resident-partition margin |
| `$4000..$407F` | 128 | source random-record cache |
| `$4080..$40FF` | 128 | source-plan sequential-record cache |
| `$4100..$45FA` | 1,275 | complete 255-part descriptor array |
| `$45FB..$45FF` | 5 | unallocated TPA |
| `$4600..$4623` | 36 | source-plan FCB |
| `$4624..$4627` | 4 | source-plan cursor, remaining count, and line state |
| `$4628..$4FFF` | 2,520 | unallocated TPA |
| `$5000..$7FFF` | 12,288 | 1,536 simultaneous eight-byte symbols |
| `$8000..$8FFF` | 4,096 | 585 complete seven-byte pending records |
| `$9000..$D77F` | 18,304 | flat output image |
| `$D780..$D7FF` | 128 | unallocated TPA |
| `$D800..$E3FF` | 3,072 | stack allocation |

The linked image contains the 12,396-byte native core account, a 16-byte COM
entry and relocation header, and 1,734 CP/M-specific resident bytes after the
eight host-service stub bytes and five bytes of the memory-backed source
fallback have been replaced. The adapter increment divides into 1,421 code
bytes, 206 immutable bytes, and 107 resident writable bytes. The command-tail
path uses 303 code bytes. The complete output portion uses 366 code bytes,
including dynamic FCB construction and rollback. The complete source portion
uses 565 code bytes. The cache key overlays the output cursor because the first
value is dead before commit initializes the second. The 18,304-byte output
image is non-resident workspace in TPA, not part of the COM file.

Multipart operation adds 1,443 bounded TPA bytes: a 128-byte plan cache, 1,275
descriptor bytes, a 36-byte FCB, and four bytes of plan state. Including the
existing 128-byte source cache, source execution storage is 1,571 bytes. The
resident build descriptor is five bytes smaller because both single- and
multipart-source commands now use the same external descriptor array. The
complete table can describe 16,711,425 logical source bytes, although the
mounted disk usually imposes a lower practical total.

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

Against the 13,681-byte cached single-source build, native source plans add 452
resident bytes: 436 code bytes and 21 immutable bytes, offset by five fewer
resident workspace bytes. They add 1,443 bytes of bounded TPA workspace and no
native-core, generated-program, runtime, output-image, symbol, pending, or stack
bytes. The first complete correct prototype occupied 14,225 bytes. The focused
feature pass reduced it to 14,133 bytes by sharing descriptor construction, FCB
clearing, plan setup, and diagnostic tails. That pass saved 92 resident bytes
without changing capacities or moving resident bytes into another account.

## Source-plan comparison

Three plan representations were assembled as independent parser kernels before
the CP/M format was selected:

| Representation | Parser code | Parser state | Host codec |
| --- | ---: | ---: | --- |
| Existing SP1 text | 173 bytes | 2 bytes | existing |
| One CP/M 8.3 name per line | 29 bytes | 1 byte | none |
| Binary FCB table | 49 bytes | 1 byte | new codec required |

These measurements exclude the common command selector, BDOS record reader,
filename checks, source preflight, descriptors, diagnostics, and part switching.
The line format has the smallest measured parser and requires no binary producer.
SP1 remains the portable host interchange because it carries logical paths and
bank ordinals that the flat CP/M profile neither needs nor can represent.
`npm run measure:cpm22-plan-candidates` reproduces the three kernels.

## Output-path comparison

Three output paths were considered against the same Atom sink contract.

| Path | Evidence | Resident result | Workspace result |
| --- | --- | ---: | ---: |
| In-TPA image, then sequential COM write | Measured complete retained implementation | 1,734-byte current adapter increment; 366 output-specific code bytes | 18,304-byte image |
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
the current adapter. The random-record and NOBJ totals remain
hypotheses because their kernels omit the filename and transactional paths now
measured in the retained adapter. Random-record output remains the next
candidate when output capacity warrants a complete second prototype. NOBJ
remains useful when the stored patchable object is itself a deliverable, but it
is not the smallest measured route to one flat CP/M COM.

## Proof account

The representative program contains a forward reference and produces a
34-byte COM. With the current Debug80 acceptance disk, the default command's
transient entry through the final `RET` uses 84,883 instructions and 1,227,658
T-states. CCP command load through the return tail uses 131,492 instructions
and 1,948,586 T-states. The named command `ATOM HELLO.ASM MADE.COM` uses 86,205
instructions and 1,240,107 T-states in the transient, or 135,820 instructions
and 1,986,215 T-states from the CCP.
The measured stack high-water mark remains 32 bytes below `$E400`.

The default success path makes 29 BDOS calls; the named path makes 27 because
its printed output name is two characters shorter. Both paths perform two
auxiliary-name open probes, one source open, one DMA selection, two sequential
source reads, two random source reads, one temporary delete and create, one
sequential output write, one output close, two backup deletes, two renames, and
console output. CP/M has no operating-system-side open handle, so the adapter
may abandon the read-only source FCB after its last random read; only written
files require close processing.

The 16,535-byte representative source uses 1,923,190 transient instructions,
19,131,614 T-states, 284 BDOS calls, and 130 random-record cache fills. CCP load
through return uses 1,972,965 instructions and 19,879,059 T-states. The
proof compares the published logical COM bytes with the checked Mac Atom
result, executes the selected COM under CP/M, and checks its terminal output.

The two-part representative contains 31 source bytes and produces four program
bytes. It uses 80,083 transient instructions, 1,176,001 T-states, 39 BDOS calls,
two plan-record reads, two source preflight reads, and two source random reads.
CCP load through return uses 129,969 instructions and 1,924,447 T-states. The
test asserts the complete BDOS call sequence, exact bytes `C3 03 01 C9`, both
part transitions, return address, and restored stack.

The large multipart proof combines two 33,000-byte comment parts with the
151-byte representative program, for 66,151 logical source bytes. It produces
the same 34 initialized bytes as the single-file program and uses 7,538,718
transient instructions, 73,843,189 T-states, 1,075 BDOS calls, two plan reads,
518 sequential source reads, and 518 random source reads. CCP load through
return uses 7,588,604 instructions and 74,591,635 T-states. Its stack
high-water mark is also 32 bytes.

Capacity proofs accept 255 parts, 65,535 bytes in each part, and 18,304 target
bytes exactly. Part 256, source byte 65,536, and target byte 18,305 fail before
publication. Canaries bracket the complete descriptor table and plan state.
Plan proofs cover missing files, empty and malformed records, lowercase names,
LF, CRLF, physical EOF, text EOF, exact 127/128/129-byte plan boundaries,
repeated files as distinct ordinals, and source/output collisions. They also
prove that a part boundary cannot join tokens and that diagnostics retain the
offending part and local offset.

Filename proofs cover both length boundaries, lowercase canonicalisation,
spacing, safe and reserved punctuation, wrong arity, missing files,
source/output collisions, and pre-existing auxiliary files. A malformed source
reports its driver status, source part, and logical byte offset, calls abort,
removes the selected temporary file, and preserves the earlier output. Strict
AZM register contracts cover the linked source. Separate cases accept 4,095,
4,096, and 4,097 bytes across the retired source limit. The suite also covers
forward lookahead followed by backward rereading, long string rereading,
plan-to-single and plan-to-plan commands in one session, failure between those
commands, exact cache records, the restored caller stack, and the `$D800` stack
floor.

`npm run build:cpm22` regenerates the COM and
[`proofs/cpm22-census.json`](../proofs/cpm22-census.json). `npm run
verify:cpm22` checks both files. `npm run measure:cpm22` repeats the guest
execution account. `npm run verify:cpm22-plan-candidates` checks the source-plan
representation measurements used above.
