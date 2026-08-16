# Atom Host Source Packager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Use z80-engineering for Task 8 and every Atom proof or measurement change.

**Goal:** Build Atom's own GPL host-side dependency resolver, SP1 source-plan support, `%` preprocessor, and equal-length source masker, while preserving a clean seam for eventual extraction into a Debug80 package or app.

**Architecture:** All implementation in this checkpoint lives in Atom. Language-neutral modules under `src/host/source-packager/` own source identity, confined filesystem access, deterministic graph resolution, placement, provenance, SP1, and atomic source-plan publication. Atom-specific modules under `src/host/atom/` own `%include`, `%define`, conditionals, literals, and masking. The neutral directory imports only Node built-ins and its own files; it never imports Atom syntax or assembler code. This is the future extraction seam. Debug80 and Nucleus remain read-only synchronization references until both projects' host requirements stabilize.

**Tech Stack:** Node.js 20+, ESM JavaScript, JSDoc contracts, `node:test`, Z80 assembly built by AZM, Debug80 runtime proofs, Git worktrees.

---

## Scope and authority

Implement the approved contract in `docs/superpowers/specs/2026-08-16-shared-source-packager-design.md` through the Node preparation boundary.

- Atom design baseline: `jhlagado/atom`, `origin/main@9585767ede261d732955016abd66a78e3c69d0c8`.
- Planning branch before this correction: `codex/shared-source-packager-contract@4b11f45`.
- Debug80 is read-only. Its observed `origin/main` on 2026-08-16 was `3f2adb669bb9e7888305c623f8c843054c3dd111`.
- The active Nucleus rewrite is read-only and may change radically.

The Atom-local implementation is intentional, not an accidental fork of a shared package. Synchronization happens at the documented contract and SP1 wire format. Extraction into Debug80 is a later repository move after Atom and Nucleus have measured their needs.

Definition of done:

- Atom has a language-neutral host submodule with no Atom-specific imports.
- SP1, identities, confinement, graph resolution, capacities, placement, provenance, snapshot consistency, and atomic plan publication have positive and negative proofs.
- Atom resolves `%include`, `%define`, `%if`, `%else`, and `%endif`, masks without moving offsets, and rejects malformed or leaked preprocessing.
- Atom's resident tokenizer accepts decimal, `$` hexadecimal, `%` binary, `H` hexadecimal, and `B` binary spellings with identical 16-bit boundaries.
- Explicit ordered parts and resolver-produced parts have byte-identical compiler inputs and source attribution at the preparation boundary.
- Atom's complete strict-contract proof suite passes, measurements are updated from observed output, and the branch is fetched, committed, and pushed.

Out of scope:

- moving code into Debug80 or adding a Debug80 package/app;
- changing Nucleus or adding a Nucleus adapter;
- a Z80 filesystem, graph resolver, or SP1 reader;
- Atom's resident multipart/output lifecycle;
- bare `EQU`, `ORG`, `DB`, `DW`, and `DS` parsing;
- private-label and symbol-table semantics;
- the ephemeral Atom-to-AZM translator;
- listing, D8, Intel HEX, modules, or assembler-visible imports.

## Module boundary to preserve

```text
src/host/source-packager/
    errors.mjs
    source-plan.mjs
    node-source-reader.mjs
    resolver.mjs
    placement.mjs
    atomic-plan-writer.mjs
    index.mjs

src/host/atom/
    literals.mjs
    directives.mjs
    source-profile.mjs

src/host/resolve-atom-project.mjs
```

Rules for later extraction:

- `source-packager/` imports only Node built-ins or another file in that directory.
- It accepts language behavior through a profile object; it never recognizes `%` or `//%` itself.
- Its exported values use logical identities and byte arrays, never Atom token ordinals.
- Atom-specific tests may import neutral exports; neutral tests may not import Atom modules.
- No new runtime dependency is introduced for this checkpoint.

The stable conceptual profile contract is represented with JSDoc:

```js
/**
 * @typedef {{logicalIdentity: string, offset: number, line: number, column: number}} SourceLocation
 * @typedef {{specifier: string, location: SourceLocation}} DependencyReference
 * @typedef {{start: number, end: number}} ByteRange
 * @typedef {{
 *   compilerBytes: Uint8Array,
 *   dependencies: readonly DependencyReference[],
 *   maskedRanges: readonly ByteRange[]
 * }} ProfilePart
 * @typedef {{
 *   inspectEntry(input: ProfileInput, configuration: unknown): ProfilePart & {state: unknown},
 *   inspectDependency(input: ProfileInput, state: unknown): ProfilePart
 * }} SourceProfile
 */
```

