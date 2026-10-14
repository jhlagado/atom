; The include graph: find every %INCLUDE and order the parts depth first.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve the root source and its leading %INCLUDE graph. Names are retained
; as exact CP/M 8.3 identities, while descriptors are emitted in dependency-
; first order. No intermediate source-order file is involved.

incSort: ; Discover and order the complete include graph.
    XOR  A                              ; Start with no published descriptors or order.
    LD   (cpDesc),A                     ; The native core must not see a stale part count.
    LD   (incDone),A                    ; No source has reached dependency order yet.
    LD   (incIdx),A                     ; Discovery begins at root ordinal zero.
    INC  A                              ; The root itself is the first retained name.
    LD   (incFound),A                   ; Record one known source part.
    LD   HL,srcFcb+1                    ; Skip the drive byte and retain the 8.3 name.
    LD   DE,incNames                    ; Store it in the root's ordinal-zero slot.
    LD   BC,11                          ; FCB name and type fields occupy eleven bytes.
    LDIR                                ; Copy the root name into the resolver table.
    LD   A,$FF                          ; Prepare the source-selection field for this run.
    LD   (srcPart),A                    ; Clear any stale current-part selection.

; First discover every exact name reachable from the root.

.discover: ; Scan each discovered filename for dependencies.
    XOR  A                              ; Mode zero records newly found include names.
    LD   (incMode),A                    ; Discovery does not test dependency ordering.
    LD   A,(incIdx)                     ; Select the next retained source name.
    CALL incScan                        ; Read its leading header and visit its includes.
; The scan helper reports malformed input, open failure or offset overflow.
    JP   C,.fail                        ; Stop on any reported scan failure.
    LD   HL,incIdx                      ; Advance the discovery cursor in place.
    INC  (HL)                           ; Each retained name is scanned for dependencies.
    LD   A,(incFound)                   ; New includes may have extended this count.
    CP   (HL)                           ; Compare the next ordinal with the live count.
    JR   NZ,.discover                   ; Scan every discovered source part.

; Place each part after its includes, depth first, so parts reach Atom in
; the order their text would appear if every include were pasted in place.
; Each walk starts at the root and follows the first unplaced include until
; it reaches a part whose includes are all placed. Bit 7 of the first
; retained-name byte marks a placed part. Name comparisons and FCB
; reconstruction mask it away. A walk longer than the part count must revisit
; a part, which proves a cycle without recursion.

.place: ; Walk from the root to the next part to place.
    XOR  A                              ; Start each walk at the root.
    LD   (incIdx),A                     ; The root is ordinal zero.
    LD   (incSteps),A                   ; No includes followed yet.
.walk: ; Check whether the current part's includes are all placed.
    LD   A,1                            ; Mode one checks whether the includes are ready.
    LD   (incMode),A                    ; The scanner reports one for a pending child.
    LD   A,(incIdx)                     ; Scan this part's include header.
    CALL incScan                        ; A=0 means every include is already placed.
    JP   C,.fail                        ; Preserve scanner errors as resolver failures.
    OR   A                              ; Is an included child still unplaced?
    JR   Z,.emit                        ; No: place this part now.
    LD   HL,incSteps                    ; Count the include about to be followed.
    INC  (HL)                           ; One more step from the root.
    LD   A,(HL)                         ; Compare the walk with the part count.
    LD   HL,incFound                    ; A longer walk must revisit a part.
    CP   (HL)                           ; Steps at least the part count?
    JR   NC,.cycle                      ; Report the include cycle.
    LD   A,(incChild)                   ; Follow the first unplaced include.
    LD   (incIdx),A                     ; Its includes are checked next.
    JR   .walk                          ; Continue down the walk.
.emit: ; Append the current part to the order.
    LD   A,(incDone)                    ; Append at the next dependency-order position.
    LD   E,A                            ; E is the byte offset into the order table.
    LD   D,incOrder/256                 ; The table remains within its fixed page.
    LD   A,(incIdx)                     ; Store this source's original ordinal.
    LD   (DE),A                         ; Map output order to source identity.
    CALL incSlot                        ; Recover the name after writing the order byte.
    SET  7,(HL)                         ; Mark this name as placed for later scans.
    LD   HL,incDone                     ; Point to the number of ordered source parts.
    INC  (HL)                           ; Include the part just appended above.
    LD   A,(incIdx)                     ; Was the root just placed?
    OR   A                              ; The root follows all of its includes.
    JR   NZ,.place                      ; Walk again for the next part.
    JR   .build                         ; Every reachable part is now ordered.
