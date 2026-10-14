;==========================================================================
;  Streaming tokenizer
;==========================================================================
;
;  PURPOSE
;  -------
;  Pull one token at a time from a prepared source part. The interface uses
;  a byte range and part ordinal, never a file. Every source byte is obtained
;  through tkRead, so the core can read memory, host-backed snapshots,
;  banked storage or an operating-system adapter.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;  tkReset selects a source part at logical offset zero.
;  Entry: A=part ordinal, HL=source begin, DE=exclusive source end.
;  Success: carry clear, A=0, IX=token record.
;  Error: carry set, A=tkBadLen for a reversed range. No state changes.
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
;  +4   word   pointer into tkLexBuf
;  +6   byte   raw lexeme length
;  +7   word   decoded numeric value, otherwise zero
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
;  tkRead receives A=part ordinal and HL=logical byte offset. The checked
;  core's implementation below reads the reset range directly. Platform builds
;  replace only the explicitly marked body with a jump to their provider.
;  Every offset below the validated part length must return successfully. This
;  seam has no read-error channel: tkPeek reserves carry for end of part.

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
tkBadLen    EQU     8                   ; Reversed source range supplied to reset.
tkHost      EQU     9                   ; Host directive reached native Atom.
tkLitCut    EQU     10                  ; Unterminated character literal.
tkBadLit    EQU     11                  ; Invalid character literal contents.

; Nine-byte token-record field offsets and total size.

tkKindAt    EQU     0                   ; Token-kind byte offset.
tkPartAt    EQU     1                   ; Source-part ordinal byte offset.
tkOffAt     EQU     2                   ; Source-relative token offset word.
tkLexAt     EQU     4                   ; Lexeme-buffer pointer word.
tkLenAt     EQU     6                   ; Raw lexeme-length byte.
tkValAt     EQU     7                   ; Decoded numeric-value word.
tkRecLen    EQU     9                   ; Total published token-record size.

;@ROUTINE IN A,HL,DE OUT A,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Preserve proposed state until end - begin proves the half-open range does
; not wrap. HL becomes the part length when subtraction succeeds.

tkReset: ; Reset the source interval and clear token state.
    PUSH AF                             ; Save proposed part ordinal.
    PUSH HL                             ; Preserve the proposed range start.
    PUSH DE                             ; Save proposed exclusive end.
    EX   DE,HL                          ; Put end in HL and start in DE.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Calculate the proposed part length.
    JR   C,.unwind                      ; Reject an end below the start atomically.

; Commit the validated length, then recover end, begin and ordinal from stack.

    LD   (tkSrcLen),HL                  ; Publish the validated source length.
    POP  DE                             ; Restore caller's proposed end.
    POP  HL                             ; Restore the memory base.
    POP  AF                             ; Restore the source-part ordinal.
    LD   (tkPart),A                     ; Publish part for tokens and reads.
    LD   (tkSrcBeg),HL                  ; Publish the memory-backed fallback base.

; Both physical read position and logical diagnostic offset begin at zero.

    XOR  A                              ; Clear offset and state bytes.
    LD   (tkHead),A                     ; Clear the physical read cursor low byte.
    LD   (tkHead+1),A                   ; Clear its high byte.
    LD   (tkTokPos),A                   ; Clear diagnostic offset low byte.
    LD   (tkTokPos+1),A                 ; Clear its high byte.

; No token has appeared on the line, no synthetic EOL is pending and no error
; or previous record kind survives into the new part.

    LD   (tkSeen),A                     ; Mark the new physical line as token-free.
    LD   (tkEolOut),A                   ; Clear the synthetic-EOL pending flag.
    LD   (tkStatus),A                   ; Clear the previous lexical error status.
    LD   (tkRecord+tkKindAt),A          ; Seed record with repeatable EOF.
    LD   IX,tkRecord                    ; Return the stable token-record address.
    RET                                 ; Report reset success with carry clear.
.unwind: ; Unwind a reversed proposed interval.

; Restore the caller's proposed values without publishing any of them.

    POP  DE                             ; Restore the proposed exclusive end.
    POP  HL                             ; Restore the proposed start.
    POP  AF                             ; Restore the proposed part ordinal.
.reversed: ; Return the public bad-source-range status.
    LD   A,tkBadLen                     ; Select the reversed-range diagnostic.
    SCF                                 ; Mark reset as failed.
    RET                                 ; Publish no state on failure.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Compare the current relative cursor with the validated part length. Equality
; is EOF. A greater cursor is impossible while tokenizer invariants hold.

tkPeek: ; Read the current byte without consuming it.
    LD   HL,(tkHead)                    ; Load the relative physical read cursor.
    LD   DE,(tkSrcLen)                  ; Load the validated part length.
    OR   A                              ; Clear carry before cursor-minus-length.
    SBC  HL,DE                          ; Set zero exactly at end of part.
    JR   Z,.eof                         ; Return EOF without a source read.
    ADD  HL,DE                          ; Restore the relative cursor value in HL.
.read: ; Invoke the configured source-byte provider.

; The service receives part ordinal and logical offset. PEEK never advances
; either cursor or copies the returned byte into the token buffer.

    LD   A,(tkPart)                     ; Supply the current source-part ordinal.
    CALL tkRead                         ; Read byte at A:HL without consuming it.
    OR   A                              ; Clear carry, preserving the byte.
    RET                                 ; Return the source byte in A.
.eof: ; Report end of the current half-open interval.
    SCF                                 ; Distinguish EOF from a real byte.
    RET                                 ; Leave both source cursors unchanged.

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
    LD   HL,(tkTokPos)                  ; Load the logical diagnostic offset.
    INC  HL                             ; Advance its one-byte source position.
    LD   (tkTokPos),HL                  ; Publish the next token-start offset.

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

; Clear raw byte count, tentative length and decoded numeric value.

    XOR  A                              ; Construct cleared tentative token fields.
    LD   (tkUsed),A                     ; Clear the number of consumed raw bytes.
    LD   (tkLexLen),A                   ; Clear the publishable lexeme length.
    LD   (tkValue),A                    ; Clear the decoded value low byte.
    LD   (tkValue+1),A                  ; Clear its high byte.
    RET                                 ; Keep previous public record.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Publish all record fields only after the scanner has accepted the token.

tkCommit: ; Publish the accepted token's complete nine-byte record.
    LD   (tkRecord+tkKindAt),A          ; Publish the accepted token kind.
    LD   A,(tkPart)                     ; Load the current source-part ordinal.
    LD   (tkRecord+tkPartAt),A          ; Publish the token's part identity.
    LD   HL,(tkMark)                    ; Load the saved tentative token offset.
    LD   (tkRecord+tkOffAt),HL          ; Publish its source-relative position.
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
    LD   (tkTokPos),HL                  ; Rewind diagnostic offset too.
    LD   A,(tkPart)                     ; Load the current part ordinal.
    LD   (tkErrPos),A                   ; Publish the error's source-part identity.
    LD   HL,(tkMark)                    ; Reload the stable error offset.
    LD   (tkErrOff),HL                  ; Publish its low and high bytes.

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
