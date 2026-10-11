;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Decode the current part's exclusive logical end for binary preflight.

BIN_RNG: ; Decode the current source descriptor end.
    LD   HL,(BIN_DESC)                  ; Point to the current five-byte descriptor.
    LD   DE,3                           ; Its exclusive logical end begins at byte three.
    ADD  HL,DE                          ; Address the low byte of the end offset.
    LD   E,(HL)                         ; Read the low byte of this source's length.
    INC  HL                             ; Advance to the high end byte.
    LD   D,(HL)                         ; Complete the sixteen-bit source length.
    EX   DE,HL                          ; Return the end offset in HL.
    LD   (BIN_STOP),HL                  ; Cache the exclusive scan boundary.
    RET                                 ; The source itself begins at logical offset zero.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read one condition-filtered source byte and advance the preflight cursor.

BIN_BYTE: ; Read and advance one filtered preflight source byte.
    LD   A,(BIN_PART)                   ; Select the resolved source-part ordinal.
    LD   HL,(BIN_POS)                   ; Read the next logical byte position.
    CALL SRC_READ                       ; Apply the ordinary CP/M source and IF filters.
    RET  C                              ; Preserve premature EOF/read failure for caller.
    LD   (BIN_TMP),A                    ; Keep the source byte during cursor update.
    LD   HL,(BIN_POS)                   ; Reload the current zero-based offset.
    INC  HL                             ; Advance to the byte after the one just read.
    LD   (BIN_POS),HL                   ; Publish the next position to every helper.
    LD   A,(BIN_TMP)                    ; Restore the filtered source byte.
    OR   A                              ; Clear carry and preserve the byte in A.
    RET                                 ; The scan cursor now names the following byte.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Collect one token into PP_TOKEN, folding lowercase ASCII to uppercase.

BIN_LEX: ; Collect a bounded uppercase source token.
    LD   (BIN_TMP),A                    ; Preserve the first byte before clearing length.
    XOR  A                              ; Start this candidate with an empty token.
    LD   (PP_TLEN),A                    ; PP_MATCH reads this exact length.
    LD   A,(BIN_TMP)                    ; Restore the first character for the token loop.
.LOOP: ; Classify and append the next token character.
    LD   (BIN_TMP),A                    ; Preserve the current byte across tests.
    CP   ' '                            ; Space completes the token without being stored.
    JR   Z,.DONE                        ; Return the delimiter to the caller.
    CP   9                              ; A tab also delimits a source token.
    JR   Z,.DONE                        ; Preserve it as the token terminator.
    CP   ':'                            ; Colon separates a label from its operation.
    JR   Z,.DONE                        ; Do not merge the label and colon.
    CP   ';'                            ; A comment begins after the token boundary.
    JR   Z,.DONE                        ; Leave comment handling to the caller.
    CP   13                             ; Carriage return terminates the physical line.
    JR   Z,.DONE                        ; Keep line endings outside the token.
    CP   10                             ; Line feed is the second accepted terminator.
    JR   Z,.DONE                        ; Return it without adding it to the token.
    LD   A,(PP_TLEN)                    ; Read the current token byte count.
    CP   17                             ; The shared token buffer has seventeen positions.
    JR   NC,.LONG                       ; Ignore overlong ordinary labels safely.
    LD   C,A                            ; Use the token length as a buffer index.
    LD   A,(BIN_TMP)                    ; Restore the source character.
    CP   'a'                            ; Check whether lowercase folding applies.
    JR   C,.CASED                       ; Leave uppercase and punctuation unchanged.
    CP   'z'+1                          ; Compare with the exclusive lowercase bound.
    JR   NC,.CASED                      ; Leave bytes outside ASCII lowercase unchanged.
    AND  $DF                            ; Fold the supported keyword to uppercase.
