;==========================================================================
;  Multipart assembly driver
;==========================================================================
;
;  PURPOSE
;  -------
;  Own one complete assembly. The driver validates the caller's
;  descriptor, resets the resident subsystems, opens an output generation,
;  assembles each ordered source part, performs the final symbol checks and
;  commits the generation.
;
;  The driver does not read files. Each part record supplies an ordinal and a
;  half-open source range. tkReset passes it to the tokenizer, whose
;  byte service may be backed by memory, an emulator or a native host.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
;  drAsm assembles one ordered multipart source stream.
;    Entry: IX points to the build descriptor below.
;    Success: carry clear, A=0, generation committed.
;    Failure: carry set, A=driver status. drDetail holds the subsystem or
;             configuration detail. stAtPart/stAtOff locate source errors.
;             drMsg holds the message number from src/host/diagnostics.mjs,
;             with its arguments in drSym, drVal and drAtPart/drAtOff.
;    State: resident assembler state is reset. A successful BEGIN ends in
;           a successful COMMIT or one ABORT. Failed COMMIT also needs ABORT.
;
;  BUILD DESCRIPTOR
;  ----------------
;
;  +0   byte   number of source parts. zero is invalid
;  +1   word   address of the first five-byte part record
;  +3   word   beginning of caller-owned symbol arena
;  +5   word   end of symbol arena, exclusive
;  +7   word   beginning of caller-owned pending-reference arena
;  +9   word   end of pending arena, exclusive
;  +11  word   target origin
;  +13  word   target extent in bytes
;
;  Each part record is: ordinal byte, source-begin word, source-end word.
;  Ordinals must be the dense sequence 0, 1, ... count-1. Source ranges are
;  half-open, so an empty part has begin = end.
;
;  FAILURE OWNERSHIP
;  -----------------
;
;  Descriptor and resident-reset failures happen before BEGIN and therefore do
;  not call ABORT. After BEGIN succeeds, each failure calls ABORT once
;  and preserves its original status. COMMIT failure also aborts the
;  open generation.

drBeg: ; Beginning of driver code and immutable constants.

; Public assembly statuses returned in A.

drOk        EQU     0                   ; Assembly committed successfully.
drBadCfg    EQU     1                   ; The build descriptor is invalid.
drBadSrc    EQU     2                   ; A source statement was rejected.
drUndef     EQU     3                   ; A referenced symbol remains undefined.
drBadOut    EQU     4                   ; The output service rejected an operation.
drIntErr    EQU     5                   ; A resident assembler invariant failed.

; Configuration detail values stored in drDetail.

drCfgCnt    EQU     1                   ; No source parts were supplied.
drCfgTab    EQU     2                   ; The part-record table wraps address space.
drCfgIdx    EQU     3                   ; A part record has the wrong ordinal.
drCfgSrc    EQU     4                   ; A source range wraps address space.
drCfgSym    EQU     5                   ; The symbol arena wraps address space.
drCfgRef    EQU     6                   ; The pending arena wraps address space.
drCfgOut    EQU     7                   ; The target range exceeds address space.

; The ordinal is one byte, so a build can contain at most 255 parts.

drMaxCnt    EQU     255                 ; Maximum count representable by one byte.

; Message numbers from src/host/diagnostics.mjs. The five subsystem blocks
; start at these bases. a test checks them against the shared message list.

drMsgInt    EQU     0                   ; Internal error.
drMsgNil    EQU     1                   ; Undefined symbol.
drMsgRej    EQU     2                   ; The output was rejected.
drMsgCfg    EQU     3                   ; Invalid build description.
drMsgJmp    EQU     10                  ; Forward relative jump out of range.
drMsgBig    EQU     11                  ; Forward reference value out of range.
drTokMsg    EQU     13                  ; First tokenizer message.
drExMsg     EQU     25                  ; First expression message.
drSymMsg    EQU     36                  ; First symbol message.
drInsMsg    EQU     46                  ; First parser message.
drOutMsg    EQU     64                  ; First output message.

; Part-record size and field offsets.

drRecLen    EQU     5                   ; Bytes in one source-part record.
drRecIdx    EQU     0                   ; Part ordinal field.
drRecBeg    EQU     1                   ; Source-range beginning field.
drRecEnd    EQU     3                   ; Source-range exclusive-end field.

; Build-descriptor field offsets.

drCount     EQU     0                   ; Source-part count.
drParts     EQU     1                   ; Source-part table address.
drSymBeg    EQU     3                   ; Symbol-arena beginning.
drSymEnd    EQU     5                   ; Symbol-arena exclusive end.
drRefBeg    EQU     7                   ; Pending-arena beginning.
drRefEnd    EQU     9                   ; Pending-arena exclusive end.
drOutBeg    EQU     11                  ; Target origin.
drOutCap    EQU     13                  ; Target capacity in bytes.
drDscLen    EQU     15                  ; Complete descriptor size.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Keep the descriptor address in resident workspace. Later subsystem calls are
; free to use IX, so the entry register cannot remain its owner.

drAsm: ; Assemble and prepare a diagnostic on failure.
    CALL drRun                          ; Assemble, leaving any failure status in A.
    RET  NC                             ; A successful build needs no diagnostic.
    PUSH AF                             ; Keep the public status and carry.
    CALL drDiag                         ; Reduce the nested statuses to one message.
    POP  AF                             ; Return the original status with carry set.
    RET                                 ; drMsg now describes the failure.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Perform the assembly described by the build descriptor at IX.

drRun: ; Validate, reset and assemble one multipart request.
    PUSH IX                             ; Transfer descriptor pointer via stack.
    POP  HL                             ; HL now owns the address supplied in IX.
    LD   (drDesc),HL                    ; Retain it while subsystem calls reuse IX.

; Clear the public detail fields before any operation can fail. drAbsent is set
; only when finalisation identifies a particular unresolved symbol.

    XOR  A                              ; Produce zero once for all public detail state.
    LD   (drDetail),A                   ; Clear the prior subsystem/configuration detail.
    LD   (drAbsent),A                   ; Clear the undefined-symbol pointer low byte.
    LD   (drAbsent+1),A                 ; Clear its high byte as well.
    LD   (drMsg),A                      ; Start with no message.
    LD   HL,0                           ; Form a zero word for the diagnostic arguments.
    LD   (drSym),HL                     ; No symbol argument yet.
    LD   (drVal),HL                     ; No value argument yet.
    DEC  A                              ; Form $FF, which marks no related location.
    LD   (drAtPart),A                   ; Clear the related location.
    INC  A                              ; Restore zero for the source location below.

; Initialise source location to part zero, offset zero. Config errors
; therefore have a deterministic location even though no source has been read.

    LD   HL,stAtPart                    ; Address the contiguous part-and-offset location.
    LD   (HL),A                         ; Default diagnostics to source part zero.
    INC  HL                             ; Advance to the offset low byte.
    LD   (HL),A                         ; Default the source offset low byte to zero.
    INC  HL                             ; Advance to the offset high byte.
    LD   (HL),A                         ; Complete the zero source offset.

; Reject invalid descriptors before resetting subsystems or opening output.

    CALL drDescOk                       ; Validate every descriptor field and part record.
    RET  C                              ; Configuration failure occurs before BEGIN.

; Reset the symbol table over the caller's half-open symbol arena.

    LD   IX,(drDesc)                    ; Reload the immutable build descriptor.
    LD   C,drSymBeg                     ; Select its symbol begin/end word pair.
    CALL drRange                        ; Return symbol begin in HL and end in DE.
    CALL syReset                        ; Reset symbols in caller arena.
    JP   C,.rstFail                     ; Post-validation rejection is internal.

; Reset the pending-reference table over its independent caller-owned arena.

    LD   IX,(drDesc)                    ; Reload descriptor after symbol reset.
    LD   C,drRefBeg                     ; Select its pending begin/end word pair.
    CALL drRange                        ; Return pending begin in HL and end in DE.
    CALL syNoRefs                       ; Reset the pending arena's live-record cursor.
    JP   C,.rstFail                     ; Reject inconsistent resident state before BEGIN.

