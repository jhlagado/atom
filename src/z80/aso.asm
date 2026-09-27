; Native CP/M ASO v1 writer. It keeps one IMAGE run and one physical record,
; then appends canonical operations to the private temporary file.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Create the tentative ASO file and write its seven-byte header.

CP_ASO_BEGIN:
    XOR  A                  ; Clear stream, buffer and transaction state.
    LD   (CP_ASO_ACTIVE),A  ; Keep ASO dispatch disabled until MAKE succeeds.
    LD   (CP_ASO_OPEN),A    ; No spool FCB is open yet.
    LD   (CP_ASO_ERROR),A   ; Clear any sticky writer failure.
    LD   (CP_ASO_STATUS),A  ; Clear the returned BDOS status.
    LD   (CP_ASO_RECORD_COUNT),A  ; Start with an empty physical record.
    LD   (CP_ASO_RUN_COUNT),A  ; Start with no pending IMAGE bytes.
    LD   (CP_ASO_IMAGE_TOP),A  ; The initial image end is an ordinary word.
    LD   (CP_OUTPUT_OPEN),A  ; The old RAM-output temp is not open.
    LD   (CP_BACKED_UP),A   ; Publication has not moved the old output.
    LD   (CP_MAT_SPOOL_OWNED),A  ; No internal spool name is owned yet.
    LD   L,(IX+11)          ; Read the descriptor's target origin.
    LD   H,(IX+12)          ; Complete the origin address.
    LD   (CP_ASO_ORIGIN),HL  ; Retain the ASO header's image origin.
    LD   (CP_ASO_IMAGE_END),HL  ; No IMAGE bytes precede the origin.
    LD   A,(CP_OUTPUT_FORMAT)  ; Distinguish ASO from an internal spool.
    CP   3                  ; Explicit ASO is already the requested file.
    JR   Z,CP_ASO_BEGIN_NAME  ; Keep its ordinary transaction temporary name.
    CALL CP_SET_BACKUP_FCB  ; Use the reserved name for the private spool.
    LD   A,1                ; Mark that abort must remove this internal spool.
    LD   (CP_MAT_SPOOL_OWNED),A  ; BAK belongs to ASO until replay ends.
    JR   CP_ASO_BEGIN_COPY  ; Copy the selected name into the spool FCB.
CP_ASO_BEGIN_NAME:
    CALL CP_SET_TEMP_FCB    ; Build the explicit ASO transaction name.
CP_ASO_BEGIN_COPY:
    LD   DE,CP_WORK_FCB+12  ; Address the FCB's mutable tail fields.
    XOR  A                  ; Select zero for every unused FCB field.
    LD   B,24               ; Count the remaining FCB bytes.
    CALL CP_CLEAR_WORK_FCB  ; Give MAKE a clean temporary-file FCB.
    LD   HL,CP_WORK_FCB     ; Copy the complete temporary-file FCB.
    LD   DE,CP_ASO_FCB      ; Keep it outside the source and work FCBs.
    LD   BC,36              ; CP/M FCBs contain thirty-six bytes.
    LDIR                    ; Preserve the ASO FCB during source reads.
    LD   DE,CP_ASO_FCB      ; Pass the private ASO FCB to BDOS.
    LD   C,CP_MAKE_FUNCTION  ; Select CP/M make-file function 22.
    CALL CP_BDOS            ; Create the tentative sequential spool.
    INC  A                  ; Convert BDOS's $FF failure result to zero.
    JR   Z,CP_ASO_BEGIN_BAD  ; Let the normal abort path remove any residue.
    LD   A,1                ; Mark the FCB open and enable the ASO hooks.
    LD   (CP_ASO_OPEN),A    ; HS_ABORT owns cleanup from this point.
    LD   (CP_ASO_ACTIVE),A  ; Route output operations into the ASO writer.
    LD   A,'A'              ; Begin the ASCII ASO signature.
    CALL CP_ASO_PUT         ; Append the first header byte.
    RET  C                  ; Stop at the first failed physical write.
    LD   A,'S'              ; Continue the ASCII ASO signature.
    CALL CP_ASO_PUT         ; Append the second header byte.
    RET  C                  ; Keep the BDOS status for HS_ABORT.
    LD   A,'O'              ; Complete the ASCII ASO signature.
    CALL CP_ASO_PUT         ; Append the third header byte.
    RET  C                  ; Stop if the spool write failed.
    LD   A,1                ; Select ASO version one.
    CALL CP_ASO_PUT         ; Append the version byte.
    RET  C                  ; Do not continue after a write failure.
    LD   HL,(CP_ASO_ORIGIN)  ; Load the flat image's target origin.
    LD   A,L                ; Select the little-endian origin low byte.
    CALL CP_ASO_PUT         ; Append the low byte to the header.
    RET  C                  ; Let the driver abort a failed spool.
    LD   A,H                ; Select the little-endian origin high byte.
    CALL CP_ASO_PUT         ; Append the high byte to the header.
    RET  C                  ; Stop after any physical write failure.
    XOR  A                  ; CP/M output currently uses zero gap fill.
    CALL CP_ASO_PUT         ; Append the ASO header fill byte.
    RET                     ; Return the final write status to Atom.
