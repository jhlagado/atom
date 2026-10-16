.vIn: ; Validate ordinary or bare C-port input.

; IN r,(C), IN (C), or IN A,(n). Bare IN (C) has one parsed operand.

    LD   A,(IX+enOp0)                   ; Read the port marker or destination register.
    CP   enPortC                        ; Bare IN (C) stores the port class in slot zero.
    JR   Z,.vOneOp2                     ; Route that one-operand form separately.
    CALL enIsReg8                       ; Slot zero must be a byte register.
    JP   NC,.invalid                    ; Reject a non-register destination.
    CALL .twoOper                       ; Require the third operand slot to be empty.
    RET  C                              ; Propagate excess-operand failure.
    LD   A,(IX+enOp1)                   ; Read the source port class.
    CP   enPortC                        ; Check for the ED form using port C.
    JP   Z,enDone2                      ; IN r,(C) always occupies two bytes.
    CP   enImm8                         ; The other accepted port form is immediate.
    JP   NZ,.invalid                    ; Reject every other source-port class.
    LD   A,(IX+enOp0)                   ; Reload the destination for the immediate form.
    CP   enRegA                         ; IN A,(n) is the only immediate-port input.
    JP   .vNzBad2                       ; Return two bytes only when the test matched.
.vOneOp2: ; Require a sole operand and return length two.
    CALL .oneOper                       ; Require one operand only.
    RET  C                              ; Propagate the one-operand count failure.
    JP   enDone2                        ; These plain one-operand forms occupy two bytes.
.vOut: ; Validate immediate-port or C-port output.

; OUT (C),r, OUT (C),0, or OUT (n),A.

    CALL .twoOper                       ; Reject an unexpected third operand.
    RET  C                              ; Stop when the arity check fails.
    LD   A,(IX+enOp0)                   ; Read the output-port class.
    CP   enPortC                        ; Select the C-register port forms.
    JR   Z,.vOutC                       ; Validate the output byte separately.
    CP   enImm8                         ; Immediate ports use the other OUT form.
    JP   NZ,.invalid                    ; Reject every other port class.
    LD   A,(IX+enOp1)                   ; Read the value supplied to the immediate port.
    CP   enRegA                         ; OUT (n),A is the only immediate-port form.
    JP   .vNzBad2                       ; Return two bytes only when the test matched.
.vOutC: ; Accept a byte register or special zero for port C.
    LD   A,(IX+enOp1)                   ; Read the byte value sent to port C.
    CP   enZero                         ; Check the special OUT (C),0 encoding.
    JP   Z,enDone2                      ; The special zero form is two bytes.
    CALL enIsReg8                       ; Otherwise require an ordinary byte register.
.vCLen2: ; Return two bytes only when the predicate accepted.
    JP   C,enDone2                      ; Accepted register or pair forms use two bytes.
    JP   .invalid                       ; Reject a class outside the accepted set.
.vBit: ; Validate bit number, target and optional copy register.

; BIT/RES/SET use a bit class followed by register, (HL), or indexed
; memory. Indexed RES/SET may carry a third destination register; BIT may not.

    LD   A,(IX+enOp0)                   ; Read the enumerated bit-number class.
    CALL enIsBit                        ; Carry accepts only BIT0 through BIT7.
    JP   NC,.invalid                    ; Reject a non-bit operand.
    LD   A,(IX+enOp1)                   ; Read the register or memory target class.
    CALL enIsReg8                       ; Test for an ordinary byte register.
    JR   C,.vBPlain                     ; Register targets use the plain CB form.
    CP   enMemHL                        ; Check the unprefixed (HL) target.
    JR   Z,.vBPlain                     ; (HL) also uses the plain CB form.
    CALL enIsDisp                       ; Test for indexed memory with displacement.
    JP   NC,.invalid                    ; Reject targets outside these three forms.
    LD   A,(IX+enMnem)                  ; Distinguish BIT from RES and SET.
    CP   mneBit                         ; BIT cannot copy its result to another register.
    JR   Z,.vBitIdx                     ; Validate BIT's two-operand indexed form.
    LD   A,(IX+enOp2)                   ; Read the optional RES/SET result register.
    JR   .vOptReg4                      ; Optional byte register; length four.
