;==============================================================================
;  RADIX-40 names and mnemonic recognition
;==============================================================================
;
;  Pack case-insensitive names and recognise Z80 mnemonics. The packed values
;  feed the symbol and mnemonic tables; the recogniser returns a compact ordinal.
;
;  Principal entries:
;    EN_R40PK  pack one name into three RADIX-40 words
;    EN_RECOG  recognise mnemonic text and return its ordinal
;    AT_DMNEM  dispatch an ordinal through a family address table
;
;  EN_SCRAT is six bytes because the packer needs three words. Later modules
;  reuse its first four bytes to stage an encoded instruction before commit.

    ORG 0

; Ten-byte parsed-instruction record shared with the parser and output layer.

EN_MNEM EQU 0
EN_OP0 EQU 1
EN_OP1 EQU 2
EN_OP2 EQU 3
EN_VAL0 EQU 4
EN_VAL1 EQU 6
EN_VAL2 EQU 8

; Operand-class ordinals. The register families deliberately mirror the Z80
; bit fields where possible: B..A are 0..7 and BC..SP are 8..11.

EN_B EQU 0
EN_C EQU 1
EN_D EQU 2
EN_E EQU 3
EN_H EQU 4
EN_L EQU 5
EN_MEMHL EQU 6
EN_A EQU 7
EN_BC EQU 8
EN_DE EQU 9
EN_HL EQU 10
EN_SP EQU 11
EN_AF EQU 15
EN_IX EQU 16
EN_IY EQU 17
EN_IXH EQU 20
EN_IXL EQU 21
EN_IYH EQU 28
EN_IYL EQU 29
EN_I EQU 32
EN_R EQU 33
EN_MEMBC EQU 40
EN_MEMDE EQU 41
EN_IIX EQU 48
EN_IIY EQU 49
EN_MABS EQU 50
EN_IMM8 EQU 51
EN_IMM16 EQU 52
EN_PORTC EQU 53
EN_REL8 EQU 54
EN_ZERO EQU 55
EN_MEMIX EQU 56
EN_MEMIY EQU 57
EN_MEMSP EQU 58
EN_APRIM EQU 59
EN_NZ EQU 64
EN_Z EQU 65
EN_NC EQU 66
EN_CC EQU 67
EN_PO EQU 68
EN_PE EQU 69
EN_P EQU 70
EN_M EQU 71
EN_BIT0 EQU 72
EN_BIT7 EQU 79
EN_RST0 EQU 80
EN_RST56 EQU 87
EN_IM0 EQU 88
EN_IM2 EQU 90
EN_NONE EQU 255

; Mnemonic ordinals are generated in compact-table order. Ordinals 1..34 are
; singleton core instructions; 35..69 form the dispatched instruction families.

AT_MNOP EQU 1
AT_MRET EQU 35
AT_MEX EQU 36
AT_MIM EQU 37
AT_MRST EQU 38
AT_MINC EQU 39
AT_MDEC EQU 40
AT_MPUSH EQU 41
AT_MPOP EQU 42
AT_MLD EQU 43
AT_MIN EQU 44
AT_MOUT EQU 45
AT_MBIT EQU 46
AT_MRES EQU 47
AT_MSET EQU 48
AT_MRLC EQU 49
AT_MSRL EQU 57
AT_MADD EQU 58
AT_MADC EQU 59
AT_MSUB EQU 60
AT_MSBC EQU 61
AT_MAND EQU 62
AT_MXOR EQU 63
AT_MOR EQU 64
AT_MCP EQU 65
AT_MJP EQU 66
AT_MCALL EQU 67
AT_MJR EQU 68
AT_MDJNZ EQU 69
AT_MLAST EQU AT_MDJNZ
EN_COREB:
EN_CODEB:
EN_R4CBE:

;@ROUTINE IN B,HL,DE OUT DE,CARRY MAYBE-OUT ZERO CLOBBERS A,BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack B source characters at HL into the caller's six bytes at DE. Names are
; one to eight characters, ASCII case-insensitive, and are committed only after
; every character is proved representable.

EN_R40PK:
    LD   A,B                 ; Copy the character count for the bounds checks.
    OR   A                   ; Set Z only when the name is empty.
    JR   Z,.PINVALID         ; Reject empty names before saving any state.
    CP   9                   ; Compare with the maximum length plus one.
    JR   NC,.PINVALID        ; Reject names longer than eight characters.
    PUSH HL                  ; Preserve the caller's source pointer.
    PUSH BC                  ; Preserve the count and caller's C value.