CP_ASO_BEGIN_BAD:
    JP   CP_ASO_FAIL        ; Report the failed temporary-file creation.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Queue an IMAGE byte in ascending address order for canonical coalescing.

CP_ASO_IMAGE:
    PUSH BC                 ; Preserve address class and caller byte state.
    LD   (CP_ASO_VALUE),A   ; Retain the byte while validating its address.
    LD   (CP_ASO_ADDRESS),HL  ; Retain the absolute IMAGE address.
    LD   A,C                ; Read the address-space class.
    OR   A                  ; ASO v1 supports only the flat address space.
    JR   NZ,CP_ASO_IMAGE_BAD  ; Reject a banked IMAGE operation.
    LD   HL,(CP_ASO_ADDRESS)  ; Load the IMAGE address for origin checking.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the declared ASO image origin.
    OR   A                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE              ; Is this byte below the declared origin?
    JR   C,CP_ASO_IMAGE_BAD  ; Reject addresses before the flat image.
    LD   A,(CP_ASO_IMAGE_TOP)  ; Check whether the preceding end was $10000.
    OR   A                  ; A set flag leaves no later u16 IMAGE address.
    JR   NZ,CP_ASO_IMAGE_BAD  ; Reject any IMAGE after the endpoint.
    LD   HL,(CP_ASO_ADDRESS)  ; Reload the candidate address.
    LD   DE,(CP_ASO_IMAGE_END)  ; Read the prior IMAGE's exclusive end.
    OR   A                  ; Clear carry before comparing the endpoints.
    SBC  HL,DE              ; Require ascending, non-overlapping IMAGE bytes.
    JR   C,CP_ASO_IMAGE_BAD  ; Reject a descending or overlapping byte.
    JR   Z,CP_ASO_IMAGE_APPEND  ; A matching end extends the pending run.
    CALL CP_ASO_FLUSH_RUN   ; A gap starts a new canonical IMAGE record.
    JR   C,CP_ASO_IMAGE_WRITE_FAILED  ; Preserve the record-write failure.
CP_ASO_IMAGE_APPEND:
    LD   A,(CP_ASO_RUN_COUNT)  ; Check whether this run needs a new address.
    OR   A                  ; A zero count marks an empty pending run.
    JR   NZ,CP_ASO_IMAGE_STORE  ; A nonempty run already has its start.
    LD   HL,(CP_ASO_ADDRESS)  ; Begin at this non-overlapping byte.
    LD   (CP_ASO_RUN_ADDRESS),HL  ; Retain the pending run's absolute start.
CP_ASO_IMAGE_STORE:
    LD   A,(CP_ASO_RUN_COUNT)  ; Use the current count as the buffer index.
    LD   E,A                ; Zero-extend the index into DE.
    LD   D,0                ; Complete the zero-extended index.
    LD   HL,CP_ASO_RUN      ; Point at the pending IMAGE buffer.
    ADD  HL,DE              ; Select the next free run byte.
    LD   A,(CP_ASO_VALUE)   ; Recover the validated IMAGE value.
    LD   (HL),A             ; Append it to the pending run.
    LD   HL,(CP_ASO_ADDRESS)  ; Advance the exclusive IMAGE end.
    INC  HL                 ; Include the byte at the current address.
    LD   (CP_ASO_IMAGE_END),HL  ; Retain the low word of the new endpoint.
    LD   A,H                ; Check whether increment wrapped from $FFFF.
    OR   L                  ; Zero means the mathematical endpoint is $10000.
    JR   NZ,CP_ASO_IMAGE_END_WORD  ; Keep the ordinary 16-bit endpoint.
    LD   A,1                ; Mark the 17-bit image endpoint.
    LD   (CP_ASO_IMAGE_TOP),A  ; No further IMAGE address can be represented.
