; Atom CP/M 2.2 transient adapter
;
; The generated COM places the native Atom core at $0110. The first sixteen
; bytes are supplied by scripts/generate-cpm22.mjs. Source bytes are read from
; BDOS through one random-record cache. Atom's IMAGE and PATCH operations are
; spooled to NAME.$$B, replayed into NAME.$$$ and published only after Atom
; commits.
;
; scripts/generate-cpm22.mjs links this file with the core and splices four
; modules in at the ;@@...@@ marker lines: cpprep.asm (the %DEFINE and %IF
; preprocessor), aso.asm and mat.asm (the spool writer and materialiser
; overlay) and the Z80 Tool Services Intel HEX writer.
;
; The adapter owns five jobs outside the assembler core:
;   1. parse a compact CP/M command tail and choose COM, BIN or Intel HEX;
;   2. discover leading %INCLUDE directives and derive dependency-first parts;
;   3. serve random source bytes from CP/M files through a 128-byte cache;
;   4. spool ordered operations, then materialise COM/BIN/HEX through a fixed
;      TPA output window or retain explicit ASO output. and
;   5. publish completed output through the $$$ and $$B work files.
;
; Atom itself has no filesystem calls. Its five-byte part descriptors use the
; half-open logical range [0,length). SRC_READ maps the ordinal
; through the derived order, opens the matching FCB and supplies the byte.

; The COM contains code through the ASO writer/materialiser. Its writable
; arenas begin at CP_WORK and are initialised before use, so they
; need addresses in the TPA but no bytes in the loaded file. The output window
; and private stack remain above those arenas.

