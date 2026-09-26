;==========================================================================
;  Logical output and patch submission
;==========================================================================
;
;  Maintain the logical target cursor and initial-capacity account. IMAGE
;  operations append bytes during assembly. Reservations advance the
;  cursor without initialising bytes and ORG selects a new logical address.
;  Defining a referenced symbol calculates its final fields and submits a
;  PATCH operation before the corresponding pending record is removed.
;
;  Principal entries:
;    OU_RESET  initialise logical output state
;    OU_EMITB  emit one IMAGE byte
;    OU_EMITW  emit one little-endian IMAGE word
;    OU_RESER  reserve a target interval
;    OU_SORIG  change the logical origin
;    OU_EINS   encode and emit one parsed instruction
;    OU_RSLV   resolve and submit every pending patch for a symbol
;
;  IMAGE cursor movement follows sink acceptance. A multi-byte helper may
;  leave partial tentative output if a later byte fails. The driver aborts
;  that generation. PATCH failure never removes its pending record.

OU_CBEG:                    ; Begin the executable output module.

; Module statuses: capacity, internal invariant, concrete value range and
; relative displacement range.

OU_SCAP EQU 1               ; Report that the target interval is too small.
OU_SINT EQU 2               ; Report an impossible internal state.
OU_SVRAN EQU 3              ; Report a concrete value outside its field range.
OU_SRRAN EQU 4              ; Report a relative target outside -128..127.

;@ROUTINE IN DE,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Start a logical output interval at HL with DE bytes of remaining capacity.

OU_RESET:
    LD   (OU_CURSO),HL      ; Install the first logical output address.
    LD   (OU_REM),DE        ; Record the number of writable target bytes.
    XOR  A                  ; Return status zero with carry clear.
    RET                     ; Give control back to the driver.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,SIGN,PARITY,HALFCARRY,HL,ZERO
; Non-mutating check that the remaining-capacity word can cover HL bytes.

OU_CCAP:
    EX   DE,HL              ; Move the requested byte count into DE.
    LD   HL,(OU_REM)        ; Load the current capacity without committing it.
    OR   A                  ; Clear carry before the unsigned subtraction.
    SBC  HL,DE              ; Does capacity cover the request?
    JR   C,OU_DCFAI         ; Reject an oversized request.
    XOR  A                  ; Report a successful capacity check.
    RET                     ; Leave the stored capacity unchanged.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Emit one IMAGE byte from A. Check capacity before calling the sink
; and cursor-commit tail.

OU_EMITB:
    LD   B,A                ; Preserve the byte while capacity is checked.
    LD   HL,1               ; Ask for exactly one target byte.
    CALL OU_CCAP            ; Check capacity before submission.
    RET  C                  ; Leave output untouched on failure.
    LD   A,B                ; Restore the caller's byte value.
    JR   OU_EBREA           ; Submit it through the common byte-emission tail.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Emit HL little-endian as two IMAGE operations. Capacity for both bytes is
; checked first. If the second sink call fails, the first IMAGE remains
; tentative and the cursor has advanced by one. The driver aborts generation.

OU_EMITW:
    LD   B,H                ; Preserve the high byte in B.
    LD   C,L                ; Preserve the low byte in C.
    LD   HL,2               ; Require room for both little-endian bytes.
    CALL OU_CCAP            ; Preflight the complete word operation.
    RET  C                  ; Fail before emitting either byte.
    LD   A,C                ; Select the low byte for the first IMAGE.
    PUSH BC                 ; Protect both bytes across the host service call.
    CALL OU_EBREA           ; Submit the low byte and advance the cursor.
    POP  BC                 ; Recover the high byte and saved low byte.
    RET  C                  ; Return if the sink rejected the low byte.
    LD   A,B                ; Select the high byte for the second IMAGE.
    JR   OU_EBREA           ; Submit it and return the common tail's result.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reserve HL logical bytes without IMAGE operations. Commit the cursor and
; remaining-capacity change only after the complete interval passes preflight.

