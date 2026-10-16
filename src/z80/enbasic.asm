;=============================================================================
; Z80 instruction byte emission
;=============================================================================
;
; Validate the record at IX, stage its encoding, then publish the complete
; one-to-four-byte result to the caller's destination.

enPutBeg: ; Begin staged instruction emission.

;@ROUTINE IN IX,DE OUT A,DE,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and encode the record at IX, then commit its bytes to DE.
; enEncode stages into enTemp; failure leaves the destination untouched.

enEmit: ; Validate, stage and commit a complete instruction.
    PUSH DE                             ; Preserve the caller's destination pointer.
    CALL enCheck                        ; Check form and arity before encoding.
    POP  DE                             ; Recover the destination after validation.
    RET  C                              ; Leave the destination unchanged on failure.
    PUSH DE                             ; Save it while enEncode uses the register pair.
;@EXPECTOUT A
    CALL enEncode                       ; Stage bytes and return their count in A.
    POP  DE                             ; Restore the caller's output address.
    LD   C,A                            ; Supply LDIR with the encoded byte count.
    LD   B,0                            ; Instruction lengths are at most four.
    LD   HL,enTemp                      ; Point at the complete staged instruction.
    LDIR                                ; Commit only after validation and encoding pass.
    OR   A                              ; Preserve the length and clear carry on success.
    RET                                 ; Return length and the advanced output pointer.

;@ROUTINE IN IX,B OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Encode a condition field into bits 3..5 and add the opcode-family base in B.

enCondOp: ; Combine condition field bits 3..5 with base B.
    LD   A,(IX+enOp0)                   ; Read the validated condition ordinal.
    SUB  enCondNZ                       ; NZ..M becomes the three-bit condition field.
    ADD  A,A                            ; Condition field now occupies bits 1..3.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish placing the condition field.
    ADD  A,B                            ; Add the caller's opcode-family base.
    RET                                 ; Return the complete opcode in A.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Encode a record already accepted by enCheck. The family table mirrors the
; validator table so both paths use the same mnemonic-ordinal partition.

enEncode: ; Dispatch an already validated instruction to its encoder.
    LD   A,(IX+enMnem)                  ; Read the ordinal already accepted by enCheck.
    LD   DE,.edTable                    ; Select the matching encoder-family table.
;@DISPATCH .edTable
    JP   mneDisp                        ; Dispatch by ordinal and enter that family.
.coreOp: ; Select direct/ED opcode.

; Core ordinals index direct opcode bytes or ED suffixes. Ordinals 1..13 are
; direct; 14..34 use the shared ED-prefix tail.

    LD   B,A                            ; Keep the one-based ordinal for the prefix test.
    DEC  A                              ; Convert the ordinal to a table byte offset.
    LD   E,A                            ; Place the low index byte in DE.
    LD   D,0                            ; Zero-extend the table index.
    LD   HL,enOpTab                     ; Point to the irregular core-opcode table.
    ADD  HL,DE                          ; Select the entry for this mnemonic ordinal.
    LD   A,B                            ; Recover the ordinal for the direct/ED split.
    CP   14                             ; Separate direct opcodes from ED suffixes.
    LD   A,(HL)                         ; Load the opcode or suffix selected above.
    JP   C,.last1                       ; Ordinals 1..13 emit this byte directly.
    LD   B,A                            ; Pass the ED suffix to the shared prefix tail.
    JP   .edTail                        ; Emit ED followed by the selected suffix.
.ret: ; Encode plain or conditional RET.

; Conditional RET is C0 | cc<<3; plain RET is the singleton C9.

    LD   A,(IX+enOp0)                   ; Read the optional condition operand.
    CP   enNone                         ; The sentinel selects ordinary RET.
    JR   Z,.retPlain                    ; Emit C9 when no condition was supplied.
    LD   B,$C0                          ; Set the base for RET NZ through RET M.
    CALL enCondOp                       ; Insert the condition into bits 3..5.
    JP   .last1                         ; Emit the completed one-byte opcode.
.retPlain: ; Emit unconditional RET.
    LD   A,$C9                          ; Select the unconditional RET opcode.
    JP   .last1                         ; Use the common one-byte emitter.
.ex: ; Select register or stack exchange.

