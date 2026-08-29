# Atom command-line assembler

The `atom` command prepares a project, runs the native Z80 assembler, renders
the requested files, and publishes them. Node.js 20 or later is required.

## Basic use

Name one root source file:

```sh
atom src/main.asm
```

With no output path, Atom writes one file:

```text
build/main.bin
```

Source `ORG` directives determine placement. The flat BIN begins at the lowest
generated or reserved address, so an `ORG 4000H` program does not acquire a
16 KiB zero prefix.

Name the outputs you want after the input:

```sh
atom src/main.asm build/main.bin build/main.hex
atom src/main.asm build/main.nobj build/main.lst build/main.d8.json
atom --target cpm22 src/main.asm build/main.com
atom src/main.asm build/main.com
```

Each path selects one format by suffix. Atom recognizes `.bin`, `.hex`, `.com`,
`.nobj`, `.lst`, and `.d8.json`, without case sensitivity. A command cannot
repeat a format or destination path. Atom renders and stages every requested
file before replacing an earlier output; a failed build publishes none.

Output selection is affirmative: Atom writes the files you name. There is no
default bundle of artifacts to suppress with negative switches. If you want
only HEX, name only a `.hex` path. If you want BIN, listing, and D8, name those
three paths.

## Includes, conditions, and binary data

The Node preparation stage resolves `%INCLUDE` relative to the importing file.
Each exact source identity is imported once, including repeated direct imports
and dependency diamonds. Included files remain distinct source parts and are
assembled before their importer.

Use `-D` for command definitions:

```sh
atom -DDEBUG -DMODE=2 src/main.asm build/main.bin
```

Values accept decimal, `$FFFF`, `%1010`, `0FFFFH`, and `1010B` forms. Quote or
escape `$` forms when the shell would expand them.

`INCBIN` paths are relative to the containing source file:

```asm
FONT: INCBIN "assets/font.bin"
```

Source and binary paths are confined to the project root, checked for exact
case, and snapshotted before assembly.

## Node project files

A JSON project records repeatable desktop build policy:

```json
{
  "assembler": "atom",
  "entry": "src/main.asm",
  "target": "cpm22",
  "outputs": ["build/main.com", "build/main.d8.json"],
  "definitions": {
    "DEBUG": 0
  }
}
```

Run it with:

```sh
atom --project atom.json
```

Project paths are relative to the JSON file. Command output paths replace the
project output list, and command definitions override project definitions:

```sh
atom --project atom.json -DDEBUG=1 build/debug.com
```

The `assembler` field is optional for the `atom` command, but shared `.asm`
projects should set it to `atom`. The command rejects `azm` instead of choosing
a source format from the filename.

JSON belongs to the Node-hosted frontend. Native CP/M and TEC profiles do not
contain a JSON parser.

## Targets and COM files

The built-in targets are `generic` and `cpm22`. The generic target starts at
zero and leaves placement to source `ORG` directives. The `cpm22` target starts
and enters at `$0100`.

A COM file has no header. Atom therefore accepts `.com` only when the rendered
load base and entry are both `$0100`, the output is flat bank zero, and the
image fits the CP/M address range. If no target is named, a `.com` output
selects the `cpm22` target. An explicit incompatible target or source placement
is an error; choosing a suffix never silently moves labels.

## Self-hosting

The installed package contains Atom's authoritative native sources. Assemble
them with:

```sh
atom self-host
```

The default output is `build/atom.bin` in the current directory. Another
positive output path can be supplied after `self-host`. Project, target, and
definition options are disabled for this fixed proof build.

## Options

```text
-p, --project FILE     Node project file
-t, --target NAME      generic or cpm22
-DNAME[=VALUE]         preprocessor definition; default value 1
-h, --help             command help
-V, --version          package version
```

Invalid command syntax returns status 2. Preparation, assembly, rendering, or
publication failure returns status 1. Success, help, and version return zero.
Diagnostics go to standard error; successful output paths go to standard
output.

## Native CP/M command

The native CP/M image uses the smaller positional form:

```text
ATOM
ATOM SOURCE
ATOM SOURCE OUTPUT.COM
ATOM ?
```

`ATOM` reads `INPUT.ASM` and writes `OUTPUT.COM`. `ATOM HELLO` reads
`HELLO.ASM` and writes `HELLO.COM`. Native source composition uses leading
`%INCLUDE` directives. Native profiles do not parse project JSON.

See [Native Atom on CP/M 2.2](cpm22.md) for its filesystem rules, limits, and
transactional COM publication.
