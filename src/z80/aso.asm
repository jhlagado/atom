; Native CP/M ASO v1 writer. It keeps one IMAGE run and one physical record,
; then appends canonical operations to the private temporary file.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Create the tentative ASO file and write its seven-byte header.

ASO_BEG: ; Open the spool and initialise ASO writer state.
    XOR  A                              ; Clear stream, buffer and transaction state.
    LD   (ASO_ON),A                     ; Keep ASO dispatch disabled until MAKE succeeds.
    LD   (ASO_OPEN),A                   ; No spool FCB is open yet.
    LD   (ASO_ERR),A                    ; Clear any sticky writer failure.
    LD   (ASO_STAT),A                   ; Clear the returned BDOS status.
    LD   (ASO_RLEN),A                   ; Start with an empty physical record.
    LD   (ASO_PEND),A                   ; Start with no pending IMAGE bytes.
    LD   (ASO_ITOP),A                   ; The initial image end is an ordinary word.
    LD   (PUB_OPEN),A                   ; The old RAM-output temp is not open.
    LD   (PUB_KEPT),A                   ; Publication has not moved the old output.
    LD   (MAT_OWNS),A                   ; No internal spool name is owned yet.
    LD   L,(IX+11)                      ; Read the descriptor's target origin.
    LD   H,(IX+12)                      ; Complete the origin address.
    LD   (ASO_ORG),HL                   ; Retain the ASO header's image origin.
    LD   (ASO_IEND),HL                  ; No IMAGE bytes precede the origin.
    LD   A,(PUB_KIND)                   ; Distinguish ASO from an internal spool.
    CP   3                              ; Explicit ASO is already the requested file.
    JR   Z,.TEMP                        ; Keep its ordinary transaction temporary name.
    CALL PUB_BAK                        ; Use the reserved name for the private spool.
    LD   A,1                            ; Mark that abort must remove this internal spool.
    LD   (MAT_OWNS),A                   ; $$B belongs to ASO until replay ends.
    JR   .COPY                          ; Copy the selected name into the spool FCB.
.TEMP: ; Choose the explicit ASO temporary name.
    CALL PUB_TEMP                       ; Build the explicit ASO transaction name.
.COPY: ; Prepare the spool FCB for MAKE.
    LD   DE,CP_FCB+12                   ; Address the FCB's mutable tail fields.
    XOR  A                              ; Select zero for every unused FCB field.
    LD   B,24                           ; Count the remaining FCB bytes.
    CALL PUB_FILL                       ; Give MAKE a clean temporary-file FCB.
    LD   HL,CP_FCB                      ; Copy the complete temporary-file FCB.
    LD   DE,ASO_FCB                     ; Keep it outside the source and work FCBs.
    LD   BC,36                          ; CP/M FCBs contain thirty-six bytes.
    LDIR                                ; Preserve the ASO FCB during source reads.
    LD   DE,ASO_FCB                     ; Pass the private ASO FCB to BDOS.
    LD   C,CP_MAKE                      ; Select CP/M make-file function 22.
    CALL CP_BDOS                        ; Create the tentative sequential spool.
    INC  A                              ; Convert BDOS's $FF failure result to zero.
    JR   Z,.BAD                         ; Let the normal abort path remove any residue.
    LD   A,1                            ; Mark the FCB open and enable the ASO hooks.
    LD   (ASO_OPEN),A                   ; HS_ABORT owns cleanup from this point.
    LD   (ASO_ON),A                     ; Route output operations into the ASO writer.
    LD   A,'A'                          ; Begin the ASCII ASO signature.
    CALL ASO_PUT                        ; Append the first header byte.
    RET  C                              ; Stop at the first failed physical write.
    LD   A,'S'                          ; Continue the ASCII ASO signature.
    CALL ASO_PUT                        ; Append the second header byte.
    RET  C                              ; Keep the BDOS status for HS_ABORT.
    LD   A,'O'                          ; Complete the ASCII ASO signature.
    CALL ASO_PUT                        ; Append the third header byte.
    RET  C                              ; Stop if the spool write failed.
    LD   A,1                            ; Select ASO version one.
    CALL ASO_PUT                        ; Append the version byte.
    RET  C                              ; Do not continue after a write failure.
    LD   HL,(ASO_ORG)                   ; Load the flat image's target origin.
    LD   A,L                            ; Select the little-endian origin low byte.
    CALL ASO_PUT                        ; Append the low byte to the header.
    RET  C                              ; Let the driver abort a failed spool.
    LD   A,H                            ; Select the little-endian origin high byte.
    CALL ASO_PUT                        ; Append the high byte to the header.
    RET  C                              ; Stop after any physical write failure.
    XOR  A                              ; CP/M output currently uses zero gap fill.
    CALL ASO_PUT                        ; Append the ASO header fill byte.
    RET                                 ; Return the final write status to Atom.
.BAD: ; Return spool-creation failure.
    JP   ASO_FAIL                       ; Report the failed temporary-file creation.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Queue an IMAGE byte in ascending address order for canonical coalescing.

ASO_EMIT: ; Accept one ascending IMAGE byte.
    PUSH BC                             ; Preserve address class and caller byte state.
    LD   (ASO_VAL),A                    ; Retain the byte while validating its address.
    LD   (ASO_ADDR),HL                  ; Retain the absolute IMAGE address.
    LD   A,C                            ; Read the address-space class.
    OR   A                              ; ASO v1 supports only the flat address space.
    JR   NZ,.BAD                        ; Reject a banked IMAGE operation.
    LD   HL,(ASO_ADDR)                  ; Load the IMAGE address for origin checking.
    LD   DE,(ASO_ORG)                   ; Load the declared ASO image origin.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is this byte below the declared origin?
    JR   C,.BAD                         ; Reject addresses before the flat image.
    LD   A,(ASO_ITOP)                   ; Check whether the preceding end was $10000.
    OR   A                              ; A set flag leaves no later u16 IMAGE address.
    JR   NZ,.BAD                        ; Reject any IMAGE after the endpoint.
    LD   HL,(ASO_ADDR)                  ; Reload the candidate address.
    LD   DE,(ASO_IEND)                  ; Read the prior IMAGE's exclusive end.
    OR   A                              ; Clear carry before comparing the endpoints.
    SBC  HL,DE                          ; Require ascending, non-overlapping IMAGE bytes.
    JR   C,.BAD                         ; Reject a descending or overlapping byte.
    JR   Z,.APPEND                      ; A matching end extends the pending run.
    CALL ASO_SYNC                       ; A gap starts a new canonical IMAGE record.
    JR   C,.FAIL                        ; Preserve the record-write failure.
.APPEND: ; Start or extend the current IMAGE run.
    LD   A,(ASO_PEND)                   ; Check whether this run needs a new address.
    OR   A                              ; A zero count marks an empty pending run.
    JR   NZ,.STORE                      ; A nonempty run already has its start.
    LD   HL,(ASO_ADDR)                  ; Begin at this non-overlapping byte.
    LD   (ASO_BASE),HL                  ; Retain the pending run's absolute start.
.STORE: ; Copy the validated value into the run.
    LD   A,(ASO_PEND)                   ; Use the current count as the buffer index.
    LD   E,A                            ; Zero-extend the index into DE.
    LD   D,0                            ; Complete the zero-extended index.
    LD   HL,ASO_RUN                     ; Point at the pending IMAGE buffer.
    ADD  HL,DE                          ; Select the next free run byte.
    LD   A,(ASO_VAL)                    ; Recover the validated IMAGE value.
    LD   (HL),A                         ; Append it to the pending run.
    LD   HL,(ASO_ADDR)                  ; Advance the exclusive IMAGE end.
    INC  HL                             ; Include the byte at the current address.
    LD   (ASO_IEND),HL                  ; Retain the low word of the new endpoint.
    LD   A,H                            ; Check whether increment wrapped from $FFFF.
    OR   L                              ; Zero means the mathematical endpoint is $10000.
    JR   NZ,.NOWRAP                     ; Keep the ordinary 16-bit endpoint.
    LD   A,1                            ; Mark the 17-bit image endpoint.
    LD   (ASO_ITOP),A                   ; No further IMAGE address can be represented.
.NOWRAP: ; Count the byte after updating the endpoint.
    LD   HL,ASO_PEND                    ; Address the pending-run byte count.
    INC  (HL)                           ; Include the byte just appended above.
    LD   A,(ASO_PEND)                   ; Check the canonical 128-byte run limit.
    CP   128                            ; A full run must be emitted immediately.
    JR   NZ,.DONE                       ; Keep a shorter run pending.
    CALL ASO_SYNC                       ; Emit the complete canonical run.
    JR   C,.FAIL                        ; Propagate a full-run write failure.
.DONE: ; Restore BC on success.
    POP  BC                             ; Restore the caller's BC pair.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Return successful sink acceptance to Atom.
.FAIL: ; Restore BC after a physical write failure.
    POP  BC                             ; Restore BC before returning the stream error.
    SCF                                 ; Preserve failure status across stack cleanup.
    RET                                 ; Return the failed record-write status.
.BAD: ; Reject invalid IMAGE geometry.
    POP  BC                             ; Restore BC before returning the stream error.
    JP   ASO_FAIL                       ; Poison the writer and report an invalid IMAGE.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a one-byte PATCH and pass it to the shared ASO record writer.

ASO_FIXB: ; Stage a byte PATCH for validation.
    LD   (ASO_VAL),A                    ; Retain the replacement byte.
    LD   (ASO_ADDR),HL                  ; Retain the absolute patch address.
    LD   A,1                            ; A byte PATCH has one payload byte.
    LD   (ASO_LEN),A                    ; Save its canonical record length.
    LD   A,C                            ; Save the patch address class.
    LD   (ASO_BANK),A                   ; The shared validator accepts only flat output.
    JP   ASO_FIX                        ; Validate and serialise the byte record.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a little-endian word PATCH for the shared ASO record writer.

ASO_FIXW: ; Stage a little-endian word PATCH.
    LD   (ASO_VAL),HL                   ; Retain low and high replacement bytes.
    LD   (ASO_ADDR),DE                  ; Retain the absolute two-byte patch address.
    LD   A,2                            ; A word PATCH has two payload bytes.
    LD   (ASO_LEN),A                    ; Save the record length for range checking.
    LD   A,C                            ; Save the patch address class.
    LD   (ASO_BANK),A                   ; The shared validator accepts only flat output.

; Validate the patch against the greatest preceding IMAGE endpoint.

ASO_FIX: ; Check PATCH geometry before writing a record.
    LD   A,(ASO_BANK)                   ; Read the saved address-space class.
    OR   A                              ; ASO v1 is one flat 16-bit address space.
    JP   NZ,.BAD                        ; Reject a banked patch operation.
    LD   HL,(ASO_ADDR)                  ; Load the patch's first target address.
    LD   DE,(ASO_ORG)                   ; Load the ASO image origin.
    OR   A                              ; Clear carry before comparing addresses.
    SBC  HL,DE                          ; Is the patch before the declared origin?
    JP   C,.BAD                         ; Reject patches outside the logical image.
    LD   A,0                            ; Reset the computed endpoint's top flag.
    LD   (ASO_PTOP),A                   ; The next addition decides whether it wraps.
    LD   HL,(ASO_ADDR)                  ; Load the first byte's address.
    LD   A,(ASO_LEN)                    ; Read the one- or two-byte payload length.
    LD   E,A                            ; Zero-extend the length for addition.
    LD   D,0                            ; Complete the zero-extended length.
    ADD  HL,DE                          ; Form the exclusive patch endpoint.
    LD   (ASO_STOP),HL                  ; Retain its low word for comparison.
    JR   NC,.INIMAGE                    ; No wrap means an ordinary endpoint.
    LD   A,H                            ; Check the low word after endpoint wrap.
    OR   L                              ; Only zero represents exactly $10000.
    JP   NZ,.BAD                        ; Reject an endpoint beyond the address space.
    LD   A,1                            ; Mark a mathematical $10000 endpoint.
    LD   (ASO_PTOP),A                   ; Retain its seventeenth bit.
