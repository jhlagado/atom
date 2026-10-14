;=============================================================================
;  Instruction form validation
;=============================================================================
;
;  Check operand classes and arity, then return the exact instruction length.
;  This pass does not read operand values, so forward references can reserve
;  their final fields before their target addresses are known.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Validate mnemonic and operand classes only. No value byte is read;
; unresolved records still obtain an exact field layout and length.

enLength: ; Length-only entry aliases complete form validation.
enCheck: ; Validate classes and return the exact encoded length.
    LD   A,(IX+enMnem)                  ; Load the parsed mnemonic ordinal.
    OR   A                              ; Test for the reserved zero ordinal.
    JP   Z,.invalid                     ; Reject zero before indexing a family table.
    CP   mneLast+1                      ; Compare with the exclusive upper bound.
    JP   NC,.invalid                    ; Reject ordinals outside the supported set.
    LD   DE,.vdTable                    ; Select the validation-family address table.
    JR   mneDisp                        ; Dispatch with the record's original ordinal.
.vCore: ; Require no operands and select direct or ED length.

; The first thirteen core opcodes are one byte; the rest carry
; an ED prefix. All core instructions reject operands.

    CALL .noOper                        ; Require all three operand slots to be empty.
    RET  C                              ; Keep the invalid-form result on any operand.
    LD   A,(IX+enMnem)                  ; Reload the ordinal after the arity check.
    CP   14                             ; Split one-byte and ED-prefixed core forms.
    SBC  A,A                            ; Set A to $FF below 14, or zero otherwise.
    ADD  A,2                            ; Convert that selector to an encoded length.
    OR   A                              ; Clear carry and set flags from the length.
    RET                                 ; Return the one- or two-byte instruction length.
.vRet: ; Validate plain or conditional RET.

; RET is either operand-free or takes one of the eight condition classes.

    LD   A,(IX+enOp0)                   ; Read the optional condition operand.
    CP   enNone                         ; The sentinel selects operand-free RET.
    JR   Z,.vRetNone                    ; Check that all remaining slots are also empty.
    CALL enIsCond                       ; Test the operand against all eight conditions.
    JP   NC,.invalid                    ; Reject a value outside the condition range.
    CALL .oneOper                       ; Require the second and third slots to be empty.
    RET  C                              ; Preserve a malformed-arity failure.
    XOR  A                              ; Start the successful one-byte length result.
    INC  A                              ; Set the returned length to one.
    RET                                 ; Return the conditional RET length.
.vRetNone: ; Require all operand slots to be empty for plain RET.
    CALL .noOper                        ; Require all three slots to be empty.
    RET  C                              ; Reject any hidden trailing operand.
    XOR  A                              ; Start the successful one-byte length result.
    INC  A                              ; Set the returned length to one.
    RET                                 ; Return the operand-free RET length.
.vEx: ; Validate the supported exchange pairings.

; EX admits only AF,AF', DE,HL and (SP),HL/IX/IY.

    CALL .twoOper                       ; Allow no more than two EX operands.
    RET  C                              ; Reject a third operand before pair checks.
    LD   A,(IX+enOp0)                   ; Read the first member of the EX pair.
    CP   enRegAF                        ; Check for the AF,AF' exchange form.
    JR   Z,.vExAf                       ; Validate its second operand separately.
    CP   enRegDE                        ; Check for the DE,HL exchange form.
    JR   Z,.vExDe                       ; Validate HL as the second operand.
    CP   enMemSP                        ; The remaining form starts with (SP).
    JP   NZ,.invalid                    ; Reject every other first operand.
    JP   .vLSp                          ; Validate HL/IX/IY and choose its length.
.vExAf: ; Require AF' opposite AF.
    LD   A,(IX+enOp1)                   ; Read the partner of the AF register pair.
    CP   enAltAF                        ; Only AF' completes this exchange form.
.vZLen1: ; Return one byte only when the preceding class matched.
    JP   Z,enDone1                      ; Return one byte when the operand test matched.
    JP   .invalid                       ; Reject any second operand that did not match.
.vExDe: ; Require HL opposite DE.
    LD   A,(IX+enOp1)                   ; Read the partner of DE.
    CP   enRegHL                        ; Only HL completes the DE,HL form.
    JR   .vZLen1                        ; Reuse the shared match and length result.
.vIm: ; Require an enumerated interrupt mode 0..2.