.CASED: ; Append the normalised token character.
    LD   (BIN_TMP),A                    ; Save the normalised character while indexing.
    LD   B,0                            ; The token length is smaller than eighteen.
    LD   A,C                            ; Place the current position in BC.
    LD   C,A                            ; Complete its one-byte index.
    LD   HL,PP_TOKEN                    ; Select the bounded token buffer.
    ADD  HL,BC                          ; Address its next free byte.
    LD   A,(BIN_TMP)                    ; Restore the normalised character.
    LD   (HL),A                         ; Append it to the token.
    LD   HL,PP_TLEN                     ; Address the token's published length.
    INC  (HL)                           ; Include the byte just stored above.
    CALL BIN_BYTE                       ; Read the following token byte or delimiter.
    JR   NC,.LOOP                       ; Continue until a delimiter is consumed.
    XOR  A                              ; EOF completes the current nonempty token.
    SCF                                 ; Mark the delimiter as end of this source part.
    RET                                 ; The caller still compares the collected token.
.DONE: ; Return the consumed token delimiter.
    LD   A,(BIN_TMP)                    ; Return the consumed delimiter to the caller.
    OR   A                              ; Clear carry and classify the delimiter byte.
    RET                                 ; PP_TOKEN contains only source token bytes.
.LONG: ; Report token overflow separately from EOF.
    LD   A,1                            ; Distinguish an overlong token from clean EOF.
    SCF                                 ; Tell the caller to ignore this unsupported name.
    RET                                 ; No partial token can equal the six-byte keyword.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted 8.3 binary name and a required numeric byte count.

BIN_ARGS: ; Parse a quoted binary filename and required count.
    LD   HL,(BIN_POS)                   ; Resume after the consumed INCBIN delimiter.
.TOQUOTE: ; Find the opening quote on this physical line.
    CALL SRC_NEXT                       ; Read the next raw byte of this source line.
    JP   C,BIN_BAD                      ; A path must begin before source end.
    CP   ' '                            ; Ignore spaces between INCBIN and its path.
    JR   Z,.TOQUOTE                     ; Keep scanning horizontal whitespace.
    CP   9                              ; Tabs are also valid between directive operands.
    JR   Z,.TOQUOTE                     ; Continue until the opening quote.
    CP   13                             ; Never let a missing path run onto another line.
    JP   Z,BIN_BAD                      ; The opening quote must be on this physical line.
    CP   10                             ; LF-only sources have the same operand boundary.
    JP   Z,BIN_BAD                      ; Keep the binary directive on its source line.
    CP   ';'                            ; A comment cannot stand in for the filename.
    JP   Z,BIN_BAD                      ; Reject an incomplete directive before assembly.
    CP   '"'                            ; CP/M accepts only a quoted current-drive name.
    JP   NZ,BIN_BAD                     ; Reject paths, comments and unquoted names.
    CALL INC_WIPE                       ; Prepare the normalised scratch filename FCB.
    CALL INC_NAME                       ; Validate and store the complete 8.3 filename.
    JP   C,BIN_BAD                      ; Reject malformed or incomplete quoted names.
    LD   (BIN_POS),HL                   ; Preserve the cursor after the closing quote.
    LD   HL,CP_FCB+1                    ; Copy the name/type the parser normalised.
    LD   DE,BIN_FILE                    ; Preserve it while work FCB builds temp names.
    LD   BC,11                          ; The filename is eight base and three type bytes.
    LDIR                                ; Keep this binary identity in private workspace.
    LD   HL,(BIN_POS)                   ; Resume at the first byte after the filename.
