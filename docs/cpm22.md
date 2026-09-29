# Atom on CP/M 2.2

Download `ATOM.COM` from the
[latest release](https://github.com/jhlagado/atom/releases/latest). The same
file is retained in this repository as
[`assets/atom-cpm22.com`](../assets/atom-cpm22.com).

The [Atom downloads page](https://jhlagado.github.io/atom/) serves the current
`ATOM.COM` directly and can open the matching disk image in Triptych. The disk
image starts CP/M from the writable A: drive and contains `EDIT.COM`, a
compilable `HELLO.ASM` example and its `HELLO.COM` output. Use A: for the
source, assembler and output files.
Each versioned image directory includes a `disk-contents.json` with the files'
sizes and checksums.

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
Malformed arguments print usage and return the command-error status.

Names must be current-drive CP/M 8.3 names. An explicit output extension must
be `.COM`, `.BIN` or `.HEX`. Drive prefixes, wildcards, extra arguments and
invalid filename characters are rejected. CP/M canonicalises lowercase
command input, so `atom hello.asm made.com` is equivalent to the uppercase
form.

COM, BIN and HEX are built in one command. Atom stages the completed output
before publishing it, so a failed build does not replace an earlier file.

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
`%INCLUDE` is an error. The CP/M preprocessor checks directive lines before
assembly. It turns each directive into an assembler comment, masks inactive
source as spaces and preserves every line ending and byte offset.

The native profile accepts quoted current-drive CP/M 8.3 names only:

```asm
%INCLUDE "MATH.ASM"
```

It does not parse project JSON, search paths or directory paths. Those are
desktop facilities. The CP/M preprocessor accepts up to 32 numeric `%DEFINE`
values in the root file's leading header. Put definitions before any include
or conditional directive. Names are case-insensitive and may be up to 17
characters. Values may use decimal, `$`-prefixed hexadecimal, `%`-prefixed
binary or Intel `H` and `B` suffixes. Intel hexadecimal values that start with
a letter need a leading zero, as in `0FFFFH`. A definition can refer to an
earlier definition.

`%IF`, `%ELSE` and `%ENDIF` select source and include branches. Conditions may
nest up to 16 levels and must be balanced within each file. Each condition is
one numeric literal or previously defined name. A conditional
`%INCLUDE` must be completed in the leading header before ordinary source
begins. Inactive includes are not opened. These numeric definitions are for
conditions; they do not substitute text into assembler source. `INCBIN` is not
part of the CP/M profile.

## Assembly and publication

Atom checks the complete include graph before it starts an output. Missing
files, malformed directives, cycles, excessive part counts and oversized
sources therefore leave an earlier output untouched. Private-label scope and
forward references continue across the ordered source files.

For an output named `NAME.EXT`, Atom writes a temporary file, moves an existing
output aside, renames the completed file and then removes the backup. A failed
assembly or publication removes temporary files and preserves the previous
output. No source part may use the output or temporary filename.

The output is a flat image beginning at `$0100`. Gaps created by `ORG` or
uninitialised `DS` contain zero bytes. BIN and COM contain the same raw bytes.
COM selects the CP/M load-and-entry convention but adds no header. HEX contains
16-byte addressed data records, checksums and an end-of-file record. All three
formats are materialised from the operation stream in 33,280-byte windows.
CP/M files occupy
complete 128-byte records, so BIN and COM may contain zero padding after the
logical image and HEX may contain `$1A` padding after its end record.
The boundary tests cover empty and one-byte images, plus images one byte below,
exactly at and one byte above the window for each format.

## Memory layout

The current `ATOM.COM` contains 19,191 bytes, from `$0100` to exclusive
`$4BF7`. The first 17,251 bytes end at `$4463`. The 1,940-byte output writer
and materialiser overlay follows immediately and ends at `$4BF7`. CP/M stores
the file in 150 records, or 19,200 bytes; nine bytes pad the loaded extent to
`$4C00`. The uninitialised workspace begins at `$5400`, leaving 2 KiB between
the loaded record boundary and workspace.

Writable work areas extend from `$5400` to `$A96A`. They hold the source
cache, include and conditional tables, symbol and pending-reference arenas,
and spool buffers. These fixed-address areas are not part of the COM payload.
The startup and assembly paths initialise their working values before use.
After successful assembly, the part-order page at `$5400` holds the
materialiser FCB and parser state. The source-cache page at `$5500` becomes the
HEX DMA buffer. The replay window begins at `$5580` and ends at `$D780`, for
33,280 bytes or 260 CP/M records. Atom fills it for each pass. The private
stack grows down from `$E400` through 3,072 reserved bytes. A 128-byte gap
separates the window from the stack.

The emulator test poisons the work areas and replay window before Atom starts.
Assembly and output still succeed, checking that neither depends on bytes
loaded from the COM image in those regions.

## Limits

| Item | Limit |
| --- | ---: |
| Source files | 255 |
| One source file | 65,535 bytes |
| COM or BIN image span | 65,280 bytes, from `$0100` to `$10000` |
| HEX logical image span | 65,280 bytes, from `$0100` to `$10000` |
| Materialiser output window | 33,280 bytes (260 CP/M records) |
| Minimum TPA | 58,112 bytes, with BDOS at `$E400` or higher |
| Global or current-scope private symbol | 8 significant characters |

The CP/M filesystem may impose a lower practical source or output limit. An
automatic build needs temporary disk space while it assembles and publishes
the requested output; HEX text can require several times the binary image's
space. A disk-full error leaves the old destination intact. The adapter checks
the BDOS boundary before using its private memory and rejects a smaller TPA.
This minimum is emulator-verified; it is not a claim of support for every CP/M
configuration or physical floppy drive.

The materialiser's measured window is 33,280 bytes (260 CP/M records). On the
bundled emulator, a dense COM spanning the complete `$FF00` target range used
two sequential spool scans and 510 sequential output-record writes. The same
run made no random output reads or writes. Peak observed stack use was 30 bytes;
this is an emulator observation, not a worst-case stack proof. Physical floppy
traffic and latency have not been measured.

## Diagnostics

An assembly error reports its status, source filename, line and column:

```text
Atom error 02 INPUT.ASM:2:1
```

This source location remains available because source errors return before the
materialiser reuses the source tables. A disk or materialisation failure uses
the same numeric diagnostic prefix and includes the destination filename, but
does not claim a source position:

```text
Atom error 04 OUTPUT.COM
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
npm run test:cpm22-self-host
```

`npm run build:cpm22` regenerates both the COM and its measurement census.
The CP/M self-assembly proof runs the resident `ATOM.COM`, assembles a
CP/M-ready copy of the Atom core source, and compares its output with the Node
assembler at the same origin. It is part of release qualification, but not the
Node package-publish check.
