# Native Atom on CP/M 2.2

Atom is available as a native CP/M 2.2 transient program. The checked image is
[`assets/atom-cpm22.com`](../assets/atom-cpm22.com). It contains the ordinary
Z80 Atom core and a CP/M provider for source files, output publication, and
diagnostics. Debug80 can emulate the machine and disk, but it does not replace
the assembler or intercept BDOS calls.

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

The compact native command has one form:

```text
ATOM [SOURCE [OUTPUT.COM]]
```

Names must be current-drive CP/M 8.3 names. The output extension must be
`.COM`. Drive prefixes, wildcards, incomplete argument pairs, extra arguments,
and invalid filename characters are rejected. CP/M canonicalises lowercase
command input, so `atom hello.asm made.com` is equivalent to the uppercase
form.

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
includes each exact CP/M name once, rejects cycles, and assembles dependencies
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

It does not parse project JSON, search paths, or directory paths. Those are
desktop facilities. `%DEFINE`, conditional preprocessing, and `INCBIN` also
remain Node-hosted facilities at present.

## Assembly and publication

Before publication starts, the provider resolves the include graph, validates
every source, measures every part, and builds Atom's five-byte source
descriptors. Missing files, malformed directives, cycles, excessive part
counts, and oversized sources therefore leave an earlier output untouched.

Each source part is read through a 128-byte CP/M random-record cache. Random
access is required because expression lookahead and string emission can reread
earlier bytes. The tokenizer resets at every part boundary, so tokens cannot be
joined accidentally across files. Private-label scope and forward references
continue across the ordered compilation unit. Diagnostics report the exact
zero-based part ordinal and offset within that part.

For an output named `NAME.COM`, Atom writes `NAME.$$$`, moves an existing output
to `NAME.BAK`, renames the completed temporary file, and then removes the
backup. A failed assembly removes the temporary file and restores the backup
when necessary. No source part may use the output, temporary, or backup name.

The output is a flat CP/M image beginning at `$0100`. Gaps created by `ORG` or
uninitialised `DS` contain zero bytes. CP/M records do not retain an exact final
byte count, so the last 128-byte record can contain padding after the logical
program.

## Measured memory map

The current checked image has this TPA layout:

| Range | Bytes | Use |
| --- | ---: | --- |
| `$0100..$3A43` | 14,660 | native core, CP/M provider, and resident state |
| `$3A44..$3E7F` | 1,084 | free resident-partition margin |
| `$3E80..$3EFF` | 128 | source random-record cache |
| `$3F00..$3FFF` | 256 | dependency-first part order |
| `$4000..$4AF4` | 2,805 | 255 retained CP/M 8.3 names |
| `$4AF5..$4FEF` | 1,275 | 255 five-byte source descriptors |
| `$4FF0..$4FFB` | 12 | resolver state |
| `$5000..$7FFF` | 12,288 | symbol arena |
| `$8000..$8FFF` | 4,096 | pending-reference arena |
| `$9000..$D77F` | 18,304 | flat output image |
| `$D800..$E3FF` | 3,072 | stack allocation |

The exact resident end changes when provider code changes; the checked values
are recorded in
[`proofs/cpm22-census.json`](../proofs/cpm22-census.json). The image remains
below the `$3E80` source-cache boundary and below the 16 KiB resident target.

The eight-bit source ABI represents 255 parts. Each part has a 16-bit logical
offset and may contain at most 65,535 bytes, for a derived descriptive maximum
of 16,711,425 source bytes. A real CP/M volume normally reaches its directory
or disk-capacity limit before that derived maximum. On Debug80's standard CP/M
2.2 disk, the integration suite proves a 41-part build; the memory census proves
the complete 255-entry tables and their boundaries.

The output capacity is 18,304 bytes. The representative proof uses 32 bytes of
the reserved stack. These are target-profile limits, not limits of the Node
command.

## Verification

The CP/M suite proves:

- direct and named commands through real BDOS calls;
- nested include graphs, diamonds, deterministic order, and import-once
  behaviour;
- missing includes, malformed or late directives, cycles, and source/output
  conflicts before publication;
- exact source boundaries at 65,535 bytes and output boundaries at 18,304
  bytes;
- record-boundary lookahead, backward rereads, CP/M text EOF, and exact part
  boundaries;
- rollback with an earlier output, restored caller stack, and stack-floor
  canaries; and
- exact bytes against the Node-hosted Atom result.

Build and verify the native image with:

```sh
npm run build:cpm22
npm run verify:cpm22
node --test test/cpm22.test.mjs
```

`npm run build:cpm22` regenerates both the COM and its measurement census.
