# Shared Source Packager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Use z80-engineering for Task 9 and every Atom proof or measurement change.

**Goal:** Build the public GPL Node reference implementation of the shared source-packager boundary, integrate Atom's `%` directive and equal-length masking profile, and add Atom's matching Intel-suffix numeric syntax and leaked-directive guard.

**Architecture:** A new language-neutral `@jhlagado/source-packager` package in Debug80 owns source identity, confined filesystem access, deterministic dependency resolution, placement, provenance, and the SP1 codec. Atom owns directive recognition, immutable definitions, conditional evaluation, masking, and the adapter that supplies the shared resolver with dependency edges and compiler bytes. The resolver snapshots every source exactly once, completes and validates the build before publishing SP1, and never calls the resident assembler. Nucleus adoption and the Z80-hosted implementation are separate plans because Nucleus is being rewritten and the resident streaming lifecycle is not yet designed.

**Tech Stack:** Node.js 20+, TypeScript 5.3 in Debug80, Vitest, Atom ESM JavaScript with `node:test`, Z80 assembly built by AZM, Debug80 runtime proofs, Git worktrees.

---

## Scope and repository baselines

This plan implements the approved contract in `docs/superpowers/specs/2026-08-16-shared-source-packager-design.md` through the Node preparation boundary.

- Atom design repository baseline: `jhlagado/atom`, `origin/main@9585767ede261d732955016abd66a78e3c69d0c8`.
- Atom planning branch: `codex/shared-source-packager-contract@6c980d413c7883aeedcdb294808bb06020522a4c`.
- Debug80 implementation baseline observed on 2026-08-16: `jhlagado/debug80`, `origin/main@3f2adb669bb9e7888305c623f8c843054c3dd111`.
- The dirty Nucleus rewrite worktree is not touched.

The implementation uses two sibling worktrees because Atom's development dependencies are relative `file:` dependencies:

```text
/tmp/atom-source-packager-implementation/
    atom/
    debug80/
```

Each task that changes a repository ends with a focused commit. At each checkpoint, fetch and fast-forward from the recorded upstream, run the stated verification, commit, and push. Never bundle unrelated existing worktree changes.

Definition of done for this plan:

- `@jhlagado/source-packager` is a public GPL workspace package with a typed API and no Atom or Nucleus syntax.
- SP1, identities, confinement, graph resolution, capacities, placement, provenance, snapshot consistency, and atomic plan publication have positive and negative proofs.
- Atom resolves `%include`, `%define`, `%if`, `%else`, and `%endif`, masks bytes without moving offsets, and rejects malformed or leaked preprocessing.
- Atom's resident tokenizer accepts decimal, `$` hexadecimal, `%` binary, `H` hexadecimal, and `B` binary spellings with identical 16-bit boundaries.
- The low-level explicit-parts path and resolver-produced parts have byte-identical inputs and provenance attribution at the preparation boundary.
- Debug80 and Atom verification pass from clean worktrees and both branches are pushed.

Not part of this plan:

- a Nucleus profile or edits to the active Nucleus rewrite;
- a Z80 filesystem, graph resolver, or SP1 reader;
- the resident Atom multipart/output lifecycle;
- bare `EQU`, `ORG`, `DB`, `DW`, and `DS` parsing;
- private-label or symbol-table semantics;
- the ephemeral Atom-to-AZM translator;
- listing, D8, Intel HEX, rich modules, or imports visible to the assembler.

## Public interfaces to hold stable

The shared package exports these shapes from `packages/source-packager/src/index.ts`:

```ts
export interface SourceLocation {
  readonly logicalIdentity: string;
  readonly offset: number;
  readonly line: number;
  readonly column: number;
}

export interface DependencyReference {
  readonly specifier: string;
  readonly location: SourceLocation;
}

export interface ByteRange {
  readonly start: number;
  readonly end: number;
}

export interface ProfilePart {
  readonly compilerBytes: Uint8Array;
  readonly dependencies: readonly DependencyReference[];
  readonly maskedRanges: readonly ByteRange[];
}

export interface SourceProfile<State, Configuration> {
  inspectEntry(input: ProfileInput, configuration: Configuration): ProfileEntry<State>;
  inspectDependency(input: ProfileInput, state: State): ProfilePart;
}

export interface ResolvedPart {
  readonly ordinal: number;
  readonly bank: number;
  readonly logicalIdentity: string;
  readonly originalBytes: Uint8Array;
  readonly compilerBytes: Uint8Array;
  readonly provenance: PartProvenance;
}

export async function resolveSourceProject<State, Configuration>(
  request: ResolveProjectRequest<State, Configuration>,
): Promise<ResolvedProject>;

export function parseSourcePlan(bytes: Uint8Array, limits: SourcePlanLimits): SourcePlan;
export function serializeSourcePlan(plan: SourcePlan): Uint8Array;
export async function writeSourcePlanAtomically(path: string, plan: SourcePlan): Promise<void>;
```

