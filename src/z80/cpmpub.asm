; These Atom sink entries replace the fail-closed host stubs. IMAGE and PATCH
; are appended to a private ASO spool. output publication waits until COMMIT.

PUB_CBEG: ; Beginning of spool and publication code.
;@@ATOM_CPM_ASO_WRITER@@
HS_CBEG: ; Beginning of replaceable CP/M output hooks.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a tentative ASO spool. Final output is published after COMMIT.

HS_BEG: ; Create a tentative ASO spool for this assembly.
    JP   ASO_BEG                                ; Start the ordered-operation writer.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize one IMAGE or byte-PATCH value in the private CP/M operation spool.

HS_IB: ; Serialise an IMAGE byte with optional INCBIN substitution.
    LD   (BIN_VAL),A                            ; Retain Atom's fill byte while selecting a row.
    LD   A,(BIN_CNT)                            ; Avoid dispatch cost for ordinary CP/M sources.
    OR   A                                      ; A zero count means no INCBIN metadata exists.
    JR   NZ,.BINARY                             ; Counted binary rows alone need sequential reads.
    LD   A,(BIN_VAL)                            ; Restore the original Atom IMAGE fill byte.
    JP   ASO_EMIT                               ; Keep the no-INCBIN output path exactly intact.
.BINARY: ; Read the binary payload for a matched statement.
    PUSH BC                                     ; Keep the address-space class for ASO_EMIT.
    PUSH HL                                     ; Keep the logical target address for the sink.
    LD   A,(ST_EPART)                           ; Read this statement's resolved part ordinal.
    LD   (BIN_SORD),A                           ; Match the sink event to its preflight row.
    LD   HL,(ST_EOFF)                           ; Read the exact IMAGE-producing source position.
    LD   (BIN_SPOS),HL                          ; Retain it while BDOS uses the shared DMA page.
    CALL BIN_SINK                               ; Swap in the next binary byte when anchors match.
    JR   C,.BINFAIL                             ; Preserve the source-aware failure for CP_ENTRY.
    POP  HL                                     ; Restore the logical IMAGE address.
    POP  BC                                     ; Restore its address-space class.
    LD   A,(BIN_VAL)                            ; Load either payload or original fill byte.
    JP   ASO_EMIT                               ; Append the selected value to the ASO stream.
.BINFAIL: ; Restore IMAGE inputs after binary-source failure.
    POP  HL                                     ; Restore the caller's stack, then report failure.
    POP  BC                                     ; Preserve the original address-class register.
    RET                                         ; Return the failed sink status to Atom's driver.
HS_PB: ; Serialise one byte PATCH operation.
    JP   ASO_FIXB                               ; Append the replacement byte to the spool.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Store one little-endian word at its translated logical address.

HS_PW: ; Serialise one little-endian word PATCH operation.
    JP   ASO_FIXW                               ; Append both replacement bytes to the spool.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; COMMIT seals the operation stream and publishes its selected representation.

HS_CMT: ; Check binary completion and seal the operation stream.
    PUSH AF                                     ; Keep Atom's high-water flags and endpoint bit.
    PUSH BC                                     ; Preserve BC, the high-water endpoint low word.
    PUSH DE                                     ; Preserve DE, the remaining target capacity.
    PUSH HL                                     ; Preserve HL, the final target cursor.
    PUSH IX                                     ; Preserve the descriptor geometry pointer.
    CALL BIN_CHK                                ; Do not publish until every payload is consumed.
    JR   C,.PARTIAL                             ; Restore geometry before returning sink failure.
    POP  IX                                     ; Restore the descriptor expected by ASO_CMT.
    POP  HL                                     ; Restore HL, the final target cursor.
    POP  DE                                     ; Restore DE, the remaining target capacity.
    POP  BC                                     ; Restore BC, the high-water endpoint low word.
    POP  AF                                     ; Restore the flags and Atom's endpoint marker.
    JP   ASO_CMT                                ; Seal, materialise if needed, and publish.
.PARTIAL: ; Restore COMMIT inputs after incomplete binary output.
    POP  IX                                     ; Restore every input even when validation fails.
    POP  HL                                     ; Keep the caller's stack balanced for HS_ABORT.
    POP  DE                                     ; Preserve caller-owned image geometry.
    POP  BC                                     ; Restore its address pair.
    POP  AF                                     ; Recover Atom's A before selecting sink status.
    LD   A,1                                    ; Return the established nonzero failure status.
    SCF                                         ; HS_ABORT will discard the tentative spool.
    RET                                         ; No partial output may be committed.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Publish the closed temporary file: move an existing output to $$B, rename
