# Atom

Atom is a single-pass Z80 assembler written in Z80. It runs on CP/M 2.2 and
as a desktop command through a Z80 emulator. Both use the same assembler
core.

On the desktop, Node.js 20 or later is required:

```sh
npm install --global atom-z80
atom main.asm
```

This writes `build/main.bin`. Other output formats include Intel HEX, CP/M COM,
listings and Debug80 D8 maps.

For CP/M, copy [ATOM.COM](assets/atom-cpm22.com) to your disk and run
`ATOM HELLO` to assemble `HELLO.ASM`. The [download site](https://jhlagado.github.io/atom/)
also has a disk image that runs in Triptych.

## Guides

- [Using Atom](docs/using-atom.md): a first program, output files and CP/M usage
- [The language](docs/language-reference.md): labels, expressions and directives
- [The Node API](docs/programming-api.md): assembly from JavaScript

## Building

From a source checkout:

```sh
npm install
npm run build
npm test
```

`npm run verify:build` rebuilds and compares the checked-in native images.
`npm pack` creates an installable Node package.

The release scripts prepare the CP/M downloads, Triptych disk and Pages site.
`npm run release:check` checks the build and tests before a version tag triggers
the GitHub release workflow. `npm publish` runs the same checks before publishing
the desktop package.

Atom's human-authored work is licensed under [GPL-3.0-only](LICENSE).
The [authorship and LLM transparency policy](AUTHORSHIP) describes tool use
and the treatment of generated material.