CP_ASO_IMAGE_END_WORD:
    LD   HL,CP_ASO_RUN_COUNT  ; Address the pending-run byte count.
    INC  (HL)               ; Include the byte just appended above.
    LD   A,(CP_ASO_RUN_COUNT)  ; Check the canonical 128-byte run limit.
    CP   128                ; A full run must be emitted immediately.
    JR   NZ,CP_ASO_IMAGE_DONE  ; Keep a shorter run pending.
    CALL CP_ASO_FLUSH_RUN  ; Emit the complete canonical run.
    JR   C,CP_ASO_IMAGE_WRITE_FAILED  ; Propagate a full-run write failure.
CP_ASO_IMAGE_DONE:
    POP  BC                 ; Restore the caller's BC pair.
    XOR  A                  ; Report success with carry clear.
    RET                     ; Return successful sink acceptance to Atom.
CP_ASO_IMAGE_WRITE_FAILED:
    POP  BC                 ; Restore BC before returning the stream error.
    SCF                     ; Preserve failure status across stack cleanup.
    RET                     ; Return the failed record-write status.
CP_ASO_IMAGE_BAD:
    POP  BC                 ; Restore BC before returning the stream error.
    JP   CP_ASO_FAIL        ; Poison the writer and report an invalid IMAGE.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a one-byte PATCH and pass it to the shared ASO record writer.

CP_ASO_PATCH_BYTE:
    LD   (CP_ASO_VALUE),A   ; Retain the replacement byte.
    LD   (CP_ASO_ADDRESS),HL  ; Retain the absolute patch address.
    LD   A,1                ; A byte PATCH has one payload byte.
    LD   (CP_ASO_LENGTH),A  ; Save its canonical record length.
    LD   A,C                ; Save the patch address class.
    LD   (CP_ASO_CLASS),A   ; The shared validator accepts only flat output.
    JP   CP_ASO_PATCH_COMMON  ; Validate and serialize the byte record.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save a little-endian word PATCH for the shared ASO record writer.

CP_ASO_PATCH_WORD:
    LD   (CP_ASO_VALUE),HL  ; Retain low and high replacement bytes.
    LD   (CP_ASO_ADDRESS),DE  ; Retain the absolute two-byte patch address.
    LD   A,2                ; A word PATCH has two payload bytes.
    LD   (CP_ASO_LENGTH),A  ; Save the record length for range checking.
    LD   A,C                ; Save the patch address class.
    LD   (CP_ASO_CLASS),A   ; The shared validator accepts only flat output.

; Validate the patch against the greatest preceding IMAGE endpoint.

CP_ASO_PATCH_COMMON:
    LD   A,(CP_ASO_CLASS)   ; Read the saved address-space class.
    OR   A                  ; ASO v1 is one flat 16-bit address space.
    JP   NZ,CP_ASO_PATCH_BAD  ; Reject a banked patch operation.
    LD   HL,(CP_ASO_ADDRESS)  ; Load the patch's first target address.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the ASO image origin.
    OR   A                  ; Clear carry before comparing addresses.
    SBC  HL,DE              ; Is the patch before the declared origin?
    JP   C,CP_ASO_PATCH_BAD  ; Reject patches outside the logical image.
    LD   A,0                ; Reset the computed endpoint's top flag.
    LD   (CP_ASO_PATCH_TOP),A  ; The next addition decides whether it wraps.
    LD   HL,(CP_ASO_ADDRESS)  ; Load the first byte's address.
    LD   A,(CP_ASO_LENGTH)  ; Read the one- or two-byte payload length.
    LD   E,A                ; Zero-extend the length for addition.
    LD   D,0                ; Complete the zero-extended length.
    ADD  HL,DE              ; Form the exclusive patch endpoint.
    LD   (CP_ASO_PATCH_END),HL  ; Retain its low word for comparison.
    JR   NC,CP_ASO_PATCH_CHECK_IMAGE  ; No wrap means an ordinary endpoint.
    LD   A,H                ; Check the low word after endpoint wrap.
    OR   L                  ; Only zero represents exactly $10000.
    JP   NZ,CP_ASO_PATCH_BAD  ; Reject an endpoint beyond the address space.
    LD   A,1                ; Mark a mathematical $10000 endpoint.
    LD   (CP_ASO_PATCH_TOP),A  ; Retain its seventeenth bit.
