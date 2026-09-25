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
;  This is an internal continuation of parser.asm. PR_POPE1 calls the pipeline
;  below after syntax parsing succeeds. refs.asm owns deferred-reference
;  publication, final commit, diagnostics, tables and shared parser workspace.
;
;  INTERNAL PIPELINE
;  -----------------
;
;  PR_NAALI handles accumulator aliases. PR_NNUMB assigns provisional numeric
;  classes. PR_VCAND chooses a form; PR_CCVAL checks its concrete values.
;  PR_FREFE in refs.asm then prepares deferred references.
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

PR_NAALI:
    LD   A,(PR_SCRAT+EN_MNEM)       ; Read the current mnemonic ordinal.
    CP   AT_MADD                     ; Is it below the contiguous ALU family?
    JR   C,.ASUCCESS                 ; Leave non-ALU instructions unchanged.
    CP   AT_MCP+1                    ; Is it above the last ALU mnemonic?
    JR   NC,.ASUCCESS                ; Leave non-ALU instructions unchanged.
    LD   A,(PR_OPCNT)                ; Read the parsed operand count.
    CP   1                           ; Does the source contain one operand?
    JR   NZ,.MAALIAS                 ; Two operands may contain explicit A.

; A one-operand ADD/ADC/SBC is invalid because it omits the explicit A.

    LD   A,(PR_SCRAT+EN_MNEM)       ; Recover the one-operand ALU mnemonic.
    CP   AT_MADD                     ; ADD requires an explicit accumulator.
    JR   Z,.RACCUMUL                 ; Reject the omitted accumulator.
    CP   AT_MADC                     ; ADC has the same source requirement.
    JR   Z,.RACCUMUL                 ; Reject the omitted accumulator.
    CP   AT_MSBC                     ; SBC also requires the explicit A.
    JR   NZ,.ASUCCESS                ; Other one-operand forms are canonical.
.RACCUMUL:
    LD   A,PR_SIFOR                  ; Select the invalid-form status.
    JP   PR_FBEG                     ; Diagnose it at the mnemonic position.
.MAALIAS:
    CP   2                           ; Only two operands qualify for collapse.
    JR   NZ,.ASUCCESS                ; Leave every other arity unchanged.
    LD   A,(PR_SCRAT+EN_OP0)         ; Inspect the first operand class.
    CP   EN_A                        ; Is the explicit destination A?
    JR   NZ,.ASUCCESS                ; Preserve another destination.
    LD   A,(PR_SCRAT+EN_OP1)         ; Load the source operand class to move.

; Shift operand 1's class and value into operand 0, then clear operand 1 and
; reduce the arity to one.

    LD   (PR_SCRAT+EN_OP0),A         ; Move the source class into slot zero.
    LD   HL,(PR_SCRAT+EN_VAL1)       ; Load source operand one's value.
    LD   (PR_SCRAT+EN_VAL0),HL       ; Move it into canonical value slot zero.
    LD   A,EN_NONE                   ; Prepare the absent-operand class.
    LD   (PR_SCRAT+EN_OP1),A         ; Clear the former source class.
    XOR  A                           ; Prepare zero bytes and count base.
    LD   (PR_SCRAT+EN_VAL1),A        ; Clear the former value's low byte.
    LD   (PR_SCRAT+EN_VAL1+1),A      ; Clear the former value's high byte.
    INC  A                           ; The canonical record has one operand.
    LD   (PR_OPCNT),A                ; Publish its reduced arity.

; If operand one held a deferred reference, retarget it to operand zero and
; shift the unresolved mask to match the canonical record.

    LD   A,(PR_UMASK)                ; Read the unresolved-operand mask.
    AND  2                           ; Did operand one carry a reference?
    JR   Z,.ASUCCESS                 ; No reference metadata needs remapping.
    LD   A,1                         ; Operand zero is now unresolved instead.
    LD   (PR_UMASK),A                ; Publish the shifted mask.
    CALL PR_RAREF                    ; Retarget matching build records.
.ASUCCESS:
    XOR  A                           ; Return success with carry clear.
    RET                              ; Continue with numeric normalisation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS B,SIGN,PARITY,HALFCARRY,DE,HL,A
; Retarget build-reference operand 1 to 0 after accumulator-alias collapse.

PR_RAREF:
    XOR  A                           ; Start at build-reference index zero.
    LD   B,A                         ; B is the current record index.
