# Phase 2f Nucleus Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Atom's Nucleus-model instruction image and resolved patch output layer, prove it natively, and measure its resident cost.

**Architecture:** Atom calls proof- or operating-adapter implementations of the Nucleus image-byte, patch-byte, and patch-word sink operations. A new native module emits encoded instructions and resolves the existing six-byte pending records; the adapter retains NOBJ framing, spools, commit, abort, and publication.

**Tech Stack:** Z80 assembly built by frozen AZM, Debug80 runtime execution, Node.js differential and memory proofs, Nucleus NOBJ 0.1 authority.

---

### Task 1: Freeze the output proof boundary

**Files:**
- Create: `asm/output-proof.asm`
- Create: `test/output-support.mjs`
- Create: `test/output.test.mjs`

- [ ] Write a proof image that links the Phase 2e modules, declares the three Nucleus-model sink entries, and includes the not-yet-existing `atom-output.asm`.
- [ ] Write a host harness that assembles the image, executes public entries with exact return-PC/SP checks, and audits writes against named regions.
- [ ] Add the first instruction-image test for `LD A,$42` at `$4000`, expecting two image-byte operations at `$4000` and `$4001`.
- [ ] Run `node --test test/output.test.mjs` and verify that assembly fails because `asm/atom-output.asm` is absent.

### Task 2: Emit instruction image bytes

**Files:**
- Create: `asm/atom-output.asm`
- Modify: `asm/atom-parser.asm`
- Modify: `asm/output-proof.asm`
- Modify: `test/output-support.mjs`
- Modify: `test/output.test.mjs`

- [ ] Add a read-only parser reference preflight shared by `AtomParserQueueReferences` and the output layer.
- [ ] Implement `AtomOutputReset`, complete instruction capacity checking, scratch encoding, increasing image-byte sink calls, cursor publication, and post-image pending publication.
- [ ] Run `node --test test/output.test.mjs` and verify the concrete image test passes.
- [ ] Add failing tests for one- through four-byte instructions, unresolved two-field instructions, exact capacity, first rejected capacity, and injected sink failure at every byte position.
- [ ] Implement only the state and failure handling required by those tests, then rerun the focused test after each change.

### Task 3: Resolve pending patches

**Files:**
- Modify: `asm/atom-symbols.asm`
- Modify: `asm/atom-output.asm`
- Modify: `asm/output-proof.asm`
- Modify: `test/output-support.mjs`
- Modify: `test/output.test.mjs`

- [ ] Add failing tests that require non-destructive lookup of one pending record and unchanged state after lookup failure.
- [ ] Implement `AtomPendingPeek` without changing the settled six-byte record or historical `AtomPendingTake` behavior.
- [ ] Add failing byte, word, relative, and displacement patch tests with exact sink operations and pending reclamation.
- [ ] Implement signed-addend calculation, kind-specific range checks, Nucleus-model patch sink calls, and removal only after sink success.
- [ ] Add and pass boundary partitions for -128, 127, 255, 256, `$FFFF`, relative bases around `$0000`, and signed addends -128 and 127.
- [ ] Add and pass multiple-reference, descending-address, injected sink-failure, and range-failure tests that distinguish partial patch-spool state from pending-record state.

### Task 4: Establish strict correctness proofs

**Files:**
- Create: `proofs/phase-2f-memory.json`
- Create: `proofs/phase-2f.json`
- Modify: `asm/output-proof.asm`
- Modify: `package.json`
- Modify: `test/output-support.mjs`
- Modify: `test/output.test.mjs`

- [ ] Define a complete non-overlapping 64 KiB memory profile with exact component and workspace extents.
- [ ] Add two-sided canaries for output workspace, sink log, symbol arena, pending arena, source, record, and stack.
- [ ] Audit every write from every public output entry and every success, range, capacity, sink, and internal-failure path.
- [ ] Add named instruction and T-state budgets for reset, instruction emission, pending peek, and all patch kinds.
- [ ] Add `asm/output-proof.asm` to `npm run annotate:contracts`, regenerate contracts, and run AZM strict mode with zero contract errors.

### Task 5: Measure and document Phase 2f

**Files:**
- Create: `test/measure-output.mjs`
- Create: `docs/output-abi.md`
- Create: `docs/phase-2f-report.md`
- Modify: `README.md`
- Modify: `docs/symbol-abi.md`
- Modify: `docs/symbolic-parser-abi.md`
- Modify: `package.json`

- [ ] Derive output code, immutable data, fixed workspace, integrated resident total, and integrated workspace from assembled symbols.
- [ ] Record worst observed instructions and T-states for every public output entry.
- [ ] Label every reported number Measured, Projected, or Hypothesis and update the whole-assembler projection.
- [ ] Document the exact Nucleus sink boundary and state explicitly that the adapter owns NOBJ serialization and storage.
- [ ] Run the human-writing prose gate over every changed Markdown file and resolve every finding.

### Task 6: Verify and publish the checkpoint

**Files:**
- Verify all changed production, proof, test, and documentation files.

- [ ] Run `npm run annotate:contracts` and review its complete diff.
- [ ] Run `npm test` and require all historical and Phase 2f proofs to pass.
- [ ] Run `npm run measure:output` and reconcile every report number with fresh output.
- [ ] Run `npm run verify:dependencies`, `git diff --check`, and the documentation prose gate.
- [ ] Request an adversarial code review against the Phase 2f design, fix every confirmed critical or important finding test-first, and rerun the complete battery.
- [ ] Fetch Atom and Debug80, record branch and HEAD, reconcile with public `main`, commit intentionally, push, and verify the public GPL-3.0 repository and clean worktree.
