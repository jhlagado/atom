; Replay one CP/M ASO spool into bounded sequential output windows.
;
; The source has already been assembled once. Each pass reopens the private
; ASO file, validates its ordered records and applies only the operations
; intersecting the current output window. Output records are always written
; sequentially. no floppy seek is needed to apply a PATCH.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Convert the internal ASO spool into COM, BIN or HEX, then publish the temp.

matRun: ; Replay the committed spool into output windows.
    LD   A,(asoFlags)                       ; Read the committed high-water endpoint form.
    BIT  1,A                                ; Is high water the mathematical endpoint $10000?
    JR   Z,.highWord                        ; Otherwise use its ordinary 16-bit address.
    LD   HL,asoCap                          ; $10000 minus the $0100 COM origin.
    JR   .lenReady                          ; The maximum logical image is exactly $FF00.
.highWord: ; Compute length from ordinary high water.
    LD   HL,(asoHigh)                       ; Load the ordinary exclusive high-water.
    LD   DE,(asoOrg)                        ; Subtract the ASO image origin.
    OR   A                                  ; Clear borrow before the subtraction.
    SBC  HL,DE                              ; Convert the absolute endpoint to a file length.
.lenReady: ; Choose exact or physical-record-rounded length.
    LD   A,(pubKind)                        ; Check whether this output is textual HEX.
    CP   2                                  ; HEX stores exact bytes rather than CP/M records.
    JR   Z,.exact                           ; Keep the exact unpadded length.
    LD   DE,127                             ; Round the last logical record up to 128 bytes.
    ADD  HL,DE                              ; The extra bytes use the ASO fill value.
    LD   A,L                                ; Keep only bit seven of the rounded low byte.
    AND  $80                                ; Clear the seven bits below a record boundary.
    LD   L,A                                ; Retain the rounded low byte.
.exact: ; Initialise replay and publication state.
    LD   (matLeft),HL                       ; Count HEX or padded binary bytes.
    XOR  A                                  ; Begin writing the first output window.
    LD   (matFill),A                        ; The native BEGIN hook declares zero fill.
    LD   (matWOff),A                        ; Its image-relative offset is zero.
    LD   (matWOff+1),A                      ; Clear the offset's high byte as well.
    CALL pubTemp                            ; Name the tentative output file.
    LD   DE,cpFcb+12                        ; Reset all mutable FCB state before MAKE.
    XOR  A                                  ; CP/M expects cleared record and extent fields.
    LD   B,24                               ; Count the remaining FCB bytes.
    CALL pubFill                            ; Keep the selected filename and clear its tail.
    LD   DE,cpFcb                           ; Pass the tentative output FCB to BDOS.
    LD   C,cpMake                           ; Select CP/M make-file function 22.
    CALL cpBdos                             ; Create the output only after ASO COMMIT.
    INC  A                                  ; Convert BDOS's $FF failure result to zero.
    JP   Z,.failure                         ; Keep the old destination untouched.
    LD   A,1                                ; The abort path now owns the open temp file.
    LD   (pubOpen),A                        ; Retain its cleanup state.
    LD   A,(pubKind)                        ; Select the representation's output encoder.
    CP   2                                  ; Format two is Intel HEX.
    JR   NZ,.winLoop                        ; Binary outputs need no HEX buffer setup.
    CALL hexReset                           ; Start one HEX stream before its replay windows.
.winLoop: ; Process each output window.
    LD   HL,(matLeft)                       ; Read the rounded output bytes remaining.
    LD   A,H                                ; Check the high byte.
    OR   L                                  ; Zero means the empty or final window is done.
    JR   NZ,.nonEmpty                       ; Continue when a window remains to write.
    LD   HL,(matWOff)                       ; Did any nonempty output window complete?
    LD   A,H                                ; Check its high byte.
    OR   L                                  ; Zero distinguishes a genuinely empty image.
    JR   NZ,.dataDone                       ; Nonempty output passed validation.
    CALL .replay                            ; Validate an empty stream through physical EOF.
    RET  C                                  ; Do not publish a malformed empty stream.
.dataDone: ; Finish the chosen output representation.
    LD   A,(pubKind)                        ; Select the format's finalisation path.
    CP   2                                  ; Intel HEX needs EOF and final record padding.
    JP   NZ,.close                          ; Binary output is already complete.
    CALL hexClose                           ; Finish the HEX stream through sequential BDOS.
    RET  C                                  ; Preserve the old output after a write failure.
    JP   .close                             ; Close only after HEX is complete.
