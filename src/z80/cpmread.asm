;@ROUTINE IN A OUT A,DE,CARRY CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Scan and validate one source header. Mode zero discovers names. mode one
; reports A=1 when any dependency has not yet been emitted.

INC_SCAN: ; Scan one include header under preprocessor conditions.
    CALL SRC_OPEN                       ; Open the requested source part for scanning.
    JR   C,.FAIL                        ; Stop if the FCB cannot be opened.
    LD   A,1                            ; The header accepts directives until code begins.
    LD   (INC_HEAD),A                   ; A source statement closes this header.
    CALL PP_CLEAR                       ; Reset conditional state and root definitions.
    LD   HL,0                           ; Begin at the first logical source byte.
.LINE: ; Scan blank, comment or directive lines.

; Blank space, line endings and comment lines remain in the header. The first
; ordinary source byte closes it permanently. a later percent directive fails.

    CALL SRC_NEXT                       ; Read the byte at the current logical offset.
    JR   C,.EOF                         ; Carry marks EOF, failed read or offset overflow.
    CP   ' '                            ; A space does not close the leading header.
    JR   Z,.LINE                        ; Continue over horizontal whitespace.
    CP   9                              ; Tabs are also header whitespace.
    JR   Z,.LINE                        ; Test the next byte without advancing a line.
    CP   13                             ; CR remains inside a blank header line.
    JR   Z,.LINE                        ; LF is checked separately for CR/LF and LF files.
    CP   10                             ; LF remains inside the leading header as well.
    JR   Z,.LINE                        ; Continue scanning after the line ending.
    CP   ';'                            ; Semicolon starts a source comment.
    JR   Z,.SKIP                        ; Ignore the remainder of that physical line.
    CP   '%'                            ; A percent byte may begin a host directive.
    JR   Z,.PERCENT                     ; Parse one while the header is still open.
    LD   A,(INC_HEAD)                   ; Check whether the leading header is still open.
    OR   A                              ; Body source closes the header permanently.
    JR   Z,.BODY                        ; Closed header has no include scope.
    CALL PP_SCOPE                       ; Reject open IF state at include.
    JP   C,.INVALID                     ; Preserve the required directive error.
.BODY: ; Close the leading header at ordinary source.
    XOR  A                              ; Any ordinary source byte closes the header.
    LD   (INC_HEAD),A                   ; Later includes and definitions are invalid.
    LD   (PP_DEFOK),A                   ; No definition may follow ordinary source.
    LD   A,(PP_LIVE)                    ; Determine whether this source line is selected.
    OR   A                              ; Inactive source still closes the file header.
    JR   Z,.SKIP                        ; Skip inactive source text.
.SKIP: ; Consume the remainder of this source line.
    CALL SRC_SKIP                       ; Discard the rest of this physical line.
    JR   NC,.LINE                       ; Carry clear means another line is available.
    OR   A                              ; A=0 means EOF/read failure. A=2 wrap.
    JR   Z,.COMPLETE                    ; Treat a zero status as the end of this source.
    JR   .IOFAIL                        ; Reject a source offset outside the 16-bit range.
.PERCENT: ; Parse one line-leading host directive.
    CALL PP_SCAN                        ; Parse host preprocessing directives.
    JR   C,.FAIL                        ; Parsing and file errors share this return path.
    OR   A                              ; In ordering mode A=1 means a child is not ready.
    JR   NZ,.DONE                       ; Stop so the caller can defer this source part.
    JR   .LINE                          ; Continue through the remaining header lines.
.EOF: ; Distinguish ordinary EOF from offset overflow.
    OR   A                              ; A=0 means EOF/read failure. A=2 overflow.
    JR   NZ,.IOFAIL                     ; Reject a source offset that wrapped.
.COMPLETE: ; Require all conditional frames to close at EOF.
    LD   A,(PP_DEPTH)                   ; Every conditional must be closed before EOF.
    OR   A                              ; A remaining frame is an unterminated IF.
    JR   NZ,.INVALID                    ; Do not accept an incomplete conditional file.
    XOR  A                              ; No unresolved dependencies remain.
.DONE: ; Return dependency readiness in A.
    RET                                 ; Preserve A for the discovery/order caller.
