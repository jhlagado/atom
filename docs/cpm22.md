# Atom on CP/M 2.2

Download `ATOM.COM` from the
[latest release](https://github.com/jhlagado/atom/releases/latest). The same
file is retained in this repository as
[`assets/atom-cpm22.com`](../assets/atom-cpm22.com).

The [Atom downloads page](https://jhlagado.github.io/atom/) serves the current
`ATOM.COM` directly and can open the matching disk image in Triptych. The disk
image starts CP/M from protected drive A and seeds writable drive B with the
same release. Switch to `B:` before running Atom.

## Command line

Run Atom without arguments to see its command forms. This returns to CP/M
without opening a source or output file:

```text
A>ATOM

Usage: ATOM [SOURCE [OUTPUT]]
A>
```

Give a source name to create a `.COM` with the same basename. If the extension
is omitted, `.ASM` is used for the source:

```text
A>ATOM HELLO.ASM

HELLO.COM written
```

The shorter form without `.ASM` remains available:

```text
A>ATOM HELLO

HELLO.COM written
```

Two names select a specific output file:

```text
A>ATOM HELLO.ASM MADE.COM

MADE.COM written
```

The native command accepts `ATOM`, `ATOM SOURCE`, and `ATOM SOURCE OUTPUT`.
`ATOM ?` remains a compatibility alias for the help shown by bare `ATOM`.
Malformed arguments print usage and return the command-error status.

Names must be current-drive CP/M 8.3 names. An explicit output extension must
be `.COM`, `.BIN`, `.HEX` or `.ASO`. Drive prefixes, wildcards, extra arguments
and invalid filename characters are rejected. CP/M canonicalises lowercase
command input, so `atom hello.asm made.com` is equivalent to the uppercase
form.

`.ASO` writes Atom's ordered image-and-patch stream instead of an executable:

```text
A>ATOM LARGE.ASM LARGE.ASO

LARGE.ASO written
```

The CP/M writer can describe an image spanning `$0100` through `$FFFF`, but
Atom does not yet read that stream back to create a correspondingly large
`.COM` or `.BIN`. Those formats still use the bounded RAM image described
below.

## Multiple source files

The root source declares its dependencies with leading `%INCLUDE` directives:

```asm
%INCLUDE "CONSOLE.ASM"
%INCLUDE "STRINGS.ASM"

ORG 100H
CALL START
RET
```

An included file can include further files. Atom discovers the complete graph,
includes each exact CP/M name once, rejects cycles and assembles dependencies
before the file that names them. Sibling order follows the order of the
directives. Include names are case-insensitive.

`%INCLUDE` belongs to the leading header of a file. Blank lines, whitespace,
and comments may appear in that header. Once ordinary source begins, another
`%INCLUDE` is an error. The provider changes each validated directive line into
an assembler comment without moving any other byte, so diagnostic offsets stay
exact.

The native profile accepts quoted current-drive CP/M 8.3 names only:

```asm
%INCLUDE "MATH.ASM"
```

It does not parse project JSON, search paths or directory paths. Those are
desktop facilities. `%DEFINE`, conditional preprocessing and `INCBIN` also
remain Node-hosted facilities at present.

## Assembly and publication

Atom checks the complete include graph before it starts an output. Missing
files, malformed directives, cycles, excessive part counts and oversized
sources therefore leave an earlier output untouched. Private-label scope and
forward references continue across the ordered source files.

For an output named `NAME.EXT`, Atom writes `NAME.$$$`, moves an existing output
to `NAME.BAK`, renames the completed temporary file and then removes the
backup. A failed assembly removes the temporary file and restores the backup
when necessary. No source part may use the output, temporary or backup name.

The output is a flat image beginning at `$0100`. Gaps created by `ORG` or
uninitialised `DS` contain zero bytes. BIN and COM contain the same raw bytes.
COM selects the CP/M load-and-entry convention but adds no header. HEX contains
16-byte addressed data records, checksums and an end-of-file record. CP/M
files occupy complete 128-byte records, so BIN and COM may contain padding
after the logical image and HEX may contain `$1A` padding after its end record.

## Limits

| Item | Limit |
| --- | ---: |
| Source files | 255 |
| One source file | 65,535 bytes |
| COM, BIN or HEX image | 18,304 bytes |
| ASO image span | 65,280 bytes, from `$0100` to `$10000` |
| Minimum TPA | 58,112 bytes, with BDOS at `$E400` or higher |
| Global or current-scope private symbol | 8 significant characters |

The CP/M filesystem may impose a lower practical source limit. The output
starts at `$0100`; COM, BIN and HEX end no later than `$487F`. ASO records the
larger address span without materialising it in the output RAM window. The
adapter checks the BDOS boundary before using its private memory and rejects a
smaller TPA. This minimum is emulator-verified; it is not a claim of support
for every CP/M configuration or physical floppy drive.

## Diagnostics

An assembly error reports its status, source filename, line and column:

```text
Atom error 02 INPUT.ASM:2:1
```

Here, `02` means that Atom rejected a source statement. The position is the
first byte of line 2 in `INPUT.ASM`. Line and column numbers are one-based
decimal values. A column counts source bytes, which are characters in an
ordinary CP/M text file. For an included file, the message names that file
rather than the root source.

| Status | Meaning |
| ---: | --- |
| `01` | Invalid build configuration |
| `02` | Source statement rejected |
| `03` | Undefined symbol at end of assembly |
| `04` | Output service failure |
| `05` | Internal invariant failure |

If the source cannot be reread after an assembly failure, Atom reports its
filename and original hexadecimal byte offset instead of an unverified line
and column. An internal error with an invalid part number retains the numeric
part and offset fields.

## Verification

Contributors can rebuild and verify the native image with:

```sh
npm run build:cpm22
npm run verify:cpm22
node --test test/cpm22.test.mjs
```

`npm run build:cpm22` regenerates both the COM and its measurement census.
