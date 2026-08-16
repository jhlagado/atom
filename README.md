# atom

`atom` is a single-pass streaming assembler for the Z80, written in Z80
assembly. It targets a TEC-1 and is intended to assemble its own source in less
than 16 KiB of resident code and immutable data.

Phase 1 contains the parsed-instruction encoder, its case-insensitive RADIX-40
mnemonic recognizer, and host-side differential proofs against AZM. Phase 2a
adds the measured symbol and pending-reference core. Phase 2b adds the measured
streaming tokenizer. Phase 2c adds the native concrete instruction parser and
proves the complete tokenizer-to-encoder path. Phase 2d adds the measured
constant-expression evaluator and its forward-symbol handoff. Phase 2e
connects expressions to instruction operands and proves their pending
patch metadata. Phase 2f submits instruction image bytes and final patch bytes
through the Nucleus operating-adapter boundary. Phase 2g adds the native
statement layer: global and `_`-private labels, bare `EQU`, `ORG`, `DB`, `DW`,
and `DS`, data strings, and append-only forward patches. Phase 3 adds the
native multipart driver, exact final undefined-symbol diagnostics, and sink
begin/commit/abort lifecycle. Phase 4 connects the source packager to that
driver through Debug80, so a Mac host now runs preprocessing and dependency
resolution before the emulated Z80 core performs the assembly. Phase 5 pins
that core, adds the installed command, renders delivery and debugging formats,
and publishes each artifact set atomically. Phase 6 adds a deterministic
Atom-syntax form of the complete native source and proves two generations of
native self-assembly against AZM.

The host source packager resolves `%include`, immutable `%define` values,
and host-evaluated `%if`/`%else`/`%endif`; preserves source identities and
offsets through equal-length masking; joins path-keyed placement; and emits a
validated SP1 source plan. The installable Mac command now executes the pinned
native core and publishes deterministic NOBJ, binary, Intel HEX, listing, and
D8 artifacts. Native self-assembly is proved. The TEC-1 filesystem and output
adapter remains to be implemented. Macros and op expansion remain out of
scope.

```sh
npm install
npm pack
npm install --global ./atom-z80-0.1.0.tgz
atom --origin 4000H src/main.asm
atom --self-host
```

The command writes one atomic bundle under `build/<name>.atom/current`. See
[`docs/command-line.md`](docs/command-line.md) for options and output paths.

```sh
npm install
npm test
npm run measure
npm run measure:symbols
npm run measure:tokenizer
npm run measure:parser
npm run measure:expression
npm run measure:integration
npm run measure:output
npm run measure:statements
npm run measure:driver
npm run measure:host-native
npm run measure:self-host
```

The local AZM oracle is frozen in [`docs/phase-1-authorities.md`](docs/phase-1-authorities.md).
The Phase 2a decisions and measurements are in
[`docs/phase-2a-report.md`](docs/phase-2a-report.md).
The Phase 2b tokenizer contract and measurements are in
[`docs/phase-2b-report.md`](docs/phase-2b-report.md).
The Phase 2c parser contract and measurements are in
[`docs/phase-2c-report.md`](docs/phase-2c-report.md).
The Phase 2d expression contract and measurements are in
[`docs/phase-2d-report.md`](docs/phase-2d-report.md).
The Phase 2e symbolic-parser contract and measurements are in
[`docs/phase-2e-report.md`](docs/phase-2e-report.md), with its public metadata
layout in [`docs/symbolic-parser-abi.md`](docs/symbolic-parser-abi.md).
The Phase 2f output contract and measurements are in
[`docs/phase-2f-report.md`](docs/phase-2f-report.md), with its native ABI in
[`docs/output-abi.md`](docs/output-abi.md).
The Phase 2g statement syntax, ABI, proof coverage, and measurements are in
[`docs/statements-abi.md`](docs/statements-abi.md) and
[`docs/phase-2g-report.md`](docs/phase-2g-report.md).
The native multipart and lifecycle ABI and its measurements are in
[`docs/native-driver-abi.md`](docs/native-driver-abi.md) and
[`docs/phase-3-report.md`](docs/phase-3-report.md).
The host preparation contract, limits, and proof map are in
[`docs/host-source-packaging.md`](docs/host-source-packaging.md).
The Mac host/native API, memory layout, diagnostics, and measurements are in
[`docs/mac-host-integration.md`](docs/mac-host-integration.md) and
[`docs/phase-4-report.md`](docs/phase-4-report.md).
The installed command, artifact publication model, and measurements are in
[`docs/command-line.md`](docs/command-line.md) and
[`docs/phase-5-report.md`](docs/phase-5-report.md). Atom's flat NOBJ profile is
specified in [`docs/atom-object-format.md`](docs/atom-object-format.md).
The generated native source and first/second-generation byte proof are
described in [`docs/phase-6-report.md`](docs/phase-6-report.md).

## License

Atom is licensed under the GNU General Public License, version 3 only
(`GPL-3.0-only`).
