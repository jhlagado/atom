# Atom

Atom is a single-pass Z80 assembler whose assembler core is written in Z80
assembly. The desktop command runs that core through Debug80, while Node handles
files, conditional preprocessing, and finished artifacts.

Atom assembles the complete Z80 instruction set, including CB, ED, DD, FD,
index-half, and undocumented SLL/SLS forms. It also supports global and
`.`-private labels, expressions, `EQU`, `ORG`, `DB`, `DW`,
`DS`, `ALIGN`, `CSTR`, `PSTR`, `ISTR`, character literals, and `LOW()` and
`HIGH()` byte functions. The Node host also supplies confined `INCBIN` input.
The native core assembles its own checked source byte for byte and fits in one
16 KiB bank.

The desktop command is available through npm. Native CP/M 2.2 Atom runs as a
Z80 transient program and accepts `ATOM SOURCE OUTPUT`, with
`INPUT.ASM` and `OUTPUT.COM` as the no-argument defaults. `ATOM HELLO` derives
`HELLO.ASM` and `HELLO.COM`; an explicit output may end in `.COM`, `.BIN`, or
`.HEX`. Leading `%INCLUDE` directives form a dependency graph of up to 255
CP/M 8.3 source names, with a 65,535-byte boundary for every part. The native
named-object harness and TECM8 source and transactional output providers now
exist. The complete TecMate launcher, include resolver, and target memory map
remain deployment work.

## Install and assemble

Node.js 20 or later is required.

```sh
npm install --global atom-z80
```

Assemble an entry file from its project root. With no explicit output, Atom
writes `build/main.bin`:

```sh
atom src/main.asm
```

Request additional formats with positive output paths:

```sh
atom src/main.asm build/main.bin build/main.hex build/main.d8.json
atom --target cpm22 src/main.asm build/main.com
```

The shipped example exercises host conditionals and dependency resolution,
then native labels, instructions, data, reservations, and a forward patch:

```sh
cd examples/hello
atom main.asm
```

See [the command-line guide](docs/command-line.md) for every option and
[the language reference](docs/language-reference.md) for source syntax. The
[Atom engineering manual](docs/codebase/index.md) gives a guided tour of the
host, native core, public interfaces, generated files, and proof system.

## Build boundary

The host resolves `%INCLUDE`, immutable `%DEFINE` values,
`%IF`/`%ELSE`/`%ENDIF`, and `INCBIN` paths. It keeps included files as separate
ordered parts and preserves exact line and byte positions while masking or
lowering host-owned syntax.

The Z80 core then performs tokenization, symbol handling, expression parsing,
directive processing, instruction encoding, forward-patch decisions, final
undefined checks, and output lifecycle control. Filesystem access, dependency
graphs, listings, D8 maps, Intel HEX, and transactional file publication stay
outside the resident assembler.

This is a two-stage build, not a two-pass assembler. The native core reads the
prepared source once. Forward references become append-only PATCH records when
their final values are known.

The measured native account is:

| Item | Bytes |
| --- | ---: |
| Code and immutable tables | 11,682 |
| Fixed workspace | 714 |
| Linked resident extent | 12,396 |
| Margin below 16 KiB | 3,988 |

The optional Z80 named-object harness replaces the memory source fallback and
host sink stubs. That composition is 13,515 resident bytes and uses 399 bytes
of caller-owned common workspace, leaving 2,873 bytes in its 16 KiB bank.
An immutable-bank profile instead places 12,770 bytes of code and tables in ROM
and relocates 741 bytes of fixed state to common RAM.

[Architecture](docs/architecture.md), [limits](docs/limits.md), and the
[CP/M adapter report](docs/cpm22.md) separate the measured host and native CP/M
configurations from the remaining [TEC-1 adapter work](docs/tec-1-deployment.md).
The [private tool-service boundary](docs/tool-services.md) records how Node,
CP/M, Debug80, and later providers sit beneath the unchanged resident core.

## Correctness

Atom's proof suite covers all 3,445 supported instruction forms, invalid forms,
register contracts, exact stack and memory effects, directive and symbol
programs, host preprocessing, artifact publication, offline package
installation, and two native self-assembly generations.

Run the maintainer gate with:

```sh
npm run release:check
```

The authoritative native source is under `native/` with an exact long-to-short
symbol ledger. Atom assembles that source into the pinned core. Every subsystem
proof executes the checked core directly; the repository retains no second
native implementation or one-way source generator. `npm run
verify:native-source` rebuilds the core from the authoritative sources and
compares the complete result. See the
[self-hosting design](docs/self-hosting.md).

The detailed engineering record remains available in the phase reports:

- [encoder measurement](docs/phase-1-report.md)
- [symbols through statements](docs/phase-2g-report.md)
- [native multipart driver](docs/phase-3-report.md)
- [desktop host integration](docs/phase-4-report.md)
- [CLI and artifacts](docs/phase-5-report.md)
- [native self-hosting](docs/phase-6-report.md)
- [product and release checkpoint](docs/phase-7-report.md)
- [source-syntax checkpoint](docs/phase-8-report.md)
- [equates, characters, and strings](docs/phase-9-report.md)
- [alignment and byte functions](docs/phase-10-report.md)
- [host-backed binary inclusion](docs/phase-11-report.md)
- [native compression audit](docs/native-compression-audit.md)
- [native CP/M 2.2 vertical slice](docs/cpm22.md)

## License

Atom is public software licensed under the GNU General Public License, version
3 only (`GPL-3.0-only`).