.vBitIdx: ; Reject a third operand for indexed BIT.
    CALL .twoOper                       ; Require BIT's third operand slot to be empty.
    RET  C                              ; Propagate the arity failure.
    JP   enDone4                        ; Indexed CB operations occupy four bytes.
.vBPlain: ; Require two operands for unindexed bit operations.
    CALL .twoOper                       ; Plain forms take two operands.
    RET  C                              ; Reject a supplied third operand.
    JP   enDone2                        ; CB prefix and operation byte make two bytes.
.vRotate: ; Validate a rotate/shift target and optional copy register.

; Rotate/shift takes a register, (HL), or indexed memory. Indexed forms
; may optionally copy the result to an ordinary register.

    LD   A,(IX+enOp0)                   ; Read the register or memory target class.
    CALL enIsReg8                       ; Test for an ordinary byte register.
    JR   C,.vRPlain                     ; Register targets use the plain CB form.
    CP   enMemHL                        ; Check the unprefixed (HL) memory form.
    JR   Z,.vRPlain                     ; (HL) uses the same two-byte CB form.
    CALL enIsDisp                       ; Otherwise require indexed memory.
    JP   NC,.invalid                    ; Reject all other target classes.
    CALL .twoOper                       ; Indexed forms allow at most two operands.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+enOp1)                   ; Read the optional result-register class.
.vOptReg4: ; Accept an absent or ordinary byte copy register.
    CP   enNone                         ; The sentinel means no result-register copy.
    JP   Z,enDone4                      ; Indexed operation still takes four bytes.
    CALL enIsReg8                       ; Otherwise require a byte-register destination.
    JP   C,enDone4                      ; A valid copy form also takes four bytes.
    JP   .invalid                       ; Reject an invalid optional destination.
.vRPlain: ; Check the sole unindexed rotate/shift operand.
    JP   .vOneOp2                       ; Reuse the one-target arity and length check.
.vAlu: ; Distinguish canonical byte ALU from pair arithmetic.

; One-operand ALU forms cover byte register, memory, or immediate. The parser
; has already removed an explicit A alias. Two-operand records are the 16-bit
; ADD/ADC/SBC families and retain their explicit destination.

    LD   A,(IX+enOp1)                   ; An empty second slot selects one-operand ALU.
    CP   enNone                         ; Check whether the parsed A alias was omitted.
    JR   NZ,.vAlu16                     ; Two slots select the 16-bit arithmetic forms.
    CALL .oneOper                       ; Require only operand zero for the byte form.
    RET  C                              ; Reject an unexpected second or third operand.
    LD   A,(IX+enOp0)                   ; Read the byte register or memory class.
    CALL enIsReg8                       ; Carry accepts an ordinary byte register.
    JP   C,enDone1                      ; Register ALU forms use one opcode byte.
    CP   enMemHL                        ; Check the unprefixed (HL) memory operand.
    JP   Z,enDone1                      ; Its ALU opcode also occupies one byte.
    CP   enImm8                         ; Check for an immediate byte operand.
    JP   Z,enDone2                      ; Immediate ALU forms add one data byte.
    CALL enIsHalf                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,enDone2                      ; Index halves add a DD/FD prefix.
    LD   A,(IX+enOp0)                   ; Reload the class for the indexed-memory test.
    CALL enIsDisp                       ; Test for (IX/IY+d).
    JP   .vCLen3                        ; Return length three if valid, else reject.
.vAlu16: ; Require two operands for ADD/ADC/SBC pair forms.
    CALL .twoOper                       ; Permit two operands but reject a third.
    RET  C                              ; Propagate the operand-count failure.
    LD   A,(IX+enMnem)                  ; Select the 16-bit arithmetic mnemonic.
    CP   mneAdd                         ; ADD has HL, IX and IY destination forms.
    JR   Z,.vAdd16                      ; Route it to the destination-specific checks.
    CP   mneAdc                         ; ADC is restricted to HL,rr.
    JR   Z,.vAdcSbc                     ; Share its destination check with SBC.
    CP   mneSbc                         ; The remaining accepted family is SBC.
    JP   NZ,.invalid                    ; Reject any other two-operand ALU mnemonic.
