ST_PUTS: ; Count decoded string bytes before preflight and emission.

; First pass: count decoded bytes without emitting. The tokenizer has
; validated the closing quote and token length. HL is the raw offset,
; B the raw bytes remaining and C the decoded count.

    LD   HL,(TK_REC+TK_ROFF)            ; Start at the string token's opening quote.
    INC  HL                             ; Advance to its first raw content byte.
    LD   A,(TK_REC+TK_RLEN)             ; Read the token's complete raw byte length.
    SUB  2                              ; Exclude the opening and closing quotes.
    LD   B,A                            ; Count raw content bytes remaining.
    LD   C,0                            ; Start the decoded output-byte count at zero.
.CNTLOOP: ; Count one raw character or complete escape per iteration.
    LD   A,B                            ; Test the remaining raw-byte count.
    OR   A                              ; Set Z after the final raw byte.
    JR   Z,.CNTDONE                     ; Finish the counting pass.

; Read one raw byte through the source service. Preserve the offset across
; the call because TK_SREAD returns the byte in A but may clobber HL.

    PUSH HL                             ; Save the offset across the callback.
    LD   A,(TK_REC+TK_RPART)            ; Supply the string's source-part ordinal.
    CALL TK_SREAD                       ; Read the raw byte at that logical offset.
    POP  HL                             ; Restore the current raw cursor.
    INC  HL                             ; Advance past the consumed raw byte.
    DEC  B                              ; Remove it from the remaining raw count.
    CP   $5C                            ; Was the byte a backslash escape introducer?
    JR   NZ,.TALLY                      ; No: it decodes directly to one byte.

; A backslash escape consumes at least one more raw character while still
; producing one byte. A hexadecimal escape consumes two further digits.

    PUSH HL                             ; Save the cursor across the escape read.
    LD   A,(TK_REC+TK_RPART)            ; Reuse the string's source-part ordinal.
    CALL TK_SREAD                       ; Read the character following the backslash.
    POP  HL                             ; Restore the raw cursor.
    INC  HL                             ; Advance past the escape code.
    DEC  B                              ; Remove that code from the remaining count.
    CP   $78                            ; Does this begin a hexadecimal escape, \xHH?
    JR   NZ,.TALLY                      ; Other escapes consume no more raw bytes.
    INC  HL                             ; Skip the high hexadecimal digit.
    INC  HL                             ; Skip the low hexadecimal digit.
    DEC  B                              ; Remove the high digit from the raw count.
    DEC  B                              ; Remove the low digit from the raw count.
.TALLY: ; Add one decoded byte to the string payload count.

; Count the decoded byte represented by the raw character or complete escape.

    INC  C                              ; Count one decoded output byte.
    JR   .CNTLOOP                       ; Count the remaining encoded characters.
.CNTDONE: ; Retain source position and length for the emission pass.

; Rewind to the first character and retain all source-service state needed by
; the emission pass. Quotes themselves are excluded from ST_SLEFT.

    LD   A,C                            ; Recover the decoded payload length.
    LD   (ST_SCNT),A                    ; Preserve it for capacity and PSTR prefix.
    LD   HL,(TK_REC+TK_ROFF)            ; Rewind to the opening quote.
    INC  HL                             ; Select the first raw content byte again.
    LD   (ST_SPTR),HL                   ; Initialise the emission-pass cursor.
    LD   A,(TK_REC+TK_RPART)            ; Read the string's source-part ordinal.
    LD   (ST_SPART),A                   ; Preserve it for all emission-pass reads.
    LD   A,(TK_REC+TK_RLEN)             ; Reload the complete raw token length.
    SUB  2                              ; Exclude both quote bytes again.
    LD   (ST_SLEFT),A                   ; Initialise raw bytes remaining for emission.

