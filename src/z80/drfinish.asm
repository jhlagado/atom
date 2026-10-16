;@ROUTINE OUT A,CARRY,IX CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY,HL,BC,IY
; Search the live pending arena for a diagnostic anchor. Exactly one pending
; record for each unresolved symbol has bit 7 set in its kind byte.

drFinish: ; Check pending references and retained symbols.
    LD   IX,(syRefBeg)                  ; Begin at the pending arena's first record.
    LD   DE,(syRefCur)                  ; Load its current exclusive end.
    CALL syAtEnd                        ; Compare the record cursor with that end.
    JR   Z,.noPend                      ; An empty pending list needs symbol-table checks.
.pendLoop: ; Search pending records for a diagnostic anchor.
    BIT  7,(IX+4)                       ; Test this record's diagnostic-anchor flag.
    JR   NZ,.anchor                     ; Validate and report the first live anchor.

; Non-anchor records cannot supply an undefined-symbol source location.

    LD   BC,syRefLen                    ; Load the pending-record stride.
    ADD  IX,BC                          ; Advance to the next live pending record.
    CALL syAtEnd                        ; Test whether the cursor reached the arena end.
    JR   NZ,.pendLoop                   ; Continue searching while records remain.
    JR   .corrupt                       ; Pending data without any anchor is corrupt.
.anchor: ; Validate an anchor before dereferencing its symbol.

; Preserve the anchor's symbol pointer before validation. A malformed
; pointer must never be dereferenced merely to improve a diagnostic.

    LD   L,(IX+0)                       ; Read the anchor's symbol pointer low byte.
    LD   H,(IX+1)                       ; Complete the candidate pointer in HL.
    LD   (drAbsent),HL                  ; Retain it for validation and diagnostics.
    CALL drPtrOk                        ; Require a live, aligned symbol-record address.
    JR   C,.corrupt                     ; Never dereference a malformed pointer.

; A live anchor must point at an undefined symbol. A defined target means the
; patch path left stale metadata, an internal fault.

    LD   IY,(drAbsent)                  ; Address the now-validated symbol record.
    BIT  6,(IY+5)                       ; Test the symbol's defined flag.
    JR   NZ,.corrupt                    ; A defined symbol must have no live anchor.

; Low kind bits must name a patch field form. Zero and values past
; fixHigh are corrupt even when the diagnostic-anchor bit itself is valid.

    LD   A,(IX+4)                       ; Read anchor flag and patch kind.
    AND  syKindLo                       ; Keep only the low patch-kind bits.
    JR   Z,.corrupt                     ; Kind zero is not a patch operation.
    CP   fixHigh+1                      ; fixHigh is the highest defined patch kind.
    JR   NC,.corrupt                    ; Reject every out-of-range kind value.

; Recover exact source location: the anchor has the part ordinal, while an
; undefined symbol's otherwise-unused value word retains the reference offset.

    LD   A,(IX+syPart)                  ; Read the anchor's complete source-part ordinal.
    LD   (stAtPart),A                   ; Publish it through the statement diagnostic ABI.
    LD   L,(IY+syValLo)                 ; Recover the reference offset low byte.
    LD   H,(IY+syValHi)                 ; Complete the source offset in HL.
    LD   (stAtOff),HL                   ; Publish the exact byte offset within that part.
    LD   L,(IX+syLine)                  ; Recover the reference's line from the anchor.
    LD   H,(IX+syLine+1)                ; Complete it.
    LD   (stAtLine),HL                  ; Publish the line too.
    XOR  A                              ; No nested statement detail applies here.
    LD   (stDetail),A                   ; Clear any detail left by the final statement.

; Return public undefined status and symbol pointer for diagnostic
; name unpacking. Carry marks the finalisation failure.

    LD   IX,(drAbsent)                  ; Return the validated record for name decoding.
    LD   A,stUndef                      ; Report the statement-layer undefined status.
    SCF                                 ; Mark finalisation as failed.
    RET                                 ; The driver will abort the open generation.
