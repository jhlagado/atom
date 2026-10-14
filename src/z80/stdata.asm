stDoDs: ; Parse DS reservation count and optional repeated fill byte.

; DS count must be concrete. Without comma it reserves a gap. With
; a comma it emits count copies of the fill byte.

    CALL stPcExpr                       ; Evaluate the number of bytes to allocate.
    JP   C,stDirErr                     ; Preserve nested expression failure detail.
    OR   A                              ; Test whether the count is unresolved.
    JP   NZ,stDirFwd                    ; DS requires a count immediately.
    LD   (stPadCnt),HL                  ; Preserve the sixteen-bit allocation count.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token following the count.
    CP   tkEol                          ; Is this the uninitialised reserve form?
    JR   Z,stSkip                       ; Yes: advance without emitting IMAGE bytes.
    CP   tkComma                        ; Otherwise require a fill-value separator.
    JP   NZ,stExtra                     ; Reject any other trailing token.

; Parse the optional fill expression and require an immediate low-byte value.

    CALL tkNext                         ; Consume comma. Expose the fill value.
    JP   C,stLexErr                     ; Preserve a lexical failure after the comma.
    CALL stPcExpr                       ; Evaluate the repeated fill byte.
    JP   C,stDirErr                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the fill expression unresolved?
    JP   NZ,stDirFwd                    ; A forward fill cannot use one patch.
    LD   A,L                            ; Select the expression's low byte as the fill.
    LD   (stFiller),A                   ; Preserve it across capacity preflight.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token after the fill value.
    CP   tkEol                          ; DS accepts no third argument.
    JP   NZ,stExtra                     ; Reject any trailing token.

; Preflight the full range so the byte loop cannot fail for capacity
; after publishing only a prefix.

    LD   HL,(stPadCnt)                  ; Supply the complete filled-range length.
    CALL outCapOk                       ; Prove all bytes fit before the first write.
    JP   C,stOutErr                     ; Preserve atomic capacity failure.
stFill: ; Emit the next fill byte until the saved count reaches zero.

; Emit one fill byte per iteration. stPadCnt reaches zero before returning
; to the outer statement loop.

    LD   HL,(stPadCnt)                  ; Read the remaining fill-byte count.
    LD   A,H                            ; Fold the high count byte into the zero test.
    OR   L                              ; Z means every requested byte was emitted.
    JP   Z,stNext                       ; Finish the directive and begin the next line.
    LD   A,(stFiller)                   ; Recover the repeated fill byte.
    CALL outEmitB                       ; Publish one byte from the preflighted range.
    JP   C,stOutErr                     ; Preserve an unexpected sink failure.
    LD   HL,(stPadCnt)                  ; Reload the remaining count after the call.
    DEC  HL                             ; Account for the byte just emitted.
    LD   (stPadCnt),HL                  ; Persist the decremented count.
    JR   stFill                         ; Emit the rest of the range.
stSkip: ; Reserve the DS interval without initialising its bytes.

; The no-fill form advances the output cursor without creating IMAGE bytes.

    LD   HL,(stPadCnt)                  ; Supply the byte count to reserve.
    CALL outSkip                        ; Advance the cursor without IMAGE emission.
    JP   stOutOk                        ; Check output status and continue.
stPad: ; Calculate zero padding to the requested alignment boundary.

; ALIGN needs a positive 16-bit boundary. A nonzero extension or zero
; in the low word is outside the directive's domain.

    CALL stPcExpr                       ; Evaluate the requested alignment boundary.
    JP   C,stDirErr                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the boundary unresolved?
    JP   NZ,stDirFwd                    ; ALIGN requires an immediate value.
    LD   A,(exRVal+2)                   ; Read the expression's extension byte.
    OR   A                              ; Does the extension mark a negative boundary?
    JP   NZ,stDirBig                    ; Reject it outside the address domain.
    LD   A,H                            ; Begin testing the low word for zero.
    OR   L                              ; Z identifies the invalid boundary zero.
    JP   Z,stDirBig                     ; Reject division by a zero alignment.
    LD   (stDirVal),HL                  ; Preserve the validated boundary.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token following the expression.
    CP   tkEol                          ; ALIGN accepts exactly one argument.
    JP   NZ,stExtra                     ; Reject any trailing token.

; Use the expression divider for cursor modulo alignment. Both operands
; are explicitly zero-extended to 24 bits before exRem is called.

    LD   HL,(outAddr)                   ; Load the current output address as dividend.
    LD   (exLVal),HL                    ; Store the dividend's low word.
    XOR  A                              ; Form the common zero extension byte.
    LD   (exLVal+2),A                   ; Zero-extend the current address to 24 bits.
    LD   HL,(stDirVal)                  ; Restore the alignment as divisor.
    LD   (exRVal),HL                    ; Store the divisor's low word.
    LD   (exRVal+2),A                   ; Zero-extend the divisor to 24 bits.
    CALL exRem                          ; Replace exRVal with cursor modulo boundary.
    JP   C,stDirErr                     ; Preserve any defensive arithmetic failure.

