# Atom Phase 2a symbol and pending-reference report

## Result

**Correctness: Measured pass.** AZM strict register and stack contracts pass.
Direct Z80 entry tests check exact return PC and SP, two-sided arena guards,
full-address-space write boundaries, case folding, name limits, duplicates, forward
definition, private eviction, stale-pending detection, and capacity at one byte
below, exactly at, and one byte above both record sizes.

**Resident symbol code: Measured 659 bytes.** Fixed non-reentrant workspace is
**Measured 28 bytes**. Each exact symbol record is **Measured 8 bytes** and each
pending reference is **Measured 6 bytes**. Linking this code with the measured
3,997-byte encoder gives **Measured 4,656 resident bytes** plus **Measured 37
fixed workspace bytes**. No Phase 1 code or table is duplicated.

## Record and scope result

The leading `.` is removed before RADIX-40 packing and stored as a flag. A
private spelling therefore has eight useful characters after `.` without
increasing the record. Permanent globals grow upward and current-scope private
records grow downward in one caller-owned arena. The two cursors may meet
exactly; the next insertion fails before writing.

Private RAM is `8 × peak private symbols in one global scope`, not eight times
the total number of private labels in the source. Pending RAM is `6 × peak
concurrent unresolved references`; resolved entries are reclaimed.

## RAM feasibility

The Nucleus calibration contains **Measured 1,617 permanent symbols** and a
**Measured peak of 395 unresolved references** in a 15 KiB target program. At
Atom's measured record sizes this requires:

| Resident data | Classification | Bytes |
| --- | --- | ---: |
| Permanent symbols: 1,617 × 8 | Measured layout applied to measured census | 12,936 |
| Pending peak: 395 × 6 | Measured layout applied to measured peak | 2,370 |
| Fixed encoder and symbol workspace | Measured | 37 |
| **Subtotal before private peak, stack, and integration state** | **Projected from measured inputs** | **15,343** |

With source and output streamed, a Nucleus-density projection gives the
following symbol-limited target sizes. It assumes permanent-symbol and pending
peak density scale linearly and excludes private peak, stack, and remaining
assembler workspace, so it is an optimistic capacity bound.

| Effective RAM for these accounts | Projected target size |
| ---: | ---: |
| 24 KiB | 24.0 KiB |
| 20 KiB | 20.0 KiB |
| 16 KiB | 16.0 KiB |

A 64 KiB target at the same density would require approximately **Projected
55,194 bytes (53.9 KiB)** of permanent symbols and **Projected 10,112 bytes
(9.9 KiB)** of pending records.
That source cannot be assembled within a 24 KiB workspace under the present
resident-table design. A less symbol-dense 64 KiB source may fit; target byte
size alone does not determine the requirement.

## Lookup cost

The prototype uses a linear exact-name scan. An empty failed lookup is
**Measured 17 instructions and 199 T-states**. An eight-record failed lookup is
**Measured 169 instructions and 1,847 T-states**, an exact observed slope of 19
instructions and 206 T-states per record in this path.

At 1,617 permanent records, the same path is **Projected about 30,740
instructions and 333,301 T-states**, or about 83 ms at 4 MHz for a worst-case
lookup. This may make a complete assembly slow even though it fits. The
prototype establishes the byte cost; a later phase should measure whole-source
assembly time before choosing a larger index or hash structure.

## Whole-assembler projection

The measured resident total is now 4,656 bytes. Replacing the old
symbol/pending estimate with the measured prototype and retaining explicit
integration allowance gives:

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Source adapter and tokenizer/classifier | Projected | 1,300–1,800 |
| Operand expressions and directives | Projected | 1,600–2,200 |
| Symbol integration and diagnostics beyond the prototype | Projected | 100–400 |
| Append-only NOBJ image/patch output | Projected | 800–1,200 |
| Diagnostics, control, and integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **4,800–7,100** |

The resulting whole assembler is **Projected 9,456–11,756 bytes**, or
**9.2–11.5 KiB**. This leaves **Projected 4.5–6.8 KiB** in a 16 KiB bank. The
range remains a hypothesis until each remaining component is measured; earlier
project estimates have understated cost.

## Reproduction

```sh
npm run annotate:contracts
npm test
npm run measure
npm run measure:symbols
```

The test command verifies the frozen dependency trees, rebuilds AZM and the
runtime, requires strict contracts, executes both native proof harnesses, and
checks both complete 64 KiB memory profiles.
