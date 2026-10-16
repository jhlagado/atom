; Source files: CP/M FCBs and a 128-byte random-record cache that serve
; Atom one source byte at a time.

srcBeg: ; Beginning of source and include-resolution code.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare a blank ordinary FCB whose name/type fields are space-filled.

srcWipe: ; Initialise a blank current-drive source FCB.
    LD   DE,srcFcb                      ; Point at the input FCB's drive byte.
    XOR  A                              ; Select the logged-in drive by default.
    LD   (DE),A                         ; Store drive zero before filling the name.
    INC  DE                             ; Advance to the eleven name/type bytes.
    LD   B,11                           ; Count all eight name and three type bytes.
    LD   A,' '                          ; CP/M pads unused name fields with spaces.
    CALL pubFill                        ; Fill the complete name/type area.
    JP   pubClear                       ; Clear the remaining FCB control fields.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reject output, temporary or backup names that collide with the source name.

srcCheck: ; Protect source names against output and work files.
    LD   HL,srcFcb                      ; Keep the original source identity in HL.
    LD   DE,pubName                     ; Compare it with the requested output name.
    CALL cmdSame                        ; Z means both twelve-byte FCB identities match.
    JR   Z,.clash                       ; Never replace the source file.
    CALL pubTemp                        ; Construct the temporary output filename.
    LD   HL,srcFcb                      ; Restore the source FCB pointer for comparison.
    LD   DE,cpFcb                       ; The temporary name occupies the work FCB.
    CALL cmdSame                        ; Reject a temporary name that aliases the source.
    JR   Z,.clash                       ; Preserve the source file.
    CALL pubBak                         ; Construct the backup filename for the output.
    LD   HL,srcFcb                      ; Compare the source against that third identity.
    LD   DE,cpFcb                       ; The backup candidate is now in the work FCB.
    CALL cmdSame                        ; Z again means the names would collide.
    JR   Z,.clash                       ; Refuse a source/output collision.
    XOR  A                              ; A=0 reports that all three names are distinct.
    RET                                 ; Return clear carry with the success result.
.clash: ; Return a source and output alias failure.
    LD   DE,msgDup                      ; Return the collision message in DE.
    SCF                                 ; Mark the preflight check as failed.
    RET                                 ; Leave file creation to the caller's error path.


;@ROUTINE IN A OUT A,CARRY,DE CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the input FCB from one retained name. Carry reports a name
; that aliases the output or a work file (DE=msgDup), or a file that cannot be
; opened (DE=msgRead).

srcOpen: ; Open the source named by its ordinal.
    PUSH AF                             ; Save ordinal while clearing FCB.
    CALL srcWipe                        ; Reset the file-control block for this source.
    POP  AF                             ; Restore the source ordinal.
    CALL incSlot                        ; Address the source's eleven-byte name record.
    LD   DE,srcFcb+1                    ; Point past the drive byte to the 8.3 fields.
    LD   BC,11                          ; Copy the full 8.3 name.
    LDIR                                ; Copy the name into the input FCB.
    CALL srcCheck                       ; Protect output and transaction files.
    RET  C                              ; Reject a source/output alias.
    LD   DE,srcFcb                      ; Pass the prepared FCB to CP/M.
    LD   C,cpOpen                       ; Select the CP/M open-file service.
    CALL cpBdos                         ; Open the selected source file.
    INC  A                              ; Convert BDOS's $FF failure result to zero.
    JR   Z,.fail                        ; Report an unavailable source.
    LD   A,1                            ; Force the next cache refill.
    LD   (srcKey),A                     ; Aligned record offsets cannot equal one.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the input FCB open.
.fail: ; Report a failed source open.
    LD   DE,msgRead                     ; Select the source-open error message.
    SCF                                 ; Mark the open operation as failed.
    RET                                 ; The caller records the file's name.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Align the logical offset to its 128-byte CP/M record base. The cache
; key stores that base. the FCB receives it divided by 128. On a miss,
; the routine installs the source cache as DMA and reads that record.
; It then uses the low seven bits to select the requested byte.