; A zero remainder is already aligned. Otherwise emit alignment - remainder
; zero bytes through the same preflighted fill loop used by DS count,fill.

    LD   HL,(exRVal)                    ; Load the sixteen-bit remainder.
    LD   A,H                            ; Begin testing whether it is zero.
    OR   L                              ; Z means the cursor is aligned.
    JR   Z,.padCount                    ; Emit no padding in that case.
    EX   DE,HL                          ; Preserve the nonzero remainder in DE.
    LD   HL,(stDirVal)                  ; Reload the alignment boundary.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compute bytes to next boundary.
.padCount: ; Preflight the computed padding and enter the shared fill loop.
    LD   (stPadCnt),HL                  ; Reuse the DS loop's remaining-byte counter.
    XOR  A                              ; ALIGN padding bytes are always zero.
    LD   (stFiller),A                   ; Select zero as the repeated fill value.
    LD   HL,(stPadCnt)                  ; Supply the complete padding length.
    CALL outCapOk                       ; Preflight all padding before emitting any.
    JP   C,stOutErr                     ; Preserve atomic output failure.
    JR   stFill                         ; Emit through the shared fill loop.
stDone: ; Return success for this part without closing private scope.

; EOF is a successful end of this source part, not the end of private scope or
; the complete build. The driver decides whether another part follows.

    XOR  A                              ; Return stOk with carry clear.
    RET                                 ; Return control to the multipart driver.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Directive names have at most five characters. Pack the lexeme into the
; shared RADIX-40 scratch buffer for exact, case-insensitive comparison.

stIsDir: ; Recognise a directive by exact packed-name comparison.
    LD   A,B                            ; Load the lexeme length for the bound check.
    CP   6                              ; Is it at most five characters?
    JR   NC,.notFound                   ; Six or more characters cannot match.
    LD   DE,enTemp                      ; Select the shared four-byte packing buffer.
    CALL nmPack                         ; Pack case-insensitively into RADIX-40 words.
    RET  C                              ; Propagate a character or length rejection.
    LD   IX,.names                      ; Point at the first packed directive entry.
    LD   B,stNumDir                     ; Search every fixed-size table entry.
    LD   C,stEqu                        ; Track the one-based ordinal alongside IX.
.loop: ; Compare the four bytes of one packed directive entry.

; Compare four packed bytes. C tracks the one-based directive ordinal as
; IX advances through the fixed table.

    LD   A,(enTemp)                     ; Load packed byte zero.
    CP   (IX+0)                         ; Compare it with the candidate entry.
    JR   NZ,.next                       ; Any mismatch rejects this candidate.
    LD   A,(enTemp+1)                   ; Load packed byte one.
    CP   (IX+1)                         ; Compare it with the candidate entry.
    JR   NZ,.next                       ; Reject on mismatch.
    LD   A,(enTemp+2)                   ; Load packed byte two.
    CP   (IX+2)                         ; Compare it with the candidate entry.
    JR   NZ,.next                       ; Reject on mismatch.
    LD   A,(enTemp+3)                   ; Load packed byte three.
    CP   (IX+3)                         ; Compare the final packed byte.
    JR   NZ,.next                       ; Reject on mismatch.
    LD   A,C                            ; Return the matching directive ordinal.
    OR   A                              ; Clear carry while preserving that ordinal.
    RET                                 ; Report successful exact recognition.
.next: ; Advance the packed-name pointer and its matching ordinal.
    LD   DE,4                           ; Each packed directive occupies four bytes.
    ADD  IX,DE                          ; Advance to the next table entry.
    INC  C                              ; Advance the corresponding ordinal.
    DJNZ .loop                          ; Continue until every entry has been compared.
.notFound: ; Return carry set when no directive name matches.

; Recognition failure returns carry set. A is deliberately cleared because no
; ordinal is valid.

    XOR  A                              ; Return no meaningful ordinal.
    SCF                                 ; Mark recognition failure.
    RET                                 ; Return to the statement classifier.
.names: ; Packed directive names in one-based ordinal order.

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

stTake: ; Read and advance the raw quoted-string cursor.
    LD   HL,(stStrPtr)                  ; Load the next logical source-byte offset.
    LD   A,(stStrSrc)                   ; Supply its source-part ordinal.
    CALL tkRead                         ; Fetch the byte through source service.
    LD   HL,(stStrPtr)                  ; Reload the cursor after callback clobbering.
    INC  HL                             ; Advance to the following raw byte.
    LD   (stStrPtr),HL                  ; Persist the new cursor.
    LD   HL,stStrLen                    ; Address the raw-byte countdown.
    DEC  (HL)                           ; Account for the byte just consumed.
    RET                                 ; Return it in A to the decoder.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch a token and mirror its kind into A for compact statement dispatch.

