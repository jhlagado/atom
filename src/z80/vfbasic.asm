;=============================================================================
;  Instruction form validation
;=============================================================================
;
;  Check operand classes and arity, then return the exact instruction length.
;  This pass does not read operand values, so forward references can reserve
;  their final fields before their target addresses are known.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Validate mnemonic and operand classes only. No EN_VAL byte is read;
; unresolved records still obtain an exact field layout and length.

EN_LEN: ; Length-only entry aliases complete form validation.
EN_VFORM: ; Validate classes and return the exact encoded length.
    LD   A,(IX+EN_MNEM)                 ; Load the parsed mnemonic ordinal.
    OR   A                              ; Test for the reserved zero ordinal.
    JP   Z,.INVALID                     ; Reject zero before indexing a family table.
    CP   AT_MLAST+1                     ; Compare with the exclusive upper bound.
    JP   NC,.INVALID                    ; Reject ordinals outside the supported set.
    LD   DE,.VDTABLE                    ; Select the validation-family address table.
    JR   AT_DMNEM                       ; Dispatch with the record's original ordinal.
.VCORE: ; Require no operands and select direct or ED length.

; The first thirteen core opcodes are one byte; the rest carry
; an ED prefix. All core instructions reject operands.

    CALL .NOOPER                        ; Require all three operand slots to be empty.
    RET  C                              ; Keep the invalid-form result on any operand.
    LD   A,(IX+EN_MNEM)                 ; Reload the ordinal after the arity check.
    CP   14                             ; Split one-byte and ED-prefixed core forms.
    SBC  A,A                            ; Set A to $FF below 14, or zero otherwise.
    ADD  A,2                            ; Convert that selector to an encoded length.
    OR   A                              ; Clear carry and set flags from the length.
    RET                                 ; Return the one- or two-byte instruction length.
.VRET: ; Validate plain or conditional RET.

; RET is either operand-free or takes one of the eight condition classes.

    LD   A,(IX+EN_OP0)                  ; Read the optional condition operand.
    CP   EN_NONE                        ; The sentinel selects operand-free RET.
    JR   Z,.VRETNONE                    ; Check that all remaining slots are also empty.
    CALL EN_ICOND                       ; Test the operand against all eight conditions.
    JP   NC,.INVALID                    ; Reject a value outside the condition range.
    CALL .ONEOPER                       ; Require the second and third slots to be empty.
    RET  C                              ; Preserve a malformed-arity failure.
    XOR  A                              ; Start the successful one-byte length result.
    INC  A                              ; Set the returned length to one.
    RET                                 ; Return the conditional RET length.
.VRETNONE: ; Require all operand slots to be empty for plain RET.
    CALL .NOOPER                        ; Require all three slots to be empty.
    RET  C                              ; Reject any hidden trailing operand.
    XOR  A                              ; Start the successful one-byte length result.
    INC  A                              ; Set the returned length to one.
    RET                                 ; Return the operand-free RET length.
.VEX: ; Validate the supported exchange pairings.

; EX admits only AF,AF', DE,HL and (SP),HL/IX/IY.

    CALL .TWOOPER                       ; Allow no more than two EX operands.
    RET  C                              ; Reject a third operand before pair checks.
    LD   A,(IX+EN_OP0)                  ; Read the first member of the EX pair.
    CP   EN_AF                          ; Check for the AF,AF' exchange form.
    JR   Z,.VEXAF                       ; Validate its second operand separately.
    CP   EN_DE                          ; Check for the DE,HL exchange form.
    JR   Z,.VEXDE                       ; Validate HL as the second operand.
    CP   EN_MEMSP                       ; The remaining form starts with (SP).
    JP   NZ,.INVALID                    ; Reject every other first operand.
    JP   .VLSP                          ; Validate HL/IX/IY and choose its length.
.VEXAF: ; Require AF' opposite AF.
    LD   A,(IX+EN_OP1)                  ; Read the partner of the AF register pair.
    CP   EN_APRIM                       ; Only AF' completes this exchange form.
.VZLEN1: ; Return one byte only when the preceding class matched.
    JP   Z,EN_D1                        ; Return one byte when the operand test matched.
    JP   .INVALID                       ; Reject any second operand that did not match.
.VEXDE: ; Require HL opposite DE.
    LD   A,(IX+EN_OP1)                  ; Read the partner of DE.
    CP   EN_HL                          ; Only HL completes the DE,HL form.
    JR   .VZLEN1                        ; Reuse the shared match and length result.
