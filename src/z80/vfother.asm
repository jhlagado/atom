.VIN: ; Validate ordinary or bare C-port input.

; IN r,(C), IN (C), or IN A,(n). Bare IN (C) has one parsed operand.

    LD   A,(IX+EN_OP0)                  ; Read the port marker or destination register.
    CP   EN_PORTC                       ; Bare IN (C) stores the port class in slot zero.
    JR   Z,.VONEOP2                     ; Route that one-operand form separately.
    CALL EN_IR8                         ; Slot zero must be a byte register.
    JP   NC,.INVALID                    ; Reject a non-register destination.
    CALL .TWOOPER                       ; Require the third operand slot to be empty.
    RET  C                              ; Propagate excess-operand failure.
    LD   A,(IX+EN_OP1)                  ; Read the source port class.
    CP   EN_PORTC                       ; Check for the ED form using port C.
    JP   Z,EN_D2                        ; IN r,(C) always occupies two bytes.
    CP   EN_IMM8                        ; The other accepted port form is immediate.
    JP   NZ,.INVALID                    ; Reject every other source-port class.
    LD   A,(IX+EN_OP0)                  ; Reload the destination for the immediate form.
    CP   EN_A                           ; IN A,(n) is the only immediate-port input.
    JP   .VNZBAD2                       ; Return two bytes only when the test matched.
.VONEOP2: ; Require a sole operand and return length two.
    CALL .ONEOPER                       ; Require one operand only.
    RET  C                              ; Propagate the one-operand count failure.
    JP   EN_D2                          ; These plain one-operand forms occupy two bytes.
.VOUT: ; Validate immediate-port or C-port output.

; OUT (C),r, OUT (C),0, or OUT (n),A.

    CALL .TWOOPER                       ; Reject an unexpected third operand.
    RET  C                              ; Stop when the arity check fails.
    LD   A,(IX+EN_OP0)                  ; Read the output-port class.
    CP   EN_PORTC                       ; Select the C-register port forms.
    JR   Z,.VOUTC                       ; Validate the output byte separately.
    CP   EN_IMM8                        ; Immediate ports use the other OUT form.
    JP   NZ,.INVALID                    ; Reject every other port class.
    LD   A,(IX+EN_OP1)                  ; Read the value supplied to the immediate port.
    CP   EN_A                           ; OUT (n),A is the only immediate-port form.
    JP   .VNZBAD2                       ; Return two bytes only when the test matched.
.VOUTC: ; Accept a byte register or special zero for port C.
    LD   A,(IX+EN_OP1)                  ; Read the byte value sent to port C.
    CP   EN_ZERO                        ; Check the special OUT (C),0 encoding.
    JP   Z,EN_D2                        ; The special zero form is two bytes.
    CALL EN_IR8                         ; Otherwise require an ordinary byte register.
.VCLEN2: ; Return two bytes only when the predicate accepted.
    JP   C,EN_D2                        ; Accepted register or pair forms use two bytes.
    JP   .INVALID                       ; Reject a class outside the accepted set.
.VBIT: ; Validate bit number, target and optional copy register.

; BIT/RES/SET use a bit class followed by register, (HL), or indexed
; memory. Indexed RES/SET may carry a third destination register; BIT may not.

    LD   A,(IX+EN_OP0)                  ; Read the enumerated bit-number class.
    CALL EN_IBIT                        ; Carry accepts only BIT0 through BIT7.
    JP   NC,.INVALID                    ; Reject a non-bit operand.
    LD   A,(IX+EN_OP1)                  ; Read the register or memory target class.
    CALL EN_IR8                         ; Test for an ordinary byte register.
    JR   C,.VBPLAIN                     ; Register targets use the plain CB form.
    CP   EN_MEMHL                       ; Check the unprefixed (HL) target.
    JR   Z,.VBPLAIN                     ; (HL) also uses the plain CB form.
    CALL EN_IDISP                       ; Test for indexed memory with displacement.
    JP   NC,.INVALID                    ; Reject targets outside these three forms.
    LD   A,(IX+EN_MNEM)                 ; Distinguish BIT from RES and SET.
    CP   AT_MBIT                        ; BIT cannot copy its result to another register.
    JR   Z,.VBITIDX                     ; Validate BIT's two-operand indexed form.
    LD   A,(IX+EN_OP2)                  ; Read the optional RES/SET result register.
    JR   .VOPTREG4                      ; Optional byte register; length four.
.VBITIDX: ; Reject a third operand for indexed BIT.
    CALL .TWOOPER                       ; Require BIT's third operand slot to be empty.
    RET  C                              ; Propagate the arity failure.
    JP   EN_D4                          ; Indexed CB operations occupy four bytes.
.VBPLAIN: ; Require two operands for unindexed bit operations.
    CALL .TWOOPER                       ; Plain forms take two operands.
    RET  C                              ; Reject a supplied third operand.
    JP   EN_D2                          ; CB prefix and operation byte make two bytes.
.VROTATE: ; Validate a rotate/shift target and optional copy register.

; Rotate/shift takes a register, (HL), or indexed memory. Indexed forms
; may optionally copy the result to an ordinary register.

    LD   A,(IX+EN_OP0)                  ; Read the register or memory target class.
    CALL EN_IR8                         ; Test for an ordinary byte register.
    JR   C,.VRPLAIN                     ; Register targets use the plain CB form.
    CP   EN_MEMHL                       ; Check the unprefixed (HL) memory form.
    JR   Z,.VRPLAIN                     ; (HL) uses the same two-byte CB form.
    CALL EN_IDISP                       ; Otherwise require indexed memory.
    JP   NC,.INVALID                    ; Reject all other target classes.
    CALL .TWOOPER                       ; Indexed forms allow at most two operands.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+EN_OP1)                  ; Read the optional result-register class.
.VOPTREG4: ; Accept an absent or ordinary byte copy register.
    CP   EN_NONE                        ; The sentinel means no result-register copy.
    JP   Z,EN_D4                        ; Indexed operation still takes four bytes.
    CALL EN_IR8                         ; Otherwise require a byte-register destination.
    JP   C,EN_D4                        ; A valid copy form also takes four bytes.
    JP   .INVALID                       ; Reject an invalid optional destination.
.VRPLAIN: ; Check the sole unindexed rotate/shift operand.
    JP   .VONEOP2                       ; Reuse the one-target arity and length check.
.VALU: ; Distinguish canonical byte ALU from pair arithmetic.

; One-operand ALU forms cover byte register, memory, or immediate. The parser
; has already removed an explicit A alias. Two-operand records are the 16-bit
; ADD/ADC/SBC families and retain their explicit destination.

    LD   A,(IX+EN_OP1)                  ; An empty second slot selects one-operand ALU.
    CP   EN_NONE                        ; Check whether the parsed A alias was omitted.
    JR   NZ,.VALU16                     ; Two slots select the 16-bit arithmetic forms.
    CALL .ONEOPER                       ; Require only operand zero for the byte form.
    RET  C                              ; Reject an unexpected second or third operand.
    LD   A,(IX+EN_OP0)                  ; Read the byte register or memory class.
    CALL EN_IR8                         ; Carry accepts an ordinary byte register.
    JP   C,EN_D1                        ; Register ALU forms use one opcode byte.
    CP   EN_MEMHL                       ; Check the unprefixed (HL) memory operand.
    JP   Z,EN_D1                        ; Its ALU opcode also occupies one byte.
    CP   EN_IMM8                        ; Check for an immediate byte operand.
    JP   Z,EN_D2                        ; Immediate ALU forms add one data byte.
    CALL EN_IHALF                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,EN_D2                        ; Index halves add a DD/FD prefix.
    LD   A,(IX+EN_OP0)                  ; Reload the class for the indexed-memory test.
    CALL EN_IDISP                       ; Test for (IX/IY+d).
    JP   .VCLEN3                        ; Return length three if valid, else reject.
.VALU16: ; Require two operands for ADD/ADC/SBC pair forms.
    CALL .TWOOPER                       ; Permit two operands but reject a third.
    RET  C                              ; Propagate the operand-count failure.
    LD   A,(IX+EN_MNEM)                 ; Select the 16-bit arithmetic mnemonic.
    CP   AT_MADD                        ; ADD has HL, IX and IY destination forms.
    JR   Z,.VADD16                      ; Route it to the destination-specific checks.
    CP   AT_MADC                        ; ADC is restricted to HL,rr.
    JR   Z,.VADCSBC                     ; Share its destination check with SBC.
    CP   AT_MSBC                        ; The remaining accepted family is SBC.
    JP   NZ,.INVALID                    ; Reject any other two-operand ALU mnemonic.
.VADCSBC: ; Require HL destination and an ordinary source pair.
    LD   A,(IX+EN_OP0)                  ; Read the destination of ADC/SBC HL,rr.
    CP   EN_HL                          ; These ED forms require HL as destination.
    JP   NZ,.INVALID                    ; Reject IX, IY or any other destination.
    LD   A,(IX+EN_OP1)                  ; Read the source pair class.
    CALL EN_IR16                        ; Carry accepts BC, DE, HL or SP.
    JP   .VCLEN2                        ; Valid ED pair forms are two bytes.
.VADD16: ; Validate the destination pair for ADD.
    LD   A,(IX+EN_OP0)                  ; Read ADD's 16-bit destination class.
    CP   EN_HL                          ; HL accepts the ordinary pair encodings.
    JR   Z,.VADDHL                      ; Validate BC, DE, HL or SP as its source.
    CP   EN_IX                          ; IX accepts BC, DE, SP or IX.
    JR   Z,.VADDIXIY                    ; Check those source classes together.
    CP   EN_IY                          ; IY follows the same indexed-pair rules.
    JP   NZ,.INVALID                    ; Reject all other ADD pair destinations.
.VADDIXIY: ; Accept BC, DE, SP or the matching index pair.
    LD   B,A                            ; Preserve IX or IY while testing the source.
    LD   A,(IX+EN_OP1)                  ; Read the source pair class.
    CP   EN_BC                          ; BC is valid with either index destination.
    JP   Z,EN_D2                        ; Indexed ADD emits prefix and opcode.
    CP   EN_DE                          ; DE is also valid with IX or IY.
    JP   Z,EN_D2                        ; Its indexed form has the same length.
    CP   EN_SP                          ; SP is the final shared pair source.
    JP   Z,EN_D2                        ; It also produces a two-byte instruction.
    CP   B                              ; The matching IX,IX or IY,IY form is valid.
    JP   .VZLEN2                        ; Return two bytes on a match, else reject.
.VADDHL: ; Accept an ordinary source pair for ADD HL.
    LD   A,(IX+EN_OP1)                  ; Read the source pair for ADD HL,rr.
    CALL EN_IR16                        ; Carry accepts BC, DE, HL or SP.
    JP   C,EN_D1                        ; The unprefixed ADD form is one byte.
    JP   .INVALID                       ; Reject non-pair sources.
.VJP: ; Validate absolute, indirect or conditional JP.

; JP accepts nn, (HL), (IX), (IY), or a condition followed by nn.

    LD   A,(IX+EN_OP1)                  ; An empty second slot selects unconditional JP.
    CP   EN_NONE                        ; Distinguish it from JP cc,nn.
    JR   NZ,.VJPCC                      ; Route the conditional form to its own checks.
    CALL .ONEOPER                       ; Require one operand at most.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+EN_OP0)                  ; Read the absolute or indirect target class.
    CP   EN_IMM16                       ; Check for JP nn.
    JP   Z,EN_D3                        ; Opcode plus address occupies three bytes.
    CP   EN_MEMHL                       ; Check for JP (HL).
    JP   Z,EN_D1                        ; The HL form is a single opcode.
    CP   EN_MEMIX                       ; Check for JP (IX).
    JP   Z,EN_D2                        ; Indexed indirect adds one prefix.
    CP   EN_MEMIY                       ; Check for JP (IY).
    JP   .VZLEN2                        ; Return two bytes only for that final match.
.VJPCC: ; Require an eight-way condition and absolute target.
    CALL .TWOOPER                       ; Allow condition and target only.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+EN_OP0)                  ; Read the condition class.
    CALL EN_ICOND                       ; Carry accepts one of the eight JP conditions.
    JR   NC,.INVALID                    ; Reject an invalid condition first.
    LD   A,(IX+EN_OP1)                  ; Read the conditional target class.
.VTARGET3: ; Require an immediate word target and return length three.
    CP   EN_IMM16                       ; Conditional JP/CALL requires an absolute word.
    JP   Z,EN_D3                        ; Opcode plus target address takes three bytes.
    JR   .INVALID                       ; Reject any other conditional target class.
.VCALL: ; Distinguish plain CALL from a conditional form.
    LD   A,(IX+EN_OP1)                  ; Empty slot selects unconditional CALL.
    CP   EN_NONE                        ; Distinguish it from CALL cc,nn.
    JR   NZ,.VCALLCC                    ; Route a supplied condition to shared checks.
    CALL .ONEOPER                       ; Require one target and no trailing operands.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+EN_OP0)                  ; Load the unconditional target class.
    JR   .VTARGET3                      ; Reuse the absolute-word length check.
.VCALLCC: ; Reuse JP's condition and absolute-target checks.
    JR   .VJPCC                         ; CALL shares JP's condition and target rules.
.VJR: ; Distinguish plain JR from its restricted conditions.

; JR has an unconditional relative form and only the four hardware-supported
; conditions NZ, Z, NC and C.

    LD   A,(IX+EN_OP1)                  ; An empty second slot selects unconditional JR.
    CP   EN_NONE                        ; Distinguish it from JR cc,e.
    JR   NZ,.VJRCC                      ; Route a condition and target to shared checks.
    CALL .ONEOPER                       ; Require one relative target at most.
    RET  C                              ; Propagate the arity failure.
    JR   .VRELOPER                      ; Check its relative-operand class.
.VJRCC: ; Require a JR-supported condition and relative target.
    CALL .TWOOPER                       ; Allow condition and target, but no third slot.
    RET  C                              ; Propagate the arity failure.
    LD   A,(IX+EN_OP0)                  ; Read the condition class.
    CALL EN_IJRCC                       ; Carry accepts NZ, Z, NC or C for JR.
    JR   NC,.INVALID                    ; Reject conditions unsupported by JR.
    LD   A,(IX+EN_OP1)                  ; Read the relative target class.
    CP   EN_REL8                        ; JR cc requires a relative displacement.
    JP   Z,EN_D2                        ; Opcode and displacement occupy two bytes.
    JR   .INVALID                       ; Reject every other target class.
.VDJNZ: ; Require a sole relative target for DJNZ.
    CALL .ONEOPER                       ; DJNZ accepts one relative target only.
    RET  C                              ; Propagate any extra-operand failure.
.VRELOPER: ; Require the relative-byte class and return length two.
    LD   A,(IX+EN_OP0)                  ; Read the unconditional relative target class.
    CP   EN_REL8                        ; Require the parser's relative-byte class.
    JP   Z,EN_D2                        ; JR e and DJNZ e each take two bytes.
    JR   .INVALID                       ; Reject non-relative operands.
.VDTABLE: ; Validator addresses in mnemonic-family order.

; Validator family table selected by AT_DMNEM.

    DW   .VCORE,.VRET,.VEX              ; Core, RET and EX validator entries.
    DW   .VIM,.VRST,.VINCDEC            ; IM, RST and INC/DEC validator entries.
    DW   .VSTACK,.VLD,.VIN              ; Stack, LD and IN validator entries.
    DW   .VOUT,.VBIT,.VROTATE           ; OUT, bit and rotate/shift entries.
    DW   .VALU,.VJP,.VCALL              ; ALU, JP and CALL validator entries.
    DW   .VJR,.VDJNZ                    ; Relative-branch validator entries.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; All invalid forms return A=0 with carry set and publish no output.

.INVALID: ; Return length zero and carry set for an invalid form.
    XOR  A                              ; Clear the length returned for an invalid form.
    SCF                                 ; Mark validation failure in carry.
    RET                                 ; Return without publishing encoded bytes.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Cascading operand-count checks: no operands, at most one, or at most two.

.NOOPER: ; Require slot zero empty before checking remaining slots.
    LD   A,(IX+EN_OP0)                  ; Read the first operand slot.
    CP   EN_NONE                        ; The sentinel means that the slot is empty.
    JR   NZ,.ARITYBAD                   ; Reject any operand in this no-operand form.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slots one and two to be empty, allowing at most one operand.

.ONEOPER: ; Require slot one empty before checking slot two.
    LD   A,(IX+EN_OP1)                  ; Read the second operand slot.
    CP   EN_NONE                        ; A one-operand form leaves this slot empty.
    JR   NZ,.ARITYBAD                   ; Reject a second operand when one is disallowed.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slot two to be empty, allowing at most two operands.

.TWOOPER: ; Require slot two empty for forms with at most two operands.
    LD   A,(IX+EN_OP2)                  ; Read the third and final operand slot.
    CP   EN_NONE                        ; Require the third operand slot to be empty.
    JR   NZ,.ARITYBAD                   ; Reject a supplied third operand.
    OR   A                              ; Clear carry to report valid operand count.
    RET                                 ; Return the successful arity check.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common invalid-form result with carry set.

