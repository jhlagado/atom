; These Atom sink entries replace the fail-closed host stubs. IMAGE and PATCH
; are appended to a private ASO spool. output publication waits until COMMIT.

pubBeg: ; Beginning of spool and publication code.
hsBeg: ; Beginning of replaceable CP/M output hooks.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Begin a tentative ASO spool. Final output is published after COMMIT.

hsBegin: ; Create a tentative ASO spool for this assembly.
    JP   asoInit                                ; Start the ordered-operation writer.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize one IMAGE byte in the private CP/M operation spool.

hsByte: ; Serialise an IMAGE byte.
    JP   asoEmit                                ; Append it to the ASO stream.
hsPatchB: ; Serialise one byte PATCH operation.
    JP   asoFixB                                ; Append the replacement byte to the spool.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Store one little-endian word at its translated logical address.

hsPatchW: ; Serialise one little-endian word PATCH operation.
    JP   asoFixW                                ; Append both replacement bytes to the spool.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; COMMIT seals the operation stream and publishes its selected representation.

hsCommit: ; Close any INCBIN file and seal the operation stream.
    PUSH AF                                     ; Keep Atom's high-water flags and endpoint bit.
    PUSH BC                                     ; Preserve BC, the high-water endpoint low word.
    PUSH DE                                     ; Preserve DE, the remaining target capacity.
    PUSH HL                                     ; Preserve HL, the final target cursor.
    CALL binShut                                ; Close the last INCBIN file.
    POP  HL                                     ; Restore HL, the final target cursor.
    POP  DE                                     ; Restore DE, the remaining target capacity.
    POP  BC                                     ; Restore BC, the high-water endpoint low word.
    POP  AF                                     ; Restore the flags and Atom's endpoint marker.
    JP   asoSeal                                ; Seal, materialise if needed, and publish.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Publish the closed temporary file: move an existing output to $$B, rename
; the temporary file to the final name, then delete $$B. hsAbort restores
; the old output if the second rename fails.

pubSwap: ; Publish a completed temporary output using a backup.
    CALL pubBak                                 ; Name the backup file for the selected output.
    LD   DE,cpFcb                               ; Pass its FCB to the delete service.
    LD   C,cpErase                              ; Select CP/M delete-file function 19.
    CALL cpBdos                                 ; Remove any prior backup file.
    LD   HL,pubName                             ; Supply the current final name as rename source.
    LD   DE,cpFcb                               ; Supply the backup name as rename destination.
    CALL pubPair                                ; Build a CP/M rename FCB for the old output.
    LD   DE,pubFcb                              ; Pass the completed rename FCB to CP/M.
    LD   C,cpRename                             ; Select CP/M rename-file function 23.
    CALL cpBdos                                 ; Move old output to backup.
    INC  A                                      ; Set zero when CP/M returned $FF for the rename.
    JR   Z,.noBackup                            ; Skip backup on rename failure.
    LD   A,1                                    ; Mark old output as backed up.
    LD   (pubKept),A                            ; Let abort restore it if the next rename fails.
.noBackup: ; Publish after moving or finding no old output.
    CALL pubTemp                                ; Select the completed temporary output name.
    LD   HL,cpFcb                               ; Supply the temporary name as rename source.
    LD   DE,pubName                             ; Supply the requested final name as destination.
    CALL pubPair                                ; Build the CP/M rename FCB for publication.
    LD   DE,pubFcb                              ; Pass the completed rename FCB to CP/M.
    LD   C,cpRename                             ; Select CP/M rename-file function 23.
    CALL cpBdos                                 ; Publish temp under final name.
    INC  A                                      ; Test for BDOS rename failure.
    JP   Z,pubFail                              ; Preserve the backup until abort restores it.
    CALL pubBak                                 ; Rebuild the backup name for cleanup.
    LD   DE,cpFcb                               ; Pass the backup FCB to the delete service.
    LD   C,cpErase                              ; Select CP/M delete-file function 19.
    CALL cpBdos                                 ; Remove old output after commit.
    XOR  A                                      ; Clear transaction state.
    LD   (pubKept),A                            ; Clear the flag after attempting backup deletion.
    JP   symShip                                ; Publish the symbol file too, if any.