.RALOOP:
    LD   A,(PR_RBCNT)                ; Read the private record count.
    CP   B                           ; Have all records been visited?
    RET  Z                           ; Return when index equals count.
    LD   A,B                         ; Select the current build record.
    CALL PR_BRADR                    ; Return its base address in DE.
    LD   HL,PR_BLDOP                 ; Load the operand-index field offset.
    ADD  HL,DE                       ; Address that field in the record.
    LD   A,(HL)                      ; Read the referenced operand index.
    CP   1                           ; Did it name removed operand one?
    JR   NZ,.RANEXT                  ; Leave other references untouched.
    LD   (HL),0                      ; Retarget it to canonical operand zero.
.RANEXT:
    INC  B                           ; Advance to the next build record.
    JR   .RALOOP                     ; Continue within the proved count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Resolve provisional numeric classes after the mnemonic and complete operand
; list are known. FMASK tracks byte candidates that may widen; CMASK tracks C
; operands that could also mean condition C.

PR_NNUMB:
    XOR  A                           ; Initialise pass masks and index.
    LD   (PR_FMASK),A                ; No numeric operand is flexible yet.
    LD   (PR_CMASK),A                ; No C operand is ambiguous yet.
    LD   (PR_SINDE),A                ; Begin with operand index zero.
.NLOOP:
    LD   A,(PR_SINDE)                ; Load the current operand index.
    LD   B,A                         ; Keep it across the count load.
    LD   A,(PR_OPCNT)                ; Read the number of parsed operands.
    CP   B                           ; Has the loop reached that count?
    RET  Z                           ; Return after the final operand.
    LD   A,B                         ; Restore the current operand index.
    CALL PR_SOP                      ; Select its class and value slots.
    LD   HL,(PR_CPTR)                ; Address the provisional class.
    LD   A,(HL)                      ; Read that class.
    CP   PR_GC                       ; Is it ambiguous register/condition C?
    JR   Z,.NC                       ; Record both possible meanings.
    CP   PR_GPNUM                    ; Is it a parenthesised generic number?
    JR   Z,.NPNUMBER                 ; Choose memory or immediate-port class.
    CP   PR_GNUMB                    ; Is it a bare generic number?
    JR   NZ,.NNEXT                   ; Fixed classes need no conversion.
    CALL PR_NBNUM                    ; Classify the bare numeric operand.
    RET  C                           ; Preserve an enum range error.
    JR   .NNEXT                      ; Advance after classification.
.NC:

; Prefer register C initially and record the alternative condition meaning for
; candidate validation.

    LD   (HL),EN_C                   ; Prefer ordinary register C initially.
    LD   A,(PR_SINDE)                ; Recover its operand index.
    CALL PR_IBIT                     ; Convert the index to a one-hot bit.
    LD   HL,PR_CMASK                 ; Address the condition-candidate mask.
    OR   (HL)                        ; Preserve any earlier ambiguous C.
    LD   (HL),A                      ; Mark this operand as a candidate.
    JR   .NNEXT                      ; Continue with the next operand.
.NPNUMBER:

; Parenthesised numbers mean absolute memory, except IN and OUT use them as an
; immediate eight-bit port.

    LD   A,(PR_SCRAT+EN_MNEM)       ; Read the instruction mnemonic.
    CP   AT_MIN                      ; Does IN use an immediate port number?
    JR   Z,.NPB                      ; Require an unsigned byte port.
    CP   AT_MOUT                     ; Does OUT use an immediate port number?
    JR   Z,.NPB                      ; Require an unsigned byte port.
    LD   HL,(PR_CPTR)                ; Reopen the selected class slot.
    LD   (HL),EN_MABS                ; Otherwise use absolute memory.
    JR   .NNEXT                      ; Continue with the next operand.
.NPB:
    CALL PR_RBVAL                    ; Require a byte-sized concrete port.
    RET  C                           ; Return its value-range diagnostic.
    LD   HL,(PR_CPTR)                ; Reopen the selected class slot.
    LD   (HL),EN_IMM8                ; Use the immediate-byte port class.
.NNEXT:
    LD   HL,PR_SINDE                 ; Address the operand scan index.
    INC  (HL)                        ; Advance to the next operand.
    JR   .NLOOP                      ; Repeat within the parsed operand count.

;@ROUTINE OUT A,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Convert one bare generic number according to its mnemonic and operand index.
; Enumerated operands encode their value in the class itself. Branch targets
; select word or relative classes; other numbers begin as flexible imm8.

