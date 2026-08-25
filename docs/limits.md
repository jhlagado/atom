# Atom limits and capacity

This document separates limits enforced by code from measured capacities of
the present Mac proof map. Unless marked Projected or Hypothesis, the numbers
below are Measured from the checked image or executable tests.

## Resident image

| Item | Classification | Bytes |
| --- | --- | ---: |
| Z80 code and immutable tables | Measured | 11,682 |
| Fixed non-reentrant workspace | Measured | 714 |
| Linked resident extent at origin zero | Measured | 12,396 |
| Margin below one 16 KiB bank | Measured | 3,988 |

The package, authoritative native source, Debug80 runtime, renderer, and Mac CLI
do not consume this Z80 bank. A TEC-specific source/output adapter is not part
of the 12,396-byte image and must be measured separately.

## Native source and output

| Limit | Value |
| --- | ---: |
| Ordered source parts | 1–255 |
| Bytes in one source part | 0–65,535 |
| Resident Z80 source-page bytes on Mac | 0 |
| Output banks | 1, bank zero |
| Encoded instruction length | 1–4 bytes |
| Build descriptor | 15 bytes |
| Complete 255-part descriptor array | 1,275 bytes |
| One `INCBIN` input | 0–65,535 bytes |

The source service uses a 16-bit logical offset, so one part may contain at most
65,535 bytes. Total source may be larger across the 255 ordered parts. The Mac
runner retains immutable JavaScript snapshots and returns one byte at each
`AtomSourceReadByte` call; it does not copy a source page into Z80 memory. The
checked native self-host input is Measured 101,492 bytes in five content parts.

The native target uses a non-wrapping half-open 16-bit range whose mathematical
end is at most `$FFFF`. It cannot currently represent `$10000` as an exclusive
end. Starting at zero therefore permits a maximum capacity of 65,535 bytes,
covering `$0000` through `$FFFE`.

`INCBIN` bytes count as initialized output and consume the target capacity.
The Mac bridge submits one IMAGE operation per byte through the existing native
`DS` emission path. Large binaries therefore consume native execution budget
even though their filesystem storage is host-owned.

## Symbols and pending references

An exact symbol record is Measured 8 bytes. A global consumes one record for
the rest of the build. Private records consume space only in the current global
scope and are evicted at the next global label. A pending reference consumes
Measured 7 bytes until its symbol is defined and its patch has been submitted.

The Mac proof map provides:

| Arena | Classification | Bytes | Complete records |
| --- | --- | ---: | ---: |
| Symbols | Measured | 13,312 | 1,664 simultaneous symbols |
| Pending references | Measured | 4,864 | 694 simultaneous references |

The useful source-size limit depends on symbol density and on the peak, not the
total, number of private and unresolved records. For any target map:

```text
symbol bytes  = 8 * (permanent globals + peak private symbols in one scope)
pending bytes = 7 * peak concurrent unresolved references
```

Names contain one through eight significant RADIX-40 characters. A private
name has a separate leading `.`, so it may occupy nine source characters. Atom
diagnoses longer names; it never truncates them.

## Expressions and statements

The expression evaluator has 16 value-stack entries and 16 operator-stack
entries. It accepts concrete final results from -32,768 through 65,535, shift
counts from 0 through 23, and forward affine addends from -128 through 127.
`JR` and `DJNZ` displacements are also -128 through 127 and are never widened.

`RST` accepts 0, 8, 16, 24, 32, 40, 48, or 56. `IM` accepts 0, 1, or 2.
Immediate, displacement, port, and data widths are validated or truncated as
described in the language reference.

## Mac host graph

The resolver, SP1 wire format, Mac runner, and native driver share one part
limit. `assembleAtomProject` validates it before execution.

| Host preparation limit | Default |
| --- | ---: |
| Graph and native Atom parts | 255 |
| Dependency depth, including entry | 64 |
| Logical path | 255 ASCII bytes |
| Retained logical paths | 65,536 bytes |
| SP1 bank ordinal | 0–255; zero for native Atom |

The Mac runner's default execution budgets are 200,000,000 Z80 instructions
and 2,000,000,000 T-states. Atom's measured self-build uses 101,840,573
instructions and 1,086,338,471 T-states.

## A realistic 24 KiB TEC workspace

The current Mac capacities are not a TEC memory map. Fixed workspace, symbols,
pending records, the maximum descriptor set, and a 256-byte stack total
Measured 20,436 bytes at those capacities, leaving 4,140 bytes in a 24 KiB RAM
budget for the operating adapter and its state. Source bytes are outside that
account because the tokenizer reads them through `AtomSourceReadByte`.

A practical TEC deployment must choose arena sizes from measured program
density and implement the source service over its storage hardware. The linked
fallback still supports an ordinary memory interval for small standalone
harnesses. The deployed capacity is therefore a target configuration, not a
claim inherited from the Mac runner.
