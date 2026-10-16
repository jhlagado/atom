; Includes as the stream reaches them. An active %INCLUDE in a file's header
; ends that file's part at the include line. The file waits on a frame while
; its include is assembled, then resumes from the same byte. Each file is
; assembled once, at its first include, which gives the order the text would
; have if every include were pasted in place. Nothing is read in advance.
;
; HOST FILE SERVICES
; ------------------
;
; The host owns file names and how files are read. A file is known to the
; front end only by the ordinal the host gives it, and the same file always
; gets the same ordinal.
;
;   sfOpen   IN B,HL: the name's B bytes at HL, relative to the file being
;            read. B=0 asks for the next root file. OUT A=ordinal. Carry with
;            A=0 means no root remains, otherwise A is a message number.
;   sfStart  IN A=ordinal. Begin reading that file from its first byte.
;            Carry: A is a message number.
;   sfRead   IN A=ordinal, HL=offset. OUT A=byte. Carry with A=0 at the end of
;            the file, otherwise A is a message number. Keeps BC and HL.
;   sfPark   IN A=frame. Keep the current file's read state while an include
;            is assembled.
;   sfBack   IN A=frame. Restore that state.
;
; The platform defines feRamLo, where the front end's workspace begins, and
; incMax, the deepest include nesting it allows.

; Failure messages from src/host/diagnostics.mjs.

ppBadDir    EQU     72                  ; Invalid source directive.
incBad      EQU     73                  ; Invalid %INCLUDE.
incCycle    EQU     74                  ; Include cycle.
incDeep     EQU     75                  ; Includes are nested too deeply.
incMany     EQU     76                  ; Too many source files.
incLost     EQU     77                  ; Could not read the included file.
srcLong     EQU     78                  ; Source file is longer than 65,535 bytes.
srcLost     EQU     79                  ; Could not read the source file.

; Workspace.

incFrLen    EQU     6                   ; Frame: ordinal, resume offset, line, condition base.
incStack    EQU     feRamLo             ; The files waiting for their includes.
incDepth    EQU     incStack+incFrLen*incMax ; Number of frames in use.
incNext     EQU     incDepth+1          ; Included file tkOpen begins next, or $FF.
srcPart     EQU     incNext+1           ; Ordinal of the file being read.
incHead     EQU     srcPart+1           ; Nonzero while the file is still in its header.
incErr      EQU     incHead+1           ; Message number of the first failure, or zero.
incErrAt    EQU     incErr+1            ; Its part, offset and line.
ppDepth     EQU     incErrAt+5          ; Number of open conditional frames.
ppActive    EQU     ppDepth+1           ; Activity of the currently selected branch.
ppBase      EQU     ppActive+1          ; Conditional depth when the current part began.
ppDefOk     EQU     ppBase+1            ; Nonzero while entry-header definitions remain legal.
ppDefCnt    EQU     ppDefOk+1           ; Number of complete numeric definitions.
ppMode      EQU     ppDefCnt+1          ; Bit 0 line start, 1 directive, 2 quoted name.
ppLastCr    EQU     ppMode+1            ; Nonzero when the previous byte was CR.
ppEnded     EQU     ppLastCr+1          ; Nonzero once the part's end has been checked.
ppCapLen    EQU     ppEnded+1           ; Directive bytes captured, $FE overflow, $FF done.
ppLine      EQU     ppCapLen+1          ; Line of the byte being filtered.
ppDirAt     EQU     ppLine+2            ; Offset of the directive's '%'.
ppDirLn     EQU     ppDirAt+2           ; Line of the directive.
ppPos       EQU     ppDirLn+2           ; Offset of the byte being filtered.
ppTokLen    EQU     ppPos+2             ; Significant byte length of the current token.
ppRadix     EQU     ppTokLen+1          ; Numeric radix selected for token conversion.
ppFirst     EQU     ppRadix+1           ; Token index of the first numeric digit.
ppDigits    EQU     ppFirst+1           ; Number of numeric digits excluding prefix or suffix.
ppIndex     EQU     ppDigits+1          ; Next digit index within numeric conversion.
ppTemp      EQU     ppIndex+1           ; Character or condition saved across helper calls.
ppSrcPtr    EQU     ppTemp+1            ; Directive cursor saved during token lookup.
ppAfter     EQU     ppSrcPtr+2          ; Directive cursor saved after a validated value.
ppValue     EQU     ppAfter+2           ; Unsigned sixteen-bit definition or condition value.
ppLength    EQU     ppValue+2           ; Significant length of the staged definition name.
ppStack     EQU     ppLength+1          ; Sixteen one-byte parent, condition and ELSE frames.
ppLnMax     EQU     64                  ; Longest directive before its comment.
ppLnBuf     EQU     ppStack+16          ; The directive line, ended by CR.
incState    EQU     ppLnBuf+ppLnMax+1   ; Per file: 0 not begun, 1 open, 2 assembled.
ppRecLen    EQU     20                  ; Definition record: length, 17 name bytes and value.
ppDefMax    EQU     32                  ; Maximum distinct numeric definitions.
ppDefBeg    EQU     incState+255        ; Beginning of the fixed-width definition table.
ppToken     EQU     ppDefBeg+ppRecLen*ppDefMax ; Seventeen-byte uppercase directive or value token.
ppName      EQU     ppToken+17          ; Separately staged padded definition name.
ppWidth     EQU     17                  ; Maximum significant definition-name length.
feRamHi     EQU     ppName+ppWidth      ; Exclusive end of the front end's workspace.

