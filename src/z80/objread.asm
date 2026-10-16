;=============================================================================
; Atom adapter for Z80 Tool Services named-object ABI 1
;=============================================================================
;
; The platform launcher calls objInit with IX pointing at a ten-byte
; configuration block, then calls AtomAssemble normally. The request, name,
; and transfer workspace must remain visible while the platform gateway
; temporarily selects another bank.
;
; This adapter binds both sides of Atom's platform boundary. The source side
; supplies the named objects in table order, one part each, and a 128-byte
; cache serves their bytes. A part ends where its object has no more bytes.
; The sink builds a tentative flat object: IMAGE appends and fills gaps,
; PATCH seeks within the initialised extent, and
; COMMIT/ABORT publish or discard the generation through the provider.
;
; Configuration:
;   +0 source-provider selector
;   +1 output-provider selector
;   +2 source-name table pointer (three bytes per part: pointer, byte length)
;   +4 output-name pointer
;   +6 output-name byte length
;   +7 common-workspace pointer
;   +9 number of source parts
;
; Common workspace (399 bytes): request 0..15, copied name 16..270, transfer
; buffer 271..398. Object names are byte strings, not zero-terminated text.

objFrom     EQU     0                   ; Config offset of the source-service selector.
objSink     EQU     1                   ; Config offset of the sink-service selector.
objTable    EQU     2                   ; Offset of the source-name table pointer.
objName     EQU     4                   ; Config offset of the output-name pointer.
objLen      EQU     6                   ; Config offset of the output-name byte length.
objArea     EQU     7                   ; Config offset of the common-workspace pointer.
objParts    EQU     9                   ; Config offset of the source-part count.
objSize     EQU     10                  ; Total byte size of the configuration block.

objPath     EQU     16                  ; Workspace offset of the copied object name.
objBuf      EQU     271                 ; Offset of the shared transfer buffer.
objChunk    EQU     128                 ; Transfer and cache capacity.
objSpace    EQU     399                 ; Request, name and transfer workspace size.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and retain configuration. The workspace may end at $10000 but
; cannot cross it. Reset handles and invalidate the source cache.

objInit: ; Validate and retain adapter configuration.
    PUSH IX                             ; Copy the configuration pointer.
    POP  HL                             ; HL now points at the configuration.
    LD   (objCfg),HL                    ; Retain it for later calls.
    LD   E,(IX+objArea)                 ; Read the common-workspace start, low byte.
    LD   D,(IX+objArea+1)               ; Read its high byte to complete the address.

    LD   A,D                            ; Begin testing whether the address is zero.
    OR   E                              ; Set Z only when both address bytes are zero.
    JR   Z,.invalid                     ; Reject a null workspace pointer.
    LD   (objWork),DE                   ; Retain the workspace start.
    LD   H,D                            ; Copy its high byte to HL.
    LD   L,E                            ; Complete the 16-bit copy without changing DE.
    LD   BC,objSpace                    ; Use the complete 399-byte workspace extent.
    ADD  HL,BC                          ; Calculate the exclusive end and detect wrap.

    JR   NC,.workOk                     ; A non-wrapping end lies below $10000.
    LD   A,H                            ; A wrapped end is legal only at $10000.
    OR   L                              ; Test for that zero result.
    JR   NZ,.invalid                    ; Reject a workspace that extends past memory.
.workOk: ; Validate the output name after workspace bounds.
    LD   A,(IX+objLen)                  ; Read the output-name byte length.
    OR   A                              ; An empty output name cannot be opened.
    JR   Z,.invalid                     ; Reject that incomplete configuration.

    XOR  A                              ; Zero marks closed handles and empty cache.
    LD   (objSrcId),A                   ; Clear the source handle low byte.
    LD   (objSrcId+1),A                 ; Clear the source handle high byte.
    LD   (objOutId),A                   ; Clear the output handle low byte.
    LD   (objOutId+1),A                 ; Clear the output handle high byte.
    LD   (objValid),A                   ; Invalidate any source-cache bytes.
    LD   (objNextP),A                   ; The first part is supplied first.
    LD   (objFail),A                    ; No source read has failed.
    LD   A,$FF                          ; No source part has been opened yet.
    LD   (objHeld),A                    ; Record the invalid part sentinel.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the adapter ready for its first request.

