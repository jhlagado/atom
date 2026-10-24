;=============================================================================
;  CP/M memory map
;=============================================================================
;
;  The fixed addresses the adapter uses are defined here. The rest of the TPA
;  is sized at entry from the BDOS address in the word at $0006.
;
;    $0100     The entry jump, then the core and the resident adapter.
;    cpResEnd  The spool and replay code (spool.asm), the end of ATOM.COM.
;    $5E00     cpWork. The writable areas start here. They are set up before
;              use, so they take addresses but no bytes in the file.
;    feRamHi   The end of the fixed workspace. The symbol arena takes three
;              quarters of the memory from here to the stack floor and the
;              pending-reference arena takes the rest.
;    BDOS-512  The 512-byte private stack, up to the BDOS entry.
;
;  The writable areas change role once assembly ends. The symbols, pending
;  references and source tables are no longer needed, so replay reuses their
;  memory:
;
;    Address   During assembly              During replay
;    $5E00     Source state                 Replay FCB, input record, state
;    $5F00     Source cache record          Intel HEX and symbol buffer
;    $5F80     Source names, saved files,   Output window, whole records
;              the spool buffers, the       up to the stack floor
;              front end's workspace,
;              symbols and references
;
;  State that must survive the handover lives in cpmstate.asm, inside
;  ATOM.COM and below cpWork, where the output window never reaches.

;@ROUTINE IN C,DE OUT A CLOBBERS BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
cpCall5     EQU     $0005                       ; CP/M BDOS entry address.
cpWork      EQU     $5E00                       ; First byte of transient writable arenas.
incMax      EQU     8                           ; Deepest include nesting.
srcPage     EQU     cpWork                      ; CP/M source state. Replay reuses the page.
incFound    EQU     srcPage                     ; Number of retained source names.
srcRoot     EQU     incFound+1                  ; Nonzero once the root has been supplied.
srcPos      EQU     srcRoot+1                   ; Logical offset saved during a cache lookup.
srcFresh    EQU     srcPos+2                    ; Nonzero while the root is open and unread.
srcPgEnd    EQU     srcFresh+1                  ; Exclusive end of the CP/M source state.
srcCache    EQU     cpWork+$100                 ; 128-byte random-source DMA cache.
srcCEnd     EQU     srcCache+$80                ; Exclusive end of the source DMA cache.
incNames    EQU     srcCEnd                     ; Eleven-byte retained CP/M source names.
incNEnd     EQU     incNames+$AF5               ; Exclusive end of 255 retained-name slots.
srcSvLen    EQU     36+2+128                    ; Saved file: FCB, cache key and cache record.
srcSaves    EQU     incNEnd                     ; One saved file per include frame.
incEnd      EQU     srcSaves+srcSvLen*incMax    ; Exclusive end of the source workspace.
; INCBIN reads one file at a time through its own FCB and record buffer, so
; binary reads never disturb the source cache.
binRamLo    EQU     incEnd                      ; Beginning of the INCBIN reader's workspace.
binLeft     EQU     binRamLo                    ; Bytes remaining in the buffered record.
binRPtr     EQU     binLeft+1                   ; Address of the next buffered byte.
binBuf      EQU     binRPtr+2                   ; 128-byte binary record buffer.
binFcb      EQU     binBuf+128                  ; 36-byte binary input FCB.
binFcbHi    EQU     binFcb+36                   ; Exclusive end of the binary input FCB.
binRamHi    EQU     binFcbHi                    ; Exclusive end of the INCBIN reader's workspace.
; The operation writer owns these buffers only during assembly. Once the
; ASO file is closed, the source page becomes materialiser workspace.
asoBufs     EQU     binRamHi                    ; Beginning of assembly-phase ASO buffers.
asoFcb      EQU     asoBufs                     ; 36-byte FCB for the tentative operation stream.
asoRun      EQU     asoFcb+36                   ; 128-byte buffer for one coalesced IMAGE run.
asoRec      EQU     asoRun+128                  ; 128-byte physical ASO output record.
feRamLo     EQU     asoRec+128                  ; The source front end's workspace, up to feRamHi.
matFcb      EQU     srcPage                     ; Replay FCB overlaid on the finished source page.
matRec      EQU     matFcb+36                   ; 128-byte replay input record after the replay FCB.
matVars     EQU     matRec+128                  ; Beginning of replay scalar state in the source page.
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
cpStkLen    EQU     $200                        ; Bytes of private stack below the BDOS entry.
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

