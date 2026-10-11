;=============================================================================
;  RADIX-40 names and mnemonic recognition
;=============================================================================
;
;  Pack case-insensitive names and recognise Z80 mnemonics. The packed values
;  feed symbol and mnemonic tables; recognition returns a compact ordinal.
;
;  Principal entries:
;    EN_R40PK  pack one name into three RADIX-40 words
;    EN_RECOG  recognise mnemonic text and return its ordinal
;    AT_DMNEM  dispatch an ordinal through a family address table
;
;  EN_TMP is six bytes because the packer needs three words. Later modules
;  reuse its first four bytes to stage an encoded instruction before commit.

    ORG  0                                          ; Start the standalone core at its relocatable base.

; Ten-byte parsed-instruction record shared with the parser and output layer.

EN_MNEM     EQU     0                               ; Record byte 0 holds the mnemonic ordinal.
EN_OP0      EQU     1                               ; Record byte 1 holds operand zero's class.
EN_OP1      EQU     2                               ; Record byte 2 holds operand one's class.
EN_OP2      EQU     3                               ; Record byte 3 holds operand two's class.
EN_VAL0     EQU     4                               ; Record bytes 4..5 hold operand zero's little-endian value.
EN_VAL1     EQU     6                               ; Record bytes 6..7 hold operand one's little-endian value.
EN_VAL2     EQU     8                               ; Record bytes 8..9 hold operand two's little-endian value.

; Operand-class ordinals. The register families deliberately mirror the Z80
; bit fields where possible: B..A are 0..7 and BC..SP are 8..11.

EN_B        EQU     0                               ; B occupies register field 0.
EN_C        EQU     1                               ; C occupies register field 1.
EN_D        EQU     2                               ; D occupies register field 2.
EN_E        EQU     3                               ; E occupies register field 3.
EN_H        EQU     4                               ; H occupies register field 4.
EN_L        EQU     5                               ; L occupies register field 5.
EN_MEMHL    EQU     6                               ; Indirect (HL) occupies register field 6.
EN_A        EQU     7                               ; A occupies register field 7.
EN_BC       EQU     8                               ; BC class has pair field 0 in its low two bits.
EN_DE       EQU     9                               ; DE class has pair field 1 in its low two bits.
EN_HL       EQU     10                              ; HL class has pair field 2 in its low two bits.
EN_SP       EQU     11                              ; SP class has pair field 3 in its low two bits.
EN_AF       EQU     15                              ; AF uses stack-pair field 3, distinct from SP.
EN_IX       EQU     16                              ; IX selects the DD-prefixed HL pair form.
EN_IY       EQU     17                              ; IY selects the FD-prefixed HL pair form.
EN_IXH      EQU     20                              ; IX high half reuses H field 4 behind DD.
EN_IXL      EQU     21                              ; IX low half reuses L field 5 behind DD.
EN_IYH      EQU     28                              ; IY high half reuses H field 4 behind FD.
EN_IYL      EQU     29                              ; IY low half reuses L field 5 behind FD.
EN_I        EQU     32                              ; Interrupt-vector register class for LD I,A and LD A,I.
EN_R        EQU     33                              ; Refresh register class for LD R,A and LD A,R.
EN_MEMBC    EQU     40                              ; Indirect (BC) class for accumulator transfers.
EN_MEMDE    EQU     41                              ; Indirect (DE) class for accumulator transfers.
EN_IIX      EQU     48                              ; Displacement-bearing (IX+d) memory class.
EN_IIY      EQU     49                              ; Displacement-bearing (IY+d) memory class.
EN_MABS     EQU     50                              ; Absolute (nn) memory class with a value word.
EN_IMM8     EQU     51                              ; Immediate byte class with its value in the low byte.
EN_IMM16    EQU     52                              ; Immediate word class with a little-endian value.
EN_PORTC    EQU     53                              ; Port (C) class, distinct from indirect memory.
EN_REL8     EQU     54                              ; Signed branch displacement class after next-PC subtraction.
EN_ZERO     EQU     55                              ; Literal zero class for the special OUT (C),0 form.
EN_MEMIX    EQU     56                              ; Undisplaced (IX) class for indirect JP.
EN_MEMIY    EQU     57                              ; Undisplaced (IY) class for indirect JP.
EN_MEMSP    EQU     58                              ; Stack-indirect (SP) class for EX.
EN_APRIM    EQU     59                              ; Alternate AF register class for EX AF,AF'.
EN_NZ       EQU     64                              ; Condition field 0 tests zero clear.
EN_Z        EQU     65                              ; Condition field 1 tests zero set.
EN_NC       EQU     66                              ; Condition field 2 tests carry clear.
EN_CC       EQU     67                              ; Condition field 3 tests carry set.
EN_PO       EQU     68                              ; Condition field 4 tests parity/overflow clear.
EN_PE       EQU     69                              ; Condition field 5 tests parity/overflow set.
EN_P        EQU     70                              ; Condition field 6 tests sign clear.
EN_M        EQU     71                              ; Condition field 7 tests sign set.
EN_BIT0     EQU     72                              ; First bit-number class, with bit 0 in the low three bits.
EN_BIT7     EQU     79                              ; Last bit-number class, with bit 7 in the low three bits.
EN_RST0     EQU     80                              ; First restart-vector class, selecting address zero.
EN_RST56    EQU     87                              ; Last restart-vector class, selecting address 56.
EN_IM0      EQU     88                              ; First interrupt-mode class, selecting mode zero.
EN_IM2      EQU     90                              ; Last interrupt-mode class, selecting mode two.
EN_NONE     EQU     255                             ; Empty operand slot sentinel outside every accepted class.

