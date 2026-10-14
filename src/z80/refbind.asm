;=============================================================================
;  Deferred references and pending publication
;=============================================================================
;
;  PURPOSE
;  -------
;  Convert unresolved operands into symbol-backed reference descriptions
;  and queue pending patches only after output accepts the corresponding
;  instruction bytes.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;+---------------------------------------------------------------------------+
;| refCheck - Preflight pending references before instruction output.        |
;|                                                                           |
;| Entry: Public references from the most recent successful parse.           |
;| Result: Carry clear when all references can be queued.                    |
;| Error: Carry set, A = symbol/pending publication status.                  |
;| Effect: Reads symbol and pending arenas without changing them.            |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| refQueue - Queue references after instruction output succeeds.            |
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
;  refBind locates every patch field and proves symbol-arena capacity before
;  inserting any missing symbol. prCommit copies the private instruction record
;  only after that work succeeds. refCheck proves pending capacity before
;  image emission. refQueue publishes the records after output accepts every
;  byte.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  This module owns the fixed parser workspace between prRamLo and prRamHi. It
;  uses caller-owned symbol and pending arenas. Calls preserve stack balance,
;  may clobber registers named by each routine contract and are not reentrant.
;  Parse failures publish source positions. Publication entries return symbol
;  or pending status directly.
;

refBeg: ; Begin forward-reference code.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Turn private build references into public symbol-reference descriptions. The
; first pass locates the encoded field and final patch kind for each operand.

refBind: ; Locate deferred fields and publish their symbol descriptions.
    XOR  A                              ; Begin with build-reference index zero.
    LD   (prRefIdx),A                   ; Publish the locator scan index.
.findLoop: ; Validate one deferred operand's encoded field per iteration.
    LD   A,(prRawCnt)                   ; Read the private build-record count.
    LD   B,A                            ; Preserve it for the loop bound.
    LD   A,(prRefIdx)                   ; Load the current record index.
    CP   B                              ; Have all build records been located?
    JR   Z,.count                       ; Begin symbol-capacity preflight.
    CALL prRawPtr                       ; Address this build record in DE.
    LD   HL,prBOper                     ; Load its operand-index field offset.
    ADD  HL,DE                          ; Address the field in the build record.
    LD   A,(HL)                         ; Load the referenced operand index.
    LD   IX,prRec                       ; Point IX at the validated instruction.
    CALL fixField                       ; Find its encoded field and patch kind.
    JR   C,.noPatch                     ; Reject an unpatchable operand form.

; Save the locator's patch kind and byte offset while returning to the
; selected thirteen-byte build entry.

    LD   (prTemp),A                     ; Save the locator's patch kind.
    LD   A,B                            ; Move its encoded byte offset to A.
    LD   (prField),A                    ; Save that offset across record lookup.
    LD   A,(prRefIdx)                   ; Reload the build-record index.
    CALL prRawPtr                       ; Address the same record in DE.
    LD   HL,prBKind                     ; Load its expression-transform offset.
    ADD  HL,DE                          ; Address the transform field.
    LD   A,(HL)                         ; Read the unresolved transform.
    CP   exFLow                         ; Does LOW request the field's low byte?
    JR   Z,.lowByte                     ; Replace the ordinary patch kind.
    CP   exFHigh                        ; Does HIGH request the high byte?
    JR   Z,.hiByte                      ; Replace the ordinary patch kind.
    LD   A,(prTemp)                     ; Otherwise retain the locator's kind.
    JR   .setKind                       ; Store the final patch metadata.
.lowByte: ; Select LOW extraction for a compatible encoded field.
    LD   A,fixLow                       ; Select low-byte extraction patch.
    JR   .extract                       ; Check its field compatibility.
.hiByte: ; Select HIGH extraction for a compatible encoded field.
    LD   A,fixHigh                      ; Select high-byte extraction patch.
.extract: ; Reject projections on relative or indexed displacements.

; LOW/HIGH cannot transform relative or displacement patches. Relative fields
; subtract an address and both field types require signed-range semantics, not
; simple byte extraction.

    PUSH AF                             ; Preserve the LOW/HIGH patch kind.
    LD   A,(prTemp)                     ; Recover the underlying field kind.
    CP   fixRel                         ; Is it a relative branch field?
    JR   Z,.badLoHi                     ; Reject byte extraction from a branch.
    CP   fixDisp                        ; Is it an indexed displacement field?
    JR   Z,.badLoHi                     ; Reject extraction from displacement.
    POP  AF                             ; Restore the compatible LOW/HIGH kind.
.setKind: ; Store final patch kind and encoded byte offset together.

; Store the final kind and encoded-field offset in the build record.

    LD   (HL),A                         ; Store the final patch kind.
    INC  HL                             ; Advance to encoded field offset.
    LD   A,(prField)                    ; Recover the locator's byte offset.
    LD   (HL),A                         ; Store it in the build record.
    LD   HL,prRefIdx                    ; Address the locator scan index.
    INC  (HL)                           ; Advance to the next build record.
    JR   .findLoop                      ; Locate every deferred field first.
.badLoHi: ; Unwind the saved projection before reporting failure.
    POP  AF                             ; Balance the saved LOW/HIGH kind.
.noPatch: ; Report an unsupported deferred patch at its source position.
    LD   A,prNoFix                      ; Select unsupported-patch status.
    JP   prAtRef                        ; Fail at this reference position.
.count: ; Count distinct missing symbols before any allocation.

; Count exact missing symbol records before inserting any. When both
; references share one key, only the first consumes capacity.

    XOR  A                              ; Clear allocation flags.
    LD   (prMissed),A                   ; No missing symbol records counted yet.
    LD   (prSame),A                     ; Assume two keys differ.
    LD   A,(prRawCnt)                   ; Read the build-reference count.
    OR   A                              ; Are there any deferred references?
    RET  Z                              ; Return success when there are none.
    CP   2                              ; Are both fixed record slots occupied?
    JR   NZ,.first                      ; A single record cannot share a key.
    CALL refKeyEq                       ; Compare both packed keys exactly.

; Carry clear means equal keys. Convert that result to one in prSame.

    SBC  A,A                            ; Equal/carry-clear becomes zero.
    INC  A                              ; Map equal to one, different to zero.
    LD   (prSame),A                     ; Record the shared-symbol flag.
.first: ; Inspect the first key and retain its diagnostic index.
    XOR  A                              ; Select build-reference record zero.
    LD   (prRefIdx),A                   ; Publish it for lookup diagnostics.
    CALL .lookup                        ; Count its symbol only if missing.
    RET  C                              ; Preserve a scope or symbol failure.
    LD   A,(prRawCnt)                   ; Recover the build-reference count.
    CP   2                              ; Does a second reference exist?
    JR   NZ,.capacity                   ; One lookup completed the preflight.
    LD   A,(prSame)                     ; Do both references use the same symbol?
    OR   A                              ; One means the first lookup covers both.
    JR   NZ,.capacity                   ; Avoid double-counting a shared symbol.
    LD   A,1                            ; Select build-reference record one.
    LD   (prRefIdx),A                   ; Publish it for lookup diagnostics.
    CALL .lookup                        ; Count its distinct symbol if missing.
    RET  C                              ; Preserve a scope or symbol failure.
.capacity: ; Prove the exact symbol-record requirement fits the arena.
    LD   A,(prMissed)                   ; Load the exact missing-symbol count.
    OR   A                              ; Is symbol allocation unnecessary?
    JR   Z,.publish                     ; Skip the arena check when all exist.

; Each missing symbol needs one eight-byte record. Check the complete
; requirement against the gap between globals and private symbols.

    ADD  A,A                            ; Multiply record count by two bytes.
    ADD  A,A                            ; Multiply it by four bytes.
    ADD  A,A                            ; Reach eight bytes per symbol record.
    LD   B,A                            ; B carries the total required capacity.
    LD   HL,(syFreeHi)                  ; Load the private-record lower edge.
    LD   DE,(syFreeLo)                  ; Global records end at this edge.
    CALL syRoom                         ; Prove the gap holds every new record.
    JP   C,refShort                     ; Translate insufficient symbol capacity.
.publish: ; Begin symbol insertion and reference-description publication.

; Capacity is now proved. Resolve or insert every key and construct the public
; nine-byte descriptions in source operand order.

    XOR  A                              ; Begin publication at reference zero.
    LD   (prRefIdx),A                   ; Publish the current build-record index.
.pubLoop: ; Publish one prepared reference per iteration.
    LD   A,(prRawCnt)                   ; Read the number of build records.
    LD   B,A                            ; Preserve it as the loop bound.
    LD   A,(prRefIdx)                   ; Load the current record index.
    CP   B                              ; Have all references been published?
    JR   Z,.done                        ; Commit the final reference count.
    CALL prRawPtr                       ; Address the current packed key in DE.
    LD   H,D                            ; Move the key pointer into HL.
    LD   L,E                            ; Complete the pointer for syRef.
    CALL syRef                          ; Find or insert the undefined symbol.
    JP   C,refFatal                     ; Any post-preflight failure is internal.
    LD   A,B                            ; syRef reports insertion as nonzero B.
    OR   A                              ; Was a new undefined symbol inserted?
    JR   Z,.record                      ; A found record already has an anchor.

; A new undefined record retains the first reference position in its unused
; value word. Mark this pending kind as the diagnostic anchor that can report
; an undefined symbol at finalisation.

    LD   A,(prRefIdx)                   ; Reload the current build-record index.
    CALL prRawPtr                       ; Address that record in DE.
    LD   HL,prBSrc                      ; Load its source-offset field position.
    ADD  HL,DE                          ; Address the source offset.
    LD   A,(HL)                         ; Read its low byte.
    LD   (IX+syValLo),A                 ; Store diagnostic offset low byte.
    INC  HL                             ; Advance to source-offset high byte.
    LD   A,(HL)                         ; Read that high byte.
    LD   (IX+syValHi),A                 ; Complete the anchored source offset.
    LD   A,(prRefIdx)                   ; Reload the build-record index again.
    CALL prRawPtr                       ; Address the private build record in DE.
    LD   A,syAnchor                     ; Select the diagnostic-anchor flag.
    LD   HL,prBKind                     ; Load the patch-kind field offset.
    ADD  HL,DE                          ; Address the stored patch kind.
    OR   (HL)                           ; Add the anchor flag to the patch kind.
    LD   (HL),A                         ; Publish the anchor on this reference.
.record: ; Copy the symbol pointer and private reference's trailing fields.

; Public record: symbol pointer, addend, operand index, patch kind and anchor,
; encoded byte offset, source part and source offset.

    PUSH IX                             ; Transfer symbol pointer via the stack.
    POP  BC                             ; BC now holds the symbol pointer.
    LD   A,(prRefIdx)                   ; Select the matching public record.
    CALL refAddr                        ; Return its base address in HL.
    LD   (HL),C                         ; Store symbol pointer low byte.
    INC  HL                             ; Advance to pointer high byte.
    LD   (HL),B                         ; Complete the symbol pointer.
    INC  HL                             ; Advance to the public addend field.
    PUSH HL                             ; Preserve the public-copy destination.
    LD   A,(prRefIdx)                   ; Reload the private record index.
    CALL prRawPtr                       ; Address the private record in DE.
    LD   HL,prBAdd                      ; Load its trailing-field offset.
    ADD  HL,DE                          ; Address the copied tail at its addend.
    POP  DE                             ; Restore the public-copy destination.
    LD   BC,7                           ; Seven trailing bytes remain.
    LDIR                                ; Copy addend, patch metadata and source.
    LD   HL,prRefIdx                    ; Address the publication scan index.
    INC  (HL)                           ; Advance to the next reference.
    JR   .pubLoop                       ; Publish every prepared record.
.done: ; Publish the count after every public record is complete.

; Publish the count after every record and symbol insertion succeeds.

    LD   A,(prRawCnt)                   ; Recover the completed reference count.
    LD   (prPubCnt),A                   ; Publish all public records atomically.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The instruction may now commit.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Inspect one build key without mutation. Not-found increments the exact
; missing count. Scope and other failures retain their nested status.

.lookup: ; Count a missing key without changing the symbol arena.
    LD   A,(prRefIdx)                   ; Select the build record to inspect.
    CALL prRawPtr                       ; Address its packed key in DE.
    LD   H,D                            ; Move the key pointer into HL.
    LD   L,E                            ; Complete the syFind input pointer.
    CALL syFind                         ; Search without inserting a symbol.
    RET  NC                             ; A found symbol needs no new record.
    CP   syMiss                         ; Is absence the only failure?
    JR   NZ,refWrap                     ; Preserve scope or key diagnostics.
    LD   HL,prMissed                    ; Address the missing-symbol count.
    INC  (HL)                           ; Count one required eight-byte record.
    XOR  A                              ; Convert absence to preflight success.
    RET                                 ; Continue without mutating the arena.
refWrap: ; Wrap symbol detail as a parser failure at this reference.
    LD   (prSymDet),A                   ; Retain the nested symbol status.
    LD   A,prSymErr                     ; Select the parser symbol category.
    JP   prAtRef                        ; Fail at this build record's source.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,B
; Compare the two six-byte packed keys. Carry clear means identical.

refKeyEq: ; Compare both packed keys to avoid duplicate allocation counts.
    LD   HL,prRawRef                    ; Point HL at the first packed symbol key.
    LD   DE,prRawRef+prRawLen           ; Point DE at the second packed key.
    LD   B,6                            ; Compare all six packed-name bytes.
.loop: ; Compare one of six packed-key bytes per iteration.
    LD   A,(DE)                         ; Load the next byte from the second key.
    CP   (HL)                           ; Compare it with the matching first byte.
    SCF                                 ; Prepare carry-set inequality result.
    RET  NZ                             ; Return different at the first mismatch.
    INC  DE                             ; Advance the second-key cursor.
    INC  HL                             ; Advance the first-key cursor.
    DJNZ .loop                          ; Compare the remaining key bytes.
    OR   A                              ; Equal keys return with carry clear.
    RET                                 ; Report exact key equality.

; Translate symbol-arena capacity failure into the parser's symbol status.

refShort: ; Report insufficient space for the complete symbol requirement.
    LD   A,sySymCap                     ; Use the symbol-arena capacity detail.
    JR   refWrap                        ; Return it through the parser category.

; Report an unexpected symbol insertion failure after successful preflight.
; Exact lookup and capacity checks should make this path unreachable.

refFatal: ; Report a symbol failure after successful allocation preflight.
    LD   (prSymDet),A                   ; Preserve the unexpected symbol status.
    LD   A,prIntErr                     ; Report a parser internal failure.
    JP   prAtRef                        ; Anchor it at the current reference.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Return public-reference address A. Two fixed nine-byte slots cover the
; parser reference capacity.

refAddr: ; Address one of the two nine-byte public references.
    LD   HL,prPubRef                    ; Start at public record zero.
    OR   A                              ; Is record zero requested?
    RET  Z                              ; Return its address directly.
    LD   DE,prPubLen                    ; Load one public-record stride.
    ADD  HL,DE                          ; Advance to fixed record one.
    RET                                 ; Return the selected record address.