CP_CALL5    EQU     $0005                       ; CP/M BDOS entry address.
CP_WORK     EQU     $5D00                       ; First byte of transient writable arenas.
INC_ORD     EQU     CP_WORK                     ; Dependency-order table with one byte per part.
INC_OEND    EQU     INC_ORD+$100                ; Exclusive end of the 256-byte order page.
SRC_PAGE    EQU     INC_OEND                    ; 128-byte random-source DMA cache.
SRC_PEND    EQU     SRC_PAGE+$80                ; Exclusive end of the source DMA cache.
INC_LIST    EQU     SRC_PEND                    ; Eleven-byte retained CP/M source names.
INC_LEND    EQU     INC_LIST+$AF5               ; Exclusive end of 255 retained-name slots.
INC_DESC    EQU     INC_LEND                    ; Five-byte source descriptors in assembly order.
INC_DEND    EQU     INC_DESC+$4FB               ; Exclusive end of 255 source-descriptor slots.
INC_NCNT    EQU     INC_DEND                    ; Number of discovered source names.
INC_OCNT    EQU     INC_NCNT+1                  ; Number of sources already placed in dependency order.
INC_DPTR    EQU     INC_OCNT+1                  ; Address of the next source-descriptor slot.
SRC_PART    EQU     INC_DPTR+2                  ; Currently selected dependency-order source ordinal.
INC_MODE    EQU     SRC_PART+1                  ; Zero discovers names, one checks dependency order.
INC_IDX     EQU     INC_MODE+1                  ; Current discovery or ordering ordinal.
INC_GAIN    EQU     INC_IDX+1                   ; Nonzero when the current ordering pass made progress.
INC_HEAD    EQU     INC_GAIN+1                  ; Nonzero while source remains in its leading header.
SRC_POS     EQU     INC_HEAD+1                  ; Logical offset saved during a cache lookup.
SRC_TMP     EQU     SRC_POS+2                   ; Source byte saved while advancing its offset.
PP_DEPTH    EQU     SRC_TMP+1                   ; Number of open conditional frames.
PP_LIVE     EQU     PP_DEPTH+1                  ; Activity of the currently selected branch.
PP_DEFOK    EQU     PP_LIVE+1                   ; Nonzero while entry-header definitions remain legal.
PP_NDEFS    EQU     PP_DEFOK+1                  ; Number of complete numeric definitions.
PP_TLEN     EQU     PP_NDEFS+1                  ; Significant byte length of the current token.
PP_BASE     EQU     PP_TLEN+1                   ; Numeric radix selected for token conversion.
PP_FIRST    EQU     PP_BASE+1                   ; Token index of the first numeric digit.
PP_COUNT    EQU     PP_FIRST+1                  ; Number of numeric digits excluding prefix or suffix.
PP_INDEX    EQU     PP_COUNT+1                  ; Next digit index within numeric conversion.
PP_TMP      EQU     PP_INDEX+1                  ; Character or condition saved across helper calls.
PP_ALLOW    EQU     PP_TMP+1                    ; Reserved byte in preprocessor workspace.
PP_LAST     EQU     PP_ALLOW+1                  ; Last directive offset applied during runtime filtering.
PP_SRC      EQU     PP_LAST+2                   ; Source cursor saved during token lookup.
PP_WORD     EQU     PP_SRC+2                    ; Source offset immediately after a directive percent.
PP_POS      EQU     PP_WORD+2                   ; Offset of the raw source byte being filtered.
PP_AFTER    EQU     PP_POS+2                    ; Source cursor saved after a validated directive line.
PP_VALUE    EQU     PP_AFTER+2                  ; Unsigned sixteen-bit definition or condition value.
PP_NLEN     EQU     PP_VALUE+2                  ; Significant length of the staged definition name.
PP_VEND     EQU     PP_NLEN+1                   ; Exclusive end of scalar preprocessor workspace.
PP_STACK    EQU     PP_VEND                     ; Sixteen one-byte parent, condition and ELSE frames.
PP_SEND     EQU     PP_STACK+16                 ; Exclusive end of the conditional stack.
PP_REC      EQU     20                          ; Definition record size: length, 17 name bytes and value.
PP_CAP      EQU     32                          ; Maximum distinct native numeric definitions.
PP_DEFS     EQU     PP_SEND                     ; Beginning of the fixed-width definition table.
PP_SIZE     EQU     PP_REC*PP_CAP               ; Total bytes reserved for definition records.
PP_DEND     EQU     PP_DEFS+PP_SIZE             ; Exclusive end of the definition table.
PP_TOKEN    EQU     PP_DEND                     ; Seventeen-byte uppercase directive or value token.
PP_TEND     EQU     PP_TOKEN+17                 ; Exclusive end of the token buffer.
PP_NAME     EQU     PP_TEND                     ; Separately staged padded definition name.
PP_WIDTH    EQU     17                          ; Maximum significant definition-name length.
INC_WEND    EQU     PP_NAME+PP_WIDTH            ; Exclusive end of include and preprocessor workspace.
; Each binary include keeps its source position, explicit byte count, CP/M
; filename and ten-byte DS replacement. Thirty-two rows bound native use.
BIN_CAP     EQU     32                          ; Maximum active native INCBIN statements.
BIN_SIZE    EQU     28                          ; Metadata row size including ten-byte DS replacement.
BIN_NAME    EQU     7                           ; Row offset of the eleven-byte CP/M binary name.
BIN_DS      EQU     18                          ; Row offset of the generated DS replacement text.
BIN_SPAN    EQU     10                          ; Bytes in the fixed DS $hhhh,0 replacement.
BIN_CNT     EQU     INC_WEND                    ; Number of complete INCBIN metadata rows.
BIN_TAB     EQU     BIN_CNT+1                   ; Beginning of fixed-width binary metadata rows.
BIN_TEND    EQU     BIN_TAB+BIN_CAP*BIN_SIZE    ; Exclusive end of the binary metadata table.
BIN_WBEG    EQU     BIN_TEND                    ; Beginning of binary filtering and reader workspace.
BIN_LIVE    EQU     BIN_WBEG                    ; Nonzero once all binary metadata passes preflight.
BIN_FIDX    EQU     BIN_LIVE+1                  ; Row ordinal used by runtime source filtering.
BIN_FPTR    EQU     BIN_FIDX+1                  ; Address of the current source-filter metadata row.
BIN_FORD    EQU     BIN_FPTR+2                  ; Source part associated with the filter cursor.
BIN_FPOS    EQU     BIN_FORD+1                  ; Last source offset supplied to the filter.
BIN_SIDX    EQU     BIN_FPOS+2                  ; Row ordinal consumed by IMAGE substitution.
BIN_SPTR    EQU     BIN_SIDX+1                  ; Address of the current IMAGE-substitution row.
BIN_BUSY    EQU     BIN_SPTR+2                  ; Nonzero while an INCBIN row is emitting bytes.
BIN_SORD    EQU     BIN_BUSY+1                  ; Current IMAGE statement source-part ordinal.
BIN_SPOS    EQU     BIN_SORD+1                  ; Current IMAGE statement source offset.
BIN_DUE     EQU     BIN_SPOS+2                  ; Payload bytes still required by the active row.
BIN_VAL     EQU     BIN_DUE+2                   ; Binary payload or ordinary IMAGE fill byte.
; These two live flags must survive replay, which reuses the high workspace.
BIN_ERR     EQU     BIN_RERR                    ; Alias for the low resident binary-failure flag.
BIN_HELD    EQU     BIN_RFCB                    ; Alias for the low resident binary-FCB ownership flag.
BIN_LEFT    EQU     BIN_VAL+1                   ; Bytes remaining in the buffered binary record.
BIN_RPTR    EQU     BIN_LEFT+1                  ; Address of the next buffered binary payload byte.
BIN_PART    EQU     BIN_RPTR+2                  ; Source-part ordinal during binary preflight.
BIN_POS     EQU     BIN_PART+1                  ; Next logical source offset during binary preflight.
BIN_DESC    EQU     BIN_POS+2                   ; Address of the source descriptor being scanned.
BIN_STOP    EQU     BIN_DESC+2                  ; Exclusive source offset cached from that descriptor.
BIN_LINE    EQU     BIN_STOP+2                  ; First token offset on the current source line.
BIN_SITE    EQU     BIN_LINE+2                  ; Exact source offset of the INCBIN keyword.
BIN_EOL     EQU     BIN_SITE+2                  ; Exclusive content end before original CR or LF bytes.
BIN_LEN     EQU     BIN_EOL+2                   ; Explicit sixteen-bit binary payload length.
BIN_FILE    EQU     BIN_LEN+2                   ; Eleven-byte normalised binary filename.
BIN_TMP     EQU     BIN_FILE+11                 ; Token byte or delimiter saved across checks.
BIN_FREE    EQU     BIN_TMP+1                   ; Address of the next unused binary metadata row.
BIN_FCB     EQU     BIN_FREE+2                  ; Independent 36-byte binary input FCB.
BIN_FEND    EQU     BIN_FCB+36                  ; Exclusive end of the binary input FCB.
BIN_WEND    EQU     BIN_FEND                    ; Exclusive end of binary preflight and reader workspace.
CP_SYMB     EQU     BIN_WEND                    ; Beginning of the caller-owned symbol arena.
CP_SYME     EQU     CP_SYMB+$3000               ; Exclusive end of the twelve-KiB symbol arena.
CP_PENDB    EQU     CP_SYME                     ; Beginning of the pending-reference arena.
CP_PENDE    EQU     CP_PENDB+$1000              ; Exclusive end of the four-KiB pending arena.
ASO_WBEG    EQU     CP_PENDE                    ; Beginning of assembly-phase ASO buffers.
MAT_WEND    EQU     CP_WORK+$8380               ; Exclusive ceiling of the replay output window.
; The operation writer owns high TPA buffers only during assembly. Once the
; ASO file is closed, the old part-order page becomes materialiser workspace.
ASO_FCB     EQU     ASO_WBEG                    ; 36-byte FCB for the tentative operation stream.
ASO_RUN     EQU     ASO_FCB+36                  ; 128-byte buffer for one coalesced IMAGE run.
ASO_REC     EQU     ASO_RUN+128                 ; 128-byte physical ASO output record.
MAT_FCB     EQU     INC_ORD                     ; Replay FCB overlaid on the completed part-order page.
MAT_REC     EQU     MAT_FCB+36                  ; 128-byte replay input record after the replay FCB.
MAT_VARS    EQU     MAT_REC+128                 ; Beginning of replay scalar state in the old order page.
MAT_PTR     EQU     MAT_VARS+1                  ; Address of the next buffered ASO input byte.
MAT_HAVE    EQU     MAT_VARS+3                  ; Unread bytes in the physical ASO input record.
MAT_BYTE    EQU     MAT_VARS+4                  ; Decoded payload or temporary word low byte.
MAT_FILL    EQU     MAT_VARS+5                  ; Validated gap-fill byte from the ASO header.
MAT_WOFF    EQU     MAT_VARS+6                  ; Current replay window offset relative to origin.
MAT_WLEN    EQU     MAT_VARS+8                  ; Bytes in the selected replay output window.
MAT_WCNT    EQU     MAT_VARS+10                 ; Window bytes remaining during sequential record writes.
MAT_WPTR    EQU     MAT_VARS+12                 ; DMA address of the next output record.
MAT_LEFT    EQU     MAT_VARS+14                 ; Output bytes remaining across replay windows.
MAT_KIND    EQU     MAT_VARS+16                 ; Reserved record-kind byte in the replay layout.
MAT_RLEN    EQU     MAT_VARS+17                 ; Current IMAGE or PATCH payload byte count.
MAT_RCNT    EQU     MAT_VARS+18                 ; Payload bytes remaining to consume this pass.
MAT_ADDR    EQU     MAT_VARS+19                 ; Absolute IMAGE or PATCH start address.
MAT_ROFF    EQU     MAT_VARS+21                 ; Current payload address relative to image origin.
MAT_REND    EQU     MAT_VARS+23                 ; Checked operation endpoint used during validation.
MAT_IEND    EQU     MAT_VARS+25                 ; Greatest preceding absolute IMAGE endpoint low word.
MAT_ITOP    EQU     MAT_VARS+27                 ; Nonzero when IMAGE extent ends at $10000.
MAT_PREV    EQU     MAT_VARS+28                 ; Previous record kind for canonical IMAGE checks.
MAT_PLEN    EQU     MAT_VARS+29                 ; Previous IMAGE payload length for coalescing checks.
MAT_RTOP    EQU     MAT_VARS+30                 ; Nonzero when a PATCH endpoint is $10000.
MAT_VEND    EQU     MAT_VARS+31                 ; Exclusive end of replay scalar state.
CP_TPA      EQU     $0100                       ; CP/M transient program load address and output origin.
ASO_CAP     EQU     $FF00                       ; Maximum output span from $0100 to $10000.
MAT_WIN     EQU     SRC_PEND                    ; Replay output window after retained replay workspace.
CP_STACK    EQU     $E400                       ; Exclusive top of the private transient stack.
CP_SFLR     EQU     CP_STACK-$200               ; Lowest byte of the 512-byte stack.
CP_GUARD    EQU     $A5                         ; Pattern kept at the stack floor.
CP_DMA      EQU     26                          ; BDOS function 26 sets the transfer-buffer address.
CP_OPEN     EQU     15                          ; BDOS function 15 opens a file.
CP_CLOSE    EQU     16                          ; BDOS function 16 closes a file.
CP_ERASE    EQU     19                          ; BDOS function 19 deletes a file.
CP_READ     EQU     20                          ; BDOS function 20 reads a sequential record.
CP_RANDR    EQU     33                          ; BDOS function 33 reads a random record.
CP_WRITE    EQU     21                          ; BDOS function 21 writes a sequential record.
CP_RANDW    EQU     34                          ; BDOS function 34 writes a random record.
CP_MAKE     EQU     22                          ; BDOS function 22 creates a file.
CP_REN      EQU     23                          ; BDOS function 23 renames a file.
CP_TEXT     EQU     9                           ; BDOS function 9 prints a dollar-terminated string.
CMD_LEN     EQU     $0080                       ; CCP command-tail length byte.
CMD_TAIL    EQU     $0081                       ; First byte of the CCP command tail.

