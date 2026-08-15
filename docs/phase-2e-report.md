# Atom Phase 2e symbolic instruction integration report

## Result

**Correctness — Measured: pass.** The instruction parser now accepts concrete
expressions and forward affine expressions. Concrete parsing and encoding
remain byte-identical to the frozen AZM oracle for **Measured: 3,445 of 3,445
supported forms (100%)**. The native patch locator identifies **Measured: 2,805
patchable operand sites** and rejects **Measured: 7,530 non-patchable sites** in
the same census.

AZM strict register contracts pass for the integrated encoder, symbol core,
tokenizer, expression evaluator, patch locator, and parser image. Runtime proofs
check exact return PC and SP, two-sided canaries, immutable resident bytes,
source preservation, destination atomicity, symbol and pending capacity,
execution budgets, and the complete **Measured: 65,536-byte address space** on
every forward-reference and failure path.

Phase 2e stops at pending metadata. It does not construct resolved patch bytes,
serialize IMAGE or PATCH records, process labels or directives, or iterate a
source manifest.

## Byte account

Phase 2d established **Measured: 8,935 bytes** of integrated code and immutable
data plus **Measured: 411 bytes** of fixed workspace. Phase 2e measures:

| Component | Classification | Code/data bytes | Workspace bytes |
| --- | --- | ---: | ---: |
| Deferred-key expression entry | Measured | 28 | 1 |
| Patch-field locator | Measured | 73 | 0 |
| Symbolic parser integration | Measured | 681 | 58 |
| **Phase 2e increment** | **Measured** | **782** | **59** |

The current integrated account is therefore:

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core | Measured | 659 |
| Streaming tokenizer | Measured | 1,051 |
| Expression evaluator with deferred-key entry | Measured | 1,908 |
| Patch-field locator | Measured | 73 |
| Symbolic instruction parser and operand table | Measured | 2,029 |
| **Integrated code and immutable data** | **Measured** | **9,717** |
| **Integrated fixed workspace** | **Measured** | **470** |

The symbolic parser workspace includes a **Measured: 26-byte private build
list** and a **Measured: 18-byte public reference list**. Both hold at most two
entries. Caller-owned source, parsed records, emitted bytes, symbol records,
pending records, and the Z80 call stack remain outside the fixed-workspace
account.

## Atomic publication

The evaluator's deferred entry returns a packed key without inserting a missing
symbol. The parser first completes expression parsing, operand normalization,
form validation, concrete range checks, and patch-field location. It then
checks every referenced key and computes the exact number of unique missing
records. One shared-arena capacity check precedes all insertions.

This ordering distinguishes failures that an eager implementation would get
wrong. `INC Forward`, `BIT Forward,A`, and `LD A,Forward*2` leave the destination,
symbol cursors, and public reference count unchanged. Two distinct forward
fields with space for only one symbol also insert neither record. Two fields
that use the same missing key insert one record and publish the same pointer in
both metadata entries.

Pending publication has a second atomic boundary. The queue routine checks
`referenceCount*6` bytes before appending the first entry. The proof exercises
an eleven-byte pending arena with a two-reference instruction and observes zero
records after the diagnosed capacity failure.

## Patch-field proof

Each patchable operand class has one structural rule:

- IX/IY displacement uses byte offset 2 and displacement kind;
- `rel8` uses the last instruction byte and relative kind;
- `imm8` uses the last instruction byte and byte kind;
- `imm16` and absolute memory use the final two bytes and word kind.

The host proof changes one parsed value at a time, encodes both records, and
compares every changed byte with the native locator's result. It performs this
check at all **Measured: 2,805 patchable sites**. The other **Measured: 7,530
operand positions** must return unpatchable.

`LD (IX+Disp),Forward` exercises the maximum reference count. Its displacement
metadata is kind 4 at byte offset 2; its immediate metadata is kind 1 at byte
offset 3. Queuing at logical address `$4000` produces patch addresses `$4002`
and `$4003` in the existing six-byte records.

## Differential and negative coverage

| Coverage observation | Result |
| --- | ---: |
| Frozen AZM-supported concrete forms parsed and encoded | Measured 3,445 / 3,445 |
| Patchable operand sites located by native code and byte differential | Measured 2,805 / 2,805 |
| Non-patchable operand sites rejected | Measured 7,530 / 7,530 |
| Resolved expression integration forms | Measured 10 / 10 |
| Forward metadata forms | Measured 5 / 5 |
| Invalid or unpatchable forward forms | Measured 4 / 4 |
| Two-reference pending handoff | Measured exact |

**Unsupported claimed instruction forms: Measured none.** Every logical form in
the frozen instruction census still parses and encodes. Phase 2e additionally
accepts expressions where a concrete result or structurally fixed patch field
exists. Forward enumerated operands are explicitly diagnosed because their
unknown value would change opcode bits and the six-byte pending record retains
no instruction tree.

## Execution measurement

| Entry | Classification | Instructions | T-states | Worst observed case |
| --- | --- | ---: | ---: | --- |
| `AtomParserParse` | Measured | 5,522 | 56,693 | `LD (IX+Disp*2),$10+2` |
| `AtomPatchLocate` | Measured | 129 | 1,152 | operand 2 lookup |
| `AtomParserQueueReferences` | Measured | 228 | 2,091 | two-reference queue |
| `AtomEncode` | Measured | 209 | 2,040 | `LD (IY-128),$00` |
| `AtomPackSymbol` | Measured | 435 | 3,736 | `Target` |
| `AtomSymbolDeclare` | Measured | 120 | 1,488 | fourth declared symbol |

The longest parser path is about **Measured: 14.17 ms at 4 MHz**.
Named proof budgets retain margin above every measured maximum.

## Whole-assembler projection

Phase 2e replaces the earlier symbol-integration projection with a measured
implementation. The remaining resident work is:

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Flat-manifest source-part iterator | Projected | 100–250 |
| Labels, equates, and required directives | Projected | 300–800 |
| Append-only NOBJ image and patch output | Projected | 800–1,200 |
| Control, diagnostics, and final integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **2,200–3,750** |

Adding that range to the **Measured: 9,717-byte** resident account gives a
**Projected: whole-assembler total of 11,917–13,467 bytes**, or about
**Projected: 11.6–13.2 KiB**. The projected margin below the **Target: 16 KiB
bank** is **Projected: 2,917–4,467 bytes**. Symbol and pending arenas remain RAM
data rather than resident code.

## Reproduction

```sh
npm run annotate:contracts  # after routine-body changes; review the diff
npm test
npm run measure:integration
```

The commands verify frozen dependency identities, build with strict AZM
contracts, execute the differential and memory proofs, and print fresh
symbol-derived measurements.
