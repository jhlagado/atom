# Z80 size-compression battery

Run this battery only after the correctness baseline passes the correctness
battery. Preserve source semantics, ABI behavior, diagnostics, traps, and
capacity rules unless the project owner separately approves a redesign.

## 1. Establish the baseline

Assemble the current tree and record:

- code bytes;
- immutable tables and constants;
- peak writable workspace;
- generated-program bytes;
- shared runtime bytes and state;
- execution storage;
- instruction count and T-states for named proofs.

Record component extents. A total without a module map cannot guide the next
change. Confirm that extent names refer to the same regions in every proof.

## 2. Remove scaffolding before tuning instructions

Find fixed-program encoders, replay buffers, duplicated parsers, proof-only
branches in resident code, compatibility shims, and state retained after its
last use. Replace narrow duplicated mechanisms with one general streaming or
table-driven path only when the complete resident account becomes smaller.

Do not move bytes from code into unreported data or workspace. Do not remove a
correctness discriminator merely because it belongs to a proof.

## 3. Merge tails and prefixes

Search for byte-identical suffixes first. A shared suffix often needs only one
fall-through case and short jumps from the others. Include the entry setup and
branch bytes in the saving.

Then inspect:

- common error endings;
- success and trap epilogues;
- emitter setup and teardown;
- `CALL routine / RET` tail calls that can become `JP routine`;
- common prefixes that can accept a selector in a register;
- inverted conditions that permit fall-through;
- jumps into a proven internal entry point.

Every shared entry has its own register, flag, and stack contract. Re-run every
exit proof after merging epilogues; frame restoration must remain on all paths.

## 4. Cost wrappers at current call sites

For a candidate wrapper, calculate both complete forms:

```text
inline total  = callers * inline bytes
wrapper total = wrapper body + callers * call-site bytes
```

The wrapper pays only when wrapper total < inline total. Include selector
loads, CALL or JP, return bytes, range bridges, and any preserved registers.

Do not create a wrapper because an older census reached break-even. Re-run the
call-site search on the current tree, distinguish active code from proof and
archive code, and inspect indirect callers that text search may miss.

## 5. Cost tables and dispatch

Tables tend to pay for dense, compiler-assigned ordinals and repeated handlers.
They tend to lose for sparse character domains or two-way decisions.

Compare:

```text
chain = tests + conditional transfers + default path
table = selector normalization + bounds check + index arithmetic
        + table bytes + indirect transfer or trampoline bytes
```

Include page constraints, alignment, entry width, terminators, out-of-range
handling, and the assembler's available indirect-transfer forms. Measure direct
page-offset, trampoline, and comparison-chain forms when placement decides the
winner.

Good candidates include semantic-operation dispatch, keyword descriptors,
punctuation pairs, type-width selection, and compact diagnostic descriptors.
Reject a 128- or 256-byte character table when a sparse chain is smaller.

## 6. Repack state by liveness

Build a lifetime table for every workspace field. Overlay fields only when the
correctness battery's three overlay conditions hold. Common phases include:

- source/token/diagnostic processing;
- successful semantic transcript retention;
- post-parse native emission;
- generated-program execution;
- terminal diagnostics.

Look for one-byte ordinals replacing pointers, packed class/type bits, shared
scratch words, fixed-capacity stack entry compression, and counters derivable
from cursors. Reconcile the final symbol arithmetic with the measured workspace
extent and add canaries around the highest-risk overlays.

## 7. Re-run every census

Treat every historical site count as stale. The earlier Nucleus wrapper, tail,
punctuation, delimiter, and dispatcher censuses were performed when the
compiler core measured 2,862 bytes. The typed-expression correctness build
later measured 7,806 bytes. The old break-even formula may remain valid, but
the old number of sites does not.

Immediately before changing code, repeat at least these censuses:

- direct callers per wrapper;
- byte-identical tails and prefixes;
- CALL followed by terminal RET;
- token and keyword handlers of the same shape;
- punctuation forms that only consume and return an ordinal;
- semantic operations and operand widths;
- diagnostic setup sequences;
- fixup creation and patch paths;
- state fields with non-overlapping lifetimes;
- table entries, bridges, and out-of-range handlers;
- repeated generated-code byte templates.

Quote the search scope and exclude archives, tests, and proofs only when they
do not contribute resident bytes. Confirm each textual match is an executable
site.

## 8. Use Z80-specific opportunities

Measure these common candidates:

- JP tail calls instead of CALL plus RET;
- JR instead of JP where placement proves the signed displacement;
- fall-through into the common case;
- shared flags instead of repeated compares or OR A operations;
- hardware flag-preserving restore idioms;
- alternate register set use when save/restore cost and interrupt policy allow;
- EX DE,HL, EX (SP),HL, and stack exchange patterns;
- DJNZ for a proven nonzero 8-bit count;
- LDIR or LDDR after complete-region and overlap proofs;
- RST vectors when the platform owns and prices them explicitly;
- self-modifying constants or dispatch only when writable-code policy,
  reentrancy, interrupts, and publication atomicity permit them.

Verify actual instruction bytes, timing, and flags for the selected Z80 target.
An optimization that depends on an undocumented emulator behavior is invalid.

## 9. Compare whole paths

Measure compiler-side and generated-code effects separately. An emitter helper
may shrink the compiler while increasing every generated program; a runtime
helper may shrink generated code while enlarging the resident runtime. Report
the intended deployment model before choosing.

Compilation speed is normally secondary in a tiny compiler, but record large
regressions. Execution speed remains part of the evidence even when bytes
decide the result.

## 10. Close the plateau

For each candidate record:

- hypothesis and exact accounting boundary;
- baseline and experimental bytes;
- workspace, generated-code, runtime, instruction, and cycle deltas;
- proof commands and results;
- retain or reject decision;
- changed premises that would justify retesting a rejected idea.

Finish with a new adversarial correctness-and-size review. Re-run the full
census on the resulting core; the pass is incomplete while its own changes have
created an unmeasured repetition.