stToken: ; Fetch a token and mirror its kind while retaining carry.
    CALL tkNext                         ; Fetch the next token record.
    LD   A,(tkRecord+tkKindAt)          ; Mirror its kind into the dispatch register.
    RET                                 ; Return kind and tokenizer carry.

;@ROUTINE OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Expressions see the current output address in BC so '$' and relative forms
; have statement-accurate meaning.

stPcExpr: ; Evaluate with the current output cursor as dollar's value.
    LD   BC,(outAddr)                   ; Supply '$' as the current output address.
    JP   exDefer                        ; Parse without a new symbol reference.

;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the current token's part and start offset as the diagnostic
; location before a nested component advances the token stream.

stMark: ; Capture a stable token position before nested parsing.
    LD   A,(tkRecord+tkPartAt)          ; Read the current token's source-part ordinal.
    LD   (stAtPart),A                   ; Save it as the diagnostic part.
    LD   HL,(tkRecord+tkOffAt)          ; Read the token's zero-based source offset.
    LD   (stAtOff),HL                   ; Save it as the diagnostic byte position.
    RET                                 ; Return with the stable anchor recorded.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Lexical failures use the tokenizer's exact position rather than the
; outer statement start captured by stMark.

stLexErr: ; Report lexical detail at the tokenizer's exact error position.
    LD   A,(tkStatus)                   ; A may now hold a token kind, not a status.
    LD   (stDetail),A                   ; Retain the tokenizer's detailed status.
    LD   A,(tkErrPos)                   ; Load its exact failing source part.
    LD   (stAtPart),A                   ; Replace the outer statement anchor with it.
    LD   HL,(tkErrOff)                  ; Load its exact failing byte offset.
    LD   (stAtOff),HL                   ; Preserve that offset for the driver.
    LD   A,stBadLex                     ; Return the public lexical-failure category.
    SCF                                 ; Mark statement failure.
    RET                                 ; Return directly to the multipart driver.

;@ROUTINE OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
; A token that cannot begin or continue a statement is normally an expression
; syntax failure. A bare '%' token has a separate directive category.

stStray: ; Classify an unexpected statement token for diagnostics.
    CALL stMark                         ; Anchor the error at this token.
    LD   A,(tkRecord+tkKindAt)          ; Read its token kind.
    CP   tkDir                          ; Is it a bare percent directive marker?
    JR   NZ,stUnexp                     ; No: report a syntax error.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report a bare or unsupported percent directive at the current token.

stHost: ; Report an unsupported percent directive token.
    LD   A,stNoHost                     ; Report the unsupported directive token.
    LD   C,stBadDir                     ; Select the public directive-failure category.
    JR   stFail                         ; Store detail and return failure.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report the current unexpected token as a statement-expression failure.

stUnexp: ; Report a token that cannot start the required statement form.
    LD   A,stNoStmt                     ; Expected a label, instruction or directive.
    LD   C,stSyntax                     ; Select the statement/expression category.
    JR   stFail                         ; Store detail and return failure.
stBadOp: ; Report an unrecognised instruction or directive name.
    LD   A,stUnkOp                      ; The leading name is not an operation.
    LD   C,stSyntax                     ; Select the statement/expression category.
    JR   stFail                         ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a symbol-layer status as a statement failure.

stSymErr: ; Wrap a nested symbol status in the statement category.
    LD   C,stBadSym                     ; Wrap A as a symbol-subsystem failure.
    JR   stFail                         ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an instruction-parser status as a statement failure.

stInsErr: ; Wrap a nested instruction-parser status.
    LD   C,stBadIns                     ; Wrap A as an instruction/parser failure.
    JR   stFail                         ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an output-layer status as a statement failure.

stOutErr: ; Wrap a nested output or patch-submission status.
    LD   C,stBadOut                     ; Wrap A as an output-subsystem failure.
    JR   stFail                         ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an EQU-expression status as an EQU statement failure.

stEqErr: ; Wrap an EQU expression or delimiter failure.
    LD   C,stBadEqu                     ; Wrap A as an EQU-specific failure.
    JR   stFail                         ; Store detail and return failure.
stEqFwd: ; Reject EQU whose value is still unresolved.
    LD   A,exPend                       ; Detail: EQU value remained unresolved.
    JR   stEqErr                        ; Return it through the EQU wrapper.
stEqTail: ; Reject trailing tokens after an EQU expression.
    LD   A,stJunk                       ; Detail: trailing token after EQU expression.
    JR   stEqErr                        ; Return it through the EQU wrapper.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a directive-argument status as a directive statement failure.

