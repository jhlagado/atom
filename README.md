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
through the Nucleus operating-adapter boundary.

The host source packager now resolves `%include`, immutable `%define` values,
and host-evaluated `%if`/`%else`/`%endif`; preserves source identities and
offsets through equal-length masking; joins path-keyed placement; and emits a
validated SP1 source plan. Native labels and directives, the multipart assembly
driver, sink lifecycle, and final artifacts remain to be implemented. Macros
and op expansion remain out of scope.

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
The host preparation contract, limits, and proof map are in
[`docs/host-source-packaging.md`](docs/host-source-packaging.md).

## License

Atom is licensed under the GNU General Public License, version 3 only
(`GPL-3.0-only`).
