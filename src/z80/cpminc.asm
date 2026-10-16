; Includes as the stream reaches them. An active %INCLUDE in a file's header
; ends that file's part at the include line. The file waits on a frame while
; its include is assembled, then resumes from the same byte. Each file is
; assembled once, at its first include, which gives the order the text would
; have if every include were pasted in place. Nothing is read in advance.
;
; A frame keeps the waiting file's FCB and its cached record, so resuming it
; reads nothing again.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare to stream the root source named in srcFcb.

incStart: ; Reset the include state for one command.
    LD   HL,srcFcb+1                    ; Skip the drive byte and retain the 8.3 name.
    LD   DE,incNames                    ; Store it in the root's ordinal-zero slot.
    LD   BC,11                          ; FCB name and type fields occupy eleven bytes.
    LDIR                                ; Copy the root name into the name table.
    LD   A,1                            ; One name is known.
    LD   (incFound),A                   ; The root.
    LD   (incState),A                   ; It is open, so including it is a cycle.
    LD   (ppActive),A                   ; Source is active until an IF says otherwise.
    XOR  A                              ; Clear the remaining state.
    LD   (incDepth),A                   ; No file is waiting.
    LD   (incNext),A                    ; tkOpen supplies the root first.
    LD   (ppDepth),A                    ; No condition is open.
    LD   (ppDefCnt),A                   ; No value is defined.
    LD   H,A                            ; Form zero.
    LD   L,A                            ; Complete it.
    LD   (incErr),HL                    ; No failure yet.
    DEC  A                              ; Form $FF.
    LD   (srcPart),A                    ; No part is open.
    LD   (incErrAt),A                   ; A failure has no position yet.
    LD   (incErrNm),A                   ; Nor a file name.
    RET                                 ; The driver asks tkOpen for the root.

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY
; Atom's next-part service on CP/M. Return the next part: an include just
; reached, or the file waiting for it, resumed where it stopped. Carry with
; A=0 means every part has been assembled. Carry with A=1 is a failure,
; recorded for cpEntry to print.

tkOpen: ; Supply the next source part.
    LD   HL,(incErr)                    ; Has a failure been recorded?
    LD   A,H                            ; Test the message pointer.
    OR   L                              ; Zero means none.
    JR   NZ,.fail                       ; Report it.
    LD   A,(incNext)                    ; Is a part waiting to begin?
    CP   $FF                            ; $FF means none.
    JR   Z,.resume                      ; Resume a waiting file instead.
    LD   C,A                            ; Keep its ordinal.
    LD   A,$FF                          ; It begins now.
    LD   (incNext),A                    ; Nothing else is waiting to begin.
    LD   A,(srcPart)                    ; An include opened its file already.
    CP   C                              ; The root has not been opened.
    JR   Z,.begin                       ; Begin the open file.
    LD   A,C                            ; Open the root.
    PUSH BC                             ; srcOpen clobbers C.
    CALL srcOpen                        ; Open its file.
    POP  BC                             ; Recover the ordinal.
    JR   C,.lost                        ; Report a file that cannot be read.
.begin: ; Begin the part at its first byte.
    LD   A,C                            ; Select the part.
    CALL ppStart                        ; Reset the filter for its first byte.
    LD   A,C                            ; Return its ordinal.
    LD   HL,0                           ; It starts at offset zero.
    LD   DE,1                           ; On line one.
    OR   A                              ; Clear carry.
    RET                                 ; The driver assembles it.
.resume: ; Resume the file that included the part just finished.
    LD   A,(incDepth)                   ; Is a file waiting?
    OR   A                              ; Zero means none.
    JP   NZ,incPop                      ; Resume it.
    XOR  A                              ; A=0: every part is assembled.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; The driver finishes.
.lost: ; Record a root that cannot be opened.
    CALL incLost                        ; Keep its name and message.
.fail: ; Report the recorded failure.
    LD   A,1                            ; A nonzero status.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; The driver aborts the build.

;@ROUTINE OUT A,CARRY,DE CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Apply %INCLUDE "NAME". It belongs in the header. An inactive one is checked
; but ignored, and a file already assembled is not assembled again. Otherwise
; the current file waits on a frame and the included file opens. A=1 then
; ends the current part at this line's end. Carry reports a malformed include,
; a cycle or a file that cannot be read, with the message in DE.

ppIncl: ; Start an included part.
    LD   HL,(ppSrcPtr)                  ; Start after the INCLUDE keyword.
.blank: ; Skip whitespace before the name.
    CALL ppNext                         ; Read the next byte.
    CP   ' '                            ; A space?
    JR   Z,.blank                       ; Skip it.
    CP   9                              ; A tab?
    JR   Z,.blank                       ; Skip it.
    CP   '"'                            ; The name must be quoted.
    JR   NZ,.bad                        ; Reject anything else.
    LD   (ppAfter),HL                   ; Keep the name's first byte.
    LD   B,0                            ; Count its bytes.
.name: ; Find the closing quote.
    CALL ppNext                         ; Read the next byte.
    CP   '"'                            ; The closing quote?
    JR   Z,.named                       ; The name is complete.
    CP   13                             ; The directive ended first?
    JR   Z,.bad                         ; Reject an unclosed name.
    INC  B                              ; Count the byte.
    JR   .name                          ; Continue.
.named: ; Store the name and check the rest of the line.
    PUSH HL                             ; Keep the cursor after the quote.
    LD   HL,(ppAfter)                   ; Address the name.
    LD   DE,cpFcb                       ; Store it in the working FCB.
    CALL srcName                        ; Validate the 8.3 name.
    POP  HL                             ; Recover the cursor.
    JR   C,.bad                         ; Reject a malformed name.
    CALL ppEol                          ; Only whitespace may follow.
    JR   C,.bad                         ; Reject anything else.
    LD   A,(incHead)                    ; Includes belong to the header.
    OR   A                              ; Zero means ordinary source has begun.
    JR   Z,.bad                         ; Reject a late include.
    XOR  A                              ; An include closes the definitions.
    LD   (ppDefOk),A                    ; No define may follow it.
    CALL ppMark                         ; Its IF must close inside the header.
    LD   A,(ppActive)                   ; Is the include active?
    OR   A                              ; Zero means it is not.
    RET  Z                              ; Ignore it, with A=0 and carry clear.
    CALL incFind                        ; Find or add its name.
    RET  C                              ; Too many files.
    LD   C,A                            ; Keep its ordinal.
    CALL incStat                        ; Address its state.
    LD   A,(HL)                         ; Read it.
    CP   2                              ; Already assembled?
    JR   Z,.skip                        ; Then it is not assembled again.
    DEC  A                              ; One means it is still open.
    JR   Z,.cycle                       ; Including it again is a cycle.
    LD   A,(incDepth)                   ; Is there room for another frame?
    CP   incMax                         ; The nesting limit.
    JR   NC,.deep                       ; Report it.
    PUSH BC                             ; Keep the ordinal.
    CALL incPush                        ; Park the current file.
    POP  BC                             ; Recover the ordinal.
    LD   A,C                            ; Select the included file.
    CALL incStat                        ; Address its state.
    LD   (HL),1                         ; It is now open.
    LD   A,C                            ; Open its file.
    PUSH BC                             ; srcOpen clobbers C.
    CALL srcOpen                        ; Its source is read from here.
    POP  BC                             ; Recover the ordinal.
    JR   C,.lost                        ; Report a file that cannot be read.
    LD   A,C                            ; It begins at the next tkOpen.
    LD   (incNext),A                    ; Keep it.
    LD   (srcPart),A                    ; Its file is the one now open.
    LD   A,1                            ; End the current part here.
    OR   A                              ; Clear carry.
    RET                                 ; The filter ends the part.
.skip: ; Leave an assembled file alone.
    XOR  A                              ; The part continues.
    RET                                 ; Return carry clear.
.bad: ; Report a malformed include.
    LD   DE,msgInc                      ; Select the include message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.
.cycle: ; Report an include of a file still open.
    LD   DE,msgLoop                     ; Select the cycle message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.
.deep: ; Report includes nested too deeply.
    LD   DE,msgDeep                     ; Select the nesting message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.
.lost: ; Report an included file that cannot be read.
    LD   A,D                            ; A read failure names the file.
    CP   HIGH(msgRead)                  ; Is DE msgRead?
    JR   NZ,.unnamed                    ; Other failures have no name.
    LD   A,E                            ; Compare the low byte too.
    CP   LOW(msgRead)                   ; Is it msgRead?
    JR   NZ,.unnamed                    ; No: no name.
    PUSH DE                             ; incName uses DE.
    CALL incName                        ; Keep the file's name.
    POP  DE                             ; Restore the message.
.unnamed: ; Return the failure.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address the state of name A: 0 not begun, 1 open, 2 assembled.

incStat: ; Address one name's include state.
    LD   E,A                            ; Widen the ordinal.
    LD   D,0                            ; Clear the high byte.
    LD   HL,incState                    ; Address the state table.
    ADD  HL,DE                          ; Address this name's state.
    RET                                 ; Return it in HL.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mark the current part's file assembled.

incDone: ; Record that a file has been assembled.
    LD   A,(srcPart)                    ; Select the current file.
    CALL incStat                        ; Address its state.
    LD   (HL),2                         ; It is finished.
    RET                                 ; Later includes of it are skipped.

;@ROUTINE IN A OUT HL,DE CLOBBERS A,B,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address frame A's header in HL and its saved parent in DE.

