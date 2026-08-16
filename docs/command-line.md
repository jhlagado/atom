# Atom command-line assembler

The `atom` command runs the host preprocessor and the native Z80 assembler,
then publishes a complete artifact set. Node.js 20 or later is required on the
Mac. AZM is a development dependency and is absent from the installed Atom
package.

## Installation

From an Atom checkout:

```sh
npm install
npm pack
npm install --global ./atom-z80-0.1.0.tgz
```

The package bundles the Debug80 Z80 runtime used to execute Atom's native core.
The core itself is the checked `assets/native-core.json` image. Its SHA-256 is
verified before execution. Maintainers regenerate it with
`npm run build:native-core`; `npm run verify:native-core` fails when source and
the checked image differ.

## Basic build

Run Atom from the project root and name the entry source:

```sh
atom --origin 4000H src/main.asm
```

The default bundle is `build/main.atom`. The `current` symlink inside that
directory names the committed generation:

```text
build/main.atom/current/main.nobj
build/main.atom/current/main.bin
build/main.atom/current/main.hex
build/main.atom/current/main.lst
build/main.atom/current/main.d8.json
build/main.atom/current/manifest.json
```

The host resolves `%include` paths relative to each importing file. Included
files remain separate source parts and appear before their importer in the
native input order. `%define` and `%if` evaluation happens before Atom receives
the equal-length masked source.

Project definitions use `-D`:

```sh
atom --origin $4000 -DDEBUG -DMODE=2 src/main.asm
```

Shells normally expand `$4000`; quote or escape that spelling when necessary,
or use `4000H`. Command-line numbers accept decimal, `$` hexadecimal, `%`
binary, and Intel `H` and `B` suffixes.

## Options

```text
-o, --output <dir>       artifact bundle
--root <dir>             project root
--origin <number>        initial target address
--capacity <number>      target byte capacity
--entry <number>         entry address recorded in NOBJ and D8
--fill <number>          binary/HEX gap and DS fill byte
-DNAME[=value]           host preprocessor definition
-h, --help               command help
```

Atom currently accepts bank zero only. The native descriptor represents a
non-wrapping half-open range whose end is no greater than `$FFFF`, so a target
starting at zero has a maximum capacity of 65,535 bytes. The native source
window is 24 KiB, with at most 16 ordered source parts.

## Artifact publication

The publisher writes an immutable generation directory, synchronizes every
file and directory entry, then replaces one `current` symlink with an atomic
rename. A build or publication error leaves the previous `current` generation
selected. The manifest records each filename, byte count, and SHA-256. Existing
content-addressed generations are verified before reuse.

Consumers should open files through `current`; generation directories are an
implementation detail. Atom retains old generations so no successful build is
removed during publication. Automatic pruning is not implemented yet.

## Diagnostics

Native source failures use the original logical path, line, and byte column:

```text
lib/device.asm:14:9: undefined symbol PORTBASE
```

Dependency and preprocessing failures also occur before artifact publication.
No `current` directory is created for a failed first build, and a failed later
build leaves the previously selected generation unchanged.