; Mnemonic ordinals are generated in compact-table order. Ordinals 1..34 are
; core singletons; 35..69 form the dispatched instruction families.

AT_MNOP     EQU     1                               ; First singleton ordinal and first compact mnemonic row.
AT_MRET     EQU     35                              ; First dispatched family ordinal, following the singletons.
AT_MEX      EQU     36                              ; Exchange family ordinal.
AT_MIM      EQU     37                              ; Interrupt-mode family ordinal.
AT_MRST     EQU     38                              ; Restart-vector family ordinal.
AT_MINC     EQU     39                              ; First INC/DEC ordinal.
AT_MDEC     EQU     40                              ; Last INC/DEC ordinal.
AT_MPUSH    EQU     41                              ; First stack-family ordinal.
AT_MPOP     EQU     42                              ; Last stack-family ordinal.
AT_MLD      EQU     43                              ; Load family ordinal.
AT_MIN      EQU     44                              ; Port input family ordinal.
AT_MOUT     EQU     45                              ; Port output family ordinal.
AT_MBIT     EQU     46                              ; First bit-operation ordinal.
AT_MRES     EQU     47                              ; Bit-reset ordinal within the bit family.
AT_MSET     EQU     48                              ; Last bit-operation ordinal.
AT_MRLC     EQU     49                              ; First rotate/shift ordinal.
AT_MSRL     EQU     57                              ; Last rotate/shift ordinal, after the SLS alias.
AT_MADD     EQU     58                              ; First arithmetic/logical ordinal.
AT_MADC     EQU     59                              ; Add-with-carry ordinal.
AT_MSUB     EQU     60                              ; Subtract ordinal.
AT_MSBC     EQU     61                              ; Subtract-with-carry ordinal.
AT_MAND     EQU     62                              ; Bitwise AND ordinal.
AT_MXOR     EQU     63                              ; Bitwise XOR ordinal.
AT_MOR      EQU     64                              ; Bitwise OR ordinal.
AT_MCP      EQU     65                              ; Last arithmetic/logical ordinal.
AT_MJP      EQU     66                              ; Absolute-jump family ordinal.
AT_MCALL    EQU     67                              ; Call family ordinal.
AT_MJR      EQU     68                              ; Relative-jump family ordinal.
AT_MDJNZ    EQU     69                              ; Counted relative-jump family ordinal.
AT_MLAST    EQU     AT_MDJNZ                        ; Inclusive upper bound for supported mnemonic ordinals.
EN_COREB: ; Begin the encoder code and immutable data range.
EN_CODEB: ; Begin executable encoder code.
EN_PKBEG: ; Begin RADIX-40 packing code.

;@ROUTINE IN B,HL,DE OUT DE,CARRY MAYBE-OUT ZERO CLOBBERS A,BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack B source characters at HL into the caller's six bytes at DE. Names
; are one to eight ASCII characters, without case distinction. Commit only
; after every character is proved representable.

EN_R40PK: ; Validate and pack a name into the caller's six-byte destination.
    LD   A,B                                        ; Copy the character count for the bounds checks.
    OR   A                                          ; Set Z only when the name is empty.
    JR   Z,.INVALID                                 ; Reject empty names before saving any state.
    CP   9                                          ; Compare with the maximum length plus one.
    JR   NC,.INVALID                                ; Reject names longer than eight characters.
    PUSH HL                                         ; Preserve the caller's source pointer.
    PUSH BC                                         ; Preserve the count and caller's C value.
.CHKLOOP: ; Validate every source character before writing the destination.
    LD   A,(HL)                                     ; Read the next name character for validation.
    CALL .CHARCODE                                  ; Convert it to a valid RADIX-40 code.
    JR   C,.CHKFAIL                                 ; Stop if a character is invalid.
    INC  HL                                         ; Advance to the next source character.
    DJNZ .CHKLOOP                                   ; Validate exactly the original B characters.
    POP  BC                                         ; Restore the original length and C register.
    POP  HL                                         ; Restore the source pointer for packing.
    PUSH DE                                         ; Save the caller's destination during packing.
    LD   IX,EN_TMP                                  ; Stage the three words in private scratch space.
    LD   A,B                                        ; Pass the full name length to the first group.

; Encode characters 0..2 and 3..5 as complete RADIX-40 words. The final call
; stores characters 6..7 directly as c6*40+c7 in the third word.

    CALL .PACK3                                     ; Pack characters zero through two.
    CALL .PACK3                                     ; Pack characters three through five.
    LD   B,A                                        ; Pass the remaining count to the third group.
    LD   C,2                                        ; Encode the final two RADIX-40 positions.
;@EXPECTOUT DE
    CALL .PACKWORD                                  ; Pack the last two characters with zero padding.
    LD   (IX+0),E                                   ; Stage the final word's low byte.
    LD   (IX+1),D                                   ; Stage the final word's high byte.
    POP  DE                                         ; Restore the caller's six-byte destination.
    LD   HL,EN_TMP                                  ; Point at the complete staged name.
    LD   BC,6                                       ; Copy all three packed words.
    LDIR                                            ; Publish only after the whole name is valid.
    OR   A                                          ; Clear carry to report successful packing.
    RET                                             ; Return with the destination fully written.
.CHKFAIL: ; Restore validation state after an invalid character.
    POP  BC                                         ; Restore the saved count after a failed scan.
    POP  HL                                         ; Restore the source pointer before returning.
.INVALID: ; Return carry set while leaving the destination untouched.
    XOR  A                                          ; Return a zero code for every invalid name.
    SCF                                             ; Set carry to report an invalid name.
    RET                                             ; Leave the caller's destination untouched.

;@ROUTINE IN A,HL,IX OUT A,HL,IX CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Consume up to three of the remaining A characters, write one word at IX and
; return the remaining count in A.

.PACK3: ; Pack a three-position group and return the remaining count.
    CP   3                                          ; Check for a full three-character group.
    JR   C,.SHORT3                                  ; Handle zero, one or two characters.
    LD   B,3                                        ; Consume exactly three real characters.
    SUB  3                                          ; Keep the count for the following group in A.
    JR   .READY3                                    ; Both paths now share the group encoder.
.SHORT3: ; Use all remaining characters and pad unused positions.
    LD   B,A                                        ; Consume every character that remains.
    XOR  A                                          ; Set the returned remaining count to zero.
.READY3: ; Encode this group with the remaining count saved on the stack.
    PUSH AF                                         ; Preserve the remaining count across packing.
    LD   C,3                                        ; This group has three base-40 positions.
;@EXPECTOUT DE
    CALL .PACKWORD                                  ; Return this group's packed value in DE.
    LD   (IX+0),E                                   ; Store the packed word's low byte.
    LD   (IX+1),D                                   ; Store the packed word's high byte.
    INC  IX                                         ; Advance to this word's high byte.
    INC  IX                                         ; Point at the next packed-word slot.
    POP  AF                                         ; Restore the number of characters still unused.
    RET                                             ; Return the remaining count for the next group.

;@ROUTINE IN BC,HL OUT DE,HL,CARRY MAYBE-OUT ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY,BC,ZERO
; Accumulate exactly C base-40 digits. B real characters are followed by zero
; padding, so each group has one canonical packed representation.

.PACKWORD: ; Accumulate the required base-40 positions into DE.
    LD   DE,0                                       ; Start this base-40 word at zero.
.WORDLOOP: ; Select a real character or a zero padding digit.
    LD   A,B                                        ; Check whether another real character remains.
    OR   A                                          ; Set Z when the group needs padding.
    JR   Z,.WORDPAD                                 ; Supply zero for unused positions at the end.
    LD   A,(HL)                                     ; Read the next source character.
    INC  HL                                         ; Advance the source pointer before conversion.
    DEC  B                                          ; Count the character consumed from this group.
    CALL .CHARCODE                                  ; Convert the source byte to its RADIX-40 code.
    JR   .ADDDIGIT                                  ; Append the digit to the accumulated word.
.WORDPAD: ; Supply the padding code after the real characters end.
    XOR  A                                          ; Zero is the canonical RADIX-40 padding digit.
.ADDDIGIT: ; Append the selected code to the base-40 accumulator.
    CALL .MULADD40                                  ; Replace DE with DE*40 plus this character code.
    DEC  C                                          ; Count down the positions in this packed word.
    JR   NZ,.WORDLOOP                               ; Continue until all positions are added.
    OR   A                                          ; Clear carry after the successful accumulation.
    RET                                             ; Return the packed word in DE.

;@ROUTINE IN DE,A OUT DE CLOBBERS A,F
; DE = DE*40 + A. Five doublings and one add avoid a general multiply.

.MULADD40: ; Calculate DE*40+A while preserving the source pointer.
    PUSH HL                                         ; Preserve the caller's source or table pointer.
    LD   H,D                                        ; Copy the 16-bit accumulator into HL.
    LD   L,E                                        ; HL now contains the prior RADIX-40 value.
    ADD  HL,HL                                      ; Double it to obtain 2 times the value.
    ADD  HL,HL                                      ; Double again to obtain 4 times the value.
    ADD  HL,DE                                      ; Add the original value to obtain 5 times it.
    ADD  HL,HL                                      ; Double to obtain 10 times the value.
    ADD  HL,HL                                      ; Double to obtain 20 times the value.
    ADD  HL,HL                                      ; Double to obtain 40 times the value.
    ADD  A,L                                        ; Add this character code into the low byte.
    LD   L,A                                        ; Retain the low byte of the new accumulator.
    JR   NC,.NOCARRY                                ; Skip the high-byte correction without carry.
    INC  H                                          ; Propagate the low-byte addition's carry into H.
.NOCARRY: ; Return the completed base-40 accumulator in DE.
    EX   DE,HL                                      ; Return the updated 16-bit value in DE.
    POP  HL                                         ; Restore the source or table pointer.
    RET                                             ; Finish one multiply-and-add step.