OU_RESER:
    PUSH HL                 ; Preserve the requested reservation length.
    CALL OU_CCAP            ; Prove the whole interval remains in range.
    POP  DE                 ; Recover reservation length in DE.
    RET  C                  ; Leave cursor and capacity unchanged on failure.
    LD   HL,(OU_CURSO)      ; Load the current logical target address.
    ADD  HL,DE              ; Advance past the uninitialized interval.
    LD   (OU_CURSO),HL      ; Publish the new logical cursor.
    LD   HL,(OU_REM)        ; Load the previously proved remaining capacity.
    OR   A                  ; Clear carry before subtracting the reservation.
    SBC  HL,DE              ; Consume the reserved bytes from the account.
    LD   (OU_REM),HL        ; Publish the reduced capacity.
    XOR  A                  ; Report successful reservation with carry clear.
    RET                     ; Return without submitting any IMAGE bytes.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Select a new logical origin. Enforcing the target extent and any append-only
; policy is the surrounding platform adapter's responsibility.

OU_SORIG:
    LD   (OU_CURSO),HL      ; Set cursor to requested origin.
    XOR  A                  ; Report successful cursor update.
    RET                     ; Continue statement assembly at the new address.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY,DE,IX,IY
; Submit A as one IMAGE byte at the cursor. C=0 is the base output class.
; Publish cursor and capacity changes only after HS_IB accepts the operation.
; Each caller preflights capacity before entering this shared tail.

OU_EBREA:
    LD   HL,(OU_CURSO)      ; Supply the current logical address to the sink.
    LD   C,0                ; Select the base output class.
    CALL HS_IB              ; Submit A as one IMAGE byte.
    RET  C                  ; Preserve state if the sink rejects the byte.
    LD   HL,(OU_CURSO)      ; Reload the accepted byte's address.
    INC  HL                 ; Move to the next logical output address.
    LD   (OU_CURSO),HL      ; Commit the new cursor.
    LD   HL,(OU_REM)        ; Reload the target-capacity account.
    DEC  HL                 ; Charge the accepted byte against the account.
    LD   (OU_REM),HL        ; Commit the reduced remaining capacity.
    XOR  A                  ; Normalize success status and clear carry.
    RET                     ; Return after the host and local state agree.
OU_DCFAI:                   ; Return the shared capacity-failure status.
    LD   A,OU_SCAP          ; Identify target-capacity exhaustion.
    SCF                     ; Mark the operation as failed.
    RET                     ; Leave every output field unchanged.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Encode and emit the parsed instruction at IX. The encoder commits into the
; private four-byte buffer; output and pending capacity are both proved before
; the first IMAGE operation is submitted.

OU_EINS:
    LD   HL,(OU_CURSO)      ; Capture instruction start address.
    LD   (OU_IBEG),HL       ; Keep it for fields and pending records.
    LD   DE,OU_INSB         ; Point at private encoder buffer.
    CALL EN_NAME            ; Validate and encode the parsed record at IX.
    RET  C                  ; Publish nothing when the form is invalid.
    LD   (OU_ILEN),A        ; Save encoded length, one to four bytes.

; Compare the returned length against remaining capacity without changing it.

    LD   B,A                ; Hold the short instruction length in B.
    LD   HL,(OU_REM)        ; Load the available target capacity.
    LD   A,H                ; Inspect the high byte first.
    OR   A                  ; Any nonzero high byte suffices.
    JR   NZ,.ICREADY        ; Skip low-byte capacity check.
    LD   A,L                ; Compare the small remaining capacity directly.
    CP   B                  ; Set carry when fewer than B bytes remain.
    JR   C,.ICFAIL          ; Reject the instruction before emitting a prefix.
.ICREADY:                   ; Check pending storage after output capacity.
    CALL PR_CREFE           ; Check every unresolved field.
    RET  C                  ; Return before instruction emission.

