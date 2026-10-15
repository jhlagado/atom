; Intel HEX writer for the CP/M materialiser. hexReset opens one stream,
; hexSeg renders pubLeft bytes from pubPos at hexAddr and hexClose writes
; the end record and pads the final CP/M record with $1A. Text collects in
; the source-cache page, which is free once assembly has finished. A failed
; record write sets hexErr, later bytes are dropped and hexClose reports it.

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Route HEX record writes through the index-preserving BDOS wrapper.

hexBdos: ; Enter BDOS for the Intel HEX record writer.
    JP   cpBdos                                 ; Use the index-preserving wrapper.

;@ROUTINE OUT A CLOBBERS HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Start an empty HEX stream with no write error.

hexReset: ; Reset the HEX buffer and error state.
    LD   HL,srcCache                            ; Start at the first buffer byte.
    LD   (hexPtr),HL                            ; Save the buffer cursor.
    XOR  A                                      ; Clear the count and the error.
    LD   (hexCnt),A                             ; No text bytes are queued.
    LD   (hexErr),A                             ; No record write has failed.
    RET                                         ; Return ready for hexSeg.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Render pubLeft bytes from pubPos as data records of up to 16 bytes.

hexSeg: ; Write data records until the segment is empty.
    LD   HL,(pubLeft)                           ; Read the bytes still to render.
    LD   A,H                                    ; Test the count for zero.
    OR   L                                      ; Combine both count bytes.
    RET  Z                                      ; The segment is complete.
    LD   A,H                                    ; 256 or more bytes remain?
    OR   A                                      ; Test the high count byte.
    LD   A,16                                   ; Assume a full record.
    JR   NZ,.ready                              ; A full record fits.
    LD   A,L                                    ; Read the low count byte.
    CP   16                                     ; Fewer than 16 bytes remain?
    JR   C,.ready                               ; Use the short count.
    LD   A,16                                   ; Otherwise use a full record.
.ready: ; A holds this record's payload length.
    LD   (hexSize),A                            ; Save the record length.
    LD   (hexLeft),A                            ; Count payload bytes down.
    LD   A,':'                                  ; Start the record.
    CALL hexPut                                 ; Queue the start code.
    XOR  A                                      ; Clear the checksum.
    LD   (hexSum),A                             ; Sum the fields from here.
    LD   A,(hexSize)                            ; Write the length field.
    CALL hexField                               ; Add it to the checksum.
    LD   HL,(hexAddr)                           ; Read the record address.
    PUSH HL                                     ; Keep its low byte.
    LD   A,H                                    ; Write the high address byte.
    CALL hexField                               ; Add it to the checksum.
    POP  HL                                     ; Recover the address.
    LD   A,L                                    ; Write the low address byte.
    CALL hexField                               ; Add it to the checksum.
    XOR  A                                      ; Record type 0 is data.
    CALL hexField                               ; Write the type field.
.data: ; Write each payload byte.
    LD   A,(hexLeft)                            ; Any payload bytes left?
    OR   A                                      ; Test the remaining count.
    JR   Z,.check                               ; Finish with the checksum.
    LD   HL,(pubPos)                            ; Read the image cursor.
    LD   A,(HL)                                 ; Fetch the next image byte.
    INC  HL                                     ; Advance the cursor.
    LD   (pubPos),HL                            ; Save the cursor.
    CALL hexField                               ; Write the byte and sum it.
    LD   A,(hexLeft)                            ; Count the byte.
    DEC  A                                      ; One fewer payload byte.
    LD   (hexLeft),A                            ; Save the count.
    JR   .data                                  ; Write the next byte.
.check: ; End the record with its checksum and CRLF.
    LD   A,(hexSum)                             ; Read the field sum.
    NEG                                         ; The checksum makes it zero.
    CALL hexByte                                ; Write it without summing.
    LD   A,13                                   ; End the record line.
    CALL hexPut                                 ; Queue CR.
    LD   A,10                                   ; Finish the line.
    CALL hexPut                                 ; Queue LF.
    LD   A,(hexSize)                            ; Read the payload length.
    LD   E,A                                    ; Widen it in DE.
    LD   D,0                                    ; Clear the high byte.
    LD   HL,(pubLeft)                           ; Read the bytes left.
    OR   A                                      ; Clear carry.
    SBC  HL,DE                                  ; Remove this record's bytes.
    LD   (pubLeft),HL                           ; Save the new count.
    LD   HL,(hexAddr)                           ; Read the record address.
    ADD  HL,DE                                  ; Advance past this record.
    LD   (hexAddr),HL                           ; Address the next record.
    JR   hexSeg                                 ; Write the next record.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write the end record, pad the last CP/M record and report any write error.

hexClose: ; Finish the HEX stream.
    LD   HL,hexEofLn                            ; Read the end-record text.
    LD   B,13                                   ; Count its bytes.
