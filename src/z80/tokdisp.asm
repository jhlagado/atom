;==========================================================================
;  Token dispatch, character literals and tokenizer storage
;==========================================================================
;
;  Continue the streaming tokenizer after token.asm's source access and
;  lexeme scanners. tkNext classifies the next byte, delegates compound
;  forms and publishes a stable token record. This part also owns character
;  literals, immutable lookup tables and fixed workspace.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IY
; Enter publication of the next source token.

tkNext: ; Classify the next source byte and publish one complete token.
.nextLoop: ; Skip separators until token or EOF.

; Begin a tentative token at the current offset, then classify its first byte.

    CALL tkStart                                                ; Capture start and clear fields.
    CALL tkPeek                                                 ; Inspect the first unconsumed source byte.
    JP   C,.atEof                                               ; Handle EOL or EOF at part end.
    CP   $20                                                    ; Is the byte an ASCII space?
    JR   Z,.skipByte                                            ; Consume it as an invisible separator.
    CP   $09                                                    ; Is the byte a horizontal tab?
    JR   Z,.skipByte                                            ; Consume it as an invisible separator.
    CP   $0A                                                    ; Is the byte a one-byte LF line ending?
    JP   Z,.lf                                                  ; Handle one-byte LF ending.
    CP   $0D                                                    ; Does the byte begin a CRLF pair?
    JP   Z,.crLf                                                ; Require and consume both bytes.
    CP   $3B                                                    ; Is the byte a semicolon comment marker?
    JR   Z,.comment                                             ; Discard through the physical line end.

; Period begins a private name. The scanner rejects a bare period.

    CP   $2E                                                    ; Is this a private-name period?
    JP   Z,tkIdent                                              ; Validate the private-name payload.
    CP   $22                                                    ; Is this a string opener?
    JP   Z,tkString                                             ; Scan the raw quoted string.
    CP   $27                                                    ; Apostrophe or character opener?
    JP   Z,.quote                                               ; Resolve from source context.
    CP   $24                                                    ; Current address or hex prefix?
    JR   Z,.dollar                                              ; Choose using lookahead.
    CP   $25                                                    ; Remainder or binary prefix?
    JR   Z,.percent                                             ; Use lookahead and line state.
    CP   $3C                                                    ; Could this begin the `<<` operator?
    JP   Z,.lShift                                              ; Require a second matching byte.
    CP   $3E                                                    ; Could this begin the `>>` operator?
    JP   Z,.rShift                                              ; Require a second matching byte.
    CP   $30                                                    ; Compare with the first decimal digit.
    JR   C,.tryName                                             ; Earlier bytes may start a name.
    CP   $39+1                                                  ; Is this byte in ASCII 0..9?
    JP   C,tkNumber                                             ; Scan the complete digit-led candidate.
.tryName: ; Try a global name start.

; Remaining ASCII name-start bytes enter the name scanner.

    CALL tkLead                                                 ; Accept ASCII letters or underscore.
    JP   C,tkIdent                                              ; Scan the complete name when accepted.

; Single-byte punctuation is a compact (character, token-kind) table. Shifts,
; apostrophe, '$' and '%' need context beyond this byte.

    LD   HL,tkMapTab                                            ; Start character/kind table.
    LD   B,tkMapCnt                                             ; Count single-byte punctuation forms.
.puncLoop: ; Search one punctuation pair per iteration.
    CP   (HL)                                                   ; Match source byte with table entry.
    INC  HL                                                     ; Advance to the corresponding token kind.
    JR   Z,.matched                                             ; Publish the matching punctuation form.
    INC  HL                                                     ; Skip the unmatched kind byte.
    DJNZ .puncLoop                                              ; Continue through the complete table.
    JR   tkErrSrc                                               ; No lexical class accepts this source byte.
.matched: ; Consume one matched punctuation byte.
    LD   C,(HL)                                                 ; Save its token kind in C.
    CALL tkTake                                                 ; Consume and buffer the source character.
    LD   A,1                                                    ; Set the raw lexeme length to one.
    JR   .publish                                               ; Publish the table-selected token kind.