.INIMAGE: ; Check the patch against the IMAGE extent.
    LD   A,(ASO_ITOP)                   ; Read the preceding IMAGE endpoint flag.
    OR   A                              ; A set flag means the image reaches $10000.
    JR   NZ,.WRITE                      ; Every valid patch end is below or at it.
    LD   A,(ASO_PTOP)                   ; Check for a patch ending at $10000.
    OR   A                              ; An ordinary IMAGE end cannot contain that end.
    JP   NZ,.BAD                        ; Reject a patch beyond the preceding IMAGE.
    LD   HL,(ASO_STOP)                  ; Load the patch's exclusive endpoint.
    LD   DE,(ASO_IEND)                  ; Load the greatest preceding IMAGE endpoint.
    OR   A                              ; Clear carry before comparing the endpoints.
    SBC  HL,DE                          ; Require the patch to end at or before IMAGE.
    JR   C,.WRITE                       ; A lower endpoint is contained.
    JR   Z,.WRITE                       ; Equality ends exactly at image high water.
    JP   .BAD                           ; A greater endpoint reaches a future byte.
.WRITE: ; Flush IMAGE before serialising PATCH.
    CALL ASO_SYNC                       ; PATCH is a barrier between IMAGE runs.
    RET  C                              ; Keep the first failed physical write status.
    LD   A,2                            ; ASO record kind two denotes PATCH.
    CALL ASO_PUT                        ; Append the record kind.
    RET  C                              ; Stop when a physical record write fails.
    LD   HL,(ASO_ADDR)                  ; Load the absolute patch address.
    LD   A,L                            ; Append its little-endian low byte.
    CALL ASO_PUT                        ; Preserve the operation's chronological order.
    RET  C                              ; Propagate any spool-write failure.
    LD   A,H                            ; Append the address high byte.
    CALL ASO_PUT                        ; Continue the four-byte record header.
    RET  C                              ; Leave cleanup to HS_ABORT.
    LD   A,(ASO_LEN)                    ; Append the one- or two-byte payload length.
    CALL ASO_PUT                        ; Complete the PATCH record header.
    RET  C                              ; Stop after any physical write error.
    LD   HL,(ASO_VAL)                   ; Load the little-endian replacement bytes.
    LD   A,L                            ; Select the patch's low byte.
    CALL ASO_PUT                        ; Append the first replacement byte.
    RET  C                              ; Propagate a failed spool write.
    LD   A,(ASO_LEN)                    ; Check whether this is a two-byte patch.
    CP   2                              ; A byte patch has no second payload byte.
    JR   NZ,.OK                         ; Finish the one-byte patch record.
    LD   A,H                            ; Select the word patch's high byte.
    CALL ASO_PUT                        ; Append its second replacement byte.
    RET  C                              ; Keep the output failure status.
.OK: ; Finish a complete PATCH record.
    XOR  A                              ; Return success after the complete record.
    RET                                 ; The spool remains open for later operations.
.BAD: ; Reject invalid PATCH geometry.
    JP   ASO_FAIL                       ; Poison the writer after invalid PATCH input.

;@ROUTINE IN A,BC,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate final geometry, append END and record padding, then publish ASO.

ASO_CMT: ; Validate COMMIT geometry and seal the spool.
    LD   (ASO_FLAG),A                   ; Retain the explicit endpoint flags.
    LD   (ASO_HIGH),BC                  ; Retain high water's low word.
    LD   (ASO_LAST),HL                  ; Retain the final cursor's low word.
    LD   A,(ASO_FLAG)                   ; Read the two defined COMMIT bits.
    AND  $FC                            ; Reject undefined COMMIT flag bits.
    JP   NZ,.BAD                        ; Reject a non-canonical flag byte.
    LD   A,(ASO_FLAG)                   ; Check the high-water endpoint representation.
    BIT  1,A                            ; Does bit one mark mathematical $10000?
    JR   Z,.HIGHWORD                    ; Otherwise high water is a 16-bit value.
    LD   HL,(ASO_HIGH)                  ; Endpoint words must be stored as zero.
    LD   A,H                            ; Inspect its high byte.
    OR   L                              ; Test whether the saved endpoint is zero.
    JP   NZ,.BAD                        ; Reject a nonzero endpoint low word.
    JR   .CURSOR                        ; Check the final cursor against high water.