Atom exports its host boundary from `src/host/resolve-atom-project.mjs`:

```js
export async function resolveAtomProject({
  root,
  entry,
  definitions = {},
  placement = { defaultBank: 0, banks: {} },
  limits,
}) {
  return resolveSourceProject({
    reader: await createNodeSourceReader(root),
    entry,
    profile: createAtomSourceProfile(),
    configuration: { definitions },
    placement,
    limits,
  });
}
```

No API in this plan compiles, links, or publishes an Atom object. Successful resolution returns an immutable prepared project; a later streaming-lifecycle plan will consume it.

### Task 1: Create clean sibling implementation worktrees

**Files:**

- No source files changed.
- Record state in the implementation log section of this plan when executing.

**Step 1: Fetch both repositories and validate the exact starting points**

Run from the existing clean clones:

```bash
git -C /Users/johnhardy/projects/debug80 fetch origin
git -C /Users/johnhardy/projects/atom fetch origin
git -C /Users/johnhardy/projects/debug80 rev-parse origin/main
git -C /Users/johnhardy/projects/atom rev-parse origin/main
git -C /Users/johnhardy/projects/debug80 status --short
git -C /Users/johnhardy/projects/atom status --short
```

Expected: the two `rev-parse` commands identify the fetched baselines; any pre-existing changes remain in their original worktrees and are not modified.

**Step 2: Create sibling worktrees**

```bash
mkdir -p /tmp/atom-source-packager-implementation
git -C /Users/johnhardy/projects/debug80 worktree add -b codex/source-packager /tmp/atom-source-packager-implementation/debug80 origin/main
git -C /Users/johnhardy/projects/atom worktree add -b codex/source-packager /tmp/atom-source-packager-implementation/atom origin/main
```

Expected: both worktrees are clean and their paths are siblings.

**Step 3: Install the existing dependency graphs without changing source**

```bash
npm install --prefix /tmp/atom-source-packager-implementation/debug80
npm install --prefix /tmp/atom-source-packager-implementation/atom
```

Expected: both installs succeed. If lockfiles change before new dependencies are declared, stop and explain the toolchain drift rather than committing it.

### Task 2: Scaffold the shared GPL workspace package

**Files:**

- Create: Debug80 `packages/source-packager/package.json`
- Create: Debug80 `packages/source-packager/tsconfig.json`
- Create: Debug80 `packages/source-packager/LICENSE`
- Create: Debug80 `packages/source-packager/README.md`
- Create: Debug80 `packages/source-packager/src/index.ts`
- Create: Debug80 `packages/source-packager/test/package.test.ts`
- Modify: Debug80 `package.json`
- Modify: Debug80 `package-lock.json`

**Step 1: Write the failing package metadata test**

Create `packages/source-packager/test/package.test.ts`:

```ts
import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

describe("package publication contract", () => {
  it("is a public GPL package with the stable export", async () => {
    const manifest = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
    expect(manifest.name).toBe("@jhlagado/source-packager");
    expect(manifest.license).toBe("GPL-3.0-only");
    expect(manifest.private).not.toBe(true);
    expect(manifest.publishConfig).toEqual({ access: "public" });
    expect(manifest.exports["."].import).toBe("./dist/index.js");
  });
});
```

**Step 2: Run it to verify the package does not exist**

```bash
npm test -w @jhlagado/source-packager
```

Expected: FAIL because the workspace/package is absent.

**Step 3: Add the package skeleton**

Use the Debug80 runtime package's strict NodeNext conventions. `package.json` must include:

```json
{
  "name": "@jhlagado/source-packager",
  "version": "0.1.0",
  "description": "Portable source planning and dependency resolution for streaming language tools",
  "license": "GPL-3.0-only",
  "type": "module",
  "engines": { "node": ">=20" },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": { "types": "./dist/index.d.ts", "import": "./dist/index.js" },
    "./package.json": "./package.json"
  },
  "files": ["dist", "README.md", "LICENSE"],
  "publishConfig": { "access": "public" },
  "scripts": {
    "clean": "node --input-type=module -e \"import { rmSync } from 'node:fs'; rmSync('dist', { recursive: true, force: true })\"",
    "build": "npm run clean && tsc -p tsconfig.json",
    "typecheck": "tsc -p tsconfig.json --noEmit",
    "lint": "eslint src test --ext .ts",
    "format": "prettier --write \"src/**/*.ts\" \"test/**/*.ts\"",
    "format:check": "prettier --check \"src/**/*.ts\" \"test/**/*.ts\"",
    "pretest": "npm run build",
    "test": "vitest run",
    "prepack": "npm run build",
    "prepublishOnly": "npm run build"
  }
}
```

