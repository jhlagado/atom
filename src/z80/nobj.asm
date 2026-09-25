;==============================================================================
; Atom adapter for Z80 Tool Services named-object ABI 1
;==============================================================================
;
; The platform launcher calls NA_INIT with IX pointing at a nine-byte
; configuration block, then calls AtomAssemble normally. The request, name,
; and transfer workspace must remain visible while the platform gateway
; temporarily selects another bank.
;
; This adapter binds both sides of Atom's platform boundary. The source side
; maps part ordinals to named objects and serves random logical byte reads through
; one 128-byte cache. The sink side builds one tentative flat object: IMAGE calls
; append and zero-fill gaps, PATCH calls seek within the initialized extent, and
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
NA_CFPT EQU 2                 ; Config offset of the source-name table pointer.
NA_CFON EQU 4                 ; Config offset of the output-name pointer.
NA_CFOL EQU 6                 ; Config offset of the output-name byte length.
NA_CFWK EQU 7                 ; Config offset of the common-workspace pointer.
NA_CFLEN EQU 9                ; Total byte size of the configuration block.

NA_NAME EQU 16                ; Workspace offset of the copied object name.
NA_XFER EQU 271               ; Workspace offset of the shared transfer buffer.
NA_XLEN EQU 128               ; Transfer-buffer capacity and source-cache size.
NA_WLEN EQU 399               ; Full request, name and transfer workspace extent.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and retain the configuration. The common workspace may end exactly at
; $10000 but may not wrap past it. Reset handles and invalidate the source cache.

NA_INIT:
    PUSH IX                   ; Preserve the configuration address while copying it.
    POP  HL                   ; HL now carries the configuration block pointer.
    LD   (NA_CFG),HL          ; Keep the block available to later service calls.
    LD   E,(IX+NA_CFWK)       ; Read the common-workspace start, low byte.
    LD   D,(IX+NA_CFWK+1)     ; Read its high byte to complete the address.

    LD   A,D                  ; Begin testing whether the address is zero.
    OR   E                    ; Set Z only when both address bytes are zero.
    JR   Z,NA_INV             ; Reject a null workspace pointer.
    LD   (NA_WORK),DE          ; Retain the workspace start for all adapter calls.
    LD   H,D                  ; Copy the start into HL for the end calculation.
    LD   L,E                  ; Complete the 16-bit copy without changing DE.
    LD   BC,NA_WLEN           ; Use the complete 399-byte workspace extent.
    ADD  HL,BC                ; Calculate the exclusive end and detect wrap.

    JR   NC,.WORKOK           ; A non-wrapping end lies below $10000.
    LD   A,H                  ; A wrapped end is legal only when it equals $10000.
    OR   L                    ; Test whether the wrapped 16-bit result is zero.
    JR   NZ,NA_INV            ; Reject a workspace that extends past memory.
.WORKOK:
    LD   A,(IX+NA_CFOL)       ; Read the output-name byte length.
    OR   A                    ; An empty output name cannot be opened.
    JR   Z,NA_INV             ; Reject that incomplete configuration.

    XOR  A                    ; Use zero to mark closed handles and an empty cache.
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
    LD   A,ZT_INV             ; Return the shared invalid-configuration status.
    SCF                       ; Mark the validation failure in carry.
    RET                       ; Return without opening a provider handle.

;@ROUTINE IN A OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Initialize the common request block. A is the operation. Clear all sixteen
; bytes first so no field from a prior provider call leaks into the next one;
; return HL at the request-block base for the gateway.

NA_REQ:
    LD   C,A                  ; Preserve the requested operation while clearing.
    LD   HL,(NA_WORK)         ; Point HL at the common request record.
    LD   D,H                  ; Preserve the base in DE as the clear loop advances.
    LD   E,L                  ; DE remains the request-record address.
    XOR  A                    ; Supply zero for every field in the old request.
    LD   B,ZT_RQLEN           ; Clear the full fixed-size request block.
.CLEAR:
    LD   (HL),A               ; Remove any argument left by the prior call.
    INC  HL                   ; Advance to the next request byte.
    DJNZ .CLEAR               ; Repeat until all sixteen bytes are clear.

    LD   HL,(NA_WORK)         ; Return to the first byte of the request record.
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
    CALL NA_GATE              ; Dispatch through the platform's selected gateway.
    RET  C                    ; Preserve the provider's failure status and carry.
    OR   A                    ; Ensure an accepted result returns with carry clear.
    RET                       ; Return the gateway's successful result in A.

;@ROUTINE IN A,B,C,HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open one named object. A=operation, C=provider selector, HL=name and B=byte
; length. Copy the name into common workspace before the gateway can switch
; banks. Success returns the provider's opaque handle in DE.

NA_OPEN:
    LD   D,A                  ; Save the operation while checking the name range.
    LD   A,B                  ; The name length is an unsigned byte in B.
    OR   A                    ; A zero-length name is never a valid object name.
    JR   Z,.INVALID           ; Return the invalid-request status for empty names.
    PUSH DE                   ; Save the operation before D becomes a length high byte.
    PUSH HL                   ; Keep the original name pointer for the later copy.
    LD   E,B                  ; Form the name length as a 16-bit offset.
    LD   D,0                  ; The high byte of the length is zero.
    ADD  HL,DE                ; Check the exclusive end of the source name.

    JR   NC,.RANGEOK           ; No carry means the end does not wrap past memory.
    LD   A,H                  ; A wrapped end is valid only at exactly $10000.
    OR   L                    ; Test the wrapped pointer for a zero result.
    JR   NZ,.RNGFAIL          ; Reject a name range that crosses the address space.
