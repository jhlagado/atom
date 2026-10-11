;==========================================================================
;  Streaming tokenizer
;==========================================================================
;
;  PURPOSE
;  -------
;  Pull one token at a time from a prepared source part. The interface uses
;  a byte range and part ordinal, never a file. Every source byte is obtained
;  through TK_SREAD, so the core can read memory, host-backed snapshots,
;  banked storage or an operating-system adapter.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;  TK_RESET selects a source part at logical offset zero.
;  Entry: A=part ordinal, HL=source begin, DE=exclusive source end.
;  Success: carry clear, A=0, IX=token record.
;  Error: carry set, A=TK_SRNG for a reversed range. No state changes.
;
;  TK_NEXT returns the next token from the selected part.
;  Success: carry clear, A=kind, IX=nine-byte token record.
;  Error: carry set, A=TK_S* lexical status. TK_EPART/TK_EOFF identify
;  the failed token. The previous record remains unchanged.
;  The lexeme pointer is valid only until the next call.
;
;  TOKEN RECORD
;  ------------
;
;  +0   byte   token kind
;  +1   byte   source-part ordinal
;  +2   word   byte offset from the beginning of that part
;  +4   word   pointer into TK_BUF
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
;  TK_SREAD receives A=part ordinal and HL=logical byte offset. The checked
;  core's implementation below reads the reset range directly. Platform builds
;  replace only the explicitly marked body with a jump to their provider.
;  Every offset below the validated part length must return successfully. This
;  seam has no read-error channel: TK_SPEEK reserves carry for end of part.

TK_CBEG: ; Begin tokenizer code and constants.

; Published kinds. Expression parsing also uses punctuation values.

TK_EOF      EQU     0                   ; Repeatable end-of-source-part token.
TK_EOL      EQU     1                   ; Physical or synthetic nonempty line end.
TK_NAME     EQU     2                   ; Name or private-name lexeme.
TK_DIR      EQU     3                   ; Reserved kind for statement diagnostics.
TK_NUM      EQU     4                   ; Decoded sixteen-bit numeric literal.
TK_STR      EQU     5                   ; Raw quoted string lexeme.
TK_COMMA    EQU     6                   ; Comma punctuation.
TK_COLON    EQU     7                   ; Colon punctuation.
TK_LPAR     EQU     8                   ; Left parenthesis punctuation.
TK_RPAR     EQU     9                   ; Right parenthesis punctuation.
TK_PLUS     EQU     10                  ; Addition or unary-plus operator.
TK_MINUS    EQU     11                  ; Subtraction or unary-minus operator.
TK_STAR     EQU     12                  ; Multiplication operator.
TK_SLASH    EQU     13                  ; Division operator.
TK_PCT      EQU     14                  ; Remainder operator when not a binary literal.
TK_AMP      EQU     15                  ; Bitwise AND operator.
TK_CARET    EQU     16                  ; Bitwise XOR operator.
TK_PIPE     EQU     17                  ; Bitwise OR operator.
TK_TILDE    EQU     18                  ; Bitwise complement operator.
TK_APOST    EQU     19                  ; Standalone apostrophe punctuation.
TK_SHL      EQU     20                  ; Two-character left-shift operator.
TK_SHR      EQU     21                  ; Two-character right-shift operator.
TK_CUR      EQU     22                  ; Current logical output address marker.

; Lexical failure statuses returned with carry set.

TK_SBYTE    EQU     1                   ; Invalid input byte.
TK_SLONG    EQU     2                   ; Name exceeds its accepted source length.
TK_SFORM    EQU     3                   ; Malformed numeric literal.
TK_SOVER    EQU     4                   ; Numeric value exceeds sixteen bits.
TK_SOPEN    EQU     5                   ; Unterminated string literal.
TK_SESC     EQU     6                   ; Unsupported string or character escape.
TK_SFULL    EQU     7                   ; String lexeme exceeds its byte limit.
TK_SRNG     EQU     8                   ; Reversed source range supplied to reset.
TK_SDIR     EQU     9                   ; Host directive reached native Atom.
TK_SCUT     EQU     10                  ; Unterminated character literal.
TK_SAPOS    EQU     11                  ; Invalid character literal contents.

; Nine-byte token-record field offsets and total size.

TK_RKIND    EQU     0                   ; Token-kind byte offset.
TK_RPART    EQU     1                   ; Source-part ordinal byte offset.
TK_ROFF     EQU     2                   ; Source-relative token offset word.
TK_RLEX     EQU     4                   ; Lexeme-buffer pointer word.
TK_RLEN     EQU     6                   ; Raw lexeme-length byte.
TK_RVAL     EQU     7                   ; Decoded numeric-value word.
TK_RECB     EQU     9                   ; Total published token-record size.

