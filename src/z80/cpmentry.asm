; CP/M entry: check memory, run one command and leave through warm boot.

cpBeg: ; Beginning of resident CP/M adapter code.

;@ROUTINE IN C,DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; CP/M standardises only the 8080 register set. Preserve the Z80 index
; registers promised by Atom's private tool-service client adapter.

cpBdos: ; Enter BDOS while preserving Z80 index registers.
    PUSH IX                                     ; Preserve IX across BDOS.
    PUSH IY                                     ; Protect the second index register as well.
    CALL cpCall5                                ; Enter the CP/M dispatcher with function in C.
    POP  IY                                     ; Restore IY before returning to the caller.
    POP  IX                                     ; Restore IX after the 8080-compatible service.
    RET                                         ; Return the BDOS result and flags unchanged.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Size the workspace from the BDOS entry in the word at $0006, the first byte
; above the TPA. The stack sits just below it. The symbol and pending arenas
; share the memory between the fixed workspace and the stack floor, and a
; build that outgrows them stops with an out-of-memory error. The layout may
; overlay CCP, so every exit uses warm boot rather than RET.
; A at the exit records 0 for success, 1 for failure or 2 for bad arguments.

cpEntry: ; Size memory and assemble one command.
    LD   HL,($0006)                             ; Read CP/M's BDOS entry, the top of the TPA.
    LD   DE,cpStkLen                            ; Leave room for the private stack below it.
    OR   A                                      ; Clear borrow before the unsigned subtraction.
    SBC  HL,DE                                  ; Form the stack floor.
    JR   C,.short                               ; Too little memory for even the stack.
    LD   B,H                                    ; Keep the floor in BC.
    LD   C,L                                    ; Complete the copy.
    LD   DE,feRamHi                             ; The arenas begin after the fixed workspace.
    SBC  HL,DE                                  ; Measure the arenas; borrow is clear.
    JR   NC,.fits                               ; Equality leaves empty arenas.
.short: ; Refuse a TPA that cannot hold the fixed workspace and stack.
    LD   DE,msgMem                              ; Explain rejection before opening any files.
    LD   C,9                                    ; Select string output on the original CCP stack.
    CALL cpCall5                                ; Use BDOS before installing the private stack.
    LD   A,1                                    ; Record the rejection for diagnostic probes.
    JP   cpExit                                 ; Warm boot without touching private arenas.
.fits: ; Install the stack and divide the arenas.
    LD   SP,($0006)                             ; Use private RAM for calls and pushes.
    LD   (cpDesc+drSymBeg),DE                   ; Symbols start at the fixed workspace's end.
    LD   (cpDesc+drRefEnd),BC                   ; Pending references end at the stack floor.
    SRL  H                                      ; Halve the arena bytes.
    RR   L                                      ; Complete the halving.
    SRL  H                                      ; Halve them again.
    RR   L                                      ; One quarter goes to pending references.
    EX   DE,HL                                  ; Hold the pending bytes in DE.
    LD   H,B                                    ; Start from the stack floor.
    LD   L,C                                    ; Complete the floor.
    OR   A                                      ; Clear borrow.
    SBC  HL,DE                                  ; Find the split.
    LD   (cpDesc+drRefBeg),HL                   ; Pending references start there.
    LD   (cpDesc+drSymEnd),HL                   ; And the symbols end there.
    LD   H,B                                    ; Mark the bottom of the private stack.
    LD   L,C                                    ; Complete its address.
    LD   B,4                                    ; Four guard bytes detect an overflow.
.guard: ; Write the four stack-floor guard bytes.
    LD   (HL),cpGuard                           ; Store one guard byte.
    INC  HL                                     ; Advance to the next guard byte.
    DJNZ .guard                                 ; Fill all four.
    CALL cmdRead                                ; Parse source and output names.
    JR   C,.cmdFail                             ; Report a usage or filename error before I/O.
    OR   A                                      ; Test whether parsing selected help-only mode.
    JR   NZ,.ok                                 ; Help returns success without assembly.
    CALL cpmStart                               ; Retain the root's name.
    XOR  A                                      ; Check the root can be opened.
    CALL srcOpen                                ; Before any output is begun.
    JR   C,.noRoot                              ; Name it and stop.
    LD   A,1                                    ; The root is open and unread.
    LD   (srcFresh),A                           ; sfStart uses it as it is.
    CALL incStart                               ; Stream the root and its includes.
    LD   HL,asoCap                              ; All output modes cover $0100..$10000.
    LD   (cpDesc+drOutCap),HL                   ; Install the selected target extent.
    LD   IX,cpDesc                              ; Pass the build descriptor.
    CALL drAsm                                  ; Assemble all parts into the private operation spool.
    JR   C,.asmFail                             ; Leave the old output intact on failure.
    LD   DE,msgCrlf                             ; Lead the success message with a newline.
    CALL cpPrint                                ; Separate the result from any command echo.
    LD   HL,pubName                             ; Point at the selected output name.
    CALL cpPutFcb                               ; Print the basename and any nonblank extension.
    LD   DE,msgDone                             ; Select the completion suffix.
    CALL cpPrint                                ; Report success after the sink has committed.
