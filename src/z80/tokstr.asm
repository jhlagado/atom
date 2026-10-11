;@ROUTINE OUT A,IX,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
; B counts raw bytes, including quotes and escapes. Consume the
; opening quote, then validate each byte without decoding the stored lexeme.

TK_SSTR: ; Validate a quoted string while retaining its raw bytes.
    LD   B,0                            ; Start raw token length at zero.
    CALL .TAKE                          ; Consume and count the opening quote.
    JP   C,TK_FAIL                      ; Publish EOF or length failure.
.LOOP: ; Validate one raw string byte per iteration.
    CALL .TAKE                          ; Consume and count the next source byte.
    JP   C,TK_FAIL                      ; Report EOF or length failure.
    CALL TK_ISEOL                       ; Is this byte CR or LF?
    JR   Z,TK_USTR                      ; A line end cannot close a string.

; Raw control bytes and DEL are never valid inside a quoted string.

    CP   $20                            ; First printable ASCII byte.
    JR   C,TK_IBYTE                     ; Reject other raw control bytes.
    CP   $7F                            ; Compare with DEL.
    JR   NC,TK_IBYTE                    ; Reject DEL and higher bytes.
    CP   $22                            ; Is this the closing double quote?
    JR   Z,.DONE                        ; Closing quote is already counted.

; Ordinary printable bytes need no further work. Backslash introduces either a
; table escape or the special two-digit hexadecimal escape.

    CP   $5C                            ; Is this an escape-introducing backslash?
    JR   NZ,.LOOP                       ; Continue for an ordinary printable byte.
    CALL .TAKE                          ; Consume and count the escape selector.
    JP   C,TK_FAIL                      ; Report truncated/overlong escape.
    CP   $78                            ; Does lowercase x introduce a hex escape?
    JR   Z,.HEXESC                      ; Validate exactly two hexadecimal digits.
    CALL TK_UNESC                       ; Validate a standard one-character escape.
    JR   C,TK_IESC                      ; Diagnose an unsupported selector.
    JR   .LOOP                          ; Continue after the complete escape.
.HEXESC: ; Validate two digits after backslash-x.

; Both hex digits must be present and valid. The statement emitter decodes
; them later because string tokens retain raw source bytes.

    CALL .TAKE                          ; Consume and count high hex digit.
    JP   C,TK_FAIL                      ; Report truncated escape/full buffer.
    CALL TK_HEX                         ; Require a hexadecimal value 0..15.
    JR   NC,TK_IESC                     ; Reject an invalid first digit.
    CALL .TAKE                          ; Consume and count low hex digit.
    JP   C,TK_FAIL                      ; Report truncated escape/full buffer.
    CALL TK_HEX                         ; Require another hexadecimal value 0..15.
    JR   NC,TK_IESC                     ; Reject an invalid second digit.
    JR   .LOOP                          ; Resume raw string scanning.
.DONE: ; Publish the complete raw quoted lexeme.

; The closing quote has already been consumed and counted.

    LD   A,B                            ; Move the complete raw length into A.
    LD   (TK_SLEN),A                    ; Save length for record publication.
    LD   A,TK_STR                       ; Select the string token kind.
    JP   TK_FIN                         ; Publish and mark line nonempty.

;@ROUTINE IN B OUT A,B,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Consume one string byte and count it. A zero result after INC
; means 256 bytes were attempted and the fixed token buffer is full.

.TAKE: ; Consume and count a string byte with EOF and length checks.
    CALL TK_STAKE                       ; Consume and buffer one raw string byte.
    JR   C,.EOF                         ; EOF means unterminated string.
    INC  B                              ; Increase the complete raw string length.
    RET  NZ                             ; Return byte while length is valid.
    LD   A,TK_SFULL                     ; Wrapped count means byte 256.
    SCF                                 ; Mark the string as too long.
    RET                                 ; Caller routes status through TK_FAIL.
.EOF: ; Return EOF while inside a string token.

; EOF while a string scanner expects another byte is an unterminated string.

    LD   A,TK_SOPEN                     ; Select unterminated-string status.
    SCF                                 ; Mark bounded consumption as failed.
    RET                                 ; Return for atomic failure publication.
TK_IESC: ; Publish invalid-escape status.
    LD   A,TK_SESC                      ; Select the unsupported-escape diagnostic.
    JP   TK_FAIL                        ; Rewind to the token start.
TK_USTR: ; Publish unterminated-string status.
    LD   A,TK_SOPEN                     ; Select missing closing quote.
    JP   TK_FAIL                        ; Rewind to the opening quote.
TK_UCHAR: ; Publish unterminated-character status.
    LD   A,TK_SCUT                      ; Select missing character quote.
    JP   TK_FAIL                        ; Rewind to the opening apostrophe.
TK_ICHAR: ; Publish invalid-character status.
    LD   A,TK_SAPOS                     ; Select malformed character contents.
    JP   TK_FAIL                        ; Rewind to the opening apostrophe.
TK_IBYTE: ; Publish invalid-input-byte status.
    LD   A,TK_SBYTE                     ; Select invalid-byte status.
    JP   TK_FAIL                        ; Rewind and keep prior record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,A
; Enter semicolon-comment consumption.

TK_SKIP: ; Discard a semicolon comment up to the physical line boundary.
.LOOP: ; Discard bytes up to line ending.

; Discard comment bytes but leave CR/LF. The line-ending path
; emits EOL only when TK_SEEN records an earlier token on this physical line.

    CALL TK_SPEEK                       ; Inspect next byte without consuming.
    RET  C                              ; Stop cleanly at part EOF.
    CALL TK_ISEOL                       ; Is the byte CR or LF?
    RET  Z                              ; Leave line end for main token loop.
    CALL TK_STAKE                       ; Consume/discard comment byte.
    JR   .LOOP                          ; Continue to the line boundary or EOF.
