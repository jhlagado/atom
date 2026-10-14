;@ROUTINE OUT A,IX,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
; B counts raw bytes, including quotes and escapes. Consume the
; opening quote, then validate each byte without decoding the stored lexeme.

tkString: ; Validate a quoted string while retaining its raw bytes.
    LD   B,0                            ; Start raw token length at zero.
    CALL .take                          ; Consume and count the opening quote.
    JP   C,tkFail                       ; Publish EOF or length failure.
.loop: ; Validate one raw string byte per iteration.
    CALL .take                          ; Consume and count the next source byte.
    JP   C,tkFail                       ; Report EOF or length failure.
    CALL tkIsEol                        ; Is this byte CR or LF?
    JR   Z,tkErrStr                     ; A line end cannot close a string.

; Raw control bytes and DEL are never valid inside a quoted string.

    CP   $20                            ; First printable ASCII byte.
    JR   C,tkErrSrc                     ; Reject other raw control bytes.
    CP   $7F                            ; Compare with DEL.
    JR   NC,tkErrSrc                    ; Reject DEL and higher bytes.
    CP   $22                            ; Is this the closing double quote?
    JR   Z,.done                        ; Closing quote is already counted.

; Ordinary printable bytes need no further work. Backslash introduces either a
; table escape or the special two-digit hexadecimal escape.

    CP   $5C                            ; Is this an escape-introducing backslash?
    JR   NZ,.loop                       ; Continue for an ordinary printable byte.
    CALL .take                          ; Consume and count the escape selector.
    JP   C,tkFail                       ; Report truncated/overlong escape.
    CP   $78                            ; Does lowercase x introduce a hex escape?
    JR   Z,.hexEsc                      ; Validate exactly two hexadecimal digits.
    CALL tkUnEsc                        ; Validate a standard one-character escape.
    JR   C,tkErrEsc                     ; Diagnose an unsupported selector.
    JR   .loop                          ; Continue after the complete escape.
.hexEsc: ; Validate two digits after backslash-x.

; Both hex digits must be present and valid. The statement emitter decodes
; them later because string tokens retain raw source bytes.

    CALL .take                          ; Consume and count high hex digit.
    JP   C,tkFail                       ; Report truncated escape/full buffer.
    CALL tkNibble                       ; Require a hexadecimal value 0..15.
    JR   NC,tkErrEsc                    ; Reject an invalid first digit.
    CALL .take                          ; Consume and count low hex digit.
    JP   C,tkFail                       ; Report truncated escape/full buffer.
    CALL tkNibble                       ; Require another hexadecimal value 0..15.
    JR   NC,tkErrEsc                    ; Reject an invalid second digit.
    JR   .loop                          ; Resume raw string scanning.
.done: ; Publish the complete raw quoted lexeme.

; The closing quote has already been consumed and counted.

    LD   A,B                            ; Move the complete raw length into A.
    LD   (tkLexLen),A                   ; Save length for record publication.
    LD   A,tkStr                        ; Select the string token kind.
    JP   tkFinish                       ; Publish and mark line nonempty.

;@ROUTINE IN B OUT A,B,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Consume one string byte and count it. A zero result after INC
; means 256 bytes were attempted and the fixed token buffer is full.

.take: ; Consume and count a string byte with EOF and length checks.
    CALL tkTake                         ; Consume and buffer one raw string byte.
    JR   C,.eof                         ; EOF means unterminated string.
    INC  B                              ; Increase the complete raw string length.
    RET  NZ                             ; Return byte while length is valid.
    LD   A,tkStrBig                     ; Wrapped count means byte 256.
    SCF                                 ; Mark the string as too long.
    RET                                 ; Caller routes status through tkFail.
.eof: ; Return EOF while inside a string token.

; EOF while a string scanner expects another byte is an unterminated string.

    LD   A,tkStrCut                     ; Select unterminated-string status.
    SCF                                 ; Mark bounded consumption as failed.
    RET                                 ; Return for atomic failure publication.
tkErrEsc: ; Publish invalid-escape status.
    LD   A,tkBadEsc                     ; Select the unsupported-escape diagnostic.
    JP   tkFail                         ; Rewind to the token start.
tkErrStr: ; Publish unterminated-string status.
    LD   A,tkStrCut                     ; Select missing closing quote.
    JP   tkFail                         ; Rewind to the opening quote.
tkErrCut: ; Publish unterminated-character status.
    LD   A,tkLitCut                     ; Select missing character quote.
    JP   tkFail                         ; Rewind to the opening apostrophe.
tkErrLit: ; Publish invalid-character status.
    LD   A,tkBadLit                     ; Select malformed character contents.
    JP   tkFail                         ; Rewind to the opening apostrophe.
tkErrSrc: ; Publish invalid-input-byte status.
    LD   A,tkBadSrc                     ; Select invalid-byte status.
    JP   tkFail                         ; Rewind and keep prior record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,A
; Enter semicolon-comment consumption.

tkSkip: ; Discard a semicolon comment up to the physical line boundary.
.loop: ; Discard bytes up to line ending.

; Discard comment bytes but leave CR/LF. The line-ending path
; emits EOL only when tkSeen records an earlier token on this physical line.

    CALL tkPeek                         ; Inspect next byte without consuming.
    RET  C                              ; Stop cleanly at part EOF.
    CALL tkIsEol                        ; Is the byte CR or LF?
    RET  Z                              ; Leave line end for main token loop.
    CALL tkTake                         ; Consume/discard comment byte.
    JR   .loop                          ; Continue to the line boundary or EOF.
