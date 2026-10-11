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
;| PR_CHECK - Preflight pending references before instruction output.        |
;|                                                                           |
;| Entry: Public references from the most recent successful parse.           |
;| Result: Carry clear when all references can be queued.                    |
;| Error: Carry set, A = symbol/pending publication status.                  |
;| Effect: Reads symbol and pending arenas without changing them.            |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| PR_QUEUE - Queue references after instruction output succeeds.            |
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
;  PR_BIND locates every patch field and proves symbol-arena capacity before
;  inserting any missing symbol. PR_CMT copies the private instruction record
;  only after that work succeeds. PR_CHECK proves pending capacity before
;  image emission. PR_QUEUE publishes the records after output accepts every
;  byte.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  This module owns the fixed parser workspace between PR_WBEG and PR_WEND. It
;  uses caller-owned symbol and pending arenas. Calls preserve stack balance,
;  may clobber registers named by each routine contract and are not reentrant.
;  Parse failures publish source positions. Publication entries return symbol
;  or pending status directly.
;

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Turn private build references into public symbol-reference descriptions. The
; first pass locates the encoded field and final patch kind for each operand.

PR_BIND: ; Locate deferred fields and publish their symbol descriptions.
    XOR  A                              ; Begin with build-reference index zero.
    LD   (PR_RIDX),A                    ; Publish the locator scan index.
.FINDLOOP: ; Validate one deferred operand's encoded field per iteration.
    LD   A,(PR_BRCNT)                   ; Read the private build-record count.
    LD   B,A                            ; Preserve it for the loop bound.
    LD   A,(PR_RIDX)                    ; Load the current record index.
    CP   B                              ; Have all build records been located?
    JR   Z,.COUNT                       ; Begin symbol-capacity preflight.
    CALL PR_BRADR                       ; Address this build record in DE.
    LD   HL,PR_BOPER                    ; Load its operand-index field offset.
    ADD  HL,DE                          ; Address the field in the build record.
    LD   A,(HL)                         ; Load the referenced operand index.
    LD   IX,PR_REC                      ; Point IX at the validated instruction.
    CALL PT_FIELD                       ; Find its encoded field and patch kind.
    JR   C,.NOPATCH                     ; Reject an unpatchable operand form.

; Save the locator's patch kind and byte offset while returning to the
; selected thirteen-byte build entry.

    LD   (PR_TMP),A                     ; Save the locator's patch kind.
    LD   A,B                            ; Move its encoded byte offset to A.
    LD   (PR_FIELD),A                   ; Save that offset across record lookup.
    LD   A,(PR_RIDX)                    ; Reload the build-record index.
    CALL PR_BRADR                       ; Address the same record in DE.
    LD   HL,PR_BKIND                    ; Load its expression-transform offset.
    ADD  HL,DE                          ; Address the transform field.
    LD   A,(HL)                         ; Read the unresolved transform.
    CP   EX_FLO                         ; Does LOW request the field's low byte?
    JR   Z,.LOWBYTE                     ; Replace the ordinary patch kind.
    CP   EX_FHI                         ; Does HIGH request the high byte?
    JR   Z,.HIBYTE                      ; Replace the ordinary patch kind.
    LD   A,(PR_TMP)                     ; Otherwise retain the locator's kind.
    JR   .SETKIND                       ; Store the final patch metadata.
.LOWBYTE: ; Select LOW extraction for a compatible encoded field.
    LD   A,PT_KLB                       ; Select low-byte extraction patch.
    JR   .EXTRACT                       ; Check its field compatibility.
.HIBYTE: ; Select HIGH extraction for a compatible encoded field.
    LD   A,PT_KHB                       ; Select high-byte extraction patch.
.EXTRACT: ; Reject projections on relative or indexed displacements.

; LOW/HIGH cannot transform relative or displacement patches. Relative fields
; subtract an address and both field types require signed-range semantics, not
; simple byte extraction.

    PUSH AF                             ; Preserve the LOW/HIGH patch kind.
    LD   A,(PR_TMP)                     ; Recover the underlying field kind.
    CP   PT_KREL                        ; Is it a relative branch field?
    JR   Z,.BADLOHI                     ; Reject byte extraction from a branch.
    CP   PT_KDISP                       ; Is it an indexed displacement field?
    JR   Z,.BADLOHI                     ; Reject extraction from displacement.
    POP  AF                             ; Restore the compatible LOW/HIGH kind.
.SETKIND: ; Store final patch kind and encoded byte offset together.

; Store the final kind and encoded-field offset in the build record.

    LD   (HL),A                         ; Store the final patch kind.
    INC  HL                             ; Advance to encoded field offset.
    LD   A,(PR_FIELD)                   ; Recover the locator's byte offset.
    LD   (HL),A                         ; Store it in the build record.
    LD   HL,PR_RIDX                     ; Address the locator scan index.
    INC  (HL)                           ; Advance to the next build record.
    JR   .FINDLOOP                      ; Locate every deferred field first.
.BADLOHI: ; Unwind the saved projection before reporting failure.
    POP  AF                             ; Balance the saved LOW/HIGH kind.
.NOPATCH: ; Report an unsupported deferred patch at its source position.
    LD   A,PR_SUNPA                     ; Select unsupported-patch status.
    JP   PR_FREF                        ; Fail at this reference position.
.COUNT: ; Count distinct missing symbols before any allocation.

; Count exact missing symbol records before inserting any. When both
; references share one key, only the first consumes capacity.

    XOR  A                              ; Clear allocation flags.
    LD   (PR_MISS),A                    ; No missing symbol records counted yet.
    LD   (PR_SAME),A                    ; Assume two keys differ.
    LD   A,(PR_BRCNT)                   ; Read the build-reference count.
    OR   A                              ; Are there any deferred references?
    RET  Z                              ; Return success when there are none.
    CP   2                              ; Are both fixed record slots occupied?
    JR   NZ,.FIRST                      ; A single record cannot share a key.
    CALL PR_KEYEQ                       ; Compare both packed keys exactly.

; Carry clear means equal keys. Convert that result to one in PR_SAME.

    SBC  A,A                            ; Equal/carry-clear becomes zero.
    INC  A                              ; Map equal to one, different to zero.
    LD   (PR_SAME),A                    ; Record the shared-symbol flag.
.FIRST: ; Inspect the first key and retain its diagnostic index.
    XOR  A                              ; Select build-reference record zero.
    LD   (PR_RIDX),A                    ; Publish it for lookup diagnostics.
    CALL .LOOKUP                        ; Count its symbol only if missing.
    RET  C                              ; Preserve a scope or symbol failure.
    LD   A,(PR_BRCNT)                   ; Recover the build-reference count.
    CP   2                              ; Does a second reference exist?
    JR   NZ,.CAPACITY                   ; One lookup completed the preflight.
    LD   A,(PR_SAME)                    ; Do both references use the same symbol?
    OR   A                              ; One means the first lookup covers both.
    JR   NZ,.CAPACITY                   ; Avoid double-counting a shared symbol.
    LD   A,1                            ; Select build-reference record one.
    LD   (PR_RIDX),A                    ; Publish it for lookup diagnostics.
    CALL .LOOKUP                        ; Count its distinct symbol if missing.
    RET  C                              ; Preserve a scope or symbol failure.
.CAPACITY: ; Prove the exact symbol-record requirement fits the arena.
    LD   A,(PR_MISS)                    ; Load the exact missing-symbol count.
    OR   A                              ; Is symbol allocation unnecessary?
    JR   Z,.PUBLISH                     ; Skip the arena check when all exist.

