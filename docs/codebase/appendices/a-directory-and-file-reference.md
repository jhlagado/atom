# Appendix A — Directory and file reference

[← Appendices](index.md) | [Build-flow reference →](b-build-flow-reference.md)

This appendix maps the files that implement, generate, execute, and prove Atom.
The narrative chapters explain how the files interact; this reference identifies
the owner of a behavior quickly.

## Top-level files

| File | Role |
| --- | --- |
| `README.md` | Product overview, installation, current capability, measured native account, and correctness summary |
| `package.json` | npm identity, public export, `atom` binary, package contents, dependencies, and verification scripts |
| `package-lock.json` | Reproducible Node dependency resolution |
| `LICENSE` | GPL-3.0-only license text |

## `asm/` native implementation

| File | Role |
| --- | --- |
| `atom-host-runtime.asm` | Complete origin-zero Mac-host link: selects full module modes, includes the native pipeline, and defines six fail-closed sink stubs |
| `atom-encoder.asm` | RADIX-40 packer, mnemonic binary search, form validation, length calculation, Z80 encoding rules, opcode tables, and four-byte commit buffer |
| `atom-symbols.asm` | Frozen bootstrap copy of exact packed symbols and pending-reference storage, retained by downstream legacy proof links |
| `atom-tokenizer.asm` | Frozen bootstrap copy of the tokenizer, retained by downstream legacy proof links |
| `atom-expression.asm` | Concrete and deferred expression parser, value/operator stacks, precedence reduction, arithmetic, and `LOW`/`HIGH` transforms |
| `atom-patch.asm` | Maps validated operand fields to byte offsets and patch kinds |
| `atom-parser.asm` | Mnemonic and operand parsing, ten-byte instruction record, concrete-value normalization, deferred reference preflight, and atomic parse commit |
| `atom-output.asm` | Target cursor, capacity, IMAGE emission, pending queueing, symbol patch resolution, `ORG`, and reservation operations |
| `atom-statements.asm` | Labels, optional-colon equates, bare directive recognition, instruction dispatch, data/string/storage/alignment handlers, and statement diagnostics |
| `atom-driver.asm` | Build-descriptor validation, multipart loop, final undefined checks, and sink begin/commit/abort lifecycle |
| `atom-abi.asmi` | External contracts supplied to AZM's strict register-contract analysis for cross-module native entries |
| `atom-mnemonics.inc` | Generated sorted packed mnemonic table |
| `atom-operands.inc` | Generated sorted packed operand-word table |

## `asm/` proof links

| File | Role |
| --- | --- |
| `encoder-proof.asm` | Direct encoder, recognizer, and RADIX-40 harness with guarded records and stack |
| `output-proof.asm` | Output, pending, encoder, and proof-sink harness |
| `statements-proof.asm` | Statement parser with source, symbol, pending, output, and sink regions |
| `driver-proof.asm` | Multipart build descriptor, source parts, arenas, sink lifecycle, and finalization proof |

## `src/` root

| File | Role |
| --- | --- |
| `src/abi.mjs` | JavaScript mnemonic and operand ordinals, parsed-record constructor, and reference RADIX-40 packer used by generators and tests |
| `src/generate-mnemonics.mjs` | Generates the packed mnemonic and operand include tables from `src/abi.mjs` |

## `src/host/` composition and execution

| File | Role |
| --- | --- |
| `index.mjs` | Root package export surface for host assembly, artifacts, native runner, translation, and self-host helpers |
| `assemble-atom-project.mjs` | High-level composition of Atom project resolution and native execution; lowers general resolver limits to the native profile |
| `resolve-atom-project.mjs` | Atom-specific source preparation: reader, profile, neutral resolver, placement, and `INCBIN` lowering |
| `native-atom-core.mjs` | Loads the checked core, verifies both digests and required symbols, and derives immutable code ranges and size accounts |
| `native-atom-runner.mjs` | Snapshots prepared projects, builds Z80 memory and descriptors, pages source, intercepts sink calls, enforces runtime invariants, and returns committed generations |
| `atom-assembly-error.mjs` | Structured error used by native execution, artifacts, translation, self-host helpers, and publication |