; IM mode is encoded in its enumerated operand class, not in the value word.

    CALL .oneOper                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if an extra operand was supplied.
    LD   A,(IX+enOp0)                   ; The mode is carried by this operand class.
    CP   enIm0                          ; Reject modes below IM 0.
    JP   C,.invalid                     ; Values below the first mode are invalid.
    CP   enIm2+1                        ; Compare with the exclusive upper mode bound.
    JP   NC,.invalid                    ; Reject values above IM 2.
    JP   enDone2                        ; Every IM mode uses the same two-byte length.
.vRst: ; Require an enumerated restart vector 0..56.
    CALL .oneOper                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if an extra operand was supplied.
    LD   A,(IX+enOp0)                   ; Read the enumerated restart-vector class.
    CP   enRst0                         ; Reject values below vector zero.
    JP   C,.invalid                     ; The vector classes begin at RST 0.
    CP   enRst56+1                      ; Compare with the exclusive RST 56 bound.
    JP   NC,.invalid                    ; Reject classes above the final vector.
    JP   enDone1                        ; Every restart instruction encodes in one byte.
.vIncDec: ; Validate register, pair or memory increment/decrement.

; INC/DEC cover byte registers, register pairs, IX/IY, index halves, (HL), and
; indexed memory. Prefix and displacement determine the returned length.

    CALL .oneOper                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if more than one operand was supplied.
    LD   A,(IX+enOp0)                   ; Test the operand as an ordinary byte register.
    CALL enIsReg8                       ; Carry accepts B,C,D,E,H,L or A.
    JP   C,enDone1                      ; Ordinary byte registers need one opcode byte.
    LD   A,(IX+enOp0)                   ; Reload the class for the 16-bit register test.
    CALL enIsPair                       ; Carry accepts BC,DE,HL or SP.
    JP   C,enDone1                      ; Ordinary pairs also need one opcode byte.
    LD   A,(IX+enOp0)                   ; Check the index-register pair classes.
    CP   enRegIX                        ; IX uses a DD-prefixed instruction.
    JP   Z,enDone2                      ; The prefix makes the instruction two bytes.
    CP   enRegIY                        ; IY uses the corresponding FD prefix.
    JP   Z,enDone2                      ; Its instruction length is also two bytes.
    CALL enIsHalf                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,enDone2                      ; An index half adds one prefix byte.
    LD   A,(IX+enOp0)                   ; Reload the operand after the class predicate.
    CP   enMemHL                        ; Check for the unprefixed (HL) memory form.
    JP   Z,enDone1                      ; INC/DEC (HL) uses one opcode byte.
    CALL enIsDisp                       ; Test for indexed memory with a displacement.
.vCLen3: ; Return three bytes only when the predicate accepted.
    JP   C,enDone3                      ; Prefix and displacement make a three-byte form.
    JP   .invalid                       ; Reject every operand class not accepted above.
.vStack: ; Accept BC, DE, HL, AF or an index pair.

; PUSH/POP accept the four ordinary stack pairs plus IX and IY.

    CALL .oneOper                       ; Allow one operand and reject trailing slots.
    RET  C                              ; Stop if a second operand was supplied.
    LD   A,(IX+enOp0)                   ; Read the stack-pair operand class.
    CP   enRegBC                        ; Check the first ordinary stack pair.
    JP   Z,enDone1                      ; PUSH/POP BC needs one opcode byte.
    CP   enRegDE                        ; Compare with the next ordinary pair.
    JP   Z,enDone1                      ; PUSH/POP DE also needs one opcode byte.
    CP   enRegHL                        ; Compare with the HL stack pair.
    JP   Z,enDone1                      ; PUSH/POP HL needs one opcode byte.
    CP   enRegAF                        ; AF is the fourth ordinary stack pair.
    JP   Z,enDone1                      ; PUSH/POP AF uses the unprefixed form.
.vIxIy2: ; Accept IX/IY with their two-byte prefixed length.
    CP   enRegIX                        ; Check for the IX class.
    JP   Z,enDone2                      ; Accept IX as a two-byte form.
    CP   enRegIY                        ; Check for the IY class.
.vZLen2: ; Return two bytes only when the preceding class matched.
    JP   Z,enDone2                      ; Return two bytes when the prior test matched.
    JP   .invalid                       ; Reject the unmatched operand form.
