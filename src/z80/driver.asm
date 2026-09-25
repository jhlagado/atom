;==============================================================================
;  Multipart assembly driver
;==============================================================================
;
;  PURPOSE
;  -------
;  Own the lifetime of one complete assembly. The driver validates the caller's
;  descriptor, resets the resident subsystems, opens an output generation,
;  assembles each ordered source part, performs the final symbol checks and
;  commits the generation.
;
;  The driver does not read files. Each part record supplies an ordinal and a
;  half-open source range. TK_RESET presents that range to the tokenizer, whose
;  byte service may be backed by memory, an emulator or a native host.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
;+---------------------------------------------------------------------------+
;| DR_ASM - Assemble one ordered multipart source stream.                    |
;|                                                                           |
;| Entry: IX -> build descriptor described below.                            |
;| Result: Carry clear and A = 0 after a committed generation.               |
;| Error: Carry set and A = DR_S* status. DR_DETAI gives the subsystem or     |
;|        configuration detail. ST_EPART/ST_EOFF identify source failures.   |
;| Side effects: Resets all resident assembler state. A successful BEGIN is  |
;|               followed by exactly one COMMIT or one ABORT.                |
;+---------------------------------------------------------------------------+
;
;  BUILD DESCRIPTOR
;  ----------------
;
;  +0   byte   number of source parts; zero is invalid
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
;  not call ABORT. After BEGIN succeeds, every failure path calls ABORT exactly
;  once and preserves the status that caused it. COMMIT failure also aborts the
;  open generation.

DR_CBEG:
; Public assembly statuses returned in A.
DR_SOK EQU 0               ; Assembly committed successfully.
DR_SCFG EQU 1              ; The build descriptor is invalid.
DR_SSRC EQU 2              ; A source statement was rejected.
DR_SUNDE EQU 3             ; A referenced symbol remains undefined.
DR_SOUT EQU 4              ; The output service rejected an operation.
DR_SINT EQU 5              ; A resident assembler invariant failed.
; Configuration detail values stored in DR_DETAI.
DR_CPCNT EQU 1             ; No source parts were supplied.
DR_CTRAN EQU 2             ; The part-record table wraps address space.
DR_CPORD EQU 3             ; A part record has the wrong ordinal.
DR_CSRAN EQU 4             ; A source range wraps address space.
DR_CSRA1 EQU 5             ; The symbol arena wraps address space.
DR_CPRAN EQU 6             ; The pending arena wraps address space.
DR_CORAN EQU 7             ; The target range exceeds address space.
; The ordinal is one byte, so a build can contain at most 255 parts.
DR_PCAP EQU 255             ; Maximum count representable by one byte.
; Part-record size and field offsets.
DR_PDB EQU 5                ; Bytes in one source-part record.
DR_PORDI EQU 0              ; Part ordinal field.
DR_PBEG EQU 1               ; Source-range beginning field.
DR_PEND EQU 3               ; Source-range exclusive-end field.
; Build-descriptor field offsets.
DR_DPCNT EQU 0              ; Source-part count.
DR_DPART EQU 1              ; Source-part table address.
DR_DSBEG EQU 3              ; Symbol-arena beginning.
DR_DSEND EQU 5              ; Symbol-arena exclusive end.
DR_DPBEG EQU 7              ; Pending-arena beginning.
DR_DPEND EQU 9              ; Pending-arena exclusive end.
DR_DTBEG EQU 11             ; Target origin.
DR_DTB EQU 13               ; Target capacity in bytes.
DR_DESCB EQU 15             ; Complete descriptor size.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
DR_ASM:
; Keep the descriptor address in resident workspace. Later subsystem calls are
; free to use IX, so the entry register cannot remain its owner.
    PUSH IX                 ; Copy the caller's descriptor pointer through stack.
    POP  HL                 ; HL now owns the address supplied in IX.
    LD   (DR_DESC),HL       ; Retain it while subsystem calls reuse IX.
