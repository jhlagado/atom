; Replay one CP/M ASO spool into bounded sequential output windows.
;
; The source has already been assembled once. Each pass reopens the private
; ASO file, validates its ordered records and applies only the operations
; intersecting the current output window. Output records are always written
; sequentially. no floppy seek is needed to apply a PATCH.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Convert the internal ASO spool into COM, BIN or HEX, then publish the temp.

MAT_RUN: ; Replay the committed spool into output windows.
    LD   A,(ASO_FLAG)                       ; Read the committed high-water endpoint form.
    BIT  1,A                                ; Is high water the mathematical endpoint $10000?
    JR   Z,.HIGHWORD                        ; Otherwise use its ordinary 16-bit address.
    LD   HL,ASO_CAP                         ; $10000 minus the $0100 COM origin.
    JR   .LENREADY                          ; The maximum logical image is exactly $FF00.
.HIGHWORD: ; Compute length from ordinary high water.
    LD   HL,(ASO_HIGH)                      ; Load the ordinary exclusive high-water.
    LD   DE,(ASO_ORG)                       ; Subtract the ASO image origin.
    OR   A                                  ; Clear borrow before the subtraction.
    SBC  HL,DE                              ; Convert the absolute endpoint to a file length.
.LENREADY: ; Choose exact or physical-record-rounded length.
    LD   A,(PUB_KIND)                       ; Check whether this output is textual HEX.
    CP   2                                  ; HEX stores exact bytes rather than CP/M records.
    JR   Z,.EXACT                           ; Keep the exact unpadded length.
    LD   DE,127                             ; Round the last logical record up to 128 bytes.
    ADD  HL,DE                              ; The extra bytes use the ASO fill value.
    LD   A,L                                ; Keep only bit seven of the rounded low byte.
    AND  $80                                ; Clear the seven bits below a record boundary.
    LD   L,A                                ; Retain the rounded low byte.
.EXACT: ; Initialise replay and publication state.
    LD   (MAT_LEFT),HL                      ; Count HEX or padded binary bytes.
    XOR  A                                  ; Begin writing the first output window.
    LD   (MAT_FILL),A                       ; The native BEGIN hook declares zero fill.
    LD   (MAT_WOFF),A                       ; Its image-relative offset is zero.
    LD   (MAT_WOFF+1),A                     ; Clear the offset's high byte as well.
    CALL PUB_TEMP                           ; Name the tentative output file.
    LD   DE,CP_FCB+12                       ; Reset all mutable FCB state before MAKE.
    XOR  A                                  ; CP/M expects cleared record and extent fields.
    LD   B,24                               ; Count the remaining FCB bytes.
    CALL PUB_FILL                           ; Keep the selected filename and clear its tail.
    LD   DE,CP_FCB                          ; Pass the tentative output FCB to BDOS.
    LD   C,CP_MAKE                          ; Select CP/M make-file function 22.
    CALL CP_BDOS                            ; Create the output only after ASO COMMIT.
    INC  A                                  ; Convert BDOS's $FF failure result to zero.
    JP   Z,.FAILURE                         ; Keep the old destination untouched.
    LD   A,1                                ; The abort path now owns the open temp file.
    LD   (PUB_OPEN),A                       ; Retain its cleanup state.
    LD   A,(PUB_KIND)                       ; Select the representation's output encoder.
    CP   2                                  ; Format two is Intel HEX.
    JR   NZ,.WINLOOP                        ; Binary outputs need no HEX buffer setup.
    CALL ZTS_CPM_HEX_BEGIN                  ; Start one HEX stream before its replay windows.
.WINLOOP: ; Process each output window.
    LD   HL,(MAT_LEFT)                      ; Read the rounded output bytes remaining.
    LD   A,H                                ; Check the high byte.
    OR   L                                  ; Zero means the empty or final window is done.
    JR   NZ,.NONEMPTY                       ; Continue when a window remains to write.
    LD   HL,(MAT_WOFF)                      ; Did any nonempty output window complete?
    LD   A,H                                ; Check its high byte.
    OR   L                                  ; Zero distinguishes a genuinely empty image.
    JR   NZ,.DATADONE                       ; Nonempty output passed validation.
    CALL .REPLAY                            ; Validate an empty stream through physical EOF.
    RET  C                                  ; Do not publish a malformed empty stream.
.DATADONE: ; Finish the chosen output representation.
    LD   A,(PUB_KIND)                       ; Select the format's finalisation path.
    CP   2                                  ; Intel HEX needs EOF and final record padding.
    JP   NZ,.CLOSE                          ; Binary output is already complete.
    CALL ZTS_CPM_HEX_END                    ; Finish the HEX stream through sequential BDOS.
    RET  C                                  ; Preserve the old output after a write failure.
    JP   .CLOSE                             ; Close only after HEX is complete.