.HIGHWORD: ; Validate ordinary high water against origin.
    LD   HL,(ASO_HIGH)                  ; Load the ordinary high-water address.
    LD   DE,(ASO_ORG)                   ; Load the ASO image origin.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Require high water not below the origin.
    JP   C,.BAD                         ; Reject an endpoint outside the image.
.CURSOR: ; Validate the final cursor representation.
    LD   A,(ASO_FLAG)                   ; Check the final cursor's endpoint form.
    BIT  0,A                            ; Does bit zero mark mathematical $10000?
    JR   Z,.LASTWORD                    ; Otherwise cursor is an ordinary word.
    LD   HL,(ASO_LAST)                  ; Endpoint words must be stored as zero.
    LD   A,H                            ; Inspect the high byte.
    OR   L                              ; Test the complete saved cursor value.
    JP   NZ,.BAD                        ; Reject a nonzero endpoint low word.
    LD   A,(ASO_FLAG)                   ; A cursor endpoint requires a high endpoint.
    BIT  1,A                            ; Check that high water is also $10000.
    JP   Z,.BAD                         ; Reject cursor above ordinary high water.
    JR   .IMAGE                         ; Compare high water with the IMAGE extent.
.LASTWORD: ; Check an ordinary cursor against image bounds.
    LD   HL,(ASO_LAST)                  ; Load the ordinary final cursor.
    LD   DE,(ASO_ORG)                   ; Load the declared target origin.
    OR   A                              ; Clear carry before the lower-bound check.
    SBC  HL,DE                          ; Require final cursor not below the origin.
    JP   C,.BAD                         ; Reject a cursor outside the target.
    LD   A,(ASO_FLAG)                   ; An ordinary high-water word bounds the cursor.
    BIT  1,A                            ; An endpoint high water needs no word comparison.
    JR   NZ,.IMAGE                      ; Any ordinary cursor is below $10000.
    LD   HL,(ASO_LAST)                  ; Reload the ordinary final cursor.
    LD   DE,(ASO_HIGH)                  ; Load the ordinary high-water mark.
    OR   A                              ; Clear carry before the upper-bound comparison.
    SBC  HL,DE                          ; Compare cursor with high water.
    JR   C,.IMAGE                       ; A backward ORG may leave a shorter cursor.
    JR   Z,.IMAGE                       ; Equality is the ordinary completed case.
    JP   .BAD                           ; Reject a cursor beyond high water.
.IMAGE: ; Compare emitted IMAGE extent with high water.
    LD   A,(ASO_ITOP)                   ; Check whether IMAGE reaches $10000.
    OR   A                              ; The endpoint requires endpoint high water.
    JR   Z,.IENDWORD                    ; Otherwise compare the ordinary words.
    LD   A,(ASO_FLAG)                   ; Load the high-water endpoint bit.
    BIT  1,A                            ; Is high water also the mathematical endpoint?
    JP   Z,.BAD                         ; Reject high water below IMAGE extent.
    JR   .APPEND                        ; The full address range includes every IMAGE.
.IENDWORD: ; Compare ordinary IMAGE and high-water words.
    LD   A,(ASO_FLAG)                   ; An endpoint high water exceeds every word end.
    BIT  1,A                            ; Does bit one represent $10000?
    JR   NZ,.APPEND                     ; Accept any ordinary IMAGE endpoint.
    LD   HL,(ASO_HIGH)                  ; Load the final exclusive high-water word.
    LD   DE,(ASO_IEND)                  ; Load the greatest preceding IMAGE endpoint.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Require IMAGE to fit within committed geometry.
    JP   C,.BAD                         ; Reject high water below emitted IMAGE bytes.