; Clear the public detail fields before any operation can fail. DR_USYM is set
; only when finalisation identifies a particular unresolved symbol.
    XOR  A                  ; Produce zero once for all public detail state.
    LD   (DR_DETAI),A       ; Clear the prior subsystem/configuration detail.
    LD   (DR_USYM),A        ; Clear the undefined-symbol pointer low byte.
    LD   (DR_USYM+1),A      ; Clear its high byte as well.
; Initialise the source location to part zero, offset zero. Configuration errors
; therefore have a deterministic location even though no source has been read.
    LD   HL,ST_EPART        ; Address the contiguous part-and-offset location.
    LD   (HL),A             ; Default diagnostics to source part zero.
    INC  HL                 ; Advance to the offset low byte.
    LD   (HL),A             ; Default the source offset low byte to zero.
    INC  HL                 ; Advance to the offset high byte.
    LD   (HL),A             ; Complete the zero source offset.
; Reject an invalid descriptor before changing any subsystem or opening output.
    CALL DR_VDESC           ; Validate every descriptor field and part record.
    RET  C                  ; Configuration failure occurs before BEGIN.
; Reset the symbol table over the caller's half-open symbol arena.
    LD   IX,(DR_DESC)       ; Reload the immutable build descriptor.
    LD   C,DR_DSBEG         ; Select its symbol begin/end word pair.
    CALL DR_LRANG           ; Return symbol begin in HL and end in DE.
    CALL SY_RESET           ; Attach an empty symbol table to the caller arena.
    JP   C,DR_IFAIL         ; Treat an impossible post-validation rejection internally.
; Reset the pending-reference table over its independent caller-owned arena.
    LD   IX,(DR_DESC)       ; Reload the descriptor after symbol initialization.
    LD   C,DR_DPBEG         ; Select its pending begin/end word pair.
    CALL DR_LRANG           ; Return pending begin in HL and end in DE.
    CALL SY_RESE1           ; Reset the pending arena's live-record cursor.
    JP   C,DR_IFAIL         ; Reject inconsistent resident state before BEGIN.
; Give the output layer the target origin in HL and target extent in DE.
    LD   IX,(DR_DESC)       ; Reload the descriptor for target configuration.
    LD   C,DR_DTBEG         ; Select target origin and byte capacity.
    CALL DR_LRANG           ; Return origin in HL and capacity in DE.
    CALL OU_RESET           ; Reset output cursor and remaining capacity.
    JP   C,DR_IFAIL         ; A validated target must initialize successfully.
; All resident state is now valid. BEGIN transfers generation ownership to the
; host sink. Failure here needs no ABORT because no generation was opened.
    LD   IX,(DR_DESC)       ; BEGIN receives the original descriptor pointer.
    CALL HS_BEG             ; Ask the platform sink to open a generation.
    JP   C,DR_BFAIL         ; No generation exists when BEGIN itself fails.
; Establish the multipart loop state from the descriptor. DR_PREM counts down;
; DR_PINDE counts up and must match every record's stored ordinal.
    LD   IX,(DR_DESC)       ; Recover the validated multipart description.
    LD   A,(IX+DR_DPCNT)    ; Read the number of records still to assemble.
    LD   (DR_PREM),A        ; Seed the descending remaining-part counter.
    LD   L,(IX+DR_DPART)    ; Read the part-table address low byte.
    LD   H,(IX+DR_DPART+1)  ; Complete the first-record pointer.
    LD   (DR_PCURS),HL      ; Publish the current part-record cursor.
    XOR  A                  ; The first dense ordinal is zero.
    LD   (DR_PINDE),A       ; Publish the ordinal passed to the tokenizer.
DR_PLOOP:
; A zero remaining count means every declared part was assembled exactly once.
    LD   A,(DR_PREM)        ; Read the number of unassembled records.
    OR   A                  ; Test the loop terminator without changing A.
    JR   Z,DR_FIN           ; Finalize after consuming every declared part.
