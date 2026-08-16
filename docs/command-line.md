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

The package also contains Atom's generated native-valid source. This command
assembles that source with the installed native core and writes
`build/atom.atom/current/atom.bin` in the current directory:

```sh
atom --self-host
```

The result is 13,058 bytes and must match the pinned core byte for byte.
`--self-host` accepts only `-o`/`--output`, so origin, capacity, fill, entry,
and preprocessor overrides cannot change the proof build.
Maintainers regenerate the checked source with
`npm run build:self-host-source`; `npm run verify:self-host-source` detects
drift from the readable implementation under `asm/`.

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

The host resolves `%INCLUDE` paths relative to each importing file. Included
files remain separate source parts and appear before their importer in the
native input order. `%DEFINE` and `%IF` evaluation happens before Atom receives
the equal-length masked source.

Project definitions use `-D`:

```sh
atom --origin $4000 -DDEBUG -DMODE=2 src/main.asm
```

Shells normally expand `$4000`; quote or escape that spelling when necessary,
or use `4000H`. Command-line numbers accept decimal, `$` hexadecimal, `%`
binary, and Intel `H` and `B` suffixes.

## Shipped example

The package includes `examples/hello`. From that directory:

```sh
atom --origin 4000H main.asm
```

The host selects and resolves `layout.asm` from the preprocessing header. The
native core then emits an exact 19-byte image beginning at `$4000`, including a
forward branch patch and both initialized and uninitialized `DS` storage.
Maintainers can reproduce the checked result without publishing files into the
checkout:

```sh
npm run verify:example
```

## Options

```text
-o, --output <dir>       artifact bundle
--root <dir>             project root
--origin <number>        initial target address
--capacity <number>      target byte capacity
--entry <number>         entry address recorded in NOBJ and D8
--fill <number>          binary/HEX gap and DS fill byte
--self-host              assemble the checked Atom source shipped in the package
-DNAME[=value]           host preprocessor definition
-h, --help               command help
```

Atom currently accepts bank zero only. The native descriptor represents a
non-wrapping half-open range whose end is no greater than `$FFFF`, so a target
starting at zero has a maximum capacity of 65,535 bytes. Each native source
part must fit the 24 KiB source window, with at most 16 ordered parts. The Mac
adapter pages parts through that window at part boundaries. Atom's self-host
build uses six parts and does not retain the whole 93,933-byte source stream in
Z80 RAM.

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

## Maintainer release gate

```sh
npm run release:check
```

This runs the complete native and host tests, strict register-contract build,
offline package/install proof, example proof, and two-generation self-host
measurement. `npm publish` invokes the same command through `prepublishOnly`.
See [`release-checklist.md`](release-checklist.md) for the repository and
licensing checks that require network or publishing authority.
