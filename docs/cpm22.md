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
4,096 logical bytes. Host preprocessing, `%INCLUDE`, `INCBIN`, and multipart
source plans remain outside this increment.

## Retained design

The adapter preloads the source and retains the target image in TPA. IMAGE
calls write sequential or placed bytes into that image; PATCH calls replace
bytes directly. For an output named `NAME.COM`, commit uses `NAME.$$$` and
`NAME.BAK`. Before reading the source, the adapter checks that neither
auxiliary file exists and that the source is not the output, temporary, or
backup file. CP/M 2.2 runs one program at a time, so successful preflight
reserves both names until Atom returns. Commit closes the temporary file,
moves an existing output to the backup name, renames the temporary file, and
then deletes the backup. Abort removes the temporary file and restores the
backup when publication had reached that stage.

This arrangement keeps compilation failure atomic without adding a second
object parser. Gaps made by `ORG` or uninitialised `DS` retain zero bytes, which
matches the flat host materialisation. The final CP/M record may contain bytes
beyond the logical COM length; CP/M 2.2 records do not carry an exact final-byte
count, and those bytes lie after the program image.

The measured TPA map is:

| Range | Bytes | Use |
| --- | ---: | --- |
| `$0100..$366C` | 13,677 | relocation header, native Atom, adapter code and resident state |
| `$4000..$4FFF` | 4,096 | source part |
| `$5000..$7FFF` | 12,288 | 1,536 simultaneous eight-byte symbols |
| `$8000..$8FFF` | 4,096 | 585 complete seven-byte pending records |
| `$9000..$D77F` | 18,304 | flat output image |
| `$D780..$D7FF` | 128 | source overflow probe |
| `$D800..$E3FF` | 3,072 | stack allocation |

The linked image contains the 12,396-byte native core account, a 16-byte COM
entry and relocation header, and 1,273 CP/M-specific resident bytes after the
eight host-service stub bytes have been replaced. The adapter increment divides
into 976 code bytes, 185 immutable bytes, and 112 resident writable bytes. The
command-tail path uses 283 code bytes. The complete output portion uses 370
code bytes, including dynamic FCB construction and rollback. The 18,304-byte
output image is non-resident workspace in TPA, not part of the COM file.

Against the fixed-name baseline, this increment adds 491 code bytes and 119
immutable bytes while removing 132 workspace bytes, for a net resident increase
of 478 bytes. One input FCB becomes the rename FCB after the source closes, and
one work FCB is rebuilt for temporary and backup operations. Generated programs,
runtime support, source capacity, output capacity, and stack allocation do not
change.

## Output-path comparison

Three output paths were considered against the same Atom sink contract.

| Path | Evidence | Resident result | Workspace result |
| --- | --- | ---: | ---: |
| In-TPA image, then sequential COM write | Measured complete implementation | 1,273-byte complete adapter increment; 370 output-specific code bytes | 18,304-byte image |
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
uses 70,469 instructions and 1,103,057 T-states. CCP command load through the
return tail uses 115,550 instructions and 1,799,321 T-states. The named command
`ATOM HELLO.ASM MADE.COM` uses 72,800 instructions and 1,123,607 T-states in
the transient, or 120,887 instructions and 1,845,051 T-states from the CCP.
The measured stack high-water mark remains 32 bytes below `$E400`.

The default success path makes 29 BDOS calls; the named path makes 27 because
its printed output name is two characters shorter. Both paths perform two
auxiliary-name open probes, one source open, two sequential source reads, one
source close, one temporary delete and create, one sequential output write,
one output close, two backup deletes, two renames, and console output. The
proof compares the published logical COM bytes with the checked Mac Atom
result, executes the selected COM under CP/M, and checks its terminal output.

Capacity proofs accept 4,096 source bytes and 18,304 target bytes exactly. The
next source byte fails before assembly. The next target byte receives Atom's
ordinary capacity diagnostic. Filename proofs cover both length boundaries,
lowercase canonicalisation, spacing, safe and reserved punctuation, wrong
arity, missing files, source/output collisions, and pre-existing auxiliary
files. A malformed named source reports its driver status, source part, and
logical byte offset, calls abort, removes the selected temporary file, and
preserves the earlier output. Strict AZM register contracts cover the linked
source, and the execution proof checks the restored caller stack and the
`$D800` stack floor.

`npm run build:cpm22` regenerates the COM and
[`proofs/cpm22-census.json`](../proofs/cpm22-census.json). `npm run
verify:cpm22` checks both files. `npm run measure:cpm22` repeats the guest
execution account.
