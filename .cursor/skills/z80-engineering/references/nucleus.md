# Nucleus Z80 project rules

Apply these rules only when working in the Nucleus package.

## Active authorities

Read the relevant sections of these files before implementation or review:

1. `packages/nucleus/docs/specification.md` — source language authority.
2. `packages/nucleus/docs/z80-runtime-contract.md` — direct-Z80 representation,
   activation, trap, service, and backend authority.
3. `packages/nucleus/docs/reviewers-charter.md` — review classifications and
   settled decisions.
4. `packages/nucleus/docs/implementation-plan.md` — non-normative current
   measurements, construction order, and capacity ledger.

The NVM implementation path was retired in commit `aab885a`. Do not cite an NVM
specification as an active authority, add NVM proofs, or require equivalence to
retired bytecode. Archived material may explain history only.

The active static-slot rule is in `z80-runtime-contract.md` section 6.2. Each
successful call has distinct logical storage for scalar parameters, scalar
locals, aggregate-parameter carriers, return address, and other live activation
state. The backend may implement this with the hardware stack, a bounded arena,
static slots saved around calls, or a measured combination. One active call may
not overwrite another.

## Settled implementation direction

- Emit Z80 directly.
- Keep the checked semantic-operation transcript private and bounded.
- Build no abstract syntax tree.
- Use scalar routine locals only.
- Keep owned aggregate storage at program scope.
- Use opaque, typed address carriers for aggregate parameters and results.
- Preserve left-to-right evaluation, exact trap timing, and atomic failure.
- Treat the 16 KiB compiler-core limit as a hard implementation gate, not a
  source-language rule.
- Prioritize resident compiler bytes over compilation speed while recording
  both.

A proposed change to any item above is redesign and requires the project
owner's explicit decision.

## Current evidence, not frozen numbers

Read fresh assembled extents from `packages/nucleus/test/proof-harness.test.ts`
and the current proof manifests. Reconcile them with the implementation plan.
Do not copy a compiler size or component census from a prior review.

In particular, the old optimization censuses were performed at a 2,862-byte
core. The typed-expression correctness build later reached 7,806 bytes. Retain
the break-even arithmetic where it remains valid, but repeat every site count.

## Scoped verification

Run commands from `packages/nucleus` unless the changed dependency requires a
different scope:

```text
npx vitest run test/proof-harness.test.ts --reporter=verbose
npm run typecheck
npx vitest run
```

Build AZM or Debug80 runtime only when its generated output is absent, stale,
or part of the change. Do not use the monorepo-wide check as the ordinary
Nucleus gate.

Keep `packages/nucleus/docs/reviews/` out of implementation commits unless the
project owner explicitly asks to publish a review artifact.

## Review sequence

For a feature milestone:

1. implement for correctness;
2. obtain a read-only adversarial correctness review;
3. repair important findings;
4. perform measured semantics-preserving compression;
5. obtain a read-only adversarial correctness-and-size review;
6. repair important findings;
7. run scoped final verification, commit, and push.

Do not compress an unreviewed correctness baseline. Do not let a reviewer treat
a settled design direction as a defect.
