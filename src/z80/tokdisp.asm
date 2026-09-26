;==========================================================================
;  Token dispatch, character literals and tokenizer storage
;==========================================================================
;
;  Continue the streaming tokenizer after token.asm's source access and
;  lexeme scanners. TK_NEXT classifies the next byte, delegates compound
;  forms and publishes a stable token record. This part also owns character
;  literals, immutable lookup tables and fixed workspace.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IY
; Enter publication of the next source token.

TK_NEXT:
.NEXTLOOP:                     ; Skip separators until token or EOF.

; Begin a tentative token at the current offset, then classify its first byte.

    CALL TK_BEG                    ; Capture start and clear fields.
    CALL TK_SPEEK                  ; Inspect the first unconsumed source byte.
    JP   C,.ATEOF                  ; Handle EOL or EOF at part end.
    CP   $20                       ; Is the byte an ASCII space?
    JR   Z,.SKIPB                  ; Consume it as an invisible separator.
    CP   $09                       ; Is the byte a horizontal tab?
    JR   Z,.SKIPB                  ; Consume it as an invisible separator.
    CP   $0A                       ; Is the byte a one-byte LF line ending?
    JP   Z,.LF                     ; Handle one-byte LF ending.
    CP   $0D                       ; Does the byte begin a CRLF pair?
    JP   Z,.CRLF                   ; Require and consume both bytes.
    CP   $3B                       ; Is the byte a semicolon comment marker?
    JR   Z,.COMMENT                ; Discard through the physical line end.

; Period begins a private name; the scanner rejects a bare period.

    CP   $2E                       ; Is this a private-name period?
    JP   Z,TK_SNAME                ; Validate the private-name payload.
    CP   $22                       ; Is this a string opener?
    JP   Z,TK_SSTRI                ; Scan the raw quoted string.
    CP   $27                       ; Apostrophe or character opener?
    JP   Z,.APOSTROP               ; Resolve from source context.
    CP   $24                       ; Current address or hex prefix?
    JR   Z,.DOLLAR                 ; Choose using lookahead.
    CP   $25                       ; Remainder or binary prefix?
    JR   Z,.PERCENT                ; Use lookahead and line state.
    CP   $3C                       ; Could this begin the `<<` operator?
    JP   Z,.LSHIFT                 ; Require a second matching byte.
    CP   $3E                       ; Could this begin the `>>` operator?
    JP   Z,.RSHIFT                 ; Require a second matching byte.
    CP   $30                       ; Compare with the first decimal digit.
    JR   C,.TRYNAME                ; Earlier bytes may start a name.
    CP   $39+1                     ; Is this byte in ASCII 0..9?
    JP   C,TK_SDLED                ; Scan the complete digit-led candidate.
.TRYNAME:                      ; Try a global name start.

; Remaining ASCII name-start bytes enter the name scanner.

    CALL TK_INBEG                  ; Accept ASCII letters or underscore.
    JP   C,TK_SNAME                ; Scan the complete name when accepted.

; Single-byte punctuation is a compact (character, token-kind) table. Shifts,
; apostrophe, '$' and '%' need context beyond this byte.

    LD   HL,TK_PTABL               ; Start character/kind table.
    LD   B,TK_PCNT                 ; Count single-byte punctuation forms.
.PLOOP:                        ; Search one punctuation pair per iteration.
    CP   (HL)                      ; Match source byte with table entry.
    INC  HL                        ; Advance to the corresponding token kind.
    JR   Z,.PUNCTUAT               ; Publish the matching punctuation form.
    INC  HL                        ; Skip the unmatched kind byte.
    DJNZ .PLOOP                   ; Continue through the complete table.
    JR   TK_IB                    ; No lexical class accepts this source byte.
.PUNCTUAT:                     ; Consume one matched punctuation byte.
    LD   C,(HL)                    ; Save its token kind in C.
    CALL TK_STAKE                  ; Consume and buffer the source character.
    LD   A,1                       ; Set the raw lexeme length to one.
    JR   .FPUNCTUA                ; Publish the table-selected token kind.
