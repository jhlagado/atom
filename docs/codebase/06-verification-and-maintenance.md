# Chapter 6 — Verification and maintenance

[← Native core generation and self-hosting](05-native-core-generation-and-self-hosting.md) | [Appendices →](appendices/index.md)

Atom's verification is organized around the same boundaries as the
implementation. Native modules run through direct Z80 entry harnesses. Host
modules run through Node tests. Wider lanes compose preparation, native
execution, logical output, artifacts, publication, package installation, and
self-hosting.

Exact bytes are only one part of the proof. The native harnesses also check
return PC, SP, register contracts, guards, immutable regions, complete memory
write sets, failure atomicity, and instruction or cycle budgets.

## Test organization

The test directory is flat, but filenames group it into clear lanes:

| Files | Boundary |
| --- | --- |
| `encoder.test.mjs`, `cases.mjs`, `support.mjs` | Complete instruction differential, recognition, RADIX-40, validation, and encoding |
| `symbols.test.mjs`, `symbol-support.mjs` | Symbol packing, global/private arenas, scope eviction, and pending records |
| `tokenizer.test.mjs`, `tokenizer-support.mjs` | Lexical surface, token commits, positions, line handling, and native memory writes |
| `expression.test.mjs`, `expression-support.mjs` | Concrete and deferred expression semantics, stack limits, and arithmetic boundaries |
| `parser.test.mjs`, `parser-support.mjs` | Operand classification, parsed records, deferred fields, and atomic reference publication |
| `output.test.mjs`, `output-support.mjs` | IMAGE/PATCH order, target capacity, patch values, and sink failure paths |
| `statements.test.mjs`, `statements-support.mjs` | Labels, equates, directives, data, strings, and statement diagnostics |
| `integration.test.mjs`, `integration-support.mjs` | Cross-module native assembly programs |
| `driver.test.mjs`, `driver-support.mjs` | Multipart descriptor validation, lifecycle, final undefined checks, and abort rules |
| `host-atom-*.test.mjs` | Atom preprocessing, literals, masking, translation, and host syntax |
| `host-resolver.test.mjs` and related source-packager tests | Source identity, graph, SP1, placement, provenance, confinement, and capacities |
| `host-native-atom-runner.test.mjs` | Prepared project through Debug80 and the native sink boundary |
| `host-artifacts.test.mjs` | NOBJ, BIN, HEX, listing, and D8 rendering |
| `host-example.test.mjs` | Shipped example through the complete CLI |
| `host-package.test.mjs` | Packed offline install, runtime dependency, CLI, failure, `INCBIN`, and installed self-host |
| `host-self-host.test.mjs` | Pinned AZM image, second Atom generation, and translated-AZM equality |
| `host-release.test.mjs` | Documentation, examples, licensing, package policy, and measured native account |

The closest test should identify the broken layer. A wider test should prove
that the public build still observes the intended result.

## Native proof harnesses

Native proof harnesses load `assets/native-core.json` and supply
guarded input and output records, source buffers, arenas, adapter state, stack,
and sentinel return addresses. Automatic Atom-to-AZM translation checks the
same complete core under strict register contracts before Debug80 executes its
entry points.

The checked expression, parser/patch, output, statement, and driver lanes execute
`native/atom.atm` directly. They supply guarded source, record, output, key,
symbol, pending, and logical sink regions and audit all 65,536 addresses after
every invocation. The output and driver harnesses intercept the production
service entries and return through the native stack; they carry no proof-only
Z80 adapter.

The support modules restore pristine memory before each invocation. They seed
workspaces and guards with varying patterns, install the input records and
return sentinel, step until the sentinel PC, then compare the complete
observable state.

For a direct entry, the common checks include:

- the routine returned through the exact sentinel PC;
- SP advanced by exactly the return address;
- promised registers and IY were preserved;
- input records and source bytes did not change;
- two-sided guards did not change;
- immutable code and tables did not change;
- failure left unpublished destinations unchanged; and
- no byte outside the declared workspace, output, or stack region changed.

The full-memory audit covers all 65,536 addresses. A passing status byte cannot
conceal a write elsewhere in the machine.

The encoder lane calls the entries in
`assets/native-core.json` and repeats the full valid and invalid differential.
The symbol lane calls the same checked core with guarded caller-owned symbol and
pending arenas. It checks the complete 64 KiB write set, exact return PC and SP,
scope transitions, failure atomicity, and record-size boundaries. The tokenizer
lane supplies a guarded source interval and repeats the complete lexical,
diagnostic, publication, classifier, and source-boundary corpus against the
checked core. The expression, parser/patch, output, statement, and driver lanes
also use the checked core. No subsystem proof links or executes a second native
image.

## Frozen memory profiles