## `src/host/atom/`

| File | Role |
| --- | --- |
| `literals.mjs` | Case-insensitive preprocessor names and 16-bit decimal, prefix, or Intel-suffix value parsing |
| `directives.mjs` | `%DEFINE`, `%INCLUDE`, `%IF`, `%ELSE`, `%ENDIF`, header rules, conditional state, dependency references, and equal-length masking |
| `source-profile.mjs` | Adapts Atom directive inspection to the neutral resolver's entry/dependency profile interface |
| `incbin.mjs` | Recognizes active `INCBIN`, snapshots a confined binary, lowers it to equal-length initialized `DS`, and retains bridge provenance |

## `src/host/source-packager/`

| File | Role |
| --- | --- |
| `index.mjs` | Neutral package export layer |
| `errors.mjs` | `SourcePackagerError` category, code, message, and optional location |
| `node-source-reader.mjs` | Project-root validation, physical spelling, realpath confinement, source snapshots, and physical/dependency/logical identities |
| `resolver.mjs` | Bounded deterministic dependency traversal, deduplication, cycle detection, profile validation, part order, and retained-path accounting |
| `placement.mjs` | Joins path-keyed bank placement to resolved parts, constructs provenance, and builds canonical SP1 |
| `source-plan.mjs` | Strict SP1 parser, serializer, path grammar, record counts, bank limits, newline handling, and terminator validation |
| `atomic-plan-writer.mjs` | Validates, writes, synchronizes, and renames one SP1 plan while preserving the previous destination on failure |
| `passthrough-profile.mjs` | Byte-preserving profile used to prove the language-neutral resolver boundary |
| `README.md` | Local source-packager module notes |

## `src/host/artifacts/`

| File | Role |
| --- | --- |
| `atom-nobj.mjs` | Atom flat NOBJ 0.2 writer and parser, IMAGE/PATCH coalescing, flat MAP, record counts, and CRC-16/CCITT-FALSE |
| `render-artifacts.mjs` | Generation materialization, Intel HEX, listing, D8 map, symbol classification, source-range grouping, and complete artifact rendering |
| `publish-artifacts.mjs` | Content digest, immutable generation staging, manifest hashes, synchronization, verified reuse, and atomic `current` symlink replacement |

## `src/host/translation/`

| File | Role |
| --- | --- |
| `atom-to-azm.mjs` | Quote-aware and comment-aware conversion of prepared Atom directives, equates, and byte functions into one AZM oracle source |

## `src/host/self-host/`

| File | Role |
| --- | --- |
| `build-self-host-source.mjs` | Flattens the readable AZM include closure, evaluates fixed conditions, removes proof annotations, rewrites directives and symbols, and chunks Atom-valid source |
| `create-self-hosted-core.mjs` | Recovers original global symbols from one Atom generation, reconstructs code ranges, materializes HEX, and produces a runner-compatible replacement core |

## `bin/`

| File | Role |
| --- | --- |
| `atom.mjs` | Installed CLI: argument parsing, build options, self-host mode, in-process assembly, artifact rendering, publication, and terminal diagnostics |

## `assets/`

| File | Role |
| --- | --- |
| `native-core.json` | Atom-built Intel HEX, checked symbol map, digests, and source identity loaded by the installed package |

## `native/`

| File | Role |
| --- | --- |
| `atom-00.atm` through `atom-04.atm` | Authoritative native Atom source parts |
| `atom.atm` | `%INCLUDE` entry that orders the five content parts through the normal host resolver |
| `atom-symbols.json` | Original-to-short symbol mapping and source-generation statistics |

The `.atm` files are the editing authority. The build never regenerates them
from the frozen `asm/` tree.

## `scripts/`

| File | Role |
| --- | --- |
| `generate-native-core.mjs` | Assembles `native/atom.atm` with Atom, proves exact equality through strict automatic AZM translation, and writes or checks `assets/native-core.json` |
| `verify-dependencies.mjs` | Pins the sibling Debug80 branch and exact AZM/runtime source trees used by proofs |
| `verify-example.mjs` | Runs the shipped CLI example in a temporary copy and verifies exact artifacts and manifest hashes |