.PVLOOP:
    LD   A,(HL)              ; Read the next name character for validation.
    CALL EN_R40CH            ; Convert it to a valid RADIX-40 code.
    JR   C,.PVFAILED         ; Stop if a character is invalid.
    INC  HL                  ; Advance to the next source character.
    DJNZ .PVLOOP             ; Validate exactly the original B characters.
    POP  BC                  ; Restore the original length and C register.
    POP  HL                  ; Restore the source pointer for packing.
    PUSH DE                  ; Save the caller's destination during packing.
    LD   IX,EN_SCRAT         ; Stage the three words in private scratch space.
    LD   A,B                 ; Pass the full name length to the first group.

; Encode characters 0..2 and 3..5 as complete RADIX-40 words. The final call
; stores characters 6..7 directly as c6*40+c7 in the third word.

    CALL EN_PTHRE            ; Pack characters zero through two.
    CALL EN_PTHRE            ; Pack characters three through five.
    LD   B,A                 ; Pass the remaining count to the third group.
    LD   C,2                 ; Encode the final two RADIX-40 positions.
;@EXPECTOUT DE
    CALL EN_PGROU            ; Pack the last two characters with zero padding.
    LD   (IX+0),E            ; Stage the final word's low byte.
    LD   (IX+1),D            ; Stage the final word's high byte.
    POP  DE                  ; Restore the caller's six-byte destination.
    LD   HL,EN_SCRAT          ; Point at the complete staged name.
    LD   BC,6                ; Copy all three packed words.
    LDIR                     ; Publish only after the whole name is valid.
    OR   A                   ; Clear carry to report successful packing.
    RET                      ; Return with the destination fully written.
.PVFAILED:
    POP  BC                  ; Restore the saved count after a failed scan.
    POP  HL                  ; Restore the source pointer before returning.
.PINVALID:
    XOR  A                   ; Return a zero code for every invalid name.
    SCF                      ; Set carry to report an invalid name.
    RET                      ; Leave the caller's destination untouched.

;@ROUTINE IN A,HL,IX OUT A,HL,IX CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Consume up to three of the remaining A characters, write one word at IX and
; return the remaining count in A.

EN_PTHRE:
    CP   3                   ; Check for a full three-character group.
    JR   C,.PTSHORT          ; Handle zero, one or two characters.
    LD   B,3                 ; Consume exactly three real characters.
    SUB  3                   ; Keep the count for the following group in A.
    JR   .PTREADY            ; Both paths now share the group encoder.
.PTSHORT:
    LD   B,A                 ; Consume every character that remains.
    XOR  A                   ; Set the returned remaining count to zero.
.PTREADY:
    PUSH AF                  ; Preserve the remaining count across packing.
    LD   C,3                 ; This group has three base-40 positions.
;@EXPECTOUT DE
    CALL EN_PGROU            ; Return this group's packed value in DE.
    LD   (IX+0),E            ; Store the packed word's low byte.
    LD   (IX+1),D            ; Store the packed word's high byte.
    INC  IX                  ; Advance to this word's high byte.
    INC  IX                  ; Point at the next packed-word slot.
    POP  AF                  ; Restore the number of characters still unused.
    RET                      ; Return the remaining count for the next group.

;@ROUTINE IN BC,HL OUT DE,HL,CARRY MAYBE-OUT ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY,BC,ZERO
; Accumulate exactly C base-40 digits. B real characters are followed by zero
; padding, so each group has one canonical packed representation.

EN_PGROU:
    LD   DE,0                 ; Start this base-40 word at zero.
.PGLOOP:
    LD   A,B                 ; Check whether another real character remains.
    OR   A                   ; Set Z when the group needs padding.
    JR   Z,.PGPADDIN         ; Supply zero for unused positions at the end.
    LD   A,(HL)              ; Read the next source character.
    INC  HL                  ; Advance the source pointer before conversion.
    DEC  B                   ; Count the character consumed from this group.
    CALL EN_R40CH            ; Convert the source byte to its RADIX-40 code.
    JR   .PGAPPEND           ; Append the digit to the accumulated word.