; Standalone strings occupy the rest of the statement. DB strings defer
; delimiter checking so the data list can continue.

    LD   A,(ST_SMODE)                   ; Test whether this is embedded DB-string mode.
    OR   A                              ; Mode zero keeps the data-list grammar active.
    JR   Z,.CAPACITY                    ; Delay delimiter handling for a DB string.
    CALL ST_TOKEN                       ; Consume a standalone string token.
    JP   C,ST_LFAIL                     ; Preserve a following tokenizer failure.
    CP   TK_EOL                         ; Standalone string must finish the line.
    JP   NZ,ST_DTAIL                    ; Reject any trailing token.
.CAPACITY: ; Calculate capacity for the selected string representation.

; Capacity is decoded payload length plus one byte for CSTR's terminator or
; PSTR's prefix. ISTR and a DB string need no extra byte.

    LD   A,(ST_SCNT)                    ; Load the decoded payload length.
    LD   L,A                            ; Place it in the low byte of capacity HL.
    LD   H,0                            ; Zero-extend the capacity request.
    LD   A,(ST_SMODE)                   ; Inspect the selected string representation.
    CP   1                              ; Does CSTR need a terminating zero?
    JR   Z,.EXTRA                       ; Yes: reserve one extra byte.
    CP   2                              ; Does PSTR need a length prefix?
    JR   NZ,.CHKCAP                     ; No: payload capacity alone is sufficient.
.EXTRA: ; Include CSTR's terminator or PSTR's prefix in capacity.
    INC  HL                             ; Include the terminator or prefix byte.
.CHKCAP: ; Check the entire decoded string before any output submission.
    CALL OU_CAPOK                       ; Preflight the complete string output.
    JP   C,ST_OFAIL                     ; Fail before publishing any prefix or payload.

; PSTR writes its one-byte decoded length before the payload.

    LD   A,(ST_SMODE)                   ; Test for length-prefixed representation.
    CP   2                              ; Is this PSTR mode?
    JR   NZ,.EMITLOOP                   ; No: begin directly with payload bytes.
    LD   A,(ST_SCNT)                    ; Select the decoded one-byte length.
    CALL OU_EMITB                       ; Emit it before the payload.
    JP   C,ST_OFAIL                     ; Preserve an unexpected sink failure.
.EMITLOOP: ; Decode and emit the next string payload byte.

; Emit decoded characters until every raw byte inside the quotes is consumed.

    LD   A,(ST_SLEFT)                   ; Read raw bytes remaining in the quoted token.
    OR   A                              ; Have all raw bytes been consumed?
    JR   Z,.STRDONE                     ; Yes: finish according to the string mode.
    CALL ST_TAKE                        ; Consume one raw source byte.
    CP   $5C                            ; Does it introduce an escape sequence?
    JR   NZ,.PUTBYTE                    ; No: emit the byte literally.

; Translate a standard one-character escape through the tokenizer's escape
; table, except \x which has its own two-hex-digit path.

    CALL ST_TAKE                        ; Consume the escape-code character.
    CP   $78                            ; Is it the hexadecimal escape marker x?
    JR   Z,.HEXESC                      ; Yes: decode the following two digits.
    CALL TK_UNESC                       ; Translate a standard one-character escape.
    JP   C,ST_DSTR                      ; Defensively reject an unknown escape code.
    JR   .PUTBYTE                       ; Emit the translated byte.
.HEXESC: ; Decode the two nibbles following a hexadecimal escape.

; Form one byte from the high and low hexadecimal nibbles. TK_HEX signals a
; valid digit with carry set, hence the deliberately inverted-looking tests.

    CALL ST_TAKE                        ; Consume the high hexadecimal digit.
    CALL TK_HEX                         ; Convert it to a nibble.
    JP   NC,ST_DSTR                     ; Reject a non-hexadecimal character.
    ADD  A,A                            ; Shift the nibble left one bit.
    ADD  A,A                            ; Shift it left two bits total.
    ADD  A,A                            ; Shift it left three bits total.
    ADD  A,A                            ; Place it in the output byte's high nibble.
    LD   (ST_HEXHI),A                   ; Preserve the shifted high nibble.
    CALL ST_TAKE                        ; Consume the low hexadecimal digit.
    CALL TK_HEX                         ; Convert it to a nibble.
    JP   NC,ST_DSTR                     ; Reject a non-hexadecimal character.
    LD   HL,ST_HEXHI                    ; Address the saved high nibble.
    OR   (HL)                           ; Combine both nibbles into the decoded byte.
