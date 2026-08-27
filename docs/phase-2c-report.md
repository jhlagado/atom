# Atom Phase 2c concrete instruction parser report

## Authority migration checkpoint

The concrete parser differential now calls the expression-enabled parser in
the authoritative `native/atom.asm` core. It no longer assembles the reduced
`asm/parser-proof.asm` variant. Every case starts with fresh symbol and pending
arenas, so a name operand follows the public expression path before complete
form validation. `LD Q,A`, for example, reports an invalid form rather than the
reduced parser's unknown-operand category; both paths leave the destination and
symbol state unchanged.

The checked parser contains **Measured 1,980 bytes** of rule code, **Measured
81 bytes** of operand-table data, and **Measured 92 bytes** of fixed workspace.
The full parser path through the encoder, symbols, tokenizer, expression
evaluator, and patch locator contains **Measured 9,240 bytes** of code and
tables plus **Measured 667 bytes** of workspace. The complete native core
is **Measured 12,396 resident bytes**. The original Phase 2c measurements
and projections below remain as the historical prototype account.

## Result

**Correctness: Measured pass.** The native parser converts instruction text to
the existing ten-byte encoder record, then the native encoder produces the
same bytes as the frozen AZM oracle for **Measured 3,445 of 3,445 supported
forms (100%)**. The same corpus passes with alternating letter case. Atom also
rejects **Measured 526 AZM-invalid forms** without changing the caller's record.

AZM strict register contracts pass for the integrated encoder, symbol core,
tokenizer, and parser image. The runtime proof checks the exact return PC and
SP, two-sided stack/source/record/output canaries, immutable resident bytes,
failure atomicity, execution budgets, and every write in the **Measured 65,536-byte
address space**.

## Byte account

All extents come from fresh AZM symbols in `asm/parser-proof.asm`.

| Component | Classification | Bytes |
| --- | --- | ---: |
| Rule-driven parser code | Measured | 1,267 |
| Packed operand-name table | Measured | 81 |
| **Parser code and immutable data** | **Measured** | **1,348** |
| Fixed parser workspace | Measured | 40 |

The operand table has **Measured 27 entries at three bytes each**: one packed
RADIX-40 word and one operand class. The parser reuses the existing packer and
mnemonic recognizer. Mnemonic recognition therefore adds **Measured zero new
bytes** in Phase 2c; its existing account remains **Measured 454 exclusive
bytes**, or **Measured 648 bytes** when the shared packer is included.

The parser has **Measured zero direct LD-only bytes**. LD uses the common
operand classifier, numeric normalization, candidate validation, and concrete
range checks. The encoder's direct LD subtotal remains **Measured 1,043
bytes**. A larger parser subtotal for LD would assign shared routines to one
mnemonic and double-count them.

The integrated resident account is now:

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core | Measured | 659 |
| Streaming tokenizer | Measured | 1,174 |
| Concrete instruction parser | Measured | 1,348 |
| **Integrated code and immutable data** | **Measured** | **7,178** |
| **Integrated fixed workspace** | **Measured** | **109** |

Caller-owned source, parsed records, output, symbol records, pending records,
and stack are outside the fixed-workspace account.

## Parser contract

`AtomParserParse` accepts the current instruction address and a ten-byte
destination. It consumes one tokenized instruction line. Success commits the
complete record and returns its address in IX. EOF and every error leave the
record unchanged. Relative targets are converted from absolute addresses using
the validated instruction length, so the exact **Measured signed range of -128
through 127** is checked before commit.

The parser classifies registers, register pairs, conditions, parenthesized
memory, ports, index halves, signed IX/IY displacement, immediate widths, bit
numbers, interrupt modes, and restart vectors. The encoder's form validator is
the authority for mnemonic/operand legality; the parser does not contain a
second validity matrix. Ambiguous `C` is tried as both register C and condition
C. Flexible numeric operands begin as an eight-bit candidate and widen to a
sixteen-bit candidate only when the form requires it.

