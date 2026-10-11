ST_DODS: ; Parse DS reservation count and optional repeated fill byte.

; DS count must be concrete. Without comma it reserves a gap. With
; a comma it emits count copies of the fill byte.

    CALL ST_PEXPR                       ; Evaluate the number of bytes to allocate.
    JP   C,ST_DFAIL                     ; Preserve nested expression failure detail.
    OR   A                              ; Test whether the count is unresolved.
    JP   NZ,ST_DUNRE                    ; DS requires a count immediately.
    LD   (ST_DCNT),HL                   ; Preserve the sixteen-bit allocation count.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token following the count.
    CP   TK_EOL                         ; Is this the uninitialised reserve form?
    JR   Z,ST_SKIP                      ; Yes: advance without emitting IMAGE bytes.
    CP   TK_COMMA                       ; Otherwise require a fill-value separator.
    JP   NZ,ST_DTAIL                    ; Reject any other trailing token.

; Parse the optional fill expression and require an immediate low-byte value.

    CALL TK_NEXT                        ; Consume comma. Expose the fill value.
    JP   C,ST_LFAIL                     ; Preserve a lexical failure after the comma.
    CALL ST_PEXPR                       ; Evaluate the repeated fill byte.
    JP   C,ST_DFAIL                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the fill expression unresolved?
    JP   NZ,ST_DUNRE                    ; A forward fill cannot use one patch.
    LD   A,L                            ; Select the expression's low byte as the fill.
    LD   (ST_DFILL),A                   ; Preserve it across capacity preflight.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token after the fill value.
    CP   TK_EOL                         ; DS accepts no third argument.
    JP   NZ,ST_DTAIL                    ; Reject any trailing token.

; Preflight the full range so the byte loop cannot fail for capacity
; after publishing only a prefix.

    LD   HL,(ST_DCNT)                   ; Supply the complete filled-range length.
    CALL OU_CAPOK                       ; Prove all bytes fit before the first write.
    JP   C,ST_OFAIL                     ; Preserve atomic capacity failure.
ST_FILL: ; Emit the next fill byte until the saved count reaches zero.

; Emit one fill byte per iteration. ST_DCNT reaches zero before returning
; to the outer statement loop.

    LD   HL,(ST_DCNT)                   ; Read the remaining fill-byte count.
    LD   A,H                            ; Fold the high count byte into the zero test.
    OR   L                              ; Z means every requested byte was emitted.
    JP   Z,ST_NEXT                      ; Finish the directive and begin the next line.
    LD   A,(ST_DFILL)                   ; Recover the repeated fill byte.
    CALL OU_EMITB                       ; Publish one byte from the preflighted range.
    JP   C,ST_OFAIL                     ; Preserve an unexpected sink failure.
    LD   HL,(ST_DCNT)                   ; Reload the remaining count after the call.
    DEC  HL                             ; Account for the byte just emitted.
    LD   (ST_DCNT),HL                   ; Persist the decremented count.
    JR   ST_FILL                        ; Emit the rest of the range.
ST_SKIP: ; Reserve the DS interval without initialising its bytes.

; The no-fill form advances the output cursor without creating IMAGE bytes.

    LD   HL,(ST_DCNT)                   ; Supply the byte count to reserve.
    CALL OU_SKIP                        ; Advance the cursor without IMAGE emission.
    JP   ST_OUTOK                       ; Check output status and continue.
ST_PAD: ; Calculate zero padding to the requested alignment boundary.

; ALIGN needs a positive 16-bit boundary. A nonzero extension or zero
; in the low word is outside the directive's domain.

    CALL ST_PEXPR                       ; Evaluate the requested alignment boundary.
    JP   C,ST_DFAIL                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the boundary unresolved?
    JP   NZ,ST_DUNRE                    ; ALIGN requires an immediate value.
    LD   A,(EX_RVAL+2)                  ; Read the expression's extension byte.
    OR   A                              ; Does the extension mark a negative boundary?
    JP   NZ,ST_DRNG                     ; Reject it outside the address domain.
    LD   A,H                            ; Begin testing the low word for zero.
    OR   L                              ; Z identifies the invalid boundary zero.
    JP   Z,ST_DRNG                      ; Reject division by a zero alignment.
    LD   (ST_DVAL),HL                   ; Preserve the validated boundary.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token following the expression.
    CP   TK_EOL                         ; ALIGN accepts exactly one argument.
    JP   NZ,ST_DTAIL                    ; Reject any trailing token.

