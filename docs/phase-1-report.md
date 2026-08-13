# atom Phase 1 measurement report

## Result

**Correctness: Measured pass.** The native Z80 encoder produced byte-identical
output to the frozen AZM oracle for all 3,445 generated valid source cases. The
negative differential rejected all 526 sampled invalid cases without changing
the destination.

**Resident core: Measured 3,968 bytes.** This exceeds the 3,500-byte
stop-and-review gate by 468 bytes. It is 1,032 bytes below the 5,000-byte reject
gate. Phase 1 therefore stops here without a compression pass and without work
on the tokenizer, symbol table, directives, or output layer.

Writable workspace is **Measured 9 bytes**: six overlaid RADIX-40/commit bytes
and three binary-search state bytes.

## Resident byte account

All extents below come from fresh AZM symbols in `asm/encoder-proof.asm`.

| Component | Classification | Bytes |
| --- | --- | ---: |
| Rule-driven instruction encoding | Measured code | 1,834 |
| Form validation and `formLength` | Measured code | 1,398 |
| RADIX-40 packer | Measured code | 194 |
| Mnemonic binary search | Measured code | 109 |
| Opcode/ordinal tables | Measured immutable data | 88 |
| Packed mnemonic table | Measured immutable data | 345 |
| **Code subtotal** | **Measured** | **3,535** |
| **Table-data subtotal** | **Measured** | **433** |
| **Resident total** | **Measured** | **3,968** |

The requested high-level split is therefore **Measured 3,535 bytes of
rule-driven code versus 433 bytes of table data**. “Rule-driven” here includes
the validation, recognition, and packing algorithms as well as opcode
construction; no code bytes are hidden in the table account.

The opcode table contains 34 two-byte singleton records plus 20 bytes of IM,
rotate/shift, and ALU selectors. The mnemonic table contains **Measured 69
entries × 5 bytes = 345 bytes**.

## LD and recognition

LD is **Measured 1,043 direct bytes**:

- LD validation: **Measured 411 bytes**;
- LD encoding: **Measured 632 bytes**.

This is 26.3% of the whole resident core and 32.3% of validation plus encoding.
Generic predicates, prefix selection, value-copy helpers, and common return
tails are outside the direct LD extent and are not double-counted. LD uses them,
so 1,043 bytes is a direct subtotal rather than a claim that LD has no share of
common code.

Mnemonic recognition is **Measured 454 exclusive bytes**: 109 bytes of binary
search plus its 345-byte packed table. Including the shared 194-byte RADIX-40
packer makes the recognizer path **Measured 648 bytes**. The packer is retained
as a separate account because the later symbol table also needs it.

## Differential coverage

The generator enumerates every logical instruction form exposed by the frozen
AZM Z80 grammar, expanding registers, conditions, bit numbers, RST vectors, IM
modes, index families, and indexed CB register destinations. Numeric fields use
the agreed boundary partitions.

| Coverage observation | Result |
| --- | ---: |
| Mnemonic spellings | Measured 69 |
| Valid source cases compared with AZM | Measured 3,445 |
| Distinct normalized input records | Measured 3,310 |
| Distinct emitted byte sequences | Measured 3,222 |
| AZM-rejected cases also rejected by atom | Measured 526 |
| AZM-supported logical instruction forms covered | **Measured 3,445 / 3,445 (100%)** |

The valid set includes:

- every register, condition, bit, RST, and IM enumeration;
- `imm8`: 0, 1, 127, 128, 255;
- `imm16`: 0, 1, 32767, 32768, 65535;
- indexed and relative displacements: -128, -1, 0, 1, 127;
- IX and IY families;
- IXH/IXL/IYH/IYL transfers and their family/H/L collision rules;
- CB, indexed CB, ED, DD, and FD forms;
- SLL and its SLS source alias;
- explicit-`A` ALU spellings where AZM accepts them; and
- AZM's two legacy register-pair LD expansions.

The denominator is AZM's logical source-form grammar, not every redundant byte
stream a Z80 will execute after arbitrary or repeated prefixes.

**Unsupported AZM forms: Measured none.** No valid form accepted by the frozen
AZM grammar is intentionally omitted by atom. Forms AZM itself rejects are not
claimed by atom and do not enter the denominator; examples include immediate
loads into index-half registers and a three-operand indexed `BIT` spelling.

Negative cases include the LD operand cross-product plus targeted arity,
condition, branch, stack, I/O, RST, IM, CB, and index-half failures. Both
`AtomFormLength` and `AtomEncode` reject them. The commit-buffer canary proves no
byte is published on failure.

## Whole-assembler projection

The encoder is the only newly measured wide-uncertainty component. For a
whole-assembler projection, the frozen Nucleus tree supplies two directly
comparable measurements: **Measured 142 bytes** for its streaming source
adapter and **Measured 865 bytes** for its tokenizer. atom needs a different
operand/directive grammar, so those numbers are a basis, not copied totals.

The remaining resident components are provisionally budgeted as follows:

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Source adapter and tokenizer/classifier | Projected | 1,300–1,800 |
| Operand expressions and directives | Projected | 1,600–2,200 |
| Symbol and pending-reference algorithms | Projected | 1,300–1,900 |
| Append-only NOBJ image/patch output | Projected | 800–1,200 |
| Diagnostics, control, and integration | Projected | 1,000–1,500 |
| **Remaining resident subtotal** | **Projected** | **6,000–8,600** |

Adding the **Measured 3,968-byte** Phase 1 core gives a **Projected whole
assembler total of 9,968–12,568 bytes**, or **9.7–12.3 KiB**. This leaves a
**Projected 3.7–6.3 KiB** below a 16 KiB bank.

That range is not clearance to continue automatically. Historical estimates
on this project have run 2.6× low, and the encoder has already crossed its
review gate. The projection remains provisional until this result is reviewed
and later components are independently measured.

## Reproduction

```sh
npm test
npm run measure
```

The first command assembles the native core with AZM, executes it under the
Debug80 Z80 runtime, and runs positive and negative differential proofs. The
second prints the symbol-derived byte accounts and coverage census.