.TOCOMMA: ; Require a comma on the same directive line.
    CALL SRC_NEXT                       ; Read the delimiter after the closing quote.
    JP   C,BIN_BAD                      ; A byte count is mandatory on the native profile.
    CP   ' '                            ; Skip optional whitespace before the comma.
    JR   Z,.TOCOMMA                     ; Keep the operand grammar simple.
    CP   9                              ; Permit a tab before the required comma.
    JR   Z,.TOCOMMA                     ; Continue over horizontal whitespace.
    CP   13                             ; Do not search a later line for the comma.
    JP   Z,BIN_BAD                      ; A count belongs to the same INCBIN statement.
    CP   10                             ; Reject the equivalent LF-only operand break.
    JP   Z,BIN_BAD                      ; Preserve original newline bytes and semantics.
    CP   ';'                            ; A trailing comment cannot replace the count.
    JP   Z,BIN_BAD                      ; Keep the count mandatory on the directive line.
    CP   ','                            ; The second operand is the exact byte count.
    JP   NZ,BIN_BAD                     ; Reject a missing count or extra filename text.
    CALL PP_READ                        ; Read a bounded numeric literal after the comma.
    JP   C,BIN_BAD                      ; Reject a missing or overlong count token.
    LD   A,(PP_TOKEN)                   ; Inspect the first byte before definition lookup.
    CP   '0'                            ; Decimal and Intel-suffix values start as digits.
    JR   C,.PREFIX                      ; Check the two supported numeric prefixes.
    CP   '9'+1                          ; Accept decimal and 0FFFFH lexical starts.
    JR   C,.NUMBER                      ; Parse a digit-leading number.
.PREFIX: ; Accept the binary count numeric prefixes.
    CP   '$'                            ; Dollar selects hexadecimal.
    JR   Z,.NUMBER                      ; Pass the complete token to the shared parser.
    CP   '%'                            ; Percent here means binary, not a host directive.
    JP   NZ,BIN_BAD                     ; Named counts are excluded from portable INCBIN.
.NUMBER: ; Parse and validate the binary byte count.
    CALL PP_EVAL                        ; Convert decimal, hex or binary to unsigned word.
    JP   C,BIN_BAD                      ; Reject invalid digits and values above $FFFF.
    LD   (BIN_LEN),HL                   ; Preserve the declared logical payload length.
    LD   HL,(PP_SRC)                    ; Resume at the count token's trailing delimiter.
    CALL PP_EOL                         ; Allow only whitespace, EOL or a comment.
    JP   C,BIN_BAD                      ; Reject another operand or trailing source token.
    LD   (BIN_POS),HL                   ; Continue scanning after the full directive line.
    LD   (BIN_EOL),HL                   ; Start with the returned exclusive source cursor.
    CALL .TRIM                          ; Remove CR/LF from the rewriteable content range.
    JP   C,BIN_LOST                     ; A changed source cannot be rewritten safely.
    CALL .VALIDATE                      ; Check span, collision, capacity and existence.
    RET                                 ; Keep the metadata check's status and message.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Find the end of source text before a consumed CR, LF or CRLF sequence.

.TRIM: ; Find the source-content end before CR or LF.
    LD   A,H                            ; Check whether the returned end is offset zero.
    OR   L                              ; No preceding newline can exist at zero.
    RET  Z                              ; Keep an empty content range unchanged.
    DEC  HL                             ; Address the last consumed source byte.
    PUSH HL                             ; The raw source reader uses HL as a cache cursor.
    CALL SRC_RAW                        ; Inspect it without applying text transformation.
    POP  HL                             ; Restore the source offset for line-end storage.
    RET  C                              ; EOF leaves the initial exclusive end unchanged.
    CP   13                             ; A consumed CR is the first byte past the line.
    JR   Z,.TRIMAT                      ; Keep the content end before that CR.
    CP   10                             ; A consumed LF also lies outside line content.
    JR   Z,.TRIMLF                      ; Trim LF and test for a preceding CR.
    OR   A                              ; A non-newline byte returns clear carry.
    RET                                 ; The original exclusive end is already correct.
