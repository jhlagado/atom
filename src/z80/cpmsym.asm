; Symbol file: write every global symbol as one line, four hex digits, a
; space and the name, for debuggers such as SID and ZSID. The table only
; survives until replay, so symWrite runs when the spool is sealed and leaves
; the lines in NAME.$$S. symShip renames it to NAME.SYM once the output is
; published, and symDrop removes it when a build fails.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Copy the requested symbol filename into the working FCB.

symCopy: ; Copy the symbol filename into the working FCB.
    LD   HL,symName                     ; Read the requested drive and 8.3 name.
    LD   DE,cpFcb                       ; Select the reusable working FCB.
    LD   BC,12                          ; Copy the drive, name and type.
    LDIR                                ; Copy the name.
    JP   pubClear                       ; Clear the FCB's control fields.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the symbol file's work name, NAME.$$S.

symTemp: ; Derive the reserved $$S work name.
    CALL symCopy                        ; Start from the requested name.
    LD   HL,$2424                       ; Form two '$' bytes.
    LD   (cpFcb+9),HL                   ; Mark the first two type characters.
    LD   A,'S'                          ; Select 'S' for the last one.
    LD   (cpFcb+11),A                   ; Complete the work type '$$S'.
    RET                                 ; Return the work name in cpFcb.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Write the global symbols to NAME.$$S if a symbol file was asked for.

symWrite: ; Write the symbol table to the work file.
    LD   A,(symOn)                      ; Was a symbol file asked for?
    OR   A                              ; Zero means no.
    RET  Z                              ; Return carry clear.
    CALL symTemp                        ; Name the work file.
    LD   DE,cpFcb                       ; Pass it to CP/M.
    LD   C,cpMake                       ; Select make-file function 22.
    CALL cpBdos                         ; Create the empty work file.
    INC  A                              ; $FF means the directory is full.
    JR   Z,.fail                        ; Report the failure.
    LD   A,2                            ; Two means the work file exists.
    LD   (symOn),A                      ; symDrop must now remove it.
    CALL hexReset                       ; Start buffered text output.
    LD   HL,symPut                      ; Send decoded names to the file.
    LD   (cpNameTo),HL                  ; Redirect the name decoder.
    LD   IX,(syBase)                    ; Start at the first global record.
.next: ; Write one symbol line.
    PUSH IX                             ; Copy the record address.
    POP  HL                             ; HL is the current record.
    LD   DE,(syFreeLo)                  ; Globals end here.
    OR   A                              ; Clear carry for the comparison.
    SBC  HL,DE                          ; Past the last global?
    JR   NC,.end                        ; Yes: finish the file.
    LD   A,(IX+syValHi)                 ; Write the value's high byte.
    CALL hexByte                        ; As two hex digits.
    LD   A,(IX+syValLo)                 ; Write the value's low byte.
    CALL hexByte                        ; As two hex digits.
    LD   A,' '                          ; Separate the value from the name.
    CALL hexPut                         ; Queue the space.
    CALL cpPutNm                        ; Write the decoded name.
    LD   A,13                           ; End the line.
    CALL hexPut                         ; Queue CR.
    LD   A,10                           ; Finish the line.
    CALL hexPut                         ; Queue LF.
    LD   DE,syRecLen                    ; Step to the next record.
    ADD  IX,DE                          ; Advance one record.
    JR   .next                          ; Write it.
.end: ; Pad, write and close the file.
    LD   HL,cpPutCh                     ; Send names to the console again.
    LD   (cpNameTo),HL                  ; Restore the name decoder.
    CALL hexDone                        ; Pad and write the last record.
    JR   C,.fail                        ; A record write failed.
    LD   DE,cpFcb                       ; Pass the work file to CP/M.
    LD   C,cpClose                      ; Select close-file function 16.
    CALL cpBdos                         ; Close it.
    INC  A                              ; $FF means the close failed.
    RET  NZ                             ; Return carry clear on success.
.fail: ; Report a failed symbol-file write.
    LD   HL,cpPutCh                     ; Send names to the console again.
    LD   (cpNameTo),HL                  ; Restore the name decoder.
    LD   A,1                            ; Return a nonzero sink status.
    SCF                                 ; hsAbort removes the work file.
    RET                                 ; Return the failure.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Queue one name character in the symbol file, keeping the decoder's
; registers.

symPut: ; Write one character to the symbol file.
    PUSH HL                             ; The decoder keeps its remainder in HL.
    PUSH DE                             ; Keep DE.
    PUSH BC                             ; Keep BC.
    CALL hexPut                         ; Queue the character.
    POP  BC                             ; Restore BC.
    POP  DE                             ; Restore DE.
    POP  HL                             ; Restore HL.
    RET                                 ; Return to the decoder.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; After the output is published, replace NAME.SYM with the work file.

symShip: ; Publish the symbol file.
    LD   A,(symOn)                      ; Was a work file written?
    CP   2                              ; Two means NAME.$$S exists.
    JR   NZ,.none                       ; Nothing to publish.
    CALL symCopy                        ; Name the old symbol file.
    LD   DE,cpFcb                       ; Pass it to CP/M.
    LD   C,cpErase                      ; Select delete-file function 19.
    CALL cpBdos                         ; Remove any old symbol file.
    CALL symTemp                        ; Name the work file.
    LD   HL,cpFcb                       ; Rename it from NAME.$$S.
    LD   DE,symName                     ; To the requested name.
    CALL pubPair                        ; Build the rename FCB.
    LD   DE,pubFcb                      ; Pass the rename FCB to CP/M.
    LD   C,cpRename                     ; Select rename-file function 23.
    CALL cpBdos                         ; Publish the symbol file.
    INC  A                              ; $FF means the rename failed.
    JP   Z,pubFail                      ; hsAbort removes the work file.
.none: ; Nothing remains to publish.
    XOR  A                              ; Clear the request.
    LD   (symOn),A                      ; The symbol file is complete.
    RET                                 ; Return carry clear.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Remove the symbol file's work file after a failed build.

symDrop: ; Delete NAME.$$S if this build wrote it.
    LD   A,(symOn)                      ; Was a work file written?
    CP   2                              ; Two means NAME.$$S exists.
    RET  NZ                             ; Nothing to remove.
    CALL symTemp                        ; Name the work file.
    LD   DE,cpFcb                       ; Pass it to CP/M.
    LD   C,cpErase                      ; Select delete-file function 19.
    CALL cpBdos                         ; Delete it.
    XOR  A                              ; The work file is gone.
    LD   (symOn),A                      ; Clear the request.
    RET                                 ; Return.