; Give the output layer the target origin in HL and target extent in DE.

    LD   IX,(drDesc)                    ; Reload the descriptor for target configuration.
    LD   C,drOutBeg                     ; Select target origin and byte capacity.
    CALL drRange                        ; Return origin in HL and capacity in DE.
    CALL outReset                       ; Reset output cursor and remaining capacity.
    JP   C,.rstFail                     ; A validated target must initialise successfully.

; All resident state is now valid. BEGIN transfers generation ownership to the
; host sink. Failure here needs no ABORT because no generation was opened.

    LD   IX,(drDesc)                    ; BEGIN receives the original descriptor pointer.
    CALL hsBegin                        ; Ask the platform sink to open a generation.
    JP   C,.begFail                     ; No generation exists when BEGIN itself fails.

; Set up the multipart loop state from the descriptor. drLeft counts down,
; drDueIdx counts up and must match every record's stored ordinal.

    LD   IX,(drDesc)                    ; Recover the validated multipart description.
    LD   A,(IX+drCount)                 ; Read the number of records still to assemble.
    LD   (drLeft),A                     ; Seed the descending remaining-part counter.
    LD   L,(IX+drParts)                 ; Read the part-table address low byte.
    LD   H,(IX+drParts+1)               ; Complete the first-record pointer.
    LD   (drCurRec),HL                  ; Publish the current part-record cursor.
    XOR  A                              ; The first dense ordinal is zero.
    LD   (drDueIdx),A                   ; Publish the ordinal passed to the tokenizer.
.partLoop: ; Decode and assemble the next ordered source part.

; A zero remaining count means every declared part was assembled exactly once.

    LD   A,(drLeft)                     ; Read the number of unassembled records.
    OR   A                              ; Test the loop terminator without changing A.
    JR   Z,.finish                      ; Finalise after consuming every declared part.

; Decode the next five-byte part record. The cursor advances to the following
; record while HL receives source begin and DE retains source end.

    LD   HL,(drCurRec)                  ; Address the current five-byte part record.
    INC  HL                             ; Skip its already-validated ordinal.
    LD   E,(HL)                         ; Read source-begin low byte.
    INC  HL                             ; Advance to source-begin high byte.
    LD   D,(HL)                         ; Complete source begin in DE.
    INC  HL                             ; Advance to source-end low byte.
    PUSH DE                             ; Save source begin while DE receives source end.
    LD   E,(HL)                         ; Read source-end low byte.
    INC  HL                             ; Advance to source-end high byte.
    LD   D,(HL)                         ; Complete source end in DE.
    INC  HL                             ; Advance to the following part record.
    LD   (drCurRec),HL                  ; Retain that next-record cursor.
    POP  HL                             ; Restore source begin in tkReset's HL input.

; Reset the tokenizer to this part's ordinal and half-open source range.

    LD   A,(drDueIdx)                   ; Supply the dense source-part ordinal.
    CALL tkReset                        ; Bind tokenizer to A:HL..DE for this part.
    JR   C,.tokFail                     ; Tokenizer setup failure is an internal fault.

; Assemble statements until the tokenizer reports end of this part.

    CALL drDoPart                       ; Assemble statements in this part.
    JR   C,.srcFail                     ; Preserve its source-facing failure detail.

; Advance both sides of the loop invariant: next expected ordinal, one fewer
; record remaining. Validation proved the record cursor stays valid.

    LD   HL,drDueIdx                    ; Address the expected source ordinal.
    INC  (HL)                           ; Select the next dense ordinal.
    LD   HL,drLeft                      ; Address the remaining-record counter.
    DEC  (HL)                           ; Account for the completed part.
    JR   .partLoop                      ; Decode the next record or finalise.
.finish: ; Resolve final symbol state before COMMIT.

; Validate the last private scope without evicting it, then prove that no
; pending or undefined symbols remain before exposing the generation.

    CALL drFinish                       ; Validate pending and symbol state.
    JR   C,.finFail                     ; Classify undefined versus internal failure.

; COMMIT receives final cursor, remaining capacity, explicit high water and
; endpoint bits. Hosts no longer reconstruct geometry from output callbacks.

    LD   IX,(drDesc)                    ; COMMIT receives the original build descriptor.
    LD   HL,(outAddr)                   ; Supply the final target cursor.
    LD   DE,(outLeft)                   ; Supply the target capacity left unused.
    LD   BC,(outHigh)                   ; Supply the low word of the high-water endpoint.
    LD   A,(outFlags)                   ; Read cursor/high-water/target endpoint state.
    AND  outAtTop+outHiTop              ; Publish only the two COMMIT endpoint bits.
    CALL hsCommit                       ; Atomically publish the completed generation.
    JR   C,.cmtFail                     ; Abort if the sink cannot commit it.

; Carry clear is the sole success indication at the public boundary.

    XOR  A                              ; Return drOk and clear carry together.
    RET                                 ; The generation is now externally visible.
.srcFail: ; Translate a failed source statement.

; drDoPart returns the source-facing statement detail in A.

    LD   (drDetail),A                   ; Retain the statement-layer error detail.
    LD   A,drBadSrc                     ; Classify it as a public source failure.
    JR   .abort                         ; Discard the open output generation.
.finFail: ; Classify undefined-symbol or invariant failure.

; Finalisation distinguishes an ordinary undefined symbol from a damaged
; internal record. Its detailed status remains available in drDetail.

    LD   (drDetail),A                   ; Retain finalisation's detailed status.
    CP   stUndef                        ; Is this an undefined symbol?
    LD   A,drUndef                      ; Prepare the public undefined-symbol category.
    JR   Z,.abort                       ; Report it after discarding the generation.
    LD   A,drIntErr                     ; Other finalisation failures violate invariants.
    JR   .abort                         ; Abort and return the internal category.
.tokFail: ; Report impossible tokenizer-reset failure.

; tkReset can fail only if resident state or its source contract is broken.

    LD   (drDetail),A                   ; Preserve the tokenizer-reset detail.
    LD   A,drIntErr                     ; Reset rejection after validation is internal.
    JR   .abort                         ; Close the generation before returning.
.cmtFail: ; Retain a failed COMMIT status.

; A failed commit is still an output failure, and the generation remains open
; until ABORT gives the sink a chance to discard temporary state.

    LD   (drDetail),A                   ; Preserve the sink's COMMIT status.
    LD   A,drBadOut                     ; Expose it as a public output failure.
.abort: ; Abort once while preserving the original failure.

; hsAbort may change A and flags. Preserve the original public status across
; the cleanup call, then force the error carry expected by drAsm callers.

    PUSH AF                             ; Save the original status across cleanup.
    CALL hsAbort                        ; Ask the sink to discard the open generation.
    POP  AF                             ; Restore the public status and prior flags.
    SCF                                 ; Force the driver's failure indication.
    RET                                 ; Return after exactly one abort.
.begFail: ; Return a BEGIN failure without aborting.

; BEGIN itself failed, so no generation exists to abort.

    LD   (drDetail),A                   ; Retain the sink's BEGIN status.
    LD   A,drBadOut                     ; Classify the failure at the public boundary.
    SCF                                 ; Mark assembly as failed.
    RET                                 ; Return without calling ABORT.
.rstFail: ; Return a reset failure before BEGIN.

; Resident reset failure is classified as internal and also precedes BEGIN.

    LD   (drDetail),A                   ; Retain the resident subsystem's status.
    LD   A,drIntErr                     ; Classify impossible reset rejection internally.
    SCF                                 ; Mark assembly as failed.
    RET                                 ; No generation exists to abort yet.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,SIGN,PARITY,HALFCARRY,HL,ZERO,IY
; Reload the immutable descriptor and require at least one part. A byte count
; naturally limits accepted builds to 255 records.

drDescOk: ; Validate descriptor structure before opening output.
    LD   IX,(drDesc)                    ; Recover the caller's immutable descriptor.
    LD   A,(IX+drCount)                 ; Read its one-byte source-part count.
    OR   A                              ; Zero parts cannot form an assembly unit.
    JP   Z,drErrCnt                     ; Report the dedicated part-count detail.