PR_NBNUM:
    LD   A,(PR_SCRAT+EN_MNEM)       ; Read the value's mnemonic context.
    CP   AT_MIM                      ; Does IM require an enumerated mode?
    JR   Z,.NIM                      ; Convert values 0..2 into IM classes.
    CP   AT_MRST                     ; Does RST require an enumerated vector?
    JR   Z,.NRST                     ; Convert eight legal vectors to classes.
    CP   AT_MBIT                     ; Is the mnemonic below BIT/RES/SET?
    JR   C,.NBRANCH                  ; Try branch and general numbers.
    CP   AT_MSET+1                   ; Is it in the BIT through SET family?
    JR   C,.NBIT                     ; Classify operand zero as a bit number.
.NBRANCH:

; Absolute JP and CALL retain the target word. JR and DJNZ are converted to a
; signed displacement only after the final instruction length is known.

    LD   A,(PR_SCRAT+EN_MNEM)       ; Reload the mnemonic for branch classes.
    CP   AT_MJP                      ; JP targets are absolute words.
    JR   Z,.NW                       ; Select the immediate-word class.
    CP   AT_MCALL                    ; CALL targets are also absolute words.
    JR   Z,.NW                       ; Select the immediate-word class.
    CP   AT_MJR                      ; JR targets become relative bytes.
    JR   Z,.NRELATIV                 ; Defer displacement calculation.
    CP   AT_MDJNZ                    ; DJNZ uses the same relative form.
    JR   Z,.NRELATIV                 ; Defer displacement calculation.
    CP   AT_MOUT                     ; OUT admits the special literal zero.
    JR   NZ,.NFLEXIBL                ; Other numbers start as flexible bytes.

; OUT (C),0 has a dedicated class. Other OUT values remain bytes and are
; checked by the complete form.

    CALL PR_SVAL                     ; Load the concrete OUT operand value.
    LD   A,H                         ; Combine both bytes to test for zero.
    OR   L                           ; Z means the complete word is zero.
    JR   NZ,.NFLEXIBL                ; Nonzero uses ordinary byte handling.
    LD   HL,(PR_CPTR)                ; Address the selected class slot.
    LD   (HL),EN_ZERO                ; Encode the dedicated OUT (C),0 class.
    XOR  A                           ; Return success with carry clear.
    RET                              ; The zero word is already canonical.
.NIM:

; IM accepts only the enumerated values 0, 1 and 2.

    CALL PR_SVAL                     ; Load the requested interrupt mode.
    LD   A,H                         ; A legal mode has no high byte.
    OR   A                           ; Set Z only when the high byte is zero.
    JP   NZ,PR_VRANG                 ; Reject a nonzero high byte.
    LD   A,L                         ; Recover the low-byte mode number.
    CP   3                           ; Modes 0, 1 and 2 are the entire domain.
    JP   NC,PR_VRANG                 ; Reject mode 3 or above.
    ADD  A,EN_IM0                    ; Convert the value to its enum class.
    JR   .SENUM                      ; Store class and clear its value.
.NRST:

; RST vectors run from 0 to 56 by eights. Divide the vector value by eight to
; obtain its class index, then add the first restart class.

    CALL PR_SVAL                     ; Load the requested restart vector.
    LD   A,H                         ; A legal vector has no high byte.
    OR   A                           ; Set Z only when the high byte is zero.
    JP   NZ,PR_VRANG                 ; Reject a value above 255 immediately.
    LD   A,L                         ; Recover the low-byte vector address.
    CP   57                          ; The largest legal vector is 56.
    JP   NC,PR_VRANG                 ; Reject 57 and above.
    AND  7                           ; Legal vectors are multiples of eight.
    JP   NZ,PR_VRANG                 ; Reject a non-aligned vector.
    LD   A,L                         ; Reload the validated vector.
    RRCA                             ; Shift the aligned vector right once.
    RRCA                             ; The value is now vector / 4.
    RRCA                             ; Vector / 8 gives restart index 0..7.
    AND  7                           ; Keep the three-bit restart index.
    ADD  A,EN_RST0                   ; Convert the index to its restart class.
    JR   .SENUM                      ; Store class and clear its value.
.NBIT:

; BIT, RES and SET encode their first operand in the class and require 0..7.

    LD   A,(PR_SINDE)                ; Read this numeric operand's index.
    OR   A                           ; Is it operand zero, the bit number?
    JR   NZ,.NFLEXIBL                ; Later operands use ordinary handling.
    CALL PR_SVAL                     ; Load the requested bit number.
    LD   A,H                         ; A legal bit has no high byte.
    OR   A                           ; Set Z only when the high byte is zero.
    JP   NZ,PR_VRANG                 ; Reject values above 255.
    LD   A,L                         ; Recover the low-byte bit number.
    CP   8                           ; Bit numbers range from zero to seven.
    JP   NC,PR_VRANG                 ; Reject eight and above.
    ADD  A,EN_BIT0                   ; Convert the number to its enum class.
.SENUM:

; The enum class carries the value, so clear its redundant word slot.

    LD   HL,(PR_CPTR)                ; Address the selected operand class.
    LD   (HL),A                      ; Store the value-bearing enum class.
    CALL PR_CSVAL                    ; Clear the now-redundant value word.
    XOR  A                           ; Return success with carry clear.
    RET                              ; Continue with the next operand.
.NW:
    LD   HL,(PR_CPTR)                ; Address the selected operand class.
    LD   (HL),EN_IMM16               ; Mark an absolute sixteen-bit target.
    XOR  A                           ; Return success with carry clear.
    RET                              ; Preserve the target value word.
.NRELATIV:
    LD   HL,(PR_CPTR)                ; Address the selected operand class.
    LD   (HL),EN_REL8                ; Mark a relative target.
    XOR  A                           ; Return success with carry clear.
    RET                              ; Preserve the absolute target for now.
.NFLEXIBL:

; Start with imm8 and mark this operand in FMASK. If no byte form validates,
; PR_WFLEX widens marked values to imm16 and retries.

    LD   HL,(PR_CPTR)                ; Address the selected operand class.
    LD   (HL),EN_IMM8                ; Try the shortest numeric class first.
    LD   A,(PR_SINDE)                ; Recover the operand index.
    CALL PR_IBIT                     ; Convert it to a one-hot bit.
    LD   HL,PR_FMASK                 ; Address the flexible-value mask.
    OR   (HL)                        ; Preserve earlier flexible operands.
    LD   (HL),A                      ; Mark this one for possible widening.
    XOR  A                           ; Return success with carry clear.
    RET                              ; Validation chooses the final width.

;@ROUTINE OUT HL CLOBBERS A
; Load the selected operand's little-endian word into HL.

PR_SVAL:
    LD   HL,(PR_VPTR)                ; Load the selected value-slot address.
    LD   A,(HL)                      ; Read its little-endian low byte.
    INC  HL                          ; Advance to the high byte.
    LD   H,(HL)                      ; Place the high byte in H.
    LD   L,A                         ; Complete the value in HL.
    RET                              ; Return the concrete operand word.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Clear the selected value once its information has moved into an enum class.

PR_CSVAL:
    LD   HL,(PR_VPTR)                ; Load the selected value-slot address.
    XOR  A                           ; Prepare a zero for both bytes.
    LD   (HL),A                      ; Clear the low byte.
    INC  HL                          ; Advance to the high byte.
    LD   (HL),A                      ; Clear the high byte.
    RET                              ; The class now carries the value.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require the selected value to fit unsigned eight-bit range.

PR_RBVAL:
    CALL PR_SVAL                     ; Load the selected concrete value.
    LD   A,H                         ; An unsigned byte needs high byte zero.
    OR   A                           ; Set Z when the value is within 0..255.
    RET  Z                           ; Return success with carry clear.
    JP   PR_VRANG                    ; Report an out-of-range value otherwise.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return a one-hot bit for operand index A: 0 -> 1, 1 -> 2, 2 -> 4.

PR_IBIT:
    OR   A                           ; Is the operand index zero?
    JR   NZ,.IBDOUBLE                ; Double either nonzero index.
    INC  A                           ; Convert index zero to bit value one.
    RET                              ; Return the one-hot mask.
.IBDOUBLE:
    ADD  A,A                         ; Convert index one/two to bit two/four.
    RET                              ; Return the one-hot mask.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Select an encoder-valid interpretation for the normalised record. Candidate
; order is provisional classes, ambiguous C as condition, widened numeric
; classes, then condition alternatives for the widened record. Success returns
; the encoder-reported length in A.

