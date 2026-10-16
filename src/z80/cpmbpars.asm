;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Decode the current part's exclusive logical end for binary preflight.

binRange: ; Decode the current source descriptor end.
    LD   HL,(binDesc)                   ; Point to the current five-byte descriptor.
    LD   DE,3                           ; Its exclusive logical end begins at byte three.
    ADD  HL,DE                          ; Address the low byte of the end offset.
    LD   E,(HL)                         ; Read the low byte of this source's length.
    INC  HL                             ; Advance to the high end byte.
    LD   D,(HL)                         ; Complete the sixteen-bit source length.
    EX   DE,HL                          ; Return the end offset in HL.
    LD   (binStop),HL                   ; Cache the exclusive scan boundary.
    RET                                 ; The source itself begins at logical offset zero.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read one condition-filtered source byte and advance the preflight cursor.

binByte: ; Read and advance one filtered preflight source byte.
    LD   A,(binPart)                    ; Select the resolved source-part ordinal.
    LD   HL,(binPos)                    ; Read the next logical byte position.
    CALL srcByte                        ; Apply the ordinary CP/M source and IF filters.
    RET  C                              ; Preserve premature EOF/read failure for caller.
    LD   (binTemp),A                    ; Keep the source byte during cursor update.
    LD   HL,(binPos)                    ; Reload the current zero-based offset.
    INC  HL                             ; Advance to the byte after the one just read.
    LD   (binPos),HL                    ; Publish the next position to every helper.
    LD   A,(binTemp)                    ; Restore the filtered source byte.
    OR   A                              ; Clear carry and preserve the byte in A.
    RET                                 ; The scan cursor now names the following byte.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Collect one token into ppToken, folding lowercase ASCII to uppercase.

binToken: ; Collect a bounded uppercase source token.
    LD   (binTemp),A                    ; Preserve the first byte before clearing length.
    XOR  A                              ; Start this candidate with an empty token.
    LD   (ppTokLen),A                   ; ppMatch reads this exact length.
    LD   A,(binTemp)                    ; Restore the first character for the token loop.
.loop: ; Classify and append the next token character.
    LD   (binTemp),A                    ; Preserve the current byte across tests.
    CP   ' '                            ; Space completes the token without being stored.
    JR   Z,.done                        ; Return the delimiter to the caller.
    CP   9                              ; A tab also delimits a source token.
    JR   Z,.done                        ; Preserve it as the token terminator.
    CP   ':'                            ; Colon separates a label from its operation.
    JR   Z,.done                        ; Do not merge the label and colon.
    CP   ';'                            ; A comment begins after the token boundary.
    JR   Z,.done                        ; Leave comment handling to the caller.
    CP   13                             ; Carriage return terminates the physical line.
    JR   Z,.done                        ; Keep line endings outside the token.
    CP   10                             ; Line feed is the second accepted terminator.
    JR   Z,.done                        ; Return it without adding it to the token.
    LD   A,(ppTokLen)                   ; Read the current token byte count.
    CP   17                             ; The shared token buffer has seventeen positions.
    JR   NC,.long                       ; Ignore overlong ordinary labels safely.
    LD   C,A                            ; Use the token length as a buffer index.
    LD   A,(binTemp)                    ; Restore the source character.
    CP   'a'                            ; Check whether lowercase folding applies.
    JR   C,.cased                       ; Leave uppercase and punctuation unchanged.
    CP   'z'+1                          ; Compare with the exclusive lowercase bound.
    JR   NC,.cased                      ; Leave bytes outside ASCII lowercase unchanged.
    AND  $DF                            ; Fold the supported keyword to uppercase.
.cased: ; Append the normalised token character.
    LD   (binTemp),A                    ; Save the normalised character while indexing.
    LD   B,0                            ; The token length is smaller than eighteen.
    LD   A,C                            ; Place the current position in BC.
    LD   C,A                            ; Complete its one-byte index.
    LD   HL,ppToken                     ; Select the bounded token buffer.
    ADD  HL,BC                          ; Address its next free byte.
    LD   A,(binTemp)                    ; Restore the normalised character.
    LD   (HL),A                         ; Append it to the token.
    LD   HL,ppTokLen                    ; Address the token's published length.
    INC  (HL)                           ; Include the byte just stored above.
    CALL binByte                        ; Read the following token byte or delimiter.
    JR   NC,.loop                       ; Continue until a delimiter is consumed.
    XOR  A                              ; EOF completes the current nonempty token.
    SCF                                 ; Mark the delimiter as end of this source part.
    RET                                 ; The caller still compares the collected token.