; Emit the exact encoded byte sequence. A sink failure leaves only already
; accepted tentative IMAGE operations. No pending reference is queued yet.

    XOR  A                  ; Start the encoded-buffer index at zero.
    LD   (OU_ISCAN),A       ; Store the index across host service calls.
.INSLOOP:                   ; Emit one encoded byte per iteration.
    LD   A,(OU_ILEN)        ; Load the total encoded instruction length.
    LD   B,A                ; Keep the loop limit in B.
    LD   A,(OU_ISCAN)       ; Load the next buffer index.
    CP   B                  ; Test whether every encoded byte was accepted.
    JR   Z,.INSDONE         ; Queue pending fields only after full emission.
    LD   E,A                ; Move the unsigned index into DE.
    LD   D,0                ; Zero-extend the index for address arithmetic.
    LD   HL,OU_INSB         ; Point at the start of the encoded byte buffer.
    ADD  HL,DE              ; Select the byte at the current index.
    LD   A,(HL)             ; Load the byte to submit as IMAGE data.
    CALL OU_EBREA           ; Emit it and commit one cursor step.
    RET  C                  ; Let the driver abort any partial instruction.
    LD   HL,OU_ISCAN        ; Address the stored scan index.
    INC  (HL)               ; Advance to the next encoded byte.
    JR   .INSLOOP           ; Continue until the saved length is reached.
.INSDONE:                   ; Every instruction byte is now tentative output.

; Queue deferred references after every byte succeeds. Patch addresses are
; derived from the instruction start saved before encoding.

    LD   DE,(OU_IBEG)       ; Supply the instruction base for field addresses.
    JP   PR_QREFE           ; Queue all deferred fields and return its status.
.ICFAIL:                    ; Reject an instruction that cannot fit.
    LD   A,OU_SCAP          ; Select the capacity status code.
    SCF                     ; Mark the instruction emission as failed.
    RET                     ; Return without submitting the first byte.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve pending records for the symbol at IX. Each loop peeks a record,
; computes and submits its final bytes, then removes that record.

OU_RSLV:
; Resolution is valid only after the symbol has a final value.

    BIT  6,(IX+5)           ; Test the symbol record's defined flag.
    JP   Z,OU_RINT          ; Reject an undefined-symbol request.
    PUSH IX                 ; Transfer symbol pointer via stack.
    POP  HL                 ; Recover pointer in storable HL.
    LD   (OU_RSPTR),HL      ; Preserve it while pending records are inspected.
.RSLVLOOP:                  ; Resolve one matching field per loop.
    LD   IX,(OU_RSPTR)      ; Restore the symbol record expected by SY_PEEK.
;@EXPECTOUT A,CARRY,BC,DE
    CALL SY_PEEK            ; Find the next unresolved field for this symbol.
    JP   C,.RPFAIL          ; Check exhaustion or failure.
    LD   (OU_RPADR),DE      ; Save the field's logical patch address.
    LD   A,B                ; Copy the field's kind-and-anchor metadata byte.
    AND  SY_KMASK           ; Retain only the patch-transform bits.
    LD   (OU_RKIND),A       ; Save transform across later calls.
    LD   A,C                ; Fetch the pending signed eight-bit addend.
    LD   (OU_RADDE),A       ; Preserve it for 24-bit value construction.

; Sign-extend the symbol value to 24 bits when its equate carries SY_FSIGN.

    LD   IX,(OU_RSPTR)      ; Return to the defined symbol record.
    LD   L,(IX+SY_VALLO)    ; Load the low byte of its stored value.
    LD   H,(IX+SY_VALHI)    ; Load the high byte of its stored value.
    XOR  A                  ; Assume a non-negative 24-bit extension byte.
    BIT  5,(IX+5)           ; Test the equate's signed-value flag.
    JR   Z,.RBREADY         ; Zero-extend labels and unsigned values.
    DEC  A                  ; Use FF to sign-extend a signed equate.
.RBREADY:                   ; A now holds the symbol's extension byte.
    LD   (OU_RBHI),A        ; Save it for the high stage of the addition.

