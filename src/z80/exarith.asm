;==========================================================================
;  Expression arithmetic
;==========================================================================
;
;  Signed 24-bit addition, subtraction, multiplication and division.
;  Results replace the right operand in EX_RVAL.
;
;@ROUTINE OUT A,BC,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Save both sign bytes for overflow checks, load the left low byte, and point
; HL at the right/result record for the bytewise operation.

EX_SETUP: ; Load operand signs and prepare bytewise result access.
    LD   A,(EX_LVAL+2)                  ; Load the left operand's sign/high byte.
    LD   B,A                            ; Preserve it for overflow detection.
    LD   A,(EX_RVAL+2)                  ; Load the right operand's sign/high byte.
    LD   C,A                            ; Preserve it for overflow detection.
    LD   A,(EX_LVAL)                    ; Start arithmetic with the left low byte.
    LD   HL,EX_RVAL                     ; Point at the in-place right/result record.
    RET                                 ; Return signs, low byte and result pointer.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Add signed 24-bit operands into EX_RVAL. Equal-sign inputs may overflow only
; if the result sign changes; mixed-sign inputs cannot overflow.

EX_ADD: ; Add signed 24-bit operands and check the result sign.
    CALL EX_SETUP                       ; Load low byte, both signs and result pointer.
    ADD  A,(HL)                         ; Add the right low byte without incoming carry.
    LD   (HL),A                         ; Store the result low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(EX_LVAL+1)                  ; Load the left middle byte.
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
    JR   NZ,EX_OK                       ; Different signs cannot overflow.
    LD   A,B                            ; Compare the common input sign with the result.
    XOR  D                              ; Bit 7 set means the result sign changed.
    BIT  7,A                            ; Did sum cross the signed limit?
    JP   NZ,EX_RANGE                    ; Yes: report range at the saved operator.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Shared arithmetic success tail clears carry and returns EX_FINAL in A.

EX_OK: ; Return concrete success with carry clear.
    XOR  A                              ; Return EX_FINAL and clear carry.
    RET                                 ; Complete arithmetic successfully.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO,IX,IY
; Subtract EX_RVAL from EX_LVAL into EX_RVAL. Opposite-sign inputs may
; overflow only if the result sign differs from the left operand.

EX_SUB: ; Subtract right from left and check signed overflow.
    CALL EX_SETUP                       ; Load low byte, both signs and result pointer.
    SUB  (HL)                           ; Subtract the right low byte.
    LD   (HL),A                         ; Store the result low byte.
    INC  HL                             ; Advance to the middle byte.
    LD   A,(EX_LVAL+1)                  ; Load the left middle byte.
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
    JR   Z,EX_OK                        ; Equal-sign subtraction cannot overflow.
    LD   A,B                            ; Compare the left sign with the result sign.
    XOR  D                              ; Bit 7 set means subtraction crossed the limit.
    BIT  7,A                            ; Did the result change from the left sign?
    JP   NZ,EX_RANGE                    ; Yes: report range at the saved operator.
    JR   EX_OK                          ; Otherwise return resolved success.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise AND to all three bytes of the 24-bit working values.

EX_AND: ; Combine corresponding bytes with bitwise AND.
    LD   HL,EX_RVAL                     ; Point at the right/result low byte.
    LD   DE,EX_LVAL                     ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.LOOP: ; Combine one corresponding operand byte with AND.
    LD   A,(DE)                         ; Load one left operand byte.
    AND  (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .LOOP                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise XOR to all three bytes of the 24-bit working values.

EX_XOR: ; Combine corresponding bytes with bitwise XOR.
    LD   HL,EX_RVAL                     ; Point at the right/result low byte.
    LD   DE,EX_LVAL                     ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.LOOP: ; Combine one corresponding operand byte with XOR.
    LD   A,(DE)                         ; Load one left operand byte.
    XOR  (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .LOOP                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise OR to all three bytes of the 24-bit working values.

EX_OR: ; Combine corresponding bytes with bitwise OR.
    LD   HL,EX_RVAL                     ; Point at the right/result low byte.
    LD   DE,EX_LVAL                     ; Point at the left low byte.
    LD   B,3                            ; Process all three working bytes.
.LOOP: ; Combine one corresponding operand byte with OR.
    LD   A,(DE)                         ; Load one left operand byte.
    OR   (HL)                           ; Combine it with the corresponding right byte.
    LD   (HL),A                         ; Store the byte in the result record.
    INC  DE                             ; Advance the left pointer.
    INC  HL                             ; Advance the right/result pointer.
    DJNZ .LOOP                          ; Repeat for middle and high bytes.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Shift the little-endian 24-bit value at HL left by one bit. Carry propagates
; from low to high byte and reports the bit discarded from the sign byte.

EX_SLA24: ; Shift three bytes left and return the discarded top bit in carry.
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

EX_SHL: ; Check the count and reject a sign change during left shift.
    CALL EX_COUNT                       ; Validate count in 0..23.
    RET  C                              ; Preserve range failure at the shift operator.
    LD   B,A                            ; Keep the repeat count in B.
    OR   A                              ; Is this a zero-bit shift?
    JR   Z,.COPY                        ; Yes: copy the left operand unchanged.
.LOOP: ; Shift one bit and reject a changed sign.

; C retains the sign byte before the shift so XOR detects a changed sign bit.

    LD   A,(EX_LVAL+2)                  ; Load the sign byte before this shift.
    LD   C,A                            ; Preserve its sign bit.
    LD   HL,EX_LVAL                     ; Shift the left operand in place.
    CALL EX_SLA24                       ; Perform one complete 24-bit left shift.
    XOR  C                              ; Compare old and new sign bits.
    BIT  7,A                            ; Did this step change the signed result's sign?
    JP   NZ,EX_RANGE                    ; Yes: report signed 24-bit overflow.
    DJNZ .LOOP                          ; Shift the remaining requested bits.
.COPY: ; Copy shifted operand to result.

; Binary reducers publish through EX_RVAL, so copy the shifted left
; operand there even when the count was zero.

    LD   HL,EX_LVAL                     ; Point at the shifted left operand.
    LD   DE,EX_RVAL                     ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the full 24-bit working value.
    LDIR                                ; Publish it as the reduction result.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave EX_RVAL ready for the value stack.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Copy the left operand to EX_RVAL, then perform an arithmetic right shift for
; each requested bit. SRA preserves the 24-bit sign in the high byte and RR
; propagates it through the lower sixteen bits.

EX_SHR: ; Copy the left value and propagate its sign through right shifts.
    CALL EX_COUNT                       ; Validate count in 0..23.
    RET  C                              ; Preserve range failure at the shift operator.
    LD   B,A                            ; Preserve the requested count.
    PUSH BC                             ; Save it across the fixed-size copy.
    LD   HL,EX_LVAL                     ; Point at the source left operand.
    LD   DE,EX_RVAL                     ; Select the result slot.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Initialise the in-place shifted result.
    POP  BC                             ; Restore the requested count in B.
    LD   A,B                            ; Test whether any shifting is required.
    OR   A                              ; Z identifies a zero-bit shift.
    JP   Z,EX_OK                        ; Return the unchanged copied value.
    LD   B,A                            ; Restore B as the loop counter.
.LOOP: ; Shift the result right by one requested bit.
    LD   HL,EX_RVAL+2                   ; Point at the result high/sign byte.
    LD   A,(HL)                         ; Load it for an arithmetic shift.
    SRA  A                              ; Preserve bit 7 and expose bit 0 in carry.
    CALL EX_SRL16                       ; Store it and rotate carry through lower bytes.
    DJNZ .LOOP                          ; Repeat for each requested bit.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the shifted value in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept only a nonnegative count below 24. Any nonzero upper
; byte or low byte of 24 and above is a range error at the operator position.

EX_COUNT: ; Require a concrete shift count within 0..23.
    LD   A,(EX_RVAL+2)                  ; Read the count's high/sign byte.
    OR   A                              ; Must it be zero?
    JP   NZ,EX_RANGE                    ; Nonzero makes the count negative or too large.
    LD   A,(EX_RVAL+1)                  ; Read the count's middle byte.
    OR   A                              ; Must it also be zero?
    JP   NZ,EX_RANGE                    ; Nonzero is at least 256 and invalid.
    LD   A,(EX_RVAL)                    ; Load the remaining low-byte count.
    CP   24                             ; Is it within the 24-bit value width?
    JP   NC,EX_RANGE                    ; Reject 24 and every larger count.
    OR   A                              ; Clear carry while preserving count A.
    RET                                 ; Return the validated count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Multiply signed 24-bit operands by shift and add. Magnitudes make
; the loop unsigned; EX_SIGN records whether the final result must be negated.

EX_MUL: ; Accumulate magnitude products from multiplier bits.
    CALL EX_ABS                         ; Copy magnitudes and signs.
    XOR  A                              ; Form a zero product accumulator.
    LD   (EX_ACCUM),A                   ; Clear its low byte.
    LD   (EX_ACCUM+1),A                 ; Clear its middle byte.
    LD   (EX_ACCUM+2),A                 ; Clear its high byte.
    LD   A,24                           ; Bound multiplication to the working width.
    LD   (EX_ROUND),A                   ; Initialise the defensive iteration counter.
.LOOP: ; Process one multiplier bit.

; Add the multiplicand when the multiplier's low bit is set. Carry from
; the 24-bit accumulator is an overflow.

    LD   A,(EX_RABS)                    ; Load the multiplier's current low byte.
    BIT  0,A                            ; Does its next bit contribute to the product?
    JR   Z,.SKIP                        ; No: skip this accumulator addition.
    CALL EX_ADDUP                       ; Add multiplicand to accumulator.
    JP   C,EX_RANGE                     ; Carry beyond bit 23 is unsigned overflow.
.SKIP: ; Advance after the optional accumulator addition.
    CALL EX_HALVE                       ; Consume the multiplier bit by shifting right.

; Stop as soon as the shifted multiplier becomes zero. This avoids needless
; remaining rounds without changing the fixed 24-bit result.

    LD   A,(EX_RABS)                    ; Begin folding all multiplier bytes together.
    LD   C,A                            ; Preserve the low-byte contribution.
    LD   A,(EX_RABS+1)                  ; Load the middle byte.
    OR   C                              ; Combine it with the low byte.
    LD   C,A                            ; Preserve the partial nonzero test.
    LD   A,(EX_RABS+2)                  ; Load the high byte.
    OR   C                              ; Combine all three multiplier bytes.
    JR   Z,.DONE                        ; No later multiplier bit contributes.

; A multiplicand with its top bit already set cannot be shifted left again in
; the positive-magnitude domain.

    LD   A,(EX_LABS+2)                  ; Inspect the multiplicand's current top bit.
    BIT  7,A                            ; Would another shift discard magnitude data?
    JP   NZ,EX_RANGE                    ; Yes: report 24-bit multiplication overflow.
    CALL EX_TWICE                       ; Double the multiplicand for the next bit.
    LD   HL,EX_ROUND                    ; Address the defensive round counter.
    DEC  (HL)                           ; Account for this completed multiplier bit.
    JR   NZ,.LOOP                       ; Continue while width remains.
.DONE: ; Publish and sign the completed product magnitude.

; Move the accumulated magnitude to the normal result slot and restore the
; computed sign.

    LD   HL,EX_ACCUM                    ; Point at the completed product magnitude.
    LD   DE,EX_RVAL                     ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the complete 24-bit product.
    LDIR                                ; Publish it as the reduction result.
    LD   A,(EX_SIGN)                    ; Load the result-sign Boolean.
    OR   A                              ; Set NZ when the product must be negative.
EX_APPLY: ; Apply the saved sign and return resolved success.
    CALL NZ,EX_NEG                      ; Apply two's-complement sign when requested.
    RET  C                              ; Preserve the helper's failure contract.
    XOR  A                              ; Return resolved success with carry clear.
    RET                                 ; Leave the signed result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Select quotient mode and share the signed long-division implementation.

EX_DIV: ; Select quotient output from the shared division routine.
    XOR  A                              ; Select quotient output mode.
    LD   (EX_MODE),A                    ; Store the division/remainder selector.
    JR   EX_LDIV                        ; Share signed long division.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Select remainder mode. The final remainder uses the dividend's sign rather
; than the quotient's XOR sign.

EX_REM: ; Select remainder output from the shared division routine.
    LD   A,1                            ; Select remainder output mode.
    LD   (EX_MODE),A                    ; Store the division/remainder selector.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Divide magnitudes with 24 rounds of restoring long division. EX_LABS is the
; shifting dividend, EX_RABS the divisor, EX_ACCUM the partial remainder and
; EX_QUOT the quotient.

EX_LDIV: ; Perform 24 restoring division rounds on unsigned magnitudes.
; Reject a zero divisor before copying or changing either operand workspace.

    LD   A,(EX_RVAL)                    ; Begin folding divisor bytes together.
    LD   B,A                            ; Preserve its low-byte contribution.
    LD   A,(EX_RVAL+1)                  ; Load the divisor middle byte.
    OR   B                              ; Combine it with the low byte.
    LD   B,A                            ; Preserve the partial nonzero test.
    LD   A,(EX_RVAL+2)                  ; Load the divisor high byte.
    OR   B                              ; Combine all three divisor bytes.
    JR   Z,.ZERO                        ; Reject an all-zero divisor before mutation.
    CALL EX_ABS                         ; Copy magnitudes and signs.
    XOR  A                              ; Form zero for division work areas.
    LD   (EX_ACCUM),A                   ; Clear partial remainder low byte.
    LD   (EX_ACCUM+1),A                 ; Clear partial remainder middle byte.
    LD   (EX_ACCUM+2),A                 ; Clear partial remainder high byte.
    LD   (EX_QUOT),A                    ; Clear quotient low byte.
    LD   (EX_QUOT+1),A                  ; Clear quotient middle byte.
    LD   (EX_QUOT+2),A                  ; Clear quotient high byte.
    LD   B,24                           ; Process exactly one round per dividend bit.
.LOOP: ; Convert one dividend bit to quotient bit.

; Shift the next dividend bit into the partial remainder and make room for the
; next quotient bit.

    LD   HL,EX_LABS                     ; Point at the shifting dividend magnitude.
    CALL EX_SLA24                       ; Move its next top bit into carry.
    LD   HL,EX_ACCUM                    ; Point at the partial remainder low byte.
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
    LD   HL,EX_QUOT                     ; Point at the quotient magnitude.
    CALL EX_SLA24                       ; Make room for this round's quotient bit.

; If remainder >= divisor, subtract the divisor and set the new quotient bit.

    CALL EX_CMP                         ; Compare remainder and divisor.
    JR   C,.NEXTBIT                     ; Smaller remainder produces quotient bit zero.
    CALL EX_MINUS                       ; Subtract divisor from the partial remainder.
    LD   HL,EX_QUOT                     ; Address the quotient low byte.
    LD   A,(HL)                         ; Load the shifted quotient byte.
    SET  0,A                            ; Publish quotient bit one for this round.
    LD   (HL),A                         ; Store the updated quotient low byte.
.NEXTBIT: ; Advance to the next restoring-division round.
    DJNZ .LOOP                          ; Process every remaining dividend bit.

; Choose quotient or remainder storage and the corresponding sign bit.

    LD   A,(EX_MODE)                    ; Read quotient/remainder output mode.
    OR   A                              ; Z selects the quotient.
    JR   NZ,.USEREM                     ; Nonzero selects the partial remainder.
    LD   HL,EX_QUOT                     ; Point at the quotient magnitude.
    LD   A,(EX_SIGN)                    ; Quotient sign is left XOR right sign.
    JR   .RESULT                        ; Copy and sign the selected magnitude.
.USEREM: ; Select remainder and dividend sign.
    LD   HL,EX_ACCUM                    ; Point at the remainder magnitude.
    LD   A,(EX_LSIGN)                   ; Remainder inherits the dividend's sign.
.RESULT: ; Copy and sign the selected division result.
    LD   DE,EX_RVAL                     ; Select the ordinary result slot.
    LD   BC,3                           ; Copy the complete selected magnitude.
    LDIR                                ; Publish it as the reduction result.
    OR   A                              ; Test selected sign and clear carry.
    JP   EX_APPLY                       ; Apply sign and return resolved success.
.ZERO: ; Report a zero divisor at its operator.
    LD   A,EX_SZERO                     ; Select division-by-zero status.
    JP   EX_FOPER                       ; Anchor failure at '/' or '%'.
