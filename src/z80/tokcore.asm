;==========================================================================
;  Streaming tokenizer
;==========================================================================
;
;  PURPOSE
;  -------
;  Pull one token at a time from a source part. The interface uses a part
;  ordinal and a logical offset, never a file. Every source byte is obtained
;  through tkRead, so the core can read memory, host-backed snapshots,
;  banked storage or an operating-system adapter. A part ends where tkRead
;  reports that no byte remains, so its length is never needed.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;  tkReset selects a source part from a logical offset and line. A part
;  resumed after an include starts past zero, so offsets and lines stay true
;  to the file. CR, LF and CRLF each end one line.
;  Entry: A=part ordinal, HL=starting logical offset, DE=starting line.
;  Exit: IX=token record.
;
;  tkNext returns the next token from the selected part.
;  Success: carry clear, A=kind, IX=nine-byte token record.
;  Error: carry set, A=tokenizer lexical status. tkErrPos/tkErrOff identify
;  the failed token. The previous record remains unchanged.
;  The lexeme pointer is valid only until the next call.
;
;  TOKEN RECORD
;  ------------
;
;  +0   byte   token kind
;  +1   byte   source-part ordinal
;  +2   word   byte offset from the beginning of that part
;  +4   word   line number, counting from one
;  +6   word   pointer into tkLexBuf
;  +8   byte   raw lexeme length
;  +9   word   decoded numeric value, otherwise zero
;
;  Names keep their source capitalisation. Mnemonic, directive and symbol
;  consumers perform case folding while recognising or packing them.
;
;  LINE BOUNDARIES
;  ---------------
;
;  Blank and comment-only lines emit no EOL. A non-empty final line without a
;  physical line ending emits one synthetic EOL before repeatable EOF. This
;  prevents the last token of one source part joining the first token of the
;  next part.
;
;  SOURCE SERVICE SEAM
;  -------------------
;
;  tkRead receives A=part ordinal and HL=logical byte offset. It returns the
;  byte with carry clear, or carry with A=0 when the part has no more bytes.
;  The seam has no read-error channel. A host that cannot supply a byte ends
;  the part, and reports why when the driver next calls tkOpen.

tkBeg: ; Begin tokenizer code and constants.

; Published kinds. Expression parsing also uses punctuation values.

tkEof       EQU     0                   ; Repeatable end-of-source-part token.
tkEol       EQU     1                   ; Physical or synthetic nonempty line end.
tkName      EQU     2                   ; Name or private-name lexeme.
tkDir       EQU     3                   ; Reserved kind for statement diagnostics.
tkNum       EQU     4                   ; Decoded sixteen-bit numeric literal.
tkStr       EQU     5                   ; Raw quoted string lexeme.
tkComma     EQU     6                   ; Comma punctuation.
tkColon     EQU     7                   ; Colon punctuation.
tkLParen    EQU     8                   ; Left parenthesis punctuation.
tkRParen    EQU     9                   ; Right parenthesis punctuation.
tkPlus      EQU     10                  ; Addition or unary-plus operator.
tkMinus     EQU     11                  ; Subtraction or unary-minus operator.
tkStar      EQU     12                  ; Multiplication operator.
tkSlash     EQU     13                  ; Division operator.
tkModulo    EQU     14                  ; Remainder operator when not a binary literal.
tkAmp       EQU     15                  ; Bitwise AND operator.
tkCaret     EQU     16                  ; Bitwise XOR operator.
tkPipe      EQU     17                  ; Bitwise OR operator.
tkTilde     EQU     18                  ; Bitwise complement operator.
tkApost     EQU     19                  ; Standalone apostrophe punctuation.
tkShiftL    EQU     20                  ; Two-character left-shift operator.
tkShiftR    EQU     21                  ; Two-character right-shift operator.
tkHere      EQU     22                  ; Current logical output address marker.

; Lexical failure statuses returned with carry set.

tkBadSrc    EQU     1                   ; Invalid input byte.
tkLong      EQU     2                   ; Name exceeds its accepted source length.
tkBadNum    EQU     3                   ; Malformed numeric literal.
tkNumBig    EQU     4                   ; Numeric value exceeds sixteen bits.
tkStrCut    EQU     5                   ; Unterminated string literal.
tkBadEsc    EQU     6                   ; Unsupported string or character escape.
tkStrBig    EQU     7                   ; String lexeme exceeds its byte limit.
tkBadLen    EQU     8                   ; Unused. Keeps later statuses' numbers.
tkHost      EQU     9                   ; Host directive reached native Atom.
tkLitCut    EQU     10                  ; Unterminated character literal.
tkBadLit    EQU     11                  ; Invalid character literal contents.