pubFail: ; Return publication failure for rollback.
    LD   A,1                                    ; Return failed-commit status.
    SCF                                         ; Mark the sink operation as failed.
    RET                                         ; Driver will call hsAbort.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close temporary output if open, then delete it. If commit moved the old
; final file aside, restore the backup. Cleanup tolerates early failure.

hsAbort: ; Close and remove tentative files on assembly failure.
    CALL binShut                                ; Close any INCBIN file.
.aso: ; Close the operation writer if it owns an FCB.
    LD   A,(asoOpen)                            ; Check whether an ASO temporary file is open.
    OR   A                                      ; A clear flag needs no ASO close operation.
    JR   Z,.reader                              ; Continue with the ordinary temporary file.
    LD   DE,asoFcb                              ; Pass the ASO spool FCB to the close service.
    LD   C,cpClose                              ; Select CP/M close-file function 16.
    CALL cpBdos                                 ; Close the spool before deleting its name.
    XOR  A                                      ; Mark the spool FCB closed for repeated cleanup.
    LD   (asoOpen),A                            ; Mark the spool closed for this abort.
.reader: ; Close an active replay reader.
    LD   A,(matOpen)                            ; Check whether the spool reader is open.
    OR   A                                      ; Zero means no materialiser reader needs closing.
    JR   Z,.temp                                ; Continue cleanup when already closed.
    LD   DE,matFcb                              ; Pass the relocated reader FCB to CP/M.
    LD   C,cpClose                              ; Select CP/M close-file function 16.
    CALL cpBdos                                 ; Release the active spool reader before reuse.
    XOR  A                                      ; Clear reader ownership even if CLOSE failed.
    LD   (matOpen),A                            ; Clear the abort close flag.
.temp: ; Close an active final-output temporary file.
    LD   A,(pubOpen)                            ; Check whether the temporary file is open.
    OR   A                                      ; Set zero when no close operation is required.
    JR   Z,.delete                              ; Continue directly to removing the temp name.
    LD   DE,cpFcb                               ; Pass the temporary file's FCB to CP/M.
    LD   C,cpClose                              ; Select CP/M close-file function 16.
    CALL cpBdos                                 ; Close the temporary file before deleting it.
.delete: ; Remove the final-output temporary name.
    CALL pubTemp                                ; Rebuild the temporary file's FCB.
    LD   DE,cpFcb                               ; Pass the temporary FCB to CP/M.
    LD   C,cpErase                              ; Select CP/M delete-file function 19.
    CALL cpBdos                                 ; Delete uncommitted temp output.
    CALL symDrop                                ; Delete an unpublished symbol file.
    LD   A,(matOwns)                            ; Is $$B still the spool?
    OR   A                                      ; Clear means $$B may hold the old output.
    CALL NZ,matDrop                             ; Let overlay remove only a private spool.
pubUndo: ; Restore a moved old output from its backup.
    LD   A,(pubKept)                            ; Check whether commit moved an old output aside.
    OR   A                                      ; No backup means no restore.
    JR   Z,.done                                ; Finish after attempting temporary-file deletion.
    CALL pubBak                                 ; Rebuild the backup file's FCB.
    LD   HL,cpFcb                               ; Supply the backup name as rename source.
    LD   DE,pubName                             ; Supply the requested output name as destination.
    CALL pubPair                                ; Build a CP/M rename FCB for restoration.
    LD   DE,pubFcb                              ; Pass the completed rename FCB to CP/M.
    LD   C,cpRename                             ; Select CP/M rename-file function 23.
    CALL cpBdos                                 ; Attempt to restore the previous output name.