.SKIPB:                        ; Consume one invisible horizontal separator.

; Spaces and tabs separate tokens but never appear in a token record.

    CALL TK_STAKE                  ; Advance past the space or tab.
    JR   .NEXTLOOP                ; Start next tentative token.
.COMMENT:                      ; Consume but do not publish a source comment.
    CALL TK_SCOMM                  ; Stop before CR/LF or at EOF.
    JR   .NEXTLOOP                ; Let line-ending or EOF logic run next.
.DOLLAR:                       ; Classify '$' using one-byte lookahead.

; Consume '$' and inspect the next byte. A valid hexadecimal digit selects a
; prefixed number; otherwise a standalone '$' denotes the current location.

    CALL TK_STAKE                  ; Consume and buffer the dollar sign.
    CALL TK_SPEEK                  ; Look ahead without consuming.
    JR   C,.CLOCATIO               ; Final '$' means current address.
    LD   B,A                       ; Preserve the following raw byte.
    CALL TK_HDIGI                  ; Test whether it begins a hex value.
    JR   C,.DNUMBER                ; Scan prefixed hex value.

; A following name-continuation byte makes the entire numeric-looking form
; invalid, preventing '$G' from becoming current-location followed by a name.

    LD   A,B                       ; Restore the following raw byte.
    CALL TK_INB                    ; Could it continue a digit-led candidate?
    JP   C,TK_INUMB                ; Reject the entire malformed form.
.CLOCATIO:                     ; Publish current-address punctuation.
    LD   A,1                       ; Raw lexeme is '$' alone.
    LD   (TK_SLEN),A               ; Save the public lexeme length.
    LD   A,TK_CUR                  ; Select the current-location token kind.
    JP   TK_FIN                    ; Publish and mark line nonempty.
.DNUMBER:                      ; Scan a dollar-prefixed hexadecimal literal.

; Raw length includes '$'; bit 2 in C selects hex accumulation.

    LD   B,1                       ; Count the already consumed prefix.
    LD   C,4                       ; Bit 2 selects hexadecimal.
    JP   TK_SBASE                  ; Decode and publish remaining digits.
.PERCENT:                      ; Classify '%' using one-byte lookahead.

; Percent begins binary only when followed by 0 or 1. Otherwise it is the
; remainder operator, subject to the leaked-host-directive guard below.

    CALL TK_STAKE                  ; Consume and buffer the percent sign.
    CALL TK_SPEEK                  ; Inspect the following byte.
    JR   C,.PTOK                   ; At EOF, '%' means remainder.
    CP   $30                       ; Does ASCII zero begin a binary literal?
    JR   Z,.PNUMBER                ; Decode the prefixed binary value.
    CP   $31                       ; Does ASCII one begin a binary literal?
    JR   Z,.PNUMBER                ; Decode the prefixed binary value.
    CALL TK_ILETT                  ; Could this be a leaked `%DIRECTIVE` name?
    JR   NC,.PTOK                  ; Non-letter leaves punctuation.

; Before the first token on a line, "%" plus a letter can only be an unmasked
; host directive. Reject it before expression parsing.

    LD   A,(TK_LHTOK)              ; Did this line emit a token yet?
    OR   A                         ; Only line-start `%name` is host syntax.
    JR   NZ,.PTOK                  ; Elsewhere publish the remainder operator.
    LD   A,TK_SUDIR                ; Select unprocessed-host-directive status.
    JP   TK_FAIL                   ; Rewind to the percent sign and report it.
.PTOK:                         ; Publish standalone remainder punctuation.
    LD   A,1                       ; Its raw lexeme length is one.
    LD   (TK_SLEN),A               ; Save that length for the public record.
    LD   A,TK_PERCE                ; Select the remainder token kind.
    JP   TK_FIN                    ; Mark the line non-empty and publish.
.PNUMBER:                      ; Scan a percent-prefixed binary literal.

; Raw length already includes '%'; C=1 selects binary accumulation.

    LD   B,1                       ; Count the already consumed prefix.
    LD   C,1                       ; Select binary accumulation.
    JP   TK_SBASE                  ; Decode remaining digits and publish.