.nonEmpty: ; Choose a bounded nonempty window.
    LD   HL,matLimit                        ; Load the exclusive replay-window ceiling.
    LD   DE,matWin                          ; Subtract the aligned start after overlay code.
    OR   A                                  ; Clear borrow before measuring available memory.
    SBC  HL,DE                              ; Form this build's measured window capacity.
    EX   DE,HL                              ; Keep the capacity in DE for comparison.
    LD   HL,(matLeft)                       ; Reload the rounded output size.
    OR   A                                  ; Clear carry before comparing window and output.
    SBC  HL,DE                              ; Is another full window left?
    JR   NC,.fullWin                        ; Use the complete buffer when it fits.
    LD   HL,(matLeft)                       ; The final window uses the remainder.
    JR   .winReady                          ; Its length remains record-aligned.
.fullWin: ; Use the complete available window.
    LD   HL,matLimit                        ; Load the ceiling used by the window calculation.
    LD   DE,matWin                          ; Load the aligned start after materialiser code.
    OR   A                                  ; Clear borrow before taking the difference.
    SBC  HL,DE                              ; Recover the record-aligned window size.
.winReady: ; Fill and replay the chosen byte range.
    LD   (matWLen),HL                       ; Save this pass's physical byte count.
    LD   (matWCnt),HL                       ; Initialize the fill loop length.
    CALL .fillWin                           ; Restore untouched gaps and reservations.
    CALL .replay                            ; Reopen and validate the complete ASO stream.
    RET  C                                  ; hsAbort removes tentative data.
    LD   A,(pubKind)                        ; Choose raw records or Intel HEX conversion.
    CP   2                                  ; Only HEX consumes the replay window as text.
    JR   NZ,.binary                         ; COM and BIN append this window unchanged.
    LD   HL,matWin                          ; Set the HEX input cursor.
    LD   (pubPos),HL                        ; Reset its window source cursor.
    LD   HL,(matWLen)                       ; Read the exact logical segment length.
    LD   (pubLeft),HL                       ; Do not render binary record padding.
    LD   HL,(asoOrg)                        ; Start with the image's absolute base address.
    LD   DE,(matWOff)                       ; Add this replay window's relative offset.
    ADD  HL,DE                              ; Form this window's first target address.
    LD   (hexAddr),HL                       ; Reset the helper for this segment.
    CALL hexSeg                             ; Emit checksummed HEX records.
    JR   .nextWin                           ; Advance to the next output window.
.binary: ; Write COM or BIN records directly.
    CALL .writeWin                          ; Append this window as sequential CP/M records.
    RET  C                                  ; Preserve the old destination on write failure.
.nextWin: ; Advance output length and window offset.
    LD   HL,(matLeft)                       ; Reload total output bytes still unwritten.
    LD   DE,(matWLen)                       ; Read the completed window's length.
    OR   A                                  ; Clear borrow before reducing the remaining size.
    SBC  HL,DE                              ; Account for this full set of output records.
    LD   (matLeft),HL                       ; Retain the count for the next window.
    LD   HL,(matWOff)                       ; Read the next relative window start.
    ADD  HL,DE                              ; Advance by the length just materialised.
    LD   (matWOff),HL                       ; Keep the next pass aligned with records.
    JP   .winLoop                           ; Continue or close after the final window.

; Fill the selected window before applying any IMAGE and PATCH operations.

.fillWin: ; Initialise gaps before replaying operations.
    LD   A,(matFill)                        ; Use the header's validated gap-fill byte.
    LD   HL,matWin                          ; Select the first byte of the destination window.
    LD   (HL),A                             ; Seed LDIR with the selected fill value.
    LD   DE,matWin+1                        ; Point one byte beyond the seed value.
    LD   BC,(matWLen)                       ; Load the complete window length.
    DEC  BC                                 ; The seed byte is already initialised.
    LD   A,B                                ; Does any byte remain after the seed?
    OR   C                                  ; A one-byte window needs no LDIR operation.
    RET  Z                                  ; Avoid treating BC=0 as 65,536 copies.
    LD   HL,matWin                          ; Point LDIR at that first initialised byte.
    LDIR                                    ; Fill only the bytes that will be written.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; Continue with a fresh spool replay.

; Open, parse and close one complete operation stream for this window.

