# Chapter 6 — Verification and maintenance

[← Native core generation and self-hosting](05-native-core-generation-and-self-hosting.md) | [Manual](index.md)

Atom tests each native subsystem at its public entries, then tests the complete
build from source files to published artifacts. A native test checks more than
the returned status: it also checks the return address, stack, preserved
registers, memory guards, immutable ranges and the complete set of written
addresses.

## Test lanes

| Tests | Boundary |
| --- | --- |
| `encoder`, `symbols`, `tokenizer`, `expression`, `parser` | Native language machinery |
| `output`, `statements`, `integration`, `driver` | Native output and whole-build lifecycle |
| `host-atom-*`, `host-resolver`, `host-incbin` | Source preparation and host syntax |
| `host-native-atom-runner` | Prepared source through the Z80 core |
| `host-artifacts` | NOBJ, BIN, HEX, listing and D8 rendering |
| `cpm22`, `host-cpm-*` | Native CP/M command, files and publication |
| `native-object-harness`, `named-object-services` | Portable Z80 service adapter |
| `host-package`, `host-release` | Installed package and release policy |
| `host-self-host` | Two executable Atom generations |

Run the narrowest useful test while editing, then the complete gate before a
commit:

```sh
node --test test/parser.test.mjs
npm test
npm run release:check
```

## Native proof maps

The JSON files under `proofs/` are machine-read measurement and memory-map
inputs. The names retain the order in which the proof suites were introduced,
but they are active test data rather than project history.

Each memory profile accounts for all 65,536 addresses without gaps or overlaps.
Tests resolve symbolic boundaries from the checked core and distinguish code,
immutable tables, fixed workspace, caller buffers, guards, stack and unused
memory.

Native routines carry `;@ROUTINE` contracts. Selected call sites use
`;@EXPECTOUT`. These comments document register and flag expectations. Runtime
tests remain responsible for proving behaviour.

## Instruction set proof

`test/cases.mjs` generates the complete supported instruction corpus. The
encoder tests call `AtomFormLength` and `AtomEncode` directly for every valid
record, compare the exact bytes with fixed reviewed results and check that
invalid records change no output.

The checked census fixes the number and distribution of cases independently of
the generator. This prevents a deleted instruction family from appearing as a
successful smaller test run. New expected bytes or rejection decisions require
independent review rather than being copied from Atom's own output.

## Failure atomicity

The stateful tests deliberately fail at publication boundaries:

- Symbol tests fill arenas to their exact capacities.
- Parser tests reject malformed forms before publishing references.
- Output tests inject IMAGE, PATCH and sink failures.
- Statement tests preserve the outer status, nested status and source position.
- Driver tests distinguish failures before `begin` from failures that require
  one `abort`.
- File publication tests fail during staging and replacement, then verify that
  the previous output survives.

These checks matter because Atom streams its input and output. It cannot repair
partially published state by making another source pass.

## Measurements

The measurement commands report current code size, workspace and execution
costs:

```sh
npm run measure
npm run measure:symbols
npm run measure:tokenizer
npm run measure:expression
npm run measure:parser
npm run measure:output
npm run measure:statements
npm run measure:driver
npm run measure:host-native
npm run measure:self-host
npm run measure:cpm22
```

Do not update a checked measurement by hand from an older report. Run the
measurement against the current linked image and review both code bytes and
writable workspace.

## Generated files

Edit native code only under `src/z80/`. Rebuild generated artifacts with their
own commands:

```sh
npm run build:native-core
npm run build:native-object
npm run build:cpm22
```

The corresponding `verify:*` commands rebuild in check mode and reject drift.
The package census is updated only after the packaged files are final.

## Change sequence

1. Identify the module that owns the behaviour.
2. Add or select a test that distinguishes the intended result from a plausible
   wrong one.
3. Make one coherent change.
4. Run the narrow test and inspect the complete observable state.
5. Run the composed host or native lane.
6. Rebuild any generated artifact whose source changed.
7. Rerun affected size and execution measurements.
8. Update this manual when an interface, file owner or build flow changes.
9. Run `npm run release:check` before committing a release candidate.

The [release checklist](../release-checklist.md) covers repository, package and
GitHub release checks.