.ARITYBAD: ; Return the common invalid-form result for excess operands.
    XOR  A                              ; Clear the length for an invalid operand count.
    SCF                                 ; Mark the arity check as failed.
    RET                                 ; Return the shared invalid-form result.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Carry means byte register B..L or A. Class 6 is (HL), so it
; is excluded from this predicate despite sharing the hardware field range.

EN_IR8: ; Test byte-register classes while excluding (HL).
    CP   EN_MEMHL                       ; Values below class six are B through L.
    RET  C                              ; Accept those ordinary register classes.
    CP   EN_A                           ; Check the remaining ordinary register class.
    JR   Z,AT_YES                       ; Accept A, but not the (HL) class at six.
    CP   A                              ; Clear carry for every class not accepted above.
    RET                                 ; Return the predicate result in carry.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry set means BC, DE, HL or SP.

EN_IR16: ; Test the contiguous BC..SP pair classes.
    CP   EN_BC                          ; Reject classes below the first register pair.
    JR   C,AT_NO                        ; Values below BC are not 16-bit pairs.
    CP   EN_SP+1                        ; Compare against the exclusive pair upper bound.
    RET                                 ; Carry accepts BC, DE, HL and SP.

;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Preserve A while testing IXH/IXL/IYH/IYL through their shared bit pattern.

EN_IHALF: ; Test index-half classes while preserving A.
    PUSH BC                             ; Preserve BC while C holds the original class.
    LD   C,A                            ; Save the operand class before masking A.
    AND  $F6                            ; Map all four index halves to one bit pattern.
    CP   EN_IXH                         ; Compare with the shared IXH pattern.
    LD   A,C                            ; Restore the operand class for the caller.
    POP  BC                             ; Restore the caller's BC value.
    JR   Z,AT_YES                       ; Accept when the reduced pattern matched.
    JR   AT_NO                          ; Return carry clear for every other class.

;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Carry set means displacement-bearing (IX+d) or (IY+d).

EN_IDISP: ; Test displacement-bearing IX/IY memory classes.
    CP   EN_IIX                         ; Reject classes below indexed IX memory.
    JR   C,AT_NO                        ; Only IX+d and IY+d belong to this range.
    CP   EN_IIY+1                       ; Compare against the exclusive IY+d bound.
    RET                                 ; Carry is set only for the two indexed classes.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; All eight condition classes, in hardware field order.

EN_ICOND: ; Test all eight hardware condition classes.
    CP   EN_NZ                          ; Reject classes before the condition range.
    JR   C,AT_NO                        ; NZ is the first encoded condition class.
    CP   EN_M+1                         ; Compare against the exclusive condition bound.
    RET                                 ; Carry accepts all eight Z80 conditions.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; The four condition classes implemented by JR.

EN_IJRCC: ; Test the four conditions implemented by JR.
    CP   EN_NZ                          ; Reject classes before the JR condition range.
    JR   C,AT_NO                        ; NZ is the first condition supported by JR.
    CP   EN_CC+1                        ; Stop after C, the last JR condition class.
    RET                                 ; Carry accepts NZ, Z, NC and C.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Enumerated bit-number classes BIT0..BIT7.

EN_IBIT: ; Test enumerated bit-number classes 0..7.
    CP   EN_BIT0                        ; Reject classes below enumerated bit zero.
    JR   C,AT_NO                        ; Only the eight bit-number classes are accepted.
    CP   EN_BIT7+1                      ; Compare against the exclusive bit-number bound.
    RET                                 ; Carry accepts BIT0 through BIT7.

;@ROUTINE IN A OUT CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common predicate result for a value outside the accepted range.

AT_NO: ; Return a rejected predicate with carry clear.
    CP   A                              ; Compare A with itself to clear carry.
    RET                                 ; Return the predicate's rejected result.

;@ROUTINE OUT CARRY CLOBBERS HALFCARRY
; Return the common predicate result for a value inside the accepted range.

AT_YES: ; Return an accepted predicate with carry set.
    SCF                                 ; Set carry to mark the predicate as successful.
    RET                                 ; Return the accepted-class result.
EN_VCEND: ; End mnemonic dispatch and form-validation code.