; Use the expression divider for cursor modulo alignment. Both operands
; are explicitly zero-extended to 24 bits before EX_REM is called.

    LD   HL,(OU_ADDR)                   ; Load the current output address as dividend.
    LD   (EX_LVAL),HL                   ; Store the dividend's low word.
    XOR  A                              ; Form the common zero extension byte.
    LD   (EX_LVAL+2),A                  ; Zero-extend the current address to 24 bits.
    LD   HL,(ST_DVAL)                   ; Restore the alignment as divisor.
    LD   (EX_RVAL),HL                   ; Store the divisor's low word.
    LD   (EX_RVAL+2),A                  ; Zero-extend the divisor to 24 bits.
    CALL EX_REM                         ; Replace EX_RVAL with cursor modulo boundary.
    JP   C,ST_DFAIL                     ; Preserve any defensive arithmetic failure.

; A zero remainder is already aligned. Otherwise emit alignment - remainder
; zero bytes through the same preflighted fill loop used by DS count,fill.

    LD   HL,(EX_RVAL)                   ; Load the sixteen-bit remainder.
    LD   A,H                            ; Begin testing whether it is zero.
    OR   L                              ; Z means the cursor is aligned.
    JR   Z,.PADCOUNT                    ; Emit no padding in that case.
    EX   DE,HL                          ; Preserve the nonzero remainder in DE.
    LD   HL,(ST_DVAL)                   ; Reload the alignment boundary.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compute bytes to next boundary.
.PADCOUNT: ; Preflight the computed padding and enter the shared fill loop.
    LD   (ST_DCNT),HL                   ; Reuse the DS loop's remaining-byte counter.
    XOR  A                              ; ALIGN padding bytes are always zero.
    LD   (ST_DFILL),A                   ; Select zero as the repeated fill value.
    LD   HL,(ST_DCNT)                   ; Supply the complete padding length.
    CALL OU_CAPOK                       ; Preflight all padding before emitting any.
    JP   C,ST_OFAIL                     ; Preserve atomic output failure.
    JR   ST_FILL                        ; Emit through the shared fill loop.
ST_DONE: ; Return success for this part without closing private scope.

; EOF is a successful end of this source part, not the end of private scope or
; the complete build. The driver decides whether another part follows.

    XOR  A                              ; Return ST_SOK with carry clear.
    RET                                 ; Return control to the multipart driver.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Directive names have at most five characters. Pack the lexeme into the
; shared RADIX-40 scratch buffer for exact, case-insensitive comparison.

EN_ISDIR: ; Recognise a directive by exact packed-name comparison.
    LD   A,B                            ; Load the lexeme length for the bound check.
    CP   6                              ; Is it at most five characters?
    JR   NC,.NOTFOUND                   ; Six or more characters cannot match.
    LD   DE,EN_TMP                      ; Select the shared four-byte packing buffer.
    CALL EN_R40PK                       ; Pack case-insensitively into RADIX-40 words.
    RET  C                              ; Propagate a character or length rejection.
    LD   IX,.NAMES                      ; Point at the first packed directive entry.
    LD   B,ST_CNT                       ; Search every fixed-size table entry.
    LD   C,ST_EQU                       ; Track the one-based ordinal alongside IX.
.LOOP: ; Compare the four bytes of one packed directive entry.