; Decode the next five-byte part record. The cursor advances to the following
; record while HL receives source begin and DE retains source end.
    LD   HL,(DR_PCURS)      ; Address the current five-byte part record.
    INC  HL                 ; Skip its already-validated ordinal.
    LD   E,(HL)             ; Read source-begin low byte.
    INC  HL                 ; Advance to source-begin high byte.
    LD   D,(HL)             ; Complete source begin in DE.
    INC  HL                 ; Advance to source-end low byte.
    PUSH DE                 ; Save source begin while DE receives source end.
    LD   E,(HL)             ; Read source-end low byte.
    INC  HL                 ; Advance to source-end high byte.
    LD   D,(HL)             ; Complete source end in DE.
    INC  HL                 ; Advance to the following part record.
    LD   (DR_PCURS),HL      ; Retain that next-record cursor.
    POP  HL                 ; Restore source begin in TK_RESET's HL input.
; Reset the tokenizer to this part's ordinal and half-open source range.
    LD   A,(DR_PINDE)       ; Supply the dense source-part ordinal.
    CALL TK_RESET           ; Bind tokenizer to A:HL..DE for this part.
    JR   C,DR_IABOR         ; Tokenizer setup failure is an internal fault.
; Assemble statements until the tokenizer reports end of this part.
    CALL DR_APART           ; Consume and assemble every statement in the part.
    JR   C,DR_SFAIL         ; Preserve its source-facing failure detail.
; Advance both sides of the loop invariant: next expected ordinal, one fewer
; record remaining. Descriptor validation proved the record cursor stays valid.
    LD   HL,DR_PINDE        ; Address the expected source ordinal.
    INC  (HL)               ; Select the next dense ordinal.
    LD   HL,DR_PREM         ; Address the remaining-record counter.
    DEC  (HL)               ; Account for the completed part.
    JR   DR_PLOOP           ; Decode the next record or finalize.
DR_FIN:
; Validate the last private scope without evicting it, then prove that no
; pending or undefined symbols remain before exposing the generation.
    CALL DR_AFIN            ; Validate pending, private and global symbol state.
    JR   C,DR_FFAIL         ; Classify undefined versus internal failure.
; COMMIT receives the output cursor and remaining capacity, allowing the host to
; derive the final written range without duplicating output-layer arithmetic.
    LD   IX,(DR_DESC)       ; COMMIT receives the original build descriptor.
    LD   HL,(OU_CURSO)      ; Supply the final target cursor.
    LD   DE,(OU_REM)        ; Supply the target capacity left unused.
    CALL HS_CMT             ; Atomically publish the completed generation.
    JR   C,DR_CFAIL         ; Abort if the sink cannot commit it.
; Carry clear is the sole success indication at the public boundary.
    XOR  A                  ; Return DR_SOK and clear carry together.
    RET                     ; The generation is now externally visible.
DR_SFAIL:
; DR_APART returns the source-facing statement detail in A.
    LD   (DR_DETAI),A       ; Retain the statement-layer error detail.
    LD   A,DR_SSRC          ; Classify it as a public source failure.
    JR   DR_ABORT           ; Discard the open output generation.
DR_FFAIL:
; Finalisation distinguishes an ordinary undefined symbol from a damaged
; internal record. Its detailed status remains available in DR_DETAI.
    LD   (DR_DETAI),A       ; Retain finalization's detailed status.
    CP   ST_SUNDE           ; Did validation find an ordinary undefined symbol?
    LD   A,DR_SUNDE         ; Prepare the public undefined-symbol category.
    JR   Z,DR_ABORT         ; Report it after discarding the generation.
    LD   A,DR_SINT          ; Other finalization failures violate invariants.
    JR   DR_ABORT           ; Abort and return the internal category.
