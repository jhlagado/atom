;=============================================================================
; Atom adapter for Z80 Tool Services named-object ABI 1
;=============================================================================
;
; The platform launcher calls NA_INIT with IX pointing at a nine-byte
; configuration block, then calls AtomAssemble normally. The request, name,
; and transfer workspace must remain visible while the platform gateway
; temporarily selects another bank.
;
; This adapter binds both sides of Atom's platform boundary. The source side
; maps part ordinals to named objects. A 128-byte cache serves random reads.
; The sink builds a tentative flat object: IMAGE appends and fills gaps,
; PATCH seeks within the initialized extent, and
; COMMIT/ABORT publish or discard the generation through the provider.
;
; Configuration:
;   +0 source-provider selector
;   +1 output-provider selector
;   +2 source-name table pointer (three bytes per part: pointer, byte length)
;   +4 output-name pointer
;   +6 output-name byte length
;   +7 common-workspace pointer
;
; Common workspace (399 bytes): request 0..15, copied name 16..270, transfer
; buffer 271..398. Object names are byte strings, not zero-terminated text.

NA_CFSS EQU 0                 ; Config offset of the source-service selector.
NA_CFSK EQU 1                 ; Config offset of the sink-service selector.
NA_CFPT EQU 2                 ; Offset of the source-name table pointer.
NA_CFON EQU 4                 ; Config offset of the output-name pointer.
NA_CFOL EQU 6                 ; Config offset of the output-name byte length.
NA_CFWK EQU 7                 ; Config offset of the common-workspace pointer.
NA_CFLEN EQU 9                ; Total byte size of the configuration block.

NA_NAME EQU 16                ; Workspace offset of the copied object name.
NA_XFER EQU 271               ; Offset of the shared transfer buffer.
NA_XLEN EQU 128               ; Transfer and cache capacity.
NA_WLEN EQU 399               ; Request, name and transfer workspace size.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and retain configuration. The workspace may end at $10000 but
; cannot cross it. Reset handles and invalidate the source cache.

NA_INIT:
    PUSH IX                   ; Copy the configuration pointer.
    POP  HL                   ; HL now points at the configuration.
    LD   (NA_CFG),HL          ; Retain it for later calls.
    LD   E,(IX+NA_CFWK)       ; Read the common-workspace start, low byte.
    LD   D,(IX+NA_CFWK+1)     ; Read its high byte to complete the address.

    LD   A,D                  ; Begin testing whether the address is zero.
    OR   E                    ; Set Z only when both address bytes are zero.
    JR   Z,NA_INV             ; Reject a null workspace pointer.
    LD   (NA_WORK),DE          ; Retain the workspace start.
    LD   H,D                  ; Copy its high byte to HL.
    LD   L,E                  ; Complete the 16-bit copy without changing DE.
    LD   BC,NA_WLEN           ; Use the complete 399-byte workspace extent.
    ADD  HL,BC                ; Calculate the exclusive end and detect wrap.

    JR   NC,.WORKOK           ; A non-wrapping end lies below $10000.
    LD   A,H                  ; A wrapped end is legal only at $10000.
    OR   L                    ; Test for that zero result.
    JR   NZ,NA_INV            ; Reject a workspace that extends past memory.
.WORKOK:
    LD   A,(IX+NA_CFOL)       ; Read the output-name byte length.
    OR   A                    ; An empty output name cannot be opened.
    JR   Z,NA_INV             ; Reject that incomplete configuration.

    XOR  A                    ; Zero marks closed handles and empty cache.
    LD   (NA_SHAND),A         ; Clear the source handle low byte.
    LD   (NA_SHAND+1),A       ; Clear the source handle high byte.
    LD   (NA_OHAND),A         ; Clear the output handle low byte.
    LD   (NA_OHAND+1),A       ; Clear the output handle high byte.
    LD   (NA_CLEN),A          ; Invalidate any source-cache bytes.
    LD   A,$FF                ; No source part has been opened yet.
    LD   (NA_SPART),A         ; Record the invalid part sentinel.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Leave the adapter ready for its first request.

NA_INV:
    LD   A,ZT_INV             ; Report invalid configuration.
    SCF                       ; Mark the validation failure in carry.
    RET                       ; Return without opening a provider handle.

;@ROUTINE IN A OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Initialize the common request block. A is the operation. Clear all sixteen
; bytes first so no field from a prior provider call leaks into the next one;
; return HL at the request-block base for the gateway.

NA_REQ:
    LD   C,A                  ; Save the operation while clearing.
    LD   HL,(NA_WORK)         ; Point HL at the common request record.
    LD   D,H                  ; Retain the base in DE.
    LD   E,L                  ; DE remains the request-record address.
    XOR  A                    ; Clear all prior request fields.
    LD   B,ZT_RQLEN           ; Clear the full fixed-size request block.
.CLEAR:
    LD   (HL),A               ; Remove any argument left by the prior call.
    INC  HL                   ; Advance to the next request byte.
    DJNZ .CLEAR               ; Repeat until all sixteen bytes are clear.

    LD   HL,(NA_WORK)         ; Return to the request base.
    LD   (HL),ZT_RQLEN        ; Publish the record size expected by the ABI.
    INC  HL                   ; Advance to the ABI-version field.
    LD   (HL),ZT_ABI          ; Identify the named-object service version.
    INC  HL                   ; Advance to the operation field.
    LD   (HL),C               ; Store the operation saved before clearing A.
    EX   DE,HL                ; Restore the request base as the return value.
    RET                       ; Return HL at the block passed to the gateway.

