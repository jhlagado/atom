;=============================================================================
;  Instruction-form normalisation and validation
;=============================================================================
;
;  PURPOSE
;  -------
;  Turn the parser's provisional operand record into the form consumed by the
;  encoder. Resolve source conveniences, select an accepted form and check its
;  concrete ranges before preparing private deferred-reference records.
;
;  MODULE BOUNDARY
;  ---------------
;
;  This is an internal continuation of parser.asm. .PARSED calls the pipeline
;  below after syntax parsing succeeds. refs.asm owns deferred-reference
;  publication, final commit, diagnostics, tables and shared parser workspace.
;
;  INTERNAL PIPELINE
;  -----------------
;
;  PR_ALIAS handles accumulator aliases. PR_CLASS assigns provisional numeric
;  classes. PR_FORM chooses a form; PR_RANGE checks its concrete values.
;  PR_BIND in refs.asm then prepares deferred references.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  The module uses fixed parser workspace declared in refs.asm. Calls preserve
;  stack balance, may clobber the registers named by each routine contract and
;  are not reentrant. Form failures publish a source position without changing
;  the caller's destination record.
;

;@ROUTINE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,HL,ZERO,BC,DE
; Normalise the optional explicit accumulator used by the ALU mnemonic family.
; ADD, ADC and SBC require an explicit accumulator when using their eight-bit
; form. Any two-operand ALU form whose first operand is A is collapsed to the
; encoder's canonical one-operand record.

PR_ALIAS: ; Collapse an explicit A into the canonical byte-ALU operand.
    LD   A,(PR_REC+EN_MNEM)             ; Read the current mnemonic ordinal.
    CP   AT_MADD                        ; Is it below the contiguous ALU family?
    JR   C,.DONE                        ; Leave non-ALU instructions unchanged.
    CP   AT_MCP+1                       ; Is it above the last ALU mnemonic?
    JR   NC,.DONE                       ; Leave non-ALU instructions unchanged.
    LD   A,(PR_OPCNT)                   ; Read the parsed operand count.
    CP   1                              ; Does the source contain one operand?
    JR   NZ,.TWOOPS                     ; Two operands may contain explicit A.

; A one-operand ADD/ADC/SBC is invalid because it omits the explicit A.

    LD   A,(PR_REC+EN_MNEM)             ; Recover the one-operand ALU mnemonic.
    CP   AT_MADD                        ; ADD requires an explicit accumulator.
    JR   Z,.NEEDA                       ; Reject the omitted accumulator.
    CP   AT_MADC                        ; ADC has the same source requirement.
    JR   Z,.NEEDA                       ; Reject the omitted accumulator.
    CP   AT_MSBC                        ; SBC also requires the explicit A.
    JR   NZ,.DONE                       ; Other one-operand forms are canonical.
.NEEDA: ; Diagnose a byte ADD/ADC/SBC with the required A omitted.
    LD   A,PR_SFORM                     ; Select the invalid-form status.
    JP   PR_FBEG                        ; Diagnose it at the mnemonic position.
.TWOOPS: ; Check whether two ALU operands qualify for accumulator collapse.
    CP   2                              ; Only two operands qualify for collapse.
    JR   NZ,.DONE                       ; Leave every other arity unchanged.
    LD   A,(PR_REC+EN_OP0)              ; Inspect the first operand class.
    CP   EN_A                           ; Is the explicit destination A?
    JR   NZ,.DONE                       ; Preserve another destination.
    LD   A,(PR_REC+EN_OP1)              ; Load the source operand class to move.

; Shift operand 1's class and value into operand 0, then clear operand 1 and
; reduce the arity to one.

    LD   (PR_REC+EN_OP0),A              ; Move the source class into slot zero.
    LD   HL,(PR_REC+EN_VAL1)            ; Load source operand one's value.
    LD   (PR_REC+EN_VAL0),HL            ; Move it into canonical value slot zero.
    LD   A,EN_NONE                      ; Prepare the absent-operand class.
    LD   (PR_REC+EN_OP1),A              ; Clear the former source class.
    XOR  A                              ; Prepare zero bytes and count base.
    LD   (PR_REC+EN_VAL1),A             ; Clear the former value's low byte.
    LD   (PR_REC+EN_VAL1+1),A           ; Clear the former value's high byte.
    INC  A                              ; The canonical record has one operand.
    LD   (PR_OPCNT),A                   ; Publish its reduced arity.

