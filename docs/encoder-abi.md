# Parsed-instruction encoder ABI

## Record

`IX` points at a ten-byte record:

| Offset | Field |
| ---: | --- |
| 0 | mnemonic ordinal |
| 1 | operand 0 class |
| 2 | operand 1 class |
| 3 | operand 2 class |
| 4–5 | operand 0 concrete value, little endian |
| 6–7 | operand 1 concrete value, little endian |
| 8–9 | operand 2 concrete value, little endian |

Registers, conditions, bit indices, interrupt modes, and restart vectors are
encoded in the operand class itself. Values are used only by immediate,
absolute, displacement, and relative operand classes.

## Entry points

`AtomRadix40Pack`

- Input: `HL` text, `B` length 1–8, `DE` six-byte destination.
- Success: carry clear, exactly three packed words written.
- Failure: carry set, destination unmodified.
- Accepts ASCII letters case-insensitively, digits, and underscore. Names are
  rejected rather than truncated.

`AtomRecognizeMnemonic`

- Input: `HL` text, `B` length.
- Success: carry clear, `A` mnemonic ordinal.
- Failure: carry set, `A=0`.

`AtomValidateForm` / `AtomFormLength`

- Input: `IX` parsed-instruction record; concrete values are ignored.
- Success: carry clear, `A` encoded length (1–4).
- Failure: carry set, `A=0`.

`AtomEncode`

- Input: `IX` parsed-instruction record, `DE` output cursor.
- Success: carry clear, `A` encoded length, `DE` advanced by that length, and
  exactly those bytes committed.
- Failure: carry set, `A=0`, `DE` unchanged, destination bytes unchanged.
- The routine is non-reentrant because it uses one four-byte scratch buffer.

Unless returned above, registers and flags are clobbered. The stack is balanced
on every return.

Phase 2e links the separate `atom-patch.asm` module after the encoder. Its
`AtomPatchLocate` entry maps a validated operand class to the fixed byte field
described in [`symbolic-parser-abi.md`](symbolic-parser-abi.md). Keeping the
locator separate preserves the measured Phase 1 encoder image.