Copy the repository GPL-3.0-only text, not a license summary. Add the workspace to the root `build`, `typecheck`, and `test` command chains. Run `npm install` to update the lockfile.

**Step 4: Run package and workspace checks**

```bash
npm run build -w @jhlagado/source-packager
npm run typecheck -w @jhlagado/source-packager
npm test -w @jhlagado/source-packager
```

Expected: PASS; the test reports one passing publication contract.

**Step 5: Commit the scaffold**

```bash
git add package.json package-lock.json packages/source-packager
git commit -m "Add shared source-packager workspace"
```

### Task 3: Implement the strict SP1 codec

**Files:**

- Create: Debug80 `packages/source-packager/src/errors.ts`
- Create: Debug80 `packages/source-packager/src/source-plan.ts`
- Create: Debug80 `packages/source-packager/test/source-plan.test.ts`
- Modify: Debug80 `packages/source-packager/src/index.ts`

**Step 1: Write the failing canonical round-trip tests**

Test LF generation and LF/CRLF parsing:

```ts
it.each(["\n", "\r\n"])("parses a complete %j plan", (newline) => {
  const text = ["SP1 2", "P 1 lib/a.asm", "P 0 main.asm", "END", ""].join(newline);
  expect(parseSourcePlan(encode(text), generousLimits)).toEqual({
    records: [
      { bank: 1, logicalIdentity: "lib/a.asm" },
      { bank: 0, logicalIdentity: "main.asm" },
    ],
  });
});

it("serializes one canonical LF spelling", () => {
  expect(decode(serializeSourcePlan(plan))).toBe(
    "SP1 2\nP 1 lib/a.asm\nP 0 main.asm\nEND\n",
  );
});
```

Add a table that rejects: count zero, count 256, leading-zero count or bank, bank 256, count mismatch, missing or misspelled `END`, blank/comment lines, lone CR, absolute/backslash/colon paths, empty/`.`/`..` components, whitespace, non-ASCII bytes, truncation, and trailing records or bytes.

**Step 2: Run the focused test and observe failure**

```bash
npm test -w @jhlagado/source-packager -- source-plan.test.ts
```

Expected: FAIL because the codec exports do not exist.

**Step 3: Implement byte-oriented parsing and canonical serialization**

Define structured failures:

```ts
export type SourcePackagerErrorCategory =
  | "project"
  | "dependency"
  | "plan"
  | "preprocessing"
  | "output";

export class SourcePackagerError extends Error {
  constructor(
    readonly category: SourcePackagerErrorCategory,
    readonly code: string,
    message: string,
    readonly location?: SourceLocation,
  ) {
    super(message);
  }
}
```

Parse ASCII bytes directly or reject non-ASCII before decoding. Do not use permissive `parseInt`; validate canonical decimal spelling first. Validate the full file before returning records. Serializer always emits a final LF.

**Step 4: Add exact capacity boundary tests**

Pass 255 records and fail 256; pass a 255-byte path and fail 256; pass bank 255 and fail 256. Verify the parser applies caller limits lower than the wire maximum.

**Step 5: Run checks and commit**

```bash
npm test -w @jhlagado/source-packager -- source-plan.test.ts
npm run typecheck -w @jhlagado/source-packager
git add packages/source-packager
git commit -m "Implement strict SP1 source plans"
```

Expected: focused tests and typecheck PASS.

### Task 4: Implement confined identities and source snapshots

**Files:**

- Create: Debug80 `packages/source-packager/src/types.ts`
- Create: Debug80 `packages/source-packager/src/node-source-reader.ts`
- Create: Debug80 `packages/source-packager/test/node-source-reader.test.ts`
- Modify: Debug80 `packages/source-packager/src/index.ts`

**Step 1: Write failing filesystem identity tests**

Build fixtures under `mkdtemp` and prove:

- entry and relative dependency resolution produce normalized `/` logical identities;
- absolute paths and `../` root escapes fail before any source is returned;
- symlink escapes fail after `realpath` confinement;
- two spellings of one dependency yield one dependency identity and a deterministic logical identity;
- a case-conflicting alias is rejected even on a case-insensitive filesystem;
- relocating identical fixture trees preserves logical identities;
- each physical file is read once and the returned bytes are an owned snapshot.

