;@ROUTINE IN B OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Write B buffered bytes to the open output. Require an exact result count
; and invalidate the source cache, which shares the transfer area.

NA_WRITE: ; Require an exact output transfer count.
    LD   A,B                            ; Save the requested count.
    LD   (NA_COUNT),A                   ; Keep it for the exact-result check.
    XOR  A                              ; Cache and output share a buffer.
    LD   (NA_CLEN),A                    ; Invalidate cached source bytes.
    LD   IX,(NA_CFG)                    ; Load the configured output-service selector.
    LD   C,(IX+NA_CFDST)                ; Select the output provider.
    LD   DE,(NA_OHAND)                  ; Pass its open handle.
    LD   A,ZT_WRITE                     ; Choose the named-object WRITE operation.
    CALL NA_TRANS                       ; Write B bytes from the common transfer buffer.
    RET  C                              ; Propagate provider failure.
    LD   A,H                            ; Expected count is at most 128.
    OR   A                              ; Reject any result with a nonzero high byte.
    JR   NZ,.BAD                        ; High byte cannot match.
    LD   A,(NA_COUNT)                   ; Recover the exact byte count requested.
    CP   L                              ; Compare with returned count.
    JR   NZ,.BAD                        ; Reject a partial write.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The provider accepted every requested byte.
.BAD: ; Reject a short or excessive write result.
    LD   A,ZT_STORE                     ; Report a partial transfer.
    SCF                                 ; Mark the mismatch as an error for the caller.
    RET                                 ; Caller updates cursor on success only.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Fill the tentative output from its current append cursor to relative offset
; HL. Reject backward IMAGE calls. write forward gaps as zero blocks
; no larger than the common 128-byte transfer buffer.

NA_FILL: ; Zero-fill forward from the output append cursor.
    EX   DE,HL                          ; Save the target in DE.
    LD   HL,(NA_OCURS)                  ; Load the current append cursor.
    OR   A                              ; Clear carry before comparing unsigned offsets.
    SBC  HL,DE                          ; Compute cursor minus requested target.
    JR   C,.FORWARD                     ; Cursor is behind target.
    JR   Z,.DONE                        ; Target equals cursor.
    LD   A,ZT_INV                       ; IMAGE cannot move the append cursor backwards.
    SCF                                 ; Report the invalid backward append.
    RET                                 ; Leave the output object unchanged.
.FORWARD: ; Compute the positive gap to the requested offset.
    EX   DE,HL                          ; Restore the requested target in HL.
    LD   DE,(NA_OCURS)                  ; Load the lower current cursor for subtraction.
    OR   A                              ; Clear carry before computing the positive gap.
    SBC  HL,DE                          ; HL now holds target minus current cursor.

; HL now holds the positive gap.

    LD   (NA_GAP),HL                    ; Save remaining zero-fill length.
.LOOP: ; Write bounded blocks until the gap is empty.
    LD   HL,(NA_GAP)                    ; Reload the remaining gap.
    LD   A,H                            ; Nonzero high byte means at least 256.
    OR   L                              ; Z means the entire gap has been emitted.
    JR   Z,.DONE                        ; Finish when no padding bytes remain.
    LD   B,NA_XLEN                      ; Default to a full 128-byte block.
    LD   A,H                            ; Check whether the remaining gap reaches 256.
    OR   A                              ; Test whether gap is under 256.
    JR   NZ,.COUNT                      ; At least 256: keep a full block.
    LD   A,L                            ; Check the low-byte remainder.
    CP   NA_XLEN                        ; Does a full block fit?
    JR   NC,.COUNT                      ; Keep B=128 if it does.
    LD   B,A                            ; Otherwise use the remainder.
.COUNT: ; Prepare the selected zero-fill block.
    LD   A,B                            ; Save block size across the write.
    LD   (NA_COUNT),A                   ; Reuse it for cursor and gap.
    LD   HL,(NA_WORK)                   ; Start at the common-workspace base.
    LD   DE,NA_XOFF                     ; Select the shared transfer buffer.
    ADD  HL,DE                          ; HL now points at the first buffer byte.
    XOR  A                              ; Fill every selected byte with zero.
