; Native CP/M ASO v1 writer. It keeps one IMAGE run and one physical record,
; then appends canonical operations to the private temporary file.

asoBeg: ; Beginning of the spool and replay code.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Create the tentative ASO file and write its seven-byte header.

asoInit: ; Open the spool and initialise ASO writer state.
    XOR  A                              ; Clear stream, buffer and transaction state.
    LD   (asoOn),A                      ; Keep ASO dispatch disabled until MAKE succeeds.
    LD   (asoOpen),A                    ; No spool FCB is open yet.
    LD   (asoErr),A                     ; Clear any sticky writer failure.
    LD   (asoStat),A                    ; Clear the returned BDOS status.
    LD   (asoInRec),A                   ; Start with an empty physical record.
    LD   (asoInRun),A                   ; Start with no pending IMAGE bytes.
    LD   (asoImTop),A                   ; The initial image end is an ordinary word.
    LD   (pubOpen),A                    ; The old RAM-output temp is not open.
    LD   (pubKept),A                    ; Publication has not moved the old output.
    LD   (matOwns),A                    ; No internal spool name is owned yet.
    LD   L,(IX+11)                      ; Read the descriptor's target origin.
    LD   H,(IX+12)                      ; Complete the origin address.
    LD   (asoOrg),HL                    ; Retain the ASO header's image origin.
    LD   (asoImEnd),HL                  ; No IMAGE bytes precede the origin.
    LD   A,(pubKind)                    ; Distinguish ASO from an internal spool.
    CP   3                              ; Explicit ASO is already the requested file.
    JR   Z,.temp                        ; Keep its ordinary transaction temporary name.
    CALL pubBak                         ; Use the reserved name for the private spool.
    LD   A,1                            ; Mark that abort must remove this internal spool.
    LD   (matOwns),A                    ; $$B belongs to ASO until replay ends.
    JR   .copy                          ; Copy the selected name into the spool FCB.
.temp: ; Choose the explicit ASO temporary name.
    CALL pubTemp                        ; Build the explicit ASO transaction name.
.copy: ; Prepare the spool FCB for MAKE.
    LD   DE,cpFcb+12                    ; Address the FCB's mutable tail fields.
    XOR  A                              ; Select zero for every unused FCB field.
    LD   B,24                           ; Count the remaining FCB bytes.
    CALL pubFill                        ; Give MAKE a clean temporary-file FCB.
    LD   HL,cpFcb                       ; Copy the complete temporary-file FCB.
    LD   DE,asoFcb                      ; Keep it outside the source and work FCBs.
    LD   BC,36                          ; CP/M FCBs contain thirty-six bytes.
    LDIR                                ; Preserve the ASO FCB during source reads.
    LD   DE,asoFcb                      ; Pass the private ASO FCB to BDOS.
    LD   C,cpMake                       ; Select CP/M make-file function 22.
    CALL cpBdos                         ; Create the tentative sequential spool.
    INC  A                              ; Convert BDOS's $FF failure result to zero.
    JR   Z,.bad                         ; Let the normal abort path remove any residue.
    LD   A,1                            ; Mark the FCB open and enable the ASO hooks.
    LD   (asoOpen),A                    ; hsAbort owns cleanup from this point.
    LD   (asoOn),A                      ; Route output operations into the ASO writer.
    LD   A,'A'                          ; Begin the ASCII ASO signature.
    CALL asoPut                         ; Append the first header byte.
    RET  C                              ; Stop at the first failed physical write.
    LD   A,'S'                          ; Continue the ASCII ASO signature.
    CALL asoPut                         ; Append the second header byte.
    RET  C                              ; Keep the BDOS status for hsAbort.
    LD   A,'O'                          ; Complete the ASCII ASO signature.
    CALL asoPut                         ; Append the third header byte.
    RET  C                              ; Stop if the spool write failed.
    LD   A,1                            ; Select ASO version one.
    CALL asoPut                         ; Append the version byte.
    RET  C                              ; Do not continue after a write failure.
    LD   HL,(asoOrg)                    ; Load the flat image's target origin.
    LD   A,L                            ; Select the little-endian origin low byte.
    CALL asoPut                         ; Append the low byte to the header.
    RET  C                              ; Let the driver abort a failed spool.
    LD   A,H                            ; Select the little-endian origin high byte.
    CALL asoPut                         ; Append the high byte to the header.
    RET  C                              ; Stop after any physical write failure.
    XOR  A                              ; CP/M output currently uses zero gap fill.
    CALL asoPut                         ; Append the ASO header fill byte.
    RET                                 ; Return the final write status to Atom.