DR_IABOR:
; TK_RESET can fail only if resident state or its source contract is broken.
    LD   (DR_DETAI),A       ; Preserve the tokenizer-reset detail.
    LD   A,DR_SINT          ; Reset rejection after validation is internal.
    JR   DR_ABORT           ; Close the generation before returning.
DR_CFAIL:
; A failed commit is still an output failure, and the generation remains open
; until ABORT gives the sink a chance to discard temporary state.
    LD   (DR_DETAI),A       ; Preserve the sink's COMMIT status.
    LD   A,DR_SOUT          ; Expose it as a public output failure.
DR_ABORT:
; HS_ABORT may change A and flags. Preserve the original public status across
; the cleanup call, then force the error carry expected by DR_ASM callers.
    PUSH AF                 ; Save the original status across cleanup.
    CALL HS_ABORT           ; Ask the sink to discard the open generation.
    POP  AF                 ; Restore the public status and prior flags.
    SCF                     ; Force the driver's failure indication.
    RET                     ; Return after exactly one abort.
DR_BFAIL:
; BEGIN itself failed, so no generation exists to abort.
    LD   (DR_DETAI),A       ; Retain the sink's BEGIN status.
    LD   A,DR_SOUT          ; Classify the failure at the public boundary.
    SCF                     ; Mark assembly as failed.
    RET                     ; Return without calling ABORT.
DR_IFAIL:
; Resident reset failure is classified as internal and also precedes BEGIN.
    LD   (DR_DETAI),A       ; Retain the resident subsystem's status.
    LD   A,DR_SINT          ; Classify impossible reset rejection internally.
    SCF                     ; Mark assembly as failed.
    RET                     ; No generation exists to abort yet.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,SIGN,PARITY,HALFCARRY,HL,ZERO,IY
DR_VDESC:
; Reload the immutable descriptor and require at least one part. A byte count
; naturally limits accepted builds to 255 records.
    LD   IX,(DR_DESC)       ; Recover the caller's immutable descriptor.
    LD   A,(IX+DR_DPCNT)    ; Read its one-byte source-part count.
    OR   A                  ; Zero parts cannot form an assembly unit.
    JP   Z,DR_BPCNT         ; Report the dedicated part-count detail.
; Seed the validation loop with the declared count and first-record address.
    LD   (DR_PREM),A        ; Seed the number of records left to validate.
    LD   L,(IX+DR_DPART)    ; Read the part-table pointer low byte.
    LD   H,(IX+DR_DPART+1)  ; Complete the first-record address.
    LD   (DR_PCURS),HL      ; Publish the validation cursor.
; Prove that base + count*5 is representable in 16 bits. The loop may then walk
; exactly count records without its cursor wrapping through address zero.
    LD   C,A                ; BC receives the unsigned part count.
    LD   B,0                ; Widen the count to sixteen bits.
    PUSH HL                 ; Preserve the part-table base address.
    LD   H,B                ; Begin HL = count without another memory read.
    LD   L,C                ; Complete the sixteen-bit count in HL.
    ADD  HL,HL              ; Multiply count by two.
    ADD  HL,HL              ; Multiply count by four.
    ADD  HL,BC              ; Add count once more: HL = count * 5.
    POP  DE                 ; Restore the part-table base in DE.
    ADD  HL,DE              ; Compute the exclusive end of all part records.
    JR   C,DR_BPTAB         ; Carry means table arithmetic wrapped past $FFFF.
; Every record must carry the ordinal implied by its position in the table.
    XOR  A                  ; The first record must carry ordinal zero.
    LD   (DR_PINDE),A       ; Publish the expected ordinal.
DR_VPLOO:
    LD   A,(DR_PREM)        ; Read the number of unchecked records.
    OR   A                  ; Test whether table validation is complete.
    JR   Z,DR_VAREN         ; Continue with the caller-owned arenas.
    LD   HL,(DR_PCURS)      ; Address the next five-byte part record.
    LD   A,(DR_PINDE)       ; Recover the ordinal implied by table position.
    CP   (HL)               ; Compare it with the record's stored ordinal.
    JR   NZ,DR_BPORD        ; Reject missing, repeated or reordered ordinals.