.APPEND: ; Append END after the last IMAGE run.
    CALL ASO_SYNC                       ; Finish any canonical pending IMAGE record.
    RET  C                              ; Do not write END after an earlier I/O failure.
    XOR  A                              ; ASO record kind zero denotes successful END.
    CALL ASO_PUT                        ; Append the END record kind.
    RET  C                              ; Keep a failed write from looking like success.
    LD   HL,(ASO_HIGH)                  ; Load the exclusive high-water low word.
    LD   A,L                            ; Append its low byte.
    CALL ASO_PUT                        ; Continue the seven-byte END record.
    RET  C                              ; Leave the tentative file for abort cleanup.
    LD   A,H                            ; Append the high-water word's high byte.
    CALL ASO_PUT                        ; Continue the END record.
    RET  C                              ; Do not close an incomplete ASO file.
    LD   A,(ASO_FLAG)                   ; Select the high-water top byte.
    AND  2                              ; Retain only bit one.
    RRCA                                ; Move the endpoint bit into bit zero.
    CALL ASO_PUT                        ; Append high water's seventeenth bit.
    RET  C                              ; Stop if the END record could not be written.
    LD   HL,(ASO_LAST)                  ; Load the final cursor's low word.
    LD   A,L                            ; Append its low byte.
    CALL ASO_PUT                        ; Continue the seven-byte END record.
    RET  C                              ; Keep the spool tentative until it is complete.
    LD   A,H                            ; Append the final cursor's high byte.
    CALL ASO_PUT                        ; Continue the END record.
    RET  C                              ; Stop on an incomplete END record.
    LD   A,(ASO_FLAG)                   ; Select the final cursor's top byte.
    AND  1                              ; Retain only bit zero.
    CALL ASO_PUT                        ; Append the cursor endpoint bit.
    RET  C                              ; Do not publish an unpadded stream.
    CALL ASO_PAD                        ; Pad the final physical record if needed.
    RET  C                              ; Keep the prior output on a failed spool write.
    LD   DE,ASO_FCB                     ; Pass the sealed ASO FCB to BDOS.
    LD   C,CP_CLOSE                     ; Select CP/M close-file function 16.
    CALL CP_BDOS                        ; Flush and close the completed ASO stream.
    INC  A                              ; Convert BDOS's $FF close failure to zero.
    JR   Z,.CLOSEBAD                    ; Let abort retry after close fails.
    XOR  A                              ; Clear the open flag after a successful close.
    LD   (ASO_OPEN),A                   ; The spool can now be renamed transactionally.
    LD   A,(PUB_KIND)                   ; Is the spool the requested file?
    CP   3                              ; Explicit ASO needs no final-image conversion.
    JR   NZ,.REPLAY                     ; COM, BIN and HEX replay to a temp.
    CALL PUB_SWAP                       ; Replace the requested destination on success.
    RET  C                              ; Let HS_ABORT restore any moved backup.
    XOR  A                              ; Disable the ASO hook path for the next command.
    LD   (ASO_ON),A                     ; The completed file is now owned by its caller.
    RET                                 ; Return successful COMMIT to the native driver.
.REPLAY: ; Convert a closed internal spool into final output.
; Compilation is complete and the spool FCB is closed. Preserve its name in
; the reclaimed part-order page before the replay window overlays the source.
    LD   HL,ASO_FCB                     ; Read the writer's now-closed spool FCB.
    LD   DE,MAT_FCB                     ; Move its filename into materialiser-owned RAM.
    LD   BC,36                          ; Copy the complete CP/M file-control block.
    LDIR                                ; Keep spool identity before overlay reuse.
    XOR  A                              ; No replay reader is open at the phase boundary.
    LD   (MAT_OPEN),A                   ; Start with the replay reader closed.
    CALL MAT_RUN                        ; Replay ASO into the selected flat output format.
    RET  C                              ; Leave HS_ABORT to clean all tentative files.
    XOR  A                              ; Disable operation dispatch after publication.
    LD   (ASO_ON),A                     ; The completed output now belongs to the caller.
    RET                                 ; Report the assembled COM or BIN as committed.
.CLOSEBAD: ; Retain a failed close for abort cleanup.
    LD   A,1                            ; Report a closed-file service failure.
    LD   (ASO_STAT),A                   ; Retain the failure for the common error return.
    SCF                                 ; Keep the FCB open flag for HS_ABORT cleanup.
    RET                                 ; Return failure without publishing the spool.
.BAD: ; Reject invalid COMMIT geometry.
    JP   ASO_FAIL                       ; Reject invalid geometry and prevent END.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write the current full 128-byte ASO record through sequential BDOS output.

ASO_SAVE: ; Flush one full physical record.
    LD   DE,ASO_REC                     ; Point BDOS at the completed physical record.
    LD   C,CP_DMA                       ; Select CP/M's set-DMA-address service.
    CALL CP_BDOS                        ; Install the writer-owned transfer buffer.
    LD   DE,ASO_FCB                     ; Pass the active temporary ASO file.
    LD   C,CP_WRITE                     ; Select sequential record-write function 21.
    CALL CP_BDOS                        ; Append exactly one physical 128-byte record.
    OR   A                              ; Zero indicates a successful record write.
    JR   NZ,.BAD                        ; Retain disk-full and write-failure status.
    XOR  A                              ; Reset the record length after successful output.
    LD   (ASO_RLEN),A                   ; The next ASO byte starts a fresh record.
    RET                                 ; Return with carry clear.
.BAD: ; Retain the first BDOS write failure.
    LD   (ASO_STAT),A                   ; Preserve the BDOS write result.
    LD   (ASO_ERR),A                    ; Poison all later writer operations.
    SCF                                 ; Require the transaction abort path.
    RET                                 ; Return the BDOS status in A.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Append one byte to the 128-byte physical record buffer.

ASO_PUT: ; Append one byte with bounded record indexing.
    PUSH BC                             ; Keep the caller's byte counter and class.
    PUSH DE                             ; Preserve any address held in DE.
    PUSH HL                             ; Preserve any address held in HL.
    LD   (ASO_BYTE),A                   ; Retain the serialised byte during indexing.
    LD   A,(ASO_ERR)                    ; Check for an earlier writer failure.
    OR   A                              ; A set error forbids further stream output.
    JR   NZ,.ERROR                      ; Return the original failure without mutation.
    LD   A,(ASO_RLEN)                   ; Read the current physical-record length.
    CP   128                            ; A count of 128 is valid only during flushing.
    JR   NC,.INVALID                    ; Reject corrupted buffer state.
    LD   E,A                            ; Zero-extend the current write index.
    LD   D,0                            ; Complete the 16-bit record offset.
    LD   HL,ASO_REC                     ; Address the sequential record buffer.
    ADD  HL,DE                          ; Select its next free byte.
    LD   A,(ASO_BYTE)                   ; Recover the byte supplied by the serialiser.
    LD   (HL),A                         ; Append it without touching the source cache.
    LD   A,(ASO_RLEN)                   ; Read the current buffer length.
    INC  A                              ; Include the byte stored above.
    LD   (ASO_RLEN),A                   ; Retain its new physical-record count.
    CP   128                            ; Is the CP/M record now complete?
    JR   NZ,.OK                         ; Keep partial records in the bounded buffer.
    CALL ASO_SAVE                       ; Flush a complete sequential BDOS record.
    JR   C,.ERROR                       ; Preserve the sticky write failure.
.OK: ; Restore caller registers after an append.
    POP  HL                             ; Restore the caller's HL value.
    POP  DE                             ; Restore the caller's DE value.
    POP  BC                             ; Restore the caller's BC value.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Complete the single-byte append.
.INVALID: ; Poison a corrupt physical-record buffer.
    LD   A,1                            ; Mark an impossible record-buffer state.
    LD   (ASO_ERR),A                    ; Prevent a later END from sealing corruption.
    LD   (ASO_STAT),A                   ; Retain the writer's internal failure code.
.ERROR: ; Restore registers and return the sticky failure.
    LD   A,(ASO_ERR)                    ; Recover the original error before stack restore.
    LD   (ASO_STAT),A                   ; Preserve it across the register pops.
    POP  HL                             ; Restore caller registers without changing flags.
    POP  DE                             ; Keep the error status in dedicated workspace.
    POP  BC                             ; Restore the class and byte-counter pair.
    LD   A,(ASO_STAT)                   ; Return the retained error code.
    SCF                                 ; Carry forces the caller to abort publication.
    RET                                 ; Return the sticky writer failure.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize a pending run as one canonical IMAGE record.

ASO_SYNC: ; Flush the pending canonical IMAGE run.
    LD   A,(ASO_PEND)                   ; Read the number of buffered IMAGE bytes.
    OR   A                              ; An empty run has nothing to serialise.
    JR   NZ,.NONEMPTY                   ; Continue when IMAGE bytes are queued.
    XOR  A                              ; No-op success must clear stale carry.
    RET                                 ; Return without changing the empty run.
.NONEMPTY: ; Write the run header and payload.
    LD   B,A                            ; Preserve the run length across byte appends.
    LD   A,1                            ; ASO record kind one denotes IMAGE.
    CALL ASO_PUT                        ; Append the record type.
    RET  C                              ; Stop before writing an incomplete header.
    LD   HL,(ASO_BASE)                  ; Load the run's first absolute address.
    LD   A,L                            ; Append the little-endian address low byte.
    CALL ASO_PUT                        ; Continue the canonical record header.
    RET  C                              ; Propagate a physical write failure.
    LD   A,H                            ; Append the address high byte.
    CALL ASO_PUT                        ; Continue the record header.
    RET  C                              ; Do not write payload after a failed header.
    LD   A,B                            ; Append the run length from one through 128.
    CALL ASO_PUT                        ; Finish the IMAGE record header.
    RET  C                              ; Stop when the record cannot be completed.
    LD   HL,ASO_RUN                     ; Point at the first buffered IMAGE byte.
.LOOP: ; Serialise each buffered IMAGE byte.
    LD   A,(HL)                         ; Load the next pending IMAGE value.
    CALL ASO_PUT                        ; Append it in source-operation order.
    RET  C                              ; Preserve the first failed physical write.
    INC  HL                             ; Advance to the following pending byte.
    DJNZ .LOOP                          ; Continue through the retained run length.
    XOR  A                              ; Clear the run only after all bytes were written.
    LD   (ASO_PEND),A                   ; The next IMAGE begins another record.
    RET                                 ; Return success with the spool still open.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pad a partial last record with exactly the CP/M-required $1A bytes.

ASO_PAD: ; Pad only the final partial physical record.
    LD   A,(ASO_RLEN)                   ; Read the bytes already queued for output.
    OR   A                              ; Zero means END ended on a record boundary.
    JR   NZ,.PARTIAL                    ; Pad only a partial final record.
    XOR  A                              ; A complete record boundary is successful.
    RET                                 ; Do not append an unnecessary extra record.
.PARTIAL: ; Compute the padding needed to reach 128 bytes.
    LD   B,A                            ; Retain the partial-record byte count.
    LD   A,128                          ; Select the CP/M physical-record length.
    SUB  B                              ; Calculate the exact number of pad bytes.
    LD   B,A                            ; Retain the bounded fill count in B.
.LOOP: ; Append SUB padding through the normal writer.
    LD   A,$1A                          ; Restore the fill byte after each helper call.
    CALL ASO_PUT                        ; Append one byte, flushing exactly at 128.
    RET  C                              ; Do not close an incomplete padded stream.
    DJNZ .LOOP                          ; Finish the single final physical record.
    XOR  A                              ; Return success after the record was flushed.
    RET                                 ; No logical ASO bytes follow END.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return a sticky write or validation failure to the native output driver.

ASO_FAIL: ; Mark the transaction failed.
    LD   A,1                            ; Use the established host-output failure status.
    LD   (ASO_ERR),A                    ; Prevent END from following a failed operation.
    LD   (ASO_STAT),A                   ; Keep the failure through any register restore.
    SCF                                 ; Tell the driver to abort this output.
    RET                                 ; Return the output-service failure.