.bad: ; Return spool-creation failure.
    JP   asoFail                        ; Report the failed temporary-file creation.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Queue an IMAGE byte in ascending address order for canonical coalescing.

asoEmit: ; Accept one ascending IMAGE byte.
    PUSH BC                             ; Preserve address class and caller byte state.
    LD   (asoVal),A                     ; Retain the byte while validating its address.
    LD   (asoAddr),HL                   ; Retain the absolute IMAGE address.
    LD   A,C                            ; Read the address-space class.
    OR   A                              ; ASO v1 supports only the flat address space.
    JR   NZ,.bad                        ; Reject a banked IMAGE operation.
    LD   HL,(asoAddr)                   ; Load the IMAGE address for origin checking.
    LD   DE,(asoOrg)                    ; Load the declared ASO image origin.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is this byte below the declared origin?
    JR   C,.bad                         ; Reject addresses before the flat image.
    LD   A,(asoImTop)                   ; Check whether the preceding end was $10000.
    OR   A                              ; A set flag leaves no later u16 IMAGE address.
    JR   NZ,.bad                        ; Reject any IMAGE after the endpoint.
    LD   HL,(asoAddr)                   ; Reload the candidate address.
    LD   DE,(asoImEnd)                  ; Read the prior IMAGE's exclusive end.
    OR   A                              ; Clear carry before comparing the endpoints.
    SBC  HL,DE                          ; Require ascending, non-overlapping IMAGE bytes.
    JR   C,.bad                         ; Reject a descending or overlapping byte.
    JR   Z,.append                      ; A matching end extends the pending run.
    CALL asoSync                        ; A gap starts a new canonical IMAGE record.
    JR   C,.fail                        ; Preserve the record-write failure.
.append: ; Start or extend the current IMAGE run.
    LD   A,(asoInRun)                   ; Check whether this run needs a new address.
    OR   A                              ; A zero count marks an empty pending run.
    JR   NZ,.store                      ; A nonempty run already has its start.
    LD   HL,(asoAddr)                   ; Begin at this non-overlapping byte.
    LD   (asoBase),HL                   ; Retain the pending run's absolute start.
.store: ; Copy the validated value into the run.
    LD   A,(asoInRun)                   ; Use the current count as the buffer index.
    LD   E,A                            ; Zero-extend the index into DE.
    LD   D,0                            ; Complete the zero-extended index.
    LD   HL,asoRun                      ; Point at the pending IMAGE buffer.
    ADD  HL,DE                          ; Select the next free run byte.
    LD   A,(asoVal)                     ; Recover the validated IMAGE value.
    LD   (HL),A                         ; Append it to the pending run.
    LD   HL,(asoAddr)                   ; Advance the exclusive IMAGE end.
    INC  HL                             ; Include the byte at the current address.
    LD   (asoImEnd),HL                  ; Retain the low word of the new endpoint.
    LD   A,H                            ; Check whether increment wrapped from $FFFF.
    OR   L                              ; Zero means the mathematical endpoint is $10000.
    JR   NZ,.noWrap                     ; Keep the ordinary 16-bit endpoint.
    LD   A,1                            ; Mark the 17-bit image endpoint.
    LD   (asoImTop),A                   ; No further IMAGE address can be represented.
.noWrap: ; Count the byte after updating the endpoint.
    LD   HL,asoInRun                    ; Address the pending-run byte count.
    INC  (HL)                           ; Include the byte just appended above.
    LD   A,(asoInRun)                   ; Check the canonical 128-byte run limit.
    CP   128                            ; A full run must be emitted immediately.
    JR   NZ,.done                       ; Keep a shorter run pending.
    CALL asoSync                        ; Emit the complete canonical run.
    JR   C,.fail                        ; Propagate a full-run write failure.
.done: ; Restore BC on success.
    POP  BC                             ; Restore the caller's BC pair.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Return successful sink acceptance to Atom.
.fail: ; Restore BC after a physical write failure.
    POP  BC                             ; Restore BC before returning the stream error.
    SCF                                 ; Preserve failure status across stack cleanup.
    RET                                 ; Return the failed record-write status.