;@ROUTINE IN A OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Map A-Z/a-z to 1..26, digits to 27..36 and underscore to 37. Codes 38 and 39
; remain unused; zero is reserved for padding.

.CHARCODE: ; Fold ASCII case and map a valid name character to 1..37.
    CP   $61                                        ; Test whether the byte could be lowercase ASCII.
    JR   C,.UPPER                                   ; Bytes below 'a' need no case conversion.
    CP   $7A+1                                      ; Compare with the first byte after lowercase z.
    JR   NC,.UPPER                                  ; Bytes after 'z' also keep their original value.
    SUB  $20                                        ; Convert lowercase ASCII to its uppercase form.
.UPPER: ; Classify uppercase letters before digits and underscore.
    CP   $41                                        ; Test against uppercase ASCII A.
    JR   C,.DIGIT                                   ; Values below A cannot encode as letters.
    CP   $5A+1                                      ; Compare with the first byte after uppercase Z.
    JR   NC,.DIGIT                                  ; Values beyond Z continue to the digit test.
    SUB  $41-1                                      ; Map A..Z to the nonzero codes 1..26.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the packed letter value in A.
.DIGIT: ; Map ASCII digits to RADIX-40 codes 27..36.
    CP   $30                                        ; Test against ASCII digit zero.
    JR   C,.UNDERBAR                                ; Lower bytes cannot encode as digits.
    CP   $39+1                                      ; Compare with the first byte after digit nine.
    JR   NC,.UNDERBAR                               ; Higher bytes continue to the underscore test.
    SUB  $30-27                                     ; Map ASCII 0..9 to RADIX-40 codes 27..36.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the packed digit value in A.
.UNDERBAR: ; Accept underscore as the sole punctuation character.
    CP   $5F                                        ; Test the one supported punctuation character.
    JR   NZ,.BADCHAR                                ; Reject anything other than underscore.
    LD   A,37                                       ; Map underscore to the final assigned code.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the underscore value in A.
.BADCHAR: ; Return an invalid-character result with carry set.
    XOR  A                                          ; Set the invalid-character result to zero.
    SCF                                             ; Mark invalid input with carry set.
    RET                                             ; Return the character-classification failure.
EN_PKEND: ; End RADIX-40 packing code.
EN_RCBEG: ; Begin mnemonic recognition code.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Recognise a mnemonic of up to four characters. The table stores the first
; packed word and the high byte of the padded second word. Its row
; position plus one is the public mnemonic ordinal.

EN_RECOG: ; Match the packed name against three-byte mnemonic rows.
    LD   A,B                                        ; Check the text length before packing it.
    CP   5                                          ; Four characters is the longest mnemonic.
    JR   NC,.NOTFOUND                               ; Reject longer text without touching the table.
    LD   DE,EN_TMP                                  ; Use private scratch for the packed name.
    CALL EN_R40PK                                   ; Validate and pack the case-folded text.
    RET  C                                          ; Propagate an invalid length or character.
    LD   IX,EN_TABLE                                ; Point at the first three-byte mnemonic entry.
    LD   B,EN_CNT                                   ; Compare against every supported mnemonic.
    LD   C,1                                        ; Entry zero represents mnemonic ordinal one.
.LOOP: ; Compare all three distinguishing bytes in this mnemonic row.
    LD   A,(EN_TMP+0)                               ; Read the first packed word's low byte.
    CP   (IX+0)                                     ; Compare it with this table entry.
    JR   NZ,.NEXT                                   ; Skip the remaining comparisons on mismatch.
    LD   A,(EN_TMP+1)                               ; Read the first packed word's high byte.
    CP   (IX+1)                                     ; Compare the second byte of the packed name.
    JR   NZ,.NEXT                                   ; A mismatch rejects this candidate mnemonic.
    LD   A,(EN_TMP+3)                               ; Read the padded word's high byte.
    CP   (IX+2)                                     ; Compare its stored high byte with the entry.
    JR   NZ,.NEXT                                   ; Try the next mnemonic if this byte differs.
    LD   A,C                                        ; The table position is the mnemonic ordinal.
    OR   A                                          ; Clear carry to report a successful match.
    RET                                             ; Return the ordinal in A.
