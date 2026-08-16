# Atom host source-packager handover

## Assignment

Finish the Atom host source-packager work described in the approved design and
implementation plan. Start from the published planning branch. Implement the
work in Atom, prove it, measure the resident tokenizer change, obtain a
read-only adversarial review, and push the completed implementation branch.

No implementation has started. The design and test-first execution plan are
complete.

## Repository state at handover

| Repository | Role | Branch or revision | Write policy |
| --- | --- | --- | --- |
| `jhlagado/atom` | Implementation repository | `codex/shared-source-packager-contract`; parent before this handover was `1d35ec418260abe31bd021b6eefca7a2b79e8c98` | Write, commit, and push on a new implementation branch |
| `jhlagado/debug80` | Frozen AZM/runtime dependency and future shared-host location | Observed `origin/main@3f2adb669bb9e7888305c623f8c843054c3dd111` on 2026-08-16 | Read-only for this assignment |
| Nucleus rewrite | Design synchronization peer | Actively changing | Do not inspect or modify unless the project owner requests a synchronization review |

Fetch the Atom planning branch before trusting the parent hash above. The
handover itself is committed after that parent.

Record the branch and HEAD of every repository checkout used during the work.
Debug80 counts as touched when its AZM or runtime build is used, even though its
source must remain unchanged.

## Governing documents

Read these files completely, in this order:

1. `docs/handovers/2026-08-16-atom-host-source-packager.md`
2. `docs/superpowers/specs/2026-08-16-shared-source-packager-design.md`
3. `docs/superpowers/plans/2026-08-16-shared-source-packager.md`
4. `docs/tokenizer-abi.md`
5. `docs/phase-2b-report.md`
6. `proofs/phase-2b.json`
7. `proofs/phase-2b-memory.json`
8. `asm/atom-tokenizer.asm`
9. `test/tokenizer.test.mjs`
10. `test/tokenizer-support.mjs`

Authority order is:

1. the project owner's latest written decision;
2. the shared source-packager design;
3. the implementation plan;
4. Atom's existing ABIs and proof manifests;
5. current Atom code;
6. AZM for instruction encoding and assembler behavior;
7. Nucleus as prior art, not as authority for this implementation.

If two authorities conflict, stop and report the exact conflict. Do not blend
them into a third design.

## Latest repository-boundary decision

The host implementation belongs in Atom for now.

Language-neutral code goes under:

```text
src/host/source-packager/
```

Atom-specific preprocessing goes under:

```text
src/host/atom/
```

The neutral directory is an extraction seam for a future Debug80 package or
app. It may import Node built-ins and its own modules. It must not import Atom
syntax, Atom token definitions, Z80 assembler code, or Nucleus code.

Do not create a Debug80 package during this assignment. Do not duplicate the
implementation in Nucleus. Atom and Nucleus will synchronize the contract from
time to time while the Nucleus rewrite is in progress.

## Settled behavior

The coding work must preserve these decisions:

- The resident assembler remains filesystem-unaware and consumes a stream of
  distinct source parts.
- The host resolves dependencies in deterministic depth-first postorder.
- An included file appears once, retains its own logical identity, and is never
  pasted anonymously into its importer.
- SP1 is the portable, strict, line-oriented source plan. It remains independent
  of Atom syntax.
- Atom host directives are bare `%include`, `%define`, `%if`, `%else`, and
  `%endif` lines.
- A directive begins when `%` follows only horizontal space at logical line
  start and the next byte is an ASCII letter. `%1` remains a binary literal and
  infix `%` remains remainder.
- The host removes directives and inactive source by equal-length masking:
  every non-newline byte becomes ASCII space; CR and LF bytes remain unchanged.
- `%define` creates an immutable host value. It performs no textual
  substitution and does not create an Atom `EQU` symbol.
- Source definitions are allowed only in the entry preprocessing header.
  Imported parts may test the frozen environment but may not define values.
- `%include` is import-once. An inactive include adds no graph edge.
- Atom accepts decimal, `$` hexadecimal, `%` binary, Intel `H` hexadecimal, and
  Intel `B` binary values in host conditions and ordinary active source.
- A leaked host directive must fail closed in the resident tokenizer.
- Host resolution completes before the later resident compiler/output adapter
  is invoked. This assignment does not design that streaming output lifecycle.

Do not add macros, token substitution, C-style repeated includes, namespaces,
exports, search paths, globs, remote dependencies, listing output, D8 output,
Intel HEX output, or assembler-visible module machinery.

