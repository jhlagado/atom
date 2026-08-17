# Symbolic instruction parser ABI

The authoritative `native/atom.asm` core enables expression operands, deferred
symbol keys, patch-field location, and driver diagnostic anchors. The concrete
and symbolic parser proofs both call this checked core. Historical Phase 2c and
Phase 2e reports retain measurements from the earlier mode-specific images.

## Parse result

`AtomParserParse` retains its ten-byte destination ABI. It accepts concrete
expressions wherever the completed value can be normalized to an encoder
operand class. A successful parse commits the record and sets
`AtomParserReferenceCount` to zero, one, or two.

A forward expression may contain one exact symbol plus a signed-byte addend.
The parser validates the complete instruction before inserting any missing
symbol record. It preflights all required records against the shared symbol
arena, including the case where two fields name the same missing symbol. A
failed form, expression, private-scope check, or capacity check leaves the
destination unchanged and publishes zero references.

Two references are required only by forms such as `LD (IX+D),N`, where both
the displacement and immediate may be forward expressions. Each public
nine-byte reference contains:

| Offset | Field |
| ---: | --- |
| 0–1 | Symbol-record pointer |
| 2 | Signed-byte expression addend |
| 3 | Parsed operand index, 0–2 |
| 4 | Patch kind |
| 5 | Byte offset from instruction start |
| 6 | Source-part ordinal |
| 7–8 | Source offset of the symbol |

The list is valid until the next `AtomParserParse` call. It contains no source
pointer or symbol spelling.

The source-part ordinal is 0 through 15. A forward reference carrying ordinal
16 or greater fails with `AtomParserStatusPartCapacity` before the destination,
reference list, or symbol arena changes.

The complete driver build marks the first reference that inserted an undefined
symbol as its diagnostic anchor. The low three bits of the kind field remain
the patch kind; bit 7 marks the anchor and bits 3–6 contain the source-part
ordinal. `AtomParserQueueReferences` copies that byte into the unchanged
six-byte pending record.

Forward references are accepted only when the operand class fixes a byte field
before the symbol value is known. `IM`, `RST`, and bit-number expressions
change opcode bits, so their forward forms are diagnosed as unpatchable.
Concrete expressions for those operands remain supported.

## Patch kinds

`AtomPatchLocate` accepts a validated ten-byte record in IX and an operand index
in A. Success returns the patch kind in A and the field's byte offset in B.

| Kind | Value | Resolution rule |
| --- | ---: | --- |
| Byte | 1 | Final value must fit 0–255 |
| Word | 2 | Store the final little-endian word |
| Relative | 3 | Subtract `patchAddress+1`; result must fit -128–127 |
| Displacement | 4 | Final value must fit -128–127 |
| Truncating byte | 5 | Store the low byte of the final signed or unsigned word; used by `DB`. |
| Low byte | 6 | Store bits 0–7 of the final word. |
| High byte | 7 | Store bits 8–15 of the final word. |

The low-byte and high-byte kinds retain an outer `LOW()` or `HIGH()` transform
without enlarging the six-byte pending record. They cannot be combined with a
relative or index-displacement patch rule.

`AtomParserQueueReferences` accepts the logical instruction output address in
DE. It preflights the complete pending-list requirement, converts each byte
offset to a logical patch address, and appends the existing six-byte pending
records. Failure from insufficient pending capacity appends nothing.

The Phase 2f build exposes the same preflight separately as
`AtomParserCheckReferences`. The output layer calls it before the first image
sink operation, then calls `AtomParserQueueReferences` after every instruction
byte succeeds. Historical Phase 2c and Phase 2e images retain the original
combined entry byte for byte.

Patch-byte construction and logical image/patch publication are specified in
[`output-abi.md`](output-abi.md). The operating adapter owns serialized NOBJ.