.replay: ; Rewind and validate the spool for this window.
    XOR  A                                  ; Reset the byte reader and record-order state.
    LD   (matHave),A                        ; The first byte must refill the input record.
    LD   (matPrev),A                        ; No previous IMAGE can constrain ordering.
    LD   (matPLen),A                        ; Clear the prior run's canonical length.
    LD   (matImTop),A                       ; Start with an ordinary endpoint.
    LD   HL,(asoOrg)                        ; The empty initial extent starts at origin.
    LD   (matImEnd),HL                      ; Use this endpoint to validate PATCH records.
    LD   DE,matFcb+12                       ; Reset the sequential reader's mutable FCB tail.
    XOR  A                                  ; Start at extent and record zero.
    LD   B,24                               ; Clear all FCB control and random-record fields.
    CALL pubFill                            ; Preserve the spool filename while rewinding it.
    LD   DE,matFcb                          ; Pass the relocated spool FCB to CP/M OPEN.
    LD   C,cpOpen                           ; Select sequential file-open function 15.
    CALL cpBdos                             ; Reopen the committed spool from record zero.
    INC  A                                  ; Convert BDOS's $FF not-found result to zero.
    JR   Z,.badPass                         ; A missing spool invalidates this output.
    LD   A,1                                ; hsAbort owns the currently open spool FCB.
    LD   (matOpen),A                        ; Track the open spool for abort cleanup.
    CALL .header                            ; Check signature, version, origin and fill.
    RET  C                                  ; Leave the reader open for the common abort path.
    CALL .records                           ; Apply records and require a valid END and EOF.
    RET  C                                  ; Do not write a window from an invalid stream.
    LD   DE,matFcb                          ; Close the validated spool pass.
    LD   C,cpClose                          ; Select CP/M close-file function 16.
    CALL cpBdos                             ; Release the reader before another window pass.
    INC  A                                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,.badPass                         ; A failed close must abort publication.
    XOR  A                                  ; Clear the open flag after a successful close.
    LD   (matOpen),A                        ; Clear the flag after closing the spool.
    RET                                     ; Return a verified window with carry clear.
.badPass: ; Reject a failed replay pass.
    JP   .failure                           ; Let hsAbort remove both temporary files.

; Check the fixed ASO v1 header against the state retained by its writer.

.header: ; Validate the fixed seven-byte ASO header.
    CALL .nextByte                          ; Read the first signature byte.
    RET  C                                  ; A short file cannot start a valid header.
    CP   'A'                                ; Require the exact ASCII signature.
    JP   NZ,.invalid                        ; Reject any different magic byte.
    CALL .nextByte                          ; Read the second signature byte.
    RET  C                                  ; Reject EOF before the header completes.
    CP   'S'                                ; Continue the three-byte signature check.
    JP   NZ,.invalid                        ; Reject a changed signature.
    CALL .nextByte                          ; Read the final signature byte.
    RET  C                                  ; A truncated signature is invalid.
    CP   'O'                                ; Complete the required ASCII magic.
    JP   NZ,.invalid                        ; Reject a different format.
    CALL .nextByte                          ; Read the ASO version.
    RET  C                                  ; Require a complete header.
    CP   1                                  ; This adapter implements ASO version one only.
    JP   NZ,.invalid                        ; Refuse unknown versions.
    CALL .nextWord                          ; Read the little-endian target origin.
    RET  C                                  ; Propagate a truncated origin field.
    LD   DE,(asoOrg)                        ; Compare with the origin supplied at BEGIN.
    OR   A                                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE                              ; Did the stream retain its declared origin?
    JP   NZ,.invalid                        ; A changed origin must not redirect output.
    CALL .nextByte                          ; Read the stream's fill byte.
    RET  C                                  ; Reject an incomplete fixed header.
    LD   (matFill),A                        ; Retain the value used to initialise this window.
    OR   A                                  ; The CP/M assembler currently declares zero fill.
    JP   NZ,.invalid                        ; Do not materialise altered fill semantics.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; The stream now has a validated v1 header.

; Parse chronological IMAGE/PATCH records through one mandatory END.

.records: ; Dispatch IMAGE, PATCH or END records.
    CALL .nextByte                          ; Read a record kind or the END marker.
    JP   C,.invalid                         ; Physical EOF before END is invalid.
    OR   A                                  ; Record kind zero is the only valid terminator.
    JP   Z,.endRec                          ; Validate final geometry and record padding.
    CP   1                                  ; Record kind one denotes IMAGE.
    JR   Z,.image                           ; Parse its address, length and bytes.
    CP   2                                  ; Record kind two denotes PATCH.
    JP   Z,.patch                           ; Parse its replacement bytes.
    JP   .invalid                           ; Reject every unknown v1 record kind.

; Validate an IMAGE range and apply its bytes if they intersect this window.

.image: ; Validate and consume one IMAGE record.
    LD   A,(matImTop)                       ; No IMAGE may follow an endpoint at $10000.
    OR   A                                  ; Check the seventeenth endpoint bit.
    JP   NZ,.invalid                        ; Reject a range beyond the address space.
    CALL .nextWord                          ; Read the absolute starting address.
    JP   C,.invalid                         ; Reject a truncated IMAGE address.
    LD   (matAddr),HL                       ; Retain the encoded start for checks.
    LD   DE,(asoOrg)                        ; Load the minimum address of this output.
    OR   A                                  ; Clear carry before subtracting the origin.
    SBC  HL,DE                              ; Convert the target address to an image offset.
    JP   C,.invalid                         ; Reject IMAGE bytes before the stream origin.
    LD   (matROff),HL                       ; Save the relative operation position.
    CALL .nextByte                          ; Read the one-byte IMAGE payload length.
    JP   C,.invalid                         ; Reject a truncated record header.
    OR   A                                  ; Zero is not a valid IMAGE record length.
    JP   Z,.invalid                         ; Require one through 128 data bytes.
    CP   129                                ; The canonical maximum is one physical record.
    JP   NC,.invalid                        ; Reject an excessive payload.
    LD   (matRLen),A                        ; Retain its validated length.
    LD   (matRCnt),A                        ; Count payload bytes as they are consumed.
    CALL .inOrder                           ; Enforce nonoverlap and canonical runs.
    RET  C                                  ; Stop before applying any invalid range.
    CALL .payload                           ; Consume the payload and update this window.
    RET  C                                  ; A short payload invalidates the whole spool.
    LD   A,1                                ; Retain IMAGE as the preceding record kind.
    LD   (matPrev),A                        ; The next adjacent short IMAGE is invalid.
    LD   A,(matRLen)                        ; Retain the run length for that check.
    LD   (matPLen),A                        ; A full 128-byte run may be followed.
    JR   .records                           ; Continue parsing until END.

; Validate that IMAGE ranges ascend, do not overlap and use canonical runs.

.inOrder: ; Check ascending IMAGE order and coalescing.
    LD   HL,(matAddr)                       ; Load the candidate absolute address.
    LD   DE,(matImEnd)                      ; Load the greatest preceding IMAGE endpoint.
    OR   A                                  ; Clear carry before comparing unsigned addresses.
    SBC  HL,DE                              ; Descending or overlapping data borrows here.
    JP   C,.invalid                         ; Reject any IMAGE before the previous endpoint.
    JR   NZ,.range                          ; A gap starts a new canonical IMAGE run.
    LD   A,(matPrev)                        ; Check whether an IMAGE preceded this one.
    CP   1                                  ; PATCH separates IMAGE runs and resets this rule.
    JR   NZ,.range                          ; Adjacent bytes after PATCH remain valid.
    LD   A,(matPLen)                        ; Read the preceding IMAGE's run length.
    CP   128                                ; Only a maximal run may be extended adjacently.
    JP   C,.invalid                         ; Reject split contiguous IMAGE records.
.range: ; Compute and validate the IMAGE endpoint.
    LD   HL,(matROff)                       ; Load the start relative to origin.
    LD   A,(matRLen)                        ; Add the validated payload size.
    LD   E,A                                ; Extend the byte length into DE.
    LD   D,0                                ; Complete the 16-bit length.
    ADD  HL,DE                              ; Form the new relative image endpoint.
    LD   (matREnd),HL                       ; Retain it for PATCH and END validation.
    LD   HL,(matAddr)                       ; Recompute the absolute exclusive end.
    ADD  HL,DE                              ; Include this IMAGE's byte length.
    JR   NC,.iEndWord                       ; No wrap gives an ordinary endpoint.
    LD   A,H                                ; A wrapped range must end exactly at zero.
    OR   L                                  ; Reject lengths that cross beyond $10000.
    JP   NZ,.invalid                        ; Do not permit a wrapped endpoint past memory.
    LD   A,1                                ; Retain the mathematical $10000 endpoint.
    LD   (matImTop),A                       ; No later IMAGE address can be represented.
    LD   HL,0                               ; Store zero as the endpoint's low word.
    JR   .saveEnd                           ; Commit the checked endpoint.