; Eleven-byte token-record field offsets and total size. Part, offset and
; line form one five-byte source position.

tkKindAt    EQU     0                   ; Token-kind byte offset.
tkPartAt    EQU     1                   ; Source-part ordinal byte offset.
tkOffAt     EQU     2                   ; Source-relative token offset word.
tkLineAt    EQU     4                   ; Token line-number word.
tkLexAt     EQU     6                   ; Lexeme-buffer pointer word.
tkLenAt     EQU     8                   ; Raw lexeme-length byte.
tkValAt     EQU     9                   ; Decoded numeric-value word.
tkRecLen    EQU     11                  ; Total published token-record size.

;@ROUTINE IN A,DE,HL OUT IX CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Bind part A from logical offset HL on line DE and clear the token state.

tkReset: ; Select a source part and clear token state.
    LD   (tkPart),A                     ; Publish part for tokens and reads.
    LD   (tkHead),HL                    ; Start the physical read cursor.
    LD   (tkTokPos),HL                  ; Start the diagnostic offset.
    LD   (tkLine),DE                    ; Start the line count.
    XOR  A                              ; Clear the state bytes.
    LD   (tkHave),A                     ; No byte has been read at the cursor.
    LD   (tkPrevCh),A                   ; No byte precedes the part's first.

; No token has appeared on the line, no synthetic EOL is pending and no error
; or previous record kind survives into the new part.

    LD   (tkSeen),A                     ; Mark the new physical line as token-free.
    LD   (tkEolOut),A                   ; Clear the synthetic-EOL pending flag.
    LD   (tkStatus),A                   ; Clear the previous lexical error status.
    LD   (tkRecord+tkKindAt),A          ; Seed record with repeatable EOF.
    LD   IX,tkRecord                    ; Return the stable token-record address.
    RET                                 ; The part is selected.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Return the byte at the cursor, or carry at the end of the part. PEEK never
; advances either cursor or copies the byte into the token buffer. The byte is
; kept until the cursor moves, so each source byte is read from the host once.

tkPeek: ; Read the current byte without consuming it.
    LD   A,(tkHave)                     ; Is the cursor's byte already held?
    DEC  A                              ; One means a byte is held.
    JR   Z,.byte                        ; Return it.
    DEC  A                              ; Two means the part has ended.
    JR   Z,.end                         ; Return the end again.
    LD   HL,(tkHead)                    ; Load the physical read cursor.
    LD   A,(tkPart)                     ; Supply the current source-part ordinal.
    CALL tkRead                         ; Read the byte, or carry at end of part.
    LD   (tkCur),A                      ; Hold the byte.
    LD   A,1                            ; One for a byte, two for the end.
    ADC  A,0                            ; Add the end-of-part carry.
    LD   (tkHave),A                     ; Record what the cursor holds.
    JR   tkPeek                         ; Return it.
.byte: ; Return the held byte.
    LD   A,(tkCur)                      ; Load the byte.
    OR   A                              ; Clear carry and classify zero.
    RET                                 ; Return the source byte.
.end: ; Report the end of the part.
    SCF                                 ; Carry marks the end of the part.
    RET                                 ; A is zero.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Preserve BC because callers often use it as a length, radix or loop counter.

tkTake: ; Consume one source byte into the tentative lexeme.
    PUSH BC                             ; Save caller length or loop state.
    CALL tkPeek                         ; Read the current byte without advancing.
    JR   C,.eof                         ; Leave cursors and buffer at EOF.

; Save the byte while both cursors advance. tkHead selects the next source
; byte. tkTokPos is the logical offset reported for the next token.

    LD   D,A                            ; Save byte while cursors advance.
    LD   HL,(tkHead)                    ; Load the physical read cursor.
    INC  HL                             ; Advance to the next source byte.
    LD   (tkHead),HL                    ; Publish the new physical cursor.
    XOR  A                              ; The next byte has not been read.
    LD   (tkHave),A                     ; Forget the consumed byte.
    LD   HL,(tkTokPos)                  ; Load the logical diagnostic offset.
    INC  HL                             ; Advance its one-byte source position.
    LD   (tkTokPos),HL                  ; Publish the next token-start offset.

; CR ends a line. LF ends one too, unless it completes a CRLF pair.

    LD   A,D                            ; Inspect the consumed byte.
    CP   13                             ; Is it CR?
    JR   Z,.line                        ; CR always ends a line.
    CP   10                             ; Is it LF?
    JR   NZ,.same                       ; Other bytes stay on the line.
    LD   A,(tkPrevCh)                   ; Did CR come just before it?
    CP   13                             ; CRLF ends only one line.
    JR   Z,.same                        ; Already counted at the CR.