; Decode source begin into DE and source end into BC, then publish the next
; record cursor. No source byte is read during descriptor validation.
    INC  HL                 ; Advance past the ordinal to source begin.
    LD   E,(HL)             ; Read source-begin low byte.
    INC  HL                 ; Advance to source-begin high byte.
    LD   D,(HL)             ; Complete source begin in DE.
    INC  HL                 ; Advance to source-end low byte.
    LD   C,(HL)             ; Read source-end low byte.
    INC  HL                 ; Advance to source-end high byte.
    LD   B,(HL)             ; Complete source end in BC.
    INC  HL                 ; Advance to the following part record.
    LD   (DR_PCURS),HL      ; Publish the next validation cursor.
; A half-open source range is valid when end - begin does not borrow. Equality
; is permitted and represents an empty source part.
    LD   H,B                ; Copy source end from BC into HL.
    LD   L,C                ; Complete the exclusive-end value.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Measure end minus begin.
    JR   C,DR_BSRAN         ; Borrow means the half-open range wraps backwards.
; Advance the expected ordinal and remaining-record count together.
    LD   HL,DR_PINDE        ; Address the next expected ordinal.
    INC  (HL)               ; Advance the dense sequence by one.
    LD   HL,DR_PREM         ; Address the unchecked-record count.
    DEC  (HL)               ; Account for the validated record.
    JR   DR_VPLOO           ; Validate the next part or leave the loop.
DR_VAREN:
; Symbol and pending arenas are each ordinary non-wrapping half-open ranges.
; Empty arenas are structurally valid; later capacity checks reject insertions.
    LD   IX,(DR_DESC)       ; Reload the build descriptor.
    LD   C,DR_DSBEG         ; Select symbol-arena begin and end.
    CALL DR_LRANG           ; Decode the pair into HL and DE.
    CALL DR_VRANG           ; Require a non-wrapping half-open range.
    JR   C,DR_BSRA1         ; Report an invalid symbol arena.
    LD   IX,(DR_DESC)       ; Reload the descriptor after helper clobbers.
    LD   C,DR_DPBEG         ; Select pending-arena begin and end.
    CALL DR_LRANG           ; Decode the pair into HL and DE.
    CALL DR_VRANG           ; Require another non-wrapping range.
    JR   C,DR_BPRAN         ; Report an invalid pending arena.
; The target descriptor uses origin plus a capacity, not begin and end. Accept
; a sum of exactly $10000, represented by carry with a wrapped result of zero,
; but reject every mathematical sum greater than $10000.
    LD   IX,(DR_DESC)       ; Reload the descriptor for target validation.
    LD   C,DR_DTBEG         ; Select target origin and capacity.
    CALL DR_LRANG           ; Return origin in HL and capacity in DE.
    ADD  HL,DE              ; Compute the wrapped sixteen-bit exclusive end.
    JR   NC,.RANGEOK        ; No carry is an ordinary in-range sum.
    LD   A,H                ; Carry is legal only when the wrapped sum is zero.
    OR   L                  ; Combine both result bytes for that exact test.
    JR   NZ,DR_BORAN        ; Nonzero plus carry exceeds mathematical $10000.
.RANGEOK:
    XOR  A                  ; Return configuration success with carry clear.
    RET                     ; All structural checks have passed.

