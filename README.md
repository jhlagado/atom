# Atom

Atom is a single-pass Z80 assembler. Its assembler core is written in Z80 and
runs as a desktop command or as a native CP/M 2.2 program.

Atom supports the complete Z80 instruction set, global and private labels,
expressions and the usual code and data directives. It can write BIN, Intel HEX,
CP/M COM, NOBJ, listing and Debug80 D8 files.

## Desktop

Atom requires Node.js 20 or later.

```sh
npm install --global atom-z80
atom main.asm
```

With no explicit output, Atom writes `build/main.bin`. Name additional outputs
on the command line:

```sh
atom main.asm build/main.bin build/main.hex
```

## CP/M

Download [ATOM.COM](https://github.com/jhlagado/atom/releases/latest/download/ATOM.COM)
from the latest release and copy it to a CP/M disk.

```text
A>ATOM HELLO
HELLO.COM written
```

This reads `HELLO.ASM` and writes `HELLO.COM`. An explicit output name may end
in `.COM`, `.BIN` or `.HEX`.

## Documentation

- [Atom books and reference](https://debug80.com/atom/)
- [Command-line guide](docs/command-line.md)
- [Language reference](docs/language-reference.md)
- [Building and contributing](docs/codebase/index.md)

Atom is licensed under [GPL-3.0-only](LICENSE).
