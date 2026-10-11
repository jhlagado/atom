;@ROUTINE OUT CARRY,ZERO CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Copy both signed operands to magnitude workspace, record their signs and
; negate negative inputs. Product/quotient sign is left XOR right.

EX_ABS: ; Copy operand magnitudes and retain the signs separately.
    LD   HL,EX_LVAL                     ; Point at the signed left operand.
    LD   DE,EX_LABS                     ; Select its magnitude workspace.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Preserve the left operand before conversion.
    LD   HL,EX_RVAL                     ; Point at the signed right operand.
    LD   DE,EX_RABS                     ; Select its magnitude workspace.
    LD   BC,3                           ; Copy the complete 24-bit value.
    LDIR                                ; Preserve the right operand before conversion.
    LD   A,(EX_LVAL+2)                  ; Load the left sign byte.
    RLCA                                ; Rotate sign bit 7 into bit 0.
    AND  1                              ; Reduce it to a Boolean sign value.
    LD   (EX_LSIGN),A                   ; Preserve the dividend/left sign.
    OR   A                              ; Set NZ for a negative left operand.
    CALL NZ,EX_NEGL                     ; Make copied left magnitude positive.
    LD   A,(EX_RVAL+2)                  ; Load the right sign byte.
    RLCA                                ; Rotate sign bit 7 into bit 0.
    AND  1                              ; Reduce it to a Boolean sign value.
    LD   (EX_RSIGN),A                   ; Preserve the divisor/right sign.
    OR   A                              ; Set NZ for a negative right operand.
    CALL NZ,EX_NEGR                     ; Make copied right magnitude positive.
    LD   A,(EX_LSIGN)                   ; Load the left sign Boolean.
    LD   HL,EX_RSIGN                    ; Address the right sign Boolean.
    XOR  (HL)                           ; Different signs require a negative result.
    LD   (EX_SIGN),A                    ; Preserve the product/quotient sign.
    OR   A                              ; Return carry clear with result sign in Z/NZ.
    RET                                 ; Leave both magnitude operands prepared.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the normal result slot in place.

EX_NEG: ; Negate the normal result record in place.
    LD   HL,EX_RVAL                     ; Select the ordinary result value.
    JR   EX_NEGHL                       ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
; Negate the copied left magnitude in place.

EX_NEGL: ; Negate the left magnitude copy in place.
    LD   HL,EX_LABS                     ; Select the copied left magnitude.
    JR   EX_NEGHL                       ; Share 24-bit two's-complement negation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,A,BC,DE,IX,IY,SIGN,PARITY,HALFCARRY
; Negate copied right magnitude through the shared 24-bit body.

EX_NEGR: ; Negate the right magnitude copy in place.
    LD   HL,EX_RABS                     ; Select the copied right magnitude.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
; Form the two's complement of the little-endian 24-bit value at HL.

EX_NEGHL: ; Complement three bytes and propagate the added one.
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
; Complement all three bytes of EX_RVAL for unary '~'.

EX_NOT: ; Invert every bit of the normal result record.
    LD   HL,EX_RVAL                     ; Point at the result low byte.
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
    RET                                 ; Leave the complemented value in EX_RVAL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Add EX_LABS to the 24-bit product accumulator. Carry reports unsigned
; overflow beyond the high byte.

EX_ADDUP: ; Add a magnitude to the product and return overflow in carry.
    LD   HL,EX_ACCUM                    ; Point at the product accumulator low byte.
    LD   A,(EX_LABS)                    ; Load the multiplicand low byte.
    ADD  A,(HL)                         ; Add the accumulator low byte.
    LD   (HL),A                         ; Store the new low product byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(EX_LABS+1)                  ; Load the multiplicand middle byte.
    ADC  A,(HL)                         ; Add accumulator middle byte and carry.
    LD   (HL),A                         ; Store the new middle product byte.
    INC  HL                             ; Advance without changing carry.
    LD   A,(EX_LABS+2)                  ; Load the multiplicand high byte.
    ADC  A,(HL)                         ; Add accumulator high byte and carry.
    LD   (HL),A                         ; Store the new high product byte.
    RET                                 ; Return carry as overflow beyond bit 23.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift the multiplication multiplicand left by one bit.