incFrame: ; Address one include frame.
    LD   B,A                            ; Keep the frame index.
    ADD  A,A                            ; Two bytes per frame index.
    ADD  A,B                            ; Three.
    ADD  A,A                            ; Six bytes per frame header.
    LD   E,A                            ; Widen the offset.
    LD   D,0                            ; Clear the high byte.
    LD   HL,incStack                    ; Address the frames.
    ADD  HL,DE                          ; Address this frame's header.
    LD   DE,incSaves                    ; Address the saved parents.
    INC  B                              ; Count the frame itself.
.save: ; Step to this frame's saved parent.
    DEC  B                              ; One fewer frame to pass.
    RET  Z                              ; DE addresses it.
    PUSH HL                             ; Keep the header address.
    LD   HL,incSvLen                    ; One saved parent.
    ADD  HL,DE                          ; Step past it.
    EX   DE,HL                          ; DE is the next saved parent.
    POP  HL                             ; Recover the header address.
    JR   .save                          ; Continue.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Park the current file on a new frame: its ordinal, the offset of the byte
; where it resumes, its line, its condition base, FCB and cached record.

incPush: ; Save the current file while its include is assembled.
    LD   A,(incDepth)                   ; Select the next frame.
    CALL incFrame                       ; Address its header and saved parent.
    LD   A,(srcPart)                    ; The waiting file.
    LD   (HL),A                         ; Store its ordinal.
    INC  HL                             ; Advance to the resume offset.
    LD   BC,(ppPos)                     ; It resumes at the byte being filtered.
    LD   (HL),C                         ; Store the offset's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   (HL),B                         ; Store it.
    INC  HL                             ; Advance to the line.
    LD   BC,(ppLine)                    ; The line of that byte.
    LD   (HL),C                         ; Store the line's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   (HL),B                         ; Store it.
    INC  HL                             ; Advance to the condition base.
    LD   A,(ppBase)                     ; The conditions open when the file began.
    LD   (HL),A                         ; Store it.
    LD   HL,srcFcb                      ; Save the open FCB.
    LD   BC,36                          ; All of it.
    LDIR                                ; Copy it to the saved parent.
    LD   HL,srcKey                      ; Save the cache key.
    LD   BC,2                           ; One word.
    LDIR                                ; Copy it.
    LD   HL,srcCache                    ; Save the cached record.
    LD   BC,128                         ; One record.
    LDIR                                ; Copy it.
    LD   HL,incDepth                    ; Count the frame.
    INC  (HL)                           ; It is in use.
    RET                                 ; The included file can open.

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY
; Resume the newest waiting file. Return its ordinal in A, the offset where it
; resumes in HL and that byte's line in DE. Nothing is read from disk.

incPop: ; Resume a file whose include has been assembled.
    LD   HL,incDepth                    ; Release the newest frame.
    DEC  (HL)                           ; It is no longer in use.
    LD   A,(HL)                         ; Select it.
    CALL incFrame                       ; Address its header and saved parent.
    PUSH HL                             ; Keep the header.
    EX   DE,HL                          ; HL addresses the saved parent.
    LD   DE,srcFcb                      ; Restore the FCB.
    LD   BC,36                          ; All of it.
    LDIR                                ; Copy it back.
    LD   DE,srcKey                      ; Restore the cache key.
    LD   BC,2                           ; One word.
    LDIR                                ; Copy it back.
    LD   DE,srcCache                    ; Restore the cached record.
    LD   BC,128                         ; One record.
    LDIR                                ; Copy it back.
    POP  HL                             ; Recover the header.
    LD   A,(HL)                         ; The file's ordinal.
    LD   (srcPart),A                    ; It is the current part again.
    INC  HL                             ; Advance to the resume offset.
    LD   C,(HL)                         ; Read its low byte.
    INC  HL                             ; Advance to its high byte.
    LD   B,(HL)                         ; Read it.
    INC  HL                             ; Advance to the line.
    LD   E,(HL)                         ; Read the line's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Read it.
    LD   (ppLine),DE                    ; Lines continue from there.
    INC  HL                             ; Advance to the condition base.
    LD   A,(HL)                         ; Read it.
    LD   (ppBase),A                     ; Restore it.
    XOR  A                              ; Clear the per-line state.
    LD   (ppLastCr),A                   ; The resume byte is a line ending.
    LD   (ppEnded),A                    ; The file's end is still ahead.
    LD   (ppDefOk),A                    ; No definition may follow an include.
    INC  A                              ; Form one.
    LD   (incHead),A                    ; The file is still in its header.
    LD   HL,(srcKey)                    ; Is the cached record the file's last?
    LD   DE,$FF80                       ; Its key would be $FF80.
    OR   A                              ; Clear carry for the comparison.
    SBC  HL,DE                          ; Zero when it is.
    LD   A,0                            ; Not in a directive, not at a line start.
    JR   NZ,.mode                       ; Keep that.
    LD   A,4                            ; Mark the last possible record.