feBeg: ; Beginning of the front end's code.

;@ROUTINE CLOBBERS A,B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the front end for one assembly. The host may then add definitions
; before assembling, as the command line's -D does.

incStart: ; Reset the include and condition state.
    LD   A,1                            ; Source is active until an IF says otherwise.
    LD   (ppActive),A                   ; No condition is open.
    XOR  A                              ; Clear the remaining state.
    LD   (incDepth),A                   ; No file is waiting.
    LD   (ppDepth),A                    ; No condition is open.
    LD   (ppDefCnt),A                   ; No value is defined.
    LD   (incErr),A                     ; No failure yet.
    LD   HL,incState                    ; No file has begun.
    LD   B,255                          ; One state per possible ordinal.
.state: ; Clear one file state.
    LD   (HL),A                         ; Not begun.
    INC  HL                             ; Advance.
    DJNZ .state                         ; Clear them all.
    DEC  A                              ; Form $FF.
    LD   (incNext),A                    ; No include is waiting to begin.
    LD   (srcPart),A                    ; No file is being read.
    RET                                 ; The driver asks tkOpen for the first root.

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY
; Atom's next-part service. Return the next part: an include just reached,
; the file waiting for it resumed where it stopped, or the host's next root.
; Carry with A=0 means every part has been assembled. Carry with A nonzero is
; a failure's message number, with its position in stAtPart, stAtOff and
; stAtLine.

tkOpen: ; Supply the next source part.
    LD   A,(incErr)                     ; Has a failure been recorded?
    OR   A                              ; Zero means none.
    JR   NZ,.fail                       ; Report it.
    LD   A,(incNext)                    ; Is an include waiting to begin?
    CP   $FF                            ; $FF means none.
    JR   NZ,.child                      ; Begin it.
    LD   A,(incDepth)                   ; Is a file waiting for an include?
    OR   A                              ; Zero means none.
    JP   NZ,incPop                      ; Resume it.
.root: ; Ask the host for the next root file.
    LD   B,0                            ; An empty name asks for a root.
    LD   H,B                            ; It has no name text.
    LD   L,B                            ; So HL addresses nothing.
    PUSH IX                             ; The host may use IX.
    PUSH IY                             ; And IY.
    CALL sfOpen                         ; Name the next root.
    POP  IY                             ; Restore the caller's IY.
    POP  IX                             ; And IX.
    JR   C,.noRoot                      ; None remains, or it failed.
    LD   C,A                            ; Keep its ordinal.
    CALL incStat                        ; Address its state.
    LD   A,(HL)                         ; Was it assembled already, as an include?
    OR   A                              ; Zero means it has not begun.
    JR   NZ,.root                       ; Then skip it.
    LD   (HL),1                         ; It is open.
    LD   A,C                            ; Start reading it.
    PUSH BC                             ; sfStart may clobber C.
    CALL sfStart                        ; Begin at its first byte.
    POP  BC                             ; Recover the ordinal.
    JR   C,.lost                        ; It cannot be read.
    JR   .begin                         ; Begin the part.
