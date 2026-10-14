stPuts: ; Count decoded string bytes before preflight and emission.

; First pass: count decoded bytes without emitting. The tokenizer has
; validated the closing quote and token length. HL is the raw offset,
; B the raw bytes remaining and C the decoded count.

    LD   HL,(tkRecord+tkOffAt)          ; Start at the string token's opening quote.
    INC  HL                             ; Advance to its first raw content byte.
    LD   A,(tkRecord+tkLenAt)           ; Read the token's complete raw byte length.
    SUB  2                              ; Exclude the opening and closing quotes.
    LD   B,A                            ; Count raw content bytes remaining.
    LD   C,0                            ; Start the decoded output-byte count at zero.
.cntLoop: ; Count one raw character or complete escape per iteration.
    LD   A,B                            ; Test the remaining raw-byte count.
    OR   A                              ; Set Z after the final raw byte.
    JR   Z,.cntDone                     ; Finish the counting pass.

; Read one raw byte through the source service. Preserve the offset across
; the call because tkRead returns the byte in A but may clobber HL.

    PUSH HL                             ; Save the offset across the callback.
    LD   A,(tkRecord+tkPartAt)          ; Supply the string's source-part ordinal.
    CALL tkRead                         ; Read the raw byte at that logical offset.
    POP  HL                             ; Restore the current raw cursor.
    INC  HL                             ; Advance past the consumed raw byte.
    DEC  B                              ; Remove it from the remaining raw count.
    CP   $5C                            ; Was the byte a backslash escape introducer?
    JR   NZ,.tally                      ; No: it decodes directly to one byte.

; A backslash escape consumes at least one more raw character while still
; producing one byte. A hexadecimal escape consumes two further digits.

    PUSH HL                             ; Save the cursor across the escape read.
    LD   A,(tkRecord+tkPartAt)          ; Reuse the string's source-part ordinal.
    CALL tkRead                         ; Read the character following the backslash.
    POP  HL                             ; Restore the raw cursor.
    INC  HL                             ; Advance past the escape code.
    DEC  B                              ; Remove that code from the remaining count.
    CP   $78                            ; Does this begin a hexadecimal escape, \xHH?
    JR   NZ,.tally                      ; Other escapes consume no more raw bytes.
    INC  HL                             ; Skip the high hexadecimal digit.
    INC  HL                             ; Skip the low hexadecimal digit.
    DEC  B                              ; Remove the high digit from the raw count.
    DEC  B                              ; Remove the low digit from the raw count.
.tally: ; Add one decoded byte to the string payload count.

; Count the decoded byte represented by the raw character or complete escape.

    INC  C                              ; Count one decoded output byte.
    JR   .cntLoop                       ; Count the remaining encoded characters.
.cntDone: ; Retain source position and length for the emission pass.

; Rewind to the first character and retain all source-service state needed by
; the emission pass. Quotes themselves are excluded from stStrLen.

    LD   A,C                            ; Recover the decoded payload length.
    LD   (stStrCnt),A                   ; Preserve it for capacity and PSTR prefix.
    LD   HL,(tkRecord+tkOffAt)          ; Rewind to the opening quote.
    INC  HL                             ; Select the first raw content byte again.
    LD   (stStrPtr),HL                  ; Initialise the emission-pass cursor.
    LD   A,(tkRecord+tkPartAt)          ; Read the string's source-part ordinal.
    LD   (stStrSrc),A                   ; Preserve it for all emission-pass reads.
    LD   A,(tkRecord+tkLenAt)           ; Reload the complete raw token length.
    SUB  2                              ; Exclude both quote bytes again.
    LD   (stStrLen),A                   ; Initialise raw bytes remaining for emission.

; Standalone strings occupy the rest of the statement. DB strings defer
; delimiter checking so the data list can continue.

    LD   A,(stStrFmt)                   ; Test whether this is embedded DB-string mode.
    OR   A                              ; Mode zero keeps the data-list grammar active.
    JR   Z,.capacity                    ; Delay delimiter handling for a DB string.
    CALL stToken                        ; Consume a standalone string token.
    JP   C,stLexErr                     ; Preserve a following tokenizer failure.
    CP   tkEol                          ; Standalone string must finish the line.
    JP   NZ,stExtra                     ; Reject any trailing token.
.capacity: ; Calculate capacity for the selected string representation.

; Capacity is decoded payload length plus one byte for CSTR's terminator or
; PSTR's prefix. ISTR and a DB string need no extra byte.

    LD   A,(stStrCnt)                   ; Load the decoded payload length.
    LD   L,A                            ; Place it in the low byte of capacity HL.
    LD   H,0                            ; Zero-extend the capacity request.
    LD   A,(stStrFmt)                   ; Inspect the selected string representation.
    CP   1                              ; Does CSTR need a terminating zero?
    JR   Z,.extra                       ; Yes: reserve one extra byte.
    CP   2                              ; Does PSTR need a length prefix?
    JR   NZ,.checkCap                   ; No: payload capacity alone is sufficient.
.extra: ; Include CSTR's terminator or PSTR's prefix in capacity.
    INC  HL                             ; Include the terminator or prefix byte.
.checkCap: ; Check the entire decoded string before any output submission.
    CALL outCapOk                       ; Preflight the complete string output.
    JP   C,stOutErr                     ; Fail before publishing any prefix or payload.

; PSTR writes its one-byte decoded length before the payload.

    LD   A,(stStrFmt)                   ; Test for length-prefixed representation.
    CP   2                              ; Is this PSTR mode?
    JR   NZ,.emitLoop                   ; No: begin directly with payload bytes.
    LD   A,(stStrCnt)                   ; Select the decoded one-byte length.
    CALL outEmitB                       ; Emit it before the payload.
    JP   C,stOutErr                     ; Preserve an unexpected sink failure.