.IOFAIL: ; Name a source whose scan overflowed.
    LD   HL,SRC_FCB                     ; The current FCB names the open part.
    CALL CP_NAME                        ; Identify the file whose scan could not continue.
    LD   DE,MSG_READ                    ; Select the source-read error message.
    JR   .FAIL                          ; Return the read error through the shared exit.
.INVALID: ; Select invalid-source-directive detail.
    LD   DE,MSG_DIR                     ; Select syntax-error detail.
.FAIL: ; Return an incomplete source-scan failure.
    SCF                                 ; Carry marks failure regardless of text.
    RET                                 ; Do not accept an incomplete dependency scan.

;@ROUTINE IN HL OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the resolved ordinal and measured byte range to the descriptor table.

INC_EMIT: ; Append a five-byte resolved source descriptor.
    LD   DE,(INC_DPTR)                  ; Start the next five-byte descriptor.
    LD   A,(INC_IDX)                    ; Assign the resolved-order ordinal.
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
    LD   (INC_DPTR),DE                  ; Save the cursor for the next descriptor.
    RET                                 ; Measure the next file after return.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse INCLUDE, one quoted current-drive 8.3 name and the rest of its line.
; Discovery records the child. Ordering checks whether it was emitted.

INC_LINE: ; Parse one quoted leading INCLUDE directive.
    LD   DE,INC_KEY                     ; Point at the uppercase directive name.
    LD   B,7                            ; Match all seven letters in INCLUDE.
.KEYBYTE: ; Compare each of the seven INCLUDE letters.
    CALL SRC_NEXT                       ; Read the next directive-name byte.
    JP   C,INC_BAD                      ; A truncated name is not a directive.
    CP   'a'                            ; Test whether ASCII lowercase folding applies.
    JR   C,.KEYCASED                    ; Leave uppercase and punctuation unchanged.
    CP   'z'+1                          ; Test the exclusive lowercase bound.
    JR   NC,.KEYCASED                   ; Leave bytes beyond 'z' unchanged.
    AND  $DF                            ; Fold lowercase ASCII to uppercase.
.KEYCASED: ; Compare the case-folded keyword character.
    EX   DE,HL                          ; Keep the source cursor in HL.
    CP   (HL)                           ; Match the current byte against INCLUDE.
    INC  HL                             ; Advance to the next byte of the directive name.
    EX   DE,HL                          ; Restore HL as the source cursor.
    JP   NZ,INC_BAD                     ; Reject any mismatched directive byte.
    DJNZ .KEYBYTE                       ; Check the remaining keyword bytes.
    CALL SRC_NEXT                       ; Read the delimiter after INCLUDE.
    JP   C,INC_BAD                      ; The keyword must have a following delimiter.
    CP   ' '                            ; Accept an ordinary space before the filename.
    JR   Z,.SPACE                       ; Skip additional horizontal whitespace.
    CP   9                              ; Also accept a horizontal tab as delimiter.
    JP   NZ,INC_BAD                     ; Require whitespace before the quote.
.SPACE: ; Find the quoted filename after the directive.
    CALL SRC_NEXT                       ; Read past the current whitespace byte.
    JP   C,INC_BAD                      ; A filename must follow the delimiter.
    CP   ' '                            ; Check for another space before the filename.
    JR   Z,.SPACE                       ; Continue across repeated spaces.
    CP   9                              ; Check for a repeated tab.
    JR   Z,.SPACE                       ; Continue across repeated tabs.
    CP   '"'                            ; The filename must begin with a double quote.
    JP   NZ,INC_BAD                     ; Reject unquoted include names.
    CALL INC_WIPE                       ; Prepare a blank current-drive filename.
    PUSH IX                             ; Save the caller's index register.
    CALL INC_NAME                       ; Store the quoted 8.3 name in the FCB.
    POP  IX                             ; Restore the caller's index register.
    RET  C                              ; Propagate an invalid or incomplete filename.
