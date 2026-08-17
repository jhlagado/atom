# Atom Phase 1 measurement report

This report preserves the original Phase 1 checkpoint. The later native
compression pass reduced the same encoder from 3,997 to Measured 3,132 resident
bytes and from 9 to Measured 6 workspace bytes while retaining the complete
differential. See [the native compression audit](native-compression-audit.md)
for the current account and measured execution trade-off.

## Result

**Correctness: Measured pass.** Strict AZM register and stack contracts pass.
Direct native entry proofs produced byte-identical output to the frozen AZM
oracle for all 3,445 valid census cases. The negative differential rejected all
526 AZM-invalid sources, and systematic validation rejected 2,453 malformed
records, without changing the destination.

**Resident core: Measured 3,997 bytes.** This exceeds the 3,500-byte
stop-and-review gate by 497 bytes. It is 1,003 bytes below the 5,000-byte reject
gate. Phase 1 therefore stops here without a compression pass and without work
on the tokenizer, symbol table, directives, or output layer.

The review accepted the 3,997-byte result without a compression pass. The
one-bank question remains open until the other components have measured
accounts; crossing the review gate did not by itself select a second bank.

Writable workspace is **Measured 9 bytes**: six overlaid RADIX-40/commit bytes
and three binary-search state bytes.

## Resident byte account

All extents below come from fresh AZM symbols in `asm/encoder-proof.asm`.

| Component | Classification | Bytes |
| --- | --- | ---: |
| Rule-driven instruction encoding | Measured code | 1,834 |
| Form validation and `formLength` | Measured code | 1,427 |
| RADIX-40 packer | Measured code | 194 |
| Mnemonic binary search | Measured code | 109 |
| Opcode/ordinal tables | Measured immutable data | 88 |
| Packed mnemonic table | Measured immutable data | 345 |
| **Code subtotal** | **Measured** | **3,564** |
| **Table-data subtotal** | **Measured** | **433** |
| **Resident total** | **Measured** | **3,997** |

The requested high-level split is therefore **Measured 3,564 bytes of
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

This is 26.1% of the whole resident core and 32.0% of validation plus encoding.
Generic predicates, prefix selection, value-copy helpers, and common return
tails are outside the direct LD extent and are not double-counted. LD uses them,
so 1,043 bytes is a direct subtotal rather than a claim that LD has no share of
common code.

Mnemonic recognition is **Measured 454 exclusive bytes**: 109 bytes of binary
search plus its 345-byte packed table. Including the shared 194-byte RADIX-40
packer makes the recognizer path **Measured 648 bytes**. The packer is retained
as a separate account because the later symbol table also needs it.

## Differential coverage

The frozen AZM form census locks the denominator with exact per-mnemonic counts
and a SHA-256 hash of every canonical source/record pair. The independently run
generator must match that census before byte comparison begins, so deleting a
whole family cannot leave a false 100% result. Numeric fields use the agreed
boundary partitions.

| Coverage observation | Result |
| --- | ---: |
| Mnemonic spellings | Measured 69 |
| Valid source cases compared with AZM | Measured 3,445 |
| Distinct normalized input records | Measured 3,310 |
| Distinct emitted byte sequences | Measured 3,222 |
| AZM-rejected cases also rejected by atom | Measured 526 |
| Systematic malformed records rejected by atom | Measured 2,453 |
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

Negative cases include the LD operand cross-product; every unknown mnemonic
ordinal; every unused operand-class value in a representative dispatcher; all
hidden trailing operands; and targeted arity, condition, branch, stack, I/O,
RST, IM, CB, and index-half failures. Both `AtomFormLength` and `AtomEncode`
reject them. This proof found and fixed hidden-operand acceptance in indexed
rotates and one-operand ALU/JP/CALL/JR paths.

Every public routine is entered directly with a sentinel return address. The
proof checks final PC, exact SP, DE semantics, register preservation from the
generated contracts, input preservation, two-sided guards, failure atomicity,
and writes outside declared memory regions. `formLength` is repeated for every
valid and rejected record with four concrete-value patterns. RADIX-40 exhausts
ASCII classification, all one/two-character arithmetic, and every field
position. Named instruction and cycle budgets come from measured maxima with
margin. The memory profile covers all 65,536 addressable bytes without gaps or
overlap.

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

Adding the **Measured 3,997-byte** Phase 1 core gives a **Projected whole
assembler total of 9,997–12,597 bytes**, or **9.8–12.3 KiB**. This leaves a
**Projected 3.7–6.3 KiB** below a 16 KiB bank.

That range is not clearance to continue automatically. Historical estimates
on this project have run 2.6× low, and the encoder has already crossed its
review gate. The projection remains provisional until this result is reviewed
and later components are independently measured.

## Reproduction

```sh
npm run annotate:contracts  # only after changing routine bodies; review the diff
npm test
npm run measure
```

Both commands first verify the reviewed dependency tree identities and rebuild
AZM and Debug80 runtime from source. The first then requires strict contracts,
executes the public ABI under the runtime, validates the complete memory
profile, and runs positive and negative proofs. The second prints symbol-derived
byte accounts and the frozen coverage census.