; If operand one held a deferred reference, retarget it to operand zero and
; shift the unresolved mask to match the canonical record.

    LD   A,(PR_UMASK)                   ; Read the unresolved-operand mask.
    AND  2                              ; Did operand one carry a reference?
    JR   Z,.DONE                        ; No reference metadata needs remapping.
    LD   A,1                            ; Operand zero is now unresolved instead.
    LD   (PR_UMASK),A                   ; Publish the shifted mask.
    CALL .REMAP                         ; Retarget matching build records.
.DONE: ; Return successful normalisation with carry clear.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Continue with numeric normalisation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS B,SIGN,PARITY,HALFCARRY,DE,HL,A
; Retarget build-reference operand 1 to 0 after accumulator-alias collapse.

.REMAP: ; Move deferred metadata from operand one to operand zero.
    XOR  A                              ; Start at build-reference index zero.
    LD   B,A                            ; B is the current record index.
.LOOP: ; Scan the private deferred-reference records.
    LD   A,(PR_BRCNT)                   ; Read the private record count.
    CP   B                              ; Have all records been visited?
    RET  Z                              ; Return when index equals count.
    LD   A,B                            ; Select the current build record.
    CALL PR_BRADR                       ; Return its base address in DE.
    LD   HL,PR_BOPER                    ; Load the operand-index field offset.
    ADD  HL,DE                          ; Address that field in the record.
    LD   A,(HL)                         ; Read the referenced operand index.
    CP   1                              ; Did it name removed operand one?
    JR   NZ,.NEXT                       ; Leave other references untouched.
    LD   (HL),0                         ; Retarget it to canonical operand zero.
.NEXT: ; Advance after retargeting or retaining this reference.
    INC  B                              ; Advance to the next build record.
    JR   .LOOP                          ; Continue within the proved count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Resolve provisional numeric classes after the mnemonic and complete operand
; list are known. FMASK tracks byte candidates that may widen; CMASK tracks C
; operands that could also mean condition C.

PR_CLASS: ; Classify numeric operands and record ambiguous C alternatives.
    XOR  A                              ; Initialise pass masks and index.
    LD   (PR_FMASK),A                   ; No numeric operand is flexible yet.
    LD   (PR_CMASK),A                   ; No C operand is ambiguous yet.
    LD   (PR_OPIDX),A                   ; Begin with operand index zero.
.LOOP: ; Visit each operand within the parsed count.
    LD   A,(PR_OPIDX)                   ; Load the current operand index.
    LD   B,A                            ; Keep it across the count load.
    LD   A,(PR_OPCNT)                   ; Read the number of parsed operands.
    CP   B                              ; Has the loop reached that count?
    RET  Z                              ; Return after the final operand.
    LD   A,B                            ; Restore the current operand index.
    CALL PR_SLOT                        ; Select its class and value slots.
    LD   HL,(PR_CPTR)                   ; Address the provisional class.
    LD   A,(HL)                         ; Read that class.
    CP   PR_GC                          ; Is it ambiguous register/condition C?
    JR   Z,.REGC                        ; Record both possible meanings.
    CP   PR_GPNUM                       ; Is it a parenthesised generic number?
    JR   Z,.PAREN                       ; Choose memory or immediate-port class.
    CP   PR_GNUM                        ; Is it a bare generic number?
    JR   NZ,.NEXT                       ; Fixed classes need no conversion.
    CALL .BARE                          ; Classify the bare numeric operand.
    RET  C                              ; Preserve an enum range error.
    JR   .NEXT                          ; Advance after classification.
.REGC: ; Start with register C and retain condition C as an alternative.

