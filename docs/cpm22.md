# Atom on CP/M 2.2

Download `ATOM.COM` from the
[latest release](https://github.com/jhlagado/atom/releases/latest). The same
file is retained in this repository as
[`assets/atom-cpm22.com`](../assets/atom-cpm22.com).

## Command line

With no arguments, Atom reads `INPUT.ASM` and writes `OUTPUT.COM`:

```text
A>ATOM

OUTPUT.COM written
```

Two arguments select another root source and output:

```text
A>ATOM HELLO.ASM MADE.COM

MADE.COM written
```

One source argument supplies conventional extensions:

```text
A>ATOM HELLO

HELLO.COM written
```

The compact native command accepts these forms:

```text
ATOM
ATOM SOURCE
ATOM SOURCE OUTPUT
ATOM ?
```

Names must be current-drive CP/M 8.3 names. An explicit output extension must
be `.COM`, `.BIN` or `.HEX`. Drive prefixes, wildcards, incomplete argument
pairs, extra arguments and invalid filename characters are rejected. CP/M
canonicalises lowercase command input, so `atom hello.asm made.com` is
equivalent to the uppercase form.

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
| Output image | 18,304 bytes |
| Global or current-scope private symbol | 8 significant characters |

The CP/M filesystem may impose a lower practical source limit. The output
starts at `$0100` and ends no later than `$487F`.

## Diagnostics

The CP/M program reports a native status, source-part ordinal and byte offset:

```text
Atom error 02 00 033C
```

All three fields are hexadecimal. Here, `02` means that Atom rejected a source
statement, `00` identifies the first source part and `033C` is the zero-based
byte offset within that file.

| Status | Meaning |
| ---: | --- |
| `01` | Invalid build configuration |
| `02` | Source statement rejected |
| `03` | Undefined symbol at end of assembly |
| `04` | Output service failure |
| `05` | Internal invariant failure |

The Node command converts the same part and offset into a filename, line and
column. The compact CP/M program does not yet perform that conversion.

## Verification

Contributors can rebuild and verify the native image with:

```sh
npm run build:cpm22
npm run verify:cpm22
node --test test/cpm22.test.mjs
```

`npm run build:cpm22` regenerates both the COM and its measurement census.