.PUTBYTE: ; Apply the final-byte ISTR bit before emission.

; ISTR sets bit 7 on its final decoded byte. ST_SLEFT counts raw bytes.
; after ST_TAKE finishes a character or escape, zero therefore identifies the
; final output character.

    LD   C,A                            ; Preserve the decoded byte during mode checks.
    LD   A,(ST_SMODE)                   ; Read the active string representation.
    CP   3                              ; Is this high-bit-terminated ISTR mode?
    LD   A,C                            ; Restore the byte without changing flags.
    JR   NZ,.PUBLISH                    ; Other modes emit it unchanged.
    LD   HL,ST_SLEFT                    ; Address the raw-byte countdown.
    LD   A,(HL)                         ; Read the remaining raw-byte count.
    OR   A                              ; Is this the last decoded character?
    LD   A,C                            ; Restore the decoded byte while retaining Z.
    JR   NZ,.PUBLISH                    ; Not last: leave bit 7 untouched.
    OR   $80                            ; Last: mark the ISTR terminator bit.
.PUBLISH: ; Submit the selected payload byte through the output sink.
    CALL OU_EMITB                       ; Publish the decoded payload byte.
    JP   C,ST_OFAIL                     ; Preserve any sink failure.
    JR   .EMITLOOP                      ; Continue until raw content is exhausted.
.STRDONE: ; Complete the representation or resume an inline DB list.

; DB mode returns to its comma/EOL grammar. CSTR appends a zero terminator.
; PSTR and ISTR are already complete and advance directly to the next line.

    LD   A,(ST_SMODE)                   ; Select completion behaviour by string format.
    OR   A                              ; Is this an inline DB string?
    JR   Z,.DBDONE                      ; Yes: check the data-list delimiter.
    CP   1                              ; Is this zero-terminated CSTR mode?
    JP   NZ,ST_NEXT                     ; PSTR and ISTR are already complete.
    XOR  A                              ; Form CSTR's trailing zero byte.
    CALL OU_EMITB                       ; Publish the terminator reserved by preflight.
    JP   ST_OUTOK                       ; Check output status and continue.
.DBDONE: ; Consume a DB string token and inspect its list delimiter.
    CALL TK_NEXT                        ; Consume the DB string token.
    JP   C,ST_LFAIL                     ; Preserve a following tokenizer failure.
    JP   ST_DMORE                       ; Require comma or end-of-line next.
ST_CMODE: ; Select a zero-terminated standalone string.

; String modes: 1 = zero-terminated, 2 = length-prefixed, 3 = high-bit final.

    LD   A,1                            ; Select zero-terminated CSTR representation.
    JR   ST_ALONE                       ; Share standalone string validation.
ST_PMODE: ; Select a length-prefixed standalone string.
    LD   A,2                            ; Select length-prefixed PSTR representation.
    JR   ST_ALONE                       ; Share standalone string validation.
ST_IMODE: ; Select a standalone string with a high-bit final byte.
    LD   A,3                            ; Select high-bit-terminated ISTR.
ST_ALONE: ; Require one quoted token for the selected standalone format.
    LD   (ST_SMODE),A                   ; Retain the string mode for emission.

; Standalone string directives accept exactly one quoted-string token.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the directive's sole argument token.
    CP   TK_STR                         ; Is it a validated quoted string?
    JP   NZ,ST_DSTR                     ; Reject expressions and other token classes.
    JP   ST_PUTS                        ; Count, preflight and emit it.