.done: ; Return the consumed token delimiter.
    LD   A,(binTemp)                    ; Return the consumed delimiter to the caller.
    OR   A                              ; Clear carry and classify the delimiter byte.
    RET                                 ; ppToken contains only source token bytes.
.long: ; Report token overflow separately from EOF.
    LD   A,1                            ; Distinguish an overlong token from clean EOF.
    SCF                                 ; Tell the caller to ignore this unsupported name.
    RET                                 ; No partial token can equal the six-byte keyword.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted 8.3 binary name and a required numeric byte count.

binArgs: ; Parse a quoted binary filename and required count.
    LD   HL,(binPos)                    ; Resume after the consumed INCBIN delimiter.
.toQuote: ; Find the opening quote on this physical line.
    CALL srcNext                        ; Read the next raw byte of this source line.
    JP   C,binBad                       ; A path must begin before source end.
    CP   ' '                            ; Ignore spaces between INCBIN and its path.
    JR   Z,.toQuote                     ; Keep scanning horizontal whitespace.
    CP   9                              ; Tabs are also valid between directive operands.
    JR   Z,.toQuote                     ; Continue until the opening quote.
    CP   13                             ; Never let a missing path run onto another line.
    JP   Z,binBad                       ; The opening quote must be on this physical line.
    CP   10                             ; LF-only sources have the same operand boundary.
    JP   Z,binBad                       ; Keep the binary directive on its source line.
    CP   ';'                            ; A comment cannot stand in for the filename.
    JP   Z,binBad                       ; Reject an incomplete directive before assembly.
    CP   '"'                            ; CP/M accepts only a quoted current-drive name.
    JP   NZ,binBad                      ; Reject paths, comments and unquoted names.
    CALL incWipe                        ; Prepare the normalised scratch filename FCB.
    CALL incName                        ; Validate and store the complete 8.3 filename.
    JP   C,binBad                       ; Reject malformed or incomplete quoted names.
    LD   (binPos),HL                    ; Preserve the cursor after the closing quote.
    LD   HL,cpFcb+1                     ; Copy the name/type the parser normalised.
    LD   DE,binFile                     ; Preserve it while work FCB builds temp names.
    LD   BC,11                          ; The filename is eight base and three type bytes.
    LDIR                                ; Keep this binary identity in private workspace.
    LD   HL,(binPos)                    ; Resume at the first byte after the filename.
.toComma: ; Require a comma on the same directive line.
    CALL srcNext                        ; Read the delimiter after the closing quote.
    JP   C,binBad                       ; A byte count is mandatory on the native profile.
    CP   ' '                            ; Skip optional whitespace before the comma.
    JR   Z,.toComma                     ; Keep the operand grammar simple.
    CP   9                              ; Permit a tab before the required comma.
    JR   Z,.toComma                     ; Continue over horizontal whitespace.
    CP   13                             ; Do not search a later line for the comma.
    JP   Z,binBad                       ; A count belongs to the same INCBIN statement.
    CP   10                             ; Reject the equivalent LF-only operand break.
    JP   Z,binBad                       ; Preserve original newline bytes and semantics.
    CP   ';'                            ; A trailing comment cannot replace the count.
    JP   Z,binBad                       ; Keep the count mandatory on the directive line.
    CP   ','                            ; The second operand is the exact byte count.
    JP   NZ,binBad                      ; Reject a missing count or extra filename text.
    CALL ppGetTok                       ; Read a bounded numeric literal after the comma.
    JP   C,binBad                       ; Reject a missing or overlong count token.
    LD   A,(ppToken)                    ; Inspect the first byte before definition lookup.
    CP   '0'                            ; Decimal and Intel-suffix values start as digits.
    JR   C,.prefix                      ; Check the two supported numeric prefixes.
    CP   '9'+1                          ; Accept decimal and 0FFFFH lexical starts.
    JR   C,.number                      ; Parse a digit-leading number.
.prefix: ; Accept the binary count numeric prefixes.
    CP   '$'                            ; Dollar selects hexadecimal.
    JR   Z,.number                      ; Pass the complete token to the shared parser.
    CP   '%'                            ; Percent here means binary, not a host directive.
    JP   NZ,binBad                      ; Named counts are excluded from portable INCBIN.