;@ROUTINE IN A,HL,DE OUT A,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Preserve proposed state until end - begin proves the half-open range does
; not wrap. HL becomes the part length when subtraction succeeds.

TK_RESET: ; Reset the source interval and clear token state.
    PUSH AF                             ; Save proposed part ordinal.
    PUSH HL                             ; Preserve the proposed range start.
    PUSH DE                             ; Save proposed exclusive end.
    EX   DE,HL                          ; Put end in HL and start in DE.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Calculate the proposed part length.
    JR   C,.UNWIND                      ; Reject an end below the start atomically.

; Commit the validated length, then recover end, begin and ordinal from stack.

    LD   (TK_LIMIT),HL                  ; Publish the validated source length.
    POP  DE                             ; Restore caller's proposed end.
    POP  HL                             ; Restore the memory base.
    POP  AF                             ; Restore the source-part ordinal.
    LD   (TK_PART),A                    ; Publish part for tokens and reads.
    LD   (TK_SRC),HL                    ; Publish the memory-backed fallback base.

; Both physical read position and logical diagnostic offset begin at zero.

    XOR  A                              ; Clear offset and state bytes.
    LD   (TK_HEAD),A                    ; Clear the physical read cursor low byte.
    LD   (TK_HEAD+1),A                  ; Clear its high byte.
    LD   (TK_POS),A                     ; Clear diagnostic offset low byte.
    LD   (TK_POS+1),A                   ; Clear its high byte.

; No token has appeared on the line, no synthetic EOL is pending and no error
; or previous record kind survives into the new part.

    LD   (TK_SEEN),A                    ; Mark the new physical line as token-free.
    LD   (TK_SYNTH),A                   ; Clear the synthetic-EOL pending flag.
    LD   (TK_ESTAT),A                   ; Clear the previous lexical error status.
    LD   (TK_REC+TK_RKIND),A            ; Seed record with repeatable EOF.
    LD   IX,TK_REC                      ; Return the stable token-record address.
    RET                                 ; Report reset success with carry clear.
.UNWIND: ; Unwind a reversed proposed interval.

; Restore the caller's proposed values without publishing any of them.

    POP  DE                             ; Restore the proposed exclusive end.
    POP  HL                             ; Restore the proposed start.
    POP  AF                             ; Restore the proposed part ordinal.
.REVERSED: ; Return the public bad-source-range status.
    LD   A,TK_SRNG                      ; Select the reversed-range diagnostic.
    SCF                                 ; Mark reset as failed.
    RET                                 ; Publish no state on failure.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Compare the current relative cursor with the validated part length. Equality
; is EOF. A greater cursor is impossible while tokenizer invariants hold.

TK_SPEEK: ; Read the current byte without consuming it.
    LD   HL,(TK_HEAD)                   ; Load the relative physical read cursor.
    LD   DE,(TK_LIMIT)                  ; Load the validated part length.
    OR   A                              ; Clear carry before cursor-minus-length.
    SBC  HL,DE                          ; Set zero exactly at end of part.
    JR   Z,.EOF                         ; Return EOF without a source read.
    ADD  HL,DE                          ; Restore the relative cursor value in HL.
.READ: ; Invoke the configured source-byte provider.

; The service receives part ordinal and logical offset. PEEK never advances
; either cursor or copies the returned byte into the token buffer.

    LD   A,(TK_PART)                    ; Supply the current source-part ordinal.
    CALL TK_SREAD                       ; Read byte at A:HL without consuming it.
    OR   A                              ; Clear carry, preserving the byte.
    RET                                 ; Return the source byte in A.
.EOF: ; Report end of the current half-open interval.
    SCF                                 ; Distinguish EOF from a real byte.
    RET                                 ; Leave both source cursors unchanged.
;@@ATOM_SOURCE_READ_BEGIN@@

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Memory-backed fallback: translate the logical offset to an absolute address.

TK_SREAD: ; Read one byte from the memory-backed source interval.
    LD   DE,(TK_SRC)                    ; Load the checked-core memory range base.
    ADD  HL,DE                          ; Translate offset to memory address.
    LD   A,(HL)                         ; Fetch the immutable source byte.
    OR   A                              ; Clear carry and classify zero.
    RET                                 ; Return without provider state.