stDirErr: ; Wrap a directive argument failure.
    LD   C,stBadDir                     ; Wrap A as a directive-argument failure.

;@ROUTINE IN A,C OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Failure adapters store component status from A, replace
; A with their outer statement category from C and set carry for the driver.

stFail: ; Publish nested detail and return the outer category with carry.
    LD   (stDetail),A                   ; Preserve the nested subsystem status.
    LD   A,C                            ; Return the statement category.
    SCF                                 ; Mark the statement as failed.
    RET                                 ; Return to the multipart driver.
stDirFwd: ; Reject a directive value that requires a forward definition.
    LD   A,exPend                       ; Detail: unresolved directive value.
    JR   stDirErr                       ; Return through the directive wrapper.
stDirBig: ; Report a directive value outside its supported range.
    LD   A,exValErr                     ; Detail: directive value out of range.
    JR   stDirErr                       ; Return through the directive wrapper.
stNoExpr: ; Report a required directive expression that is absent.
    LD   A,exNoTerm                     ; Detail: a required expression was absent.
    JR   stDirErr                       ; Return through the directive wrapper.
stExtra: ; Report trailing text after directive arguments.
    LD   A,stJunk                       ; Detail: unexpected trailing token.
    JR   stDirErr                       ; Return through the directive wrapper.
stStrErr: ; Report an argument where a quoted string was required.
    LD   A,stNoStr                      ; Detail: a quoted string was required.
    JR   stDirErr                       ; Return through the directive wrapper.
stDwStr: ; Reject a quoted string in a DW list.
    LD   A,stDbOnly                     ; Detail: strings belong only in DB.
    JR   stDirErr                       ; Return through the directive wrapper.
stEnd: ; End statement code and its immutable lookup table.
stRamLo: ; Begin fixed statement workspace and phase overlays.

; Twenty bytes shared by mutually exclusive statement phases.

.union:     DS      20                  ; Union storage shared by all statement phases.

; Packed label/EQU name or instruction record at the same base.

stKey       EQU     .union              ; Six-byte packed leading symbol key.
stIns       EQU     .union              ; Parsed instruction record at the same base.

; Cached mnemonic/directive ordinals and their explicit validity flags.

stMnem      EQU     .union+6            ; Cached mnemonic ordinal.
stMnemOk    EQU     .union+7            ; Mnemonic cache-valid Boolean.
stDir       EQU     .union+8            ; Cached directive ordinal.
stDirOk     EQU     .union+9            ; Directive cache-valid Boolean.

; Nested subsystem status retained for the driver and public diagnostics.

stDetail    EQU     .union+10           ; Nested subsystem status for diagnostics.

; EQU result and its negative/sign-extension flag.

stEqVal     EQU     .union+6            ; EQU low sixteen-bit value.
stEqSign    EQU     .union+8            ; EQU sign-extension marker.

; Data-list element width, default patch kind, unresolved addend and DS fill.

stWidth     EQU     .union              ; Active DB/DW scalar width.
stFixDef    EQU     .union+1            ; Default unresolved patch kind.
stDelta     EQU     .union+2            ; Saved unresolved signed addend.
stFiller    EQU     .union+3            ; DS/ALIGN repeated fill byte.

; General directive value. While queuing a patch, the chosen patch kind.

stDirVal    EQU     .union+4            ; General directive word value.
stKind      EQU     stDirVal            ; Selected patch kind overlaid on that word.

; DS/ALIGN byte count, followed by unresolved-expression state.

stPadCnt    EQU     .union+6            ; DS/ALIGN remaining byte count.
stFwdKey    EQU     .union+8            ; Saved unresolved packed-key pointer.
stFwdSym    EQU     .union+10           ; Saved unresolved symbol-record pointer.
stFwdAt     EQU     .union+12           ; Saved placeholder target address.

; Raw quoted-string cursor, remaining raw bytes and decoded-byte count.

stStrPtr    EQU     .union+14           ; String raw-source cursor.
stStrLen    EQU     .union+16           ; String raw bytes remaining.
stStrCnt    EQU     .union+17           ; String decoded-byte count.

; Saved high hexadecimal nibble and string mode selector.

stHexHi     EQU     .union+18           ; Saved high nibble for \xHH decoding.
stStrFmt    EQU     .union+19           ; DB/CSTR/PSTR/ISTR mode selector.

; Stable statement diagnostic position.

stAtPart:   DB      0                   ; Stable diagnostic source-part ordinal.
stAtOff:    DW      0                   ; Stable zero-based source-byte offset.

; Source part retained while a quoted string is decoded through tkRead.

stStrSrc:   DB      0                   ; Source part used by raw string reads.
stRamHi: ; End the fixed statement workspace extent.