.NONEMPTY: ; Choose a bounded nonempty window.
    LD   HL,MAT_WEND                        ; Load the exclusive replay-window ceiling.
    LD   DE,MAT_WIN                         ; Subtract the aligned start after overlay code.
    OR   A                                  ; Clear borrow before measuring available memory.
    SBC  HL,DE                              ; Form this build's measured window capacity.
    EX   DE,HL                              ; Keep the capacity in DE for comparison.
    LD   HL,(MAT_LEFT)                      ; Reload the rounded output size.
    OR   A                                  ; Clear carry before comparing window and output.
    SBC  HL,DE                              ; Is another full window left?
    JR   NC,.FULLWIN                        ; Use the complete buffer when it fits.
    LD   HL,(MAT_LEFT)                      ; The final window uses the remainder.
    JR   .WINREADY                          ; Its length remains record-aligned.
.FULLWIN: ; Use the complete available window.
    LD   HL,MAT_WEND                        ; Load the ceiling used by the window calculation.
    LD   DE,MAT_WIN                         ; Load the aligned start after materialiser code.
    OR   A                                  ; Clear borrow before taking the difference.
    SBC  HL,DE                              ; Recover the record-aligned window size.
.WINREADY: ; Fill and replay the chosen byte range.
    LD   (MAT_WLEN),HL                      ; Save this pass's physical byte count.
    LD   (MAT_WCNT),HL                      ; Initialize the fill loop length.
    CALL .FILLWIN                           ; Restore untouched gaps and reservations.
    CALL .REPLAY                            ; Reopen and validate the complete ASO stream.
    RET  C                                  ; HS_ABORT removes tentative data.
    LD   A,(PUB_KIND)                       ; Choose raw records or Intel HEX conversion.
    CP   2                                  ; Only HEX consumes the replay window as text.
    JR   NZ,.BINARY                         ; COM and BIN append this window unchanged.
    LD   HL,MAT_WIN                         ; Set the HEX input cursor.
    LD   (ZTS_CPM_FINAL_SOURCE_CURSOR),HL   ; Reset its window source cursor.
    LD   HL,(MAT_WLEN)                      ; Read the exact logical segment length.
    LD   (ZTS_CPM_FINAL_REMAINING),HL       ; Do not render binary record padding.
    LD   HL,(ASO_ORG)                       ; Start with the image's absolute base address.
    LD   DE,(MAT_WOFF)                      ; Add this replay window's relative offset.
    ADD  HL,DE                              ; Form this window's first target address.
    LD   (ZTS_CPM_FINAL_ADDRESS),HL         ; Reset the helper for this segment.
    CALL ZTS_CPM_HEX_SEGMENT                ; Emit checksummed HEX records.
    JR   .NEXTWIN                           ; Advance to the next output window.
.BINARY: ; Write COM or BIN records directly.
    CALL .WRITEWIN                          ; Append this window as sequential CP/M records.
    RET  C                                  ; Preserve the old destination on write failure.
.NEXTWIN: ; Advance output length and window offset.
    LD   HL,(MAT_LEFT)                      ; Reload total output bytes still unwritten.
    LD   DE,(MAT_WLEN)                      ; Read the completed window's length.
    OR   A                                  ; Clear borrow before reducing the remaining size.
    SBC  HL,DE                              ; Account for this full set of output records.
    LD   (MAT_LEFT),HL                      ; Retain the count for the next window.
    LD   HL,(MAT_WOFF)                      ; Read the next relative window start.
    ADD  HL,DE                              ; Advance by the length just materialised.
    LD   (MAT_WOFF),HL                      ; Keep the next pass aligned with records.
    JP   .WINLOOP                           ; Continue or close after the final window.

; Fill the selected window before applying any IMAGE and PATCH operations.

.FILLWIN: ; Initialise gaps before replaying operations.
    LD   A,(MAT_FILL)                       ; Use the header's validated gap-fill byte.
    LD   HL,MAT_WIN                         ; Select the first byte of the destination window.
    LD   (HL),A                             ; Seed LDIR with the selected fill value.
    LD   DE,MAT_WIN+1                       ; Point one byte beyond the seed value.
    LD   BC,(MAT_WLEN)                      ; Load the complete window length.
    DEC  BC                                 ; The seed byte is already initialised.
    LD   A,B                                ; Does any byte remain after the seed?
    OR   C                                  ; A one-byte window needs no LDIR operation.
    RET  Z                                  ; Avoid treating BC=0 as 65,536 copies.
    LD   HL,MAT_WIN                         ; Point LDIR at that first initialised byte.
    LDIR                                    ; Fill only the bytes that will be written.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; Continue with a fresh spool replay.

; Open, parse and close one complete operation stream for this window.

.REPLAY: ; Rewind and validate the spool for this window.
    XOR  A                                  ; Reset the byte reader and record-order state.
    LD   (MAT_HAVE),A                       ; The first byte must refill the input record.
    LD   (MAT_PREV),A                       ; No previous IMAGE can constrain ordering.
    LD   (MAT_PLEN),A                       ; Clear the prior run's canonical length.
    LD   (MAT_ITOP),A                       ; Start with an ordinary endpoint.
    LD   HL,(ASO_ORG)                       ; The empty initial extent starts at origin.
    LD   (MAT_IEND),HL                      ; Use this endpoint to validate PATCH records.
    LD   DE,MAT_FCB+12                      ; Reset the sequential reader's mutable FCB tail.
    XOR  A                                  ; Start at extent and record zero.
    LD   B,24                               ; Clear all FCB control and random-record fields.
    CALL PUB_FILL                           ; Preserve the spool filename while rewinding it.
    LD   DE,MAT_FCB                         ; Pass the relocated spool FCB to CP/M OPEN.
    LD   C,CP_OPEN                          ; Select sequential file-open function 15.
    CALL CP_BDOS                            ; Reopen the committed spool from record zero.
    INC  A                                  ; Convert BDOS's $FF not-found result to zero.
    JR   Z,.BADPASS                         ; A missing spool invalidates this output.
    LD   A,1                                ; HS_ABORT owns the currently open spool FCB.
    LD   (MAT_OPEN),A                       ; Track the open spool for abort cleanup.
    CALL .HEADER                            ; Check signature, version, origin and fill.
    RET  C                                  ; Leave the reader open for the common abort path.
    CALL .RECORDS                           ; Apply records and require a valid END and EOF.
    RET  C                                  ; Do not write a window from an invalid stream.
    LD   DE,MAT_FCB                         ; Close the validated spool pass.
    LD   C,CP_CLOSE                         ; Select CP/M close-file function 16.
    CALL CP_BDOS                            ; Release the reader before another window pass.
    INC  A                                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,.BADPASS                         ; A failed close must abort publication.
    XOR  A                                  ; Clear the open flag after a successful close.
    LD   (MAT_OPEN),A                       ; Clear the flag after closing the spool.
    RET                                     ; Return a verified window with carry clear.
.BADPASS: ; Reject a failed replay pass.
    JP   .FAILURE                           ; Let HS_ABORT remove both temporary files.

; Check the fixed ASO v1 header against the state retained by its writer.

.HEADER: ; Validate the fixed seven-byte ASO header.
    CALL .NEXTBYTE                          ; Read the first signature byte.
    RET  C                                  ; A short file cannot start a valid header.
    CP   'A'                                ; Require the exact ASCII signature.
    JP   NZ,.INVALID                        ; Reject any different magic byte.
    CALL .NEXTBYTE                          ; Read the second signature byte.
    RET  C                                  ; Reject EOF before the header completes.
    CP   'S'                                ; Continue the three-byte signature check.
    JP   NZ,.INVALID                        ; Reject a changed signature.
    CALL .NEXTBYTE                          ; Read the final signature byte.
    RET  C                                  ; A truncated signature is invalid.
    CP   'O'                                ; Complete the required ASCII magic.
    JP   NZ,.INVALID                        ; Reject a different format.
    CALL .NEXTBYTE                          ; Read the ASO version.
    RET  C                                  ; Require a complete header.
    CP   1                                  ; This adapter implements ASO version one only.
    JP   NZ,.INVALID                        ; Refuse unknown versions.
    CALL .NEXTWORD                          ; Read the little-endian target origin.
    RET  C                                  ; Propagate a truncated origin field.
    LD   DE,(ASO_ORG)                       ; Compare with the origin supplied at BEGIN.
    OR   A                                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE                              ; Did the stream retain its declared origin?
    JP   NZ,.INVALID                        ; A changed origin must not redirect output.
    CALL .NEXTBYTE                          ; Read the stream's fill byte.
    RET  C                                  ; Reject an incomplete fixed header.
    LD   (MAT_FILL),A                       ; Retain the value used to initialise this window.
    OR   A                                  ; The CP/M assembler currently declares zero fill.
    JP   NZ,.INVALID                        ; Do not materialise altered fill semantics.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; The stream now has a validated v1 header.

; Parse chronological IMAGE/PATCH records through one mandatory END.

