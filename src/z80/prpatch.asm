;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO,IX
; Before emitting an instruction byte, prove that the pending arena has room
; for every reference and that each symbol remains undefined. Each entry is
; SY_PENDB (nine) bytes including its source position. PR_QUEUE allocates the
; records after output accepts the instruction.

PR_CHECK: ; Preflight pending space and ensure referenced symbols are undefined.
    LD   A,(PR_PRCNT)                   ; Load the public-reference count.
    LD   B,A                            ; Retain the count for multiplication.
    ADD  A,A                            ; Form two bytes per reference.
    ADD  A,A                            ; Form four bytes per reference.
    ADD  A,A                            ; Form eight bytes per reference.
    ADD  A,B                            ; Reach the nine-byte record size.
    LD   B,A                            ; B is the complete pending requirement.
    LD   HL,(SY_PTOP)                   ; Load the pending-arena exclusive end.
    LD   DE,(SY_NEXT)                   ; Load its next free address.
    CALL AT_ROOM                        ; Check the remaining half-open capacity.
    JR   C,PR_QFULL                     ; Reject before any output or allocation.
.SYMBOLS: ; Validate symbol state after the pending-capacity check.

; A symbol defined between parse and emission would make the already encoded
; placeholder invalid. Treat it as a defensive publication-state failure.

    XOR  A                              ; Begin at public reference zero.
    LD   (PR_RIDX),A                    ; Publish the verification index.
.LOOP: ; Check one public reference's symbol per iteration.
    LD   A,(PR_PRCNT)                   ; Read the reference count.
    LD   B,A                            ; Retain it as the loop bound.
    LD   A,(PR_RIDX)                    ; Load the current reference index.
    CP   B                              ; Have all symbols been checked?
    JR   Z,.DONE                        ; Return success after the final record.
    CALL PR_PRADR                       ; Address this public reference.
    LD   E,(HL)                         ; Load symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    EX   DE,HL                          ; Move the symbol address into HL.
    LD   DE,5                           ; Select its packed-name flag byte.
    ADD  HL,DE                          ; Address the symbol flags.
    BIT  6,(HL)                         ; Has the symbol become defined?
    JR   NZ,PR_STALE                    ; Reject a stale deferred reference.
    LD   HL,PR_RIDX                     ; Address the verification index.
    INC  (HL)                           ; Advance to the next public record.
    JR   .LOOP                          ; Check every referenced symbol.
.DONE: ; Return successful pending-space and symbol-state preflight.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Pending capacity is now proved.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Queue every public reference after the encoded bytes have been accepted. DE
; supplies the instruction's logical start address. A second preflight
; protects direct callers and keeps this entry self-contained.

PR_QUEUE: ; Append pending references after the instruction bytes are accepted.
    LD   (PR_QBASE),DE                  ; Retain the instruction start address.
    CALL PR_CHECK                       ; Recheck capacity and symbol state.
    RET  C                              ; Publish nothing when preflight fails.
.APPEND: ; Initialise the queue index after successful preflight.
    XOR  A                              ; Begin with public reference zero.
    LD   (PR_RIDX),A                    ; Publish the queue index.
.LOOP: ; Convert one public reference to a pending record per iteration.
    LD   A,(PR_PRCNT)                   ; Read the number of public references.
    LD   B,A                            ; Retain it as the loop bound.
    LD   A,(PR_RIDX)                    ; Load the current reference index.
    CP   B                              ; Have all pending records been queued?
    JR   Z,.DONE                        ; Return after the final record.
    CALL PR_PRADR                       ; Address the selected public record.

; Load the symbol pointer, signed addend, final kind, source part and encoded
; byte offset from the public record.

    LD   E,(HL)                         ; Load symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    PUSH DE                             ; Transfer the pointer through the stack.
    POP  IX                             ; IX now identifies the symbol record.
    INC  HL                             ; Advance to the signed addend.
    LD   C,(HL)                         ; C carries that addend to SY_ADD.
    INC  HL                             ; Skip to the operand index.
    INC  HL                             ; Advance to patch kind and anchor flag.
    LD   B,(HL)                         ; B carries kind and anchor metadata.
    INC  HL                             ; Advance to encoded field offset.
    LD   A,(HL)                         ; Load the field's byte offset.
    LD   (PR_FIELD),A                   ; Save it across the address calculation.
    INC  HL                             ; Advance to the source-part ordinal.
    LD   A,(HL)                         ; Load the diagnostic source part.
    LD   (PR_TMP),A                     ; Save it across address calculation.
    INC  HL                             ; Advance to the reference's source offset.
    LD   E,(HL)                         ; Load its low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the source offset.
    LD   (SY_ROFF),DE                   ; SY_ADD stores it with the record.
    LD   A,(PR_FIELD)                   ; Recover the encoded field offset.
    LD   HL,(PR_QBASE)                  ; Load the instruction start address.
    LD   E,A                            ; Extend the unsigned byte offset in DE.
    LD   D,0                            ; Clear the offset's high byte.
    ADD  HL,DE                          ; Calculate the logical patch address.
    EX   DE,HL                          ; Put that address in SY_ADD's DE input.