.ZERO: ; Clear each byte in this transfer block.
    LD   (HL),A                         ; Store one zero padding byte.
    INC  HL                             ; Advance within the transfer buffer.
    DJNZ .ZERO                          ; Stop after exactly B bytes have been cleared.
    LD   A,(NA_COUNT)                   ; Restore the selected block size.
    LD   B,A                            ; Pass that size to the exact-count writer.
    CALL NA_WRITE                       ; Append the zero block to the output object.
    RET  C                              ; Do not advance offsets after a failed write.
    LD   A,(NA_COUNT)                   ; Recover the accepted block size.
    LD   E,A                            ; Extend it to a 16-bit cursor increment.
    LD   D,0                            ; The block size is at most 128.
    LD   HL,(NA_OCURS)                  ; Load the append cursor before this block.
    ADD  HL,DE                          ; Advance the cursor by the bytes just accepted.
    LD   (NA_OCURS),HL                  ; Publish the new append position.
    LD   HL,(NA_GAP)                    ; Reload the remaining zero-fill distance.
    OR   A                              ; Clear carry for subtraction.
    SBC  HL,DE                          ; Remove this block from the gap still to write.
    LD   (NA_GAP),HL                    ; Preserve the remainder for the next iteration.
    JR   .LOOP                          ; Emit another block until the gap reaches zero.
.DONE: ; Return with the append cursor at the target.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Cursor now equals the target.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Convert absolute target address HL to the flat output-relative offset.

NA_REL: ; Translate target address to output-relative offset.
    LD   DE,(NA_TBASE)                  ; Load the flat image base.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Form the image-relative offset.
    RET  NC                             ; Return offset when nonnegative.
    LD   A,ZT_INV                       ; A target below the image base is invalid.
    SCF                                 ; Return the range failure through carry.
    RET                                 ; Preserve the invalid-target status in A.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek the output object to relative offset HL.

NA_OSEEK: ; Seek the current output object.
    LD   IX,(NA_CFG)                    ; Load adapter configuration.
    LD   C,(IX+NA_CFDST)                ; Select the output provider.
    LD   DE,(NA_OHAND)                  ; Supply its current handle to the seek helper.
    JP   NA_SEEK                        ; Reuse the common request and offset setup.

; Begin a tentative flat-image object. Capture the descriptor's target base,
; reject a nested generation, and reset append/high-water offsets after OPEN.

HS_CBEG: ; Mark the first sink callback in the adapter.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a tentative output object and reset its append and high-water offsets.

HS_BEG: ; Open one tentative output generation.
    PUSH BC                             ; Save caller state across provider calls.
    PUSH DE                             ; DE will hold the opened handle.
    PUSH HL                             ; Preserve the caller's address and byte values.
    PUSH IX                             ; Save the Atom descriptor pointer.
    PUSH IY                             ; Preserve IY across the named-object gateway.
    LD   A,(NA_OHAND)                   ; Read the tentative output handle's low byte.
    LD   B,A                            ; Keep it while checking the high byte.
    LD   A,(NA_OHAND+1)                 ; Read the tentative output handle's high byte.
    OR   B                              ; Nonzero means a generation is open.
    JR   NZ,.NESTED                     ; Reject a nested output generation.
    LD   L,(IX+11)                      ; Read the descriptor's target base, low byte.
    LD   H,(IX+12)                      ; Complete the target-base address.
    LD   (NA_TBASE),HL                  ; Retain the absolute base used by NA_REL.
    LD   IX,(NA_CFG)                    ; Switch IX to adapter configuration.
    LD   L,(IX+NA_CFOUT)                ; Read output-name pointer, low byte.
    LD   H,(IX+NA_CFOUT+1)              ; Read output-name pointer, high byte.
    LD   B,(IX+NA_CFLEN)                ; Supply its configured byte length to NA_OPEN.
    LD   C,(IX+NA_CFDST)                ; Select the output provider for the new object.
    LD   A,ZT_BEGIN                     ; Begin a tentative output object.
    CALL NA_OPEN                        ; Open the uncommitted generation.
    JR   C,.DONE                        ; Restore caller state on failure.
    LD   (NA_OHAND),DE                  ; Retain the tentative generation's handle.
    LD   HL,0                           ; The new image begins at relative offset zero.
    LD   (NA_OCURS),HL                  ; Reset its append cursor.
    LD   (NA_OHIGH),HL                  ; Reset its initialised high-water extent.
    XOR  A                              ; Return success with carry clear.
    JR   .DONE                          ; Restore saved caller state before returning.
