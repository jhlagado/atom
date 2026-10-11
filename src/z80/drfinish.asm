;@ROUTINE OUT A,CARRY,IX CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY,HL,BC,IY
; Search the live pending arena for a diagnostic anchor. Exactly one pending
; record for each unresolved symbol has bit 7 set in its kind byte.

DR_AFIN: ; Check pending references and retained symbols.
    LD   IX,(SY_PBASE)                  ; Begin at the pending arena's first record.
    LD   DE,(SY_NEXT)                   ; Load its current exclusive end.
    CALL AT_IXEND                       ; Compare the record cursor with that end.
    JR   Z,.NOPEND                      ; An empty pending list needs symbol-table checks.
.PENDLOOP: ; Search pending records for a diagnostic anchor.
    BIT  7,(IX+4)                       ; Test this record's diagnostic-anchor flag.
    JR   NZ,.ANCHOR                     ; Validate and report the first live anchor.

; Non-anchor records cannot supply an undefined-symbol source location.

    LD   BC,SY_PENDB                    ; Load the pending-record stride.
    ADD  IX,BC                          ; Advance to the next live pending record.
    CALL AT_IXEND                       ; Test whether the cursor reached the arena end.
    JR   NZ,.PENDLOOP                   ; Continue searching while records remain.
    JR   .CORRUPT                       ; Pending data without any anchor is corrupt.
.ANCHOR: ; Validate an anchor before dereferencing its symbol.

; Preserve the anchor's symbol pointer before validation. A malformed
; pointer must never be dereferenced merely to improve a diagnostic.

    LD   L,(IX+0)                       ; Read the anchor's symbol pointer low byte.
    LD   H,(IX+1)                       ; Complete the candidate pointer in HL.
    LD   (DR_USYM),HL                   ; Retain it for validation and diagnostics.
    CALL DR_VPTR                        ; Require a live, aligned symbol-record address.
    JR   C,.CORRUPT                     ; Never dereference a malformed pointer.

; A live anchor must point at an undefined symbol. A defined target means the
; patch path left stale metadata, an internal fault.

    LD   IY,(DR_USYM)                   ; Address the now-validated symbol record.
    BIT  6,(IY+5)                       ; Test the symbol's defined flag.
    JR   NZ,.CORRUPT                    ; A defined symbol must have no live anchor.

; Low kind bits must name a patch field form. Zero and values past
; PT_KHB are corrupt even when the diagnostic-anchor bit itself is valid.

    LD   A,(IX+4)                       ; Read anchor flag and patch kind.
    AND  SY_KMASK                       ; Keep only the low patch-kind bits.
    JR   Z,.CORRUPT                     ; Kind zero is not a patch operation.
    CP   PT_KHB+1                       ; PT_KHB is the highest defined patch kind.
    JR   NC,.CORRUPT                    ; Reject every out-of-range kind value.

; Recover exact source location: the anchor has the part ordinal, while an
; undefined symbol's otherwise-unused value word retains the reference offset.

    LD   A,(IX+SY_PART)                 ; Read the anchor's complete source-part ordinal.
    LD   (ST_EPART),A                   ; Publish it through the statement diagnostic ABI.
    LD   L,(IY+SY_VALLO)                ; Recover the reference offset low byte.
    LD   H,(IY+SY_VALHI)                ; Complete the source offset in HL.
    LD   (ST_EOFF),HL                   ; Publish the exact byte offset within that part.
    XOR  A                              ; No nested statement detail applies here.
    LD   (ST_DETAI),A                   ; Clear any detail left by the final statement.

; Return public undefined status and symbol pointer for diagnostic
; name unpacking. Carry marks the finalisation failure.

    LD   IX,(DR_USYM)                   ; Return the validated record for name decoding.
    LD   A,ST_SUDEF                     ; Report the statement-layer undefined status.
    SCF                                 ; Mark finalisation as failed.
    RET                                 ; The driver will abort the open generation.
.NOPEND: ; Validate symbols when no pending records remain.