Files such as `proofs/phase-1-memory.json` describe every region in a direct
proof map. The corresponding test resolves symbolic boundaries from the checked
native core and verifies that the regions begin at zero, meet without a gap or
overlap, have their exact declared sizes, and end at `$10000`.

Later phase profiles apply the same discipline to the symbol, tokenizer,
expression, parser, output, statement, integration, and driver images. Code,
immutable tables, fixed workspace, caller buffers, guards, stack, and unused
memory remain separate accounts.

## Instruction differential

`test/cases.mjs` generates the complete Atom instruction corpus as source text
plus ten-byte parsed records. For every valid case, the encoder lane:

1. assembles the source independently with AZM;
2. calls native `AtomFormLength` directly;
3. calls native `AtomEncode` directly;
4. compares length and every emitted byte; and
5. checks the remaining guarded destination.

The frozen `proofs/azm-form-census.json` fixes the denominator independently of
the generator. It records 3,445 cases across 69 mnemonics, exact counts by
mnemonic, and a SHA-256 of the canonical source/record pairs. The proof first
requires the generated set to match this census, so deleting a family cannot
leave a misleading 100% differential result.

The negative lane asks AZM to reject malformed source and requires both native
length and encoding entries to reject the corresponding record without output.
Additional systematic records cover unknown ordinals, unused operand-class
holes, and hidden trailing operands. Targeted cases cover the DD/FD index-half
collision rules that are easy to encode incorrectly.

## Register and stack contracts

Every native public routine carries an AZM `.routine` annotation. Call sites may
use `.expectout` where an inferred output must be explicit. Automatic
translation assembles the authoritative `.atm` core under strict
register-contract mode. Runtime harnesses then execute those checked bytes.

The annotations state inputs, outputs, possible outputs, clobbers, and flag
effects. Runtime tests remain necessary: a static contract can describe the
wrong implementation, and an execution test can miss an unexercised path. Atom
uses both.

`npm run annotate:contracts` remains as a compatibility name for the strict
translated-core check. It does not rewrite the authoritative `;@` annotations.
Any contract change requires review against the routine body and direct runtime
proof before commit.

## Execution budgets

Proof manifests record measured instruction and T-state maxima plus explicit
ceilings for public entries. Harnesses fail when an execution does not reach the
sentinel within both budgets. Failure messages retain recent PCs, current PC,
SP, instruction count, and cycles.

The host runner applies the same principle to complete builds. Its default
budgets are intentionally above the measured self-host run, and the self-host
measurement pins its exact current counts. A budget change is reviewed as an
execution-account change, not used to conceal nontermination.

## Symbol, parser, and output failure proofs

The stateful native modules need discriminators for partial publication:

- Symbol tests fill arenas to exact capacity, attempt the next insertion, and
  compare cursors and records.
- Scope tests leave undefined private records or pending invariants and prove
  that failed global transitions retain the old scope.
- Parser tests use malformed forms with missing symbols and prove that no
  symbol or reference appears before complete validation succeeds.
- Output tests inject sink failures at IMAGE, PATCH, commit, and abort
  boundaries and inspect pending records and cursor movement.
- Statement tests combine label, expression, pending, and output failures to
  prove exact outer category, nested status, and source position.
- Driver tests distinguish pre-begin configuration failure from every
  post-begin abort path.

These tests protect the transactional rules that make a streaming assembler
recoverable even though it cannot roll source input backward.

## Host preparation proofs

The source-packager tests construct temporary filesystem graphs. They cover:

- deterministic postorder and diamond deduplication;
- repeated direct dependencies and complete cycle paths;
- lexical, symlink, absolute, missing, and case-alias path failures;
- exact part, depth, path, retained-path, and bank limits;
- LF and CRLF SP1 parsing, truncation, required `END`, and trailing bytes;
- path-keyed placement independent of graph-order changes;
- snapshot stability after filesystem mutation;
- neutral profile separation from Atom imports;
- `%` directive recognition without stealing binary literals or remainder;
- definition, conditional, inactive-include, and header rules;
- equal lengths, newline bytes, masked ranges, and source positions; and
- confined `INCBIN` snapshots and equal-length lowering.

Composed tests pass the resolved project into the native runner and check that
an error in a dependency retains that file's logical identity rather than the
entry file or an anonymous concatenated stream.

## Native host-runner proofs

`test/host-native-atom-runner.test.mjs` exercises the complete 64 KiB Mac map.
It checks descriptor construction, source paging, read-only code and source,
stack canaries, execution budgets, sink status propagation, service exceptions,
target boundaries, IMAGE order, PATCH targets, layout high-water, and exact
source diagnostics.

Replacement-core tests reject empty, truncated, out-of-range, or structurally
incomplete HEX before execution. A malicious core that attempts to write the
source page provides a discriminator for the runtime's read-only range.

`INCBIN` bridge tests compare every substituted byte and inject metadata count
mismatches in both directions. Listing and D8 tests then verify that those bytes
remain attributed to the original directive line.