.invalid: ; Reject invalid configuration.
    LD   A,ZT_INV                       ; Report invalid configuration.
    SCF                                 ; Mark the validation failure in carry.
    RET                                 ; Return without opening a provider handle.

;@ROUTINE IN A OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Initialise the common request block. A is the operation. Clear all sixteen
; bytes first so no field from a prior provider call leaks into the next one;
; return HL at the request-block base for the gateway.

objPrep: ; Initialise a sixteen-byte service request.
    LD   C,A                            ; Save the operation while clearing.
    LD   HL,(objWork)                   ; Point HL at the common request record.
    LD   D,H                            ; Retain the base in DE.
    LD   E,L                            ; DE remains the request-record address.
    XOR  A                              ; Clear all prior request fields.
    LD   B,ZT_RQLEN                     ; Clear the full fixed-size request block.
.clear: ; Clear each request field before reuse.
    LD   (HL),A                         ; Remove any argument left by the prior call.
    INC  HL                             ; Advance to the next request byte.
    DJNZ .clear                         ; Repeat until all sixteen bytes are clear.

    LD   HL,(objWork)                   ; Return to the request base.
    LD   (HL),ZT_RQLEN                  ; Publish the record size expected by the ABI.
    INC  HL                             ; Advance to the ABI-version field.
    LD   (HL),ZT_ABI                    ; Identify the named-object service version.
    INC  HL                             ; Advance to the operation field.
    LD   (HL),C                         ; Store the operation saved before clearing A.
    EX   DE,HL                          ; Restore the request base as the return value.
    RET                                 ; Return HL at the block passed to the gateway.

;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Invoke the selected platform service. The platform replaces objGate or
; routes it to its native gateway. Carry reports transport/provider failure;
; the checked image's default gateway always fails closed.

objCall: ; Dispatch the selected provider request.
    CALL objGate                        ; Call the selected platform gateway.
    RET  C                              ; Preserve failure status and carry.
    OR   A                              ; Clear carry on accepted results.
    RET                                 ; Return the gateway's successful result in A.

;@ROUTINE IN A,B,C,HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open one named object. A=operation, C=provider selector, HL=name and B=byte
; length. Copy the name into common workspace before the gateway can switch
; banks. Success returns the provider's opaque handle in DE.

objOpen: ; Copy a name into bank-visible workspace.
    LD   D,A                            ; Save the operation during range checks.
    LD   A,B                            ; The name length is an unsigned byte in B.
    OR   A                              ; An empty name is invalid.
    JR   Z,.invalid                     ; Reject an empty name.
    PUSH DE                             ; Save D before forming the length.
    PUSH HL                             ; Save the original name pointer.
    LD   E,B                            ; Form the name length as a 16-bit offset.
    LD   D,0                            ; The high byte of the length is zero.
    ADD  HL,DE                          ; Check the exclusive end of the source name.

    JR   NC,.rangeOk                    ; Accept a non-wrapping end.
    LD   A,H                            ; A wrapped end is valid only at exactly $10000.
    OR   L                              ; Test the wrapped pointer for a zero result.
    JR   NZ,.rangeErr                   ; Reject a range past memory.
.rangeOk: ; Copy a name whose address range is valid.
    POP  HL                             ; Restore the name pointer for the copy.
    POP  DE                             ; Restore the saved operation from D.
    PUSH BC                             ; Preserve provider selector and name length.
    PUSH DE                             ; Save the open operation.
    LD   DE,(objWork)                   ; Start from the common-workspace base.
    PUSH DE                             ; Save the request base for IX.
    LD   A,E                            ; Begin the copied-name address.
    ADD  A,objPath                      ; Advance to the name area.
    LD   E,A                            ; Store the calculated low byte in DE.
    JR   NC,.nameOk                     ; Keep the high byte if no carry.
    INC  D                              ; Cross into the next page.