EX_TWICE: ; Advance the multiplicand to its next binary place.
    LD   HL,EX_LABS                     ; Select the multiplicand magnitude.
    JP   EX_SLA24                       ; Tail-call one 24-bit left shift.

;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
; Shift unsigned multiplier right. SRL clears the high sign bit, and the
; shared tail rotates carry through the low sixteen bits.

EX_HALVE: ; Consume a multiplier bit with a logical right shift.
    LD   HL,EX_RABS+2                   ; Point at the multiplier high byte.
    LD   A,(HL)                         ; Load it for an unsigned shift.
    SRL  A                              ; Shift in zero and expose bit 0 in carry.

;@ROUTINE IN A,HL OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the already-shifted high byte in A, then rotate the two lower bytes at
; HL-1 and HL-2 through carry. Arithmetic right shift enters here too.

EX_SRL16: ; Propagate a shifted high byte through the lower two bytes.
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

EX_CMP: ; Compare unsigned remainder and divisor from high byte to low.
    LD   A,(EX_ACCUM+2)                 ; Load the remainder high byte.
    LD   HL,EX_RABS+2                   ; Point at the divisor high byte.
    CP   (HL)                           ; Compare the most-significant bytes.
    RET  NZ                             ; Their order decides unless they are equal.
    LD   A,(EX_ACCUM+1)                 ; Load the remainder middle byte.
    DEC  HL                             ; Point at the divisor middle byte.
    CP   (HL)                           ; Compare the next-significant bytes.
    RET  NZ                             ; Their order decides unless they are equal.
    LD   A,(EX_ACCUM)                   ; Load the remainder low byte.
    DEC  HL                             ; Point at the divisor low byte.
    CP   (HL)                           ; Complete the unsigned 24-bit comparison.
    RET                                 ; Carry means remainder is smaller.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY
; Subtract the divisor magnitude from the partial remainder in place.

EX_MINUS: ; Subtract the divisor from the current partial remainder.
    LD   HL,EX_ACCUM                    ; Point at the remainder low byte.
    LD   DE,EX_RABS                     ; Point at the divisor low byte.
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
; Expand the resolved word in HL into EX_RVAL and clear both the 24-bit high
; byte and the deferred-state marker.

EX_STORE: ; Zero-extend HL and mark the working result concrete.
    LD   (EX_RVAL),HL                   ; Store the resolved low sixteen bits.
    XOR  A                              ; Form zero for high byte and resolution state.
    LD   (EX_RVAL+2),A                  ; Zero-extend the word to 24 bits.
    LD   (EX_RFORM),A                   ; Mark the result concrete.
    RET                                 ; Return carry clear from XOR.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL
; Require a resolved result in the final word domain. Positive values may
; reach $00FFFF; negative values must be sign-extended from $FF8000..$FFFFFF.

EX_WORD: ; Accept the final -32768..65535 word domain.
    LD   A,(EX_RVAL+2)                  ; Load the 24-bit result's extension byte.
    OR   A                              ; Is it zero for a non-negative word?
    RET  Z                              ; Yes: $000000..$00FFFF is valid.
    INC  A                              ; Does $FF wrap to zero?
    JR   NZ,.BAD                        ; Other extensions are outside the word domain.
    LD   A,(EX_RVAL+1)                  ; Inspect a negative result's middle byte.
    BIT  7,A                            ; Is bit 15 set for proper sign extension?
    RET  NZ                             ; Yes: $FF8000..$FFFFFF is valid.
.BAD: ; Report a final result outside the word domain.
    LD   A,EX_SRNG                      ; Select final word-range failure.
    JR   EX_FHERE                       ; Anchor it at the current delimiter token.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require a deferred addend sign-extended from one byte:
; $000000..$00007F or $FFFF80..$FFFFFF.

