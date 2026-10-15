# Atom's records

Atom's stages hand each other small fixed-size records. A token goes from the
tokenizer to the parser, an instruction record from the parser to the encoder,
and a reference from the parser to the symbol table, to wait for a symbol that
has not been defined yet. Learning these records is most of the way to
understanding how Atom works, because each stage is the code that fills one
record or reads another.

This page lists every record with its layout, then follows one small program
through all of them. The tables, the worked example and the figures are
generated from the source and from a trace of the real assembler, and a test
fails if any of them drift.

## How the records connect

1. The **build descriptor** tells the driver where the source parts, the symbol
   and pending arenas and the output range are.
2. The tokenizer reads source bytes and publishes one **token record** at a
   time.
3. Names are packed into RADIX-40 words. Each name the source uses gets a
   **symbol record**, created the first time the name appears, whether it is
   defined there or only used.
4. The parser turns an instruction's tokens into an **instruction record**. An
   operand that names a symbol not yet defined also produces a **build
   reference**, which becomes a **public reference** once the symbol has a
   record.
5. The encoder turns the instruction record into bytes, which the output layer
   emits. Each public reference then becomes a **pending record**, which says
   which bytes to patch and how.
6. When the symbol is defined, the output layer finds its pending records,
   works out the final bytes and submits a patch.

## Record layouts

<!-- generated:layouts -->
### Token record

9 bytes in tkRecord. Written by the tokenizer (tkNext). Read by the statement layer, expressions and the parser.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 1 | kind (`tkKindAt`) | Token kind: name, number, punctuation, end of line |
| 1 | 1 | part (`tkPartAt`) | Source part the token came from |
| 2 | 2 | offset (`tkOffAt`) | Byte offset of the token in its part |
| 4 | 2 | lexeme (`tkLexAt`) | Address of the token's text in the lexeme buffer |
| 6 | 1 | length (`tkLenAt`) | Length of that text in bytes |
| 7 | 2 | value (`tkValAt`) | A number's value |

### Symbol record

8 bytes in the symbol arena. Written by the symbol table (syRef, syDecl, syLabel). Read by expressions, the output layer and the driver.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 6 | name (`syKeyLen`) | Three RADIX-40 words. The top bits of byte 5 are flags: private $80, defined $40, signed $20 |
| 6 | 2 | value (`syValLo`) | The value once defined. Until then, where the name was first used |

### Instruction record

10 bytes in prRec, then the caller's destination. Written by the parser (prCommit). Read by form validation and the encoder.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 1 | mnemonic (`enMnem`) | Mnemonic number from mnemonic.asm |
| 1 | 1 | operand 0 (`enOp0`) | Class of the first operand |
| 2 | 1 | operand 1 (`enOp1`) | Class of the second operand |
| 3 | 1 | operand 2 (`enOp2`) | Class of the third operand, or enNone |
| 4 | 2 | value 0 (`enVal0`) | First operand's value |
| 6 | 2 | value 1 (`enVal1`) | Second operand's value |
| 8 | 2 | value 2 (`enVal2`) | Third operand's value |

### Build reference

13 bytes in prRawRef. Written by the parser, for an operand naming a later symbol. Read by refBind.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 6 | key (`prBKey`) | The symbol's packed name |
| 6 | 1 | addend (`prBAdd`) | Signed amount added to the symbol |
| 7 | 1 | operand (`prBOper`) | Which operand refers to the symbol |
| 8 | 1 | kind (`prBKind`) | How to patch: byte, word, relative, LOW or HIGH |
| 9 | 1 | field (`prBField`) | Offset of the patched bytes in the instruction |
| 10 | 1 | part (`prBPart`) | Source part of the reference |
| 11 | 2 | source (`prBSrc`) | Source offset of the reference |

### Public reference

9 bytes in prPubRef. Written by refBind, once the symbol has a record. Read by refCheck and refQueue.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 2 | symbol (`prRSym`) | Address of the symbol's record |
| 2 | 1 | addend (`prRAdd`) | Signed amount added to the symbol |
| 3 | 1 | operand (`prROper`) | Which operand refers to the symbol |
| 4 | 1 | kind (`prRKind`) | How to patch, with the anchor flag $80 |
| 5 | 1 | field (`prRField`) | Offset of the patched bytes in the instruction |
| 6 | 1 | part (`prRPart`) | Source part of the reference |
| 7 | 2 | source (`prRSrc`) | Source offset of the reference |

### Pending record

9 bytes in the pending arena. Written by refQueue, through syAdd. Read by outFixUp, when the symbol is defined.

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 2 | symbol | Address of the symbol's record |
| 2 | 2 | address | Address of the bytes to patch |
| 4 | 1 | kind | How to patch, in the low three bits. $80 marks the anchor |
| 5 | 1 | addend | Signed amount added to the symbol |
| 6 | 1 | part (`syPart`) | Source part of the reference |
| 7 | 2 | source (`sySrcOff`) | Source offset of the reference |

### Build descriptor

15 bytes in the host's memory, passed in IX. Written by the host. Read by the driver (drAsm).

