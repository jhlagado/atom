; Replay one CP/M ASO spool into bounded sequential output windows.
;
; The source has already been assembled once. Each pass reopens the private
; ASO file, validates its ordered records and applies only the operations
; intersecting the current output window. Output records are always written
; sequentially; no floppy seek is needed to apply a PATCH.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Convert the internal ASO spool into COM, BIN or HEX, then publish the temp.

CP_MAT_ASO_OUTPUT:
    LD   A,(CP_ASO_FLAGS)   ; Read the committed high-water endpoint form.
    BIT  1,A                ; Is high water the mathematical endpoint $10000?
    JR   Z,CP_MAT_HIGH_WORD  ; Otherwise use its ordinary 16-bit address.
    LD   HL,CP_ASO_TARGET_CAPACITY  ; $10000 minus the $0100 COM origin.
    JR   CP_MAT_LENGTH_READY  ; The maximum logical image is exactly $FF00.
CP_MAT_HIGH_WORD:
    LD   HL,(CP_ASO_HIGH_WATER)  ; Load the ordinary exclusive high-water.
    LD   DE,(CP_ASO_ORIGIN)  ; Subtract the ASO image origin.
    OR   A                  ; Clear borrow before the subtraction.
    SBC  HL,DE              ; Convert the absolute endpoint to a file length.
CP_MAT_LENGTH_READY:
    LD   A,(CP_OUTPUT_FORMAT)  ; Check whether this output is textual HEX.
    CP   2                  ; HEX stores exact bytes rather than CP/M records.
    JR   Z,CP_MAT_LENGTH_EXACT  ; Keep the exact unpadded length.
    LD   DE,127             ; Round the last logical record up to 128 bytes.
    ADD  HL,DE              ; The extra bytes use the ASO fill value.
    LD   A,L                ; Keep only bit seven of the rounded low byte.
    AND  $80                ; Clear the seven bits below a record boundary.
    LD   L,A                ; Retain the rounded low byte.
CP_MAT_LENGTH_EXACT:
    LD   (CP_MAT_OUTPUT_LEFT),HL  ; Count HEX or padded binary bytes.
    XOR  A                  ; Begin writing the first output window.
    LD   (CP_MAT_FILL),A    ; The native BEGIN hook declares zero fill.
    LD   (CP_MAT_WINDOW_START),A  ; Its image-relative offset is zero.
    LD   (CP_MAT_WINDOW_START+1),A  ; Clear the offset's high byte as well.
    CALL CP_SET_TEMP_FCB    ; Name the tentative output file.
    LD   DE,CP_WORK_FCB+12  ; Reset all mutable FCB state before MAKE.
    XOR  A                  ; CP/M expects cleared record and extent fields.
    LD   B,24               ; Count the remaining FCB bytes.
    CALL CP_CLEAR_WORK_FCB  ; Keep the selected filename and clear its tail.
    LD   DE,CP_WORK_FCB     ; Pass the tentative output FCB to BDOS.
    LD   C,CP_MAKE_FUNCTION  ; Select CP/M make-file function 22.
    CALL CP_BDOS            ; Create the output only after ASO COMMIT.
    INC  A                  ; Convert BDOS's $FF failure result to zero.
    JP   Z,CP_MAT_FAILURE   ; Keep the old destination untouched.
    LD   A,1                ; The abort path now owns the open temp file.
    LD   (CP_OUTPUT_OPEN),A  ; Retain its cleanup state.
    LD   A,(CP_OUTPUT_FORMAT)  ; Select the representation's output encoder.
    CP   2                  ; Format two is Intel HEX.
    JR   NZ,CP_MAT_WINDOW_LOOP  ; Binary outputs need no HEX buffer setup.
    CALL ZTS_CPM_HEX_BEGIN  ; Start one HEX stream before its replay windows.
CP_MAT_WINDOW_LOOP:
    LD   HL,(CP_MAT_OUTPUT_LEFT)  ; Read the rounded output bytes remaining.
    LD   A,H                ; Check the high byte.
    OR   L                  ; Zero means the empty or final window is done.
    JR   NZ,CP_MAT_WINDOW_NONEMPTY  ; Continue when a window remains to write.
    LD   HL,(CP_MAT_WINDOW_START)  ; Did any nonempty output window complete?
    LD   A,H                ; Check its high byte.
    OR   L                  ; Zero distinguishes a genuinely empty image.
    JR   NZ,CP_MAT_OUTPUT_DATA_DONE  ; Nonempty output passed validation.
    CALL CP_MAT_REPLAY      ; Validate an empty stream through physical EOF.
    RET  C                  ; Do not publish a malformed empty stream.
CP_MAT_OUTPUT_DATA_DONE:
    LD   A,(CP_OUTPUT_FORMAT)  ; Select the format's finalization path.
    CP   2                  ; Intel HEX needs EOF and final record padding.
    JP   NZ,CP_MAT_OUTPUT_CLOSE  ; Binary output is already complete.
    CALL ZTS_CPM_HEX_END    ; Finish the HEX stream through sequential BDOS.
    RET  C                  ; Preserve the old output after a write failure.
    JP   CP_MAT_OUTPUT_CLOSE  ; Close only after HEX is complete.