.RECORDS: ; Dispatch IMAGE, PATCH or END records.
    CALL .NEXTBYTE                          ; Read a record kind or the END marker.
    JP   C,.INVALID                         ; Physical EOF before END is invalid.
    OR   A                                  ; Record kind zero is the only valid terminator.
    JP   Z,.ENDREC                          ; Validate final geometry and record padding.
    CP   1                                  ; Record kind one denotes IMAGE.
    JR   Z,.IMAGE                           ; Parse its address, length and bytes.
    CP   2                                  ; Record kind two denotes PATCH.
    JP   Z,.PATCH                           ; Parse its replacement bytes.
    JP   .INVALID                           ; Reject every unknown v1 record kind.

; Validate an IMAGE range and apply its bytes if they intersect this window.

.IMAGE: ; Validate and consume one IMAGE record.
    LD   A,(MAT_ITOP)                       ; No IMAGE may follow an endpoint at $10000.
    OR   A                                  ; Check the seventeenth endpoint bit.
    JP   NZ,.INVALID                        ; Reject a range beyond the address space.
    CALL .NEXTWORD                          ; Read the absolute starting address.
    JP   C,.INVALID                         ; Reject a truncated IMAGE address.
    LD   (MAT_ADDR),HL                      ; Retain the encoded start for checks.
    LD   DE,(ASO_ORG)                       ; Load the minimum address of this output.
    OR   A                                  ; Clear carry before subtracting the origin.
    SBC  HL,DE                              ; Convert the target address to an image offset.
    JP   C,.INVALID                         ; Reject IMAGE bytes before the stream origin.
    LD   (MAT_ROFF),HL                      ; Save the relative operation position.
    CALL .NEXTBYTE                          ; Read the one-byte IMAGE payload length.
    JP   C,.INVALID                         ; Reject a truncated record header.
    OR   A                                  ; Zero is not a valid IMAGE record length.
    JP   Z,.INVALID                         ; Require one through 128 data bytes.
    CP   129                                ; The canonical maximum is one physical record.
    JP   NC,.INVALID                        ; Reject an excessive payload.
    LD   (MAT_RLEN),A                       ; Retain its validated length.
    LD   (MAT_RCNT),A                       ; Count payload bytes as they are consumed.
    CALL .CHKORDER                          ; Enforce nonoverlap and canonical runs.
    RET  C                                  ; Stop before applying any invalid range.
    CALL .PAYLOAD                           ; Consume the payload and update this window.
    RET  C                                  ; A short payload invalidates the whole spool.
    LD   A,1                                ; Retain IMAGE as the preceding record kind.
    LD   (MAT_PREV),A                       ; The next adjacent short IMAGE is invalid.
    LD   A,(MAT_RLEN)                       ; Retain the run length for that check.
    LD   (MAT_PLEN),A                       ; A full 128-byte run may be followed.
    JR   .RECORDS                           ; Continue parsing until END.

; Validate that IMAGE ranges ascend, do not overlap and use canonical runs.

.CHKORDER: ; Check ascending IMAGE order and coalescing.
    LD   HL,(MAT_ADDR)                      ; Load the candidate absolute address.
    LD   DE,(MAT_IEND)                      ; Load the greatest preceding IMAGE endpoint.
    OR   A                                  ; Clear carry before comparing unsigned addresses.
    SBC  HL,DE                              ; Descending or overlapping data borrows here.
    JP   C,.INVALID                         ; Reject any IMAGE before the previous endpoint.
    JR   NZ,.RANGE                          ; A gap starts a new canonical IMAGE run.
    LD   A,(MAT_PREV)                       ; Check whether an IMAGE preceded this one.
    CP   1                                  ; PATCH separates IMAGE runs and resets this rule.
    JR   NZ,.RANGE                          ; Adjacent bytes after PATCH remain valid.
    LD   A,(MAT_PLEN)                       ; Read the preceding IMAGE's run length.
    CP   128                                ; Only a maximal run may be extended adjacently.
    JP   C,.INVALID                         ; Reject split contiguous IMAGE records.
.RANGE: ; Compute and validate the IMAGE endpoint.
    LD   HL,(MAT_ROFF)                      ; Load the start relative to origin.
    LD   A,(MAT_RLEN)                       ; Add the validated payload size.
    LD   E,A                                ; Extend the byte length into DE.
    LD   D,0                                ; Complete the 16-bit length.
    ADD  HL,DE                              ; Form the new relative image endpoint.
    LD   (MAT_REND),HL                      ; Retain it for PATCH and END validation.
    LD   HL,(MAT_ADDR)                      ; Recompute the absolute exclusive end.
    ADD  HL,DE                              ; Include this IMAGE's byte length.
    JR   NC,.IENDWORD                       ; No wrap gives an ordinary endpoint.
    LD   A,H                                ; A wrapped range must end exactly at zero.
    OR   L                                  ; Reject lengths that cross beyond $10000.
    JP   NZ,.INVALID                        ; Do not permit a wrapped endpoint past memory.
    LD   A,1                                ; Retain the mathematical $10000 endpoint.
    LD   (MAT_ITOP),A                       ; No later IMAGE address can be represented.
    LD   HL,0                               ; Store zero as the endpoint's low word.
    JR   .SAVEEND                           ; Commit the checked endpoint.