.PGPADDIN:
    XOR  A                   ; Zero is the canonical RADIX-40 padding digit.
.PGAPPEND:
    CALL AT_MA40             ; Replace DE with DE*40 plus this character code.
    DEC  C                   ; Count down the positions in this packed word.
    JR   NZ,.PGLOOP          ; Continue until all positions are added.
    OR   A                   ; Clear carry after the successful accumulation.
    RET                      ; Return the packed word in DE.

;@ROUTINE IN DE,A OUT DE CLOBBERS A,F
; DE = DE*40 + A. Five doublings and one add are smaller than a general multiply.

AT_MA40:
    PUSH HL                  ; Preserve the caller's source or table pointer.
    LD   H,D                 ; Copy the 16-bit accumulator into HL.
    LD   L,E                 ; HL now contains the prior RADIX-40 value.
    ADD  HL,HL               ; Double it to obtain 2 times the value.
    ADD  HL,HL               ; Double again to obtain 4 times the value.
    ADD  HL,DE               ; Add the original value to obtain 5 times it.
    ADD  HL,HL               ; Double to obtain 10 times the value.
    ADD  HL,HL               ; Double to obtain 20 times the value.
    ADD  HL,HL               ; Double to obtain 40 times the value.
    ADD  A,L                 ; Add this character code into the low byte.
    LD   L,A                 ; Retain the low byte of the new accumulator.
    JR   NC,.MA4NCARR        ; Skip the high-byte correction without carry.
    INC  H                   ; Propagate the low-byte addition's carry into H.
.MA4NCARR:
    EX   DE,HL               ; Return the updated 16-bit value in DE.
    POP  HL                  ; Restore the source or table pointer.
    RET                      ; Finish one multiply-and-add step.

;@ROUTINE IN A OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Map A-Z/a-z to 1..26, digits to 27..36 and underscore to 37. Codes 38 and 39
; remain unused; zero is reserved for padding.

EN_R40CH:
    CP   $61                 ; Test whether the byte could be lowercase ASCII.
    JR   C,.R4UPPER          ; Bytes below 'a' need no case conversion.
    CP   $7A+1               ; Compare with the first byte after lowercase z.
    JR   NC,.R4UPPER         ; Bytes after 'z' also keep their original value.
    SUB  $20                 ; Convert lowercase ASCII to its uppercase form.
.R4UPPER:
    CP   $41                 ; Test against uppercase ASCII A.
    JR   C,.R4DIGIT          ; Values below A cannot encode as letters.
    CP   $5A+1               ; Compare with the first byte after uppercase Z.
    JR   NC,.R4DIGIT         ; Values beyond Z continue to the digit test.
    SUB  $41-1               ; Map A..Z to the nonzero codes 1..26.
    OR   A                   ; Clear carry to report a valid character code.
    RET                      ; Return the packed letter value in A.
.R4DIGIT:
    CP   $30                 ; Test against ASCII digit zero.
    JR   C,.R4UNDERS         ; Lower bytes cannot encode as digits.
    CP   $39+1               ; Compare with the first byte after digit nine.
    JR   NC,.R4UNDERS        ; Higher bytes continue to the underscore test.
    SUB  $30-27              ; Map ASCII 0..9 to RADIX-40 codes 27..36.
    OR   A                   ; Clear carry to report a valid character code.
    RET                      ; Return the packed digit value in A.
.R4UNDERS:
    CP   $5F                 ; Test the one supported punctuation character.
    JR   NZ,.R4BAD           ; Reject anything other than underscore.
    LD   A,37                ; Map underscore to the final assigned code.
    OR   A                   ; Clear carry to report a valid character code.
    RET                      ; Return the underscore value in A.
.R4BAD:
    XOR  A                   ; Set the invalid-character result to zero.
    SCF                      ; Mark invalid input with carry set.
    RET                      ; Return the character-classification failure.
EN_R4CEN:
EN_RCBEG:

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Recognise a one-to-four-character mnemonic. The compact table stores the first
; packed word and the significant high byte of the padded second word. Its table
; position plus one is the public mnemonic ordinal.