CP_ASO_PATCH_CHECK_IMAGE:
    LD   A,(CP_ASO_IMAGE_TOP)  ; Read the preceding IMAGE endpoint flag.
    OR   A                  ; A set flag means the image reaches $10000.
    JR   NZ,CP_ASO_PATCH_FLUSH  ; Every valid patch end is below or at it.
    LD   A,(CP_ASO_PATCH_TOP)  ; Check for a patch ending at $10000.
    OR   A                  ; An ordinary IMAGE end cannot contain that end.
    JP   NZ,CP_ASO_PATCH_BAD  ; Reject a patch beyond the preceding IMAGE.
    LD   HL,(CP_ASO_PATCH_END)  ; Load the patch's exclusive endpoint.
    LD   DE,(CP_ASO_IMAGE_END)  ; Load the greatest preceding IMAGE endpoint.
    OR   A                  ; Clear carry before comparing the endpoints.
    SBC  HL,DE              ; Require the patch to end at or before IMAGE.
    JR   C,CP_ASO_PATCH_FLUSH  ; A lower endpoint is contained.
    JR   Z,CP_ASO_PATCH_FLUSH  ; Equality ends exactly at image high water.
    JP   CP_ASO_PATCH_BAD   ; A greater endpoint reaches a future byte.
CP_ASO_PATCH_FLUSH:
    CALL CP_ASO_FLUSH_RUN   ; PATCH is a barrier between IMAGE runs.
    RET  C                  ; Keep the first failed physical write status.
    LD   A,2                ; ASO record kind two denotes PATCH.
    CALL CP_ASO_PUT         ; Append the record kind.
    RET  C                  ; Stop when a physical record write fails.
    LD   HL,(CP_ASO_ADDRESS)  ; Load the absolute patch address.
    LD   A,L                ; Append its little-endian low byte.
    CALL CP_ASO_PUT         ; Preserve the operation's chronological order.
    RET  C                  ; Propagate any spool-write failure.
    LD   A,H                ; Append the address high byte.
    CALL CP_ASO_PUT         ; Continue the four-byte record header.
    RET  C                  ; Leave cleanup to HS_ABORT.
    LD   A,(CP_ASO_LENGTH)  ; Append the one- or two-byte payload length.
    CALL CP_ASO_PUT         ; Complete the PATCH record header.
    RET  C                  ; Stop after any physical write error.
    LD   HL,(CP_ASO_VALUE)  ; Load the little-endian replacement bytes.
    LD   A,L                ; Select the patch's low byte.
    CALL CP_ASO_PUT         ; Append the first replacement byte.
    RET  C                  ; Propagate a failed spool write.
    LD   A,(CP_ASO_LENGTH)  ; Check whether this is a two-byte patch.
    CP   2                  ; A byte patch has no second payload byte.
    JR   NZ,CP_ASO_PATCH_OK  ; Finish the one-byte patch record.
    LD   A,H                ; Select the word patch's high byte.
    CALL CP_ASO_PUT         ; Append its second replacement byte.
    RET  C                  ; Keep the output failure status.
CP_ASO_PATCH_OK:
    XOR  A                  ; Return success after the complete record.
    RET                     ; The spool remains open for later operations.
CP_ASO_PATCH_BAD:
    JP   CP_ASO_FAIL        ; Poison the writer after invalid PATCH input.

;@ROUTINE IN A,BC,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate final geometry, append END and record padding, then publish ASO.