.line: ; Count one line ending.
    LD   HL,(tkLine)                    ; Load the line count.
    INC  HL                             ; The next byte starts a new line.
    LD   (tkLine),HL                    ; Keep it.
.same: ; The line count is current.

; Append at tkLexBuf + count. tkTake permits count wrap: token scanners
; reject byte 256 immediately afterwards, while comments discard the buffer.

    LD   A,(tkUsed)                     ; Read tentative raw-byte count.
    LD   C,A                            ; Move it into the low offset byte.
    LD   B,0                            ; Zero-extend the buffer index.
    LD   HL,tkLexBuf                    ; Point at the start of the token buffer.
    ADD  HL,BC                          ; Select the next tentative byte slot.
    LD   A,D                            ; Restore the consumed source byte.
    LD   (HL),A                         ; Append it to the tentative lexeme.

; tkPrevCh supports the apostrophe ambiguity after a name such as AF'.

    LD   (tkPrevCh),A                   ; Keep it for apostrophe handling.
    LD   A,(tkUsed)                     ; Reload the raw byte count.
    INC  A                              ; Count new byte, possibly wrapping.
    LD   (tkUsed),A                     ; Publish the new tentative count.
    LD   A,D                            ; Return the consumed byte to the caller.
    POP  BC                             ; Restore caller loop/radix state.

; Return the consumed byte and normalise carry clear through OR.

    OR   A                              ; Normalise carry clear and classify zero.
    RET                                 ; Cursors and buffer now agree.
.eof: ; Unwind a consume attempted at EOF.
    POP  BC                             ; Restore caller state.
    SCF                                 ; Report that no byte was consumed.
    RET                                 ; Leave all tokenizer cursors unchanged.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Start a tentative token. Until tkCommit runs, the public record describes
; the preceding successful token.

tkStart: ; Capture a token start before scanning its contents.
    LD   HL,tkLexBuf                    ; Point to tentative lexeme storage.
    LD   (tkLexPtr),HL                  ; Save pointer for publication.
    LD   HL,(tkTokPos)                  ; Capture current source offset.
    LD   (tkMark),HL                    ; Save token's diagnostic start.
    LD   HL,(tkLine)                    ; Capture its line.
    LD   (tkMarkLn),HL                  ; Save it with the offset.

; Clear raw byte count, tentative length and decoded numeric value.

    XOR  A                              ; Construct cleared tentative token fields.
    LD   (tkUsed),A                     ; Clear the number of consumed raw bytes.
    LD   (tkLexLen),A                   ; Clear the publishable lexeme length.
    LD   (tkValue),A                    ; Clear the decoded value low byte.
    LD   (tkValue+1),A                  ; Clear its high byte.
    RET                                 ; Keep previous public record.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Publish all record fields only after the scanner has accepted the token.

tkCommit: ; Publish the accepted token's complete eleven-byte record.
    LD   (tkRecord+tkKindAt),A          ; Publish the accepted token kind.
    LD   A,(tkPart)                     ; Load the current source-part ordinal.
    LD   (tkRecord+tkPartAt),A          ; Publish the token's part identity.
    LD   HL,(tkMark)                    ; Load the saved tentative token offset.
    LD   (tkRecord+tkOffAt),HL          ; Publish its source-relative position.
    LD   HL,(tkMarkLn)                  ; Load the token's line.
    LD   (tkRecord+tkLineAt),HL         ; Publish it.
    LD   HL,(tkLexPtr)                  ; Load the tentative lexeme-buffer pointer.
    LD   (tkRecord+tkLexAt),HL          ; Publish the lexeme location.
    LD   A,(tkLexLen)                   ; Load the accepted raw lexeme length.
    LD   (tkRecord+tkLenAt),A           ; Publish its one-byte length.
    LD   HL,(tkValue)                   ; Load the decoded numeric value or zero.
    LD   (tkRecord+tkValAt),HL          ; Publish the token value word.

; Return a stable record pointer and mirror its kind in A. OR clears carry.

    LD   IX,tkRecord                    ; Return the stable public record address.
    LD   A,(tkRecord+tkKindAt)          ; Mirror its published kind into A.
    OR   A                              ; Clear carry and classify EOF kind zero.
    RET                                 ; Return the complete token atomically.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; A completed non-EOL token marks this physical line as non-empty.