.TRIMLF: ; Trim LF and an optional preceding CR.
    LD   (BIN_EOL),HL                   ; The content ends immediately before LF.
    LD   A,H                            ; Check whether LF was the first source byte.
    OR   L                              ; No preceding CR is possible at offset zero.
    RET  Z                              ; Preserve the LF-only content boundary.
    DEC  HL                             ; Inspect the byte before LF for a CRLF pair.
    PUSH HL                             ; Keep its source offset across the cache lookup.
    CALL SRC_RAW                        ; Read only the preceding physical source byte.
    POP  HL                             ; Restore the offset before deciding the boundary.
    RET  C                              ; Keep the LF boundary if the source changed.
    CP   13                             ; CRLF has one content end before its CR byte.
    JR   Z,.TRIMAT                      ; CR is outside content as well as LF.
    OR   A                              ; A non-CR byte keeps the LF boundary. no carry.
    RET                                 ; Do not leak CP's carry for bytes below CR.
.TRIMAT: ; Record the first byte of the original line ending.
    LD   (BIN_EOL),HL                   ; Publish the first byte of the line ending.
    RET                                 ; Source offsets after the directive stay fixed.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and append one active, bounded binary include record.

.VALIDATE: ; Validate and append a bounded binary row.
    LD   A,(BIN_CNT)                    ; Read the count of preflighted binary statements.
    CP   BIN_CAP                        ; The fixed table must not be overrun.
    JP   NC,BIN_FULL                    ; Reject the thirty-third include before a write.
    LD   HL,(BIN_EOL)                   ; Load the rewriteable source-content boundary.
    LD   DE,(BIN_SITE)                  ; Locate the directive keyword start.
    OR   A                              ; Clear carry before computing the available span.
    SBC  HL,DE                          ; Count bytes from INCBIN through line content.
    LD   DE,BIN_SPAN                    ; The generated DS statement is ten bytes.
    OR   A                              ; Clear carry before checking the minimum span.
    SBC  HL,DE                          ; Can the original line hold the full replacement?
    JP   C,BIN_BAD                      ; Never move source offsets or truncate the line.
    CALL .PROBE                         ; Guard transaction names. prove the file exists.
    JP   C,BIN_EXIT                     ; Keep the failing filename and source anchor.
    CALL .APPEND                        ; Publish a complete, source-ordered table entry.
    XOR  A                              ; Return success after incrementing the row count.
    RET                                 ; The scanner continues with the next source line.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Preserve exact input names while rejecting output/temp/backup aliases.

.PROBE: ; Protect output names and probe the binary file.
    LD   DE,BIN_FCB+12                  ; Address the mutable tail of the private FCB.
    XOR  A                              ; Clear record counters, extent and random record.
    LD   B,24                           ; Eleven name bytes precede this 24-byte tail.
    CALL PUB_FILL                       ; Initialize all binary-FCB control fields.
    XOR  A                              ; Select the logged-in drive for each INCBIN file.
    LD   (BIN_FCB),A                    ; CP/M native paths cannot name another drive.
    LD   HL,BIN_FILE                    ; Read the normalised eleven-byte 8.3 identity.
    LD   DE,BIN_FCB+1                   ; Store it after the private FCB's drive byte.
    LD   BC,11                          ; Copy the complete base and extension fields.
    LDIR                                ; The runtime reader never reuses CP_FCB.
    LD   HL,BIN_FCB                     ; Compare the candidate's drive and 8.3 identity.
    LD   DE,PUB_NAME                    ; The final output name must remain protected.
    CALL CMD_SAME                       ; Z marks a destructive binary/output collision.
    JR   Z,.CLASH                       ; Do not replace an input after it was assembled.
    CALL PUB_TEMP                       ; Rebuild the transaction's temporary filename.
    LD   HL,BIN_FCB                     ; Keep the binary identity in its independent FCB.
    LD   DE,CP_FCB                      ; Compare with the temporary output name.
    CALL CMD_SAME                       ; Z means ASO or final output may overwrite input.
    JR   Z,.CLASH                       ; Reject a binary alias of the temporary file.
    CALL PUB_BAK                        ; Reconstruct the reserved backup/spool name.
    LD   HL,BIN_FCB                     ; Restore the binary FCB pointer for comparison.
    LD   DE,CP_FCB                      ; The work FCB now carries the backup name.
    CALL CMD_SAME                       ; Z means the ASO spool could destroy this input.
    JR   Z,.CLASH                       ; Protect $$B when it is the private spool.
    LD   DE,BIN_FCB                     ; Open the candidate using its dedicated FCB.
    LD   C,CP_OPEN                      ; Select CP/M file-open function fifteen.
    CALL CP_BDOS                        ; Confirm the binary exists before output begins.
    INC  A                              ; BDOS returns $FF when the file cannot be opened.
    JR   Z,.MISSING                     ; Report the source position and requested file.
    LD   DE,BIN_FCB                     ; Close the temporary validation open.
    LD   C,CP_CLOSE                     ; Select CP/M close function sixteen.
    CALL CP_BDOS                        ; Release the FCB before assembly starts.
    INC  A                              ; Convert close failure into the zero test.
    JR   Z,.NOCLOSE                     ; Do not accept an uncertain input handle.
    XOR  A                              ; Clear carry and status once validation succeeds.
    RET                                 ; BIN_FCB is ready for a clean runtime reopen.
