;@ROUTINE IN DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a dollar-terminated string through CP/M BDOS function 9.

CP_PRINT: ; Print a BDOS dollar-terminated console string.
    LD   C,CP_TEXT                                                  ; Select CP/M dollar-terminated string output.
    JP   CP_BDOS                                                    ; Print the string addressed by DE.

;@ROUTINE IN HL OUT A CLOBBERS B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the non-space characters of one drive-plus-8.3 filename record.

CP_NAME: ; Print one normalised CP/M 8.3 filename.
    INC  HL                                                         ; Skip the drive byte and point at the basename.
    LD   B,8                                                        ; Count the eight basename characters.
.BASE: ; Print nonpadding basename characters.
    LD   A,(HL)                                                     ; Read the next basename character.
    INC  HL                                                         ; Advance to the next FCB name byte.
    AND  $7F                                                        ; Remove any CP/M filename attribute bit.
    CP   ' '                                                        ; FCB padding marks an unused character position.
    CALL NZ,CP_PUTC                                                 ; Print only non-padding bytes.
    DJNZ .BASE                                                      ; Check the remaining basename positions.
    LD   A,(HL)                                                     ; Inspect the first character of the extension.
    AND  $7F                                                        ; Ignore its read-only attribute bit.
    CP   ' '                                                        ; A blank extension has no visible suffix.
    RET  Z                                                          ; Return without printing a dot for an empty type.
    LD   A,'.'                                                      ; Select the filename separator.
    CALL CP_PUTC                                                    ; Print the dot before the extension.
    LD   B,3                                                        ; Count the three extension characters.
.TYPE: ; Print nonpadding extension characters.
    LD   A,(HL)                                                     ; Read the next extension character.
    INC  HL                                                         ; Advance to the following FCB byte.
    AND  $7F                                                        ; Ignore system and archive attribute bits.
    CP   ' '                                                        ; Skip blank extension positions.
    CALL NZ,CP_PUTC                                                 ; Print a nonblank extension character.
    DJNZ .TYPE                                                      ; Check the remaining extension positions.
    RET                                                             ; Finish printing the normalised filename.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print one character while preserving the caller's working registers.

CP_PUTC: ; Print one console character with register preservation.
    PUSH BC                                                         ; Save caller's BC pair.
    PUSH DE                                                         ; Preserve the caller's DE pair.
    PUSH HL                                                         ; Preserve the caller's HL pair.
    LD   E,A                                                        ; Pass the requested character in E.
    LD   C,2                                                        ; Select CP/M console-output function 2.
    CALL CP_BDOS                                                    ; Write the character to the console.
    POP  HL                                                         ; Restore the caller's HL pair.
    POP  DE                                                         ; Restore the caller's DE pair.
    POP  BC                                                         ; Restore the caller's BC pair.
    RET                                                             ; Return after the console output attempt.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print A as two uppercase hexadecimal digits.

CP_HEX: ; Print a byte as two hexadecimal digits.
    PUSH AF                                                         ; Preserve the original byte for its low digit.
    RRCA                                                            ; Begin rotating the high nibble toward bits 0..3.
    RRCA                                                            ; Move high nibble toward bits 0..3.
    RRCA                                                            ; Rotate one more position within the byte.
    RRCA                                                            ; Place the original bits 4..7 in the low nibble.
    CALL .NIBBLE                                                    ; Print the high hexadecimal digit.
    POP  AF                                                         ; Restore original byte for low digit.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the low nibble of A as one uppercase hexadecimal digit.

.NIBBLE: ; Print the selected low hexadecimal nibble.
    AND  $0F                                                        ; Keep only the nibble selected by the caller.
    ADD  A,'0'                                                      ; Convert values 0..9 to ASCII.
    CP   '9'+1                                                      ; Separate decimal from hex letters.
    JR   C,CP_PUTC                                                  ; Send a decimal digit directly to the console.
    ADD  A,7                                                        ; Convert 10..15 to A..F.
    JR   CP_PUTC                                                    ; Print the uppercase hex digit.

;@ROUTINE IN HL OUT A CLOBBERS BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a one-based 16-bit position in decimal. A wrapped zero can only mean
; 65,536 because no source part exceeds 65,535 bytes.

CP_NUM: ; Print a one-based sixteen-bit source position.
    LD   A,H                                                        ; Test whether the counter wrapped to zero.
    OR   L                                                          ; Both bytes must be zero for 65,536.
    JR   NZ,.START                                                  ; Ordinary positions fit in 16 bits.
    LD   DE,MSG_WRAP                                                ; Select the one possible overflow value.
    JP   CP_PRINT                                                   ; Print it and return.
.START: ; Render an ordinary nonzero sixteen-bit position.
    LD   IX,CP_TENS                                                 ; Start with the ten-thousands place.
    LD   C,5                                                        ; Five places cover every 16-bit value.
    XOR  A                                                          ; No nonzero digit has been printed yet.
    LD   (CP_SEEN),A                                                ; Suppress leading zeroes.
.PLACE: ; Compute each decimal place digit.
    LD   E,(IX+0)                                                   ; Load the divisor's low byte.
    LD   D,(IX+1)                                                   ; Load the divisor's high byte.
    LD   B,0                                                        ; Count this place's decimal digit.
.SUBTRACT: ; Count the place values contained in the remainder.
    OR   A                                                          ; Clear carry before a 16-bit subtraction.
    SBC  HL,DE                                                      ; Remove one place value if it fits.
    JR   C,.DIGIT                                                   ; Borrow means the digit is complete.
    INC  B                                                          ; Count the successful subtraction.
    JR   .SUBTRACT                                                  ; Try the next unit of this place.
.DIGIT: ; Undo the borrowing subtraction and choose digit visibility.
    ADD  HL,DE                                                      ; Undo the first subtraction that borrowed.
    LD   A,B                                                        ; Inspect the computed digit.
    OR   A                                                          ; Nonzero digits begin visible output.
    JR   NZ,.EMIT                                                   ; Print the first nonzero digit.
    LD   A,(CP_SEEN)                                                ; Check whether output has begun.
    OR   A                                                          ; Later zero digits must still be printed.
    JR   NZ,.EMIT                                                   ; Preserve interior and trailing zeroes.
    LD   A,C                                                        ; Is this the units place?
    CP   1                                                          ; A number must print at least one digit.
    JR   NZ,.NEXT                                                   ; Skip only a leading zero.
.EMIT: ; Print a significant or interior decimal digit.
    LD   A,1                                                        ; Mark decimal output as started.
    LD   (CP_SEEN),A                                                ; Preserve the mark across console calls.
    LD   A,B                                                        ; Reload the digit for ASCII conversion.
    ADD  A,'0'                                                      ; Convert it to a printable numeral.
    CALL CP_PUTC                                                    ; Send the digit to the CP/M console.
.NEXT: ; Advance to the next decimal place.
    INC  IX                                                         ; Move to the next divisor's low byte.
    INC  IX                                                         ; Skip the previous divisor's high byte.
    DEC  C                                                          ; Count down the remaining decimal places.
    JR   NZ,.PLACE                                                  ; Continue through units.
    RET                                                             ; Finish the decimal position.

CP_CODEE: ; Exclusive end of resident CP/M adapter code.

; Descriptor and FCB workspace retained for the complete command. The 36-byte
; rename FCB overlays the input FCB after all source reads finish.

CP_WS1B: ; Beginning of descriptor and FCB writable storage.
CP_DESC: ; Fifteen-byte native multipart build descriptor.
    DB   1                                                          ; Initial source-part count, replaced after include resolution.
    DW   INC_DESC                                                   ; Address of the ordered five-byte source descriptors.
    DW   CP_SYMB,CP_SYME                                            ; Half-open caller symbol-arena bounds.
    DW   CP_PENDB,CP_PENDE                                          ; Half-open pending-reference arena bounds.
    DW   CP_TPA,ASO_CAP                                             ; CP/M target origin and maximum byte capacity.

PUB_FCB: ; Rename FCB overlaid after source reads finish.
SRC_FCB: ; Source file FCB before the publication phase.
    DB   0,'I','N','P','U','T',' ',' ',' ','A','S','M'              ; Initial source identity with current drive and ASM extension.
    DS   24                                                         ; Zero-initialised mutable source-FCB control fields.
CP_FCB: ; Independent working FCB for output and reserved names.
    DB   0,'O','U','T','P','U','T',' ',' ','$','$','$'              ; Initial reserved temporary output identity.
    DS   24                                                         ; Zero-initialised mutable output-FCB control fields.
PUB_NAME: ; Retained requested output drive and 8.3 identity.
    DB   0,'O','U','T','P','U','T',' ',' ','C','O','M'              ; Initial requested output identity before argument parsing.
CP_WS1E: ; Exclusive end of descriptor and FCB storage.

CP_IMMB: ; Beginning of immutable console text and selectors.
MSG_DONE:   DB      ' ','w','r','i','t','t','e','n',13,10,'$'       ; Completion suffix printed after successful publication.
MSG_READ: ; Source-open or source-read diagnostic suffix.
    DB   ' ','r','e','a','d',' ','f','a','i','l','e','d',13,10,'$'  ; Source-read failure text followed by CRLF and BDOS terminator.
MSG_CRLF:   DB      13,10,'$'                                       ; Console line break terminated for BDOS function 9.
MSG_BYTE:   DB      ':','b','y','t','e',' ','$'                     ; Prefix distinguishing a raw byte-offset fallback.
MSG_WRAP:   DB      '6','5','5','3','6','$'                         ; Decimal spelling of the wrapped position 65,536.
CP_TENS:    DW      10000,1000,100,10,1                             ; Descending decimal place values for position printing.
MSG_HELP: ; Compact command syntax for help and argument errors.
    DB   13,10,'U','s','a','g','e',':',' ','A','T','O','M',' '      ; Syntax prefix.
    DB   '[','S','O','U','R','C','E',' '                            ; Optional source.
    DB   '[','O','U','T','P','U','T',']',']',13,10,'$'              ; Optional output.
MSG_SRC: ; Invalid source-filename diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   's','o','u','r','c','e',' ','n','a','m','e',13,10,'$'      ; Source name.
MSG_OUT: ; Invalid output-filename diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   'o','u','t','p','u','t',' ','n','a','m','e',13,10,'$'      ; Output name.
MSG_DUP: ; Source and output filename-conflict diagnostic.
    DB   13,10,'S','o','u','r','c','e','/'                          ; First filename.
    DB   'o','u','t','p','u','t',' '                                ; Second filename.
    DB   'c','o','n','f','l','i','c','t',13,10,'$'                  ; Conflict suffix.
MSG_BUSY: ; Reserved work-file collision diagnostic.
    DB   " exists: erase it first",13,10,'$'                        ; Leftover work file.
MSG_INC: ; Malformed INCLUDE diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   '%','I','N','C','L','U','D','E',13,10,'$'                  ; Directive name.
BIN_KEY: ; Exact uppercase binary directive spelling.
    DB   'I','N','C','B','I','N'                                    ; Exact assembler operation token.
MSG_BIN: ; Malformed counted INCBIN diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   'I','N','C','B','I','N',13,10,'$'                          ; Native byte-count directive.
MSG_FULL: ; Native binary-include capacity diagnostic.
    DB   13,10,'T','o','o',' ','m','a','n','y',' '                  ; Error prefix.
    DB   'I','N','C','B','I','N',' ','f','i','l','e','s',13,10,'$'  ; Finish the binary-capacity message and BDOS string.
MSG_SAME: ; Binary input and output name-conflict suffix.
    DB   ' ','c','o','n','f','l','i','c','t','s',' '                ; Name collision suffix.
    DB   'w','i','t','h',' ','o','u','t','p','u','t',13,10,'$'      ; Finish the output-alias message and BDOS string.
MSG_LOAD: ; Binary payload-read failure suffix.
    DB   ' ','b','i','n','a','r','y',' ','r','e','a','d',' '        ; Input failure.
    DB   'f','a','i','l','e','d',13,10,'$'                          ; Finish the binary-read error and BDOS string.
MSG_DIR: ; Unsupported or malformed preprocessor directive diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   's','o','u','r','c','e',' '                                ; Describe the rejected construct.
    DB   'd','i','r','e','c','t','i','v','e',13,10,'$'              ; Finish the message.
MSG_LOOP: ; Include dependency-cycle diagnostic.
    DB   13,10,'I','n','c','l','u','d','e',' '                      ; Include prefix.
    DB   'c','y','c','l','e',13,10,'$'                              ; Cycle suffix.
MSG_CAP: ; Source-part capacity diagnostic.
    DB   13,10,'T','o','o',' ','m','a','n','y',' '                  ; Error prefix.
    DB   's','o','u','r','c','e','s',13,10,'$'                      ; Source count.
MSG_MEM: ; Insufficient transient-memory diagnostic.
    DB   13,10                                                      ; Start the diagnostic on a new line.
    DB   "Insufficient transient memory"                            ; Explain the fixed-layout failure.
    DB   13,10,'$'                                                  ; End the line and BDOS string.
INC_KEY:    DB      'I','N','C','L','U','D','E'                     ; Exact uppercase include directive spelling.
CMD_ASM:    DB      'A','S','M'                                     ; Default source extension.
CMD_COM:    DB      'C','O','M'                                     ; COM output extension selector.
CMD_BIN:    DB      'B','I','N'                                     ; Raw binary output extension selector.
CMD_HEX:    DB      'H','E','X'                                     ; Intel HEX output extension selector.
CMD_ASO:    DB      'A','S','O'                                     ; Serialised-operation output extension selector.
;@@ATOM_CPM_MESSAGES@@
CP_IMME: ; Exclusive end of immutable console text and selectors.
CP_WS2B: ; Beginning of scalar resident execution state.