Use an injectable filesystem seam for the case-insensitive spelling test so it is deterministic on Linux and macOS:

```ts
const reader = await createNodeSourceReader(root, {
  filesystem: recordingFilesystem,
  verifyCase: true,
});
```

**Step 2: Run the focused test and observe failure**

```bash
npm test -w @jhlagado/source-packager -- node-source-reader.test.ts
```

Expected: FAIL because `createNodeSourceReader` does not exist.

**Step 3: Implement the three-identity reader**

The reader returns:

```ts
export interface SourceSnapshot {
  readonly physicalPath: string;
  readonly dependencyIdentity: string;
  readonly logicalIdentity: string;
  readonly originalBytes: Uint8Array;
}
```

Resolve and `realpath` the root once. For each component, compare the requested spelling with the actual directory entry where the platform might fold case. Reject escaped real paths using `relative(realRoot, realPath)` rather than string prefix comparison. Cache snapshots by dependency identity and return cloned or immutable-owned bytes so later filesystem changes cannot alter the build.

**Step 4: Run checks and commit**

```bash
npm test -w @jhlagado/source-packager -- node-source-reader.test.ts
npm run typecheck -w @jhlagado/source-packager
git add packages/source-packager
git commit -m "Add confined source identity reader"
```

### Task 5: Implement deterministic graph resolution and capacities

**Files:**

- Create: Debug80 `packages/source-packager/src/resolver.ts`
- Create: Debug80 `packages/source-packager/src/passthrough-profile.ts`
- Create: Debug80 `packages/source-packager/test/resolver.test.ts`
- Modify: Debug80 `packages/source-packager/src/types.ts`
- Modify: Debug80 `packages/source-packager/src/index.ts`

**Step 1: Write failing graph tests using an in-memory reader**

Use a tiny directive-free profile fixture and an in-memory reader so graph semantics are isolated from Node paths. Cover:

```text
main -> display -> hardware
     -> input   -> hardware
```

Expected order: `hardware`, `display`, `input`, `main`. Assert the shared dependency occurs once and sibling order follows source order.

Add negative tests for repeated direct dependency, missing source, alias identity, and a complete cycle. The cycle diagnostic must preserve each logical source and dependency location in order.

**Step 2: Write exact limit tests**

For each caller limit, pass exactly at the limit and fail one beyond:

- part count;
- recursive dependency depth;
- logical path bytes;
- total retained logical-path bytes.

The default Node limits are explicit constants, not unlimited values:

```ts
export const NODE_SOURCE_LIMITS = Object.freeze({
  maxParts: 255,
  maxDepth: 64,
  maxLogicalPathBytes: 255,
  maxRetainedPathBytes: 64 * 1024,
  maxBank: 255,
});
```

**Step 3: Run the focused test and observe failure**

```bash
npm test -w @jhlagado/source-packager -- resolver.test.ts
```

Expected: FAIL because the resolver is absent.

**Step 4: Implement entry-first inspection and postorder emission**

The resolver inspects the entry first to freeze profile state, then traverses active dependency references depth-first, and appends each importer only after dependencies. Use `visiting`, `visited`, and an edge stack; do not infer cycles from recursion failure text. Reject a second edge with the same dependency identity within one importer before deduplication.

The passthrough profile must return byte-identical streams:

```ts
export const passthroughProfile: SourceProfile<undefined, undefined> = {
  inspectEntry({ originalBytes }) {
    return {
      state: undefined,
      compilerBytes: originalBytes,
      dependencies: [],
      maskedRanges: [],
    };
  },
  inspectDependency({ originalBytes }) {
    return { compilerBytes: originalBytes, dependencies: [], maskedRanges: [] };
  },
};
```

Assert `compilerBytes === originalBytes` for this profile, not merely equal content.

**Step 5: Run checks and commit**

```bash
npm test -w @jhlagado/source-packager -- resolver.test.ts
npm run typecheck -w @jhlagado/source-packager
git add packages/source-packager
git commit -m "Resolve deterministic source dependency graphs"
```

### Task 6: Join placement and publish complete provenance

**Files:**

- Create: Debug80 `packages/source-packager/src/placement.ts`
- Create: Debug80 `packages/source-packager/test/placement.test.ts`
- Create: Debug80 `packages/source-packager/test/provenance.test.ts`
- Modify: Debug80 `packages/source-packager/src/resolver.ts`
- Modify: Debug80 `packages/source-packager/src/types.ts`
- Modify: Debug80 `packages/source-packager/src/index.ts`

