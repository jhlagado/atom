# Development and release guide

Atom's Z80 source is both production code and an explanation of a small native
assembler. Changes must preserve that explanation as well as the executable.

## ASO spool and replay

The [internal ASO spool format and implementation notes](aso-format.md)
describe Atom's ordered IMAGE/PATCH stream. Node provides the streaming codec
and the CP/M program uses a temporary spool before materialising COM, BIN or
HEX in sequential 33,280-byte windows. ASO is not a selectable final output.
The current CP/M executable is 19,191 bytes, with 17,251 bytes of resident
code and 1,940 bytes of spool code after it. CP/M loads the payload in 150
records; nine bytes pad the file to the record boundary at `$4C00`. The
uninitialised workspace begins at `$5400`, so it is outside the COM payload
with 2 KiB between the loaded record boundary and workspace. The measured
minimum TPA is 58,112 bytes with BDOS at `$E400`. These emulator measurements
do not establish physical floppy performance. Refresh them with
`npm run measure:cpm22` after any native change.

## Assembly source style

Begin each module with its purpose, public calling convention, errors, memory
ownership and reentrancy limits. Give every public entry a brief summary.
Routine contracts use `;@ROUTINE` and call-site expectations use
`;@EXPECTOUT` because the proof tools read those annotations.

Put the routine summary next to its contract, followed by one blank line and
the global label:

```asm
;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return carry set when A is one of the eight bit-number operand classes.

EN_IBIND:
    CP   EN_BIT0                 ; Compare with the first accepted class.
    JR   C,AT_PNO                ; Reject a value below the range.
    CP   EN_BIT7+1               ; Compare with the exclusive upper bound.
    RET                          ; Carry reports the range test.
```

Use these layout rules throughout `src/z80/`:

- labels and named `EQU` definitions begin at column one
- instructions, unlabelled data and directives are indented by four spaces
- full-line comments and proof annotations begin at column one
- a blank line separates routines and distinct instruction groups
- source lines should normally fit within 78 columns
- filenames should be short, concrete and readily usable on small systems

Align inline comments within a module. In the CP/M adapter the semicolon starts
at column 29 when the instruction fits. Allow two spaces after a longer operand
instead of forcing its comment into the next column group.

Inline comments should explain the program state, not restate the opcode.
Document the value loaded into a register, the condition behind a branch, the
meaning of carry and each change in a register's role. Dense arithmetic should
have near-continuous commentary. A few obvious instructions may share one
explanation when they form a single operation.

Every workspace declaration needs its unit and purpose. For loops, state the
register roles at the loop head and the invariant that makes each memory access
safe. Comments affected by a code change are part of that change.

For a comment-only edit, assemble with Atom and compare executable bytes and
symbol values with the preceding source. Line offsets may change. Machine code
and symbol addresses may not.

## Tests

Run the narrowest useful test while editing. Use the full suite for changes to
the assembler or its host interfaces:

```sh
node --test test/parser.test.mjs
npm test
```

Native tests check the return address, stack, preserved registers, memory
guards, immutable ranges and complete write set as well as the returned status.
The main test lanes are:

| Tests | Boundary |
| --- | --- |
| `encoder`, `symbols`, `tokenizer`, `expression`, `parser` | Native language machinery |
| `output`, `statements`, `integration`, `driver` | Native output and complete build lifecycle |
| `host-atom-*`, `host-resolver`, `host-incbin` | Host source preparation |
| `host-native-atom-runner` | Prepared source through the Z80 core |
| `host-artifacts` | NOBJ, BIN, COM, HEX, listing and D8 |
| `cpm22`, `host-cpm-*` | Native CP/M command and files |
| `native-object-harness`, `named-object-services` | Portable Z80 service adapter |
| `host-package`, `host-release` | Installed package and release contents |
| `host-self-host` | Two executable Atom generations |