.NESTED: ; Reject BEGIN while a generation is open.
    LD   A,ZT_INV                       ; Reject a nested generation.
    SCF                                 ; Mark the nested begin as invalid.
.DONE: ; Restore caller state after BEGIN.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's descriptor pointer.
    POP  HL                             ; Restore the caller's HL input pair.
    POP  DE                             ; Restore the caller's DE input pair.
    POP  BC                             ; Restore the caller's BC input pair.
    RET                                 ; Return the begin status in A and carry.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Append one IMAGE byte. Address class C must be zero for this flat target.
; Convert the address to a flat offset, zero-fill any forward gap, write
; the byte and advance both cursor and high-water mark.

HS_IB: ; Append one IMAGE byte after filling any gap.
    PUSH BC                             ; Save address class and caller BC.
    PUSH IX                             ; Preserve IX across the output provider call.
    PUSH IY                             ; Preserve IY across the output provider call.
    LD   (NA_BYTE),A                    ; Save the IMAGE byte before address validation.
    LD   A,C                            ; The flat sink accepts only address class zero.
    OR   A                              ; Test the class without changing C.
    JR   NZ,.BAD                        ; Reject banked or otherwise non-flat addresses.

    CALL NA_REL                         ; Form the image-relative offset.
    JR   C,.DONE                        ; Reject an address below the image base.
    CALL NA_FILL                        ; Zero-fill up to this offset.
    JR   C,.DONE                        ; Stop after a failed gap fill.

    LD   HL,(NA_WORK)                   ; Start at the shared transfer workspace.
    LD   DE,NA_XOFF                     ; Select the buffer used by the provider.
    ADD  HL,DE                          ; HL now points at its first byte.
    LD   A,(NA_BYTE)                    ; Recover the caller's IMAGE value.
    LD   (HL),A                         ; Stage one byte for NA_WRITE.
    LD   B,1                            ; The IMAGE operation appends exactly one byte.
    CALL NA_WRITE                       ; Require the provider to accept that byte.
    JR   C,.DONE                        ; Do not advance cursor after failure.

    LD   HL,(NA_OCURS)                  ; Read the cursor after any preceding zero fill.
    INC  HL                             ; Advance past the newly appended IMAGE byte.
    LD   (NA_OCURS),HL                  ; Publish the next append position.
    LD   (NA_OHIGH),HL                  ; Advance initialised high water.
    XOR  A                              ; Return success with carry clear.
    JR   .DONE                          ; Restore caller registers before returning.
.BAD: ; Reject a non-flat IMAGE address.
    LD   A,ZT_INV                       ; Reject a non-flat address class.
    SCF                                 ; Mark the rejected IMAGE operation as invalid.
.DONE: ; Restore caller state after IMAGE.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX register.
    POP  BC                             ; Restore the caller's BC pair.
    RET                                 ; Return the IMAGE result in A and carry.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier byte. C must be zero and the address must lie below
; initialised high water. Seek, replace one byte, then restore the
; append cursor on success. a provider failure is left for driver-level abort.

