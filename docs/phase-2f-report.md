# Atom Phase 2f Nucleus-model output report

## Result

**Correctness — Measured: pass.** Atom now submits instruction image bytes and
resolved patch bytes through the same logical target-sink boundary as Nucleus.
The operating adapter owns the image and patch spools and complete NOBJ
serialization.

The parser-to-output differential remains byte-identical to frozen AZM for
**Measured: 3,445 of 3,445 supported instruction forms (100%)**. Native proofs
cover every Z80 instruction length and all byte, word, relative, and index-
displacement patch kinds.

AZM strict register contracts pass for the complete Phase 2f image. Runtime
proofs check exact return PC and SP, two-sided canaries, immutable resident
bytes, source and parsed-record preservation, output and pending capacity,
injected adapter failures, named execution budgets, and the complete
**Measured: 65,536-byte address space** on every exercised output and
resolution failure path.

Phase 2f does not add labels, equates, directives, source-manifest iteration,
final undefined-symbol checks, map construction, or sink commit and abort
calls.

## Nucleus boundary

Atom calls logical image-byte, patch-byte, and patch-word sink entries. This is
the Nucleus model. The operating adapter owns NOBJ headers, CRC, the two
sequential spools, record ordering, commit, abort, storage capacity, and atomic
publication.

The adapter serializes every accepted image operation before every accepted
patch operation. Atom retains neither the generated image nor serialized NOBJ.
The proof-only adapter is measured separately and is not part of Atom's
resident account.

## Byte account

Phase 2e established **Measured: 9,840 bytes** of code and immutable data plus
**Measured: 470 bytes** of fixed workspace. Phase 2f adds:

| Component | Classification | Code/data bytes | Workspace bytes |
| --- | --- | ---: | ---: |
| Non-destructive pending lookup | Measured | 64 | 0 |
| Read-only parser pending preflight | Measured | 6 | 0 |
| Nucleus-model output and patch resolver | Measured | 359 | 21 |
| **Phase 2f increment** | **Measured** | **429** | **21** |

The integrated account is:

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core with pending peek | Measured | 723 |
| Streaming tokenizer | Measured | 1,174 |
| Expression evaluator | Measured | 1,908 |
| Patch-field locator | Measured | 73 |
| Symbolic parser with output preflight | Measured | 2,035 |
| Nucleus-model output and resolver | Measured | 359 |
| **Integrated code and immutable data** | **Measured** | **10,269** |
| **Integrated fixed workspace** | **Measured** | **491** |

The output workspace contains the target cursor, remaining capacity, a
four-byte instruction buffer, and patch calculation scratch. Caller-owned
symbol records, pending records, source, sink spools, sink state, and the Z80
stack remain outside fixed workspace.

The proof adapter measures **Measured: 178 code bytes** and **Measured: 10
workspace bytes**. It is external-service evidence, not Atom resident code.

## Image publication

`AtomOutputEmitInstruction` encodes into scratch and checks the complete local
output and pending capacity before the first sink call. It then submits bytes
one at a time through the Nucleus image sink. The target cursor advances only
after each accepted byte. Pending records become visible after every byte of
the instruction has been accepted.

The proof injects an adapter failure at **Measured: all four possible byte
positions of a four-byte instruction**. Earlier accepted image operations
remain in the uncommitted proof spool, the cursor reports their exact count,
and no pending record is published. The future driver will abort that
generation, matching Nucleus.

The proof adapter reserves each complete logical operation before writing it.
Image and word-patch operations are exercised with one byte less than needed,
exactly enough space, and one byte more; rejected operations leave both the
spool cursor and its after-canary unchanged.

## Patch resolution

The resolver peeks without removing, calculates and checks the final value,
submits a byte or word patch, then reclaims the six-byte pending record. A
range failure or failed sink call leaves the current pending record unchanged.

Evidence includes:

- byte values 0 and 255, with -1 and 256 rejected;
- displacements -128, -1, 0, and 127, with 128 rejected;
- relative displacements -128, 0, and 127, with -129 and 128 rejected;
- a relative base that wraps from `$FFFF+1` to `$0000`;
- word results -1 and 65,535, with 65,536 rejected;
- signed addends -128 and 127;
- **Measured: eight pending records** drained for one symbol; and
- symbols defined in reverse order, producing descending patch addresses in
  append order.

Every patch operation contains final replacement bytes. No operation contains
a name, symbol pointer, expression, or relocation request.

## Coverage

| Observation | Result |
| --- | ---: |
| Frozen AZM-supported forms parsed and emitted through the image sink | Measured 3,445 / 3,445 |
| Z80 instruction lengths | Measured 4 / 4 |
| Patch kinds | Measured 4 / 4 |
| Four-byte instruction sink-failure positions | Measured 4 / 4 |
| Proof-spool capacity boundaries | Measured 6 / 6 |
| Maximum proof pending drain | Measured 8 / 8 records |
| Claimed output banks | Measured 1 / 1, flat bank zero |

**Unsupported claimed instruction forms: Measured none.** The output layer
preserves the complete Phase 2e instruction claim. Banked output remains
outside the claim because the settled six-byte pending record has no bank
ordinal.

## Execution measurement

| Entry | Classification | Instructions | T-states | Measured case |
| --- | --- | ---: | ---: | --- |
| `AtomOutputReset` | Measured | 4 | 50 | flat output reset |
| `AtomOutputEmitInstruction` | Measured | 828 | 7,778 | four-byte instruction with two pending records |
| `AtomPendingPeek` | Measured | 136 | 1,683 | eighth pending record |
| `AtomOutputResolveSymbol` | Measured | 1,348 | 16,039 | drain eight word patches |

At 4 MHz, the measured eight-patch drain takes **Measured: about 4.01 ms**.
The named proof budgets retain margin above every measured maximum.

## Whole-assembler projection

Phase 2f replaces the former 800–1,200-byte output-layer projection with a
measured implementation. Remaining Atom-resident work is:

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Flat-manifest source-part iterator | Projected | 100–250 |
| Labels, equates, and required directives | Projected | 300–800 |
| Control, diagnostics, sink lifecycle, and final integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **1,400–2,550** |

Adding that range to **Measured: 10,269 bytes** gives a **Projected:
whole-assembler total of 11,669–12,819 bytes**, or **Projected: 11.4–12.5
KiB**. The margin below the **Target: 16 KiB bank** is **Projected:
3,565–4,715 bytes**. Operating-adapter code and storage remain platform
services, as they do in Nucleus.

## Reproduction

```sh
npm run annotate:contracts
npm test
npm run measure:output
```

These commands verify the frozen dependency identities, strict AZM contracts,
complete historical and Phase 2f proofs, exact memory account, and fresh
symbol-derived measurements.