.cycle: ; A walk revisited a part.
    LD   DE,msgLoop                     ; Select the include-cycle message.
    JR   .fail                          ; Report it through the shared failure path.

; Measure the already validated parts in final order and build the ordinary
; native five-byte descriptors. Each starts at logical zero and ends at the
; measured 16-bit byte length. source storage itself remains in CP/M files.

.build: ; Build source descriptors in dependency order.
    XOR  A                              ; Start at the first dependency-ordered part.
    LD   (incIdx),A                     ; This cursor indexes incOrder.
    LD   HL,incDescs                    ; Point to the native part-descriptor array.
    LD   (incDPtr),HL                   ; The append helper advances this pointer.
.nextDesc: ; Select the next resolved source to measure.
    LD   A,(incIdx)                     ; Select the next output-order position.
    LD   E,A                            ; E indexes the one-byte order table.
    LD   D,incOrder/256                 ; Address its fixed high-page storage.
    LD   A,(DE)                         ; Recover the original discovery ordinal.
    CALL srcOpen                        ; Reopen it before measuring its logical length.
    JP   C,.fail                        ; Abort if the part cannot be reopened.
    LD   HL,0                           ; Count source bytes from logical offset zero.
.measure: ; Measure source bytes through EOF.
    CALL srcNext                        ; Read a byte and advance logical offset HL.
    JR   NC,.measure                    ; Carry clear means more source bytes remain.
    OR   A                              ; A=0 means EOF/read failure. A=2 overflow.
    JP   NZ,.ioFail                     ; Report a source length beyond the 16-bit range.
    CALL incEmit                        ; Store this ordinal and measured [0,HL) range.
    LD   HL,incIdx                      ; Advance the position in dependency order.
    INC  (HL)                           ; The order table has one entry per retained name.
    LD   A,(incFound)                   ; Compare with the total number of source parts.
    CP   (HL)                           ; Continue while another descriptor remains.
    JR   NZ,.nextDesc                   ; Measure the next dependency-ordered file.
    LD   A,(incFound)                   ; Publish the final descriptor count to the core.
    LD   (cpDesc),A                     ; Descriptors are complete and ready for assembly.
    CALL binPrep                       ; Validate active binary includes before assembly.
    JP   C,.fail                        ; Preflight failure forbids an output transaction.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Return after publishing the count.
.ioFail: ; Name a source whose logical length overflowed.
    LD   HL,srcFcb                      ; Identify the overlong source.
    CALL cpPutFcb                       ; Print its parsed 8.3 name before the error text.
    LD   DE,msgRead                     ; Select the source-read error text.
.fail: ; Print resolver failure detail and return carry.
    CALL cpPrint                        ; Print the error selected in DE.
    SCF                                 ; Return failure to the command entry point.
    RET                                 ; No partial descriptor set reaches the core.


;@ROUTINE IN A OUT A,DE,CARRY CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Scan and validate one source header. Mode zero discovers names. mode one
; reports A=1 when any dependency has not yet been emitted.

incScan: ; Scan one include header under preprocessor conditions.
    CALL srcOpen                        ; Open the requested source part for scanning.
    JR   C,.fail                        ; Stop if the FCB cannot be opened.
    LD   A,1                            ; The header accepts directives until code begins.
    LD   (incHead),A                    ; A source statement closes this header.
    CALL ppClear                        ; Reset conditional state and root definitions.
    LD   HL,0                           ; Begin at the first logical source byte.
.line: ; Scan blank, comment or directive lines.

; Blank space, line endings and comment lines remain in the header. The first
; ordinary source byte closes it permanently. a later percent directive fails.

    CALL srcNext                        ; Read the byte at the current logical offset.
    JR   C,.eof                         ; Carry marks EOF, failed read or offset overflow.
    CP   ' '                            ; A space does not close the leading header.
    JR   Z,.line                        ; Continue over horizontal whitespace.
    CP   9                              ; Tabs are also header whitespace.
    JR   Z,.line                        ; Test the next byte without advancing a line.
    CP   13                             ; CR remains inside a blank header line.
    JR   Z,.line                        ; LF is checked separately for CR/LF and LF files.
    CP   10                             ; LF remains inside the leading header as well.
    JR   Z,.line                        ; Continue scanning after the line ending.
    CP   ';'                            ; Semicolon starts a source comment.
    JR   Z,.skip                        ; Ignore the remainder of that physical line.
    CP   '%'                            ; A percent byte may begin a host directive.
    JR   Z,.percent                     ; Parse one while the header is still open.
    LD   A,(incHead)                    ; Check whether the leading header is still open.
    OR   A                              ; Body source closes the header permanently.
    JR   Z,.body                        ; Closed header has no include scope.
    CALL ppScope                        ; Reject open IF state at include.
    JP   C,.invalid                     ; Preserve the required directive error.
