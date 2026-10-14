; Diagnostics: locate a failure in its source file and print the message.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Map Atom's source ordinal to the retained CP/M filename, then reread only
; the bytes before the failing position. If the file cannot be read, keep the
; original byte offset instead of printing a guessed line or column.

errWhere: ; Render source filename, line and byte column.
    LD   A,(stAtPart)                           ; Select the failed dependency-order part.
    LD   HL,cpDesc                              ; Read the count of valid part ordinals.
    CP   (HL)                                   ; Reject an impossible ordinal defensively.
    JR   NC,.badPart                            ; Retain the original numeric diagnostic.
    LD   E,A                                    ; Index the dependency-order table.
    LD   D,incOrder/256                         ; The table occupies one fixed page.
    LD   A,(DE)                                 ; Recover the retained-name ordinal.
    CALL srcOpen                                ; Reopen its source for position counting.
    JR   C,.noOpen                              ; Its name was printed. retain the offset.
    CALL errCount                               ; Convert the byte offset in this file.
    JR   C,.unread                              ; Report the raw offset on a read failure.
    LD   HL,srcFcb                              ; Address the reopened file's 8.3 name.
    CALL cpPutFcb                               ; Print the physical source filename.
    LD   A,':'                                  ; Separate filename from line number.
    CALL cpPutCh                                ; Print the first colon.
    LD   HL,(errLine)                           ; Load the one-based source line.
    CALL cpPutNum                               ; Print it without leading zeroes.
    LD   A,':'                                  ; Separate line from source column.
    CALL cpPutCh                                ; Print the second colon.
    LD   HL,(errCol)                            ; Load the one-based byte column.
    JP   cpPutNum                               ; Finish the location and return.
.unread: ; Use the filename when position counting failed.
    LD   HL,srcFcb                              ; The filename remains in the opened FCB.
    CALL cpPutFcb                               ; Identify the unreadable source part.
.noOpen: ; Print the raw-offset fallback prefix.
    LD   DE,msgByte                             ; Mark the fallback as a byte offset.
    CALL cpPrint                                ; Never confuse it with line and column.
    JR   .offset                                ; Print the unchanged hexadecimal offset.
.badPart: ; Print an invalid part ordinal numerically.
    LD   A,(stAtPart)                           ; Recover the impossible source ordinal.
    CALL cpPutHex                               ; Preserve its two-digit hexadecimal form.
    LD   A,' '                                  ; Separate ordinal from byte offset.
    CALL cpPutCh                                ; Print the separator.
.offset: ; Print the unchanged hexadecimal source offset.
    LD   HL,(stAtOff)                           ; Recover Atom's original byte offset.
    PUSH HL                                     ; Save it across printing its high byte.
    LD   A,H                                    ; Select the high byte first.
    CALL cpPutHex                               ; Emit two hexadecimal digits.
    POP  HL                                     ; Restore the offset's low byte.
    LD   A,L                                    ; Select its remaining byte.
    JP   cpPutHex                               ; Finish the four-digit offset and return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Count physical line breaks and byte columns before the reported offset.
; CRLF is one break. lone CR and lone LF are each one break. Counters start
; at one, and zero represents the sole possible overflow value, 65,536.

errCount: ; Count physical lines up to the diagnostic offset.
    LD   HL,1                                   ; Both positions are one-based.
    LD   (errLine),HL                           ; Begin on the first source line.
    LD   (errCol),HL                            ; Begin at its first byte column.
    LD   HL,0                                   ; Scan from the first source byte.
    LD   (errPos),HL                            ; Store the current zero-based offset.
    XOR  A                                      ; No preceding byte was CR.
    LD   (errSawCr),A                           ; Clear the CRLF state.