.bad: ; Reject invalid IMAGE geometry.
    POP  BC                             ; Restore BC before returning the stream error.
    JP   asoFail                        ; Poison the writer and report an invalid IMAGE.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a one-byte PATCH and pass it to the shared ASO record writer.

asoFixB: ; Stage a byte PATCH for validation.
    LD   (asoVal),A                     ; Retain the replacement byte.
    LD   (asoAddr),HL                   ; Retain the absolute patch address.
    LD   A,1                            ; A byte PATCH has one payload byte.
    LD   (asoLen),A                     ; Save its canonical record length.
    LD   A,C                            ; Save the patch address class.
    LD   (asoSpace),A                   ; The shared validator accepts only flat output.
    JP   asoPatch                       ; Validate and serialise the byte record.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a little-endian word PATCH for the shared ASO record writer.

asoFixW: ; Stage a little-endian word PATCH.
    LD   (asoVal),HL                    ; Retain low and high replacement bytes.
    LD   (asoAddr),DE                   ; Retain the absolute two-byte patch address.
    LD   A,2                            ; A word PATCH has two payload bytes.
    LD   (asoLen),A                     ; Save the record length for range checking.
    LD   A,C                            ; Save the patch address class.
    LD   (asoSpace),A                   ; The shared validator accepts only flat output.

; Validate the patch against the greatest preceding IMAGE endpoint.

asoPatch: ; Check PATCH geometry before writing a record.
    LD   A,(asoSpace)                   ; Read the saved address-space class.
    OR   A                              ; ASO v1 is one flat 16-bit address space.
    JP   NZ,.bad                        ; Reject a banked patch operation.
    LD   HL,(asoAddr)                   ; Load the patch's first target address.
    LD   DE,(asoOrg)                    ; Load the ASO image origin.
    OR   A                              ; Clear carry before comparing addresses.
    SBC  HL,DE                          ; Is the patch before the declared origin?
    JP   C,.bad                         ; Reject patches outside the logical image.
    LD   A,0                            ; Reset the computed endpoint's top flag.
    LD   (asoTop),A                     ; The next addition decides whether it wraps.
    LD   HL,(asoAddr)                   ; Load the first byte's address.
    LD   A,(asoLen)                     ; Read the one- or two-byte payload length.
    LD   E,A                            ; Zero-extend the length for addition.
    LD   D,0                            ; Complete the zero-extended length.
    ADD  HL,DE                          ; Form the exclusive patch endpoint.
    LD   (asoStop),HL                   ; Retain its low word for comparison.
    JR   NC,.inImage                    ; No wrap means an ordinary endpoint.
    LD   A,H                            ; Check the low word after endpoint wrap.
    OR   L                              ; Only zero represents exactly $10000.
    JP   NZ,.bad                        ; Reject an endpoint beyond the address space.
    LD   A,1                            ; Mark a mathematical $10000 endpoint.
    LD   (asoTop),A                     ; Retain its seventeenth bit.
.inImage: ; Check the patch against the IMAGE extent.
    LD   A,(asoImTop)                   ; Read the preceding IMAGE endpoint flag.
    OR   A                              ; A set flag means the image reaches $10000.
    JR   NZ,.write                      ; Every valid patch end is below or at it.
    LD   A,(asoTop)                     ; Check for a patch ending at $10000.
    OR   A                              ; An ordinary IMAGE end cannot contain that end.
    JP   NZ,.bad                        ; Reject a patch beyond the preceding IMAGE.
    LD   HL,(asoStop)                   ; Load the patch's exclusive endpoint.
    LD   DE,(asoImEnd)                  ; Load the greatest preceding IMAGE endpoint.
    OR   A                              ; Clear carry before comparing the endpoints.
    SBC  HL,DE                          ; Require the patch to end at or before IMAGE.
    JR   C,.write                       ; A lower endpoint is contained.
    JR   Z,.write                       ; Equality ends exactly at image high water.
    JP   .bad                           ; A greater endpoint reaches a future byte.