.TRAILING: ; Validate text after the closing filename quote.
    CALL SRC_NEXT                       ; Read the next byte after the closing quote.
    JR   C,INC_EOF                      ; Branch on EOF or offset overflow.
    CP   ' '                            ; Permit spaces after the filename.
    JR   Z,.TRAILING                    ; Skip trailing spaces.
    CP   9                              ; Permit tabs after the filename.
    JR   Z,.TRAILING                    ; Skip trailing tabs.
    CP   ';'                            ; A semicolon starts a trailing comment.
    JR   Z,INC_TAIL                     ; Validate the rest of the comment line.
    CP   13                             ; Accept a CR line ending.
    JR   Z,INC_LINK                     ; The include name is complete.
    CP   10                             ; Also accept an LF line ending.
    JP   NZ,INC_BAD                     ; Reject any other trailing byte.
INC_LINK: ; Deduplicate and order the selected include name.

; Deduplicate the eleven-byte CP/M name. Discovery adds missing names.
; Ordering reports whether each child has already been emitted.

    CALL PP_MARK                        ; Retain header IF state for import.
    LD   A,(PP_LIVE)                    ; Zero means validate, but do not import.
    OR   A                              ; Zero means validate name only.
    JR   Z,.IGNORED                     ; Do not open or order an inactive dependency.

    PUSH IX                             ; Save IX across name lookup.
    PUSH HL                             ; Save the source cursor.
    CALL INC_FIND                       ; Reuse a known child or append its name.
    POP  HL                             ; Restore the source cursor.
    POP  IX                             ; Restore the caller's index register.
    RET  C                              ; Return a name-capacity failure to the resolver.
    PUSH HL                             ; Save cursor across child lookup.
    CALL INC_PEND                       ; Return the pending-child status.
    POP  HL                             ; Restore cursor. preserve result flags.
    RET                                 ; Return the pending-child status.
.IGNORED: ; Skip importing a validated inactive dependency.
    XOR  A                              ; An inactive import creates no pending child.
    RET                                 ; Continue preflight with the next directive.
INC_TAIL: ; Consume a validated include trailing comment.
    CALL SRC_SKIP                       ; Consume the trailing comment through line end.
    JR   C,INC_EOF                      ; Check the carried end status.
    JR   INC_LINK                       ; The include line has no more source text.
INC_EOF: ; Accept an include at ordinary EOF.
    OR   A                              ; Zero means EOF. NZ means overflow.
    JP   NZ,INC_BAD                     ; Reject an offset that wrapped.
    JR   INC_LINK                       ; Accept the include at end of input.
INC_BAD: ; Return malformed-include detail.
    LD   DE,MSG_INC                     ; Select the malformed-include message.
    SCF                                 ; Mark the include directive as invalid.
    RET                                 ; Return the message pointer and failure flag.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted include filename into the working CP/M FCB.

INC_NAME: ; Parse a quoted current-drive 8.3 include name.
    LD   IX,CP_FCB+1                    ; Begin writing the eight-byte base field.
    LD   D,8                            ; Set the base-name capacity.
    LD   C,0                            ; Count characters in the current name field.
.BYTE: ; Inspect the next quoted filename byte.
    CALL SRC_NEXT                       ; Read the next quoted filename byte.
    JP   C,.BAD                         ; Require a complete closing quote.
    CP   '"'                            ; Check for the end of the filename.
    JR   Z,.DONE                        ; Validate that the final field is nonempty.
    CP   '.'                            ; Check for the single base/extension separator.
    JR   NZ,.DATA                       ; Other bytes belong to the current field.
    LD   A,D                            ; Read the active field's maximum width.
    CP   8                              ; Dot is valid only after the base.
    JP   NZ,.BAD                        ; Reject repeated separators.
    LD   A,C                            ; Read the number of base-name characters.
    OR   A                              ; Set Z when the base field is empty.
    JP   Z,.BAD                         ; Require at least one base character.
    LD   IX,CP_FCB+9                    ; Continue writing at the three-byte type field.
    LD   D,3                            ; Set the extension capacity.
    LD   C,0                            ; Start the extension character count.
    JR   .BYTE                          ; Read the first extension character.
.DATA: ; Fold a filename byte before validation.
    CP   'a'                            ; Test for an ASCII lowercase filename letter.
    JR   C,.CASED                       ; Keep non-lowercase bytes unchanged.
    CP   'z'+1                          ; Test the lowercase upper bound.
    JR   NC,.CASED                      ; Keep bytes above 'z' unchanged.
    AND  $DF                            ; Fold ASCII lowercase for lookup.