.LSHIFT:                       ; Prepare a left-shift token.
    LD   C,TK_LSHIF                ; Save the published left-shift kind.
    JR   .SHIFT                   ; Validate the doubled punctuation.
.RSHIFT:                       ; Prepare a right-shift token.
    LD   C,TK_RSHIF                ; Save the published right-shift kind.
.SHIFT:                        ; Require and consume two equal shift bytes.

; A shift operator is valid only as a doubled matching character, << or >>.

    LD   B,A                       ; Preserve the opening '<' or '>' byte.
    CALL TK_STAKE                  ; Consume and buffer the first character.
    CALL TK_SPEEK                  ; Inspect the required second character.
    JP   C,TK_IB                   ; Diagnose a shift truncated by EOF.
    CP   B                         ; Does it match the opening character?
    JP   NZ,TK_IB                  ; Reject a single or mixed angle bracket.
    CALL TK_STAKE                  ; Consume and buffer the second character.
    LD   A,2                       ; Set the raw shift lexeme length.
.FPUNCTUA:                     ; Publish punctuation kind C with length A.
    LD   (TK_SLEN),A               ; Save the raw punctuation length.
    LD   A,C                       ; Restore the selected token kind.
    JP   TK_FIN                    ; Mark the line non-empty and publish it.
.LF:                           ; Consume a one-byte LF line ending.

; LF ends a line. CR requires LF and is otherwise invalid.

    CALL TK_STAKE                  ; Consume and buffer the LF byte.
    LD   A,1                       ; Record its one-byte raw length.
    LD   (TK_SLEN),A               ; Save possible EOL length.
    JR   .FINLINE                 ; Apply blank-line suppression.
.CRLF:                         ; Consume and validate a two-byte CRLF ending.
    CALL TK_STAKE                  ; Consume and buffer the CR byte.
    CALL TK_SPEEK                  ; Inspect the mandatory following byte.
    JP   C,TK_IB                   ; A terminal bare CR is invalid input.
    CP   $0A                       ; Require LF immediately after CR.
    JP   NZ,TK_IB                  ; Reject any other following byte.
    CALL TK_STAKE                  ; Consume and buffer the LF byte.
    LD   A,2                       ; Record the two-byte raw line ending.
    LD   (TK_SLEN),A               ; Save possible EOL length.
.FINLINE:                      ; Decide whether to publish EOL.

; A physical ending clears synthetic-EOL state. If no token appeared on the
; line, suppress EOL and continue scanning the next physical line.

    XOR  A                         ; Clear the synthetic-EOL pending state.
    LD   (TK_EPEND),A              ; Physical ending clears synthetic state.
    LD   A,(TK_LHTOK)              ; Did this physical line contain a token?
    OR   A                         ; Zero means blank/comment-only line.
    JP   Z,.NEXTLOOP               ; Suppress EOL and scan the following line.
    XOR  A                         ; Construct the next-line token-free state.
    LD   (TK_LHTOK),A              ; Publish that state before returning EOL.
    LD   A,TK_EOL                  ; Select the end-of-line token kind.
    JP   TK_CMT                    ; Publish without marking new line.
.ATEOF:                        ; Handle the current source-part endpoint.

; EOF after a non-empty unterminated final line first publishes one synthetic
; EOL. TK_EPEND ensures the following and all later calls return EOF instead.

    LD   A,(TK_EPEND)              ; Synthetic EOL already emitted?
    OR   A                         ; Nonzero makes EOF repeatable immediately.
    JR   NZ,.EMITEOF               ; Publish EOF on this and all later calls.
    LD   A,(TK_LHTOK)              ; Final line had a token?
    OR   A                         ; Zero needs no synthetic line boundary.
    JR   Z,.EMITEOF                ; Publish EOF for an empty final line.
    XOR  A                         ; Construct cleared line state.
    LD   (TK_LHTOK),A              ; Mark the final line as closed.
    INC  A                         ; Mark synthetic EOL emitted.
    LD   (TK_EPEND),A              ; Ensure the next call emits EOF instead.
    XOR  A                         ; A synthetic EOL has no raw lexeme bytes.
    LD   (TK_SLEN),A               ; Publish a zero raw length.
    LD   A,TK_EOL                  ; Select the synthetic EOL token kind.
    JP   TK_CMT                    ; Publish it at the current end offset.