.RANGEOK:
    POP  HL                   ; Restore the name pointer for the copy.
    POP  DE                   ; Restore the saved operation from D.
    PUSH BC                   ; Preserve provider selector and name length.
    PUSH DE                   ; Keep the operation safe while DE holds addresses.
    LD   DE,(NA_WORK)         ; Start from the common-workspace base.
    PUSH DE                   ; Save that base for the request-record IX pointer.
    LD   A,E                  ; Calculate the copied-name address from its low byte.
    ADD  A,NA_NAME            ; Skip request fields to the name area at offset 16.
    LD   E,A                  ; Store the calculated low byte in DE.
    JR   NC,.NAMEOK           ; No low-byte carry leaves the high byte unchanged.
    INC  D                    ; Carry advances the destination into the next page.
.NAMEOK:
    LD   C,B                  ; Move the byte count into the low byte of BC.
    LD   B,0                  ; LDIR now copies exactly the one-byte name length.
    LDIR                      ; Copy the name before the gateway can switch banks.

    POP  IX                   ; IX now addresses the common request block.
    POP  DE                   ; Restore the requested open operation.
    POP  BC                   ; Restore selector C and name length B.
    LD   A,D                  ; Pass the saved operation to NA_REQ.
    PUSH BC                   ; Preserve selector and length across request setup.
    CALL NA_REQ               ; Clear the record and return its base in HL.
    LD   DE,(NA_WORK)         ; Recover the workspace base for the name pointer.
    LD   A,E                  ; Begin forming workspace base plus NA_NAME.
    ADD  A,NA_NAME            ; Compute the pointer low byte and its carry.
    LD   (IX+ZT_FPTR),A       ; Point the request at the copied object name.
    LD   A,D                  ; Start the high-byte calculation from the base.
    ADC  A,0                  ; Include carry from adding the name-area offset.
    LD   (IX+ZT_FPTR+1),A     ; Complete the request's 16-bit name pointer.

    POP  BC                   ; Restore provider selector C and name length B.
    LD   (IX+ZT_FLEN),B       ; Supply the name byte count in the low length byte.
    LD   (IX+ZT_FLEN+1),0     ; Names are byte-counted and never exceed 255 bytes.
    CALL NA_CALL              ; Ask the selected provider to open the copied name.
    RET  C                    ; Return provider failure without reading its handle.
    LD   E,(IX+ZT_FHND)       ; Read the returned opaque handle's low byte.
    LD   D,(IX+ZT_FHND+1)     ; Read its high byte for the caller's DE result.
    XOR  A                    ; Mark the completed open as successful.
    RET                       ; Return the provider handle in DE.
.RNGFAIL:
    POP  HL                   ; Discard the saved source pointer on range failure.
    POP  DE                   ; Discard the saved operation before returning.
.INVALID:
    LD   A,ZT_INV             ; Report an invalid name or request range.
    SCF                       ; Mark the invalid-name or range result as a failure.
    RET                       ; Return without publishing an open handle.

;@ROUTINE IN A,C,DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Submit a handle-only operation. A=operation, C=selector and DE=handle.

NA_HCALL:
    PUSH BC                   ; Preserve the provider selector across request setup.
    PUSH DE                   ; Preserve the opaque handle across request setup.
    CALL NA_REQ               ; Clear the request and store the operation from A.
    POP  DE                   ; Restore the handle for the request fields.
    LD   IX,(NA_WORK)         ; Address the request through its common-workspace base.
    LD   (IX+ZT_FHND),E       ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle high byte.
    POP  BC                   ; Restore selector C before dispatch.
    JP   NA_CALL              ; Send this handle-only request to the platform gateway.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek an object to one 16-bit absolute byte offset. C=selector, DE=handle,
; HL=offset.

NA_SEEK:
    PUSH BC                   ; Preserve provider selector C across request setup.
    PUSH DE                   ; Preserve the object handle while HL supplies the offset.
    PUSH HL                   ; Save the absolute seek offset before NA_REQ clobbers HL.
    LD   A,ZT_SEEK            ; Choose the named-object SEEK operation.
    CALL NA_REQ               ; Clear the request and return its base in HL.
    POP  DE                   ; Restore the seek offset for its request fields.
    LD   IX,(NA_WORK)         ; Address request fields through the workspace base.
    LD   (IX+ZT_FOFF),E       ; Store the requested offset low byte.
    LD   (IX+ZT_FOFF+1),D     ; Store the requested offset high byte.
    POP  DE                   ; Restore the object handle for its request fields.
    LD   (IX+ZT_FHND),E       ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle high byte.
    POP  BC                   ; Restore selector C before dispatch.
    JP   NA_CALL              ; Submit the fully populated seek request.

;@ROUTINE IN A,B,C,DE OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Transfer through the fixed common 128-byte buffer. A=read/write, C=selector,
; DE=handle and B=count. Success returns the provider's result count in HL.

