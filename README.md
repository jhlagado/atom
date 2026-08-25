# Atom

Atom is a single-pass Z80 assembler whose assembler core is written in Z80
assembly. The Mac command runs that core through Debug80, while the host handles
files, conditional preprocessing, and finished artifacts.

Atom assembles the complete Z80 instruction set claimed by its AZM oracle,
including CB, ED, DD, FD, index-half, and undocumented SLL/SLS forms. It also
supports global and `.`-private labels, expressions, `EQU`, `ORG`, `DB`, `DW`,
`DS`, `ALIGN`, `CSTR`, `PSTR`, `ISTR`, character literals, and `LOW()` and
`HIGH()` byte functions. The Mac host also supplies confined `INCBIN` input.
The native core assembles its own checked source byte for byte and fits in one
16 KiB bank.

The Mac command is usable now. The TEC-1 filesystem, source-service, and output
adapter is designed but not yet implemented.

## Install and assemble

Node.js 20 or later is required.

```sh
npm install
npm pack
npm install --global ./atom-z80-0.1.0.tgz
```

Assemble an entry file from its project root:

```sh
atom --origin 4000H src/main.asm
```

Migrate a source file from AZM's byte-preserving common subset:

```sh
azm-to-atom source/main.asm
```

The converter writes `source/main.atom.asm`. It reports an error instead of guessing
when an AZM construct has no Atom equivalent. The
[AZM conversion guide](docs/azm-to-atom.md) lists every direct mapping and
rejected boundary.

Atom publishes one immutable bundle under
`build/main.atom/current` containing:

```text
main.nobj
main.bin
main.hex
main.lst
main.d8.json
manifest.json
```

The shipped example exercises host conditionals and dependency resolution,
then native labels, instructions, data, reservations, and a forward patch:

```sh
cd examples/hello
atom --origin 4000H main.asm
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
graphs, listings, D8 maps, Intel HEX, and atomic publication stay outside the
resident assembler.

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

[Architecture](docs/architecture.md), [limits](docs/limits.md), and the
[TEC-1 deployment design](docs/tec-1-deployment.md) separate the measured Mac
configuration from the remaining hardware-adapter work.

## Correctness

Atom's test suite uses AZM as an independent oracle. The proof covers all 3,445
claimed instruction forms, invalid forms, register contracts, exact stack and
memory effects, directive and symbol programs, host preprocessing, artifact
publication, offline package installation, and two native self-assembly
generations.

Run the maintainer gate with:

```sh
npm run release:check
```

The authoritative native source is under `native/` with an exact long-to-short
symbol ledger. Atom assembles that source into the pinned core; the build also
translates the same prepared parts to AZM for strict register-contract and byte
comparison. Every subsystem proof executes the checked core directly; the
repository retains no second native implementation or one-way source generator.
`npm run verify:native-source` checks the complete authority path. See the
[self-hosting design](docs/self-hosting.md). AZM is a development oracle and is
not installed with the command-line package.

The detailed engineering record remains available in the phase reports:

- [encoder measurement](docs/phase-1-report.md)
- [symbols through statements](docs/phase-2g-report.md)
- [native multipart driver](docs/phase-3-report.md)
- [Mac host integration](docs/phase-4-report.md)
- [CLI and artifacts](docs/phase-5-report.md)
- [native self-hosting](docs/phase-6-report.md)
- [product and release checkpoint](docs/phase-7-report.md)
- [source-syntax checkpoint](docs/phase-8-report.md)
- [equates, characters, and strings](docs/phase-9-report.md)
- [alignment and byte functions](docs/phase-10-report.md)
- [host-backed binary inclusion](docs/phase-11-report.md)
- [native compression audit](docs/native-compression-audit.md)

## License

Atom is public software licensed under the GNU General Public License, version
3 only (`GPL-3.0-only`).