CP_ASO_COMMIT:
    LD   (CP_ASO_FLAGS),A   ; Retain the explicit endpoint flags.
    LD   (CP_ASO_HIGH_WATER),BC  ; Retain high water's low word.
    LD   (CP_ASO_FINAL_CURSOR),HL  ; Retain the final cursor's low word.
    LD   A,(CP_ASO_FLAGS)   ; Read the two defined COMMIT bits.
    AND  $FC                ; Reject undefined COMMIT flag bits.
    JP   NZ,CP_ASO_COMMIT_BAD  ; Reject a non-canonical flag byte.
    LD   A,(CP_ASO_FLAGS)   ; Check the high-water endpoint representation.
    BIT  1,A                ; Does bit one mark mathematical $10000?
    JR   Z,CP_ASO_COMMIT_HIGH_WORD  ; Otherwise high water is a 16-bit value.
    LD   HL,(CP_ASO_HIGH_WATER)  ; Endpoint words must be stored as zero.
    LD   A,H                ; Inspect its high byte.
    OR   L                  ; Test whether the saved endpoint is zero.
    JP   NZ,CP_ASO_COMMIT_BAD  ; Reject a nonzero endpoint low word.
    JR   CP_ASO_COMMIT_CURSOR  ; Check the final cursor against high water.
CP_ASO_COMMIT_HIGH_WORD:
    LD   HL,(CP_ASO_HIGH_WATER)  ; Load the ordinary high-water address.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the ASO image origin.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Require high water not below the origin.
    JP   C,CP_ASO_COMMIT_BAD  ; Reject an endpoint outside the image.
CP_ASO_COMMIT_CURSOR:
    LD   A,(CP_ASO_FLAGS)   ; Check the final cursor's endpoint form.
    BIT  0,A                ; Does bit zero mark mathematical $10000?
    JR   Z,CP_ASO_COMMIT_CURSOR_WORD  ; Otherwise cursor is an ordinary word.
    LD   HL,(CP_ASO_FINAL_CURSOR)  ; Endpoint words must be stored as zero.
    LD   A,H                ; Inspect the high byte.
    OR   L                  ; Test the complete saved cursor value.
    JP   NZ,CP_ASO_COMMIT_BAD  ; Reject a nonzero endpoint low word.
    LD   A,(CP_ASO_FLAGS)   ; A cursor endpoint requires a high endpoint.
    BIT  1,A                ; Check that high water is also $10000.
    JP   Z,CP_ASO_COMMIT_BAD  ; Reject cursor above ordinary high water.
    JR   CP_ASO_COMMIT_IMAGE  ; Compare high water with the IMAGE extent.
CP_ASO_COMMIT_CURSOR_WORD:
    LD   HL,(CP_ASO_FINAL_CURSOR)  ; Load the ordinary final cursor.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the declared target origin.
    OR   A                  ; Clear carry before the lower-bound check.
    SBC  HL,DE              ; Require final cursor not below the origin.
    JP   C,CP_ASO_COMMIT_BAD  ; Reject a cursor outside the target.
    LD   A,(CP_ASO_FLAGS)   ; An ordinary high-water word bounds the cursor.
    BIT  1,A                ; An endpoint high water needs no word comparison.
    JR   NZ,CP_ASO_COMMIT_IMAGE  ; Any ordinary cursor is below $10000.
    LD   HL,(CP_ASO_FINAL_CURSOR)  ; Reload the ordinary final cursor.
    LD   DE,(CP_ASO_HIGH_WATER)  ; Load the ordinary high-water mark.
    OR   A                  ; Clear carry before the upper-bound comparison.
    SBC  HL,DE              ; Compare cursor with high water.
    JR   C,CP_ASO_COMMIT_IMAGE  ; A backward ORG may leave a shorter cursor.
    JR   Z,CP_ASO_COMMIT_IMAGE  ; Equality is the ordinary completed case.
    JP   CP_ASO_COMMIT_BAD  ; Reject a cursor beyond high water.
CP_ASO_COMMIT_IMAGE:
    LD   A,(CP_ASO_IMAGE_TOP)  ; Check whether IMAGE reaches $10000.
    OR   A                  ; The endpoint requires endpoint high water.
    JR   Z,CP_ASO_COMMIT_IMAGE_WORD  ; Otherwise compare the ordinary words.
    LD   A,(CP_ASO_FLAGS)   ; Load the high-water endpoint bit.
    BIT  1,A                ; Is high water also the mathematical endpoint?
    JP   Z,CP_ASO_COMMIT_BAD  ; Reject high water below IMAGE extent.
    JR   CP_ASO_COMMIT_APPEND  ; The full address range includes every IMAGE.