; Each missing symbol needs one eight-byte record. Check the complete
; requirement against the gap between globals and private symbols.

    ADD  A,A                            ; Multiply record count by two bytes.
    ADD  A,A                            ; Multiply it by four bytes.
    ADD  A,A                            ; Reach eight bytes per symbol record.
    LD   B,A                            ; B carries the total required capacity.
    LD   HL,(SY_LBEG)                   ; Load the private-record lower edge.
    LD   DE,(SY_GEND)                   ; Global records end at this edge.
    CALL AT_ROOM                        ; Prove the gap holds every new record.
    JP   C,PR_FSCAP                     ; Translate insufficient symbol capacity.
.PUBLISH: ; Begin symbol insertion and reference-description publication.

; Capacity is now proved. Resolve or insert every key and construct the public
; nine-byte descriptions in source operand order.

    XOR  A                              ; Begin publication at reference zero.
    LD   (PR_RIDX),A                    ; Publish the current build-record index.
.PUBLOOP: ; Publish one prepared reference per iteration.
    LD   A,(PR_BRCNT)                   ; Read the number of build records.
    LD   B,A                            ; Preserve it as the loop bound.
    LD   A,(PR_RIDX)                    ; Load the current record index.
    CP   B                              ; Have all references been published?
    JR   Z,.DONE                        ; Commit the final reference count.
    CALL PR_BRADR                       ; Address the current packed key in DE.
    LD   H,D                            ; Move the key pointer into HL.
    LD   L,E                            ; Complete the pointer for SY_REF.
    CALL SY_REF                         ; Find or insert the undefined symbol.
    JP   C,PR_FINT                      ; Any post-preflight failure is internal.
    LD   A,B                            ; SY_REF reports insertion as nonzero B.
    OR   A                              ; Was a new undefined symbol inserted?
    JR   Z,.RECORD                      ; A found record already has an anchor.

; A new undefined record retains the first reference position in its unused
; value word. Mark this pending kind as the diagnostic anchor that can report
; an undefined symbol at finalisation.

    LD   A,(PR_RIDX)                    ; Reload the current build-record index.
    CALL PR_BRADR                       ; Address that record in DE.
    LD   HL,PR_BSOFF                    ; Load its source-offset field position.
    ADD  HL,DE                          ; Address the source offset.
    LD   A,(HL)                         ; Read its low byte.
    LD   (IX+SY_VALLO),A                ; Store diagnostic offset low byte.
    INC  HL                             ; Advance to source-offset high byte.
    LD   A,(HL)                         ; Read that high byte.
    LD   (IX+SY_VALHI),A                ; Complete the anchored source offset.
    LD   A,(PR_RIDX)                    ; Reload the build-record index again.
    CALL PR_BRADR                       ; Address the private build record in DE.
    LD   A,SY_DANCH                     ; Select the diagnostic-anchor flag.
    LD   HL,PR_BKIND                    ; Load the patch-kind field offset.
    ADD  HL,DE                          ; Address the stored patch kind.
    OR   (HL)                           ; Add the anchor flag to the patch kind.
    LD   (HL),A                         ; Publish the anchor on this reference.
.RECORD: ; Copy the symbol pointer and private reference's trailing fields.

; Public record: symbol pointer, addend, operand index, patch kind and anchor,
; encoded byte offset, source part and source offset.

    PUSH IX                             ; Transfer symbol pointer via the stack.
    POP  BC                             ; BC now holds the symbol pointer.
    LD   A,(PR_RIDX)                    ; Select the matching public record.
    CALL PR_PRADR                       ; Return its base address in HL.
    LD   (HL),C                         ; Store symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   (HL),B                         ; Complete the symbol pointer.
    INC  HL                             ; Advance to the public addend field.
    PUSH HL                             ; Preserve the public-copy destination.
    LD   A,(PR_RIDX)                    ; Reload the private record index.
    CALL PR_BRADR                       ; Address the private record in DE.
    LD   HL,PR_BADD                     ; Load its trailing-field offset.
    ADD  HL,DE                          ; Address the copied tail at its addend.
    POP  DE                             ; Restore the public-copy destination.
    LD   BC,7                           ; Seven trailing bytes remain.
    LDIR                                ; Copy addend, patch metadata and source.
    LD   HL,PR_RIDX                     ; Address the publication scan index.
    INC  (HL)                           ; Advance to the next reference.
    JR   .PUBLOOP                       ; Publish every prepared record.
.DONE: ; Publish the count after every public record is complete.

; Publish the count after every record and symbol insertion succeeds.

    LD   A,(PR_BRCNT)                   ; Recover the completed reference count.
    LD   (PR_PRCNT),A                   ; Publish all public records atomically.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The instruction may now commit.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Inspect one build key without mutation. Not-found increments the exact
; missing count. Scope and other failures retain their nested status.

.LOOKUP: ; Count a missing key without changing the symbol arena.
    LD   A,(PR_RIDX)                    ; Select the build record to inspect.
    CALL PR_BRADR                       ; Address its packed key in DE.
    LD   H,D                            ; Move the key pointer into HL.
    LD   L,E                            ; Complete the SY_FIND input pointer.
    CALL SY_FIND                        ; Search without inserting a symbol.
    RET  NC                             ; A found symbol needs no new record.
    CP   SY_SMISS                       ; Is absence the only failure?
    JR   NZ,PR_FSYM                     ; Preserve scope or key diagnostics.
    LD   HL,PR_MISS                     ; Address the missing-symbol count.
    INC  (HL)                           ; Count one required eight-byte record.
    XOR  A                              ; Convert absence to preflight success.
    RET                                 ; Continue without mutating the arena.
PR_FSYM: ; Wrap symbol detail as a parser failure at this reference.
    LD   (PR_SYERR),A                   ; Retain the nested symbol status.
    LD   A,PR_SSYM                      ; Select the parser symbol category.
    JP   PR_FREF                        ; Fail at this build record's source.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,B
; Compare the two six-byte packed keys. Carry clear means identical.

PR_KEYEQ: ; Compare both packed keys to avoid duplicate allocation counts.
    LD   HL,PR_BREFS                    ; Point HL at the first packed symbol key.
    LD   DE,PR_BREFS+PR_BRB             ; Point DE at the second packed key.
    LD   B,6                            ; Compare all six packed-name bytes.
.LOOP: ; Compare one of six packed-key bytes per iteration.
    LD   A,(DE)                         ; Load the next byte from the second key.
    CP   (HL)                           ; Compare it with the matching first byte.
    SCF                                 ; Prepare carry-set inequality result.
    RET  NZ                             ; Return different at the first mismatch.
    INC  DE                             ; Advance the second-key cursor.
    INC  HL                             ; Advance the first-key cursor.
    DJNZ .LOOP                          ; Compare the remaining key bytes.
    OR   A                              ; Equal keys return with carry clear.
    RET                                 ; Report exact key equality.

; Translate symbol-arena capacity failure into the parser's symbol status.

PR_FSCAP: ; Report insufficient space for the complete symbol requirement.
    LD   A,SY_SSCAP                     ; Use the symbol-arena capacity detail.
    JR   PR_FSYM                        ; Return it through the parser category.

; Report an unexpected symbol insertion failure after successful preflight.
; Exact lookup and capacity checks should make this path unreachable.

PR_FINT: ; Report a symbol failure after successful allocation preflight.
    LD   (PR_SYERR),A                   ; Preserve the unexpected symbol status.
    LD   A,PR_SINT                      ; Report a parser internal failure.
    JP   PR_FREF                        ; Anchor it at the current reference.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Return public-reference address A. Two fixed nine-byte slots cover the
; parser reference capacity.

PR_PRADR: ; Address one of the two nine-byte public references.
    LD   HL,PR_PREFS                    ; Start at public record zero.
    OR   A                              ; Is record zero requested?
    RET  Z                              ; Return its address directly.
    LD   DE,PR_PRB                      ; Load one public-record stride.
    ADD  HL,DE                          ; Advance to fixed record one.
    RET                                 ; Return the selected record address.