.nameOk: ; Copy after computing the common name address.
    LD   C,B                            ; Move the byte count into the low byte of BC.
    LD   B,0                            ; Extend the name length to BC.
    LDIR                                ; Copy before a bank switch.

    POP  IX                             ; IX now addresses the common request block.
    POP  DE                             ; Restore the requested open operation.
    POP  BC                             ; Restore selector C and name length B.
    LD   A,D                            ; Pass the saved operation to objPrep.
    PUSH BC                             ; Save selector and length.
    CALL objPrep                        ; Clear the record and return its base in HL.
    LD   DE,(objWork)                   ; Recover the workspace base.
    LD   A,E                            ; Begin forming workspace base plus objPath.
    ADD  A,objPath                      ; Compute the pointer low byte and its carry.
    LD   (IX+ZT_FPTR),A                 ; Point the request at the copied object name.
    LD   A,D                            ; Start the high-byte calculation from the base.
    ADC  A,0                            ; Add the low-byte carry.
    LD   (IX+ZT_FPTR+1),A               ; Complete the request's 16-bit name pointer.

    POP  BC                             ; Restore provider selector C and name length B.
    LD   (IX+ZT_FLEN),B                 ; Set the name length's low byte.
    LD   (IX+ZT_FLEN+1),0               ; Length fits one byte.
    CALL objCall                        ; Open the copied name.
    RET  C                              ; Do not read a failed open's handle.
    LD   E,(IX+ZT_FHND)                 ; Read the returned opaque handle's low byte.
    LD   D,(IX+ZT_FHND+1)               ; Read its high byte for the caller's DE result.
    XOR  A                              ; Mark the completed open as successful.
    RET                                 ; Return the provider handle in DE.
.rangeErr: ; Unwind saved registers after name-range failure.
    POP  HL                             ; Discard the saved source pointer.
    POP  DE                             ; Discard the saved operation before returning.
.invalid: ; Return invalid-name status.
    LD   A,ZT_INV                       ; Report an invalid name or request range.
    SCF                                 ; Mark the invalid request.
    RET                                 ; Return without publishing an open handle.

;@ROUTINE IN A,C,DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Submit a handle-only operation. A=operation, C=selector and DE=handle.

objHCall: ; Submit a handle-only request.
    PUSH BC                             ; Save the provider selector.
    PUSH DE                             ; Save the opaque handle.
    CALL objPrep                        ; Clear and set up the request.
    POP  DE                             ; Restore the handle for the request fields.
    LD   IX,(objWork)                   ; Address the request fields.
    LD   (IX+ZT_FHND),E                 ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle high byte.
    POP  BC                             ; Restore selector C before dispatch.
    JP   objCall                        ; Submit the handle-only request.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek an object to one 16-bit absolute byte offset. C=selector, DE=handle,
; HL=offset.

objSeek: ; Submit a seek to an absolute object offset.
    PUSH BC                             ; Save provider selector C.
    PUSH DE                             ; Save the object handle.
    PUSH HL                             ; Save the seek offset.
    LD   A,ZT_SEEK                      ; Choose the named-object SEEK operation.
    CALL objPrep                        ; Clear the request and return its base in HL.
    POP  DE                             ; Restore the seek offset.
    LD   IX,(objWork)                   ; Address the request fields.
    LD   (IX+ZT_FOFF),E                 ; Store the requested offset low byte.
    LD   (IX+ZT_FOFF+1),D               ; Store the requested offset high byte.
    POP  DE                             ; Restore the object handle.
    LD   (IX+ZT_FHND),E                 ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle high byte.
    POP  BC                             ; Restore selector C before dispatch.
    JP   objCall                        ; Submit the fully populated seek request.