; Small execution state. PUB_POS overlays the source-cache key;
; source reads and patches finish before COMMIT publishes the output.

PUB_POS:    DW      0                                               ; Current output-window or HEX input cursor.
SRC_KEY     EQU     PUB_POS                                         ; Alias for source-record cache key before final rendering.
; Replay may overwrite the binary FCB and metadata, so only these live abort
; and diagnostic flags remain in the low resident workspace.
BIN_RERR:   DB      0                                               ; Binary-read failure flag retained across replay overlays.
BIN_RFCB:   DB      0                                               ; Binary-FCB ownership flag retained across replay overlays.
PUB_LEFT:   DW      0                                               ; Logical bytes remaining for final output rendering.
PUB_OPEN:   DB      0                                               ; Nonzero while the final-output temporary FCB is open.
PUB_KEPT:   DB      0                                               ; Nonzero after old output moves to the backup name.
PUB_KIND:   DB      0                                               ; Output selector: zero COM, one BIN, two HEX, three ASO.
ASO_ON:     DB      0                                               ; Nonzero while operation-spool dispatch is active.
ASO_OPEN:   DB      0                                               ; Nonzero while the writer owns an open spool FCB.
MAT_OPEN:   DB      0                                               ; Nonzero while replay owns an open spool reader.
ASO_ERR:    DB      0                                               ; Sticky operation-spool failure status.
ASO_STAT:   DB      0                                               ; BDOS or validation status retained for the caller.
ASO_BANK:   DB      0                                               ; Address-space class staged for PATCH validation.
ASO_BYTE:   DB      0                                               ; Serialised byte staged during record indexing.
ASO_RLEN:   DB      0                                               ; Bytes queued in the physical output record.
ASO_PEND:   DB      0                                               ; Bytes buffered in the current IMAGE run.
ASO_BASE:   DW      0                                               ; Absolute start address of the pending IMAGE run.
ASO_IEND:   DW      0                                               ; Greatest accepted IMAGE exclusive-end low word.
ASO_ITOP:   DB      0                                               ; Nonzero when accepted IMAGE extent reaches $10000.
ASO_ORG:    DW      0                                               ; Target origin written into the ASO header.
ASO_ADDR:   DW      0                                               ; Absolute IMAGE or PATCH address being checked.
ASO_VAL:    DW      0                                               ; One-byte or little-endian word replacement value.
ASO_LEN:    DB      0                                               ; PATCH payload length of one or two bytes.
ASO_FLAG:   DB      0                                               ; Retained cursor and high-water endpoint flags.
ASO_HIGH:   DW      0                                               ; COMMIT high-water endpoint low word.
ASO_LAST:   DW      0                                               ; COMMIT final cursor low word.
ASO_STOP:   DW      0                                               ; Computed PATCH exclusive-end low word.
ASO_PTOP:   DB      0                                               ; Nonzero when a computed PATCH end is $10000.
MAT_OWNS:   DB      0                                               ; Nonzero while the reserved $$B name contains a spool.
HEX_ADDR:   DW      0                                               ; Target address for the next Intel HEX record.
HEX_PTR:    DW      0                                               ; Next free byte in the HEX transfer buffer.
HEX_CNT:    DB      0                                               ; Text bytes queued for a physical CP/M write.
HEX_ERR:    DB      0                                               ; Sticky HEX physical-record write status.
HEX_SUM:    DB      0                                               ; Checksum accumulator for one Intel HEX record.
HEX_SIZE:   DB      0                                               ; Payload length in the current Intel HEX record.
HEX_LEFT:   DB      0                                               ; Payload bytes remaining in the current HEX record.
ERR_POS:    DW      0                                               ; Zero-based source offset during diagnostic counting.
ERR_LINE:   DW      0                                               ; One-based source line or wrapped 65,536 sentinel.
ERR_COL:    DW      0                                               ; One-based byte column or wrapped 65,536 sentinel.
ERR_CR:     DB      0                                               ; Nonzero when the preceding diagnostic-count byte was CR.
CP_SEEN:    DB      0                                               ; Nonzero after decimal printing emits its first digit.
CP_WS2E: ; Exclusive end of scalar resident execution state.
HS_CEND: ; Exclusive end of output-service resident storage.
HS_REND: ; Exclusive end of host-service resident extent.
CP_REND: ; Exclusive end of the resident CP/M adapter.
;@@ATOM_CPM_ASO_OVERLAY@@