.IENDWORD: ; Store an ordinary IMAGE endpoint.
    XOR  A                                  ; Mark an ordinary 16-bit exclusive endpoint.
    LD   (MAT_ITOP),A                       ; Clear any endpoint flag.
.SAVEEND: ; Publish the checked IMAGE extent.
    LD   (MAT_IEND),HL                      ; Update the greatest IMAGE endpoint.
    XOR  A                                  ; Return with carry clear.
    RET                                     ; Allow the validated payload to be consumed.

; Validate a byte/word PATCH and apply its final replacement values.

.PATCH: ; Validate and consume a byte or word PATCH.
    CALL .NEXTWORD                          ; Read the absolute target address.
    JP   C,.INVALID                         ; A missing address cannot be a valid PATCH.
    LD   (MAT_ADDR),HL                      ; Retain the target for range checks.
    LD   DE,(ASO_ORG)                       ; Load the declared output origin.
    OR   A                                  ; Clear carry before subtracting origin.
    SBC  HL,DE                              ; Convert the target to an image-relative offset.
    JP   C,.INVALID                         ; Reject a patch before the logical image.
    LD   (MAT_ROFF),HL                      ; Save the first replacement position.
    CALL .NEXTBYTE                          ; Read a byte or word patch length.
    JP   C,.INVALID                         ; Reject a truncated PATCH header.
    CP   1                                  ; The one-byte case is canonical.
    JR   Z,.SIZEOK                          ; Keep its length unchanged.
    CP   2                                  ; The only other accepted length is two.
    JP   NZ,.INVALID                        ; Reject empty or longer replacement records.
.SIZEOK: ; Retain the accepted PATCH payload length.
    LD   (MAT_RLEN),A                       ; Retain the validated payload length.
    LD   (MAT_RCNT),A                       ; Count replacement bytes during reading.
    LD   HL,(MAT_ADDR)                      ; Form the exclusive absolute endpoint.
    LD   E,A                                ; Extend the patch size into DE.
    LD   D,0                                ; Complete the 16-bit addition operand.
    ADD  HL,DE                              ; Detect a patch that wraps past $10000.
    JR   NC,.NOWRAP                         ; No carry gives an ordinary endpoint.
    LD   A,H                                ; A carry is legal only for the exact endpoint.
    OR   L                                  ; The low word must wrap to zero.
    JP   NZ,.INVALID                        ; Reject a PATCH beyond address space.
    LD   A,1                                ; Mark mathematical endpoint $10000.
    LD   (MAT_RTOP),A                       ; Compare it with the IMAGE endpoint.
    JR   .COMPARE                           ; Finish the bounded-image check.
.NOWRAP: ; Store an ordinary PATCH endpoint.
    XOR  A                                  ; This PATCH has an ordinary word endpoint.
    LD   (MAT_RTOP),A                       ; Clear the temporary endpoint flag.
    LD   (MAT_REND),HL                      ; Keep its absolute endpoint for comparison.
.COMPARE: ; Require the PATCH to fit preceding IMAGE extent.
    LD   A,(MAT_ITOP)                       ; Read the greatest preceding IMAGE endpoint.
    OR   A                                  ; An endpoint image contains every valid address.
    JR   NZ,.APPLY                          ; Any in-range PATCH fits below $10000.
    LD   A,(MAT_RTOP)                       ; Compare the PATCH endpoint's top bit.
    OR   A                                  ; A top PATCH cannot fit below a word endpoint.
    JP   NZ,.INVALID                        ; Reject a PATCH beyond preceding IMAGE data.
    LD   HL,(MAT_REND)                      ; Load the ordinary PATCH endpoint.
    LD   DE,(MAT_IEND)                      ; Load the current IMAGE exclusive end.
    OR   A                                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE                              ; Is the complete replacement within prior IMAGE?
    JR   C,.APPLY                           ; A lower endpoint also permits fill-gap PATCH.
    JR   Z,.APPLY                           ; Equality is the greatest preceding IMAGE end.
    JP   .INVALID                           ; Reject a PATCH that reaches future bytes.
.APPLY: ; Apply a validated PATCH in stream order.
    CALL .PAYLOAD                           ; Consume and apply the final patch bytes.
    RET  C                                  ; Do not accept a truncated replacement payload.
    LD   A,2                                ; A PATCH breaks adjacent IMAGE canonical runs.
    LD   (MAT_PREV),A                       ; Retain it for the next record's rule.
    LD   A,(MAT_RLEN)                       ; Preserve the exact accepted patch length.
    LD   (MAT_PLEN),A                       ; The value is irrelevant after PATCH.
    JP   .RECORDS                           ; Continue through the mandatory END record.