.EMITEOF:                      ; Publish repeatable end-of-part.

; EOF has kind and length zero; TK_CMT fills in current part and offset.

    XOR  A                         ; EOF kind and length are zero.
    LD   (TK_SLEN),A               ; Publish an empty lexeme.
    JP   TK_CMT                    ; Fill location and return stable EOF.
.APOSTROP:                     ; Choose punctuation or character.

; Apostrophe is ambiguous with a character literal. At the start of a source
; part or after a non-name byte, it opens a character. Directly after a name
; byte it remains punctuation, preserving forms such as AF'.

    LD   HL,(TK_SOFF1)             ; Load apostrophe's part offset.
    LD   A,H                       ; Test whether it is the first source byte.
    OR   L                         ; Zero means no preceding byte exists.
    JR   Z,TK_SCHAR                ; First byte opens a character.
    LD   A,(TK_PREV)               ; Load the previously consumed source byte.
    CALL TK_INB                    ; Could it end a name such as AF?
    JR   NC,TK_SCHAR               ; Non-name byte opens a character.

; Emit the punctuation form as a one-byte token.

    CALL TK_STAKE                  ; Buffer punctuation apostrophe.
    LD   A,1                       ; Its raw lexeme length is one.
    LD   (TK_SLEN),A               ; Save the length for record publication.
    LD   A,TK_APOST                ; Select the apostrophe token kind.
    JP   TK_FIN                    ; Mark the line non-empty and publish.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; B begins at one for the opener. Consume it and the first payload byte.
; EOF or a line ending in this initial position is an unterminated character;
; line endings reached later inside an escape are invalid escapes instead.

TK_SCHAR:
    LD   B,1                       ; Count the opening apostrophe in advance.
    CALL TK_STAKE                  ; Buffer opening apostrophe.
    CALL TK_STAKE                  ; Read first payload or close.
    JP   C,TK_UCHAR                ; Diagnose EOF before a complete character.
    INC  B                         ; Count the consumed payload byte.
    CALL TK_ILEND                  ; Is the payload byte CR or LF?
    JP   Z,TK_UCHAR                ; Line end truncates character.

; An immediate close is an empty character literal. Backslash enters the
; shared escape language; an ordinary payload must be printable ASCII.

    CP   $27                       ; Was this an empty literal?
    JP   Z,TK_ICHAR                ; Reject a character with no decoded byte.
    CP   $5C                       ; Does backslash introduce an escape?
    JR   Z,.SCESCAPE               ; Decode the escape language.
    CP   $20                       ; Compare with printable ASCII.
    JP   C,TK_IB                   ; Reject raw control bytes.
    CP   $7F                       ; Compare with DEL.
    JP   NC,TK_IB                  ; Reject DEL and higher bytes.
    LD   (TK_SVAL),A               ; Save decoded character byte.
    JR   .SCCLOSE                 ; Require one closing apostrophe next.
.SCESCAPE:                     ; Decode one escaped character payload.

; Decode and count the selector after backslash. Table entries yield one byte;
; \x consumes two additional hexadecimal digits.

    CALL TK_STAKE                  ; Consume and buffer the escape selector.
    JP   C,TK_UCHAR                ; Diagnose EOF before the selector.
    INC  B                         ; Count the selector in the raw lexeme.
    CP   $78                       ; Does lowercase x select a hex escape?
    JR   Z,.SCHEX                  ; Decode exactly two hexadecimal digits.
    CALL TK_DESCA                  ; Decode a standard one-character escape.
    JP   C,TK_IESCA                ; Reject selector not in table.
    LD   (TK_SVAL),A               ; Store the decoded character byte.
    JR   .SCCLOSE                 ; Require the closing apostrophe.
.SCHEX:                        ; Decode a two-digit hexadecimal escape.