; Seed the validation loop with the declared count and first-record address.

    LD   (drLeft),A                     ; Seed the number of records left to validate.
    LD   L,(IX+drParts)                 ; Read the part-table pointer low byte.
    LD   H,(IX+drParts+1)               ; Complete the first-record address.
    LD   (drCurRec),HL                  ; Publish the validation cursor.

; Prove base + count*5 fits in 16 bits. The loop may then walk
; exactly count records without its cursor wrapping through address zero.

    LD   C,A                            ; BC receives the unsigned part count.
    LD   B,0                            ; Widen the count to sixteen bits.
    PUSH HL                             ; Preserve the part-table base address.
    LD   H,B                            ; Begin HL = count without another memory read.
    LD   L,C                            ; Complete the sixteen-bit count in HL.
    ADD  HL,HL                          ; Multiply count by two.
    ADD  HL,HL                          ; Multiply count by four.
    ADD  HL,BC                          ; Add count once more: HL = count * 5.
    POP  DE                             ; Restore the part-table base in DE.
    ADD  HL,DE                          ; Compute the exclusive end of all part records.
    JR   C,drErrTab                     ; Carry means table arithmetic wrapped past $FFFF.

; Every record must carry the ordinal implied by its position in the table.

    XOR  A                              ; The first record must carry ordinal zero.
    LD   (drDueIdx),A                   ; Publish the expected ordinal.
.partLoop: ; Validate dense ordinals and source ranges.
    LD   A,(drLeft)                     ; Read the number of unchecked records.
    OR   A                              ; Test whether table validation is complete.
    JR   Z,.arenas                      ; Continue with the caller-owned arenas.
    LD   HL,(drCurRec)                  ; Address the next five-byte part record.
    LD   A,(drDueIdx)                   ; Recover the ordinal implied by table position.
    CP   (HL)                           ; Compare it with the record's stored ordinal.
    JR   NZ,drErrIdx                    ; Reject missing, repeated or reordered ordinals.

; Decode source begin into DE and source end into BC, then publish the next
; record cursor. No source byte is read during descriptor validation.

    INC  HL                             ; Advance past the ordinal to source begin.
    LD   E,(HL)                         ; Read source-begin low byte.
    INC  HL                             ; Advance to source-begin high byte.
    LD   D,(HL)                         ; Complete source begin in DE.
    INC  HL                             ; Advance to source-end low byte.
    LD   C,(HL)                         ; Read source-end low byte.
    INC  HL                             ; Advance to source-end high byte.
    LD   B,(HL)                         ; Complete source end in BC.
    INC  HL                             ; Advance to the following part record.
    LD   (drCurRec),HL                  ; Publish the next validation cursor.

; A half-open source range is valid when end - begin does not borrow. Equality
; is permitted and represents an empty source part.

    LD   H,B                            ; Copy source end from BC into HL.
    LD   L,C                            ; Complete the exclusive-end value.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Measure end minus begin.
    JR   C,drErrSrc                     ; Borrow means range wraps backwards.

; Advance the expected ordinal and remaining-record count together.

    LD   HL,drDueIdx                    ; Address the next expected ordinal.
    INC  (HL)                           ; Advance the dense sequence by one.
    LD   HL,drLeft                      ; Address the unchecked-record count.
    DEC  (HL)                           ; Account for the validated record.
    JR   .partLoop                      ; Validate the next part or leave the loop.
.arenas: ; Validate symbol, pending and target arenas.

; Symbol and pending arenas are each ordinary non-wrapping half-open ranges.
; Empty arenas are valid. Capacity checks later reject insertions.

    LD   IX,(drDesc)                    ; Reload the build descriptor.
    LD   C,drSymBeg                     ; Select symbol-arena begin and end.
    CALL drRange                        ; Decode the pair into HL and DE.
    CALL drSpanOk                       ; Require a non-wrapping half-open range.
    JR   C,drErrSym                     ; Report an invalid symbol arena.
    LD   IX,(drDesc)                    ; Reload the descriptor after helper clobbers.
    LD   C,drRefBeg                     ; Select pending-arena begin and end.
    CALL drRange                        ; Decode the pair into HL and DE.
    CALL drSpanOk                       ; Require another non-wrapping range.
    JR   C,drErrRef                     ; Report an invalid pending arena.

; The target descriptor uses origin plus a capacity, not begin and end. Accept
; a sum of exactly $10000, represented by carry with a wrapped result of zero,
; but reject every mathematical sum greater than $10000.

    LD   IX,(drDesc)                    ; Reload the descriptor for target validation.
    LD   C,drOutBeg                     ; Select target origin and capacity.
    CALL drRange                        ; Return origin in HL and capacity in DE.
    ADD  HL,DE                          ; Compute the wrapped sixteen-bit exclusive end.
    JR   NC,.rangeOk                    ; No carry is an ordinary in-range sum.
    LD   A,H                            ; Carry is legal only at exact wrap.
    OR   L                              ; Combine both result bytes for that exact test.
    JR   NZ,drErrOut                    ; Nonzero plus carry exceeds mathematical $10000.
.rangeOk: ; Accept the fully checked descriptor.
    XOR  A                              ; Return configuration success with carry clear.
    RET                                 ; All structural checks have passed.

;@ROUTINE IN IX,C OUT HL,DE CLOBBERS A,B,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Address field C in the descriptor, read two adjacent little-endian words and
; return the first in HL and second in DE. Shared decoding makes
; all three range users agree on the descriptor layout.

drRange: ; Decode two adjacent descriptor words.
    PUSH IX                             ; Copy the descriptor base without changing IX.
    POP  HL                             ; HL now addresses descriptor offset zero.
    LD   B,0                            ; Widen the byte field offset in C.
    ADD  HL,BC                          ; Address the first selected little-endian word.
    LD   E,(HL)                         ; Read its low byte into DE.
    INC  HL                             ; Advance to the first word's high byte.
    LD   D,(HL)                         ; Complete the first word in DE.
    INC  HL                             ; Advance to the adjacent second word.
    LD   A,(HL)                         ; Hold the second word's low byte temporarily.
    INC  HL                             ; Advance to its high byte.
    LD   H,(HL)                         ; Install the second word's high byte in HL.
    LD   L,A                            ; Complete the second word in HL.
    EX   DE,HL                          ; Return first word in HL and second in DE.
    RET                                 ; The descriptor itself remains unchanged.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL,DE
; Compute end - begin. No borrow means the half-open range does not wrap.

drSpanOk: ; Check an ordinary half-open address range.
    EX   DE,HL                          ; Put exclusive end in HL and begin in DE.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Compute end minus begin.
    RET  NC                             ; No borrow accepts empty or live ranges.
    SCF                                 ; Restore the helper's explicit failure contract.
    RET                                 ; Report a range that wraps backwards.
drErrCnt: ; Report an empty source-part list.

; The following stubs translate one failed structural check into a stable
; configuration-detail value, then share the public failure return.

    LD   A,drCfgCnt                     ; Identify an empty source-part list.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrTab: ; Report a wrapped part-record table.
    LD   A,drCfgTab                     ; Identify wrapped part-table arithmetic.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrIdx: ; Report a non-dense source ordinal.
    LD   A,drCfgIdx                     ; Identify a non-dense part ordinal.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrSrc: ; Report a backwards source range.
    LD   A,drCfgSrc                     ; Identify a backwards source range.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrSym: ; Report a backwards symbol arena.
    LD   A,drCfgSym                     ; Identify a backwards symbol arena.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrRef: ; Report a backwards pending arena.
    LD   A,drCfgRef                     ; Identify a backwards pending arena.
    JR   drErrCfg                       ; Publish the common configuration failure.
drErrOut: ; Report target geometry beyond $10000.
    LD   A,drCfgOut                     ; Identify a target beyond mathematical $10000.
drErrCfg: ; Publish descriptor failure and detail.
    LD   (drDetail),A                   ; Retain the precise descriptor check that failed.
    LD   A,drBadCfg                     ; Return the broad public configuration category.
    SCF                                 ; Mark descriptor validation as failed.
    RET                                 ; No resident subsystem or sink was touched.