.write: ; Flush IMAGE before serialising PATCH.
    CALL asoSync                        ; PATCH is a barrier between IMAGE runs.
    RET  C                              ; Keep the first failed physical write status.
    LD   A,2                            ; ASO record kind two denotes PATCH.
    CALL asoPut                         ; Append the record kind.
    RET  C                              ; Stop when a physical record write fails.
    LD   HL,(asoAddr)                   ; Load the absolute patch address.
    LD   A,L                            ; Append its little-endian low byte.
    CALL asoPut                         ; Preserve the operation's chronological order.
    RET  C                              ; Propagate any spool-write failure.
    LD   A,H                            ; Append the address high byte.
    CALL asoPut                         ; Continue the four-byte record header.
    RET  C                              ; Leave cleanup to hsAbort.
    LD   A,(asoLen)                     ; Append the one- or two-byte payload length.
    CALL asoPut                         ; Complete the PATCH record header.
    RET  C                              ; Stop after any physical write error.
    LD   HL,(asoVal)                    ; Load the little-endian replacement bytes.
    LD   A,L                            ; Select the patch's low byte.
    CALL asoPut                         ; Append the first replacement byte.
    RET  C                              ; Propagate a failed spool write.
    LD   A,(asoLen)                     ; Check whether this is a two-byte patch.
    CP   2                              ; A byte patch has no second payload byte.
    JR   NZ,.ok                         ; Finish the one-byte patch record.
    LD   A,H                            ; Select the word patch's high byte.
    CALL asoPut                         ; Append its second replacement byte.
    RET  C                              ; Keep the output failure status.
.ok: ; Finish a complete PATCH record.
    XOR  A                              ; Return success after the complete record.
    RET                                 ; The spool remains open for later operations.
.bad: ; Reject invalid PATCH geometry.
    JP   asoFail                        ; Poison the writer after invalid PATCH input.

;@ROUTINE IN A,BC,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate final geometry, append END and record padding, then publish ASO.

asoSeal: ; Validate COMMIT geometry and seal the spool.
    LD   (asoFlags),A                   ; Retain the explicit endpoint flags.
    LD   (asoHigh),BC                   ; Retain high water's low word.
    LD   (asoLast),HL                   ; Retain the final cursor's low word.
    LD   A,(asoFlags)                   ; Read the two defined COMMIT bits.
    AND  $FC                            ; Reject undefined COMMIT flag bits.
    JP   NZ,.bad                        ; Reject a non-canonical flag byte.
    LD   A,(asoFlags)                   ; Check the high-water endpoint representation.
    BIT  1,A                            ; Does bit one mark mathematical $10000?
    JR   Z,.highWord                    ; Otherwise high water is a 16-bit value.
    LD   HL,(asoHigh)                   ; Endpoint words must be stored as zero.
    LD   A,H                            ; Inspect its high byte.
    OR   L                              ; Test whether the saved endpoint is zero.
    JP   NZ,.bad                        ; Reject a nonzero endpoint low word.
    JR   .cursor                        ; Check the final cursor against high water.
.highWord: ; Validate ordinary high water against origin.
    LD   HL,(asoHigh)                   ; Load the ordinary high-water address.
    LD   DE,(asoOrg)                    ; Load the ASO image origin.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Require high water not below the origin.
    JP   C,.bad                         ; Reject an endpoint outside the image.
.cursor: ; Validate the final cursor representation.
    LD   A,(asoFlags)                   ; Check the final cursor's endpoint form.
    BIT  0,A                            ; Does bit zero mark mathematical $10000?
    JR   Z,.lastWord                    ; Otherwise cursor is an ordinary word.
    LD   HL,(asoLast)                   ; Endpoint words must be stored as zero.
    LD   A,H                            ; Inspect the high byte.
    OR   L                              ; Test the complete saved cursor value.
    JP   NZ,.bad                        ; Reject a nonzero endpoint low word.
    LD   A,(asoFlags)                   ; A cursor endpoint requires a high endpoint.
    BIT  1,A                            ; Check that high water is also $10000.
    JP   Z,.bad                         ; Reject cursor above ordinary high water.
    JR   .image                         ; Compare high water with the IMAGE extent.
.lastWord: ; Check an ordinary cursor against image bounds.
    LD   HL,(asoLast)                   ; Load the ordinary final cursor.
    LD   DE,(asoOrg)                    ; Load the declared target origin.
    OR   A                              ; Clear carry before the lower-bound check.
    SBC  HL,DE                          ; Require final cursor not below the origin.
    JP   C,.bad                         ; Reject a cursor outside the target.
    LD   A,(asoFlags)                   ; An ordinary high-water word bounds the cursor.
    BIT  1,A                            ; An endpoint high water needs no word comparison.
    JR   NZ,.image                      ; Any ordinary cursor is below $10000.
    LD   HL,(asoLast)                   ; Reload the ordinary final cursor.
    LD   DE,(asoHigh)                   ; Load the ordinary high-water mark.
    OR   A                              ; Clear carry before the upper-bound comparison.
    SBC  HL,DE                          ; Compare cursor with high water.
    JR   C,.image                       ; A backward ORG may leave a shorter cursor.
    JR   Z,.image                       ; Equality is the ordinary completed case.
    JP   .bad                           ; Reject a cursor beyond high water.