;@ROUTINE IN IX,C OUT HL,DE CLOBBERS A,B,ZERO,SIGN,PARITY,HALFCARRY,CARRY
DR_LRANG:
; Address field C in the descriptor, read two adjacent little-endian words and
; return the first in HL and the second in DE. Keeping this decoding here makes
; all three range users agree on the descriptor layout.
    PUSH IX                 ; Copy the descriptor base without changing IX.
    POP  HL                 ; HL now addresses descriptor offset zero.
    LD   B,0                ; Widen the byte field offset in C.
    ADD  HL,BC              ; Address the first selected little-endian word.
    LD   E,(HL)             ; Read its low byte into DE.
    INC  HL                 ; Advance to the first word's high byte.
    LD   D,(HL)             ; Complete the first word in DE.
    INC  HL                 ; Advance to the adjacent second word.
    LD   A,(HL)             ; Hold the second word's low byte temporarily.
    INC  HL                 ; Advance to its high byte.
    LD   H,(HL)             ; Install the second word's high byte in HL.
    LD   L,A                ; Complete the second word in HL.
    EX   DE,HL              ; Return first word in HL and second in DE.
    RET                     ; The descriptor itself remains unchanged.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL,DE
DR_VRANG:
; Compute end - begin. No borrow means the half-open range does not wrap.
    EX   DE,HL              ; Put exclusive end in HL and begin in DE.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Compute end minus begin.
    RET  NC                 ; No borrow accepts both empty and nonempty ranges.
    SCF                     ; Restore the helper's explicit failure contract.
    RET                     ; Report a range that wraps backwards.
DR_BPCNT:
; The following stubs translate one failed structural check into a stable
; configuration-detail value, then share the public failure return.
    LD   A,DR_CPCNT         ; Identify an empty source-part list.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BPTAB:
    LD   A,DR_CTRAN         ; Identify wrapped part-table arithmetic.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BPORD:
    LD   A,DR_CPORD         ; Identify a non-dense part ordinal.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BSRAN:
    LD   A,DR_CSRAN         ; Identify a backwards source range.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BSRA1:
    LD   A,DR_CSRA1         ; Identify a backwards symbol arena.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BPRAN:
    LD   A,DR_CPRAN         ; Identify a backwards pending arena.
    JR   DR_CFAI1           ; Publish the common configuration failure.
DR_BORAN:
    LD   A,DR_CORAN         ; Identify a target beyond mathematical $10000.
DR_CFAI1:
    LD   (DR_DETAI),A       ; Retain the precise descriptor check that failed.
    LD   A,DR_SCFG          ; Return the broad public configuration category.
    SCF                     ; Mark descriptor validation as failed.
    RET                     ; No resident subsystem or sink was touched.

;@ROUTINE OUT A,CARRY,IX CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY,HL,BC,IY
DR_AFIN:
; Search the live pending arena for a diagnostic anchor. Exactly one pending
; record for each unresolved symbol has bit 7 set in its kind byte.
    LD   IX,(SY_ABAS1)      ; Begin at the pending arena's first record.
    LD   DE,(SY_NEXT)       ; Load its current exclusive end.
    CALL AT_CIDE            ; Compare the record cursor with that end.
    JR   Z,DR_FNPEN         ; An empty pending list needs symbol-table checks.
DR_FPLOO:
    BIT  7,(IX+4)           ; Test this record's diagnostic-anchor flag.
    JR   NZ,DR_FANCH        ; Validate and report the first live anchor.
; Non-anchor records cannot supply an undefined-symbol source location.
    LD   BC,SY_RECB1        ; Load the seven-byte pending-record stride.
    ADD  IX,BC              ; Advance to the next live pending record.
    CALL AT_CIDE            ; Test whether the cursor reached the arena end.
    JR   NZ,DR_FPLOO        ; Continue searching while records remain.
    JR   DR_FINT            ; Pending data without any anchor is corrupt.
DR_FANCH:
; Preserve the anchor's symbol-record pointer before validating it. A malformed
; pointer must never be dereferenced merely to improve a diagnostic.
    LD   L,(IX+0)           ; Read the anchor's symbol pointer low byte.
    LD   H,(IX+1)           ; Complete the candidate pointer in HL.
    LD   (DR_USYM),HL       ; Retain it for validation and diagnostics.
    CALL DR_VSPTR           ; Require a live, aligned symbol-record address.
    JR   C,DR_FINT          ; Never dereference a malformed pointer.
