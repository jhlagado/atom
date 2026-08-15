# Symbolic instruction parser ABI

Phase 2e assembles `atom-parser.asm` with `AtomParserExpressionMode=1` and
assembles `atom-expression.asm` with `AtomExpressionDeferredMode=1`. The Phase
2c and Phase 2d proof images set their respective flags to zero, which preserves
their measured concrete and standalone images byte for byte.

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

Two references are required only by forms such as `LD (IX+d),n`, where both
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