; Compare four packed bytes. C tracks the one-based directive ordinal as
; IX advances through the fixed table.

    LD   A,(EN_TMP)                     ; Load packed byte zero.
    CP   (IX+0)                         ; Compare it with the candidate entry.
    JR   NZ,.NEXT                       ; Any mismatch rejects this candidate.
    LD   A,(EN_TMP+1)                   ; Load packed byte one.
    CP   (IX+1)                         ; Compare it with the candidate entry.
    JR   NZ,.NEXT                       ; Reject on mismatch.
    LD   A,(EN_TMP+2)                   ; Load packed byte two.
    CP   (IX+2)                         ; Compare it with the candidate entry.
    JR   NZ,.NEXT                       ; Reject on mismatch.
    LD   A,(EN_TMP+3)                   ; Load packed byte three.
    CP   (IX+3)                         ; Compare the final packed byte.
    JR   NZ,.NEXT                       ; Reject on mismatch.
    LD   A,C                            ; Return the matching directive ordinal.
    OR   A                              ; Clear carry while preserving that ordinal.
    RET                                 ; Report successful exact recognition.
.NEXT: ; Advance the packed-name pointer and its matching ordinal.
    LD   DE,4                           ; Each packed directive occupies four bytes.
    ADD  IX,DE                          ; Advance to the next table entry.
    INC  C                              ; Advance the corresponding ordinal.
    DJNZ .LOOP                          ; Continue until every entry has been compared.
.NOTFOUND: ; Return carry set when no directive name matches.

; Recognition failure returns carry set. A is deliberately cleared because no
; ordinal is valid.

    XOR  A                              ; Return no meaningful ordinal.
    SCF                                 ; Mark recognition failure.
    RET                                 ; Return to the statement classifier.
.NAMES: ; Packed directive names in one-based ordinal order.

; Packed RADIX-40 forms of EQU, ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN.

    DW   $21FD,$0000                    ; EQU
    DW   $6097,$0000                    ; ORG
    DW   $1950,$0000                    ; DB
    DW   $1C98,$0000                    ; DW
    DW   $1BF8,$0000                    ; DS
    DW   $15CC,$7080                    ; CSTR
    DW   $670C,$7080                    ; PSTR
    DW   $3B4C,$7080                    ; ISTR
    DW   $0829,$2DF0                    ; ALIGN

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Consume one raw byte. The source service receives the original part
; in A and offset in HL. Advance workspace only after
; the read, leaving A as the consumed character.

ST_TAKE: ; Read and advance the raw quoted-string cursor.
    LD   HL,(ST_SPTR)                   ; Load the next logical source-byte offset.
    LD   A,(ST_SPART)                   ; Supply its source-part ordinal.
    CALL TK_SREAD                       ; Fetch the byte through source service.
    LD   HL,(ST_SPTR)                   ; Reload the cursor after callback clobbering.
    INC  HL                             ; Advance to the following raw byte.
    LD   (ST_SPTR),HL                   ; Persist the new cursor.
    LD   HL,ST_SLEFT                    ; Address the raw-byte countdown.
    DEC  (HL)                           ; Account for the byte just consumed.
    RET                                 ; Return it in A to the decoder.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch a token and mirror its kind into A for compact statement dispatch.

ST_TOKEN: ; Fetch a token and mirror its kind while retaining carry.
    CALL TK_NEXT                        ; Fetch the next token record.
    LD   A,(TK_REC+TK_RKIND)            ; Mirror its kind into the dispatch register.
    RET                                 ; Return kind and tokenizer carry.

;@ROUTINE OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Expressions see the current output address in BC so '$' and relative forms
; have statement-accurate meaning.

ST_PEXPR: ; Evaluate with the current output cursor as dollar's value.
    LD   BC,(OU_ADDR)                   ; Supply '$' as the current output address.
    JP   EX_DEFER                       ; Parse without a new symbol reference.

;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the current token's part and start offset as the diagnostic
; location before a nested component advances the token stream.

ST_MARK: ; Capture a stable token position before nested parsing.
    LD   A,(TK_REC+TK_RPART)            ; Read the current token's source-part ordinal.
    LD   (ST_EPART),A                   ; Save it as the diagnostic part.
    LD   HL,(TK_REC+TK_ROFF)            ; Read the token's zero-based source offset.
    LD   (ST_EOFF),HL                   ; Save it as the diagnostic byte position.
    RET                                 ; Return with the stable anchor recorded.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Lexical failures use the tokenizer's exact position rather than the
; outer statement start captured by ST_MARK.