.vAdcSbc: ; Require HL destination and an ordinary source pair.
    LD   A,(IX+enOp0)                   ; Read the destination of ADC/SBC HL,rr.
    CP   enRegHL                        ; These ED forms require HL as destination.
    JP   NZ,.invalid                    ; Reject IX, IY or any other destination.
    LD   A,(IX+enOp1)                   ; Read the source pair class.
    CALL enIsPair                       ; Carry accepts BC, DE, HL or SP.
    JP   .vCLen2                        ; Valid ED pair forms are two bytes.
.vAdd16: ; Validate the destination pair for ADD.
    LD   A,(IX+enOp0)                   ; Read ADD's 16-bit destination class.
    CP   enRegHL                        ; HL accepts the ordinary pair encodings.
    JR   Z,.vAddHl                      ; Validate BC, DE, HL or SP as its source.
    CP   enRegIX                        ; IX accepts BC, DE, SP or IX.
    JR   Z,.vAddIxIy                    ; Check those source classes together.
    CP   enRegIY                        ; IY follows the same indexed-pair rules.
    JP   NZ,.invalid                    ; Reject all other ADD pair destinations.
.vAddIxIy: ; Accept BC, DE, SP or the matching index pair.
    LD   B,A                            ; Preserve IX or IY while testing the source.
    LD   A,(IX+enOp1)                   ; Read the source pair class.
    CP   enRegBC                        ; BC is valid with either index destination.
    JP   Z,enDone2                      ; Indexed ADD emits prefix and opcode.
    CP   enRegDE                        ; DE is also valid with IX or IY.
    JP   Z,enDone2                      ; Its indexed form has the same length.
    CP   enRegSP                        ; SP is the final shared pair source.
    JP   Z,enDone2                      ; It also produces a two-byte instruction.
    CP   B                              ; The matching IX,IX or IY,IY form is valid.
    JP   .vZLen2                        ; Return two bytes on a match, else reject.
.vAddHl: ; Accept an ordinary source pair for ADD HL.
    LD   A,(IX+enOp1)                   ; Read the source pair for ADD HL,rr.
    CALL enIsPair                       ; Carry accepts BC, DE, HL or SP.
    JP   C,enDone1                      ; The unprefixed ADD form is one byte.
    JP   .invalid                       ; Reject non-pair sources.
.vJp: ; Validate absolute, indirect or conditional JP.

; JP accepts nn, (HL), (IX), (IY), or a condition followed by nn.

    LD   A,(IX+enOp1)                   ; An empty second slot selects unconditional JP.
    CP   enNone                         ; Distinguish it from JP cc,nn.
    JR   NZ,.vJpCc                      ; Route the conditional form to its own checks.
    CALL .oneOper                       ; Require one operand at most.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+enOp0)                   ; Read the absolute or indirect target class.
    CP   enImm16                        ; Check for JP nn.
    JP   Z,enDone3                      ; Opcode plus address occupies three bytes.
    CP   enMemHL                        ; Check for JP (HL).
    JP   Z,enDone1                      ; The HL form is a single opcode.
    CP   enMemIX                        ; Check for JP (IX).
    JP   Z,enDone2                      ; Indexed indirect adds one prefix.
    CP   enMemIY                        ; Check for JP (IY).
    JP   .vZLen2                        ; Return two bytes only for that final match.
.vJpCc: ; Require an eight-way condition and absolute target.
    CALL .twoOper                       ; Allow condition and target only.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+enOp0)                   ; Read the condition class.
    CALL enIsCond                       ; Carry accepts one of the eight JP conditions.
    JR   NC,.invalid                    ; Reject an invalid condition first.
    LD   A,(IX+enOp1)                   ; Read the conditional target class.
.vTarget3: ; Require an immediate word target and return length three.
    CP   enImm16                        ; Conditional JP/CALL requires an absolute word.
    JP   Z,enDone3                      ; Opcode plus target address takes three bytes.
    JR   .invalid                       ; Reject any other conditional target class.