.child: ; Begin the include just reached.
    LD   C,A                            ; Keep its ordinal.
    LD   A,$FF                          ; It begins now.
    LD   (incNext),A                    ; Nothing else is waiting to begin.
.begin: ; Begin the part at its first byte.
    LD   A,C                            ; Select the part.
    CALL ppStart                        ; Reset the filter for its first byte.
    LD   A,C                            ; Return its ordinal.
    LD   HL,0                           ; It starts at offset zero.
    LD   DE,1                           ; On line one.
    OR   A                              ; Clear carry.
    RET                                 ; The driver assembles it.
.noRoot: ; Finish, or report a root that cannot be named.
    OR   A                              ; A=0 means no root remains.
    JR   NZ,.lost                       ; Report the failure.
    SCF                                 ; Carry with A=0: every part is assembled.
    RET                                 ; The driver finishes.
.lost: ; Record a failure that has no source position.
    LD   (incErr),A                     ; Keep the message.
    LD   A,$FF                          ; No part holds it.
    LD   (incErrAt),A                   ; Mark the position unknown.
.fail: ; Report the recorded failure through the statement fields.
    LD   A,(incErrAt)                   ; The failure's part.
    LD   (stAtPart),A                   ; Publish it.
    LD   HL,(incErrAt+1)                ; Its offset.
    LD   (stAtOff),HL                   ; Publish it.
    LD   HL,(incErrAt+3)                ; Its line.
    LD   (stAtLine),HL                  ; Publish it.
    LD   A,(incErr)                     ; Return its message number.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; The driver aborts the build.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Atom's source-byte service. Return the byte at offset HL of the current
; part through the filter, or carry with A=0 at the part's end. The core
; reads each byte once, in order.

tkRead: ; Read and filter one source byte.
    CALL sfRead                         ; Read the byte from the host.
    JP   NC,ppFilter                    ; Filter it.
    PUSH BC                             ; Keep the caller's BC.
    OR   A                              ; Did the file end?
    JR   NZ,.lost                       ; No: the read failed.
    CALL ppEnd                          ; Finish the part.
    POP  BC                             ; Restore the caller's BC.
    RET                                 ; Return carry with A=0.
.lost: ; Record a read failure at this byte.
    LD   (ppDirAt),HL                   ; Report it at this offset.
    LD   DE,(ppLine)                    ; And line.
    LD   (ppDirLn),DE                   ; Keep it.
    CALL incFail                        ; Keep the first failure.
    POP  BC                             ; Restore the caller's BC.
    XOR  A                              ; A=0 with carry ends the part.
    SCF                                 ; Carry marks the end.
    RET                                 ; tkOpen reports the failure.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Apply %INCLUDE "NAME". It belongs in the header. An inactive one is checked
; but ignored, and a file already assembled is not assembled again. Otherwise
; the current file waits on a frame and the included file begins. A=1 then
; ends the current part at this line's end. Carry reports a failure, with its
; message number in A.

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
.named: ; Check the name and the rest of the line.
    LD   A,B                            ; An empty name names no file.
    OR   A                              ; Zero bytes?
    JR   Z,.bad                         ; Reject it.
    LD   (ppTemp),A                     ; Keep the length.
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
    LD   HL,(ppAfter)                   ; Address the name.
    LD   A,(ppTemp)                     ; Its length.
    LD   B,A                            ; In B.
    CALL sfOpen                         ; The host names the file.
    RET  C                              ; It cannot.
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
    LD   A,C                            ; Start reading it.
    PUSH BC                             ; sfStart may clobber C.
    CALL sfStart                        ; Begin at its first byte.
    POP  BC                             ; Recover the ordinal.
    RET  C                              ; It cannot be read.
    LD   A,C                            ; It begins at the next tkOpen.
    LD   (incNext),A                    ; Keep it.
    LD   A,1                            ; End the current part here.
    OR   A                              ; Clear carry.
    RET                                 ; The filter ends the part.
.skip: ; Leave an assembled file alone.
    XOR  A                              ; The part continues.
    RET                                 ; Return carry clear.
.bad: ; Report a malformed include.
    LD   A,incBad                       ; Select the include message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.
.cycle: ; Report an include of a file still open.
    LD   A,incCycle                     ; Select the cycle message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.