; Sign-extend the pending one-byte addend and add it to the 24-bit base. The
; third byte retains overflow information for the domain/range checks below.

    LD   A,(OU_RADDE)       ; Reload the pending record's addend byte.
    LD   C,A                ; Place its low byte in C for addition.
    LD   D,0                ; Assume the addend is non-negative.
    BIT  7,C                ; Inspect the signed addend's sign bit.
    JR   Z,.RSREADY         ; Keep a zero extension for 0..127.
    DEC  D                  ; Use FF to sign-extend -128..-1.
.RSREADY:                   ; C holds the addend; D holds its sign extension.
    LD   A,L                ; Begin with the symbol value's low byte.
    ADD  A,C                ; Add the pending low-byte adjustment.
    LD   (OU_RVAL),A        ; Store the final low byte.
    LD   A,H                ; Continue with the symbol value's high byte.
    ADC  A,D                ; Add the extension and propagated carry.
    LD   (OU_RVAL+1),A      ; Store the final high byte.
    LD   A,(OU_RBHI)        ; Load the symbol's 24-bit extension byte.
    ADC  A,D                ; Complete the signed 24-bit sum.
    LD   (OU_RVAL+2),A      ; Retain its domain and overflow evidence.
    CALL OU_RWDOM           ; Require the supported -32768..65535 domain.
    RET  C                  ; Keep record on invalid value.

; Dispatch patch transform. Truncate and LOW select the low byte.
; HIGH selects the second byte. Byte, displacement and relative forms enforce
; their distinct ranges before submission.

    LD   A,(OU_RKIND)       ; Load the retained patch-transform kind.
    CP   PT_KINDB           ; Is this a range-checked immediate byte?
    JR   Z,.RSLVB           ; Validate 0..255 before submission.
    CP   PT_KINDW           ; Is this a complete little-endian word?
    JR   Z,.RSLVW           ; Submit both low sixteen-bit bytes.
    CP   PT_KRELA           ; Is this a PC-relative displacement?
    JR   Z,.RRELATIV        ; Convert the target into a signed offset.
    CP   PT_KDISP           ; Is this an indexed signed displacement?
    JR   Z,.RDISPLAC        ; Enforce the -128..127 domain.
    CP   PT_KTB             ; Is this an explicit truncating byte transform?
    JR   Z,.RSB             ; Select the low byte without a range check.
    CP   PT_KLB             ; Is this the LOW transform?
    JR   Z,.RSB             ; Select the low byte without a range check.
    CP   PT_KHB             ; Is this the HIGH transform?
    JP   NZ,OU_RINT         ; Reject an unknown pending-record kind.
.RSLVHIB:                   ; Select the high byte of the resolved value.
    LD   A,(OU_RVAL+1)      ; Load bits 8..15 for a HIGH patch.
    JR   .RSBA              ; Submit the selected byte.
.RSLVB:                     ; Validate an ordinary unsigned byte field.

; An ordinary byte patch accepts only 0..255.

    LD   A,(OU_RVAL+2)      ; Inspect the 24-bit extension byte.
    OR   A                  ; It must be zero for an unsigned byte.
    JR   NZ,OU_RVRAN        ; Reject negative or overflowing values.
    LD   A,(OU_RVAL+1)      ; Inspect bits 8..15.
    OR   A                  ; They must also be zero.
    JR   NZ,OU_RVRAN        ; Reject values above 255.
    JR   .RSB               ; Submit the already validated low byte.
.RDISPLAC:                  ; Validate a signed indexed displacement.