; Decode high nibble into TK_SVAL, then read low nibble.

    CALL TK_STAKE                  ; Buffer high hex digit.
    JP   C,TK_UCHAR                ; Diagnose EOF before that digit.
    INC  B                         ; Count the high digit in the raw lexeme.
    CALL TK_HDIGI                  ; Decode it to a nibble.
    JP   NC,TK_IESCA               ; Reject a non-hexadecimal digit.
    ADD  A,A                       ; Shift the nibble left one place.
    ADD  A,A                       ; Shift it left two places.
    ADD  A,A                       ; Shift it left three places.
    ADD  A,A                       ; Place it in bits 4..7.
    LD   (TK_SVAL),A               ; Save high nibble during low read.
    CALL TK_STAKE                  ; Buffer low hex digit.
    JP   C,TK_UCHAR                ; Diagnose EOF before that digit.
    INC  B                         ; Count the low digit in the raw lexeme.
    CALL TK_HDIGI                  ; Decode it to a low nibble.
    JP   NC,TK_IESCA               ; Reject a non-hexadecimal digit.
    LD   HL,TK_SVAL                ; Point at the retained high nibble.
    OR   (HL)                      ; Combine it with the decoded low nibble.
    LD   (TK_SVAL),A               ; Save decoded byte.
.SCCLOSE:                      ; Require the literal's closing apostrophe.

; One decoded byte is ready. The next raw byte must be the closing
; apostrophe and becomes part of the published raw lexeme length.

    CALL TK_STAKE                  ; Buffer required closing byte.
    JP   C,TK_UCHAR                ; Diagnose EOF before the close.
    INC  B                         ; Include it in the raw lexeme length.
    CALL TK_ILEND                  ; Is close a line ending?
    JP   Z,TK_UCHAR                ; Report unterminated character.
    CP   $27                       ; Require immediate apostrophe.
    JP   NZ,TK_ICHAR               ; Reject extra payload/wrong delimiter.
    JP   TK_FNLEN                  ; Publish decoded byte as number.
TK_RCEND:                      ; End tokenizer rule-code measurement.

;@ROUTINE OUT A,B,HL
; Return the current token's lexeme pointer and raw length. This is
; intentionally a borrowed view whose lifetime ends at the next TK_NEXT call.

TK_LLEXE:
    LD   HL,(TK_REC+TK_LOFF)       ; Return published lexeme pointer.
    LD   A,(TK_REC+TK_LOFF1)       ; Load its raw byte length.
    LD   B,A                       ; Copy length to B for recognizers.
    RET                            ; Return without changing tokenizer state.
TK_IBEG:                       ; Begin immutable tokenizer lookup tables.
TK_PTABL:                      ; Begin character/kind punctuation pairs.

; Single-byte punctuation table: raw ASCII byte followed by token kind.

    DB $2C,TK_COMMA                ; Map comma to its token kind.
    DB $3A,TK_COLON                ; Map colon to its token kind.
    DB $28,TK_LPARE                ; Map left parenthesis to its token kind.
    DB $29,TK_RPARE                ; Map right parenthesis to its token kind.
    DB $2B,TK_PLUS                 ; Map plus to its token kind.
    DB $2D,TK_MINUS                ; Map minus to its token kind.
    DB $2A,TK_STAR                 ; Map asterisk to multiplication.
    DB $2F,TK_SLASH                ; Map slash to division.
    DB $26,TK_AMPER                ; Map ampersand to bitwise AND.
    DB $5E,TK_CARET                ; Map caret to bitwise XOR.
    DB $7C,TK_PIPE                 ; Map vertical bar to bitwise OR.
    DB $7E,TK_TILDE                ; Map tilde to bitwise complement.
    DB $27,TK_APOST                ; Apostrophe context handled above.
TK_PEND:                       ; Mark the end of punctuation pairs.
TK_PCNT EQU (TK_PEND-TK_PTABL)/2  ; Count two-byte table entries.
TK_ETABL:                      ; Begin source-byte/decoded-byte escape pairs.

