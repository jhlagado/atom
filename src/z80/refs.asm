;=============================================================================
;  Deferred references and parser publication
;=============================================================================
;
;  PURPOSE
;  -------
;  Convert unresolved operands into symbol-backed reference descriptions,
;  commit validated instruction records and queue pending patches only after
;  output accepts the corresponding instruction bytes.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;+---------------------------------------------------------------------------+
;| PR_CREFE - Preflight pending references before instruction output.        |
;|                                                                           |
;| Entry: Public references from the most recent successful parse.           |
;| Result: Carry clear when all references can be queued.                    |
;| Error: Carry set, A = symbol/pending publication status.                  |
;| Effect: Reads symbol and pending arenas without changing them.            |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| PR_QREFE - Queue references after instruction output succeeds.            |
;|                                                                           |
;| Entry: DE = logical address of the emitted instruction.                   |
;|        Public references from the most recent successful parse.           |
;| Result: Carry clear after every pending record is appended.               |
;| Error: Carry set, A = symbol/pending publication status.                  |
;| Effect: Appends records to the caller-owned pending arena.                |
;+---------------------------------------------------------------------------+
;
;  TRANSACTION RULE
;  ----------------
;
;  PR_FREFE locates every patch field and proves symbol-arena capacity before
;  inserting any missing symbol. PR_CMT copies the private instruction record
;  only after that work succeeds. PR_CREFE proves pending capacity before
;  image emission. PR_QREFE publishes the records after output accepts every
;  byte.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  This module owns the fixed parser workspace between PR_WBEG and PR_WEND. It
;  uses caller-owned symbol and pending arenas. Calls preserve stack balance,
;  may clobber registers named by each routine contract and are not reentrant.
;  Parse failures publish source positions; publication entries return symbol
;  or pending status directly.
;

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Turn private build references into public symbol-reference descriptions. The
; first pass locates the encoded field and final patch kind for each operand.

PR_FREFE:
    XOR  A                           ; Begin with build-reference index zero.
    LD   (PR_RSCAN),A                ; Publish the locator scan index.
.LRLOOP:
    LD   A,(PR_RBCNT)                ; Read the private build-record count.
    LD   B,A                         ; Preserve it for the loop bound.
    LD   A,(PR_RSCAN)                ; Load the current record index.
    CP   B                           ; Have all build records been located?
    JR   Z,.PREFEREN                 ; Begin symbol-capacity preflight.
    CALL PR_BRADR                    ; Address this build record in DE.
    LD   HL,PR_BLDOP                 ; Load its operand-index field offset.
    ADD  HL,DE                       ; Address the field in the build record.
    LD   A,(HL)                      ; Load the referenced operand index.
    LD   IX,PR_SCRAT                 ; Point IX at the validated instruction.
    CALL PT_LOCAT                    ; Find its encoded field and patch kind.
    JR   C,.UREF                     ; Reject an unpatchable operand form.

; Save the locator's patch kind and byte offset while returning to the
; selected thirteen-byte build entry.

    LD   (PR_RKSCR),A                ; Save the locator's patch kind.
    LD   A,B                         ; Move its encoded byte offset to A.
    LD   (PR_ROSCR),A                ; Save that offset across record lookup.
    LD   A,(PR_RSCAN)                ; Reload the build-record index.
    CALL PR_BRADR                    ; Address the same record in DE.
    LD   HL,PR_BKIND                 ; Load its expression-transform offset.
    ADD  HL,DE                       ; Address the transform field.
    LD   A,(HL)                      ; Read the unresolved transform.
    CP   EX_FLO                      ; Does LOW request the field's low byte?
    JR   Z,.LLREF                    ; Replace the ordinary patch kind.
    CP   EX_FHI                      ; Does HIGH request the high byte?
    JR   Z,.LHREF                    ; Replace the ordinary patch kind.
    LD   A,(PR_RKSCR)                ; Otherwise retain the locator's kind.
    JR   .LSKIND                     ; Store the final patch metadata.
.LLREF:
    LD   A,PT_KLB                    ; Select low-byte extraction patch.
    JR   .LBFUNCTI                   ; Check its field compatibility.
