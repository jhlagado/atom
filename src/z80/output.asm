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
;    outReset  initialise logical output state
;    outEmitB  emit one IMAGE byte
;    outEmitW  emit one little-endian IMAGE word
;    outSkip  reserve a target interval
;    outOrg  change the logical origin
;    outEmitI   encode and emit one parsed instruction
;    outFixUp   resolve and submit every pending patch for a symbol
;
;  IMAGE cursor movement follows sink acceptance. A multi-byte helper may
;  leave partial tentative output if a later byte fails. The driver aborts
;  that generation. PATCH failure never removes its pending record.

outBeg: ; Begin the executable output module.

; Module statuses: capacity, internal invariant, concrete value range and
; relative displacement range.

outFull     EQU     1                   ; Report that the target interval is too small.
outInvar    EQU     2                   ; Report an impossible internal state.
outRange    EQU     3                   ; Report a concrete value outside its field range.
outFar      EQU     4                   ; Report a relative target outside -128..127.
outAtTop    EQU     1                   ; Cursor word zero can mean exclusive end $10000.
outHiTop    EQU     2                   ; High-water word zero can mean exclusive $10000.
outToTop    EQU     4                   ; Target extent itself ends at exclusive $10000.

;@ROUTINE IN DE,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Start a target interval at HL with DE bytes of capacity. Keep its absolute
; bounds and initialise cursor/high-water state before any sink can begin.

outReset: ; Initialise cursor, target bounds and endpoint markers.
    PUSH DE                             ; Preserve the descriptor's target capacity.
    PUSH HL                             ; Preserve the descriptor's target origin.
    LD   (outAddr),HL                   ; Install the first logical output address.
    LD   (outBase),HL                   ; Retain the inclusive lower target bound.
    LD   (outHigh),HL                   ; Start high water at the target origin.
    LD   (outLeft),DE                   ; Record the number of writable target bytes.
    ADD  HL,DE                          ; Calculate the exclusive target end.
    LD   (outLimit),HL                  ; Keep its low sixteen bits for range checks.
    LD   A,0                            ; Prepare a zero-extended carry value.
    ADC  A,0                            ; Record whether the end is exactly $10000.
    RLCA                                ; Move the endpoint marker toward bit two.
    RLCA                                ; Store target-end state in outToTop.
    LD   (outFlags),A                   ; Cursor and high water both start below $10000.
    POP  HL                             ; Restore the caller's target origin.
    POP  DE                             ; Restore the caller's target capacity.
    XOR  A                              ; Return status zero with carry clear.
    LD   (outBadOp),A                   ; No sink operation has failed yet.
    RET                                 ; Give control back to the driver.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,SIGN,PARITY,HALFCARRY,HL,ZERO
; Non-mutating check that the remaining-capacity word can cover HL bytes.

outCapOk: ; Prove a requested interval fits without changing output state.
    EX   DE,HL                          ; Move the requested byte count into DE.
    LD   HL,(outLeft)                   ; Load the current capacity without committing it.
    OR   A                              ; Clear carry before the unsigned subtraction.
    SBC  HL,DE                          ; Does capacity cover the request?
    JP   C,outNoFit                     ; Reject an oversized request.
    LD   A,(outFlags)                   ; Read endpoint state for the current cursor.
    BIT  0,A                            ; Is the cursor already at $10000?
    JR   NZ,.atEnd                      ; Only zero bytes fit at the endpoint.
    LD   HL,(outAddr)                   ; Load the current sixteen-bit cursor.
    ADD  HL,DE                          ; Compute the exclusive end of this operation.
    JR   C,.wrapped                     ; Carry can be valid only for exact $10000.
    LD   A,(outFlags)                   ; Check whether every sixteen-bit end is in range.
    BIT  2,A                            ; Does the configured target end at $10000?
    JR   NZ,.ready                      ; Then this nonwrapped end is necessarily inside.
    LD   DE,(outLimit)                  ; Load the ordinary sixteen-bit target endpoint.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is the operation end at or below that endpoint?
    JR   C,.ready                       ; A smaller end is inside the target.
    JR   Z,.ready                       ; Equality is the permitted exclusive endpoint.
    JP   outNoFit                       ; Reject an operation extending past the target.