AZM accepts `(IX)` and `(IY)` in two different roles. `JP (IX)` and `JP (IY)`
use indirect register classes. Other accepted forms treat the same spellings as
indexed memory with a zero displacement. The parser proves both meanings,
including `(IX+0)`, `(IX-0)`, and their IY equivalents. The proof derives
**Measured 484 canonical zero-displacement forms** and checks both alternate
spellings, for **Measured 968 additional source/record/byte comparisons**.

## Differential coverage

The frozen Phase 1 census supplies the denominator and its source/record hash.
Phase 2c compares the parser's record before comparing emitted bytes, so an
encoder coincidence cannot hide a classification error.

| Coverage observation | Result |
| --- | ---: |
| Frozen AZM-supported logical forms | Measured 3,445 |
| Exact parsed-record matches | Measured 3,445 / 3,445 |
| Exact AZM byte matches after native encoding | Measured 3,445 / 3,445 |
| Alternating-case record and byte matches | Measured 3,445 / 3,445 |
| AZM-invalid forms rejected atomically | Measured 526 / 526 |
| Additional indexed-zero spelling aliases | Measured 968 |

**Unsupported claimed instruction forms: Measured none.** Every logical form
in the frozen AZM encoder census parses and encodes. The parser also covers the
zero-displacement `(IX)` and `(IY)` spelling aliases, which normalize to records
already present in that census.

Phase 2c deliberately does not claim these source forms:

- symbol operands, including forward references and private `.` names;
- `$` as the current address inside an operand;
- arithmetic, bitwise, shift, unary, or parenthesized expressions around
  numeric operands;
- directives, labels, equates, strings, or multiple statements per line;
- AZM's `0x`/`0b` prefixes, `H`/`B` suffixes, single-quoted bytes,
  question-mark names, dotted directives, brackets, and typed-layout syntax.

Those are expression, symbol, directive, or lexical facilities rather than
missing Z80 instruction forms. The tokenizer report records the deliberately
narrower lexical boundary.

## Execution measurement

The full positive and negative corpora produced these worst observed paths:

| Entry | Classification | Instructions | T-states | Case |
| --- | --- | ---: | ---: | --- |
| `AtomTokenizerReset` | Measured | 22 | 248 | `NOP` source part |
| `AtomParserParse` | Measured | 3,864 | 37,057 | rejected `LD (IY-1),(IY-1)` |
| `AtomEncode` | Measured | 209 | 2,040 | `LD (IY-128),$00` |

The longest parser path is about **Measured 9.26 ms at 4 MHz**. Named proof
budgets retain margin above each measured maximum.

## Whole-assembler projection

Phase 2b projected **Projected 1,600–2,200 bytes** for operand expressions and
directives together. Phase 2c measured **Measured 1,348 bytes** of that work,
leaving an arithmetic remainder of **Projected 252–852 bytes** for general
expressions and directives. That remainder is not an independent measurement
and carries the same estimation risk as the earlier combined range.

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Multipart source iterator | Projected | 100–250 |
| General expressions and directives | Projected | 252–852 |
| Symbol integration and additional diagnostics | Projected | 100–400 |
| Append-only NOBJ image and patch output | Projected | 800–1,200 |
| Control, diagnostics, and integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **2,252–4,202** |

Adding that range to the **Measured 7,178-byte** resident account gives a
**Projected whole-assembler total of 9,430–11,380 bytes**, or about
**Projected 9.2–11.1 KiB**. The projected margin below the **Target 16 KiB
bank** is **Projected 4.9–6.8 KiB**. Symbol and pending arenas remain RAM data,
not resident code.

## Reproduction

```sh
npm run annotate:contracts  # after routine-body changes; review the diff
npm test
npm run measure:parser
```

The commands verify the frozen dependency identities, rebuild AZM and the
Debug80 runtime, assemble with strict contracts, execute the differential and
memory proofs, and print symbol-derived measurements.
