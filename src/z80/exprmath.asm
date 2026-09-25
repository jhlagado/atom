;==============================================================================
;  Expression arithmetic and workspace
;==============================================================================
;
;  Concrete 24-bit arithmetic kernels used by expr.asm, followed by the
;  evaluator's fixed working state and bounded stacks. This is a separate source
;  part so the educational commentary remains within Atom's 16-bit per-part
;  source-offset range; it is assembled immediately after expr.asm.
;
;@ROUTINE OUT A,BC,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Load the low bytes and sign bytes used by the 24-bit add/subtract paths. A is
; the left low byte, HL points at the right result and B/C retain both signs.

EX_LARIT:
    LD   A,(EX_LVAL+2)        ; Load the left operand's sign/high byte.
    LD   B,A                   ; Preserve it for overflow detection.
    LD   A,(EX_RVAL+2)        ; Load the right operand's sign/high byte.
    LD   C,A                   ; Preserve it for overflow detection.
    LD   A,(EX_LVAL)          ; Start arithmetic with the left low byte.
    LD   HL,EX_RVAL           ; Point at the in-place right/result record.
    RET                       ; Return both signs, low byte and result pointer.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Add signed 24-bit operands into EX_RVAL. Equal-sign inputs may overflow only
; if the result sign changes; mixed-sign inputs cannot overflow.

EX_ADD:
    CALL EX_LARIT             ; Load low byte, both signs and result pointer.
    ADD  A,(HL)               ; Add the right low byte without incoming carry.
    LD   (HL),A               ; Store the result low byte.
    INC  HL                   ; Advance to the middle byte.
    LD   A,(EX_LVAL+1)        ; Load the left middle byte.
    ADC  A,(HL)               ; Add right middle byte plus low-byte carry.
    LD   (HL),A               ; Store the result middle byte.
    INC  HL                   ; Advance to the high/sign byte.
    LD   A,B                  ; Reload the left high byte.
    ADC  A,(HL)               ; Add right high byte plus middle-byte carry.
    LD   (HL),A               ; Store the result high byte.
    LD   D,A                  ; Preserve the result sign for the overflow test.
    LD   A,B                  ; Compare input signs first.
    XOR  C                    ; Bit 7 set means the inputs had different signs.
    BIT  7,A                  ; Can signed addition overflow?
    JR   NZ,EX_AOK            ; Different signs cannot overflow.
    LD   A,B                  ; Compare the common input sign with the result.
    XOR  D                    ; Bit 7 set means the result sign changed.
    BIT  7,A                  ; Did equal-sign addition cross the signed limit?
    JP   NZ,EX_ROPER          ; Yes: report range at the saved operator.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Shared arithmetic success tail clears carry and returns EX_RESOL in A.

EX_AOK:
    XOR  A                    ; Return EX_RESOL and clear carry.
    RET                       ; Complete the arithmetic operation successfully.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO,IX,IY
; Subtract EX_RVAL from EX_LVAL into EX_RVAL. Different-sign inputs may overflow
; only if the result sign differs from the left operand.

EX_SUBTR:
    CALL EX_LARIT             ; Load low byte, both signs and result pointer.
    SUB  (HL)                 ; Subtract the right low byte.
    LD   (HL),A               ; Store the result low byte.
    INC  HL                   ; Advance to the middle byte.
    LD   A,(EX_LVAL+1)        ; Load the left middle byte.
    SBC  A,(HL)               ; Subtract right middle byte and low-byte borrow.
    LD   (HL),A               ; Store the result middle byte.
    INC  HL                   ; Advance to the high/sign byte.
    LD   A,B                  ; Reload the left high byte.
    SBC  A,(HL)               ; Subtract right high byte and middle-byte borrow.
    LD   (HL),A               ; Store the result high byte.
    LD   D,A                  ; Preserve the result sign for the overflow test.
    LD   A,B                  ; Compare the two input signs.
    XOR  C                    ; Bit 7 set means their signs differed.
    BIT  7,A                  ; Can signed subtraction overflow?
    JR   Z,EX_AOK             ; Equal-sign subtraction cannot overflow.
    LD   A,B                  ; Compare the left sign with the result sign.
    XOR  D                    ; Bit 7 set means subtraction crossed the limit.
    BIT  7,A                  ; Did the result change from the left sign?
    JP   NZ,EX_ROPER          ; Yes: report range at the saved operator.
    JR   EX_AOK               ; Otherwise return resolved success.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise AND to all three bytes of the 24-bit working values.

EX_AND:
    LD   HL,EX_RVAL           ; Point at the right/result low byte.
    LD   DE,EX_LVAL           ; Point at the left low byte.
    LD   B,3                  ; Process all three working bytes.