srcRaw: ; Read a source byte through the random-record cache.
    LD   (srcPos),HL                    ; Save the requested logical byte offset.
    LD   A,L                            ; Inspect the low byte of the requested offset.
    AND  $80                            ; Keep its 128-byte record-boundary bit.
    LD   E,A                            ; Form the aligned offset's low byte.
    LD   D,H                            ; Form its high byte from the logical offset.
    LD   HL,(srcKey)                    ; Read the offset currently in the cache.
    OR   A                              ; Clear carry for base subtraction.
    SBC  HL,DE                          ; Compare the cached and requested record bases.
    JR   Z,srcHit                       ; Reuse the cache when both bases match.
srcMiss: ; Load the required random source record.
    LD   (srcKey),DE                    ; Store the aligned offset being loaded.
    RLC  E                              ; Move offset bit 7 into record bit 0.
    LD   A,D                            ; Load the offset high byte.
    ADD  A,A                            ; Shift its bits left one place.
    OR   E                              ; Add the original offset's bit 7.
    LD   (srcFcb+33),A                  ; Store the random record number's low byte.
    LD   A,D                            ; Reload the offset's high byte.
    RLCA                                ; Move offset bit 15 into bit 0.
    AND  1                              ; Keep only the record number's high bit.
    LD   (srcFcb+34),A                  ; Store the random record number's high byte.
    LD   DE,srcCache                    ; Select the 128-byte DMA buffer.
    LD   C,cpSetDma                     ; Set the CP/M transfer address.
    CALL cpBdos                         ; Direct the next read into the source cache.
    LD   DE,srcFcb                      ; Pass the file and record number to CP/M.
    LD   C,cpReadAt                     ; Select a random-record read.
    CALL cpBdos                         ; Load the requested 128-byte source record.
    OR   A                              ; Zero means the random read succeeded.
    JR   NZ,srcFail                     ; Treat a BDOS read failure as no source byte.

; A file may hold at most 65,535 bytes. If the record at $FF80 is full, the
; file has a 65,536th byte.

    LD   HL,(srcKey)                    ; Is this the last record a file may use?
    LD   DE,$FF80                       ; Its key.
    OR   A                              ; Clear carry for the comparison.
    SBC  HL,DE                          ; Zero when it is.
    JR   NZ,srcHit                      ; No: take the byte.
    LD   A,(srcCache+$7F)               ; Does its final byte hold text?
    CP   $1A                            ; ^Z means the file ended earlier.
    JR   Z,srcHit                       ; Then it fits.
    LD   HL,1                           ; No record base is odd.
    LD   (srcKey),HL                    ; The cache holds no record now.
    LD   A,srcLong                      ; The file is too long.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The front end reports it.
srcHit: ; Select a byte within the cached source record.
    LD   HL,(srcPos)                    ; Restore the byte's logical offset.
    RES  7,L                            ; Keep its within-record offset in $00..$7F.
    LD   H,srcCache/256                 ; Select the source cache's memory page.
    LD   A,(HL)                         ; Read the byte from the cached record.
    CP   $1A                            ; Test CP/M's text-file end marker.
    JR   Z,srcEof                       ; Return end-of-input at control-Z.
    OR   A                              ; Clear carry. retain source byte.
    RET                                 ; Return the raw byte to the caller.
srcFail: ; Return a failed random-read result.
    LD   HL,1                           ; No record base is odd.
    LD   (srcKey),HL                    ; The cache holds no record now.
srcEof: ; Return text EOF at the SUB marker.
    XOR  A                              ; Return EOF or read failure.
    SCF                                 ; Carry reports that no source byte is available.
    RET                                 ; Share the no-byte result.

;@ROUTINE IN B,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Store the B-byte name at HL as a current-drive 8.3 name in the FCB at DE.
; Lowercase letters fold to uppercase. Carry reports an empty, overlong or
; otherwise invalid name.

srcName: ; Parse a current-drive 8.3 name from memory into an FCB.
    PUSH DE                             ; Keep the FCB address.
    POP  IY                             ; IY writes the name.
    LD   (IY+0),0                       ; Drive zero is the current drive.
    LD   C,11                           ; Blank the name and type fields.
.blank: ; Store one padding space.
    INC  DE                             ; Advance to the next field byte.
    LD   A,' '                          ; CP/M pads names with spaces.
    LD   (DE),A                         ; Store it.
    DEC  C                              ; Count it.
    JR   NZ,.blank                      ; Blank all eleven bytes.
    INC  IY                             ; IY writes the base name.
    LD   D,8                            ; The base name holds eight characters.
    LD   C,0                            ; Count characters in the current field.