CP_CODEB: ; Beginning of resident CP/M adapter code.

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; CP/M standardises only the 8080 register set. Preserve the Z80 index
; registers promised by Atom's private tool-service client adapter.

CP_BDOS: ; Enter BDOS while preserving Z80 index registers.
    PUSH IX                                     ; Preserve IX across BDOS.
    PUSH IY                                     ; Protect the second index register as well.
    CALL CP_CALL5                               ; Enter the CP/M dispatcher with function in C.
    POP  IY                                     ; Restore IY before returning to the caller.
    POP  IX                                     ; Restore IX after the 8080-compatible service.
    RET                                         ; Return the BDOS result and flags unchanged.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check available transient memory before leaving the CCP stack. The accepted
; layout may overlay CCP, so every exit uses warm boot rather than RET.
; A at the exit records 0 for success, 1 for failure or 2 for bad arguments.

CP_ENTRY: ; Check memory and assemble one command.
    LD   HL,($0006)                             ; Read CP/M's advertised BDOS memory boundary.
    LD   DE,CP_STACK                            ; Require the fixed workspace and stack.
    OR   A                                      ; Clear borrow before the unsigned comparison.
    SBC  HL,DE                                  ; Is the private region entirely below BDOS?
    JR   NC,.FITS                               ; Equality accepts the exclusive stack top.
    LD   DE,MSG_MEM                             ; Explain rejection before opening any files.
    LD   C,9                                    ; Select string output on the original CCP stack.
    CALL CP_CALL5                               ; Use BDOS before installing the private stack.
    LD   A,1                                    ; Record the rejection for diagnostic probes.
    JP   CP_EXIT                                ; Warm boot without touching private arenas.
