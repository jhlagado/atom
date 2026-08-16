# Z80 correctness battery

Run this battery before size work and again after it. A test suite is evidence
only for the states and paths it distinguishes.

## 1. Authority and target

- Identify the exact CPU contract: Z80, documented extension, or compatible
  derivative.
- Record the assembler version and its instruction, flag, range, and contract
  model.
- Identify the governing language, ABI, runtime, service, image, and platform
  documents in authority order.
- Freeze the reviewed revision and list untracked files that belong to the
  target.
- Separate settled design from a proposed redesign.

## 2. Entry and exit contracts

For every public or indirectly dispatched routine, record:

- input and output registers;
- preserved and clobbered registers;
- flags read on entry and defined on exit;
- stack input and output shape;
- writable regions and aliases;
- success, failure, trap, and capacity exits.

Trace the actual caller as well as the callee. A locally balanced routine can
still violate the caller's live-register or stack assumptions.

Generated terminal paths require special treatment. Confirm that every path
restores local allocation, IX/IY, saved registers, activation state, and the
hardware return address before `RET`. Observe SP and the return PC directly.

## 3. Memory map and liveness

Write the complete address interval for every code, immutable, workspace,
source, output, runtime, activation, service, proof, and stack region.

For overlays, prove all three facts:

1. the old value is dead before the first overlay write;
2. every error path that still needs the old value occurs before that write or
   stores a separate copy;
3. no asynchronous or nested operation observes both meanings.

Check half-open intervals, final-byte arithmetic, multi-byte fields, alignment,
and arithmetic wrap. Derive the reported workspace size from the symbols and
reconcile it with the assembled extent.

## 4. Control flow and fixups

- Enumerate direct, conditional, indirect, table, fall-through, and synthetic
  return edges.
- Prove every jump target is an instruction boundary in the intended routine.
- Check relative displacement from the address after the branch instruction;
  the signed range is -128 through 127.
- Exercise the nearest accepted and first rejected displacement in both
  directions.
- Verify each fixup is initialized, patched once, and not read after its storage
  is reused.
- Check that an emission error retains the source position rather than a
  generated address or overwritten cursor.
- Treat a shared tail as a multi-entry routine and prove every entry contract.

## 5. Arithmetic, flags, and carriers

Derive arithmetic from bit width, not from a host language's default integer.
For every operation check carry, borrow, wraparound, sign interpretation,
division by zero, and canonical high bytes.

Use exhaustive enumeration for byte-wide helpers and boundary partitions for
word-wide helpers. For a word helper, include zero, one, 255, 256, 32767, 32768,
65534, 65535, powers of two, and values around every branch threshold.

Check Z80 hardware flags against a primary instruction reference. Also inspect
the assembler's static model. For example, standard `ADD HL,ss` changes H, N,
and C while leaving S, Z, and P/V unchanged; `ADC HL,ss` and `SBC HL,ss` do not
share that flag contract. Do not transfer an idiom between them without a new
proof.

For typed compilers, reconstruct the source-type matrix independently from the
implementation. Compare folded and runtime evaluation at the same selected
width and verify every conversion, comparison, and trap in both forms.

## 6. Parsing and diagnostics

- Prove tokenizer maximality, delimiters, comments, literal limits, and payload
  preservation across lookahead.
- Check expected-token and context-specific diagnostics separately.
- Retain full source-part identity and source offset until every emitter error
  that may need them has completed.
- Check provisional declarations, self-reference, duplicate names, and failure
  publication.
- Exercise one byte before, exactly at, and one byte after every bounded input,
  table, stack, transcript, fixup, and output capacity.

An internal invariant failure must not masquerade as an ordinary source-capacity
diagnostic. Give defensive failures a distinct code or an impossible-state
assertion that the proof harness can identify.

## 7. Calls and activation state

Verify argument order, copied scalar values, opaque aggregate carriers, return
values, nested calls, recursion, early return, recoverable failure, and traps.

For static-slot implementations, prove that active scalar state is saved and
restored for every re-entry. Do not infer this rule from retired VM material.
For Nucleus, the active authority is `packages/nucleus/docs/z80-runtime-contract.md`
section 6.2: each successful call has distinct logical activation state, while
the backend may implement it with hardware stack entries, an activation arena,
static slots saved around calls, or a measured combination.

Check activation-capacity before any caller state is overwritten. A failed call
must not partially publish arguments, depth, slots, or completion state.

## 8. Failure atomicity

For each compile diagnostic, recoverable failure, and runtime trap, list every
state that could change before the check. Confirm the required subset remains
unchanged.

Inspect destination storage, output cursors, service effects, symbol visibility,
semantic transcript publication, generated-code publication, activation depth,
frame state, SP, and return PC. Run a second compilation or invocation after a
recoverable failure to prove reset behavior where recovery is admitted.

## 9. Proof strength

A strong proof distinguishes a plausible wrong implementation. Prefer:

- exact output and final storage;
- exact diagnostic or trap reason and source position;
- stack pointer and return control flow;
- canaries around writable regions;
- before/after destination values on atomic failures;
- exhaustive helper checks;
- assembler-derived extents;
- recursion that would fail under shared activation state.

A terminal pass marker alone is weak when execution can reach it after a bogus
return, fall-through, or stale state. Inspect the route to the marker.

## 10. Clearance

Report confirmed defects, proof gaps, questions, and redesign suggestions in
separate groups. Clear size work only when every high-risk path is either proved
or has a named blocking finding. Optional strengthening does not block clearance
when the existing evidence already distinguishes the relevant failure.