The public Atom composition remains preparation-only:

```js
export async function resolveAtomProject({
  root,
  entry,
  definitions = {},
  placement = { defaultBank: 0, banks: {} },
  limits,
}) {
  const reader = await createNodeSourceReader(root);
  return resolveSourceProject({
    reader,
    entry,
    profile: createAtomSourceProfile(),
    configuration: { definitions },
    placement,
    limits,
  });
}
```

No function in this plan compiles, links, or publishes an Atom object.

### Task 1: Create a clean Atom implementation worktree

**Files:** None.

**Step 1: Fetch and record the planning checkpoint**

```bash
git -C /Users/johnhardy/projects/atom fetch origin
git -C /Users/johnhardy/projects/atom rev-parse origin/codex/shared-source-packager-contract
git -C /Users/johnhardy/projects/atom status --short
```

Expected: the remote design branch contains this corrected plan. Existing changes in other worktrees remain untouched.

**Step 2: Create sibling Atom and frozen-dependency checkouts**

```bash
mkdir -p /tmp/atom-host-packager-work
git clone --branch main --single-branch https://github.com/jhlagado/debug80.git /tmp/atom-host-packager-work/debug80
git -C /Users/johnhardy/projects/atom worktree add -b codex/atom-host-packager /tmp/atom-host-packager-work/atom origin/codex/shared-source-packager-contract
npm install --prefix /tmp/atom-host-packager-work/debug80
npm install --prefix /tmp/atom-host-packager-work/atom
```

Expected: Atom's existing `file:../debug80/...` dependencies resolve against the
sibling checkout. Record the Debug80 branch and HEAD, then treat that checkout
as a frozen build dependency: make no source change, commit, or push there.
The Atom worktree is clean and install does not alter `package-lock.json` before
planned script changes.

**Step 3: Record the exact start**

```bash
git -C /tmp/atom-host-packager-work/debug80 branch --show-current
git -C /tmp/atom-host-packager-work/debug80 rev-parse HEAD
git -C /tmp/atom-host-packager-work/atom branch --show-current
git -C /tmp/atom-host-packager-work/atom rev-parse HEAD
git -C /tmp/atom-host-packager-work/atom status --short --branch
```

Append these values to the implementation log before changing source.

### Task 2: Establish the Atom-local neutral module boundary

**Files:**

- Create: `src/host/source-packager/errors.mjs`
- Create: `src/host/source-packager/index.mjs`
- Create: `src/host/source-packager/README.md`
- Create: `test/host-source-packager-boundary.test.mjs`
- Modify: `package.json`

**Step 1: Write the failing boundary test**

```js
import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

test("neutral host modules do not import Atom implementation", () => {
  for (const name of fs.readdirSync("src/host/source-packager")) {
    if (!name.endsWith(".mjs")) continue;
    const source = fs.readFileSync(`src/host/source-packager/${name}`, "utf8");
    assert.doesNotMatch(source, /from\s+["'][^"']*(?:\/atom\/|atom-token|atom-parser)/i);
  }
});
```

Add a second test that imports `SourcePackagerError` and verifies `{category, code, location}`.

**Step 2: Run the focused test and observe failure**

```bash
node --test test/host-source-packager-boundary.test.mjs
```

Expected: FAIL because the neutral module does not exist.

**Step 3: Add the module and scripts**

Export a structured error:

```js
export class SourcePackagerError extends Error {
  constructor(category, code, message, location) {
    super(message);
    this.name = "SourcePackagerError";
    this.category = category;
    this.code = code;
    if (location !== undefined) this.location = Object.freeze({ ...location });
  }
}
```

Add scripts:

```json
"test:host": "node --test test/host-*.test.mjs"
```

Document that the directory is provisional Atom-owned code intended for later extraction, not a published package.

**Step 4: Run and commit**

```bash
npm run test:host
git add package.json src/host/source-packager test/host-source-packager-boundary.test.mjs
git commit -m "Establish Atom host packaging boundary"
```

Expected: host tests PASS.

### Task 3: Implement the strict SP1 codec

**Files:**