.eof: ; Queue each end-record byte.
    PUSH BC                                     ; Keep the count.
    PUSH HL                                     ; Keep the text cursor.
    LD   A,(HL)                                 ; Fetch the next byte.
    CALL hexPut                                 ; Queue it.
    POP  HL                                     ; Recover the cursor.
    POP  BC                                     ; Recover the count.
    INC  HL                                     ; Advance the cursor.
    DJNZ .eof                                   ; Queue the rest.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pad the last CP/M record with $1A, write it and report any write error.
; Any text file written through hexPut ends here.

hexDone: ; Finish a text file written through hexPut.
.pad: ; Fill the last record with CP/M end-of-file bytes.
    LD   A,(hexCnt)                             ; Bytes in the open record?
    OR   A                                      ; Zero means it was written.
    JR   Z,.done                                ; Nothing to pad.
    LD   A,$1A                                  ; CP/M end of text.
    CALL hexPut                                 ; Queue one pad byte.
    JR   .pad                                   ; Pad until written.
.done: ; Report the sticky write status.
    LD   A,(hexErr)                             ; Did a record write fail?
    OR   A                                      ; Test the status.
    RET  Z                                      ; Return carry clear on success.
    SCF                                         ; Report the failure.
    RET                                         ; Return carry set.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Add a field byte to the checksum, then write it as two hex digits.

hexField: ; Sum and write one field byte.
    PUSH AF                                     ; Keep the byte.
    LD   E,A                                    ; Hold it for the sum.
    LD   A,(hexSum)                             ; Read the checksum.
    ADD  A,E                                    ; Add the byte.
    LD   (hexSum),A                             ; Save the checksum.
    POP  AF                                     ; Recover the byte.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write A as two uppercase hex digits.

hexByte: ; Write the high digit, then fall into the low digit.
    PUSH AF                                     ; Keep the low digit.
    RRCA                                        ; Move the high digit down.
    RRCA                                        ; Second rotate.
    RRCA                                        ; Third rotate.
    RRCA                                        ; The high digit is now low.
    CALL hexDigit                               ; Write it.
    POP  AF                                     ; Recover the low digit.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the low four bits of A as one uppercase hex digit.

hexDigit: ; Convert a digit to ASCII and queue it.
    AND  $0F                                    ; Keep one digit.
    ADD  A,'0'                                  ; Convert 0 to 9.
    CP   '9'+1                                  ; Is it a decimal digit?
    JR   C,hexPut                               ; Queue the digit.
    ADD  A,7                                    ; Convert 10 to 15 to A to F.

;@ROUTINE IN A OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Queue one text byte and write the buffer when it holds a full record.

hexPut: ; Queue one byte unless a write has failed.
    PUSH AF                                     ; Keep the byte.
    LD   A,(hexErr)                             ; Has a record write failed?
    OR   A                                      ; Test the status.
    JR   NZ,hexDrop                             ; Drop the byte.
    POP  AF                                     ; Recover the byte.
    LD   HL,(hexPtr)                            ; Read the buffer cursor.
    LD   (HL),A                                 ; Store the byte.
    INC  HL                                     ; Advance the cursor.
    LD   (hexPtr),HL                            ; Save the cursor.
    LD   A,(hexCnt)                             ; Count the byte.
    INC  A                                      ; One more queued byte.
    LD   (hexCnt),A                             ; Save the count.
    CP   128                                    ; Is the record full?
    RET  NZ                                     ; Not yet.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Write the full buffer as one sequential CP/M record and empty it.

hexFlush: ; Write the buffered record.
    LD   DE,srcCache                            ; Point CP/M at the buffer.
    LD   C,26                                   ; Select set-DMA function 26.
    CALL hexBdos                                ; Set the transfer address.
    LD   DE,cpFcb                               ; Select the output FCB.
    LD   C,21                                   ; Select write-sequential function 21.
    CALL hexBdos                                ; Write the record.
    OR   A                                      ; Did the write succeed?
    JR   NZ,.fail                               ; Record the failure.
    LD   HL,srcCache                            ; Restart at the first byte.
    LD   (hexPtr),HL                            ; Save the buffer cursor.
    XOR  A                                      ; The buffer is empty.
    LD   (hexCnt),A                             ; Clear the count.
    RET                                         ; Return with the record written.
.fail: ; Make the failure sticky and discard the record.
    LD   A,1                                    ; Mark the stream as failed.
    LD   (hexErr),A                             ; Later bytes are dropped.
    XOR  A                                      ; Discard the buffered text.
    LD   (hexCnt),A                             ; Stop hexClose padding.
    RET                                         ; Return the failure through hexErr.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Discard a byte queued after a failed write.

hexDrop: ; Drop the byte saved by hexPut.
    POP  AF                                     ; Discard the saved byte.
    RET                                         ; Return to hexPut's caller.

hexEofLn:   DB      ':','0','0','0','0','0','0','0','1','F','F',13,10      ; End-of-file record and CRLF.