.CASED: ; Validate and store the normalised filename byte.
    CALL CMD_CHAR                       ; Reject characters outside the CP/M name set.
    JP   C,.BAD                         ; Carry marks a forbidden filename character.
    INC  C                              ; Count this field's next byte.
    LD   B,A                            ; Save byte during capacity check.
    LD   A,D                            ; Load the active base or extension limit.
    CP   C                              ; Compare limit with new length.
    JP   C,.BAD                         ; Reject a field wider than 8.3 allows.
    LD   A,B                            ; Restore the normalised filename byte.
    LD   (IX+0),A                       ; Store it in the current FCB name field.
    INC  IX                             ; Advance to the next character slot.
    JR   .BYTE                          ; Continue through the closing quote.
.DONE: ; Require a nonempty final filename field.
    LD   A,C                            ; Read the character count of the final field.
    OR   A                              ; Set Z only when that field is empty.
    RET  NZ                             ; Accept a nonempty base or extension field.
.BAD: ; Return malformed quoted-name detail.
    LD   DE,MSG_INC                     ; Select the malformed-include message.
    SCF                                 ; Mark the filename as invalid.
    RET                                 ; Return failure to the directive parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Visit a discovered include child when dependency scanning is active.

INC_PEND: ; Report whether a discovered include child is pending.
    LD   E,A                            ; Keep the child ordinal across the mode check.
    LD   A,(INC_MODE)                   ; Read whether this is discovery or ordering.
    OR   A                              ; Discovery mode is zero.
    RET  Z                              ; Discovery needs no pending-child result.
    LD   A,E                            ; Restore the child's retained-name ordinal.
    CALL INC_SLOT                       ; Address its eleven-byte name record.
    BIT  7,(HL)                         ; Test the emitted marker in the first name byte.
    LD   A,0                            ; Zero means child already emitted.
    RET  NZ                             ; An emitted child is ready.
    INC  A                              ; One means child is still pending.
    RET                                 ; Return one for a pending child.

;@ROUTINE OUT A CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the working include FCB to a blank 8.3 filename.

INC_WIPE: ; Initialise a blank working include-name FCB.
    LD   DE,CP_FCB                      ; Address the temporary working FCB.
    XOR  A                              ; Select the current drive.
    LD   (DE),A                         ; Clear the explicit drive byte.
    INC  DE                             ; Advance to the eleven-byte 8.3 name.
    LD   B,11                           ; Clear all eight base and three extension bytes.
    LD   A,' '                          ; CP/M represents unused name bytes with spaces.
    CALL PUB_FILL                       ; Fill the name and extension fields.
    JP   PUB_TAIL                       ; Clear the remaining FCB control bytes.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains.

INC_FIND: ; Find or allocate an exact retained source name.
    LD   C,0                            ; Start with retained-name ordinal zero.
.LOOP: ; Search each retained source-name slot.
    LD   A,(INC_NCNT)                   ; Read the number of names already retained.
    CP   C                              ; Compare count with candidate ordinal.
    JR   Z,.ADD                         ; Append when no existing slot remains to inspect.
    LD   A,C                            ; Select this retained name's ordinal.
    CALL INC_SLOT                       ; Address its eleven-byte name record.
    LD   IX,CP_FCB+1                    ; Address the normalised candidate filename.
    LD   B,11                           ; Compare the complete base and extension fields.
.BYTE: ; Compare each of the eleven name bytes.
    LD   A,(HL)                         ; Read one byte from the retained name.
    AND  $7F                            ; Ignore the emitted bit in the name.
    CP   (IX+0)                         ; Compare with the corresponding candidate byte.
    JR   NZ,.NEXT                       ; Try the next ordinal on any mismatch.
    INC  HL                             ; Advance the retained-name cursor.
    INC  IX                             ; Advance the candidate-name cursor.
    DJNZ .BYTE                          ; Compare the remaining name bytes.
    LD   A,C                            ; Return the ordinal whose full name matched.
    OR   A                              ; Clear carry and set zero for ordinal zero.
    RET                                 ; Return the existing name ordinal.
.NEXT: ; Advance after a mismatched retained name.
    INC  C                              ; Advance to the next retained-name ordinal.
    JR   .LOOP                          ; Continue until a name matches or the table ends.