.noPend: ; Validate symbols when no pending records remain.

; With no pending records, validate the final private-label scope without
; evicting it. An undefined private here is inconsistent because it has no
; diagnostic anchor.

    CALL syDropOk                       ; Validate the current private scope in place.
    JR   C,.corrupt                     ; A private failure without an anchor is corrupt.

; Private validation leaves that scope intact. Walk permanent globals
; and require every record's defined flag. an undefined global without pending
; metadata is likewise an internal invariant failure.

    LD   IX,(syBase)                    ; Begin at the permanent global-symbol arena.
    LD   DE,(syFreeLo)                  ; Load its current exclusive end.
.globLoop: ; Check each retained global is defined.
    CALL syAtEnd                        ; Compare the symbol cursor with the arena end.
    JR   Z,.ok                          ; Every retained global is defined.
    BIT  6,(IX+5)                       ; Test this global record's defined flag.
    JR   Z,.corrupt                     ; Undefined with no pending data is corrupt.
    LD   BC,syRecLen                    ; Load the eight-byte symbol-record stride.
    ADD  IX,BC                          ; Advance to the next permanent global.
    JR   .globLoop                      ; Validate it or finish the scan.
.ok: ; Return complete symbol state.
    XOR  A                              ; Return finalisation success with carry clear.
    RET                                 ; Symbol state is complete and internally sound.
.corrupt: ; Clear unsafe pointers and report internal corruption.

; Do not expose a stale or unvalidated pointer on an internal failure.

    XOR  A                              ; Produce zero for both pointer bytes.
    LD   (drAbsent),A                   ; Clear the public symbol pointer low byte.
    LD   (drAbsent+1),A                 ; Clear its high byte before returning failure.
    LD   A,stIntErr                     ; Report a statement-layer internal invariant.
    SCF                                 ; Mark finalisation as failed.
    RET                                 ; The driver will translate and abort.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
; First test the upward-growing global range [syBase, syFreeLo). Preserve the
; candidate around each subtraction because the comparisons destroy HL.

drPtrOk: ; Validate a live aligned symbol-record pointer.
    PUSH HL                             ; Preserve candidate for lower-bound test.
    LD   DE,(syBase)                    ; Load the first live global-record address.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare against global lower bound.
    POP  HL                             ; Restore the original candidate pointer.
    JR   C,.private                     ; Check private storage if below globals.
    PUSH HL                             ; Preserve it across the upper-bound compare.
    LD   DE,(syFreeLo)                  ; Load the exclusive end of live globals.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate against that exclusive end.
    POP  HL                             ; Restore the candidate again.
    JR   NC,.private                    ; Check private storage at/above global end.

; A global pointer is valid only at an eight-byte record boundary from the
; arena base. syRecLen is a power of two, so a mask performs the modulus test.

    LD   DE,(syBase)                    ; Measure candidate from the global arena base.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Produce the byte displacement from that base.
    LD   A,L                            ; Only low alignment bits can affect modulo eight.
    AND  syRecLen-1                     ; Keep displacement modulo the record size.
    RET  Z                              ; Zero means an exact global-record boundary.
    SCF                                 ; An interior byte is not a symbol pointer.
    RET                                 ; Return invalid global alignment.
.private: ; Check the downward-growing private-symbol range.

; Private records occupy [syFreeHi, syLimit) and grow down from syLimit.

    PUSH HL                             ; Preserve candidate for lower-bound test.
    LD   DE,(syFreeHi)                  ; Load the first live private-record address.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate with the private lower bound.
    POP  HL                             ; Restore the original candidate pointer.
    RET  C                              ; Below the live private range is invalid.
    PUSH HL                             ; Preserve it across the upper-bound compare.
    LD   DE,(syLimit)                   ; Load the symbol arena's exclusive end.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compare candidate with that exclusive end.
    POP  HL                             ; Restore the candidate for alignment testing.
    JR   NC,.invalid                    ; At or above arena end is not a live record.

; Measure backwards from the arena end to prove eight-byte alignment with the
; downward-growing record layout.

    LD   DE,(syLimit)                   ; Load the fixed high end of private allocation.
    EX   DE,HL                          ; Put arena end in HL and candidate in DE.
    OR   A                              ; Clear carry before the in-range subtraction.
    SBC  HL,DE                          ; Measure backwards from the arena end.
    LD   A,L                            ; Select the low alignment bits.
    AND  syRecLen-1                     ; Keep displacement modulo eight.
    RET  Z                              ; Zero means an exact private-record boundary.
.invalid: ; Reject an interior or out-of-range symbol pointer.
    SCF                                 ; Mark every other candidate pointer invalid.
    RET                                 ; The caller must not dereference it.
;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce a failure to one message number in drMsg. A holds the public driver
; status. A source failure nests up to three statuses: the statement category
; in drDetail, its subsystem status in stDetail and, for parser and expression
; failures, a further expression, symbol or tokenizer status. Each subsystem's
; codes map to a block of message numbers starting at its base: drTokMsg,
; drExMsg, drSymMsg, drInsMsg or drOutMsg.

drDiag: ; Translate nested statuses into diagnostic arguments.
    LD   C,drMsgNil                     ; Assume an undefined symbol.
    CP   drUndef                        ; Did finalisation find one?
    JP   Z,.undef                       ; Name it from drAbsent.
    LD   C,drMsgRej                     ; Assume the output was rejected.
    CP   drBadOut                       ; Did BEGIN or COMMIT fail?
    JP   Z,.set                         ; Report the output failure.
    LD   C,drMsgCfg                     ; Assume an invalid build description.
    CP   drBadCfg                       ; Was the descriptor rejected?
    JP   Z,.set                         ; Report the configuration failure.
    CP   drBadIn                        ; Did the host's source service fail?
    JR   NZ,.source                     ; No: look at the statement.
    LD   A,(drDetail)                   ; Its status is a message number.
    LD   C,A                            ; Report that message.
    JP   .set                           ; At the position tkOpen published.
.source: ; Classify the remaining statuses.
    LD   C,drMsgInt                     ; Anything other than a source error is internal.
    CP   drBadSrc                       ; Was a source statement rejected?
    JP   NZ,.set                        ; No: report an internal error.

    LD   A,(stDetail)                   ; Read the statement layer's detail.
    LD   E,A                            ; E holds the subsystem status from here on.
    LD   A,(drDetail)                   ; Read the statement category.
    CP   stSyntax                       ; Is it a statement-level grammar failure?
    JP   Z,.direct                      ; Its detail is already a message number.
    CP   stBadLex                       ; Did the tokenizer reject the source?
    JR   Z,.token                       ; Use the tokenizer block.
    CP   stBadSym                       ; Did a symbol operation fail?
    JR   Z,.symbol                      ; Use the symbol block.
    CP   stBadOut                       ; Did output or patching fail?
    JR   Z,.output                      ; Use the output block.
    CP   stBadIns                       ; Did instruction parsing fail?
    JR   Z,.parser                      ; Use the parser block.
    CP   stBadEqu                       ; Did an EQU expression fail?
    JR   Z,.expr                        ; Use the expression block.
    CP   stBadDir                       ; Did directive arguments fail?
    JR   Z,.expr                        ; Directives also report expression statuses.
    LD   C,drMsgInt                     ; Every other category is internal.
    JP   .set                           ; Publish the internal error.
.parser: ; Decode an instruction-parser failure.
    LD   A,E                            ; Inspect the parser status.
    CP   prFarRel                       ; Is it a relative jump out of range?
    JR   NZ,.parseErr                   ; No: no offset to report.
    LD   HL,(prRelVal)                  ; Load the rejected offset.
    LD   (drVal),HL                     ; Quote it in the message.