; Indexed displacement accepts a fully sign-extended -128..-1 or 0..127.

    LD   A,(OU_RVAL+2)      ; Inspect the sign-extension byte.
    OR   A                  ; Zero selects the non-negative half.
    JR   Z,.RDPOSITI        ; Validate 0..127 separately.
    INC  A                  ; FF becomes zero only for a negative extension.
    JR   NZ,OU_RVRAN        ; Reject every other upper byte.
    LD   A,(OU_RVAL+1)      ; Inspect the middle byte of a negative value.
    INC  A                  ; It too must be FF.
    JR   NZ,OU_RVRAN        ; Reject values below the signed-byte domain.
    LD   A,(OU_RVAL)        ; Inspect the candidate displacement byte.
    BIT  7,A                ; A negative byte must have its sign bit set.
    JR   Z,OU_RVRAN         ; Reject -256..-129 aliases.
    JR   .RSB               ; Submit the valid negative displacement.
.RDPOSITI:                  ; Validate the non-negative signed-byte half.
    LD   A,(OU_RVAL+1)      ; Inspect bits 8..15.
    OR   A                  ; They must be zero for 0..127.
    JR   NZ,OU_RVRAN        ; Reject values above 255 immediately.
    LD   A,(OU_RVAL)        ; Load the candidate positive displacement.
    BIT  7,A                ; Its sign bit must remain clear.
    JR   NZ,OU_RVRAN        ; Reject 128..255.
    JR   .RSB               ; Submit the valid non-negative displacement.
.RRELATIV:                  ; Convert an absolute target to a relative field.

; Relative fields store target-(patch-address+1). Subtraction wraps at 16 bits
; with the Z80 program counter before the signed-byte range check.

    LD   HL,(OU_RVAL)       ; Load the resolved absolute target address.
    LD   DE,(OU_RPADR)      ; Load the address of the relative field byte.
    INC  DE                 ; Form the address immediately after that field.
    OR   A                  ; Clear carry before target-base subtraction.
    SBC  HL,DE              ; Calculate the wrapped sixteen-bit displacement.
    LD   A,H                ; Inspect the displacement's high byte.
    OR   A                  ; Zero selects the non-negative half.
    JR   Z,.RRPOSITI        ; Validate 0..127 separately.
    INC  A                  ; FF is required for a negative signed byte.
    JR   NZ,OU_RRRAN        ; Reject high bytes other than 00 or FF.
    BIT  7,L                ; Confirm the low byte is actually negative.
    JR   Z,OU_RRRAN         ; Reject wrapped values outside -128..-1.
    LD   A,L                ; Select the valid negative displacement byte.
    JR   .RSBA              ; Submit it as the resolved patch.
.RRPOSITI:                  ; Validate a non-negative relative displacement.
    BIT  7,L                ; Its sign bit must remain clear.
    JR   NZ,OU_RRRAN        ; Reject 128..255.
    LD   A,L                ; Select the valid positive displacement byte.
    JR   .RSBA              ; Submit it as the resolved patch.
.RSB:                       ; Select the low byte of the resolved value.
    LD   A,(OU_RVAL)        ; Load bits 0..7 for byte and LOW transforms.
.RSBA:                      ; Submit the selected single-byte patch value.

; Submit a one-byte PATCH at the saved logical field address. C=0 is the base
; output class. Do not remove the pending record if the sink rejects it.

    LD   HL,(OU_RPADR)      ; Restore the pending field's logical address.
    LD   C,0                ; Select the base output class.
    CALL HS_PB              ; Ask the sink to accept the final patch byte.
    RET  C                  ; Preserve the pending record on rejection.
    JR   .RREMOVE           ; Remove the record only after sink acceptance.
.RSLVW:                     ; Submit a complete little-endian word patch.

; Word patches submit the checked low sixteen bits little-endian.

    LD   HL,(OU_RVAL)       ; Supply the resolved low sixteen-bit value.
    LD   DE,(OU_RPADR)      ; Supply the logical field address.
    LD   C,0                ; Select the base output class.
    CALL HS_PW              ; Ask the sink to accept both patch bytes.
    RET  C                  ; Keep the pending record if submission fails.
.RREMOVE:                   ; Reclaim the record for an accepted patch.

; Sink acceptance makes removal safe. SY_TAKE preserves metadata from
; SY_PEEK while compacting the pending arena.

    LD   IX,(OU_RSPTR)      ; Restore the defined symbol record.