.body: ; Close the leading header at ordinary source.
    XOR  A                              ; Any ordinary source byte closes the header.
    LD   (incHead),A                    ; Later includes and definitions are invalid.
    LD   (ppDefOk),A                    ; No definition may follow ordinary source.
    LD   A,(ppActive)                   ; Determine whether this source line is selected.
    OR   A                              ; Inactive source still closes the file header.
    JR   Z,.skip                        ; Skip inactive source text.
.skip: ; Consume the remainder of this source line.
    CALL srcSkip                        ; Discard the rest of this physical line.
    JR   NC,.line                       ; Carry clear means another line is available.
    OR   A                              ; A=0 means EOF/read failure. A=2 wrap.
    JR   Z,.complete                    ; Treat a zero status as the end of this source.
    JR   .ioFail                        ; Reject a source offset outside the 16-bit range.
.percent: ; Parse one line-leading host directive.
    CALL ppScan                         ; Parse host preprocessing directives.
    JR   C,.fail                        ; Parsing and file errors share this return path.
    OR   A                              ; In ordering mode A=1 means a child is not ready.
    JR   NZ,.done                       ; Stop so the caller can defer this source part.
    JR   .line                          ; Continue through the remaining header lines.
.eof: ; Distinguish ordinary EOF from offset overflow.
    OR   A                              ; A=0 means EOF/read failure. A=2 overflow.
    JR   NZ,.ioFail                     ; Reject a source offset that wrapped.
.complete: ; Require all conditional frames to close at EOF.
    LD   A,(ppDepth)                    ; Every conditional must be closed before EOF.
    OR   A                              ; A remaining frame is an unterminated IF.
    JR   NZ,.invalid                    ; Do not accept an incomplete conditional file.
    XOR  A                              ; No unresolved dependencies remain.
.done: ; Return dependency readiness in A.
    RET                                 ; Preserve A for the discovery/order caller.
.ioFail: ; Name a source whose scan overflowed.
    LD   HL,srcFcb                      ; The current FCB names the open part.
    CALL cpPutFcb                       ; Identify the file whose scan could not continue.
    LD   DE,msgRead                     ; Select the source-read error message.
    JR   .fail                          ; Return the read error through the shared exit.
.invalid: ; Select invalid-source-directive detail.
    LD   DE,msgDir                      ; Select syntax-error detail.
.fail: ; Return an incomplete source-scan failure.
    SCF                                 ; Carry marks failure regardless of text.
    RET                                 ; Do not accept an incomplete dependency scan.

;@ROUTINE IN HL OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the resolved ordinal and measured byte range to the descriptor table.

incEmit: ; Append a five-byte resolved source descriptor.
    LD   DE,(incDPtr)                   ; Start the next five-byte descriptor.
    LD   A,(incIdx)                     ; Assign the resolved-order ordinal.
    LD   (DE),A                         ; Descriptor byte zero is that ordinal.
    INC  DE                             ; Advance to the logical start low byte.
    XOR  A                              ; Each part starts at logical zero.
    LD   (DE),A                         ; Store the start low byte.
    INC  DE                             ; Advance to the logical start high byte.
    LD   (DE),A                         ; Store the start high byte.
    INC  DE                             ; Advance to the exclusive end low byte.
    LD   A,L                            ; HL holds the measured source length.
    LD   (DE),A                         ; Store the low byte of the half-open end.
    INC  DE                             ; Advance to the exclusive end high byte.
    LD   A,H                            ; Complete the 16-bit source length.
    LD   (DE),A                         ; Store the high byte of the half-open end.
    INC  DE                             ; Point at the following descriptor slot.
    LD   (incDPtr),DE                   ; Save the cursor for the next descriptor.
    RET                                 ; Measure the next file after return.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse INCLUDE, one quoted current-drive 8.3 name and the rest of its line.