; Read a payload byte and apply it only when its offset lies in this window.

.PAYLOAD: ; Consume every payload byte for this pass.
    LD   A,(MAT_RCNT)                       ; Check how many payload bytes remain.
    OR   A                                  ; Zero means the record is complete.
    JR   Z,.CONSUMED                        ; Return without reading the next kind.
    CALL .NEXTBYTE                          ; Consume one byte from the sequential ASO file.
    RET  C                                  ; Reject truncated record payloads.
    LD   (MAT_BYTE),A                       ; Save the byte while checking its destination.
    LD   HL,(MAT_ROFF)                      ; Load this payload byte's image offset.
    LD   DE,(MAT_WOFF)                      ; Load the current window's relative start.
    OR   A                                  ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                              ; Is the record byte before this output window?
    JR   C,.SKIP                            ; Older records are consumed but not reapplied.
    PUSH HL                                 ; Preserve its nonnegative offset into the window.
    LD   DE,(MAT_WLEN)                      ; Load this window's exclusive size.
    OR   A                                  ; Clear carry before comparing the offset.
    SBC  HL,DE                              ; Is the byte at or beyond the window's end?
    POP  HL                                 ; Recover its relative position, preserving flags.
    JR   NC,.SKIP                           ; A later pass will apply this record.
    LD   DE,MAT_WIN                         ; Convert the window-relative offset to a pointer.
    ADD  HL,DE                              ; Address the byte to replace in the RAM window.
    LD   A,(MAT_BYTE)                       ; Reload the current IMAGE or PATCH value.
    LD   (HL),A                             ; Apply this operation in stream order.
.SKIP: ; Advance after applying or skipping one byte.
    LD   HL,(MAT_ROFF)                      ; Advance to the next payload address.
    INC  HL                                 ; Each record payload is a consecutive byte run.
    LD   (MAT_ROFF),HL                      ; Retain its image-relative position.
    LD   HL,MAT_RCNT                        ; Address the remaining payload counter.
    DEC  (HL)                               ; Consume the byte read above.
    JR   .PAYLOAD                           ; Continue until every encoded byte is consumed.
.CONSUMED: ; Finish a completely consumed payload.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; The caller can advance to the next record.

; END must match the writer's committed geometry. padding is exactly $1A.

.ENDREC: ; Validate END against retained COMMIT geometry.
    CALL .NEXTWORD                          ; Read the high-water word.
    JP   C,.INVALID                         ; END requires all six geometry bytes.
    LD   DE,(ASO_HIGH)                      ; Compare with the writer's checked endpoint.
    OR   A                                  ; Clear carry before the word comparison.
    SBC  HL,DE                              ; Did the stream retain the committed high water?
    JP   NZ,.INVALID                        ; Refuse altered geometry.
    CALL .NEXTBYTE                          ; Read high water's seventeenth bit.
    JP   C,.INVALID                         ; Reject a truncated endpoint.
    LD   B,A                                ; Preserve the encoded high-water top byte.
    LD   A,(ASO_FLAG)                       ; Read the writer's validated COMMIT flags.
    AND  2                                  ; Isolate the high-water endpoint bit.
    RRCA                                    ; Move that endpoint marker into bit zero.
    CP   B                                  ; Require exact agreement with the checked value.
    JP   NZ,.INVALID                        ; Reject endpoints other than 0 or exactly $10000.
    CALL .NEXTWORD                          ; Read the final-cursor word.
    JP   C,.INVALID                         ; Require the rest of the END record.
    LD   DE,(ASO_LAST)                      ; Compare with the committed final cursor.
    OR   A                                  ; Clear borrow for this exact equality check.
    SBC  HL,DE                              ; Did the cursor survive serialization unchanged?
    JP   NZ,.INVALID                        ; Refuse a changed final position.
    CALL .NEXTBYTE                          ; Read the final cursor's seventeenth bit.
    JP   C,.INVALID                         ; END is incomplete without the final byte.
    LD   B,A                                ; Preserve its encoded endpoint marker.
    LD   A,(ASO_FLAG)                       ; Read the writer's cursor endpoint bit.
    AND  1                                  ; Keep only the cursor's mathematical top bit.
    CP   B                                  ; Require exact agreement with the COMMIT state.
    JP   NZ,.INVALID                        ; Reject a cursor endpoint that changed on disk.
    LD   A,(ASO_FLAG)                       ; Read whether high water is exactly $10000.
    AND  2                                  ; The top endpoint contains every valid IMAGE end.
    JR   NZ,.IMAGEOK                        ; The maximum valid IMAGE end is $10000.
    LD   A,(MAT_ITOP)                       ; Otherwise IMAGE end must also fit in 16 bits.
    OR   A                                  ; Is its exclusive endpoint $10000?
    JP   NZ,.INVALID                        ; That exceeds any ordinary committed high water.
    LD   HL,(ASO_HIGH)                      ; Load the ordinary committed endpoint.
    LD   DE,(MAT_IEND)                      ; Load the greatest parsed IMAGE endpoint.
    OR   A                                  ; Clear borrow before checking endpoint ordering.
    SBC  HL,DE                              ; High water minus IMAGE end must be nonnegative.
    JP   C,.INVALID                         ; Reject IMAGE data beyond the committed geometry.