.CLASH: ; Report a binary-input and output alias.
    CALL BIN_LOC                        ; Show the source file, line and column.
    LD   HL,BIN_FCB                     ; Name the candidate binary that aliases output.
    CALL CP_NAME                        ; Print the conflicting current-drive 8.3 name.
    LD   DE,MSG_SAME                    ; Select the destructive-name diagnostic.
    SCF                                 ; Reject this source before ASO begins.
    RET                                 ; No transaction file has been created.
.MISSING: ; Report a missing binary file.
    CALL BIN_LOC                        ; Point at the active INCBIN statement.
    LD   HL,BIN_FCB                     ; Identify the unavailable binary source.
    CALL CP_NAME                        ; Print its exact CP/M filename.
    LD   DE,MSG_LOAD                    ; Select the binary-input diagnostic suffix.
    SCF                                 ; Refuse to assemble a missing payload.
    RET                                 ; The prior output remains untouched.
.NOCLOSE: ; Report a failed binary preflight close.
    CALL BIN_LOC                        ; Keep the source anchor on close failure.
    LD   HL,BIN_FCB                     ; Identify the FCB whose close failed.
    CALL CP_NAME                        ; Print the requested binary filename.
    LD   DE,MSG_LOAD                    ; Report the preflight file operation failure.
    SCF                                 ; Stop before the assembler begins a generation.
    RET                                 ; No partial operation stream exists.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the normalised source anchor, count, name and DS replacement text.