;@@ATOM_SOURCE_READ_END@@

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Preserve BC because callers often use it as a length, radix or loop counter.

TK_STAKE: ; Consume one source byte into the tentative lexeme.
    PUSH BC                             ; Save caller length or loop state.
    CALL TK_SPEEK                       ; Read the current byte without advancing.
    JR   C,.EOF                         ; Leave cursors and buffer at EOF.

; Save the byte while both cursors advance. TK_HEAD selects the next source
; byte. TK_POS is the logical offset reported for the next token.

    LD   D,A                            ; Save byte while cursors advance.
    LD   HL,(TK_HEAD)                   ; Load the physical read cursor.
    INC  HL                             ; Advance to the next source byte.
    LD   (TK_HEAD),HL                   ; Publish the new physical cursor.
    LD   HL,(TK_POS)                    ; Load the logical diagnostic offset.
    INC  HL                             ; Advance its one-byte source position.
    LD   (TK_POS),HL                    ; Publish the next token-start offset.

; Append at TK_BUF + count. TK_STAKE permits count wrap: token scanners
; reject byte 256 immediately afterwards, while comments discard the buffer.

    LD   A,(TK_USED)                    ; Read tentative raw-byte count.
    LD   C,A                            ; Move it into the low offset byte.
    LD   B,0                            ; Zero-extend the buffer index.
    LD   HL,TK_BUF                      ; Point at the start of the token buffer.
    ADD  HL,BC                          ; Select the next tentative byte slot.
    LD   A,D                            ; Restore the consumed source byte.
    LD   (HL),A                         ; Append it to the tentative lexeme.

; TK_PREV supports the apostrophe ambiguity after a name such as AF'.

    LD   (TK_PREV),A                    ; Keep it for apostrophe handling.
    LD   A,(TK_USED)                    ; Reload the raw byte count.
    INC  A                              ; Count new byte, possibly wrapping.
    LD   (TK_USED),A                    ; Publish the new tentative count.
    LD   A,D                            ; Return the consumed byte to the caller.
    POP  BC                             ; Restore caller loop/radix state.

; Return the consumed byte and normalise carry clear through OR.

    OR   A                              ; Normalise carry clear and classify zero.
    RET                                 ; Cursors and buffer now agree.
.EOF: ; Unwind a consume attempted at EOF.
    POP  BC                             ; Restore caller state.
    SCF                                 ; Report that no byte was consumed.
    RET                                 ; Leave all tokenizer cursors unchanged.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Start a tentative token. Until TK_CMT runs, the public record describes
; the preceding successful token.

TK_BEG: ; Capture a token start before scanning its contents.
    LD   HL,TK_BUF                      ; Point to tentative lexeme storage.
    LD   (TK_LEX),HL                    ; Save pointer for publication.
    LD   HL,(TK_POS)                    ; Capture current source offset.
    LD   (TK_MARK),HL                   ; Save token's diagnostic start.

; Clear raw byte count, tentative length and decoded numeric value.

    XOR  A                              ; Construct cleared tentative token fields.
    LD   (TK_USED),A                    ; Clear the number of consumed raw bytes.
    LD   (TK_SLEN),A                    ; Clear the publishable lexeme length.
    LD   (TK_SVAL),A                    ; Clear the decoded value low byte.
    LD   (TK_SVAL+1),A                  ; Clear its high byte.
    RET                                 ; Keep previous public record.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Publish all record fields only after the scanner has accepted the token.

TK_CMT: ; Publish the accepted token's complete nine-byte record.
    LD   (TK_REC+TK_RKIND),A            ; Publish the accepted token kind.
    LD   A,(TK_PART)                    ; Load the current source-part ordinal.
    LD   (TK_REC+TK_RPART),A            ; Publish the token's part identity.
    LD   HL,(TK_MARK)                   ; Load the saved tentative token offset.
    LD   (TK_REC+TK_ROFF),HL            ; Publish its source-relative position.
    LD   HL,(TK_LEX)                    ; Load the tentative lexeme-buffer pointer.
    LD   (TK_REC+TK_RLEX),HL            ; Publish the lexeme location.
    LD   A,(TK_SLEN)                    ; Load the accepted raw lexeme length.
    LD   (TK_REC+TK_RLEN),A             ; Publish its one-byte length.
    LD   HL,(TK_SVAL)                   ; Load the decoded numeric value or zero.
    LD   (TK_REC+TK_RVAL),HL            ; Publish the token value word.