.done: ; Clear resident transaction state after cleanup.
    XOR  A                                      ; Clear the temporary-file and backup state.
    LD   (pubOpen),A                            ; Clear the open flag after cleanup attempts.
    LD   (pubKept),A                            ; Clear backup state after all cleanup attempts.
    LD   (asoOn),A                              ; Disable ASO dispatch after abort cleanup.
    LD   (asoOpen),A                            ; No ASO temporary FCB remains owned.
    LD   (matOwns),A                            ; Clear private-spool ownership after cleanup attempts.
    RET                                         ; Finish cleanup with the flags cleared.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild the single ordinary output FCB before each new BDOS operation phase.

pubCopy: ; Copy the final filename into the working FCB.
    LD   HL,pubName                             ; Read the normalised drive-plus-name record.
    LD   DE,cpFcb                               ; Select the reusable working FCB as destination.
    LD   BC,12                                  ; Count the drive byte and eleven name/type bytes.
    LDIR                                        ; Copy output name to work FCB.

;@ROUTINE IN DE OUT A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the unused tail of the current CP/M file-control block.

pubClear: ; Clear mutable control fields after the FCB name.
    XOR  A                                      ; Select zero as the byte written to the FCB tail.
    LD   B,24                                   ; Clear remaining FCB fields.

;@ROUTINE IN A,B,DE OUT B,DE
; Fill B bytes at DE with A while advancing the destination pointer.

pubFill: ; Fill a counted byte range without changing A.
    LD   (DE),A                                 ; Write the fill byte at the current FCB address.
    INC  DE                                     ; Advance to the next byte in the control block.
    DJNZ pubFill                                ; Repeat until B bytes have been written.
    RET                                         ; Return with DE advanced past the cleared region.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's temporary filename from the requested output name.

pubTemp: ; Derive the reserved $$$ temporary name.
    CALL pubCopy                                ; Start from the caller's requested output name.
    LD   HL,$2424                               ; Form two '$' bytes.
    LD   (cpFcb+9),HL                           ; Mark the first two extension characters.
    LD   A,'$'                                  ; Select '$' for the extension's final character.
    LD   (cpFcb+11),A                           ; Complete the temporary type '$$$'.
    RET                                         ; Return the temporary FCB name.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the private '$$B' name from the requested output name. It holds the
; ASO spool during assembly and the old output during publication. Editors
; write NAME.BAK, so Atom never uses that name.

pubBak: ; Derive the reserved $$B spool or backup name.
    CALL pubCopy                                ; Start from the caller's requested output name.
    LD   HL,$2424                               ; Form two '$' bytes.
    LD   (cpFcb+9),HL                           ; Mark the first two extension characters.
    LD   A,'B'                                  ; Select 'B' for the extension's final character.
    LD   (cpFcb+11),A                           ; Complete the private type '$$B'.
    RET                                         ; Return the backup filename in the working FCB.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Construct a CP/M rename FCB in the input FCB's dead storage. HL addresses
; the old 12-byte name and DE the new 12-byte name.

pubPair: ; Construct a rename FCB from old and new names.
    PUSH HL                                     ; Preserve the old drive-plus-name source pointer.
    PUSH DE                                     ; Save new-name source pointer.
    LD   DE,pubFcb                              ; Select the start of the 36-byte rename FCB.
    XOR  A                                      ; Use zero to clear unused FCB fields.
    LD   B,36                                   ; Count every byte in the rename FCB.
    CALL pubFill                                ; Clear it before copying either filename.
    POP  DE                                     ; Restore the pointer to the new filename.
    POP  HL                                     ; Restore the pointer to the old filename.
    PUSH DE                                     ; Save new name during old-name copy.
    LD   DE,pubFcb                              ; Place the old name at the start of the FCB.
    LD   BC,12                                  ; Copy its drive, basename and extension fields.
    LDIR                                        ; Fill the rename FCB's old-name field.
    POP  HL                                     ; Use new name as LDIR source.
    LD   DE,pubFcb+16                           ; Select the new-name field in the FCB.
    LD   BC,12                                  ; Copy its drive, basename and extension fields.
    LDIR                                        ; Fill the rename FCB's new-name field.
    RET                                         ; Return the completed rename FCB in workspace.

pubEnd: ; Exclusive end of output publication code.
