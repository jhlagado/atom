;=============================================================================
;  CP/M memory map
;=============================================================================
;
;  Every fixed address the adapter uses is defined here.
;
;    $0100     The entry jump, then the core and the resident adapter.
;    cpResEnd  The spool and replay code (spool.asm), the end of ATOM.COM.
;    $5E00     cpWork. The writable areas start here. They are set up before
;              use, so they take addresses but no bytes in the file.
;    $E200     The 512-byte private stack, from cpFloor up to cpStack.
;
;  The writable areas change role once assembly ends. The symbols, pending
;  references and source tables are no longer needed, so replay reuses their
;  memory:
;
;    Address   During assembly              During replay
;    $5E00     Include frames and state     Replay FCB, input record, state
;    $5F00     Source cache record          Intel HEX and symbol buffer
;    $5F80     Source names, saved parent   Output window, up to $E180
;              records, symbols,
;              references and the spool
;              buffers
;
;  State that must survive the handover lives in cpmstate.asm, inside
;  ATOM.COM and below cpWork, where the output window never reaches.

cpCall5     EQU     $0005                       ; CP/M BDOS entry address.
cpWork      EQU     $5E00                       ; First byte of transient writable arenas.
incStack    EQU     cpWork                      ; Include frames: the parts waiting for their includes.
incFrLen    EQU     6                           ; Frame: ordinal, resume offset, line, condition base.
incMax      EQU     8                           ; Deepest include nesting.
incFound    EQU     incStack+incFrLen*incMax    ; Number of retained source names.
incDepth    EQU     incFound+1                  ; Number of frames in use.
incNext     EQU     incDepth+1                  ; Part tkOpen supplies next, or $FF.
srcPart     EQU     incNext+1                   ; Ordinal of the part being read.
incHead     EQU     srcPart+1                   ; Nonzero while the part is still in its header.
incErrAt    EQU     incHead+1                   ; A front-end failure's part, offset and line, or part $FF.
incErrNm    EQU     incErrAt+5                  ; Drive and 8.3 name of a file that failed to read.
srcPos      EQU     incErrNm+12                 ; Logical offset saved during a cache lookup.
ppDepth     EQU     srcPos+2                    ; Number of open conditional frames.
ppActive    EQU     ppDepth+1                   ; Activity of the currently selected branch.
ppBase      EQU     ppActive+1                  ; Conditional depth when the current part began.
ppDefOk     EQU     ppBase+1                    ; Nonzero while entry-header definitions remain legal.
ppDefCnt    EQU     ppDefOk+1                   ; Number of complete numeric definitions.
ppMode      EQU     ppDefCnt+1                  ; Bit 0 line start, bit 1 directive, bit 2 last record.
ppLastCr    EQU     ppMode+1                    ; Nonzero when the previous byte was CR.
ppEnded     EQU     ppLastCr+1                  ; Nonzero once the part's end has been checked.
ppCapLen    EQU     ppEnded+1                   ; Directive bytes captured, $FE overflow, $FF done.
ppLine      EQU     ppCapLen+1                  ; Line of the byte being filtered.
ppDirAt     EQU     ppLine+2                    ; Offset of the directive's '%'.
ppDirLn     EQU     ppDirAt+2                   ; Line of the directive.
ppPos       EQU     ppDirLn+2                   ; Offset of the byte being filtered.
ppTokLen    EQU     ppPos+2                     ; Significant byte length of the current token.
ppRadix     EQU     ppTokLen+1                  ; Numeric radix selected for token conversion.
ppFirst     EQU     ppRadix+1                   ; Token index of the first numeric digit.
ppDigits    EQU     ppFirst+1                   ; Number of numeric digits excluding prefix or suffix.
ppIndex     EQU     ppDigits+1                  ; Next digit index within numeric conversion.
ppTemp      EQU     ppIndex+1                   ; Character or condition saved across helper calls.
ppSrcPtr    EQU     ppTemp+1                    ; Directive cursor saved during token lookup.
ppAfter     EQU     ppSrcPtr+2                  ; Directive cursor saved after a validated value.
ppValue     EQU     ppAfter+2                   ; Unsigned sixteen-bit definition or condition value.
ppLength    EQU     ppValue+2                   ; Significant length of the staged definition name.
ppVarEnd    EQU     ppLength+1                  ; Exclusive end of scalar preprocessor workspace.
ppStack     EQU     ppVarEnd                    ; Sixteen one-byte parent, condition and ELSE frames.
ppLimit     EQU     ppStack+16                  ; Exclusive end of the conditional stack.
ppLnMax     EQU     64                          ; Longest directive before its comment.
ppLnBuf     EQU     ppLimit                     ; The directive line, ended by CR.
ppLnEnd     EQU     ppLnBuf+ppLnMax+1           ; Exclusive end of the directive line.
srcCache    EQU     cpWork+$100                 ; 128-byte random-source DMA cache.
srcCEnd     EQU     srcCache+$80                ; Exclusive end of the source DMA cache.
incNames    EQU     srcCEnd                     ; Eleven-byte retained CP/M source names.
incNEnd     EQU     incNames+$AF5               ; Exclusive end of 255 retained-name slots.
incState    EQU     incNEnd                     ; Per name: 0 not begun, 1 open, 2 finished.
incSEnd     EQU     incState+255                ; Exclusive end of the name states.
incSvLen    EQU     36+2+128                    ; Saved parent: FCB, cache key and cache record.
incSaves    EQU     incSEnd                     ; One saved parent per include frame.
incSvEnd    EQU     incSaves+incSvLen*incMax    ; Exclusive end of the saved parents.
ppRecLen    EQU     20                          ; Definition record size: length, 17 name bytes and value.
ppDefMax    EQU     32                          ; Maximum distinct native numeric definitions.
ppDefBeg    EQU     incSvEnd                    ; Beginning of the fixed-width definition table.
ppDefLen    EQU     ppRecLen*ppDefMax           ; Total bytes reserved for definition records.
ppDefEnd    EQU     ppDefBeg+ppDefLen           ; Exclusive end of the definition table.
ppToken     EQU     ppDefEnd                    ; Seventeen-byte uppercase directive or value token.
ppTokEnd    EQU     ppToken+17                  ; Exclusive end of the token buffer.
ppName      EQU     ppTokEnd                    ; Separately staged padded definition name.
ppWidth     EQU     17                          ; Maximum significant definition-name length.
incEnd      EQU     ppName+ppWidth              ; Exclusive end of include and preprocessor workspace.
; INCBIN reads one file at a time through its own FCB and record buffer, so
; binary reads never disturb the source cache.
binRamLo    EQU     incEnd                      ; Beginning of the INCBIN reader's workspace.
binLeft     EQU     binRamLo                    ; Bytes remaining in the buffered record.
binRPtr     EQU     binLeft+1                   ; Address of the next buffered byte.
binBuf      EQU     binRPtr+2                   ; 128-byte binary record buffer.
binFcb      EQU     binBuf+128                  ; 36-byte binary input FCB.
binFcbHi    EQU     binFcb+36                   ; Exclusive end of the binary input FCB.
binRamHi    EQU     binFcbHi                    ; Exclusive end of the INCBIN reader's workspace.
cpSymBeg    EQU     binRamHi                    ; Beginning of the caller-owned symbol arena.
cpSymEnd    EQU     cpSymBeg+$3000              ; Exclusive end of the twelve-KiB symbol arena.
cpRefBeg    EQU     cpSymEnd                    ; Beginning of the pending-reference arena.
cpRefEnd    EQU     cpRefBeg+$1000              ; Exclusive end of the four-KiB pending arena.
asoBufs     EQU     cpRefEnd                    ; Beginning of assembly-phase ASO buffers.
matLimit    EQU     cpWork+$8380                ; Exclusive ceiling of the replay output window.
; The operation writer owns high TPA buffers only during assembly. Once the
; ASO file is closed, the include page becomes materialiser workspace.
asoFcb      EQU     asoBufs                     ; 36-byte FCB for the tentative operation stream.
asoRun      EQU     asoFcb+36                   ; 128-byte buffer for one coalesced IMAGE run.
asoRec      EQU     asoRun+128                  ; 128-byte physical ASO output record.
matFcb      EQU     incStack                    ; Replay FCB overlaid on the finished include page.
matRec      EQU     matFcb+36                   ; 128-byte replay input record after the replay FCB.
matVars     EQU     matRec+128                  ; Beginning of replay scalar state in the include page.
matPtr      EQU     matVars+1                   ; Address of the next buffered ASO input byte.
matHave     EQU     matVars+3                   ; Unread bytes in the physical ASO input record.
matByte     EQU     matVars+4                   ; Decoded payload or temporary word low byte.
matFill     EQU     matVars+5                   ; Validated gap-fill byte from the ASO header.
matWOff     EQU     matVars+6                   ; Current replay window offset relative to origin.
matWLen     EQU     matVars+8                   ; Bytes in the selected replay output window.
matWCnt     EQU     matVars+10                  ; Window bytes remaining during sequential record writes.
matWPtr     EQU     matVars+12                  ; DMA address of the next output record.
matLeft     EQU     matVars+14                  ; Output bytes remaining across replay windows.
matKind     EQU     matVars+16                  ; Reserved record-kind byte in the replay layout.
matRLen     EQU     matVars+17                  ; Current IMAGE or PATCH payload byte count.
matRCnt     EQU     matVars+18                  ; Payload bytes remaining to consume this pass.
matAddr     EQU     matVars+19                  ; Absolute IMAGE or PATCH start address.
matROff     EQU     matVars+21                  ; Current payload address relative to image origin.
matREnd     EQU     matVars+23                  ; Checked operation endpoint used during validation.
matImEnd    EQU     matVars+25                  ; Greatest preceding absolute IMAGE endpoint low word.
matImTop    EQU     matVars+27                  ; Nonzero when IMAGE extent ends at $10000.
matPrev     EQU     matVars+28                  ; Previous record kind for canonical IMAGE checks.
matPLen     EQU     matVars+29                  ; Previous IMAGE payload length for coalescing checks.
matRTop     EQU     matVars+30                  ; Nonzero when a PATCH endpoint is $10000.
matVEnd     EQU     matVars+31                  ; Exclusive end of replay scalar state.
cpTpa       EQU     $0100                       ; CP/M transient program load address and output origin.
asoCap      EQU     $FF00                       ; Maximum output span from $0100 to $10000.
matWin      EQU     srcCEnd                     ; Replay output window after retained replay workspace.
cpStack     EQU     $E400                       ; Exclusive top of the private transient stack.
cpFloor     EQU     cpStack-$200                ; Lowest byte of the 512-byte stack.
cpGuard     EQU     $A5                         ; Pattern kept at the stack floor.
cpSetDma    EQU     26                          ; BDOS function 26 sets the transfer-buffer address.
cpOpen      EQU     15                          ; BDOS function 15 opens a file.
cpClose     EQU     16                          ; BDOS function 16 closes a file.
cpErase     EQU     19                          ; BDOS function 19 deletes a file.
cpRead      EQU     20                          ; BDOS function 20 reads a sequential record.
cpReadAt    EQU     33                          ; BDOS function 33 reads a random record.
cpWrite     EQU     21                          ; BDOS function 21 writes a sequential record.
cpWrRand    EQU     34                          ; BDOS function 34 writes a random record.
cpMake      EQU     22                          ; BDOS function 22 creates a file.
cpRename    EQU     23                          ; BDOS function 23 renames a file.
cpText      EQU     9                           ; BDOS function 9 prints a dollar-terminated string.
cmdLen      EQU     $0080                       ; CCP command-tail length byte.
cmdTail     EQU     $0081                       ; First byte of the CCP command tail.