.ANDLOOP:                  ; Combine one corresponding operand byte with AND.
    LD   A,(DE)               ; Load one left operand byte.
    AND  (HL)                 ; Combine it with the corresponding right byte.
    LD   (HL),A               ; Store the byte in the result record.
    INC  DE                   ; Advance the left pointer.
    INC  HL                   ; Advance the right/result pointer.
    DJNZ .ANDLOOP             ; Repeat for middle and high bytes.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise XOR to all three bytes of the 24-bit working values.

EX_XOR:
    LD   HL,EX_RVAL           ; Point at the right/result low byte.
    LD   DE,EX_LVAL           ; Point at the left low byte.
    LD   B,3                  ; Process all three working bytes.
.XORLOOP:                  ; Combine one corresponding operand byte with XOR.
    LD   A,(DE)               ; Load one left operand byte.
    XOR  (HL)                 ; Combine it with the corresponding right byte.
    LD   (HL),A               ; Store the byte in the result record.
    INC  DE                   ; Advance the left pointer.
    INC  HL                   ; Advance the right/result pointer.
    DJNZ .XORLOOP             ; Repeat for middle and high bytes.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Apply bitwise OR to all three bytes of the 24-bit working values.

EX_OR:
    LD   HL,EX_RVAL           ; Point at the right/result low byte.
    LD   DE,EX_LVAL           ; Point at the left low byte.
    LD   B,3                  ; Process all three working bytes.
.ORLOOP:                   ; Combine one corresponding operand byte with OR.
    LD   A,(DE)               ; Load one left operand byte.
    OR   (HL)                 ; Combine it with the corresponding right byte.
    LD   (HL),A               ; Store the byte in the result record.
    INC  DE                   ; Advance the left pointer.
    INC  HL                   ; Advance the right/result pointer.
    DJNZ .ORLOOP              ; Repeat for middle and high bytes.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave the 24-bit result in EX_RVAL.

;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Shift the little-endian 24-bit value at HL left by one bit. Carry propagates
; from low to high byte and reports the bit discarded from the sign byte.

EX_SL24:
    LD   A,(HL)               ; Load the low byte.
    SLA  A                    ; Shift left and place bit 7 in carry.
    LD   (HL),A               ; Store the shifted low byte.
    INC  HL                   ; Advance to the middle byte.
    LD   A,(HL)               ; Load the middle byte.
    RL   A                    ; Shift left through the low-byte carry.
    LD   (HL),A               ; Store the shifted middle byte.
    INC  HL                   ; Advance to the high/sign byte.
    LD   A,(HL)               ; Load the high byte.
    RL   A                    ; Shift through carry and expose discarded bit 23.
    LD   (HL),A               ; Store the shifted high byte.
    RET                       ; Return final carry and high byte in A.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Validate the right operand as a count from 0 through 23, then shift the left
; operand repeatedly. A sign change on any step reports signed 24-bit overflow.

EX_SLEFT:
    CALL EX_SCNT              ; Validate and return a count from zero through 23.
    RET  C                    ; Preserve range failure at the shift operator.
    LD   B,A                  ; Keep the repeat count in B.
    OR   A                    ; Is this a zero-bit shift?
    JR   Z,.SLCOPY            ; Yes: copy the left operand unchanged.
.SLLOOP:                   ; Shift one bit and reject a changed sign.

; C retains the sign byte before the shift so XOR detects a changed sign bit.

    LD   A,(EX_LVAL+2)        ; Load the sign byte before this shift.
    LD   C,A                  ; Preserve its sign bit.
    LD   HL,EX_LVAL           ; Shift the left operand in place.
    CALL EX_SL24              ; Perform one complete 24-bit left shift.
    XOR  C                    ; Compare old and new sign bits.
    BIT  7,A                  ; Did this step change the signed result's sign?
    JP   NZ,EX_ROPER          ; Yes: report signed 24-bit overflow.
    DJNZ .SLLOOP              ; Shift the remaining requested bits.
.SLCOPY:                   ; Copy the shifted left operand into result workspace.

; Binary reducers publish their result through EX_RVAL, so copy the shifted left
; operand there even when the count was zero.

    LD   HL,EX_LVAL           ; Point at the shifted left operand.
    LD   DE,EX_RVAL           ; Select the ordinary result slot.
    LD   BC,3                 ; Copy the full 24-bit working value.
    LDIR                      ; Publish it as the reduction result.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave EX_RVAL ready for the value stack.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Copy the left operand to EX_RVAL, then perform an arithmetic right shift for
; each requested bit. SRA preserves the 24-bit sign in the high byte and RR
; propagates it through the lower sixteen bits.

EX_SRIGH:
    CALL EX_SCNT              ; Validate and return a count from zero through 23.
    RET  C                    ; Preserve range failure at the shift operator.
    LD   B,A                  ; Preserve the requested count.
    PUSH BC                   ; Save it across the fixed-size copy.
    LD   HL,EX_LVAL           ; Point at the source left operand.
    LD   DE,EX_RVAL           ; Select the result slot.
    LD   BC,3                 ; Copy the complete 24-bit value.
    LDIR                      ; Initialize the in-place shifted result.
    POP  BC                   ; Restore the requested count in B.
    LD   A,B                  ; Test whether any shifting is required.
    OR   A                    ; Z identifies a zero-bit shift.
    JP   Z,EX_AOK             ; Return the unchanged copied value.
    LD   B,A                  ; Restore B as the loop counter.
.SRLOOP:                   ; Shift the result right by one requested bit.
    LD   HL,EX_RVAL+2         ; Point at the result high/sign byte.
    LD   A,(HL)               ; Load it for an arithmetic shift.
    SRA  A                    ; Preserve bit 7 and expose bit 0 in carry.
    CALL EX_SRL16             ; Store it and rotate carry through lower bytes.
    DJNZ .SRLOOP              ; Repeat for each requested bit.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave the shifted value in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept only a non-negative 24-bit shift count less than 24. Any non-zero upper
; byte or low byte of 24 and above is a range error at the operator position.

EX_SCNT:
    LD   A,(EX_RVAL+2)        ; Read the count's high/sign byte.
    OR   A                    ; Must it be zero?
    JP   NZ,EX_ROPER          ; Nonzero makes the count negative or too large.
    LD   A,(EX_RVAL+1)        ; Read the count's middle byte.
    OR   A                    ; Must it also be zero?
    JP   NZ,EX_ROPER          ; Nonzero is at least 256 and invalid.
    LD   A,(EX_RVAL)          ; Load the remaining low-byte count.
    CP   24                   ; Is it within the 24-bit value width?
    JP   NC,EX_ROPER          ; Reject 24 and every larger count.
    OR   A                    ; Clear carry while preserving count A.
    RET                       ; Return the validated count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Multiply signed 24-bit operands by shift and add. Magnitude preparation makes
; the loop unsigned; EX_SRES records whether the final result must be negated.

EX_MULTI:
    CALL EX_PMAGN             ; Copy both operands as unsigned magnitudes and signs.
    XOR  A                    ; Form a zero product accumulator.
    LD   (EX_ACCUM),A         ; Clear its low byte.
    LD   (EX_ACCUM+1),A       ; Clear its middle byte.
    LD   (EX_ACCUM+2),A       ; Clear its high byte.
    LD   A,24                 ; Bound multiplication to the working width.
    LD   (EX_MCOUN),A         ; Initialize the defensive iteration counter.
.MLOOP:                    ; Process one multiplier bit.

; Add the current multiplicand when the multiplier's low bit is set. Carry from
; the 24-bit accumulator is an overflow.

    LD   A,(EX_MRIGH)         ; Load the multiplier's current low byte.
    BIT  0,A                  ; Does its next bit contribute to the product?
    JR   Z,.MSADD             ; No: skip this accumulator addition.
    CALL EX_AALEF             ; Add the shifted multiplicand to the accumulator.
    JP   C,EX_ROPER           ; Carry beyond bit 23 is unsigned overflow.
.MSADD:                    ; Advance after the optional accumulator addition.
    CALL EX_MRSHI             ; Consume the multiplier bit by shifting right.

; Stop as soon as the shifted multiplier becomes zero. This avoids needless
; remaining rounds without changing the fixed 24-bit result.

    LD   A,(EX_MRIGH)         ; Begin folding all multiplier bytes together.
    LD   C,A                  ; Preserve the low-byte contribution.
    LD   A,(EX_MRIGH+1)       ; Load the middle byte.
    OR   C                    ; Combine it with the low byte.
    LD   C,A                  ; Preserve the partial nonzero test.
    LD   A,(EX_MRIGH+2)       ; Load the high byte.
    OR   C                    ; Combine all three multiplier bytes.
    JR   Z,.MDONE             ; Zero means no later multiplier bit contributes.

; A multiplicand with its top bit already set cannot be shifted left again in
; the positive-magnitude domain.

    LD   A,(EX_MLEFT+2)       ; Inspect the multiplicand's current top bit.
    BIT  7,A                  ; Would another shift discard magnitude data?
    JP   NZ,EX_ROPER          ; Yes: report 24-bit multiplication overflow.
    CALL EX_MLSHI             ; Double the multiplicand for the next bit.
    LD   HL,EX_MCOUN          ; Address the defensive round counter.
    DEC  (HL)                 ; Account for this completed multiplier bit.
    JR   NZ,.MLOOP            ; Continue while width remains.
.MDONE:                    ; Publish and sign the completed product magnitude.

