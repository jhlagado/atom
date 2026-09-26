# Development and release guide

Atom's Z80 source is both production code and an explanation of a small native
assembler. Changes must preserve that explanation as well as the executable.

## Planned output work

The [ASO specification](aso-format.md) defines Atom's chronological IMAGE/PATCH
stream and its [implementation order](aso-format.md#8-implementation-order-and-acceptance).
The specification is merged, but the output changes are not yet implemented.
Begin with shared byte-exact vectors, then the ordered Node interface and an
explicit high-water result from native COMMIT. Follow with bounded CP/M disk
output and ASO replay, and finally move Node's normal outputs to the same
stream. Keep current output paths working and prove each step independently.

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

Run the narrowest useful test while editing. Run the complete gate before a
checkpoint:

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

## Release

Run the release gate from a clean checkout:

```sh
npm run release:check
npm run verify:package-census
```

The gate rebuilds the native core, object harness and CP/M program. It runs the
native and host suites, installs the packed npm archive offline and proves two
self-host generations. It must finish without changing a checked asset or proof
record.

Before tagging a release:

1. Confirm `main` is current with its remote and the working tree is clean.
2. Confirm `package.json` has the intended version.
3. Prepare the versioned Triptych image and run its verification.
4. Inspect `npm pack --dry-run` and the package census.
5. Run the release gate.
6. Tag the exact commit as `v<version>`.

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
descriptor, and the updated `site/index.html` with the release candidate. The
image contains the Triptych N04 system and the exact `ATOM.COM` from the checked
census. The release workflow adds the official GitHub release files to the same
versioned directory and deploys the complete site. The stable page is
`https://jhlagado.github.io/atom/`; its Triptych link opens the descriptor from
that release directory. Published version directories are immutable. The
separate Pages workflow can redeploy the current site on demand.
