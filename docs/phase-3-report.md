# Atom Phase 3 native-driver report

## Result

**Measured: pass.** Atom now performs complete native multipart assembly from a
validated memory descriptor. It resets all build state, assembles as many as 16
ordered parts, resolves forward image patches across part boundaries, checks
the final private scope and every unresolved symbol, and commits or aborts one
operating-adapter generation.

Undefined global and private symbols return their packed name and exact
zero-based source part and byte offset. The implementation retains the settled
eight-byte symbol and six-byte pending records. A diagnostic anchor occupies
unused high bits of one pending patch-kind byte; the undefined symbol's unused
value word temporarily holds the source offset.

Strict AZM register contracts pass for the linked Phase 3 image. Runtime proofs
check exact return PC and SP, two-sided canaries, immutable code and source,
descriptor preservation, complete-address-space writes, descriptor boundaries,
cross-part private scope, pending-list hole filling, undefined metadata,
injected begin/image/patch/commit failures, and exact abort counts. The full
repository suite contains **Measured: 211 passing tests**.

## Resident byte account

Phase 2g measured 11,705 code/data bytes and 541 fixed workspace bytes. Phase 3
adds 779 code/data bytes and nine workspace bytes.

| Phase 3 increment | Classification | Code/data bytes |
| --- | --- | ---: |
| Diagnostic metadata in symbol, parser, output, and statement paths | Measured | 124 |
| Descriptor validation, multipart loop, finalization, and lifecycle driver | Measured | 655 |
| **Phase 3 increment** | **Measured** | **779** |

| Resident component | Classification | Bytes |
| --- | --- | ---: |
| Encoder, validation, RADIX-40, and mnemonic recognition | Measured | 3,997 |
| Symbol and pending-reference core | Measured | 874 |
| Streaming tokenizer | Measured | 1,174 |
| Expression evaluator | Measured | 1,929 |
| Patch-field locator | Measured | 73 |
| Symbolic instruction parser | Measured | 2,126 |
| Nucleus-model output and resolver | Measured | 490 |
| Statement layer | Measured | 1,166 |
| Multipart driver and finalizer | Measured | 655 |
| **Integrated code and immutable data** | **Measured** | **12,484** |
| **Integrated fixed workspace** | **Measured** | **550** |

The measured code margin below 16 KiB is **Measured: 3,900 bytes**. The build
descriptor and complete 16-part descriptor array occupy 15 and 80 caller-owned
bytes. Source, symbol records, pending records, sink spools, and stack remain
outside fixed workspace and retain their separately reported capacities.

## Lifecycle and failure evidence

The driver validates all descriptors before begin. Zero and 17 parts, wrapped
descriptor arithmetic, a wrong ordinal, reversed source or arena bounds, and a
wrapped target extent all fail with no sink call. One and 16 parts pass.

A successful build calls begin and commit once and never calls abort. Begin
failure calls neither commit nor abort. Source, output, final undefined, and
commit failures call abort once. Accepted image or patch operations may remain
in the proof spool before abort, but no failed generation receives commit.

The exact undefined-position proof includes part 15, a current-scope private
name, and a pending anchor moved by hole filling. Corrupt or missing anchor
metadata produces the internal status rather than an ordinary undefined-symbol
diagnostic.

## Execution measurements

The 16-part descriptor validator executes in **Measured: 489 instructions and
4,374 T-states**. Final scanning of an exactly full 32-record proof symbol arena
executes in **Measured: 354 instructions and 4,116 T-states**. The complete
32-definition driver case executes in **Measured: 98,940 instructions and
980,298 T-states**, about **Measured: 245.1 ms at 4 MHz**. These are named proof
cases rather than source-size-independent worst-case bounds.

## Remaining resident projection

The native assembly path is complete through exact structured diagnostics and
generation closure. Remaining one-bank work consists of deployment support:

| Remaining resident component | Classification | Bytes |
| --- | --- | ---: |
| TEC-1 diagnostic text and RADIX-40 unpacking | Projected | 200–500 |
| Target initialization and self-assembly glue | Projected | 200–400 |
| **Remaining subtotal** | **Projected** | **400–900** |

Adding that range to **Measured: 12,484 bytes** gives a **Projected:
whole native total of 12,884–13,384 bytes**, with **Projected: 3,000–3,500
bytes** below the 16 KiB limit. Mac preprocessing, filesystem access, SP1
parsing, NOBJ serialization, binary/HEX/listing/D8 rendering, and atomic
artifact publication remain host or operating-adapter services.

## Reproduction

```sh
npm run annotate:contracts
npm test
npm run measure:statements
npm run measure:driver
```

The commands verify the frozen Debug80/AZM dependency identity, historical
Phase 2g byte stability, strict contracts, the Phase 3 memory profile,
multipart runtime paths, and fresh symbol-derived measurements.
