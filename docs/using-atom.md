# Using Atom

Atom assembles Z80 source on a desktop or directly on CP/M. The source language
is the same in both environments. The desktop command also produces listings
and debugger maps.

## A first program

Save this as `main.asm`:

```asm
ORG $4000
START: LD A,42
       JR START
```

`ORG` sets the output address. The program loads 42 into A and loops back to
`START`. With the desktop command, assemble it with:

```sh
atom main.asm
```

The result is `build/main.bin` containing four bytes:

```text
3E 2A 18 FC
```

`3E 2A` encodes `LD A,42`. `18 FC` encodes the jump back four bytes from the
end of `JR`. The BIN file begins at `$4000`. It contains no leading padding
for the addresses below that origin.

## Output files

An output filename selects its format:

```sh
atom main.asm build/main.bin build/main.hex build/main.lst
```

| Suffix | Contents |
| --- | --- |
| `.bin` | Flat binary bytes |
| `.hex` | Intel HEX records with addresses and checksums |
| `.com` | Flat binary for CP/M, loaded and entered at `$0100` |
| `.lst` | Source lines, addresses, bytes and symbols |
| `.sym` | Global symbols for CP/M debuggers such as SID and ZSID |
| `.d8.json` | Source and symbol information for Debug80 |

A listing also contains routine sizes and a jump report. The report identifies
relative jumps near their range limit and absolute jumps that could use `JR`.

Output paths can follow the input or use `-o`:

```sh
atom -o build/main.hex main.asm
```

Each format and destination can appear once per command. A failed build leaves
previous outputs intact. Successful paths go to standard output. Diagnostics go
to standard error.

A `.com` output selects the CP/M target unless another target is explicit.
Its load base and entry must both be `$0100`. Atom reports incompatible source
placement rather than moving the assembled bytes.

## Source files and conditions

A leading `%INCLUDE` imports another source file. For example, `constants.asm`
containing `LIMIT EQU 42` supplies the value used by this program:

```asm
%DEFINE DEBUG 1
%INCLUDE "constants.asm"

ORG $4000
%IF DEBUG
LD A,LIMIT
%ELSE
LD A,0
%ENDIF
```

Atom assembles an included file when it reaches the `%INCLUDE`, then carries on
with the importer's next line. The result is the order you would get by pasting
each file's text in at its first `%INCLUDE`. Each source is assembled once,
including repeated imports through other dependencies. Cycles are rejected.
CP/M and Node share the code that does this, so they use the same order.
`%INCLUDE` belongs in the header before ordinary assembler source. A condition
that selects includes must close within that header.

`%DEFINE` creates a numeric preprocessor value. It selects `%IF` branches but
does not substitute text or create an assembler symbol. Definitions belong in
the root file's header before includes and conditions. Body conditions can
select instructions and data. Each file must have balanced `%IF`, `%ELSE`
and `%ENDIF` directives.

On the desktop, `-D` supplies a definition on the command line. Omit the
corresponding `%DEFINE` from the source before using it. Defining the same name
twice is an error:

```sh
atom -DDEBUG=0 main.asm build/main.bin
```

Include paths are relative to their source file. Source and binary paths must
stay inside the project root and match the filesystem's exact spelling.
Atom reads each file once, when it reaches it. Nothing is scanned ahead, so
avoid editing a project's files while it builds.

For binary data, `INCBIN` emits a file's bytes:

```asm
FONT: INCBIN "font.bin", 2048
```

The count selects a prefix of the file and can be any expression already
resolved. On Node, omitting it includes the whole file. CP/M requires a count
because file lengths are recorded in 128-byte units.

## Desktop project files

A JSON project saves the entry point, target and outputs:

```json
{
  "assembler": "atom",
  "entry": "main.asm",
  "target": "generic",
  "outputs": ["build/main.bin"]
}
```

`atom --project atom.json` reads paths relative to the project file.
Command-line paths replace the saved output list. A `definitions` object can
supply numeric values and `-D` overrides those saved values. A name supplied by
either method cannot also have a source `%DEFINE`. The `assembler` field is
optional for the Atom command.
CP/M reads assembly files directly and has no JSON project format.

`atom --help` lists the desktop options. Invalid command syntax returns status 2.
A build failure returns 1 and success returns 0.

## CP/M

CP/M loads commands at `$0100`. This program prints a message through BDOS
function 9 and returns to the command processor:

```asm
ORG $100
LD DE,MESSAGE
LD C,9
CALL 5
RET
MESSAGE: DB "HELLO FROM ATOM",13,10,"$"
```