; A live anchor must point at an undefined symbol. A defined target means the
; patch-resolution path left stale metadata and is therefore an internal fault.
    LD   IY,(DR_USYM)       ; Address the now-validated symbol record.
    BIT  6,(IY+5)           ; Test the symbol's defined flag.
    JR   NZ,DR_FINT         ; A defined symbol must have no live anchor.
; The low kind bits must name one of the patch field forms. Zero and values past
; PT_KHB are corrupt even when the diagnostic-anchor bit itself is valid.
    LD   A,(IX+4)           ; Read anchor flag and encoded patch kind together.
    AND  SY_KMASK           ; Keep only the low patch-kind bits.
    JR   Z,DR_FINT          ; Kind zero is not a patch operation.
    CP   PT_KHB+1           ; PT_KHB is the highest defined patch kind.
    JR   NC,DR_FINT         ; Reject every out-of-range kind value.
; Recover the exact source location: the anchor owns the part ordinal, while an
; undefined symbol's otherwise-unused value word retains the reference offset.
    LD   A,(IX+SY_PMASK)    ; Read the anchor's complete source-part ordinal.
    LD   (ST_EPART),A       ; Publish it through the statement diagnostic ABI.
    LD   L,(IY+SY_VALLO)    ; Recover the reference offset low byte.
    LD   H,(IY+SY_VALHI)    ; Complete the source offset in HL.
    LD   (ST_EOFF),HL       ; Publish the exact byte offset within that part.
    XOR  A                  ; No nested statement detail applies here.
    LD   (ST_DETAI),A       ; Clear any detail left by the final statement.
; Return both the public undefined status and the symbol pointer for diagnostic
; name unpacking. Carry marks the finalisation failure.
    LD   IX,(DR_USYM)       ; Return the validated record for name decoding.
    LD   A,ST_SUNDE         ; Report the statement-layer undefined status.
    SCF                     ; Mark finalization as failed.
    RET                     ; The driver will abort the open generation.
DR_FNPEN:
; With no pending records, validate the final private-label scope without
; evicting it. An undefined private here is inconsistent because it has no
; diagnostic anchor.
    CALL SY_VSCOP           ; Validate the current private scope in place.
    JR   C,DR_FINT          ; A private failure without an anchor is corrupt.
; Private validation succeeded and may evict that scope. Walk permanent globals
; and require every record's defined flag; an undefined global without pending
; metadata is likewise an internal invariant failure.
    LD   IX,(SY_ABASE)      ; Begin at the permanent global-symbol arena.
    LD   DE,(SY_GEND)       ; Load its current exclusive end.
DR_FGLOO:
    CALL AT_CIDE            ; Compare the symbol cursor with the arena end.
    JR   Z,DR_FSUCC         ; Every retained global is defined.
    BIT  6,(IX+5)           ; Test this global record's defined flag.
    JR   Z,DR_FINT          ; Undefined without pending metadata is inconsistent.
    LD   BC,SY_RECB         ; Load the eight-byte symbol-record stride.
    ADD  IX,BC              ; Advance to the next permanent global.
    JR   DR_FGLOO           ; Validate it or finish the scan.
DR_FSUCC:
    XOR  A                  ; Return finalization success with carry clear.
    RET                     ; Symbol state is complete and internally sound.
DR_FINT:
; Do not expose a stale or unvalidated pointer on an internal failure.
    XOR  A                  ; Produce zero for both pointer bytes.
    LD   (DR_USYM),A        ; Clear the public symbol pointer low byte.
    LD   (DR_USYM+1),A      ; Clear its high byte before returning failure.
    LD   A,ST_SINT          ; Report a statement-layer internal invariant.
    SCF                     ; Mark finalization as failed.
    RET                     ; The driver will translate and abort.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