.LHREF:
    LD   A,PT_KHB                    ; Select high-byte extraction patch.
.LBFUNCTI:

; LOW/HIGH cannot transform relative or displacement patches. Relative fields
; subtract an address and both field types require signed-range semantics, not
; simple byte extraction.

    PUSH AF                          ; Preserve the LOW/HIGH patch kind.
    LD   A,(PR_RKSCR)                ; Recover the underlying field kind.
    CP   PT_KRELA                    ; Is it a relative branch field?
    JR   Z,.LBFINVAL                 ; Reject byte extraction from a branch.
    CP   PT_KDISP                    ; Is it an indexed displacement field?
    JR   Z,.LBFINVAL                 ; Reject extraction from displacement.
    POP  AF                          ; Restore the compatible LOW/HIGH kind.
.LSKIND:

; Store the final kind and encoded-field offset in the build record.

    LD   (HL),A                      ; Store the final patch kind.
    INC  HL                          ; Advance to encoded field offset.
    LD   A,(PR_ROSCR)                ; Recover the locator's byte offset.
    LD   (HL),A                      ; Store it in the build record.
    LD   HL,PR_RSCAN                 ; Address the locator scan index.
    INC  (HL)                        ; Advance to the next build record.
    JR   .LRLOOP                     ; Locate every deferred field first.
.LBFINVAL:
    POP  AF                          ; Balance the saved LOW/HIGH kind.
.UREF:
    LD   A,PR_SUNPA                  ; Select unsupported-patch status.
    JP   PR_FREF                     ; Fail at this reference position.
.PREFEREN:

; Count exact missing symbol records before inserting any. When both
; references share one key, only the first consumes capacity.

    XOR  A                           ; Clear allocation flags.
    LD   (PR_RMCNT),A                ; No missing symbol records counted yet.
    LD   (PR_RSKEY),A                ; Assume two keys differ.
    LD   A,(PR_RBCNT)                ; Read the build-reference count.
    OR   A                           ; Are there any deferred references?
    RET  Z                           ; Return success when there are none.
    CP   2                           ; Are both fixed record slots occupied?
    JR   NZ,.PFIRST                  ; A single record cannot share a key.
    CALL PR_CRKEY                    ; Compare both packed keys exactly.

; Carry clear means equal keys. Convert that result to one in PR_RSKEY.

    SBC  A,A                         ; Equal/carry-clear becomes zero.
    INC  A                           ; Map equal to one, different to zero.
    LD   (PR_RSKEY),A                ; Record the shared-symbol flag.
.PFIRST:
    XOR  A                           ; Select build-reference record zero.
    LD   (PR_RSCAN),A                ; Publish it for lookup diagnostics.
    CALL PR_PREF                     ; Count its symbol only if missing.
    RET  C                           ; Preserve a scope or symbol failure.
    LD   A,(PR_RBCNT)                ; Recover the build-reference count.
    CP   2                           ; Does a second reference exist?
    JR   NZ,.PCAP                    ; One lookup completed the preflight.
    LD   A,(PR_RSKEY)                ; Do both references use the same symbol?
    OR   A                           ; One means the first lookup covers both.
    JR   NZ,.PCAP                    ; Avoid double-counting a shared symbol.
    LD   A,1                         ; Select build-reference record one.
    LD   (PR_RSCAN),A                ; Publish it for lookup diagnostics.
    CALL PR_PREF                     ; Count its distinct symbol if missing.
    RET  C                           ; Preserve a scope or symbol failure.
.PCAP:
    LD   A,(PR_RMCNT)                ; Load the exact missing-symbol count.
    OR   A                           ; Is symbol allocation unnecessary?
    JR   Z,.PREFERE1                 ; Skip the arena check when all exist.

; Each missing symbol needs one eight-byte record. Check the complete
; requirement against the gap between globals and private symbols.

    ADD  A,A                         ; Multiply record count by two bytes.
    ADD  A,A                         ; Multiply it by four bytes.
    ADD  A,A                         ; Reach eight bytes per symbol record.
    LD   B,A                         ; B carries the total required capacity.
    LD   HL,(SY_LBEG)                ; Load the private-record lower edge.
    LD   DE,(SY_GEND)                ; Global records end at this edge.
    CALL AT_RHCAP                    ; Prove the gap holds every new record.
    JP   C,PR_SCFAI                  ; Translate insufficient symbol capacity.
