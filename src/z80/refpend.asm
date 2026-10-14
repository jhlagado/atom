;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO,IX
; Before emitting an instruction byte, prove that the pending arena has room
; for every reference and that each symbol remains undefined. Each entry is
; syRefLen (nine) bytes including its source position. refQueue allocates the
; records after output accepts the instruction.

refCheck: ; Preflight pending space and ensure referenced symbols are undefined.
    LD   A,(prPubCnt)                   ; Load the public-reference count.
    LD   B,A                            ; Retain the count for multiplication.
    ADD  A,A                            ; Form two bytes per reference.
    ADD  A,A                            ; Form four bytes per reference.
    ADD  A,A                            ; Form eight bytes per reference.
    ADD  A,B                            ; Reach the nine-byte record size.
    LD   B,A                            ; B is the complete pending requirement.
    LD   HL,(syRefEnd)                  ; Load the pending-arena exclusive end.
    LD   DE,(syRefCur)                  ; Load its next free address.
    CALL syRoom                         ; Check the remaining half-open capacity.
    JR   C,refFull                      ; Reject before any output or allocation.
.symbols: ; Validate symbol state after the pending-capacity check.

; A symbol defined between parse and emission would make the already encoded
; placeholder invalid. Treat it as a defensive publication-state failure.

    XOR  A                              ; Begin at public reference zero.
    LD   (prRefIdx),A                   ; Publish the verification index.
.loop: ; Check one public reference's symbol per iteration.
    LD   A,(prPubCnt)                   ; Read the reference count.
    LD   B,A                            ; Retain it as the loop bound.
    LD   A,(prRefIdx)                   ; Load the current reference index.
    CP   B                              ; Have all symbols been checked?
    JR   Z,.done                        ; Return success after the final record.
    CALL refAddr                        ; Address this public reference.
    LD   E,(HL)                         ; Load symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    EX   DE,HL                          ; Move the symbol address into HL.
    LD   DE,5                           ; Select its packed-name flag byte.
    ADD  HL,DE                          ; Address the symbol flags.
    BIT  6,(HL)                         ; Has the symbol become defined?
    JR   NZ,refStale                    ; Reject a stale deferred reference.
    LD   HL,prRefIdx                    ; Address the verification index.
    INC  (HL)                           ; Advance to the next public record.
    JR   .loop                          ; Check every referenced symbol.
.done: ; Return successful pending-space and symbol-state preflight.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Pending capacity is now proved.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Queue every public reference after the encoded bytes have been accepted. DE
; supplies the instruction's logical start address. A second preflight
; protects direct callers and keeps this entry self-contained.

refQueue: ; Append pending references after the instruction bytes are accepted.
    LD   (prBasePC),DE                  ; Retain the instruction start address.
    CALL refCheck                       ; Recheck capacity and symbol state.
    RET  C                              ; Publish nothing when preflight fails.
.append: ; Initialise the queue index after successful preflight.
    XOR  A                              ; Begin with public reference zero.
    LD   (prRefIdx),A                   ; Publish the queue index.
.loop: ; Convert one public reference to a pending record per iteration.
    LD   A,(prPubCnt)                   ; Read the number of public references.
    LD   B,A                            ; Retain it as the loop bound.
    LD   A,(prRefIdx)                   ; Load the current reference index.
    CP   B                              ; Have all pending records been queued?
    JR   Z,.done                        ; Return after the final record.
    CALL refAddr                        ; Address the selected public record.

; Load the symbol pointer, signed addend, final kind, source part and encoded
; byte offset from the public record.

    LD   E,(HL)                         ; Load symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    PUSH DE                             ; Transfer the pointer through the stack.
    POP  IX                             ; IX now identifies the symbol record.
    INC  HL                             ; Advance to the signed addend.
    LD   C,(HL)                         ; C carries that addend to syAdd.
    INC  HL                             ; Skip to the operand index.
    INC  HL                             ; Advance to patch kind and anchor flag.
    LD   B,(HL)                         ; B carries kind and anchor metadata.
    INC  HL                             ; Advance to encoded field offset.
    LD   A,(HL)                         ; Load the field's byte offset.
    LD   (prField),A                    ; Save it across the address calculation.
    INC  HL                             ; Advance to the source-part ordinal.
    LD   A,(HL)                         ; Load the diagnostic source part.
    LD   (prTemp),A                     ; Save it across address calculation.
    INC  HL                             ; Advance to the reference's source offset.
    LD   E,(HL)                         ; Load its low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the source offset.
    LD   (syAddOff),DE                  ; syAdd stores it with the record.
    LD   A,(prField)                    ; Recover the encoded field offset.
    LD   HL,(prBasePC)                  ; Load the instruction start address.
    LD   E,A                            ; Extend the unsigned byte offset in DE.
    LD   D,0                            ; Clear the offset's high byte.
    ADD  HL,DE                          ; Calculate the logical patch address.
    EX   DE,HL                          ; Put that address in syAdd's DE input.

; syAdd receives A=part, IX=symbol, DE=patch address, B=kind and C=addend.
; B also carries the diagnostic-anchor flag.

    LD   A,(prTemp)                     ; Restore the diagnostic source part.
    CALL syAdd                          ; Append the complete pending record.
    RET  C                              ; Preserve any defensive arena failure.
    LD   HL,prRefIdx                    ; Address the queue index.
    INC  (HL)                           ; Advance after successful publication.
    JR   .loop                          ; Queue the remaining references.
.done: ; Return after every public reference has been queued.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Every reference is now pending.

; Report that the pending arena cannot hold the complete reference set.

refFull: ; Report pending-arena exhaustion before output publication.
    LD   A,syRefCap                     ; Report pending-arena capacity failure.
    SCF                                 ; Mark the preflight as failed.
    RET                                 ; No pending record was appended.

; Report a symbol defined before its deferred reference is queued.

refStale: ; Reject a deferred record whose symbol is already defined.
    LD   A,syAddDef                     ; Report an already-defined symbol.
    SCF                                 ; Mark the publication state invalid.
    RET                                 ; Leave the pending arena unchanged.

refEnd: ; End forward-reference code.