.deep: ; Report includes nested too deeply.
    LD   A,incDeep                      ; Select the nesting message.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The filter records where it was.

;@ROUTINE IN A OUT HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address the state of file A: 0 not begun, 1 open, 2 assembled.

incStat: ; Address one file's include state.
    LD   E,A                            ; Widen the ordinal.
    LD   D,0                            ; Clear the high byte.
    LD   HL,incState                    ; Address the state table.
    ADD  HL,DE                          ; Address this file's state.
    RET                                 ; Return it in HL.

;@ROUTINE CLOBBERS A,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Mark the current part's file assembled.

incDone: ; Record that a file has been assembled.
    LD   A,(srcPart)                    ; Select the current file.
    CALL incStat                        ; Address its state.
    LD   (HL),2                         ; It is finished.
    RET                                 ; Later includes of it are skipped.

;@ROUTINE IN A OUT HL CLOBBERS A,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address frame A's header.

incFrame: ; Address one include frame.
    LD   E,A                            ; Keep the frame index.
    ADD  A,A                            ; Two bytes per frame index.
    ADD  A,E                            ; Three.
    ADD  A,A                            ; Six bytes per frame header.
    LD   E,A                            ; Widen the offset.
    LD   D,0                            ; Clear the high byte.
    LD   HL,incStack                    ; Address the frames.
    ADD  HL,DE                          ; Address this frame's header.
    RET                                 ; Return it.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Park the current file on a new frame: its ordinal, the offset of the byte
; where it resumes, its line and its condition base. The host keeps its read
; state.

incPush: ; Save the current file while its include is assembled.
    LD   A,(incDepth)                   ; Select the next frame.
    PUSH AF                             ; Keep its index.
    CALL incFrame                       ; Address its header.
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
    POP  AF                             ; Recover the frame index.
    CALL sfPark                         ; The host keeps the file's read state.
    LD   HL,incDepth                    ; Count the frame.
    INC  (HL)                           ; It is in use.
    RET                                 ; The included file can begin.

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY
; Resume the newest waiting file. Return its ordinal in A, the offset where it
; resumes in HL and that byte's line in DE.

incPop: ; Resume a file whose include has been assembled.
    LD   HL,incDepth                    ; Release the newest frame.
    DEC  (HL)                           ; It is no longer in use.
    LD   A,(HL)                         ; Select it.
    PUSH AF                             ; Keep its index.
    CALL incFrame                       ; Address its header.
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
    POP  AF                             ; Recover the frame index.
    PUSH BC                             ; Keep the resume offset.
    CALL sfBack                         ; The host restores the file's read state.
    POP  BC                             ; Recover the resume offset.
    XOR  A                              ; Clear the per-line state.
    LD   (ppMode),A                     ; Not in a directive, not at a line start.
    LD   (ppLastCr),A                   ; The resume byte is a line ending.
    LD   (ppEnded),A                    ; The file's end is still ahead.
    LD   (ppDefOk),A                    ; No definition may follow an include.
    INC  A                              ; Form one.
    LD   (incHead),A                    ; The file is still in its header.
    LD   A,(srcPart)                    ; Return the ordinal.
    LD   H,B                            ; Return the resume offset.
    LD   L,C                            ; Complete it.
    LD   DE,(ppLine)                    ; Return its line.
    OR   A                              ; Clear carry.
    RET                                 ; The driver resumes the file.

;@ROUTINE IN A CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Record failure message A at the directive just applied. Only the first
; failure is kept.

incFail: ; Record a failure and where it happened.
    LD   L,A                            ; Keep the message.
    LD   A,(incErr)                     ; Is a failure already recorded?
    OR   A                              ; Zero means none.
    RET  NZ                             ; Keep the first.
    LD   A,L                            ; Recover the message.
    LD   (incErr),A                     ; Keep it.
    LD   A,(srcPart)                    ; The part being read.
    LD   (incErrAt),A                   ; Keep it.
    LD   HL,(ppDirAt)                   ; Where the directive started.
    LD   (incErrAt+1),HL                ; Keep the offset.
    LD   HL,(ppDirLn)                   ; And its line.
    LD   (incErrAt+3),HL                ; Keep it.
    RET                                 ; tkOpen reports the failure.
