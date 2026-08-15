# Atom Phase 2d expression evaluator report

## Result

**Correctness: Measured pass.** The native evaluator implements AZM's integer
precedence ladder for `|`, `^`, `&`, `<<`, `>>`, `+`, `-`, `*`, `/`, and `%`,
with unary `+`, `-`, and `~`, grouping parentheses, the current address `$`,
and case-insensitive global and private symbol names. The concrete differential
contains **Measured 1,787 expressions**, all of which produce the same 16-bit
word as the frozen AZM oracle.

AZM strict register contracts pass for the integrated encoder, symbol core,
tokenizer, parser, and evaluator image. The runtime proof checks the exact
return PC and SP, two-sided stack/source/key/symbol/pending canaries, immutable
resident bytes, source preservation, execution budgets, and every write in the
**Measured 65,536-byte address space** on every exercised call.

Phase 2d does not connect general expressions to instruction operands. The
evaluator has a separate entry point and a proved handoff to the existing
pending-reference core. Parser integration remains Phase 2e.

## Byte account

All extents come from fresh AZM symbols in `asm/expression-proof.asm`.

| Component | Classification | Bytes |
| --- | --- | ---: |
| Rule-driven evaluator code | Measured | 1,880 |
| Immutable expression tables | Measured | 0 |
| **Expression code and immutable data** | **Measured** | **1,880** |
| Value stack, 16 ten-byte entries | Measured | 160 |
| Operator stack, 16 five-byte entries | Measured | 80 |
| Other evaluator workspace | Measured | 62 |
| **Fixed evaluator workspace** | **Measured** | **302** |

The evaluator uses an iterative operator/value-stack parser. This removes
recursive Z80 stack use and gives both capacities an exact RAM cost. Sixteen
operator entries permit up to **Measured 16 grouping or unary levels**; the
seventeenth is a diagnosed capacity failure. A later valid expression resets
the bounded state and evaluates normally.

The integrated resident account is now:

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core | Measured | 659 |
| Streaming tokenizer | Measured | 1,051 |
| Concrete instruction parser | Measured | 1,348 |
| Expression evaluator and pending handoff | Measured | 1,880 |
| **Integrated code and immutable data** | **Measured** | **8,935** |
| **Integrated fixed workspace** | **Measured** | **411** |

Caller-owned source, parsed records, emitted bytes, symbol records, pending
records, and the Z80 call stack remain outside the fixed-workspace account.

## Expression and forward-reference contract

Concrete arithmetic uses signed 24-bit intermediates. A successful concrete
result must finish in the accepted word domain **Measured -32,768 through
65,535**. Division truncates toward zero and remainder has the dividend's sign,
matching AZM. Shift counts are **Measured 0 through 23**; arithmetic overflow,
invalid shifts, division by zero, malformed input, and capacity exhaustion have
distinct status values and source positions.

The six-byte pending record cannot retain an expression tree. An unresolved
expression is therefore restricted to one exact symbol plus a signed-byte
addend, **Measured -128 through 127**. Accepted examples include `name`,
`name+5`, `5+name`, `name-5`, and `name+(2*3)`. Two unresolved symbols,
multiplication of a symbol, unary negation of a symbol, and an out-of-range
addend are rejected. A missing symbol is inserted only after the complete
expression passes, so invalid input cannot leak global or private records.

`AtomExpressionQueue` converts the successful unresolved result directly to
the existing pending ABI: symbol-record address, patch address, patch kind,
and signed-byte addend. The proof compares the resulting six bytes exactly.

The tokenizer gives `%0` and `%1` binary-literal meaning when the percent sign
is adjacent to the digit. Remainder by zero or one must therefore contain
whitespace, as in `value % 0`. This is a lexical boundary, not an evaluator
exception.

## Differential and negative coverage

| Coverage observation | Result |
| --- | ---: |
| Boundary-partitioned concrete AZM comparisons | Measured 1,787 / 1,787 |
| Explicit lexical, syntax, range, divide, and capacity failures | Measured 10 / 10 |
| Case-insensitive defined global/private symbol checks | Measured pass |
| Affine forward-symbol acceptance and rejection checks | Measured pass |
| Exact pending-record handoff | Measured pass |
| Frozen instruction forms still covered by the parser/encoder proof | Measured 3,445 / 3,445 |

**Unsupported claimed instruction forms: Measured none.** Phase 2d changes no
instruction encoding claim. General expressions in instruction operands are
explicitly unsupported until Phase 2e connects this evaluator to the parser.

## Execution measurement

The measurement corpus produced these worst observed paths:

| Entry | Classification | Instructions | T-states | Case |
| --- | --- | ---: | ---: | --- |
| `AtomExpressionParse` | Measured | 4,189 | 41,491 | instructions: `100/5/2`; cycles: `(-32768) % (-32768)` |
| `AtomTokenizerNext` | Measured | 494 | 5,038 | first token of `Forward+(2*3)` |
| `AtomPackSymbol` | Measured | 368 | 3,207 | `Base` |
| `AtomSymbolDeclare` | Measured | 63 | 870 | `Base=$1234` |
| `AtomExpressionQueue` | Measured | 45 | 442 | `Target-3` handoff |

The longest measured evaluator path is about **Measured 10.37 ms at 4 MHz**.
Named proof budgets retain margin above every measured maximum.

## Whole-assembler projection

Phase 2c left **Projected 252–852 bytes** from the old combined estimate for
general expressions and directives. The evaluator alone is **Measured 1,880
bytes**, exceeding that remainder by **Measured 1,028–1,628 bytes**. The old
whole-assembler projection is therefore retired.

The directive range below is a new projection based on reusing the measured
tokenizer, evaluator, and symbol APIs for a small directive dispatcher. It is
not derived by subtracting from the failed estimate.

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Flat-manifest source-part iterator | Projected | 100–250 |
| Labels, equates, and required directives | Projected | 300–800 |
| Symbol integration and additional diagnostics | Projected | 100–400 |
| Append-only NOBJ image and patch output | Projected | 800–1,200 |
| Control, diagnostics, and integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **2,300–4,150** |

Adding that range to the **Measured 8,935-byte** resident account gives a
**Projected whole-assembler total of 11,235–13,085 bytes**, or about
**Projected 11.0–12.8 KiB**. The projected margin below the **Target 16 KiB
bank** is **Projected 3,299–5,149 bytes**. Symbol and pending arenas remain RAM
data rather than resident code.

## Reproduction

```sh
npm run annotate:contracts  # after routine-body changes; review the diff
npm test
npm run measure:expression
```

The commands verify the frozen dependency identities, rebuild AZM and the
Debug80 runtime, assemble with strict contracts, execute the differential and
memory proofs, and print symbol-derived measurements.