;@EXPECTOUT A,CARRY,BC,DE
    CALL SY_TAKE            ; Remove record returned by SY_PEEK.
    JR   C,OU_RINT          ; Peek/take disagreement is internal.
    JP   .RSLVLOOP          ; Look for another field referencing this symbol.
.RPFAIL:                    ; Interpret the status returned by SY_PEEK.

; SY_PEEK reports SY_SNFOU when no matching record remains. Translate that
; exhaustion status to successful completion of this symbol's resolution loop.

    CP   SY_SNFOU           ; Is this normal end-of-list rather than an error?
    RET  NZ                 ; Return an unexpected status unchanged in A.
    XOR  A                  ; Translate exhaustion into successful completion.
    RET                     ; Return after every matching patch was submitted.
OU_RVRAN:                   ; Return the concrete-value range failure.
    LD   A,OU_SVRAN         ; Select the value-range status code.
    SCF                     ; Mark resolution as failed.
    RET                     ; Leave the current pending record intact.
OU_RRRAN:                   ; Return the relative-displacement range failure.
    LD   A,OU_SRRAN         ; Select the relative-range status code.
    SCF                     ; Mark resolution as failed.
    RET                     ; Preserve the unresolved pending record.
OU_RINT:                    ; Return an internal-consistency failure.
    LD   A,OU_SINT          ; Select the invariant status code.
    SCF                     ; Mark the impossible state as failed.
    RET                     ; Return for driver-level abort and diagnosis.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Require the signed/unsigned word domain -32768..65535. A zero top
; byte admits nonnegative words. FF is valid only with bit 15 set.

OU_RWDOM:
    LD   A,(OU_RVAL+2)      ; Inspect the 24-bit extension byte.
    OR   A                  ; Zero admits every unsigned sixteen-bit value.
    RET  Z                  ; Return success with carry clear for 0..65535.
    INC  A                  ; FF becomes zero for a negative sign extension.
    JR   NZ,OU_RVRAN        ; Reject values outside both supported extensions.
    LD   A,(OU_RVAL+1)      ; Inspect the sign bit of the low sixteen bits.
    BIT  7,A                ; Negative-domain values require bit 15 set.
    RET  NZ                 ; Accept -32768..-1 with carry still clear.
    JR   OU_RVRAN           ; Reject sign-extended values below -32768.
OU_CEND:                    ; Mark the end of executable output code.
OU_WBEG:                    ; Begin the output module's fixed workspace.

; Fixed workspace is fourteen bytes: four for cursor/capacity and ten
; shared by the instruction buffer and patch-resolution state while
; draining one symbol's pending patches.

; Statements call OU_EINS and OU_RSLV in sequence, never nested, so
; their scratch lifetimes do not overlap.

OU_CURSO: DW 0              ; Current logical target address.
OU_REM: DW 0                ; Remaining bytes in the initial target interval.
OU_WUNIO: DS 10             ; Instruction/patch scratch overlay.
OU_IBEG EQU OU_WUNIO        ; Instruction start address during emission.
OU_INSB EQU OU_WUNIO+2      ; Four-byte encoder destination buffer.
OU_ILEN EQU OU_WUNIO+6      ; Encoded instruction length.
OU_ISCAN EQU OU_WUNIO+7     ; Current index within the encoder buffer.
OU_RSPTR EQU OU_WUNIO       ; Defined symbol-record pointer during resolution.
OU_RPADR EQU OU_WUNIO+2     ; Address of the pending field being patched.
OU_RKIND EQU OU_WUNIO+4     ; Pending field transform kind.
OU_RADDE EQU OU_WUNIO+5     ; Signed one-byte pending addend.
OU_RVAL EQU OU_WUNIO+6      ; Three-byte resolved value with domain evidence.
OU_RBHI EQU OU_WUNIO+9      ; Sign-extension byte for the symbol base value.
OU_WEND:                    ; End the fixed workspace extent.
