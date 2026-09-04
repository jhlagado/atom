# Appendix A — Directory and file reference

[← Appendices](index.md) | [Build-flow reference →](b-build-flow-reference.md)

This appendix maps the files that implement, generate, execute, and prove Atom.
The narrative chapters explain how the files interact; this reference identifies
the owner of a behavior quickly.

## Top-level files

| File | Role |
| --- | --- |
| `README.md` | Product overview, installation, current capability, measured native account, and correctness summary |
| `package.json` | npm identity, public exports, `atom` and `azm-to-atom` binaries, package contents, dependencies, and verification scripts |
| `LICENSE` | GPL-3.0-only license text |

## `src/` root

| File | Role |
| --- | --- |
| `src/abi.mjs` | JavaScript mnemonic and operand ordinals, parsed-record constructor, and reference RADIX-40 packer used by tests and host tooling |

## `src/host/` public surface

| File | Role |
| --- | --- |
| `index.mjs` | Root package export surface for host assembly, artifacts, native runner, translation, and self-host helpers |
| `atom-assembly-error.mjs` | Structured error used by native execution, artifacts, translation, self-host helpers, and publication |
| `package-metadata.mjs` | Single package-version authority used by the CLI and generated D8 metadata |

## `src/host/application/`

| File | Role |
| --- | --- |
| `assemble-atom-project.mjs` | High-level composition of Atom project resolution and native execution; lowers general resolver limits to the native profile |
| `resolve-atom-project.mjs` | Atom-specific source preparation: reader, profile, neutral resolver, placement, and `INCBIN` lowering |

## `src/host/core/`

| File | Role |
| --- | --- |
| `native-atom-core.mjs` | Loads the checked core, verifies both digests and required symbols, and derives immutable code ranges and size accounts |

## `src/host/harness/`

| File | Role |
| --- | --- |
| `native-atom-runner.mjs` | Snapshots prepared projects, builds Z80 descriptors, serves logical source reads, intercepts sink calls, enforces runtime invariants, and returns committed generations |
| `named-object-atom-adapter.mjs` | Adapts Atom's source and output callbacks to the shared named-object provider contract |

## `src/host/providers/`

| File | Role |
| --- | --- |
| `tool-service-gateway.mjs` | Dispatches the direct Node source, output, console, and exit service calls through one checked boundary |
| `named-object-services.mjs` | Re-exports the shared named-object provider constants and client under Atom's public compatibility names |

## `src/host/atom/`

| File | Role |
| --- | --- |
| `literals.mjs` | Case-insensitive preprocessor names and 16-bit decimal, prefix, or Intel-suffix value parsing |
| `directives.mjs` | `%DEFINE`, `%INCLUDE`, `%IF`, `%ELSE`, `%ENDIF`, header rules, conditional state, dependency references, and equal-length masking |
| `source-profile.mjs` | Adapts Atom directive inspection to the neutral resolver's entry/dependency profile interface |
| `incbin.mjs` | Recognizes active `INCBIN`, snapshots a confined binary, lowers it to equal-length initialized `DS`, and retains bridge provenance |

## Shared source preparation

The modules below are exported by
`@jhlagado/z80-tool-services/source-preparation` rather than copied into Atom.

| Shared file | Role |
| --- | --- |
| `index.mjs` | Neutral package export layer |
| `errors.mjs` | `SourcePreparationError` category, code, message, and optional location |
| `node-source-reader.mjs` | Project-root validation, case-conflicting paths, realpath confinement, source snapshots, and physical/dependency/logical identities |
| `resolver.mjs` | Bounded deterministic dependency traversal, deduplication, cycle detection, profile validation, part order, and retained-path accounting |
| `placement.mjs` | Joins path-keyed bank placement to resolved parts and constructs provenance |
| `passthrough-profile.mjs` | Byte-preserving profile used to prove the language-neutral resolver boundary |
| `README.md` | Shared project-preparation module notes |

## `src/host/artifacts/`