.skipByte: ; Consume one invisible horizontal separator.

; Spaces and tabs separate tokens but never appear in a token record.

    CALL tkTake                                                 ; Advance past the space or tab.
    JR   .nextLoop                                              ; Start next tentative token.
.comment: ; Consume but do not publish a source comment.
    CALL tkSkip                                                 ; Stop before CR/LF or at EOF.
    JR   .nextLoop                                              ; Let line-ending or EOF logic run next.
.dollar: ; Classify '$' using one-byte lookahead.

; Consume '$' and inspect the next byte. A valid hexadecimal digit selects a
; prefixed number. Otherwise a standalone '$' denotes the current location.

    CALL tkTake                                                 ; Consume and buffer the dollar sign.
    CALL tkPeek                                                 ; Look ahead without consuming.
    JR   C,.here                                                ; Final '$' means current address.
    LD   B,A                                                    ; Preserve the following raw byte.
    CALL tkNibble                                               ; Test whether it begins a hex value.
    JR   C,.hexNum                                              ; Scan prefixed hex value.

; A following name-continuation byte makes the entire numeric-looking form
; invalid, preventing '$G' from becoming current-location followed by a name.

    LD   A,B                                                    ; Restore the following raw byte.
    CALL tkAlnum                                                ; Could it continue a digit-led candidate?
    JP   C,tkErrNum                                             ; Reject the entire malformed form.
.here: ; Publish current-address punctuation.
    LD   A,1                                                    ; Raw lexeme is '$' alone.
    LD   (tkLexLen),A                                           ; Save the public lexeme length.
    LD   A,tkHere                                               ; Select the current-location token kind.
    JP   tkFinish                                               ; Publish and mark line nonempty.
.hexNum: ; Scan a dollar-prefixed hexadecimal literal.

; Raw length includes '$'. Bit 2 in C selects hex accumulation.

    LD   B,1                                                    ; Count the already consumed prefix.
    LD   C,4                                                    ; Bit 2 selects hexadecimal.
    JP   tkRadix                                                ; Decode and publish remaining digits.
.percent: ; Classify '%' using one-byte lookahead.

; Percent begins binary only when followed by 0 or 1. Otherwise it is the
; remainder operator, subject to the leaked-host-directive guard below.

    CALL tkTake                                                 ; Consume and buffer the percent sign.
    CALL tkPeek                                                 ; Inspect the following byte.
    JR   C,.modulo                                              ; At EOF, '%' means remainder.
    CP   $30                                                    ; Does ASCII zero begin a binary literal?
    JR   Z,.binNum                                              ; Decode the prefixed binary value.
    CP   $31                                                    ; Does ASCII one begin a binary literal?
    JR   Z,.binNum                                              ; Decode the prefixed binary value.
    CALL tkAlpha                                                ; Could this be a leaked `%DIRECTIVE` name?
    JR   NC,.modulo                                             ; Non-letter leaves punctuation.

; Before the first token on a line, "%" plus a letter can only be an unmasked
; host directive. Reject it before expression parsing.

    LD   A,(tkSeen)                                             ; Did this line emit a token yet?
    OR   A                                                      ; Only line-start `%name` is host syntax.
    JR   NZ,.modulo                                             ; Elsewhere publish the remainder operator.
    LD   A,tkHost                                               ; Select unprocessed-host-directive status.
    JP   tkFail                                                 ; Rewind to the percent sign and report it.
.modulo: ; Publish standalone remainder punctuation.
    LD   A,1                                                    ; Its raw lexeme length is one.
    LD   (tkLexLen),A                                           ; Save that length for the public record.
    LD   A,tkModulo                                             ; Select the remainder token kind.
    JP   tkFinish                                               ; Mark the line non-empty and publish.
.binNum: ; Scan a percent-prefixed binary literal.

; Raw length already includes '%'. C=1 selects binary accumulation.

    LD   B,1                                                    ; Count the already consumed prefix.
    LD   C,1                                                    ; Select binary accumulation.
    JP   tkRadix                                                ; Decode remaining digits and publish.