; the temporary file to the final name, then delete $$B. HS_ABORT restores
; the old output if the second rename fails.

PUB_SWAP: ; Publish a completed temporary output using a backup.
    CALL PUB_BAK                                ; Name the backup file for the selected output.
    LD   DE,CP_FCB                              ; Pass its FCB to the delete service.
    LD   C,CP_ERASE                             ; Select CP/M delete-file function 19.
    CALL CP_BDOS                                ; Remove any prior backup file.
    LD   HL,PUB_NAME                            ; Supply the current final name as rename source.
    LD   DE,CP_FCB                              ; Supply the backup name as rename destination.
    CALL PUB_PAIR                               ; Build a CP/M rename FCB for the old output.
    LD   DE,PUB_FCB                             ; Pass the completed rename FCB to CP/M.
    LD   C,CP_REN                               ; Select CP/M rename-file function 23.
    CALL CP_BDOS                                ; Move old output to backup.
    INC  A                                      ; Set zero when CP/M returned $FF for the rename.
    JR   Z,.NOBACKUP                            ; Skip backup on rename failure.
    LD   A,1                                    ; Mark old output as backed up.
    LD   (PUB_KEPT),A                           ; Let abort restore it if the next rename fails.
.NOBACKUP: ; Publish after moving or finding no old output.
    CALL PUB_TEMP                               ; Select the completed temporary output name.
    LD   HL,CP_FCB                              ; Supply the temporary name as rename source.
    LD   DE,PUB_NAME                            ; Supply the requested final name as destination.
    CALL PUB_PAIR                               ; Build the CP/M rename FCB for publication.
    LD   DE,PUB_FCB                             ; Pass the completed rename FCB to CP/M.
    LD   C,CP_REN                               ; Select CP/M rename-file function 23.
    CALL CP_BDOS                                ; Publish temp under final name.
    INC  A                                      ; Test for BDOS rename failure.
    JP   Z,PUB_FAIL                             ; Preserve the backup until abort restores it.
    CALL PUB_BAK                                ; Rebuild the backup name for cleanup.
    LD   DE,CP_FCB                              ; Pass the backup FCB to the delete service.
    LD   C,CP_ERASE                             ; Select CP/M delete-file function 19.
    CALL CP_BDOS                                ; Remove old output after commit.
    XOR  A                                      ; Clear transaction state.
    LD   (PUB_KEPT),A                           ; Clear the flag after attempting backup deletion.
    RET                                         ; Report successful publication with carry clear.
PUB_FAIL: ; Return publication failure for rollback.
    LD   A,1                                    ; Return failed-commit status.
    SCF                                         ; Mark the sink operation as failed.
    RET                                         ; Driver will call HS_ABORT.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close temporary output if open, then delete it. If commit moved the old
; final file aside, restore the backup. Cleanup tolerates early failure.

HS_ABORT: ; Close and remove tentative files on assembly failure.
    LD   A,(BIN_HELD)                           ; See whether a binary include still owns an FCB.
    OR   A                                      ; A clear flag needs no binary close operation.
    JR   Z,.ASO                                 ; Continue when no binary input is open.
    LD   DE,BIN_FCB                             ; Pass the dedicated payload FCB to CP/M.
    LD   C,CP_CLOSE                             ; Select CP/M close-file function sixteen.
    CALL CP_BDOS                                ; Release the binary input before other cleanup.
    XOR  A                                      ; Clear ownership even when CLOSE itself failed.
    LD   (BIN_HELD),A                           ; HS_ABORT must remain safe if called again.
.ASO: ; Close the operation writer if it owns an FCB.
    LD   A,(ASO_OPEN)                           ; Check whether an ASO temporary file is open.
    OR   A                                      ; A clear flag needs no ASO close operation.
    JR   Z,.READER                              ; Continue with the ordinary temporary file.
    LD   DE,ASO_FCB                             ; Pass the ASO spool FCB to the close service.
    LD   C,CP_CLOSE                             ; Select CP/M close-file function 16.
    CALL CP_BDOS                                ; Close the spool before deleting its name.
    XOR  A                                      ; Mark the spool FCB closed for repeated cleanup.
    LD   (ASO_OPEN),A                           ; Mark the spool closed for this abort.
