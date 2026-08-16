# Atom limits and capacity

This document separates limits enforced by code from measured capacities of
the present Mac proof map. Unless marked Projected or Hypothesis, the numbers
below are Measured from the checked image or executable tests.

## Resident image

| Item | Classification | Bytes |
| --- | --- | ---: |
| Z80 code and immutable tables | Measured | 13,261 |
| Fixed non-reentrant workspace | Measured | 551 |
| Linked resident extent at origin zero | Measured | 13,812 |
| Margin below one 16 KiB bank | Measured | 2,572 |

The package, generated self-host source, Debug80 runtime, renderer, and Mac CLI
do not consume this Z80 bank. A TEC-specific source/output adapter is not part
of the 13,812-byte image and must be measured separately.

## Native source and output

| Limit | Value |
| --- | ---: |
| Ordered source parts | 1–16 |
| Bytes in one Mac source page | 24,576 |
| Output banks | 1, bank zero |
| Encoded instruction length | 1–4 bytes |
| Build descriptor | 15 bytes |
| Complete 16-part descriptor array | 80 bytes |

Every source part must fit one 24 KiB page. Total source may exceed that size
because the Mac adapter replaces the page at part boundaries. The checked
self-host input is Measured 99,469 bytes in six parts; its largest individual
part fits the page.

The native target uses a non-wrapping half-open 16-bit range whose mathematical
end is at most `$FFFF`. It cannot currently represent `$10000` as an exclusive
end. Starting at zero therefore permits a maximum capacity of 65,535 bytes,
covering `$0000` through `$FFFE`.

## Symbols and pending references

An exact symbol record is Measured 8 bytes. A global consumes one record for
the rest of the build. Private records consume space only in the current global
scope and are evicted at the next global label. A pending reference consumes
Measured 6 bytes until its symbol is defined and its patch has been submitted.

The Mac proof map provides:

| Arena | Classification | Bytes | Complete records |
| --- | --- | ---: | ---: |
| Symbols | Measured | 13,312 | 1,664 simultaneous symbols |
| Pending references | Measured | 2,560 | 426 simultaneous references |

The useful source-size limit depends on symbol density and on the peak, not the
total, number of private and unresolved records. For any target map:

```text
symbol bytes  = 8 * (permanent globals + peak private symbols in one scope)
pending bytes = 6 * peak concurrent unresolved references
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

The general resolver and SP1 wire format allow more than the current native
driver. `assembleAtomProject` lowers the relevant capacities before execution.

| Host preparation limit | Default |
| --- | ---: |
| Graph parts | 255; 16 for native Atom |
| Dependency depth, including entry | 64 |
| Logical path | 255 ASCII bytes |
| Retained logical paths | 65,536 bytes |
| SP1 bank ordinal | 0–255; zero for native Atom |

The Mac runner's default execution budgets are 200,000,000 Z80 instructions
and 2,000,000,000 T-states. Atom's measured self-build uses 163,392,529
instructions and 1,492,523,777 T-states.

## A realistic 24 KiB TEC workspace

The current Mac capacities are not a TEC memory map. Fixed workspace, symbols,
pending records, descriptors, and a 256-byte stack already total Measured
16,774 bytes at those capacities, leaving 7,802 bytes in a 24 KiB RAM budget
before any source buffer or operating-adapter state. A 24,576-byte source page
cannot coexist there.

A practical TEC deployment must choose smaller arenas from measured program
density, place source in a separate bank or external window, or replace the
memory-backed tokenizer boundary with a measured source service. The deployed
capacity is therefore a target configuration, not a claim inherited from the
Mac harness.