Save it as `HELLO.ASM` on the current drive alongside `ATOM.COM`. Then run:

```text
A>ATOM HELLO

HELLO.COM written
A>HELLO

HELLO FROM ATOM
```

`ATOM HELLO.ASM MADE.COM` selects a different output name. The output extension
can be `.COM`, `.BIN`, `.HEX` or `.ASO`. BIN and COM contain the same flat bytes.
ASO contains the ordered image and patch operations for a separate materialiser.
It is not an executable command. `ATOM` alone prints the usage line.

A third name asks for a symbol file:

```text
A>ATOM HELLO HELLO.COM HELLO.SYM
```

The type defaults to `.SYM` and cannot be anything else. Each line holds a
global symbol's value in four hex digits, a space and its name, in the order
Atom first met the names. Debuggers such as SID and ZSID load this format.
Private labels are not included. The Node `.sym` output is byte-for-byte the
same text. Atom writes the symbols to `HELLO.$$S` while it still has them,
then renames that to `HELLO.SYM` once the output is published. A failed build
leaves any earlier symbol file as it was.

CP/M names are current-drive 8.3 names. Includes use quoted names such as
`%INCLUDE "MATH.ASM"`. Directory paths, drive prefixes and wildcards are rejected.
Include and definition names are case-insensitive.

Atom accepts 32 numeric definitions with names up to 17 characters and 16
levels of conditions on both hosts. A condition is a literal or a previously
defined name. Values accept decimal, `$` hexadecimal, `%` binary and Intel `H`
or `B` suffixes. Includes nest up to eight files deep. Each CP/M `INCBIN` needs
an explicit count and a current-drive 8.3 filename.

A build accepts up to 255 source files of at most 65,535 bytes each.
The CP/M assembler requires BDOS at `$E400` or higher. It checks that boundary
before using its workspace. COM and BIN can span 65,280 bytes from `$0100`
to `$10000`, subject to available disk space.

CP/M files occupy complete 128-byte records. BIN and COM have zero padding in
the last record. HEX uses `$1A` padding after its end record.

### Interrupted builds

For `NAME.COM`, Atom assembles into `NAME.$$B` and writes the finished image to
`NAME.$$$`. During replacement, the old `NAME.COM` is moved to `NAME.$$B` until
the new file is in place. Successful builds remove both work files. Assembly
and disk errors preserve the old destination where recovery succeeds.

A reset can leave either work file behind. The next build stops and names it.
Check `NAME.$$B` before erasing it: it may contain the only copy of the previous
output. Atom leaves an editor's `NAME.BAK` alone.

## Errors

An assembly error names the source file, line and column. For `LD A,MISSING`
on line 2:

```text
main.asm:2:6: undefined symbol MISSING
```

Lines and columns start at one. Included-file errors name the included file,
and errors after a `%LINE` name the file and line it gives.
A malformed `%` directive is reported at its line as an invalid source
directive, and an unclosed `%IF` at the end of its file.
A failed forward reference points to the instruction that used it and can also
name the line that defined its target.

## Macros

Atom has no macros of its own. `atompp prog.mac` expands the macros in
`prog.mac` and writes `prog.asm`, which Atom then assembles. Errors in the
result name the lines of `prog.mac` and its macro files.
[ATOMPP](atompp.md) describes the macro language.

## Converting older source

`azm-to-atom source.asm` converts the supported AZM syntax to `source.atom.asm`.
It converts dotted data directives, underscore locals, numeric prefixes and
`LSB`/`MSB` calls. An existing output is preserved. `--stdout` prints the result
and `--output` selects another destination.

Macros, typed layouts and AZM includes or conditions need manual rewriting.
An unsupported construct produces a positioned error and no output file.
The converter does not run AZM.

## Assembling Atom itself

`atom self-host` assembles the native sources shipped in the installed package.
It writes `build/atom.bin`. Another output path can follow `self-host`.
Project, target and definition options are disabled for this fixed source build.

On CP/M, Atom can assemble its own `ATOM.COM`. Copy every file from `src/z80`
and `ATOM.COM` to one drive, then run:

```text
A>ATOM CPM22 NEWATOM.COM
```

`cpm22.asm` lists the CP/M build in assembly order. `atom.asm` is the root of
the native core that the Node host runs. Both include `core.asm`. The sources
take about 1.1 MB, so the build needs a drive larger than an 8-inch floppy,
such as a Triptych 2 MB disk. The result is byte-for-byte the `ATOM.COM` that
`npm run build` produces.