.READER: ; Close an active replay reader.
    LD   A,(MAT_OPEN)                           ; Check whether the spool reader is open.
    OR   A                                      ; Zero means no materialiser reader needs closing.
    JR   Z,.TEMP                                ; Continue cleanup when already closed.
    LD   DE,MAT_FCB                             ; Pass the relocated reader FCB to CP/M.
    LD   C,CP_CLOSE                             ; Select CP/M close-file function 16.
    CALL CP_BDOS                                ; Release the active spool reader before reuse.
    XOR  A                                      ; Clear reader ownership even if CLOSE failed.
    LD   (MAT_OPEN),A                           ; Clear the abort close flag.
.TEMP: ; Close an active final-output temporary file.
    LD   A,(PUB_OPEN)                           ; Check whether the temporary file is open.
    OR   A                                      ; Set zero when no close operation is required.
    JR   Z,.DELETE                              ; Continue directly to removing the temp name.
    LD   DE,CP_FCB                              ; Pass the temporary file's FCB to CP/M.
    LD   C,CP_CLOSE                             ; Select CP/M close-file function 16.
    CALL CP_BDOS                                ; Close the temporary file before deleting it.
.DELETE: ; Remove the final-output temporary name.
    CALL PUB_TEMP                               ; Rebuild the temporary file's FCB.
    LD   DE,CP_FCB                              ; Pass the temporary FCB to CP/M.
    LD   C,CP_ERASE                             ; Select CP/M delete-file function 19.
    CALL CP_BDOS                                ; Delete uncommitted temp output.
    LD   A,(MAT_OWNS)                           ; Is $$B still the spool?
    OR   A                                      ; Clear means $$B may hold the old output.
    CALL NZ,MAT_DROP                            ; Let overlay remove only a private spool.
PUB_UNDO: ; Restore a moved old output from its backup.
    LD   A,(PUB_KEPT)                           ; Check whether commit moved an old output aside.
    OR   A                                      ; No backup means no restore.
    JR   Z,.DONE                                ; Finish after attempting temporary-file deletion.
    CALL PUB_BAK                                ; Rebuild the backup file's FCB.
    LD   HL,CP_FCB                              ; Supply the backup name as rename source.
    LD   DE,PUB_NAME                            ; Supply the requested output name as destination.
    CALL PUB_PAIR                               ; Build a CP/M rename FCB for restoration.
    LD   DE,PUB_FCB                             ; Pass the completed rename FCB to CP/M.
    LD   C,CP_REN                               ; Select CP/M rename-file function 23.
    CALL CP_BDOS                                ; Attempt to restore the previous output name.
.DONE: ; Clear resident transaction state after cleanup.
    XOR  A                                      ; Clear the temporary-file and backup state.
    LD   (PUB_OPEN),A                           ; Clear the open flag after cleanup attempts.
    LD   (PUB_KEPT),A                           ; Clear backup state after all cleanup attempts.
    LD   (ASO_ON),A                             ; Disable ASO dispatch after abort cleanup.
    LD   (ASO_OPEN),A                           ; No ASO temporary FCB remains owned.
    LD   (MAT_OWNS),A                           ; Clear private-spool ownership after cleanup attempts.
    RET                                         ; Finish cleanup with the flags cleared.

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Route final-image writer requests through the index-preserving BDOS wrapper.

ZTS_CPM_FINAL_BDOS: ; Enter BDOS for the Intel HEX record writer.
    JP   CP_BDOS                                ; Use the index-preserving wrapper.
ZTS_CPM_FINAL_FCB           EQU     CP_FCB      ; FCB used for writing HEX records.
ZTS_CPM_FINAL_DMA           EQU     SRC_PAGE    ; HEX reuses the source-cache page.
ZTS_CPM_FINAL_SOURCE_CURSOR EQU     PUB_POS     ; Current byte in the image.
ZTS_CPM_FINAL_REMAINING     EQU     PUB_LEFT    ; Image bytes left to render.
ZTS_CPM_FINAL_ADDRESS       EQU     HEX_ADDR    ; Address in the next HEX record.
ZTS_CPM_FINAL_DMA_CURSOR    EQU     HEX_PTR     ; Next byte in the HEX buffer.
ZTS_CPM_FINAL_DMA_COUNT     EQU     HEX_CNT     ; Bytes queued for transfer.
ZTS_CPM_FINAL_ERROR         EQU     HEX_ERR     ; Sticky record-write error status.
ZTS_CPM_FINAL_SUM           EQU     HEX_SUM     ; Checksum accumulator for one HEX record.
ZTS_CPM_FINAL_SIZE          EQU     HEX_SIZE    ; Current HEX record payload length.
ZTS_CPM_FINAL_DATA_LEFT     EQU     HEX_LEFT    ; Payload bytes still to render.
;@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild the single ordinary output FCB before each new BDOS operation phase.

