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
;
; Common workspace (399 bytes): request 0..15, copied name 16..270, transfer
; buffer 271..398. Object names are byte strings, not zero-terminated text.

NA_CFSRC    EQU     0                   ; Config offset of the source-service selector.
NA_CFDST    EQU     1                   ; Config offset of the sink-service selector.
NA_CFTAB    EQU     2                   ; Offset of the source-name table pointer.
NA_CFOUT    EQU     4                   ; Config offset of the output-name pointer.
NA_CFLEN    EQU     6                   ; Config offset of the output-name byte length.
NA_CFCOM    EQU     7                   ; Config offset of the common-workspace pointer.
NA_CFEND    EQU     9                   ; Total byte size of the configuration block.

NA_NAME     EQU     16                  ; Workspace offset of the copied object name.
NA_XOFF     EQU     271                 ; Offset of the shared transfer buffer.
NA_XLEN     EQU     128                 ; Transfer and cache capacity.
NA_WLEN     EQU     399                 ; Request, name and transfer workspace size.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and retain configuration. The workspace may end at $10000 but
; cannot cross it. Reset handles and invalidate the source cache.

NA_INIT: ; Validate and retain adapter configuration.
    PUSH IX                             ; Copy the configuration pointer.
    POP  HL                             ; HL now points at the configuration.
    LD   (NA_CFG),HL                    ; Retain it for later calls.
    LD   E,(IX+NA_CFCOM)                ; Read the common-workspace start, low byte.
    LD   D,(IX+NA_CFCOM+1)              ; Read its high byte to complete the address.

    LD   A,D                            ; Begin testing whether the address is zero.
    OR   E                              ; Set Z only when both address bytes are zero.
    JR   Z,.INVALID                     ; Reject a null workspace pointer.
    LD   (NA_WORK),DE                   ; Retain the workspace start.
    LD   H,D                            ; Copy its high byte to HL.
    LD   L,E                            ; Complete the 16-bit copy without changing DE.
    LD   BC,NA_WLEN                     ; Use the complete 399-byte workspace extent.
    ADD  HL,BC                          ; Calculate the exclusive end and detect wrap.

    JR   NC,.WORKOK                     ; A non-wrapping end lies below $10000.
    LD   A,H                            ; A wrapped end is legal only at $10000.
    OR   L                              ; Test for that zero result.
    JR   NZ,.INVALID                    ; Reject a workspace that extends past memory.
.WORKOK: ; Validate the output name after workspace bounds.
    LD   A,(IX+NA_CFLEN)                ; Read the output-name byte length.
    OR   A                              ; An empty output name cannot be opened.
    JR   Z,.INVALID                     ; Reject that incomplete configuration.

    XOR  A                              ; Zero marks closed handles and empty cache.
    LD   (NA_SHAND),A                   ; Clear the source handle low byte.
    LD   (NA_SHAND+1),A                 ; Clear the source handle high byte.
    LD   (NA_OHAND),A                   ; Clear the output handle low byte.
    LD   (NA_OHAND+1),A                 ; Clear the output handle high byte.
    LD   (NA_CLEN),A                    ; Invalidate any source-cache bytes.
    LD   A,$FF                          ; No source part has been opened yet.
    LD   (NA_SPART),A                   ; Record the invalid part sentinel.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the adapter ready for its first request.

.INVALID: ; Reject invalid configuration.
    LD   A,ZT_INV                       ; Report invalid configuration.
    SCF                                 ; Mark the validation failure in carry.
    RET                                 ; Return without opening a provider handle.

;@ROUTINE IN A OUT HL CLOBBERS A,BC,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Initialise the common request block. A is the operation. Clear all sixteen
; bytes first so no field from a prior provider call leaks into the next one;
; return HL at the request-block base for the gateway.

NA_REQ: ; Initialise a sixteen-byte service request.
    LD   C,A                            ; Save the operation while clearing.
    LD   HL,(NA_WORK)                   ; Point HL at the common request record.
    LD   D,H                            ; Retain the base in DE.
    LD   E,L                            ; DE remains the request-record address.
    XOR  A                              ; Clear all prior request fields.
    LD   B,ZT_RQLEN                     ; Clear the full fixed-size request block.
.CLEAR: ; Clear each request field before reuse.
    LD   (HL),A                         ; Remove any argument left by the prior call.
    INC  HL                             ; Advance to the next request byte.
    DJNZ .CLEAR                         ; Repeat until all sixteen bytes are clear.

    LD   HL,(NA_WORK)                   ; Return to the request base.
    LD   (HL),ZT_RQLEN                  ; Publish the record size expected by the ABI.
    INC  HL                             ; Advance to the ABI-version field.
    LD   (HL),ZT_ABI                    ; Identify the named-object service version.
    INC  HL                             ; Advance to the operation field.
    LD   (HL),C                         ; Store the operation saved before clearing A.
    EX   DE,HL                          ; Restore the request base as the return value.
    RET                                 ; Return HL at the block passed to the gateway.

;@ROUTINE IN C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Invoke the selected platform service. The platform replaces NA_GATE or
; routes it to its native gateway. Carry reports transport/provider failure;
; the checked image's default gateway always fails closed.

NA_CALL: ; Dispatch the selected provider request.
    CALL NA_GATE                        ; Call the selected platform gateway.
    RET  C                              ; Preserve failure status and carry.
    OR   A                              ; Clear carry on accepted results.
    RET                                 ; Return the gateway's successful result in A.

;@ROUTINE IN A,B,C,HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open one named object. A=operation, C=provider selector, HL=name and B=byte
; length. Copy the name into common workspace before the gateway can switch
; banks. Success returns the provider's opaque handle in DE.

NA_OPEN: ; Copy a name into bank-visible workspace.
    LD   D,A                            ; Save the operation during range checks.
    LD   A,B                            ; The name length is an unsigned byte in B.
    OR   A                              ; An empty name is invalid.
    JR   Z,.INVALID                     ; Reject an empty name.
    PUSH DE                             ; Save D before forming the length.
    PUSH HL                             ; Save the original name pointer.
    LD   E,B                            ; Form the name length as a 16-bit offset.
    LD   D,0                            ; The high byte of the length is zero.
    ADD  HL,DE                          ; Check the exclusive end of the source name.

    JR   NC,.RANGEOK                    ; Accept a non-wrapping end.
    LD   A,H                            ; A wrapped end is valid only at exactly $10000.
    OR   L                              ; Test the wrapped pointer for a zero result.
    JR   NZ,.RNGFAIL                    ; Reject a range past memory.
.RANGEOK: ; Copy a name whose address range is valid.
    POP  HL                             ; Restore the name pointer for the copy.
    POP  DE                             ; Restore the saved operation from D.
    PUSH BC                             ; Preserve provider selector and name length.
    PUSH DE                             ; Save the open operation.
    LD   DE,(NA_WORK)                   ; Start from the common-workspace base.
    PUSH DE                             ; Save the request base for IX.
    LD   A,E                            ; Begin the copied-name address.
    ADD  A,NA_NAME                      ; Advance to the name area.
    LD   E,A                            ; Store the calculated low byte in DE.
    JR   NC,.NAMEOK                     ; Keep the high byte if no carry.
    INC  D                              ; Cross into the next page.
.NAMEOK: ; Copy after computing the common name address.
    LD   C,B                            ; Move the byte count into the low byte of BC.
    LD   B,0                            ; Extend the name length to BC.
    LDIR                                ; Copy before a bank switch.

    POP  IX                             ; IX now addresses the common request block.
    POP  DE                             ; Restore the requested open operation.
    POP  BC                             ; Restore selector C and name length B.
    LD   A,D                            ; Pass the saved operation to NA_REQ.
    PUSH BC                             ; Save selector and length.
    CALL NA_REQ                         ; Clear the record and return its base in HL.
    LD   DE,(NA_WORK)                   ; Recover the workspace base.
    LD   A,E                            ; Begin forming workspace base plus NA_NAME.
    ADD  A,NA_NAME                      ; Compute the pointer low byte and its carry.
    LD   (IX+ZT_FPTR),A                 ; Point the request at the copied object name.
    LD   A,D                            ; Start the high-byte calculation from the base.
    ADC  A,0                            ; Add the low-byte carry.
    LD   (IX+ZT_FPTR+1),A               ; Complete the request's 16-bit name pointer.

    POP  BC                             ; Restore provider selector C and name length B.
    LD   (IX+ZT_FLEN),B                 ; Set the name length's low byte.
    LD   (IX+ZT_FLEN+1),0               ; Length fits one byte.
    CALL NA_CALL                        ; Open the copied name.
    RET  C                              ; Do not read a failed open's handle.
    LD   E,(IX+ZT_FHND)                 ; Read the returned opaque handle's low byte.
    LD   D,(IX+ZT_FHND+1)               ; Read its high byte for the caller's DE result.
    XOR  A                              ; Mark the completed open as successful.
    RET                                 ; Return the provider handle in DE.
.RNGFAIL: ; Unwind saved registers after name-range failure.
    POP  HL                             ; Discard the saved source pointer.
    POP  DE                             ; Discard the saved operation before returning.
.INVALID: ; Return invalid-name status.
    LD   A,ZT_INV                       ; Report an invalid name or request range.
    SCF                                 ; Mark the invalid request.
    RET                                 ; Return without publishing an open handle.

;@ROUTINE IN A,C,DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Submit a handle-only operation. A=operation, C=selector and DE=handle.

NA_HCALL: ; Submit a handle-only request.
    PUSH BC                             ; Save the provider selector.
    PUSH DE                             ; Save the opaque handle.
    CALL NA_REQ                         ; Clear and set up the request.
    POP  DE                             ; Restore the handle for the request fields.
    LD   IX,(NA_WORK)                   ; Address the request fields.
    LD   (IX+ZT_FHND),E                 ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle high byte.
    POP  BC                             ; Restore selector C before dispatch.
    JP   NA_CALL                        ; Submit the handle-only request.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Seek an object to one 16-bit absolute byte offset. C=selector, DE=handle,
; HL=offset.

NA_SEEK: ; Submit a seek to an absolute object offset.
    PUSH BC                             ; Save provider selector C.
    PUSH DE                             ; Save the object handle.
    PUSH HL                             ; Save the seek offset.
    LD   A,ZT_SEEK                      ; Choose the named-object SEEK operation.
    CALL NA_REQ                         ; Clear the request and return its base in HL.
    POP  DE                             ; Restore the seek offset.
    LD   IX,(NA_WORK)                   ; Address the request fields.
    LD   (IX+ZT_FOFF),E                 ; Store the requested offset low byte.
    LD   (IX+ZT_FOFF+1),D               ; Store the requested offset high byte.
    POP  DE                             ; Restore the object handle.
    LD   (IX+ZT_FHND),E                 ; Store the handle low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle high byte.
    POP  BC                             ; Restore selector C before dispatch.
    JP   NA_CALL                        ; Submit the fully populated seek request.

;@ROUTINE IN A,B,C,DE OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Transfer through the fixed common 128-byte buffer. A=read/write, C=selector,
; DE=handle and B=count. Success returns the provider's result count in HL.

NA_TRANS: ; Transfer through the common 128-byte buffer.
    PUSH AF                             ; Save the read/write operation.
    LD   A,B                            ; Copy the requested transfer count from B.
    LD   (NA_COUNT),A                   ; Save count outside the request.
    POP  AF                             ; Restore the operation for the request record.

    PUSH BC                             ; Preserve selector C and count B across NA_REQ.
    PUSH DE                             ; Preserve the provider's opaque object handle.
    CALL NA_REQ                         ; Clear the request and store this operation.
    LD   IX,(NA_WORK)                   ; Address the request fields.
    POP  DE                             ; Restore the handle for its two request bytes.
    LD   (IX+ZT_FHND),E                 ; Store the handle's low byte.
    LD   (IX+ZT_FHND+1),D               ; Store the handle's high byte.
    LD   HL,(NA_WORK)                   ; Begin forming the transfer-buffer address.
    LD   DE,NA_XOFF                     ; Add the buffer's workspace-relative offset.
    ADD  HL,DE                          ; HL now points to the shared 128-byte buffer.
    LD   (IX+ZT_FPTR),L                 ; Set transfer pointer, low byte.
    LD   (IX+ZT_FPTR+1),H               ; Set transfer pointer, high byte.

    LD   A,(NA_COUNT)                   ; Recover the requested transfer size.
    LD   (IX+ZT_FLEN),A                 ; Store it in the request length low byte.
    LD   (IX+ZT_FLEN+1),0               ; The request count is limited to one byte.
    POP  BC                             ; Restore selector C and count B for NA_CALL.
    LD   HL,(NA_WORK)                   ; Pass the request-record base to the gateway.
    CALL NA_CALL                        ; Dispatch the selected read or write operation.
    RET  C                              ; Preserve a provider or transport failure.
    LD   L,(IX+ZT_FRES)                 ; Read the provider's result count, low byte.
    LD   H,(IX+ZT_FRES+1)               ; Complete the result count in HL.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Return the transfer result count in HL.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Close the source object if open, then invalidate its part/cache
; identity only after the provider accepts CLOSE.

NA_CLOSE: ; Close the current source handle.
    LD   DE,(NA_SHAND)                  ; Load the current source handle.
    LD   A,D                            ; Begin checking whether the handle is zero.
    OR   E                              ; Z means no source object needs closing.
    RET  Z                              ; Treat an already-closed source as success.
    LD   IX,(NA_CFG)                    ; Read the source provider from configuration.
    LD   C,(IX+NA_CFSRC)                ; Select that provider for the close request.
    LD   A,ZT_CLOSE                     ; Choose the named-object CLOSE operation.
    CALL NA_HCALL                       ; Submit CLOSE with the saved source handle.
    RET  C                              ; Keep the handle if CLOSE failed.
    XOR  A                              ; Prepare zero for the closed state.
    LD   (NA_SHAND),A                   ; Clear the source handle low byte.
    LD   (NA_SHAND+1),A                 ; Clear the source handle high byte.
    LD   (NA_CLEN),A                    ; Invalidate every byte in the shared cache.
    LD   A,$FF                          ; Mark that no source part owns the handle.
    LD   (NA_SPART),A                   ; Publish the invalid-part sentinel.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Finish after the provider accepted CLOSE.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Open the source for part A. Each three-byte name-table entry is a pointer
; followed by a one-byte length. Only one source handle stays open.

NA_SOPEN: ; Open the named source for one part ordinal.
    LD   (NA_PART),A                    ; Save the part while closing the old one.
    CALL NA_CLOSE                       ; Only one source object may remain open.
    RET  C                              ; Propagate a failed close.
    LD   A,(NA_PART)                    ; Recover the requested part ordinal.
    LD   L,A                            ; Begin extending the ordinal to a 16-bit index.
    LD   H,0                            ; The ordinal's high byte is zero.
    LD   D,H                            ; Copy the ordinal into DE.
    LD   E,L                            ; DE now holds the original part ordinal.
    ADD  HL,HL                          ; Form twice the ordinal.
    ADD  HL,DE                          ; Form three times the ordinal.
    LD   IX,(NA_CFG)                    ; Address the source-name table pointer.
    LD   E,(IX+NA_CFTAB)                ; Read the table pointer's low byte.
    LD   D,(IX+NA_CFTAB+1)              ; Read its high byte.
    ADD  HL,DE                          ; Locate this part's pointer-and-length record.
    LD   E,(HL)                         ; Read the source-name pointer's low byte.
    INC  HL                             ; Advance to the pointer high byte.
    LD   D,(HL)                         ; Read the source-name pointer's high byte.
    INC  HL                             ; Advance to the one-byte name length.
    LD   B,(HL)                         ; Preserve the name length for NA_OPEN.

    EX   DE,HL                          ; Put the name pointer in HL.
    LD   C,(IX+NA_CFSRC)                ; Select the configured source provider.
    LD   A,ZT_OPEN                      ; Choose the named-object OPEN operation.
    CALL NA_OPEN                        ; Open this part's named source object.
    RET  C                              ; Do not publish a handle after a failed open.
    LD   (NA_SHAND),DE                  ; Retain the provider's returned source handle.
    LD   A,(NA_PART)                    ; Recover the part associated with that handle.
    LD   (NA_SPART),A                   ; Associate handle with this part.
    XOR  A                              ; The new source has no cached bytes yet.
    LD   (NA_CLEN),A                    ; Force its first read through the provider.
    RET                                 ; Return success with carry clear.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; AtomSourceReadByte replacement. It keeps a 128-byte source cache and one
; readable object handle. A part change closes and reopens by name. A miss
; seeks to the requested offset and fills from there, so the assembler may
; reread tokens without retaining a whole source part in Z80 memory.

NA_SREAD: ; Read a source byte through the shared cache.
    PUSH BC                             ; Preserve the caller's BC pair.
    PUSH IX                             ; Keep the caller's IX across provider calls.
    PUSH IY                             ; Keep the caller's IY across provider calls.
    LD   (NA_PART),A                    ; Save the requested source-part ordinal.
    LD   (NA_OFF),HL                    ; Save the logical byte offset to fetch.
    LD   B,A                            ; Save the requested part for comparison.
    LD   A,(NA_SPART)                   ; Load the open handle's part.
    CP   B                              ; Check whether this part is open.
    JR   Z,.HAVE                        ; Reuse its handle.
    LD   A,B                            ; Pass the new part to the open helper.
    CALL NA_SOPEN                       ; Open the requested source.
    JR   C,.DONE                        ; Restore registers after failure.
.HAVE: ; Check the current part cache for this offset.
    LD   HL,(NA_OFF)                    ; Load the requested logical source offset.
    LD   DE,(NA_CBASE)                  ; Load the cache's first offset.
    OR   A                              ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                          ; Form a cache-relative offset.
    JR   C,.MISS                        ; Before the cache: miss.
    LD   A,H                            ; Cache offsets must fit in the low byte.
    OR   A                              ; Test whether the relative offset exceeds 255.
    JR   NZ,.MISS                       ; High byte set: outside cache.
    LD   A,(NA_CLEN)                    ; Load the cached byte count.
    CP   L                              ; Compare length and relative offset.
    JR   Z,.MISS                        ; The first byte after the cache is a miss.
    JR   C,.MISS                        ; Any offset beyond the cache length is a miss.
    LD   A,L                            ; Use the relative offset as index.
    LD   HL,(NA_WORK)                   ; Start at the common workspace base.
    LD   DE,NA_XOFF                     ; Select the shared transfer-buffer offset.
    ADD  HL,DE                          ; HL now points at the first cached byte.
    LD   E,A                            ; Extend the cache-relative byte index to DE.
    LD   D,0                            ; Its high byte is zero after the prior check.
    ADD  HL,DE                          ; Address the requested byte inside the cache.
    LD   A,(HL)                         ; Return the cached source byte.
    OR   A                              ; Clear carry and report the byte's zero flag.
    JR   .DONE                          ; Restore caller registers and return this byte.
.MISS: ; Seek and refill on a cache miss.

; Refill at the requested offset. An empty successful read is a storage
; failure: the caller's part descriptor promised a byte here.

    LD   IX,(NA_CFG)                    ; Reload the source provider selector.
    LD   C,(IX+NA_CFSRC)                ; Select the provider that owns the open handle.
    LD   DE,(NA_SHAND)                  ; Pass the current source handle to NA_SEEK.
    LD   HL,(NA_OFF)                    ; Seek to the exact requested logical offset.
    CALL NA_SEEK                        ; Seek before refilling the cache.
    JR   C,.DONE                        ; Keep cache bounds on seek failure.
    LD   IX,(NA_CFG)                    ; NA_SEEK clobbered IX. reload config.
    LD   C,(IX+NA_CFSRC)                ; Select the source provider for the transfer.
    LD   DE,(NA_SHAND)                  ; Pass the open object handle to NA_TRANS.
    LD   B,NA_XLEN                      ; Request up to 128 bytes.
    LD   A,ZT_READ                      ; Choose the named-object READ operation.
    CALL NA_TRANS                       ; Refill from the requested byte.
    JR   C,.DONE                        ; Do not publish a failed refill.
    LD   A,H                            ; Test the provider's result count.
    OR   L                              ; Z means it returned no bytes.
    JR   Z,.SHORT                       ; Descriptor promised a byte here.
    LD   A,L                            ; Use the result as cache length.
    LD   (NA_CLEN),A                    ; It fits the 128-byte cache.
    LD   HL,(NA_OFF)                    ; Load the refill offset.
    LD   (NA_CBASE),HL                  ; Publish it as cache base.
    LD   HL,(NA_WORK)                   ; Locate the first byte in the refilled buffer.
    LD   DE,NA_XOFF                     ; Select the transfer buffer.
    ADD  HL,DE                          ; HL now addresses the newly read first byte.
    LD   A,(HL)                         ; Return the byte requested at the cache base.
    OR   A                              ; Clear carry and set Z according to that byte.
    JR   .DONE                          ; Restore caller registers before returning.
.SHORT: ; Reject a read that returned no promised byte.
    LD   A,ZT_STORE                     ; Empty read violates the descriptor.
    SCF                                 ; Distinguish failure from byte zero.
.DONE: ; Restore caller registers after a source read.
    POP  IY                             ; Restore the caller's IY register.
    POP  IX                             ; Restore the caller's IX register.
    POP  BC                             ; Restore the caller's BC pair.
    RET                                 ; Return A, carry and zero status to Atom.