; With no pending records, validate the final private-label scope without
; evicting it. An undefined private here is inconsistent because it has no
; diagnostic anchor.

    CALL SY_VSCOP                       ; Validate the current private scope in place.
    JR   C,.CORRUPT                     ; A private failure without an anchor is corrupt.

; Private validation leaves that scope intact. Walk permanent globals
; and require every record's defined flag. an undefined global without pending
; metadata is likewise an internal invariant failure.

    LD   IX,(SY_ABASE)                  ; Begin at the permanent global-symbol arena.
    LD   DE,(SY_GEND)                   ; Load its current exclusive end.
.GLOBLOOP: ; Check each retained global is defined.
    CALL AT_IXEND                       ; Compare the symbol cursor with the arena end.
    JR   Z,.OK                          ; Every retained global is defined.
    BIT  6,(IX+5)                       ; Test this global record's defined flag.
    JR   Z,.CORRUPT                     ; Undefined with no pending data is corrupt.
    LD   BC,SY_RECB                     ; Load the eight-byte symbol-record stride.
    ADD  IX,BC                          ; Advance to the next permanent global.
    JR   .GLOBLOOP                      ; Validate it or finish the scan.
.OK: ; Return complete symbol state.
    XOR  A                              ; Return finalisation success with carry clear.
    RET                                 ; Symbol state is complete and internally sound.
.CORRUPT: ; Clear unsafe pointers and report internal corruption.

; Do not expose a stale or unvalidated pointer on an internal failure.

    XOR  A                              ; Produce zero for both pointer bytes.
    LD   (DR_USYM),A                    ; Clear the public symbol pointer low byte.
    LD   (DR_USYM+1),A                  ; Clear its high byte before returning failure.
    LD   A,ST_SINT                      ; Report a statement-layer internal invariant.
    SCF                                 ; Mark finalisation as failed.
    RET                                 ; The driver will translate and abort.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
; First test the upward-growing global range [SY_ABASE, SY_GEND). Preserve the
; candidate around each subtraction because the comparisons destroy HL.

DR_VPTR: ; Validate a live aligned symbol-record pointer.
    PUSH HL                             ; Preserve candidate for lower-bound test.
    LD   DE,(SY_ABASE)                  ; Load the first live global-record address.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare against global lower bound.
    POP  HL                             ; Restore the original candidate pointer.
    JR   C,.PRIVATE                     ; Check private storage if below globals.
    PUSH HL                             ; Preserve it across the upper-bound compare.
    LD   DE,(SY_GEND)                   ; Load the exclusive end of live globals.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate against that exclusive end.
    POP  HL                             ; Restore the candidate again.
    JR   NC,.PRIVATE                    ; Check private storage at/above global end.

; A global pointer is valid only at an eight-byte record boundary from the
; arena base. SY_RECB is a power of two, so a mask performs the modulus test.

    LD   DE,(SY_ABASE)                  ; Measure candidate from the global arena base.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Produce the byte displacement from that base.
    LD   A,L                            ; Only low alignment bits can affect modulo eight.
    AND  SY_RECB-1                      ; Keep displacement modulo the record size.
    RET  Z                              ; Zero means an exact global-record boundary.
    SCF                                 ; An interior byte is not a symbol pointer.
    RET                                 ; Return invalid global alignment.
.PRIVATE: ; Check the downward-growing private-symbol range.

; Private records occupy [SY_LBEG, SY_AEND) and grow down from SY_AEND.

    PUSH HL                             ; Preserve candidate for lower-bound test.
    LD   DE,(SY_LBEG)                   ; Load the first live private-record address.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate with the private lower bound.
    POP  HL                             ; Restore the original candidate pointer.
    RET  C                              ; Below the live private range is invalid.
    PUSH HL                             ; Preserve it across the upper-bound compare.
    LD   DE,(SY_AEND)                   ; Load the symbol arena's exclusive end.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate with that exclusive end.
    POP  HL                             ; Restore the candidate for alignment testing.
    JR   NC,.INVALID                    ; At or above arena end is not a live record.

; Measure backwards from the arena end to prove eight-byte alignment with the
; downward-growing record layout.

    LD   DE,(SY_AEND)                   ; Load the fixed high end of private allocation.
    EX   DE,HL                          ; Put arena end in HL and candidate in DE.
    OR   A                              ; Clear carry before the in-range subtraction.
    SBC  HL,DE                          ; Measure backwards from the arena end.
    LD   A,L                            ; Select the low alignment bits.
    AND  SY_RECB-1                      ; Keep displacement modulo eight.
    RET  Z                              ; Zero means an exact private-record boundary.
.INVALID: ; Reject an interior or out-of-range symbol pointer.
    SCF                                 ; Mark every other candidate pointer invalid.
    RET                                 ; The caller must not dereference it.
;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce a failure to one message number in DR_MSG. A holds the public DR_S*
; status. A source failure nests up to three statuses: the statement category
; in DR_DETAI, its subsystem status in ST_DETAI and, for parser and expression
; failures, a further expression, symbol or tokenizer status. Each subsystem's
; codes map to a block of message numbers starting at its DR_M* base.

DR_DIAG: ; Translate nested statuses into diagnostic arguments.
    LD   C,DR_MUNDF                     ; Assume an undefined symbol.
    CP   DR_SUNDE                       ; Did finalisation find one?
    JP   Z,.UNDEF                       ; Name it from DR_USYM.
    LD   C,DR_MOUT                      ; Assume the output was rejected.
    CP   DR_SOUT                        ; Did BEGIN or COMMIT fail?
    JP   Z,.SET                         ; Report the output failure.
    LD   C,DR_MCFG                      ; Assume an invalid build description.
    CP   DR_SCFG                        ; Was the descriptor rejected?
    JP   Z,.SET                         ; Report the configuration failure.
    LD   C,DR_MINT                      ; Anything other than a source error is internal.
    CP   DR_SSRC                        ; Was a source statement rejected?
    JP   NZ,.SET                        ; No: report an internal error.

    LD   A,(ST_DETAI)                   ; Read the statement layer's detail.
    LD   E,A                            ; E holds the subsystem status from here on.
    LD   A,(DR_DETAI)                   ; Read the statement category.
    CP   ST_SEXP                        ; Is it a statement-level grammar failure?
    JP   Z,.DIRECT                      ; Its detail is already a message number.
    CP   ST_SLEX                        ; Did the tokenizer reject the source?
    JR   Z,.TOKEN                       ; Use the tokenizer block.
    CP   ST_SSYM                        ; Did a symbol operation fail?
    JR   Z,.SYMBOL                      ; Use the symbol block.
    CP   ST_SOUT                        ; Did output or patching fail?
    JR   Z,.OUTPUT                      ; Use the output block.
    CP   ST_SINS                        ; Did instruction parsing fail?
    JR   Z,.PARSER                      ; Use the parser block.
    CP   ST_SEQU                        ; Did an EQU expression fail?
    JR   Z,.EXPR                        ; Use the expression block.
    CP   ST_SDIR                        ; Did directive arguments fail?
    JR   Z,.EXPR                        ; Directives also report expression statuses.
    LD   C,DR_MINT                      ; Every other category is internal.
    JP   .SET                           ; Publish the internal error.
.PARSER: ; Decode an instruction-parser failure.
    LD   A,E                            ; Inspect the parser status.
    CP   PR_SRRNG                       ; Is it a relative jump out of range?
    JR   NZ,.PRSTAT                     ; No: no offset to report.
    LD   HL,(PR_DVAL)                   ; Load the rejected offset.
    LD   (DR_VAL),HL                    ; Quote it in the message.
.PRSTAT: ; Select parser or nested expression detail.
    CP   PR_SLEX                        ; Did the tokenizer fail inside the operands?
    JR   Z,.LEXICAL                     ; Use the tokenizer's own status.
    CP   PR_SSYM                        ; Did a symbol operation fail?
    JR   Z,.PRSYM                       ; Use the retained symbol status.
    LD   B,DR_MPR                       ; Select the parser block.
    LD   D,PR_SPCAP+1                   ; It holds one message per parser status.
    CP   PR_SEXPR                       ; Did an operand expression fail?
    JP   NZ,.TABLE                      ; No: report the parser status itself.
    LD   A,(PR_EXERR)                   ; Load the retained expression status.
    LD   E,A                            ; Decode it as an expression failure.
.EXPR: ; Decode expression or nested lexical failure.
    LD   A,E                            ; Inspect the expression status.
    BIT  7,A                            ; Did the statement layer give a message number?
    JP   NZ,.DIRECT                     ; Yes: use it directly.
    CP   EX_SSYM                        ; Did a symbol lookup fail?
    JR   Z,.EXSYM                       ; Use the expression's retained symbol status.
    CP   EX_SLEX                        ; Did the tokenizer fail inside the expression?
    JR   Z,.LEXICAL                     ; Use the tokenizer's own status.
    LD   B,DR_MEX                       ; Select the expression block.
    LD   D,EX_SINT+1                    ; It holds one message per expression status.
    JR   .TABLE                         ; Map the status.
.EXSYM: ; Read the expression symbol failure.
    LD   A,(EX_CAUSE)                   ; Load the expression's symbol status.
    LD   E,A                            ; Decode it as a symbol failure.
    JR   .SYMBOL                        ; Use the symbol block.
.PRSYM: ; Read the parser symbol failure.
    LD   A,(PR_SYERR)                   ; Load the parser's symbol status.
    LD   E,A                            ; Decode it as a symbol failure.
.SYMBOL: ; Decode a symbol-table failure.
    LD   A,E                            ; Inspect the symbol status.
    CP   SY_SUNDF                       ; Was a private label left undefined?
    JR   NZ,.SYSTAT                     ; No: no name to report.
    LD   HL,(SY_UPRIV)                  ; Load the undefined private record.
    LD   (DR_SYM),HL                    ; Name it in the message.
.SYSTAT: ; Select the symbol diagnostic block.
    LD   B,DR_MSY                       ; Select the symbol block.
    LD   D,SY_SPART+1                   ; It holds one message per symbol status.
    JR   .TABLE                         ; Map the status.
.LEXICAL: ; Read the retained tokenizer failure.
    LD   A,(TK_ESTAT)                   ; Load the tokenizer's own status.
    LD   E,A                            ; Decode it as a lexical failure.
.TOKEN: ; Select the tokenizer diagnostic block.
    LD   B,DR_MTK                       ; Select the tokenizer block.
    LD   D,TK_SAPOS+1                   ; It holds one message per tokenizer status.
    JR   .TABLE                         ; Map the status.
.OUTPUT: ; Decode output failure and pending-reference location.
    LD   A,(OU_FSINK)                   ; Did the sink reject an operation?
    OR   A                              ; Zero means an output-layer failure.
    LD   C,DR_MOUT                      ; The sink's own status is in ST_DETAI.
    JR   NZ,.SET                        ; Report that the output could not be written.

; A range failure while patching a forward reference belongs to the
; referencing instruction. Move the location there and keep the definition
; that triggered the patch as the related location.

    LD   HL,(OU_FVAL)                   ; Quote the rejected value or offset.
    LD   (DR_VAL),HL                    ; Keep it for the message.
    LD   HL,(OU_FREC)                   ; Was a pending record being patched?
    LD   A,H                            ; Test its high byte.
    OR   L                              ; Zero means an ordinary output failure.
    JR   Z,.OUTTAB                      ; Report the output status directly.
    LD   A,E                            ; Inspect the output status.
    LD   C,DR_MJREF                     ; Assume a relative jump out of range.
    CP   OU_SRRNG                       ; Is it?
    JR   Z,.MOVE                        ; Report it at the jump.
    LD   C,DR_MVREF                     ; Assume a value out of range.
    CP   OU_SVRNG                       ; Is it?
    JR   NZ,.OUTTAB                     ; Other output failures keep their location.
.MOVE: ; Move a patch failure to its original reference.
    LD   A,(ST_EPART)                   ; The definition becomes the related location.
    LD   (DR_RPART),A                   ; Keep its source part.
    LD   DE,(ST_EOFF)                   ; Load its source offset.
    LD   (DR_ROFF),DE                   ; Keep it too.
    LD   E,(HL)                         ; Read the record's symbol pointer low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    LD   (DR_SYM),DE                    ; Name the target symbol.
    LD   DE,SY_PART-1                   ; Step from the pointer's high byte to the part.
    ADD  HL,DE                          ; Address the reference's source part.
    LD   A,(HL)                         ; Read it.
    LD   (ST_EPART),A                   ; The reference becomes the primary location.
    INC  HL                             ; Advance to its source offset.
    LD   E,(HL)                         ; Read the offset low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the offset.
    LD   (ST_EOFF),DE                   ; Publish the reference's position.
    JR   .SET                           ; Publish the message selected in C.
.OUTTAB: ; Select output status or pending-capacity detail.
    LD   A,E                            ; Instruction output preflights pending space.
    CP   SY_SPCAP                       ; Is the pending arena full?
    JP   Z,.SYMBOL                      ; Report too many forward references.
    LD   B,DR_MOU                       ; Select the output block.
    LD   D,OU_SRRNG+1                   ; It holds one message per output status.
.TABLE: ; Map a bounded subsystem status to a message.

; B is the block's first message number, D its length and E the status.

    LD   A,E                            ; Inspect the status.
    LD   C,DR_MINT                      ; Assume it falls outside the block.
    CP   D                              ; Is it a known status?
    JR   NC,.SET                        ; No: report an internal error.
    ADD  A,B                            ; Form the message number.
    LD   C,A                            ; Select it.
.SET: ; Publish the chosen diagnostic message.
    LD   A,C                            ; Publish the selected message number.
    LD   (DR_MSG),A                     ; Leave it for the host.
    RET                                 ; Return to DR_ASM.
.DIRECT: ; Decode a direct statement-layer message number.

; Statement, EQU and directive failures that need no nested status store
; their message number in ST_DETAI with bit 7 set. Sink statuses can also
; have bit 7 set, so only these categories are read this way.

    LD   A,E                            ; Recover the statement detail.
    AND  $7F                            ; Keep the message number.
    LD   C,A                            ; Select it.
    JR   .SET                           ; Publish it.
.UNDEF: ; Attach the unresolved symbol to the diagnostic.
    LD   HL,(DR_USYM)                   ; The undefined symbol is the message argument.
    LD   (DR_SYM),HL                    ; Publish it.
    JR   .SET                           ; Publish the message number.
DR_CEND: ; Exclusive end of driver code.
DR_WBEG: ; Beginning of writable driver state.

; Address of the immutable build descriptor supplied to DR_ASM.

DR_DESC:    DW      0                   ; Saved build-descriptor address.

; Address of the next five-byte part record during validation or assembly.

DR_PCURS:   DW      0                   ; Current source-part record address.

; Number of part records still to validate or assemble.

DR_PLEFT:   DB      0                   ; Remaining part-record count.

; Dense ordinal expected for the current part record.

DR_PNEXT:   DB      0                   ; Expected dense part ordinal.

; Subsystem or configuration detail associated with the public driver status.

DR_DETAI:   DB      0                   ; Nested status or configuration detail.

; Validated symbol pointer for undefined diagnostic, else zero.

DR_USYM:    DW      0                   ; Validated undefined-symbol record address.

; Diagnostic message and arguments, published when DR_ASM fails. DR_DIAG
; collects the symbol and value from the subsystem that failed.

DR_MSG:     DB      0                   ; Message number from src/host/diagnostics.mjs.
DR_RPART:   DB      0                   ; Related location's source part, or $FF.
DR_ROFF:    DW      0                   ; Related location's source offset.
DR_SYM:     DW      0                   ; Symbol record named by the message, or zero.
DR_VAL:     DW      0                   ; Signed value quoted by the message.
DR_WEND: ; Exclusive end of writable driver state.
