SRC_CBEG: ; Beginning of source and include-resolution code.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare a blank ordinary FCB whose name/type fields are space-filled.

SRC_WIPE: ; Initialise a blank current-drive source FCB.
    LD   DE,SRC_FCB                     ; Point at the input FCB's drive byte.
    XOR  A                              ; Select the logged-in drive by default.
    LD   (DE),A                         ; Store drive zero before filling the name.
    INC  DE                             ; Advance to the eleven name/type bytes.
    LD   B,11                           ; Count all eight name and three type bytes.
    LD   A,' '                          ; CP/M pads unused name fields with spaces.
    CALL PUB_FILL                       ; Fill the complete name/type area.
    JP   PUB_TAIL                       ; Clear the remaining FCB control fields.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reject output, temporary or backup names that collide with the source name.

SRC_CHK: ; Protect source names against output and work files.
    LD   HL,SRC_FCB                     ; Keep the original source identity in HL.
    LD   DE,PUB_NAME                    ; Compare it with the requested output name.
    CALL CMD_SAME                       ; Z means both twelve-byte FCB identities match.
    JR   Z,.CLASH                       ; Never replace the source file.
    CALL PUB_TEMP                       ; Construct the temporary output filename.
    LD   HL,SRC_FCB                     ; Restore the source FCB pointer for comparison.
    LD   DE,CP_FCB                      ; The temporary name occupies the work FCB.
    CALL CMD_SAME                       ; Reject a temporary name that aliases the source.
    JR   Z,.CLASH                       ; Preserve the source file.
    CALL PUB_BAK                        ; Construct the backup filename for the output.
    LD   HL,SRC_FCB                     ; Compare the source against that third identity.
    LD   DE,CP_FCB                      ; The backup candidate is now in the work FCB.
    CALL CMD_SAME                       ; Z again means the names would collide.
    JR   Z,.CLASH                       ; Refuse a source/output collision.
    XOR  A                              ; A=0 reports that all three names are distinct.
    RET                                 ; Return clear carry with the success result.
.CLASH: ; Return a source and output alias failure.
    LD   DE,MSG_DUP                     ; Return the collision message in DE.
    SCF                                 ; Mark the preflight check as failed.
    RET                                 ; Leave file creation to the caller's error path.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Read one logical source byte through a 128-byte random-record cache. The
; pre-scan proves each requested record exists until this command returns.

SRC_READ: ; Expose the source-byte service to the core.
    JP   SRC_BYTE                       ; Expose the resolved source-byte reader.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve the root source and its leading %INCLUDE graph. Names are retained
; as exact CP/M 8.3 identities, while descriptors are emitted in dependency-
; first order. No intermediate source-order file is involved.

INC_SORT: ; Discover and order the complete include graph.
    XOR  A                              ; Start with no published descriptors or order.
    LD   (CP_DESC),A                    ; The native core must not see a stale part count.
    LD   (INC_OCNT),A                   ; No source has reached dependency order yet.
    LD   (INC_IDX),A                    ; Discovery begins at root ordinal zero.
    INC  A                              ; The root itself is the first retained name.
    LD   (INC_NCNT),A                   ; Record one known source part.
    LD   HL,SRC_FCB+1                   ; Skip the drive byte and retain the 8.3 name.
    LD   DE,INC_LIST                    ; Store it in the root's ordinal-zero slot.
    LD   BC,11                          ; FCB name and type fields occupy eleven bytes.
    LDIR                                ; Copy the root name into the resolver table.
    LD   A,$FF                          ; Prepare the source-selection field for this run.
    LD   (SRC_PART),A                   ; Clear any stale current-part selection.

; First discover every exact name reachable from the root.

.DISCOVER: ; Scan each discovered filename for dependencies.
    XOR  A                              ; Mode zero records newly found include names.
    LD   (INC_MODE),A                   ; Discovery does not test dependency ordering.
    LD   A,(INC_IDX)                    ; Select the next retained source name.
    CALL INC_SCAN                       ; Read its leading header and visit its includes.
