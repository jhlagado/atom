; INCBIN: the core parses each INCBIN statement as it reaches it and asks for
; the file's bytes through tkBin and tkBinRd. One file is open at a time,
; read sequentially through its own FCB and record buffer.

;@ROUTINE IN B,HL OUT A,CARRY MAYBE-OUT HL CLOBBERS BC,DE,IY,HALFCARRY,ZERO,SIGN,PARITY
; Open the binary file named by the B bytes at HL. CP/M records file sizes in
; 128-byte units, so the exact length cannot be told: A=1 asks the core for an
; explicit count. A name that would alias the output or a work file fails.

tkBin: ; Open an INCBIN file on CP/M.
    PUSH HL                             ; Keep the name.
    PUSH BC                             ; Keep its length.
    CALL binShut                        ; Close the previous file, if any.
    POP  BC                             ; Restore the length.
    POP  HL                             ; Restore the name.
    LD   DE,binFcb                      ; Parse into the binary FCB.
    CALL srcName                        ; Validate and store the 8.3 name.
    JR   C,.fail                        ; Reject a malformed name.
    LD   DE,binFcb+12                   ; Address the FCB's control fields.
    XOR  A                              ; Clear extent, record and random record.
    LD   B,24                           ; The FCB has a twenty-four-byte tail.
    CALL pubFill                        ; Start reading at the first record.

; Reading a file that the build will replace could destroy it.

    LD   HL,binFcb                      ; Compare with the output name.
    LD   DE,pubName                     ; The final output name.
    CALL cmdSame                        ; Z means the same file.
    JR   Z,.fail                        ; Refuse it.
    CALL pubTemp                        ; Build the temporary output name.
    LD   HL,binFcb                      ; Compare with it.
    LD   DE,cpFcb                       ; The temporary name.
    CALL cmdSame                        ; Z means the same file.
    JR   Z,.fail                        ; Refuse it.
    CALL pubBak                         ; Build the backup and spool name.
    LD   HL,binFcb                      ; Compare with it.
    LD   DE,cpFcb                       ; The backup name.
    CALL cmdSame                        ; Z means the same file.
    JR   Z,.fail                        ; Refuse it.
    LD   DE,binFcb                      ; Pass the binary FCB to CP/M.
    LD   C,cpOpen                       ; Select open-file function 15.
    CALL cpBdos                         ; Open the file.
    INC  A                              ; $FF means it cannot be opened.
    JR   Z,.fail                        ; Report it.
    LD   A,1                            ; The FCB is now open.
    LD   (binHeld),A                    ; binShut and hsAbort close it.
    XOR  A                              ; No record is buffered yet.
    LD   (binLeft),A                    ; The first read loads a record.
    INC  A                              ; A=1: the length cannot be told.
    OR   A                              ; Clear carry.
    RET                                 ; The file is open.
.fail: ; Report a file that cannot be read.
    LD   A,1                            ; A nonzero status.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The core reports the INCBIN line.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,HALFCARRY,ZERO,SIGN,PARITY
; Return the next byte of the open binary file. Carry means its records ran
; out or a read failed before the core had all the bytes it counted.

tkBinRd: ; Read one INCBIN byte on CP/M.
    LD   A,(binLeft)                    ; Bytes left in the buffered record.
    OR   A                              ; Zero asks for the next record.
    JR   NZ,.byte                       ; Take a buffered byte.
    LD   DE,binBuf                      ; Read into the binary record buffer.
    LD   C,cpSetDma                     ; Select set-DMA function 26.
    CALL cpBdos                         ; Install it.
    LD   DE,binFcb                      ; Pass the binary FCB.
    LD   C,cpRead                       ; Select sequential read function 20.
    CALL cpBdos                         ; Read one record.
    OR   A                              ; Zero means success.
    JR   NZ,.fail                       ; The file ended too soon.
    LD   A,128                          ; A whole record is buffered.
    LD   (binLeft),A                    ; Count it down.
    LD   HL,binBuf                      ; Start at its first byte.
    LD   (binRPtr),HL                   ; Keep the cursor.
.byte: ; Take the next buffered byte.
    LD   HL,(binRPtr)                   ; Address it.
    LD   A,(HL)                         ; $1A, CR and LF are ordinary data here.
    INC  HL                             ; Advance the cursor.
    LD   (binRPtr),HL                   ; Keep it.
    LD   HL,binLeft                     ; Count the byte.
    DEC  (HL)                           ; One fewer remains in the record.
    OR   A                              ; Clear carry.
    RET                                 ; Return the byte.
.fail: ; Report a short or unreadable file.
    LD   A,1                            ; A nonzero status.
    SCF                                 ; Carry marks the failure.
    RET                                 ; The core reports the INCBIN line.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Close the open binary file, if any. Reading leaves nothing to flush, so a
; failed close changes nothing.

binShut: ; Close the current INCBIN file.
    LD   A,(binHeld)                    ; Is a file open?
    OR   A                              ; Zero means no.
    RET  Z                              ; Nothing to close.
    XOR  A                              ; Release ownership first.
    LD   (binHeld),A                    ; A second call does nothing.
    LD   DE,binFcb                      ; Pass the binary FCB.
    LD   C,cpClose                      ; Select close-file function 16.
    JP   cpBdos                         ; Close it.
