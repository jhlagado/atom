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


;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the ordinary input FCB from one retained name.

srcOpen: ; Open the source named by its discovery ordinal.
    PUSH AF                             ; Save ordinal while clearing FCB.
    CALL srcWipe                        ; Reset the file-control block for this source.
    POP  AF                             ; Restore the source ordinal.
    CALL incSlot                        ; Address the source's eleven-byte name record.
    LD   DE,srcFcb+1                    ; Point past the drive byte to the 8.3 fields.
    LD   B,11                           ; Copy the full 8.3 name.
.copy: ; Copy the source name with the emitted marker removed.
    LD   A,(HL)                         ; Read the next byte of the retained source name.
    AND  $7F                            ; Clear the first byte's order bit.
    LD   (DE),A                         ; Copy the ordinary name byte into the input FCB.
    INC  HL                             ; Advance within the retained name record.
    INC  DE                             ; Advance within the input FCB name fields.
    DJNZ .copy                          ; Copy all eleven name and type bytes.
    CALL srcCheck                       ; Protect output and transaction files.
    RET  C                              ; Reject a source/output alias.
    LD   DE,srcFcb                      ; Pass the prepared FCB to CP/M.
    LD   C,cpOpen                       ; Select the CP/M open-file service.
    CALL cpBdos                         ; Open the selected source file.
    INC  A                              ; Convert BDOS's $FF failure result to zero.
    JR   Z,.fail                        ; Report an unavailable source by name.
    LD   A,1                            ; Force the next cache refill.
    LD   (srcKey),A                     ; Aligned record offsets cannot equal one.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the input FCB open.
.fail: ; Report a failed source open by filename.
    LD   HL,srcFcb                      ; Address the filename that failed to open.
    CALL cpPutFcb                       ; Print its drive-independent 8.3 name.
    LD   DE,msgRead                     ; Select the source-open error message.
    SCF                                 ; Mark the open operation as failed.
    RET                                 ; Return the message pointer with carry set.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the next raw source byte and advance HL. Carry with A=0 means EOF or
; an unsuccessful CP/M random read. Carry with A=2 means the 16-bit offset
; wrapped. BC and DE survive for parsers.
; A part is limited to 65,535 bytes so the next offset cannot wrap to zero.

srcNext: ; Read a raw source byte and advance its logical offset.
    PUSH BC                             ; Preserve the parser's byte-sized working values.
    PUSH DE                             ; Save the parser's DE value.
    PUSH HL                             ; Save the logical offset.
    CALL srcRaw                         ; Read from the current CP/M record cache.
    POP  HL                             ; Restore the logical offset.
    POP  DE                             ; Restore the caller's DE value.
    POP  BC                             ; Restore the caller's BC value.
    RET  C                              ; Return EOF/read failure. keep HL.
    LD   (srcTemp),A                    ; Save the byte while advancing the offset.
    INC  HL                             ; Advance to the following offset.
    LD   A,H                            ; Test the high byte of the advanced offset.
    OR   L                              ; Zero means the 16-bit offset wrapped.
    JR   Z,.tooLong                     ; Reject a part that would exceed 65,535 bytes.
    LD   A,(srcTemp)                    ; Restore the byte read from the source.
    OR   A                              ; Clear carry. set Z for byte zero.
    RET                                 ; Return byte and advanced offset.
.tooLong: ; Reject a source offset that wrapped to zero.
    LD   A,2                            ; Distinguish offset overflow.
    SCF                                 ; Report that the logical source offset wrapped.
    RET                                 ; Return the overflow status to the resolver.

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
srcEof: ; Return text EOF at the SUB marker.
    XOR  A                              ; Return EOF or read failure.
    SCF                                 ; Carry reports that no source byte is available.
    RET                                 ; Share the no-byte result.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Consume source bytes through the next CR, LF or end of file.

srcSkip: ; Skip through the next physical line ending.
    CALL srcNext                        ; Read the next byte in the current line.
    RET  C                              ; Stop at EOF or offset overflow.
    CP   13                             ; Test for a carriage return.
    RET  Z                              ; Stop after consuming CR.
    CP   10                             ; Test for a line feed.
    JR   NZ,srcSkip                     ; Continue until LF or another CR.
    RET                                 ; Stop after consuming LF.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Open a part on ordinal change, then return one source byte through the
; 128-byte random-record cache. This is the core's source service. The
; pre-scan proves each requested record exists until this command returns.
; Preflight validates INCLUDE, DEFINE and conditional directives. A leading
; percent becomes a semicolon so Atom reads the directive as a comment.

tkRead: ; Atom's source-byte service on CP/M.
srcByte: ; Select a source part and apply preprocessing filters.
    LD   E,A                            ; Keep the resolved source-part ordinal.
    LD   A,(srcPart)                    ; Read the ordinal of the open source file.
    CP   E                              ; Compare it with the requested part.
    JR   Z,.ready                       ; Reuse the file when ordinals match.
    PUSH BC                             ; Preserve the caller's byte-sized parser state.
    PUSH HL                             ; Save offset across file open.
    LD   A,E                            ; Restore the requested resolved ordinal.
    LD   (srcPart),A                    ; Record which resolved part is now active.
    LD   D,incOrder/256                 ; Address the order table's fixed memory page.
    LD   A,(DE)                         ; Map order to source ordinal.
    CALL srcOpen                        ; Open the source named by that original ordinal.
    CALL ppReset                        ; Start each source part outside a conditional.
    POP  HL                             ; Restore the byte offset.
    POP  BC                             ; Restore the caller's parser state.
.ready: ; Read from the already selected source part.
    PUSH BC                             ; Save parser BC across raw read.
    PUSH HL                             ; Preserve the source offset across cache lookup.
    CALL srcRaw                         ; Read one byte from the active source file.
    POP  HL                             ; Restore the source offset.
    POP  BC                             ; Restore the caller's parser state.
    RET  C                              ; Return end-of-input or a failed read unchanged.
    JP   ppFilter                       ; Filter directives and inactive lines.

;@ROUTINE IN HL OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Decide whether a percent character begins a recognised host directive.

srcLead: ; Test whether percent follows only line indentation.
    LD   A,H                            ; Test the current source offset's high byte.
    OR   L                              ; Zero means the percent is the first source byte.
    RET  Z                              ; Report line start when no preceding byte exists.
    DEC  HL                             ; Begin scanning at the byte before the percent.
.back: ; Scan preceding source bytes back to a line boundary.
    PUSH HL                             ; Save the backward-scan cursor.
    CALL srcRaw                         ; Read the preceding source byte.
    POP  HL                             ; Restore the offset used for the backward scan.
    CP   13                             ; Does percent follow CR?
    JR   Z,.yes                         ; CR marks the start of a source line.
    CP   10                             ; Check whether the percent follows a line feed.
    JR   Z,.yes                         ; LF also marks the start of a source line.
    CP   ' '                            ; Check for a space before the percent.
    JR   Z,.prev                        ; Skip whitespace while scanning backwards.
    CP   9                              ; Check for a horizontal tab.
    RET  NZ                             ; Other prefix means ordinary text.
.prev: ; Continue backwards over horizontal indentation.
    LD   A,H                            ; Did whitespace reach offset zero?
    OR   L                              ; No preceding non-space byte.
    JR   Z,.yes                         ; Only spaces or tabs precede the percent.
    DEC  HL                             ; Step back one source byte.
    JR   .back                          ; Continue until line start or ordinary text.
.yes: ; Accept a line-leading percent directive.
    XOR  A                              ; Mark a line-leading percent.
    RET                                 ; Return with carry clear.
