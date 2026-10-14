; INCBIN preflight: find each active INCBIN before assembly starts.

; Preflight active INCBIN statements after dependency order and definitions
; are final. The scan records exact source anchors before the core starts.

binPrep: ; Collect active binary includes after source ordering.
    XOR  A                              ; Disable rewriting until the table is complete.
    LD   (binReady),A                   ; No partially collected row may reach assembly.
    LD   (binCount),A                   ; Start with an empty binary-include table.
    LD   (binErr),A                     ; Clear the source-sink failure discriminator.
    LD   HL,binTable                    ; Select the first fixed-width metadata row.
    LD   (binFree),HL                   ; The collector appends rows in source order.
    XOR  A                              ; Rescan the root to rebuild its numeric defines.
    LD   (incIdx),A                     ; Root discovery ordinal is always zero.
    LD   A,1                            ; Ordering mode checks each header child is ready.
    LD   (incMode),A                    ; Root definitions are rebuilt during this scan.
    XOR  A                              ; Scan the root header from its first source byte.
    CALL incScan                        ; Rebuild definitions without changing part order.
    RET  C                              ; Preserve a header, include or file-read failure.
    OR   A                              ; Every dependency must already be ordered.
    JP   NZ,binBad                      ; A pending root child breaks resolver invariants.
    LD   A,$FF                          ; Force the first ordered source part to reopen.
    LD   (srcPart),A                    ; Runtime conditional state resets on that open.
    XOR  A                              ; Begin scanning dependency-order ordinal zero.
    LD   (binPart),A                    ; Metadata uses the assembler's part ordinals.
    LD   HL,incDescs                    ; The first five-byte descriptor is ordinal zero.
    LD   (binDesc),HL                   ; Advance this pointer once per source part.
    LD   HL,0                           ; Each resolved source part begins at offset zero.
    LD   (binPos),HL                    ; Track the next byte requested from Atom.
    CALL binRange                       ; Cache this part's exclusive logical end.
binScan: ; Scan filtered lines for possible INCBIN tokens.
    LD   HL,(binPos)                    ; Read the next filtered source position.
    LD   DE,(binStop)                   ; Compare it with the descriptor's exclusive end.
    OR   A                              ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                          ; Has this part reached its measured end?
    JP   NC,binNext                     ; Move on without requesting an EOF byte.
    CALL binByte                        ; Mask conditionally and advance the cursor.
    JP   C,binLost                      ; A changed file cannot pass preflight.
    CP   ' '                            ; Ignore leading source indentation.
    JR   Z,binScan                      ; Skip to the first token on this physical line.
    CP   9                              ; A tab may also precede the label or directive.
    JR   Z,binScan                      ; Leave tab-separated source syntax unchanged.
    CP   13                             ; CR marks a physical line boundary.
    JR   Z,binScan                      ; The next byte may be LF or the next line.
    CP   10                             ; LF-only files use the same outer scan loop.
    JR   Z,binScan                      ; The line break was already consumed.
    CP   ';'                            ; A comment cannot contain an assembler directive.
    JP   Z,binSkip                      ; Ignore its remaining bytes through line end.
    LD   HL,(binPos)                    ; The token began at the byte just read.
    DEC  HL                             ; Convert the next-byte cursor to a start offset.
    LD   (binLine),HL                   ; Retain a possible label's source position.
    CALL binToken                       ; Collect and uppercase the first source token.
    JP   C,binLong                      ; Distinguish token length after the full scan.
binWord: ; Identify an operation token or optional label.
    LD   (binTemp),A                    ; Keep the delimiter across keyword matching.
    LD   HL,binKey                      ; Select the exact six-byte operation name.
    LD   B,6                            ; Do not accept a prefix or longer identifier.
    CALL ppMatch                        ; Compare the case-folded token buffer.
    JR   Z,.keyword                     ; A direct statement may begin with INCBIN.
    LD   A,(binTemp)                    ; Other first names may be colon labels.
    CP   ':'                            ; Test for a directly adjacent label separator.
    JP   Z,.colon                       ; Read the operation after this label.
    CP   ' '                            ; The colon may also follow source whitespace.
    JR   Z,.labSpace                    ; Check for that common label layout.
    CP   9                              ; Tabs may precede the optional colon as well.
    JR   Z,.labSpace                    ; Ignore spaces while looking for the colon.
    CP   13                             ; A consumed CR already ended this statement.
    JP   Z,binScan                      ; Do not skip the following physical source line.
    CP   10                             ; LF-only files end the token in the same way.
    JP   Z,binScan                      ; Resume right after the consumed line ending.
    JP   binSkip                        ; An unrelated statement has no binary input.
.keyword: ; Validate an exact INCBIN token boundary.
    LD   HL,(binLine)                   ; Keep the token location for malformed forms too.
    LD   (binSite),HL                   ; Diagnostics always point at this keyword.
    LD   A,(binTemp)                    ; A colon makes this token a label, not an op.
    CP   ':'                            ; Permit a label named INCBIN before another op.
    JP   Z,.colon                       ; Inspect the statement after its colon.
    CP   ' '                            ; Whitespace may precede a label's colon.
    JR   Z,.keySpace                    ; Distinguish INCBIN: from the directive form.
    CP   9                              ; A tab may also separate a label from its colon.
    JR   Z,.keySpace                    ; Use the same bounded lookahead for either form.
    CP   13                             ; A directive cannot continue on the next line.
    JP   Z,binBad                       ; Reject a missing same-line filename and count.
    CP   10                             ; LF-only source has the same operand boundary.
    JP   Z,binBad                       ; INCBIN cannot borrow operands from a later line.
    CP   0                              ; EOF after the keyword is an incomplete INCBIN.
    JP   Z,binBad                       ; Require a separator and a complete operand list.
    CP   ';'                            ; A comment without operands is still incomplete.
    JP   Z,binBad                       ; Do not read past the comment into another line.
    JP   binBad                         ; The operation requires horizontal separation.
.keySpace: ; Distinguish a label colon from INCBIN operands.
    CALL binByte                        ; Look past optional whitespace for a label colon.
    JP   C,binBad                       ; A directive with no operands is incomplete.
    CP   ' '                            ; Skip additional spaces while checking the colon.
    JR   Z,.keySpace                    ; Keep the lookahead on this physical line.
    CP   9                              ; Tabs are the only other lookahead space allowed.
    JR   Z,.keySpace                    ; Continue until colon or the first operand byte.
    CP   ':'                            ; A matching token plus colon declares a label.
    JP   Z,.colon                       ; Its following token may be another operation.
    CP   13                             ; A directive's operands must remain on this line.
    JP   Z,binBad                       ; Reject a line break before the quoted filename.
    CP   10                             ; Do not let LF-only input run into a new line.
    JP   Z,binBad                       ; Keep the directive grammar bounded to one line.
    CP   ';'                            ; An operand cannot be replaced by a comment.
    JP   Z,binBad                       ; Reject the incomplete directive before assembly.
    LD   HL,(binPos)                    ; The first nonspace operand byte was consumed.
    DEC  HL                             ; Restore the cursor for the operand parser.
    LD   (binPos),HL                    ; The quote or invalid byte stays on this line.
    JR   .direct                        ; Parse only after the boundary checks above.
.direct: ; Parse direct INCBIN operands on this line.
    CALL binArgs                        ; Validate path/count and append one metadata row.
    JP   C,binExit                      ; Keep the diagnostic selected by the helper.
    JP   binScan                        ; Continue after the consumed source line.
.labSpace: ; Check whitespace after a possible label.
    CALL binByte                        ; Find the next non-space byte after any label.
    JP   C,binScan                      ; EOF ends this final, non-directive source line.
    CP   ' '                            ; Skip another ordinary space before a colon.
    JR   Z,.labSpace                    ; Continue through the label's horizontal padding.
    CP   9                              ; Tabs have the same role around the colon.
    JR   Z,.labSpace                    ; Continue until a delimiter or another token.
    CP   ':'                            ; A colon confirms this first token is a label.
    JR   Z,.colon                       ; Parse a possible INCBIN operation next.
    CP   13                             ; The delimiter was already consumed on this line.
    JP   Z,binScan                      ; Do not skip the following source line as a tail.
    CP   10                             ; LF-only sources end the optional label probe.
    JP   Z,binScan                      ; Continue directly at the next physical line.
    JP   binSkip                        ; No colon means this is not a supported label.