- Create: `src/host/source-packager/source-plan.mjs`
- Create: `test/host-source-plan.test.mjs`
- Modify: `src/host/source-packager/index.mjs`

**Step 1: Write failing canonical tests**

Test LF generation and LF/CRLF parsing:

```js
for (const newline of ["\n", "\r\n"]) {
  const bytes = new TextEncoder().encode(
    ["SP1 2", "P 1 lib/a.asm", "P 0 main.asm", "END", ""].join(newline),
  );
  assert.deepEqual(parseSourcePlan(bytes, generousLimits), {
    records: [
      { bank: 1, logicalIdentity: "lib/a.asm" },
      { bank: 0, logicalIdentity: "main.asm" },
    ],
  });
}
```

Assert serialization is exactly `SP1 2\nP 1 lib/a.asm\nP 0 main.asm\nEND\n`.

Reject count 0/256, leading-zero count or bank, bank 256, count mismatch, missing/misspelled `END`, blank or comment lines, lone CR, absolute/backslash/colon paths, empty/`.`/`..` components, whitespace, non-ASCII bytes, truncation, and trailing records or bytes.

Pass exactly 255 records and fail 256; pass a 255-byte path and fail 256; pass bank 255 and fail 256. Apply caller limits below wire limits.

**Step 2: Observe failure**

```bash
node --test test/host-source-plan.test.mjs
```

Expected: FAIL because codec exports do not exist.

**Step 3: Implement byte-strict parsing**

Reject non-ASCII before decoding. Validate canonical decimal spelling before conversion. Validate the entire file before returning. Always serialize LF with one final newline.

**Step 4: Verify and commit**

```bash
node --test test/host-source-plan.test.mjs
git add src/host/source-packager test/host-source-plan.test.mjs
git commit -m "Implement strict SP1 source plans"
```

### Task 4: Implement confined identities and immutable snapshots

**Files:**

- Create: `src/host/source-packager/node-source-reader.mjs`
- Create: `test/host-node-source-reader.test.mjs`
- Modify: `src/host/source-packager/index.mjs`

**Step 1: Write failing filesystem tests**

Under `mkdtemp`, prove:

- relative entry/dependency resolution returns physical, dependency, and normalized `/` logical identities;
- absolute paths and `../` escapes fail;
- symlink escapes fail after `realpath` confinement;
- aliases to one file get one deterministic identity or a diagnostic;
- case-conflicting aliases fail through an injectable filesystem seam on every OS;
- relocating identical trees preserves logical identities;
- each physical file is read once and later disk mutation cannot change its returned snapshot.

The returned value is:

```js
{
  physicalPath,
  dependencyIdentity,
  logicalIdentity,
  originalBytes: Uint8Array,
}
```

**Step 2: Observe failure**

```bash
node --test test/host-node-source-reader.test.mjs
```

Expected: FAIL because `createNodeSourceReader` is absent.

**Step 3: Implement confinement correctly**

Resolve and `realpath` the root once. Use `path.relative(realRoot, realPath)` for containment, not a string prefix. Verify requested component case against directory entries where case folding is possible. Cache owned byte snapshots by dependency identity.

**Step 4: Verify and commit**

```bash
node --test test/host-node-source-reader.test.mjs
git add src/host/source-packager test/host-node-source-reader.test.mjs
git commit -m "Add confined source identity reader"
```

### Task 5: Resolve deterministic graphs and enforce capacities

**Files:**

- Create: `src/host/source-packager/resolver.mjs`
- Create: `src/host/source-packager/passthrough-profile.mjs`
- Create: `test/host-resolver.test.mjs`
- Modify: `src/host/source-packager/index.mjs`

**Step 1: Write failing graph tests with an in-memory reader**

For this diamond:

```text
main -> display -> hardware
     -> input   -> hardware
```

assert `hardware`, `display`, `input`, `main`, one shared part, and sibling source order. Add typed failures for repeated direct dependency, missing source, alias identity, and a complete cycle whose diagnostic contains every edge and source location.

Pass exactly at and fail one beyond each limit: part count, recursive depth, logical path bytes, and total retained path bytes.

```js
export const NODE_SOURCE_LIMITS = Object.freeze({
  maxParts: 255,
  maxDepth: 64,
  maxLogicalPathBytes: 255,
  maxRetainedPathBytes: 64 * 1024,
  maxBank: 255,
});
```

