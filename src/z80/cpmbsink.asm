;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Replace only the active INCBIN line's content. preserve its source offsets.

BIN_EDIT: ; Lower active INCBIN text without changing source offsets.
    LD   A,(BIN_LIVE)                   ; Preflight must publish a full metadata table.
    OR   A                              ; Zero means ordinary source has no rewrite rows.
    JR   NZ,.READY                      ; Continue with the table cursor when enabled.
    LD   A,(PP_TMP)                     ; Restore the source provider's original byte.
    OR   A                              ; This path never reports a binary I/O error.
    RET                                 ; Return ordinary source unchanged.
.READY: ; Synchronise the filter cursor with source position.
    LD   A,(SRC_PART)                   ; Read the currently selected dependency ordinal.
    LD   E,A                            ; Keep it while comparing the last filter call.
    LD   A,(BIN_FORD)                   ; A part change restarts the row cursor.
    CP   E                              ; Does the cached cursor belong to this part?
    JR   NZ,.RESET                      ; Reset before searching another source file.
    LD   HL,(PP_POS)                    ; Load this byte's logical source position.
    LD   DE,(BIN_FPOS)                  ; Compare with the previous position.
    OR   A                              ; Clear borrow before the unsigned subtraction.
    SBC  HL,DE                          ; Did Atom request an earlier byte again?
    JR   C,.RESET                       ; Rewind the metadata cursor for a backward peek.
    JR   NC,.SAVEPOS                    ; Keep the cursor for repeated or forward reads.
.RESET: ; Restart metadata lookup after a part change or rewind.
    XOR  A                              ; Restart at metadata row zero.
    LD   (BIN_FIDX),A                   ; Clear the byte-sized row ordinal.
    LD   HL,BIN_TAB                     ; Select the first fixed-width entry.
    LD   (BIN_FPTR),HL                  ; Publish the reset row pointer.
.SAVEPOS: ; Retain the current filter source position.
    LD   A,(SRC_PART)                   ; Retain the part used for this lookup.
    LD   (BIN_FORD),A                   ; The next call can detect part changes.
    LD   HL,(PP_POS)                    ; Reload the requested source offset.
    LD   (BIN_FPOS),HL                  ; Peeks can detect a later rewind.
.ROW: ; Compare this source byte with metadata rows.
    LD   A,(BIN_FIDX)                   ; Read the next possible include row.
    LD   B,A                            ; Keep the row ordinal for the bound check.
    LD   A,(BIN_CNT)                    ; Read the number of complete metadata entries.
    CP   B                              ; Equality means every include line was passed.
    JR   Z,.ORIGINAL                    ; No remaining row can change this source byte.
    LD   HL,(BIN_FPTR)                  ; Address the current metadata row.
    LD   A,(HL)                         ; Read its dependency-ordered part ordinal.
    LD   E,A                            ; Keep the row's part for the unsigned compare.
    LD   A,(SRC_PART)                   ; Read the current source part.
    CP   E                              ; Is this byte before or after the row's part?
    JR   C,.ORIGINAL                    ; A later row leaves this earlier byte untouched.
    JR   NZ,.ADVANCE                    ; A previous part cannot match this source byte.
    INC  HL                             ; Advance to the INCBIN keyword's offset low byte.
    LD   E,(HL)                         ; Read the operation anchor's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the operation anchor word.
    LD   HL,(PP_POS)                    ; Load the current byte's source offset.
    OR   A                              ; Clear borrow before comparing source positions.
    SBC  HL,DE                          ; Is the current byte before the keyword?
    JR   C,.ORIGINAL                    ; Keep labels and indentation before INCBIN.
    LD   HL,(BIN_FPTR)                  ; Address the row's exclusive content end.
    LD   DE,3                           ; Its line-end word begins at byte three.
    ADD  HL,DE                          ; Point at the line-end low byte.
    LD   E,(HL)                         ; Read the exclusive content end's low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the line-end boundary.
    LD   HL,(PP_POS)                    ; Reload the byte being transformed.
    OR   A                              ; Clear borrow before the boundary comparison.
    SBC  HL,DE                          ; Has the source reached CR, LF or end of file?
    JP   NC,.ADVANCE                    ; Preserve endings and move beyond this metadata.
    LD   HL,(BIN_FPTR)                  ; Address the row's operation anchor.
    INC  HL                             ; Point to the start-offset low byte.
    LD   E,(HL)                         ; Read its low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the start-offset word.
    LD   HL,(PP_POS)                    ; Compute displacement from the keyword.
    OR   A                              ; Clear borrow to compute the replacement index.
    SBC  HL,DE                          ; HL now contains the source-byte displacement.
    LD   A,H                            ; Replacement text is only ten bytes long.
    OR   A                              ; A nonzero high byte is already beyond that span.
    JR   NZ,.SPACE                      ; Mask any remaining directive text with spaces.
    LD   A,L                            ; Read the small replacement-text displacement.
    CP   BIN_SPAN                       ; Check whether it names one of ten bytes.
    JR   NC,.SPACE                      ; The rest of the old line becomes whitespace.
    LD   C,A                            ; Preserve the replacement index across addition.
    LD   HL,(BIN_FPTR)                  ; Address this row's fixed DS replacement.
    LD   DE,BIN_DS                      ; Its replacement text starts at offset eighteen.
    ADD  HL,DE                          ; Point at the generated source text.
    LD   E,C                            ; Zero-extend the displacement in DE.
    LD   D,0                            ; Complete the offset pair.
    ADD  HL,DE                          ; Select the character corresponding to this byte.
    LD   A,(HL)                         ; Read one byte of the fixed-width DS statement.
    OR   A                              ; Return it with carry clear.
    RET                                 ; Keep every original byte offset unchanged.