; EX AF,AF', EX DE,HL and EX (SP),HL are singletons. IX/IY stack exchange adds
; the selected prefix before the E3 opcode.

    LD   A,(IX+enOp0)                   ; Check the first operand for AF or DE.
    CP   enRegAF                        ; AF,AF' has its own one-byte opcode.
    JR   Z,.exAf                        ; Select that singleton when matched.
    CP   enRegDE                        ; DE,HL is the other unprefixed register swap.
    JR   Z,.exDe                        ; Select its one-byte opcode when matched.
    LD   A,(IX+enOp1)                   ; The remaining forms test the second operand.
    CP   enRegHL                        ; HL selects EX (SP),HL without a prefix.
    JR   Z,.exSpHl                      ; Emit E3 for the unprefixed stack exchange.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select DD or FD for the validated index pair.
    LD   (enTemp+0),A                   ; Stage the IX/IY prefix before the opcode.
    LD   A,$E3                          ; The indexed stack exchange reuses E3.
    JP   .last2                         ; Append E3 and return a two-byte length.
.exAf: ; Emit the alternate AF exchange.
    LD   A,$08                          ; Select EX AF,AF'.
    JP   .last1                         ; Emit the one-byte form.
.exDe: ; Emit the DE/HL exchange.
    LD   A,$EB                          ; Select EX DE,HL.
    JP   .last1                         ; Emit the one-byte form.
.exSpHl: ; Emit stack exchange with HL.
    LD   A,$E3                          ; Select EX (SP),HL.
    JP   .last1                         ; Emit the one-byte form.
.im: ; Select an interrupt-mode ED suffix.

; IM's three enumerated classes select the irregular ED suffix table.

    LD   A,(IX+enOp0)                   ; Read the validated IM 0..IM 2 class.
    SUB  enIm0                          ; Convert it to a zero-based table offset.
    LD   E,A                            ; Place the offset in DE for address addition.
    LD   D,0                            ; Clear the high byte of the table offset.
    LD   HL,enImTab                     ; Point to the three irregular ED suffixes.
    ADD  HL,DE                          ; Select the suffix for this interrupt mode.
    LD   A,(HL)                         ; Load the selected suffix byte.
    LD   B,A                            ; Pass it to the common ED-prefix emitter.
    JP   .edTail                        ; Emit ED and the selected mode suffix.
.rst: ; Encode the restart-vector field.

; RST classes are ordered vectors, so C7 | vector produces the opcode.

    LD   A,(IX+enOp0)                   ; Read one of the eight validated vector classes.
    SUB  enRst0                         ; Convert RST 0..RST 56 to values zero..seven.
    ADD  A,A                            ; Vector field now occupies bits 1..3.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish forming the vector field.
    ADD  A,$C7                          ; Combine the field with the RST opcode base.
    JP   .last1                         ; Emit the completed one-byte opcode.
.incDec: ; Select byte, pair or indexed INC/DEC.

; B starts at the byte-register base 04/05. Pair forms use 03/0B and memory
; forms add 30 for 34/35. Index forms add a prefix; indexed memory also adds
; its displacement.

    LD   A,(IX+enMnem)                  ; Read INC or DEC from the validated record.
    SUB  mneInc-4                       ; Derive the byte-register opcode base 04 or 05.
    LD   B,A                            ; Keep the selected base during class checks.
    LD   A,(IX+enOp0)                   ; Test the operand as an ordinary byte register.
    CALL enIsReg8                       ; Carry marks B,C,D,E,H,L or A.
    JR   C,.stepReg                     ; Encode a byte register in bits 3..5.
    LD   A,(IX+enOp0)                   ; Reload the class for the register-pair test.
    CALL enIsPair                       ; Carry marks BC,DE,HL or SP.
    JR   C,.stepPair                    ; Route ordinary pairs to shared field logic.
    LD   A,(IX+enOp0)                   ; Check whether the operand is IX or IY.
    CP   enRegIX                        ; Compare with the IX pair class.
    JR   Z,.stepIxIy                    ; Encode IX behind its DD prefix.
    CP   enRegIY                        ; Compare with the IY pair class.
    JR   Z,.stepIxIy                    ; Encode IY behind its FD prefix.
    CALL enIsHalf                       ; Test for IXH, IXL, IYH or IYL.
    JR   C,.stepHalf                    ; Index halves reuse the H/L register field.
    LD   A,(IX+enOp0)                   ; Reload the class for the memory-form test.
    CP   enMemHL                        ; Compare with the unprefixed (HL) class.
    JR   Z,.stepMHl                     ; Keep (HL) on the one-byte path.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the index prefix.
    LD   (enTemp+0),A                   ; Stage the index prefix before the opcode.
    LD   A,B                            ; Restore the INC/DEC family base.
    ADD  A,$30                          ; Form the indexed-memory opcode 34 or 35.
    LD   (enTemp+1),A                   ; Stage the opcode after its prefix.
    LD   A,(IX+enVal0)                  ; Read the displacement selected during parsing.
.last3: ; Finish byte two and return length three.
    LD   (enTemp+2),A                   ; Store the displacement as the third byte.
    JP   enDone3                        ; Return the three-byte indexed form.
.stepReg: ; Encode the byte-register INC/DEC field.

; INC/DEC r = base | r<<3.

    LD   A,(IX+enOp0)                   ; Load the register number for bits 3..5.
.shl3AddB: ; Combine A shifted three bits with base B.
    ADD  A,A                            ; Shift one bit toward the opcode field.
    ADD  A,A                            ; Continue the shared field shift.
    ADD  A,A                            ; Complete the three doublings in this tail.
    ADD  A,B                            ; Add the selected opcode-family base in B.
    JP   .last1                         ; Emit the one-byte register form.
.stepPair: ; Choose the pair INC/DEC opcode base.

; INC/DEC rr = 03/0B | pair<<4.

    LD   A,B                            ; Compare the family base to distinguish INC.
    CP   4                              ; INC starts at 04; DEC starts at 05.
    LD   B,$03                          ; Prepare the INC rr opcode base.
    JR   Z,.pairBase                    ; Preserve the comparison result through LD.
    LD   B,$0B                          ; Select DEC rr when the mnemonic is DEC.
.pairBase: ; Load the ordinary register-pair class.
    LD   A,(IX+enOp0)                   ; Reload BC,DE,HL or SP as the pair number.
.pairAddB: ; Form pair bits 4..5 before the shared tail.
    AND  3                              ; Keep the pair number in the low two bits.
    ADD  A,A                            ; Start shifting the pair field into bits 4..5.
    JR   .shl3AddB                      ; The common tail supplies three more doublings.
.stepIxIy: ; Stage the prefix for indexed pair INC/DEC.

; IX/IY pair operations reuse the HL opcode behind DD/FD.

    CALL enStage                        ; Stage DD/FD and restore the IX/IY class in A.
    LD   A,B                            ; Read the family base to distinguish INC/DEC.
    CP   4                              ; INC uses 23; DEC uses 2B behind the prefix.
    LD   A,$23                          ; Prepare the IX/IY increment opcode.
    JR   Z,.ixIyOp                      ; Keep 23 when the family base was 04.
    LD   A,$2B                          ; Select the decrement opcode for base 05.
.ixIyOp: ; Finish the indexed pair opcode.
    JP   .last2                         ; Emit prefix and opcode as a two-byte form.
.stepHalf: ; Encode an H/L field behind its index prefix.

; Index halves reuse H/L field values behind their family prefix.

    LD   A,(IX+enOp0)                   ; Load IXH/IXL/IYH/IYL as a register class.
    CALL enStage                        ; Stage its prefix and restore the class in A.
    AND  7                              ; Reduce the class to the H or L register field.
    ADD  A,A                            ; Move that field toward opcode bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,B                            ; Add the INC/DEC base to the H/L field.
    JP   .last2                         ; Emit the prefix and one-byte opcode.
.stepMHl: ; Emit unprefixed INC/DEC (HL).
    LD   A,B                            ; Restore the INC/DEC family base.
    ADD  A,$30                          ; Form the (HL) opcode 34 or 35.
    JP   .last1                         ; Emit this unprefixed one-byte form.
.stack: ; Choose PUSH/POP base and stack pair.

; PUSH/POP use C5/C1 | pair<<4. IX/IY reuse the HL field behind DD/FD.

    LD   A,(IX+enMnem)                  ; Read whether this is PUSH or POP.
    CP   mnePush                        ; Set Z for PUSH; POP selects the other base.
    LD   B,$C5                          ; Prepare the PUSH pair-opcode base.
    JR   Z,.pushPop                     ; Keep C5 when the mnemonic is PUSH.
    LD   B,$C1                          ; Select C1 for POP when the test did not match.
.pushPop: ; Select ordinary or indexed stack encoding.
    LD   A,(IX+enOp0)                   ; Read the validated stack-pair class.
    CP   enRegIX                        ; IX uses the HL field behind DD.
    JR   Z,.stackIdx                    ; Stage that prefix before forming the opcode.
    CP   enRegIY                        ; IY uses the corresponding field behind FD.
    JR   Z,.stackIdx                    ; Route both index pairs through the prefix path.
    JR   .pairAddB                      ; Ordinary pairs share the low-field calculation.
.stackIdx: ; Use the prefixed HL stack field.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the index prefix.
    LD   (enTemp+0),A                   ; Stage the prefix before the stack opcode.
    LD   A,B                            ; Restore the PUSH/POP base after prefix lookup.
    ADD  A,$20                          ; Convert C5/C1 to indexed E5/E1.
    JP   .last2                         ; Emit the prefix and indexed stack opcode.