;@ROUTINE IN A,B,C,DE OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Transfer through the fixed common 128-byte buffer. A=read/write, C=selector,
; DE=handle and B=count. Success returns the provider's result count in HL.

objXfer: ; Transfer through the common 128-byte buffer.
    PUSH AF                             ; Save the read/write operation.
    LD   A,B                            ; Copy the requested transfer count from B.
    LD   (objCount),A                   ; Save count outside the request.
    POP  AF                             ; Restore the operation for the request record.

    PUSH BC                             ; Preserve selector C and count B across objPrep.
    PUSH DE                             ; Preserve the provider's opaque object handle.
    CALL objPrep                        ; Clear the request and store this operation.
    LD   IX,(objWork)                   ; Address the request fields.
    POP  DE                             ; Restore the handle for its two request bytes.
    LD   (IX+ZT_FHND),E                 ; Store the handle's low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle's high byte.
    LD   HL,(objWork)                   ; Begin forming the transfer-buffer address.
    LD   DE,objBuf                      ; Add the buffer's workspace-relative offset.
    ADD  HL,DE                          ; HL now points to the shared 128-byte buffer.
    LD   (IX+ZT_FPTR),L                 ; Set transfer pointer, low byte.
    LD   (IX+ZT_FPTR+1),H               ; Set transfer pointer, high byte.

    LD   A,(objCount)                   ; Recover the requested transfer size.
    LD   (IX+ZT_FLEN),A                 ; Store it in the request length low byte.
    LD   (IX+ZT_FLEN+1),0               ; The request count is limited to one byte.
    POP  BC                             ; Restore selector C and count B for objCall.
    LD   HL,(objWork)                   ; Pass the request-record base to the gateway.
    CALL objCall                        ; Dispatch the selected read or write operation.
    RET  C                              ; Preserve a provider or transport failure.
    LD   L,(IX+ZT_FRES)                 ; Read the provider's result count, low byte.
    LD   H,(IX+ZT_FRES+1)               ; Complete the result count in HL.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Return the transfer result count in HL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Close the source object if open, then invalidate its part/cache
; identity only after the provider accepts CLOSE.

objClose: ; Close the current source handle.
    LD   DE,(objSrcId)                  ; Load the current source handle.
    LD   A,D                            ; Begin checking whether the handle is zero.
    OR   E                              ; Z means no source object needs closing.
    RET  Z                              ; Treat an already-closed source as success.
    LD   IX,(objCfg)                    ; Read the source provider from configuration.
    LD   C,(IX+objFrom)                 ; Select that provider for the close request.
    LD   A,ZT_CLOSE                     ; Choose the named-object CLOSE operation.
    CALL objHCall                       ; Submit CLOSE with the saved source handle.
    RET  C                              ; Keep the handle if CLOSE failed.
    XOR  A                              ; Prepare zero for the closed state.
    LD   (objSrcId),A                   ; Clear the source handle low byte.
    LD   (objSrcId+1),A                 ; Clear the source handle high byte.
    LD   (objValid),A                   ; Invalidate every byte in the shared cache.
    LD   A,$FF                          ; Mark that no source part owns the handle.
    LD   (objHeld),A                    ; Publish the invalid-part sentinel.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Finish after the provider accepted CLOSE.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open the source for part A. Each three-byte name-table entry is a pointer
; followed by a one-byte length. Only one source handle stays open.