.byte: ; Inspect the next name byte.
    LD   A,B                            ; Any bytes left?
    OR   A                              ; Zero means the name has ended.
    JR   Z,.done                        ; Check the final field.
    LD   A,(HL)                         ; Read the byte.
    INC  HL                             ; Advance past it.
    DEC  B                              ; Count it.
    CP   '.'                            ; Does the type start here?
    JR   NZ,.data                       ; No: store the byte.
    LD   A,D                            ; Only one dot, after the base name.
    CP   8                              ; Still in the base name?
    JR   NZ,.bad                        ; No: a second dot.
    LD   A,C                            ; The base name must not be empty.
    OR   A                              ; Zero characters so far?
    JR   Z,.bad                         ; Reject a leading dot.
    LD   A,8                            ; Skip the rest of the base field.
    SUB  C                              ; Unused base bytes.
    LD   E,A                            ; Widen the count.
    LD   D,0                            ; DE is the distance to the type field.
    ADD  IY,DE                          ; IY writes the type.
    LD   D,3                            ; The type holds three characters.
    LD   C,0                            ; Start counting them.
    JR   .byte                          ; Read the type.
.data: ; Fold, check and store one name byte.
    CP   'a'                            ; Is it a lowercase letter?
    JR   C,.cased                       ; No: keep it.
    CP   'z'+1                          ; Test the upper bound.
    JR   NC,.cased                      ; No: keep it.
    AND  $DF                            ; Fold it to uppercase.
.cased: ; Check and store the byte.
    CALL cmdChar                        ; Is it allowed in a CP/M name?
    JR   C,.bad                         ; No: reject the name.
    INC  C                              ; Count it.
    LD   E,A                            ; Keep it during the width check.
    LD   A,D                            ; Load the field's width.
    CP   C                              ; Has the field overflowed?
    JR   C,.bad                         ; Yes: reject the name.
    LD   (IY+0),E                       ; Store the byte.
    INC  IY                             ; Advance within the field.
    JR   .byte                          ; Continue.
.done: ; Require a nonempty final field.
    LD   A,C                            ; Characters in the last field.
    OR   A                              ; Zero means empty.
    RET  NZ                             ; Accept the name with carry clear.
.bad: ; Reject the name.
    SCF                                 ; Carry marks an invalid name.
    RET                                 ; The FCB holds a partial name.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Return the byte at offset HL of the open file. Carry with A=0 at its end,
; or with a message number when it cannot be read. Most bytes come from the
; cached record.

sfRead: ; Read one byte of the open source file.
    LD   A,(srcKey+1)                   ; Compare the cached record's high byte.
    CP   H                              ; Same 256-byte page of the file?
    JR   NZ,.slow                       ; No: load the record.
    LD   A,L                            ; Align the offset to its record.
    AND  $80                            ; Keep the record-boundary bit.
    LD   E,A                            ; Hold the aligned low byte.
    LD   A,(srcKey)                     ; Compare the cached record's low byte.
    CP   E                              ; Same 128-byte record?
    JR   NZ,.slow                       ; No: load the record.
    LD   E,L                            ; Form the byte's address in the cache.
    RES  7,E                            ; Keep its offset within the record.
    LD   D,srcCache/256                 ; Select the cache page.
    LD   A,(DE)                         ; Read the cached byte.
    CP   $1A                            ; CP/M's end-of-text marker?
    JR   Z,.end                         ; Yes: the file has ended.
    OR   A                              ; Clear carry.
    RET                                 ; Return the byte.
.end: ; Report the end of the file.
    XOR  A                              ; A=0 with carry is the end.
    SCF                                 ; Carry marks it.
    RET                                 ; The front end finishes the part.
.slow: ; Read through the cache loader.
    PUSH BC                             ; Keep the caller's BC.
    PUSH HL                             ; Keep the offset.
    CALL srcRaw                         ; Read one byte from the open file.
    POP  HL                             ; Restore the offset.
    POP  BC                             ; Restore the caller's BC.
    RET                                 ; Return the byte, the end or a failure.