; SY_ADD receives A=part, IX=symbol, DE=patch address, B=kind and C=addend.
; B also carries the diagnostic-anchor flag.

    LD   A,(PR_TMP)                     ; Restore the diagnostic source part.
    CALL SY_ADD                         ; Append the complete pending record.
    RET  C                              ; Preserve any defensive arena failure.
    LD   HL,PR_RIDX                     ; Address the queue index.
    INC  (HL)                           ; Advance after successful publication.
    JR   .LOOP                          ; Queue the remaining references.
.DONE: ; Return after every public reference has been queued.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Every reference is now pending.

; Report that the pending arena cannot hold the complete reference set.

PR_QFULL: ; Report pending-arena exhaustion before output publication.
    LD   A,SY_SPCAP                     ; Report pending-arena capacity failure.
    SCF                                 ; Mark the preflight as failed.
    RET                                 ; No pending record was appended.

; Report a symbol defined before its deferred reference is queued.

PR_STALE: ; Reject a deferred record whose symbol is already defined.
    LD   A,SY_SADEF                     ; Report an already-defined symbol.
    SCF                                 ; Mark the publication state invalid.
    RET                                 ; Leave the pending arena unchanged.

; Report a reference-build failure at the evaluator's saved symbol position.
; PR_PUB callers use the enclosing statement. PR_PARSE callers receive these
; parser fields directly.

PR_FMISS: ; Report failure at the evaluator's saved symbol position.
    LD   (PR_ESTAT),A                   ; Save the evaluator or symbol status.
    LD   A,(EX_SPART)                   ; Load the deferred symbol's source part.
    LD   (PR_EPART),A                   ; Publish that diagnostic part.
    LD   HL,(EX_SOFF)                   ; Load the symbol's source offset.
    LD   (PR_EOFF),HL                   ; Publish the diagnostic byte offset.
    LD   A,(PR_ESTAT)                   ; Restore the failure status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the symbol's exact position.

; Report a reference-finalisation failure at the source position in the
; current private build record selected by PR_RIDX.

PR_FREF: ; Report failure at the selected private reference's position.
    LD   (PR_ESTAT),A                   ; Preserve the reference failure status.
    LD   A,(PR_RIDX)                    ; Select the failing private record.
    CALL PR_BRADR                       ; Address that record in DE.
    LD   HL,PR_BPART                    ; Load its source-part field offset.
    ADD  HL,DE                          ; Address the stored source position.
    LD   A,(HL)                         ; Load the source-part ordinal.
    LD   (PR_EPART),A                   ; Publish it for the caller.
    INC  HL                             ; Advance to source-offset low byte.
    LD   E,(HL)                         ; Load the low byte.
    INC  HL                             ; Advance to source-offset high byte.
    LD   D,(HL)                         ; Complete the byte offset.
    LD   (PR_EOFF),DE                   ; Publish the reference position.
    LD   A,(PR_ESTAT)                   ; Restore the parser failure status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the exact reference position.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Commit the fully validated private record to the caller's destination and
; return IX pointing at it. No earlier parser path writes the destination.

PR_CMT: ; Commit the validated ten-byte record to the caller's destination.
    LD   HL,PR_REC                      ; Point at the validated private record.
    LD   DE,(PR_DST)                    ; Load the caller's destination.
    LD   BC,10                          ; Copy the complete encoder record.
    LDIR                                ; Commit all fields together.
    LD   IX,(PR_DST)                    ; Return the committed record pointer.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Publication is complete.

; Compact status adapters select the appropriate source anchor below.

PR_FNOMN: ; Report a missing mnemonic at the current token.
    LD   A,PR_SNOMN                     ; Report an empty mnemonic.
    JR   PR_FHERE                       ; Use the current token position.
PR_FBADM: ; Report an unknown mnemonic at the current token.
    LD   A,PR_SBADM                     ; Report an unknown mnemonic.
    JR   PR_FHERE                       ; Use the current token position.
PR_FNOOP: ; Report a missing operand at the current token.
    LD   A,PR_SNOOP                     ; Report an expected operand.
    JR   PR_FHERE                       ; Use the current token position.
PR_FBADO: ; Report an unsupported operand at the current token.
    LD   A,PR_SBADO                     ; Report an unsupported operand form.
    JR   PR_FHERE                       ; Use the current token position.