## Artifact and publication proofs

Artifact tests independently parse the generated NOBJ, check CRC and record
order, compare materialized bytes, verify Intel HEX text, inspect listing rows,
and validate D8 files, segments, symbols, source units, and entry metadata.

Publication tests inject failures during staging, synchronization, generation
promotion, and `current` selection. They prove that the prior selected
generation survives, owned temporary paths are removed, and an existing
content-addressed generation is reused only after complete byte and manifest
verification.

The shipped example supplies a small stable acceptance program. Its verifier
checks an exact 19-byte image, Intel HEX, listing provenance, D8 structure,
NOBJ and manifest presence, and every manifest byte count and SHA-256.

## Package proof

`test/host-package.test.mjs` runs `npm pack`, installs the archive offline under
a temporary prefix, and executes it from an unrelated project. The test proves
that:

- Debug80 Runtime is bundled and operational;
- AZM is absent from the installed dependency tree;
- the public CLI assembles valid source and `INCBIN`;
- invalid source returns a positioned diagnostic and publishes nothing;
- all five artifacts are present;
- `atom --self-host` reproduces the installed native core; and
- tampering with the checked core or symbol map is detected.

The same test records an exact unpacked byte count and package entry count after
the packaged file set is frozen. Compressed gzip size remains an observation
because it can vary with npm and compression tooling.

## Self-host proof

`test/host-self-host.test.mjs` is the broadest native correctness lane. It reads
the authoritative native source, assembles it with the pinned core, constructs
a core from that first generation, and assembles the same source again.

It then translates the prepared source to AZM and compares the exact initialized
address set and every resident byte. Generator statistics, code bytes,
workspace, resident extent, patch count, instruction count, T-states, service
calls, and source-page order are checked against the frozen proof record.

## Measurements and proof records

Measurement scripts print current observations rather than editing proof files:

| Command | Measurement |
| --- | --- |
| `npm run measure` | Encoder code/data split, LD subtotal, recognition, and instruction census |
| `npm run measure:symbols` | Symbol and pending code, records, arenas, and boundaries |
| `npm run measure:tokenizer` | Tokenizer code, workspace, lexical coverage, and maxima |
| `npm run measure:expression` | Expression code, stacks, semantics, and execution maxima |
| `npm run measure:parser` | Parser code, references, classification, and execution maxima |
| `npm run measure:output` | Output code, workspace, logical operations, and failure paths |
| `npm run measure:statements` | Statement code, directives, diagnostics, and execution maxima |
| `npm run measure:driver` | Driver code, descriptor limits, lifecycle, and execution maxima |
| `npm run measure:host-native` | Linked native account, caller-owned Mac regions, and composed execution |
| `npm run measure:self-host` | Source size, two generations, AZM comparison, and complete execution account |

`proofs/phase-*.json` freezes reviewed observations and named budgets. A phase
report explains their basis and classifies each number as Measured, Projected,
or Hypothesis. When code changes, rerun the measurement after all edits settle;
do not copy an earlier total into a new report.

## Dependency pin

Atom's development proofs depend on the AZM oracle and Debug80 Runtime in the
sibling Debug80 repository. `scripts/verify-dependencies.mjs` checks the
required Debug80 branch, exact AZM and runtime tree identities, and a clean
dependency worktree before the normal npm test preparation rebuilds them.

This pin protects the oracle denominator and emulator semantics. Updating it is
a separate reviewed dependency checkpoint with fresh native and differential
evidence.

## Maintainer commands

The principal lanes are:

```sh
npm run test:host
npm test
npm run verify:strict-contracts
npm run verify:native-core
npm run verify:native-source
npm run measure:host-native
npm run measure:self-host
npm run release:check
```

`npm run release:check` is the complete local maintainer gate. It runs all
native and host tests, strict core and authoritative-source checks, and the final
host and self-host measurements. `prepublishOnly` invokes the same gate.

Network and release-authority checks remain explicit:

```sh
git fetch origin
git status --short --branch
gh repo view jhlagado/atom --json visibility,licenseInfo
npm pack --dry-run
```

## Change workflow

A normal change follows this sequence:

1. identify the owning host or native boundary;
2. read the corresponding chapter, ABI document, source, and closest proof;
3. add a discriminator that would fail for the plausible wrong implementation;
4. make one structural change;
5. run the narrow proof and inspect exact state, not only status;
6. run the composed host or native lane that observes the public result;
7. regenerate checked tables, core, or self-host source when their authorities
   changed;
8. rerun size and execution measurements from the current linked image;
9. update this manual when a file owner, flow, public surface, or proof lane
   changed; and
10. run the release gate before a release checkpoint.

For native work, preserve both code bytes and writable workspace as separate
accounts. A reduction in one is not a net saving when it moves unreported bytes
into the other or into caller-owned RAM.