; The scan helper reports malformed input, open failure or offset overflow.
    JP   C,.FAIL                        ; Stop on any reported scan failure.
    LD   HL,INC_IDX                     ; Advance the discovery cursor in place.
    INC  (HL)                           ; Each retained name is scanned for dependencies.
    LD   A,(INC_NCNT)                   ; New includes may have extended this count.
    CP   (HL)                           ; Compare the next ordinal with the live count.
    JR   NZ,.DISCOVER                   ; Scan every discovered source part.

; Emit parts after their dependencies. Bit 7 of the first retained-name byte
; marks an emitted part. Name comparisons and FCB reconstruction mask it away.
; A pass with no progress proves a cycle without recursion.

.PASS: ; Begin another nonrecursive dependency-order pass.
    XOR  A                              ; Begin another pass over all discovered files.
    LD   (INC_IDX),A                    ; Restart at the root ordinal.
    LD   (INC_GAIN),A                   ; Track whether this pass emits any source.
.TRYPART: ; Attempt to place one not-yet-emitted source.
    LD   A,(INC_IDX)                    ; Read the candidate part's ordinal.
    CALL INC_SLOT                       ; HL points to its retained eleven-byte name.
    BIT  7,(HL)                         ; Bit 7 marks a part already placed in the order.
    JR   NZ,.NEXTPART                   ; Do not emit a part twice.
    LD   A,1                            ; Mode one checks whether the includes are ready.
    LD   (INC_MODE),A                   ; The scanner reports one for a pending child.
    LD   A,(INC_IDX)                    ; Scan this part's include header.
    CALL INC_SCAN                       ; A=0 means every dependency is already ordered.
    JP   C,.FAIL                        ; Preserve scanner errors as resolver failures.
    OR   A                              ; Is an included child still unordered?
    JR   NZ,.NEXTPART                   ; Defer this part until a later pass.
    LD   A,(INC_OCNT)                   ; Append at the next dependency-order position.
    LD   E,A                            ; E is the byte offset into the order table.
    LD   D,INC_ORD/256                  ; The table remains within its fixed page.
    LD   A,(INC_IDX)                    ; Store this source's original ordinal.
    LD   (DE),A                         ; Map output order to source identity.
    CALL INC_SLOT                       ; Recover the name after writing the order byte.
    SET  7,(HL)                         ; Mark this name as emitted for later scans.
    LD   HL,INC_OCNT                    ; Point to the number of ordered source parts.
    INC  (HL)                           ; Include the part just appended above.
    LD   A,1                            ; Record that this pass made progress.
    LD   (INC_GAIN),A                   ; Newly ready dependants can run next pass.
.NEXTPART: ; Advance through the retained source-name table.
    LD   HL,INC_IDX                     ; Advance to the next discovered name.
    INC  (HL)                           ; The table follows original discovery order.
    LD   A,(INC_NCNT)                   ; Read the current count, including new includes.
    CP   (HL)                           ; Compare against the next candidate ordinal.
    JR   NZ,.TRYPART                    ; Continue this pass while names remain.
    LD   A,(INC_OCNT)                   ; Count the parts already placed in order.
    LD   HL,INC_NCNT                    ; Compare it with the total discovered count.
    CP   (HL)                           ; Equality means every dependency was ordered.
    JR   Z,.BUILD                       ; Build the native part descriptors.
    LD   A,(INC_GAIN)                   ; Check whether this pass placed any source.
    OR   A                              ; A zero value means ordering made no progress.
    JR   NZ,.PASS                       ; Retry now that some dependencies are ready.
    LD   DE,MSG_LOOP                    ; No progress means an include cycle.
    JR   .FAIL                          ; Report it through the shared failure path.

; Measure the already validated parts in final order and build the ordinary
; native five-byte descriptors. Each starts at logical zero and ends at the
; measured 16-bit byte length. source storage itself remains in CP/M files.