CP_MAT_WINDOW_NONEMPTY:
    LD   HL,CP_OUTPUT_END   ; Load the inclusive address-space ceiling.
    LD   DE,CP_MAT_WINDOW   ; Subtract the aligned start after overlay code.
    OR   A                  ; Clear borrow before measuring available memory.
    SBC  HL,DE              ; Form this build's measured window capacity.
    EX   DE,HL              ; Keep the capacity in DE for comparison.
    LD   HL,(CP_MAT_OUTPUT_LEFT)  ; Reload the rounded output size.
    OR   A                  ; Clear carry before comparing window and output.
    SBC  HL,DE              ; Is another full window left?
    JR   NC,CP_MAT_FULL_WINDOW  ; Use the complete buffer when it fits.
    LD   HL,(CP_MAT_OUTPUT_LEFT)  ; The final window uses the remainder.
    JR   CP_MAT_WINDOW_SIZE_READY  ; Its length remains record-aligned.
CP_MAT_FULL_WINDOW:
    LD   HL,CP_OUTPUT_END   ; Load the ceiling used by the window calculation.
    LD   DE,CP_MAT_WINDOW   ; Load the aligned start after materializer code.
    OR   A                  ; Clear borrow before taking the difference.
    SBC  HL,DE              ; Recover the record-aligned window size.
CP_MAT_WINDOW_SIZE_READY:
    LD   (CP_MAT_WINDOW_LENGTH),HL  ; Save this pass's physical byte count.
    LD   (CP_MAT_WINDOW_LEFT),HL  ; Initialize the fill loop length.
    CALL CP_MAT_FILL_WINDOW  ; Restore untouched gaps and reservations.
    CALL CP_MAT_REPLAY      ; Reopen and validate the complete ASO stream.
    RET  C                  ; HS_ABORT removes tentative data.
    LD   A,(CP_OUTPUT_FORMAT)  ; Choose raw records or Intel HEX conversion.
    CP   2                  ; Only HEX consumes the replay window as text.
    JR   NZ,CP_MAT_WRITE_BINARY  ; COM and BIN append this window unchanged.
    LD   HL,CP_MAT_WINDOW   ; Set the HEX input cursor.
    LD   (ZTS_CPM_FINAL_SOURCE_CURSOR),HL  ; Reset its window source cursor.
    LD   HL,(CP_MAT_WINDOW_LENGTH)  ; Read the exact logical segment length.
    LD   (ZTS_CPM_FINAL_REMAINING),HL  ; Do not render binary record padding.
    LD   HL,(CP_ASO_ORIGIN)  ; Start with the image's absolute base address.
    LD   DE,(CP_MAT_WINDOW_START)  ; Add this replay window's relative offset.
    ADD  HL,DE              ; Form this window's first target address.
    LD   (ZTS_CPM_FINAL_ADDRESS),HL  ; Reset the helper for this segment.
    CALL ZTS_CPM_HEX_SEGMENT  ; Emit checksummed HEX records.
    JR   CP_MAT_WINDOW_WRITTEN  ; Advance to the next output window.
CP_MAT_WRITE_BINARY:
    CALL CP_MAT_WRITE_WINDOW  ; Append this window as sequential CP/M records.
    RET  C                  ; Preserve the old destination on write failure.
CP_MAT_WINDOW_WRITTEN:
    LD   HL,(CP_MAT_OUTPUT_LEFT)  ; Reload total output bytes still unwritten.
    LD   DE,(CP_MAT_WINDOW_LENGTH)  ; Read the completed window's length.
    OR   A                  ; Clear borrow before reducing the remaining size.
    SBC  HL,DE              ; Account for this full set of output records.
    LD   (CP_MAT_OUTPUT_LEFT),HL  ; Retain the count for the next window.
    LD   HL,(CP_MAT_WINDOW_START)  ; Read the next relative window start.
    ADD  HL,DE              ; Advance by the length just materialized.
    LD   (CP_MAT_WINDOW_START),HL  ; Keep the next pass aligned with records.
    JP   CP_MAT_WINDOW_LOOP  ; Continue or close after the final window.

; Fill the selected window before applying any IMAGE and PATCH operations.

CP_MAT_FILL_WINDOW:
    LD   A,(CP_MAT_FILL)    ; Use the header's validated gap-fill byte.
    LD   HL,CP_MAT_WINDOW   ; Select the first byte of the destination window.
    LD   (HL),A             ; Seed LDIR with the selected fill value.
    LD   DE,CP_MAT_WINDOW+1  ; Point one byte beyond the seed value.
    LD   BC,(CP_MAT_WINDOW_LENGTH)  ; Load the complete window length.
    DEC  BC                 ; The seed byte is already initialized.
    LD   A,B                ; Does any byte remain after the seed?
    OR   C                  ; A one-byte window needs no LDIR operation.
    RET  Z                  ; Avoid treating BC=0 as 65,536 copies.
    LD   HL,CP_MAT_WINDOW   ; Point LDIR at that first initialized byte.
    LDIR                    ; Fill only the bytes that will be written.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Continue with a fresh spool replay.

; Open, parse and close one complete operation stream for this window.

CP_MAT_REPLAY:
    XOR  A                  ; Reset the byte reader and record-order state.
    LD   (CP_MAT_READ_LEFT),A  ; The first byte must refill the input record.
    LD   (CP_MAT_PREVIOUS_KIND),A  ; No previous IMAGE can constrain ordering.
    LD   (CP_MAT_PREVIOUS_LENGTH),A  ; Clear the prior run's canonical length.
    LD   (CP_MAT_IMAGE_TOP),A  ; Start with an ordinary endpoint.
    LD   HL,(CP_ASO_ORIGIN)  ; The empty initial extent starts at origin.
    LD   (CP_MAT_IMAGE_END),HL  ; Use this endpoint to validate PATCH records.
    LD   DE,CP_MAT_FCB+12   ; Reset the sequential reader's mutable FCB tail.
    XOR  A                  ; Start at extent and record zero.
    LD   B,24               ; Clear all FCB control and random-record fields.
    CALL CP_CLEAR_WORK_FCB  ; Preserve the spool filename while rewinding it.
    LD   DE,CP_MAT_FCB      ; Pass the relocated spool FCB to CP/M OPEN.
    LD   C,CP_OPEN_FUNCTION  ; Select sequential file-open function 15.
    CALL CP_BDOS            ; Reopen the committed spool from record zero.
    INC  A                  ; Convert BDOS's $FF not-found result to zero.
    JR   Z,CP_MAT_REPLAY_BAD  ; A missing spool invalidates this output.
    LD   A,1                ; HS_ABORT owns the currently open spool FCB.
    LD   (CP_MAT_READER_OPEN),A  ; Track the open spool for abort cleanup.
    CALL CP_MAT_HEADER      ; Check signature, version, origin and fill.
    RET  C                  ; Leave the reader open for the common abort path.
    CALL CP_MAT_RECORDS     ; Apply records and require a valid END and EOF.
    RET  C                  ; Do not write a window from an invalid stream.
    LD   DE,CP_MAT_FCB      ; Close the validated spool pass.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Release the reader before another window pass.
    INC  A                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,CP_MAT_REPLAY_BAD  ; A failed close must abort publication.
    XOR  A                  ; Clear the open flag after a successful close.
    LD   (CP_MAT_READER_OPEN),A  ; Clear the flag after closing the spool.
    RET                     ; Return a verified window with carry clear.
CP_MAT_REPLAY_BAD:
    JP   CP_MAT_FAILURE     ; Let HS_ABORT remove both temporary files.

; Check the fixed ASO v1 header against the state retained by its writer.

CP_MAT_HEADER:
    CALL CP_MAT_NEXT_BYTE   ; Read the first signature byte.
    RET  C                  ; A short file cannot start a valid header.
    CP   'A'                ; Require the exact ASCII signature.
    JP   NZ,CP_MAT_INVALID  ; Reject any different magic byte.
    CALL CP_MAT_NEXT_BYTE   ; Read the second signature byte.
    RET  C                  ; Reject EOF before the header completes.
    CP   'S'                ; Continue the three-byte signature check.
    JP   NZ,CP_MAT_INVALID  ; Reject a changed signature.
    CALL CP_MAT_NEXT_BYTE   ; Read the final signature byte.
    RET  C                  ; A truncated signature is invalid.
    CP   'O'                ; Complete the required ASCII magic.
    JP   NZ,CP_MAT_INVALID  ; Reject a different format.
    CALL CP_MAT_NEXT_BYTE   ; Read the ASO version.
    RET  C                  ; Require a complete header.
    CP   1                  ; This adapter implements ASO version one only.
    JP   NZ,CP_MAT_INVALID  ; Refuse unknown versions.
    CALL CP_MAT_READ_WORD   ; Read the little-endian target origin.
    RET  C                  ; Propagate a truncated origin field.
    LD   DE,(CP_ASO_ORIGIN)  ; Compare with the origin supplied at BEGIN.
    OR   A                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE              ; Did the stream retain its declared origin?
    JP   NZ,CP_MAT_INVALID  ; A changed origin must not redirect output.
    CALL CP_MAT_NEXT_BYTE   ; Read the stream's fill byte.
    RET  C                  ; Reject an incomplete fixed header.
    LD   (CP_MAT_FILL),A    ; Retain the value used to initialize this window.
    OR   A                  ; The CP/M assembler currently declares zero fill.
    JP   NZ,CP_MAT_INVALID  ; Do not materialize altered fill semantics.
    XOR  A                  ; Return success with carry clear.
    RET                     ; The stream now has a validated v1 header.

; Parse chronological IMAGE/PATCH records through one mandatory END.

