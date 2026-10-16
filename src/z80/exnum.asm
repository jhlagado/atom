; Numeric helpers: signed magnitudes, multiplication, division and the
; expression diagnostics.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Copy both signed operands to magnitude workspace, record their signs and
; negate negative inputs. Product/quotient sign is left XOR right.

exAbs: ; Copy operand magnitudes and retain the signs separately.
    LD   HL,exLVal                      ; Point at the signed left operand.
    LD   DE,exLAbs                      ; Select its magnitude workspace.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Preserve the left operand before conversion.
    LD   HL,exRVal                      ; Point at the signed right operand.
    LD   DE,exRAbs                      ; Select its magnitude workspace.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Preserve the right operand before conversion.
    LD   A,(exLVal+2)                   ; Load the left sign byte.
    RLCA                                ; Rotate sign bit 7 into bit 0.
    AND  1                              ; Reduce it to a Boolean sign value.
    LD   (exLSign),A                    ; Preserve the dividend/left sign.
    OR   A                              ; Set NZ for a negative left operand.
    CALL NZ,exNegL                      ; Make copied left magnitude positive.
    LD   A,(exRVal+2)                   ; Load the right sign byte.
    RLCA                                ; Rotate sign bit 7 into bit 0.
    AND  1                              ; Reduce it to a Boolean sign value.
    LD   (exRSign),A                    ; Preserve the divisor/right sign.
    OR   A                              ; Set NZ for a negative right operand.
    CALL NZ,exNegR                      ; Make copied right magnitude positive.
    LD   A,(exLSign)                    ; Load the left sign Boolean.
    LD   HL,exRSign                     ; Address the right sign Boolean.
    XOR  (HL)                           ; Different signs require a negative result.
    LD   (exSign),A                     ; Preserve the product/quotient sign.
    OR   A                              ; Return carry clear with result sign in Z/NZ.
    RET                                 ; Leave both magnitude operands prepared.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the normal result slot in place.

exNeg: ; Negate the normal result record in place.
    LD   HL,exRVal                      ; Select the ordinary result value.
    JR   exNegHL                        ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the copied left magnitude in place.

exNegL: ; Negate the left magnitude copy in place.
    LD   HL,exLAbs                      ; Select the copied left magnitude.
    JR   exNegHL                        ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,A,BC,DE,IX,IY,SIGN,PARITY,HALFCARRY
; Negate copied right magnitude through the shared 24-bit body.

exNegR: ; Negate the right magnitude copy in place.
    LD   HL,exRAbs                      ; Select the copied right magnitude.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Form the two's complement of the little-endian 24-bit value at HL.

exNegHL: ; Complement three bytes and propagate the added one.
    LD   A,(HL)                         ; Load the low byte.
    CPL                                 ; Form its one's complement.
    ADD  A,1                            ; Add the two's-complement increment.
    LD   (HL),A                         ; Store the negated low byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(HL)                         ; Load the middle byte.
    CPL                                 ; Complement without changing carry.
    ADC  A,0                            ; Propagate the increment carry.
    LD   (HL),A                         ; Store the negated middle byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(HL)                         ; Load the high byte.
    CPL                                 ; Complement without changing carry.
    ADC  A,0                            ; Complete the 24-bit two's complement.
    LD   (HL),A                         ; Store the negated high byte.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the negated value in place.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A
; Complement all three bytes of exRVal for unary '~'.

exNot: ; Invert every bit of the normal result record.
    LD   HL,exRVal                      ; Point at the result low byte.
    LD   A,(HL)                         ; Load the low byte.
    CPL                                 ; Invert every bit.
    LD   (HL),A                         ; Store the complemented low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(HL)                         ; Load the middle byte.
    CPL                                 ; Invert every bit.
    LD   (HL),A                         ; Store the complemented middle byte.
    INC  HL                             ; Advance to the high byte.
    LD   A,(HL)                         ; Load the high byte.
    CPL                                 ; Invert every bit.
    LD   (HL),A                         ; Store the complemented high byte.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the complemented value in exRVal.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Add exLAbs to the 24-bit product accumulator. Carry reports unsigned
; overflow beyond the high byte.

exAddUp: ; Add a magnitude to the product and return overflow in carry.
    LD   HL,exAccum                     ; Point at the product accumulator low byte.
    LD   A,(exLAbs)                     ; Load the multiplicand low byte.
    ADD  A,(HL)                         ; Add the accumulator low byte.
    LD   (HL),A                         ; Store the new low product byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(exLAbs+1)                   ; Load the multiplicand middle byte.
    ADC  A,(HL)                         ; Add accumulator middle byte and carry.
    LD   (HL),A                         ; Store the new middle product byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(exLAbs+2)                   ; Load the multiplicand high byte.
    ADC  A,(HL)                         ; Add accumulator high byte and carry.
    LD   (HL),A                         ; Store the new high product byte.
    RET                                 ; Return carry as overflow beyond bit 23.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift the multiplication multiplicand left by one bit.

exDouble: ; Advance the multiplicand to its next binary place.
    LD   HL,exLAbs                      ; Select the multiplicand magnitude.
    JP   exSla24                        ; Tail-call one 24-bit left shift.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift unsigned multiplier right. SRL clears the high sign bit, and the
; shared tail rotates carry through the low sixteen bits.

exHalve: ; Consume a multiplier bit with a logical right shift.
    LD   HL,exRAbs+2                    ; Point at the multiplier high byte.
    LD   A,(HL)                         ; Load it for an unsigned shift.
    SRL  A                              ; Shift in zero and expose bit 0 in carry.

;@ROUTINE IN A,HL OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the already-shifted high byte in A, then rotate the two lower bytes at
; HL-1 and HL-2 through carry. Arithmetic right shift enters here too.

exSrl16: ; Propagate a shifted high byte through the lower two bytes.
    LD   (HL),A                         ; Store the shifted high byte.
    DEC  HL                             ; Move to middle byte; keep carry.
    LD   A,(HL)                         ; Load the middle byte.
    RR   A                              ; Shift through the high byte's outgoing bit.
    LD   (HL),A                         ; Store the shifted middle byte.
    DEC  HL                             ; Move to the low byte without changing carry.
    LD   A,(HL)                         ; Load the low byte.
    RR   A                              ; Complete the 24-bit right shift.
    LD   (HL),A                         ; Store the shifted low byte.
    RET                                 ; Return flags from the final low-byte rotation.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Compare remainder and divisor as unsigned 24-bit magnitudes,
; most-significant byte first. Carry means remainder is smaller.

exIsLess: ; Compare unsigned remainder and divisor from high byte to low.
    LD   A,(exAccum+2)                  ; Load the remainder high byte.
    LD   HL,exRAbs+2                    ; Point at the divisor high byte.
    CP   (HL)                           ; Compare the most-significant bytes.
    RET  NZ                             ; Their order decides unless they are equal.
    LD   A,(exAccum+1)                  ; Load the remainder middle byte.
    DEC  HL                             ; Point at the divisor middle byte.
    CP   (HL)                           ; Compare the next-significant bytes.
    RET  NZ                             ; Their order decides unless they are equal.
    LD   A,(exAccum)                    ; Load the remainder low byte.
    DEC  HL                             ; Point at the divisor low byte.
    CP   (HL)                           ; Complete the unsigned 24-bit comparison.
    RET                                 ; Carry means remainder is smaller.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY
; Subtract the divisor magnitude from the partial remainder in place.

exSubDiv: ; Subtract the divisor from the current partial remainder.
    LD   HL,exAccum                     ; Point at the remainder low byte.
    LD   DE,exRAbs                      ; Point at the divisor low byte.
    LD   A,(DE)                         ; Load the divisor low byte.
    LD   C,A                            ; Save it for subtraction from memory.
    LD   A,(HL)                         ; Load the remainder low byte.
    SUB  C                              ; Subtract without incoming borrow.
    LD   (HL),A                         ; Store the new remainder low byte.
    INC  HL                             ; Advance without changing borrow.
    INC  DE                             ; Advance the divisor pointer likewise.
    LD   A,(DE)                         ; Load the divisor middle byte.
    LD   C,A                            ; Preserve it for subtraction.
    LD   A,(HL)                         ; Load the remainder middle byte.
    SBC  A,C                            ; Subtract with low-byte borrow.
    LD   (HL),A                         ; Store the new remainder middle byte.
    INC  HL                             ; Advance without changing borrow.
    INC  DE                             ; Advance the divisor pointer likewise.
    LD   A,(DE)                         ; Load the divisor high byte.
    LD   C,A                            ; Preserve it for subtraction.
    LD   A,(HL)                         ; Load the remainder high byte.
    SBC  A,C                            ; Complete the 24-bit subtraction.
    LD   (HL),A                         ; Store the new remainder high byte.
    RET                                 ; Return final subtraction flags.

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY
; Expand the resolved word in HL into exRVal and clear both the 24-bit high
; byte and the deferred-state marker.

exStore: ; Zero-extend HL and mark the working result concrete.
    LD   (exRVal),HL                    ; Store the resolved low sixteen bits.
    XOR  A                              ; Form zero for high byte and resolution state.
    LD   (exRVal+2),A                   ; Zero-extend the word to 24 bits.
    LD   (exRForm),A                    ; Mark the result concrete.
    RET                                 ; Return carry clear from XOR.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL
; Require a resolved result in the final word domain. Positive values may
; reach $00FFFF; negative values must be sign-extended from $FF8000..$FFFFFF.

exWordOk: ; Accept the final -32768..65535 word domain.
    LD   A,(exRVal+2)                   ; Load the 24-bit result's extension byte.
    OR   A                              ; Is it zero for a non-negative word?
    RET  Z                              ; Yes: $000000..$00FFFF is valid.
    INC  A                              ; Does $FF wrap to zero?
    JR   NZ,.bad                        ; Other extensions are outside the word domain.
    LD   A,(exRVal+1)                   ; Inspect a negative result's middle byte.
    BIT  7,A                            ; Is bit 15 set for proper sign extension?
    RET  NZ                             ; Yes: $FF8000..$FFFFFF is valid.
.bad: ; Report a final result outside the word domain.
    LD   A,exValErr                     ; Select final word-range failure.
    JR   exAtTok                        ; Anchor it at the current delimiter token.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require a deferred addend sign-extended from one byte:
; $000000..$00007F or $FFFF80..$FFFFFF.

exByteOk: ; Accept only a sign-extended -128..127 deferred addend.
    LD   A,(exRVal+2)                   ; Load the deferred addend extension byte.
    OR   A                              ; Zero selects the non-negative range check.
    JR   Z,.positive                    ; Validate $00 in both upper bytes.
    INC  A                              ; Does the extension equal $FF?
    JR   NZ,exRange                     ; No: it cannot be an eight-bit sign extension.
    LD   A,(exRVal+1)                   ; Load the middle addend byte.
    INC  A                              ; Does it also equal $FF?
    JR   NZ,exRange                     ; No: reject outside the signed-byte domain.
    LD   A,(exRVal)                     ; Load the candidate negative low byte.
    BIT  7,A                            ; Is it $80..$FF?
    RET  NZ                             ; Yes: the addend is correctly sign-extended.
    JR   exRange                        ; Reject $FFFF00..$FFFF7F.
.positive: ; Validate the non-negative deferred-addend range.
    LD   A,(exRVal+1)                   ; Load the non-negative addend middle byte.
    OR   A                              ; Must it be zero?
    JR   NZ,exRange                     ; Nonzero exceeds the signed-byte range.
    LD   A,(exRVal)                     ; Load the candidate positive low byte.
    BIT  7,A                            ; Is it $80 or above?
    JR   NZ,exRange                     ; Yes: it is not a positive signed byte.
    OR   A                              ; Clear carry while preserving the addend byte.
    RET                                 ; Accept $00..$7F.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Advance the tokenizer. A lexical failure carries the tokenizer's own source
; position rather than the expression's current operator or token position.

exNext: ; Advance the tokenizer or retain its exact lexical failure.
    CALL tkNext                         ; Ask the tokenizer to publish the next record.
    RET  NC                             ; Return it unchanged on lexical success.
    LD   A,exLexErr                     ; Select the expression lexical category.
    JR   exAtLex                        ; Use the tokenizer's exact failure position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Report a numeric range error at the operator whose calculation failed.

exRange: ; Report numeric range failure at the saved operator.
    LD   A,exValErr                     ; Select arithmetic/range failure.
    JR   exAtOper                       ; Anchor it at the saved operator position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token's stored source position for primary, delimiter and
; capacity failures.

exAtTok: ; Select the current token as the diagnostic anchor.
    LD   HL,tkRecord+tkPartAt           ; Point at current token part and offset fields.
    JR   exFail                         ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use saved operator position for arithmetic or form errors.

exAtOper: ; Select the saved operator as the diagnostic anchor.
    LD   HL,exOpPart                    ; Point at saved operator part and offset fields.
    JR   exFail                         ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the saved name position for symbol packing and lookup failures.

exAtSym: ; Select the saved symbol name as the diagnostic anchor.
    LD   HL,exIdPart                    ; Point at the current name's part and offset.
    JR   exFail                         ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the tokenizer's recorded position for lexical errors.

exAtLex: ; Select the tokenizer failure as the diagnostic anchor.
    LD   HL,tkErrPos                    ; Point at tokenizer failure location.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy the contiguous part-and-offset triple at HL into the public expression
; error fields, preserve the status in A and set carry.

exFail: ; Publish a part/offset diagnostic while retaining status A.
    PUSH BC                             ; Preserve caller BC across the three-byte copy.
    PUSH DE                             ; Preserve caller DE likewise.
    LD   DE,exErrPos                    ; Select the public expression error destination.
    LD   BC,3                           ; Copy one part byte and one offset word.
    LDIR                                ; Publish the exact selected source position.
    POP  DE                             ; Restore caller DE.
    POP  BC                             ; Restore caller BC.
    SCF                                 ; Fail while retaining status A.
    RET                                 ; Return category and positioned diagnostic.
exRuleHi: ; End the expression rule-code measurement range.
exEnd: ; End expression code and immutable tables.