.APPEND: ; Write the complete binary metadata and DS replacement.
    LD   HL,(BIN_FREE)                  ; Select the next unused metadata row.
    LD   A,(BIN_PART)                   ; Store its dependency-ordered source part.
    LD   (HL),A                         ; Byte zero keys both filtering and sink dispatch.
    INC  HL                             ; Advance to the exact INCBIN keyword offset.
    LD   DE,(BIN_SITE)                  ; Load the operation's original source position.
    LD   (HL),E                         ; Store the offset low byte.
    INC  HL                             ; Advance to the offset high byte.
    LD   (HL),D                         ; Complete the stable statement anchor.
    INC  HL                             ; Advance to the source line's content end.
    LD   DE,(BIN_EOL)                   ; Load the exclusive end before CR/LF.
    LD   (HL),E                         ; Store the line-end low byte.
    INC  HL                             ; Advance to the line-end high byte.
    LD   (HL),D                         ; Preserve every original line-ending offset.
    INC  HL                             ; Advance to the requested binary byte count.
    LD   DE,(BIN_LEN)                   ; Load the explicit payload length.
    LD   (HL),E                         ; Store the count low byte.
    INC  HL                             ; Advance to the count high byte.
    LD   (HL),D                         ; Complete the sixteen-bit logical length.
    INC  HL                             ; Advance to the eleven-byte normalised name.
    EX   DE,HL                          ; Keep the row cursor in DE while copying.
    LD   HL,BIN_FILE                    ; Read the candidate's base and type fields.
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
    LD   DE,(BIN_LEN)                   ; Load both count bytes for nibble extraction.
    LD   A,D                            ; Select the high byte's upper nibble.
    RRCA                                ; Move bit four into the low nibble.
    RRCA                                ; Move bit five into the low nibble.
    RRCA                                ; Move bit six into the low nibble.
    RRCA                                ; Move bit seven into the low nibble.
    AND  $0F                            ; Keep only the most-significant hex digit.
    CALL .HEXCHAR                       ; Convert nibble 0..15 to uppercase ASCII.
    LD   (HL),A                         ; Store count digit three.
    INC  HL                             ; Advance to the next count nibble.
    LD   A,D                            ; Reload the count's high byte.
    AND  $0F                            ; Keep its lower nibble.
    CALL .HEXCHAR                       ; Convert it to the second hexadecimal digit.
    LD   (HL),A                         ; Store count digit two.
    INC  HL                             ; Advance to the high nibble of the low byte.
    LD   A,E                            ; Select the count's low byte.
    RRCA                                ; Move bit four into the low nibble.
    RRCA                                ; Move bit five into the low nibble.
    RRCA                                ; Move bit six into the low nibble.
    RRCA                                ; Move bit seven into the low nibble.
    AND  $0F                            ; Keep the third hexadecimal digit.
    CALL .HEXCHAR                       ; Convert it to uppercase ASCII.
    LD   (HL),A                         ; Store count digit one.
    INC  HL                             ; Advance to the least-significant nibble.
    LD   A,E                            ; Reload the low count byte.
    AND  $0F                            ; Keep its lower nibble.
    CALL .HEXCHAR                       ; Convert it to the final hexadecimal digit.
    LD   (HL),A                         ; Store count digit zero.
    INC  HL                             ; Advance to the data-fill separator.
    LD   A,','                          ; DS uses an explicit fill byte for IMAGE output.
    LD   (HL),A                         ; Separate count from the zero fill value.
    INC  HL                             ; Advance to the final fill digit.
    LD   A,'0'                          ; The sink replaces each fill byte with payload.
    LD   (HL),A                         ; Store the tenth replacement character.
    INC  HL                             ; Point at the following 28-byte row boundary.
    LD   (BIN_FREE),HL                  ; Save the append cursor only after completion.
    LD   HL,BIN_CNT                     ; Publish the fully initialised metadata record.
    INC  (HL)                           ; Include this row in the bounded table.
    RET                                 ; Return with carry clear.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert one four-bit count nibble to an uppercase hexadecimal character.

.HEXCHAR: ; Convert a count nibble to uppercase ASCII.
    CP   10                             ; Values zero through nine use decimal glyphs.
    JR   C,.DIGIT                       ; Keep their ASCII representation direct.
    ADD  A,'A'-10                       ; Convert ten through fifteen to A through F.
    RET                                 ; Return the complete uppercase hex digit.
.DIGIT: ; Convert a decimal count nibble to ASCII.
    ADD  A,'0'                          ; Convert the nibble to its ASCII digit.
    RET                                 ; Return the completed replacement character.

BIN_EXIT: ; Return the selected binary preflight error.
    RET                                 ; Preserve the detailed error selected above.
BIN_BAD: ; Report malformed INCBIN source.
    CALL BIN_LOC                        ; Identify the malformed INCBIN line.
    LD   DE,MSG_BIN                     ; Select the source-syntax diagnostic.
    SCF                                 ; Stop before output generation begins.
    RET                                 ; Return the user-facing detail in DE.
BIN_FULL: ; Report native INCBIN table capacity.
    CALL BIN_LOC                        ; Point to the first excess include.
    LD   DE,MSG_FULL                    ; Report the published native-profile limit.
    SCF                                 ; Do not write beyond the fixed table.
    RET                                 ; Return the capacity detail in DE.