.loop: ; Consume bytes before the failing position.
    LD   HL,(errPos)                            ; Read the next byte offset.
    LD   DE,(stAtOff)                           ; Read the failing offset as an exclusive end.
    OR   A                                      ; Clear carry before comparing positions.
    SBC  HL,DE                                  ; Stop before consuming the failing byte.
    JR   Z,.done                                ; The counters now describe that byte.
    LD   HL,(errPos)                            ; Address the current source byte.
    CALL srcRaw                                 ; Read it through the existing CP/M cache.
    RET  C                                      ; Changed or unreadable input needs a fallback.
    LD   B,A                                    ; Preserve the byte across cursor update.
    LD   HL,(errPos)                            ; Advance by exactly one source byte.
    INC  HL                                     ; Move to the following zero-based offset.
    LD   (errPos),HL                            ; Save the advanced cursor.
    LD   A,B                                    ; Classify the byte just consumed.
    CP   13                                     ; A carriage return always starts a new line.
    JR   Z,.cr                                  ; Retain CR state for an optional following LF.
    CP   10                                     ; A lone line feed also starts a new line.
    JR   Z,.lf                                  ; Avoid double-counting CRLF.
    XOR  A                                      ; Ordinary text ends CRLF lookbehind.
    LD   (errSawCr),A                           ; The preceding byte is not CR.
    LD   HL,(errCol)                            ; Move one byte to the right.
    INC  HL                                     ; Advance the one-based column.
    LD   (errCol),HL                            ; Keep its full 16-bit value.
    JR   .loop                                  ; Continue toward the error offset.
.cr: ; Count CR and retain CRLF state.
    LD   A,1                                    ; Record a preceding CR.
    LD   (errSawCr),A                           ; The next LF belongs to this break.
    CALL .newLine                               ; Start the next line at column one.
    JR   .loop                                  ; Continue after the CR byte.
.lf: ; Count LF only when a preceding CR did not.
    LD   A,(errSawCr)                           ; Check whether CR already advanced the line.
    OR   A                                      ; Z means this LF is a lone break.
    CALL Z,.newLine                             ; Count a lone LF exactly once.
    XOR  A                                      ; The lookbehind ends at this LF.
    LD   (errSawCr),A                           ; Clear it before another source byte.
    JR   .loop                                  ; Continue after the LF byte.
.done: ; Return the computed line and column.
    OR   A                                      ; Return success with carry clear.
    RET                                         ; Leave the computed line and column in RAM.

;@ROUTINE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Advance to a physical source line and reset its byte column.

.newLine: ; Start a new source line at column one.
    LD   HL,(errLine)                           ; Load the current line number.
    INC  HL                                     ; Move to the next line.
    LD   (errLine),HL                           ; Keep the complete 16-bit result.
    LD   HL,1                                   ; The first byte has column one.
    LD   (errCol),HL                            ; Reset the column for that line.
    RET                                         ; Return to the source-byte classifier.

;@ROUTINE OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the ": " that separates a location from its message.

errSep: ; Print the separator after a source location.
    LD   A,':'                                  ; End the location field.
    CALL cpPutCh                                ; Print the colon.
    LD   A,' '                                  ; Leave one space before the message.
    JP   cpPutCh                                ; Print it and return.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the line of the related location in drAtPart/drAtOff, such as the
; label a failed forward jump refers to. Print ? when there is none.

errRelLn: ; Print a related source line while preserving the primary offset.
    LD   A,(drAtPart)                           ; Select the related source part.
    LD   HL,cpDesc                              ; Read the count of valid part ordinals.
    CP   (HL)                                   ; $FF and impossible ordinals both fail.
    JR   NC,.unknown                            ; No related location was recorded.
    LD   HL,(stAtOff)                           ; errCount counts up to stAtOff.
    PUSH HL                                     ; Keep the primary offset.
    LD   HL,(drAtOff)                           ; Count up to the related offset instead.
    LD   (stAtOff),HL                           ; Install it for errCount.
    LD   E,A                                    ; Index the dependency-order table.
    LD   D,incOrder/256                         ; The table occupies one fixed page.
    LD   A,(DE)                                 ; Recover the retained-name ordinal.
    CALL srcOpen                                ; Reopen that source file.
    JR   C,.restore                             ; Fall back to ? if it cannot be read.
    CALL errCount                               ; Find the related line.
    JR   C,.restore                             ; Fall back to ? on a read failure.
    LD   HL,(errLine)                           ; Load the related line number.
    CALL cpPutNum                               ; Print it.
    POP  HL                                     ; Recover the primary offset.
    LD   (stAtOff),HL                           ; Restore it.
    RET                                         ; The related line is printed.
