;=============================================================================
;  CP/M memory map
;=============================================================================
;
;  Every fixed address the adapter uses is defined here.
;
;    $0100     The entry jump, then the core and the resident adapter.
;    cpResEnd  The spool and replay code (spool.asm), the end of ATOM.COM.
;    $5D00     cpWork. The writable areas start here. They are set up before
;              use, so they take addresses but no bytes in the file.
;    $E200     The 512-byte private stack, from cpFloor up to cpStack.
;
;  The writable areas change role once assembly ends. The symbols, pending
;  references and source tables are no longer needed, so replay reuses their
;  memory:
;
;    Address   During assembly              During replay
;    $5D00     Part-order page              Replay FCB, input record, state
;    $5E00     Source cache record          Intel HEX output buffer
;    $5E80     Source names, descriptors,   Output window, up to $E080
;              symbols, references and
;              the spool buffers
;
;  State that must survive the handover lives in cpmstate.asm, inside
;  ATOM.COM and below cpWork, where the output window never reaches.

cpCall5     EQU     $0005                       ; CP/M BDOS entry address.
cpWork      EQU     $5D00                       ; First byte of transient writable arenas.
incOrder    EQU     cpWork                      ; Dependency-order table with one byte per part.
incOEnd     EQU     incOrder+$100               ; Exclusive end of the 256-byte order page.
srcCache    EQU     incOEnd                     ; 128-byte random-source DMA cache.
srcCEnd     EQU     srcCache+$80                ; Exclusive end of the source DMA cache.
incNames    EQU     srcCEnd                     ; Eleven-byte retained CP/M source names.
incNEnd     EQU     incNames+$AF5               ; Exclusive end of 255 retained-name slots.
incDescs    EQU     incNEnd                     ; Five-byte source descriptors in assembly order.
incDEnd     EQU     incDescs+$4FB               ; Exclusive end of 255 source-descriptor slots.
incFound    EQU     incDEnd                     ; Number of discovered source names.
incDone     EQU     incFound+1                  ; Number of sources already placed in dependency order.
incDPtr     EQU     incDone+1                   ; Address of the next source-descriptor slot.
srcPart     EQU     incDPtr+2                   ; Currently selected dependency-order source ordinal.
incMode     EQU     srcPart+1                   ; Zero discovers names, one checks dependency order.
incIdx      EQU     incMode+1                   ; Current discovery or ordering ordinal.
incSteps    EQU     incIdx+1                    ; Includes followed by the current ordering walk.
incChild    EQU     incSteps+1                  ; First unplaced include found by an ordering scan.
incHead     EQU     incChild+1                  ; Nonzero while source remains in its leading header.
srcPos      EQU     incHead+1                   ; Logical offset saved during a cache lookup.
srcTemp     EQU     srcPos+2                    ; Source byte saved while advancing its offset.
ppDepth     EQU     srcTemp+1                   ; Number of open conditional frames.
ppActive    EQU     ppDepth+1                   ; Activity of the currently selected branch.
ppDefOk     EQU     ppActive+1                  ; Nonzero while entry-header definitions remain legal.
ppDefCnt    EQU     ppDefOk+1                   ; Number of complete numeric definitions.
ppTokLen    EQU     ppDefCnt+1                  ; Significant byte length of the current token.
ppRadix     EQU     ppTokLen+1                  ; Numeric radix selected for token conversion.
ppFirst     EQU     ppRadix+1                   ; Token index of the first numeric digit.
ppDigits    EQU     ppFirst+1                   ; Number of numeric digits excluding prefix or suffix.
ppIndex     EQU     ppDigits+1                  ; Next digit index within numeric conversion.
ppTemp      EQU     ppIndex+1                   ; Character or condition saved across helper calls.
ppSpare     EQU     ppTemp+1                    ; Reserved byte in preprocessor workspace.
ppDirOff    EQU     ppSpare+1                   ; Last directive offset applied during runtime filtering.
ppSrcPtr    EQU     ppDirOff+2                  ; Source cursor saved during token lookup.
ppWord      EQU     ppSrcPtr+2                  ; Source offset immediately after a directive percent.
ppPos       EQU     ppWord+2                    ; Offset of the raw source byte being filtered.
ppAfter     EQU     ppPos+2                     ; Source cursor saved after a validated directive line.
ppValue     EQU     ppAfter+2                   ; Unsigned sixteen-bit definition or condition value.
ppLength    EQU     ppValue+2                   ; Significant length of the staged definition name.
ppVarEnd    EQU     ppLength+1                  ; Exclusive end of scalar preprocessor workspace.
ppStack     EQU     ppVarEnd                    ; Sixteen one-byte parent, condition and ELSE frames.
ppLimit     EQU     ppStack+16                  ; Exclusive end of the conditional stack.
ppRecLen    EQU     20                          ; Definition record size: length, 17 name bytes and value.
ppDefMax    EQU     32                          ; Maximum distinct native numeric definitions.
ppDefBeg    EQU     ppLimit                     ; Beginning of the fixed-width definition table.
ppDefLen    EQU     ppRecLen*ppDefMax           ; Total bytes reserved for definition records.
ppDefEnd    EQU     ppDefBeg+ppDefLen           ; Exclusive end of the definition table.
ppToken     EQU     ppDefEnd                    ; Seventeen-byte uppercase directive or value token.
ppTokEnd    EQU     ppToken+17                  ; Exclusive end of the token buffer.
ppName      EQU     ppTokEnd                    ; Separately staged padded definition name.
ppWidth     EQU     17                          ; Maximum significant definition-name length.
incEnd      EQU     ppName+ppWidth              ; Exclusive end of include and preprocessor workspace.
; Each binary include keeps its source position, explicit byte count, CP/M
; filename and ten-byte DS replacement. Thirty-two rows bound native use.
binMax      EQU     32                          ; Maximum active native INCBIN statements.
binSize     EQU     28                          ; Metadata row size including ten-byte DS replacement.
binName     EQU     7                           ; Row offset of the eleven-byte CP/M binary name.
binDsOff    EQU     18                          ; Row offset of the generated DS replacement text.
binDsLen    EQU     10                          ; Bytes in the fixed DS $hhhh,0 replacement.
binCount    EQU     incEnd                      ; Number of complete INCBIN metadata rows.
binTable    EQU     binCount+1                  ; Beginning of fixed-width binary metadata rows.
binLimit    EQU     binTable+binMax*binSize     ; Exclusive end of the binary metadata table.
binRamLo    EQU     binLimit                    ; Beginning of binary filtering and reader workspace.
binReady    EQU     binRamLo                    ; Nonzero once all binary metadata passes preflight.
binFIdx     EQU     binReady+1                  ; Row ordinal used by runtime source filtering.
binFPtr     EQU     binFIdx+1                   ; Address of the current source-filter metadata row.
binFPart    EQU     binFPtr+2                   ; Source part associated with the filter cursor.
binFPos     EQU     binFPart+1                  ; Last source offset supplied to the filter.
binSIdx     EQU     binFPos+2                   ; Row ordinal consumed by IMAGE substitution.
binSPtr     EQU     binSIdx+1                   ; Address of the current IMAGE-substitution row.
binBusy     EQU     binSPtr+2                   ; Nonzero while an INCBIN row is emitting bytes.
binSPart    EQU     binBusy+1                   ; Current IMAGE statement source-part ordinal.
binSPos     EQU     binSPart+1                  ; Current IMAGE statement source offset.
binDue      EQU     binSPos+2                   ; Payload bytes still required by the active row.
binVal      EQU     binDue+2                    ; Binary payload or ordinary IMAGE fill byte.
binLeft     EQU     binVal+1                    ; Bytes remaining in the buffered binary record.
binRPtr     EQU     binLeft+1                   ; Address of the next buffered binary payload byte.
binPart     EQU     binRPtr+2                   ; Source-part ordinal during binary preflight.
binPos      EQU     binPart+1                   ; Next logical source offset during binary preflight.
binDesc     EQU     binPos+2                    ; Address of the source descriptor being scanned.
binStop     EQU     binDesc+2                   ; Exclusive source offset cached from that descriptor.
binLine     EQU     binStop+2                   ; First token offset on the current source line.
binSite     EQU     binLine+2                   ; Exact source offset of the INCBIN keyword.
binEol      EQU     binSite+2                   ; Exclusive content end before original CR or LF bytes.
binLen      EQU     binEol+2                    ; Explicit sixteen-bit binary payload length.
binFile     EQU     binLen+2                    ; Eleven-byte normalised binary filename.
binTemp     EQU     binFile+11                  ; Token byte or delimiter saved across checks.
binFree     EQU     binTemp+1                   ; Address of the next unused binary metadata row.
binFcb      EQU     binFree+2                   ; Independent 36-byte binary input FCB.
binFEnd     EQU     binFcb+36                   ; Exclusive end of the binary input FCB.
binRamHi    EQU     binFEnd                     ; Exclusive end of binary preflight and reader workspace.
cpSymBeg    EQU     binRamHi                    ; Beginning of the caller-owned symbol arena.
cpSymEnd    EQU     cpSymBeg+$3000              ; Exclusive end of the twelve-KiB symbol arena.
cpRefBeg    EQU     cpSymEnd                    ; Beginning of the pending-reference arena.
cpRefEnd    EQU     cpRefBeg+$1000              ; Exclusive end of the four-KiB pending arena.
asoBufs     EQU     cpRefEnd                    ; Beginning of assembly-phase ASO buffers.
matLimit    EQU     cpWork+$8380                ; Exclusive ceiling of the replay output window.
; The operation writer owns high TPA buffers only during assembly. Once the
; ASO file is closed, the old part-order page becomes materialiser workspace.
asoFcb      EQU     asoBufs                     ; 36-byte FCB for the tentative operation stream.
asoRun      EQU     asoFcb+36                   ; 128-byte buffer for one coalesced IMAGE run.
asoRec      EQU     asoRun+128                  ; 128-byte physical ASO output record.
matFcb      EQU     incOrder                    ; Replay FCB overlaid on the completed part-order page.
matRec      EQU     matFcb+36                   ; 128-byte replay input record after the replay FCB.
matVars     EQU     matRec+128                  ; Beginning of replay scalar state in the old order page.
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