PR_VCAND:
    CALL PR_VCUR                     ; Try provisional register/byte classes.
    RET  NC                          ; Keep the first complete valid form.
    CALL PR_TCOND                    ; Try each ambiguous C as condition C.
    RET  NC                          ; Keep the first valid condition form.
    LD   A,(PR_FMASK)                ; Read the flexible numeric-operand mask.
    OR   A                           ; Can any byte class widen to a word?
    JR   Z,.IFORM                    ; No remaining form can validate.
    CALL PR_WFLEX                    ; Widen every marked byte candidate.
    CALL PR_VCUR                     ; Validate the widened register-C form.
    RET  NC                          ; Keep it when valid.
    CALL PR_TCOND                    ; Retry condition C after widening.
    RET  NC                          ; Keep the first complete valid form.
.IFORM:
    LD   A,PR_SIFOR                  ; Select invalid-form status.
    JP   PR_FBEG                     ; Diagnose it at the mnemonic position.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate the private instruction record without examining operand values.

PR_VCUR:
    LD   IX,PR_SCRAT                 ; Point IX at the private record.
    JP   EN_VFORM                    ; Return the encoder validator's result.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY,HL
; Try each operand marked in CMASK as condition C. Change one candidate at a
; time, restore register C after failure and stop at the first
; complete valid form.

PR_TCOND:
    XOR  A                           ; Begin with operand index zero.
    LD   (PR_SINDE),A                ; Publish the condition scan index.
.TCLOOP:
    LD   A,(PR_SINDE)                ; Load the current operand index.
    CP   3                           ; Have all three record slots been tried?
    JR   Z,.TCFAILED                 ; No condition form validated.
    LD   B,A                         ; Preserve index across conversion.
    CALL PR_IBIT                     ; Convert the index to a one-hot mask.
    LD   HL,PR_CMASK                 ; Address the ambiguous-C mask.
    AND  (HL)                        ; Is this operand an ambiguity candidate?
    JR   Z,.TCNEXT                   ; Skip fixed operands.
    LD   A,B                         ; Restore the candidate operand index.
    CALL PR_SOP                      ; Select its class slot.
    LD   HL,(PR_CPTR)                ; Load the selected class address.
    LD   (HL),EN_CC                  ; Temporarily interpret C as condition C.
    PUSH HL                          ; Preserve the class address.
    CALL PR_VCUR                     ; Test the complete modified record.
    POP  HL                          ; Recover it without changing flags.
    RET  NC                          ; Keep EN_CC when the form validates.
    LD   (HL),EN_C                   ; Restore register C after failure.
.TCNEXT:
    LD   HL,PR_SINDE                 ; Address the condition scan index.
    INC  (HL)                        ; Advance to the next operand slot.
    JR   .TCLOOP                     ; Continue until a candidate validates.
.TCFAILED:
    SCF                              ; Report every condition choice failed.
    RET                              ; Ambiguous slots are register C again.

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,A
; Widen every flexible imm8 candidate to imm16 before the second validation
; pass. The chosen form determines each deferred reference's patch width.

PR_WFLEX:
    XOR  A                           ; Begin with operand index zero.
    LD   (PR_SINDE),A                ; Publish the widening scan index.
.WLOOP:
    LD   A,(PR_SINDE)                ; Load the current operand index.
    CP   3                           ; Have all record slots been visited?
    RET  Z                           ; Return after the final slot.
    LD   B,A                         ; Preserve index across conversion.
    CALL PR_IBIT                     ; Convert the index to a one-hot mask.
    LD   HL,PR_FMASK                 ; Address the flexible-value mask.
    AND  (HL)                        ; Was this a byte candidate?
    JR   Z,.WNEXT                    ; Leave fixed classes unchanged.
    LD   A,B                         ; Restore the flexible operand index.
    CALL PR_SOP                      ; Select its class slot.
    LD   HL,(PR_CPTR)                ; Load the selected class address.
    LD   (HL),EN_IMM16               ; Widen it to a word immediate.
.WNEXT:
    LD   HL,PR_SINDE                 ; Address the widening scan index.
    INC  (HL)                        ; Advance to the next operand slot.
    JR   .WLOOP                      ; Continue through the fixed three slots.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Check each resolved value against its selected class. UMASK bits mark
; placeholders checked after their symbols resolve.

PR_CCVAL:
    XOR  A                           ; Begin with operand index zero.
    LD   (PR_SINDE),A                ; Publish the concrete-value scan index.