## `test/` native harness support

| File | Role |
| --- | --- |
| `support.mjs` | Encoder direct-entry AZM assembly, Debug80 stepping, complete memory audit, instruction oracle helpers, and execution statistics |
| `symbol-support.mjs` | Checked-core symbol and pending direct-entry harness with guarded caller-owned arenas and complete memory auditing |
| `tokenizer-support.mjs` | Checked-core tokenizer harness with guarded source, exact token/error observations, and complete memory auditing |
| `expression-support.mjs` | Expression harness, token setup, symbol state, and result extraction |
| `parser-support.mjs` | Concrete-parser view over the checked symbolic parser harness |
| `output-support.mjs` | Output harness and injectable proof-sink states |
| `statements-support.mjs` | Statement harness with source, symbol, pending, output, and diagnostic observations |
| `integration-support.mjs` | Checked-core symbolic parser and patch harness with guarded caller-owned regions |
| `driver-support.mjs` | Multipart driver harness, descriptor builders, sink lifecycle, and full-map checks |
| `cases.mjs` | Generated valid, AZM-invalid, and systematically malformed instruction records |
| `native-host-case.mjs` | Small two-part program shared by host-native tests and measurements |

## `test/` native proof suites

| File | Role |
| --- | --- |
| `encoder.test.mjs` | Full positive and negative instruction differential, record validation, recognition, and RADIX-40 |
| `symbols.test.mjs` | Symbol packing, lookup, declaration, scope, capacity, and pending behavior |
| `tokenizer.test.mjs` | Token forms, literals, strings, comments, line endings, errors, positions, and memory writes |
| `expression.test.mjs` | Precedence, arithmetic, functions, forward forms, ranges, errors, and stack capacities |
| `parser.test.mjs` | Operand grammar, validation, values, references, and atomic failure |
| `output.test.mjs` | IMAGE, PATCH, resolution, capacity, range, and sink failure behavior |
| `statements.test.mjs` | Source statement grammar, directives, symbols, output, and diagnostics |
| `integration.test.mjs` | Cross-module single-part programs and failure propagation |
| `driver.test.mjs` | Descriptor validation, multipart order, finalization, and lifecycle |
| `proof-system.test.mjs` | Complete 64 KiB region coverage and independently frozen instruction census |

## `test/` host source and preparation suites

| File | Role |
| --- | --- |
| `host-atom-literals.test.mjs` | Host numeric spellings, definition names, and boundaries |
| `host-atom-directives.test.mjs` | Directive grammar, definitions, headers, conditionals, and dependency selection |
| `host-atom-masking.test.mjs` | Equal lengths, CR/LF preservation, inactive bytes, and leaked-directive discrimination |
| `host-incbin.test.mjs` | Binary recognition, confinement, snapshotting, lowering, bridge counts, listing, and D8 |
| `host-atom-to-azm.test.mjs` | Atom-to-AZM syntax translation and initialized-address comparison |
| `host-node-source-reader.test.mjs` | Physical path spelling, confinement, symlinks, identities, and snapshots |
| `host-resolver.test.mjs` | Graph order, diamonds, repeats, cycles, and limits |
| `host-placement.test.mjs` | Path-keyed bank assignments and placement failures |
| `host-source-plan.test.mjs` | SP1 syntax, limits, newlines, truncation, counts, and terminator |
| `host-atomic-plan-writer.test.mjs` | Temporary write, synchronization, rename, cleanup, and prior-plan preservation |
| `host-provenance.test.mjs` | Logical identities, include stacks, locations, and frozen metadata |
| `host-source-packager-boundary.test.mjs` | Neutral modules remain independent of Atom syntax |
| `host-resolve-atom-project.test.mjs` | Composed Atom preparation, lowering, placement, state, and failures |

## `test/` execution, artifact, and product suites