**Step 1: Write failing path-keyed placement tests**

Prove that `{ "lib/hardware.asm": 2 }` follows that logical source after an unrelated sibling-order change while the ordinal bank array changes appropriately. Cover default bank, bank 0 and 255, missing default, out-of-range bank, conflicting assignment, unreachable assignment, and a mapping path that does not exist.

**Step 2: Write failing provenance tests**

For every resolved part assert:

```ts
expect(part.provenance).toEqual({
  logicalIdentity: "lib/hardware.asm",
  diagnosticName: "lib/hardware.asm",
  physicalPath: expect.any(String),
  ordinal: 0,
  bank: 2,
  originalByteLength: 4,
  maskedRanges: [],
  dependencyLocations: expect.any(Array),
  includeStack: expect.any(Array),
});
```

Ensure compiler offsets index the same original byte offset. Returned arrays and records must be frozen or defensively copied.

**Step 3: Implement placement only after a complete graph exists**

Resolve every placement key to a canonical logical identity, reject unused entries, join banks, then assign ordinals. Serialize SP1 from these final parts and immediately parse it under the same limits as an internal invariant.

**Step 4: Run checks and commit**

```bash
npm test -w @jhlagado/source-packager -- placement.test.ts provenance.test.ts
npm run typecheck -w @jhlagado/source-packager
git add packages/source-packager
git commit -m "Join placement and source provenance"
```

### Task 7: Make generated SP1 publication atomic

**Files:**

- Create: Debug80 `packages/source-packager/src/atomic-plan-writer.ts`
- Create: Debug80 `packages/source-packager/test/atomic-plan-writer.test.ts`
- Modify: Debug80 `packages/source-packager/src/index.ts`

**Step 1: Write the failing publication tests**

Start with an existing `sources.sp1` containing `old`. Prove:

- successful publication replaces it with the canonical complete plan;
- a serialization/validation failure leaves `old` byte-identical;
- an injected write or rename failure leaves `old` byte-identical;
- no temporary file remains after a handled failure;
- the function validates by parsing the exact bytes it will publish before opening a temporary output.

**Step 2: Run the focused test and observe failure**

```bash
npm test -w @jhlagado/source-packager -- atomic-plan-writer.test.ts
```

Expected: FAIL because the writer does not exist.

**Step 3: Implement same-directory temporary publication**

Write a uniquely named file in the destination directory with exclusive creation, close it, and rename it over the target only after success. Cleanup only the exact temporary path created by this call. Do not delete or truncate the existing destination on failure.

**Step 4: Run package verification and commit**

```bash
npm test -w @jhlagado/source-packager
npm run typecheck -w @jhlagado/source-packager
npm run lint -w @jhlagado/source-packager
npm run format:check -w @jhlagado/source-packager
git add packages/source-packager
git commit -m "Publish source plans atomically"
```

### Task 8: Implement Atom directive parsing and equal-length masking

**Files:**

- Create: Atom `src/host/atom-literals.mjs`
- Create: Atom `src/host/atom-directives.mjs`
- Create: Atom `src/host/atom-source-profile.mjs`
- Create: Atom `test/host-literals.test.mjs`
- Create: Atom `test/host-directives.test.mjs`
- Create: Atom `test/host-masking.test.mjs`

**Step 1: Write failing numeric grammar tests**

Test equivalence and boundaries:

```js
for (const [source, value] of [
  ["65535", 0xffff], ["$FFFF", 0xffff], ["%01110111", 0x77],
  ["0FFFFH", 0xffff], ["0ffffh", 0xffff], ["01110111B", 0x77],
]) assert.equal(parseAtomPreprocessorValue(source), value);
```

Reject `65536`, `$10000`, `%` with a non-binary digit, `10000H`, `FFFFH`, `12B`, empty values, signs, operators, and trailing tokens. `DEBUG` is parsed as a name, never a literal.

**Step 2: Write failing directive and structure tests**

Cover case-insensitive directive and definition names, `%define DEBUG %1`, project definitions preceding source definitions, duplicate definitions even when equal, imported-file definitions, undefined names, extra condition tokens, unknown directives, duplicate `%else`, unmatched `%else`/`%endif`, unterminated nesting, and illegal `%include`/`%define` in a body conditional.

Recognize a directive only when `%` follows only ASCII SP or HT on a line and is followed by a letter. Prove `%1`, `A % B`, and an Atom comment containing `%if` are ordinary Atom text.