HS_PB: ; Replace one earlier byte and restore append position.
    PUSH BC                             ; Save address class and caller BC.
    PUSH IX                             ; Preserve IX across provider calls.
    PUSH IY                             ; Preserve IY across provider calls.
    LD   (NA_BYTE),A                    ; Save the replacement byte before validation.
    LD   A,C                            ; A flat patch must use address class zero.
    OR   A                              ; Test the class while keeping C unchanged.
    JR   NZ,.BAD                        ; Reject a patch for a banked address.

    CALL NA_REL                         ; Form the relative patch offset.
    JR   C,.DONE                        ; Reject a patch below the image base.
    LD   DE,(NA_OHIGH)                  ; Load exclusive initialised end.
    PUSH HL                             ; Save offset for the seek.
    OR   A                              ; Clear carry for comparison.
    SBC  HL,DE                          ; Compare offset with high water.
    POP  HL                             ; Restore the patch offset after the comparison.
    JR   NC,.BAD                        ; No byte exists at or beyond high water.

    CALL NA_OSEEK                       ; Seek to the byte being patched.
    JR   C,.DONE                        ; Do not stage after failed seek.
    LD   HL,(NA_WORK)                   ; Start at the shared transfer workspace.
    LD   DE,NA_XOFF                     ; Select the provider's transfer buffer.
    ADD  HL,DE                          ; HL now points at its first byte.
    LD   A,(NA_BYTE)                    ; Recover the replacement value.
    LD   (HL),A                         ; Stage the one-byte patch for NA_WRITE.
    LD   B,1                            ; The patch replaces exactly one output byte.
    CALL NA_WRITE                       ; Require an exact one-byte provider write.
    JR   C,.DONE                        ; Let driver abort after failed write.

    LD   HL,(NA_OCURS)                  ; Load the append cursor.
    CALL NA_OSEEK                       ; Restore provider position.
    JR   .DONE                          ; Return the restoration result to the driver.
.BAD: ; Reject byte-PATCH class or bounds.
    LD   A,ZT_INV                       ; Reject class or patch range.
    SCF                                 ; Mark the invalid patch.
.DONE: ; Restore caller state after byte PATCH.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX register.
    POP  BC                             ; Restore the caller's BC pair.
    RET                                 ; Return patch or provider status.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier little-endian word. Address class C must be zero and both
; bytes must lie below high water. Write low byte first, then restore append
; cursor on success. a provider failure is left for driver-level abort.

HS_PW: ; Replace one earlier word and restore append position.
    PUSH IX                             ; Preserve the Atom descriptor pointer.
    PUSH IY                             ; Preserve IY across output-provider calls.
    LD   (NA_WORD),HL                   ; Save the little-endian patch value.
    LD   A,C                            ; A flat word patch must use address class zero.
    OR   A                              ; Test the class while keeping C unchanged.
    JR   NZ,.BAD                        ; Reject a word patch for a banked address.

    EX   DE,HL                          ; Move the absolute patch address from DE to HL.
    CALL NA_REL                         ; Convert that address to a flat image offset.
    JR   C,.DONE                        ; Reject an address below the base.
    PUSH HL                             ; Preserve the first-byte offset for NA_OSEEK.
    INC  HL                             ; Check the second byte's offset.
    LD   DE,(NA_OHIGH)                  ; Load exclusive initialised end.
    OR   A                              ; Clear carry for comparison.
    SBC  HL,DE                          ; Compare second byte with high water.
    POP  HL                             ; Restore the first-byte offset for the seek.
    JR   NC,.BAD                        ; Reject beyond the initialised extent.

    CALL NA_OSEEK                       ; Position the provider at the word's low byte.
    JR   C,.DONE                        ; Do not write after failed seek.
    LD   HL,(NA_WORK)                   ; Start at the common workspace base.
    LD   DE,NA_XOFF                     ; Select the provider's transfer buffer.
    ADD  HL,DE                          ; HL now points at its first byte.
    LD   DE,(NA_WORD)                   ; Recover the patch value.
    LD   (HL),E                         ; Stage the low byte at the patch offset.
    INC  HL                             ; Advance to the next transfer-buffer byte.
    LD   (HL),D                         ; Stage the high byte after the low byte.
    LD   B,2                            ; The word patch replaces exactly two bytes.
    CALL NA_WRITE                       ; Require an exact two-byte provider write.
    JR   C,.DONE                        ; Let driver abort on failure.

    LD   HL,(NA_OCURS)                  ; Load the append cursor.
    CALL NA_OSEEK                       ; Restore provider position.
    JR   .DONE                          ; Return the restoration result to the driver.
