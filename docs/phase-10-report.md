# Atom Phase 10 alignment and byte functions

Atom now implements bare `ALIGN` and the case-insensitive `LOW()` and `HIGH()`
expression functions. The functions work with concrete expressions and with
one forward affine symbol where the output field has a fixed absolute byte
position. The host translator maps them to AZM's `LSB()` and `MSB()` spellings.

## Native cost

| Change | Classification | Bytes |
| --- | --- | ---: |
| Expression functions | Measured | 206 |
| Parser patch handling | Measured | 36 |
| Output resolution | Measured | 13 |
| `ALIGN` statement code and table data | Measured | 127 |
| **Code and table growth** | **Measured** | **382** |
| Fixed workspace growth | Measured | 0 |

The complete native account is:

| Item | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 13,261 |
| Fixed workspace | Measured | 551 |
| Linked resident extent | Measured | 13,812 |
| Code margin below 16 KiB | Measured | 3,123 |
| Physical margin below 16 KiB | Measured | 2,572 |

## Semantics and proof

`ALIGN BOUNDARY` requires a resolved positive word. It emits initialized zero
bytes up to the next address divisible by the boundary, accepts any positive
boundary rather than only powers of two, and emits nothing at an already
aligned address. The statement preflights complete output capacity before
emitting its first byte. D8 attributes every padding byte to the `ALIGN` source
line and classifies it as data.

`LOW(EXPRESSION)` selects bits 0–7 and `HIGH(EXPRESSION)` selects bits 8–15.
Concrete functions nest. A forward form may retain one symbol and a signed-byte
addend, but the function must remain the outermost operation. Forward byte
functions are rejected in `JR`, `DJNZ`, and IX/IY displacement fields because
the existing six-byte pending record cannot retain both the byte transform and
the required relative-range rule.

The pending-record size remains Measured 6 bytes. Two formerly unused values in
its three-bit patch-kind field now represent low-byte and high-byte resolution.
The differential suite compares concrete results with AZM, compares forward
instruction fields against AZM's `LSB()` and `MSB()` forms, checks exact data
patch bytes, and covers invalid nesting, range, delimiter, and capacity cases.

Self-hosting remains byte exact. The checked input is Measured 99,469 bytes
across six parts. The pinned core, translated AZM build, first Atom generation,
and second Atom generation agree across all Measured 13,812 resident bytes and
all Measured 13,436 initialized addresses. The first generation uses Measured
163,392,529 instructions and Measured 1,492,523,777 T-states.

The shared Debug80 checkout was observed read-only at
`codex/nucleus-docs-sync@13ee4e8861f996c7c4e9a9278979d3e19b447571`.
Atom's release certificate still requires its pinned Debug80 dependency at
`main@3f2adb669bb9e7888305c623f8c843054c3dd111`; no Debug80 state was changed.