NA_TRANS:
    PUSH AF                   ; Preserve the read/write operation while saving B.
    LD   A,B                  ; Copy the requested transfer count from B.
    LD   (NA_COUNT),A         ; Keep the count outside the request fields being reset.
    POP  AF                   ; Restore the operation for the request record.

    PUSH BC                   ; Preserve selector C and count B across NA_REQ.
    PUSH DE                   ; Preserve the provider's opaque object handle.
    CALL NA_REQ               ; Clear the request and store this operation.
    LD   IX,(NA_WORK)         ; Address request fields through the workspace base.
    POP  DE                   ; Restore the handle for its two request bytes.
    LD   (IX+ZT_FHND),E       ; Store the handle's low byte.
    LD   (IX+ZT_FHND+1),D     ; Store the handle's high byte.
    LD   HL,(NA_WORK)         ; Begin forming the transfer-buffer address.
    LD   DE,NA_XFER           ; Add the buffer's workspace-relative offset.
    ADD  HL,DE                ; HL now points to the shared 128-byte buffer.
    LD   (IX+ZT_FPTR),L       ; Give the provider the transfer pointer low byte.
    LD   (IX+ZT_FPTR+1),H     ; Complete the provider's 16-bit transfer pointer.

    LD   A,(NA_COUNT)         ; Recover the requested transfer size.
    LD   (IX+ZT_FLEN),A       ; Store it in the request length low byte.
    LD   (IX+ZT_FLEN+1),0     ; The request count is limited to one byte.
    POP  BC                   ; Restore selector C and count B for NA_CALL.
    LD   HL,(NA_WORK)         ; Pass the request-record base to the gateway.
    CALL NA_CALL              ; Dispatch the selected read or write operation.
    RET  C                    ; Preserve a provider or transport failure.
    LD   L,(IX+ZT_FRES)       ; Read the provider's result count, low byte.
    LD   H,(IX+ZT_FRES+1)     ; Read its high byte to return the full count in HL.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Return the transfer result count in HL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Close the current source object if one is open, then invalidate its part/cache
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
    RET  C                    ; Keep handle and cache identity if CLOSE failed.
    XOR  A                    ; Prepare zero for the closed state.
    LD   (NA_SHAND),A         ; Clear the source handle low byte.
    LD   (NA_SHAND+1),A       ; Clear the source handle high byte.
    LD   (NA_CLEN),A          ; Invalidate every byte in the shared cache.
    LD   A,$FF                ; Mark that no source part owns the handle.
    LD   (NA_SPART),A         ; Publish the invalid-part sentinel.
    XOR  A                    ; Return success with carry clear.
    RET                       ; Finish after the provider accepted CLOSE.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open the source name associated with part A. Each three-byte name-table entry
; is pointer followed by one-byte length. Only one source handle stays open.

NA_SOPEN:
    LD   (NA_WPART),A         ; Keep the requested part while closing its predecessor.
    CALL NA_SCLOS             ; Only one source object may remain open.
    RET  C                    ; Preserve a failure to close the previous source.
    LD   A,(NA_WPART)         ; Recover the requested part ordinal.
    LD   L,A                  ; Begin extending the ordinal to a 16-bit index.
    LD   H,0                  ; The ordinal's high byte is zero.
    LD   D,H                  ; Copy the index into DE for multiplication by three.
    LD   E,L                  ; DE now holds the original part ordinal.
    ADD  HL,HL                ; Form twice the ordinal.
    ADD  HL,DE                ; Add the original to obtain the three-byte entry offset.
    LD   IX,(NA_CFG)          ; Address the configuration's source-name table pointer.
    LD   E,(IX+NA_CFPT)       ; Read the table pointer's low byte.
    LD   D,(IX+NA_CFPT+1)     ; Read its high byte.
    ADD  HL,DE                ; Locate this part's pointer-and-length record.
    LD   E,(HL)               ; Read the source-name pointer's low byte.
    INC  HL                   ; Advance to the pointer high byte.
    LD   D,(HL)               ; Read the source-name pointer's high byte.
    INC  HL                   ; Advance to the one-byte name length.
    LD   B,(HL)               ; Preserve the name length for NA_OPEN.

    EX   DE,HL                ; Pass the name pointer in HL as NA_OPEN expects.
    LD   C,(IX+NA_CFSS)       ; Select the configured source provider.
    LD   A,ZT_OPEN            ; Choose the named-object OPEN operation.
    CALL NA_OPEN              ; Open this part's named source object.
    RET  C                    ; Do not publish a handle after a failed open.
    LD   (NA_SHAND),DE        ; Retain the provider's returned source handle.
    LD   A,(NA_WPART)         ; Recover the part associated with that handle.
    LD   (NA_SPART),A         ; Mark the cached handle as belonging to this part.
    XOR  A                    ; The new source has no cached bytes yet.
    LD   (NA_CLEN),A          ; Force its first read through the provider.
    RET                       ; Return success with carry clear.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; AtomSourceReadByte replacement. It keeps a 128-byte source cache and one
; readable object handle. A part change closes and reopens by name. A cache miss
; seeks to the exact requested offset and fills from there, so the assembler may
; reread tokens without retaining a whole source part in Z80 memory.

NA_SREAD:
    PUSH BC                   ; Preserve the caller's BC pair.
    PUSH IX                   ; Keep the caller's IX across provider calls.
    PUSH IY                   ; Keep the caller's IY across provider calls.
    LD   (NA_WPART),A         ; Save the requested source-part ordinal.
    LD   (NA_WOFF),HL         ; Save the logical byte offset to fetch.
    LD   B,A                  ; Keep the requested part for the identity comparison.
    LD   A,(NA_SPART)         ; Read which part currently owns the open handle.
    CP   B                    ; Compare the cached handle's part with this request.
    JR   Z,.HAVE              ; Reuse the open handle when the part is unchanged.
    LD   A,B                  ; Pass the new part ordinal to the open helper.
    CALL NA_SOPEN             ; Close the old source and open this part's object.
    JR   C,.DONE              ; Return the provider's failure after restoring registers.
.HAVE:
    LD   HL,(NA_WOFF)         ; Load the requested logical source offset.
    LD   DE,(NA_CBASE)        ; Load the first offset represented by the cache.
    OR   A                    ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                ; Convert the requested offset to a cache-relative one.
    JR   C,.MISS              ; A request before the cached range cannot be a hit.
    LD   A,H                  ; Cache offsets must fit in the low byte.
    OR   A                    ; Test whether the relative offset exceeds 255.
    JR   NZ,.MISS             ; A nonzero high byte is outside this cache block.
    LD   A,(NA_CLEN)           ; Read how many bytes the cache currently holds.
    CP   L                    ; Compare the cache length with the relative offset.
    JR   Z,.MISS              ; The first byte after the cache is a miss.
    JR   C,.MISS              ; Any offset beyond the cache length is a miss.
    LD   A,L                  ; Retain the in-cache offset as the buffer index.
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

; Refill the cache at the requested offset. A zero-length successful read is an
; unexpected storage failure because the caller's part descriptor proved length.

    LD   IX,(NA_CFG)          ; Reload the source provider selector.
    LD   C,(IX+NA_CFSS)       ; Select the provider that owns the open handle.
    LD   DE,(NA_SHAND)        ; Pass the current source handle to NA_SEEK.
    LD   HL,(NA_WOFF)         ; Seek to the exact requested logical offset.
    CALL NA_SEEK              ; Position the object before refilling the cache.
    JR   C,.DONE              ; Preserve a seek failure without changing cache bounds.
    LD   IX,(NA_CFG)          ; Reload the configuration after NA_SEEK clobbers IX.
    LD   C,(IX+NA_CFSS)       ; Select the source provider for the transfer.
    LD   DE,(NA_SHAND)        ; Pass the open object handle to NA_TRANS.
    LD   B,NA_XLEN            ; Request at most the full 128-byte cache capacity.
    LD   A,ZT_READ            ; Choose the named-object READ operation.
    CALL NA_TRANS             ; Fill the shared buffer beginning at the requested byte.
    JR   C,.DONE              ; Return a provider failure without publishing cache data.
    LD   A,H                  ; Begin testing whether the provider returned any bytes.
    OR   L                    ; Z means the source object returned an empty read.
    JR   Z,.SHORT             ; A valid descriptor promised data at this offset.
    LD   A,L                  ; Keep the one-byte result count as the cache length.
    LD   (NA_CLEN),A          ; The request is capped at the 128-byte buffer size.
    LD   HL,(NA_WOFF)         ; The refill begins exactly at the requested offset.
    LD   (NA_CBASE),HL        ; Publish that offset as the cache's logical base.
    LD   HL,(NA_WORK)         ; Locate the first byte in the refilled buffer.
    LD   DE,NA_XFER           ; Add the transfer-buffer offset within workspace.
    ADD  HL,DE                ; HL now addresses the newly read first byte.
    LD   A,(HL)               ; Return the byte requested at the cache base.
    OR   A                    ; Clear carry and set Z according to that byte.
    JR   .DONE                ; Restore caller registers before returning.
.SHORT:
    LD   A,ZT_STORE           ; Report an impossible empty read as a storage failure.
    SCF                       ; Distinguish the failed read from a zero source byte.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return A, carry and zero status to Atom.

;@ROUTINE IN B OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Write B bytes already held in the transfer buffer to the open output. Require
; an exact provider byte count and invalidate source-cache contents that shared
; the transfer area.

NA_WRITE:
    LD   A,B                  ; Preserve the requested count before NA_TRANS uses B.
    LD   (NA_COUNT),A         ; Keep the expected count for the exact-result check.
    XOR  A                    ; The transfer buffer also backs the source cache.
    LD   (NA_CLEN),A          ; Invalidate the cache now that its buffer holds output.
    LD   IX,(NA_CFG)          ; Load the configured output-service selector.
    LD   C,(IX+NA_CFSK)       ; Select the provider that owns the tentative output.
    LD   DE,(NA_OHAND)        ; Pass the current output handle to the provider.
    LD   A,ZT_WRITE           ; Choose the named-object WRITE operation.
    CALL NA_TRANS             ; Write B bytes from the common transfer buffer.
    RET  C                    ; Return provider failure without accepting a short write.
    LD   A,H                  ; The expected result count is at most 128 bytes.
    OR   A                    ; Reject any result with a nonzero high byte.
    JR   NZ,.BAD              ; Such a count cannot match this transfer request.
    LD   A,(NA_COUNT)         ; Recover the exact byte count requested.
    CP   L                    ; Compare it with the provider's returned low byte.
    JR   NZ,.BAD              ; A short write leaves the output generation invalid.
    XOR  A                    ; Return success with carry clear.
    RET                       ; The provider accepted every requested byte.
.BAD:
    LD   A,ZT_STORE           ; Convert a partial transfer into a storage failure.
    SCF                       ; Mark the mismatch as an error for the caller.
    RET                       ; Leave cursor updates to the caller's success path.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Fill the tentative output from its current append cursor to relative offset
; HL. Backward IMAGE calls are rejected. Forward gaps are written as zero blocks
; no larger than the common 128-byte transfer buffer.

NA_FILL:
    EX   DE,HL                ; Keep the requested target in DE for comparison.
    LD   HL,(NA_OCURS)        ; Load the current append cursor.
    OR   A                    ; Clear carry before comparing unsigned offsets.
    SBC  HL,DE                ; Compute cursor minus requested target.
    JR   C,.FORWARD           ; A lower cursor means the target needs a zero gap.
    JR   Z,.DONE              ; No gap is needed when target equals the cursor.
    LD   A,ZT_INV             ; IMAGE cannot move the append cursor backwards.
    SCF                       ; Report the invalid backward append.
    RET                       ; Leave the output object unchanged.
.FORWARD:
    EX   DE,HL                ; Restore the requested target in HL.
    LD   DE,(NA_OCURS)        ; Load the lower current cursor for subtraction.
    OR   A                    ; Clear carry before computing the positive gap.
    SBC  HL,DE                ; HL now holds target minus current cursor.

; HL now holds the positive gap.

    LD   (NA_GAP),HL          ; Retain the number of zero bytes still to append.
.LOOP:
    LD   HL,(NA_GAP)          ; Reload the remaining gap at each block iteration.
    LD   A,H                  ; A nonzero high byte guarantees at least 256 remain.
    OR   L                    ; Z means the entire gap has been emitted.
    JR   Z,.DONE              ; Finish when no padding bytes remain.
    LD   B,NA_XLEN            ; Use the full buffer for gaps of at least 128 bytes.
    LD   A,H                  ; Check whether the remaining gap reaches 256.
    OR   A                    ; A zero high byte leaves its size in the low byte.
    JR   NZ,.COUNT             ; Keep a full block whenever the gap is at least 256.
    LD   A,L                  ; Inspect the low-byte gap when the high byte is zero.
    CP   NA_XLEN              ; Test whether a complete 128-byte block remains.
    JR   NC,.COUNT             ; Keep B=128 when the gap is at least buffer-sized.
    LD   B,A                  ; Use the smaller final remainder as the block size.
.COUNT:
    LD   A,B                  ; Save this block size before the write helper clobbers B.
    LD   (NA_COUNT),A         ; Reuse the saved size for cursor and gap updates.
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
    OR   A                    ; Clear carry before subtracting the accepted count.
    SBC  HL,DE                ; Remove this block from the gap still to write.
    LD   (NA_GAP),HL          ; Preserve the remainder for the next iteration.
    JR   .LOOP                ; Emit another block until the gap reaches zero.
.DONE:
    XOR  A                    ; Return success with carry clear.
    RET                       ; The append cursor now equals the requested target.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Convert absolute target address HL to the flat output-relative offset.

NA_REL:
    LD   DE,(NA_TBASE)        ; Load the absolute base of the flat output image.
    OR   A                    ; Clear carry before subtracting the target base.
    SBC  HL,DE                ; Convert the absolute address to an image-relative offset.
    RET  NC                   ; Return the nonnegative flat-image offset in HL.
    LD   A,ZT_INV             ; A target below the image base is invalid.
    SCF                       ; Return the range failure through carry.
    RET                       ; Preserve the invalid-target status in A.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek the output object to relative offset HL.

NA_OSEEK:
    LD   IX,(NA_CFG)          ; Load the output provider selector's config block.
    LD   C,(IX+NA_CFSK)       ; Select the provider that owns the output object.
    LD   DE,(NA_OHAND)        ; Supply its current handle to the seek helper.
    JP   NA_SEEK              ; Reuse the common request and offset setup.

; Begin a tentative flat-image object. Capture the descriptor's target base,
; reject a nested generation, and reset append/high-water offsets after OPEN.

HS_SCBEG:                      ; Mark the first sink callback in the adapter.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a tentative output object and reset its append and high-water offsets.

HS_BEG:
    PUSH BC                   ; Preserve caller state across provider operations.
    PUSH DE                   ; The output setup uses DE for the opened handle.
    PUSH HL                   ; Preserve the caller's address and byte values.
    PUSH IX                   ; Keep the Atom descriptor pointer for later restoration.
    PUSH IY                   ; Preserve IY across the named-object gateway.
    LD   A,(NA_OHAND)         ; Read the tentative output handle's low byte.
    LD   B,A                  ; Keep it while checking the high byte.
    LD   A,(NA_OHAND+1)       ; Read the tentative output handle's high byte.
    OR   B                    ; A nonzero handle means a generation is already open.
    JR   NZ,.STATE             ; Reject a nested output generation.
    LD   L,(IX+11)            ; Read the descriptor's target base, low byte.
    LD   H,(IX+12)            ; Read its high byte from the documented descriptor slot.
    LD   (NA_TBASE),HL        ; Retain the absolute base used by NA_REL.
    LD   IX,(NA_CFG)          ; Switch IX from the descriptor to adapter configuration.
    LD   L,(IX+NA_CFON)       ; Read the output object's name pointer low byte.
    LD   H,(IX+NA_CFON+1)     ; Read the output object's name pointer high byte.
    LD   B,(IX+NA_CFOL)       ; Supply its configured byte length to NA_OPEN.
    LD   C,(IX+NA_CFSK)       ; Select the output provider for the new object.
    LD   A,ZT_BEGIN           ; Choose the provider's tentative-output operation.
    CALL NA_OPEN              ; Open the named output as an uncommitted generation.
    JR   C,.DONE              ; Keep the provider error and restore caller registers.
    LD   (NA_OHAND),DE        ; Retain the tentative generation's handle.
    LD   HL,0                 ; The new image begins at relative offset zero.
    LD   (NA_OCURS),HL        ; Reset its append cursor.
    LD   (NA_OHIGH),HL        ; Reset its initialized high-water extent.
    XOR  A                    ; Return success with carry clear.
    JR   .DONE                ; Restore saved caller state before returning.
.STATE:
    LD   A,ZT_INV             ; Report that an output generation is already open.
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
; Convert the logical address to a flat offset, zero-fill any forward gap, write
; the byte and advance both cursor and high-water mark.

HS_IB:
    PUSH BC                   ; Preserve the address class and caller's BC pair.
    PUSH IX                   ; Preserve IX across the output provider call.
    PUSH IY                   ; Preserve IY across the output provider call.
    LD   (NA_BYTE),A          ; Save the IMAGE byte before address validation.
    LD   A,C                  ; The flat sink accepts only address class zero.
    OR   A                    ; Test the class without changing C.
    JR   NZ,.BAD              ; Reject banked or otherwise non-flat addresses.

    CALL NA_REL               ; Convert the absolute target to an image offset.
    JR   C,.DONE              ; Return failure for an address below the configured image base.
    CALL NA_FILL              ; Append zeroes when the target lies beyond the cursor.
    JR   C,.DONE              ; Do not write the IMAGE byte after a failed gap fill.

    LD   HL,(NA_WORK)         ; Start at the shared transfer workspace.
    LD   DE,NA_XFER           ; Select the buffer used by the provider.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   A,(NA_BYTE)          ; Recover the caller's IMAGE value.
    LD   (HL),A               ; Stage one byte for NA_WRITE.
    LD   B,1                  ; The IMAGE operation appends exactly one byte.
    CALL NA_WRITE             ; Require the provider to accept that byte.
    JR   C,.DONE              ; Leave cursor and extent unchanged after failure.

    LD   HL,(NA_OCURS)        ; Read the cursor after any preceding zero fill.
    INC  HL                   ; Advance past the newly appended IMAGE byte.
    LD   (NA_OCURS),HL        ; Publish the next append position.
    LD   (NA_OHIGH),HL        ; The append also establishes the new high-water mark.
    XOR  A                    ; Return success with carry clear.
    JR   .DONE                ; Restore caller registers before returning.
.BAD:
    LD   A,ZT_INV             ; Report an address class the flat sink cannot store.
    SCF                       ; Mark the rejected IMAGE operation as invalid.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return the IMAGE result in A and carry.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier byte. Address class C must be zero and the address must lie
; below the initialized high-water mark. Seek, replace one byte, then restore the
; append cursor on success; a provider failure is left for driver-level abort.

HS_PB:
    PUSH BC                   ; Preserve the address class and caller's BC pair.
    PUSH IX                   ; Preserve IX across provider calls.
    PUSH IY                   ; Preserve IY across provider calls.
    LD   (NA_BYTE),A          ; Save the replacement byte before validation.
    LD   A,C                  ; A flat patch must use address class zero.
    OR   A                    ; Test the class while keeping C unchanged.
    JR   NZ,.BAD              ; Reject a patch for a banked address.

    CALL NA_REL               ; Convert the absolute patch address to an offset.
    JR   C,.DONE              ; Return failure for an address below the flat image base.
    LD   DE,(NA_OHIGH)        ; Load the first offset beyond initialized output.
    PUSH HL                   ; Preserve the relative patch offset for NA_OSEEK.
    OR   A                    ; Clear carry before the unsigned boundary comparison.
    SBC  HL,DE                ; Compare patch offset with the high-water boundary.
    POP  HL                   ; Restore the patch offset after the comparison.
    JR   NC,.BAD              ; A patch at or beyond high water has no prior byte.

    CALL NA_OSEEK             ; Position the provider at the earlier byte to patch.
    JR   C,.DONE              ; Return a failed seek without staging a replacement.
    LD   HL,(NA_WORK)         ; Start at the shared transfer workspace.
    LD   DE,NA_XFER           ; Select the provider's transfer buffer.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   A,(NA_BYTE)          ; Recover the replacement value.
    LD   (HL),A               ; Stage the one-byte patch for NA_WRITE.
    LD   B,1                  ; The patch replaces exactly one output byte.
    CALL NA_WRITE             ; Require an exact one-byte provider write.
    JR   C,.DONE              ; Leave append position restoration to abort handling.

    LD   HL,(NA_OCURS)        ; Recover the append cursor after the patch write.
    CALL NA_OSEEK             ; Restore the provider position for the next IMAGE.
    JR   .DONE                ; Return the restoration result to the driver.
.BAD:
    LD   A,ZT_INV             ; Report an unsupported class or out-of-range patch.
    SCF                       ; Mark the patch as invalid for this flat output.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return patch or provider status in A and carry.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Patch one earlier little-endian word. Address class C must be zero and both
; bytes must lie below high water. Write low byte first, then restore the append
; cursor on success; a provider failure is left for driver-level abort.

HS_PW:
    PUSH IX                   ; Preserve the Atom descriptor pointer.
    PUSH IY                   ; Preserve IY across output-provider calls.
    LD   (NA_WORD),HL         ; Save the little-endian value before using HL for its address.
    LD   A,C                  ; A flat word patch must use address class zero.
    OR   A                    ; Test the class while keeping C unchanged.
    JR   NZ,.BAD              ; Reject a word patch for a banked address.

    EX   DE,HL                ; Move the absolute patch address from DE to HL.
    CALL NA_REL               ; Convert that address to a flat image offset.
    JR   C,.DONE              ; Return failure for an address below the output base.
    PUSH HL                   ; Preserve the first-byte offset for NA_OSEEK.
    INC  HL                   ; Advance to the second byte for the extent check.
    LD   DE,(NA_OHIGH)        ; Load the exclusive initialized-output boundary.
    OR   A                    ; Clear carry before comparing the second-byte offset.
    SBC  HL,DE                ; Check that the second byte lies below high water.
    POP  HL                   ; Restore the first-byte offset for the seek.
    JR   NC,.BAD              ; Reject when the second byte is at or beyond the extent.

    CALL NA_OSEEK             ; Position the provider at the word's low byte.
    JR   C,.DONE              ; Return a failed seek without writing either byte.
    LD   HL,(NA_WORK)         ; Start at the common workspace base.
    LD   DE,NA_XFER           ; Select the provider's transfer buffer.
    ADD  HL,DE                ; HL now points at its first byte.
    LD   DE,(NA_WORD)         ; Recover the value in little-endian register order.
    LD   (HL),E               ; Stage the low byte at the patch offset.
    INC  HL                   ; Advance to the next transfer-buffer byte.
    LD   (HL),D               ; Stage the high byte after the low byte.
    LD   B,2                  ; The word patch replaces exactly two bytes.
    CALL NA_WRITE             ; Require an exact two-byte provider write.
    JR   C,.DONE              ; Return failure and let the driver abort the object.

    LD   HL,(NA_OCURS)        ; Recover the append cursor after the patch write.
    CALL NA_OSEEK             ; Restore the provider position for subsequent IMAGEs.
    JR   .DONE                ; Return the restoration result to the driver.
.BAD:
    LD   A,ZT_INV             ; Report an unsupported class or out-of-range word patch.
    SCF                       ; Mark the rejected patch as invalid.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX descriptor pointer.
    RET                       ; Return patch or provider status in A and carry.

;@ROUTINE IN IX,HL,DE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Commit the highest of the final logical cursor and highest IMAGE extent. This
; materializes trailing DS/ORG reservations as zeros, closes the source object,
; then asks the provider to atomically publish the tentative output.

HS_CMT:
    CALL NA_REL               ; Convert the final logical cursor to an image offset.
    JR   C,.DONE              ; Return if the final cursor lies below the image base.
    LD   DE,(NA_OHIGH)        ; Load the exclusive end established by IMAGE.
    PUSH HL                   ; Preserve the final cursor across the comparison.
    OR   A                    ; Clear carry before comparing unsigned offsets.
    SBC  HL,DE                ; Compute final cursor minus initialized high-water.
    POP  HL                   ; Restore the final cursor for the fill operation.
    JR   NC,.LIMIT             ; Keep HL when the cursor already reaches high water.
    EX   DE,HL                ; Otherwise select high water as the required end offset.
.LIMIT:
    CALL NA_FILL              ; Materialize any trailing reservation as zero bytes.
    JR   C,.DONE              ; Do not publish an image that could not be completed.
    CALL NA_SCLOS             ; Close the source object before committing output.
    JR   C,.DONE              ; Keep the tentative output for driver-level abort.
    LD   IX,(NA_CFG)          ; Load the output provider selector.
    LD   C,(IX+NA_CFSK)       ; Select the provider that owns the generation.
    LD   DE,(NA_OHAND)        ; Supply the tentative output handle.
    LD   A,ZT_COM             ; Choose the provider's atomic COMMIT operation.
    CALL NA_HCALL             ; Ask the provider to publish the completed object.
    JR   C,.DONE              ; Preserve its failure status for the driver.
    XOR  A                    ; Prepare the closed-handle value and success status.
    LD   (NA_OHAND),A         ; Clear the committed handle's low byte.
    LD   (NA_OHAND+1),A       ; Clear its high byte so later BEGIN can proceed.
    RET                       ; Return successful publication with carry clear.
.DONE:
    RET                       ; Return the preceding fill, close or commit result.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Abort an open generation and close any source handle. Attempt both cleanups;
; output-abort failure takes precedence, otherwise return a source-close failure.

HS_ABORT:
    PUSH BC                   ; Preserve caller state while cleanup calls clobber BC.
    PUSH DE                   ; Preserve the caller's DE pair.
    PUSH HL                   ; Preserve the caller's HL pair.
    PUSH IX                   ; Preserve the caller's IX register.
    PUSH IY                   ; Preserve the caller's IY register.
    CALL NA_SCLOS             ; Attempt to close the current source object.
    LD   B,0                  ; No source-close status is pending unless carry is set.
    JR   NC,.SOURCEOK         ; Continue directly when source close succeeded.
    LD   B,A                  ; Save its error code while the output abort is tried.
.SOURCEOK:
    LD   DE,(NA_OHAND)        ; Read the tentative output handle.
    LD   A,D                  ; Begin checking whether an output is open.
    OR   E                    ; Z means there is no output generation to abort.
    JR   Z,.RESULT            ; Return the source-close result when no output exists.
    LD   IX,(NA_CFG)          ; Load the output provider selector.
    LD   C,(IX+NA_CFSK)       ; Select the provider that owns the tentative object.
    LD   A,ZT_ABORT           ; Choose the provider's ABORT operation.
    PUSH BC                   ; Preserve the source-close result in B across the call.
    CALL NA_HCALL             ; Ask the provider to discard its tentative object.
    POP  BC                   ; Restore the pending source-close result.
    JR   C,.ABFAIL            ; Give output-abort failure precedence over close failure.
    XOR  A                    ; Prepare zero for the now-closed local handle.
    LD   (NA_OHAND),A         ; Clear the output handle low byte after accepted ABORT.
    LD   (NA_OHAND+1),A       ; Clear the output handle high byte.
    JR   .RESULT              ; Return any source-close failure saved in B.
.ABFAIL:
    LD   (NA_BYTE),A          ; Preserve the higher-priority output-abort status.
    XOR  A                    ; Clear the local handle even when ABORT failed.
    LD   (NA_OHAND),A         ; Remove the stale output handle's low byte.
    LD   (NA_OHAND+1),A       ; Remove its high byte as well.
    LD   A,(NA_BYTE)          ; Restore the abort failure after clearing the handle.
    SCF                       ; Return that failure as the primary cleanup result.
    JR   .DONE                ; Restore all caller-saved registers before returning.
.RESULT:
    LD   A,B                  ; Recover a source-close error if one was recorded.
    OR   A                    ; Z means both requested cleanup operations succeeded.
    JR   Z,.OK                ; Return success when there is no saved source error.
    SCF                       ; Preserve the source error and mark failure in carry.
    JR   .DONE                ; Restore all caller-saved registers before returning.
.OK:
    XOR  A                    ; Return success with A zero and carry clear.
.DONE:
    POP  IY                   ; Restore the caller's IY register.
    POP  IX                   ; Restore the caller's IX register.
    POP  HL                   ; Restore the caller's HL pair.
    POP  DE                   ; Restore the caller's DE pair.
    POP  BC                   ; Restore the caller's BC pair.
    RET                       ; Return the selected cleanup status in A and carry.

; Fail-closed transport replaced by a concrete platform binding.

;@@ATOM_OBJECT_GATEWAY_BEGIN@@
;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Fail closed until a platform replaces this named-object transport gateway.

NA_GATE:
    LD   A,ZT_UNAV            ; Report that no platform gateway was installed.
    SCF                       ; Fail closed instead of touching an unknown service.
    RET                       ; Return the unavailable status to the caller.
;@@ATOM_OBJECT_GATEWAY_END@@

HS_SCEND:                      ; End the sink callbacks before adapter state data.

; Private adapter state. Handles are zero when closed; source cache identity is
; (part, base, length). Output cursor/high-water are relative to NA_TBASE. The
; remaining scratch words stage gaps, patch values, bytes and transfer counts.

NA_CFG: DW 0                  ; Caller-owned nine-byte configuration address.
NA_WORK: DW 0                 ; Base of the 399-byte common request workspace.
NA_SHAND: DW 0                ; Open source-object handle, or zero when closed.
NA_OHAND: DW 0                ; Tentative output-object handle, or zero when closed.
NA_SPART: DB $FF              ; Part ordinal for NA_SHAND, or $FF when invalid.
NA_WPART: DB 0                ; Part ordinal staged across source-provider calls.
NA_WOFF: DW 0                 ; Requested logical source offset staged for a refill.
NA_CBASE: DW 0                ; Logical source offset represented by buffer byte zero.
NA_CLEN: DB 0                 ; Count of valid cached bytes or zero when invalid.
NA_TBASE: DW 0                ; Absolute target base used to form output offsets.
NA_OCURS: DW 0                ; Relative position where the next IMAGE bytes append.
NA_OHIGH: DW 0                ; Exclusive end of the highest initialized output byte.
NA_GAP: DW 0                  ; Zero-padding bytes still required by NA_FILL.
NA_WORD: DW 0                 ; Little-endian value staged for a word PATCH.
NA_BYTE: DB 0                 ; Byte staged for IMAGE, byte PATCH or error preservation.
NA_COUNT: DB 0                ; Transfer count saved across request and provider calls.
NA_REND:                      ; End marker used to measure the adapter's resident extent.