.BUILD: ; Build source descriptors in dependency order.
    XOR  A                              ; Start at the first dependency-ordered part.
    LD   (INC_IDX),A                    ; This cursor indexes INC_ORD.
    LD   HL,INC_DESC                    ; Point to the native part-descriptor array.
    LD   (INC_DPTR),HL                  ; The append helper advances this pointer.
.NEXTDESC: ; Select the next resolved source to measure.
    LD   A,(INC_IDX)                    ; Select the next output-order position.
    LD   E,A                            ; E indexes the one-byte order table.
    LD   D,INC_ORD/256                  ; Address its fixed high-page storage.
    LD   A,(DE)                         ; Recover the original discovery ordinal.
    CALL SRC_OPEN                       ; Reopen it before measuring its logical length.
    JP   C,.FAIL                        ; Abort if the part cannot be reopened.
    LD   HL,0                           ; Count source bytes from logical offset zero.
.MEASURE: ; Measure source bytes through EOF.
    CALL SRC_NEXT                       ; Read a byte and advance logical offset HL.
    JR   NC,.MEASURE                    ; Carry clear means more source bytes remain.
    OR   A                              ; A=0 means EOF/read failure. A=2 overflow.
    JP   NZ,.IOFAIL                     ; Report a source length beyond the 16-bit range.
    CALL INC_EMIT                       ; Store this ordinal and measured [0,HL) range.
    LD   HL,INC_IDX                     ; Advance the position in dependency order.
    INC  (HL)                           ; The order table has one entry per retained name.
    LD   A,(INC_NCNT)                   ; Compare with the total number of source parts.
    CP   (HL)                           ; Continue while another descriptor remains.
    JR   NZ,.NEXTDESC                   ; Measure the next dependency-ordered file.
    LD   A,(INC_NCNT)                   ; Publish the final descriptor count to the core.
    LD   (CP_DESC),A                    ; Descriptors are complete and ready for assembly.
    CALL .BINPREP                       ; Validate active binary includes before assembly.
    JP   C,.FAIL                        ; Preflight failure forbids an output transaction.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Return after publishing the count.
.IOFAIL: ; Name a source whose logical length overflowed.
    LD   HL,SRC_FCB                     ; Identify the overlong source.
    CALL CP_NAME                        ; Print its parsed 8.3 name before the error text.
    LD   DE,MSG_READ                    ; Select the source-read error text.
.FAIL: ; Print resolver failure detail and return carry.
    CALL CP_PRINT                       ; Print the error selected in DE.
    SCF                                 ; Return failure to the command entry point.
    RET                                 ; No partial descriptor set reaches the core.

; Preflight active INCBIN statements after dependency order and definitions
; are final. The scan records exact source anchors before the core starts.

.BINPREP: ; Collect active binary includes after source ordering.
    XOR  A                              ; Disable rewriting until the table is complete.
    LD   (BIN_LIVE),A                   ; No partially collected row may reach assembly.
    LD   (BIN_CNT),A                    ; Start with an empty binary-include table.
    LD   (BIN_ERR),A                    ; Clear the source-sink failure discriminator.
    LD   HL,BIN_TAB                     ; Select the first fixed-width metadata row.
    LD   (BIN_FREE),HL                  ; The collector appends rows in source order.
    XOR  A                              ; Rescan the root to rebuild its numeric defines.
    LD   (INC_IDX),A                    ; Root discovery ordinal is always zero.
    LD   A,1                            ; Ordering mode checks each header child is ready.
    LD   (INC_MODE),A                   ; Root definitions are rebuilt during this scan.
    XOR  A                              ; Scan the root header from its first source byte.
    CALL INC_SCAN                       ; Rebuild definitions without changing part order.
    RET  C                              ; Preserve a header, include or file-read failure.
    OR   A                              ; Every dependency must already be ordered.
    JP   NZ,BIN_BAD                     ; A pending root child breaks resolver invariants.
    LD   A,$FF                          ; Force the first ordered source part to reopen.
    LD   (SRC_PART),A                   ; Runtime conditional state resets on that open.
    XOR  A                              ; Begin scanning dependency-order ordinal zero.
    LD   (BIN_PART),A                   ; Metadata uses the assembler's part ordinals.
    LD   HL,INC_DESC                    ; The first five-byte descriptor is ordinal zero.
    LD   (BIN_DESC),HL                  ; Advance this pointer once per source part.
    LD   HL,0                           ; Each resolved source part begins at offset zero.
    LD   (BIN_POS),HL                   ; Track the next byte requested from Atom.
    CALL BIN_RNG                        ; Cache this part's exclusive logical end.