objMount: ; Open the named source for one part ordinal.
    LD   (objPart),A                    ; Save the part while closing the old one.
    CALL objClose                       ; Only one source object may remain open.
    RET  C                              ; Propagate a failed close.
    LD   A,(objPart)                    ; Recover the requested part ordinal.
    LD   L,A                            ; Begin extending the ordinal to a 16-bit index.
    LD   H,0                            ; The ordinal's high byte is zero.
    LD   D,H                            ; Copy the ordinal into DE.
    LD   E,L                            ; DE now holds the original part ordinal.
    ADD  HL,HL                          ; Form twice the ordinal.
    ADD  HL,DE                          ; Form three times the ordinal.
    LD   IX,(objCfg)                    ; Address the source-name table pointer.
    LD   E,(IX+objTable)                ; Read the table pointer's low byte.
    LD   D,(IX+objTable+1)              ; Read its high byte.
    ADD  HL,DE                          ; Locate this part's pointer-and-length record.
    LD   E,(HL)                         ; Read the source-name pointer's low byte.
    INC  HL                             ; Advance to the pointer high byte.
    LD   D,(HL)                         ; Read the source-name pointer's high byte.
    INC  HL                             ; Advance to the one-byte name length.
    LD   B,(HL)                         ; Preserve the name length for objOpen.

    EX   DE,HL                          ; Put the name pointer in HL.
    LD   C,(IX+objFrom)                 ; Select the configured source provider.
    LD   A,ZT_OPEN                      ; Choose the named-object OPEN operation.
    CALL objOpen                        ; Open this part's named source object.
    RET  C                              ; Do not publish a handle after a failed open.
    LD   (objSrcId),DE                  ; Retain the provider's returned source handle.
    LD   A,(objPart)                    ; Recover the part associated with that handle.
    LD   (objHeld),A                    ; Associate handle with this part.
    XOR  A                              ; The new source has no cached bytes yet.
    LD   (objValid),A                   ; Force its first read through the provider.
    RET                                 ; Return success with carry clear.

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; AtomSourceOpenPart replacement. Supply the next part in table order from
; offset zero on line one, carry with A=0 when none remains, or carry with the status of a
; source read that failed.

objNext: ; Supply the next named source part.
    LD   A,(objFail)                    ; Did a source read fail?
    OR   A                              ; Zero means no failure.
    JR   NZ,.fail                       ; Report the failed read.
    LD   HL,(objCfg)                    ; Address the configuration.
    LD   DE,objParts                    ; Select the part count.
    ADD  HL,DE                          ; Address it.
    LD   A,(objNextP)                   ; Select the next part.
    CP   (HL)                           ; Is every part supplied?
    JR   NC,.none                       ; Yes: report that none remains.
    LD   HL,objNextP                    ; Address the part counter.
    INC  (HL)                           ; Select the following part next time.
    LD   HL,0                           ; Every named part starts at offset zero.
    LD   DE,1                           ; It starts on line one.
    OR   A                              ; Clear carry.
    RET                                 ; Return the part in A.
.none: ; Report that every part has been supplied.
    XOR  A                              ; A=0 means none remains.
.fail: ; Return the failure status in A.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; The driver finishes or aborts.

;@ROUTINE OUT A,CARRY
; AtomBinaryOpen and AtomBinaryRead replacement. This harness supplies no
; INCBIN files, so INCBIN fails as an unreadable file.

objNoBin: ; Refuse an INCBIN file.
    LD   A,ZT_INV                       ; Report the request as invalid.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The core reports the INCBIN line.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; AtomSourceReadByte replacement. It keeps a 128-byte source cache and one
; readable object handle. A part change closes and reopens by name. A miss
; seeks to the requested offset and fills from there, so the assembler may
; reread tokens without retaining a whole source part in Z80 memory. An empty
; read ends the part. A failed request also ends it, and objNext reports why.

objFetch: ; Read a source byte through the shared cache.
    PUSH BC                             ; Preserve the caller's BC pair.
    PUSH IX                             ; Keep the caller's IX across provider calls.
    PUSH IY                             ; Keep the caller's IY across provider calls.
    LD   (objPart),A                    ; Save the requested source-part ordinal.
    LD   (objWant),HL                   ; Save the logical byte offset to fetch.
    LD   B,A                            ; Save the requested part for comparison.
    LD   A,(objHeld)                    ; Load the open handle's part.
    CP   B                              ; Check whether this part is open.
    JR   Z,.have                        ; Reuse its handle.
    LD   A,B                            ; Pass the new part to the open helper.
    CALL objMount                       ; Open the requested source.
    JR   C,.fail                        ; Report the failed open.