.wrapped: ; Accept wrapped arithmetic only at mathematical endpoint $10000.
    LD   A,H                            ; Check for a zero wrapped result.
    OR   L                              ; A nonzero result exceeds $10000.
    JP   NZ,outNoFit                    ; Reject arithmetic beyond the Z80 address space.
    LD   A,(outFlags)                   ; Exact $10000 needs a target with that endpoint.
    BIT  2,A                            ; Is $10000 the configured exclusive target end?
    JP   Z,outNoFit                     ; Otherwise the operation exceeds the target.
    JR   .ready                         ; The exact endpoint is valid for this target.
.atEnd: ; Allow only zero length after the cursor reaches $10000.
    LD   A,D                            ; Check the requested length's high byte.
    OR   E                              ; Only a zero-length operation can remain at end.
    JP   NZ,outNoFit                    ; Reject any attempt to write beyond $10000.
.ready: ; Return successful capacity preflight with carry clear.
    XOR  A                              ; Report a successful capacity check.
    RET                                 ; Leave the stored capacity unchanged.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Emit one IMAGE byte from A. Check capacity before calling the sink
; and cursor-commit tail.

outEmitB: ; Preflight and submit one IMAGE byte from A.
    LD   B,A                            ; Preserve the byte while capacity is checked.
    LD   HL,1                           ; Ask for exactly one target byte.
    CALL outCapOk                       ; Check capacity before submission.
    RET  C                              ; Leave output untouched on failure.
    LD   A,B                            ; Restore the caller's byte value.
    JR   outSendB                       ; Submit it through the common byte-emission tail.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Emit HL little-endian as two IMAGE operations. Capacity for both bytes is
; checked first. If the second sink call fails, the first IMAGE remains
; tentative and the cursor has advanced by one. The driver aborts generation.

outEmitW: ; Preflight and submit HL as two little-endian IMAGE bytes.
    LD   B,H                            ; Preserve the high byte in B.
    LD   C,L                            ; Preserve the low byte in C.
    LD   HL,2                           ; Require room for both little-endian bytes.
    CALL outCapOk                       ; Preflight the complete word operation.
    RET  C                              ; Fail before emitting either byte.
    LD   A,C                            ; Select the low byte for the first IMAGE.
    PUSH BC                             ; Protect both bytes across the host service call.
    CALL outSendB                       ; Submit the low byte and advance the cursor.
    POP  BC                             ; Recover the high byte and saved low byte.
    RET  C                              ; Return if the sink rejected the low byte.
    LD   A,B                            ; Select the high byte for the second IMAGE.
    JR   outSendB                       ; Submit it and return the common tail's result.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reserve HL logical bytes without IMAGE operations. Commit the cursor and
; remaining-capacity change only after the complete interval passes preflight.

outSkip: ; Reserve a logical interval without emitting IMAGE bytes.
    PUSH HL                             ; Preserve the requested reservation length.
    CALL outCapOk                       ; Prove the whole interval remains in range.
    POP  DE                             ; Recover reservation length in DE.
    RET  C                              ; Leave cursor and capacity unchanged on failure.
    LD   HL,(outAddr)                   ; Load the current logical target address.
    ADD  HL,DE                          ; Advance past the uninitialised interval.
    LD   (outAddr),HL                   ; Publish the new logical cursor.
    JR   NC,.high                       ; No carry leaves the cursor below $10000.
    LD   A,(outFlags)                   ; Preserve target and high-water endpoint bits.
    OR   outAtTop                       ; Mark the cursor as mathematical $10000.
    LD   (outFlags),A                   ; Keep that endpoint distinct from address zero.