.restore: ; Restore the primary diagnostic offset after failed counting.
    POP  HL                                     ; Recover the primary offset.
    LD   (stAtOff),HL                           ; Restore it.
.unknown: ; Print the unknown-related-line marker.
    LD   A,'?'                                  ; Show that the line is unknown.
    JP   cpPutCh                                ; Print it and return.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print message number A from cpmsg.asm. Bytes 1, 2 and 3 in the sentence
; print the symbol in drSym, the value in drVal and the related line.

cpDiag: ; Look up and render one core diagnostic.
    CP   msgNum                                 ; Is it a known message number?
    JR   C,.known                               ; Yes: look it up.
    XOR  A                                      ; No: use the internal-error message.
.known: ; Read the sentence index for a valid message number.
    LD   E,A                                    ; Index msgIdx by message number.
    LD   D,0                                    ; Widen the index.
    LD   HL,msgIdx                              ; Address the sentence index.
    ADD  HL,DE                                  ; Address this message's entry.
    LD   B,(HL)                                 ; Load its sentence number.
    LD   HL,msgText                             ; Start at the first sentence.
    INC  B                                      ; Count sentences from one.
.skip: ; Skip preceding zero-terminated sentences.
    DEC  B                                      ; Have we reached the sentence?
    JR   Z,.print                               ; Yes: print it.
.skipCh: ; Consume bytes of a preceding sentence.
    LD   A,(HL)                                 ; Read a byte of an earlier sentence.
    INC  HL                                     ; Step past it.
    OR   A                                      ; Zero ends that sentence.
    JR   NZ,.skipCh                             ; Keep skipping its text.
    JR   .skip                                  ; Count the sentence just skipped.
.print: ; Print the selected sentence and substitutions.
    LD   A,(HL)                                 ; Read the next byte of the sentence.
    INC  HL                                     ; Step past it.
    OR   A                                      ; Zero ends the sentence.
    RET  Z                                      ; The message is complete.
    PUSH HL                                     ; Keep the sentence position.
    CP   4                                      ; Bytes 1 to 3 stand for arguments.
    JR   NC,.char                               ; Anything else is printed as text.
    CALL .arg                                   ; Print the argument.
    JR   .next                                  ; Continue with the sentence.
.char: ; Print an ordinary diagnostic character.
    CALL cpPutCh                                ; Print one character of text.
.next: ; Resume the retained sentence position.
    POP  HL                                     ; Recover the sentence position.
    JR   .print                                 ; Print the next byte.
.arg: ; Dispatch symbol, signed-value or related-line substitution.
    DEC  A                                      ; 1 selects the symbol name.
    JP   Z,cpPutSym                             ; Print it.
    DEC  A                                      ; 2 selects the signed value.
    JP   Z,cpPutInt                             ; Print it.
    JP   errRelLn                               ; 3 selects the related line.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the signed sixteen-bit value in drVal in decimal.

cpPutInt: ; Print the signed diagnostic value in decimal.
    LD   HL,(drVal)                             ; Load the value.
    BIT  7,H                                    ; Is it negative?
    JP   Z,cpPutNum                             ; No: print it as it is.
    LD   A,'-'                                  ; Print the minus sign first.
    CALL cpPutCh                                ; cpPutCh preserves HL.
    LD   A,L                                    ; Negate HL: complement the low byte.
    CPL                                         ; Invert every low bit.
    LD   L,A                                    ; Store the inverted low byte.
    LD   A,H                                    ; Complement the high byte too.
    CPL                                         ; Invert every high bit.
    LD   H,A                                    ; Store the inverted high byte.
    INC  HL                                     ; Add one to finish the two's complement.
    JP   cpPutNum                               ; Print the magnitude.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the name of the symbol record in drSym. Names are packed three