.ADD: ; Append a name when no existing slot matched.

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C                            ; The next ordinal is the current number of names.
    CP   255                            ; The byte-sized table has no ordinal 255 entry.
    JR   Z,.FULL                        ; Reject a 256th distinct source file.
    PUSH AF                             ; Save the new source ordinal.
    CALL INC_SLOT                       ; Address the next eleven-byte table slot.
    EX   DE,HL                          ; Put the slot destination in DE for LDIR.
    LD   HL,CP_FCB+1                    ; Point to the normalised 8.3 name bytes.
    LD   BC,11                          ; Copy name and type, not drive.
    LDIR                                ; Store the new name in its ordinal slot.
    LD   HL,INC_NCNT                    ; Address the count published to the resolver.
    INC  (HL)                           ; Publish the completed name slot.
    POP  AF                             ; Return the allocated ordinal.
    OR   A                              ; Clear carry to mark successful insertion.
    RET                                 ; Return the new retained-name identity.
.FULL: ; Reject an excess source part before writing the table.
    LD   DE,MSG_CAP                     ; Select the part-capacity diagnostic.
    SCF                                 ; Mark the resolver's name table as full.
    RET                                 ; Return without changing the retained-name count.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

INC_SLOT: ; Compute an eleven-byte source-name slot address.
    LD   L,A                            ; Place the ordinal in the low byte of HL.
    LD   H,0                            ; Extend the ordinal to a 16-bit value.
    LD   D,H                            ; Clear the high byte of the temporary DE value.
    LD   E,L                            ; Copy ordinal for x11.
    ADD  HL,HL                          ; Compute twice the ordinal.
    ADD  HL,HL                          ; Compute four times the ordinal.
    ADD  HL,DE                          ; Combine to make five times the ordinal.
    ADD  HL,HL                          ; Compute ten times the ordinal.
    ADD  HL,DE                          ; Complete eleven times the ordinal.
    LD   DE,INC_LIST                    ; Load the base of the retained-name table.
    ADD  HL,DE                          ; Convert the byte offset to the slot address.
    RET                                 ; Return this name-record address.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the ordinary input FCB from one retained name.

SRC_OPEN: ; Open the source named by its discovery ordinal.
    PUSH AF                             ; Save ordinal while clearing FCB.
    CALL SRC_WIPE                       ; Reset the file-control block for this source.
    POP  AF                             ; Restore the source ordinal.
    CALL INC_SLOT                       ; Address the source's eleven-byte name record.
    LD   DE,SRC_FCB+1                   ; Point past the drive byte to the 8.3 fields.
    LD   B,11                           ; Copy the full 8.3 name.
.COPY: ; Copy the source name with the emitted marker removed.
    LD   A,(HL)                         ; Read the next byte of the retained source name.
    AND  $7F                            ; Clear the first byte's order bit.
    LD   (DE),A                         ; Copy the ordinary name byte into the input FCB.
    INC  HL                             ; Advance within the retained name record.
    INC  DE                             ; Advance within the input FCB name fields.
    DJNZ .COPY                          ; Copy all eleven name and type bytes.
    CALL SRC_CHK                        ; Protect output and transaction files.
    RET  C                              ; Reject a source/output alias.
    LD   DE,SRC_FCB                     ; Pass the prepared FCB to CP/M.
    LD   C,CP_OPEN                      ; Select the CP/M open-file service.
    CALL CP_BDOS                        ; Open the selected source file.
    INC  A                              ; Convert BDOS's $FF failure result to zero.
    JR   Z,.FAIL                        ; Report an unavailable source by name.
    LD   A,1                            ; Force the next cache refill.
    LD   (SRC_KEY),A                    ; Aligned record offsets cannot equal one.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the input FCB open.
.FAIL: ; Report a failed source open by filename.
    LD   HL,SRC_FCB                     ; Address the filename that failed to open.
    CALL CP_NAME                        ; Print its drive-independent 8.3 name.
    LD   DE,MSG_READ                    ; Select the source-open error message.
    SCF                                 ; Mark the open operation as failed.
    RET                                 ; Return the message pointer with carry set.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the next raw source byte and advance HL. Carry with A=0 means EOF or
; an unsuccessful CP/M random read. Carry with A=2 means the 16-bit offset
; wrapped. BC and DE survive for parsers.
; A part is limited to 65,535 bytes so the next offset cannot wrap to zero.

SRC_NEXT: ; Read a raw source byte and advance its logical offset.
    PUSH BC                             ; Preserve the parser's byte-sized working values.
    PUSH DE                             ; Save the parser's DE value.
    PUSH HL                             ; Save the logical offset.
    CALL SRC_RAW                        ; Read from the current CP/M record cache.
    POP  HL                             ; Restore the logical offset.
    POP  DE                             ; Restore the caller's DE value.
    POP  BC                             ; Restore the caller's BC value.
    RET  C                              ; Return EOF/read failure. keep HL.
    LD   (SRC_TMP),A                    ; Save the byte while advancing the offset.
    INC  HL                             ; Advance to the following offset.
    LD   A,H                            ; Test the high byte of the advanced offset.
    OR   L                              ; Zero means the 16-bit offset wrapped.
    JR   Z,.TOOLONG                     ; Reject a part that would exceed 65,535 bytes.
    LD   A,(SRC_TMP)                    ; Restore the byte read from the source.
    OR   A                              ; Clear carry. set Z for byte zero.
    RET                                 ; Return byte and advanced offset.
.TOOLONG: ; Reject a source offset that wrapped to zero.
    LD   A,2                            ; Distinguish offset overflow.
    SCF                                 ; Report that the logical source offset wrapped.
    RET                                 ; Return the overflow status to the resolver.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Align the logical offset to its 128-byte CP/M record base. The cache
; key stores that base. the FCB receives it divided by 128. On a miss,
; the routine installs the source cache as DMA and reads that record.
; It then uses the low seven bits to select the requested byte.

SRC_RAW: ; Read a source byte through the random-record cache.
    LD   (SRC_POS),HL                   ; Save the requested logical byte offset.
    LD   A,L                            ; Inspect the low byte of the requested offset.
    AND  $80                            ; Keep its 128-byte record-boundary bit.
    LD   E,A                            ; Form the aligned offset's low byte.
    LD   D,H                            ; Form its high byte from the logical offset.
    LD   HL,(SRC_KEY)                   ; Read the offset currently in the cache.
    OR   A                              ; Clear carry for base subtraction.
    SBC  HL,DE                          ; Compare the cached and requested record bases.
    JR   Z,SRC_HIT                      ; Reuse the cache when both bases match.
SRC_MISS: ; Load the required random source record.
    LD   (SRC_KEY),DE                   ; Store the aligned offset being loaded.
    RLC  E                              ; Move offset bit 7 into record bit 0.
    LD   A,D                            ; Load the offset high byte.
    ADD  A,A                            ; Shift its bits left one place.
    OR   E                              ; Add the original offset's bit 7.
    LD   (SRC_FCB+33),A                 ; Store the random record number's low byte.
    LD   A,D                            ; Reload the offset's high byte.
    RLCA                                ; Move offset bit 15 into bit 0.
    AND  1                              ; Keep only the record number's high bit.
    LD   (SRC_FCB+34),A                 ; Store the random record number's high byte.
    LD   DE,SRC_PAGE                    ; Select the 128-byte DMA buffer.
    LD   C,CP_DMA                       ; Set the CP/M transfer address.
    CALL CP_BDOS                        ; Direct the next read into the source cache.
    LD   DE,SRC_FCB                     ; Pass the file and record number to CP/M.
    LD   C,CP_RANDR                     ; Select a random-record read.
    CALL CP_BDOS                        ; Load the requested 128-byte source record.
    OR   A                              ; Zero means the random read succeeded.
    JR   NZ,SRC_FAIL                    ; Treat a BDOS read failure as no source byte.
SRC_HIT: ; Select a byte within the cached source record.
    LD   HL,(SRC_POS)                   ; Restore the byte's logical offset.
    RES  7,L                            ; Keep its within-record offset in $00..$7F.
    LD   H,SRC_PAGE/256                 ; Select the source cache's memory page.
    LD   A,(HL)                         ; Read the byte from the cached record.
    CP   $1A                            ; Test CP/M's text-file end marker.
    JR   Z,SRC_EOF                      ; Return end-of-input at control-Z.
    OR   A                              ; Clear carry. retain source byte.
    RET                                 ; Return the raw byte to the caller.