CP_ASO_COMMIT_IMAGE_WORD:
    LD   A,(CP_ASO_FLAGS)   ; An endpoint high water exceeds every word end.
    BIT  1,A                ; Does bit one represent $10000?
    JR   NZ,CP_ASO_COMMIT_APPEND  ; Accept any ordinary IMAGE endpoint.
    LD   HL,(CP_ASO_HIGH_WATER)  ; Load the final exclusive high-water word.
    LD   DE,(CP_ASO_IMAGE_END)  ; Load the greatest preceding IMAGE endpoint.
    OR   A                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE              ; Require IMAGE to fit within committed geometry.
    JP   C,CP_ASO_COMMIT_BAD  ; Reject high water below emitted IMAGE bytes.
CP_ASO_COMMIT_APPEND:
    CALL CP_ASO_FLUSH_RUN   ; Finish any canonical pending IMAGE record.
    RET  C                  ; Do not write END after an earlier I/O failure.
    XOR  A                  ; ASO record kind zero denotes successful END.
    CALL CP_ASO_PUT         ; Append the END record kind.
    RET  C                  ; Keep a failed write from looking like success.
    LD   HL,(CP_ASO_HIGH_WATER)  ; Load the exclusive high-water low word.
    LD   A,L                ; Append its low byte.
    CALL CP_ASO_PUT         ; Continue the six-byte END record.
    RET  C                  ; Leave the tentative file for abort cleanup.
    LD   A,H                ; Append the high-water word's high byte.
    CALL CP_ASO_PUT         ; Continue the END record.
    RET  C                  ; Do not close an incomplete ASO file.
    LD   A,(CP_ASO_FLAGS)   ; Select the high-water top byte.
    AND  2                  ; Retain only bit one.
    RRCA                    ; Move the endpoint bit into bit zero.
    CALL CP_ASO_PUT         ; Append high water's seventeenth bit.
    RET  C                  ; Stop if the END record could not be written.
    LD   HL,(CP_ASO_FINAL_CURSOR)  ; Load the final cursor's low word.
    LD   A,L                ; Append its low byte.
    CALL CP_ASO_PUT         ; Continue the six-byte END record.
    RET  C                  ; Keep the spool tentative until it is complete.
    LD   A,H                ; Append the final cursor's high byte.
    CALL CP_ASO_PUT         ; Continue the END record.
    RET  C                  ; Stop on an incomplete END record.
    LD   A,(CP_ASO_FLAGS)   ; Select the final cursor's top byte.
    AND  1                  ; Retain only bit zero.
    CALL CP_ASO_PUT         ; Append the cursor endpoint bit.
    RET  C                  ; Do not publish an unpadded stream.
    CALL CP_ASO_PAD_RECORD  ; Pad the final physical record if needed.
    RET  C                  ; Keep the prior output on a failed spool write.
    LD   DE,CP_ASO_FCB      ; Pass the sealed ASO FCB to BDOS.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Flush and close the completed ASO stream.
    INC  A                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,CP_ASO_COMMIT_CLOSE_BAD  ; Let abort retry after close fails.
    XOR  A                  ; Clear the open flag after a successful close.
    LD   (CP_ASO_OPEN),A    ; The spool can now be renamed transactionally.
    LD   A,(CP_OUTPUT_FORMAT)  ; Is the spool the requested file?
    CP   3                  ; Explicit ASO needs no final-image conversion.
    JR   NZ,CP_ASO_COMMIT_MATERIALIZE  ; COM, BIN and HEX replay to a temp.
    CALL CP_PUBLISH_TEMP    ; Replace the requested destination on success.
    RET  C                  ; Let HS_ABORT restore any moved backup.
    XOR  A                  ; Disable the ASO hook path for the next command.
    LD   (CP_ASO_ACTIVE),A  ; The completed file is now owned by its caller.
    RET                     ; Return successful COMMIT to the native driver.
CP_ASO_COMMIT_MATERIALIZE:
    CALL CP_MAT_ASO_OUTPUT  ; Replay ASO into the selected flat output format.
    RET  C                  ; Leave HS_ABORT to clean all tentative files.
    XOR  A                  ; Disable operation dispatch after publication.
    LD   (CP_ASO_ACTIVE),A  ; The completed output now belongs to the caller.
    RET                     ; Report the assembled COM or BIN as committed.
CP_ASO_COMMIT_CLOSE_BAD:
    LD   A,1                ; Report a closed-file service failure.
    LD   (CP_ASO_STATUS),A  ; Retain the failure for the common error return.
    SCF                     ; Keep the FCB open flag for HS_ABORT cleanup.
    RET                     ; Return failure without publishing the spool.
CP_ASO_COMMIT_BAD:
    JP   CP_ASO_FAIL        ; Reject invalid geometry and prevent END.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write the current full 128-byte ASO record through sequential BDOS output.

CP_ASO_WRITE_RECORD:
    LD   DE,CP_ASO_RECORD   ; Point BDOS at the completed physical record.
    LD   C,CP_DMA_FUNCTION  ; Select CP/M's set-DMA-address service.
    CALL CP_BDOS            ; Install the writer-owned transfer buffer.
    LD   DE,CP_ASO_FCB      ; Pass the active temporary ASO file.
    LD   C,CP_WRITE_FUNCTION  ; Select sequential record-write function 21.
    CALL CP_BDOS            ; Append exactly one physical 128-byte record.
    OR   A                  ; Zero indicates a successful record write.
    JR   NZ,CP_ASO_WRITE_BAD  ; Retain disk-full and write-failure status.
    XOR  A                  ; Reset the record length after successful output.
    LD   (CP_ASO_RECORD_COUNT),A  ; The next ASO byte starts a fresh record.
    RET                     ; Return with carry clear.
CP_ASO_WRITE_BAD:
    LD   (CP_ASO_STATUS),A  ; Preserve the BDOS write result.
    LD   (CP_ASO_ERROR),A   ; Poison all later writer operations.
    SCF                     ; Require the transaction abort path.
    RET                     ; Return the BDOS status in A.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Append one byte to the 128-byte physical record buffer.

CP_ASO_PUT:
    PUSH BC                 ; Keep the caller's byte counter and class.
    PUSH DE                 ; Preserve any address held in DE.
    PUSH HL                 ; Preserve any address held in HL.
    LD   (CP_ASO_PUT_BYTE),A  ; Retain the serialized byte during indexing.
    LD   A,(CP_ASO_ERROR)   ; Check for an earlier writer failure.
    OR   A                  ; A set error forbids further stream output.
    JR   NZ,CP_ASO_PUT_ERROR  ; Return the original failure without mutation.
    LD   A,(CP_ASO_RECORD_COUNT)  ; Read the current physical-record length.
    CP   128                ; A count of 128 is valid only during flushing.
    JR   NC,CP_ASO_PUT_INVALID  ; Reject corrupted buffer state.
    LD   E,A                ; Zero-extend the current write index.
    LD   D,0                ; Complete the 16-bit record offset.
    LD   HL,CP_ASO_RECORD   ; Address the sequential record buffer.
    ADD  HL,DE              ; Select its next free byte.
    LD   A,(CP_ASO_PUT_BYTE)  ; Recover the byte supplied by the serializer.
    LD   (HL),A             ; Append it without touching the source cache.
    LD   A,(CP_ASO_RECORD_COUNT)  ; Read the updated buffer length.
    INC  A                  ; Include the byte stored above.
    LD   (CP_ASO_RECORD_COUNT),A  ; Retain its new physical-record count.
    CP   128                ; Is the CP/M record now complete?
    JR   NZ,CP_ASO_PUT_OK   ; Keep partial records in the bounded buffer.
    CALL CP_ASO_WRITE_RECORD  ; Flush a complete sequential BDOS record.
    JR   C,CP_ASO_PUT_ERROR  ; Preserve the sticky write failure.
CP_ASO_PUT_OK:
    POP  HL                 ; Restore the caller's HL value.
    POP  DE                 ; Restore the caller's DE value.
    POP  BC                 ; Restore the caller's BC value.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Complete the single-byte append.
CP_ASO_PUT_INVALID:
    LD   A,1                ; Mark an impossible record-buffer state.
    LD   (CP_ASO_ERROR),A   ; Prevent a later END from sealing corruption.
    LD   (CP_ASO_STATUS),A  ; Retain the writer's internal failure code.