.high: ; Charge the reservation and update its high-water extent.
    LD   HL,(outLeft)                   ; Load the previously proved remaining capacity.
    OR   A                              ; Clear carry before subtracting the reservation.
    SBC  HL,DE                          ; Consume the reserved bytes from the account.
    LD   (outLeft),HL                   ; Publish the reduced capacity.
    CALL outRaise                       ; Retain the greatest reached logical address.
    XOR  A                              ; Report successful reservation with carry clear.
    RET                                 ; Return without submitting any IMAGE bytes.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Select an origin inside the configured target. A successful backward ORG
; changes the final cursor but never reduces the accumulated high-water mark.

outOrg: ; Select an origin within the configured target interval.
    PUSH DE                             ; Keep the caller's DE pair unchanged.
    PUSH HL                             ; Keep the origin during comparison.
    LD   DE,(outBase)                   ; Load the target's inclusive lower bound.
    OR   A                              ; Clear carry before checking the lower bound.
    SBC  HL,DE                          ; Is the requested address at or above the base?
    POP  HL                             ; Restore origin and preserve flags.
    JR   C,.bad                         ; Reject an origin before the configured target.
    LD   A,(outFlags)                   ; Read the target-end representation.
    BIT  2,A                            ; Is its exclusive end mathematical $10000?
    JR   NZ,.inRange                    ; Every address is below this endpoint.
    PUSH HL                             ; Preserve the origin during the upper-bound test.
    LD   DE,(outLimit)                  ; Load the ordinary exclusive target endpoint.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is the requested address below the endpoint?
    POP  HL                             ; Restore the origin after comparison.
    JR   C,.inRange                     ; A smaller address is inside the target.
    JR   Z,.inRange                     ; The exclusive endpoint itself is a valid cursor.
    JR   .bad                           ; Reject an origin beyond the configured target.
.inRange: ; Commit the accepted origin and clear cursor-end state.
    LD   (outAddr),HL                   ; Set cursor to requested origin.
    LD   A,(outFlags)                   ; Read flags before clearing cursor-end state.
    AND  $FE                            ; An ORG literal cannot mean $10000.
    LD   (outFlags),A                   ; Publish the ordinary sixteen-bit cursor state.
    PUSH HL                             ; Preserve the requested address for the caller.
    CALL outRaise                       ; Raise high water if this ORG moves it forward.
    POP  HL                             ; Restore the input cursor promised by this entry.
    POP  DE                             ; Restore the caller's original DE pair.
    XOR  A                              ; Report successful cursor update.
    RET                                 ; Continue statement assembly at the new address.
.bad: ; Restore caller state before reporting an invalid origin.
    POP  DE                             ; Restore the caller's original DE pair.
    JP   outNoFit                       ; Report a target-capacity/range failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY,DE,IX,IY
; Submit A as one IMAGE byte at the cursor. C=0 is the base output class.
; Publish cursor and capacity changes only after hsByte accepts the operation.
; Each caller preflights capacity before entering this shared tail.

outSendB: ; Submit one byte and advance state after sink acceptance.
    LD   HL,(outAddr)                   ; Supply the current logical address to the sink.
    LD   C,0                            ; Select the base output class.
    CALL hsByte                         ; Submit A as one IMAGE byte.
    JP   C,outDeny                      ; Preserve state if the sink rejects the byte.
    LD   HL,(outAddr)                   ; Reload the accepted byte's address.
    INC  HL                             ; Move to the next logical output address.
    LD   (outAddr),HL                   ; Commit the new cursor.
    LD   A,H                            ; Check whether increment reached the end.
    OR   L                              ; Zero means the accepted byte was at $FFFF.
    JR   NZ,.high                       ; Keep the ordinary cursor otherwise.
    LD   A,(outFlags)                   ; Preserve target/high-water endpoint state.
    OR   outAtTop                       ; Distinguish the end from literal address zero.
    LD   (outFlags),A                   ; Publish the cursor endpoint bit.