.BAD: ; Reject word-PATCH class or bounds.
    LD   A,ZT_INV                       ; Reject class or word range.
    SCF                                 ; Mark the rejected patch as invalid.
.DONE: ; Restore caller state after word PATCH.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX descriptor pointer.
    RET                                 ; Return patch or provider status.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Materialize to the core's explicit high-water endpoint, close the source
; object, then publish the tentative output atomically.

HS_CMT: ; Materialise high water and commit the object.
    BIT  1,A                            ; Is high water mathematical $10000?
    JR   NZ,.ENDPOINT                   ; Convert that endpoint modulo the image base.
    LD   H,B                            ; Load the high-water address's high byte.
    LD   L,C                            ; Complete the high-water address.
    LD   DE,(NA_TBASE)                  ; Load the absolute target origin.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Convert absolute high water to image offset.
    JR   C,.DONE                        ; Reject an impossible mark below the origin.
    JR   .FILL                          ; Materialize ordinary high-water extent.
.ENDPOINT: ; Translate the mathematical $10000 endpoint.
    LD   HL,0                           ; Store $10000's low word as zero.
    LD   DE,(NA_TBASE)                  ; Load the absolute target origin.
    OR   A                              ; Clear carry before modulo subtraction.
    SBC  HL,DE                          ; Obtain $10000 minus origin in sixteen bits.
.FILL: ; Fill trailing reservations before publication.
    CALL NA_FILL                        ; Zero-fill the trailing reservation.
    JR   C,.DONE                        ; Do not publish incomplete output.
    CALL NA_CLOSE                       ; Close source before commit.
    JR   C,.DONE                        ; Driver will abort tentative output.
    LD   IX,(NA_CFG)                    ; Load the output provider selector.
    LD   C,(IX+NA_CFDST)                ; Select the provider that owns the generation.
    LD   DE,(NA_OHAND)                  ; Supply the tentative output handle.
    LD   A,ZT_COM                       ; Choose the provider's atomic COMMIT operation.
    CALL NA_HCALL                       ; Publish the completed object.
    JR   C,.DONE                        ; Preserve its failure status for the driver.
    XOR  A                              ; Clear handle and return status.
    LD   (NA_OHAND),A                   ; Clear the committed handle's low byte.
    LD   (NA_OHAND+1),A                 ; Allow a later BEGIN.
    RET                                 ; Publication succeeded.
.DONE: ; Return a failed fill, close or commit.
    RET                                 ; Propagate fill, close or commit result.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Abort an open generation and close any source handle. Attempt both cleanups;
; output-abort failure takes precedence over source-close failure.

HS_ABORT: ; Attempt source close and output abort.
    PUSH BC                             ; Save caller state during cleanup.
    PUSH DE                             ; Preserve the caller's DE pair.
    PUSH HL                             ; Preserve the caller's HL pair.
    PUSH IX                             ; Preserve the caller's IX register.
    PUSH IY                             ; Preserve the caller's IY register.
    CALL NA_CLOSE                       ; Attempt to close the current source object.
    LD   B,0                            ; No pending source-close error.
    JR   NC,.SOURCEOK                   ; Continue directly when source close succeeded.
    LD   B,A                            ; Save its error during output abort.