; RADIX-40 characters to a word: 1-26 are A-Z, 27-36 are 0-9, 37 is _ and
; 0 is padding. Private names print with their leading period.

cpPutSym: ; Unpack and print the diagnostic symbol name.
    LD   IX,(drSym)                             ; Address the symbol record.
    LD   A,(drSym)                              ; Is there a symbol?
    LD   HL,drSym+1                             ; Address the pointer's high byte.
    OR   (HL)                                   ; Zero means no symbol was recorded.
    JR   NZ,.named                              ; Print the recorded name.
    LD   A,'?'                                  ; Show that the name is unknown.
    JP   cpPutCh                                ; Print it and return.
.named: ; Print a validated symbol record.
    BIT  7,(IX+5)                               ; Is this a private name?
    JR   Z,.global                              ; No: print it as it is.
    LD   A,'.'                                  ; Private names begin with a period.
    CALL cpPutCh                                ; Print it.
.global: ; Decode a global or private packed name.
    LD   L,(IX+0)                               ; Load the first packed word.
    LD   H,(IX+1)                               ; It holds characters one to three.
    CALL .word3                                 ; Print them.
    LD   L,(IX+2)                               ; Load the second packed word.
    LD   H,(IX+3)                               ; It holds characters four to six.
    CALL .word3                                 ; Print them.
    LD   L,(IX+4)                               ; Load the low byte of the final pair.
    LD   A,(IX+5)                               ; Its high bits share a byte with the flags.
    AND  syNameLo                               ; Keep only the name bits.
    LD   H,A                                    ; HL holds characters seven and eight.
    JR   .word2                                 ; Print them and return.
.word3: ; Decode three RADIX-40 characters.
    LD   DE,1600                                ; The first character is the 1600s digit.
    CALL .digit                                 ; Divide it out and print it.
.word2: ; Decode two RADIX-40 characters.
    LD   DE,40                                  ; The next character is the 40s digit.
    CALL .digit                                 ; Divide it out and print it.
    LD   A,L                                    ; The remainder is the last character.
    JR   .code                                  ; Print it and return.
.digit: ; Divide out the next packed character.
    LD   C,0                                    ; C counts how many times DE fits.
.sub: ; Count complete RADIX-40 place values.
    OR   A                                      ; Clear carry for the subtraction.
    SBC  HL,DE                                  ; Take DE away once more.
    JR   C,.back                                ; Too far: undo the last step.
    INC  C                                      ; One more whole DE.
    JR   .sub                                   ; Try again.
.back: ; Undo the first subtraction that borrowed.
    ADD  HL,DE                                  ; HL is now the remainder.
    LD   A,C                                    ; A is the character code.
.code: ; Convert a nonzero packed name code to ASCII.
    OR   A                                      ; Code zero is padding.
    RET  Z                                      ; Print nothing for it.
    CP   27                                     ; Codes 1 to 26 are letters.
    JR   NC,.notAlpha                           ; Higher codes are digits or underscore.
    ADD  A,'A'-1                                ; Convert 1 to A.
    JP   cpPutCh                                ; Print it and return.
.notAlpha: ; Convert a packed digit or underscore code.
    CP   37                                     ; Codes 27 to 36 are digits.
    JR   NC,.under                              ; Code 37 is the underscore.
    ADD  A,'0'-27                               ; Convert 27 to 0.
    JP   cpPutCh                                ; Print it and return.
.under: ; Print packed underscore code 37.
    LD   A,'_'                                  ; Code 37 prints as an underscore.
    JP   cpPutCh                                ; Print it and return.

