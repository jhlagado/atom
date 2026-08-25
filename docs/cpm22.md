# Native Atom on CP/M 2.2

Atom has a native CP/M 2.2 transient program for the ideal Debug80 platform.
The checked image is [`assets/atom-cpm22.com`](../assets/atom-cpm22.com). It
loads `INPUT.ASM`, runs the ordinary Z80 Atom core inside CP/M, and publishes
`OUTPUT.COM` through real BDOS file calls. Debug80 supplies the disk and
terminal below the BIOS; it does not intercept BDOS or replace the assembler
with host code.

This is the first vertical slice, with fixed filenames and one source part:

```text
A>ATOM

OUTPUT.COM written
A>OUTPUT
Hello from native Atom
```

The CP/M adapter treats `$1A` as text EOF. `INPUT.ASM` may contain at most
4,096 logical bytes. Host preprocessing, `%INCLUDE`, `INCBIN`, command-tail
filenames, and multipart source plans remain outside this increment.

## Retained design

The adapter preloads the source and retains the target image in TPA. IMAGE
calls write sequential or placed bytes into that image; PATCH calls replace
bytes directly. Commit writes a temporary CP/M file, closes it, moves any
existing `OUTPUT.COM` to a backup name, renames the temporary file, and then
deletes the backup. Abort removes the temporary file and restores the backup
when publication had reached that stage.

This arrangement keeps compilation failure atomic without adding a second
object parser. Gaps made by `ORG` or uninitialised `DS` retain zero bytes, which
matches the flat host materialisation. The final CP/M record may contain bytes
beyond the logical COM length; CP/M 2.2 records do not carry an exact final-byte
count, and those bytes lie after the program image.

The measured TPA map is:

| Range | Bytes | Use |
| --- | ---: | --- |
| `$0100..$348E` | 13,199 | relocation header, native Atom, adapter code and resident state |
| `$4000..$4FFF` | 4,096 | source part |
| `$5000..$7FFF` | 12,288 | 1,536 simultaneous eight-byte symbols |
| `$8000..$8FFF` | 4,096 | 585 complete seven-byte pending records |
| `$9000..$D77F` | 18,304 | flat output image |
| `$D780..$D7FF` | 128 | source overflow probe |
| `$D800..$E3FF` | 3,072 | stack allocation |

The linked image contains the 12,396-byte native core account, a 16-byte COM
entry and relocation header, and 795 CP/M-specific resident bytes after the
eight host-service stub bytes have been replaced. The adapter increment divides
into 485 code bytes, 66 immutable bytes, and 244 resident writable bytes. The
complete output portion uses 233 of those code bytes. The 18,304-byte output
image is non-resident workspace in TPA, not part of the COM file.

## Output-path comparison

Three output paths were considered against the same Atom sink contract.

| Path | Evidence | Resident result | Workspace result |
| --- | --- | ---: | ---: |
| In-TPA image, then sequential COM write | Measured complete implementation | 795-byte complete adapter increment; 233 output-specific code bytes | 18,304-byte image |
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
this increment. Random-record output is the likely next design when output
capacity matters more than roughly 55–255 resident bytes. NOBJ remains useful
when the stored patchable object is itself a deliverable, but it is not the
smallest route to one flat CP/M COM.

## Proof account

The representative program contains a forward reference and produces a
34-byte COM. From transient entry through the final `RET`, native CP/M Atom
executes 65,205 instructions and 1,046,209 T-states. Including CCP command load
through the return tail gives 109,140 instructions and 1,723,975 T-states. The
measured stack high-water mark is 32 bytes below `$E400`.

The successful adapter path makes sixteen BDOS calls: source open, two DMA
selections and two sequential reads, source close, temporary erase and create,
output DMA selection and write, close, backup erase, two renames, final backup
erase, and console text output. The proof compares the published logical COM
bytes with the checked Mac Atom result, executes that COM under CP/M, and
checks its terminal output.

Capacity proofs accept 4,096 source bytes and 18,304 target bytes exactly. The
next source byte fails before assembly. The next target byte receives Atom's
ordinary capacity diagnostic. A malformed source reports its driver status,
source part, and logical byte offset, calls abort, removes `OUTPUT.$$$`, and
preserves an earlier `OUTPUT.COM`. Strict AZM register contracts cover the
linked source, and the execution proof checks the restored caller stack and the
`$D800` stack floor.

`npm run build:cpm22` regenerates the COM and
[`proofs/cpm22-census.json`](../proofs/cpm22-census.json). `npm run
verify:cpm22` checks both files. `npm run measure:cpm22` repeats the guest
execution account.