.FITS: ; Install the private stack after the memory check.
    LD   SP,CP_STACK                            ; Use private RAM for calls and pushes.
    LD   HL,CP_SFLR                             ; Mark the bottom of the private stack.
    LD   B,4                                    ; Four guard bytes detect an overflow.
.GUARD: ; Write the four stack-floor guard bytes.
    LD   (HL),CP_GUARD                          ; Store one guard byte.
    INC  HL                                     ; Advance to the next guard byte.
    DJNZ .GUARD                                 ; Fill all four.
    CALL CMD_READ                               ; Parse source and output names.
    JR   C,.CMDFAIL                             ; Report a usage or filename error before I/O.
    OR   A                                      ; Test whether parsing selected help-only mode.
    JR   NZ,.OK                                 ; Help returns success without assembly.
    CALL INC_SORT                               ; Resolve includes and measure all parts.
    JP   C,.FAIL                                ; Report source-graph failure.
    LD   HL,ASO_CAP                             ; All output modes cover $0100..$10000.
    LD   (CP_DESC+13),HL                        ; Install the selected target extent.
    LD   IX,CP_DESC                             ; Pass the measured source descriptor.
    CALL DR_ASM                                 ; Assemble all parts into the private operation spool.
    JR   C,.ASMFAIL                             ; Leave the old output intact on failure.
    LD   DE,MSG_CRLF                            ; Lead the success message with a newline.
    CALL CP_PRINT                               ; Separate the result from any command echo.
    LD   HL,PUB_NAME                            ; Point at the selected output name.
    CALL CP_NAME                                ; Print the basename and any nonblank extension.
    LD   DE,MSG_DONE                            ; Select the completion suffix.
    CALL CP_PRINT                               ; Report success after the sink has committed.
.OK: ; Finish successful assembly or help.
    XOR  A                                      ; Record status zero for success or help.
    JR   .LEAVE                                 ; Check the stack guard, then warm boot.
.CMDFAIL: ; Report invalid command arguments.
    CALL CP_PRINT                               ; DE holds the parser's diagnostic text.
    LD   A,2                                    ; Use status two for argument errors.
    JR   .LEAVE                                 ; Check the stack guard, then warm boot.

; Assembly failures print FILE:line:column: message. An output failure names
; the output file instead, and a failed INCBIN read names the binary file.