| File | Role |
| --- | --- |
| `host-native-atom-runner.test.mjs` | Complete prepared-source execution, paging, memory protection, sink bridge, errors, budgets, and replacement cores |
| `host-artifacts.test.mjs` | NOBJ, materialized binary, Intel HEX, listing, D8, symbols, and source ranges |
| `host-example.test.mjs` | Runs the shipped example verifier |
| `host-package.test.mjs` | npm archive census, offline installation, installed CLI, absent AZM, bundled runtime, and installed self-host |
| `host-self-host.test.mjs` | Authoritative source, first and second Atom generations, pinned core, and translated AZM equality |
| `host-release.test.mjs` | Product documentation links and example case, package/public license policy, and proof/native measurement agreement |

## Measurement scripts under `test/`

| File | Role |
| --- | --- |
| `measure.mjs` | Encoder code/data, LD, recognition, coverage, and maximum execution accounts |
| `measure-symbols.mjs` | Symbol and pending code/workspace/record accounts |
| `measure-tokenizer.mjs` | Tokenizer code/workspace and execution observations |
| `measure-expression.mjs` | Expression code/workspace, stacks, and execution observations |
| `measure-parser.mjs` | Parser code/workspace, reference records, and execution observations |
| `measure-output.mjs` | Output code/workspace and operation observations |
| `measure-statements.mjs` | Statement code/workspace, directives, and execution observations |
| `measure-integration.mjs` | Linked cross-module native account |
| `measure-driver.mjs` | Multipart driver account and lifecycle observations |
| `measure-host-native.mjs` | Complete linked Mac image, caller-owned regions, and host execution |
| `measure-self-host.mjs` | Source generation, two Atom generations, AZM oracle comparison, and execution totals |

## `proofs/`

| Files | Role |
| --- | --- |
| `azm-form-census.json` | Independent instruction-form denominator, per-mnemonic counts, and canonical hash |
| `phase-1.json` through `phase-11.json` | Reviewed correctness, size, capacity, execution, package, and product observations by checkpoint |
| `phase-*-memory.json` | Exact symbolic 64 KiB memory maps and declared subsystem extents |
| `package-census.json` | Frozen npm unpacked byte and entry counts after packaged files settle |

## `docs/`

| Files | Role |
| --- | --- |
| `architecture.md` | Concise host/native responsibility and lifecycle design |
| `language-reference.md` | Current Atom source syntax and deliberate language boundaries |
| `limits.md` | Native limits, Mac proof capacities, expressions, symbols, pending records, and realistic TEC RAM discussion |
| `command-line.md` | Installation, CLI options, bundle layout, diagnostics, example, and release command |
| `mac-host-integration.md` | Native runner, sink interception, memory map, diagnostics, and public host modules |
| `host-source-packaging.md` | Resolver, preprocessing, SP1, binary inclusion, extraction seam, and proof map |
| `atom-object-format.md` | Atom flat NOBJ 0.2 framing and MAP profile |
| `encoder-abi.md` | Parsed instruction record and encoder entries |
| `tokenizer-abi.md` | Source interval, token record, lexical surface, and handoff |
| `symbol-abi.md` | Packed symbol and pending record layouts and arena rules |
| `symbolic-parser-abi.md` | Deferred parser references and patch kinds |
| `statements-abi.md` | Native labels, equates, directives, status categories, and statement limits |
| `output-abi.md` | Sink calls, output entries, patch resolution, and failure lifecycle |
| `native-driver-abi.md` | Build and part descriptors, multipart sequence, finalization, and driver statuses |
| `tec-1-deployment.md` | Remaining operating-adapter work and deployment constraints |
| `release-checklist.md` | Local release gate plus network, repository, license, and package checks |
| `phase-*-report.md` | Chronological measurement and design record for completed checkpoints |
| `codebase/` | This maintained engineering manual |

## `examples/`

| Path | Role |
| --- | --- |
| `examples/hello/main.asm` | Entry source with conditional dependency selection, instructions, labels, forward patch, data, and storage |
| `examples/hello/layout.asm` | Default dependency selected by the entry header |
| `examples/hello/release-layout.asm` | Alternate dependency used by host conditionals |
| `examples/hello/README.md` | Example build and expected artifact description |