.parseErr: ; Select parser or nested expression detail.
    CP   prLexErr                       ; Did the tokenizer fail inside the operands?
    JR   Z,.lexical                     ; Use the tokenizer's own status.
    CP   prSymErr                       ; Did a symbol operation fail?
    JR   Z,.parseSym                    ; Use the retained symbol status.
    LD   B,drInsMsg                     ; Select the parser block.
    LD   D,prSrcCap+1                   ; It holds one message per parser status.
    CP   prExErr                        ; Did an operand expression fail?
    JP   NZ,.table                      ; No: report the parser status itself.
    LD   A,(prExDet)                    ; Load the retained expression status.
    LD   E,A                            ; Decode it as an expression failure.
.expr: ; Decode expression or nested lexical failure.
    LD   A,E                            ; Inspect the expression status.
    BIT  7,A                            ; Did the statement layer give a message number?
    JP   NZ,.direct                     ; Yes: use it directly.
    CP   exSymErr                       ; Did a symbol lookup fail?
    JR   Z,.exSym                       ; Use the expression's retained symbol status.
    CP   exLexErr                       ; Did the tokenizer fail inside the expression?
    JR   Z,.lexical                     ; Use the tokenizer's own status.
    LD   B,drExMsg                      ; Select the expression block.
    LD   D,exIntErr+1                   ; It holds one message per expression status.
    JP   .table                         ; Map the status.
.exSym: ; Read the expression symbol failure.
    LD   A,(exCause)                    ; Load the expression's symbol status.
    LD   E,A                            ; Decode it as a symbol failure.
    JR   .symbol                        ; Use the symbol block.
.parseSym: ; Read the parser symbol failure.
    LD   A,(prSymDet)                   ; Load the parser's symbol status.
    LD   E,A                            ; Decode it as a symbol failure.
.symbol: ; Decode a symbol-table failure.
    LD   A,E                            ; Inspect the symbol status.
    CP   syUndef                        ; Was a private label left undefined?
    JR   NZ,.syStat                     ; No: no name to report.
    LD   HL,(syNoDef)                   ; Load the undefined private record.
    LD   (drSym),HL                     ; Name it in the message.
.syStat: ; Select the symbol diagnostic block.
    LD   B,drSymMsg                     ; Select the symbol block.
    LD   D,syParts+1                    ; It holds one message per symbol status.
    JR   .table                         ; Map the status.
.lexical: ; Read the retained tokenizer failure.
    LD   A,(tkStatus)                   ; Load the tokenizer's own status.
    LD   E,A                            ; Decode it as a lexical failure.
.token: ; Select the tokenizer diagnostic block.
    LD   B,drTokMsg                     ; Select the tokenizer block.
    LD   D,tkBadLit+1                   ; It holds one message per tokenizer status.
    JR   .table                         ; Map the status.
.output: ; Decode output failure and pending-reference location.
    LD   A,(outBadOp)                   ; Did the sink reject an operation?
    OR   A                              ; Zero means an output-layer failure.
    LD   C,drMsgRej                     ; The sink's own status is in stDetail.
    JR   NZ,.set                        ; Report that the output could not be written.

; A range failure while patching a forward reference belongs to the
; referencing instruction. Move the location there and keep the definition
; that triggered the patch as the related location.

    LD   HL,(outCause)                  ; Quote the rejected value or offset.
    LD   (drVal),HL                     ; Keep it for the message.
    LD   HL,(outRec)                    ; Was a pending record being patched?
    LD   A,H                            ; Test its high byte.
    OR   L                              ; Zero means an ordinary output failure.
    JR   Z,.outTab                      ; Report the output status directly.
    LD   A,E                            ; Inspect the output status.
    LD   C,drMsgJmp                     ; Assume a relative jump out of range.
    CP   outFar                         ; Is it?
    JR   Z,.move                        ; Report it at the jump.
    LD   C,drMsgBig                     ; Assume a value out of range.
    CP   outRange                       ; Is it?
    JR   NZ,.outTab                     ; Other output failures keep their location.