.iEndWord: ; Store an ordinary IMAGE endpoint.
    XOR  A                                  ; Mark an ordinary 16-bit exclusive endpoint.
    LD   (matImTop),A                       ; Clear any endpoint flag.
.saveEnd: ; Publish the checked IMAGE extent.
    LD   (matImEnd),HL                      ; Update the greatest IMAGE endpoint.
    XOR  A                                  ; Return with carry clear.
    RET                                     ; Allow the validated payload to be consumed.

; Validate a byte/word PATCH and apply its final replacement values.

.patch: ; Validate and consume a byte or word PATCH.
    CALL .nextWord                          ; Read the absolute target address.
    JP   C,.invalid                         ; A missing address cannot be a valid PATCH.
    LD   (matAddr),HL                       ; Retain the target for range checks.
    LD   DE,(asoOrg)                        ; Load the declared output origin.
    OR   A                                  ; Clear carry before subtracting origin.
    SBC  HL,DE                              ; Convert the target to an image-relative offset.
    JP   C,.invalid                         ; Reject a patch before the logical image.
    LD   (matROff),HL                       ; Save the first replacement position.
    CALL .nextByte                          ; Read a byte or word patch length.
    JP   C,.invalid                         ; Reject a truncated PATCH header.
    CP   1                                  ; The one-byte case is canonical.
    JR   Z,.sizeOk                          ; Keep its length unchanged.
    CP   2                                  ; The only other accepted length is two.
    JP   NZ,.invalid                        ; Reject empty or longer replacement records.
.sizeOk: ; Retain the accepted PATCH payload length.
    LD   (matRLen),A                        ; Retain the validated payload length.
    LD   (matRCnt),A                        ; Count replacement bytes during reading.
    LD   HL,(matAddr)                       ; Form the exclusive absolute endpoint.
    LD   E,A                                ; Extend the patch size into DE.
    LD   D,0                                ; Complete the 16-bit addition operand.
    ADD  HL,DE                              ; Detect a patch that wraps past $10000.
    JR   NC,.noWrap                         ; No carry gives an ordinary endpoint.
    LD   A,H                                ; A carry is legal only for the exact endpoint.
    OR   L                                  ; The low word must wrap to zero.
    JP   NZ,.invalid                        ; Reject a PATCH beyond address space.
    LD   A,1                                ; Mark mathematical endpoint $10000.
    LD   (matRTop),A                        ; Compare it with the IMAGE endpoint.
    JR   .compare                           ; Finish the bounded-image check.
.noWrap: ; Store an ordinary PATCH endpoint.
    XOR  A                                  ; This PATCH has an ordinary word endpoint.
    LD   (matRTop),A                        ; Clear the temporary endpoint flag.
    LD   (matREnd),HL                       ; Keep its absolute endpoint for comparison.
.compare: ; Require the PATCH to fit preceding IMAGE extent.
    LD   A,(matImTop)                       ; Read the greatest preceding IMAGE endpoint.
    OR   A                                  ; An endpoint image contains every valid address.
    JR   NZ,.apply                          ; Any in-range PATCH fits below $10000.
    LD   A,(matRTop)                        ; Compare the PATCH endpoint's top bit.
    OR   A                                  ; A top PATCH cannot fit below a word endpoint.
    JP   NZ,.invalid                        ; Reject a PATCH beyond preceding IMAGE data.
    LD   HL,(matREnd)                       ; Load the ordinary PATCH endpoint.
    LD   DE,(matImEnd)                      ; Load the current IMAGE exclusive end.
    OR   A                                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE                              ; Is the complete replacement within prior IMAGE?
    JR   C,.apply                           ; A lower endpoint also permits fill-gap PATCH.
    JR   Z,.apply                           ; Equality is the greatest preceding IMAGE end.
    JP   .invalid                           ; Reject a PATCH that reaches future bytes.
.apply: ; Apply a validated PATCH in stream order.
    CALL .payload                           ; Consume and apply the final patch bytes.
    RET  C                                  ; Do not accept a truncated replacement payload.
    LD   A,2                                ; A PATCH breaks adjacent IMAGE canonical runs.
    LD   (matPrev),A                        ; Retain it for the next record's rule.
    LD   A,(matRLen)                        ; Preserve the exact accepted patch length.
    LD   (matPLen),A                        ; The value is irrelevant after PATCH.
    JP   .records                           ; Continue through the mandatory END record.