.lShift: ; Prepare a left-shift token.
    LD   C,tkShiftL                                             ; Save the published left-shift kind.
    JR   .shift                                                 ; Validate the doubled punctuation.
.rShift: ; Prepare a right-shift token.
    LD   C,tkShiftR                                             ; Save the published right-shift kind.
.shift: ; Require and consume two equal shift bytes.

; A shift operator is valid only as a doubled matching character, << or >>.

    LD   B,A                                                    ; Preserve the opening '<' or '>' byte.
    CALL tkTake                                                 ; Consume and buffer the first character.
    CALL tkPeek                                                 ; Inspect the required second character.
    JP   C,tkErrSrc                                             ; Diagnose a shift truncated by EOF.
    CP   B                                                      ; Does it match the opening character?
    JP   NZ,tkErrSrc                                            ; Reject a single or mixed angle bracket.
    CALL tkTake                                                 ; Consume and buffer the second character.
    LD   A,2                                                    ; Set the raw shift lexeme length.
.publish: ; Publish punctuation kind C with length A.
    LD   (tkLexLen),A                                           ; Save the raw punctuation length.
    LD   A,C                                                    ; Restore the selected token kind.
    JP   tkFinish                                               ; Mark the line non-empty and publish it.
.lf: ; Consume a one-byte LF line ending.

; LF ends a line. CR requires LF and is otherwise invalid.

    CALL tkTake                                                 ; Consume and buffer the LF byte.
    LD   A,1                                                    ; Record its one-byte raw length.
    LD   (tkLexLen),A                                           ; Save possible EOL length.
    JR   .finLine                                               ; Apply blank-line suppression.
.crLf: ; Consume and validate a two-byte CRLF ending.
    CALL tkTake                                                 ; Consume and buffer the CR byte.
    CALL tkPeek                                                 ; Inspect the mandatory following byte.
    JP   C,tkErrSrc                                             ; A terminal bare CR is invalid input.
    CP   $0A                                                    ; Require LF immediately after CR.
    JP   NZ,tkErrSrc                                            ; Reject any other following byte.
    CALL tkTake                                                 ; Consume and buffer the LF byte.
    LD   A,2                                                    ; Record the two-byte raw line ending.
    LD   (tkLexLen),A                                           ; Save possible EOL length.
.finLine: ; Decide whether to publish EOL.

; A physical ending clears synthetic-EOL state. If no token appeared on the
; line, suppress EOL and continue scanning the next physical line.

    XOR  A                                                      ; Clear the synthetic-EOL pending state.
    LD   (tkEolOut),A                                           ; Physical ending clears synthetic state.
    LD   A,(tkSeen)                                             ; Did this physical line contain a token?
    OR   A                                                      ; Zero means blank/comment-only line.
    JP   Z,.nextLoop                                            ; Suppress EOL and scan the following line.
    XOR  A                                                      ; Construct the next-line token-free state.
    LD   (tkSeen),A                                             ; Publish that state before returning EOL.
    LD   A,tkEol                                                ; Select the end-of-line token kind.
    JP   tkCommit                                               ; Publish without marking new line.
.atEof: ; Handle the current source-part endpoint.

; EOF after a non-empty unterminated final line first publishes one synthetic
; EOL. tkEolOut ensures the following and all later calls return EOF instead.

    LD   A,(tkEolOut)                                           ; Synthetic EOL already emitted?
    OR   A                                                      ; Nonzero makes EOF repeatable immediately.
    JR   NZ,.emitEof                                            ; Publish EOF on this and all later calls.
    LD   A,(tkSeen)                                             ; Final line had a token?
    OR   A                                                      ; Zero needs no synthetic line boundary.
    JR   Z,.emitEof                                             ; Publish EOF for an empty final line.
    XOR  A                                                      ; Construct cleared line state.
    LD   (tkSeen),A                                             ; Mark the final line as closed.
    INC  A                                                      ; Mark synthetic EOL emitted.
    LD   (tkEolOut),A                                           ; Ensure the next call emits EOF instead.
    XOR  A                                                      ; A synthetic EOL has no raw lexeme bytes.
    LD   (tkLexLen),A                                           ; Publish a zero raw length.
    LD   A,tkEol                                                ; Select the synthetic EOL token kind.
    JP   tkCommit                                               ; Publish it at the current end offset.