| File | Role |
| --- | --- |
| `atom-nobj.mjs` | Atom flat NOBJ 0.2 writer and parser, IMAGE/PATCH coalescing, flat MAP, record counts, and CRC-16/CCITT-FALSE |
| `render-artifacts.mjs` | Generation materialization, Intel HEX, listing, D8 map, symbol classification, source-range grouping, and complete artifact rendering |
| `publish-artifacts.mjs` | Content digest, immutable generation staging, manifest hashes, synchronization, verified reuse, and atomic `current` symlink replacement |

## `src/host/translation/`

| File | Role |
| --- | --- |
| `atom-to-azm.mjs` | Quote-aware and comment-aware conversion of prepared Atom directives, equates, and byte functions into one AZM comparison source |
| `azm-to-atom.mjs` | Strict AZM common-subset conversion, symbol and source checks, positioned rejection, and deterministic Atom source output |

## `src/host/self-host/`

| File | Role |
| --- | --- |
| `create-self-hosted-core.mjs` | Recovers original global symbols from one Atom generation, reconstructs code ranges, materializes HEX, and produces a runner-compatible replacement core |

## `bin/`

| File | Role |
| --- | --- |
| `atom.mjs` | Installed CLI: argument parsing, build options, self-host mode, in-process assembly, artifact rendering, publication, and terminal diagnostics |
| `azm-to-atom.mjs` | Installed strict source converter with non-overwriting `.atom.asm` output, standard-output mode, and positioned diagnostics |

## `assets/`

| File | Role |
| --- | --- |
| `native-core.json` | Atom-built Intel HEX, checked symbol map, digests, and source identity loaded by the installed package |
| `atom-object-harness.bin` | ATOM-built native core composed with the portable named-object adapter and fail-closed transport |

## `native/`

| File | Role |
| --- | --- |
| `atom-00.asm` through `atom-04.asm` | Authoritative native Atom source parts |
| `atom.asm` | `%INCLUDE` entry that orders the five content parts through the normal host resolver |
| `atom-symbols.json` | Original-to-short symbol mapping and source-generation statistics |
| `named-object-adapter.asm` | Z80 adapter from Atom source and sink callbacks to the shared named-object request |

The `.asm` files are the sole editing authority for the native assembler.

## `scripts/`

| File | Role |
| --- | --- |
| `generate-native-core.mjs` | Assembles `native/atom.asm` with ATOM, executes that emitted core to prove a second identical generation, and writes or checks `assets/native-core.json` |
| `generate-native-object-harness.mjs` | Uses ATOM to link the shared ABI constants and Z80 object adapter, checks the one-bank gate, and writes or verifies the binary and census |
| `verify-dependencies.mjs` | Checks installed runtime, tool-service and historical AZM package version ranges; remaining AZM requirement is not yet migrated |
| `verify-example.mjs` | Runs the shipped CLI example in a temporary copy and verifies exact artifacts and manifest hashes |

## `test/` native harness support

| File | Role |
| --- | --- |
| `support.mjs` | Encoder direct-entry AZM assembly, Debug80 stepping, complete memory audit, instruction comparison helpers, and execution statistics |
| `symbol-support.mjs` | Checked-core symbol and pending direct-entry harness with guarded caller-owned arenas and complete memory auditing |
| `tokenizer-support.mjs` | Checked-core tokenizer harness with guarded source, exact token/error observations, and complete memory auditing |
| `expression-support.mjs` | Expression harness, token setup, symbol state, and result extraction |
| `parser-support.mjs` | Concrete-parser view over the checked symbolic parser harness |
| `output-support.mjs` | Checked-core output harness with host-intercepted production services, guarded logical-operation state, and complete memory auditing |
| `statements-support.mjs` | Checked-core statement harness with guarded caller state, host-intercepted production services, exact diagnostics, and complete memory auditing |
| `integration-support.mjs` | Checked-core symbolic parser and patch harness with guarded caller-owned regions |
| `driver-support.mjs` | Checked-core multipart driver harness with guarded descriptors and arenas, all six host-intercepted services, exact lifecycle state, and complete memory auditing |
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
| `native-object-harness.test.mjs` | Full Z80 object-adapter execution, 255-part capacity, cache, patch, commit, and poisoned-write abort proof |