**Step 3: Write failing masking invariants**

For mixed LF and CRLF input, prove:

```js
assert.equal(result.compilerBytes.length, original.length);
for (let offset = 0; offset < original.length; offset += 1) {
  if (original[offset] === 0x0a || original[offset] === 0x0d) {
    assert.equal(result.compilerBytes[offset], original[offset]);
  }
}
```

Assert every directive line is spaces except CR/LF, every inactive ordinary byte is space, and every active ordinary byte is unchanged. Test nested true/false branches and an inactive `%include` that creates no edge.

**Step 4: Run tests and observe failure**

```bash
node --test test/host-literals.test.mjs test/host-directives.test.mjs test/host-masking.test.mjs
```

Expected: FAIL because the host modules do not exist.

**Step 5: Implement a byte-offset line scanner**

Scan the original `Uint8Array` without normalizing newlines. Each parsed line retains `{ start, contentEnd, newlineEnd, line }`. Copy the input once for `compilerBytes`; masking writes `0x20` only in `[start, contentEnd)`. Track a stack of:

```js
{
  parentActive,
  conditionTrue,
  branchActive,
  elseSeen,
  directiveLocation,
}
```

The first ordinary line closes the preprocessing header even if its branch is inactive. Source definitions are permitted only in the entry before the first include, conditional, or ordinary line. Freeze the definition map before imported parts are inspected.

**Step 6: Run focused tests and commit**

```bash
node --test test/host-literals.test.mjs test/host-directives.test.mjs test/host-masking.test.mjs
git add src/host test/host-literals.test.mjs test/host-directives.test.mjs test/host-masking.test.mjs
git commit -m "Add Atom host preprocessing profile"
```

### Task 9: Add resident Intel-suffix literals and fail closed on leaked directives

**Files:**

- Modify: Atom `asm/atom-tokenizer.asm`
- Modify: Atom `test/tokenizer.test.mjs`
- Modify: Atom `test/measure-tokenizer.mjs`
- Modify: Atom `proofs/phase-2b.json`
- Modify only if measured extents change: Atom `proofs/phase-2b-memory.json`

Use the `z80-engineering` and `superpowers:test-driven-development` skills for this task.

**Step 1: Replace the old negative test with failing positive and boundary proofs**

Extend the numeric test with `0FFFFH`, `0ffffh`, `01110111B`, and lowercase suffixes. Add:

- equivalent-value assertions against `$FFFF` and `%01110111`;
- `00000H` and leading-zero binary spellings;
- invalid `FFFFH`, `10000H`, `12B`, `0G`, and suffix-plus-name forms;
- failure atomicity for every invalid spelling.

Add leaked-directive cases at logical line start, after SP/HT indentation, and after a previous EOL:

```js
for (const source of ["%include \"x.asm\"", "  %IF DEBUG", "NOP\n%endif"]) {
  const result = h.tokenize(source);
  assert.equal(result.error?.status, TOKEN_STATUS.UNPROCESSED_DIRECTIVE);
}
```

Prove `%1`, `LD A,%1`, and `A % B` retain their existing binary/remainder tokenization.

**Step 2: Run the focused proof and observe failure**

```bash
node --test test/tokenizer.test.mjs
```

Expected: suffix literals fail with `INVALID_NUMBER`, and leaked directives are not yet rejected with the new status.

**Step 3: Implement one shared digit-led scanner**

Replace the early decimal accumulation path with a maximal digit/name lookahead that chooses exactly one grammar before accumulation:

- final `H`/`h`: the body starts with a decimal digit and contains only hex digits;
- final `B`/`b`: the body contains only `0` and `1`;
- no suffix: every byte is decimal;
- every other name continuation makes the whole token invalid.

Accumulate only after grammar selection, detect 16-bit overflow during shifts/multiply-by-ten, and preserve the current token record on failure. Do not allocate a source copy or widen resident offsets.

At `_AtomTokenizerPercent`, if the next byte is a letter and `AtomTokenLineHasToken` is zero, return the new `AtomTokenStatusUnprocessedDirective`. This makes a leaked host line fail closed while preserving infix remainder and `%` binary behavior.

Update the exported test status map and strict `.routine` annotations. Run AZM contract annotation only if the implementation changes a proven contract, then review every generated annotation change.

**Step 4: Run all native correctness proofs**

```bash
npm test
```

Expected: every Atom proof passes under strict register contracts; tokenizer canaries, stack balance, immutable code, full-memory write audit, and execution budgets remain green.

**Step 5: Measure and label the change**

```bash
npm run measure:tokenizer
```