.number: ; Parse and validate the binary byte count.
    CALL ppEval                         ; Convert decimal, hex or binary to unsigned word.
    JP   C,binBad                       ; Reject invalid digits and values above $FFFF.
    LD   (binLen),HL                    ; Preserve the declared logical payload length.
    LD   HL,(ppSrcPtr)                  ; Resume at the count token's trailing delimiter.
    CALL ppEol                          ; Allow only whitespace, EOL or a comment.
    JP   C,binBad                       ; Reject another operand or trailing source token.
    LD   (binPos),HL                    ; Continue scanning after the full directive line.
    LD   (binEol),HL                    ; Start with the returned exclusive source cursor.
    CALL .trim                          ; Remove CR/LF from the rewriteable content range.
    JP   C,binLost                      ; A changed source cannot be rewritten safely.
    CALL .validate                      ; Check span, collision, capacity and existence.
    RET                                 ; Keep the metadata check's status and message.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Find the end of source text before a consumed CR, LF or CRLF sequence.

.trim: ; Find the source-content end before CR or LF.
    LD   A,H                            ; Check whether the returned end is offset zero.
    OR   L                              ; No preceding newline can exist at zero.
    RET  Z                              ; Keep an empty content range unchanged.
    DEC  HL                             ; Address the last consumed source byte.
    PUSH HL                             ; The raw source reader uses HL as a cache cursor.
    CALL srcRaw                         ; Inspect it without applying text transformation.
    POP  HL                             ; Restore the source offset for line-end storage.
    RET  C                              ; EOF leaves the initial exclusive end unchanged.
    CP   13                             ; A consumed CR is the first byte past the line.
    JR   Z,.trimAt                      ; Keep the content end before that CR.
    CP   10                             ; A consumed LF also lies outside line content.
    JR   Z,.trimLf                      ; Trim LF and test for a preceding CR.
    OR   A                              ; A non-newline byte returns clear carry.
    RET                                 ; The original exclusive end is already correct.
.trimLf: ; Trim LF and an optional preceding CR.
    LD   (binEol),HL                    ; The content ends immediately before LF.
    LD   A,H                            ; Check whether LF was the first source byte.
    OR   L                              ; No preceding CR is possible at offset zero.
    RET  Z                              ; Preserve the LF-only content boundary.
    DEC  HL                             ; Inspect the byte before LF for a CRLF pair.
    PUSH HL                             ; Keep its source offset across the cache lookup.
    CALL srcRaw                         ; Read only the preceding physical source byte.
    POP  HL                             ; Restore the offset before deciding the boundary.
    RET  C                              ; Keep the LF boundary if the source changed.
    CP   13                             ; CRLF has one content end before its CR byte.
    JR   Z,.trimAt                      ; CR is outside content as well as LF.
    OR   A                              ; A non-CR byte keeps the LF boundary. no carry.
    RET                                 ; Do not leak CP's carry for bytes below CR.
.trimAt: ; Record the first byte of the original line ending.
    LD   (binEol),HL                    ; Publish the first byte of the line ending.
    RET                                 ; Source offsets after the directive stay fixed.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and append one active, bounded binary include record.

.validate: ; Validate and append a bounded binary row.
    LD   A,(binCount)                   ; Read the count of preflighted binary statements.
    CP   binMax                         ; The fixed table must not be overrun.
    JP   NC,binFull                     ; Reject the thirty-third include before a write.
    LD   HL,(binEol)                    ; Load the rewriteable source-content boundary.
    LD   DE,(binSite)                   ; Locate the directive keyword start.
    OR   A                              ; Clear carry before computing the available span.
    SBC  HL,DE                          ; Count bytes from INCBIN through line content.
    LD   DE,binDsLen                    ; The generated DS statement is ten bytes.
    OR   A                              ; Clear carry before checking the minimum span.
    SBC  HL,DE                          ; Can the original line hold the full replacement?
    JP   C,binBad                       ; Never move source offsets or truncate the line.
    CALL .probe                         ; Guard transaction names. prove the file exists.
    JP   C,binExit                      ; Keep the failing filename and source anchor.
    CALL .append                        ; Publish a complete, source-ordered table entry.
    XOR  A                              ; Return success after incrementing the row count.
    RET                                 ; The scanner continues with the next source line.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Preserve exact input names while rejecting output/temp/backup aliases.

.probe: ; Protect output names and probe the binary file.
    LD   DE,binFcb+12                   ; Address the mutable tail of the private FCB.
    XOR  A                              ; Clear record counters, extent and random record.
    LD   B,24                           ; Eleven name bytes precede this 24-byte tail.
    CALL pubFill                        ; Initialize all binary-FCB control fields.
    XOR  A                              ; Select the logged-in drive for each INCBIN file.
    LD   (binFcb),A                     ; CP/M native paths cannot name another drive.
    LD   HL,binFile                     ; Read the normalised eleven-byte 8.3 identity.
    LD   DE,binFcb+1                    ; Store it after the private FCB's drive byte.
    LD   BC,11                          ; Copy the complete base and extension fields.
    LDIR                                ; The runtime reader never reuses cpFcb.
    LD   HL,binFcb                      ; Compare the candidate's drive and 8.3 identity.
    LD   DE,pubName                     ; The final output name must remain protected.
    CALL cmdSame                        ; Z marks a destructive binary/output collision.
    JR   Z,.clash                       ; Do not replace an input after it was assembled.
    CALL pubTemp                        ; Rebuild the transaction's temporary filename.
    LD   HL,binFcb                      ; Keep the binary identity in its independent FCB.
    LD   DE,cpFcb                       ; Compare with the temporary output name.
    CALL cmdSame                        ; Z means ASO or final output may overwrite input.
    JR   Z,.clash                       ; Reject a binary alias of the temporary file.
    CALL pubBak                         ; Reconstruct the reserved backup/spool name.
    LD   HL,binFcb                      ; Restore the binary FCB pointer for comparison.
    LD   DE,cpFcb                       ; The work FCB now carries the backup name.
    CALL cmdSame                        ; Z means the ASO spool could destroy this input.
    JR   Z,.clash                       ; Protect $$B when it is the private spool.
    LD   DE,binFcb                      ; Open the candidate using its dedicated FCB.
    LD   C,cpOpen                       ; Select CP/M file-open function fifteen.
    CALL cpBdos                         ; Confirm the binary exists before output begins.
    INC  A                              ; BDOS returns $FF when the file cannot be opened.
    JR   Z,.missing                     ; Report the source position and requested file.
    LD   DE,binFcb                      ; Close the temporary validation open.
    LD   C,cpClose                      ; Select CP/M close function sixteen.
    CALL cpBdos                         ; Release the FCB before assembly starts.
    INC  A                              ; Convert close failure into the zero test.
    JR   Z,.noClose                     ; Do not accept an uncertain input handle.
    XOR  A                              ; Clear carry and status once validation succeeds.
    RET                                 ; binFcb is ready for a clean runtime reopen.
.clash: ; Report a binary-input and output alias.
    CALL binLoc                         ; Show the source file, line and column.
    LD   HL,binFcb                      ; Name the candidate binary that aliases output.
    CALL cpPutFcb                       ; Print the conflicting current-drive 8.3 name.
    LD   DE,msgSame                     ; Select the destructive-name diagnostic.
    SCF                                 ; Reject this source before ASO begins.
    RET                                 ; No transaction file has been created.
.missing: ; Report a missing binary file.
    CALL binLoc                         ; Point at the active INCBIN statement.
    LD   HL,binFcb                      ; Identify the unavailable binary source.
    CALL cpPutFcb                       ; Print its exact CP/M filename.
    LD   DE,msgLoad                     ; Select the binary-input diagnostic suffix.
    SCF                                 ; Refuse to assemble a missing payload.
    RET                                 ; The prior output remains untouched.
.noClose: ; Report a failed binary preflight close.
    CALL binLoc                         ; Keep the source anchor on close failure.
    LD   HL,binFcb                      ; Identify the FCB whose close failed.
    CALL cpPutFcb                       ; Print the requested binary filename.
    LD   DE,msgLoad                     ; Report the preflight file operation failure.
    SCF                                 ; Stop before the assembler begins a generation.
    RET                                 ; No partial operation stream exists.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the normalised source anchor, count, name and DS replacement text.

.append: ; Write the complete binary metadata and DS replacement.
    LD   HL,(binFree)                   ; Select the next unused metadata row.
    LD   A,(binPart)                    ; Store its dependency-ordered source part.
    LD   (HL),A                         ; Byte zero keys both filtering and sink dispatch.
    INC  HL                             ; Advance to the exact INCBIN keyword offset.
    LD   DE,(binSite)                   ; Load the operation's original source position.
    LD   (HL),E                         ; Store the offset low byte.
    INC  HL                             ; Advance to the offset high byte.
    LD   (HL),D                         ; Complete the stable statement anchor.
    INC  HL                             ; Advance to the source line's content end.
    LD   DE,(binEol)                    ; Load the exclusive end before CR/LF.
    LD   (HL),E                         ; Store the line-end low byte.
    INC  HL                             ; Advance to the line-end high byte.
    LD   (HL),D                         ; Preserve every original line-ending offset.
    INC  HL                             ; Advance to the requested binary byte count.
    LD   DE,(binLen)                    ; Load the explicit payload length.
    LD   (HL),E                         ; Store the count low byte.
    INC  HL                             ; Advance to the count high byte.
    LD   (HL),D                         ; Complete the sixteen-bit logical length.
    INC  HL                             ; Advance to the eleven-byte normalised name.
    EX   DE,HL                          ; Keep the row cursor in DE while copying.
    LD   HL,binFile                     ; Read the candidate's base and type fields.
    LD   BC,11                          ; The row stores exactly the CP/M 8.3 name bytes.
    LDIR                                ; Preserve it independently of all FCB work.
    EX   DE,HL                          ; Resume at row offset eighteen, the replacement.
    LD   A,'D'                          ; Begin the fixed-width DS lowering.
    LD   (HL),A                         ; Replacement byte zero is uppercase D.
    INC  HL                             ; Advance within the ten-byte directive form.
    LD   A,'S'                          ; Select the second mnemonic character.
    LD   (HL),A                         ; Store S after D.
    INC  HL                             ; Advance to the operand separator.
    LD   A,' '                          ; Keep the assembler's ordinary token boundary.
    LD   (HL),A                         ; Store the space after DS.
    INC  HL                             ; Advance to the hexadecimal prefix.
    LD   A,'$'                          ; Use a fixed-width hexadecimal byte count.
    LD   (HL),A                         ; Store the prefix before four digits.
    INC  HL                             ; Advance to the most-significant count nibble.
    LD   DE,(binLen)                    ; Load both count bytes for nibble extraction.
    LD   A,D                            ; Select the high byte's upper nibble.
    RRCA                                ; Move bit four into the low nibble.
    RRCA                                ; Move bit five into the low nibble.
    RRCA                                ; Move bit six into the low nibble.
    RRCA                                ; Move bit seven into the low nibble.
    AND  $0F                            ; Keep only the most-significant hex digit.
    CALL .hexChar                       ; Convert nibble 0..15 to uppercase ASCII.
    LD   (HL),A                         ; Store count digit three.
    INC  HL                             ; Advance to the next count nibble.
    LD   A,D                            ; Reload the count's high byte.
    AND  $0F                            ; Keep its lower nibble.
    CALL .hexChar                       ; Convert it to the second hexadecimal digit.
    LD   (HL),A                         ; Store count digit two.
    INC  HL                             ; Advance to the high nibble of the low byte.
    LD   A,E                            ; Select the count's low byte.
    RRCA                                ; Move bit four into the low nibble.
    RRCA                                ; Move bit five into the low nibble.
    RRCA                                ; Move bit six into the low nibble.
    RRCA                                ; Move bit seven into the low nibble.
    AND  $0F                            ; Keep the third hexadecimal digit.
    CALL .hexChar                       ; Convert it to uppercase ASCII.
    LD   (HL),A                         ; Store count digit one.
    INC  HL                             ; Advance to the least-significant nibble.
    LD   A,E                            ; Reload the low count byte.
    AND  $0F                            ; Keep its lower nibble.
    CALL .hexChar                       ; Convert it to the final hexadecimal digit.
    LD   (HL),A                         ; Store count digit zero.
    INC  HL                             ; Advance to the data-fill separator.
    LD   A,','                          ; DS uses an explicit fill byte for IMAGE output.
    LD   (HL),A                         ; Separate count from the zero fill value.
    INC  HL                             ; Advance to the final fill digit.
    LD   A,'0'                          ; The sink replaces each fill byte with payload.
    LD   (HL),A                         ; Store the tenth replacement character.
    INC  HL                             ; Point at the following 28-byte row boundary.
    LD   (binFree),HL                   ; Save the append cursor only after completion.
    LD   HL,binCount                    ; Publish the fully initialised metadata record.
    INC  (HL)                           ; Include this row in the bounded table.
    RET                                 ; Return with carry clear.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert one four-bit count nibble to an uppercase hexadecimal character.

.hexChar: ; Convert a count nibble to uppercase ASCII.
    CP   10                             ; Values zero through nine use decimal glyphs.
    JR   C,.digit                       ; Keep their ASCII representation direct.
    ADD  A,'A'-10                       ; Convert ten through fifteen to A through F.
    RET                                 ; Return the complete uppercase hex digit.