; Read a payload byte and apply it only when its offset lies in this window.

.payload: ; Consume every payload byte for this pass.
    LD   A,(matRCnt)                        ; Check how many payload bytes remain.
    OR   A                                  ; Zero means the record is complete.
    JR   Z,.consumed                        ; Return without reading the next kind.
    CALL .nextByte                          ; Consume one byte from the sequential ASO file.
    RET  C                                  ; Reject truncated record payloads.
    LD   (matByte),A                        ; Save the byte while checking its destination.
    LD   HL,(matROff)                       ; Load this payload byte's image offset.
    LD   DE,(matWOff)                       ; Load the current window's relative start.
    OR   A                                  ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                              ; Is the record byte before this output window?
    JR   C,.skip                            ; Older records are consumed but not reapplied.
    PUSH HL                                 ; Preserve its nonnegative offset into the window.
    LD   DE,(matWLen)                       ; Load this window's exclusive size.
    OR   A                                  ; Clear carry before comparing the offset.
    SBC  HL,DE                              ; Is the byte at or beyond the window's end?
    POP  HL                                 ; Recover its relative position, preserving flags.
    JR   NC,.skip                           ; A later pass will apply this record.
    LD   DE,matWin                          ; Convert the window-relative offset to a pointer.
    ADD  HL,DE                              ; Address the byte to replace in the RAM window.
    LD   A,(matByte)                        ; Reload the current IMAGE or PATCH value.
    LD   (HL),A                             ; Apply this operation in stream order.
.skip: ; Advance after applying or skipping one byte.
    LD   HL,(matROff)                       ; Advance to the next payload address.
    INC  HL                                 ; Each record payload is a consecutive byte run.
    LD   (matROff),HL                       ; Retain its image-relative position.
    LD   HL,matRCnt                         ; Address the remaining payload counter.
    DEC  (HL)                               ; Consume the byte read above.
    JR   .payload                           ; Continue until every encoded byte is consumed.
.consumed: ; Finish a completely consumed payload.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; The caller can advance to the next record.

; END must match the writer's committed geometry. padding is exactly $1A.

.endRec: ; Validate END against retained COMMIT geometry.
    CALL .nextWord                          ; Read the high-water word.
    JP   C,.invalid                         ; END requires all six geometry bytes.
    LD   DE,(asoHigh)                       ; Compare with the writer's checked endpoint.
    OR   A                                  ; Clear carry before the word comparison.
    SBC  HL,DE                              ; Did the stream retain the committed high water?
    JP   NZ,.invalid                        ; Refuse altered geometry.
    CALL .nextByte                          ; Read high water's seventeenth bit.
    JP   C,.invalid                         ; Reject a truncated endpoint.
    LD   B,A                                ; Preserve the encoded high-water top byte.
    LD   A,(asoFlags)                       ; Read the writer's validated COMMIT flags.
    AND  2                                  ; Isolate the high-water endpoint bit.
    RRCA                                    ; Move that endpoint marker into bit zero.
    CP   B                                  ; Require exact agreement with the checked value.
    JP   NZ,.invalid                        ; Reject endpoints other than 0 or exactly $10000.
    CALL .nextWord                          ; Read the final-cursor word.
    JP   C,.invalid                         ; Require the rest of the END record.
    LD   DE,(asoLast)                       ; Compare with the committed final cursor.
    OR   A                                  ; Clear borrow for this exact equality check.
    SBC  HL,DE                              ; Did the cursor survive serialization unchanged?
    JP   NZ,.invalid                        ; Refuse a changed final position.
    CALL .nextByte                          ; Read the final cursor's seventeenth bit.
    JP   C,.invalid                         ; END is incomplete without the final byte.
    LD   B,A                                ; Preserve its encoded endpoint marker.
    LD   A,(asoFlags)                       ; Read the writer's cursor endpoint bit.
    AND  1                                  ; Keep only the cursor's mathematical top bit.
    CP   B                                  ; Require exact agreement with the COMMIT state.
    JP   NZ,.invalid                        ; Reject a cursor endpoint that changed on disk.
    LD   A,(asoFlags)                       ; Read whether high water is exactly $10000.
    AND  2                                  ; The top endpoint contains every valid IMAGE end.
    JR   NZ,.imageOk                        ; The maximum valid IMAGE end is $10000.
    LD   A,(matImTop)                       ; Otherwise IMAGE end must also fit in 16 bits.
    OR   A                                  ; Is its exclusive endpoint $10000?
    JP   NZ,.invalid                        ; That exceeds any ordinary committed high water.
    LD   HL,(asoHigh)                       ; Load the ordinary committed endpoint.
    LD   DE,(matImEnd)                      ; Load the greatest parsed IMAGE endpoint.
    OR   A                                  ; Clear borrow before checking endpoint ordering.
    SBC  HL,DE                              ; High water minus IMAGE end must be nonnegative.
    JP   C,.invalid                         ; Reject IMAGE data beyond the committed geometry.