.ASMFAIL: ; Select source, output or binary-input diagnostics.
    PUSH AF                                     ; Save Atom's status while printing.
    LD   DE,MSG_CRLF                            ; Start the diagnostic on a fresh line.
    CALL CP_PRINT                               ; Separate it from the command echo.
    LD   A,(BIN_ERR)                            ; Did an INCBIN read fail inside the sink?
    OR   A                                      ; Zero means an ordinary assembler failure.
    JR   NZ,.BINFAIL                            ; Name the binary file that failed.
    POP  AF                                     ; Recover Atom's public status.
    CP   DR_SOUT                                ; Did BEGIN or COMMIT reject the output?
    JR   Z,.OUTFAIL                             ; There is no source line to report.
    CALL ERR_LOC                                ; Print the source file, line and column.
.TEXT: ; Print the core diagnostic text.
    CALL ERR_SEP                                ; Separate the location from the message.
    LD   A,(DR_MSG)                             ; Load the core's message number.
    CALL CP_MSG                                 ; Print the message and its arguments.
    LD   DE,MSG_CRLF                            ; Point at the terminating line break.
    CALL CP_PRINT                               ; Finish the diagnostic line.
    JR   .FAIL                                  ; Return failure.
.OUTFAIL: ; Name the failed output destination.
    LD   HL,PUB_NAME                            ; Identify the selected output file.
    CALL CP_NAME                                ; Print its CP/M filename.
    JR   .TEXT                                  ; Explain the output failure.
.BINFAIL: ; Name the failed binary input.
    POP  AF                                     ; Discard Atom's statement-facing status.
    CALL ERR_LOC                                ; Report the INCBIN statement's position.
    CALL ERR_SEP                                ; Separate the location from the message.
    LD   HL,BIN_FCB                             ; The dedicated FCB retains the binary filename.
    CALL CP_NAME                                ; Identify the failed binary input.
    LD   DE,MSG_LOAD                            ; Explain that its payload could not be read.
    CALL CP_PRINT                               ; Finish the binary-source diagnostic.
.FAIL: ; Select build-failure exit status.
    LD   A,1                                    ; Record status one for build failure.
.LEAVE: ; Check the stack guard before exiting.
    PUSH AF                                     ; Keep the exit status.
    CALL CP_CHECK                               ; Report a damaged stack guard.
    POP  AF                                     ; Restore the exit status.
CP_EXIT: ; Warm boot after transient workspace use.

; The private regions may have overwritten CCP and its original return stack.
; Warm boot reloads the command processor. never return through those bytes.

    JP   $0000                                  ; Reload CP/M's command processor through BIOS.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Map Atom's source ordinal to the retained CP/M filename, then reread only
; the bytes before the failing position. If the file cannot be read, keep the
; original byte offset instead of printing a guessed line or column.

ERR_LOC: ; Render source filename, line and byte column.
    LD   A,(ST_EPART)                           ; Select the failed dependency-order part.
    LD   HL,CP_DESC                             ; Read the count of valid part ordinals.
    CP   (HL)                                   ; Reject an impossible ordinal defensively.
    JR   NC,.BADPART                            ; Retain the original numeric diagnostic.
    LD   E,A                                    ; Index the dependency-order table.
    LD   D,INC_ORD/256                          ; The table occupies one fixed page.
    LD   A,(DE)                                 ; Recover the retained-name ordinal.
    CALL SRC_OPEN                               ; Reopen its source for position counting.
    JR   C,.NOOPEN                              ; Its name was printed. retain the offset.
    CALL ERR_CNT                                ; Convert the byte offset in this file.
    JR   C,.UNREAD                              ; Report the raw offset on a read failure.
    LD   HL,SRC_FCB                             ; Address the reopened file's 8.3 name.
    CALL CP_NAME                                ; Print the physical source filename.
    LD   A,':'                                  ; Separate filename from line number.
    CALL CP_PUTC                                ; Print the first colon.
    LD   HL,(ERR_LINE)                          ; Load the one-based source line.
    CALL CP_NUM                                 ; Print it without leading zeroes.
    LD   A,':'                                  ; Separate line from source column.
    CALL CP_PUTC                                ; Print the second colon.
    LD   HL,(ERR_COL)                           ; Load the one-based byte column.
    JP   CP_NUM                                 ; Finish the location and return.
.UNREAD: ; Use the filename when position counting failed.
    LD   HL,SRC_FCB                             ; The filename remains in the opened FCB.
    CALL CP_NAME                                ; Identify the unreadable source part.
.NOOPEN: ; Print the raw-offset fallback prefix.
    LD   DE,MSG_BYTE                            ; Mark the fallback as a byte offset.
    CALL CP_PRINT                               ; Never confuse it with line and column.
    JR   .OFFSET                                ; Print the unchanged hexadecimal offset.
.BADPART: ; Print an invalid part ordinal numerically.
    LD   A,(ST_EPART)                           ; Recover the impossible source ordinal.
    CALL CP_HEX                                 ; Preserve its two-digit hexadecimal form.
    LD   A,' '                                  ; Separate ordinal from byte offset.
    CALL CP_PUTC                                ; Print the separator.
.OFFSET: ; Print the unchanged hexadecimal source offset.
    LD   HL,(ST_EOFF)                           ; Recover Atom's original byte offset.
    PUSH HL                                     ; Save it across printing its high byte.
    LD   A,H                                    ; Select the high byte first.
    CALL CP_HEX                                 ; Emit two hexadecimal digits.
    POP  HL                                     ; Restore the offset's low byte.
    LD   A,L                                    ; Select its remaining byte.
    JP   CP_HEX                                 ; Finish the four-digit offset and return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Count physical line breaks and byte columns before the reported offset.
; CRLF is one break. lone CR and lone LF are each one break. Counters start
; at one, and zero represents the sole possible overflow value, 65,536.

ERR_CNT: ; Count physical lines up to the diagnostic offset.
    LD   HL,1                                   ; Both positions are one-based.
    LD   (ERR_LINE),HL                          ; Begin on the first source line.
    LD   (ERR_COL),HL                           ; Begin at its first byte column.
    LD   HL,0                                   ; Scan from the first source byte.
    LD   (ERR_POS),HL                           ; Store the current zero-based offset.
    XOR  A                                      ; No preceding byte was CR.
    LD   (ERR_CR),A                             ; Clear the CRLF state.
.LOOP: ; Consume bytes before the failing position.
    LD   HL,(ERR_POS)                           ; Read the next byte offset.
    LD   DE,(ST_EOFF)                           ; Read the failing offset as an exclusive end.
    OR   A                                      ; Clear carry before comparing positions.
    SBC  HL,DE                                  ; Stop before consuming the failing byte.
    JR   Z,.DONE                                ; The counters now describe that byte.
    LD   HL,(ERR_POS)                           ; Address the current source byte.
    CALL SRC_RAW                                ; Read it through the existing CP/M cache.
    RET  C                                      ; Changed or unreadable input needs a fallback.
    LD   B,A                                    ; Preserve the byte across cursor update.
    LD   HL,(ERR_POS)                           ; Advance by exactly one source byte.
    INC  HL                                     ; Move to the following zero-based offset.
    LD   (ERR_POS),HL                           ; Save the advanced cursor.
    LD   A,B                                    ; Classify the byte just consumed.
    CP   13                                     ; A carriage return always starts a new line.
    JR   Z,.CR                                  ; Retain CR state for an optional following LF.
    CP   10                                     ; A lone line feed also starts a new line.
    JR   Z,.LF                                  ; Avoid double-counting CRLF.
    XOR  A                                      ; Ordinary text ends CRLF lookbehind.
    LD   (ERR_CR),A                             ; The preceding byte is not CR.
    LD   HL,(ERR_COL)                           ; Move one byte to the right.
    INC  HL                                     ; Advance the one-based column.
    LD   (ERR_COL),HL                           ; Keep its full 16-bit value.
    JR   .LOOP                                  ; Continue toward the error offset.
.CR: ; Count CR and retain CRLF state.
    LD   A,1                                    ; Record a preceding CR.
    LD   (ERR_CR),A                             ; The next LF belongs to this break.
    CALL .NEWLINE                               ; Start the next line at column one.
    JR   .LOOP                                  ; Continue after the CR byte.
.LF: ; Count LF only when a preceding CR did not.
    LD   A,(ERR_CR)                             ; Check whether CR already advanced the line.
    OR   A                                      ; Z means this LF is a lone break.
    CALL Z,.NEWLINE                             ; Count a lone LF exactly once.
    XOR  A                                      ; The lookbehind ends at this LF.
    LD   (ERR_CR),A                             ; Clear it before another source byte.
    JR   .LOOP                                  ; Continue after the LF byte.
.DONE: ; Return the computed line and column.
    OR   A                                      ; Return success with carry clear.
    RET                                         ; Leave the computed line and column in RAM.

;@ROUTINE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Advance to a physical source line and reset its byte column.

.NEWLINE: ; Start a new source line at column one.
    LD   HL,(ERR_LINE)                          ; Load the current line number.
    INC  HL                                     ; Move to the next line.
    LD   (ERR_LINE),HL                          ; Keep the complete 16-bit result.
    LD   HL,1                                   ; The first byte has column one.
    LD   (ERR_COL),HL                           ; Reset the column for that line.
    RET                                         ; Return to the source-byte classifier.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the ": " that separates a location from its message.

ERR_SEP: ; Print the separator after a source location.
    LD   A,':'                                  ; End the location field.
    CALL CP_PUTC                                ; Print the colon.
    LD   A,' '                                  ; Leave one space before the message.
    JP   CP_PUTC                                ; Print it and return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the line of the related location in DR_RPART/DR_ROFF, such as the
; label a failed forward jump refers to. Print ? when there is none.