Update `proofs/phase-2b.json` measured instruction/cycle observations and budgets only from the emitted measurements. Keep slack explicit. Record the exact measured code/table/workspace delta in the commit message body or checkpoint report. Do not compress merely to hide an increase.

**Step 6: Commit the native syntax checkpoint**

```bash
git add asm/atom-tokenizer.asm test/tokenizer.test.mjs test/measure-tokenizer.mjs proofs/phase-2b.json proofs/phase-2b-memory.json
git commit -m "Accept Intel suffix literals in Atom source"
```

### Task 10: Compose Atom with the shared resolver

**Files:**

- Create: Atom `src/host/resolve-atom-project.mjs`
- Create: Atom `test/host-source-packager.test.mjs`
- Create: Atom `test/fixtures/source-packager/diamond/main.asm`
- Create: Atom `test/fixtures/source-packager/diamond/display.asm`
- Create: Atom `test/fixtures/source-packager/diamond/input.asm`
- Create: Atom `test/fixtures/source-packager/diamond/hardware.asm`
- Modify: Atom `package.json`
- Modify: Atom `package-lock.json`
- Modify: Atom `scripts/verify-dependencies.mjs`

**Step 1: Add the sibling workspace dependency**

Add:

```json
"@jhlagado/source-packager": "file:../debug80/packages/source-packager"
```

Extend `build:dependencies` to build the new package before tests. Extend dependency verification with the exact reviewed `packages/source-packager` tree hash; keep the existing AZM and runtime tree pins. Run `npm install` in Atom to update its lockfile.

**Step 2: Write the failing end-to-end preparation tests**

The diamond fixture uses mixed-case directives, active and inactive includes, both newline styles, and an entry definition. Assert:

- order is `hardware.asm`, `display.asm`, `input.asm`, `main.asm`;
- each physical file is a separate part and the diamond dependency appears once;
- ordinals and banks agree with the generated and reparsed SP1 plan;
- all original/compiler lengths match and offset-to-original attribution is exact;
- relocating the fixture root leaves logical identities, SP1, and compiler bytes unchanged;
- a saved explicit-parts array made from the same files has byte-identical compiler streams and attribution to resolver output;
- changing a dependency file after its snapshot is read cannot change returned compiler bytes;
- malformed preprocessing returns no prepared project, publishes no partial artifact, and does not replace an existing SP1 file.

Also enumerate all required negative diagnostics: repeated import, missing source, root escape, alias, cycle, unknown directive, undefined condition, inactive include selection, imbalance, path/part/depth/retained-path capacity, and invalid placement.

**Step 3: Run the focused test and observe failure**

```bash
npm run build:dependencies
node --test test/host-source-packager.test.mjs
```

Expected: FAIL because `resolveAtomProject` is absent.

**Step 4: Implement the thin Atom composition module**

The module creates the shared Node reader, supplies `createAtomSourceProfile()`, calls `resolveSourceProject`, and returns the prepared project. It contains no duplicate graph, path, placement, or SP1 logic. Freeze configuration and results at the public boundary.

**Step 5: Run Atom and shared-package verification**

```bash
node --test test/host-source-packager.test.mjs test/host-directives.test.mjs test/host-masking.test.mjs
npm test
npm test --prefix ../debug80 -w @jhlagado/source-packager
```

Expected: all focused and full tests PASS.

**Step 6: Commit the integration**

```bash
git add package.json package-lock.json scripts/verify-dependencies.mjs src/host test
git commit -m "Resolve Atom source projects on the host"
```

### Task 11: Document limits and verify both repositories

**Files:**

- Modify: Debug80 `packages/source-packager/README.md`
- Create: Debug80 `packages/source-packager/docs/sp1.md`
- Create: Atom `docs/host-source-packaging.md`
- Modify if applicable: Atom `README.md`

**Step 1: Document only measured or enforced facts**

The shared package documentation records SP1 grammar, three identities, resolution order, default Node limits, placement behavior, snapshot ownership, atomic-plan semantics, public API, GPL license, and error categories.

Atom documentation records `%` grammar, immutable definition rules, header/body restrictions, import-once behavior, numeric spellings, masking, the fact that `%define` does not create an assembler symbol, and the preparation-only boundary. Include this warning verbatim:

```text
The source packager does not compile or publish an Atom object. It returns a
fully validated ordered set of source parts for the later streaming adapter.
```

**Step 2: Run formatting and complete checks in Debug80**