BIN_SCAN: ; Scan filtered lines for possible INCBIN tokens.
    LD   HL,(BIN_POS)                   ; Read the next filtered source position.
    LD   DE,(BIN_STOP)                  ; Compare it with the descriptor's exclusive end.
    OR   A                              ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                          ; Has this part reached its measured end?
    JP   NC,BIN_NEXT                    ; Move on without requesting an EOF byte.
    CALL BIN_BYTE                       ; Mask conditionally and advance the cursor.
    JP   C,BIN_LOST                     ; A changed file cannot pass preflight.
    CP   ' '                            ; Ignore leading source indentation.
    JR   Z,BIN_SCAN                     ; Skip to the first token on this physical line.
    CP   9                              ; A tab may also precede the label or directive.
    JR   Z,BIN_SCAN                     ; Leave tab-separated source syntax unchanged.
    CP   13                             ; CR marks a physical line boundary.
    JR   Z,BIN_SCAN                     ; The next byte may be LF or the next line.
    CP   10                             ; LF-only files use the same outer scan loop.
    JR   Z,BIN_SCAN                     ; The line break was already consumed.
    CP   ';'                            ; A comment cannot contain an assembler directive.
    JP   Z,BIN_SKIP                     ; Ignore its remaining bytes through line end.
    LD   HL,(BIN_POS)                   ; The token began at the byte just read.
    DEC  HL                             ; Convert the next-byte cursor to a start offset.
    LD   (BIN_LINE),HL                  ; Retain a possible label's source position.
    CALL BIN_LEX                        ; Collect and uppercase the first source token.
    JP   C,BIN_LONG                     ; Distinguish token length after the full scan.
BIN_WORD: ; Identify an operation token or optional label.
    LD   (BIN_TMP),A                    ; Keep the delimiter across keyword matching.
    LD   HL,BIN_KEY                     ; Select the exact six-byte operation name.
    LD   B,6                            ; Do not accept a prefix or longer identifier.
    CALL PP_MATCH                       ; Compare the case-folded token buffer.
    JR   Z,.KEYWORD                     ; A direct statement may begin with INCBIN.
    LD   A,(BIN_TMP)                    ; Other first names may be colon labels.
    CP   ':'                            ; Test for a directly adjacent label separator.
    JP   Z,.COLON                       ; Read the operation after this label.
    CP   ' '                            ; The colon may also follow source whitespace.
    JR   Z,.LABSPACE                    ; Check for that common label layout.
    CP   9                              ; Tabs may precede the optional colon as well.
    JR   Z,.LABSPACE                    ; Ignore spaces while looking for the colon.
    CP   13                             ; A consumed CR already ended this statement.
    JP   Z,BIN_SCAN                     ; Do not skip the following physical source line.
    CP   10                             ; LF-only files end the token in the same way.
    JP   Z,BIN_SCAN                     ; Resume right after the consumed line ending.
    JP   BIN_SKIP                       ; An unrelated statement has no binary input.