**Step 2: Observe failure**

```bash
node --test test/host-resolver.test.mjs
```

Expected: FAIL because the resolver is absent.

**Step 3: Implement entry-first inspection and postorder**

Inspect the entry first to freeze profile state, then walk active dependencies depth-first. Maintain explicit `visiting`, `visited`, and edge-stack state. Reject repeated direct dependency before diamond deduplication. Append an importer only after its dependencies.

The passthrough profile returns `compilerBytes === originalBytes`, an empty dependency list, and empty masked ranges. Prove reference identity as well as content equality.

**Step 4: Verify and commit**

```bash
node --test test/host-resolver.test.mjs
git add src/host/source-packager test/host-resolver.test.mjs
git commit -m "Resolve deterministic source graphs"
```

### Task 6: Join placement, provenance, and atomic SP1 publication

**Files:**

- Create: `src/host/source-packager/placement.mjs`
- Create: `src/host/source-packager/atomic-plan-writer.mjs`
- Create: `test/host-placement.test.mjs`
- Create: `test/host-provenance.test.mjs`
- Create: `test/host-atomic-plan-writer.test.mjs`
- Modify: `src/host/source-packager/resolver.mjs`
- Modify: `src/host/source-packager/index.mjs`

**Step 1: Write failing placement proofs**

Prove that a bank keyed by `lib/hardware.asm` follows that source after unrelated order changes while ordinal bank arrays update. Cover default bank, bank 0/255, missing default, out-of-range bank, conflicting assignment, unreachable assignment, and nonexistent mapping path.

**Step 2: Write failing provenance proofs**

Every part exposes logical/diagnostic/physical identity, ordinal, bank, original length, masked ranges, dependency locations, and include stack. Prove compiler offset `n` maps directly to original offset `n`. Freeze or defensively copy returned records and arrays.

**Step 3: Write failing publication proofs**

With an existing `sources.sp1` containing `old`, prove success replaces it and serialization, validation, write, or rename failure leaves it byte-identical. No temporary file remains after handled failure. Validate the exact bytes before opening a temporary output.

**Step 4: Implement complete-graph placement and same-directory rename**

Join placement only after graph completion, assign ordinals, serialize SP1, and parse it again under the same limits. Publish through an exclusively created same-directory temporary file followed by rename. Cleanup only that exact temporary file.

**Step 5: Verify and commit**

```bash
node --test test/host-placement.test.mjs test/host-provenance.test.mjs test/host-atomic-plan-writer.test.mjs
git add src/host/source-packager test/host-placement.test.mjs test/host-provenance.test.mjs test/host-atomic-plan-writer.test.mjs
git commit -m "Add placement provenance and atomic plans"
```

### Task 7: Implement Atom directives, literals, and masking

**Files:**

- Create: `src/host/atom/literals.mjs`
- Create: `src/host/atom/directives.mjs`
- Create: `src/host/atom/source-profile.mjs`
- Create: `test/host-atom-literals.test.mjs`
- Create: `test/host-atom-directives.test.mjs`
- Create: `test/host-atom-masking.test.mjs`

**Step 1: Write failing literal tests**

```js
for (const [source, value] of [
  ["65535", 0xffff], ["$FFFF", 0xffff], ["%01110111", 0x77],
  ["0FFFFH", 0xffff], ["0ffffh", 0xffff], ["01110111B", 0x77],
]) assert.equal(parseAtomPreprocessorValue(source), value);
```

Reject `65536`, `$10000`, malformed binary, `10000H`, `FFFFH`, `12B`, signs, operators, and trailing tokens. Parse `DEBUG` as a name, not a literal.

**Step 2: Write failing directive tests**

Cover case-insensitive directives/names, `%define DEBUG %1`, project definitions before source definitions, duplicate definitions even when equal, imported-file definitions, undefined names, extra condition tokens, unknown directives, duplicate/unmatched `%else`, unmatched/unterminated `%endif`, and illegal body `%include`/`%define`.

A directive marker follows only ASCII SP/HT and is followed by a letter. Prove `%1`, `A % B`, and comments containing `%if` are ordinary Atom source.

**Step 3: Write failing masking proofs**

For LF and CRLF, assert equal lengths, unchanged CR/LF, spaces over every directive and inactive ordinary byte, and byte-identical active source. Cover nested true/false branches, inactive includes, and structural validation inside false branches.

**Step 4: Observe failure**

```bash
node --test test/host-atom-literals.test.mjs test/host-atom-directives.test.mjs test/host-atom-masking.test.mjs
```

Expected: FAIL because Atom profile modules are absent.

**Step 5: Implement byte-offset scanning**

Retain `{start, contentEnd, newlineEnd, line}` for each original line. Copy input once; masking writes `0x20` only before CR/LF. Track `{parentActive, conditionTrue, branchActive, elseSeen, directiveLocation}` per conditional level.

The first ordinary line closes the preprocessing header even in an inactive branch. Entry source definitions stop before the first include, conditional, or ordinary line. Imported parts cannot define. Freeze the environment before graph traversal.

**Step 6: Verify and commit**

```bash
node --test test/host-atom-literals.test.mjs test/host-atom-directives.test.mjs test/host-atom-masking.test.mjs
git add src/host/atom test/host-atom-literals.test.mjs test/host-atom-directives.test.mjs test/host-atom-masking.test.mjs
git commit -m "Add Atom host preprocessing profile"
```

### Task 8: Add resident Intel-suffix literals and reject leaked directives

**Files:**

- Modify: `asm/atom-tokenizer.asm`
- Modify: `test/tokenizer.test.mjs`
- Modify: `test/tokenizer-support.mjs`
- Modify: `test/measure-tokenizer.mjs`
- Modify: `proofs/phase-2b.json`
- Modify only if measured extents change: `proofs/phase-2b-memory.json`

Use `z80-engineering` and `superpowers:test-driven-development` for this task.

**Step 1: Replace the old negative cases with failing proofs**

Add positive `0FFFFH`, `0ffffh`, `01110111B`, and lowercase suffix cases, equivalent values versus `$FFFF` and `%01110111`, leading zeros, overflow, malformed suffixes, and failure atomicity.

Add `AtomTokenStatusUnprocessedDirective` cases for line-start `%include`, indented `%IF`, and `%endif` after EOL. Prove `%1`, `LD A,%1`, and `A % B` retain binary/remainder behavior.

**Step 2: Observe the native failures**

```bash
node --test test/tokenizer.test.mjs
```

Expected: suffix literals report `INVALID_NUMBER`; leaked directives do not yet report the new status.

**Step 3: Implement one shared digit-led scanner**

Perform maximal digit/name lookahead, then choose exactly one grammar before accumulation:

- final `H`/`h`: body starts with a decimal digit and contains only hex digits;
- final `B`/`b`: body contains only `0`/`1`;
- no suffix: body contains only decimal digits;
- every other continuation invalidates the whole token.

Accumulate only after selection, detect 16-bit overflow, preserve the token record on failure, and allocate no source copy.

At the percent path, a following letter while `AtomTokenLineHasToken` is zero returns `AtomTokenStatusUnprocessedDirective`. Preserve infix remainder and `%` binary behavior. Update strict `.routine` annotations deliberately.

**Step 4: Run all correctness proofs and measure**

```bash
npm test
npm run measure:tokenizer
```

Expected: strict register contracts, stack balance, canaries, immutable code, full-memory write audit, and budgets pass. Update measured observations and budget slack only from emitted values. Report rule-code, tables, total resident code, workspace, instructions, cycles, and deltas; do not compress to hide growth.

**Step 5: Commit**

```bash
git add asm/atom-tokenizer.asm test/tokenizer.test.mjs test/tokenizer-support.mjs test/measure-tokenizer.mjs proofs/phase-2b.json proofs/phase-2b-memory.json
git commit -m "Accept Intel suffix literals in Atom source"
```

### Task 9: Compose the Atom project resolver and prove the boundary

**Files:**

- Create: `src/host/resolve-atom-project.mjs`
- Create: `test/host-resolve-atom-project.test.mjs`
- Create: `test/fixtures/source-packager/diamond/main.asm`
- Create: `test/fixtures/source-packager/diamond/display.asm`
- Create: `test/fixtures/source-packager/diamond/input.asm`
- Create: `test/fixtures/source-packager/diamond/hardware.asm`

**Step 1: Write failing end-to-end preparation tests**

The fixture uses mixed-case directives, active/inactive includes, LF/CRLF, and an entry definition. Assert:

- order is hardware, display, input, main, each as a distinct part;
- ordinals/banks agree with generated and reparsed SP1;
- original/compiler lengths and offset attribution are exact;
- relocation preserves logical identities, SP1, and compiler bytes;
- explicit ordered parts and resolver parts have byte-identical compiler streams/provenance;
- later filesystem mutation cannot alter snapshots;
- preprocessing failure returns no project, publishes no partial artifact, and preserves existing SP1.

Enumerate repeated import, missing source, root escape, alias, cycle, unknown directive, undefined condition, inactive include selection, imbalance, every capacity, and invalid placement.

**Step 2: Observe failure**

```bash
node --test test/host-resolve-atom-project.test.mjs
```

Expected: FAIL because `resolveAtomProject` is absent.

**Step 3: Implement only composition**

Create the reader, Atom profile, and shared resolver request. Do not duplicate path, graph, placement, masking, or SP1 code. Freeze input configuration and returned records.

**Step 4: Verify and commit**

```bash
npm run test:host
npm test
git add src/host test/host-resolve-atom-project.test.mjs test/fixtures/source-packager
git commit -m "Resolve Atom projects on the host"
```

### Task 10: Document, adversarially review, get, commit, and push

**Files:**

- Create: `docs/host-source-packaging.md`
- Modify: `src/host/source-packager/README.md`
- Modify if the new host entry point belongs in the overview: `README.md`
- Modify only reproduced review findings elsewhere.

**Step 1: Document enforced behavior and extraction policy**

Document SP1, three identities, resolution order, capacities, placement, snapshots, atomic plans, `%` grammar, immutable definitions, header/body rules, import-once, numeric spellings, masking, and `%define` not creating an assembler symbol.

Include:

```text
The source packager does not compile or publish an Atom object. It returns a
fully validated ordered set of source parts for the later streaming adapter.

The neutral source-packager modules are currently owned by Atom. They may move
to a Debug80 package or app after Atom and Nucleus host requirements stabilize.
```

**Step 2: Run complete verification**

```bash
npm run test:host
npm test
npm run measure:tokenizer
git diff --check
```

Expected: all tests and strict-contract proofs pass; measurement reproduces the recorded manifest.

**Step 3: Audit the approved proof set**

Map every bullet under the design's `Required proof set` to a named test. Record one deliberate boundary: resident compiler-output/listing/D8 equivalence awaits the streaming-adapter design, while prepared bytes and provenance are proved here.

Run:

```bash
rg -n 'TO''DO|TB''D|FIX''ME' src/host test/host-*.test.mjs docs/host-source-packaging.md
```

Expected: no unfinished markers.

**Step 4: Launch the required read-only adversarial review**

Ask a review agent to use the adversarial-review portion of `z80-engineering` and report file/line evidence for contract gaps, path/symlink escapes, graph mistakes, conditional masking, directive leakage, snapshot/atomicity faults, SP1 ambiguity, capacity off-by-ones, register contracts, stack/canary/memory proofs, measurement drift, GPL status, extraction-boundary violations, and unintended Debug80/Nucleus changes.

Reproduce each correctness finding with a failing test before fixing it.

**Step 5: Re-run complete verification and commit documentation/fixes**

```bash
npm run test:host
npm test
npm run measure:tokenizer
git diff --check
git add README.md docs/host-source-packaging.md src/host asm/atom-tokenizer.asm test proofs/phase-2b.json proofs/phase-2b-memory.json package.json package-lock.json
git commit -m "Document and harden Atom host packaging"
```

Skip the commit only if there are no changes.

**Step 6: Get upstream and re-prove**

```bash
git fetch origin
git rebase origin/main
npm run test:host
npm test
npm run measure:tokenizer
```

If overlapping upstream changes affect host code, tokenizer code, proof infrastructure, or dependency pins, resolve deliberately and run every command again.

**Step 7: Push the checkpoint**

```bash
git push -u origin codex/atom-host-packager
git status --short --branch
```

Expected: clean and up to date with the remote branch.

**Step 8: Report exact evidence**

Report branch/HEAD, host and full proof counts, measured tokenizer values and deltas, implemented/deferred contract items, review dispositions, and confirmation that Debug80 and Nucleus were untouched.

## Implementation log

Execution appends one short entry per checkpoint with date, fetched base, branch, HEAD, verification commands, measurement output, and push result. Numbers are labeled **Measured**, **Projected**, or **Hypothesis**.