; Prefer register C initially and record the alternative condition meaning for
; candidate validation.

    LD   (HL),EN_C                      ; Prefer ordinary register C initially.
    LD   A,(PR_OPIDX)                   ; Recover its operand index.
    CALL PR_MASK                        ; Convert the index to a one-hot bit.
    LD   HL,PR_CMASK                    ; Address the condition-candidate mask.
    OR   (HL)                           ; Preserve any earlier ambiguous C.
    LD   (HL),A                         ; Mark this operand as a candidate.
    JR   .NEXT                          ; Continue with the next operand.
.PAREN: ; Select absolute memory or an immediate I/O port.

; Parenthesised numbers mean absolute memory, except IN and OUT use them as an
; immediate eight-bit port.

    LD   A,(PR_REC+EN_MNEM)             ; Read the instruction mnemonic.
    CP   AT_MIN                         ; Does IN use an immediate port number?
    JR   Z,.PORT                        ; Require an unsigned byte port.
    CP   AT_MOUT                        ; Does OUT use an immediate port number?
    JR   Z,.PORT                        ; Require an unsigned byte port.
    LD   HL,(PR_CPTR)                   ; Reopen the selected class slot.
    LD   (HL),EN_MABS                   ; Otherwise use absolute memory.
    JR   .NEXT                          ; Continue with the next operand.
.PORT: ; Check the concrete port number before selecting imm8.
    CALL PR_BYTE                        ; Require a byte-sized concrete port.
    RET  C                              ; Return its value-range diagnostic.
    LD   HL,(PR_CPTR)                   ; Reopen the selected class slot.
    LD   (HL),EN_IMM8                   ; Use the immediate-byte port class.
.NEXT: ; Advance to the next operand class slot.
    LD   HL,PR_OPIDX                    ; Address the operand scan index.
    INC  (HL)                           ; Advance to the next operand.
    JR   .LOOP                          ; Repeat within the parsed operand count.

;@ROUTINE OUT A,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Convert one bare generic number according to its mnemonic and operand index.
; Enumerated operands encode their value in the class itself. Branch targets
; select word or relative classes; other numbers begin as flexible imm8.

.BARE: ; Select an enum, branch target or flexible numeric class.
    LD   A,(PR_REC+EN_MNEM)             ; Read the value's mnemonic context.
    CP   AT_MIM                         ; Does IM require an enumerated mode?
    JR   Z,.IMMODE                      ; Convert values 0..2 into IM classes.
    CP   AT_MRST                        ; Does RST require an enumerated vector?
    JR   Z,.RSTVEC                      ; Convert eight legal vectors to classes.
    CP   AT_MBIT                        ; Is the mnemonic below BIT/RES/SET?
    JR   C,.BRANCH                      ; Try branch and general numbers.
    CP   AT_MSET+1                      ; Is it in the BIT through SET family?
    JR   C,.BITNUM                      ; Classify operand zero as a bit number.
.BRANCH: ; Choose absolute words for JP/CALL or relative bytes for JR/DJNZ.

; Absolute JP and CALL retain the target word. JR and DJNZ are converted to a
; signed displacement only after the final instruction length is known.

    LD   A,(PR_REC+EN_MNEM)             ; Reload the mnemonic for branch classes.
    CP   AT_MJP                         ; JP targets are absolute words.
    JR   Z,.WORD                        ; Select the immediate-word class.
    CP   AT_MCALL                       ; CALL targets are also absolute words.
    JR   Z,.WORD                        ; Select the immediate-word class.
    CP   AT_MJR                         ; JR targets become relative bytes.
    JR   Z,.RELATIVE                    ; Defer displacement calculation.
    CP   AT_MDJNZ                       ; DJNZ uses the same relative form.
    JR   Z,.RELATIVE                    ; Defer displacement calculation.
    CP   AT_MOUT                        ; OUT admits the special literal zero.
    JR   NZ,.FLEXIBLE                   ; Other numbers start as flexible bytes.

; OUT (C),0 has a dedicated class. Other OUT values remain bytes and are
; checked by the complete form.

    CALL PR_LOAD                        ; Load the concrete OUT operand value.
    LD   A,H                            ; Combine both bytes to test for zero.
    OR   L                              ; Z means the complete word is zero.
    JR   NZ,.FLEXIBLE                   ; Nonzero uses ordinary byte handling.
    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   (HL),EN_ZERO                   ; Encode the dedicated OUT (C),0 class.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The zero word is already canonical.