EX_BYTE: ; Accept only a sign-extended -128..127 deferred addend.
    LD   A,(EX_RVAL+2)                  ; Load the deferred addend extension byte.
    OR   A                              ; Zero selects the non-negative range check.
    JR   Z,.POSITIVE                    ; Validate $00 in both upper bytes.
    INC  A                              ; Does the extension equal $FF?
    JR   NZ,EX_RANGE                    ; No: it cannot be an eight-bit sign extension.
    LD   A,(EX_RVAL+1)                  ; Load the middle addend byte.
    INC  A                              ; Does it also equal $FF?
    JR   NZ,EX_RANGE                    ; No: reject outside the signed-byte domain.
    LD   A,(EX_RVAL)                    ; Load the candidate negative low byte.
    BIT  7,A                            ; Is it $80..$FF?
    RET  NZ                             ; Yes: the addend is correctly sign-extended.
    JR   EX_RANGE                       ; Reject $FFFF00..$FFFF7F.
.POSITIVE: ; Validate the non-negative deferred-addend range.
    LD   A,(EX_RVAL+1)                  ; Load the non-negative addend middle byte.
    OR   A                              ; Must it be zero?
    JR   NZ,EX_RANGE                    ; Nonzero exceeds the signed-byte range.
    LD   A,(EX_RVAL)                    ; Load the candidate positive low byte.
    BIT  7,A                            ; Is it $80 or above?
    JR   NZ,EX_RANGE                    ; Yes: it is not a positive signed byte.
    OR   A                              ; Clear carry while preserving the addend byte.
    RET                                 ; Accept $00..$7F.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Advance the tokenizer. A lexical failure carries the tokenizer's own source
; position rather than the expression's current operator or token position.

EX_NEXT: ; Advance the tokenizer or retain its exact lexical failure.
    CALL TK_NEXT                        ; Ask the tokenizer to publish the next record.
    RET  NC                             ; Return it unchanged on lexical success.
    LD   A,EX_SLEX                      ; Select the expression lexical category.
    JR   EX_FLEX                        ; Use the tokenizer's exact failure position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Report a numeric range error at the operator whose calculation failed.

EX_RANGE: ; Report numeric range failure at the saved operator.
    LD   A,EX_SRNG                      ; Select arithmetic/range failure.
    JR   EX_FOPER                       ; Anchor it at the saved operator position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token's stored source position for primary, delimiter and
; capacity failures.

EX_FHERE: ; Select the current token as the diagnostic anchor.
    LD   HL,TK_REC+TK_RPART             ; Point at current token part and offset fields.
    JR   EX_FAIL                        ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use saved operator position for arithmetic or form errors.

EX_FOPER: ; Select the saved operator as the diagnostic anchor.
    LD   HL,EX_OPART                    ; Point at saved operator part and offset fields.
    JR   EX_FAIL                        ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the saved name position for symbol packing and lookup failures.

EX_FSYM: ; Select the saved symbol name as the diagnostic anchor.
    LD   HL,EX_NPART                    ; Point at the current name's part and offset.
    JR   EX_FAIL                        ; Copy that position and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the tokenizer's recorded position for lexical errors.

EX_FLEX: ; Select the tokenizer failure as the diagnostic anchor.
    LD   HL,TK_EPART                    ; Point at tokenizer failure location.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy the contiguous part-and-offset triple at HL into the public expression
; error fields, preserve the status in A and set carry.

EX_FAIL: ; Publish a part/offset diagnostic while retaining status A.
    PUSH BC                             ; Preserve caller BC across the three-byte copy.
    PUSH DE                             ; Preserve caller DE likewise.
    LD   DE,EX_EPART                    ; Select the public expression error destination.
    LD   BC,3                           ; Copy one part byte and one offset word.
    LDIR                                ; Publish the exact selected source position.
    POP  DE                             ; Restore caller DE.
    POP  BC                             ; Restore caller BC.
    SCF                                 ; Fail while retaining status A.
    RET                                 ; Return category and positioned diagnostic.
EX_RCEND: ; End the expression rule-code measurement range.
EX_CEND: ; End expression code and immutable tables.
EX_WBEG: ; Begin fixed expression workspace.