ERR_REL: ; Print a related source line while preserving the primary offset.
    LD   A,(DR_RPART)                           ; Select the related source part.
    LD   HL,CP_DESC                             ; Read the count of valid part ordinals.
    CP   (HL)                                   ; $FF and impossible ordinals both fail.
    JR   NC,.UNKNOWN                            ; No related location was recorded.
    LD   HL,(ST_EOFF)                           ; ERR_CNT counts up to ST_EOFF.
    PUSH HL                                     ; Keep the primary offset.
    LD   HL,(DR_ROFF)                           ; Count up to the related offset instead.
    LD   (ST_EOFF),HL                           ; Install it for ERR_CNT.
    LD   E,A                                    ; Index the dependency-order table.
    LD   D,INC_ORD/256                          ; The table occupies one fixed page.
    LD   A,(DE)                                 ; Recover the retained-name ordinal.
    CALL SRC_OPEN                               ; Reopen that source file.
    JR   C,.RESTORE                             ; Fall back to ? if it cannot be read.
    CALL ERR_CNT                                ; Find the related line.
    JR   C,.RESTORE                             ; Fall back to ? on a read failure.
    LD   HL,(ERR_LINE)                          ; Load the related line number.
    CALL CP_NUM                                 ; Print it.
    POP  HL                                     ; Recover the primary offset.
    LD   (ST_EOFF),HL                           ; Restore it.
    RET                                         ; The related line is printed.
.RESTORE: ; Restore the primary diagnostic offset after failed counting.
    POP  HL                                     ; Recover the primary offset.
    LD   (ST_EOFF),HL                           ; Restore it.
.UNKNOWN: ; Print the unknown-related-line marker.
    LD   A,'?'                                  ; Show that the line is unknown.
    JP   CP_PUTC                                ; Print it and return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print message number A from cpmsg.asm. Bytes 1, 2 and 3 in the sentence
; print the symbol in DR_SYM, the value in DR_VAL and the related line.

CP_MSG: ; Look up and render one core diagnostic.
    CP   MSG_NUM                                ; Is it a known message number?
    JR   C,.KNOWN                               ; Yes: look it up.
    XOR  A                                      ; No: use the internal-error message.
.KNOWN: ; Read the sentence index for a valid message number.
    LD   E,A                                    ; Index MSG_IDX by message number.
    LD   D,0                                    ; Widen the index.
    LD   HL,MSG_IDX                             ; Address the sentence index.
    ADD  HL,DE                                  ; Address this message's entry.
    LD   B,(HL)                                 ; Load its sentence number.
    LD   HL,MSG_TEXT                            ; Start at the first sentence.
    INC  B                                      ; Count sentences from one.
.SKIP: ; Skip preceding zero-terminated sentences.
    DEC  B                                      ; Have we reached the sentence?
    JR   Z,.PRINT                               ; Yes: print it.
.SKIPCH: ; Consume bytes of a preceding sentence.
    LD   A,(HL)                                 ; Read a byte of an earlier sentence.
    INC  HL                                     ; Step past it.
    OR   A                                      ; Zero ends that sentence.
    JR   NZ,.SKIPCH                             ; Keep skipping its text.
    JR   .SKIP                                  ; Count the sentence just skipped.
.PRINT: ; Print the selected sentence and substitutions.
    LD   A,(HL)                                 ; Read the next byte of the sentence.
    INC  HL                                     ; Step past it.
    OR   A                                      ; Zero ends the sentence.
    RET  Z                                      ; The message is complete.
    PUSH HL                                     ; Keep the sentence position.
    CP   4                                      ; Bytes 1 to 3 stand for arguments.
    JR   NC,.CHAR                               ; Anything else is printed as text.
    CALL .ARG                                   ; Print the argument.
    JR   .NEXT                                  ; Continue with the sentence.
.CHAR: ; Print an ordinary diagnostic character.
    CALL CP_PUTC                                ; Print one character of text.
.NEXT: ; Resume the retained sentence position.
    POP  HL                                     ; Recover the sentence position.
    JR   .PRINT                                 ; Print the next byte.
.ARG: ; Dispatch symbol, signed-value or related-line substitution.
    DEC  A                                      ; 1 selects the symbol name.
    JP   Z,CP_SYM                               ; Print it.
    DEC  A                                      ; 2 selects the signed value.
    JP   Z,CP_SNUM                              ; Print it.
    JP   ERR_REL                                ; 3 selects the related line.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the signed sixteen-bit value in DR_VAL in decimal.

CP_SNUM: ; Print the signed diagnostic value in decimal.
    LD   HL,(DR_VAL)                            ; Load the value.
    BIT  7,H                                    ; Is it negative?
    JP   Z,CP_NUM                               ; No: print it as it is.
    LD   A,'-'                                  ; Print the minus sign first.
    CALL CP_PUTC                                ; CP_PUTC preserves HL.
    LD   A,L                                    ; Negate HL: complement the low byte.
    CPL                                         ; Invert every low bit.
    LD   L,A                                    ; Store the inverted low byte.
    LD   A,H                                    ; Complement the high byte too.
    CPL                                         ; Invert every high bit.
    LD   H,A                                    ; Store the inverted high byte.
    INC  HL                                     ; Add one to finish the two's complement.
    JP   CP_NUM                                 ; Print the magnitude.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the name of the symbol record in DR_SYM. Names are packed three