; Return a stable record pointer and mirror its kind in A. OR clears carry.

    LD   IX,TK_REC                      ; Return the stable public record address.
    LD   A,(TK_REC+TK_RKIND)            ; Mirror its published kind into A.
    OR   A                              ; Clear carry and classify EOF kind zero.
    RET                                 ; Return the complete token atomically.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; A completed non-EOL token marks this physical line as non-empty.

TK_FIN: ; Mark the line nonempty and publish the accepted token.
    PUSH AF                             ; Preserve the accepted token kind.
    LD   A,1                            ; Construct the line-has-token state.
    LD   (TK_SEEN),A                    ; Mark line nonempty for later EOL.
    POP  AF                             ; Restore the accepted token kind.
    JR   TK_CMT                         ; Publish the complete token record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,SIGN,PARITY,ZERO
; Retain lexical status, then rewind both cursors to the token's first byte.
; This makes failure atomic with respect to source consumption and leaves the
; previously published token record untouched.

TK_FAIL: ; Rewind failed scanning and publish the lexical diagnostic.
    LD   (TK_ESTAT),A                   ; Publish the detailed lexical status.
    LD   HL,(TK_MARK)                   ; Reload token's first offset.
    LD   (TK_HEAD),HL                   ; Rewind physical reads to that byte.
    LD   (TK_POS),HL                    ; Rewind diagnostic offset too.
    LD   A,(TK_PART)                    ; Load the current part ordinal.
    LD   (TK_EPART),A                   ; Publish the error's source-part identity.
    LD   HL,(TK_MARK)                   ; Reload the stable error offset.
    LD   (TK_EOFF),HL                   ; Publish its low and high bytes.

; Reload the saved status after using A for the part ordinal.

    LD   A,(TK_ESTAT)                   ; Return the original lexical status in A.
    SCF                                 ; Mark tokenisation as failed.
    RET                                 ; Keep previous public record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; ASCII case-folding by bit 5 maps A-Z and a-z into the same 0..25 interval.
; Carry from CP 26 is the routine's "is letter" result. A itself is restored.

TK_ALPHA: ; Classify ASCII letters with carry set for a match.
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

TK_LEAD: ; Classify a letter or underscore as a name starter.
    CALL TK_ALPHA                       ; Accept either case of an ASCII letter.
    RET  C                              ; Return original byte if accepted.
    CP   $5F                            ; Otherwise test underscore.
    JR   Z,TK_YES                       ; Return shared accepted result.
    OR   A                              ; Clear carry for every other byte.
    RET                                 ; Return not-a-name-start.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Continuation additionally permits decimal digits.

TK_ALNUM: ; Classify the letters, digits and underscore allowed within a name.
    CALL TK_LEAD                        ; First accept letters and underscore.
    RET  C                              ; Preserve the accepted result.
    CP   $30                            ; Compare remaining bytes with ASCII zero.
    JR   C,.NO                          ; Bytes below zero are not continuations.
    CP   $39+1                          ; Carry now denotes decimal digits 0..9.
    RET  C                              ; Return accepted for a digit.
.NO: ; Return a false classifier result.
    OR   A                              ; Clear carry while preserving A.
    RET                                 ; Report rejection.
TK_YES: ; Return a true classifier result.
    SCF                                 ; Set carry while preserving A.
    RET                                 ; Report acceptance.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Convert one ASCII hexadecimal digit to 0..15. Carry set means valid.

TK_HEX: ; Decode a hexadecimal digit with carry set for valid input.
    CP   $30                            ; Reject bytes below ASCII zero.
    JR   C,.NOTHEX                      ; Return carry clear for that range.
    CP   $39+1                          ; Is the byte an ASCII decimal digit?
    JR   C,.DECIMAL                     ; Decode it through the decimal path.
    OR   $20                            ; Fold uppercase A..F to lowercase.
    SUB  $61                            ; Map A..F to candidate values 0..5.
    CP   6                              ; Accept only that six-value interval.
    JR   NC,.NOTHEX                     ; Reject G and every later byte.
    ADD  A,10                           ; Convert the letter index to 10..15.
    SCF                                 ; Mark hex digit valid.
    RET                                 ; Return its nibble value in A.
.DECIMAL: ; Decode an ASCII decimal digit.
    SUB  $30                            ; Convert character 0..9 to numeric 0..9.
    SCF                                 ; Mark the decoded digit as valid.
    RET                                 ; Return its nibble value in A.
.NOTHEX: ; Return invalid-hexadecimal classification.
    OR   A                              ; Clear carry. Retain value in A.
    RET                                 ; Report rejection.