EN_RECOG:
    LD   A,B                 ; Check the text length before packing it.
    CP   5                   ; Four characters is the longest mnemonic.
    JR   NC,.RNFOUND         ; Reject longer text without touching the table.
    LD   DE,EN_SCRAT         ; Use private scratch for the packed name.
    CALL EN_R40PK            ; Validate and pack the case-folded text.
    RET  C                   ; Propagate an invalid length or character.
    LD   IX,EN_TABLE         ; Point at the first three-byte mnemonic entry.
    LD   B,EN_CNT            ; Compare against every supported mnemonic.
    LD   C,1                 ; Entry zero represents mnemonic ordinal one.
.RLOOP:
    LD   A,(EN_SCRAT+0)     ; Read the first packed word's low byte.
    CP   (IX+0)              ; Compare it with this table entry.
    JR   NZ,.RNEXT           ; Skip the remaining comparisons on mismatch.
    LD   A,(EN_SCRAT+1)     ; Read the first packed word's high byte.
    CP   (IX+1)              ; Compare the second byte of the packed name.
    JR   NZ,.RNEXT           ; A mismatch rejects this candidate mnemonic.
    LD   A,(EN_SCRAT+3)     ; Read the padded word's high byte.
    CP   (IX+2)              ; Compare its stored high byte with the entry.
    JR   NZ,.RNEXT           ; Try the next mnemonic if this byte differs.
    LD   A,C                 ; The table position is the mnemonic ordinal.
    OR   A                   ; Clear carry to report a successful match.
    RET                      ; Return the ordinal in A.
.RNEXT:
    INC  IX                  ; Move from the low to high byte of the entry.
    INC  IX                  ; Move to the entry's distinguishing byte.
    INC  IX                  ; Advance to the next three-byte entry.
    INC  C                   ; Keep the ordinal aligned with the table row.
    DJNZ .RLOOP              ; Check the remaining mnemonic entries.
.RNFOUND:
    XOR  A                   ; Return zero when no mnemonic matches.
    SCF                      ; Set carry to mark an unknown mnemonic.
    RET                      ; Return the unrecognised-name result.
EN_RCEND:
EN_VCBEG:

;@ROUTINE IN A,DE CLOBBERS B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Dispatch mnemonic A through a family table based at DE. Core ordinals 1..34
; share family zero. Later dense ordinal ranges are mapped by EN_CENDS to the
; RET, EX, IM, RST, INC/DEC, stack, LD, I/O, bit, rotate, ALU and branch families.

AT_DMNEM:
    LD   B,A                 ; Preserve the mnemonic for the selected handler.
    CP   AT_MRET             ; Core ordinals all use family zero.
    JR   NC,.DMAPPED         ; Later ordinals need a family-table lookup.
    XOR  A                   ; Select entry zero for a core instruction.
    JR   .DREADY             ; Use the common address-table dispatch below.
.DMAPPED:
    SUB  AT_MRET             ; Convert the ordinal to a zero-based offset.
    PUSH BC                  ; Preserve the ordinal and caller's C register.
    LD   HL,EN_CENDS         ; Point at exclusive ends of family ranges.
    LD   C,1                 ; Begin at family one; core uses family zero.
.DCLOOP:
    CP   (HL)                ; Compare against this family's exclusive end.
    JR   C,.DCREADY          ; Select the first range containing the offset.
    INC  HL                  ; Advance to the next family boundary.
    INC  C                   ; Advance the corresponding family index.
    JR   .DCLOOP             ; Continue until a range contains the ordinal.
.DCREADY:
    LD   A,C                 ; Use the matching family index for dispatch.
    POP  BC                  ; Restore the original ordinal in B.
.DREADY:
    ADD  A,A                 ; Convert the family index to a word offset.
    LD   L,A                 ; Place the offset in the low byte of HL.
    LD   H,0                 ; Form the offset with a zero high byte.
    ADD  HL,DE               ; Address the selected handler pointer.
    LD   E,(HL)              ; Load the handler address's low byte.
    INC  HL                  ; Advance to the high byte of that address.
    LD   D,(HL)              ; Complete the 16-bit handler address in DE.
    EX   DE,HL                ; Put the handler address in the jump register.
    LD   A,B                 ; Restore the mnemonic ordinal for the handler.
    JP   (HL)                ; Enter the selected family handler.
EN_CENDS:

; Exclusive cumulative family-end offsets from AT_MRET.

    DB 1,2,3,4,6,8,9,10,11,14,23,31,32,33,34,35