.move: ; Move a patch failure to its original reference.
    LD   A,(stAtPart)                   ; The definition becomes the related location.
    LD   (drAtPart),A                   ; Keep its source part.
    LD   DE,(stAtOff)                   ; Load its source offset.
    LD   (drAtOff),DE                   ; Keep it too.
    LD   DE,(stAtLine)                  ; Load its line.
    LD   (drAtLine),DE                  ; Keep it too.
    LD   E,(HL)                         ; Read the record's symbol pointer low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the symbol pointer.
    LD   (drSym),DE                     ; Name the target symbol.
    LD   DE,syPart-1                    ; Step from the pointer's high byte to the part.
    ADD  HL,DE                          ; Address the reference's source part.
    LD   A,(HL)                         ; Read it.
    LD   (stAtPart),A                   ; The reference becomes the primary location.
    INC  HL                             ; Advance to its source offset.
    LD   E,(HL)                         ; Read the offset low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the offset.
    LD   (stAtOff),DE                   ; Publish the reference's position.
    INC  HL                             ; Advance to its line.
    LD   E,(HL)                         ; Read the line's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the line.
    LD   (stAtLine),DE                  ; Publish it too.
    JR   .set                           ; Publish the message selected in C.
.outTab: ; Select output status or pending-capacity detail.
    LD   A,E                            ; Instruction output preflights pending space.
    CP   syRefCap                       ; Is the pending arena full?
    JP   Z,.symbol                      ; Report too many forward references.
    LD   B,drOutMsg                     ; Select the output block.
    LD   D,outFar+1                     ; It holds one message per output status.
.table: ; Map a bounded subsystem status to a message.

; B is the block's first message number, D its length and E the status.

    LD   A,E                            ; Inspect the status.
    LD   C,drMsgInt                     ; Assume it falls outside the block.
    CP   D                              ; Is it a known status?
    JR   NC,.set                        ; No: report an internal error.
    ADD  A,B                            ; Form the message number.
    LD   C,A                            ; Select it.
.set: ; Publish the chosen diagnostic message.
    LD   A,C                            ; Publish the selected message number.
    LD   (drMsg),A                      ; Leave it for the host.
    RET                                 ; Return to drAsm.
.direct: ; Decode a direct statement-layer message number.

; Statement, EQU and directive failures that need no nested status store
; their message number in stDetail with bit 7 set. Sink statuses can also
; have bit 7 set, so only these categories are read this way.

    LD   A,E                            ; Recover the statement detail.
    AND  $7F                            ; Keep the message number.
    LD   C,A                            ; Select it.
    JR   .set                           ; Publish it.
.undef: ; Attach the unresolved symbol to the diagnostic.
    LD   HL,(drAbsent)                  ; The undefined symbol is the message argument.
    LD   (drSym),HL                     ; Publish it.
    JR   .set                           ; Publish the message number.
drEnd: ; Exclusive end of driver code.
drRamLo: ; Beginning of writable driver state.

; Address of the immutable build descriptor supplied to drAsm.

drDesc:    DW      0                    ; Saved build-descriptor address.

; Subsystem or configuration detail associated with the public driver status.

drDetail:   DB      0                   ; Nested status or configuration detail.

; Validated symbol pointer for undefined diagnostic, else zero.

drAbsent:    DW      0                  ; Validated undefined-symbol record address.

; Diagnostic message and arguments, published when drAsm fails. drDiag
; collects the symbol and value from the subsystem that failed.

drMsg:     DB      0                    ; Message number from src/host/diagnostics.mjs.
drAtPart:   DB      0                   ; Related location's source part, or $FF.
drAtOff:    DW      0                   ; Related location's source offset.
drAtLine:   DW      0                   ; Related location's line.
drSym:     DW      0                    ; Symbol record named by the message, or zero.
drVal:     DW      0                    ; Signed value quoted by the message.
drRamHi: ; Exclusive end of writable driver state.