.imageOk: ; Check final-record padding and physical EOF.
    LD   A,(matHave)                        ; Check bytes remaining in the final record.
    OR   A                                  ; Zero means END ended at a record boundary.
    JR   Z,.eof                             ; Verify there is no extra physical record.
.padLoop: ; Consume only SUB padding after END.
    CALL .nextByte                          ; Read one remaining byte from this same record.
    JP   C,.invalid                         ; The current physical record must be complete.
    CP   $1A                                ; The CP/M writer pads only with SUB bytes.
    JP   NZ,.invalid                        ; Reject data after END or wrong padding.
    LD   A,(matHave)                        ; Is the final record now consumed?
    OR   A                                  ; Zero permits only a subsequent EOF response.
    JR   NZ,.padLoop                        ; Validate every remaining physical padding byte.
.eof: ; Require EOF immediately after the final record.
    CALL .fetch                             ; Ask whether another physical record exists.
    CP   1                                  ; Only end-of-file completes the stream.
    JP   NZ,.invalid                        ; Reject extra records and read failures.
    XOR  A                                  ; Return a verified END with carry clear.
    RET                                     ; The replay may now close the spool.

; Read one little-endian word through the bounded sequential byte reader.

.nextWord: ; Decode a little-endian word from the spool.
    CALL .nextByte                          ; Read the low byte first.
    RET  C                                  ; Propagate a truncated field.
    LD   (matByte),A                        ; Retain it while fetching the high byte.
    CALL .nextByte                          ; Read the high byte.
    RET  C                                  ; Do not return a partial word.
    LD   H,A                                ; Place the high byte in H.
    LD   A,(matByte)                        ; Recover the low byte.
    LD   L,A                                ; Complete the little-endian word in HL.
    XOR  A                                  ; Return success with carry clear.
    RET                                     ; HL contains the decoded u16 value.

; Refill the one-record input buffer and return the next ASO byte in A.

.nextByte: ; Read a byte or refill the physical record.
    LD   A,(matHave)                        ; Check for bytes already in the DMA record.
    OR   A                                  ; A nonzero count avoids another BDOS read.
    JR   NZ,.buffered                       ; Consume the buffered byte.
    CALL .fetch                             ; Read the next physical ASO record.
    OR   A                                  ; BDOS zero denotes a successful record read.
    JR   NZ,.readFail                       ; EOF or a disk error before END is invalid.
    LD   A,128                              ; A successful BDOS read supplies one full record.
    LD   (matHave),A                        ; Retain its physical size.
    LD   HL,matRec                          ; Point at the first byte from the DMA transfer.
    LD   (matPtr),HL                        ; Retain the next byte to consume.
.buffered: ; Consume a byte already buffered.
    LD   HL,(matPtr)                        ; Address the current byte in the record.
    LD   A,(HL)                             ; Read one encoded header or payload byte.
    INC  HL                                 ; Advance the bounded input cursor.
    LD   (matPtr),HL                        ; Retain its updated record position.
    LD   HL,matHave                         ; Address the remaining physical-byte count.
    DEC  (HL)                               ; Mark the byte consumed exactly once.
    OR   A                                  ; Return the byte with carry clear.
    RET                                     ; A contains the next ASO stream byte.
.readFail: ; Report a failed physical record read.
    SCF                                     ; Signal EOF or disk failure to the parser.
    RET                                     ; No incomplete stream can be materialised.

; Read one raw physical record, leaving BDOS's status in A.

.fetch: ; Fetch one sequential CP/M record.
    LD   DE,matRec                          ; Use the relocated record buffer.
    LD   C,cpSetDma                         ; Select CP/M's set-DMA-address service.
    CALL cpBdos                             ; Install the reader-owned transfer buffer.
    LD   DE,matFcb                          ; Pass the relocated sequential spool FCB.
    LD   C,cpRead                           ; Select CP/M sequential record-read function 20.
    JP   cpBdos                             ; Return zero, EOF one, or the BDOS error code.