## Execution route

The implementation plan contains ten test-first tasks. Execute them in order.
The dependency structure matters:

```text
neutral boundary
    -> SP1 codec
    -> identities and snapshots
    -> dependency graph and capacities
    -> placement, provenance, atomic SP1 publication
    -> Atom directive profile and masking
    -> resident numeric syntax and leaked-directive guard
    -> Atom composition and end-to-end preparation proofs
    -> documentation and adversarial review
```

Use `superpowers:executing-plans` for the implementation. Use
`superpowers:test-driven-development` for every feature or defect. Use
`z80-engineering` for the resident tokenizer change, proof review, measurement,
and final adversarial audit. Read the Z80 correctness battery before modifying
the tokenizer and the size battery before interpreting byte changes.

Do not implement several plan tasks and test them at the end. Each behavior
starts with a failing discriminator, followed by the smallest implementation,
focused verification, then a focused commit.

## Worktree and dependency setup

Atom's package uses sibling `file:../debug80/...` dependencies. A standalone
Atom worktree under `/tmp` will fail with `ERR_MODULE_NOT_FOUND` unless a
Debug80 checkout exists beside it.

Use this layout:

```text
/tmp/atom-host-packager-work/
    atom/       writable Atom implementation worktree
    debug80/    frozen dependency checkout
```

Create it with:

```sh
git -C /Users/johnhardy/projects/atom fetch origin
mkdir -p /tmp/atom-host-packager-work
git clone --branch main --single-branch https://github.com/jhlagado/debug80.git /tmp/atom-host-packager-work/debug80
git -C /Users/johnhardy/projects/atom worktree add -b codex/atom-host-packager /tmp/atom-host-packager-work/atom origin/codex/shared-source-packager-contract
npm install --prefix /tmp/atom-host-packager-work/debug80
npm install --prefix /tmp/atom-host-packager-work/atom
```

Record both branch/HEAD pairs immediately. Confirm both worktrees are clean.
Never stage, commit, or push from the frozen Debug80 checkout.

The handover worktree could not reproduce Atom proofs because it had no sibling
Debug80 checkout or installed `@jhlagado/azm`. The observed error was
`ERR_MODULE_NOT_FOUND`, not an Atom proof failure. Establish the layout above
before recording a correctness baseline.

## First checkpoint

Before changing source, run from the Atom implementation worktree:

```sh
npm test
npm run measure:tokenizer
git status --short --branch
```

Record the actual Node version, Debug80 HEAD, AZM tree, runtime tree, proof
counts, and tokenizer measurement. The current package declares Node 20 or
newer. Do not treat a newer local Node version as the project baseline without
recording it.

The last committed Phase 2b tokenizer evidence is:

| Account | Classification | Value |
| --- | --- | ---: |
| Rule-driven tokenizer code | Measured | 1,018 bytes |
| Immutable tokenizer tables | Measured | 33 bytes |
| Tokenizer code and tables | Measured | 1,051 bytes |
| Fixed tokenizer workspace | Measured | 32 bytes |
| Token record | Measured | 9 bytes |
| Longest recorded `AtomTokenizerNext` path | Measured | 24,619 instructions |
| Longest recorded `AtomTokenizerNext` path | Measured | 277,004 T-states |

Reproduce these values before changing the resident scanner. If the clean
baseline differs, stop and identify the source, assembler, runtime, or Node
revision responsible.

## Host implementation contract

The neutral host layer owns:

- strict SP1 parsing and canonical LF serialization;
- physical, dependency, and logical source identities;
- project-root and symlink confinement;
- immutable source snapshots;
- deterministic dependency traversal, diamond deduplication, and complete
  cycle diagnostics;
- exact limits for parts, depth, logical path bytes, retained path bytes, and
  bank ordinal;
- logical-path-keyed placement;
- part provenance and direct original/compiler offset correspondence;
- atomic publication of a complete validated SP1 file.

The Atom layer owns:

- numeric literal parsing for host conditions;
- directive recognition and exact diagnostics;
- entry definition collection and environment freezing;
- conditional structure and active include selection;
- equal-length masking;
- composition of the Atom profile with the neutral resolver.

Keep one implementation of each concern. `resolve-atom-project.mjs` is a thin
composition module, not a second path resolver, graph walker, masker, placement
join, or SP1 writer.

## Proof obligations

Every required proof is enumerated in the design and plan. The most important
wrong implementations to distinguish are:

- a diamond emits a shared dependency twice;
- traversal order changes the canonical logical identity;
- a repeated direct include is silently treated as a diamond;
- a symlink or case alias escapes project identity checks;
- a cycle diagnostic omits one edge or its source location;
- SP1 accepts a noncanonical integer, lone CR, truncated `END`, trailing byte,
  invalid component, or count mismatch;
- an exact capacity passes one unit beyond its limit;
- placement follows ordinal position instead of logical identity;
- the resolver scans one file version and compiles a later version;
- masking changes source length, CR/LF, or an active source byte;
- an inactive include contributes a graph edge;
- an unknown or leaked directive becomes ordinary Atom source;
- `%define DEBUG %1` is mistaken for a directive marker followed by a value;
- `0FFFFH` or `01110111B` differs from `$FFFF` or `%01110111`;
- failure replaces a previously committed SP1 file;
- the resident tokenizer writes outside its workspace, changes source/code,
  corrupts SP/return PC, or violates a register contract.

For the Z80 tokenizer, retain the existing proof strength:

- strict AZM register contracts;
- exact return PC and stack pointer;
- two-sided stack and source canaries;
- immutable resident-code checks;
- complete 64 KiB unexpected-write audit;
- unchanged caller source;
- IY preservation;
- token-record failure atomicity;
- exact diagnostic part and byte offset;
- assembler-derived memory extents;
- recorded instruction and T-state budgets.

Do not run automatic `.routine` annotation generation and accept its output
wholesale. If a contract changes, inspect every changed annotation against the
actual callers and hardware flag behavior.

## Resident numeric scanner rule

The present tokenizer accepts digit-led decimal immediately, so it rejects
Intel suffix forms. Replace that decision with maximal digit/name lookahead,
then select exactly one grammar:

- final `H` or `h`: the body begins with a decimal digit and every body byte is
  hexadecimal;
- final `B` or `b`: every body byte is `0` or `1`;
- no suffix: every byte is decimal;
- any other name continuation invalidates the complete token.

Select the grammar before accumulation. This prevents `01110111B` from
overflowing as decimal before the suffix is seen. Check 16-bit overflow during
accumulation. Preserve the previous token record on every failure. Measure the
code, immutable data, workspace, instruction, and cycle deltas separately.

## Checkpoint and Git rules

The project owner requires a get, commit, and push at the end of every
checkpoint.

For each checkpoint:

1. run the focused tests;
2. run the broader proof command proportional to the risk;
3. record measurements when resident Z80 bytes or paths changed;
4. fetch the remote;
5. rebase or fast-forward deliberately;
6. rerun affected proofs after integration;
7. commit only the checkpoint files;
8. push the implementation branch;
9. report branch, HEAD, proof result, measurement result, and next task.

Do not commit generated dependency output, unrelated worktree changes, or any
Debug80/Nucleus source. Never change a proof budget merely to obtain green
output. Budgets follow reproduced measurements with explicit slack.

## Completion gate

The work is complete when:

- all ten implementation-plan tasks are complete;
- `npm run test:host` passes;
- the complete `npm test` strict-contract suite passes;
- `npm run measure:tokenizer` reproduces the committed measurements;
- the source-packager boundary test proves no Atom import in neutral modules;
- every design proof bullet maps to a named test or is explicitly deferred to
  the later resident streaming adapter;
- a read-only adversarial review using `z80-engineering` has no unresolved
  correctness finding;
- Debug80 and Nucleus have no source change from this assignment;
- `codex/atom-host-packager` is clean, committed, and pushed.

The final report must separate **Measured**, **Projected**, and **Hypothesis**.
Include Atom and Debug80 branch/HEAD values, host/full proof counts, tokenizer
byte/workspace/instruction/cycle deltas, review findings and dispositions, the
implemented feature list, and the deliberately deferred streaming lifecycle.

## Stop conditions

Stop and ask the project owner when:

- the approved design and current code require incompatible semantics;
- the implementation requires a Debug80 or Nucleus source change;
- SP1 needs a wire-format revision;
- a host choice changes resident assembler syntax beyond the approved numeric
  suffix and leaked-directive rules;
- an upstream rebase changes Atom's tokenizer ABI, proof memory map, dependency
  pins, or register-contract model;
- a required proof cannot distinguish a plausible wrong implementation.

Do not broaden the assignment to the resident output lifecycle, global/private
labels, `EQU` or essential directives, self-assembly, listing, D8, Intel HEX,
or module/import machinery. Those are separate checkpoints after this host
preparation boundary is reviewed.