.VIM: ; Require an enumerated interrupt mode 0..2.

; IM mode is encoded in its enumerated operand class, not in the value word.

    CALL .ONEOPER                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if an extra operand was supplied.
    LD   A,(IX+EN_OP0)                  ; The mode is carried by this operand class.
    CP   EN_IM0                         ; Reject modes below IM 0.
    JP   C,.INVALID                     ; Values below the first mode are invalid.
    CP   EN_IM2+1                       ; Compare with the exclusive upper mode bound.
    JP   NC,.INVALID                    ; Reject values above IM 2.
    JP   EN_D2                          ; Every IM mode uses the same two-byte length.
.VRST: ; Require an enumerated restart vector 0..56.
    CALL .ONEOPER                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if an extra operand was supplied.
    LD   A,(IX+EN_OP0)                  ; Read the enumerated restart-vector class.
    CP   EN_RST0                        ; Reject values below vector zero.
    JP   C,.INVALID                     ; The vector classes begin at RST 0.
    CP   EN_RST56+1                     ; Compare with the exclusive RST 56 bound.
    JP   NC,.INVALID                    ; Reject classes above the final vector.
    JP   EN_D1                          ; Every restart instruction encodes in one byte.
.VINCDEC: ; Validate register, pair or memory increment/decrement.

; INC/DEC cover byte registers, register pairs, IX/IY, index halves, (HL), and
; indexed memory. Prefix and displacement determine the returned length.

    CALL .ONEOPER                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if more than one operand was supplied.
    LD   A,(IX+EN_OP0)                  ; Test the operand as an ordinary byte register.
    CALL EN_IR8                         ; Carry accepts B,C,D,E,H,L or A.
    JP   C,EN_D1                        ; Ordinary byte registers need one opcode byte.
    LD   A,(IX+EN_OP0)                  ; Reload the class for the 16-bit register test.
    CALL EN_IR16                        ; Carry accepts BC,DE,HL or SP.
    JP   C,EN_D1                        ; Ordinary pairs also need one opcode byte.
    LD   A,(IX+EN_OP0)                  ; Check the index-register pair classes.
    CP   EN_IX                          ; IX uses a DD-prefixed instruction.
    JP   Z,EN_D2                        ; The prefix makes the instruction two bytes.
    CP   EN_IY                          ; IY uses the corresponding FD prefix.
    JP   Z,EN_D2                        ; Its instruction length is also two bytes.
    CALL EN_IHALF                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,EN_D2                        ; An index half adds one prefix byte.
    LD   A,(IX+EN_OP0)                  ; Reload the operand after the class predicate.
    CP   EN_MEMHL                       ; Check for the unprefixed (HL) memory form.
    JP   Z,EN_D1                        ; INC/DEC (HL) uses one opcode byte.
    CALL EN_IDISP                       ; Test for indexed memory with a displacement.
.VCLEN3: ; Return three bytes only when the predicate accepted.
    JP   C,EN_D3                        ; Prefix and displacement make a three-byte form.
    JP   .INVALID                       ; Reject every operand class not accepted above.
.VSTACK: ; Accept BC, DE, HL, AF or an index pair.

; PUSH/POP accept the four ordinary stack pairs plus IX and IY.

    CALL .ONEOPER                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if a second operand was supplied.
    LD   A,(IX+EN_OP0)                  ; Read the stack-pair operand class.
    CP   EN_BC                          ; Check the first ordinary stack pair.
    JP   Z,EN_D1                        ; PUSH/POP BC needs one opcode byte.
    CP   EN_DE                          ; Compare with the next ordinary pair.
    JP   Z,EN_D1                        ; PUSH/POP DE also needs one opcode byte.
    CP   EN_HL                          ; Compare with the HL stack pair.
    JP   Z,EN_D1                        ; PUSH/POP HL needs one opcode byte.
    CP   EN_AF                          ; AF is the fourth ordinary stack pair.
    JP   Z,EN_D1                        ; PUSH/POP AF uses the unprefixed form.
.VIXIY2: ; Accept IX/IY with their two-byte prefixed length.
    CP   EN_IX                          ; Check for the IX class.
    JP   Z,EN_D2                        ; Accept IX as a two-byte form.
    CP   EN_IY                          ; Check for the IY class.
.VZLEN2: ; Return two bytes only when the preceding class matched.
    JP   Z,EN_D2                        ; Return two bytes when the prior test matched.
    JP   .INVALID                       ; Reject the unmatched operand form.