.SOURCEOK: ; Inspect the output handle after source cleanup.
    LD   DE,(NA_OHAND)                  ; Read the tentative output handle.
    LD   A,D                            ; Begin checking whether an output is open.
    OR   E                              ; Z means no output is open.
    JR   Z,.RESULT                      ; Return the source-close result.
    LD   IX,(NA_CFG)                    ; Load the output provider selector.
    LD   C,(IX+NA_CFDST)                ; Select the output provider.
    LD   A,ZT_ABORT                     ; Choose the provider's ABORT operation.
    PUSH BC                             ; Save source-close status in B.
    CALL NA_HCALL                       ; Discard tentative output.
    POP  BC                             ; Restore the pending source-close result.
    JR   C,.OUTFAIL                     ; Abort failure takes precedence.
    XOR  A                              ; Prepare zero for the now-closed local handle.
    LD   (NA_OHAND),A                   ; Clear accepted output handle.
    LD   (NA_OHAND+1),A                 ; Clear the output handle high byte.
    JR   .RESULT                        ; Return any source-close failure saved in B.
.OUTFAIL: ; Give output-abort failure precedence.
    LD   (NA_BYTE),A                    ; Save the abort failure.
    XOR  A                              ; Clear the local handle even when ABORT failed.
    LD   (NA_OHAND),A                   ; Remove the stale output handle's low byte.
    LD   (NA_OHAND+1),A                 ; Remove its high byte as well.
    LD   A,(NA_BYTE)                    ; Recover the abort failure.
    SCF                                 ; Return it as primary failure.
    JR   .DONE                          ; Restore caller registers.
.RESULT: ; Return any saved source-close failure.
    LD   A,B                            ; Recover any source-close error.
    OR   A                              ; Z means cleanup succeeded.
    JR   Z,.OK                          ; Return success without source error.
    SCF                                 ; Set carry for the source error.
    JR   .DONE                          ; Restore caller registers.
.OK: ; Return successful cleanup.
    XOR  A                              ; Return success with A zero and carry clear.
.DONE: ; Restore caller registers after cleanup.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX register.
    POP  HL                             ; Restore the caller's HL pair.
    POP  DE                             ; Restore the caller's DE pair.
    POP  BC                             ; Restore the caller's BC pair.
    RET                                 ; Return the selected cleanup result.

; Fail-closed transport replaced by a concrete platform binding.

;@@ATOM_OBJECT_GATEWAY_BEGIN@@
;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Fail closed until a platform replaces this named-object transport gateway.

NA_GATE: ; Return unavailable transport until the platform binds it.
    LD   A,ZT_UNAV                      ; Report that no platform gateway was installed.
    SCF                                 ; Fail closed without a platform binding.
    RET                                 ; Return the unavailable status to the caller.
;@@ATOM_OBJECT_GATEWAY_END@@

HS_CEND: ; End sink callbacks before adapter state.

; Adapter state. Handles are zero when closed. source cache identity is
; (part, base, length). Output cursor/high-water are relative to NA_TBASE. The
; remaining scratch words stage gaps, patch values, bytes and transfer counts.

NA_CFG:     DW      0                   ; Caller-owned nine-byte configuration address.
NA_WORK:    DW      0                   ; Base of the 399-byte common request workspace.
NA_SHAND:   DW      0                   ; Source handle, or zero when closed.
NA_OHAND:   DW      0                   ; Tentative output handle, or zero.
NA_SPART:   DB      $FF                 ; Source part, or $FF when invalid.
NA_PART:    DB      0                   ; Part staged across provider calls.
NA_OFF:     DW      0                   ; Requested source offset for a refill.
NA_CBASE:   DW      0                   ; Logical offset of cached byte zero.
NA_CLEN:    DB      0                   ; Number of valid cached bytes.
NA_TBASE:   DW      0                   ; Absolute target image base.
NA_OCURS:   DW      0                   ; Relative append cursor.
NA_OHIGH:   DW      0                   ; Exclusive initialised high water.
NA_GAP:     DW      0                   ; Zero-padding bytes still required by NA_FILL.
NA_WORD:    DW      0                   ; Little-endian value staged for a word PATCH.
NA_BYTE:    DB      0                   ; IMAGE, PATCH or saved error byte.
NA_COUNT:   DB      0                   ; Transfer count saved across calls.
NA_REND: ; End of the adapter's resident extent.