SRC_FAIL: ; Return a failed random-read result.
SRC_EOF: ; Return text EOF at the SUB marker.
    XOR  A                              ; Return EOF or read failure.
    SCF                                 ; Carry reports that no source byte is available.
    RET                                 ; Share the no-byte result.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Consume source bytes through the next CR, LF or end of file.

SRC_SKIP: ; Skip through the next physical line ending.
    CALL SRC_NEXT                       ; Read the next byte in the current line.
    RET  C                              ; Stop at EOF or offset overflow.
    CP   13                             ; Test for a carriage return.
    RET  Z                              ; Stop after consuming CR.
    CP   10                             ; Test for a line feed.
    JR   NZ,SRC_SKIP                    ; Continue until LF or another CR.
    RET                                 ; Stop after consuming LF.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Open a part on ordinal change, then return one source byte.
; Preflight validates INCLUDE, DEFINE and conditional directives. A leading
; percent becomes a semicolon so Atom reads the directive as a comment.

SRC_BYTE: ; Select a source part and apply preprocessing filters.
    LD   E,A                            ; Keep the resolved source-part ordinal.
    LD   A,(SRC_PART)                   ; Read the ordinal of the open source file.
    CP   E                              ; Compare it with the requested part.
    JR   Z,.READY                       ; Reuse the file when ordinals match.
    PUSH BC                             ; Preserve the caller's byte-sized parser state.
    PUSH HL                             ; Save offset across file open.
    LD   A,E                            ; Restore the requested resolved ordinal.
    LD   (SRC_PART),A                   ; Record which resolved part is now active.
    LD   D,INC_ORD/256                  ; Address the order table's fixed memory page.
    LD   A,(DE)                         ; Map order to source ordinal.
    CALL SRC_OPEN                       ; Open the source named by that original ordinal.
    CALL PP_RESET                       ; Start each source part outside a conditional.
    POP  HL                             ; Restore the byte offset.
    POP  BC                             ; Restore the caller's parser state.
.READY: ; Read from the already selected source part.
    PUSH BC                             ; Save parser BC across raw read.
    PUSH HL                             ; Preserve the source offset across cache lookup.
    CALL SRC_RAW                        ; Read one byte from the active source file.
    POP  HL                             ; Restore the source offset.
    POP  BC                             ; Restore the caller's parser state.
    RET  C                              ; Return end-of-input or a failed read unchanged.
    JP   PP_MASK                        ; Filter directives and inactive lines.

;@ROUTINE IN HL OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Decide whether a percent character begins a recognised host directive.

SRC_LEAD: ; Test whether percent follows only line indentation.
    LD   A,H                            ; Test the current source offset's high byte.
    OR   L                              ; Zero means the percent is the first source byte.
    RET  Z                              ; Report line start when no preceding byte exists.
    DEC  HL                             ; Begin scanning at the byte before the percent.
.BACK: ; Scan preceding source bytes back to a line boundary.
    PUSH HL                             ; Save the backward-scan cursor.
    CALL SRC_RAW                        ; Read the preceding source byte.
    POP  HL                             ; Restore the offset used for the backward scan.
    CP   13                             ; Does percent follow CR?
    JR   Z,.YES                         ; CR marks the start of a source line.
    CP   10                             ; Check whether the percent follows a line feed.
    JR   Z,.YES                         ; LF also marks the start of a source line.
    CP   ' '                            ; Check for a space before the percent.
    JR   Z,.PREV                        ; Skip whitespace while scanning backwards.
    CP   9                              ; Check for a horizontal tab.
    RET  NZ                             ; Other prefix means ordinary text.
.PREV: ; Continue backwards over horizontal indentation.
    LD   A,H                            ; Did whitespace reach offset zero?
    OR   L                              ; No preceding non-space byte.
    JR   Z,.YES                         ; Only spaces or tabs precede the percent.
    DEC  HL                             ; Step back one source byte.
    JR   .BACK                          ; Continue until line start or ordinary text.
.YES: ; Accept a line-leading percent directive.
    XOR  A                              ; Mark a line-leading percent.
    RET                                 ; Return with carry clear.
;@@ATOM_CPM_PREPROCESSOR@@
SRC_CEND: ; Exclusive end of source and preprocessing code.