.IMMODE: ; Map interrupt mode 0..2 into an operand class.

; IM accepts only the enumerated values 0, 1 and 2.

    CALL PR_LOAD                        ; Load the requested interrupt mode.
    LD   A,H                            ; A legal mode has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,PR_FVRNG                    ; Reject a nonzero high byte.
    LD   A,L                            ; Recover the low-byte mode number.
    CP   3                              ; Modes 0, 1 and 2 are the entire domain.
    JP   NC,PR_FVRNG                    ; Reject mode 3 or above.
    ADD  A,EN_IM0                       ; Convert the value to its enum class.
    JR   .ENUM                          ; Store class and clear its value.
.RSTVEC: ; Map an aligned restart vector 0..56 into its class.

; RST vectors run from 0 to 56 by eights. Divide the vector value by eight to
; obtain its class index, then add the first restart class.

    CALL PR_LOAD                        ; Load the requested restart vector.
    LD   A,H                            ; A legal vector has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,PR_FVRNG                    ; Reject a value above 255 immediately.
    LD   A,L                            ; Recover the low-byte vector address.
    CP   57                             ; The largest legal vector is 56.
    JP   NC,PR_FVRNG                    ; Reject 57 and above.
    AND  7                              ; Legal vectors are multiples of eight.
    JP   NZ,PR_FVRNG                    ; Reject a non-aligned vector.
    LD   A,L                            ; Reload the validated vector.
    RRCA                                ; Shift the aligned vector right once.
    RRCA                                ; The value is now vector / 4.
    RRCA                                ; Vector / 8 gives restart index 0..7.
    AND  7                              ; Keep the three-bit restart index.
    ADD  A,EN_RST0                      ; Convert the index to its restart class.
    JR   .ENUM                          ; Store class and clear its value.
.BITNUM: ; Map operand zero of BIT/RES/SET into bit class 0..7.

; BIT, RES and SET encode their first operand in the class and require 0..7.

    LD   A,(PR_OPIDX)                   ; Read this numeric operand's index.
    OR   A                              ; Is it operand zero, the bit number?
    JR   NZ,.FLEXIBLE                   ; Later operands use ordinary handling.
    CALL PR_LOAD                        ; Load the requested bit number.
    LD   A,H                            ; A legal bit has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,PR_FVRNG                    ; Reject values above 255.
    LD   A,L                            ; Recover the low-byte bit number.
    CP   8                              ; Bit numbers range from zero to seven.
    JP   NC,PR_FVRNG                    ; Reject eight and above.
    ADD  A,EN_BIT0                      ; Convert the number to its enum class.
.ENUM: ; Store the enum class and clear its redundant value word.

; The enum class carries the value, so clear its redundant word slot.

    LD   HL,(PR_CPTR)                   ; Address the selected operand class.
    LD   (HL),A                         ; Store the value-bearing enum class.
    CALL PR_CLEAR                       ; Clear the now-redundant value word.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Continue with the next operand.
.WORD: ; Keep an absolute branch target as an immediate word.
    LD   HL,(PR_CPTR)                   ; Address the selected operand class.
    LD   (HL),EN_IMM16                  ; Mark an absolute sixteen-bit target.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the target value word.
.RELATIVE: ; Retain the target until the final instruction length is known.
    LD   HL,(PR_CPTR)                   ; Address the selected operand class.
    LD   (HL),EN_REL8                   ; Mark a relative target.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the absolute target for now.
.FLEXIBLE: ; Try imm8 first and retain a possible imm16 alternative.

; Start with imm8 and mark this operand in FMASK. If no byte form validates,
; PR_WIDEN widens marked values to imm16 and retries.

    LD   HL,(PR_CPTR)                   ; Address the selected operand class.
    LD   (HL),EN_IMM8                   ; Try the shortest numeric class first.
    LD   A,(PR_OPIDX)                   ; Recover the operand index.
    CALL PR_MASK                        ; Convert it to a one-hot bit.
    LD   HL,PR_FMASK                    ; Address the flexible-value mask.
    OR   (HL)                           ; Preserve earlier flexible operands.
    LD   (HL),A                         ; Mark this one for possible widening.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Validation chooses the final width.