tkFinish: ; Mark the line nonempty and publish the accepted token.
    PUSH AF                             ; Preserve the accepted token kind.
    LD   A,1                            ; Construct the line-has-token state.
    LD   (tkSeen),A                     ; Mark line nonempty for later EOL.
    POP  AF                             ; Restore the accepted token kind.
    JR   tkCommit                       ; Publish the complete token record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,SIGN,PARITY,ZERO
; Retain lexical status, then rewind both cursors to the token's first byte.
; This makes failure atomic with respect to source consumption and leaves the
; previously published token record untouched.

tkFail: ; Rewind failed scanning and publish the lexical diagnostic.
    LD   (tkStatus),A                   ; Publish the detailed lexical status.
    LD   HL,(tkMark)                    ; Reload token's first offset.
    LD   (tkHead),HL                    ; Rewind physical reads to that byte.
    XOR  A                              ; The held byte belongs to the old cursor.
    LD   (tkHave),A                     ; Forget it.
    LD   (tkTokPos),HL                  ; Rewind diagnostic offset too.
    LD   (tkErrOff),HL                  ; Publish the error's offset.
    LD   HL,(tkMarkLn)                  ; Reload the token's line.
    LD   (tkLine),HL                    ; Rewind the line count.
    LD   (tkErrLn),HL                   ; Publish the error's line.
    LD   A,(tkPart)                     ; Load the current part ordinal.
    LD   (tkErrPos),A                   ; Publish the error's source-part identity.

; Reload the saved status after using A for the part ordinal.

    LD   A,(tkStatus)                   ; Return the original lexical status in A.
    SCF                                 ; Mark tokenisation as failed.
    RET                                 ; Keep previous public record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; ASCII case-folding by bit 5 maps A-Z and a-z into the same 0..25 interval.
; Carry from CP 26 is the routine's "is letter" result. A itself is restored.

tkAlpha: ; Classify ASCII letters with carry set for a match.
    PUSH BC                             ; Save BC while C is scratch.
    LD   C,A                            ; Save the original byte for return.
    OR   $20                            ; Fold ASCII to lowercase range.
    SUB  $61                            ; Map lowercase a..z to 0..25.
    CP   26                             ; Carry means a letter index.
    LD   A,C                            ; Restore the caller's original byte.
    POP  BC                             ; Restore caller BC without changing flags.
    RET                                 ; Return the letter result in carry.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; A name may begin with an ASCII letter or underscore.

tkLead: ; Classify a letter or underscore as a name starter.
    CALL tkAlpha                        ; Accept either case of an ASCII letter.
    RET  C                              ; Return original byte if accepted.
    CP   $5F                            ; Otherwise test underscore.
    JR   Z,tkYes                        ; Return shared accepted result.
    OR   A                              ; Clear carry for every other byte.
    RET                                 ; Return not-a-name-start.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Continuation additionally permits decimal digits.

tkAlnum: ; Classify the letters, digits and underscore allowed within a name.
    CALL tkLead                         ; First accept letters and underscore.
    RET  C                              ; Preserve the accepted result.
    CP   $30                            ; Compare remaining bytes with ASCII zero.
    JR   C,.no                          ; Bytes below zero are not continuations.
    CP   $39+1                          ; Carry now denotes decimal digits 0..9.
    RET  C                              ; Return accepted for a digit.
.no: ; Return a false classifier result.
    OR   A                              ; Clear carry while preserving A.
    RET                                 ; Report rejection.
tkYes: ; Return a true classifier result.
    SCF                                 ; Set carry while preserving A.
    RET                                 ; Report acceptance.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Convert one ASCII hexadecimal digit to 0..15. Carry set means valid.

tkNibble: ; Decode a hexadecimal digit with carry set for valid input.
    CP   $30                            ; Reject bytes below ASCII zero.
    JR   C,.notHex                      ; Return carry clear for that range.
    CP   $39+1                          ; Is the byte an ASCII decimal digit?
    JR   C,.decimal                     ; Decode it through the decimal path.
    OR   $20                            ; Fold uppercase A..F to lowercase.
    SUB  $61                            ; Map A..F to candidate values 0..5.
    CP   6                              ; Accept only that six-value interval.
    JR   NC,.notHex                     ; Reject G and every later byte.
    ADD  A,10                           ; Convert the letter index to 10..15.
    SCF                                 ; Mark hex digit valid.
    RET                                 ; Return its nibble value in A.
.decimal: ; Decode an ASCII decimal digit.
    SUB  $30                            ; Convert character 0..9 to numeric 0..9.
    SCF                                 ; Mark the decoded digit as valid.
    RET                                 ; Return its nibble value in A.
.notHex: ; Return invalid-hexadecimal classification.
    OR   A                              ; Clear carry. Retain value in A.
    RET                                 ; Report rejection.