.image: ; Compare emitted IMAGE extent with high water.
    LD   A,(asoImTop)                   ; Check whether IMAGE reaches $10000.
    OR   A                              ; The endpoint requires endpoint high water.
    JR   Z,.iEndWord                    ; Otherwise compare the ordinary words.
    LD   A,(asoFlags)                   ; Load the high-water endpoint bit.
    BIT  1,A                            ; Is high water also the mathematical endpoint?
    JP   Z,.bad                         ; Reject high water below IMAGE extent.
    JR   .append                        ; The full address range includes every IMAGE.
.iEndWord: ; Compare ordinary IMAGE and high-water words.
    LD   A,(asoFlags)                   ; An endpoint high water exceeds every word end.
    BIT  1,A                            ; Does bit one represent $10000?
    JR   NZ,.append                     ; Accept any ordinary IMAGE endpoint.
    LD   HL,(asoHigh)                   ; Load the final exclusive high-water word.
    LD   DE,(asoImEnd)                  ; Load the greatest preceding IMAGE endpoint.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Require IMAGE to fit within committed geometry.
    JP   C,.bad                         ; Reject high water below emitted IMAGE bytes.
.append: ; Append END after the last IMAGE run.
    CALL asoSync                        ; Finish any canonical pending IMAGE record.
    RET  C                              ; Do not write END after an earlier I/O failure.
    XOR  A                              ; ASO record kind zero denotes successful END.
    CALL asoPut                         ; Append the END record kind.
    RET  C                              ; Keep a failed write from looking like success.
    LD   HL,(asoHigh)                   ; Load the exclusive high-water low word.
    LD   A,L                            ; Append its low byte.
    CALL asoPut                         ; Continue the seven-byte END record.
    RET  C                              ; Leave the tentative file for abort cleanup.
    LD   A,H                            ; Append the high-water word's high byte.
    CALL asoPut                         ; Continue the END record.
    RET  C                              ; Do not close an incomplete ASO file.
    LD   A,(asoFlags)                   ; Select the high-water top byte.
    AND  2                              ; Retain only bit one.
    RRCA                                ; Move the endpoint bit into bit zero.
    CALL asoPut                         ; Append high water's seventeenth bit.
    RET  C                              ; Stop if the END record could not be written.
    LD   HL,(asoLast)                   ; Load the final cursor's low word.
    LD   A,L                            ; Append its low byte.
    CALL asoPut                         ; Continue the seven-byte END record.
    RET  C                              ; Keep the spool tentative until it is complete.
    LD   A,H                            ; Append the final cursor's high byte.
    CALL asoPut                         ; Continue the END record.
    RET  C                              ; Stop on an incomplete END record.
    LD   A,(asoFlags)                   ; Select the final cursor's top byte.
    AND  1                              ; Retain only bit zero.
    CALL asoPut                         ; Append the cursor endpoint bit.
    RET  C                              ; Do not publish an unpadded stream.
    CALL asoPad                         ; Pad the final physical record if needed.
    RET  C                              ; Keep the prior output on a failed spool write.
    LD   DE,asoFcb                      ; Pass the sealed ASO FCB to BDOS.
    LD   C,cpClose                      ; Select CP/M close-file function 16.
    CALL cpBdos                         ; Flush and close the completed ASO stream.
    INC  A                              ; Convert BDOS's $FF close failure to zero.
    JR   Z,.closeBad                    ; Let abort retry after close fails.
    XOR  A                              ; Clear the open flag after a successful close.
    LD   (asoOpen),A                    ; The spool can now be renamed transactionally.
    LD   A,(pubKind)                    ; Is the spool the requested file?
    CP   3                              ; Explicit ASO needs no final-image conversion.
    JR   NZ,.replay                     ; COM, BIN and HEX replay to a temp.
    CALL pubSwap                        ; Replace the requested destination on success.
    RET  C                              ; Let hsAbort restore any moved backup.
    XOR  A                              ; Disable the ASO hook path for the next command.
    LD   (asoOn),A                      ; The completed file is now owned by its caller.
    RET                                 ; Return successful COMMIT to the native driver.
.replay: ; Convert a closed internal spool into final output.
; Compilation is complete and the spool FCB is closed. Preserve its name in
; the reclaimed part-order page before the replay window overlays the source.
    LD   HL,asoFcb                      ; Read the writer's now-closed spool FCB.
    LD   DE,matFcb                      ; Move its filename into materialiser-owned RAM.
    LD   BC,36                          ; Copy the complete CP/M file-control block.
    LDIR                                ; Keep spool identity before overlay reuse.
    XOR  A                              ; No replay reader is open at the phase boundary.
    LD   (matOpen),A                    ; Start with the replay reader closed.
    CALL matRun                         ; Replay ASO into the selected flat output format.
    RET  C                              ; Leave hsAbort to clean all tentative files.
    XOR  A                              ; Disable operation dispatch after publication.
    LD   (asoOn),A                      ; The completed output now belongs to the caller.
    RET                                 ; Report the assembled COM or BIN as committed.
.closeBad: ; Retain a failed close for abort cleanup.
    LD   A,1                            ; Report a closed-file service failure.
    LD   (asoStat),A                    ; Retain the failure for the common error return.
    SCF                                 ; Keep the FCB open flag for hsAbort cleanup.
    RET                                 ; Return failure without publishing the spool.
.bad: ; Reject invalid COMMIT geometry.
    JP   asoFail                        ; Reject invalid geometry and prevent END.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write the current full 128-byte ASO record through sequential BDOS output.

asoSave: ; Flush one full physical record.
    LD   DE,asoRec                      ; Point BDOS at the completed physical record.
    LD   C,cpSetDma                     ; Select CP/M's set-DMA-address service.
    CALL cpBdos                         ; Install the writer-owned transfer buffer.
    LD   DE,asoFcb                      ; Pass the active temporary ASO file.
    LD   C,cpWrite                      ; Select sequential record-write function 21.
    CALL cpBdos                         ; Append exactly one physical 128-byte record.
    OR   A                              ; Zero indicates a successful record write.
    JR   NZ,.bad                        ; Retain disk-full and write-failure status.
    XOR  A                              ; Reset the record length after successful output.
    LD   (asoInRec),A                   ; The next ASO byte starts a fresh record.
    RET                                 ; Return with carry clear.
.bad: ; Retain the first BDOS write failure.
    LD   (asoStat),A                    ; Preserve the BDOS write result.
    LD   (asoErr),A                     ; Poison all later writer operations.
    SCF                                 ; Require the transaction abort path.
    RET                                 ; Return the BDOS status in A.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Append one byte to the 128-byte physical record buffer.

asoPut: ; Append one byte with bounded record indexing.
    PUSH BC                             ; Keep the caller's byte counter and class.
    PUSH DE                             ; Preserve any address held in DE.
    PUSH HL                             ; Preserve any address held in HL.
    LD   (asoByte),A                    ; Retain the serialised byte during indexing.
    LD   A,(asoErr)                     ; Check for an earlier writer failure.
    OR   A                              ; A set error forbids further stream output.
    JR   NZ,.error                      ; Return the original failure without mutation.
    LD   A,(asoInRec)                   ; Read the current physical-record length.
    CP   128                            ; A count of 128 is valid only during flushing.
    JR   NC,.invalid                    ; Reject corrupted buffer state.
    LD   E,A                            ; Zero-extend the current write index.
    LD   D,0                            ; Complete the 16-bit record offset.
    LD   HL,asoRec                      ; Address the sequential record buffer.
    ADD  HL,DE                          ; Select its next free byte.
    LD   A,(asoByte)                    ; Recover the byte supplied by the serialiser.
    LD   (HL),A                         ; Append it without touching the source cache.
    LD   A,(asoInRec)                   ; Read the current buffer length.
    INC  A                              ; Include the byte stored above.
    LD   (asoInRec),A                   ; Retain its new physical-record count.
    CP   128                            ; Is the CP/M record now complete?
    JR   NZ,.ok                         ; Keep partial records in the bounded buffer.
    CALL asoSave                        ; Flush a complete sequential BDOS record.
    JR   C,.error                       ; Preserve the sticky write failure.
.ok: ; Restore caller registers after an append.
    POP  HL                             ; Restore the caller's HL value.
    POP  DE                             ; Restore the caller's DE value.
    POP  BC                             ; Restore the caller's BC value.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Complete the single-byte append.