;@ROUTINE OUT HL CLOBBERS A
; Load the selected operand's little-endian word into HL.

PR_LOAD: ; Read the selected little-endian operand word into HL.
    LD   HL,(PR_VPTR)                   ; Load the selected value-slot address.
    LD   A,(HL)                         ; Read its little-endian low byte.
    INC  HL                             ; Advance to the high byte.
    LD   H,(HL)                         ; Place the high byte in H.
    LD   L,A                            ; Complete the value in HL.
    RET                                 ; Return the concrete operand word.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Clear the selected value once its information has moved into an enum class.

PR_CLEAR: ; Erase the value word after its enum class carries the value.
    LD   HL,(PR_VPTR)                   ; Load the selected value-slot address.
    XOR  A                              ; Prepare a zero for both bytes.
    LD   (HL),A                         ; Clear the low byte.
    INC  HL                             ; Advance to the high byte.
    LD   (HL),A                         ; Clear the high byte.
    RET                                 ; The class now carries the value.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require the selected value to fit unsigned eight-bit range.

PR_BYTE: ; Require the selected word to be within 0..255.
    CALL PR_LOAD                        ; Load the selected concrete value.
    LD   A,H                            ; An unsigned byte needs high byte zero.
    OR   A                              ; Set Z when the value is within 0..255.
    RET  Z                              ; Return success with carry clear.
    JP   PR_FVRNG                       ; Report an out-of-range value otherwise.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return a one-hot bit for operand index A: 0 -> 1, 1 -> 2, 2 -> 4.

PR_MASK: ; Convert operand index 0, 1 or 2 into bit 1, 2 or 4.
    OR   A                              ; Is the operand index zero?
    JR   NZ,.DOUBLE                     ; Double either nonzero index.
    INC  A                              ; Convert index zero to bit value one.
    RET                                 ; Return the one-hot mask.
.DOUBLE: ; Map either nonzero operand index to its mask bit.
    ADD  A,A                            ; Convert index one/two to bit two/four.
    RET                                 ; Return the one-hot mask.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Select an encoder-valid interpretation for the normalised record. Candidate
; order is provisional classes, ambiguous C as condition, widened numeric
; classes, then condition alternatives for the widened record. Success returns
; the encoder-reported length in A.

PR_FORM: ; Try the candidate classes in a fixed order until one validates.
    CALL PR_TRY                         ; Try provisional register/byte classes.
    RET  NC                             ; Keep the first complete valid form.
    CALL PR_TRYCC                       ; Try each ambiguous C as condition C.
    RET  NC                             ; Keep the first valid condition form.
    LD   A,(PR_FMASK)                   ; Read the flexible numeric-operand mask.
    OR   A                              ; Can any byte class widen to a word?
    JR   Z,.INVALID                     ; No remaining form can validate.
    CALL PR_WIDEN                       ; Widen every marked byte candidate.
    CALL PR_TRY                         ; Validate the widened register-C form.
    RET  NC                             ; Keep it when valid.
    CALL PR_TRYCC                       ; Retry condition C after widening.
    RET  NC                             ; Keep the first complete valid form.
.INVALID: ; Report that no complete instruction form validated.
    LD   A,PR_SFORM                     ; Select invalid-form status.
    JP   PR_FBEG                        ; Diagnose it at the mnemonic position.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate the private instruction record without examining operand values.

PR_TRY: ; Validate the private record without reading numeric values.
    LD   IX,PR_REC                      ; Point IX at the private record.
    JP   EN_VFORM                       ; Return the encoder validator's result.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY,HL
; Try each operand marked in CMASK as condition C. Change one candidate at a
; time, restore register C after failure and stop at the first
; complete valid form.

PR_TRYCC: ; Try each ambiguous C as a condition and restore failed choices.
    XOR  A                              ; Begin with operand index zero.
    LD   (PR_OPIDX),A                   ; Publish the condition scan index.