.high: ; Update high water and charge the accepted byte's capacity.
    CALL outRaise                       ; Retain the greatest accepted output address.
    LD   HL,(outLeft)                   ; Reload the target-capacity account.
    DEC  HL                             ; Charge the accepted byte against the account.
    LD   (outLeft),HL                   ; Commit the reduced remaining capacity.
    XOR  A                              ; Normalise success status and clear carry.
    RET                                 ; Return after the host and local state agree.

;@ROUTINE CLOBBERS A,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Raise high water to the current cursor. Reload the cursor here because
; callers may have reused HL while updating another part of output state.
; Cursor-end state promotes the mathematical mark to $10000.

outRaise: ; Raise the exclusive high-water extent to the current cursor.
    LD   A,(outFlags)                   ; Read cursor and accumulated endpoint markers.
    BIT  1,A                            ; Is high water already mathematical $10000?
    RET  NZ                             ; Nothing can raise that maximum further.
    BIT  0,A                            ; Did this cursor just reach mathematical $10000?
    JR   NZ,.endPoint                   ; Promote high water without another comparison.
    LD   HL,(outAddr)                   ; Read the cursor rather than trusting caller HL.
    LD   DE,(outHigh)                   ; Load the current ordinary high-water word.
    OR   A                              ; Clear carry before the unsigned comparison.
    SBC  HL,DE                          ; Is the current cursor greater than high water?
    RET  C                              ; A lower cursor must not shrink the extent.
    RET  Z                              ; Equality already represents the maximum.
    LD   HL,(outAddr)                   ; Restore the current cursor after subtraction.
    LD   (outHigh),HL                   ; Publish the new ordinary high-water mark.
    RET                                 ; Leave the endpoint bits unchanged.
.endPoint: ; Represent the greatest possible extent with an endpoint flag.
    XOR  A                              ; Mathematical $10000 has a zero low word.
    LD   (outHigh),A                    ; Store the endpoint's low byte.
    LD   (outHigh+1),A                  ; Store its high byte as well.
    LD   A,(outFlags)                   ; Preserve cursor and target endpoint markers.
    OR   outHiTop                       ; Mark high water as mathematical $10000.
    LD   (outFlags),A                   ; Keep the endpoint explicit for COMMIT.
    RET                                 ; The greatest possible Z80 endpoint is retained.

outNoFit: ; Return the shared capacity-failure status.
    LD   A,outFull                      ; Identify target-capacity exhaustion.
    SCF                                 ; Mark the operation as failed.
    RET                                 ; Leave every output field unchanged.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Encode and emit the parsed instruction at IX. The encoder commits into the
; private four-byte buffer. Output and pending capacity are both proved before
; the first IMAGE operation is submitted.

outEmitI: ; Encode and preflight an instruction before byte submission.
    LD   HL,(outAddr)                   ; Capture instruction start address.
    LD   (outStart),HL                  ; Keep it for fields and pending records.
    LD   DE,outBytes                    ; Point at private encoder buffer.
    CALL enEmit                         ; Validate and encode the parsed record at IX.
    RET  C                              ; Publish nothing when the form is invalid.
    LD   (outLen),A                     ; Save encoded length, one to four bytes.

; Prove both remaining capacity and the absolute target extent before emit.

    LD   L,A                            ; Pass the short encoded length as a word request.
    LD   H,0                            ; Zero-extend its one-byte encoder result.
    CALL outCapOk                       ; Check the whole instruction without mutation.
    JR   C,.noCap                       ; Reject before emitting any encoded byte.
.checkRef: ; Check pending storage after output capacity.
    CALL refCheck                       ; Check every unresolved field.
    RET  C                              ; Return before instruction emission.

; Emit the exact encoded byte sequence. A sink failure leaves only already
; accepted tentative IMAGE operations. No pending reference is queued yet.

    XOR  A                              ; Start the encoded-buffer index at zero.
    LD   (outIndex),A                   ; Store the index across host service calls.
.loop: ; Emit one encoded byte per iteration.
    LD   A,(outLen)                     ; Load the total encoded instruction length.
    LD   B,A                            ; Keep the loop limit in B.
    LD   A,(outIndex)                   ; Load the next buffer index.
    CP   B                              ; Test whether every encoded byte was accepted.
    JR   Z,.done                        ; Queue pending fields only after full emission.
    LD   E,A                            ; Move the unsigned index into DE.
    LD   D,0                            ; Zero-extend the index for address arithmetic.
    LD   HL,outBytes                    ; Point at the start of the encoded byte buffer.
    ADD  HL,DE                          ; Select the byte at the current index.
    LD   A,(HL)                         ; Load the byte to submit as IMAGE data.
    CALL outSendB                       ; Emit it and commit one cursor step.
    RET  C                              ; Let the driver abort any partial instruction.
    LD   HL,outIndex                    ; Address the stored scan index.
    INC  (HL)                           ; Advance to the next encoded byte.
    JR   .loop                          ; Continue until the saved length is reached.
.done: ; Every instruction byte is now tentative output.

; Queue deferred references after every byte succeeds. Patch addresses are
; derived from the instruction start saved before encoding.

    LD   DE,(outStart)                  ; Supply the instruction base for field addresses.
    JP   refQueue                       ; Queue all deferred fields and return its status.
.noCap: ; Reject an instruction that cannot fit.
    LD   A,outFull                      ; Select the capacity status code.
    SCF                                 ; Mark the instruction emission as failed.
    RET                                 ; Return without submitting the first byte.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve pending records for the symbol at IX. Each loop peeks a record,
; computes and submits its final bytes, then removes that record.

outFixUp: ; Resolve and submit each pending field for the defined symbol.
; Resolution is valid only after the symbol has a final value.

    BIT  6,(IX+5)                       ; Test the symbol record's defined flag.
    JP   Z,outFault                     ; Reject an undefined-symbol request.
    PUSH IX                             ; Transfer symbol pointer via stack.
    POP  HL                             ; Recover pointer in storable HL.
    LD   (outSym),HL                    ; Preserve it while pending records are inspected.
.loop: ; Resolve one matching field per loop.
    LD   IX,(outSym)                    ; Restore the symbol record expected by syPeek.
;@EXPECTOUT A,CARRY,BC,DE
    CALL syPeek                         ; Find the next unresolved field for this symbol.
    JP   C,.peekFail                    ; Check exhaustion or failure.
    LD   (outRec),IX                    ; Name this record if its patch fails.
    LD   (outField),DE                  ; Save the field's logical patch address.
    LD   A,B                            ; Copy the field's kind-and-anchor metadata byte.
    AND  syKindLo                       ; Retain only the patch-transform bits.
    LD   (outKind),A                    ; Save transform across later calls.
    LD   A,C                            ; Fetch the pending signed eight-bit addend.
    LD   (outDelta),A                   ; Preserve it for 24-bit value construction.

; Sign-extend the symbol value to 24 bits when its equate carries syFSign.

    LD   IX,(outSym)                    ; Return to the defined symbol record.
    LD   L,(IX+syValLo)                 ; Load the low byte of its stored value.
    LD   H,(IX+syValHi)                 ; Load the high byte of its stored value.
    XOR  A                              ; Assume a non-negative 24-bit extension byte.
    BIT  5,(IX+5)                       ; Test the equate's signed-value flag.
    JR   Z,.extReady                    ; Zero-extend labels and unsigned values.
    DEC  A                              ; Use FF to sign-extend a signed equate.
.extReady: ; A now holds the symbol's extension byte.
    LD   (outSymHi),A                   ; Save it for the high stage of the addition.

; Sign-extend the pending one-byte addend and add it to the 24-bit base. The
; third byte retains overflow information for the domain/range checks below.

    LD   A,(outDelta)                   ; Reload the pending record's addend byte.
    LD   C,A                            ; Place its low byte in C for addition.
    LD   D,0                            ; Assume the addend is non-negative.
    BIT  7,C                            ; Inspect the signed addend's sign bit.
    JR   Z,.addReady                    ; Keep a zero extension for 0..127.
    DEC  D                              ; Use FF to sign-extend -128..-1.
.addReady: ; C holds the addend. D holds its sign extension.
    LD   A,L                            ; Begin with the symbol value's low byte.
    ADD  A,C                            ; Add the pending low-byte adjustment.
    LD   (outValue),A                   ; Store the final low byte.
    LD   A,H                            ; Continue with the symbol value's high byte.
    ADC  A,D                            ; Add the extension and propagated carry.
    LD   (outValue+1),A                 ; Store the final high byte.
    LD   A,(outSymHi)                   ; Load the symbol's 24-bit extension byte.
    ADC  A,D                            ; Complete the signed 24-bit sum.
    LD   (outValue+2),A                 ; Retain its domain and overflow evidence.
    CALL outValOk                       ; Require the supported -32768..65535 domain.
    RET  C                              ; Keep record on invalid value.

; Dispatch patch transform. Truncate and LOW select the low byte.
; HIGH selects the second byte. Byte, displacement and relative forms enforce
; their distinct ranges before submission.

    LD   A,(outKind)                    ; Load the retained patch-transform kind.
    CP   fixByte                        ; Is this a range-checked immediate byte?
    JR   Z,.byte                        ; Validate 0..255 before submission.
    CP   fixWord                        ; Is this a complete little-endian word?
    JR   Z,.fullWord                    ; Submit both low sixteen-bit bytes.
    CP   fixRel                         ; Is this a PC-relative displacement?
    JR   Z,.rel                         ; Convert the target into a signed offset.
    CP   fixDisp                        ; Is this an indexed signed displacement?
    JR   Z,.disp                        ; Enforce the -128..127 domain.
    CP   fixTrunc                       ; Is this an explicit truncating byte transform?
    JR   Z,.lowB                        ; Select the low byte without a range check.
    CP   fixLow                         ; Is this the LOW transform?
    JR   Z,.lowB                        ; Select the low byte without a range check.
    CP   fixHigh                        ; Is this the HIGH transform?
    JP   NZ,outFault                    ; Reject an unknown pending-record kind.
.highB: ; Select the high byte of the resolved value.
    LD   A,(outValue+1)                 ; Load bits 8..15 for a HIGH patch.
    JR   .patchB                        ; Submit the selected byte.
.byte: ; Validate an ordinary unsigned byte field.

; An ordinary byte patch accepts only 0..255.

    LD   A,(outValue+2)                 ; Inspect the 24-bit extension byte.
    OR   A                              ; It must be zero for an unsigned byte.
    JR   NZ,outBound                    ; Reject negative or overflowing values.
    LD   A,(outValue+1)                 ; Inspect bits 8..15.
    OR   A                              ; They must also be zero.
    JR   NZ,outBound                    ; Reject values above 255.
    JR   .lowB                          ; Submit the already validated low byte.
.disp: ; Validate a signed indexed displacement.

; Indexed displacement accepts a fully sign-extended -128..-1 or 0..127.

    LD   A,(outValue+2)                 ; Inspect the sign-extension byte.
    OR   A                              ; Zero selects the non-negative half.
    JR   Z,.dispPos                     ; Validate 0..127 separately.
    INC  A                              ; FF becomes zero only for a negative extension.
    JR   NZ,outBound                    ; Reject every other upper byte.
    LD   A,(outValue+1)                 ; Inspect the middle byte of a negative value.
    INC  A                              ; It too must be FF.
    JR   NZ,outBound                    ; Reject values below the signed-byte domain.
    LD   A,(outValue)                   ; Inspect the candidate displacement byte.
    BIT  7,A                            ; A negative byte must have its sign bit set.
    JR   Z,outBound                     ; Reject -256..-129 aliases.
    JR   .lowB                          ; Submit the valid negative displacement.
.dispPos: ; Validate the non-negative signed-byte half.
    LD   A,(outValue+1)                 ; Inspect bits 8..15.
    OR   A                              ; They must be zero for 0..127.
    JR   NZ,outBound                    ; Reject values above 255 immediately.
    LD   A,(outValue)                   ; Load the candidate positive displacement.
    BIT  7,A                            ; Its sign bit must remain clear.
    JR   NZ,outBound                    ; Reject 128..255.
    JR   .lowB                          ; Submit the valid non-negative displacement.
.rel: ; Convert an absolute target to a relative field.

; Relative fields store target-(patch-address+1). Subtraction wraps at 16 bits
; with the Z80 program counter before the signed-byte range check.

    LD   HL,(outValue)                  ; Load the resolved absolute target address.
    LD   DE,(outField)                  ; Load the address of the relative field byte.
    INC  DE                             ; Form the address immediately after that field.
    OR   A                              ; Clear carry before target-base subtraction.
    SBC  HL,DE                          ; Calculate the wrapped sixteen-bit displacement.
    LD   A,H                            ; Inspect the displacement's high byte.
    OR   A                              ; Zero selects the non-negative half.
    JR   Z,.relPos                      ; Validate 0..127 separately.
    INC  A                              ; FF is required for a negative signed byte.
    JR   NZ,outReach                    ; Reject high bytes other than 00 or FF.
    BIT  7,L                            ; Confirm the low byte is actually negative.
    JR   Z,outReach                     ; Reject wrapped values outside -128..-1.
    LD   A,L                            ; Select the valid negative displacement byte.
    JR   .patchB                        ; Submit it as the resolved patch.
.relPos: ; Validate a non-negative relative displacement.
    BIT  7,L                            ; Its sign bit must remain clear.
    JR   NZ,outReach                    ; Reject 128..255.
    LD   A,L                            ; Select the valid positive displacement byte.
    JR   .patchB                        ; Submit it as the resolved patch.
.lowB: ; Select the low byte of the resolved value.
    LD   A,(outValue)                   ; Load bits 0..7 for byte and LOW transforms.
.patchB: ; Submit the selected single-byte patch value.

; Submit a one-byte PATCH at the saved logical field address. C=0 is the base
; output class. Do not remove the pending record if the sink rejects it.

    LD   HL,(outField)                  ; Restore the pending field's logical address.
    LD   C,0                            ; Select the base output class.
    CALL hsPatchB                       ; Ask the sink to accept the final patch byte.
    JR   C,outDeny                      ; Preserve the pending record on rejection.
    JR   .remove                        ; Remove the record only after sink acceptance.
.fullWord: ; Submit a complete little-endian word patch.

; Word patches submit the checked low sixteen bits little-endian.

    LD   HL,(outValue)                  ; Supply the resolved low sixteen-bit value.
    LD   DE,(outField)                  ; Supply the logical field address.
    LD   C,0                            ; Select the base output class.
    CALL hsPatchW                       ; Ask the sink to accept both patch bytes.
    JR   C,outDeny                      ; Keep the pending record if submission fails.
.remove: ; Reclaim the record for an accepted patch.

; Sink acceptance makes removal safe. syTake preserves metadata from
; syPeek while compacting the pending arena.

    LD   IX,(outSym)                    ; Restore the defined symbol record.
;@EXPECTOUT A,CARRY,BC,DE
    CALL syTake                         ; Remove record returned by syPeek.
    JR   C,outFault                     ; Peek/take disagreement is internal.
    JP   .loop                          ; Look for another field referencing this symbol.
.peekFail: ; Interpret the status returned by syPeek.

; syPeek reports syMiss when no matching record remains. Translate that
; exhaustion status to successful completion of this symbol's resolution loop.

    CP   syMiss                         ; Is this normal end-of-list rather than an error?
    RET  NZ                             ; Return an unexpected status unchanged in A.
    XOR  A                              ; Translate exhaustion into successful completion.
    RET                                 ; Return after every matching patch was submitted.
