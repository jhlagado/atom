# Atom Phase 2g statement-layer report

## Result

**Measured: pass.** Atom now assembles case-insensitive instruction, label,
equate, placement, and data statements from a native source stream. The
implemented directives are the agreed bare forms `EQU`, `ORG`, `DB`, `DW`, and
`DS`.

The full statement path is byte-identical to frozen AZM for **Measured: 3,445
of 3,445 claimed instruction forms (100%)**. Multi-line directive programs are
also compared with AZM at numeric, signed, list, current-address, placement,
reservation, and fill boundaries. Atom string escapes are compared after the
required host translation to explicit AZM byte values.

AZM strict register contracts pass for the linked Phase 2g image. Runtime
proofs check exact return PC and SP, two-sided canaries, immutable code, source
preservation, bounded arenas, complete-address-space writes, direct data-output
entries, injected capacity failures, and a **Measured: 65,536-byte** memory
map. The complete repository suite contains **Measured: 193 passing tests**.

## Resident byte account

Phase 2f measured 10,269 bytes of code and immutable data and 491 bytes of
fixed workspace. Phase 2g adds 1,436 code/data bytes and 50 workspace bytes.

| Phase 2g increment | Classification | Code/data bytes |
| --- | --- | ---: |
| Parser continuation after a published mnemonic | Measured | 22 |
| Global-label transaction, pending preflight, and statement symbol support | Measured | 144 |
| Signed-symbol expression support | Measured | 21 |
| Data/placement output and truncating patch support | Measured | 129 |
| Statement dispatcher, five-directive recognizer, labels, equates, data lists, and strings | Measured | 1,120 |
| **Phase 2g increment** | **Measured** | **1,436** |

The five-entry directive table occupies **Measured: 20 bytes** inside the
statement component. The other **Measured: 1,100 statement bytes** are
rule-driven code. No per-mnemonic or per-directive syntax matrix was added.

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, and mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core | Measured | 867 |
| Streaming tokenizer | Measured | 1,174 |
| Expression evaluator | Measured | 1,929 |
| Patch-field locator | Measured | 73 |
| Symbolic instruction parser | Measured | 2,057 |
| Nucleus-model output and resolver | Measured | 488 |
| Statement layer | Measured | 1,120 |
| **Integrated code and immutable data** | **Measured** | **11,705** |
| **Integrated fixed workspace** | **Measured** | **541** |

The measured code margin below 16 KiB is **Measured: 4,679 bytes**. Caller-owned
source, symbol records, pending records, sink spools, and stack remain outside
the fixed-workspace account.

## Supported and unsupported forms

Measured positive coverage includes standalone and same-line global/private
labels, mixed case, immediate and forward equate use, signed equates, all
proved expression operators, byte and word lists, string fragments, current
address per list item, multiple origins, uninitialized and filled storage,
and forward data patches.

The explicit unsupported list is:

- forward-dependent equates;
- unresolved origins;
- unresolved `DS` counts or fill values;
- strings in `DW`;
- string-valued equates;
- `NAME: EQU VALUE`;
- dotted `.EQU`, `.ORG`, `.DB`, `.DW`, and `.DS` aliases; and
- any directive outside the five Phase 2g essentials.

The final undefined-symbol check is not yet present. Part EOF therefore cannot
commit a generation.

## Execution measurements

The longest measured `AtomAssemblePart` case executes a six-statement program
with signed equates and three instructions in **Measured: 24,496 instructions
and 239,549 T-states**, about **Measured: 59.9 ms at 4 MHz**. Direct output
entries measure 74 instructions for a byte, 141 for a word, 20 for a
reservation, and 3 for an origin change. Named proof budgets retain margin
above each observation.

## Whole-assembler projection

Remaining native work is smaller than the completed statement layer:

| Remaining native component | Classification | Bytes |
| --- | --- | ---: |
| Flat SP1/source-part iterator and part reset | Projected | 100–250 |
| Final undefined-symbol check and finish entry | Projected | 100–250 |
| Assembly driver and sink commit/abort lifecycle | Projected | 150–350 |
| Native diagnostic formatting and integration state | Projected | 300–600 |
| Self-assembly and target initialization glue | Projected | 200–400 |
| **Remaining subtotal** | **Projected** | **850–1,850** |

Adding that range to **Measured: 11,705 bytes** gives a **Projected:
whole-assembler total of 12,555–13,555 bytes**. The projected margin below the
16 KiB code limit is **Projected: 2,829–3,829 bytes**. Host preprocessing,
filesystem resolution, SP1 production, Intel HEX, listing, D8 maps, and NOBJ
serialization remain host or operating-adapter services and do not enter this
resident account.

## Reproduction

```sh
npm run annotate:contracts
npm test
npm run measure:output
npm run measure:statements
```

These commands verify the frozen Debug80/AZM dependency identity, strict
contracts, historical byte stability, full Phase 2g memory profile, statement
differentials, and fresh symbol-derived measurements.