.LOOP: ; Scan the three operand slots for a C ambiguity.
    LD   A,(PR_OPIDX)                   ; Load the current operand index.
    CP   3                              ; Have all three record slots been tried?
    JR   Z,.FAIL                        ; No condition form validated.
    LD   B,A                            ; Preserve index across conversion.
    CALL PR_MASK                        ; Convert the index to a one-hot mask.
    LD   HL,PR_CMASK                    ; Address the ambiguous-C mask.
    AND  (HL)                           ; Is this operand an ambiguity candidate?
    JR   Z,.NEXT                        ; Skip fixed operands.
    LD   A,B                            ; Restore the candidate operand index.
    CALL PR_SLOT                        ; Select its class slot.
    LD   HL,(PR_CPTR)                   ; Load the selected class address.
    LD   (HL),EN_CC                     ; Temporarily interpret C as condition C.
    PUSH HL                             ; Preserve the class address.
    CALL PR_TRY                         ; Test the complete modified record.
    POP  HL                             ; Recover it without changing flags.
    RET  NC                             ; Keep EN_CC when the form validates.
    LD   (HL),EN_C                      ; Restore register C after failure.
.NEXT: ; Advance past this fixed or rejected candidate.
    LD   HL,PR_OPIDX                    ; Address the condition scan index.
    INC  (HL)                           ; Advance to the next operand slot.
    JR   .LOOP                          ; Continue until a candidate validates.
.FAIL: ; Return failure with every rejected candidate restored to register C.
    SCF                                 ; Report every condition choice failed.
    RET                                 ; Ambiguous slots are register C again.

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,A
; Widen every flexible imm8 candidate to imm16 before the second validation
; pass. The chosen form determines each deferred reference's patch width.

PR_WIDEN: ; Convert all flexible byte classes to immediate-word classes.
    XOR  A                              ; Begin with operand index zero.
    LD   (PR_OPIDX),A                   ; Publish the widening scan index.
.LOOP: ; Scan all three slots for numeric widening candidates.
    LD   A,(PR_OPIDX)                   ; Load the current operand index.
    CP   3                              ; Have all record slots been visited?
    RET  Z                              ; Return after the final slot.
    LD   B,A                            ; Preserve index across conversion.
    CALL PR_MASK                        ; Convert the index to a one-hot mask.
    LD   HL,PR_FMASK                    ; Address the flexible-value mask.
    AND  (HL)                           ; Was this a byte candidate?
    JR   Z,.NEXT                        ; Leave fixed classes unchanged.
    LD   A,B                            ; Restore the flexible operand index.
    CALL PR_SLOT                        ; Select its class slot.
    LD   HL,(PR_CPTR)                   ; Load the selected class address.
    LD   (HL),EN_IMM16                  ; Widen it to a word immediate.
.NEXT: ; Advance after retaining or widening this operand.
    LD   HL,PR_OPIDX                    ; Address the widening scan index.
    INC  (HL)                           ; Advance to the next operand slot.
    JR   .LOOP                          ; Continue through the fixed three slots.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Check each resolved value against its selected class. UMASK bits mark
; placeholders checked after their symbols resolve.

PR_RANGE: ; Check concrete operands and defer unresolved placeholders.
    XOR  A                              ; Begin with operand index zero.
    LD   (PR_OPIDX),A                   ; Publish the concrete-value scan index.
.LOOP: ; Check each value within the parsed operand count.
    LD   A,(PR_OPIDX)                   ; Load the current operand index.
    LD   B,A                            ; Preserve it across the count load.
    LD   A,(PR_OPCNT)                   ; Read the number of parsed operands.
    CP   B                              ; Has the loop reached that count?
    RET  Z                              ; Return after the final value.
    LD   A,B                            ; Restore the current operand index.
    CALL PR_SLOT                        ; Select its class and value slots.
    LD   A,(PR_OPIDX)                   ; Reload the index for mask conversion.
    CALL PR_MASK                        ; Convert it to a one-hot bit.
    LD   HL,PR_UMASK                    ; Address the unresolved-value mask.
    AND  (HL)                           ; Is this value still a placeholder?
    JR   NZ,.NEXT                       ; Defer its range check until resolution.