```bash
npm run format -w @jhlagado/source-packager
npm run build -w @jhlagado/source-packager
npm run typecheck -w @jhlagado/source-packager
npm run lint -w @jhlagado/source-packager
npm run format:check -w @jhlagado/source-packager
npm test -w @jhlagado/source-packager
npm pack -w @jhlagado/source-packager --dry-run
```

Expected: every command passes and the dry-run contains only `dist`, `README.md`, `LICENSE`, and package metadata.

**Step 3: Run complete Atom proofs and measurements**

```bash
npm test
npm run measure:tokenizer
```

Expected: all strict-contract proofs pass and the measurement reproduces the recorded manifest values.

**Step 4: Self-review against the approved contract**

Run:

```bash
rg -n 'TO''DO|TB''D|FIX''ME' packages/source-packager ../atom/src/host ../atom/test/host-*.test.mjs ../atom/docs/host-source-packaging.md
git status --short
```

Expected: no unfinished-marker matches; status shows only the intended documentation or formatting changes. Manually map every bullet under the design's `Required proof set` to a named test. Record the one intentional boundary: resident compiler-output equivalence awaits the separately designed streaming adapter, while preparation bytes and attribution are proved here.

**Step 5: Commit documentation in each repository**

Debug80:

```bash
git add packages/source-packager/README.md packages/source-packager/docs/sp1.md
git commit -m "Document shared source packaging"
```

Atom:

```bash
git add docs/host-source-packaging.md README.md
git commit -m "Document Atom host source packaging"
```

Skip a repository's commit only if the named files did not change; do not create empty commits.

### Task 12: Final adversarial review, get, commit, and push checkpoint

**Files:**

- Modify only files required by verified review findings.

**Step 1: Request a read-only adversarial review**

Launch a review agent explicitly using the adversarial-review portion of `z80-engineering`. Give it both exact worktrees and ask it to audit:

- design-contract coverage;
- path and symlink escapes;
- graph order, duplicate, alias, and cycle handling;
- conditional masking and directive leakage;
- snapshot consistency and atomic publication;
- SP1 ambiguity and capacity off-by-one errors;
- Atom register contracts, stack/canary proofs, memory writes, and measurements;
- GPL/public-package metadata;
- absence of unintended Nucleus edits.

The agent is read-only and must report file/line evidence. Apply only reproduced correctness findings, using failing tests before fixes.

**Step 2: Re-run both final verification sets after fixes**

Debug80:

```bash
npm run build -w @jhlagado/source-packager
npm run typecheck -w @jhlagado/source-packager
npm run lint -w @jhlagado/source-packager
npm run format:check -w @jhlagado/source-packager
npm test -w @jhlagado/source-packager
npm pack -w @jhlagado/source-packager --dry-run
```

Atom:

```bash
npm test
npm run measure:tokenizer
```

Expected: every command passes from clean dependency builds.

**Step 3: Commit any review fixes**

Use one focused commit per repository, for example:

Debug80, when review fixes touch the shared package:

```bash
git add package.json package-lock.json packages/source-packager
git commit -m "Harden source packaging proofs"
```

Atom, when review fixes touch its adapter or tokenizer:

```bash
git add package.json package-lock.json scripts/verify-dependencies.mjs src/host asm/atom-tokenizer.asm test proofs/phase-2b.json proofs/phase-2b-memory.json docs/host-source-packaging.md README.md
git commit -m "Harden Atom source packaging proofs"
```

Do not create a commit when no files changed.

**Step 4: Get remote changes without merging unrelated history**

In each worktree:

```bash
git fetch origin
git rebase origin/main
```

Expected: clean rebase. If upstream changes overlap package, Atom tokenizer, or dependency pins, stop and re-run the complete proof set after resolving deliberately.

**Step 5: Push both checkpoints**

```bash
git -C /tmp/atom-source-packager-implementation/debug80 push -u origin codex/source-packager
git -C /tmp/atom-source-packager-implementation/atom push -u origin codex/source-packager
```

Expected: both branches are published and `git status --short --branch` reports clean, up-to-date worktrees.

**Step 6: Report exact evidence**

Report:

- branch and HEAD for Atom and Debug80;
- Debug80 source-packager test count and package dry-run result;
- Atom full proof count;
- measured Atom tokenizer rule-code, table, total resident-code, workspace, instruction, and cycle values, with deltas from the starting manifest;
- the complete list of implemented and deliberately deferred design-contract items;
- adversarial review findings and dispositions.

## Implementation log

Execution appends one short entry per repository checkpoint containing date, fetched base, branch, HEAD, verification commands, and push result. Measurements are labeled **Measured**; design expectations are labeled **Projected**; untested claims are labeled **Hypothesis**.