.emitLoop: ; Decode and emit the next string payload byte.

; Emit decoded characters until every raw byte inside the quotes is consumed.

    LD   A,(stStrLen)                   ; Read raw bytes remaining in the quoted token.
    OR   A                              ; Have all raw bytes been consumed?
    JR   Z,.strDone                     ; Yes: finish according to the string mode.
    CALL stTake                         ; Consume one raw source byte.
    CP   $5C                            ; Does it introduce an escape sequence?
    JR   NZ,.putByte                    ; No: emit the byte literally.

; Translate a standard one-character escape through the tokenizer's escape
; table, except \x which has its own two-hex-digit path.

    CALL stTake                         ; Consume the escape-code character.
    CP   $78                            ; Is it the hexadecimal escape marker x?
    JR   Z,.hexEsc                      ; Yes: decode the following two digits.
    CALL tkUnEsc                        ; Translate a standard one-character escape.
    JP   C,stStrErr                     ; Defensively reject an unknown escape code.
    JR   .putByte                       ; Emit the translated byte.
.hexEsc: ; Decode the two nibbles following a hexadecimal escape.

; Form one byte from the high and low hexadecimal nibbles. tkNibble signals a
; valid digit with carry set, hence the deliberately inverted-looking tests.

    CALL stTake                         ; Consume the high hexadecimal digit.
    CALL tkNibble                       ; Convert it to a nibble.
    JP   NC,stStrErr                    ; Reject a non-hexadecimal character.
    ADD  A,A                            ; Shift the nibble left one bit.
    ADD  A,A                            ; Shift it left two bits total.
    ADD  A,A                            ; Shift it left three bits total.
    ADD  A,A                            ; Place it in the output byte's high nibble.
    LD   (stHexHi),A                    ; Preserve the shifted high nibble.
    CALL stTake                         ; Consume the low hexadecimal digit.
    CALL tkNibble                       ; Convert it to a nibble.
    JP   NC,stStrErr                    ; Reject a non-hexadecimal character.
    LD   HL,stHexHi                     ; Address the saved high nibble.
    OR   (HL)                           ; Combine both nibbles into the decoded byte.
.putByte: ; Apply the final-byte ISTR bit before emission.

; ISTR sets bit 7 on its final decoded byte. stStrLen counts raw bytes.
; after stTake finishes a character or escape, zero therefore identifies the
; final output character.

    LD   C,A                            ; Preserve the decoded byte during mode checks.
    LD   A,(stStrFmt)                   ; Read the active string representation.
    CP   3                              ; Is this high-bit-terminated ISTR mode?
    LD   A,C                            ; Restore the byte without changing flags.
    JR   NZ,.publish                    ; Other modes emit it unchanged.
    LD   HL,stStrLen                    ; Address the raw-byte countdown.
    LD   A,(HL)                         ; Read the remaining raw-byte count.
    OR   A                              ; Is this the last decoded character?
    LD   A,C                            ; Restore the decoded byte while retaining Z.
    JR   NZ,.publish                    ; Not last: leave bit 7 untouched.
    OR   $80                            ; Last: mark the ISTR terminator bit.
.publish: ; Submit the selected payload byte through the output sink.
    CALL outEmitB                       ; Publish the decoded payload byte.
    JP   C,stOutErr                     ; Preserve any sink failure.
    JR   .emitLoop                      ; Continue until raw content is exhausted.
.strDone: ; Complete the representation or resume an inline DB list.

; DB mode returns to its comma/EOL grammar. CSTR appends a zero terminator.
; PSTR and ISTR are already complete and advance directly to the next line.

    LD   A,(stStrFmt)                   ; Select completion behaviour by string format.
    OR   A                              ; Is this an inline DB string?
    JR   Z,.dbDone                      ; Yes: check the data-list delimiter.
    CP   1                              ; Is this zero-terminated CSTR mode?
    JP   NZ,stNext                      ; PSTR and ISTR are already complete.
    XOR  A                              ; Form CSTR's trailing zero byte.
    CALL outEmitB                       ; Publish the terminator reserved by preflight.
    JP   stOutOk                        ; Check output status and continue.
.dbDone: ; Consume a DB string token and inspect its list delimiter.
    CALL tkNext                         ; Consume the DB string token.
    JP   C,stLexErr                     ; Preserve a following tokenizer failure.
    JP   stMore                         ; Require comma or end-of-line next.
stCMode: ; Select a zero-terminated standalone string.

; String modes: 1 = zero-terminated, 2 = length-prefixed, 3 = high-bit final.

    LD   A,1                            ; Select zero-terminated CSTR representation.
    JR   stAlone                        ; Share standalone string validation.
stPMode: ; Select a length-prefixed standalone string.
    LD   A,2                            ; Select length-prefixed PSTR representation.
    JR   stAlone                        ; Share standalone string validation.
stIMode: ; Select a standalone string with a high-bit final byte.
    LD   A,3                            ; Select high-bit-terminated ISTR.
stAlone: ; Require one quoted token for the selected standalone format.
    LD   (stStrFmt),A                   ; Retain the string mode for emission.

; Standalone string directives accept exactly one quoted-string token.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the directive's sole argument token.
    CP   tkStr                          ; Is it a validated quoted string?
    JP   NZ,stStrErr                    ; Reject expressions and other token classes.
    JP   stPuts                         ; Count, preflight and emit it.