.mode: ; Restore the filter mode.
    LD   (ppMode),A                     ; Keep it.
    LD   A,(srcPart)                    ; Return the ordinal.
    LD   H,B                            ; Return the resume offset.
    LD   L,C                            ; Complete it.
    LD   DE,(ppLine)                    ; Return its line.
    OR   A                              ; Clear carry.
    RET                                 ; The driver resumes the file.

;@ROUTINE IN DE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record a front-end failure at the directive just applied. Only the first
; failure is kept.

incFail: ; Record a failure and where it happened.
    LD   HL,(incErr)                    ; Is a failure already recorded?
    LD   A,H                            ; Test the pointer.
    OR   L                              ; Zero means none.
    RET  NZ                             ; Keep the first.
    LD   (incErr),DE                    ; Keep the message.
    LD   A,(srcPart)                    ; The part being read.
    LD   (incErrAt),A                   ; Keep it.
    LD   HL,(ppDirAt)                   ; Where the directive started.
    LD   (incErrAt+1),HL                ; Keep the offset.
    LD   HL,(ppDirLn)                   ; And its line.
    LD   (incErrAt+3),HL                ; Keep it.
    RET                                 ; tkOpen reports the failure.

;@ROUTINE IN DE CLOBBERS A,BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record a file that cannot be read. Its name is printed instead of a
; position.

incLost: ; Record a failed read and the file's name.
    LD   HL,(incErr)                    ; Is a failure already recorded?
    LD   A,H                            ; Test the pointer.
    OR   L                              ; Zero means none.
    RET  NZ                             ; Keep the first.
    LD   (incErr),DE                    ; Keep the message.
    PUSH DE                             ; incName uses DE.
    CALL incName                        ; Keep the file's name.
    POP  DE                             ; Restore the message.
    RET                                 ; tkOpen reports the failure.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Keep the name in srcFcb for the failure message.

incName: ; Copy the failing file's name.
    LD   HL,srcFcb                      ; Its drive and 8.3 name.
    LD   DE,incErrNm                    ; The failure's name field.
    LD   BC,12                          ; Drive and eleven name bytes.
    LDIR                                ; Copy them.
    RET                                 ; The name is kept.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a recorded front-end failure: FILE:line:column: message, or the
; failing file's name and message when it could not be read.

incShow: ; Print the recorded failure.
    LD   A,(incErrAt)                   ; Is there a position?
    CP   $FF                            ; $FF means none.
    JR   Z,.noAt                        ; Print the name instead.
    LD   (stAtPart),A                   ; Report the failure's part.
    LD   HL,(incErrAt+1)                ; Its offset.
    LD   (stAtOff),HL                   ; Through the usual diagnostic fields.
    LD   HL,(incErrAt+3)                ; Its line.
    LD   (stAtLine),HL                  ; Keep it.
    CALL errWhere                       ; Print FILE:line:column.
    CALL errSep                         ; Separate it from the message.
.noAt: ; Print the failing file's name, if any.
    LD   A,(incErrNm)                   ; Was a name recorded?
    CP   $FF                            ; $FF means none.
    JR   Z,.text                        ; Print the message alone.
    LD   HL,incErrNm                    ; Address the name.
    CALL cpPutFcb                       ; Print it.
.text: ; Print the message.
    LD   DE,(incErr)                    ; Address it.
    LD   A,(DE)                         ; Does it start a new line?
    CP   13                             ; CR LF leads a standalone message.
    JR   NZ,.print                      ; No: print it all.
    INC  DE                             ; Skip the CR.
    INC  DE                             ; Skip the LF.
.print: ; Print the message.
    JP   cpPrint                        ; Print it and return.

;@ROUTINE OUT A,CARRY,DE CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
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
    CALL incStat                        ; Address its state.
    LD   (HL),0                         ; It has not begun.
    POP  AF                             ; Recover the ordinal.
    PUSH AF                             ; Keep it for the return.
    CALL incSlot                        ; Address the next eleven-byte table slot.
    EX   DE,HL                          ; Put the slot destination in DE for LDIR.
    LD   HL,cpFcb+1                     ; Point to the normalised 8.3 name bytes.
    LD   BC,11                          ; Copy name and type, not drive.
    LDIR                                ; Store the new name in its ordinal slot.
    LD   HL,incFound                    ; Address the count of names.
    INC  (HL)                           ; Publish the completed name slot.
    POP  AF                             ; Return the allocated ordinal.
    OR   A                              ; Clear carry to mark successful insertion.
    RET                                 ; Return the new retained-name identity.
.full: ; Reject an excess source part before writing the table.
    LD   DE,msgCap                      ; Select the part-capacity diagnostic.
    SCF                                 ; Mark the name table as full.
    RET                                 ; Return without changing the name count.

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