.emitEof: ; Publish repeatable end-of-part.

; EOF has kind and length zero. tkCommit fills in current part and offset.

    XOR  A                                                      ; EOF kind and length are zero.
    LD   (tkLexLen),A                                           ; Publish an empty lexeme.
    JP   tkCommit                                               ; Fill location and return stable EOF.
.quote: ; Choose punctuation or character.

; Apostrophe is ambiguous with a character literal. At the start of a source
; part or after a non-name byte, it opens a character. Directly after a name
; byte it remains punctuation, preserving forms such as AF'.

    LD   HL,(tkMark)                                            ; Load apostrophe's part offset.
    LD   A,H                                                    ; Test whether it is the first source byte.
    OR   L                                                      ; Zero means no preceding byte exists.
    JR   Z,tkChar                                               ; First byte opens a character.
    LD   A,(tkPrevCh)                                           ; Load the previously consumed source byte.
    CALL tkAlnum                                                ; Could it end a name such as AF?
    JR   NC,tkChar                                              ; Non-name byte opens a character.

; Emit the punctuation form as a one-byte token.

    CALL tkTake                                                 ; Buffer punctuation apostrophe.
    LD   A,1                                                    ; Its raw lexeme length is one.
    LD   (tkLexLen),A                                           ; Save the length for record publication.
    LD   A,tkApost                                              ; Select the apostrophe token kind.
    JP   tkFinish                                               ; Mark the line non-empty and publish.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; B begins at one for the opener. Consume it and the first payload byte.
; EOF or a line ending in this initial position is an unterminated character.
; Line endings reached later inside an escape are invalid escapes instead.

tkChar: ; Decode exactly one character between apostrophes.
    LD   B,1                                                    ; Count the opening apostrophe in advance.
    CALL tkTake                                                 ; Buffer opening apostrophe.
    CALL tkTake                                                 ; Read first payload or close.
    JP   C,tkErrCut                                             ; Diagnose EOF before a complete character.
    INC  B                                                      ; Count the consumed payload byte.
    CALL tkIsEol                                                ; Is the payload byte CR or LF?
    JP   Z,tkErrCut                                             ; Line end truncates character.

; An immediate close is an empty character literal. Backslash enters the
; shared escape language. An ordinary payload must be printable ASCII.

    CP   $27                                                    ; Was this an empty literal?
    JP   Z,tkErrLit                                             ; Reject a character with no decoded byte.
    CP   $5C                                                    ; Does backslash introduce an escape?
    JR   Z,.escape                                              ; Decode the escape language.
    CP   $20                                                    ; Compare with printable ASCII.
    JP   C,tkErrSrc                                             ; Reject raw control bytes.
    CP   $7F                                                    ; Compare with DEL.
    JP   NC,tkErrSrc                                            ; Reject DEL and higher bytes.
    LD   (tkValue),A                                            ; Save decoded character byte.
    JR   .close                                                 ; Require one closing apostrophe next.
.escape: ; Decode one escaped character payload.

; Decode and count the selector after backslash. Table entries yield one byte.
; \x consumes two additional hexadecimal digits.

    CALL tkTake                                                 ; Consume and buffer the escape selector.
    JP   C,tkErrCut                                             ; Diagnose EOF before the selector.
    INC  B                                                      ; Count the selector in the raw lexeme.
    CP   $78                                                    ; Does lowercase x select a hex escape?
    JR   Z,.hexEsc                                              ; Decode exactly two hexadecimal digits.
    CALL tkUnEsc                                                ; Decode a standard one-character escape.
    JP   C,tkErrEsc                                             ; Reject selector not in table.
    LD   (tkValue),A                                            ; Store the decoded character byte.
    JR   .close                                                 ; Require the closing apostrophe.
.hexEsc: ; Decode a two-digit hexadecimal escape.