.PREFERE1:

; Capacity is now proved. Resolve or insert every key and construct the public
; nine-byte descriptions in source operand order.

    XOR  A                           ; Begin publication at reference zero.
    LD   (PR_RSCAN),A                ; Publish the current build-record index.
.PRLOOP:
    LD   A,(PR_RBCNT)                ; Read the number of build records.
    LD   B,A                         ; Preserve it as the loop bound.
    LD   A,(PR_RSCAN)                ; Load the current record index.
    CP   B                           ; Have all references been published?
    JR   Z,.PRCNT                    ; Commit the final reference count.
    CALL PR_BRADR                    ; Address the current packed key in DE.
    LD   H,D                         ; Move the key pointer into HL.
    LD   L,E                         ; Complete the pointer for SY_REF.
    CALL SY_REF                      ; Find or insert the undefined symbol.
    JP   C,PR_USFAI                  ; Any post-preflight failure is internal.
    LD   A,B                         ; SY_REF reports insertion as nonzero B.
    OR   A                           ; Was a new undefined symbol inserted?
    JR   Z,.RDREADY                  ; A found record already has an anchor.

; A new undefined record retains the first reference position in its unused
; value word. Mark this pending kind as the diagnostic anchor that can report
; an undefined symbol at finalisation.

    LD   A,(PR_RSCAN)                ; Reload the current build-record index.
    CALL PR_BRADR                    ; Address that record in DE.
    LD   HL,PR_BSOFF                 ; Load its source-offset field position.
    ADD  HL,DE                       ; Address the source offset.
    LD   A,(HL)                      ; Read its low byte.
    LD   (IX+SY_VALLO),A             ; Store diagnostic offset low byte.
    INC  HL                          ; Advance to source-offset high byte.
    LD   A,(HL)                      ; Read that high byte.
    LD   (IX+SY_VALHI),A             ; Complete the anchored source offset.
    LD   A,(PR_RSCAN)                ; Reload the build-record index again.
    CALL PR_BRADR                    ; Address the private build record in DE.
    LD   A,SY_DANCH                  ; Select the diagnostic-anchor flag.
    LD   HL,PR_BKIND                 ; Load the patch-kind field offset.
    ADD  HL,DE                       ; Address the stored patch kind.
    OR   (HL)                        ; Add the anchor flag to the patch kind.
    LD   (HL),A                      ; Publish the anchor on this reference.
.RDREADY:

; Public record: symbol pointer, addend, operand index, patch kind and anchor,
; encoded byte offset, source part and source offset.

    PUSH IX                          ; Transfer symbol pointer via the stack.
    POP  BC                          ; BC now holds the symbol pointer.
    LD   A,(PR_RSCAN)                ; Select the matching public record.
    CALL PR_PRADR                    ; Return its base address in HL.
    LD   (HL),C                      ; Store symbol pointer low byte.
    INC  HL                          ; Advance to pointer high byte.
    LD   (HL),B                      ; Complete the symbol pointer.
    INC  HL                          ; Advance to the public addend field.
    PUSH HL                          ; Preserve the public-copy destination.
    LD   A,(PR_RSCAN)                ; Reload the private record index.
    CALL PR_BRADR                    ; Address the private record in DE.
    LD   HL,PR_BADDE                 ; Load its trailing-field offset.
    ADD  HL,DE                       ; Address the copied tail at its addend.
    POP  DE                          ; Restore the public-copy destination.
    LD   BC,7                        ; Seven trailing bytes remain.
    LDIR                             ; Copy addend, patch metadata and source.
    LD   HL,PR_RSCAN                 ; Address the publication scan index.
    INC  (HL)                        ; Advance to the next reference.
    JR   .PRLOOP                     ; Publish every prepared record.
.PRCNT:

; Publish the count after every record and symbol insertion succeeds.

    LD   A,(PR_RBCNT)                ; Recover the completed reference count.
    LD   (PR_RCNT),A                 ; Publish all public records atomically.
    XOR  A                           ; Return success with carry clear.
    RET                              ; The instruction may now commit.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Inspect one build key without mutation. Not-found increments the exact
; missing count. Scope and other failures retain their nested status.

PR_PREF:
    LD   A,(PR_RSCAN)                ; Select the build record to inspect.
    CALL PR_BRADR                    ; Address its packed key in DE.
    LD   H,D                         ; Move the key pointer into HL.
    LD   L,E                         ; Complete the SY_FIND input pointer.
    CALL SY_FIND                     ; Search without inserting a symbol.
    RET  NC                          ; A found symbol needs no new record.
    CP   SY_SNFOU                    ; Is absence the only failure?
    JR   NZ,PR_SFAIL                 ; Preserve scope or key diagnostics.
    LD   HL,PR_RMCNT                 ; Address the missing-symbol count.
    INC  (HL)                        ; Count one required eight-byte record.
    XOR  A                           ; Convert absence to preflight success.
    RET                              ; Continue without mutating the arena.
PR_SFAIL:
    LD   (PR_SSTAT),A                ; Retain the nested symbol status.
    LD   A,PR_SSYM                   ; Select the parser symbol category.
    JP   PR_FREF                     ; Fail at this build record's source.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,B
; Compare the two six-byte packed keys. Carry clear means identical.

PR_CRKEY:
    LD   HL,PR_RBLD               ; Point HL at the first packed symbol key.
    LD   DE,PR_RBLD+PR_BRB        ; Point DE at the second packed key.
    LD   B,6                      ; Compare all six packed-name bytes.
.CRKLOOP:
    LD   A,(DE)                   ; Load the next byte from the second key.
    CP   (HL)                     ; Compare it with the matching first byte.
    SCF                           ; Prepare carry-set inequality result.
    RET  NZ                      ; Return different at the first mismatch.
    INC  DE                      ; Advance the second-key cursor.
    INC  HL                      ; Advance the first-key cursor.
    DJNZ .CRKLOOP                ; Compare the remaining key bytes.
    OR   A                       ; Equal keys return with carry clear.
    RET                          ; Report exact key equality.

; Translate symbol-arena capacity failure into the parser's symbol status.

PR_SCFAI:
    LD   A,SY_SSCAP              ; Use the symbol-arena capacity detail.
    JR   PR_SFAIL                ; Return it through the parser category.

; Report an unexpected symbol insertion failure after successful preflight.
; Exact lookup and capacity checks should make this path unreachable.

PR_USFAI:
    LD   (PR_SSTAT),A             ; Preserve the unexpected symbol status.
    LD   A,PR_SINT                ; Report a parser internal failure.
    JP   PR_FREF                  ; Anchor it at the current reference.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Return public-reference address A. Two fixed nine-byte slots cover the
; parser reference capacity.

PR_PRADR:
    LD   HL,PR_REFER              ; Start at public record zero.
    OR   A                        ; Is record zero requested?
    RET  Z                        ; Return its address directly.
    LD   DE,PR_PRB                ; Load one public-record stride.
    ADD  HL,DE                    ; Advance to fixed record one.
    RET                           ; Return the selected record address.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO,IX
; Before emitting an instruction byte, prove that the pending arena has room
; for every reference and that each symbol remains undefined. Each entry is
; seven bytes including its full source-part ordinal. PR_QREFE allocates the
; records after output accepts the instruction.

PR_CREFE:
    LD   A,(PR_RCNT)              ; Load the public-reference count.
    LD   B,A                      ; Retain the count for multiplication.
    ADD  A,A                     ; Form two bytes per reference.
    ADD  A,B                     ; Form three bytes per reference.
    ADD  A,A                     ; Form six bytes per reference.
    ADD  A,B                     ; Reach the seven-byte record size.
    LD   B,A                      ; B is the complete pending requirement.
    LD   HL,(SY_AEND1)            ; Load the pending-arena exclusive end.
    LD   DE,(SY_NEXT)             ; Load its next free address.
    CALL AT_RHCAP                 ; Check the remaining half-open capacity.
    JR   C,PR_QCAP                ; Reject before any output or allocation.
.QCSYMBOL:

; A symbol defined between parse and emission would make the already encoded
; placeholder invalid. Treat it as a defensive publication-state failure.

    XOR  A                        ; Begin at public reference zero.
    LD   (PR_RSCAN),A             ; Publish the verification index.
.QCLOOP:
    LD   A,(PR_RCNT)              ; Read the reference count.
    LD   B,A                      ; Retain it as the loop bound.
    LD   A,(PR_RSCAN)             ; Load the current reference index.
    CP   B                        ; Have all symbols been checked?
    JR   Z,.QPDONE                ; Return success after the final record.
    CALL PR_PRADR                 ; Address this public reference.
    LD   E,(HL)                   ; Load symbol pointer low byte.
    INC  HL                       ; Advance to pointer high byte.
    LD   D,(HL)                   ; Complete the symbol pointer.
    EX   DE,HL                    ; Move the symbol address into HL.
    LD   DE,5                     ; Select its packed-name flag byte.
    ADD  HL,DE                    ; Address the symbol flags.
    BIT  6,(HL)                   ; Has the symbol become defined?
    JR   NZ,PR_QADEF              ; Reject a stale deferred reference.
    LD   HL,PR_RSCAN              ; Address the verification index.
    INC  (HL)                     ; Advance to the next public record.
    JR   .QCLOOP                  ; Check every referenced symbol.
.QPDONE:
    XOR  A                        ; Report success with carry clear.
    RET                           ; Pending capacity is now proved.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Queue every public reference after the encoded bytes have been accepted. DE
; supplies the instruction's logical start address. A second preflight
; protects direct callers and keeps this entry self-contained.

PR_QREFE:
    LD   (PR_QBASE),DE            ; Retain the instruction start address.
    CALL PR_CREFE                 ; Recheck capacity and symbol state.
    RET  C                        ; Publish nothing when preflight fails.
.QUEUECMT:
    XOR  A                        ; Begin with public reference zero.
    LD   (PR_RSCAN),A             ; Publish the queue index.
.QLOOP:
    LD   A,(PR_RCNT)              ; Read the number of public references.
    LD   B,A                      ; Retain it as the loop bound.
    LD   A,(PR_RSCAN)             ; Load the current reference index.
    CP   B                        ; Have all pending records been queued?
    JR   Z,.QDONE                 ; Return after the final record.
    CALL PR_PRADR                 ; Address the selected public record.

; Load the symbol pointer, signed addend, final kind, source part and encoded
; byte offset from the public record.

    LD   E,(HL)                   ; Load symbol pointer low byte.
    INC  HL                       ; Advance to pointer high byte.
    LD   D,(HL)                   ; Complete the symbol pointer.
    PUSH DE                       ; Transfer the pointer through the stack.
    POP  IX                       ; IX now identifies the symbol record.
    INC  HL                       ; Advance to the signed addend.
    LD   C,(HL)                   ; C carries that addend to SY_ADD.
    INC  HL                       ; Skip to the operand index.
    INC  HL                       ; Advance to patch kind and anchor flag.
    LD   B,(HL)                   ; B carries kind and anchor metadata.
    INC  HL                       ; Advance to encoded field offset.
    LD   A,(HL)                   ; Load the field's byte offset.
    LD   (PR_ROSCR),A             ; Save it across the address calculation.
    INC  HL                       ; Advance to the source-part ordinal.
    LD   A,(HL)                   ; Load the diagnostic source part.
    LD   (PR_RKSCR),A             ; Save it across address calculation.
    LD   A,(PR_ROSCR)             ; Recover the encoded field offset.
    LD   HL,(PR_QBASE)            ; Load the instruction start address.
    LD   E,A                      ; Extend the unsigned byte offset in DE.
    LD   D,0                      ; Clear the offset's high byte.
    ADD  HL,DE                    ; Calculate the logical patch address.
    EX   DE,HL                    ; Put that address in SY_ADD's DE input.

; SY_ADD receives A=part, IX=symbol, DE=patch address, B=kind and C=addend.
; B also carries the diagnostic-anchor flag.

    LD   A,(PR_RKSCR)             ; Restore the diagnostic source part.
    CALL SY_ADD                   ; Append the complete pending record.
    RET  C                        ; Preserve any defensive arena failure.
    LD   HL,PR_RSCAN              ; Address the queue index.
    INC  (HL)                     ; Advance after successful publication.
    JR   .QLOOP                   ; Queue the remaining references.
.QDONE:
    XOR  A                        ; Return success with carry clear.
    RET                           ; Every reference is now pending.

; Report that the pending arena cannot hold the complete reference set.

PR_QCAP:
    LD   A,SY_SPCAP              ; Report pending-arena capacity failure.
    SCF                           ; Mark the preflight as failed.
    RET                           ; No pending record was appended.

; Report a symbol defined before its deferred reference is queued.

PR_QADEF:
    LD   A,SY_SADEF              ; Report an already-defined symbol.
    SCF                           ; Mark the publication state invalid.
    RET                           ; Leave the pending arena unchanged.

; Report a reference-build failure at the evaluator's saved symbol position.
; PR_PUB callers use the enclosing statement; PR_PARSE callers receive these
; parser fields directly.

PR_FESYM:
    LD   (PR_ESTAT),A             ; Save the evaluator or symbol status.
    LD   A,(EX_SPART)             ; Load the deferred symbol's source part.
    LD   (PR_EPART),A             ; Publish that diagnostic part.
    LD   HL,(EX_SOFF)             ; Load the symbol's source offset.
    LD   (PR_EOFF),HL             ; Publish the diagnostic byte offset.
    LD   A,(PR_ESTAT)             ; Restore the failure status.
    SCF                           ; Mark the parse as failed.
    RET                           ; Return the symbol's exact position.

; Report a reference-finalisation failure at the source position in the
; current private build record selected by PR_RSCAN.

PR_FREF:
    LD   (PR_ESTAT),A             ; Preserve the reference failure status.
    LD   A,(PR_RSCAN)             ; Select the failing private record.
    CALL PR_BRADR                 ; Address that record in DE.
    LD   HL,PR_BPART              ; Load its source-part field offset.
    ADD  HL,DE                    ; Address the stored source position.
    LD   A,(HL)                   ; Load the source-part ordinal.
    LD   (PR_EPART),A             ; Publish it for the caller.
    INC  HL                       ; Advance to source-offset low byte.
    LD   E,(HL)                   ; Load the low byte.
    INC  HL                       ; Advance to source-offset high byte.
    LD   D,(HL)                   ; Complete the byte offset.
    LD   (PR_EOFF),DE             ; Publish the reference position.
    LD   A,(PR_ESTAT)             ; Restore the parser failure status.
    SCF                           ; Mark the parse as failed.
    RET                           ; Return the exact reference position.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Commit the fully validated private record to the caller's destination and
; return IX pointing at it. No earlier parser path writes the destination.

PR_CMT:
    LD   HL,PR_SCRAT              ; Point at the validated private record.
    LD   DE,(PR_DST)              ; Load the caller's destination.
    LD   BC,10                    ; Copy the complete encoder record.
    LDIR                          ; Commit all fields together.
    LD   IX,(PR_DST)              ; Return the committed record pointer.
    XOR  A                        ; Report success with carry clear.
    RET                           ; Publication is complete.

; Compact status adapters select the appropriate source anchor below.

PR_EMNEM:
    LD   A,PR_SEMNE               ; Report an empty mnemonic.
    JR   PR_FHERE                 ; Use the current token position.
PR_UMNEM:
    LD   A,PR_SUMNE               ; Report an unknown mnemonic.
    JR   PR_FHERE                 ; Use the current token position.
PR_EXPOP:
    LD   A,PR_SEOP                ; Report an expected operand.
    JR   PR_FHERE                 ; Use the current token position.
PR_UOP:
    LD   A,PR_SUOP                ; Report an unsupported operand form.
    JR   PR_FHERE                 ; Use the current token position.
PR_EDELI:
    LD   A,PR_SEDEL               ; Report a missing operand delimiter.
    JR   PR_FHERE                 ; Use the current token position.
PR_TMOPE:
    LD   A,PR_STMOP               ; Report more than three operands.
    JR   PR_FHERE                 ; Use the current token position.
PR_VRANG:
    LD   A,PR_SVRAN               ; Report a concrete operand range error.
    JR   PR_FHERE                 ; Use the current token position.
PR_RRANG:
    LD   A,PR_SRRAN               ; Report relative displacement overflow.
    JR   PR_FBEG                  ; Anchor it at the mnemonic.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token position for token-local syntax and value failures.

PR_FHERE:
    LD   HL,TK_REC+TK_POFF        ; Point at token part and offset fields.
    JR   PR_FPOSI                 ; Copy that contiguous position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the mnemonic position for form and relative-range failures.
; PR_PARSE captures this position. The statement layer supplies its own outer
; position when it calls PR_PUB.

PR_FBEG:
    LD   HL,PR_IPART              ; Point at saved mnemonic part and offset.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy a contiguous part-and-offset triple into the parser error fields.
; Preserve the status in A and set carry.

PR_FPOSI:
    LD   (PR_ESTAT),A             ; Preserve the public parser status.
    PUSH BC                       ; Preserve the caller's BC pair.
    PUSH DE                       ; Preserve the caller's DE pair.
    LD   DE,PR_EPART              ; Select the parser position destination.
    LD   BC,3                     ; Copy part plus two-byte offset.
    LDIR                          ; Publish the contiguous source position.
    POP  DE                       ; Restore the caller's DE pair.
    POP  BC                       ; Restore the caller's BC pair.
    LD   A,(PR_ESTAT)             ; Restore the public parser status.
    SCF                           ; Mark the parse as failed.
    RET                           ; Return the published position.
PR_RCEND:
PR_IBEG:

; Sorted RADIX-40 operand-word table. Each three-byte entry contains one
; packed word and its provisional encoder class. C maps to PR_GC because only
; complete form validation can distinguish register C from condition C.

PR_OWCNT EQU 27                  ; Number of three-byte operand-word entries.
PR_OWTAB:
    DW  $0640                    ; Packed operand word A.
    DB  EN_A                     ; Accumulator register class.
    DW  $0730                    ; Packed operand word AF.
    DB  EN_AF                    ; AF register-pair class.
    DW  $0C80                    ; Packed operand word B.
    DB  EN_B                     ; B register class.
    DW  $0CF8                    ; Packed operand word BC.
    DB  EN_BC                    ; BC register-pair class.
    DW  $12C0                    ; Packed operand word C.
    DB  PR_GC                    ; Ambiguous register or condition class.
    DW  $1900                    ; Packed operand word D.
    DB  EN_D                     ; D register class.
    DW  $19C8                    ; Packed operand word DE.
    DB  EN_DE                    ; DE register-pair class.
    DW  $1F40                    ; Packed operand word E.
    DB  EN_E                     ; E register class.
    DW  $3200                    ; Packed operand word H.
    DB  EN_H                     ; H register class.
    DW  $33E0                    ; Packed operand word HL.
    DB  EN_HL                    ; HL register-pair class.
    DW  $3840                    ; Packed operand word I.
    DB  EN_I                     ; Interrupt-vector register class.
    DW  $3C00                    ; Packed operand word IX.
    DB  EN_IX                    ; IX register-pair class.
    DW  $3C08                    ; Packed operand word IXH.
    DB  EN_IXH                   ; IX high-byte register class.
    DW  $3C0C                    ; Packed operand word IXL.
    DB  EN_IXL                   ; IX low-byte register class.
    DW  $3C28                    ; Packed operand word IY.
    DB  EN_IY                    ; IY register-pair class.
    DW  $3C30                    ; Packed operand word IYH.
    DB  EN_IYH                   ; IY high-byte register class.
    DW  $3C34                    ; Packed operand word IYL.
    DB  EN_IYL                   ; IY low-byte register class.
    DW  $4B00                    ; Packed operand word L.
    DB  EN_L                     ; L register class.
    DW  $5140                    ; Packed operand word M.
    DB  EN_M                     ; Minus condition class.
    DW  $57F8                    ; Packed operand word NC.
    DB  EN_NC                    ; No-carry condition class.
    DW  $5B90                    ; Packed operand word NZ.
    DB  EN_NZ                    ; Nonzero condition class.
    DW  $6400                    ; Packed operand word P.
    DB  EN_P                     ; Plus condition class.
    DW  $64C8                    ; Packed operand word PE.
    DB  EN_PE                    ; Parity-even condition class.
    DW  $6658                    ; Packed operand word PO.
    DB  EN_PO                    ; Parity-odd condition class.
    DW  $7080                    ; Packed operand word R.
    DB  EN_R                     ; Memory-refresh register class.
    DW  $7940                    ; Packed operand word SP.
    DB  EN_SP                    ; Stack-pointer class.
    DW  $A280                    ; Packed operand word Z.
    DB  EN_Z                     ; Zero condition class.