; Move the accumulated magnitude to the normal result slot and restore the
; computed sign.

    LD   HL,EX_ACCUM          ; Point at the completed product magnitude.
    LD   DE,EX_RVAL           ; Select the ordinary result slot.
    LD   BC,3                 ; Copy the complete 24-bit product.
    LDIR                      ; Publish it as the reduction result.
    LD   A,(EX_SRES)          ; Load the result-sign Boolean.
    OR   A                    ; Set NZ when the product must be negative.
EX_ASRES:                  ; Apply the saved sign and return resolved success.
    CALL NZ,EX_NRES           ; Apply two's-complement sign when requested.
    RET  C                    ; Preserve the helper's failure contract.
    XOR  A                    ; Return resolved success with carry clear.
    RET                       ; Leave the signed result in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Select quotient mode and share the signed long-division implementation.

EX_DIVID:
    XOR  A                    ; Select quotient output mode.
    LD   (EX_DRMOD),A         ; Store the division/remainder selector.
    JR   EX_DCOMM             ; Share signed long division.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Select remainder mode. The final remainder uses the dividend's sign rather
; than the quotient's XOR sign.

EX_REMAI:
    LD   A,1                  ; Select remainder output mode.
    LD   (EX_DRMOD),A         ; Store the division/remainder selector.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
; Divide magnitudes with 24 rounds of restoring long division. EX_MLEFT is the
; shifting dividend, EX_MRIGH the divisor, EX_ACCUM the partial remainder and
; EX_QUOTI the quotient.

EX_DCOMM:
; Reject zero before magnitude conversion.
; Reject zero before magnitude conversion.

    LD   A,(EX_RVAL)          ; Begin folding divisor bytes together.
    LD   B,A                  ; Preserve its low-byte contribution.
    LD   A,(EX_RVAL+1)        ; Load the divisor middle byte.
    OR   B                    ; Combine it with the low byte.
    LD   B,A                  ; Preserve the partial nonzero test.
    LD   A,(EX_RVAL+2)        ; Load the divisor high byte.
    OR   B                    ; Combine all three divisor bytes.
    JR   Z,.DZERO             ; Reject an all-zero divisor before mutation.
    CALL EX_PMAGN             ; Copy operands as unsigned magnitudes and signs.
    XOR  A                    ; Form zero for division work areas.
    LD   (EX_ACCUM),A         ; Clear partial remainder low byte.
    LD   (EX_ACCUM+1),A       ; Clear partial remainder middle byte.
    LD   (EX_ACCUM+2),A       ; Clear partial remainder high byte.
    LD   (EX_QUOTI),A         ; Clear quotient low byte.
    LD   (EX_QUOTI+1),A       ; Clear quotient middle byte.
    LD   (EX_QUOTI+2),A       ; Clear quotient high byte.
    LD   B,24                 ; Process exactly one round per dividend bit.
.DLOOP:                    ; Process one dividend bit and produce one quotient bit.

; Shift the next dividend bit into the partial remainder and make room for the
; next quotient bit.

    LD   HL,EX_MLEFT          ; Point at the shifting dividend magnitude.
    CALL EX_SL24              ; Move its next top bit into carry.
    LD   HL,EX_ACCUM          ; Point at the partial remainder low byte.
    LD   A,(HL)               ; Load it without disturbing carry.
    RL   A                    ; Shift in the dividend bit.
    LD   (HL),A               ; Store the new low remainder byte.
    INC  HL                   ; Advance to the middle remainder byte.
    LD   A,(HL)               ; Load it without disturbing carry.
    RL   A                    ; Propagate low-byte carry.
    LD   (HL),A               ; Store the new middle remainder byte.
    INC  HL                   ; Advance to the high remainder byte.
    LD   A,(HL)               ; Load it without disturbing carry.
    RL   A                    ; Complete the 24-bit remainder shift.
    LD   (HL),A               ; Store the new high remainder byte.
    LD   HL,EX_QUOTI          ; Point at the quotient magnitude.
    CALL EX_SL24              ; Make room for this round's quotient bit.

; If remainder >= divisor, subtract the divisor and set the new quotient bit.

    CALL EX_RALDI             ; Compare partial remainder with divisor magnitude.
    JR   C,.DNEXT             ; Smaller remainder produces quotient bit zero.
    CALL EX_RSDIV             ; Subtract divisor from the partial remainder.
    LD   HL,EX_QUOTI          ; Address the quotient low byte.
    LD   A,(HL)               ; Load the shifted quotient byte.
    SET  0,A                  ; Publish quotient bit one for this round.
    LD   (HL),A               ; Store the updated quotient low byte.
.DNEXT:                    ; Advance to the next restoring-division round.
    DJNZ .DLOOP               ; Process every remaining dividend bit.

; Choose quotient or remainder storage and the corresponding sign bit.

    LD   A,(EX_DRMOD)         ; Read quotient/remainder output mode.
    OR   A                    ; Z selects the quotient.
    JR   NZ,.UREMAIND         ; Nonzero selects the partial remainder.
    LD   HL,EX_QUOTI          ; Point at the quotient magnitude.
    LD   A,(EX_SRES)          ; Quotient sign is left XOR right sign.
    JR   .DSTORE              ; Copy and sign the selected magnitude.
.UREMAIND:                 ; Select the unsigned remainder magnitude and dividend sign.
    LD   HL,EX_ACCUM          ; Point at the remainder magnitude.
    LD   A,(EX_SLEF1)         ; Remainder inherits the dividend's sign.
.DSTORE:                   ; Copy and sign the selected division result.
    LD   DE,EX_RVAL           ; Select the ordinary result slot.
    LD   BC,3                 ; Copy the complete selected magnitude.
    LDIR                      ; Publish it as the reduction result.
    OR   A                    ; Test the selected sign for conditional negation.
    JP   EX_ASRES             ; Apply sign and return resolved success.
.DZERO:                    ; Report a zero divisor at its operator.
    LD   A,EX_SDZER           ; Select division-by-zero status.
    JP   EX_FOPER             ; Anchor failure at '/' or '%'.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Copy both signed operands to magnitude workspace, record their signs and
; negate negative inputs. The quotient/product sign is left-sign XOR right-sign.

EX_PMAGN:
    LD   HL,EX_LVAL           ; Point at the signed left operand.
    LD   DE,EX_MLEFT          ; Select its magnitude workspace.
    LD   BC,3                 ; Copy the complete 24-bit value.
    LDIR                      ; Preserve the left operand before conversion.
    LD   HL,EX_RVAL           ; Point at the signed right operand.
    LD   DE,EX_MRIGH          ; Select its magnitude workspace.
    LD   BC,3                 ; Copy the complete 24-bit value.
    LDIR                      ; Preserve the right operand before conversion.
    LD   A,(EX_LVAL+2)        ; Load the left sign byte.
    RLCA                      ; Rotate sign bit 7 into bit 0.
    AND  1                    ; Reduce it to a Boolean sign value.
    LD   (EX_SLEF1),A         ; Preserve the dividend/left sign.
    OR   A                    ; Set NZ for a negative left operand.
    CALL NZ,EX_NMLEF          ; Convert its copied value to positive magnitude.
    LD   A,(EX_RVAL+2)        ; Load the right sign byte.
    RLCA                      ; Rotate sign bit 7 into bit 0.
    AND  1                    ; Reduce it to a Boolean sign value.
    LD   (EX_SRIG1),A         ; Preserve the divisor/right sign.
    OR   A                    ; Set NZ for a negative right operand.
    CALL NZ,EX_NMRIG          ; Convert its copied value to positive magnitude.
    LD   A,(EX_SLEF1)         ; Load the left sign Boolean.
    LD   HL,EX_SRIG1          ; Address the right sign Boolean.
    XOR  (HL)                 ; Different signs require a negative result.
    LD   (EX_SRES),A          ; Preserve the product/quotient sign.
    OR   A                    ; Return carry clear with result sign in Z/NZ.
    RET                       ; Leave both magnitude operands prepared.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the normal result slot in place.

EX_NRES:
    LD   HL,EX_RVAL           ; Select the ordinary result value.
    JR   EX_NAHL              ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the copied left magnitude in place.

EX_NMLEF:
    LD   HL,EX_MLEFT          ; Select the copied left magnitude.
    JR   EX_NAHL              ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,A,BC,DE,IX,IY,SIGN,PARITY,HALFCARRY
; Negate the copied right magnitude and fall through to the shared 24-bit body.

EX_NMRIG:
    LD   HL,EX_MRIGH          ; Select the copied right magnitude.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Form the two's complement of the little-endian 24-bit value at HL.

EX_NAHL:
    LD   A,(HL)               ; Load the low byte.
    CPL                       ; Form its one's complement.
    ADD  A,1                  ; Add the two's-complement increment.
    LD   (HL),A               ; Store the negated low byte.
    INC  HL                   ; Advance to the middle byte without changing carry.
    LD   A,(HL)               ; Load the middle byte.
    CPL                       ; Form its one's complement without changing carry.
    ADC  A,0                  ; Propagate the increment carry.
    LD   (HL),A               ; Store the negated middle byte.
    INC  HL                   ; Advance to the high byte without changing carry.
    LD   A,(HL)               ; Load the high byte.
    CPL                       ; Form its one's complement without changing carry.
    ADC  A,0                  ; Complete the 24-bit two's complement.
    LD   (HL),A               ; Store the negated high byte.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Leave the negated value in place.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A
; Complement all three bytes of EX_RVAL for unary '~'.

EX_CRES:
    LD   HL,EX_RVAL           ; Point at the result low byte.
    LD   A,(HL)               ; Load the low byte.
    CPL                       ; Invert every bit.
    LD   (HL),A               ; Store the complemented low byte.
    INC  HL                   ; Advance to the middle byte.
    LD   A,(HL)               ; Load the middle byte.
    CPL                       ; Invert every bit.
    LD   (HL),A               ; Store the complemented middle byte.
    INC  HL                   ; Advance to the high byte.
    LD   A,(HL)               ; Load the high byte.
    CPL                       ; Invert every bit.
    LD   (HL),A               ; Store the complemented high byte.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Leave the complemented value in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Add EX_MLEFT to the 24-bit product accumulator. Carry reports unsigned
; overflow beyond the high byte.

EX_AALEF:
    LD   HL,EX_ACCUM          ; Point at the product accumulator low byte.
    LD   A,(EX_MLEFT)         ; Load the multiplicand low byte.
    ADD  A,(HL)               ; Add the accumulator low byte.
    LD   (HL),A               ; Store the new low product byte.
    INC  HL                   ; Advance without changing carry.
    LD   A,(EX_MLEFT+1)       ; Load the multiplicand middle byte.
    ADC  A,(HL)               ; Add accumulator middle byte and carry.
    LD   (HL),A               ; Store the new middle product byte.
    INC  HL                   ; Advance without changing carry.
    LD   A,(EX_MLEFT+2)       ; Load the multiplicand high byte.
    ADC  A,(HL)               ; Add accumulator high byte and carry.
    LD   (HL),A               ; Store the new high product byte.
    RET                       ; Return carry as overflow beyond bit 23.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift the multiplication multiplicand left by one bit.

EX_MLSHI:
    LD   HL,EX_MLEFT          ; Select the multiplicand magnitude.
    JP   EX_SL24              ; Tail-call one 24-bit left shift.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift the unsigned multiplier magnitude right by one bit. SRL clears the high
; sign position and the shared tail rotates carry through the low sixteen bits.

EX_MRSHI:
    LD   HL,EX_MRIGH+2        ; Point at the multiplier high byte.
    LD   A,(HL)               ; Load it for an unsigned shift.
    SRL  A                    ; Shift in zero and expose bit 0 in carry.

;@ROUTINE IN A,HL OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the already-shifted high byte in A, then rotate the two lower bytes at
; HL-1 and HL-2 through carry. The arithmetic right-shift path also enters here.

EX_SRL16:
    LD   (HL),A               ; Store the shifted high byte.
    DEC  HL                   ; Move to the middle byte without changing carry.
    LD   A,(HL)               ; Load the middle byte.
    RR   A                    ; Shift through the high byte's outgoing bit.
    LD   (HL),A               ; Store the shifted middle byte.
    DEC  HL                   ; Move to the low byte without changing carry.
    LD   A,(HL)               ; Load the low byte.
    RR   A                    ; Complete the 24-bit right shift.
    LD   (HL),A               ; Store the shifted low byte.
    RET                       ; Return flags from the final low-byte rotation.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Compare the partial remainder with the divisor as unsigned 24-bit magnitudes,
; most-significant byte first. Carry means remainder is smaller.

EX_RALDI:
    LD   A,(EX_ACCUM+2)       ; Load the remainder high byte.
    LD   HL,EX_MRIGH+2        ; Point at the divisor high byte.
    CP   (HL)                 ; Compare the most-significant bytes.
    RET  NZ                   ; Their order decides unless they are equal.
    LD   A,(EX_ACCUM+1)       ; Load the remainder middle byte.
    DEC  HL                   ; Point at the divisor middle byte.
    CP   (HL)                 ; Compare the next-significant bytes.
    RET  NZ                   ; Their order decides unless they are equal.
    LD   A,(EX_ACCUM)         ; Load the remainder low byte.
    DEC  HL                   ; Point at the divisor low byte.
    CP   (HL)                 ; Complete the unsigned 24-bit comparison.
    RET                       ; Carry means remainder is smaller.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY
; Subtract the divisor magnitude from the partial remainder in place.

EX_RSDIV:
    LD   HL,EX_ACCUM          ; Point at the remainder low byte.
    LD   DE,EX_MRIGH          ; Point at the divisor low byte.
    LD   A,(DE)               ; Load the divisor low byte.
    LD   C,A                  ; Preserve it for memory-destination subtraction.
    LD   A,(HL)               ; Load the remainder low byte.
    SUB  C                    ; Subtract without incoming borrow.
    LD   (HL),A               ; Store the new remainder low byte.
    INC  HL                   ; Advance without changing borrow.
    INC  DE                   ; Advance the divisor pointer likewise.
    LD   A,(DE)               ; Load the divisor middle byte.
    LD   C,A                  ; Preserve it for subtraction.
    LD   A,(HL)               ; Load the remainder middle byte.
    SBC  A,C                  ; Subtract with low-byte borrow.
    LD   (HL),A               ; Store the new remainder middle byte.
    INC  HL                   ; Advance without changing borrow.
    INC  DE                   ; Advance the divisor pointer likewise.
    LD   A,(DE)               ; Load the divisor high byte.
    LD   C,A                  ; Preserve it for subtraction.
    LD   A,(HL)               ; Load the remainder high byte.
    SBC  A,C                  ; Complete the 24-bit subtraction.
    LD   (HL),A               ; Store the new remainder high byte.
    RET                       ; Return final subtraction flags.

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY
; Expand the resolved word in HL into EX_RVAL and clear both the 24-bit high
; byte and the deferred-state marker.

EX_SRW:
    LD   (EX_RVAL),HL         ; Store the resolved low sixteen bits.
    XOR  A                    ; Form zero for high byte and resolution state.
    LD   (EX_RVAL+2),A       ; Zero-extend the word to 24 bits.
    LD   (EX_RUNRE),A        ; Mark the result concrete.
    RET                      ; Return carry clear from XOR.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL
; Require a resolved 24-bit result in the final word domain. Positive values may
; reach $00FFFF; negative values must be sign-extended from $FF8000..$FFFFFF.

EX_REQW:
    LD   A,(EX_RVAL+2)       ; Load the 24-bit result's extension byte.
    OR   A                   ; Is it zero for a non-negative word?
    RET  Z                   ; Yes: $000000..$00FFFF is valid.
    INC  A                   ; Does $FF wrap to zero?
    JR   NZ,.RHERE           ; Other extensions are outside the word domain.
    LD   A,(EX_RVAL+1)       ; Inspect a negative result's middle byte.
    BIT  7,A                 ; Is bit 15 set for proper sign extension?
    RET  NZ                  ; Yes: $FF8000..$FFFFFF is valid.
.RHERE:                    ; Report a final result outside the word domain.
    LD   A,EX_SRANG          ; Select final word-range failure.
    JR   EX_FHERE            ; Anchor it at the current delimiter token.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require the 24-bit deferred addend to be exactly sign-extended from one byte:
; $000000..$00007F or $FFFF80..$FFFFFF.

EX_RADDE:
    LD   A,(EX_RVAL+2)       ; Load the deferred addend extension byte.
    OR   A                   ; Zero selects the non-negative range check.
    JR   Z,.APOSITIV         ; Validate $00 in both upper bytes.
    INC  A                   ; Does the extension equal $FF?
    JR   NZ,EX_ROPER         ; No: it cannot be an eight-bit sign extension.
    LD   A,(EX_RVAL+1)       ; Load the middle addend byte.
    INC  A                   ; Does it also equal $FF?
    JR   NZ,EX_ROPER         ; No: reject outside the signed-byte domain.
    LD   A,(EX_RVAL)         ; Load the candidate negative low byte.
    BIT  7,A                 ; Is it $80..$FF?
    RET  NZ                  ; Yes: the addend is correctly sign-extended.
    JR   EX_ROPER            ; Reject $FFFF00..$FFFF7F.
.APOSITIV:                 ; Validate the non-negative deferred-addend range.
    LD   A,(EX_RVAL+1)       ; Load the non-negative addend middle byte.
    OR   A                   ; Must it be zero?
    JR   NZ,EX_ROPER         ; Nonzero exceeds the signed-byte range.
    LD   A,(EX_RVAL)         ; Load the candidate positive low byte.
    BIT  7,A                 ; Is it $80 or above?
    JR   NZ,EX_ROPER         ; Yes: it is not a positive signed byte.
    OR   A                   ; Clear carry while preserving the addend byte.
    RET                      ; Accept $00..$7F.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Advance the tokenizer. A lexical failure carries the tokenizer's own source
; position rather than the expression's current operator or token position.

EX_NTOK:
    CALL TK_NEXT             ; Ask the tokenizer to publish the next record.
    RET  NC                  ; Return it unchanged on lexical success.
    LD   A,EX_SLEXI          ; Select the expression lexical category.
    JR   EX_FTOKE            ; Use the tokenizer's exact failure position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Report a numeric range error at the operator whose calculation failed.

EX_ROPER:
    LD   A,EX_SRANG          ; Select arithmetic/range failure.
    JR   EX_FOPER            ; Anchor it at the saved operator position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token's stored source position for primary, delimiter and
; capacity failures.

EX_FHERE:
    LD   HL,TK_REC+TK_POFF   ; Point at current token part and offset fields.
    JR   EX_FPOSI            ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the saved operator position for arithmetic and unsupported-form failures.

EX_FOPER:
    LD   HL,EX_OPART         ; Point at saved operator part and offset fields.
    JR   EX_FPOSI            ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the saved name position for symbol packing and lookup failures.

EX_FSYM:
    LD   HL,EX_SPART         ; Point at saved symbol part and offset fields.
    JR   EX_FPOSI            ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the tokenizer's independently recorded failure position for lexical errors.

EX_FTOKE:
    LD   HL,TK_EPART         ; Point at tokenizer failure part and offset fields.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy the contiguous part-and-offset triple at HL into the public expression
; error fields, preserve the status in A and set carry.

EX_FPOSI:
    PUSH BC                  ; Preserve caller BC across the three-byte copy.
    PUSH DE                  ; Preserve caller DE likewise.
    LD   DE,EX_EPART         ; Select the public expression error destination.
    LD   BC,3                ; Copy one part byte and one offset word.
    LDIR                     ; Publish the exact selected source position.
    POP  DE                  ; Restore caller DE.
    POP  BC                  ; Restore caller BC.
    SCF                      ; Mark expression failure while retaining status A.
    RET                      ; Return category and positioned diagnostic.
EX_RCEND:                  ; End the expression rule-code measurement range.
EX_CEND:                   ; End executable expression code and immutable tables.
EX_WBEG:                   ; Begin fixed expression workspace.

; Persistent state for one parse. EX_CADR gives '$' its statement address and
; EX_PSYM selects direct publication or caller-managed deferred publication.

EX_CADR: DW 0            ; Current address used when parsing '$'.
EX_PSYM: DB 0            ; Nonzero permits successful symbol publication.

; Current/right value record: signed 24-bit value or addend, deferred transform
; and six-byte exact packed key.

EX_RVAL: DS 3            ; Right/current 24-bit value or signed addend.
EX_RUNRE: DB 0           ; Concrete/plain/LOW/HIGH result state.
EX_RKEY: DS 6            ; Exact packed key for a deferred right result.

; Left value record loaded during binary reduction.

EX_LVAL: DS 3            ; Left 24-bit value or signed addend.
EX_LUNRE: DB 0           ; Left concrete/deferred transform state.
EX_LKEY: DS 6            ; Exact packed key for a deferred left operand.

; Current operator record and a spare copy used while precedence reduction loads
; older operators from the stack.

EX_OPER: DB 0            ; Current packed precedence/operation byte.
EX_OPART: DB 0           ; Current operator's source-part ordinal.
EX_OOFF: DW 0            ; Current operator's source-byte offset.
EX_INCOM: DS EX_OPERB    ; Saved incoming operator during reduction.

; Saved name diagnostics and nested symbol status. Multiply and divide reuse
; these bytes while reducing a concrete pair. Because the source position is not
; copied into a value-stack entry, a concrete subexpression evaluated after a
; deferred name can currently overwrite that name's later diagnostic anchor.

EX_SPART: DB 0           ; Saved symbol source-part ordinal.
EX_SOFF: DW 0            ; Saved symbol source-byte offset.
EX_SSTAT: DB 0           ; Nested symbol status for diagnostics.
EX_MCOUN EQU EX_SSTAT    ; Multiplication round count overlay.

; Bounded parser state. EX_EOP is one when the grammar requires a primary and
; zero when it requires an operator or delimiter.

EX_VDEPT: DB 0           ; Number of live value-stack entries.
EX_ODEPT: DB 0           ; Number of live operator-stack entries.
EX_PDEPT: DB 0           ; Open-parenthesis nesting depth.
EX_EOP: DB 0             ; Nonzero when the grammar expects a primary.

; Multiply and divide overlay the two popped operand-key slots with magnitudes,
; accumulator and quotient. Both popped operands are concrete on these paths, so
; their keys are dead. The sign fields also overlay the saved name position as
; described above.

EX_SLEF1 EQU EX_SPART     ; Saved left/dividend sign overlay.
EX_SRIG1 EQU EX_SOFF      ; Saved right/divisor sign overlay.
EX_SRES EQU EX_SOFF+1     ; Product/quotient sign overlay.
EX_DRMOD EQU EX_MCOUN     ; Quotient-versus-remainder selector overlay.
EX_MLEFT EQU EX_RKEY      ; Left operand magnitude overlay.
EX_MRIGH EQU EX_RKEY+3    ; Right operand magnitude overlay.
EX_ACCUM EQU EX_LKEY      ; Product/partial-remainder accumulator overlay.
EX_EPART EQU EX_ACCUM     ; Public error-part field overlay.
EX_EOFF EQU EX_ACCUM+1    ; Public error-offset field overlay.
EX_QUOTI EQU EX_LKEY+3    ; Division quotient overlay.

; Sixteen ten-byte value entries followed by sixteen four-byte operator entries.
; The complete fixed expression workspace is 263 bytes.

EX_VSTAC: DS EX_VALB*EX_VCAP ; Sixteen complete value records.
EX_OSTAC: DS EX_OPERB*EX_OCAP ; Sixteen positioned operator records.
EX_WEND:                   ; End fixed expression workspace.