PUB_COPY: ; Copy the final filename into the working FCB.
    LD   HL,PUB_NAME                            ; Read the normalised drive-plus-name record.
    LD   DE,CP_FCB                              ; Select the reusable working FCB as destination.
    LD   BC,12                                  ; Count the drive byte and eleven name/type bytes.
    LDIR                                        ; Copy output name to work FCB.

;@ROUTINE IN DE OUT A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the unused tail of the current CP/M file-control block.

PUB_TAIL: ; Clear mutable control fields after the FCB name.
    XOR  A                                      ; Select zero as the byte written to the FCB tail.
    LD   B,24                                   ; Clear remaining FCB fields.

;@ROUTINE IN A,B,DE OUT B,DE
; Fill B bytes at DE with A while advancing the destination pointer.

PUB_FILL: ; Fill a counted byte range without changing A.
    LD   (DE),A                                 ; Write the fill byte at the current FCB address.
    INC  DE                                     ; Advance to the next byte in the control block.
    DJNZ PUB_FILL                               ; Repeat until B bytes have been written.
    RET                                         ; Return with DE advanced past the cleared region.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's temporary filename from the requested output name.

PUB_TEMP: ; Derive the reserved $$$ temporary name.
    CALL PUB_COPY                               ; Start from the caller's requested output name.
    LD   HL,$2424                               ; Form two '$' bytes.
    LD   (CP_FCB+9),HL                          ; Mark the first two extension characters.
    LD   A,'$'                                  ; Select '$' for the extension's final character.
    LD   (CP_FCB+11),A                          ; Complete the temporary type '$$$'.
    RET                                         ; Return the temporary FCB name.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the private '$$B' name from the requested output name. It holds the
; ASO spool during assembly and the old output during publication. Editors
; write NAME.BAK, so Atom never uses that name.

PUB_BAK: ; Derive the reserved $$B spool or backup name.
    CALL PUB_COPY                               ; Start from the caller's requested output name.
    LD   HL,$2424                               ; Form two '$' bytes.
    LD   (CP_FCB+9),HL                          ; Mark the first two extension characters.
    LD   A,'B'                                  ; Select 'B' for the extension's final character.
    LD   (CP_FCB+11),A                          ; Complete the private type '$$B'.
    RET                                         ; Return the backup filename in the working FCB.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Construct a CP/M rename FCB in the input FCB's dead storage. HL addresses
; the old 12-byte name and DE the new 12-byte name.

PUB_PAIR: ; Construct a rename FCB from old and new names.
    PUSH HL                                     ; Preserve the old drive-plus-name source pointer.
    PUSH DE                                     ; Save new-name source pointer.
    LD   DE,PUB_FCB                             ; Select the start of the 36-byte rename FCB.
    XOR  A                                      ; Use zero to clear unused FCB fields.
    LD   B,36                                   ; Count every byte in the rename FCB.
    CALL PUB_FILL                               ; Clear it before copying either filename.
    POP  DE                                     ; Restore the pointer to the new filename.
    POP  HL                                     ; Restore the pointer to the old filename.
    PUSH DE                                     ; Save new name during old-name copy.
    LD   DE,PUB_FCB                             ; Place the old name at the start of the FCB.
    LD   BC,12                                  ; Copy its drive, basename and extension fields.
    LDIR                                        ; Fill the rename FCB's old-name field.
    POP  HL                                     ; Use new name as LDIR source.
    LD   DE,PUB_FCB+16                          ; Select the new-name field in the FCB.
    LD   BC,12                                  ; Copy its drive, basename and extension fields.
    LDIR                                        ; Fill the rename FCB's new-name field.
    RET                                         ; Return the completed rename FCB in workspace.

PUB_CEND: ; Exclusive end of output publication code.