; Word and absolute classes need no conversion. Byte, relative and indexed
; classes need the checks below.

    LD   HL,(PR_CPTR)                   ; Address the selected operand class.
    LD   A,(HL)                         ; Read the class that defines its range.
    CP   EN_IMM8                        ; Does it require an unsigned byte?
    JR   Z,.BYTE                        ; Check the value against 0..255.
    CP   EN_REL8                        ; Is it a relative-branch target?
    JR   Z,.RELATIVE                    ; Convert and check signed displacement.
    CP   EN_IIX                         ; Is it an IX signed displacement?
    JR   Z,.DISP                        ; Check the signed-byte representation.
    CP   EN_IIY                         ; Is it an IY signed displacement?
    JR   Z,.DISP                        ; Check the same signed-byte range.
.NEXT: ; Continue after accepting or deferring this value.
    LD   HL,PR_OPIDX                    ; Address the concrete-value scan index.
    INC  (HL)                           ; Advance to the next operand.
    JR   .LOOP                          ; Continue within the operand count.
.BYTE: ; Validate an unsigned immediate byte.
    CALL PR_BYTE                        ; Require an unsigned eight-bit value.
    RET  C                              ; Preserve the range diagnostic.
    JR   .NEXT                          ; Continue after a valid byte.
.DISP: ; Validate a sign-extended indexed displacement.

; IX/IY displacement accepts exactly -128..127 represented as a sign-extended
; word or a positive low byte.

    CALL PR_LOAD                        ; Load the signed displacement word.
    LD   A,H                            ; Inspect its sign-extension byte.
    OR   A                              ; Zero denotes a non-negative value.
    JR   Z,.DISPPOS                     ; Check the positive half separately.
    INC  A                              ; $FF wraps for negative candidates.
    JP   NZ,PR_FVRNG                    ; Reject any other high byte.
    BIT  7,L                            ; Negative low bytes need bit 7 set.
    JP   Z,PR_FVRNG                     ; Reject -256..-129 representations.
    JR   .NEXT                          ; Accept -128..-1 and continue.
.DISPPOS: ; Require a non-negative indexed displacement below 128.
    BIT  7,L                            ; Positive bytes must be below $80.
    JP   NZ,PR_FVRNG                    ; Reject 128..255.
    JR   .NEXT                          ; Accept 0..127 and continue.
.RELATIVE: ; Compute target minus the address following the instruction.

; Convert target to target-(instruction address+length). The 16-bit arithmetic
; wraps at $FFFF like the Z80 PC; the result must fit a signed byte.

    CALL PR_LOAD                        ; Load the absolute branch target.
    LD   DE,(PR_IADR)                   ; Load the instruction's logical address.
    LD   A,(PR_ILEN)                    ; Read its validated encoded length.
    ADD  A,E                            ; Add length to the address low byte.
    LD   E,A                            ; Store the next-PC low byte.
    JR   NC,.BASE                       ; Skip when no carry occurred.
    INC  D                              ; Carry into the address high byte.
.BASE: ; Subtract the computed next PC from the absolute target.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Subtract the next-instruction address.
    LD   A,H                            ; Inspect the displacement high byte.
    OR   A                              ; Zero means non-negative displacement.
    JR   Z,.RELPOS                      ; Check the positive half separately.
    INC  A                              ; $FF wraps for negative candidates.
    JP   NZ,PR_FRRNG                    ; Reject missing sign extension.
    BIT  7,L                            ; Negative bytes need bit 7 set.
    JP   Z,PR_FRRNG                     ; Reject values below -128.
    JR   .RELSTORE                      ; Accept -128..-1.
.RELPOS: ; Require a non-negative branch displacement below 128.
    BIT  7,L                            ; Positive bytes must be below $80.
    JP   NZ,PR_FRRNG                    ; Reject displacements above 127.
.RELSTORE: ; Replace the target word with the validated displacement.

; Replace the absolute target with the encoded displacement for EN_EMIT.

    CALL PR_STORE                       ; Store the signed displacement word.
    JR   .NEXT                          ; Continue checking later operands.