;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Invoke the selected platform service. The platform replaces NA_GATE or
; routes it to its native gateway. Carry reports transport/provider failure;
; the checked image's default gateway always fails closed.

NA_CALL:
    CALL NA_GATE              ; Call the selected platform gateway.
    RET  C                    ; Preserve failure status and carry.
    OR   A                    ; Clear carry on accepted results.
    RET                       ; Return the gateway's successful result in A.

;@ROUTINE IN A,B,C,HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open one named object. A=operation, C=provider selector, HL=name and B=byte
; length. Copy the name into common workspace before the gateway can switch
; banks. Success returns the provider's opaque handle in DE.

NA_OPEN:
    LD   D,A                  ; Save the operation during range checks.
    LD   A,B                  ; The name length is an unsigned byte in B.
    OR   A                    ; An empty name is invalid.
    JR   Z,.INVALID           ; Reject an empty name.
    PUSH DE                   ; Save D before forming the length.
    PUSH HL                   ; Save the original name pointer.
    LD   E,B                  ; Form the name length as a 16-bit offset.
    LD   D,0                  ; The high byte of the length is zero.
    ADD  HL,DE                ; Check the exclusive end of the source name.

    JR   NC,.RANGEOK           ; Accept a non-wrapping end.
    LD   A,H                  ; A wrapped end is valid only at exactly $10000.
    OR   L                    ; Test the wrapped pointer for a zero result.
    JR   NZ,.RNGFAIL          ; Reject a range past memory.
.RANGEOK:
    POP  HL                   ; Restore the name pointer for the copy.
    POP  DE                   ; Restore the saved operation from D.
    PUSH BC                   ; Preserve provider selector and name length.
    PUSH DE                   ; Save the open operation.
    LD   DE,(NA_WORK)         ; Start from the common-workspace base.
    PUSH DE                   ; Save the request base for IX.
    LD   A,E                  ; Begin the copied-name address.
    ADD  A,NA_NAME            ; Advance to the name area.
    LD   E,A                  ; Store the calculated low byte in DE.
    JR   NC,.NAMEOK           ; Keep the high byte if no carry.
    INC  D                    ; Cross into the next page.
.NAMEOK:
    LD   C,B                  ; Move the byte count into the low byte of BC.
    LD   B,0                  ; Extend the name length to BC.
    LDIR                      ; Copy before a bank switch.

    POP  IX                   ; IX now addresses the common request block.
    POP  DE                   ; Restore the requested open operation.
    POP  BC                   ; Restore selector C and name length B.
    LD   A,D                  ; Pass the saved operation to NA_REQ.
    PUSH BC                   ; Save selector and length.
    CALL NA_REQ               ; Clear the record and return its base in HL.
    LD   DE,(NA_WORK)         ; Recover the workspace base.
    LD   A,E                  ; Begin forming workspace base plus NA_NAME.
    ADD  A,NA_NAME            ; Compute the pointer low byte and its carry.
    LD   (IX+ZT_FPTR),A       ; Point the request at the copied object name.
    LD   A,D                  ; Start the high-byte calculation from the base.
    ADC  A,0                  ; Add the low-byte carry.
    LD   (IX+ZT_FPTR+1),A     ; Complete the request's 16-bit name pointer.

    POP  BC                   ; Restore provider selector C and name length B.
    LD   (IX+ZT_FLEN),B       ; Set the name length's low byte.
    LD   (IX+ZT_FLEN+1),0     ; Length fits one byte.
    CALL NA_CALL              ; Open the copied name.
    RET  C                    ; Do not read a failed open's handle.
    LD   E,(IX+ZT_FHND)       ; Read the returned opaque handle's low byte.
    LD   D,(IX+ZT_FHND+1)     ; Read its high byte for the caller's DE result.
    XOR  A                    ; Mark the completed open as successful.
    RET                       ; Return the provider handle in DE.
.RNGFAIL:
    POP  HL                   ; Discard the saved source pointer.
    POP  DE                   ; Discard the saved operation before returning.
.INVALID:
    LD   A,ZT_INV             ; Report an invalid name or request range.
    SCF                       ; Mark the invalid request.
    RET                       ; Return without publishing an open handle.

;@ROUTINE IN A,C,DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Submit a handle-only operation. A=operation, C=selector and DE=handle.

NA_HCALL:
    PUSH BC                   ; Save the provider selector.
    PUSH DE                   ; Save the opaque handle.
    CALL NA_REQ               ; Clear and set up the request.
    POP  DE                   ; Restore the handle for the request fields.
    LD   IX,(NA_WORK)         ; Address the request fields.
    LD   (IX+ZT_FHND),E       ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle high byte.
    POP  BC                   ; Restore selector C before dispatch.
    JP   NA_CALL              ; Submit the handle-only request.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek an object to one 16-bit absolute byte offset. C=selector, DE=handle,
; HL=offset.