.NEXT: ; Advance IX by a row and C by an ordinal.
    INC  IX                                         ; Move from the low to high byte of the entry.
    INC  IX                                         ; Move to the entry's distinguishing byte.
    INC  IX                                         ; Advance to the next three-byte entry.
    INC  C                                          ; Keep the ordinal aligned with the table row.
    DJNZ .LOOP                                      ; Check the remaining mnemonic entries.
.NOTFOUND: ; Return ordinal zero and carry set for an unknown mnemonic.
    XOR  A                                          ; Return zero when no mnemonic matches.
    SCF                                             ; Set carry to mark an unknown mnemonic.
    RET                                             ; Return the unrecognised-name result.
EN_RCEND: ; End mnemonic recognition code.
EN_VCBEG: ; Begin mnemonic dispatch and form-validation code.

;@ROUTINE IN A,DE CLOBBERS B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Dispatch mnemonic A through a family table based at DE. Core ordinals 1..34
; share family zero. Later dense ordinal ranges are mapped by .FAMILIES to the
; RET, EX, IM, RST, INC/DEC, stack, LD, I/O, bit, rotate, ALU and branches.

AT_DMNEM: ; Select a handler from the table at DE using mnemonic A.
    LD   B,A                                        ; Preserve the mnemonic for the selected handler.
    CP   AT_MRET                                    ; Core ordinals all use family zero.
    JR   NC,.MAPPED                                 ; Later ordinals need a family-table lookup.
    XOR  A                                          ; Select entry zero for a core instruction.
    JR   .DISPATCH                                  ; Use the common address-table dispatch below.
.MAPPED: ; Convert a non-singleton ordinal to its family index.
    SUB  AT_MRET                                    ; Convert the ordinal to a zero-based offset.
    PUSH BC                                         ; Preserve the ordinal and caller's C register.
    LD   HL,.FAMILIES                               ; Point at exclusive ends of family ranges.
    LD   C,1                                        ; Begin at family one; core uses family zero.
.LOOP: ; Find the first exclusive family boundary above this offset.
    CP   (HL)                                       ; Compare against this family's exclusive end.
    JR   C,.FOUND                                   ; Select the first range containing the offset.
    INC  HL                                         ; Advance to the next family boundary.
    INC  C                                          ; Advance the corresponding family index.
    JR   .LOOP                                      ; Continue until a range contains the ordinal.
.FOUND: ; Retain the family index and restore the original mnemonic.
    LD   A,C                                        ; Use the matching family index for dispatch.
    POP  BC                                         ; Restore the original ordinal in B.
.DISPATCH: ; Load the family handler and tail-jump with the mnemonic in A.
    ADD  A,A                                        ; Convert the family index to a word offset.
    LD   L,A                                        ; Place the offset in the low byte of HL.
    LD   H,0                                        ; Form the offset with a zero high byte.
    ADD  HL,DE                                      ; Address the selected handler pointer.
    LD   E,(HL)                                     ; Load the handler address's low byte.
    INC  HL                                         ; Advance to the high byte of that address.
    LD   D,(HL)                                     ; Complete the 16-bit handler address in DE.
    EX   DE,HL                                      ; Put the handler address in the jump register.
    LD   A,B                                        ; Restore the mnemonic ordinal for the handler.
    JP   (HL)                                       ; Enter the selected family handler.
.FAMILIES: ; Exclusive cumulative ends for the non-singleton families.

; Exclusive cumulative family-end offsets from AT_MRET.

    DB   1,2,3,4,6,8,9,10,11,14,23,31,32,33,34,35   ; Family boundaries relative to AT_MRET, ending at DJNZ.