.vCall: ; Distinguish plain CALL from a conditional form.
    LD   A,(IX+enOp1)                   ; Empty slot selects unconditional CALL.
    CP   enNone                         ; Distinguish it from CALL cc,nn.
    JR   NZ,.vCallCc                    ; Route a supplied condition to shared checks.
    CALL .oneOper                       ; Require one target and no trailing operands.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+enOp0)                   ; Load the unconditional target class.
    JR   .vTarget3                      ; Reuse the absolute-word length check.
.vCallCc: ; Reuse JP's condition and absolute-target checks.
    JR   .vJpCc                         ; CALL shares JP's condition and target rules.
.vJr: ; Distinguish plain JR from its restricted conditions.

; JR has an unconditional relative form and only the four hardware-supported
; conditions NZ, Z, NC and C.

    LD   A,(IX+enOp1)                   ; An empty second slot selects unconditional JR.
    CP   enNone                         ; Distinguish it from JR cc,e.
    JR   NZ,.vJrCc                      ; Route a condition and target to shared checks.
    CALL .oneOper                       ; Require one relative target at most.
    RET  C                              ; Propagate the arity failure.
    JR   .vRelOper                      ; Check its relative-operand class.
.vJrCc: ; Require a JR-supported condition and relative target.
    CALL .twoOper                       ; Allow condition and target, but no third slot.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+enOp0)                   ; Read the condition class.
    CALL enIsJrCC                       ; Carry accepts NZ, Z, NC or C for JR.
    JR   NC,.invalid                    ; Reject conditions unsupported by JR.
    LD   A,(IX+enOp1)                   ; Read the relative target class.
    CP   enRel8                         ; JR cc requires a relative displacement.
    JP   Z,enDone2                      ; Opcode and displacement occupy two bytes.
    JR   .invalid                       ; Reject every other target class.
.vDjnz: ; Require a sole relative target for DJNZ.
    CALL .oneOper                       ; DJNZ accepts one relative target only.
    RET  C                              ; Propagate any extra-operand failure.
.vRelOper: ; Require the relative-byte class and return length two.
    LD   A,(IX+enOp0)                   ; Read the unconditional relative target class.
    CP   enRel8                         ; Require the parser's relative-byte class.
    JP   Z,enDone2                      ; JR e and DJNZ e each take two bytes.
    JR   .invalid                       ; Reject non-relative operands.
.vdTable: ; Validator addresses in mnemonic-family order.

; Validator family table selected by mneDisp.

    DW   .vCore,.vRet,.vEx              ; Core, RET and EX validator entries.
    DW   .vIm,.vRst,.vIncDec            ; IM, RST and INC/DEC validator entries.
    DW   .vStack,.vLd,.vIn              ; Stack, LD and IN validator entries.
    DW   .vOut,.vBit,.vRotate           ; OUT, bit and rotate/shift entries.
    DW   .vAlu,.vJp,.vCall              ; ALU, JP and CALL validator entries.
    DW   .vJr,.vDjnz                    ; Relative-branch validator entries.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; All invalid forms return A=0 with carry set and publish no output.

.invalid: ; Return length zero and carry set for an invalid form.
    XOR  A                              ; Clear the length returned for an invalid form.
    SCF                                 ; Mark validation failure in carry.
    RET                                 ; Return without publishing encoded bytes.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Cascading operand-count checks: no operands, at most one, or at most two.

.noOper: ; Require slot zero empty before checking remaining slots.
    LD   A,(IX+enOp0)                   ; Read the first operand slot.
    CP   enNone                         ; The sentinel means that the slot is empty.
    JR   NZ,.arityBad                   ; Reject any operand in this no-operand form.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slots one and two to be empty, allowing at most one operand.

.oneOper: ; Require slot one empty before checking slot two.
    LD   A,(IX+enOp1)                   ; Read the second operand slot.
    CP   enNone                         ; A one-operand form leaves this slot empty.
    JR   NZ,.arityBad                   ; Reject a second operand when one is disallowed.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slot two to be empty, allowing at most two operands.

.twoOper: ; Require slot two empty for forms with at most two operands.
    LD   A,(IX+enOp2)                   ; Read the third and final operand slot.
    CP   enNone                         ; Require the third operand slot to be empty.
    JR   NZ,.arityBad                   ; Reject a supplied third operand.
    OR   A                              ; Clear carry to report valid operand count.
    RET                                 ; Return the successful arity check.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common invalid-form result with carry set.