.invalid: ; Poison a corrupt physical-record buffer.
    LD   A,1                            ; Mark an impossible record-buffer state.
    LD   (asoErr),A                     ; Prevent a later END from sealing corruption.
    LD   (asoStat),A                    ; Retain the writer's internal failure code.
.error: ; Restore registers and return the sticky failure.
    LD   A,(asoErr)                     ; Recover the original error before stack restore.
    LD   (asoStat),A                    ; Preserve it across the register pops.
    POP  HL                             ; Restore caller registers without changing flags.
    POP  DE                             ; Keep the error status in dedicated workspace.
    POP  BC                             ; Restore the class and byte-counter pair.
    LD   A,(asoStat)                    ; Return the retained error code.
    SCF                                 ; Carry forces the caller to abort publication.
    RET                                 ; Return the sticky writer failure.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize a pending run as one canonical IMAGE record.

asoSync: ; Flush the pending canonical IMAGE run.
    LD   A,(asoInRun)                   ; Read the number of buffered IMAGE bytes.
    OR   A                              ; An empty run has nothing to serialise.
    JR   NZ,.nonEmpty                   ; Continue when IMAGE bytes are queued.
    XOR  A                              ; No-op success must clear stale carry.
    RET                                 ; Return without changing the empty run.
.nonEmpty: ; Write the run header and payload.
    LD   B,A                            ; Preserve the run length across byte appends.
    LD   A,1                            ; ASO record kind one denotes IMAGE.
    CALL asoPut                         ; Append the record type.
    RET  C                              ; Stop before writing an incomplete header.
    LD   HL,(asoBase)                   ; Load the run's first absolute address.
    LD   A,L                            ; Append the little-endian address low byte.
    CALL asoPut                         ; Continue the canonical record header.
    RET  C                              ; Propagate a physical write failure.
    LD   A,H                            ; Append the address high byte.
    CALL asoPut                         ; Continue the record header.
    RET  C                              ; Do not write payload after a failed header.
    LD   A,B                            ; Append the run length from one through 128.
    CALL asoPut                         ; Finish the IMAGE record header.
    RET  C                              ; Stop when the record cannot be completed.
    LD   HL,asoRun                      ; Point at the first buffered IMAGE byte.
.loop: ; Serialise each buffered IMAGE byte.
    LD   A,(HL)                         ; Load the next pending IMAGE value.
    CALL asoPut                         ; Append it in source-operation order.
    RET  C                              ; Preserve the first failed physical write.
    INC  HL                             ; Advance to the following pending byte.
    DJNZ .loop                          ; Continue through the retained run length.
    XOR  A                              ; Clear the run only after all bytes were written.
    LD   (asoInRun),A                   ; The next IMAGE begins another record.
    RET                                 ; Return success with the spool still open.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pad a partial last record with exactly the CP/M-required $1A bytes.

asoPad: ; Pad only the final partial physical record.
    LD   A,(asoInRec)                   ; Read the bytes already queued for output.
    OR   A                              ; Zero means END ended on a record boundary.
    JR   NZ,.partial                    ; Pad only a partial final record.
    XOR  A                              ; A complete record boundary is successful.
    RET                                 ; Do not append an unnecessary extra record.
.partial: ; Compute the padding needed to reach 128 bytes.
    LD   B,A                            ; Retain the partial-record byte count.
    LD   A,128                          ; Select the CP/M physical-record length.
    SUB  B                              ; Calculate the exact number of pad bytes.
    LD   B,A                            ; Retain the bounded fill count in B.
.loop: ; Append SUB padding through the normal writer.
    LD   A,$1A                          ; Restore the fill byte after each helper call.
    CALL asoPut                         ; Append one byte, flushing exactly at 128.
    RET  C                              ; Do not close an incomplete padded stream.
    DJNZ .loop                          ; Finish the single final physical record.
    XOR  A                              ; Return success after the record was flushed.
    RET                                 ; No logical ASO bytes follow END.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return a sticky write or validation failure to the native output driver.

asoFail: ; Mark the transaction failed.
    LD   A,1                            ; Use the established host-output failure status.
    LD   (asoErr),A                     ; Prevent END from following a failed operation.
    LD   (asoStat),A                    ; Keep the failure through any register restore.
    SCF                                 ; Tell the driver to abort this output.
    RET                                 ; Return the output-service failure.