PR_FNODL: ; Report a missing or invalid operand delimiter.
    LD   A,PR_SNODL                     ; Report a missing operand delimiter.
    JR   PR_FHERE                       ; Use the current token position.
PR_FMANY: ; Report an operand count beyond the three available slots.
    LD   A,PR_SMANY                     ; Report more than three operands.
    JR   PR_FHERE                       ; Use the current token position.
PR_FVRNG: ; Report a resolved operand outside its encoded range.
    LD   A,PR_SVRNG                     ; Report a concrete operand range error.
    JR   PR_FHERE                       ; Use the current token position.
PR_FRRNG: ; Retain a rejected relative offset and anchor it at the mnemonic.
    LD   (PR_DVAL),HL                   ; Publish the rejected displacement in HL.
    LD   A,PR_SRRNG                     ; Report relative displacement overflow.
    JR   PR_FBEG                        ; Anchor it at the mnemonic.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token position for token-local syntax and value failures.

PR_FHERE: ; Select the current token as a diagnostic source anchor.
    LD   HL,TK_REC+TK_RPART             ; Point at token part and offset fields.
    JR   PR_FPOS                        ; Copy that contiguous position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the mnemonic position for form and relative-range failures.
; PR_PARSE captures this position. The statement layer supplies its own outer
; position when it calls PR_PUB.

PR_FBEG: ; Select the saved mnemonic as a diagnostic source anchor.
    LD   HL,PR_IPART                    ; Point at saved mnemonic part and offset.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy a contiguous part-and-offset triple into the parser error fields.
; Preserve the status in A and set carry.

PR_FPOS: ; Copy the selected position while preserving the parser status.
    LD   (PR_ESTAT),A                   ; Preserve the public parser status.
    PUSH BC                             ; Preserve the caller's BC pair.
    PUSH DE                             ; Preserve the caller's DE pair.
    LD   DE,PR_EPART                    ; Select the parser position destination.
    LD   BC,3                           ; Copy part plus two-byte offset.
    LDIR                                ; Publish the contiguous source position.
    POP  DE                             ; Restore the caller's DE pair.
    POP  BC                             ; Restore the caller's BC pair.
    LD   A,(PR_ESTAT)                   ; Restore the public parser status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return the published position.
PR_RCEND: ; End parser rule code before its operand lookup table.
PR_IBEG: ; Begin immutable parser operand-name data.

; Sorted RADIX-40 operand-word table. Each three-byte entry contains one
; packed word and its provisional encoder class. C maps to PR_GC because only
; complete form validation can distinguish register C from condition C.

PR_OWCNT    EQU     27                  ; Number of three-byte operand-word entries.
PR_OWTAB: ; Packed operand words followed by provisional encoder classes.
    DW   $0640                          ; Packed operand word A.
    DB   EN_A                           ; Accumulator register class.
    DW   $0730                          ; Packed operand word AF.
    DB   EN_AF                          ; AF register-pair class.
    DW   $0C80                          ; Packed operand word B.
    DB   EN_B                           ; B register class.
    DW   $0CF8                          ; Packed operand word BC.
    DB   EN_BC                          ; BC register-pair class.
    DW   $12C0                          ; Packed operand word C.
    DB   PR_GC                          ; Ambiguous register or condition class.
    DW   $1900                          ; Packed operand word D.
    DB   EN_D                           ; D register class.
    DW   $19C8                          ; Packed operand word DE.
    DB   EN_DE                          ; DE register-pair class.
    DW   $1F40                          ; Packed operand word E.
    DB   EN_E                           ; E register class.
    DW   $3200                          ; Packed operand word H.
    DB   EN_H                           ; H register class.
    DW   $33E0                          ; Packed operand word HL.
    DB   EN_HL                          ; HL register-pair class.
    DW   $3840                          ; Packed operand word I.
    DB   EN_I                           ; Interrupt-vector register class.
    DW   $3C00                          ; Packed operand word IX.
    DB   EN_IX                          ; IX register-pair class.
    DW   $3C08                          ; Packed operand word IXH.
    DB   EN_IXH                         ; IX high-byte register class.
    DW   $3C0C                          ; Packed operand word IXL.
    DB   EN_IXL                         ; IX low-byte register class.
    DW   $3C28                          ; Packed operand word IY.
    DB   EN_IY                          ; IY register-pair class.
    DW   $3C30                          ; Packed operand word IYH.
    DB   EN_IYH                         ; IY high-byte register class.
    DW   $3C34                          ; Packed operand word IYL.
    DB   EN_IYL                         ; IY low-byte register class.
    DW   $4B00                          ; Packed operand word L.
    DB   EN_L                           ; L register class.
    DW   $5140                          ; Packed operand word M.
    DB   EN_M                           ; Minus condition class.
    DW   $57F8                          ; Packed operand word NC.
    DB   EN_NC                          ; No-carry condition class.
    DW   $5B90                          ; Packed operand word NZ.
    DB   EN_NZ                          ; Nonzero condition class.
    DW   $6400                          ; Packed operand word P.
    DB   EN_P                           ; Plus condition class.
    DW   $64C8                          ; Packed operand word PE.
    DB   EN_PE                          ; Parity-even condition class.
    DW   $6658                          ; Packed operand word PO.
    DB   EN_PO                          ; Parity-odd condition class.
    DW   $7080                          ; Packed operand word R.
    DB   EN_R                           ; Memory-refresh register class.
    DW   $7940                          ; Packed operand word SP.
    DB   EN_SP                          ; Stack-pointer class.
    DW   $A280                          ; Packed operand word Z.
    DB   EN_Z                           ; Zero condition class.