.IMAGEOK: ; Check final-record padding and physical EOF.
    LD   A,(MAT_HAVE)                       ; Check bytes remaining in the final record.
    OR   A                                  ; Zero means END ended at a record boundary.
    JR   Z,.EOF                             ; Verify there is no extra physical record.
.PADLOOP: ; Consume only SUB padding after END.
    CALL .NEXTBYTE                          ; Read one remaining byte from this same record.
    JP   C,.INVALID                         ; The current physical record must be complete.
    CP   $1A                                ; The CP/M writer pads only with SUB bytes.
    JP   NZ,.INVALID                        ; Reject data after END or wrong padding.
    LD   A,(MAT_HAVE)                       ; Is the final record now consumed?
    OR   A                                  ; Zero permits only a subsequent EOF response.
    JR   NZ,.PADLOOP                        ; Validate every remaining physical padding byte.
.EOF: ; Require EOF immediately after the final record.
    CALL .FETCH                             ; Ask whether another physical record exists.
    CP   1                                  ; Only end-of-file completes the stream.
    JP   NZ,.INVALID                        ; Reject extra records and read failures.
    XOR  A                                  ; Return a verified END with carry clear.
    RET                                     ; The replay may now close the spool.

; Read one little-endian word through the bounded sequential byte reader.

.NEXTWORD: ; Decode a little-endian word from the spool.
    CALL .NEXTBYTE                          ; Read the low byte first.
    RET  C                                  ; Propagate a truncated field.
    LD   (MAT_BYTE),A                       ; Retain it while fetching the high byte.
    CALL .NEXTBYTE                          ; Read the high byte.
    RET  C                                  ; Do not return a partial word.
    LD   H,A                                ; Place the high byte in H.
    LD   A,(MAT_BYTE)                       ; Recover the low byte.
    LD   L,A                                ; Complete the little-endian word in HL.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; HL contains the decoded u16 value.

; Refill the one-record input buffer and return the next ASO byte in A.

.NEXTBYTE: ; Read a byte or refill the physical record.
    LD   A,(MAT_HAVE)                       ; Check for bytes already in the DMA record.
    OR   A                                  ; A nonzero count avoids another BDOS read.
    JR   NZ,.BUFFERED                       ; Consume the buffered byte.
    CALL .FETCH                             ; Read the next physical ASO record.
    OR   A                                  ; BDOS zero denotes a successful record read.
    JR   NZ,.READFAIL                       ; EOF or a disk error before END is invalid.
    LD   A,128                              ; A successful BDOS read supplies one full record.
    LD   (MAT_HAVE),A                       ; Retain its physical size.
    LD   HL,MAT_REC                         ; Point at the first byte from the DMA transfer.
    LD   (MAT_PTR),HL                       ; Retain the next byte to consume.
.BUFFERED: ; Consume a byte already buffered.
    LD   HL,(MAT_PTR)                       ; Address the current byte in the record.
    LD   A,(HL)                             ; Read one encoded header or payload byte.
    INC  HL                                 ; Advance the bounded input cursor.
    LD   (MAT_PTR),HL                       ; Retain its updated record position.
    LD   HL,MAT_HAVE                        ; Address the remaining physical-byte count.
    DEC  (HL)                               ; Mark the byte consumed exactly once.
    OR   A                                  ; Return the byte with carry clear.
    RET                                     ; A contains the next ASO stream byte.
.READFAIL: ; Report a failed physical record read.
    SCF                                     ; Signal EOF or disk failure to the parser.
    RET                                     ; No incomplete stream can be materialised.

; Read one raw physical record, leaving BDOS's status in A.

.FETCH: ; Fetch one sequential CP/M record.
    LD   DE,MAT_REC                         ; Use the relocated record buffer.
    LD   C,CP_DMA                           ; Select CP/M's set-DMA-address service.
    CALL CP_BDOS                            ; Install the reader-owned transfer buffer.
    LD   DE,MAT_FCB                         ; Pass the relocated sequential spool FCB.
    LD   C,CP_READ                          ; Select CP/M sequential record-read function 20.
    JP   CP_BDOS                            ; Return zero, EOF one, or the BDOS error code.