.SPACE: ; Mask original operand text after the DS replacement.
    LD   A,' '                          ; Do not leave any original filename characters.
    OR   A                              ; Return harmless assembler whitespace.
    RET                                 ; The line ending stays outside the rewrite span.
.ADVANCE: ; Advance beyond a completed filter row.
    LD   HL,(BIN_FPTR)                  ; Select the row just passed by the source cursor.
    LD   DE,BIN_SIZE                    ; Every fixed row is the same twenty-eight bytes.
    ADD  HL,DE                          ; Move to the following include record.
    LD   (BIN_FPTR),HL                  ; Save its address for the next byte request.
    LD   HL,BIN_FIDX                    ; Address the byte-sized row ordinal.
    INC  (HL)                           ; Advance only after this row is fully passed.
    JR   .ROW                           ; Compare the following metadata entry.
.ORIGINAL: ; Return source bytes outside a binary directive.
    LD   A,(PP_TMP)                     ; Return the byte originally supplied by CP/M.
    OR   A                              ; Clear carry for the ordinary active-source path.
    RET                                 ; No later include row matches this position.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Substitute sequential binary bytes for the zero-fill IMAGE operations.

BIN_SINK: ; Substitute binary payload for DS zero-fill IMAGE bytes.
    LD   A,(BIN_BUSY)                   ; Is one INCBIN statement currently emitting?
    OR   A                              ; Zero means compare the next source-ordered row.
    JR   Z,.SEEK                        ; Start or skip a row when no statement is active.
    CALL .MATCHROW                      ; Compare this IMAGE anchor with the active row.
    JR   Z,.READ                        ; A matching anchor takes the next payload byte.
    LD   HL,(BIN_DUE)                   ; Load any payload bytes not emitted yet.
    LD   A,H                            ; Test the remaining count's high byte.
    OR   L                              ; A nonzero count means Atom wrote too few bytes.
    JP   NZ,BIN_FAIL                    ; Reject a short DS before the next statement.
    CALL BIN_STEP                       ; The full row may now leave the ordered cursor.
.SEEK: ; Select the next source-ordered binary row.
    LD   A,(BIN_SIDX)                   ; Read the next candidate row ordinal.
    LD   B,A                            ; Keep it while comparing with the complete count.
    LD   A,(BIN_CNT)                    ; Read the number of active include statements.
    CP   B                              ; Equal means this IMAGE byte is ordinary output.
    JR   Z,.ORIGINAL                    ; No metadata remains to substitute.
    LD   HL,(BIN_SPTR)                  ; Address the candidate row's count field.
    LD   DE,5                           ; The count word begins at metadata offset five.
    ADD  HL,DE                          ; Select its low byte.
    LD   E,(HL)                         ; Load the count low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the declared byte count.
    LD   A,D                            ; Check for the zero-byte form.
    OR   E                              ; A zero count emits no IMAGE operations.
    JR   NZ,.COMPARE                    ; Nonzero rows must match one sink anchor.
    CALL BIN_STEP                       ; Consume a zero-length metadata row without I/O.
    JR   .SEEK                          ; Continue with the following row.
.COMPARE: ; Compare a nonempty row with the IMAGE source anchor.
    CALL .MATCHROW                      ; Compare source part and operation byte offset.
    JR   C,.ORIGINAL                    ; An earlier IMAGE operation precedes this row.
    JR   Z,.START                       ; A matching operation begins its binary payload.
    JP   BIN_FAIL                       ; An unconsumed row means IMAGE was absent.
.START: ; Open the matched row and initialise its byte count.
    LD   HL,(BIN_SPTR)                  ; Address the declared count in this metadata row.
    LD   DE,5                           ; Skip its part and two source-position words.
    ADD  HL,DE                          ; Read the count low byte.
    LD   E,(HL)                         ; Preserve the low byte in DE.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the full sixteen-bit payload count.
    EX   DE,HL                          ; Move the count to HL for its workspace store.
    LD   (BIN_DUE),HL                   ; Track precisely the IMAGE bytes still expected.
    LD   A,1                            ; Mark the row active before opening its file.
    LD   (BIN_BUSY),A                   ; Any open failure still retains its source row.
    CALL BIN_OPEN                       ; Open the private FCB at sequential record zero.
    JP   C,BIN_FAIL                     ; No output can commit after a failed binary open.
.READ: ; Read exactly the remaining declared payload.
    LD   HL,(BIN_DUE)                   ; Guard against an extra IMAGE from Atom.
    LD   A,H                            ; Inspect both count bytes before reading.
    OR   L                              ; A completed statement cannot emit another byte.
    JP   Z,BIN_FAIL                     ; Reject excess output at the exact source anchor.
    CALL BIN_READ                       ; Read from the buffered 128-byte binary record.
    JP   C,BIN_FAIL                     ; EOF or BDOS error aborts the tentative output.
    LD   (BIN_VAL),A                    ; Keep the payload for HS_IB's spool call.
    LD   HL,(BIN_DUE)                   ; Load the declared bytes left after this one.
    DEC  HL                             ; Account for the just-read payload byte.
    LD   (BIN_DUE),HL                   ; Retain the remaining logical file length.
    LD   A,H                            ; Check whether the complete payload has arrived.
    OR   L                              ; Zero requires closing the FCB before returning.
    JR   NZ,.GOTBYTE                    ; Keep the sequential file open for more records.
    CALL BIN_SHUT                       ; Finish the binary input right at its count.
    JP   C,BIN_FAIL                     ; A close error prevents successful publication.
.GOTBYTE: ; Return a selected binary byte to the sink.
    XOR  A                              ; Report success. HS_IB reloads the byte from RAM.
    RET                                 ; The caller restores its address and class.
.ORIGINAL: ; Return the ordinary IMAGE fill byte.
    LD   A,(BIN_VAL)                    ; Keep the ordinary zero-fill byte unchanged.
    OR   A                              ; Clear carry for the normal ASO image operation.
    RET                                 ; Continue without reading any binary file.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Compare the current IMAGE source anchor with the pending metadata row.

.MATCHROW: ; Compare IMAGE and metadata source anchors.
    LD   HL,(BIN_SPTR)                  ; Point at the row's source-part ordinal.
    LD   A,(HL)                         ; Read the dependency-order part identity.
    LD   E,A                            ; Keep it beside the incoming IMAGE anchor.
    LD   A,(BIN_SORD)                   ; Read the current Atom statement's part.
    CP   E                              ; Carry means current part precedes the row.
    RET  NZ                             ; Return the part ordering in the flags.
    INC  HL                             ; Advance to the metadata offset's low byte.
    LD   E,(HL)                         ; Read the keyword offset's low byte.
    INC  HL                             ; Advance to the keyword offset's high byte.
    LD   D,(HL)                         ; Complete the row's exact statement anchor.
    LD   HL,(BIN_SPOS)                  ; Load the current Atom source position.
    OR   A                              ; Clear carry before comparing the two offsets.
    SBC  HL,DE                          ; Carry means the current IMAGE is earlier.
    RET                                 ; Preserve the three-way anchor comparison.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Advance both sink cursors over one completed or zero-count metadata row.

BIN_STEP: ; Retire one complete or zero-count binary row.
    LD   HL,BIN_BUSY                    ; Address the current-operation flag.
    XOR  A                              ; No row remains active after cursor advancement.
    LD   (HL),A                         ; Clear it before publishing the next pointer.
    LD   HL,(BIN_SPTR)                  ; Select the row that was just consumed.
    LD   DE,BIN_SIZE                    ; Fixed-width rows keep the table scan bounded.
    ADD  HL,DE                          ; Point at its successor.
    LD   (BIN_SPTR),HL                  ; Publish the source-order next-row pointer.
    LD   HL,BIN_SIDX                    ; Address the row's byte-sized ordinal.
    INC  (HL)                           ; Advance it exactly once with the pointer.
    RET                                 ; Return ready to compare another IMAGE operation.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require every nonempty INCBIN row to have produced its exact byte count.

BIN_CHK: ; Require all binary rows to be consumed before COMMIT.
    LD   A,(BIN_BUSY)                   ; Check the final operation's count state.
    OR   A                              ; Zero means no payload row is active.
    JR   Z,.ROWS                        ; Inspect all metadata that remains unconsumed.
    LD   HL,(BIN_DUE)                   ; Read any bytes Atom failed to request.
    LD   A,H                            ; Check the high count byte.
    OR   L                              ; A remaining payload is a short IMAGE sequence.
    JP   NZ,BIN_FAIL                    ; Keep the diagnostic anchored to that directive.
    CALL BIN_STEP                       ; The final completed row can now be retired.
.ROWS: ; Check each remaining metadata row.
    LD   A,(BIN_SIDX)                   ; Read the next pending metadata ordinal.
    LD   B,A                            ; Retain it while comparing against the row count.
    LD   A,(BIN_CNT)                    ; Load the total number of active directives.
    CP   B                              ; Equality means no required row remains.
    JR   Z,.CLOSED                      ; Confirm that no FCB escaped the final operation.
    LD   HL,(BIN_SPTR)                  ; Address this pending row's count field.
    LD   DE,5                           ; The explicit count begins at row offset five.
    ADD  HL,DE                          ; Select its low byte.
    LD   A,(HL)                         ; Read the low count byte.
    INC  HL                             ; Advance to its high byte.
    OR   (HL)                           ; A nonzero count means the row was never emitted.
    JP   NZ,BIN_FAIL                    ; Refuse to commit an unconsumed binary statement.
    CALL BIN_STEP                       ; Retire a zero-count statement unopened.
    JR   .ROWS                          ; Check the rest of the fixed metadata table.
.CLOSED: ; Require every binary input FCB to be closed.
    LD   A,(BIN_HELD)                   ; The normal final byte closes every binary input.
    OR   A                              ; A lingering open FCB is an internal mismatch.
    JP   NZ,BIN_FAIL                    ; Abort instead of publishing with an open file.
    XOR  A                              ; Return success after every row has been checked.
    RET                                 ; The ASO commit can now seal and publish output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open the metadata row's binary file with a clean sequential FCB.

BIN_OPEN: ; Open the current row binary file at record zero.
    LD   DE,BIN_FCB+12                  ; Address its sequential-record control fields.
    XOR  A                              ; Clear extent, record and random record numbers.
    LD   B,24                           ; The FCB has a twenty-four-byte mutable tail.
    CALL PUB_FILL                       ; Reset this runtime open to the first record.
    XOR  A                              ; Select CP/M's current logged-in drive.
    LD   (BIN_FCB),A                    ; Native INCBIN paths contain no drive prefix.
    LD   HL,(BIN_SPTR)                  ; Address the metadata row's eleven-byte name.
    LD   DE,BIN_NAME                    ; The filename follows the two source offsets.
    ADD  HL,DE                          ; Skip the row header and explicit count.
    LD   DE,BIN_FCB+1                   ; Point past the drive byte in the FCB.
    LD   BC,11                          ; Copy the complete normalised 8.3 identity.
    LDIR                                ; Keep the binary FCB independent of SRC_FCB.
    LD   DE,BIN_FCB                     ; Pass the clean filename to CP/M's open service.
    LD   C,CP_OPEN                      ; Select function fifteen for sequential reading.
    CALL CP_BDOS                        ; Open the payload from its first record.
    INC  A                              ; Convert BDOS's $FF error into the zero test.
    JR   Z,.FAILED                      ; Propagate an open failure through the sink.
    LD   A,1                            ; Record that abort cleanup now owns the FCB.
    LD   (BIN_HELD),A                   ; Close it on any later assembly or sink failure.
    XOR  A                              ; Start with no buffered record bytes.
    LD   (BIN_LEFT),A                   ; A new file always begins with a BDOS read.
    LD   HL,SRC_PAGE                    ; Use the existing 128-byte transfer area as DMA.
    LD   (BIN_RPTR),HL                  ; Payload records are consumed sequentially.
    XOR  A                              ; Return a successful open with carry clear.
    RET                                 ; The first actual record is fetched on demand.
.FAILED: ; Return a failed binary input open.
    SCF                                 ; No file handle was acquired on the failed open.
    RET                                 ; HS_ABORT therefore has nothing to close.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close one complete binary payload and release its record buffer.

BIN_SHUT: ; Close the binary file after its final declared byte.
    LD   DE,BIN_FCB                     ; Pass the dedicated payload FCB to CP/M.
    LD   C,CP_CLOSE                     ; Select sequential file close, function sixteen.
    CALL CP_BDOS                        ; Flush CP/M's directory state for this input.
    INC  A                              ; A zero result becomes one. $FF becomes zero.
    JR   Z,.FAILED                      ; Leave ownership set if CP/M rejects the close.
    XOR  A                              ; Clear both open and buffered-record state.
    LD   (BIN_HELD),A                   ; HS_ABORT no longer owns a cleanly closed FCB.
    LD   (BIN_LEFT),A                   ; Do not reuse the tail of its final record.
    RET                                 ; Return with carry clear after a clean close.
.FAILED: ; Retain FCB ownership after a failed close.
    SCF                                 ; The statement cannot commit after CLOSE fails.
    RET                                 ; Leave BIN_HELD set for abort cleanup to retry.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return one payload byte, refilling the shared DMA page per CP/M record.

BIN_READ: ; Read one binary payload byte through the DMA page.
    LD   A,(BIN_LEFT)                   ; Reuse the current physical record if possible.
    OR   A                              ; Zero requests one sequential 128-byte read.
    JR   NZ,.BYTE                       ; The buffered record still contains payload.
    LD   DE,SRC_PAGE                    ; Direct the next binary record to the cache page.
    LD   C,CP_DMA                       ; Select CP/M set-DMA function twenty-six.
    CALL CP_BDOS                        ; Install the DMA address before the disk read.
    LD   HL,$FFFF                       ; No valid source record uses this cache key.
    LD   (SRC_KEY),HL                   ; Invalidate before BDOS overwrites the page.
    LD   DE,BIN_FCB                     ; Pass the next sequential binary record's FCB.
    LD   C,CP_READ                      ; Select sequential record read, function twenty.
    CALL CP_BDOS                        ; Read one physical record into SRC_PAGE.
    OR   A                              ; Zero means success. EOF or error is nonzero.
    JR   NZ,.FAILED                     ; Never treat a short binary file as text padding.
    LD   A,128                          ; One complete CP/M record is now available.
    LD   (BIN_LEFT),A                   ; Count down as payload bytes are returned.
    LD   HL,SRC_PAGE                    ; Restart at the first byte of this record.
    LD   (BIN_RPTR),HL                  ; Retain the current DMA-page cursor.
.BYTE: ; Consume the next buffered payload byte.
    LD   HL,(BIN_RPTR)                  ; Address the next unconsumed payload byte.
    LD   A,(HL)                         ; Binary $1A, CR and LF are ordinary data here.
    INC  HL                             ; Advance the in-memory record cursor.
    LD   (BIN_RPTR),HL                  ; Keep the following byte for the next IMAGE.
    LD   HL,BIN_LEFT                    ; Address the bytes left in this physical record.
    DEC  (HL)                           ; Consume one of its 128 transferred bytes.
    OR   A                              ; The payload value itself does not set carry.
    RET                                 ; Return one byte with the record state updated.
.FAILED: ; Report premature binary EOF or read failure.
    SCF                                 ; BDOS EOF/error cannot meet the declared count.
    RET                                 ; HS_IB aborts the uncommitted output transaction.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the INCBIN anchor and fail the output sink without losing its origin.

BIN_FAIL: ; Retain the binary source anchor and reject output.
    LD   A,1                            ; Make CP_ENTRY print a binary-source diagnostic.
    LD   (BIN_ERR),A                    ; DR_SOUT alone identifies only the output file.
    LD   HL,(BIN_SPTR)                  ; Read the failed metadata row's part ordinal.
    LD   A,(HL)                         ; Select the dependency-order part number.
    LD   (ST_EPART),A                   ; Preserve the public source-diagnostic location.
    INC  HL                             ; Advance to the operation offset's low byte.
    LD   A,(HL)                         ; Read that low byte.
    LD   E,A                            ; Preserve it across the high-byte read.
    INC  HL                             ; Advance to the operation offset's high byte.
    LD   D,(HL)                         ; Complete the metadata source offset.
    EX   DE,HL                          ; Move the source offset into HL.
    LD   (ST_EOFF),HL                   ; Keep the directive token as the failure site.
    LD   A,1                            ; Return a nonzero host-sink detail.
    SCF                                 ; Tell Atom to abort before COMMIT.
    RET                                 ; HS_ABORT closes any still-open binary FCB.
