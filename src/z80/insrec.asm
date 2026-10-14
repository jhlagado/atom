; The parsed-instruction record and its operand classes. The parser fills
; the record, form validation checks it and the encoder turns it into bytes.

; Ten-byte parsed-instruction record shared with the parser and output layer.

enMnem      EQU     0                               ; Record byte 0 holds the mnemonic ordinal.
enOp0       EQU     1                               ; Record byte 1 holds operand zero's class.
enOp1       EQU     2                               ; Record byte 2 holds operand one's class.
enOp2       EQU     3                               ; Record byte 3 holds operand two's class.
enVal0      EQU     4                               ; Record bytes 4..5 hold operand zero's little-endian value.
enVal1      EQU     6                               ; Record bytes 6..7 hold operand one's little-endian value.
enVal2      EQU     8                               ; Record bytes 8..9 hold operand two's little-endian value.

; Operand-class ordinals. The register families deliberately mirror the Z80
; bit fields where possible: B..A are 0..7 and BC..SP are 8..11.

enRegB      EQU     0                               ; B occupies register field 0.
enRegC      EQU     1                               ; C occupies register field 1.
enRegD      EQU     2                               ; D occupies register field 2.
enRegE      EQU     3                               ; E occupies register field 3.
enRegH      EQU     4                               ; H occupies register field 4.
enRegL      EQU     5                               ; L occupies register field 5.
enMemHL     EQU     6                               ; Indirect (HL) occupies register field 6.
enRegA      EQU     7                               ; A occupies register field 7.
enRegBC     EQU     8                               ; BC class has pair field 0 in its low two bits.
enRegDE     EQU     9                               ; DE class has pair field 1 in its low two bits.
enRegHL     EQU     10                              ; HL class has pair field 2 in its low two bits.
enRegSP     EQU     11                              ; SP class has pair field 3 in its low two bits.
enRegAF     EQU     15                              ; AF uses stack-pair field 3, distinct from SP.
enRegIX     EQU     16                              ; IX selects the DD-prefixed HL pair form.
enRegIY     EQU     17                              ; IY selects the FD-prefixed HL pair form.
enRegIXH    EQU     20                              ; IX high half reuses H field 4 behind DD.
enRegIXL    EQU     21                              ; IX low half reuses L field 5 behind DD.
enRegIYH    EQU     28                              ; IY high half reuses H field 4 behind FD.
enRegIYL    EQU     29                              ; IY low half reuses L field 5 behind FD.
enRegI      EQU     32                              ; Interrupt-vector register class for LD I,A and LD A,I.
enRegR      EQU     33                              ; Refresh register class for LD R,A and LD A,R.
enMemBC     EQU     40                              ; Indirect (BC) class for accumulator transfers.
enMemDE     EQU     41                              ; Indirect (DE) class for accumulator transfers.
enDispIX    EQU     48                              ; Displacement-bearing (IX+d) memory class.
enDispIY    EQU     49                              ; Displacement-bearing (IY+d) memory class.
enMemAbs    EQU     50                              ; Absolute (nn) memory class with a value word.
enImm8      EQU     51                              ; Immediate byte class with its value in the low byte.
enImm16     EQU     52                              ; Immediate word class with a little-endian value.
enPortC     EQU     53                              ; Port (C) class, distinct from indirect memory.
enRel8      EQU     54                              ; Signed branch displacement class after next-PC subtraction.
enZero      EQU     55                              ; Literal zero class for the special OUT (C),0 form.
enMemIX     EQU     56                              ; Undisplaced (IX) class for indirect JP.
enMemIY     EQU     57                              ; Undisplaced (IY) class for indirect JP.
enMemSP     EQU     58                              ; Stack-indirect (SP) class for EX.
enAltAF     EQU     59                              ; Alternate AF register class for EX AF,AF'.
enCondNZ    EQU     64                              ; Condition field 0 tests zero clear.
enCondZ     EQU     65                              ; Condition field 1 tests zero set.
enCondNC    EQU     66                              ; Condition field 2 tests carry clear.
enCondC     EQU     67                              ; Condition field 3 tests carry set.
enCondPO    EQU     68                              ; Condition field 4 tests parity/overflow clear.
enCondPE    EQU     69                              ; Condition field 5 tests parity/overflow set.
enCondP     EQU     70                              ; Condition field 6 tests sign clear.
enCondM     EQU     71                              ; Condition field 7 tests sign set.
enBit0      EQU     72                              ; First bit-number class, with bit 0 in the low three bits.
enBit7      EQU     79                              ; Last bit-number class, with bit 7 in the low three bits.
enRst0      EQU     80                              ; First restart-vector class, selecting address zero.
enRst56     EQU     87                              ; Last restart-vector class, selecting address 56.
enIm0       EQU     88                              ; First interrupt-mode class, selecting mode zero.
enIm2       EQU     90                              ; Last interrupt-mode class, selecting mode two.
enNone      EQU     255                             ; Empty operand slot sentinel outside every accepted class.

; Reference and record geometry. The build form contains a packed key. The
; public form uses a symbol-record pointer and omits build-only data.

prRefCap    EQU     2                   ; At most two independently deferred fields per instruction.
prRawLen    EQU     13                  ; Bytes in a private reference with its packed symbol key.
prPubLen    EQU     9                   ; Bytes in a public reference with its symbol-record pointer.
prBKey      EQU     0                   ; Packed six-byte key begins the private reference.
prBAdd      EQU     6                   ; Signed addend byte within the private reference.
prBOper     EQU     7                   ; Operand index byte within the private reference.
prBKind     EQU     8                   ; Transform kind byte within the private reference.
prBField    EQU     9                   ; Encoded field offset byte within the private reference.
prBPart     EQU     10                  ; Diagnostic source-part byte within the private reference.
prBSrc      EQU     11                  ; Diagnostic source-offset word within the private reference.
prRSym      EQU     0                   ; Symbol pointer word begins the public reference.
prRAdd      EQU     2                   ; Signed addend byte within the public reference.
prROper     EQU     3                   ; Operand index byte within the public reference.
prRKind     EQU     4                   ; Final patch-kind byte within the public reference.
prRField    EQU     5                   ; Encoded field offset byte within the public reference.
prRPart     EQU     6                   ; Diagnostic source-part byte within the public reference.
prRSrc      EQU     7                   ; Diagnostic source-offset word within the public reference.