; Persistent state for one parse. EX_LOC gives '$' its statement address and
; EX_DOPUB selects direct publication or caller-managed deferred publication.

EX_LOC:     DW      0                   ; Current address used when parsing '$'.
EX_DOPUB:   DB      0                   ; Nonzero permits successful symbol publication.

; Right/current record: signed 24-bit value or addend, deferred transform
; and six-byte exact packed key.

EX_RVAL:    DS      3                   ; Right/current 24-bit value or signed addend.
EX_RFORM:   DB      0                   ; Concrete/plain/LOW/HIGH result state.
EX_RKEY:    DS      6                   ; Exact packed key for a deferred right result.

; Left value record loaded during binary reduction.

EX_LVAL:    DS      3                   ; Left 24-bit value or signed addend.
EX_LFORM:   DB      0                   ; Left concrete/deferred transform state.
EX_LKEY:    DS      6                   ; Exact packed key for a deferred left operand.

; Operator record and a spare copy used while precedence reduction loads
; older operators from the stack.

EX_OPER:    DB      0                   ; Current packed precedence/operation byte.
EX_OPART:   DB      0                   ; Current operator's source-part ordinal.
EX_OOFF:    DW      0                   ; Current operator's source-byte offset.
EX_SAVED:   DS      EX_OPERB            ; Saved incoming operator during reduction.

; EX_NPART/EX_NOFF hold the name being resolved and are dead once EX_NAME
; returns, so multiply and divide reuse them. EX_SPART/EX_SOFF hold the
; deferred symbol's anchor and are written only when a name becomes pending.

EX_NPART:   DB      0                   ; Current name's source-part ordinal.
EX_NOFF:    DW      0                   ; Current name's source-byte offset.
EX_SPART:   DB      0                   ; Deferred symbol source-part ordinal.
EX_SOFF:    DW      0                   ; Deferred symbol source-byte offset.
EX_CAUSE:   DB      0                   ; Nested symbol status for diagnostics.
EX_ROUND    EQU     EX_CAUSE            ; Multiplication round count overlay.

; Bounded parser state. EX_HALF is one when the grammar requires a primary and
; zero when it requires an operator or delimiter.

EX_VCNT:    DB      0                   ; Number of live value-stack entries.
EX_OCNT:    DB      0                   ; Number of live operator-stack entries.
EX_NEST:    DB      0                   ; Open-parenthesis nesting depth.
EX_HALF:    DB      0                   ; Nonzero in the primary half of expression parsing.

; Multiply/divide overlay popped operand-key slots with magnitudes,
; accumulator and quotient. Both popped operands are concrete, so
; their keys are dead. The sign fields overlay the current-name position,
; which is dead between names; the deferred anchor is never overlaid.

EX_LSIGN    EQU     EX_NPART            ; Saved left/dividend sign overlay.
EX_RSIGN    EQU     EX_NOFF             ; Saved right/divisor sign overlay.
EX_SIGN     EQU     EX_NOFF+1           ; Product/quotient sign overlay.
EX_MODE     EQU     EX_ROUND            ; Quotient-versus-remainder selector overlay.
EX_LABS     EQU     EX_RKEY             ; Left operand magnitude overlay.
EX_RABS     EQU     EX_RKEY+3           ; Right operand magnitude overlay.
EX_ACCUM    EQU     EX_LKEY             ; Product/partial-remainder accumulator overlay.
EX_EPART    EQU     EX_ACCUM            ; Public error-part field overlay.
EX_EOFF     EQU     EX_ACCUM+1          ; Public error-offset field overlay.
EX_QUOT     EQU     EX_LKEY+3           ; Division quotient overlay.

; Sixteen ten-byte values followed by sixteen four-byte operators.
; The complete fixed expression workspace is 266 bytes.

EX_VALS:    DS      EX_VALB*EX_VCAP     ; Sixteen complete value records.
EX_OPERS:   DS      EX_OPERB*EX_OCAP    ; Sixteen positioned operator records.
EX_WEND: ; End fixed expression workspace.
