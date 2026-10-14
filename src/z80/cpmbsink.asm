;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Replace only the active INCBIN line's content. preserve its source offsets.

binEdit: ; Lower active INCBIN text without changing source offsets.
    LD   A,(binReady)                   ; Preflight must publish a full metadata table.
    OR   A                              ; Zero means ordinary source has no rewrite rows.
    JR   NZ,.ready                      ; Continue with the table cursor when enabled.
    LD   A,(ppTemp)                     ; Restore the source provider's original byte.
    OR   A                              ; This path never reports a binary I/O error.
    RET                                 ; Return ordinary source unchanged.
.ready: ; Synchronise the filter cursor with source position.
    LD   A,(srcPart)                    ; Read the currently selected dependency ordinal.
    LD   E,A                            ; Keep it while comparing the last filter call.
    LD   A,(binFPart)                   ; A part change restarts the row cursor.
    CP   E                              ; Does the cached cursor belong to this part?
    JR   NZ,.reset                      ; Reset before searching another source file.
    LD   HL,(ppPos)                     ; Load this byte's logical source position.
    LD   DE,(binFPos)                   ; Compare with the previous position.
    OR   A                              ; Clear borrow before the unsigned subtraction.
    SBC  HL,DE                          ; Did Atom request an earlier byte again?
    JR   C,.reset                       ; Rewind the metadata cursor for a backward peek.
    JR   NC,.savePos                    ; Keep the cursor for repeated or forward reads.
.reset: ; Restart metadata lookup after a part change or rewind.
    XOR  A                              ; Restart at metadata row zero.
    LD   (binFIdx),A                    ; Clear the byte-sized row ordinal.
    LD   HL,binTable                    ; Select the first fixed-width entry.
    LD   (binFPtr),HL                   ; Publish the reset row pointer.
.savePos: ; Retain the current filter source position.
    LD   A,(srcPart)                    ; Retain the part used for this lookup.
    LD   (binFPart),A                   ; The next call can detect part changes.
    LD   HL,(ppPos)                     ; Reload the requested source offset.
    LD   (binFPos),HL                   ; Peeks can detect a later rewind.
.row: ; Compare this source byte with metadata rows.
    LD   A,(binFIdx)                    ; Read the next possible include row.
    LD   B,A                            ; Keep the row ordinal for the bound check.
    LD   A,(binCount)                   ; Read the number of complete metadata entries.
    CP   B                              ; Equality means every include line was passed.
    JR   Z,.original                    ; No remaining row can change this source byte.
    LD   HL,(binFPtr)                   ; Address the current metadata row.
    LD   A,(HL)                         ; Read its dependency-ordered part ordinal.
    LD   E,A                            ; Keep the row's part for the unsigned compare.
    LD   A,(srcPart)                    ; Read the current source part.
    CP   E                              ; Is this byte before or after the row's part?
    JR   C,.original                    ; A later row leaves this earlier byte untouched.
    JR   NZ,.advance                    ; A previous part cannot match this source byte.
    INC  HL                             ; Advance to the INCBIN keyword's offset low byte.
    LD   E,(HL)                         ; Read the operation anchor's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the operation anchor word.
    LD   HL,(ppPos)                     ; Load the current byte's source offset.
    OR   A                              ; Clear borrow before comparing source positions.
    SBC  HL,DE                          ; Is the current byte before the keyword?
    JR   C,.original                    ; Keep labels and indentation before INCBIN.
    LD   HL,(binFPtr)                   ; Address the row's exclusive content end.
    LD   DE,3                           ; Its line-end word begins at byte three.
    ADD  HL,DE                          ; Point at the line-end low byte.
    LD   E,(HL)                         ; Read the exclusive content end's low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the line-end boundary.
    LD   HL,(ppPos)                     ; Reload the byte being transformed.
    OR   A                              ; Clear borrow before the boundary comparison.
    SBC  HL,DE                          ; Has the source reached CR, LF or end of file?
    JP   NC,.advance                    ; Preserve endings and move beyond this metadata.
    LD   HL,(binFPtr)                   ; Address the row's operation anchor.
    INC  HL                             ; Point to the start-offset low byte.
    LD   E,(HL)                         ; Read its low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the start-offset word.
    LD   HL,(ppPos)                     ; Compute displacement from the keyword.
    OR   A                              ; Clear borrow to compute the replacement index.
    SBC  HL,DE                          ; HL now contains the source-byte displacement.
    LD   A,H                            ; Replacement text is only ten bytes long.
    OR   A                              ; A nonzero high byte is already beyond that span.
    JR   NZ,.space                      ; Mask any remaining directive text with spaces.
    LD   A,L                            ; Read the small replacement-text displacement.
    CP   binDsLen                       ; Check whether it names one of ten bytes.
    JR   NC,.space                      ; The rest of the old line becomes whitespace.
    LD   C,A                            ; Preserve the replacement index across addition.
    LD   HL,(binFPtr)                   ; Address this row's fixed DS replacement.
    LD   DE,binDsOff                    ; Its replacement text starts at offset eighteen.
    ADD  HL,DE                          ; Point at the generated source text.
    LD   E,C                            ; Zero-extend the displacement in DE.
    LD   D,0                            ; Complete the offset pair.
    ADD  HL,DE                          ; Select the character corresponding to this byte.
    LD   A,(HL)                         ; Read one byte of the fixed-width DS statement.
    OR   A                              ; Return it with carry clear.
    RET                                 ; Keep every original byte offset unchanged.