.have: ; Check the current part cache for this offset.
    LD   HL,(objWant)                   ; Load the requested logical source offset.
    LD   DE,(objCache)                  ; Load the cache's first offset.
    OR   A                              ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                          ; Form a cache-relative offset.
    JR   C,.miss                        ; Before the cache: miss.
    LD   A,H                            ; Cache offsets must fit in the low byte.
    OR   A                              ; Test whether the relative offset exceeds 255.
    JR   NZ,.miss                       ; High byte set: outside cache.
    LD   A,(objValid)                   ; Load the cached byte count.
    CP   L                              ; Compare length and relative offset.
    JR   Z,.miss                        ; The first byte after the cache is a miss.
    JR   C,.miss                        ; Any offset beyond the cache length is a miss.
    LD   A,L                            ; Use the relative offset as index.
    LD   HL,(objWork)                   ; Start at the common workspace base.
    LD   DE,objBuf                      ; Select the shared transfer-buffer offset.
    ADD  HL,DE                          ; HL now points at the first cached byte.
    LD   E,A                            ; Extend the cache-relative byte index to DE.
    LD   D,0                            ; Its high byte is zero after the prior check.
    ADD  HL,DE                          ; Address the requested byte inside the cache.
    LD   A,(HL)                         ; Return the cached source byte.
    OR   A                              ; Clear carry and report the byte's zero flag.
    JR   .done                          ; Restore caller registers and return this byte.
.miss: ; Seek and refill on a cache miss.

; Refill at the requested offset. An empty successful read is the end of
; the part.

    LD   IX,(objCfg)                    ; Reload the source provider selector.
    LD   C,(IX+objFrom)                 ; Select the provider that owns the open handle.
    LD   DE,(objSrcId)                  ; Pass the current source handle to objSeek.
    LD   HL,(objWant)                   ; Seek to the exact requested logical offset.
    CALL objSeek                        ; Seek before refilling the cache.
    JR   C,.fail                        ; Keep cache bounds on seek failure.
    LD   IX,(objCfg)                    ; objSeek clobbered IX. reload config.
    LD   C,(IX+objFrom)                 ; Select the source provider for the transfer.
    LD   DE,(objSrcId)                  ; Pass the open object handle to objXfer.
    LD   B,objChunk                     ; Request up to 128 bytes.
    LD   A,ZT_READ                      ; Choose the named-object READ operation.
    CALL objXfer                        ; Refill from the requested byte.
    JR   C,.fail                        ; Do not publish a failed refill.
    LD   A,H                            ; Test the provider's result count.
    OR   L                              ; Z means it returned no bytes.
    JR   Z,.end                         ; The part has no more bytes.
    LD   A,L                            ; Use the result as cache length.
    LD   (objValid),A                   ; It fits the 128-byte cache.
    LD   HL,(objWant)                   ; Load the refill offset.
    LD   (objCache),HL                  ; Publish it as cache base.
    LD   HL,(objWork)                   ; Locate the first byte in the refilled buffer.
    LD   DE,objBuf                      ; Select the transfer buffer.
    ADD  HL,DE                          ; HL now addresses the newly read first byte.
    LD   A,(HL)                         ; Return the byte requested at the cache base.
    OR   A                              ; Clear carry and set Z according to that byte.
    JR   .done                          ; Restore caller registers before returning.
.fail: ; Keep the failed request's status for objNext.
    LD   (objFail),A                    ; objNext reports it to the driver.
.end: ; End the part.
    XOR  A                              ; A=0 with carry means no byte remains.
    SCF                                 ; Carry marks the end of the part.
.done: ; Restore caller registers after a source read.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX register.
    POP  BC                             ; Restore the caller's BC pair.
    RET                                 ; Return A, carry and zero status to Atom.