; Discovery records the child. Ordering checks whether it was emitted.

incLine: ; Parse one quoted leading INCLUDE directive.
    LD   DE,incKey                      ; Point at the uppercase directive name.
    LD   B,7                            ; Match all seven letters in INCLUDE.
.keyByte: ; Compare each of the seven INCLUDE letters.
    CALL srcNext                        ; Read the next directive-name byte.
    JP   C,incBad                       ; A truncated name is not a directive.
    CP   'a'                            ; Test whether ASCII lowercase folding applies.
    JR   C,.keyCased                    ; Leave uppercase and punctuation unchanged.
    CP   'z'+1                          ; Test the exclusive lowercase bound.
    JR   NC,.keyCased                   ; Leave bytes beyond 'z' unchanged.
    AND  $DF                            ; Fold lowercase ASCII to uppercase.
.keyCased: ; Compare the case-folded keyword character.
    EX   DE,HL                          ; Keep the source cursor in HL.
    CP   (HL)                           ; Match the current byte against INCLUDE.
    INC  HL                             ; Advance to the next byte of the directive name.
    EX   DE,HL                          ; Restore HL as the source cursor.
    JP   NZ,incBad                      ; Reject any mismatched directive byte.
    DJNZ .keyByte                       ; Check the remaining keyword bytes.
    CALL srcNext                        ; Read the delimiter after INCLUDE.
    JP   C,incBad                       ; The keyword must have a following delimiter.
    CP   ' '                            ; Accept an ordinary space before the filename.
    JR   Z,.space                       ; Skip additional horizontal whitespace.
    CP   9                              ; Also accept a horizontal tab as delimiter.
    JP   NZ,incBad                      ; Require whitespace before the quote.
.space: ; Find the quoted filename after the directive.
    CALL srcNext                        ; Read past the current whitespace byte.
    JP   C,incBad                       ; A filename must follow the delimiter.
    CP   ' '                            ; Check for another space before the filename.
    JR   Z,.space                       ; Continue across repeated spaces.
    CP   9                              ; Check for a repeated tab.
    JR   Z,.space                       ; Continue across repeated tabs.
    CP   '"'                            ; The filename must begin with a double quote.
    JP   NZ,incBad                      ; Reject unquoted include names.
    CALL incWipe                        ; Prepare a blank current-drive filename.
    PUSH IX                             ; Save the caller's index register.
    CALL incName                        ; Store the quoted 8.3 name in the FCB.
    POP  IX                             ; Restore the caller's index register.
    RET  C                              ; Propagate an invalid or incomplete filename.
.trailing: ; Validate text after the closing filename quote.
    CALL srcNext                        ; Read the next byte after the closing quote.
    JR   C,incEof                       ; Branch on EOF or offset overflow.
    CP   ' '                            ; Permit spaces after the filename.
    JR   Z,.trailing                    ; Skip trailing spaces.
    CP   9                              ; Permit tabs after the filename.
    JR   Z,.trailing                    ; Skip trailing tabs.
    CP   ';'                            ; A semicolon starts a trailing comment.
    JR   Z,incTail                      ; Validate the rest of the comment line.
    CP   13                             ; Accept a CR line ending.
    JR   Z,incLink                      ; The include name is complete.
    CP   10                             ; Also accept an LF line ending.
    JP   NZ,incBad                      ; Reject any other trailing byte.
incLink: ; Deduplicate and order the selected include name.

; Deduplicate the eleven-byte CP/M name. Discovery adds missing names.
; Ordering reports whether each child has already been emitted.

    CALL ppMark                         ; Retain header IF state for import.
    LD   A,(ppActive)                   ; Zero means validate, but do not import.
    OR   A                              ; Zero means validate name only.
    JR   Z,.ignored                     ; Do not open or order an inactive dependency.

    PUSH IX                             ; Save IX across name lookup.
    PUSH HL                             ; Save the source cursor.
    CALL incFind                        ; Reuse a known child or append its name.
    POP  HL                             ; Restore the source cursor.
    POP  IX                             ; Restore the caller's index register.
    RET  C                              ; Return a name-capacity failure to the resolver.
    PUSH HL                             ; Save cursor across child lookup.
    CALL incPend                        ; Return the pending-child status.
    POP  HL                             ; Restore cursor. preserve result flags.
    RET                                 ; Return the pending-child status.
.ignored: ; Skip importing a validated inactive dependency.
    XOR  A                              ; An inactive import creates no pending child.
    RET                                 ; Continue preflight with the next directive.
incTail: ; Consume a validated include trailing comment.
    CALL srcSkip                        ; Consume the trailing comment through line end.
    JR   C,incEof                       ; Check the carried end status.
    JR   incLink                        ; The include line has no more source text.
incEof: ; Accept an include at ordinary EOF.
    OR   A                              ; Zero means EOF. NZ means overflow.
    JP   NZ,incBad                      ; Reject an offset that wrapped.
    JR   incLink                        ; Accept the include at end of input.
incBad: ; Return malformed-include detail.
    LD   DE,msgInc                      ; Select the malformed-include message.
    SCF                                 ; Mark the include directive as invalid.
    RET                                 ; Return the message pointer and failure flag.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted include filename into the working CP/M FCB.

incName: ; Parse a quoted current-drive 8.3 include name.
    LD   IX,cpFcb+1                     ; Begin writing the eight-byte base field.
    LD   D,8                            ; Set the base-name capacity.
    LD   C,0                            ; Count characters in the current name field.
.byte: ; Inspect the next quoted filename byte.
    CALL srcNext                        ; Read the next quoted filename byte.
    JP   C,.bad                         ; Require a complete closing quote.
    CP   '"'                            ; Check for the end of the filename.
    JR   Z,.done                        ; Validate that the final field is nonempty.
    CP   '.'                            ; Check for the single base/extension separator.
    JR   NZ,.data                       ; Other bytes belong to the current field.
    LD   A,D                            ; Read the active field's maximum width.
    CP   8                              ; Dot is valid only after the base.
    JP   NZ,.bad                        ; Reject repeated separators.
    LD   A,C                            ; Read the number of base-name characters.
    OR   A                              ; Set Z when the base field is empty.
    JP   Z,.bad                         ; Require at least one base character.
    LD   IX,cpFcb+9                     ; Continue writing at the three-byte type field.
    LD   D,3                            ; Set the extension capacity.
    LD   C,0                            ; Start the extension character count.
    JR   .byte                          ; Read the first extension character.
.data: ; Fold a filename byte before validation.
    CP   'a'                            ; Test for an ASCII lowercase filename letter.
    JR   C,.cased                       ; Keep non-lowercase bytes unchanged.
    CP   'z'+1                          ; Test the lowercase upper bound.
    JR   NC,.cased                      ; Keep bytes above 'z' unchanged.
    AND  $DF                            ; Fold ASCII lowercase for lookup.
.cased: ; Validate and store the normalised filename byte.
    CALL cmdChar                        ; Reject characters outside the CP/M name set.
    JP   C,.bad                         ; Carry marks a forbidden filename character.
    INC  C                              ; Count this field's next byte.
    LD   B,A                            ; Save byte during capacity check.
    LD   A,D                            ; Load the active base or extension limit.
    CP   C                              ; Compare limit with new length.
    JP   C,.bad                         ; Reject a field wider than 8.3 allows.
    LD   A,B                            ; Restore the normalised filename byte.
    LD   (IX+0),A                       ; Store it in the current FCB name field.
    INC  IX                             ; Advance to the next character slot.
    JR   .byte                          ; Continue through the closing quote.
.done: ; Require a nonempty final filename field.
    LD   A,C                            ; Read the character count of the final field.
    OR   A                              ; Set Z only when that field is empty.
    RET  NZ                             ; Accept a nonempty base or extension field.
.bad: ; Return malformed quoted-name detail.
    LD   DE,msgInc                      ; Select the malformed-include message.
    SCF                                 ; Mark the filename as invalid.
    RET                                 ; Return failure to the directive parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Visit a discovered include child when dependency scanning is active.

incPend: ; Report whether a discovered include child is pending.
    LD   E,A                            ; Keep the child ordinal across the mode check.
    LD   A,(incMode)                    ; Read whether this is discovery or ordering.
    OR   A                              ; Discovery mode is zero.
    RET  Z                              ; Discovery needs no pending-child result.
    LD   A,E                            ; Restore the child's retained-name ordinal.
    LD   (incChild),A                   ; Keep it for the ordering walk.
    CALL incSlot                        ; Address its eleven-byte name record.
    BIT  7,(HL)                         ; Test the emitted marker in the first name byte.
    LD   A,0                            ; Zero means child already emitted.
    RET  NZ                             ; An emitted child is ready.
    INC  A                              ; One means child is still pending.
    RET                                 ; Return one for a pending child.