; RADIX-40 characters to a word: 1-26 are A-Z, 27-36 are 0-9, 37 is _ and
; 0 is padding. Private names print with their leading period.

CP_SYM: ; Unpack and print the diagnostic symbol name.
    LD   IX,(DR_SYM)                            ; Address the symbol record.
    LD   A,(DR_SYM)                             ; Is there a symbol?
    LD   HL,DR_SYM+1                            ; Address the pointer's high byte.
    OR   (HL)                                   ; Zero means no symbol was recorded.
    JR   NZ,.NAMED                              ; Print the recorded name.
    LD   A,'?'                                  ; Show that the name is unknown.
    JP   CP_PUTC                                ; Print it and return.
.NAMED: ; Print a validated symbol record.
    BIT  7,(IX+5)                               ; Is this a private name?
    JR   Z,.GLOBAL                              ; No: print it as it is.
    LD   A,'.'                                  ; Private names begin with a period.
    CALL CP_PUTC                                ; Print it.
.GLOBAL: ; Decode a global or private packed name.
    LD   L,(IX+0)                               ; Load the first packed word.
    LD   H,(IX+1)                               ; It holds characters one to three.
    CALL .WORD3                                 ; Print them.
    LD   L,(IX+2)                               ; Load the second packed word.
    LD   H,(IX+3)                               ; It holds characters four to six.
    CALL .WORD3                                 ; Print them.
    LD   L,(IX+4)                               ; Load the low byte of the final pair.
    LD   A,(IX+5)                               ; Its high bits share a byte with the flags.
    AND  SY_NMASK                               ; Keep only the name bits.
    LD   H,A                                    ; HL holds characters seven and eight.
    JR   .WORD2                                 ; Print them and return.
.WORD3: ; Decode three RADIX-40 characters.
    LD   DE,1600                                ; The first character is the 1600s digit.
    CALL .DIGIT                                 ; Divide it out and print it.
.WORD2: ; Decode two RADIX-40 characters.
    LD   DE,40                                  ; The next character is the 40s digit.
    CALL .DIGIT                                 ; Divide it out and print it.
    LD   A,L                                    ; The remainder is the last character.
    JR   .CODE                                  ; Print it and return.
.DIGIT: ; Divide out the next packed character.
    LD   C,0                                    ; C counts how many times DE fits.
.SUB: ; Count complete RADIX-40 place values.
    OR   A                                      ; Clear carry for the subtraction.
    SBC  HL,DE                                  ; Take DE away once more.
    JR   C,.BACK                                ; Too far: undo the last step.
    INC  C                                      ; One more whole DE.
    JR   .SUB                                   ; Try again.
.BACK: ; Undo the first subtraction that borrowed.
    ADD  HL,DE                                  ; HL is now the remainder.
    LD   A,C                                    ; A is the character code.
.CODE: ; Convert a nonzero packed name code to ASCII.
    OR   A                                      ; Code zero is padding.
    RET  Z                                      ; Print nothing for it.
    CP   27                                     ; Codes 1 to 26 are letters.
    JR   NC,.NOTALPHA                           ; Higher codes are digits or underscore.
    ADD  A,'A'-1                                ; Convert 1 to A.
    JP   CP_PUTC                                ; Print it and return.
.NOTALPHA: ; Convert a packed digit or underscore code.
    CP   37                                     ; Codes 27 to 36 are digits.
    JR   NC,.UNDER                              ; Code 37 is the underscore.
    ADD  A,'0'-27                               ; Convert 27 to 0.
    JP   CP_PUTC                                ; Print it and return.
.UNDER: ; Print packed underscore code 37.
    LD   A,'_'                                  ; Code 37 prints as an underscore.
    JP   CP_PUTC                                ; Print it and return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Report a stack overflow when the guard bytes at CP_SFLR have changed.

CP_CHECK: ; Check the four private-stack guard bytes.
    LD   HL,CP_SFLR                             ; Address the first guard byte.
    LD   B,4                                    ; Check all four.
.LOOP: ; Compare each byte with the guard pattern.
    LD   A,(HL)                                 ; Read one guard byte.
    CP   CP_GUARD                               ; Is it still the guard pattern?
    JR   NZ,.BAD                                ; No: the stack went too deep.
    INC  HL                                     ; Advance to the next guard byte.
    DJNZ .LOOP                                  ; Check every guard byte.
    RET                                         ; The stack stayed within its reserve.
.BAD: ; Report a changed stack guard.
    LD   DE,MSG_CRLF                            ; Start the warning on a fresh line.
    CALL CP_PRINT                               ; Print the line break.
    LD   A,MSG_STACK                            ; Select the stack-overflow message.
    CALL CP_MSG                                 ; Print it.
    LD   DE,MSG_CRLF                            ; End the warning line.
    JP   CP_PRINT                               ; Print the line break and return.