.colon: ; Read the operation token after a label colon.
    CALL binByte                        ; Read the first byte after the label separator.
    JP   C,binScan                      ; A label-only final line has no binary operation.
    CP   ' '                            ; Ignore indentation before the operation name.
    JR   Z,.colon                       ; Continue across ordinary spaces.
    CP   9                              ; Tabs may separate the colon from the operation.
    JR   Z,.colon                       ; Continue across horizontal whitespace.
    CP   13                             ; A line ending means the label has no operation.
    JP   Z,binScan                      ; Begin the next physical line across this module.
    CP   10                             ; An LF-only line has the same empty-tail result.
    JP   Z,binScan                      ; Resume at the byte after LF across this module.
    CP   ';'                            ; A trailing comment has no operation token.
    JR   Z,binSkip                      ; Consume its remaining line before continuing.
    LD   HL,(binPos)                    ; The operation token began at the byte read.
    DEC  HL                             ; Convert the next-byte cursor to a start offset.
    LD   (binSite),HL                   ; Store the exact diagnostic/sink position.
    CALL binToken                       ; Collect the operation following the label.
    JR   NC,.labelOp                    ; A consumed delimiter completes the token.
    OR   A                              ; A=1 means too long. A=0 means ordinary EOF.
    JP   NZ,binSkip                     ; An overlong operation cannot equal INCBIN.
    XOR  A                              ; EOF delimits an incomplete directive.
.labelOp: ; Match the complete operation after a label.
    LD   (binTemp),A                    ; Preserve the operation's following delimiter.
    LD   HL,binKey                      ; Select the supported binary directive name.
    LD   B,6                            ; Match every letter in INCBIN.
    CALL ppMatch                        ; Compare without accepting an identifier prefix.
    JR   NZ,.otherOp                    ; Other labeled statements need no rewrite.
    LD   A,(binTemp)                    ; The directive needs same-line horizontal space.
    CP   ' '                            ; Ordinary spaces separate the quoted operand.
    JR   Z,.labeled                     ; Parse after validating this boundary.
    CP   9                              ; Tabs are the other accepted separator.
    JP   NZ,binBad                      ; Do not consume a path from another source line.
.labeled: ; Parse operands for a labelled INCBIN.
    CALL binArgs                        ; Preflight and record the labeled binary input.
    JP   C,binExit                      ; Stop before any output transaction begins.
    JP   binScan                        ; Continue at the next unconsumed source byte.
.otherOp: ; Skip operands of an unrelated operation.
    LD   A,(binTemp)                    ; The parser already consumed this delimiter.
    CP   ';'                            ; A comment delimiter requires skipping its tail.
    JR   Z,binSkip                      ; Ignore the rest of the physical line.
    CP   ' '                            ; A non-INCBIN statement may have more operands.
    JR   Z,binSkip                      ; Skip them without scanning their text as labels.
    CP   9                              ; Tabs also begin the remainder of the statement.
    JR   Z,binSkip                      ; Keep operand names out of directive detection.
    JP   binScan                        ; CR, LF or EOF was already consumed.
binLong: ; Distinguish token overflow from ordinary EOF.
    OR   A                              ; A=1 marks an overlong token. A=0 marks EOF.
    JP   Z,binWord                      ; An exact INCBIN token at EOF is malformed.
    JP   binSkip                        ; No supported directive exceeds the token limit.
binSkip: ; Consume the remainder of a non-INCBIN line.
    LD   HL,(binPos)                    ; Stop at the measured part end if needed.
    LD   DE,(binStop)                   ; Keep random reads inside the source descriptor.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is there another byte on this line?
    JP   NC,binScan                     ; The next iteration advances to another part.
    CALL binByte                        ; Consume one filtered byte from the comment/tail.
    JP   C,binLost                      ; A premature read failure is not EOF.
    CP   13                             ; CR ends the current physical line.
    JP   Z,binScan                      ; Resume after LF at the outer scan loop.
    CP   10                             ; LF-only and CRLF sources share this terminator.
    JR   NZ,binSkip                     ; Keep scanning until either byte is consumed.
    JP   binScan                        ; Resume after LF without changing source offsets.