| Offset | Size | Field | Meaning |
| ---: | ---: | --- | --- |
| 0 | 1 | parts (`drCount`) | Number of source parts |
| 1 | 2 | part table (`drParts`) | Address of the five-byte part records |
| 3 | 2 | symbols (`drSymBeg`) | Start of the symbol arena |
| 5 | 2 | symbols end (`drSymEnd`) | End of the symbol arena |
| 7 | 2 | pending (`drRefBeg`) | Start of the pending arena |
| 9 | 2 | pending end (`drRefEnd`) | End of the pending arena |
| 11 | 2 | origin (`drOutBeg`) | First output address |
| 13 | 2 | capacity (`drOutCap`) | Output capacity in bytes |
<!-- end:layouts -->

## One program through every record

The example has one forward reference, `COUNT`, used before it is defined, and
one backward jump.

![The token record for $100](images/records/records-token.svg)

The number `$100` is a token of kind 4. Its value is already decoded, stored
low byte first like every word on the Z80.

![LD A,(COUNT) as an instruction record and its public reference](images/records/records-instruction.svg)

`COUNT` is not defined when line 2 is parsed, so its operand's value is a
placeholder of zero. The public reference beside it records which symbol to
wait for and which bytes of the instruction to patch.

![The pending record waiting for COUNT](images/records/records-pending.svg)

Once the instruction's bytes are emitted, the reference becomes a pending
record holding the absolute address of the placeholder.

![COUNT's address patched into the output](images/records/records-patch.svg)

When line 4 defines `COUNT`, the output layer finds that pending record,
computes `$0105` and patches it into the two placeholder bytes.

![The symbol record for COUNT](images/records/records-symbol.svg)

At the end, `COUNT`'s symbol record holds its name and value. Its record was
created at line 2, when the name was first used, so it follows `START` in the
symbol table even though it was defined last.

The complete trace:

<!-- generated:trace -->
```asm
        ORG $100
START:  LD A,(COUNT)
        JR START
COUNT:  DB 5
```

**Tokens.** Each line becomes a run of tokens ending in an end of line.

| Line | Kind | Text |
| ---: | --- | --- |
| 1 | `tkName` | `ORG` |
| 1 | `tkNum` | $100 = $0100 |
| 1 | `tkEol` | end of line |
| 2 | `tkName` | `START` |
| 2 | `tkColon` | `:` |
| 2 | `tkName` | `LD` |
| 2 | `tkName` | `A` |
| 2 | `tkComma` | `,` |
| 2 | `tkLParen` | `(` |
| 2 | `tkName` | `COUNT` |
| 2 | `tkRParen` | `)` |
| 2 | `tkEol` | end of line |
| 3 | `tkName` | `JR` |
| 3 | `tkName` | `START` |
| 3 | `tkEol` | end of line |
| 4 | `tkName` | `COUNT` |
| 4 | `tkColon` | `:` |
| 4 | `tkName` | `DB` |
| 4 | `tkNum` | 5 = $0005 |
| 4 | `tkEol` | end of line |

**Instruction records.** The parser commits one per instruction.

| Line | Bytes | Mnemonic | Operands | References |
| ---: | --- | --- | --- | ---: |
| 2 | `2B 07 32 FF 00 00 00 00 1F 00` | `mneLd` | `enRegA`, `enMemAbs`, `enNone` | 1 |
| 3 | `44 36 FF FF FB FF 06 00 31 00` | `mneJr` | `enRel8`, `enNone`, `enNone` | 0 |

**Public reference** for `LD A,(COUNT)`: `08 41 00 01 82 01 00 1F 00`.

**Definitions.** Each label resolves the pending records for its symbol.

| Line | Symbol record | Pending records |
| ---: | --- | --- |
| 2 | $4100 | none |
| 4 | $4108 | `08 41 01 01 82 00 00 1F 00` |

**Output.** IMAGE operations emit bytes as each line is assembled, and PATCH operations fill in later.

| Operation | Address | Bytes | Line |
| --- | --- | --- | ---: |
| IMAGE | $0100 | 3A | 2 |
| IMAGE | $0101 | 00 | 2 |
| IMAGE | $0102 | 00 | 2 |
| IMAGE | $0103 | 18 | 3 |
| IMAGE | $0104 | FB | 3 |
| IMAGE | $0105 | 05 | 4 |
| PATCH | $0101 | 05 01 | 4 |

**Symbols** at the end, in table order.

| Record | Bytes | Name | Value |
| --- | --- | --- | --- |
| $4100 | `E1 79 A0 73 00 40 00 01` | START | $0100 |
| $4108 | `2D 15 A0 5A 00 40 05 01` | COUNT | $0105 |
<!-- end:trace -->

## Keeping this page true

`node scripts/generate-records-doc.mjs` regenerates the tables, the trace and
the figures. It checks every field offset against the `EQU` that defines it in
`src/z80`, and takes every byte shown from the assembler's memory while it
assembles the example. `npm test` runs it with `--check`, so a change to a
record that is not reflected here fails the build.