CP_MAT_RECORDS:
    CALL CP_MAT_NEXT_BYTE   ; Read a record kind or the END marker.
    JP   C,CP_MAT_INVALID   ; Physical EOF before END is invalid.
    OR   A                  ; Record kind zero is the only valid terminator.
    JP   Z,CP_MAT_END       ; Validate final geometry and record padding.
    CP   1                  ; Record kind one denotes IMAGE.
    JR   Z,CP_MAT_IMAGE     ; Parse its address, length and bytes.
    CP   2                  ; Record kind two denotes PATCH.
    JP   Z,CP_MAT_PATCH    ; Parse its replacement bytes.
    JP   CP_MAT_INVALID     ; Reject every unknown v1 record kind.

; Validate an IMAGE range and apply its bytes if they intersect this window.

CP_MAT_IMAGE:
    LD   A,(CP_MAT_IMAGE_TOP)  ; No IMAGE may follow an endpoint at $10000.
    OR   A                  ; Check the seventeenth endpoint bit.
    JP   NZ,CP_MAT_INVALID  ; Reject a range beyond the address space.
    CALL CP_MAT_READ_WORD   ; Read the absolute starting address.
    JP   C,CP_MAT_INVALID  ; Reject a truncated IMAGE address.
    LD   (CP_MAT_RECORD_ADDRESS),HL  ; Retain the encoded start for checks.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the minimum address of this output.
    OR   A                  ; Clear carry before subtracting the origin.
    SBC  HL,DE              ; Convert the target address to an image offset.
    JP   C,CP_MAT_INVALID   ; Reject IMAGE bytes before the stream origin.
    LD   (CP_MAT_RECORD_OFFSET),HL  ; Save the relative operation position.
    CALL CP_MAT_NEXT_BYTE   ; Read the one-byte IMAGE payload length.
    JP   C,CP_MAT_INVALID   ; Reject a truncated record header.
    OR   A                  ; Zero is not a valid IMAGE record length.
    JP   Z,CP_MAT_INVALID   ; Require one through 128 data bytes.
    CP   129                ; The canonical maximum is one physical record.
    JP   NC,CP_MAT_INVALID  ; Reject an excessive payload.
    LD   (CP_MAT_RECORD_LENGTH),A  ; Retain its validated length.
    LD   (CP_MAT_RECORD_LEFT),A  ; Count payload bytes as they are consumed.
    CALL CP_MAT_CHECK_IMAGE_ORDER  ; Enforce nonoverlap and canonical runs.
    RET  C                  ; Stop before applying any invalid range.
    CALL CP_MAT_RECORD_BYTES  ; Consume the payload and update this window.
    RET  C                  ; A short payload invalidates the whole spool.
    LD   A,1                ; Retain IMAGE as the preceding record kind.
    LD   (CP_MAT_PREVIOUS_KIND),A  ; The next adjacent short IMAGE is invalid.
    LD   A,(CP_MAT_RECORD_LENGTH)  ; Remember the run length for that check.
    LD   (CP_MAT_PREVIOUS_LENGTH),A  ; A full 128-byte run may be followed.
    JR   CP_MAT_RECORDS     ; Continue parsing until END.

; Validate that IMAGE ranges ascend, do not overlap and use canonical runs.

CP_MAT_CHECK_IMAGE_ORDER:
    LD   HL,(CP_MAT_RECORD_ADDRESS)  ; Load the candidate absolute address.
    LD   DE,(CP_MAT_IMAGE_END)  ; Load the greatest preceding IMAGE endpoint.
    OR   A                  ; Clear carry before comparing unsigned addresses.
    SBC  HL,DE              ; Descending or overlapping data borrows here.
    JP   C,CP_MAT_INVALID   ; Reject any IMAGE before the previous endpoint.
    JR   NZ,CP_MAT_IMAGE_RANGE  ; A gap starts a new canonical IMAGE run.
    LD   A,(CP_MAT_PREVIOUS_KIND)  ; Check whether an IMAGE preceded this one.
    CP   1                  ; PATCH separates IMAGE runs and resets this rule.
    JR   NZ,CP_MAT_IMAGE_RANGE  ; Adjacent bytes after PATCH remain valid.
    LD   A,(CP_MAT_PREVIOUS_LENGTH)  ; Read the preceding IMAGE's run length.
    CP   128                ; Only a maximal run may be extended adjacently.
    JP   C,CP_MAT_INVALID   ; Reject split contiguous IMAGE records.
CP_MAT_IMAGE_RANGE:
    LD   HL,(CP_MAT_RECORD_OFFSET)  ; Load the start relative to origin.
    LD   A,(CP_MAT_RECORD_LENGTH)  ; Add the validated payload size.
    LD   E,A                ; Extend the byte length into DE.
    LD   D,0                ; Complete the 16-bit length.
    ADD  HL,DE              ; Form the new relative image endpoint.
    LD   (CP_MAT_RECORD_END),HL  ; Retain it for PATCH and END validation.
    LD   HL,(CP_MAT_RECORD_ADDRESS)  ; Recompute the absolute exclusive end.
    ADD  HL,DE              ; Include this IMAGE's byte length.
    JR   NC,CP_MAT_IMAGE_WORD_END  ; No wrap gives an ordinary endpoint.
    LD   A,H                ; A wrapped range must end exactly at zero.
    OR   L                  ; Reject lengths that cross beyond $10000.
    JP   NZ,CP_MAT_INVALID  ; Do not permit a wrapped endpoint past memory.
    LD   A,1                ; Retain the mathematical $10000 endpoint.
    LD   (CP_MAT_IMAGE_TOP),A  ; No later IMAGE address can be represented.
    LD   HL,0               ; Store zero as the endpoint's low word.
    JR   CP_MAT_IMAGE_END_SAVE  ; Commit the checked endpoint.