; Append this aligned window using only sequential record writes.

.writeWin: ; Append this window to the tentative output.
    LD   HL,matWin                          ; Point at the first output record in the window.
    LD   (matWPtr),HL                       ; Retain the current DMA record address.
    LD   HL,(matWLen)                       ; Load the number of bytes to emit.
    LD   (matWCnt),HL                       ; Count output records by their byte size.
.recLoop: ; Write each complete 128-byte output record.
    LD   HL,(matWCnt)                       ; Check whether the window is fully written.
    LD   A,H                                ; Test the high byte.
    OR   L                                  ; Zero ends this output window.
    JR   Z,.written                         ; Replay the next window or finish.
    LD   DE,(matWPtr)                       ; Select the next complete 128-byte block.
    LD   C,cpSetDma                         ; Point CP/M's DMA at that output block.
    CALL cpBdos                             ; Install the sequential write buffer.
    LD   DE,cpFcb                           ; Pass the tentative output file's FCB.
    LD   C,cpWrite                          ; Select sequential record-write function 21.
    CALL cpBdos                             ; Append this complete output record.
    OR   A                                  ; Zero denotes a successful BDOS write.
    JR   NZ,.writeBad                       ; Preserve old output on write failure.
    LD   HL,(matWPtr)                       ; Read the current output-buffer address.
    LD   DE,128                             ; Every CP/M record contains exactly 128 bytes.
    ADD  HL,DE                              ; Advance to the next block in this window.
    LD   (matWPtr),HL                       ; Retain its address for the next write.
    LD   HL,(matWCnt)                       ; Reload the remaining window length.
    OR   A                                  ; Clear carry before subtracting one record.
    SBC  HL,DE                              ; Account for the record written above.
    LD   (matWCnt),HL                       ; Retain the nonnegative aligned remainder.
    JR   .recLoop                           ; Continue until this window is appended.
.written: ; Return after writing the whole window.
    XOR  A                                  ; Return success after all records were written.
    RET                                     ; The caller can release and reuse the window.
.writeBad: ; Propagate a record-write failure.
    JP   .failure                           ; Leave cleanup and rollback to hsAbort.

; Finalise the temp file, discard the spool, and publish only after success.

.close: ; Close final output and discard the private spool.
    LD   DE,cpFcb                           ; Close the completed output temporary file.
    LD   C,cpClose                          ; Select CP/M close-file function 16.
    CALL cpBdos                             ; Flush its last full record to disk.
    INC  A                                  ; Convert BDOS's $FF close failure to zero.
    JR   Z,.failure                         ; The prior output remains untouched.
    XOR  A                                  ; No open output file remains for abort to close.
    LD   (pubOpen),A                        ; Clear ownership before the next transaction.
    CALL pubBak                             ; Select the private ASO spool name.
    LD   DE,cpFcb                           ; Pass its FCB to CP/M's delete service.
    LD   C,cpErase                          ; Remove the spool before $$B changes owner.
    CALL cpBdos                             ; Discard the internal stream after replay.
    OR   A                                  ; A zero result means the spool was removed.
    JR   NZ,.failure                        ; Do not publish if internal cleanup failed.
    XOR  A                                  ; $$B is free for the output transaction now.
    LD   (matOwns),A                        ; Keep output backup separate from the spool.
    CALL pubSwap                            ; Atomically replace the selected output file.
    RET                                     ; Preserve publication's carry result.

; Common fail-closed result. hsAbort removes temp/spool and restores backup.

.invalid: ; Reject malformed operation data.
.failure: ; Return failure for the driver to abort.
    LD   A,1                                ; Return the ordinary build-failure code.
    SCF                                     ; Prevent the output service from committing.
    RET                                     ; The driver will enter hsAbort immediately.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Remove an internal spool during abort. leave an old output in $$B alone.

matDrop: ; Remove the private spool without deleting an output backup.
    CALL pubBak                             ; Select the private spool's reserved filename.
    LD   DE,cpFcb                           ; Pass the spool name to the delete service.
    LD   C,cpErase                          ; Select CP/M delete-file function 19.
    CALL cpBdos                             ; Remove the failed internal operation stream.
    XOR  A                                  ; BAK is no longer owned by the materialiser.
    LD   (matOwns),A                        ; Preserve any later output-backup ownership.
    RET                                     ; Return to the resident abort/restore sequence.