.digit: ; Convert a decimal count nibble to ASCII.
    ADD  A,'0'                          ; Convert the nibble to its ASCII digit.
    RET                                 ; Return the completed replacement character.

binExit: ; Return the selected binary preflight error.
    RET                                 ; Preserve the detailed error selected above.
binBad: ; Report malformed INCBIN source.
    CALL binLoc                         ; Identify the malformed INCBIN line.
    LD   DE,msgBin                      ; Select the source-syntax diagnostic.
    SCF                                 ; Stop before output generation begins.
    RET                                 ; Return the user-facing detail in DE.
binFull: ; Report native INCBIN table capacity.
    CALL binLoc                         ; Point to the first excess include.
    LD   DE,msgFull                     ; Report the published native-profile limit.
    SCF                                 ; Do not write beyond the fixed table.
    RET                                 ; Return the capacity detail in DE.
binLost: ; Report changed or unreadable source bytes.
    CALL binLoc                         ; Identify the part whose bytes changed.
    LD   DE,msgRead                     ; Reuse the established CP/M source read text.
    SCF                                 ; A measured source cannot end during collection.
    RET                                 ; The measured descriptor length differs from the file.
binLoc: ; Render the INCBIN source anchor.
    LD   A,(binPart)                    ; Publish the dependency-order source ordinal.
    LD   (stAtPart),A                   ; Reuse the public source-diagnostic contract.
    LD   HL,(binSite)                   ; Point at the exact INCBIN operation name.
    LD   (stAtOff),HL                   ; Keep the byte offset while location is rendered.
    CALL errWhere                       ; Print source filename and line:column.
    LD   A,' '                          ; Separate the location from its diagnostic text.
    JP   cpPutCh                        ; Return after the field separator.

binNext: ; Advance binary preflight to the next source part.
    LD   HL,binPart                     ; Advance to the next dependency-ordered source.
    INC  (HL)                           ; Descriptor ordinals are consecutive bytes.
    LD   A,(HL)                         ; Read the next part or final descriptor count.
    LD   HL,cpDesc                      ; Address the published number of resolved parts.
    CP   (HL)                           ; Equality means every source part was scanned.
    JR   Z,.enable                      ; Enable the complete metadata table.
    LD   HL,(binDesc)                   ; Select the descriptor just completed.
    LD   DE,5                           ; Each Atom source descriptor occupies five bytes.
    ADD  HL,DE                          ; Point to the next dependency-order descriptor.
    LD   (binDesc),HL                   ; Retain its address for the next part.
    CALL binRange                       ; Load the following part's exclusive end.
    LD   HL,0                           ; Each source part has its own zero origin.
    LD   (binPos),HL                    ; Restart scanning at its first byte.
    JP   binScan                        ; Continue with the next resolved source.
.enable: ; Publish the complete binary table and reset consumers.
    XOR  A                              ; Runtime filtering begins with table row zero.
    LD   (binFIdx),A                    ; Initialize the binary-lowering cursor.
    LD   (binSIdx),A                    ; The output sink consumes rows in source order.
    LD   HL,binTable                    ; Point both consumers to the first fixed row.
    LD   (binFPtr),HL                   ; Runtime source transformation starts here.
    LD   (binSPtr),HL                   ; IMAGE dispatch starts at the same source anchor.
    LD   A,$FF                          ; Make filtering resynchronize at the first byte.
    LD   (binFPart),A                   ; No source part has been filtered yet.
    LD   HL,$FFFF                       ; No valid source offset equals this sentinel.
    LD   (binFPos),HL                   ; Peeks can detect backward source reads.
    XOR  A                              ; No binary file is open and no sink is active.
    LD   (binBusy),A                    ; Clear the current binary statement state.
    LD   (binHeld),A                    ; The dedicated binary FCB is closed.
    LD   (binLeft),A                    ; No binary record bytes are buffered.
    LD   HL,0                           ; No payload byte is expected before Atom begins.
    LD   (binDue),HL                    ; Clear the active statement's remaining count.
    LD   A,$FF                          ; Make Atom's first source read reopen part zero.
    LD   (srcPart),A                    ; Preflight left the last source file open at EOF.
    XOR  A                              ; Keep this operation's status clear for callers.
    INC  A                              ; Only now expose all completely validated rows.
    LD   (binReady),A                   ; Live rewriting starts at the assembly boundary.
    RET                                 ; Return success with metadata ready for Atom.