## `test/` host source and preparation suites

| File | Role |
| --- | --- |
| `host-atom-literals.test.mjs` | Host numeric literal forms, definition names, and boundaries |
| `host-atom-directives.test.mjs` | Directive grammar, definitions, headers, conditionals, and dependency selection |
| `host-atom-masking.test.mjs` | Equal lengths, CR/LF preservation, inactive bytes, and leaked-directive discrimination |
| `host-incbin.test.mjs` | Binary recognition, confinement, snapshotting, lowering, bridge counts, listing, and D8 |
| `host-atom-to-azm.test.mjs` | Atom-to-AZM syntax translation and initialized-address comparison |
| `host-azm-to-atom.test.mjs` | Strict mapping and rejection census, CLI behavior, and exact AZM-to-Atom initialized-address and byte differential |
| `host-node-source-reader.test.mjs` | Physical path casing, confinement, symlinks, identities, and snapshots |
| `host-resolver.test.mjs` | Graph order, diamonds, repeats, cycles, and limits |
| `host-placement.test.mjs` | Path-keyed bank assignments and placement failures |
| `host-provenance.test.mjs` | Logical identities, include stacks, locations, and frozen metadata |
| `host-project-preparation-boundary.test.mjs` | Neutral modules remain independent of Atom syntax |
| `host-resolve-atom-project.test.mjs` | Composed Atom preparation, lowering, placement, state, and failures |

## `test/` execution, artifact, and product suites

| File | Role |
| --- | --- |
| `host-native-atom-runner.test.mjs` | Complete prepared-source execution, source-service boundaries, memory protection, sink bridge, errors, budgets, and replacement cores |
| `host-artifacts.test.mjs` | NOBJ, materialized binary, Intel HEX, listing, D8, symbols, and source ranges |
| `host-example.test.mjs` | Runs the shipped example verifier |
| `host-package.test.mjs` | npm archive census, offline installation, installed CLI, absent AZM, bundled runtime, and installed self-host |
| `host-self-host.test.mjs` | Authoritative source, first and second ATOM generations, pinned bytes, initialized addresses and recovered ABI symbols |
| `host-core-bootstrap.test.mjs` | Executes native-core verification with AZM imports forbidden and checks that verification leaves the reference unchanged |
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
| `measure-host-native.mjs` | Complete linked desktop image, caller-owned regions, and host execution |
| `measure-self-host.mjs` | Two ATOM generations, pinned-image comparison, initialized addresses, ABI symbols and execution totals |

## `proofs/`

| Files | Role |
| --- | --- |
| `azm-form-census.json` | Independent instruction-form denominator, per-mnemonic counts, and canonical hash |
| `phase-1.json` through `phase-11.json` | Reviewed correctness, size, capacity, execution, package, and product observations by checkpoint |
| `phase-*-memory.json` | Exact symbolic 64 KiB memory maps and declared subsystem extents |
| `package-census.json` | Frozen npm unpacked byte and entry counts for the explicit package-census audit |
| `native-object-harness-census.json` | Linked adapter size, workspace, entry, capacity, symbol, and digest account |

## `docs/`

| Files | Role |
| --- | --- |
| `architecture.md` | Concise host/native responsibility and lifecycle design |
| `language-reference.md` | Current Atom source syntax and deliberate language boundaries |
| `limits.md` | Native limits, desktop proof capacities, expressions, symbols, pending records, and realistic TEC RAM discussion |
| `command-line.md` | Installation, CLI options, positive output selection, diagnostics, examples, and native CP/M command |
| `azm-to-atom.md` | Converter commands, exact syntax mappings, rejected AZM boundaries, diagnostics, and programmatic API |
| `desktop-host-integration.md` | Native runner, sink interception, memory map, diagnostics, and public host modules |
| `host-source-preparation.md` | Resolver, preprocessing, binary inclusion, extraction seam, and proof map |
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