outBound: ; Return the concrete-value range failure.
    LD   HL,(outValue)                  ; Publish the rejected value for the message.
    LD   (outCause),HL                  ; Keep it with the failure.
    LD   A,outRange                     ; Select the value-range status code.
    SCF                                 ; Mark resolution as failed.
    RET                                 ; Leave the current pending record intact.
outReach: ; Return the relative-displacement range failure.
    LD   (outCause),HL                  ; Publish the rejected displacement in HL.
    LD   A,outFar                       ; Select the relative-range status code.
    SCF                                 ; Mark resolution as failed.
    RET                                 ; Preserve the unresolved pending record.
outDeny: ; Return a rejected sink operation.
    LD   (outBadOp),A                   ; Mark the failure as the sink's own.
    SCF                                 ; Mark the operation as failed.
    RET                                 ; Return the sink's status unchanged in A.
outFault: ; Return an internal-consistency failure.
    LD   A,outInvar                     ; Select the invariant status code.
    SCF                                 ; Mark the impossible state as failed.
    RET                                 ; Return for driver-level abort and diagnosis.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
; Require the signed/unsigned word domain -32768..65535. A zero top
; byte admits nonnegative words. FF is valid only with bit 15 set.

outValOk: ; Check the resolved 24-bit value fits a signed or unsigned word.
    LD   A,(outValue+2)                 ; Inspect the 24-bit extension byte.
    OR   A                              ; Zero admits every unsigned sixteen-bit value.
    RET  Z                              ; Return success with carry clear for 0..65535.
    INC  A                              ; FF becomes zero for a negative sign extension.
    JR   NZ,outBound                    ; Reject values outside both supported extensions.
    LD   A,(outValue+1)                 ; Inspect the sign bit of the low sixteen bits.
    BIT  7,A                            ; Negative-domain values require bit 15 set.
    RET  NZ                             ; Accept -32768..-1 with carry still clear.
    JR   outBound                       ; Reject sign-extended values below -32768.
outEnd: ; Mark the end of executable output code.
outRamLo: ; Begin the output module's fixed workspace.

; Fixed workspace is 26 bytes: seven for target geometry, four for
; cursor/capacity, five for sink and failure details and ten shared by
; instruction emission and patch-resolution scratch.

; Statements call outEmitI and outFixUp in sequence, never nested, so
; their scratch lifetimes do not overlap.

outAddr:    DW      0                   ; Current logical target address.
outLeft:     DW      0                  ; Remaining bytes in the initial target interval.
outBase:    DW      0                   ; Inclusive lower target address.
outLimit:     DW      0                 ; Low word of the exclusive target endpoint.
outHigh:    DW      0                   ; Low word of the exclusive high-water endpoint.
outBadOp:   DB      0                   ; Nonzero after the sink rejects an operation.
outRec:    DW      0                    ; Pending record whose patch was attempted.
outCause:    DW      0                  ; Value or offset of a range failure.
outFlags:   DB      0                   ; Cursor, high-water and target endpoint bits.
.scratch:   DS      10                  ; Instruction/patch scratch overlay.
outStart    EQU     .scratch            ; Instruction start address during emission.
outBytes    EQU     .scratch+2          ; Four-byte encoder destination buffer.
outLen      EQU     .scratch+6          ; Encoded instruction length.
outIndex    EQU     .scratch+7          ; Current index within the encoder buffer.
outSym      EQU     .scratch            ; Defined symbol-record pointer during resolution.
outField    EQU     .scratch+2          ; Address of the pending field being patched.
outKind     EQU     .scratch+4          ; Pending field transform kind.
outDelta    EQU     .scratch+5          ; Signed one-byte pending addend.
outValue    EQU     .scratch+6          ; Three-byte resolved value with domain evidence.
outSymHi    EQU     .scratch+9          ; Sign-extension byte for the symbol base value.
outRamHi: ; End the fixed workspace extent.