CP_MAT_IMAGE_WORD_END:
    XOR  A                  ; Mark an ordinary 16-bit exclusive endpoint.
    LD   (CP_MAT_IMAGE_TOP),A  ; Clear any endpoint flag.
CP_MAT_IMAGE_END_SAVE:
    LD   (CP_MAT_IMAGE_END),HL  ; Update the greatest IMAGE endpoint.
    XOR  A                  ; Return with carry clear.
    RET                     ; Allow the validated payload to be consumed.

; Validate a byte/word PATCH and apply its final replacement values.

CP_MAT_PATCH:
    CALL CP_MAT_READ_WORD   ; Read the absolute target address.
    JP   C,CP_MAT_INVALID   ; A missing address cannot be a valid PATCH.
    LD   (CP_MAT_RECORD_ADDRESS),HL  ; Retain the target for range checks.
    LD   DE,(CP_ASO_ORIGIN)  ; Load the declared output origin.
    OR   A                  ; Clear carry before subtracting origin.
    SBC  HL,DE              ; Convert the target to an image-relative offset.
    JP   C,CP_MAT_INVALID   ; Reject a patch before the logical image.
    LD   (CP_MAT_RECORD_OFFSET),HL  ; Save the first replacement position.
    CALL CP_MAT_NEXT_BYTE   ; Read a byte or word patch length.
    JP   C,CP_MAT_INVALID   ; Reject a truncated PATCH header.
    CP   1                  ; The one-byte case is canonical.
    JR   Z,CP_MAT_PATCH_SIZE  ; Keep its length unchanged.
    CP   2                  ; The only other accepted length is two.
    JP   NZ,CP_MAT_INVALID  ; Reject empty or longer replacement records.
CP_MAT_PATCH_SIZE:
    LD   (CP_MAT_RECORD_LENGTH),A  ; Retain the validated payload length.
    LD   (CP_MAT_RECORD_LEFT),A  ; Count replacement bytes during reading.
    LD   HL,(CP_MAT_RECORD_ADDRESS)  ; Form the exclusive absolute endpoint.
    LD   E,A                ; Extend the patch size into DE.
    LD   D,0                ; Complete the 16-bit addition operand.
    ADD  HL,DE              ; Detect a patch that wraps past $10000.
    JR   NC,CP_MAT_PATCH_END_WORD  ; No carry gives an ordinary endpoint.
    LD   A,H                ; A carry is legal only for the exact endpoint.
    OR   L                  ; The low word must wrap to zero.
    JP   NZ,CP_MAT_INVALID  ; Reject a PATCH beyond address space.
    LD   A,1                ; Mark mathematical endpoint $10000.
    LD   (CP_MAT_ENDPOINT_TOP),A  ; Compare it with the IMAGE endpoint.
    JR   CP_MAT_PATCH_COMPARE  ; Finish the bounded-image check.
CP_MAT_PATCH_END_WORD:
    XOR  A                  ; This PATCH has an ordinary word endpoint.
    LD   (CP_MAT_ENDPOINT_TOP),A  ; Clear the temporary endpoint flag.
    LD   (CP_MAT_RECORD_END),HL  ; Keep its absolute endpoint for comparison.
CP_MAT_PATCH_COMPARE:
    LD   A,(CP_MAT_IMAGE_TOP)  ; Read the greatest preceding IMAGE endpoint.
    OR   A                  ; An endpoint image contains every valid address.
    JR   NZ,CP_MAT_PATCH_VALID  ; Any in-range PATCH fits below $10000.
    LD   A,(CP_MAT_ENDPOINT_TOP)  ; Compare the PATCH endpoint's top bit.
    OR   A                  ; A top PATCH cannot fit below a word endpoint.
    JP   NZ,CP_MAT_INVALID  ; Reject a PATCH beyond preceding IMAGE data.
    LD   HL,(CP_MAT_RECORD_END)  ; Load the ordinary PATCH endpoint.
    LD   DE,(CP_MAT_IMAGE_END)  ; Load the current IMAGE exclusive end.
    OR   A                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE              ; Is the complete replacement within prior IMAGE?
    JR   C,CP_MAT_PATCH_VALID  ; A lower endpoint also permits fill-gap PATCH.
    JR   Z,CP_MAT_PATCH_VALID  ; Equality is the greatest preceding IMAGE end.
    JP   CP_MAT_INVALID     ; Reject a PATCH that reaches future bytes.
