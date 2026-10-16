; Console output: strings, filenames, characters and numbers.

;@ROUTINE IN DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a dollar-terminated string through CP/M BDOS function 9.

cpPrint: ; Print a BDOS dollar-terminated console string.
    LD   C,cpText                                                   ; Select CP/M dollar-terminated string output.
    JP   cpBdos                                                     ; Print the string addressed by DE.

;@ROUTINE IN HL OUT A CLOBBERS B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the non-space characters of one drive-plus-8.3 filename record.

cpPutFcb: ; Print one normalised CP/M 8.3 filename.
    INC  HL                                                         ; Skip the drive byte and point at the basename.
    LD   B,8                                                        ; Count the eight basename characters.
.base: ; Print nonpadding basename characters.
    LD   A,(HL)                                                     ; Read the next basename character.
    INC  HL                                                         ; Advance to the next FCB name byte.
    AND  $7F                                                        ; Remove any CP/M filename attribute bit.
    CP   ' '                                                        ; FCB padding marks an unused character position.
    CALL NZ,cpPutCh                                                 ; Print only non-padding bytes.
    DJNZ .base                                                      ; Check the remaining basename positions.
    LD   A,(HL)                                                     ; Inspect the first character of the extension.
    AND  $7F                                                        ; Ignore its read-only attribute bit.
    CP   ' '                                                        ; A blank extension has no visible suffix.
    RET  Z                                                          ; Return without printing a dot for an empty type.
    LD   A,'.'                                                      ; Select the filename separator.
    CALL cpPutCh                                                    ; Print the dot before the extension.
    LD   B,3                                                        ; Count the three extension characters.
.type: ; Print nonpadding extension characters.
    LD   A,(HL)                                                     ; Read the next extension character.
    INC  HL                                                         ; Advance to the following FCB byte.
    AND  $7F                                                        ; Ignore system and archive attribute bits.
    CP   ' '                                                        ; Skip blank extension positions.
    CALL NZ,cpPutCh                                                 ; Print a nonblank extension character.
    DJNZ .type                                                      ; Check the remaining extension positions.
    RET                                                             ; Finish printing the normalised filename.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print one character while preserving the caller's working registers.

cpPutCh: ; Print one console character with register preservation.
    PUSH BC                                                         ; Save caller's BC pair.
    PUSH DE                                                         ; Preserve the caller's DE pair.
    PUSH HL                                                         ; Preserve the caller's HL pair.
    LD   E,A                                                        ; Pass the requested character in E.
    LD   D,A                                                        ; Function 2 ignores D. Define it anyway.
    LD   C,2                                                        ; Select CP/M console-output function 2.
    CALL cpBdos                                                     ; Write the character to the console.
    POP  HL                                                         ; Restore the caller's HL pair.
    POP  DE                                                         ; Restore the caller's DE pair.
    POP  BC                                                         ; Restore the caller's BC pair.
    RET                                                             ; Return after the console output attempt.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print A as two uppercase hexadecimal digits.

cpPutHex: ; Print a byte as two hexadecimal digits.
    PUSH AF                                                         ; Preserve the original byte for its low digit.
    RRCA                                                            ; Begin rotating the high nibble toward bits 0..3.
    RRCA                                                            ; Move high nibble toward bits 0..3.
    RRCA                                                            ; Rotate one more position within the byte.
    RRCA                                                            ; Place the original bits 4..7 in the low nibble.
    CALL .nibble                                                    ; Print the high hexadecimal digit.
    POP  AF                                                         ; Restore original byte for low digit.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the low nibble of A as one uppercase hexadecimal digit.

.nibble: ; Print the selected low hexadecimal nibble.
    AND  $0F                                                        ; Keep only the nibble selected by the caller.
    ADD  A,'0'                                                      ; Convert values 0..9 to ASCII.
    CP   '9'+1                                                      ; Separate decimal from hex letters.
    JR   C,cpPutCh                                                  ; Send a decimal digit directly to the console.
    ADD  A,7                                                        ; Convert 10..15 to A..F.
    JR   cpPutCh                                                    ; Print the uppercase hex digit.

;@ROUTINE IN HL OUT A CLOBBERS BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a one-based 16-bit position in decimal. A wrapped zero can only mean
; 65,536 because no source part exceeds 65,535 bytes.

cpPutNum: ; Print a one-based sixteen-bit source position.
    LD   A,H                                                        ; Test whether the counter wrapped to zero.
    OR   L                                                          ; Both bytes must be zero for 65,536.
    JR   NZ,.start                                                  ; Ordinary positions fit in 16 bits.
    LD   DE,msgWrap                                                 ; Select the one possible overflow value.
    JP   cpPrint                                                    ; Print it and return.
.start: ; Render an ordinary nonzero sixteen-bit position.
    LD   IX,cpTens                                                  ; Start with the ten-thousands place.
    LD   C,5                                                        ; Five places cover every 16-bit value.
    XOR  A                                                          ; No nonzero digit has been printed yet.
    LD   (cpSeen),A                                                 ; Suppress leading zeroes.
.place: ; Compute each decimal place digit.
    LD   E,(IX+0)                                                   ; Load the divisor's low byte.
    LD   D,(IX+1)                                                   ; Load the divisor's high byte.
    LD   B,0                                                        ; Count this place's decimal digit.
.subtract: ; Count the place values contained in the remainder.
    OR   A                                                          ; Clear carry before a 16-bit subtraction.
    SBC  HL,DE                                                      ; Remove one place value if it fits.
    JR   C,.digit                                                   ; Borrow means the digit is complete.
    INC  B                                                          ; Count the successful subtraction.
    JR   .subtract                                                  ; Try the next unit of this place.
.digit: ; Undo the borrowing subtraction and choose digit visibility.
    ADD  HL,DE                                                      ; Undo the first subtraction that borrowed.
    LD   A,B                                                        ; Inspect the computed digit.
    OR   A                                                          ; Nonzero digits begin visible output.
    JR   NZ,.emit                                                   ; Print the first nonzero digit.
    LD   A,(cpSeen)                                                 ; Check whether output has begun.
    OR   A                                                          ; Later zero digits must still be printed.
    JR   NZ,.emit                                                   ; Preserve interior and trailing zeroes.
    LD   A,C                                                        ; Is this the units place?
    CP   1                                                          ; A number must print at least one digit.
    JR   NZ,.next                                                   ; Skip only a leading zero.
.emit: ; Print a significant or interior decimal digit.
    LD   A,1                                                        ; Mark decimal output as started.
    LD   (cpSeen),A                                                 ; Preserve the mark across console calls.
    LD   A,B                                                        ; Reload the digit for ASCII conversion.
    ADD  A,'0'                                                      ; Convert it to a printable numeral.
    CALL cpPutCh                                                    ; Send the digit to the CP/M console.
.next: ; Advance to the next decimal place.
    INC  IX                                                         ; Move to the next divisor's low byte.
    INC  IX                                                         ; Skip the previous divisor's high byte.
    DEC  C                                                          ; Count down the remaining decimal places.
    JR   NZ,.place                                                  ; Continue through units.
    RET                                                             ; Finish the decimal position.

cpEnd: ; Exclusive end of resident CP/M adapter code.
