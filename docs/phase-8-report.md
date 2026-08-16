# Atom Phase 8 source-syntax checkpoint

## Result

**Measured: pass.** Atom now uses bare assembler directives and dot-prefixed
private symbols. `EQU`, `ORG`, `DB`, `DW`, and `DS` are the only native
directive spellings. `.NAME` is private to the nearest preceding global label;
`_NAME` is an ordinary global name. Source remains case-insensitive, while the
shipped examples and documentation use uppercase assembly consistently.

The private prefix is syntax rather than payload. Atom removes the leading dot
before RADIX-40 packing and records privacy in the existing flag bit, so a
private name still has eight significant characters and an eight-byte symbol
record. The change therefore adds no symbol RAM.

## Native account

Removing the obsolete dotted-directive token path reduced the native image by
**Measured: 45 bytes**.

| Native account | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 12,508 |
| Fixed workspace | Measured | 550 |
| Linked resident extent | Measured | 13,058 |
| Physical margin below 16 KiB | Measured | 3,326 |

## Correctness evidence

The tokenizer proves exact limits for eight-character globals and dot plus
eight-character private names. Symbol tests prove that `_GLOBAL` is global,
private scope is unchanged, and overlength names fail atomically. Statement
tests prove that dotted directive-looking words are private identifiers rather
than directive aliases. Host artifact tests preserve dot-local D8 identities,
and Atom-to-AZM translation rewrites bare directives while retaining private
labels.

The checked self-host source contains **Measured: 7,127 statements** in five
generated parts totalling **Measured: 93,760 bytes**. With its entry part, the
native boundary receives **Measured: 93,933 bytes across six parts**. The proof
compares the first Atom generation, second Atom generation, pinned AZM core,
and translated AZM build across all **Measured: 13,058 resident bytes** and all
**Measured: 12,682 initialized addresses**; every comparison is identical.

Both Atom generations execute **Measured: 148,925,343 instructions** and
**Measured: 1,360,961,063 T-states**, with **Measured: 14,809 host service
calls**. AZM strict register contracts and the complete memory, stack, canary,
and read-only-source proofs remain enabled.

## Reproduction

```sh
npm run verify:example
npm run release:check
npm pack --dry-run
```

The dry-run package census is frozen only after every packaged document and
asset is final.