.CVLOOP:
    LD   A,(PR_SINDE)                ; Load the current operand index.
    LD   B,A                         ; Preserve it across the count load.
    LD   A,(PR_OPCNT)                ; Read the number of parsed operands.
    CP   B                           ; Has the loop reached that count?
    RET  Z                           ; Return after the final value.
    LD   A,B                         ; Restore the current operand index.
    CALL PR_SOP                      ; Select its class and value slots.
    LD   A,(PR_SINDE)                ; Reload the index for mask conversion.
    CALL PR_IBIT                     ; Convert it to a one-hot bit.
    LD   HL,PR_UMASK                 ; Address the unresolved-value mask.
    AND  (HL)                        ; Is this value still a placeholder?
    JR   NZ,.CVNEXT                  ; Defer its range check until resolution.

; Word and absolute classes need no conversion. Byte, relative and indexed
; classes need the checks below.

    LD   HL,(PR_CPTR)                ; Address the selected operand class.
    LD   A,(HL)                      ; Read the class that defines its range.
    CP   EN_IMM8                     ; Does it require an unsigned byte?
    JR   Z,.CHKB                     ; Check the value against 0..255.
    CP   EN_REL8                     ; Is it a relative-branch target?
    JR   Z,.CRELATIV                 ; Convert and check signed displacement.
    CP   EN_IIX                      ; Is it an IX signed displacement?
    JR   Z,.CDISPLAC                 ; Check the signed-byte representation.
    CP   EN_IIY                      ; Is it an IY signed displacement?
    JR   Z,.CDISPLAC                 ; Check the same signed-byte range.
.CVNEXT:
    LD   HL,PR_SINDE                 ; Address the concrete-value scan index.
    INC  (HL)                        ; Advance to the next operand.
    JR   .CVLOOP                     ; Continue within the operand count.
.CHKB:
    CALL PR_RBVAL                    ; Require an unsigned eight-bit value.
    RET  C                           ; Preserve the range diagnostic.
    JR   .CVNEXT                     ; Continue after a valid byte.
.CDISPLAC:

; IX/IY displacement accepts exactly -128..127 represented as a sign-extended
; word or a positive low byte.

    CALL PR_SVAL                     ; Load the signed displacement word.
    LD   A,H                         ; Inspect its sign-extension byte.
    OR   A                           ; Zero denotes a non-negative value.
    JR   Z,.CDPOSITI                 ; Check the positive half separately.
    INC  A                           ; $FF wraps for negative candidates.
    JP   NZ,PR_VRANG                 ; Reject any other high byte.
    BIT  7,L                         ; Negative low bytes need bit 7 set.
    JP   Z,PR_VRANG                  ; Reject -256..-129 representations.
    JR   .CVNEXT                     ; Accept -128..-1 and continue.
.CDPOSITI:
    BIT  7,L                         ; Positive bytes must be below $80.
    JP   NZ,PR_VRANG                 ; Reject 128..255.
    JR   .CVNEXT                     ; Accept 0..127 and continue.
.CRELATIV:

; Convert target to target-(instruction address+length). The 16-bit arithmetic
; wraps at $FFFF like the Z80 PC; the result must fit a signed byte.

    CALL PR_SVAL                     ; Load the absolute branch target.
    LD   DE,(PR_IADR)                ; Load the instruction's logical address.
    LD   A,(PR_ILEN)                 ; Read its validated encoded length.
    ADD  A,E                         ; Add length to the address low byte.
    LD   E,A                         ; Store the next-PC low byte.
    JR   NC,.RBREADY                 ; Skip when no carry occurred.
    INC  D                           ; Carry into the address high byte.
.RBREADY:
    OR   A                           ; Clear carry before subtraction.
    SBC  HL,DE                       ; Subtract the next-instruction address.
    LD   A,H                         ; Inspect the displacement high byte.
    OR   A                           ; Zero means non-negative displacement.
    JR   Z,.RPOSITIV                 ; Check the positive half separately.
    INC  A                           ; $FF wraps for negative candidates.
    JP   NZ,PR_RRANG                 ; Reject missing sign extension.
    BIT  7,L                         ; Negative bytes need bit 7 set.
    JP   Z,PR_RRANG                  ; Reject values below -128.
    JR   .RSTORE                     ; Accept -128..-1.
.RPOSITIV:
    BIT  7,L                         ; Positive bytes must be below $80.
    JP   NZ,PR_RRANG                 ; Reject displacements above 127.
.RSTORE:

; Replace the absolute target with the encoded displacement for EN_NAME.

    CALL PR_SHVAL                    ; Store the signed displacement word.
    JR   .CVNEXT                     ; Continue checking later operands.