PR_OWTEN:
PR_IEND:
PR_CEND:
PR_WBEG:

; Per-call destinations and instruction identity. PR_ILEN is returned by
; EN_VFORM and is required for relative-target conversion.

PR_DST: DW 0                      ; Caller-owned ten-byte commit destination.
PR_IADR: DW 0                     ; Current instruction's logical address.
PR_IPART: DB 0                    ; Source part containing the mnemonic.
PR_IOFF: DW 0                     ; Byte offset of the mnemonic in that part.
PR_ILEN: DB 0                     ; Validated encoded instruction length.
PR_OPCNT: DB 0                    ; Parsed operand count, zero to three.

; Shared scan index, ambiguity masks and selected class/value pointers used by
; operand normalisation and range checking.

PR_SINDE: DB 0                    ; Operand index used by normalisation loops.
PR_FMASK: DB 0                    ; Byte-value fields that may widen to words.
PR_CMASK: DB 0                    ; C fields that may be condition C.
PR_CPTR: DW 0                     ; Selected operand-class byte address.
PR_VPTR: DW 0                     ; Selected operand-value word address.
PR_LCLAS: DB 0                    ; Operand class saved across token fetch.
PR_MBASE: DB 0                    ; Parenthesised register or port base class.
PR_ICLAS: DB 0                    ; Indexed IX/IY class saved during parsing.

; Retained workspace byte with no caller in the current parser implementation.

PR_DSIGN: DB 0                    ; Reserved legacy displacement-sign scratch.

; Six-byte packed operand key and private ten-byte instruction record.
; Selected scratch bytes are also reused for nested status and source fields.
; Terminal errors prevent commit, but a recovered short-word probe may leave
; ignored error bytes in unused operand-value slots of a successful record.

PR_NKEY: DS 6                     ; Packed short operand-word key buffer.
PR_SCRAT: DS 10                   ; Private encoder-format instruction record.
PR_ESTAT EQU PR_SCRAT+6           ; Public parser error status overlay.
PR_EPART EQU PR_SCRAT+7           ; Public error source-part overlay.
PR_EOFF EQU PR_SCRAT+8            ; Public error source-offset overlay.
PR_ESTA1 EQU PR_SCRAT+5           ; Nested expression status overlay.
PR_SSTAT EQU PR_SCRAT+5           ; Nested symbol status overlay.

; Reference publication state. PR_RBCNT counts private entries. PR_RCNT is
; published after their symbols and public records are complete.

PR_RCNT: DB 0                     ; Published reference-description count.
PR_RBCNT: DB 0                    ; Private build-reference count.
PR_UMASK: DB 0                    ; Bits marking unresolved operand values.
PR_RSCAN: DB 0                    ; Reference index during publication.
PR_RMCNT: DB 0                    ; Missing symbols for this instruction.
PR_RSKEY: DB 0                    ; One when both build records share a key.
PR_RKSCR: DB 0                    ; Patch kind or queued source-part ordinal.
PR_ROSCR: DB 0                    ; Encoded field offset across lookup.
PR_RASCR: DW 0                    ; Signed addend before key copying.
PR_QBASE: DW 0                    ; Logical instruction base while queueing.

; Two thirteen-byte build entries and two nine-byte public entries complete
; the fixed 92-byte parser workspace.

PR_RBLD: DS PR_BRB*PR_RCAP        ; Two private thirteen-byte build records.
PR_REFER: DS PR_PRB*PR_RCAP       ; Two public nine-byte reference records.
PR_WEND:
