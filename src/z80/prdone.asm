; Finish a parse: commit the instruction record, or report a failure at the
; source position that caused it.

; Report a reference-build failure at the evaluator's saved symbol position.
; prPostMn callers use the enclosing statement. prParse callers receive these
; parser fields directly.

prAtSym: ; Report failure at the evaluator's saved symbol position.
    LD   (prStatus),A                   ; Save the evaluator or symbol status.
    LD   A,(exSrcPos)                   ; Load the deferred symbol's source part.
    LD   (prErrSrc),A                   ; Publish that diagnostic part.
    LD   HL,(exSrcOff)                  ; Load the symbol's source offset.
    LD   (prErrOff),HL                  ; Publish the diagnostic byte offset.
    LD   A,(prStatus)                   ; Restore the failure status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the symbol's exact position.

; Report a reference-finalisation failure at the source position in the
; current private build record selected by prRefIdx.

prAtRef: ; Report failure at the selected private reference's position.
    LD   (prStatus),A                   ; Preserve the reference failure status.
    LD   A,(prRefIdx)                   ; Select the failing private record.
    CALL prRawPtr                       ; Address that record in DE.
    LD   HL,prBPart                     ; Load its source-part field offset.
    ADD  HL,DE                          ; Address the stored source position.
    LD   A,(HL)                         ; Load the source-part ordinal.
    LD   (prErrSrc),A                   ; Publish it for the caller.
    INC  HL                             ; Advance to source-offset low byte.
    LD   E,(HL)                         ; Load the low byte.
    INC  HL                             ; Advance to source-offset high byte.
    LD   D,(HL)                         ; Complete the byte offset.
    LD   (prErrOff),DE                  ; Publish the reference position.
    LD   A,(prStatus)                   ; Restore the parser failure status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the exact reference position.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Commit the fully validated private record to the caller's destination and
; return IX pointing at it. No earlier parser path writes the destination.

prCommit: ; Commit the validated ten-byte record to the caller's destination.
    LD   HL,prRec                       ; Point at the validated private record.
    LD   DE,(prDest)                    ; Load the caller's destination.
    LD   BC,10                          ; Copy the complete encoder record.
    LDIR                                ; Commit all fields together.
    LD   IX,(prDest)                    ; Return the committed record pointer.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Publication is complete.

; Compact status adapters select the appropriate source anchor below.

prLackMn: ; Report a missing mnemonic at the current token.
    LD   A,prNoMnem                     ; Report an empty mnemonic.
    JR   prAtTok                        ; Use the current token position.
prDenyMn: ; Report an unknown mnemonic at the current token.
    LD   A,prBadMn                      ; Report an unknown mnemonic.
    JR   prAtTok                        ; Use the current token position.
prLackOp: ; Report a missing operand at the current token.
    LD   A,prNoOper                     ; Report an expected operand.
    JR   prAtTok                        ; Use the current token position.
prDenyOp: ; Report an unsupported operand at the current token.
    LD   A,prBadOp                      ; Report an unsupported operand form.
    JR   prAtTok                        ; Use the current token position.
prBadSep: ; Report a missing or invalid operand delimiter.
    LD   A,prNoDlm                      ; Report a missing operand delimiter.
    JR   prAtTok                        ; Use the current token position.
prExcess: ; Report an operand count beyond the three available slots.
    LD   A,prManyOp                     ; Report more than three operands.
    JR   prAtTok                        ; Use the current token position.
prTooBig: ; Report a resolved operand outside its encoded range.
    LD   A,prBigVal                     ; Report a concrete operand range error.
    JR   prAtTok                        ; Use the current token position.
prTooFar: ; Retain a rejected relative offset and anchor it at the mnemonic.
    LD   (prRelVal),HL                  ; Publish the rejected displacement in HL.
    LD   A,prFarRel                     ; Report relative displacement overflow.
    JR   prAtMnem                       ; Anchor it at the mnemonic.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token position for token-local syntax and value failures.

prAtTok: ; Select the current token as a diagnostic source anchor.
    LD   HL,tkRecord+tkPartAt           ; Point at token part and offset fields.
    JR   prSetPos                       ; Copy that contiguous position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the mnemonic position for form and relative-range failures.
; prParse captures this position. The statement layer supplies its own outer
; position when it calls prPostMn.

prAtMnem: ; Select the saved mnemonic as a diagnostic source anchor.
    LD   HL,prMnPart                    ; Point at saved mnemonic part and offset.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy a contiguous part-and-offset triple into the parser error fields.
; Preserve the status in A and set carry.

prSetPos: ; Copy the selected position while preserving the parser status.
    LD   (prStatus),A                   ; Preserve the public parser status.
    PUSH BC                             ; Preserve the caller's BC pair.
    PUSH DE                             ; Preserve the caller's DE pair.
    LD   DE,prErrSrc                    ; Select the parser position destination.
    LD   BC,3                           ; Copy part plus two-byte offset.
    LDIR                                ; Publish the contiguous source position.
    POP  DE                             ; Restore the caller's DE pair.
    POP  BC                             ; Restore the caller's BC pair.
    LD   A,(prStatus)                   ; Restore the public parser status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the published position.
