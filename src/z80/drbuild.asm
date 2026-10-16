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
;  The driver does not read files. It asks the host's tkOpen service for each
;  source part as the previous one ends, and tkReset binds the tokenizer to it.
;  A part ends where the host's tkRead service reports that no byte remains, so
;  no part's length, order or count is known before assembly. The source is
;  read once, as a stream.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
;  drAsm assembles one ordered multipart source stream.
;    Entry: IX points to the build descriptor below.
;    Success: carry clear, A=0, generation committed.
;    Failure: carry set, A=driver status. drDetail holds the subsystem,
;             configuration or host source-service detail. stAtPart, stAtOff
;             and stAtLine locate source errors.
;             drMsg holds the message number from src/host/diagnostics.mjs,
;             with its arguments in drSym, drVal and drAtPart/drAtOff/drAtLine.
;    State: resident assembler state is reset. A successful BEGIN ends in
;           a successful COMMIT or one ABORT. Failed COMMIT also needs ABORT.
;
;  BUILD DESCRIPTOR
;  ----------------
;
;  +0   word   beginning of caller-owned symbol arena
;  +2   word   end of symbol arena, exclusive
;  +4   word   beginning of caller-owned pending-reference arena
;  +6   word   end of pending arena, exclusive
;  +8   word   target origin
;  +10  word   target extent in bytes
;
;  SOURCE SERVICES
;  ---------------
;
;  tkOpen returns the next part: A = ordinal, HL = the logical offset where
;  it starts and DE = the line it starts on, with carry clear. A part resumed
;  after an include starts past offset zero and line one. Carry with A=0
;  means no part remains. Carry with A nonzero is a failure: A is its message
;  number and stAtPart, stAtOff and stAtLine its position. The driver returns
;  drBadIn with that number in drDetail and drMsg.
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
drBadIn     EQU     6                   ; The host's source service failed.

; Configuration detail values stored in drDetail.

drCfgSym    EQU     5                   ; The symbol arena wraps address space.
drCfgRef    EQU     6                   ; The pending arena wraps address space.
drCfgOut    EQU     7                   ; The target range exceeds address space.

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

; Build-descriptor field offsets.

drSymBeg    EQU     0                   ; Symbol-arena beginning.
drSymEnd    EQU     2                   ; Symbol-arena exclusive end.
drRefBeg    EQU     4                   ; Pending-arena beginning.
drRefEnd    EQU     6                   ; Pending-arena exclusive end.
drOutBeg    EQU     8                   ; Target origin.
drOutCap    EQU     10                  ; Target capacity in bytes.
drDscLen    EQU     12                  ; Complete descriptor size.

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

; Initialise source location to part zero, offset zero, line one. Config
; errors therefore have a deterministic location even though no source has
; been read.

    LD   (stAtPart),A                   ; Default diagnostics to source part zero.
    LD   L,A                            ; Form zero.
    LD   H,A                            ; Complete it.
    LD   (stAtOff),HL                   ; Default the source offset to zero.
    INC  L                              ; Form one.
    LD   (stAtLine),HL                  ; Default the line to one.

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

.partLoop: ; Assemble the next source part the host supplies.
    CALL tkOpen                         ; Ask the host for the next part.
    JR   C,.noPart                      ; None remains, or the host failed.
    CALL tkReset                        ; Bind the tokenizer to part A from offset HL.

; Assemble statements until the host reports the end of this part.

    CALL drDoPart                       ; Assemble statements in this part.
    JR   C,.srcFail                     ; Preserve its source-facing failure detail.
    JR   .partLoop                      ; Ask for the next part.
.noPart: ; Finish, or report a failed source service.
    OR   A                              ; A=0 means every part has been assembled.
    JR   Z,.finish                      ; Finalise the generation.
    LD   (drDetail),A                   ; Keep the host's status.
    LD   A,drBadIn                      ; Classify it as a source-service failure.
    JR   .abort                         ; Discard the open generation.
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
; Validate the descriptor's arenas and target before opening output.

drDescOk: ; Validate descriptor structure before opening output.

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
drErrSym: ; Report a backwards symbol arena.

; The following stubs translate one failed structural check into a stable
; configuration-detail value, then share the public failure return.

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