;@ROUTINE OUT A CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the working include FCB to a blank 8.3 filename.

incWipe: ; Initialise a blank working include-name FCB.
    LD   DE,cpFcb                       ; Address the temporary working FCB.
    XOR  A                              ; Select the current drive.
    LD   (DE),A                         ; Clear the explicit drive byte.
    INC  DE                             ; Advance to the eleven-byte 8.3 name.
    LD   B,11                           ; Clear all eight base and three extension bytes.
    LD   A,' '                          ; CP/M represents unused name bytes with spaces.
    CALL pubFill                        ; Fill the name and extension fields.
    JP   pubClear                       ; Clear the remaining FCB control bytes.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains.

incFind: ; Find or allocate an exact retained source name.
    LD   C,0                            ; Start with retained-name ordinal zero.
.loop: ; Search each retained source-name slot.
    LD   A,(incFound)                   ; Read the number of names already retained.
    CP   C                              ; Compare count with candidate ordinal.
    JR   Z,.add                         ; Append when no existing slot remains to inspect.
    LD   A,C                            ; Select this retained name's ordinal.
    CALL incSlot                        ; Address its eleven-byte name record.
    LD   IX,cpFcb+1                     ; Address the normalised candidate filename.
    LD   B,11                           ; Compare the complete base and extension fields.
.byte: ; Compare each of the eleven name bytes.
    LD   A,(HL)                         ; Read one byte from the retained name.
    AND  $7F                            ; Ignore the emitted bit in the name.
    CP   (IX+0)                         ; Compare with the corresponding candidate byte.
    JR   NZ,.next                       ; Try the next ordinal on any mismatch.
    INC  HL                             ; Advance the retained-name cursor.
    INC  IX                             ; Advance the candidate-name cursor.
    DJNZ .byte                          ; Compare the remaining name bytes.
    LD   A,C                            ; Return the ordinal whose full name matched.
    OR   A                              ; Clear carry and set zero for ordinal zero.
    RET                                 ; Return the existing name ordinal.
.next: ; Advance after a mismatched retained name.
    INC  C                              ; Advance to the next retained-name ordinal.
    JR   .loop                          ; Continue until a name matches or the table ends.
.add: ; Append a name when no existing slot matched.

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C                            ; The next ordinal is the current number of names.
    CP   255                            ; The byte-sized table has no ordinal 255 entry.
    JR   Z,.full                        ; Reject a 256th distinct source file.
    PUSH AF                             ; Save the new source ordinal.
    CALL incSlot                        ; Address the next eleven-byte table slot.
    EX   DE,HL                          ; Put the slot destination in DE for LDIR.
    LD   HL,cpFcb+1                     ; Point to the normalised 8.3 name bytes.
    LD   BC,11                          ; Copy name and type, not drive.
    LDIR                                ; Store the new name in its ordinal slot.
    LD   HL,incFound                    ; Address the count published to the resolver.
    INC  (HL)                           ; Publish the completed name slot.
    POP  AF                             ; Return the allocated ordinal.
    OR   A                              ; Clear carry to mark successful insertion.
    RET                                 ; Return the new retained-name identity.
.full: ; Reject an excess source part before writing the table.
    LD   DE,msgCap                      ; Select the part-capacity diagnostic.
    SCF                                 ; Mark the resolver's name table as full.
    RET                                 ; Return without changing the retained-name count.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

incSlot: ; Compute an eleven-byte source-name slot address.
    LD   L,A                            ; Place the ordinal in the low byte of HL.
    LD   H,0                            ; Extend the ordinal to a 16-bit value.
    LD   D,H                            ; Clear the high byte of the temporary DE value.
    LD   E,L                            ; Copy ordinal for x11.
    ADD  HL,HL                          ; Compute twice the ordinal.
    ADD  HL,HL                          ; Compute four times the ordinal.
    ADD  HL,DE                          ; Combine to make five times the ordinal.
    ADD  HL,HL                          ; Compute ten times the ordinal.
    ADD  HL,DE                          ; Complete eleven times the ordinal.
    LD   DE,incNames                    ; Load the base of the retained-name table.
    ADD  HL,DE                          ; Convert the byte offset to the slot address.
    RET                                 ; Return this name-record address.