.space: ; Mask original operand text after the DS replacement.
    LD   A,' '                          ; Do not leave any original filename characters.
    OR   A                              ; Return harmless assembler whitespace.
    RET                                 ; The line ending stays outside the rewrite span.
.advance: ; Advance beyond a completed filter row.
    LD   HL,(binFPtr)                   ; Select the row just passed by the source cursor.
    LD   DE,binSize                     ; Every fixed row is the same twenty-eight bytes.
    ADD  HL,DE                          ; Move to the following include record.
    LD   (binFPtr),HL                   ; Save its address for the next byte request.
    LD   HL,binFIdx                     ; Address the byte-sized row ordinal.
    INC  (HL)                           ; Advance only after this row is fully passed.
    JR   .row                           ; Compare the following metadata entry.
.original: ; Return source bytes outside a binary directive.
    LD   A,(ppTemp)                     ; Return the byte originally supplied by CP/M.
    OR   A                              ; Clear carry for the ordinary active-source path.
    RET                                 ; No later include row matches this position.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Substitute sequential binary bytes for the zero-fill IMAGE operations.

binSink: ; Substitute binary payload for DS zero-fill IMAGE bytes.
    LD   A,(binBusy)                    ; Is one INCBIN statement currently emitting?
    OR   A                              ; Zero means compare the next source-ordered row.
    JR   Z,.seek                        ; Start or skip a row when no statement is active.
    CALL .matchRow                      ; Compare this IMAGE anchor with the active row.
    JR   Z,.read                        ; A matching anchor takes the next payload byte.
    LD   HL,(binDue)                    ; Load any payload bytes not emitted yet.
    LD   A,H                            ; Test the remaining count's high byte.
    OR   L                              ; A nonzero count means Atom wrote too few bytes.
    JP   NZ,binFail                     ; Reject a short DS before the next statement.
    CALL binStep                        ; The full row may now leave the ordered cursor.
.seek: ; Select the next source-ordered binary row.
    LD   A,(binSIdx)                    ; Read the next candidate row ordinal.
    LD   B,A                            ; Keep it while comparing with the complete count.
    LD   A,(binCount)                   ; Read the number of active include statements.
    CP   B                              ; Equal means this IMAGE byte is ordinary output.
    JR   Z,.original                    ; No metadata remains to substitute.
    LD   HL,(binSPtr)                   ; Address the candidate row's count field.
    LD   DE,5                           ; The count word begins at metadata offset five.
    ADD  HL,DE                          ; Select its low byte.
    LD   E,(HL)                         ; Load the count low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the declared byte count.
    LD   A,D                            ; Check for the zero-byte form.
    OR   E                              ; A zero count emits no IMAGE operations.
    JR   NZ,.compare                    ; Nonzero rows must match one sink anchor.
    CALL binStep                        ; Consume a zero-length metadata row without I/O.
    JR   .seek                          ; Continue with the following row.
.compare: ; Compare a nonempty row with the IMAGE source anchor.
    CALL .matchRow                      ; Compare source part and operation byte offset.
    JR   C,.original                    ; An earlier IMAGE operation precedes this row.
    JR   Z,.start                       ; A matching operation begins its binary payload.
    JP   binFail                        ; An unconsumed row means IMAGE was absent.
.start: ; Open the matched row and initialise its byte count.
    LD   HL,(binSPtr)                   ; Address the declared count in this metadata row.
    LD   DE,5                           ; Skip its part and two source-position words.
    ADD  HL,DE                          ; Read the count low byte.
    LD   E,(HL)                         ; Preserve the low byte in DE.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the full sixteen-bit payload count.
    EX   DE,HL                          ; Move the count to HL for its workspace store.
    LD   (binDue),HL                    ; Track precisely the IMAGE bytes still expected.
    LD   A,1                            ; Mark the row active before opening its file.
    LD   (binBusy),A                    ; Any open failure still retains its source row.
    CALL binOpen                        ; Open the private FCB at sequential record zero.
    JP   C,binFail                      ; No output can commit after a failed binary open.
.read: ; Read exactly the remaining declared payload.
    LD   HL,(binDue)                    ; Guard against an extra IMAGE from Atom.
    LD   A,H                            ; Inspect both count bytes before reading.
    OR   L                              ; A completed statement cannot emit another byte.
    JP   Z,binFail                      ; Reject excess output at the exact source anchor.
    CALL binRead                        ; Read from the buffered 128-byte binary record.
    JP   C,binFail                      ; EOF or BDOS error aborts the tentative output.
    LD   (binVal),A                     ; Keep the payload for hsByte's spool call.
    LD   HL,(binDue)                    ; Load the declared bytes left after this one.
    DEC  HL                             ; Account for the just-read payload byte.
    LD   (binDue),HL                    ; Retain the remaining logical file length.
    LD   A,H                            ; Check whether the complete payload has arrived.
    OR   L                              ; Zero requires closing the FCB before returning.
    JR   NZ,.gotByte                    ; Keep the sequential file open for more records.
    CALL binClose                       ; Finish the binary input right at its count.
    JP   C,binFail                      ; A close error prevents successful publication.
.gotByte: ; Return a selected binary byte to the sink.
    XOR  A                              ; Report success. hsByte reloads the byte from RAM.
    RET                                 ; The caller restores its address and class.
.original: ; Return the ordinary IMAGE fill byte.
    LD   A,(binVal)                     ; Keep the ordinary zero-fill byte unchanged.
    OR   A                              ; Clear carry for the normal ASO image operation.
    RET                                 ; Continue without reading any binary file.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Compare the current IMAGE source anchor with the pending metadata row.

.matchRow: ; Compare IMAGE and metadata source anchors.
    LD   HL,(binSPtr)                   ; Point at the row's source-part ordinal.
    LD   A,(HL)                         ; Read the dependency-order part identity.
    LD   E,A                            ; Keep it beside the incoming IMAGE anchor.
    LD   A,(binSPart)                   ; Read the current Atom statement's part.
    CP   E                              ; Carry means current part precedes the row.
    RET  NZ                             ; Return the part ordering in the flags.
    INC  HL                             ; Advance to the metadata offset's low byte.
    LD   E,(HL)                         ; Read the keyword offset's low byte.
    INC  HL                             ; Advance to the keyword offset's high byte.
    LD   D,(HL)                         ; Complete the row's exact statement anchor.
    LD   HL,(binSPos)                   ; Load the current Atom source position.
    OR   A                              ; Clear carry before comparing the two offsets.
    SBC  HL,DE                          ; Carry means the current IMAGE is earlier.
    RET                                 ; Preserve the three-way anchor comparison.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Advance both sink cursors over one completed or zero-count metadata row.

binStep: ; Retire one complete or zero-count binary row.
    LD   HL,binBusy                     ; Address the current-operation flag.
    XOR  A                              ; No row remains active after cursor advancement.
    LD   (HL),A                         ; Clear it before publishing the next pointer.
    LD   HL,(binSPtr)                   ; Select the row that was just consumed.
    LD   DE,binSize                     ; Fixed-width rows keep the table scan bounded.
    ADD  HL,DE                          ; Point at its successor.
    LD   (binSPtr),HL                   ; Publish the source-order next-row pointer.
    LD   HL,binSIdx                     ; Address the row's byte-sized ordinal.
    INC  (HL)                           ; Advance it exactly once with the pointer.
    RET                                 ; Return ready to compare another IMAGE operation.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require every nonempty INCBIN row to have produced its exact byte count.

binCheck: ; Require all binary rows to be consumed before COMMIT.
    LD   A,(binBusy)                    ; Check the final operation's count state.
    OR   A                              ; Zero means no payload row is active.
    JR   Z,.rows                        ; Inspect all metadata that remains unconsumed.
    LD   HL,(binDue)                    ; Read any bytes Atom failed to request.
    LD   A,H                            ; Check the high count byte.
    OR   L                              ; A remaining payload is a short IMAGE sequence.
    JP   NZ,binFail                     ; Keep the diagnostic anchored to that directive.
    CALL binStep                        ; The final completed row can now be retired.
.rows: ; Check each remaining metadata row.
    LD   A,(binSIdx)                    ; Read the next pending metadata ordinal.
    LD   B,A                            ; Retain it while comparing against the row count.
    LD   A,(binCount)                   ; Load the total number of active directives.
    CP   B                              ; Equality means no required row remains.
    JR   Z,.closed                      ; Confirm that no FCB escaped the final operation.
    LD   HL,(binSPtr)                   ; Address this pending row's count field.
    LD   DE,5                           ; The explicit count begins at row offset five.
    ADD  HL,DE                          ; Select its low byte.
    LD   A,(HL)                         ; Read the low count byte.
    INC  HL                             ; Advance to its high byte.
    OR   (HL)                           ; A nonzero count means the row was never emitted.
    JP   NZ,binFail                     ; Refuse to commit an unconsumed binary statement.
    CALL binStep                        ; Retire a zero-count statement unopened.
    JR   .rows                          ; Check the rest of the fixed metadata table.
.closed: ; Require every binary input FCB to be closed.
    LD   A,(binHeld)                    ; The normal final byte closes every binary input.
    OR   A                              ; A lingering open FCB is an internal mismatch.
    JP   NZ,binFail                     ; Abort instead of publishing with an open file.
    XOR  A                              ; Return success after every row has been checked.
    RET                                 ; The ASO commit can now seal and publish output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open the metadata row's binary file with a clean sequential FCB.

binOpen: ; Open the current row binary file at record zero.
    LD   DE,binFcb+12                   ; Address its sequential-record control fields.
    XOR  A                              ; Clear extent, record and random record numbers.
    LD   B,24                           ; The FCB has a twenty-four-byte mutable tail.
    CALL pubFill                        ; Reset this runtime open to the first record.
    XOR  A                              ; Select CP/M's current logged-in drive.
    LD   (binFcb),A                     ; Native INCBIN paths contain no drive prefix.
    LD   HL,(binSPtr)                   ; Address the metadata row's eleven-byte name.
    LD   DE,binName                     ; The filename follows the two source offsets.
    ADD  HL,DE                          ; Skip the row header and explicit count.
    LD   DE,binFcb+1                    ; Point past the drive byte in the FCB.
    LD   BC,11                          ; Copy the complete normalised 8.3 identity.
    LDIR                                ; Keep the binary FCB independent of srcFcb.
    LD   DE,binFcb                      ; Pass the clean filename to CP/M's open service.
    LD   C,cpOpen                       ; Select function fifteen for sequential reading.
    CALL cpBdos                         ; Open the payload from its first record.
    INC  A                              ; Convert BDOS's $FF error into the zero test.
    JR   Z,.failed                      ; Propagate an open failure through the sink.
    LD   A,1                            ; Record that abort cleanup now owns the FCB.
    LD   (binHeld),A                    ; Close it on any later assembly or sink failure.
    XOR  A                              ; Start with no buffered record bytes.
    LD   (binLeft),A                    ; A new file always begins with a BDOS read.
    LD   HL,srcCache                    ; Use the existing 128-byte transfer area as DMA.
    LD   (binRPtr),HL                   ; Payload records are consumed sequentially.
    XOR  A                              ; Return a successful open with carry clear.
    RET                                 ; The first actual record is fetched on demand.
.failed: ; Return a failed binary input open.
    SCF                                 ; No file handle was acquired on the failed open.
    RET                                 ; hsAbort therefore has nothing to close.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close one complete binary payload and release its record buffer.

binClose: ; Close the binary file after its final declared byte.
    LD   DE,binFcb                      ; Pass the dedicated payload FCB to CP/M.
    LD   C,cpClose                      ; Select sequential file close, function sixteen.
    CALL cpBdos                         ; Flush CP/M's directory state for this input.
    INC  A                              ; A zero result becomes one. $FF becomes zero.
    JR   Z,.failed                      ; Leave ownership set if CP/M rejects the close.
    XOR  A                              ; Clear both open and buffered-record state.
    LD   (binHeld),A                    ; hsAbort no longer owns a cleanly closed FCB.
    LD   (binLeft),A                    ; Do not reuse the tail of its final record.
    RET                                 ; Return with carry clear after a clean close.
.failed: ; Retain FCB ownership after a failed close.
    SCF                                 ; The statement cannot commit after CLOSE fails.
    RET                                 ; Leave binHeld set for abort cleanup to retry.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return one payload byte, refilling the shared DMA page per CP/M record.

binRead: ; Read one binary payload byte through the DMA page.
    LD   A,(binLeft)                    ; Reuse the current physical record if possible.
    OR   A                              ; Zero requests one sequential 128-byte read.
    JR   NZ,.byte                       ; The buffered record still contains payload.
    LD   DE,srcCache                    ; Direct the next binary record to the cache page.
    LD   C,cpSetDma                     ; Select CP/M set-DMA function twenty-six.
    CALL cpBdos                         ; Install the DMA address before the disk read.
    LD   HL,$FFFF                       ; No valid source record uses this cache key.
    LD   (srcKey),HL                    ; Invalidate before BDOS overwrites the page.
    LD   DE,binFcb                      ; Pass the next sequential binary record's FCB.
    LD   C,cpRead                       ; Select sequential record read, function twenty.
    CALL cpBdos                         ; Read one physical record into srcCache.
    OR   A                              ; Zero means success. EOF or error is nonzero.
    JR   NZ,.failed                     ; Never treat a short binary file as text padding.
    LD   A,128                          ; One complete CP/M record is now available.
    LD   (binLeft),A                    ; Count down as payload bytes are returned.
    LD   HL,srcCache                    ; Restart at the first byte of this record.
    LD   (binRPtr),HL                   ; Retain the current DMA-page cursor.
.byte: ; Consume the next buffered payload byte.
    LD   HL,(binRPtr)                   ; Address the next unconsumed payload byte.
    LD   A,(HL)                         ; Binary $1A, CR and LF are ordinary data here.
    INC  HL                             ; Advance the in-memory record cursor.
    LD   (binRPtr),HL                   ; Keep the following byte for the next IMAGE.
    LD   HL,binLeft                     ; Address the bytes left in this physical record.
    DEC  (HL)                           ; Consume one of its 128 transferred bytes.
    OR   A                              ; The payload value itself does not set carry.
    RET                                 ; Return one byte with the record state updated.
.failed: ; Report premature binary EOF or read failure.
    SCF                                 ; BDOS EOF/error cannot meet the declared count.
    RET                                 ; hsByte aborts the uncommitted output transaction.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the INCBIN anchor and fail the output sink without losing its origin.

binFail: ; Retain the binary source anchor and reject output.
    LD   A,1                            ; Make cpEntry print a binary-source diagnostic.
    LD   (binErr),A                     ; drBadOut alone identifies only the output file.
    LD   HL,(binSPtr)                   ; Read the failed metadata row's part ordinal.
    LD   A,(HL)                         ; Select the dependency-order part number.
    LD   (stAtPart),A                   ; Preserve the public source-diagnostic location.
    INC  HL                             ; Advance to the operation offset's low byte.
    LD   A,(HL)                         ; Read that low byte.
    LD   E,A                            ; Preserve it across the high-byte read.
    INC  HL                             ; Advance to the operation offset's high byte.
    LD   D,(HL)                         ; Complete the metadata source offset.
    EX   DE,HL                          ; Move the source offset into HL.
    LD   (stAtOff),HL                   ; Keep the directive token as the failure site.
    LD   A,1                            ; Return a nonzero host-sink detail.
    SCF                                 ; Tell Atom to abort before COMMIT.
    RET                                 ; hsAbort closes any still-open binary FCB.
