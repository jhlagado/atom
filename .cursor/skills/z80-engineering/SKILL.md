---
name: z80-engineering
description: Review, implement, debug, measure, and compress handwritten Z80 assembly and Z80-hosted systems. Use for Z80 compiler or runtime work, AZM source, register and flag contracts, stack or frame analysis, memory maps and overlays, generated Z80 code, byte and cycle measurements, small-machine architecture, adversarial correctness reviews, and semantics-preserving code-size optimization. Apply the Nucleus-specific rules when working under packages/nucleus.
---

# Z80 Engineering

Treat correctness and resident bytes as simultaneous design constraints. Prove
the complete path before compressing it, then retain an optimization only when
fresh assembly and execution evidence show a net improvement at the declared
accounting boundary.

## Route the task

- Read [references/correctness-battery.md](references/correctness-battery.md)
  completely before a correctness review, implementation milestone, ABI change,
  state overlay, arithmetic helper, trap path, or generated-code change.
- Read [references/size-battery.md](references/size-battery.md) completely before
  a size pass, byte census, table conversion, tail merge, wrapper decision, or
  compiler-budget projection.
- Read [references/nucleus.md](references/nucleus.md) completely when the target
  is Nucleus. It records the active authorities, retired NVM boundary, scoped
  gates, and project-specific accounting rules.

Use all three references when reviewing or compressing Nucleus Z80 code.

## Work in evidence order

1. Freeze the exact source tree, baseline revision, assembler version, target
   CPU, memory map, entry point, and accounting boundary.
2. State the behavior and machine invariants that must survive. Include stack
   shape, frame restoration, registers, flags, source positions, atomic failure,
   memory regions, and capacity behavior.
3. Assemble and execute the baseline. Record code, immutable data, writable
   workspace, generated output, runtime support, instruction count, and T-states
   separately where they apply.
4. Trace every success, early return, recoverable failure, trap, and capacity
   exit. A green final state does not prove the return path that reached it.
5. Add a discriminator for every plausible wrong implementation before changing
   representation. Prefer boundary state, stack-pointer, return-address, memory,
   and exact diagnostic observations over a terminal pass byte alone.
6. Apply one structural change at a time. Reassemble, rerun the focused proofs,
   and compare like-for-like accounts.
7. Keep the change only when the claimed account improves and every invariant
   remains proved. Record losing experiments so later agents do not repeat them
   without new premises.
8. Run a final adversarial pass over the combined result. Re-run censuses and
   measurements; never carry their counts forward from an older core.

## Hard rules

- Optimize compiler size ahead of compilation speed when the project declares
  that priority, but always record any cycle regression.
- Count assembled bytes, not source lines or visual complexity.
- Keep compiler core, workspace, generated program, runtime, and execution
  storage separate. Do not claim a saving by moving bytes into an unreported
  account.
- Use the hardware Z80 flag behavior as authority. Check the assembler's model
  separately; a conservative or incorrect model can reject a valid idiom or
  conceal a dependency.
- Preserve every caller-visible register and flag promised by the routine
  contract. Re-check contracts after tail calls, shared suffixes, and
  jump-into-middle transformations.
- Restore frames on every terminal generated path. Check SP and the actual
  return PC after success, failure, and trap exits.
- Prove bounds before a write and preserve the original reason and source
  position on failure.
- Treat tables as candidates, not automatic wins. Include scan or dispatch code,
  terminators, alignment, range bridges, and data bytes in the comparison.
- Re-run call-site, wrapper, token, tail, and dispatcher censuses against the
  current tree immediately before acting on them.
- Prefer scoped build and proof commands. Rebuild dependencies only when their
  outputs are absent, stale, or part of the change.
- Classify a language or ABI change as redesign. Do not present it as an
  implementation cleanup or size optimization.

## Report results

Lead with correctness status and the net measured account. For every retained
change report the baseline, result, byte delta, workspace delta, generated-code
delta, runtime delta, and material cycle delta. For every finding provide an
exact location, failing trace or proof, consequence, and smallest correction.
Separate measured results, projections, hypotheses, and rejected experiments.

Do not declare a plateau until the relevant censuses have been repeated on the
current assembled core and no unmeasured structural candidate remains.