.KEYWORD: ; Validate an exact INCBIN token boundary.
    LD   HL,(BIN_LINE)                  ; Keep the token location for malformed forms too.
    LD   (BIN_SITE),HL                  ; Diagnostics always point at this keyword.
    LD   A,(BIN_TMP)                    ; A colon makes this token a label, not an op.
    CP   ':'                            ; Permit a label named INCBIN before another op.
    JP   Z,.COLON                       ; Inspect the statement after its colon.
    CP   ' '                            ; Whitespace may precede a label's colon.
    JR   Z,.KEYSPACE                    ; Distinguish INCBIN: from the directive form.
    CP   9                              ; A tab may also separate a label from its colon.
    JR   Z,.KEYSPACE                    ; Use the same bounded lookahead for either form.
    CP   13                             ; A directive cannot continue on the next line.
    JP   Z,BIN_BAD                      ; Reject a missing same-line filename and count.
    CP   10                             ; LF-only source has the same operand boundary.
    JP   Z,BIN_BAD                      ; INCBIN cannot borrow operands from a later line.
    CP   0                              ; EOF after the keyword is an incomplete INCBIN.
    JP   Z,BIN_BAD                      ; Require a separator and a complete operand list.
    CP   ';'                            ; A comment without operands is still incomplete.
    JP   Z,BIN_BAD                      ; Do not read past the comment into another line.
    JP   BIN_BAD                        ; The operation requires horizontal separation.
.KEYSPACE: ; Distinguish a label colon from INCBIN operands.
    CALL BIN_BYTE                       ; Look past optional whitespace for a label colon.
    JP   C,BIN_BAD                      ; A directive with no operands is incomplete.
    CP   ' '                            ; Skip additional spaces while checking the colon.
    JR   Z,.KEYSPACE                    ; Keep the lookahead on this physical line.
    CP   9                              ; Tabs are the only other lookahead space allowed.
    JR   Z,.KEYSPACE                    ; Continue until colon or the first operand byte.
    CP   ':'                            ; A matching token plus colon declares a label.
    JP   Z,.COLON                       ; Its following token may be another operation.
    CP   13                             ; A directive's operands must remain on this line.
    JP   Z,BIN_BAD                      ; Reject a line break before the quoted filename.
    CP   10                             ; Do not let LF-only input run into a new line.
    JP   Z,BIN_BAD                      ; Keep the directive grammar bounded to one line.
    CP   ';'                            ; An operand cannot be replaced by a comment.
    JP   Z,BIN_BAD                      ; Reject the incomplete directive before assembly.
    LD   HL,(BIN_POS)                   ; The first nonspace operand byte was consumed.
    DEC  HL                             ; Restore the cursor for the operand parser.
    LD   (BIN_POS),HL                   ; The quote or invalid byte stays on this line.
    JR   .DIRECT                        ; Parse only after the boundary checks above.
.DIRECT: ; Parse direct INCBIN operands on this line.
    CALL BIN_ARGS                       ; Validate path/count and append one metadata row.
    JP   C,BIN_EXIT                     ; Keep the diagnostic selected by the helper.
    JP   BIN_SCAN                       ; Continue after the consumed source line.
.LABSPACE: ; Check whitespace after a possible label.
    CALL BIN_BYTE                       ; Find the next non-space byte after any label.
    JP   C,BIN_SCAN                     ; EOF ends this final, non-directive source line.
    CP   ' '                            ; Skip another ordinary space before a colon.
    JR   Z,.LABSPACE                    ; Continue through the label's horizontal padding.
    CP   9                              ; Tabs have the same role around the colon.
    JR   Z,.LABSPACE                    ; Continue until a delimiter or another token.
    CP   ':'                            ; A colon confirms this first token is a label.
    JR   Z,.COLON                       ; Parse a possible INCBIN operation next.
    CP   13                             ; The delimiter was already consumed on this line.
    JP   Z,BIN_SCAN                     ; Do not skip the following source line as a tail.
    CP   10                             ; LF-only sources end the optional label probe.
    JP   Z,BIN_SCAN                     ; Continue directly at the next physical line.
    JP   BIN_SKIP                       ; No colon means this is not a supported label.
.COLON: ; Read the operation token after a label colon.
    CALL BIN_BYTE                       ; Read the first byte after the label separator.
    JP   C,BIN_SCAN                     ; A label-only final line has no binary operation.
    CP   ' '                            ; Ignore indentation before the operation name.
    JR   Z,.COLON                       ; Continue across ordinary spaces.
    CP   9                              ; Tabs may separate the colon from the operation.
    JR   Z,.COLON                       ; Continue across horizontal whitespace.
    CP   13                             ; A line ending means the label has no operation.
    JP   Z,BIN_SCAN                     ; Begin the next physical line across this module.
    CP   10                             ; An LF-only line has the same empty-tail result.
    JP   Z,BIN_SCAN                     ; Resume at the byte after LF across this module.
    CP   ';'                            ; A trailing comment has no operation token.
    JR   Z,BIN_SKIP                     ; Consume its remaining line before continuing.
    LD   HL,(BIN_POS)                   ; The operation token began at the byte read.
    DEC  HL                             ; Convert the next-byte cursor to a start offset.
    LD   (BIN_SITE),HL                  ; Store the exact diagnostic/sink position.
    CALL BIN_LEX                        ; Collect the operation following the label.
    JR   NC,.LABELOP                    ; A consumed delimiter completes the token.
    OR   A                              ; A=1 means too long. A=0 means ordinary EOF.
    JP   NZ,BIN_SKIP                    ; An overlong operation cannot equal INCBIN.
    XOR  A                              ; EOF delimits an incomplete directive.
.LABELOP: ; Match the complete operation after a label.
    LD   (BIN_TMP),A                    ; Preserve the operation's following delimiter.
    LD   HL,BIN_KEY                     ; Select the supported binary directive name.
    LD   B,6                            ; Match every letter in INCBIN.
    CALL PP_MATCH                       ; Compare without accepting an identifier prefix.
    JR   NZ,.OTHEROP                    ; Other labeled statements need no rewrite.
    LD   A,(BIN_TMP)                    ; The directive needs same-line horizontal space.
    CP   ' '                            ; Ordinary spaces separate the quoted operand.
    JR   Z,.LABELED                     ; Parse after validating this boundary.
    CP   9                              ; Tabs are the other accepted separator.
    JP   NZ,BIN_BAD                     ; Do not consume a path from another source line.
.LABELED: ; Parse operands for a labelled INCBIN.
    CALL BIN_ARGS                       ; Preflight and record the labeled binary input.
    JP   C,BIN_EXIT                     ; Stop before any output transaction begins.
    JP   BIN_SCAN                       ; Continue at the next unconsumed source byte.
.OTHEROP: ; Skip operands of an unrelated operation.
    LD   A,(BIN_TMP)                    ; The parser already consumed this delimiter.
    CP   ';'                            ; A comment delimiter requires skipping its tail.
    JR   Z,BIN_SKIP                     ; Ignore the rest of the physical line.
    CP   ' '                            ; A non-INCBIN statement may have more operands.
    JR   Z,BIN_SKIP                     ; Skip them without scanning their text as labels.
    CP   9                              ; Tabs also begin the remainder of the statement.
    JR   Z,BIN_SKIP                     ; Keep operand names out of directive detection.
    JP   BIN_SCAN                       ; CR, LF or EOF was already consumed.
BIN_LONG: ; Distinguish token overflow from ordinary EOF.
    OR   A                              ; A=1 marks an overlong token. A=0 marks EOF.
    JP   Z,BIN_WORD                     ; An exact INCBIN token at EOF is malformed.
    JP   BIN_SKIP                       ; No supported directive exceeds the token limit.
BIN_SKIP: ; Consume the remainder of a non-INCBIN line.
    LD   HL,(BIN_POS)                   ; Stop at the measured part end if needed.
    LD   DE,(BIN_STOP)                  ; Keep random reads inside the source descriptor.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is there another byte on this line?
    JP   NC,BIN_SCAN                    ; The next iteration advances to another part.
    CALL BIN_BYTE                       ; Consume one filtered byte from the comment/tail.
    JP   C,BIN_LOST                     ; A premature read failure is not EOF.
    CP   13                             ; CR ends the current physical line.
    JP   Z,BIN_SCAN                     ; Resume after LF at the outer scan loop.
    CP   10                             ; LF-only and CRLF sources share this terminator.
    JR   NZ,BIN_SKIP                    ; Keep scanning until either byte is consumed.
    JP   BIN_SCAN                       ; Resume after LF without changing source offsets.