CP_MAT_PATCH_VALID:
    CALL CP_MAT_RECORD_BYTES  ; Consume and apply the final patch bytes.
    RET  C                  ; Do not accept a truncated replacement payload.
    LD   A,2                ; A PATCH breaks adjacent IMAGE canonical runs.
    LD   (CP_MAT_PREVIOUS_KIND),A  ; Retain it for the next record's rule.
    LD   A,(CP_MAT_RECORD_LENGTH)  ; Preserve the exact accepted patch length.
    LD   (CP_MAT_PREVIOUS_LENGTH),A  ; The value is irrelevant after PATCH.
    JP   CP_MAT_RECORDS     ; Continue through the mandatory END record.

; Read a payload byte and apply it only when its offset lies in this window.

CP_MAT_RECORD_BYTES:
    LD   A,(CP_MAT_RECORD_LEFT)  ; Check how many payload bytes remain.
    OR   A                  ; Zero means the record is complete.
    JR   Z,CP_MAT_RECORD_BYTES_DONE  ; Return without reading the next kind.
    CALL CP_MAT_NEXT_BYTE   ; Consume one byte from the sequential ASO file.
    RET  C                  ; Reject truncated record payloads.
    LD   (CP_MAT_BYTE),A    ; Save the byte while checking its destination.
    LD   HL,(CP_MAT_RECORD_OFFSET)  ; Load this payload byte's image offset.
    LD   DE,(CP_MAT_WINDOW_START)  ; Load the current window's relative start.
    OR   A                  ; Clear carry before the unsigned subtraction.
    SBC  HL,DE              ; Is the record byte before this output window?
    JR   C,CP_MAT_RECORD_SKIP  ; Older records are consumed but not reapplied.
    PUSH HL                 ; Preserve its nonnegative offset into the window.
    LD   DE,(CP_MAT_WINDOW_LENGTH)  ; Load this window's exclusive size.
    OR   A                  ; Clear carry before comparing the offset.
    SBC  HL,DE              ; Is the byte at or beyond the window's end?
    POP  HL                 ; Recover its relative position, preserving flags.
    JR   NC,CP_MAT_RECORD_SKIP  ; A later pass will apply this record.
    LD   DE,CP_MAT_WINDOW   ; Convert the window-relative offset to a pointer.
    ADD  HL,DE              ; Address the byte to replace in the RAM window.
    LD   A,(CP_MAT_BYTE)    ; Reload the current IMAGE or PATCH value.
    LD   (HL),A             ; Apply this operation in stream order.
CP_MAT_RECORD_SKIP:
    LD   HL,(CP_MAT_RECORD_OFFSET)  ; Advance to the next payload address.
    INC  HL                 ; Each record payload is a consecutive byte run.
    LD   (CP_MAT_RECORD_OFFSET),HL  ; Retain its image-relative position.
    LD   HL,CP_MAT_RECORD_LEFT  ; Address the remaining payload counter.
    DEC  (HL)               ; Consume the byte read above.
    JR   CP_MAT_RECORD_BYTES  ; Continue until every encoded byte is consumed.
CP_MAT_RECORD_BYTES_DONE:
    XOR  A                  ; Return success with carry clear.
    RET                     ; The caller can advance to the next record.

; END must match the writer's committed geometry; padding is exactly $1A.

CP_MAT_END:
    CALL CP_MAT_READ_WORD   ; Read the high-water word.
    JP   C,CP_MAT_INVALID   ; END requires all six geometry bytes.
    LD   DE,(CP_ASO_HIGH_WATER)  ; Compare with the writer's checked endpoint.
    OR   A                  ; Clear carry before the word comparison.
    SBC  HL,DE              ; Did the stream retain the committed high water?
    JP   NZ,CP_MAT_INVALID  ; Refuse altered geometry.
    CALL CP_MAT_NEXT_BYTE   ; Read high water's seventeenth bit.
    JP   C,CP_MAT_INVALID   ; Reject a truncated endpoint.
    LD   B,A                ; Preserve the encoded high-water top byte.
    LD   A,(CP_ASO_FLAGS)   ; Read the writer's validated COMMIT flags.
    AND  2                  ; Isolate the high-water endpoint bit.
    RRCA                    ; Move that endpoint marker into bit zero.
    CP   B                  ; Require exact agreement with the checked value.
    JP   NZ,CP_MAT_INVALID  ; Reject endpoints other than 0 or exactly $10000.
    CALL CP_MAT_READ_WORD   ; Read the final-cursor word.
    JP   C,CP_MAT_INVALID   ; Require the rest of the END record.
    LD   DE,(CP_ASO_FINAL_CURSOR)  ; Compare with the committed final cursor.
    OR   A                  ; Clear borrow for this exact equality check.
    SBC  HL,DE              ; Did the cursor survive serialization unchanged?
    JP   NZ,CP_MAT_INVALID  ; Refuse a changed final position.
    CALL CP_MAT_NEXT_BYTE   ; Read the final cursor's seventeenth bit.
    JP   C,CP_MAT_INVALID   ; END is incomplete without the final byte.
    LD   B,A                ; Preserve its encoded endpoint marker.
    LD   A,(CP_ASO_FLAGS)   ; Read the writer's cursor endpoint bit.
    AND  1                  ; Keep only the cursor's mathematical top bit.
    CP   B                  ; Require exact agreement with the COMMIT state.
    JP   NZ,CP_MAT_INVALID  ; Reject a cursor endpoint that changed on disk.
    LD   A,(CP_ASO_FLAGS)   ; Read whether high water is exactly $10000.
    AND  2                  ; The top endpoint contains every valid IMAGE end.
    JR   NZ,CP_MAT_END_IMAGE_OK  ; The maximum valid IMAGE end is $10000.
    LD   A,(CP_MAT_IMAGE_TOP)  ; Otherwise IMAGE end must also fit in 16 bits.
    OR   A                  ; Is its exclusive endpoint $10000?
    JP   NZ,CP_MAT_INVALID  ; That exceeds any ordinary committed high water.
    LD   HL,(CP_ASO_HIGH_WATER)  ; Load the ordinary committed endpoint.
    LD   DE,(CP_MAT_IMAGE_END)  ; Load the greatest parsed IMAGE endpoint.
    OR   A                  ; Clear borrow before checking endpoint ordering.
    SBC  HL,DE              ; High water minus IMAGE end must be nonnegative.
    JP   C,CP_MAT_INVALID   ; Reject IMAGE data beyond the committed geometry.
CP_MAT_END_IMAGE_OK:
    LD   A,(CP_MAT_READ_LEFT)  ; Check bytes remaining in the final record.
    OR   A                  ; Zero means END ended at a record boundary.
    JR   Z,CP_MAT_END_EOF  ; Verify there is no extra physical record.
CP_MAT_PADDING:
    CALL CP_MAT_NEXT_BYTE   ; Read one remaining byte from this same record.
    JP   C,CP_MAT_INVALID   ; The current physical record must be complete.
    CP   $1A                ; The CP/M writer pads only with SUB bytes.
    JP   NZ,CP_MAT_INVALID  ; Reject data after END or wrong padding.
    LD   A,(CP_MAT_READ_LEFT)  ; Is the final record now consumed?
    OR   A                  ; Zero permits only a subsequent EOF response.
    JR   NZ,CP_MAT_PADDING  ; Validate every remaining physical padding byte.
CP_MAT_END_EOF:
    CALL CP_MAT_FETCH_RECORD  ; Ask whether another physical record exists.
    CP   1                  ; Only end-of-file completes the stream.
    JP   NZ,CP_MAT_INVALID  ; Reject extra records and read failures.
    XOR  A                  ; Return a verified END with carry clear.
    RET                     ; The replay may now close the spool.

; Read one little-endian word through the bounded sequential byte reader.

CP_MAT_READ_WORD:
    CALL CP_MAT_NEXT_BYTE   ; Read the low byte first.
    RET  C                  ; Propagate a truncated field.
    LD   (CP_MAT_BYTE),A    ; Retain it while fetching the high byte.
    CALL CP_MAT_NEXT_BYTE   ; Read the high byte.
    RET  C                  ; Do not return a partial word.
    LD   H,A                ; Place the high byte in H.
    LD   A,(CP_MAT_BYTE)    ; Recover the low byte.
    LD   L,A                ; Complete the little-endian word in HL.
    XOR  A                  ; Return success with carry clear.
    RET                     ; HL contains the decoded u16 value.

; Refill the one-record input buffer and return the next ASO byte in A.

CP_MAT_NEXT_BYTE:
    LD   A,(CP_MAT_READ_LEFT)  ; Check for bytes already in the DMA record.
    OR   A                  ; A nonzero count avoids another BDOS read.
    JR   NZ,CP_MAT_BYTE_READY  ; Consume the buffered byte.
    CALL CP_MAT_FETCH_RECORD  ; Read the next physical ASO record.
    OR   A                  ; BDOS zero denotes a successful record read.
    JR   NZ,CP_MAT_READ_BAD  ; EOF or a disk error before END is invalid.
    LD   A,128              ; A successful BDOS read supplies one full record.
    LD   (CP_MAT_READ_LEFT),A  ; Retain its physical size.
    LD   HL,CP_MAT_RECORD   ; Point at the first byte from the DMA transfer.
    LD   (CP_MAT_READ_PTR),HL  ; Retain the next byte to consume.
CP_MAT_BYTE_READY:
    LD   HL,(CP_MAT_READ_PTR)  ; Address the current byte in the record.
    LD   A,(HL)              ; Read one encoded header or payload byte.
    INC  HL                 ; Advance the bounded input cursor.
    LD   (CP_MAT_READ_PTR),HL  ; Retain its updated record position.
    LD   HL,CP_MAT_READ_LEFT  ; Address the remaining physical-byte count.
    DEC  (HL)               ; Mark the byte consumed exactly once.
    OR   A                  ; Return the byte with carry clear.
    RET                     ; A contains the next ASO stream byte.
CP_MAT_READ_BAD:
    SCF                     ; Signal EOF or disk failure to the parser.
    RET                     ; No incomplete stream can be materialized.

; Read one raw physical record, leaving BDOS's status in A.