PR_OWEND: ; End the packed operand-word table.
PR_IEND: ; End immutable parser data.
PR_CEND: ; End parser and reference-publication code.
PR_WBEG: ; Begin fixed parser workspace.

; Per-call destinations and instruction identity. PR_ILEN is returned by
; EN_VFORM and is required for relative-target conversion.

PR_DST:     DW      0                   ; Caller-owned ten-byte commit destination.
PR_IADR:    DW      0                   ; Current instruction's logical address.
PR_IPART:   DB      0                   ; Source part containing the mnemonic.
PR_IOFF:    DW      0                   ; Byte offset of the mnemonic in that part.
PR_ILEN:    DB      0                   ; Validated encoded instruction length.
PR_OPCNT:   DB      0                   ; Parsed operand count, zero to three.

; Shared scan index, ambiguity masks and selected class/value pointers used by
; operand normalisation and range checking.

PR_OPIDX:   DB      0                   ; Operand index used by normalisation loops.
PR_FMASK:   DB      0                   ; Byte-value fields that may widen to words.
PR_CMASK:   DB      0                   ; C fields that may be condition C.
PR_CPTR:    DW      0                   ; Selected operand-class byte address.
PR_VPTR:    DW      0                   ; Selected operand-value word address.
PR_SAVED:   DB      0                   ; Operand class saved across token fetch.
PR_BASE:    DB      0                   ; Parenthesised register or port base class.
PR_IXIY:    DB      0                   ; Indexed IX/IY class saved during parsing.

; Retained workspace byte with no caller in the current parser implementation.

PR_SPARE:   DB      0                   ; Reserved legacy displacement-sign scratch.

; Six-byte packed operand key and private ten-byte instruction record.
; Selected scratch bytes are also reused for nested status and source fields.
; Terminal errors prevent commit, but a recovered short-word probe may leave
; ignored error bytes in unused operand-value slots of a successful record.

PR_OWKEY:   DS      6                   ; Packed short operand-word key buffer.
PR_REC:     DS      10                  ; Private encoder-format instruction record.
PR_ESTAT    EQU     PR_REC+6            ; Public parser error status overlay.
PR_EPART    EQU     PR_REC+7            ; Public error source-part overlay.
PR_EOFF     EQU     PR_REC+8            ; Public error source-offset overlay.
PR_EXERR    EQU     PR_REC+5            ; Nested expression status overlay.
PR_SYERR    EQU     PR_REC+5            ; Nested symbol status overlay.

; Reference publication state. PR_BRCNT counts private entries. PR_PRCNT is
; published after their symbols and public records are complete.

PR_PRCNT:   DB      0                   ; Published reference-description count.
PR_BRCNT:   DB      0                   ; Private build-reference count.
PR_UMASK:   DB      0                   ; Bits marking unresolved operand values.
PR_RIDX:    DB      0                   ; Reference index during publication.
PR_MISS:    DB      0                   ; Missing symbols for this instruction.
PR_SAME:    DB      0                   ; One when both build records share a key.
PR_TMP:     DB      0                   ; Patch kind or queued source-part ordinal.
PR_FIELD:   DB      0                   ; Encoded field offset across lookup.
PR_ADDW:    DW      0                   ; Signed addend before key copying.
PR_QBASE:   DW      0                   ; Logical instruction base while queueing.

; Two thirteen-byte build entries and two nine-byte public entries complete
; the fixed 94-byte parser workspace.

PR_DVAL:    DW      0                   ; Offset of a rejected relative jump.
PR_BREFS:   DS      PR_BRB*PR_RCAP      ; Two private thirteen-byte build records.
PR_PREFS:   DS      PR_PRB*PR_RCAP      ; Two public nine-byte reference records.
PR_WEND: ; End the fixed parser workspace extent.
