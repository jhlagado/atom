# Symbol and pending-reference prototype ABI

Phase 2a measures the resident algorithms and record layouts. The tokenizer,
expression evaluator, diagnostics text, and NOBJ serializer remain outside this
module.

## Identifier representation

`AtomPackSymbol` accepts a global name of one to eight characters or a private
name written as `.` followed by one to eight significant characters. It folds
ASCII letters to uppercase while packing. The leading `.` is syntax and is not
part of the RADIX-40 payload.

The exact packed name occupies six bytes. Bits 3–7 of byte 5 remain outside the
RADIX-40 value. Bit 7 records `private`, bit 6 records `defined`, and Phase 2g
uses bit 5 to preserve a negative `EQU` value as signed. Names are rejected
when they exceed the limit. No path truncates a name.

An eight-byte symbol record contains:

| Offset | Field |
| ---: | --- |
| 0–5 | Exact packed name and flags |
| 6–7 | Value or address, little endian |

## Arenas and scope

`AtomSymbolReset` takes a caller-owned half-open arena in `HL..DE`. Permanent
global records grow upward from the start. Records for the current private
scope grow downward from the end. Every insertion proves that at least eight
bytes remain before it writes or publishes a cursor.

Both reset routines require valid, non-wrapping half-open regions. The final
memory map, rather than source input, supplies those trusted bounds.

`AtomSymbolAdvanceScope` checks the current private records before eviction. An
undefined private returns `AtomStatusUndefinedPrivate` and leaves the scope
unchanged. A pending record that still points at a defined private returns the
distinct internal status `AtomStatusPendingInvariant`. Successful eviction
restores the private cursor to the arena end, so total private labels do not
accumulate across global scopes.

`AtomSymbolDeclareGlobalLabel` validates private eviction, duplicate state, and
post-eviction capacity before it changes either cursor. It then closes the old
private scope and declares the global label as one transaction. Global
constants do not change private-label scope.

## Pending records

`AtomPendingReset` takes a separate caller-owned half-open arena in `HL..DE`.
Each six-byte entry contains:

| Offset | Field |
| ---: | --- |
| 0–1 | Symbol-record pointer |
| 2–3 | Patch address |
| 4 | Patch kind and optional diagnostic anchor |
| 5 | Auxiliary byte |

In the complete driver build, bits 0–2 of byte 4 retain patch kinds 1–5. One
pending record for each undefined symbol sets bit 7 as its diagnostic anchor;
bits 3–6 contain the zero-based source-part ordinal. The undefined symbol's
otherwise-unused value word contains that reference's source offset. Definition
overwrites the word with the symbol value, and successful patch resolution
removes every pending record for the symbol. This encoding retains the settled
record sizes while supporting exact diagnostics across 16 source parts.

`AtomPendingAdd` accepts only an undefined symbol. `AtomPendingTake` finds one
entry for a newly defined symbol, returns its patch metadata, and fills the
hole with the last live record. Repeating `AtomPendingTake` drains all entries
for that symbol. This keeps resident use proportional to concurrent unresolved
references.

The Phase 2f build also exposes `AtomPendingPeek`. It returns the same patch
metadata without removing the record. The output layer peeks, constructs and
submits final patch bytes through the Nucleus sink boundary, then calls
`AtomPendingTake` after the sink succeeds. Historical Phase 2a–2e images omit
this entry and retain their measured bytes exactly.

`AtomPendingPeek` returns the complete byte 4 in B. Driver-enabled output masks
it with `AtomPendingKindMask` before dispatching the patch rule.

The Phase 2g build exposes `AtomPendingCheckCapacity`. Data directives use it
before inserting a missing symbol or emitting a placeholder, so a one-record
pending-capacity failure publishes neither state.

All public routines return `A=AtomStatusOk` with carry clear on success. Failure
returns a nonzero status with carry set. Unless a routine contract says
otherwise, registers and flags are clobbered. The routines are non-reentrant
because they share 20 bytes of fixed workspace.