CP_MAT_FETCH_RECORD:
    LD   DE,CP_MAT_RECORD   ; Use the relocated record buffer.
    LD   C,CP_DMA_FUNCTION  ; Select CP/M's set-DMA-address service.
    CALL CP_BDOS            ; Install the reader-owned transfer buffer.
    LD   DE,CP_MAT_FCB      ; Pass the relocated sequential spool FCB.
    LD   C,CP_READ_FUNCTION  ; Select CP/M sequential record-read function 20.
    JP   CP_BDOS            ; Return zero, EOF one, or the BDOS error code.

; Append this aligned window using only sequential record writes.

CP_MAT_WRITE_WINDOW:
    LD   HL,CP_MAT_WINDOW   ; Point at the first output record in the window.
    LD   (CP_MAT_WINDOW_CURSOR),HL  ; Retain the current DMA record address.
    LD   HL,(CP_MAT_WINDOW_LENGTH)  ; Load the number of bytes to emit.
    LD   (CP_MAT_WINDOW_LEFT),HL  ; Count output records by their byte size.
CP_MAT_WRITE_RECORD:
    LD   HL,(CP_MAT_WINDOW_LEFT)  ; Check whether the window is fully written.
    LD   A,H                ; Test the high byte.
    OR   L                  ; Zero ends this output window.
    JR   Z,CP_MAT_WRITE_DONE  ; Replay the next window or finish.
    LD   DE,(CP_MAT_WINDOW_CURSOR)  ; Select the next complete 128-byte block.
    LD   C,CP_DMA_FUNCTION  ; Point CP/M's DMA at that output block.
    CALL CP_BDOS            ; Install the sequential write buffer.
    LD   DE,CP_WORK_FCB     ; Pass the tentative output file's FCB.
    LD   C,CP_WRITE_FUNCTION  ; Select sequential record-write function 21.
    CALL CP_BDOS            ; Append this complete output record.
    OR   A                  ; Zero denotes a successful BDOS write.
    JR   NZ,CP_MAT_WRITE_BAD  ; Preserve old output on write failure.
    LD   HL,(CP_MAT_WINDOW_CURSOR)  ; Read the current output-buffer address.
    LD   DE,128             ; Every CP/M record contains exactly 128 bytes.
    ADD  HL,DE              ; Advance to the next block in this window.
    LD   (CP_MAT_WINDOW_CURSOR),HL  ; Retain its address for the next write.
    LD   HL,(CP_MAT_WINDOW_LEFT)  ; Reload the remaining window length.
    OR   A                  ; Clear carry before subtracting one record.
    SBC  HL,DE              ; Account for the record written above.
    LD   (CP_MAT_WINDOW_LEFT),HL  ; Retain the nonnegative aligned remainder.
    JR   CP_MAT_WRITE_RECORD  ; Continue until this window is appended.
CP_MAT_WRITE_DONE:
    XOR  A                  ; Return success after all records were written.
    RET                     ; The caller can release and reuse the window.
CP_MAT_WRITE_BAD:
    JP   CP_MAT_FAILURE     ; Leave cleanup and rollback to HS_ABORT.

; Finalize the temp file, discard the spool, and publish only after success.

CP_MAT_OUTPUT_CLOSE:
    LD   DE,CP_WORK_FCB     ; Close the completed output temporary file.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Flush its last full record to disk.
    INC  A                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,CP_MAT_FAILURE   ; The prior output remains untouched.
    XOR  A                  ; No open output file remains for abort to close.
    LD   (CP_OUTPUT_OPEN),A  ; Clear ownership before the next transaction.
    CALL CP_SET_BACKUP_FCB  ; Select the private ASO spool name.
    LD   DE,CP_WORK_FCB     ; Pass its FCB to CP/M's delete service.
    LD   C,CP_DELETE_FUNCTION  ; Remove the spool before BAK changes owner.
    CALL CP_BDOS            ; Discard the internal stream after replay.
    OR   A                  ; A zero result means the spool was removed.
    JR   NZ,CP_MAT_FAILURE  ; Do not publish if internal cleanup failed.
    XOR  A                  ; BAK is free for the output transaction now.
    LD   (CP_MAT_SPOOL_OWNED),A  ; Keep output backup separate from the spool.
    CALL CP_PUBLISH_TEMP    ; Atomically replace the selected output file.
    RET                     ; Preserve publication's carry result.

; Common fail-closed result; HS_ABORT removes temp/spool and restores backup.

CP_MAT_INVALID:
CP_MAT_FAILURE:
    LD   A,1                ; Return the ordinary build-failure code.
    SCF                     ; Prevent the output service from committing.
    RET                     ; The driver will enter HS_ABORT immediately.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Remove an internal spool during abort while leaving a real BAK untouched.

CP_MAT_DELETE_SPOOL:
    CALL CP_SET_BACKUP_FCB  ; Select the private spool's reserved filename.
    LD   DE,CP_WORK_FCB     ; Pass the spool name to the delete service.
    LD   C,CP_DELETE_FUNCTION  ; Select CP/M delete-file function 19.
    CALL CP_BDOS            ; Remove the failed internal operation stream.
    XOR  A                  ; BAK is no longer owned by the materializer.
    LD   (CP_MAT_SPOOL_OWNED),A  ; Preserve any later output-backup ownership.
    RET                     ; Return to the resident abort/restore sequence.