.ok: ; Finish successful assembly or help.
    XOR  A                                      ; Record status zero for success or help.
    JR   .leave                                 ; Check the stack guard, then warm boot.
.cmdFail: ; Report invalid command arguments.
    CALL cpPrint                                ; DE holds the parser's diagnostic text.
    LD   A,2                                    ; Use status two for argument errors.
    JR   .leave                                 ; Check the stack guard, then warm boot.

; Assembly failures print FILE:line:column: message. An output failure names
; the output file instead.

.asmFail: ; Select source or output diagnostics.
    PUSH AF                                     ; Save Atom's status while printing.
    LD   DE,msgCrlf                             ; Start the diagnostic on a fresh line.
    CALL cpPrint                                ; Separate it from the command echo.
    POP  AF                                     ; Recover Atom's public status.
    CP   drBadOut                               ; Did BEGIN or COMMIT reject the output?
    JR   Z,.outFail                             ; There is no source line to report.
    CALL errWhere                               ; Print the source file, line and column.
.text: ; Print the core diagnostic text.
    CALL errSep                                 ; Separate the location from the message.
    LD   A,(drMsg)                              ; Load the core's message number.
    CP   drSymMsg+sySymCap                      ; Did the symbol arena fill?
    JR   Z,.oom                                 ; Memory ran out.
    CP   drSymMsg+syRefCap                      ; Did the pending arena fill?
    JR   NZ,.say                                ; No: print the message alone.
.oom: ; Say that the arenas ran out of memory.
    LD   DE,msgOom                              ; Name the cause before the message.
    CALL cpPrint                                ; Print it.
    LD   A,(drMsg)                              ; Reload the message number.
.say: ; Print the message and its arguments.
    CALL cpDiag                                 ; Print the message and its arguments.
    LD   DE,msgCrlf                             ; Point at the terminating line break.
    CALL cpPrint                                ; Finish the diagnostic line.
    JR   .fail                                  ; Return failure.
.outFail: ; Name the failed output destination.
    LD   HL,pubName                             ; Identify the selected output file.
    CALL cpPutFcb                               ; Print its CP/M filename.
    JR   .text                                  ; Explain the output failure.
.noRoot: ; Name a root source that cannot be opened.
    LD   DE,msgCrlf                             ; Start the diagnostic on a fresh line.
    CALL cpPrint                                ; Separate it from the command echo.
    LD   HL,srcFcb                              ; The root's name.
    CALL cpPutFcb                               ; Print it.
    LD   DE,msgRead                             ; Explain that it cannot be read.
    CALL cpPrint                                ; Finish the line.
.fail: ; Select build-failure exit status.
    LD   A,1                                    ; Record status one for build failure.
.leave: ; Check the stack guard before exiting.
    PUSH AF                                     ; Keep the exit status.
    CALL cpCheck                                ; Report a damaged stack guard.
    POP  AF                                     ; Restore the exit status.
cpExit: ; Warm boot after transient workspace use.

; The private regions may have overwritten CCP and its original return stack.
; Warm boot reloads the command processor. never return through those bytes.

    JP   $0000                                  ; Reload CP/M's command processor through BIOS.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Report a stack overflow when the guard bytes at the stack floor have changed.

cpCheck: ; Check the four private-stack guard bytes.
    LD   HL,(cpDesc+drRefEnd)                   ; Address the first guard byte at the floor.
    LD   B,4                                    ; Check all four.
.loop: ; Compare each byte with the guard pattern.
    LD   A,(HL)                                 ; Read one guard byte.
    CP   cpGuard                                ; Is it still the guard pattern?
    JR   NZ,.bad                                ; No: the stack went too deep.
    INC  HL                                     ; Advance to the next guard byte.
    DJNZ .loop                                  ; Check every guard byte.
    RET                                         ; The stack stayed within its reserve.
.bad: ; Report a changed stack guard.
    LD   DE,msgCrlf                             ; Start the warning on a fresh line.
    CALL cpPrint                                ; Print the line break.
    LD   A,msgOver                              ; Select the stack-overflow message.
    CALL cpDiag                                 ; Print it.
    LD   DE,msgCrlf                             ; End the warning line.
    JP   cpPrint                                ; Print the line break and return.