CP_ASO_PUT_ERROR:
    LD   A,(CP_ASO_ERROR)   ; Recover the original error before stack restore.
    LD   (CP_ASO_STATUS),A  ; Preserve it across the register pops.
    POP  HL                 ; Restore caller registers without changing flags.
    POP  DE                 ; Keep the error status in dedicated workspace.
    POP  BC                 ; Restore the class and byte-counter pair.
    LD   A,(CP_ASO_STATUS)  ; Return the retained error code.
    SCF                     ; Carry forces the caller to abort publication.
    RET                     ; Return the sticky writer failure.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize a pending run as one canonical IMAGE record.

CP_ASO_FLUSH_RUN:
    LD   A,(CP_ASO_RUN_COUNT)  ; Read the number of buffered IMAGE bytes.
    OR   A                  ; An empty run has nothing to serialize.
    JR   NZ,CP_ASO_FLUSH_RUN_NONEMPTY  ; Continue when IMAGE bytes are queued.
    XOR  A                  ; No-op success must clear stale carry.
    RET                     ; Return without changing the empty run.
CP_ASO_FLUSH_RUN_NONEMPTY:
    LD   B,A                ; Preserve the run length across byte appends.
    LD   A,1                ; ASO record kind one denotes IMAGE.
    CALL CP_ASO_PUT         ; Append the record type.
    RET  C                  ; Stop before writing an incomplete header.
    LD   HL,(CP_ASO_RUN_ADDRESS)  ; Load the run's first absolute address.
    LD   A,L                ; Append the little-endian address low byte.
    CALL CP_ASO_PUT         ; Continue the canonical record header.
    RET  C                  ; Propagate a physical write failure.
    LD   A,H                ; Append the address high byte.
    CALL CP_ASO_PUT         ; Continue the record header.
    RET  C                  ; Do not write payload after a failed header.
    LD   A,B                ; Append the run length from one through 128.
    CALL CP_ASO_PUT         ; Finish the IMAGE record header.
    RET  C                  ; Stop when the record cannot be completed.
    LD   HL,CP_ASO_RUN      ; Point at the first buffered IMAGE byte.
CP_ASO_FLUSH_RUN_BYTE:
    LD   A,(HL)             ; Load the next pending IMAGE value.
    CALL CP_ASO_PUT         ; Append it in source-operation order.
    RET  C                  ; Preserve the first failed physical write.
    INC  HL                 ; Advance to the following pending byte.
    DJNZ CP_ASO_FLUSH_RUN_BYTE  ; Continue through the retained run length.
    XOR  A                  ; Clear the run only after all bytes were written.
    LD   (CP_ASO_RUN_COUNT),A  ; The next IMAGE begins another record.
    RET                     ; Return success with the spool still open.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pad a partial last record with exactly the CP/M-required $1A bytes.

CP_ASO_PAD_RECORD:
    LD   A,(CP_ASO_RECORD_COUNT)  ; Read the bytes already queued for output.
    OR   A                  ; Zero means END ended on a record boundary.
    JR   NZ,CP_ASO_PAD_RECORD_PARTIAL  ; Pad only a partial final record.
    XOR  A                  ; A complete record boundary is successful.
    RET                     ; Do not append an unnecessary extra record.
CP_ASO_PAD_RECORD_PARTIAL:
    LD   B,A                ; Retain the partial-record byte count.
    LD   A,128              ; Select the CP/M physical-record length.
    SUB  B                  ; Calculate the exact number of pad bytes.
    LD   B,A                ; Retain the bounded fill count in B.
CP_ASO_PAD_BYTE:
    LD   A,$1A              ; Restore the fill byte after each helper call.
    CALL CP_ASO_PUT         ; Append one byte, flushing exactly at 128.
    RET  C                  ; Do not close an incomplete padded stream.
    DJNZ CP_ASO_PAD_BYTE    ; Finish the single final physical record.
    XOR  A                  ; Return success after the record was flushed.
    RET                     ; No logical ASO bytes follow END.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return a sticky write or validation failure to the native output driver.

CP_ASO_FAIL:
    LD   A,1                ; Use the established host-output failure status.
    LD   (CP_ASO_ERROR),A   ; Prevent END from following a failed operation.
    LD   (CP_ASO_STATUS),A  ; Keep the failure through any register restore.
    SCF                     ; Tell the driver to abort this output.
    RET                     ; Return the output-service failure.