ST_LFAIL: ; Report lexical detail at the tokenizer's exact error position.
    LD   A,(TK_ESTAT)                   ; A may now hold a token kind, not a status.
    LD   (ST_DETAI),A                   ; Retain the tokenizer's detailed status.
    LD   A,(TK_EPART)                   ; Load its exact failing source part.
    LD   (ST_EPART),A                   ; Replace the outer statement anchor with it.
    LD   HL,(TK_EOFF)                   ; Load its exact failing byte offset.
    LD   (ST_EOFF),HL                   ; Preserve that offset for the driver.
    LD   A,ST_SLEX                      ; Return the public lexical-failure category.
    SCF                                 ; Mark statement failure.
    RET                                 ; Return directly to the multipart driver.

;@ROUTINE OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
; A token that cannot begin or continue a statement is normally an expression
; syntax failure. A bare '%' token has a separate directive category.

ST_STRAY: ; Classify an unexpected statement token for diagnostics.
    CALL ST_MARK                        ; Anchor the error at this token.
    LD   A,(TK_REC+TK_RKIND)            ; Read its token kind.
    CP   TK_DIR                         ; Is it a bare percent directive marker?
    JR   NZ,ST_UNEXP                    ; No: report a syntax error.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report a bare or unsupported percent directive at the current token.

ST_UNSUP: ; Report an unsupported percent directive token.
    LD   A,ST_XPCT                      ; Report the unsupported directive token.
    LD   C,ST_SDIR                      ; Select the public directive-failure category.
    JR   ST_FAIL                        ; Store detail and return failure.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report the current unexpected token as a statement-expression failure.

ST_UNEXP: ; Report a token that cannot start the required statement form.
    LD   A,ST_XSTRT                     ; Expected a label, instruction or directive.
    LD   C,ST_SEXP                      ; Select the statement/expression category.
    JR   ST_FAIL                        ; Store detail and return failure.
ST_UNOP: ; Report an unrecognised instruction or directive name.
    LD   A,ST_XNAME                     ; The leading name is not an operation.
    LD   C,ST_SEXP                      ; Select the statement/expression category.
    JR   ST_FAIL                        ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a symbol-layer status as a statement failure.

ST_SFAIL: ; Wrap a nested symbol status in the statement category.
    LD   C,ST_SSYM                      ; Wrap A as a symbol-subsystem failure.
    JR   ST_FAIL                        ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an instruction-parser status as a statement failure.

ST_IFAIL: ; Wrap a nested instruction-parser status.
    LD   C,ST_SINS                      ; Wrap A as an instruction/parser failure.
    JR   ST_FAIL                        ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an output-layer status as a statement failure.

ST_OFAIL: ; Wrap a nested output or patch-submission status.
    LD   C,ST_SOUT                      ; Wrap A as an output-subsystem failure.
    JR   ST_FAIL                        ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an EQU-expression status as an EQU statement failure.

ST_EFAIL: ; Wrap an EQU expression or delimiter failure.
    LD   C,ST_SEQU                      ; Wrap A as an EQU-specific failure.
    JR   ST_FAIL                        ; Store detail and return failure.
ST_EUNRE: ; Reject EQU whose value is still unresolved.
    LD   A,EX_PEND                      ; Detail: EQU value remained unresolved.
    JR   ST_EFAIL                       ; Return it through the EQU wrapper.
ST_ETAIL: ; Reject trailing tokens after an EQU expression.
    LD   A,ST_XTAIL                     ; Detail: trailing token after EQU expression.
    JR   ST_EFAIL                       ; Return it through the EQU wrapper.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a directive-argument status as a directive statement failure.

ST_DFAIL: ; Wrap a directive argument failure.
    LD   C,ST_SDIR                      ; Wrap A as a directive-argument failure.

;@ROUTINE IN A,C OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Failure adapters store component status from A, replace
; A with their outer statement category from C and set carry for the driver.

ST_FAIL: ; Publish nested detail and return the outer category with carry.
    LD   (ST_DETAI),A                   ; Preserve the nested subsystem status.
    LD   A,C                            ; Return the statement category.
    SCF                                 ; Mark the statement as failed.
    RET                                 ; Return to the multipart driver.
ST_DUNRE: ; Reject a directive value that requires a forward definition.
    LD   A,EX_PEND                      ; Detail: unresolved directive value.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_DRNG: ; Report a directive value outside its supported range.
    LD   A,EX_SRNG                      ; Detail: directive value out of range.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_DMISS: ; Report a required directive expression that is absent.
    LD   A,EX_STERM                     ; Detail: a required expression was absent.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_DTAIL: ; Report trailing text after directive arguments.
    LD   A,ST_XTAIL                     ; Detail: unexpected trailing token.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_DSTR: ; Report an argument where a quoted string was required.
    LD   A,ST_XNSTR                     ; Detail: a quoted string was required.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_DWSTR: ; Reject a quoted string in a DW list.
    LD   A,ST_XDWST                     ; Detail: strings belong only in DB.
    JR   ST_DFAIL                       ; Return through the directive wrapper.
ST_CEND: ; End statement code and its immutable lookup table.
ST_WBEG: ; Begin fixed statement workspace and phase overlays.

; Twenty bytes shared by mutually exclusive statement phases.

.UNION:     DS      20                  ; Union storage shared by all statement phases.

; Packed label/EQU name or instruction record at the same base.

ST_KEY      EQU     .UNION              ; Six-byte packed leading symbol key.
ST_INS      EQU     .UNION              ; Parsed instruction record at the same base.

; Cached mnemonic/directive ordinals and their explicit validity flags.

ST_MNEM     EQU     .UNION+6            ; Cached mnemonic ordinal.
ST_MOK      EQU     .UNION+7            ; Mnemonic cache-valid Boolean.
ST_DIR      EQU     .UNION+8            ; Cached directive ordinal.
ST_DOK      EQU     .UNION+9            ; Directive cache-valid Boolean.

; Nested subsystem status retained for the driver and public diagnostics.

ST_DETAI    EQU     .UNION+10           ; Nested subsystem status for diagnostics.

; EQU result and its negative/sign-extension flag.

ST_EVAL     EQU     .UNION+6            ; EQU low sixteen-bit value.
ST_ESIGN    EQU     .UNION+8            ; EQU sign-extension marker.

; Data-list element width, default patch kind, unresolved addend and DS fill.

ST_WIDTH    EQU     .UNION              ; Active DB/DW scalar width.
ST_DKIND    EQU     .UNION+1            ; Default unresolved patch kind.
ST_DELTA    EQU     .UNION+2            ; Saved unresolved signed addend.
ST_DFILL    EQU     .UNION+3            ; DS/ALIGN repeated fill byte.

; General directive value. While queuing a patch, the chosen patch kind.

ST_DVAL     EQU     .UNION+4            ; General directive word value.
ST_PKIND    EQU     ST_DVAL             ; Selected patch kind overlaid on that word.

; DS/ALIGN byte count, followed by unresolved-expression state.

ST_DCNT     EQU     .UNION+6            ; DS/ALIGN remaining byte count.
ST_DKEY     EQU     .UNION+8            ; Saved unresolved packed-key pointer.
ST_DSYM     EQU     .UNION+10           ; Saved unresolved symbol-record pointer.
ST_DADDR    EQU     .UNION+12           ; Saved placeholder target address.

; Raw quoted-string cursor, remaining raw bytes and decoded-byte count.

ST_SPTR     EQU     .UNION+14           ; String raw-source cursor.
ST_SLEFT    EQU     .UNION+16           ; String raw bytes remaining.
ST_SCNT     EQU     .UNION+17           ; String decoded-byte count.

; Saved high hexadecimal nibble and string mode selector.

ST_HEXHI    EQU     .UNION+18           ; Saved high nibble for \xHH decoding.
ST_SMODE    EQU     .UNION+19           ; DB/CSTR/PSTR/ISTR mode selector.

; Stable statement diagnostic position.

ST_EPART:   DB      0                   ; Stable diagnostic source-part ordinal.
ST_EOFF:    DW      0                   ; Stable zero-based source-byte offset.

; Source part retained while a quoted string is decoded through TK_SREAD.

ST_SPART:   DB      0                   ; Source part used by raw string reads.
ST_WEND: ; End the fixed statement workspace extent.