; Append this aligned window using only sequential record writes.

.WRITEWIN: ; Append this window to the tentative output.
    LD   HL,MAT_WIN                         ; Point at the first output record in the window.
    LD   (MAT_WPTR),HL                      ; Retain the current DMA record address.
    LD   HL,(MAT_WLEN)                      ; Load the number of bytes to emit.
    LD   (MAT_WCNT),HL                      ; Count output records by their byte size.
.RECLOOP: ; Write each complete 128-byte output record.
    LD   HL,(MAT_WCNT)                      ; Check whether the window is fully written.
    LD   A,H                                ; Test the high byte.
    OR   L                                  ; Zero ends this output window.
    JR   Z,.WRITTEN                         ; Replay the next window or finish.
    LD   DE,(MAT_WPTR)                      ; Select the next complete 128-byte block.
    LD   C,CP_DMA                           ; Point CP/M's DMA at that output block.
    CALL CP_BDOS                            ; Install the sequential write buffer.
    LD   DE,CP_FCB                          ; Pass the tentative output file's FCB.
    LD   C,CP_WRITE                         ; Select sequential record-write function 21.
    CALL CP_BDOS                            ; Append this complete output record.
    OR   A                                  ; Zero denotes a successful BDOS write.
    JR   NZ,.WRITEBAD                       ; Preserve old output on write failure.
    LD   HL,(MAT_WPTR)                      ; Read the current output-buffer address.
    LD   DE,128                             ; Every CP/M record contains exactly 128 bytes.
    ADD  HL,DE                              ; Advance to the next block in this window.
    LD   (MAT_WPTR),HL                      ; Retain its address for the next write.
    LD   HL,(MAT_WCNT)                      ; Reload the remaining window length.
    OR   A                                  ; Clear carry before subtracting one record.
    SBC  HL,DE                              ; Account for the record written above.
    LD   (MAT_WCNT),HL                      ; Retain the nonnegative aligned remainder.
    JR   .RECLOOP                           ; Continue until this window is appended.
.WRITTEN: ; Return after writing the whole window.
    XOR  A                                  ; Return success after all records were written.
    RET                                     ; The caller can release and reuse the window.
.WRITEBAD: ; Propagate a record-write failure.
    JP   .FAILURE                           ; Leave cleanup and rollback to HS_ABORT.

; Finalise the temp file, discard the spool, and publish only after success.

.CLOSE: ; Close final output and discard the private spool.
    LD   DE,CP_FCB                          ; Close the completed output temporary file.
    LD   C,CP_CLOSE                         ; Select CP/M close-file function 16.
    CALL CP_BDOS                            ; Flush its last full record to disk.
    INC  A                                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,.FAILURE                         ; The prior output remains untouched.
    XOR  A                                  ; No open output file remains for abort to close.
    LD   (PUB_OPEN),A                       ; Clear ownership before the next transaction.
    CALL PUB_BAK                            ; Select the private ASO spool name.
    LD   DE,CP_FCB                          ; Pass its FCB to CP/M's delete service.
    LD   C,CP_ERASE                         ; Remove the spool before $$B changes owner.
    CALL CP_BDOS                            ; Discard the internal stream after replay.
    OR   A                                  ; A zero result means the spool was removed.
    JR   NZ,.FAILURE                        ; Do not publish if internal cleanup failed.
    XOR  A                                  ; $$B is free for the output transaction now.
    LD   (MAT_OWNS),A                       ; Keep output backup separate from the spool.
    CALL PUB_SWAP                           ; Atomically replace the selected output file.
    RET                                     ; Preserve publication's carry result.

; Common fail-closed result. HS_ABORT removes temp/spool and restores backup.

.INVALID: ; Reject malformed operation data.
.FAILURE: ; Return failure for the driver to abort.
    LD   A,1                                ; Return the ordinary build-failure code.
    SCF                                     ; Prevent the output service from committing.
    RET                                     ; The driver will enter HS_ABORT immediately.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Remove an internal spool during abort. leave an old output in $$B alone.

MAT_DROP: ; Remove the private spool without deleting an output backup.
    CALL PUB_BAK                            ; Select the private spool's reserved filename.
    LD   DE,CP_FCB                          ; Pass the spool name to the delete service.
    LD   C,CP_ERASE                         ; Select CP/M delete-file function 19.
    CALL CP_BDOS                            ; Remove the failed internal operation stream.
    XOR  A                                  ; BAK is no longer owned by the materialiser.
    LD   (MAT_OWNS),A                       ; Preserve any later output-backup ownership.
    RET                                     ; Return to the resident abort/restore sequence.