The full suite includes slow self-assembly, exhaustive instruction cases and
installed native-builder tests. It is an engineering check. Publishing the
Node package uses the smaller package check described below.

The measurement commands report current code, workspace and execution costs:

```sh
npm run measure
npm run measure:host-native
npm run measure:self-host
npm run measure:cpm22
```

Update a checked measurement only from a fresh run against the current linked
image.

## Generated runtime files

Edit native source under `src/z80/`. Rebuild the affected file with:

```sh
npm run build:native-core
npm run build:native-object
npm run build:cpm22
```

The matching `verify:*` commands rebuild in check mode and report drift. Do not
edit generated images or proof JSON by hand to make a failing check pass.

## Node package checks

`npm publish` automatically runs `npm run publish:check`. This checks dependency
versions and release metadata, packs the archive, installs it offline in a
temporary directory and exercises the installed CLI and public API. A short
program checks forward references and BIN, COM, HEX and D8 output. A rejected
source checks diagnostics and preservation of an existing output.

Run the same check before publishing:

```sh
npm run publish:check
```

`npm pack` checks the hashes and sizes of the existing runtime assets and
bundles dependencies. Neither command rebuilds the assembler or runs
self-host proofs. Packing verifies artifact integrity, not that edited Z80
source matches those artifacts. After a native source change, rebuild the
affected assets and run the full release check before publishing them.

| Command | Use |
| --- | --- |
| `npm run publish:check` | Verify the installable Node package |
| `npm test` | Run all development tests, including slow native proofs |
| `npm run release:check` | Qualify a complete release with native rebuild checks and measurements |

## Full release qualification

Run the release gate from a clean checkout:

```sh
npm run release:check
npm run verify:package-census
```

The gate runs the native and host suites, including the native-core rebuild,
offline package installation and self-host proofs. It also explicitly checks
the object harness and CP/M builds and runs the host-native and self-host
measurements. It must finish without changing a checked asset or proof record.
This gate remains mandatory for a version tag and runs in GitHub Actions.

Before tagging a release:

1. Confirm `main` is current with its remote and the working tree is clean.
2. Confirm `package.json` has the intended version.
3. Prepare the versioned Triptych image and run its verification.
4. Inspect `npm pack --dry-run` and the package census.
5. Run the release gate.
6. Tag the exact commit as `v<version>`.

Pushing the tag creates a GitHub release with the CP/M executable, manifest
and checksums, then deploys the matching Triptych image and download page to
GitHub Pages. This workflow does not publish the npm package. The package
version is prepared in the release commit. `npm publish` remains a separate
manual step with the smaller Node package check, so it does not repeat the
full qualification suite.

If the packaged files changed deliberately, refresh the census only after the
file set is final:

```sh
npm run update:package-census
npm run verify:package-census
```

Pushing the version tag runs `.github/workflows/release.yml`. The workflow
publishes `ATOM.COM`, `ATOM.manifest.json` and `SHA256SUMS` after repeating the
release checks.

### Triptych release image

Each release also has a versioned two-MiB CP/M image on the Atom Pages site.
Prepare it before tagging, using a clean Triptych checkout containing the
pinned N04 resident image:

```sh
TRIPTYCH_ROOT=/path/to/triptych npm run prepare:triptych-release
npm test
```

Commit the generated `site/releases/<version>/atom.img`, its `system.json`
descriptor, `disk-contents.json`, and the updated `site/index.html` with the
release candidate. The image contains the Triptych N04 system, the exact
`ATOM.COM` from the checked census, verified `EDIT.COM`, and the `HELLO.ASM`
example with a `HELLO.COM` assembled by Atom. The contents manifest records
the image files, sizes, checksums and Edit source provenance. The release
workflow adds the official GitHub release files to the same versioned directory
and deploys the complete site. The stable page is
`https://jhlagado.github.io/atom/`; its Triptych link opens the descriptor from
that release directory. Published version directories are immutable. The
separate Pages workflow can redeploy the current site on demand.