NA_SEEK:
    PUSH BC                   ; Save provider selector C.
    PUSH DE                   ; Save the object handle.
    PUSH HL                   ; Save the seek offset.
    LD   A,ZT_SEEK            ; Choose the named-object SEEK operation.
    CALL NA_REQ               ; Clear the request and return its base in HL.
    POP  DE                   ; Restore the seek offset.
    LD   IX,(NA_WORK)         ; Address the request fields.
    LD   (IX+ZT_FOFF),E       ; Store the requested offset low byte.
    LD   (IX+ZT_FOFF+1),D     ; Store the requested offset high byte.
    POP  DE                   ; Restore the object handle.
    LD   (IX+ZT_FHND),E       ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle high byte.
    POP  BC                   ; Restore selector C before dispatch.
    JP   NA_CALL              ; Submit the fully populated seek request.

;@ROUTINE IN A,B,C,DE OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Transfer through the fixed common 128-byte buffer. A=read/write, C=selector,
; DE=handle and B=count. Success returns the provider's result count in HL.

NA_TRANS:
    PUSH AF                   ; Save the read/write operation.
    LD   A,B                  ; Copy the requested transfer count from B.
    LD   (NA_COUNT),A         ; Save count outside the request.
    POP  AF                   ; Restore the operation for the request record.

    PUSH BC                   ; Preserve selector C and count B across NA_REQ.
    PUSH DE                   ; Preserve the provider's opaque object handle.
    CALL NA_REQ               ; Clear the request and store this operation.
    LD   IX,(NA_WORK)         ; Address the request fields.
    POP  DE                   ; Restore the handle for its two request bytes.
    LD   (IX+ZT_FHND),E       ; Store the handle's low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle's high byte.
    LD   HL,(NA_WORK)         ; Begin forming the transfer-buffer address.
    LD   DE,NA_XFER           ; Add the buffer's workspace-relative offset.
    ADD  HL,DE                ; HL now points to the shared 128-byte buffer.
    LD   (IX+ZT_FPTR),L       ; Set transfer pointer, low byte.
    LD   (IX+ZT_FPTR+1),H     ; Set transfer pointer, high byte.

    LD   A,(NA_COUNT)         ; Recover the requested transfer size.
    LD   (IX+ZT_FLEN),A       ; Store it in the request length low byte.
    LD   (IX+ZT_FLEN+1),0     ; The request count is limited to one byte.
    POP  BC                   ; Restore selector C and count B for NA_CALL.
    LD   HL,(NA_WORK)         ; Pass the request-record base to the gateway.
    CALL NA_CALL              ; Dispatch the selected read or write operation.
    RET  C                    ; Preserve a provider or transport failure.
    LD   L,(IX+ZT_FRES)       ; Read the provider's result count, low byte.
    LD   H,(IX+ZT_FRES+1)     ; Complete the result count in HL.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Return the transfer result count in HL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Close the source object if open, then invalidate its part/cache
; identity only after the provider accepts CLOSE.

NA_SCLOS:
    LD   DE,(NA_SHAND)        ; Load the current source handle.
    LD   A,D                  ; Begin checking whether the handle is zero.
    OR   E                    ; Z means no source object needs closing.
    RET  Z                    ; Treat an already-closed source as success.
    LD   IX,(NA_CFG)           ; Read the source provider from configuration.
    LD   C,(IX+NA_CFSS)       ; Select that provider for the close request.
    LD   A,ZT_CLOSE            ; Choose the named-object CLOSE operation.
    CALL NA_HCALL             ; Submit CLOSE with the saved source handle.
    RET  C                    ; Keep the handle if CLOSE failed.
    XOR  A                    ; Prepare zero for the closed state.
    LD   (NA_SHAND),A         ; Clear the source handle low byte.
    LD   (NA_SHAND+1),A       ; Clear the source handle high byte.
    LD   (NA_CLEN),A          ; Invalidate every byte in the shared cache.
    LD   A,$FF                ; Mark that no source part owns the handle.
    LD   (NA_SPART),A         ; Publish the invalid-part sentinel.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Finish after the provider accepted CLOSE.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open the source for part A. Each three-byte name-table entry is a pointer
; followed by a one-byte length. Only one source handle stays open.

NA_SOPEN:
    LD   (NA_WPART),A         ; Save the part while closing the old one.
    CALL NA_SCLOS             ; Only one source object may remain open.
    RET  C                    ; Propagate a failed close.
    LD   A,(NA_WPART)         ; Recover the requested part ordinal.
    LD   L,A                  ; Begin extending the ordinal to a 16-bit index.
    LD   H,0                  ; The ordinal's high byte is zero.
    LD   D,H                  ; Copy the ordinal into DE.
    LD   E,L                  ; DE now holds the original part ordinal.
    ADD  HL,HL                ; Form twice the ordinal.
    ADD  HL,DE                ; Form three times the ordinal.
    LD   IX,(NA_CFG)          ; Address the source-name table pointer.
    LD   E,(IX+NA_CFPT)       ; Read the table pointer's low byte.
    LD   D,(IX+NA_CFPT+1)     ; Read its high byte.
    ADD  HL,DE                ; Locate this part's pointer-and-length record.
    LD   E,(HL)               ; Read the source-name pointer's low byte.
    INC  HL                   ; Advance to the pointer high byte.
    LD   D,(HL)               ; Read the source-name pointer's high byte.
    INC  HL                   ; Advance to the one-byte name length.
    LD   B,(HL)               ; Preserve the name length for NA_OPEN.

    EX   DE,HL                ; Put the name pointer in HL.
    LD   C,(IX+NA_CFSS)       ; Select the configured source provider.
    LD   A,ZT_OPEN            ; Choose the named-object OPEN operation.
    CALL NA_OPEN              ; Open this part's named source object.
    RET  C                    ; Do not publish a handle after a failed open.
    LD   (NA_SHAND),DE        ; Retain the provider's returned source handle.
    LD   A,(NA_WPART)         ; Recover the part associated with that handle.
    LD   (NA_SPART),A         ; Associate handle with this part.
    XOR  A                    ; The new source has no cached bytes yet.
    LD   (NA_CLEN),A          ; Force its first read through the provider.
    RET                       ; Return success with carry clear.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; AtomSourceReadByte replacement. It keeps a 128-byte source cache and one
; readable object handle. A part change closes and reopens by name. A miss
; seeks to the requested offset and fills from there, so the assembler may
; reread tokens without retaining a whole source part in Z80 memory.

NA_SREAD:
    PUSH BC                   ; Preserve the caller's BC pair.
    PUSH IX                   ; Keep the caller's IX across provider calls.
    PUSH IY                   ; Keep the caller's IY across provider calls.
    LD   (NA_WPART),A         ; Save the requested source-part ordinal.
    LD   (NA_WOFF),HL         ; Save the logical byte offset to fetch.
    LD   B,A                  ; Save the requested part for comparison.
    LD   A,(NA_SPART)         ; Load the open handle's part.
    CP   B                    ; Check whether this part is open.
    JR   Z,.HAVE              ; Reuse its handle.
    LD   A,B                  ; Pass the new part to the open helper.
    CALL NA_SOPEN             ; Open the requested source.
    JR   C,.DONE              ; Restore registers after failure.
.HAVE:
    LD   HL,(NA_WOFF)         ; Load the requested logical source offset.
    LD   DE,(NA_CBASE)        ; Load the cache's first offset.
    OR   A                    ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                ; Form a cache-relative offset.
    JR   C,.MISS              ; Before the cache: miss.
    LD   A,H                  ; Cache offsets must fit in the low byte.
    OR   A                    ; Test whether the relative offset exceeds 255.
    JR   NZ,.MISS             ; High byte set: outside cache.
    LD   A,(NA_CLEN)           ; Load the cached byte count.
    CP   L                    ; Compare length and relative offset.
    JR   Z,.MISS              ; The first byte after the cache is a miss.
    JR   C,.MISS              ; Any offset beyond the cache length is a miss.
    LD   A,L                  ; Use the relative offset as index.
    LD   HL,(NA_WORK)         ; Start at the common workspace base.
    LD   DE,NA_XFER           ; Select the shared transfer-buffer offset.
    ADD  HL,DE                ; HL now points at the first cached byte.
    LD   E,A                  ; Extend the cache-relative byte index to DE.
    LD   D,0                  ; Its high byte is zero after the prior check.
    ADD  HL,DE                ; Address the requested byte inside the cache.
    LD   A,(HL)               ; Return the cached source byte.
    OR   A                    ; Clear carry and report the byte's zero flag.
    JR   .DONE                ; Restore caller registers and return this byte.
.MISS:

; Refill at the requested offset. An empty successful read is a storage
; failure: the caller's part descriptor promised a byte here.

    LD   IX,(NA_CFG)          ; Reload the source provider selector.
    LD   C,(IX+NA_CFSS)       ; Select the provider that owns the open handle.
    LD   DE,(NA_SHAND)        ; Pass the current source handle to NA_SEEK.
    LD   HL,(NA_WOFF)         ; Seek to the exact requested logical offset.
    CALL NA_SEEK              ; Seek before refilling the cache.
    JR   C,.DONE              ; Keep cache bounds on seek failure.
    LD   IX,(NA_CFG)          ; NA_SEEK clobbered IX; reload config.
    LD   C,(IX+NA_CFSS)       ; Select the source provider for the transfer.
    LD   DE,(NA_SHAND)        ; Pass the open object handle to NA_TRANS.
    LD   B,NA_XLEN            ; Request up to 128 bytes.
    LD   A,ZT_READ            ; Choose the named-object READ operation.
    CALL NA_TRANS             ; Refill from the requested byte.
    JR   C,.DONE              ; Do not publish a failed refill.
    LD   A,H                  ; Test the provider's result count.
    OR   L                    ; Z means it returned no bytes.
    JR   Z,.SHORT             ; Descriptor promised a byte here.
    LD   A,L                  ; Use the result as cache length.
    LD   (NA_CLEN),A          ; It fits the 128-byte cache.
    LD   HL,(NA_WOFF)         ; Load the refill offset.
    LD   (NA_CBASE),HL        ; Publish it as cache base.
    LD   HL,(NA_WORK)         ; Locate the first byte in the refilled buffer.
    LD   DE,NA_XFER           ; Select the transfer buffer.
    ADD  HL,DE                ; HL now addresses the newly read first byte.
    LD   A,(HL)               ; Return the byte requested at the cache base.
    OR   A                    ; Clear carry and set Z according to that byte.
    JR   .DONE                ; Restore caller registers before returning.
.SHORT:
    LD   A,ZT_STORE           ; Empty read violates the descriptor.
    SCF                       ; Distinguish failure from byte zero.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return A, carry and zero status to Atom.

;@ROUTINE IN B OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Write B buffered bytes to the open output. Require an exact result count
; and invalidate the source cache, which shares the transfer area.

NA_WRITE:
    LD   A,B                  ; Save the requested count.
    LD   (NA_COUNT),A         ; Keep it for the exact-result check.
    XOR  A                    ; Cache and output share a buffer.
    LD   (NA_CLEN),A          ; Invalidate cached source bytes.
    LD   IX,(NA_CFG)          ; Load the configured output-service selector.
    LD   C,(IX+NA_CFSK)       ; Select the output provider.
    LD   DE,(NA_OHAND)        ; Pass its open handle.
    LD   A,ZT_WRITE           ; Choose the named-object WRITE operation.
    CALL NA_TRANS             ; Write B bytes from the common transfer buffer.
    RET  C                    ; Propagate provider failure.
    LD   A,H                  ; Expected count is at most 128.
    OR   A                    ; Reject any result with a nonzero high byte.
    JR   NZ,.BAD              ; High byte cannot match.
    LD   A,(NA_COUNT)         ; Recover the exact byte count requested.
    CP   L                    ; Compare with returned count.
    JR   NZ,.BAD              ; Reject a partial write.
    XOR  A                    ; Return success with carry clear.
    RET                       ; The provider accepted every requested byte.
.BAD:
    LD   A,ZT_STORE           ; Report a partial transfer.
    SCF                       ; Mark the mismatch as an error for the caller.
    RET                       ; Caller updates cursor on success only.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Fill the tentative output from its current append cursor to relative offset
; HL. Reject backward IMAGE calls; write forward gaps as zero blocks
; no larger than the common 128-byte transfer buffer.

NA_FILL:
    EX   DE,HL                ; Save the target in DE.
    LD   HL,(NA_OCURS)        ; Load the current append cursor.
    OR   A                    ; Clear carry before comparing unsigned offsets.
    SBC  HL,DE                ; Compute cursor minus requested target.
    JR   C,.FORWARD           ; Cursor is behind target.
    JR   Z,.DONE              ; Target equals cursor.
    LD   A,ZT_INV             ; IMAGE cannot move the append cursor backwards.
    SCF                       ; Report the invalid backward append.
    RET                       ; Leave the output object unchanged.
.FORWARD:
    EX   DE,HL                ; Restore the requested target in HL.
    LD   DE,(NA_OCURS)        ; Load the lower current cursor for subtraction.
    OR   A                    ; Clear carry before computing the positive gap.
    SBC  HL,DE                ; HL now holds target minus current cursor.

; HL now holds the positive gap.

    LD   (NA_GAP),HL          ; Save remaining zero-fill length.
.LOOP:
    LD   HL,(NA_GAP)          ; Reload the remaining gap.
    LD   A,H                  ; Nonzero high byte means at least 256.
    OR   L                    ; Z means the entire gap has been emitted.
    JR   Z,.DONE              ; Finish when no padding bytes remain.
    LD   B,NA_XLEN            ; Default to a full 128-byte block.
    LD   A,H                  ; Check whether the remaining gap reaches 256.
    OR   A                    ; Test whether gap is under 256.
    JR   NZ,.COUNT             ; At least 256: keep a full block.
    LD   A,L                  ; Check the low-byte remainder.
    CP   NA_XLEN              ; Does a full block fit?
    JR   NC,.COUNT             ; Keep B=128 if it does.
    LD   B,A                  ; Otherwise use the remainder.
.COUNT:
    LD   A,B                  ; Save block size across the write.
    LD   (NA_COUNT),A         ; Reuse it for cursor and gap.
    LD   HL,(NA_WORK)         ; Start at the common-workspace base.
    LD   DE,NA_XFER           ; Select the shared transfer buffer.
    ADD  HL,DE                ; HL now points at the first buffer byte.
    XOR  A                    ; Fill every selected byte with zero.
.ZERO:
    LD   (HL),A               ; Store one zero padding byte.
    INC  HL                   ; Advance within the transfer buffer.
    DJNZ .ZERO                ; Stop after exactly B bytes have been cleared.
    LD   A,(NA_COUNT)         ; Restore the selected block size.
    LD   B,A                  ; Pass that size to the exact-count writer.
    CALL NA_WRITE             ; Append the zero block to the output object.
    RET  C                    ; Do not advance offsets after a failed write.
    LD   A,(NA_COUNT)         ; Recover the accepted block size.
    LD   E,A                  ; Extend it to a 16-bit cursor increment.
    LD   D,0                  ; The block size is at most 128.
    LD   HL,(NA_OCURS)        ; Load the append cursor before this block.
    ADD  HL,DE                ; Advance the cursor by the bytes just accepted.
    LD   (NA_OCURS),HL        ; Publish the new append position.
    LD   HL,(NA_GAP)          ; Reload the remaining zero-fill distance.
    OR   A                    ; Clear carry for subtraction.
    SBC  HL,DE                ; Remove this block from the gap still to write.
    LD   (NA_GAP),HL          ; Preserve the remainder for the next iteration.
    JR   .LOOP                ; Emit another block until the gap reaches zero.
.DONE:
    XOR  A                    ; Return success with carry clear.
    RET                       ; Cursor now equals the target.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Convert absolute target address HL to the flat output-relative offset.

NA_REL:
    LD   DE,(NA_TBASE)        ; Load the flat image base.
    OR   A                    ; Clear carry before subtraction.
    SBC  HL,DE                ; Form the image-relative offset.
    RET  NC                   ; Return offset when nonnegative.
    LD   A,ZT_INV             ; A target below the image base is invalid.
    SCF                       ; Return the range failure through carry.
    RET                       ; Preserve the invalid-target status in A.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek the output object to relative offset HL.

NA_OSEEK:
    LD   IX,(NA_CFG)          ; Load adapter configuration.
    LD   C,(IX+NA_CFSK)       ; Select the output provider.
    LD   DE,(NA_OHAND)        ; Supply its current handle to the seek helper.
    JP   NA_SEEK              ; Reuse the common request and offset setup.

; Begin a tentative flat-image object. Capture the descriptor's target base,
; reject a nested generation, and reset append/high-water offsets after OPEN.

HS_SCBEG:                      ; Mark the first sink callback in the adapter.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a tentative output object and reset its append and high-water offsets.

HS_BEG:
    PUSH BC                   ; Save caller state across provider calls.
    PUSH DE                   ; DE will hold the opened handle.
    PUSH HL                   ; Preserve the caller's address and byte values.
    PUSH IX                   ; Save the Atom descriptor pointer.
    PUSH IY                   ; Preserve IY across the named-object gateway.
    LD   A,(NA_OHAND)         ; Read the tentative output handle's low byte.
    LD   B,A                  ; Keep it while checking the high byte.
    LD   A,(NA_OHAND+1)       ; Read the tentative output handle's high byte.
    OR   B                    ; Nonzero means a generation is open.
    JR   NZ,.STATE             ; Reject a nested output generation.
    LD   L,(IX+11)            ; Read the descriptor's target base, low byte.
    LD   H,(IX+12)            ; Complete the target-base address.
    LD   (NA_TBASE),HL        ; Retain the absolute base used by NA_REL.
    LD   IX,(NA_CFG)          ; Switch IX to adapter configuration.
    LD   L,(IX+NA_CFON)       ; Read output-name pointer, low byte.
    LD   H,(IX+NA_CFON+1)     ; Read output-name pointer, high byte.
    LD   B,(IX+NA_CFOL)       ; Supply its configured byte length to NA_OPEN.
    LD   C,(IX+NA_CFSK)       ; Select the output provider for the new object.
    LD   A,ZT_BEGIN           ; Begin a tentative output object.
    CALL NA_OPEN              ; Open the uncommitted generation.
    JR   C,.DONE              ; Restore caller state on failure.
    LD   (NA_OHAND),DE        ; Retain the tentative generation's handle.
    LD   HL,0                 ; The new image begins at relative offset zero.
    LD   (NA_OCURS),HL        ; Reset its append cursor.
    LD   (NA_OHIGH),HL        ; Reset its initialized high-water extent.
    XOR  A                    ; Return success with carry clear.
    JR   .DONE                ; Restore saved caller state before returning.
.STATE:
    LD   A,ZT_INV             ; Reject a nested generation.
    SCF                       ; Mark the nested begin as invalid.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's descriptor pointer.
    POP  HL                   ; Restore the caller's HL input pair.
    POP  DE                   ; Restore the caller's DE input pair.
    POP  BC                   ; Restore the caller's BC input pair.
    RET                       ; Return the begin status in A and carry.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Append one IMAGE byte. Address class C must be zero for this flat target.
; Convert the address to a flat offset, zero-fill any forward gap, write
; the byte and advance both cursor and high-water mark.

HS_IB:
    PUSH BC                   ; Save address class and caller BC.
    PUSH IX                   ; Preserve IX across the output provider call.
    PUSH IY                   ; Preserve IY across the output provider call.
    LD   (NA_BYTE),A          ; Save the IMAGE byte before address validation.
    LD   A,C                  ; The flat sink accepts only address class zero.
    OR   A                    ; Test the class without changing C.
    JR   NZ,.BAD              ; Reject banked or otherwise non-flat addresses.

    CALL NA_REL               ; Form the image-relative offset.
    JR   C,.DONE              ; Reject an address below the image base.
    CALL NA_FILL              ; Zero-fill up to this offset.
    JR   C,.DONE              ; Stop after a failed gap fill.

    LD   HL,(NA_WORK)         ; Start at the shared transfer workspace.
    LD   DE,NA_XFER           ; Select the buffer used by the provider.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   A,(NA_BYTE)          ; Recover the caller's IMAGE value.
    LD   (HL),A               ; Stage one byte for NA_WRITE.
    LD   B,1                  ; The IMAGE operation appends exactly one byte.
    CALL NA_WRITE             ; Require the provider to accept that byte.
    JR   C,.DONE              ; Do not advance cursor after failure.

    LD   HL,(NA_OCURS)        ; Read the cursor after any preceding zero fill.
    INC  HL                   ; Advance past the newly appended IMAGE byte.
    LD   (NA_OCURS),HL        ; Publish the next append position.
    LD   (NA_OHIGH),HL        ; Advance initialized high water.
    XOR  A                    ; Return success with carry clear.
    JR   .DONE                ; Restore caller registers before returning.
.BAD:
    LD   A,ZT_INV             ; Reject a non-flat address class.
    SCF                       ; Mark the rejected IMAGE operation as invalid.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return the IMAGE result in A and carry.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier byte. C must be zero and the address must lie below
; initialized high water. Seek, replace one byte, then restore the
; append cursor on success; a provider failure is left for driver-level abort.

HS_PB:
    PUSH BC                   ; Save address class and caller BC.
    PUSH IX                   ; Preserve IX across provider calls.
    PUSH IY                   ; Preserve IY across provider calls.
    LD   (NA_BYTE),A          ; Save the replacement byte before validation.
    LD   A,C                  ; A flat patch must use address class zero.
    OR   A                    ; Test the class while keeping C unchanged.
    JR   NZ,.BAD              ; Reject a patch for a banked address.

    CALL NA_REL               ; Form the relative patch offset.
    JR   C,.DONE              ; Reject a patch below the image base.
    LD   DE,(NA_OHIGH)        ; Load exclusive initialized end.
    PUSH HL                   ; Save offset for the seek.
    OR   A                    ; Clear carry for comparison.
    SBC  HL,DE                ; Compare offset with high water.
    POP  HL                   ; Restore the patch offset after the comparison.
    JR   NC,.BAD              ; No byte exists at or beyond high water.

    CALL NA_OSEEK             ; Seek to the byte being patched.
    JR   C,.DONE              ; Do not stage after failed seek.
    LD   HL,(NA_WORK)         ; Start at the shared transfer workspace.
    LD   DE,NA_XFER           ; Select the provider's transfer buffer.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   A,(NA_BYTE)          ; Recover the replacement value.
    LD   (HL),A               ; Stage the one-byte patch for NA_WRITE.
    LD   B,1                  ; The patch replaces exactly one output byte.
    CALL NA_WRITE             ; Require an exact one-byte provider write.
    JR   C,.DONE              ; Let driver abort after failed write.

    LD   HL,(NA_OCURS)        ; Load the append cursor.
    CALL NA_OSEEK             ; Restore provider position.
    JR   .DONE                ; Return the restoration result to the driver.
.BAD:
    LD   A,ZT_INV             ; Reject class or patch range.
    SCF                       ; Mark the invalid patch.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return patch or provider status.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier little-endian word. Address class C must be zero and both
; bytes must lie below high water. Write low byte first, then restore append
; cursor on success; a provider failure is left for driver-level abort.

HS_PW:
    PUSH IX                   ; Preserve the Atom descriptor pointer.
    PUSH IY                   ; Preserve IY across output-provider calls.
    LD   (NA_WORD),HL         ; Save the little-endian patch value.
    LD   A,C                  ; A flat word patch must use address class zero.
    OR   A                    ; Test the class while keeping C unchanged.
    JR   NZ,.BAD              ; Reject a word patch for a banked address.

    EX   DE,HL                ; Move the absolute patch address from DE to HL.
    CALL NA_REL               ; Convert that address to a flat image offset.
    JR   C,.DONE              ; Reject an address below the base.
    PUSH HL                   ; Preserve the first-byte offset for NA_OSEEK.
    INC  HL                   ; Check the second byte's offset.
    LD   DE,(NA_OHIGH)        ; Load exclusive initialized end.
    OR   A                    ; Clear carry for comparison.
    SBC  HL,DE                ; Compare second byte with high water.
    POP  HL                   ; Restore the first-byte offset for the seek.
    JR   NC,.BAD              ; Reject beyond the initialized extent.

    CALL NA_OSEEK             ; Position the provider at the word's low byte.
    JR   C,.DONE              ; Do not write after failed seek.
    LD   HL,(NA_WORK)         ; Start at the common workspace base.
    LD   DE,NA_XFER           ; Select the provider's transfer buffer.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   DE,(NA_WORD)         ; Recover the patch value.
    LD   (HL),E               ; Stage the low byte at the patch offset.
    INC  HL                   ; Advance to the next transfer-buffer byte.
    LD   (HL),D               ; Stage the high byte after the low byte.
    LD   B,2                  ; The word patch replaces exactly two bytes.
    CALL NA_WRITE             ; Require an exact two-byte provider write.
    JR   C,.DONE              ; Let driver abort on failure.

    LD   HL,(NA_OCURS)        ; Load the append cursor.
    CALL NA_OSEEK             ; Restore provider position.
    JR   .DONE                ; Return the restoration result to the driver.
.BAD:
    LD   A,ZT_INV             ; Reject class or word range.
    SCF                       ; Mark the rejected patch as invalid.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX descriptor pointer.
    RET                       ; Return patch or provider status.

;@ROUTINE IN IX,HL,DE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Commit the greater of final cursor and highest IMAGE extent. First
; materialize trailing DS/ORG reservations, close the source object, then
; ask the provider to publish the tentative output atomically.

HS_CMT:
    CALL NA_REL               ; Form the final relative cursor.
    JR   C,.DONE              ; Reject a cursor below image base.
    LD   DE,(NA_OHIGH)        ; Load the exclusive end established by IMAGE.
    PUSH HL                   ; Save final cursor for the fill.
    OR   A                    ; Clear carry before comparing unsigned offsets.
    SBC  HL,DE                ; Compare cursor with high water.
    POP  HL                   ; Restore the final cursor.
    JR   NC,.LIMIT             ; Use cursor if it reaches high water.
    EX   DE,HL                ; Otherwise fill to high water.
.LIMIT:
    CALL NA_FILL              ; Zero-fill the trailing reservation.
    JR   C,.DONE              ; Do not publish incomplete output.
    CALL NA_SCLOS             ; Close source before commit.
    JR   C,.DONE              ; Driver will abort tentative output.
    LD   IX,(NA_CFG)          ; Load the output provider selector.
    LD   C,(IX+NA_CFSK)       ; Select the provider that owns the generation.
    LD   DE,(NA_OHAND)        ; Supply the tentative output handle.
    LD   A,ZT_COM             ; Choose the provider's atomic COMMIT operation.
    CALL NA_HCALL             ; Publish the completed object.
    JR   C,.DONE              ; Preserve its failure status for the driver.
    XOR  A                    ; Clear handle and return status.
    LD   (NA_OHAND),A         ; Clear the committed handle's low byte.
    LD   (NA_OHAND+1),A       ; Allow a later BEGIN.
    RET                       ; Publication succeeded.
.DONE:
    RET                       ; Propagate fill, close or commit result.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Abort an open generation and close any source handle. Attempt both cleanups;
; output-abort failure takes precedence over source-close failure.

HS_ABORT:
    PUSH BC                   ; Save caller state during cleanup.
    PUSH DE                   ; Preserve the caller's DE pair.
    PUSH HL                   ; Preserve the caller's HL pair.
    PUSH IX                   ; Preserve the caller's IX register.
    PUSH IY                   ; Preserve the caller's IY register.
    CALL NA_SCLOS             ; Attempt to close the current source object.
    LD   B,0                  ; No pending source-close error.
    JR   NC,.SOURCEOK         ; Continue directly when source close succeeded.
    LD   B,A                  ; Save its error during output abort.
.SOURCEOK:
    LD   DE,(NA_OHAND)        ; Read the tentative output handle.
    LD   A,D                  ; Begin checking whether an output is open.
    OR   E                    ; Z means no output is open.
    JR   Z,.RESULT            ; Return the source-close result.
    LD   IX,(NA_CFG)          ; Load the output provider selector.
    LD   C,(IX+NA_CFSK)       ; Select the output provider.
    LD   A,ZT_ABORT           ; Choose the provider's ABORT operation.
    PUSH BC                   ; Save source-close status in B.
    CALL NA_HCALL             ; Discard tentative output.
    POP  BC                   ; Restore the pending source-close result.
    JR   C,.ABFAIL            ; Abort failure takes precedence.
    XOR  A                    ; Prepare zero for the now-closed local handle.
    LD   (NA_OHAND),A         ; Clear accepted output handle.
    LD   (NA_OHAND+1),A       ; Clear the output handle high byte.
    JR   .RESULT              ; Return any source-close failure saved in B.
.ABFAIL:
    LD   (NA_BYTE),A          ; Save the abort failure.
    XOR  A                    ; Clear the local handle even when ABORT failed.
    LD   (NA_OHAND),A         ; Remove the stale output handle's low byte.
    LD   (NA_OHAND+1),A       ; Remove its high byte as well.
    LD   A,(NA_BYTE)          ; Recover the abort failure.
    SCF                       ; Return it as primary failure.
    JR   .DONE                ; Restore caller registers.
.RESULT:
    LD   A,B                  ; Recover any source-close error.
    OR   A                    ; Z means cleanup succeeded.
    JR   Z,.OK                ; Return success without source error.
    SCF                       ; Set carry for the source error.
    JR   .DONE                ; Restore caller registers.
.OK:
    XOR  A                    ; Return success with A zero and carry clear.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  HL                   ; Restore the caller's HL pair.
    POP  DE                   ; Restore the caller's DE pair.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return the selected cleanup result.

; Fail-closed transport replaced by a concrete platform binding.

;@@ATOM_OBJECT_GATEWAY_BEGIN@@
;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Fail closed until a platform replaces this named-object transport gateway.

NA_GATE:
    LD   A,ZT_UNAV            ; Report that no platform gateway was installed.
    SCF                       ; Fail closed without a platform binding.
    RET                       ; Return the unavailable status to the caller.
;@@ATOM_OBJECT_GATEWAY_END@@

HS_SCEND:                      ; End sink callbacks before adapter state.

; Adapter state. Handles are zero when closed; source cache identity is
; (part, base, length). Output cursor/high-water are relative to NA_TBASE. The
; remaining scratch words stage gaps, patch values, bytes and transfer counts.

NA_CFG: DW 0                  ; Caller-owned nine-byte configuration address.
NA_WORK: DW 0                 ; Base of the 399-byte common request workspace.
NA_SHAND: DW 0                ; Source handle, or zero when closed.
NA_OHAND: DW 0                ; Tentative output handle, or zero.
NA_SPART: DB $FF              ; Source part, or $FF when invalid.
NA_WPART: DB 0                ; Part staged across provider calls.
NA_WOFF: DW 0                 ; Requested source offset for a refill.
NA_CBASE: DW 0                ; Logical offset of cached byte zero.
NA_CLEN: DB 0                 ; Number of valid cached bytes.
NA_TBASE: DW 0                ; Absolute target image base.
NA_OCURS: DW 0                ; Relative append cursor.
NA_OHIGH: DW 0                ; Exclusive initialized high water.
NA_GAP: DW 0                  ; Zero-padding bytes still required by NA_FILL.
NA_WORD: DW 0                 ; Little-endian value staged for a word PATCH.
NA_BYTE: DB 0                 ; IMAGE, PATCH or saved error byte.
NA_COUNT: DB 0                ; Transfer count saved across calls.
NA_REND:                      ; End of the adapter's resident extent.