; Decode high nibble into tkValue, then read low nibble.

    CALL tkTake                                                 ; Buffer high hex digit.
    JP   C,tkErrCut                                             ; Diagnose EOF before that digit.
    INC  B                                                      ; Count the high digit in the raw lexeme.
    CALL tkNibble                                               ; Decode it to a nibble.
    JP   NC,tkErrEsc                                            ; Reject a non-hexadecimal digit.
    ADD  A,A                                                    ; Shift the nibble left one place.
    ADD  A,A                                                    ; Shift it left two places.
    ADD  A,A                                                    ; Shift it left three places.
    ADD  A,A                                                    ; Place it in bits 4..7.
    LD   (tkValue),A                                            ; Save high nibble during low read.
    CALL tkTake                                                 ; Buffer low hex digit.
    JP   C,tkErrCut                                             ; Diagnose EOF before that digit.
    INC  B                                                      ; Count the low digit in the raw lexeme.
    CALL tkNibble                                               ; Decode it to a low nibble.
    JP   NC,tkErrEsc                                            ; Reject a non-hexadecimal digit.
    LD   HL,tkValue                                             ; Point at the retained high nibble.
    OR   (HL)                                                   ; Combine it with the decoded low nibble.
    LD   (tkValue),A                                            ; Save decoded byte.
.close: ; Require the literal's closing apostrophe.

; One decoded byte is ready. The next raw byte must be the closing
; apostrophe and becomes part of the published raw lexeme length.

    CALL tkTake                                                 ; Buffer required closing byte.
    JP   C,tkErrCut                                             ; Diagnose EOF before the close.
    INC  B                                                      ; Include it in the raw lexeme length.
    CALL tkIsEol                                                ; Is close a line ending?
    JP   Z,tkErrCut                                             ; Report unterminated character.
    CP   $27                                                    ; Require immediate apostrophe.
    JP   NZ,tkErrLit                                            ; Reject extra payload/wrong delimiter.
    JP   tkPutLen                                               ; Publish decoded byte as number.
tkRuleTo: ; End tokenizer rule-code measurement.

;@ROUTINE OUT A,B,HL
; Return the current token's lexeme pointer and raw length. This is
; intentionally a borrowed view whose lifetime ends at the next tkNext call.

tkText: ; Return the current token's borrowed lexeme pointer and length.
    LD   HL,(tkRecord+tkLexAt)                                  ; Return published lexeme pointer.
    LD   A,(tkRecord+tkLenAt)                                   ; Load its raw byte length.
    LD   B,A                                                    ; Copy length to B for recognisers.
    RET                                                         ; Return without changing tokenizer state.
tkTabBeg: ; Begin immutable tokenizer lookup tables.
tkMapTab: ; Begin character/kind punctuation pairs.

; Single-byte punctuation table: raw ASCII byte followed by token kind.

    DB   $2C,tkComma                                            ; Map comma to its token kind.
    DB   $3A,tkColon                                            ; Map colon to its token kind.
    DB   $28,tkLParen                                           ; Map left parenthesis to its token kind.
    DB   $29,tkRParen                                           ; Map right parenthesis to its token kind.
    DB   $2B,tkPlus                                             ; Map plus to its token kind.
    DB   $2D,tkMinus                                            ; Map minus to its token kind.
    DB   $2A,tkStar                                             ; Map asterisk to multiplication.
    DB   $2F,tkSlash                                            ; Map slash to division.
    DB   $26,tkAmp                                              ; Map ampersand to bitwise AND.
    DB   $5E,tkCaret                                            ; Map caret to bitwise XOR.
    DB   $7C,tkPipe                                             ; Map vertical bar to bitwise OR.
    DB   $7E,tkTilde                                            ; Map tilde to bitwise complement.
    DB   $27,tkApost                                            ; Apostrophe context handled above.
tkMapEnd: ; Mark the end of punctuation pairs.
tkMapCnt    EQU     (tkMapEnd-tkMapTab)/2                       ; Count two-byte table entries.
tkEscTab: ; Begin source-byte/decoded-byte escape pairs.

; Escape table pairs source byte with decoded value: 0, n, r, t, quotes and
; backslash.

    DB   $30,0,$6E,$0A,$72,$0D,$74,$09,$27,$27,$22,$22,$5C,$5C  ; Escapes.