BIN_LOST: ; Report changed or unreadable source bytes.
    CALL BIN_LOC                        ; Identify the part whose bytes changed.
    LD   DE,MSG_READ                    ; Reuse the established CP/M source read text.
    SCF                                 ; A measured source cannot end during collection.
    RET                                 ; The measured descriptor length differs from the file.
BIN_LOC: ; Render the INCBIN source anchor.
    LD   A,(BIN_PART)                   ; Publish the dependency-order source ordinal.
    LD   (ST_EPART),A                   ; Reuse the public source-diagnostic contract.
    LD   HL,(BIN_SITE)                  ; Point at the exact INCBIN operation name.
    LD   (ST_EOFF),HL                   ; Keep the byte offset while location is rendered.
    CALL ERR_LOC                        ; Print source filename and line:column.
    LD   A,' '                          ; Separate the location from its diagnostic text.
    JP   CP_PUTC                        ; Return after the field separator.

BIN_NEXT: ; Advance binary preflight to the next source part.
    LD   HL,BIN_PART                    ; Advance to the next dependency-ordered source.
    INC  (HL)                           ; Descriptor ordinals are consecutive bytes.
    LD   A,(HL)                         ; Read the next part or final descriptor count.
    LD   HL,CP_DESC                     ; Address the published number of resolved parts.
    CP   (HL)                           ; Equality means every source part was scanned.
    JR   Z,.ENABLE                      ; Enable the complete metadata table.
    LD   HL,(BIN_DESC)                  ; Select the descriptor just completed.
    LD   DE,5                           ; Each Atom source descriptor occupies five bytes.
    ADD  HL,DE                          ; Point to the next dependency-order descriptor.
    LD   (BIN_DESC),HL                  ; Retain its address for the next part.
    CALL BIN_RNG                        ; Load the following part's exclusive end.
    LD   HL,0                           ; Each source part has its own zero origin.
    LD   (BIN_POS),HL                   ; Restart scanning at its first byte.
    JP   BIN_SCAN                       ; Continue with the next resolved source.
.ENABLE: ; Publish the complete binary table and reset consumers.
    XOR  A                              ; Runtime filtering begins with table row zero.
    LD   (BIN_FIDX),A                   ; Initialize the binary-lowering cursor.
    LD   (BIN_SIDX),A                   ; The output sink consumes rows in source order.
    LD   HL,BIN_TAB                     ; Point both consumers to the first fixed row.
    LD   (BIN_FPTR),HL                  ; Runtime source transformation starts here.
    LD   (BIN_SPTR),HL                  ; IMAGE dispatch starts at the same source anchor.
    LD   A,$FF                          ; Make filtering resynchronize at the first byte.
    LD   (BIN_FORD),A                   ; No source part has been filtered yet.
    LD   HL,$FFFF                       ; No valid source offset equals this sentinel.
    LD   (BIN_FPOS),HL                  ; Peeks can detect backward source reads.
    XOR  A                              ; No binary file is open and no sink is active.
    LD   (BIN_BUSY),A                   ; Clear the current binary statement state.
    LD   (BIN_HELD),A                   ; The dedicated binary FCB is closed.
    LD   (BIN_LEFT),A                   ; No binary record bytes are buffered.
    LD   HL,0                           ; No payload byte is expected before Atom begins.
    LD   (BIN_DUE),HL                   ; Clear the active statement's remaining count.
    LD   A,$FF                          ; Make Atom's first source read reopen part zero.
    LD   (SRC_PART),A                   ; Preflight left the last source file open at EOF.
    XOR  A                              ; Keep this operation's status clear for callers.
    INC  A                              ; Only now expose all completely validated rows.
    LD   (BIN_LIVE),A                   ; Live rewriting starts at the assembly boundary.
    RET                                 ; Return success with metadata ready for Atom.