DR_VSPTR:
; First test the upward-growing global range [SY_ABASE, SY_GEND). Preserve the
; candidate around each subtraction because the comparisons destroy HL.
    PUSH HL                 ; Preserve the candidate across lower-bound compare.
    LD   DE,(SY_ABASE)      ; Load the first live global-record address.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Compare candidate against the global lower bound.
    POP  HL                 ; Restore the original candidate pointer.
    JR   C,DR_VPPTR         ; Below globals may still belong to private storage.
    PUSH HL                 ; Preserve it across the upper-bound compare.
    LD   DE,(SY_GEND)       ; Load the exclusive end of live globals.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Compare candidate against that exclusive end.
    POP  HL                 ; Restore the candidate again.
    JR   NC,DR_VPPTR        ; At or above global end requires private checking.
; A global pointer is valid only at an eight-byte record boundary from the
; arena base. SY_RECB is a power of two, so a mask performs the modulus test.
    LD   DE,(SY_ABASE)      ; Measure candidate from the global arena base.
    OR   A                  ; Clear carry before the known in-range subtraction.
    SBC  HL,DE              ; Produce the byte displacement from that base.
    LD   A,L                ; Only low alignment bits can affect modulo eight.
    AND  SY_RECB-1          ; Keep displacement modulo the record size.
    RET  Z                  ; Zero means an exact global-record boundary.
    SCF                     ; An interior byte is not a symbol pointer.
    RET                     ; Return invalid global alignment.
DR_VPPTR:
; Private records occupy [SY_LBEG, SY_AEND) and grow down from SY_AEND.
    PUSH HL                 ; Preserve the candidate across lower-bound compare.
    LD   DE,(SY_LBEG)       ; Load the first live private-record address.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Compare candidate with the private lower bound.
    POP  HL                 ; Restore the original candidate pointer.
    RET  C                  ; Below the live private range is invalid.
    PUSH HL                 ; Preserve it across the upper-bound compare.
    LD   DE,(SY_AEND)       ; Load the symbol arena's exclusive end.
    OR   A                  ; Clear carry before unsigned subtraction.
    SBC  HL,DE              ; Compare candidate with that exclusive end.
    POP  HL                 ; Restore the candidate for alignment testing.
    JR   NC,DR_ISPTR        ; At or above arena end is not a live record.
; Measure backwards from the arena end to prove eight-byte alignment with the
; downward-growing record layout.
    LD   DE,(SY_AEND)       ; Load the fixed high end of private allocation.
    EX   DE,HL              ; Put arena end in HL and candidate in DE.
    OR   A                  ; Clear carry before the in-range subtraction.
    SBC  HL,DE              ; Measure backwards from the arena end.
    LD   A,L                ; Select the low alignment bits.
    AND  SY_RECB-1          ; Keep displacement modulo eight.
    RET  Z                  ; Zero means an exact private-record boundary.
DR_ISPTR:
    SCF                     ; Mark every other candidate pointer invalid.
    RET                     ; The caller must not dereference it.
DR_CEND:
DR_WBEG:
; Address of the immutable build descriptor supplied to DR_ASM.
DR_DESC: DW 0               ; Saved build-descriptor address.
; Address of the next five-byte part record during validation or assembly.
DR_PCURS: DW 0              ; Current source-part record address.
; Number of part records still to validate or assemble.
DR_PREM: DB 0               ; Remaining part-record count.
; Dense ordinal expected for the current part record.
DR_PINDE: DB 0              ; Expected dense part ordinal.
; Subsystem or configuration detail associated with the public driver status.
DR_DETAI: DB 0              ; Nested status or configuration detail.
; Validated symbol-record pointer for an undefined-symbol diagnostic, else zero.
DR_USYM: DW 0               ; Validated undefined-symbol record address.
DR_WEND:
