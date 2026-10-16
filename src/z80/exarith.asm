;==========================================================================
;  Expression arithmetic
;==========================================================================
;
;  Signed 24-bit addition, subtraction, multiplication and division.
;  Results replace the right operand in exRVal.
;
;@ROUTINE OUT A,BC,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Save both sign bytes for overflow checks, load the left low byte, and point
; HL at the right/result record for the bytewise operation.

exSetup: ; Load operand signs and prepare bytewise result access.
    LD   A,(exLVal+2)                   ; Load the left operand's sign/high byte.
    LD   B,A                            ; Preserve it for overflow detection.
    LD   A,(exRVal+2)                   ; Load the right operand's sign/high byte.
    LD   C,A                            ; Preserve it for overflow detection.
    LD   A,(exLVal)                     ; Start arithmetic with the left low byte.
    LD   HL,exRVal                      ; Point at the in-place right/result record.
    RET                                 ; Return signs, low byte and result pointer.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Add signed 24-bit operands into exRVal. Equal-sign inputs may overflow only
; if the result sign changes; mixed-sign inputs cannot overflow.

exAdd: ; Add signed 24-bit operands and check the result sign.
    CALL exSetup                        ; Load low byte, both signs and result pointer.
    ADD  A,(HL)                         ; Add the right low byte without incoming carry.
    LD   (HL),A                         ; Store the result low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(exLVal+1)                   ; Load the left middle byte.
    ADC  A,(HL)                         ; Add right middle byte plus low-byte carry.
    LD   (HL),A                         ; Store the result middle byte.
    INC  HL                             ; Advance to the high/sign byte.
    LD   A,B                            ; Reload the left high byte.
    ADC  A,(HL)                         ; Add right high byte plus middle-byte carry.
    LD   (HL),A                         ; Store the result high byte.
    LD   D,A                            ; Save result sign for overflow test.
    LD   A,B                            ; Compare input signs first.
    XOR  C                              ; Bit 7 shows differing input signs.
    BIT  7,A                            ; Can signed addition overflow?
    JR   NZ,exOk                        ; Different signs cannot overflow.
    LD   A,B                            ; Compare the common input sign with the result.
    XOR  D                              ; Bit 7 set means the result sign changed.
    BIT  7,A                            ; Did sum cross the signed limit?
    JP   NZ,exRange                     ; Yes: report range at the saved operator.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Shared arithmetic success tail clears carry and returns exFinal in A.

exOk: ; Return concrete success with carry clear.
    XOR  A                              ; Return exFinal and clear carry.
    RET                                 ; Complete arithmetic successfully.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO,IX,IY
; Subtract exRVal from exLVal into exRVal. Opposite-sign inputs may
; overflow only if the result sign differs from the left operand.

exSub: ; Subtract right from left and check signed overflow.
    CALL exSetup                        ; Load low byte, both signs and result pointer.
    SUB  (HL)                           ; Subtract the right low byte.
    LD   (HL),A                         ; Store the result low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(exLVal+1)                   ; Load the left middle byte.
    SBC  A,(HL)                         ; Subtract middle byte and borrow.
    LD   (HL),A                         ; Store the result middle byte.
    INC  HL                             ; Advance to the high/sign byte.
    LD   A,B                            ; Reload the left high byte.
    SBC  A,(HL)                         ; Subtract high byte and borrow.
    LD   (HL),A                         ; Store the result high byte.
    LD   D,A                            ; Save result sign for overflow test.
    LD   A,B                            ; Compare the two input signs.
    XOR  C                              ; Bit 7 set means their signs differed.
    BIT  7,A                            ; Can signed subtraction overflow?
    JR   Z,exOk                         ; Equal-sign subtraction cannot overflow.
    LD   A,B                            ; Compare the left sign with the result sign.
    XOR  D                              ; Bit 7 set means subtraction crossed the limit.
    BIT  7,A                            ; Did the result change from the left sign?
    JP   NZ,exRange                     ; Yes: report range at the saved operator.
    JR   exOk                           ; Otherwise return resolved success.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise AND to all three bytes of the 24-bit working values.

exAnd: ; Combine corresponding bytes with bitwise AND.
    LD   HL,exRVal                      ; Point at the right/result low byte.
    LD   DE,exLVal                      ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.loop: ; Combine one corresponding operand byte with AND.
    LD   A,(DE)                         ; Load one left operand byte.
    AND  (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .loop                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in exRVal.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise XOR to all three bytes of the 24-bit working values.

exXor: ; Combine corresponding bytes with bitwise XOR.
    LD   HL,exRVal                      ; Point at the right/result low byte.
    LD   DE,exLVal                      ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.loop: ; Combine one corresponding operand byte with XOR.
    LD   A,(DE)                         ; Load one left operand byte.
    XOR  (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .loop                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in exRVal.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise OR to all three bytes of the 24-bit working values.

exOr: ; Combine corresponding bytes with bitwise OR.
    LD   HL,exRVal                      ; Point at the right/result low byte.
    LD   DE,exLVal                      ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.loop: ; Combine one corresponding operand byte with OR.
    LD   A,(DE)                         ; Load one left operand byte.
    OR   (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .loop                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in exRVal.

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Shift the little-endian 24-bit value at HL left by one bit. Carry propagates
; from low to high byte and reports the bit discarded from the sign byte.

exSla24: ; Shift three bytes left and return the discarded top bit in carry.
    LD   A,(HL)                         ; Load the low byte.
    SLA  A                              ; Shift left and place bit 7 in carry.
    LD   (HL),A                         ; Store the shifted low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(HL)                         ; Load the middle byte.
    RL   A                              ; Shift left through the low-byte carry.
    LD   (HL),A                         ; Store the shifted middle byte.
    INC  HL                             ; Advance to the high/sign byte.
    LD   A,(HL)                         ; Load the high byte.
    RL   A                              ; Shift through carry and expose bit 23.
    LD   (HL),A                         ; Store the shifted high byte.
    RET                                 ; Return final carry and high byte in A.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Validate the right operand as a count from 0 through 23, then shift the left
; operand repeatedly. Any sign change reports signed 24-bit overflow.

exShl: ; Check the count and reject a sign change during left shift.
    CALL exShCnt                        ; Validate count in 0..23.
    RET  C                              ; Preserve range failure at the shift operator.
    LD   B,A                            ; Keep the repeat count in B.
    OR   A                              ; Is this a zero-bit shift?
    JR   Z,.copy                        ; Yes: copy the left operand unchanged.
.loop: ; Shift one bit and reject a changed sign.

; C retains the sign byte before the shift so XOR detects a changed sign bit.

    LD   A,(exLVal+2)                   ; Load the sign byte before this shift.
    LD   C,A                            ; Preserve its sign bit.
    LD   HL,exLVal                      ; Shift the left operand in place.
    CALL exSla24                        ; Perform one complete 24-bit left shift.
    XOR  C                              ; Compare old and new sign bits.
    BIT  7,A                            ; Did this step change the signed result's sign?
    JP   NZ,exRange                     ; Yes: report signed 24-bit overflow.
    DJNZ .loop                          ; Shift the remaining requested bits.
.copy: ; Copy shifted operand to result.

; Binary reducers publish through exRVal, so copy the shifted left
; operand there even when the count was zero.

    LD   HL,exLVal                      ; Point at the shifted left operand.
    LD   DE,exRVal                      ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the full 24-bit working value.
    LDIR                                ; Publish it as the reduction result.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave exRVal ready for the value stack.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Copy the left operand to exRVal, then perform an arithmetic right shift for
; each requested bit. SRA preserves the 24-bit sign in the high byte and RR
; propagates it through the lower sixteen bits.

exShr: ; Copy the left value and propagate its sign through right shifts.
    CALL exShCnt                        ; Validate count in 0..23.
    RET  C                              ; Preserve range failure at the shift operator.
    LD   B,A                            ; Preserve the requested count.
    PUSH BC                             ; Save it across the fixed-size copy.
    LD   HL,exLVal                      ; Point at the source left operand.
    LD   DE,exRVal                      ; Select the result slot.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Initialise the in-place shifted result.
    POP  BC                             ; Restore the requested count in B.
    LD   A,B                            ; Test whether any shifting is required.
    OR   A                              ; Z identifies a zero-bit shift.
    JP   Z,exOk                         ; Return the unchanged copied value.
    LD   B,A                            ; Restore B as the loop counter.
.loop: ; Shift the result right by one requested bit.
    LD   HL,exRVal+2                    ; Point at the result high/sign byte.
    LD   A,(HL)                         ; Load it for an arithmetic shift.
    SRA  A                              ; Preserve bit 7 and expose bit 0 in carry.
    CALL exSrl16                        ; Store it and rotate carry through lower bytes.
    DJNZ .loop                          ; Repeat for each requested bit.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the shifted value in exRVal.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept only a nonnegative count below 24. Any nonzero upper
; byte or low byte of 24 and above is a range error at the operator position.

exShCnt: ; Require a concrete shift count within 0..23.
    LD   A,(exRVal+2)                   ; Read the count's high/sign byte.
    OR   A                              ; Must it be zero?
    JP   NZ,exRange                     ; Nonzero makes the count negative or too large.
    LD   A,(exRVal+1)                   ; Read the count's middle byte.
    OR   A                              ; Must it also be zero?
    JP   NZ,exRange                     ; Nonzero is at least 256 and invalid.
    LD   A,(exRVal)                     ; Load the remaining low-byte count.
    CP   24                             ; Is it within the 24-bit value width?
    JP   NC,exRange                     ; Reject 24 and every larger count.
    OR   A                              ; Clear carry while preserving count A.
    RET                                 ; Return the validated count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Multiply signed 24-bit operands by shift and add. Magnitudes make
; the loop unsigned; exSign records whether the final result must be negated.

exMul: ; Accumulate magnitude products from multiplier bits.
    CALL exAbs                          ; Copy magnitudes and signs.
    XOR  A                              ; Form a zero product accumulator.
    LD   (exAccum),A                    ; Clear its low byte.
    LD   (exAccum+1),A                  ; Clear its middle byte.
    LD   (exAccum+2),A                  ; Clear its high byte.
    LD   A,24                           ; Bound multiplication to the working width.
    LD   (exRndCnt),A                   ; Initialise the defensive iteration counter.
.loop: ; Process one multiplier bit.

; Add the multiplicand when the multiplier's low bit is set. Carry from
; the 24-bit accumulator is an overflow.

    LD   A,(exRAbs)                     ; Load the multiplier's current low byte.
    BIT  0,A                            ; Does its next bit contribute to the product?
    JR   Z,.skip                        ; No: skip this accumulator addition.
    CALL exAddUp                        ; Add multiplicand to accumulator.
    JP   C,exRange                      ; Carry beyond bit 23 is unsigned overflow.
.skip: ; Advance after the optional accumulator addition.
    CALL exHalve                        ; Consume the multiplier bit by shifting right.

; Stop as soon as the shifted multiplier becomes zero. This avoids needless
; remaining rounds without changing the fixed 24-bit result.

    LD   A,(exRAbs)                     ; Begin folding all multiplier bytes together.
    LD   C,A                            ; Preserve the low-byte contribution.
    LD   A,(exRAbs+1)                   ; Load the middle byte.
    OR   C                              ; Combine it with the low byte.
    LD   C,A                            ; Preserve the partial nonzero test.
    LD   A,(exRAbs+2)                   ; Load the high byte.
    OR   C                              ; Combine all three multiplier bytes.
    JR   Z,.done                        ; No later multiplier bit contributes.

; A multiplicand with its top bit already set cannot be shifted left again in
; the positive-magnitude domain.

    LD   A,(exLAbs+2)                   ; Inspect the multiplicand's current top bit.
    BIT  7,A                            ; Would another shift discard magnitude data?
    JP   NZ,exRange                     ; Yes: report 24-bit multiplication overflow.
    CALL exDouble                       ; Double the multiplicand for the next bit.
    LD   HL,exRndCnt                    ; Address the defensive round counter.
    DEC  (HL)                           ; Account for this completed multiplier bit.
    JR   NZ,.loop                       ; Continue while width remains.
.done: ; Publish and sign the completed product magnitude.

; Move the accumulated magnitude to the normal result slot and restore the
; computed sign.

    LD   HL,exAccum                     ; Point at the completed product magnitude.
    LD   DE,exRVal                      ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the complete 24-bit product.
    LDIR                                ; Publish it as the reduction result.
    LD   A,(exSign)                     ; Load the result-sign Boolean.
    OR   A                              ; Set NZ when the product must be negative.
exSigned: ; Apply the saved sign and return resolved success.
    CALL NZ,exNeg                       ; Apply two's-complement sign when requested.
    RET  C                              ; Preserve the helper's failure contract.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the signed result in exRVal.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Select quotient mode and share the signed long-division implementation.

exDiv: ; Select quotient output from the shared division routine.
    XOR  A                              ; Select quotient output mode.
    LD   (exDivSel),A                   ; Store the division/remainder selector.
    JR   exDivide                       ; Share signed long division.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Select remainder mode. The final remainder uses the dividend's sign rather
; than the quotient's XOR sign.

exRem: ; Select remainder output from the shared division routine.
    LD   A,1                            ; Select remainder output mode.
    LD   (exDivSel),A                   ; Store the division/remainder selector.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Divide magnitudes with 24 rounds of restoring long division. exLAbs is the
; shifting dividend, exRAbs the divisor, exAccum the partial remainder and
; exQuot the quotient.

exDivide: ; Perform 24 restoring division rounds on unsigned magnitudes.
; Reject a zero divisor before copying or changing either operand workspace.

    LD   A,(exRVal)                     ; Begin folding divisor bytes together.
    LD   B,A                            ; Preserve its low-byte contribution.
    LD   A,(exRVal+1)                   ; Load the divisor middle byte.
    OR   B                              ; Combine it with the low byte.
    LD   B,A                            ; Preserve the partial nonzero test.
    LD   A,(exRVal+2)                   ; Load the divisor high byte.
    OR   B                              ; Combine all three divisor bytes.
    JR   Z,.zero                        ; Reject an all-zero divisor before mutation.
    CALL exAbs                          ; Copy magnitudes and signs.
    XOR  A                              ; Form zero for division work areas.
    LD   (exAccum),A                    ; Clear partial remainder low byte.
    LD   (exAccum+1),A                  ; Clear partial remainder middle byte.
    LD   (exAccum+2),A                  ; Clear partial remainder high byte.
    LD   (exQuot),A                     ; Clear quotient low byte.
    LD   (exQuot+1),A                   ; Clear quotient middle byte.
    LD   (exQuot+2),A                   ; Clear quotient high byte.
    LD   B,24                           ; Process exactly one round per dividend bit.
.loop: ; Convert one dividend bit to quotient bit.

; Shift the next dividend bit into the partial remainder and make room for the
; next quotient bit.

    LD   HL,exLAbs                      ; Point at the shifting dividend magnitude.
    CALL exSla24                        ; Move its next top bit into carry.
    LD   HL,exAccum                     ; Point at the partial remainder low byte.
    LD   A,(HL)                         ; Load it without disturbing carry.
    RL   A                              ; Shift in the dividend bit.
    LD   (HL),A                         ; Store the new low remainder byte.
    INC  HL                             ; Advance to the middle remainder byte.
    LD   A,(HL)                         ; Load it without disturbing carry.
    RL   A                              ; Propagate low-byte carry.
    LD   (HL),A                         ; Store the new middle remainder byte.
    INC  HL                             ; Advance to the high remainder byte.
    LD   A,(HL)                         ; Load it without disturbing carry.
    RL   A                              ; Complete the 24-bit remainder shift.
    LD   (HL),A                         ; Store the new high remainder byte.
    LD   HL,exQuot                      ; Point at the quotient magnitude.
    CALL exSla24                        ; Make room for this round's quotient bit.

; If remainder >= divisor, subtract the divisor and set the new quotient bit.

    CALL exIsLess                       ; Compare remainder and divisor.
    JR   C,.nextBit                     ; Smaller remainder produces quotient bit zero.
    CALL exSubDiv                       ; Subtract divisor from the partial remainder.
    LD   HL,exQuot                      ; Address the quotient low byte.
    LD   A,(HL)                         ; Load the shifted quotient byte.
    SET  0,A                            ; Publish quotient bit one for this round.
    LD   (HL),A                         ; Store the updated quotient low byte.
.nextBit: ; Advance to the next restoring-division round.
    DJNZ .loop                          ; Process every remaining dividend bit.

; Choose quotient or remainder storage and the corresponding sign bit.

    LD   A,(exDivSel)                   ; Read quotient/remainder output mode.
    OR   A                              ; Z selects the quotient.
    JR   NZ,.useRem                     ; Nonzero selects the partial remainder.
    LD   HL,exQuot                      ; Point at the quotient magnitude.
    LD   A,(exSign)                     ; Quotient sign is left XOR right sign.
    JR   .result                        ; Copy and sign the selected magnitude.
.useRem: ; Select remainder and dividend sign.
    LD   HL,exAccum                     ; Point at the remainder magnitude.
    LD   A,(exLSign)                    ; Remainder inherits the dividend's sign.
.result: ; Copy and sign the selected division result.
    LD   DE,exRVal                      ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the complete selected magnitude.
    LDIR                                ; Publish it as the reduction result.
    OR   A                              ; Test selected sign and clear carry.
    JP   exSigned                       ; Apply sign and return resolved success.
.zero: ; Report a zero divisor at its operator.
    LD   A,exDiv0                       ; Select division-by-zero status.
    JP   exAtOper                       ; Anchor failure at '/' or '%'.