.arityBad: ; Return the common invalid-form result for excess operands.
    XOR  A                              ; Clear the length for an invalid operand count.
    SCF                                 ; Mark the arity check as failed.
    RET                                 ; Return the shared invalid-form result.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Carry means byte register B..L or A. Class 6 is (HL), so it
; is excluded from this predicate despite sharing the hardware field range.

enIsReg8: ; Test byte-register classes while excluding (HL).
    CP   enMemHL                        ; Values below class six are B through L.
    RET  C                              ; Accept those ordinary register classes.
    CP   enRegA                         ; Check the remaining ordinary register class.
    JR   Z,enYes                        ; Accept A, but not the (HL) class at six.
    CP   A                              ; Clear carry for every class not accepted above.
    RET                                 ; Return the predicate result in carry.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry set means BC, DE, HL or SP.

enIsPair: ; Test the contiguous BC..SP pair classes.
    CP   enRegBC                        ; Reject classes below the first register pair.
    JR   C,enNo                         ; Values below BC are not 16-bit pairs.
    CP   enRegSP+1                      ; Compare against the exclusive pair upper bound.
    RET                                 ; Carry accepts BC, DE, HL and SP.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Preserve A while testing IXH/IXL/IYH/IYL through their shared bit pattern.

enIsHalf: ; Test index-half classes while preserving A.
    PUSH BC                             ; Preserve BC while C holds the original class.
    LD   C,A                            ; Save the operand class before masking A.
    AND  $F6                            ; Map all four index halves to one bit pattern.
    CP   enRegIXH                       ; Compare with the shared IXH pattern.
    LD   A,C                            ; Restore the operand class for the caller.
    POP  BC                             ; Restore the caller's BC value.
    JR   Z,enYes                        ; Accept when the reduced pattern matched.
    JR   enNo                           ; Return carry clear for every other class.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry set means displacement-bearing (IX+d) or (IY+d).

enIsDisp: ; Test displacement-bearing IX/IY memory classes.
    CP   enDispIX                       ; Reject classes below indexed IX memory.
    JR   C,enNo                         ; Only IX+d and IY+d belong to this range.
    CP   enDispIY+1                     ; Compare against the exclusive IY+d bound.
    RET                                 ; Carry is set only for the two indexed classes.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; All eight condition classes, in hardware field order.

enIsCond: ; Test all eight hardware condition classes.
    CP   enCondNZ                       ; Reject classes before the condition range.
    JR   C,enNo                         ; NZ is the first encoded condition class.
    CP   enCondM+1                      ; Compare against the exclusive condition bound.
    RET                                 ; Carry accepts all eight Z80 conditions.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; The four condition classes implemented by JR.

enIsJrCC: ; Test the four conditions implemented by JR.
    CP   enCondNZ                       ; Reject classes before the JR condition range.
    JR   C,enNo                         ; NZ is the first condition supported by JR.
    CP   enCondC+1                      ; Stop after C, the last JR condition class.
    RET                                 ; Carry accepts NZ, Z, NC and C.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Enumerated bit-number classes BIT0..BIT7.

enIsBit: ; Test enumerated bit-number classes 0..7.
    CP   enBit0                         ; Reject classes below enumerated bit zero.
    JR   C,enNo                         ; Only the eight bit-number classes are accepted.
    CP   enBit7+1                       ; Compare against the exclusive bit-number bound.
    RET                                 ; Carry accepts BIT0 through BIT7.

;@ROUTINE IN A OUT CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common predicate result for a value outside the accepted range.

enNo: ; Return a rejected predicate with carry clear.
    CP   A                              ; Compare A with itself to clear carry.
    RET                                 ; Return the predicate's rejected result.

;@ROUTINE OUT CARRY CLOBBERS HALFCARRY
; Return the common predicate result for a value inside the accepted range.

enYes: ; Return an accepted predicate with carry set.
    SCF                                 ; Set carry to mark the predicate as successful.
    RET                                 ; Return the accepted-class result.
enVetEnd: ; End mnemonic dispatch and form-validation code.