tkEscCnt    EQU     7                                           ; Number of fixed escape pairs.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
; Search seven fixed escape pairs. Matching CP clears carry. Not found
; returns carry set without inventing a decoded byte.

tkUnEsc: ; Decode a fixed escape selector with carry set on failure.
    LD   HL,tkEscTab                                            ; Point at the first source/decoded pair.
    LD   C,tkEscCnt                                             ; Load the number of pairs to search.
.loop: ; Compare one escape selector per iteration.
    CP   (HL)                                                   ; Does A match this source selector?
    JR   Z,.found                                               ; Return its decoded value when equal.
    INC  HL                                                     ; Skip the unmatched source byte.
    INC  HL                                                     ; Skip its decoded value.
    DEC  C                                                      ; Account for the rejected pair.
    JR   NZ,.loop                                               ; Continue through all seven entries.
    SCF                                                         ; Report an unsupported selector.
    RET                                                         ; Leave no invented decoded byte.
.found: ; Load a matched escape's decoded value.
    INC  HL                                                     ; Advance to decoded byte.
    LD   A,(HL)                                                 ; Return that decoded byte in A.
    RET                                                         ; Matching CP already left carry clear.

;@ROUTINE IN A OUT A,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Zero is set for either accepted physical line-ending byte.

tkIsEol: ; Classify LF or CR through the zero flag.
    CP   $0A                                                    ; Is A an LF byte?
    RET  Z                                                      ; Return zero immediately when it is.
    CP   $0D                                                    ; Else compare with CR.
    RET                                                         ; Zero means LF or CR.
tkTabEnd: ; Mark the end of tokenizer immutable tables.
tkEnd: ; Mark the end of executable tokenizer code.
tkRamLo: ; Begin fixed tokenizer workspace.

; Absolute base used only by the checked memory-backed source provider.

tkSrcBeg:     DW      0                                         ; Absolute base of the checked memory source.

; Relative offset of the next unread source byte and validated part length.

tkHead:    DW      0                                            ; Relative offset of the next physical read.
tkSrcLen:   DW      0                                           ; Validated source-part byte length.

; Logical byte offset used for token starts and diagnostics.

tkTokPos:     DW      0                                         ; Next token's logical source offset.

; Current source-part ordinal supplied to every source-service call.

tkPart:    DB      0                                            ; Current eight-bit source-part ordinal.

; Nonzero after at least one token on the current physical line.

tkSeen:    DB      0                                            ; Nonzero after a token on the physical line.

; Nonzero after final synthetic EOL, preventing a second one.

tkEolOut:   DB      0                                           ; Nonzero after the final synthetic EOL.

; Pointer to the fixed token buffer and current raw byte count.

tkLexPtr:     DW      0                                         ; Pointer to the fixed lexeme buffer.
tkUsed:    DB      0                                            ; Tentative raw byte count, allowed to wrap.

; Most recently consumed raw byte, used to disambiguate apostrophe.

tkPrevCh:    DB      0                                          ; Most recently consumed source byte.

; Tentative token's starting logical offset, raw length and decoded value.

tkMark:    DW      0                                            ; Tentative token's logical starting offset.
tkLexLen:    DB      0                                          ; Accepted raw lexeme length or failure status.
tkValue:    DW      0                                           ; Value or failure part/offset bytes.

; Prefix/suffix scanners use this as digit-seen or remaining count.

tkDigits:    DB      0                                          ; Digit flag or remaining count.

; On failure the temporary length/value/count cells become status, part and
; offset storage. The public token record remains untouched.

tkStatus    EQU     tkLexLen                                    ; Overlay lexical status on tentative length.
tkErrPos    EQU     tkValue                                     ; Overlay failure part on value low byte.
tkErrOff    EQU     tkValue+1                                   ; Offset spans value high byte and digit count.

; Published token record, followed by its 256-byte transient lexeme buffer.

tkRecord:     DS      tkRecLen                                  ; Stable nine-byte public token record.
tkLexBuf:     DS      256                                       ; Transient raw lexeme buffer.
tkRamHi: ; End fixed tokenizer workspace.