; Escape table pairs source byte with decoded value: 0, n, r, t, quotes and
; backslash.

    DB $30,0,$6E,$0A,$72,$0D,$74,$09,$27,$27,$22,$22,$5C,$5C  ; Escapes.
TK_ECNT EQU 7                  ; Number of fixed escape pairs.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
; Search seven fixed escape pairs. Matching CP clears carry; not found
; returns carry set without inventing a decoded byte.

TK_DESCA:
    LD   HL,TK_ETABL               ; Point at the first source/decoded pair.
    LD   C,TK_ECNT                 ; Load the number of pairs to search.
.DELOOP:                       ; Compare one escape selector per iteration.
    CP   (HL)                      ; Does A match this source selector?
    JR   Z,.DEFOUND                ; Return its decoded value when equal.
    INC  HL                        ; Skip the unmatched source byte.
    INC  HL                        ; Skip its decoded value.
    DEC  C                         ; Account for the rejected pair.
    JR   NZ,.DELOOP                ; Continue through all seven entries.
    SCF                            ; Report an unsupported selector.
    RET                            ; Leave no invented decoded byte.
.DEFOUND:                      ; Load a matched escape's decoded value.
    INC  HL                        ; Advance to decoded byte.
    LD   A,(HL)                    ; Return that decoded byte in A.
    RET                            ; Matching CP already left carry clear.

;@ROUTINE IN A OUT A,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Zero is set for either accepted physical line-ending byte.

TK_ILEND:
    CP   $0A                       ; Is A an LF byte?
    RET  Z                         ; Return zero immediately when it is.
    CP   $0D                       ; Else compare with CR.
    RET                            ; Zero means LF or CR.
TK_IEND:                       ; Mark the end of tokenizer immutable tables.
TK_CEND:                       ; Mark the end of executable tokenizer code.
TK_WBEG:                       ; Begin fixed tokenizer workspace.

; Absolute base used only by the checked memory-backed source provider.

TK_SRCBA: DW 0                 ; Absolute base of the checked memory source.

; Relative offset of the next unread source byte and validated part length.

TK_SCURS: DW 0                 ; Relative offset of the next physical read.
TK_SEND: DW 0                  ; Validated source-part byte length.

; Logical byte offset used for token starts and diagnostics.

TK_SOSTA: DW 0                 ; Next token's logical source offset.

; Current source-part ordinal supplied to every source-service call.

TK_SPART: DB 0                 ; Current eight-bit source-part ordinal.

; Nonzero after at least one token on the current physical line.

TK_LHTOK: DB 0                 ; Nonzero after a token on the physical line.

; Nonzero after final synthetic EOL, preventing a second one.

TK_EPEND: DB 0                 ; Nonzero after the final synthetic EOL.

; Pointer to the fixed token buffer and current raw byte count.

TK_SPTR: DW 0                  ; Pointer to the fixed lexeme buffer.
TK_BCNT: DB 0                  ; Tentative raw byte count, allowed to wrap.

; Most recently consumed raw byte, used to disambiguate apostrophe.

TK_PREV: DB 0                  ; Most recently consumed source byte.

; Tentative token's starting logical offset, raw length and decoded value.

TK_SOFF1: DW 0                 ; Tentative token's logical starting offset.
TK_SLEN: DB 0                  ; Accepted raw lexeme length or failure status.
TK_SVAL: DW 0                  ; Value or failure part/offset bytes.

; Prefix/suffix scanners use this as digit-seen or remaining count.

TK_DSEEN: DB 0                 ; Digit flag or remaining count.

; On failure the temporary length/value/count cells become status, part and
; offset storage. The public token record remains untouched.

TK_ESTAT EQU TK_SLEN           ; Overlay lexical status on tentative length.
TK_EPART EQU TK_SVAL           ; Overlay failure part on value low byte.
TK_EOFF EQU TK_SVAL+1          ; Offset spans value high byte and digit count.

; Published token record, followed by its 256-byte transient lexeme buffer.

TK_REC: DS TK_RECB             ; Stable nine-byte public token record.
TK_TBUF: DS 256                ; Transient raw lexeme buffer.
TK_WEND:                       ; End fixed tokenizer workspace.
