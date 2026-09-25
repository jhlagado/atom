;==============================================================================
;  Instruction-form normalisation and publication
;==============================================================================
;
;  PURPOSE
;  -------
;  Turn the parser's provisional operand record into the exact form consumed by
;  the encoder. Resolve source conveniences, check concrete ranges, prepare
;  deferred symbol patches and commit the validated record atomically.
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
;  INTERNAL PIPELINE
;  -----------------
;
;  PR_NAALI handles accumulator aliases. PR_NNUMB assigns provisional numeric
;  classes. PR_VCAND selects an encoder-valid form, PR_CCVAL checks concrete
;  values, PR_FREFE prepares symbol references and PR_CMT commits the record.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  The module owns the fixed parser workspace between PR_WBEG and PR_WEND. It
;  uses the caller-owned symbol and pending arenas but does not own their memory.
;  Calls preserve stack balance, may clobber the registers named by each routine
;  contract, and are not reentrant. Parse and form failures publish a source
;  position without changing the caller's destination record. Publication
;  entries return their symbol or pending status directly.
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

; A one-operand ADD/ADC/SBC would silently imply A, which Atom does not permit.

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

; If the removed second operand carried a deferred reference, remap its operand
; index from one to zero and shift the unresolved mask with the record.

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
; Rewrite build-reference operand index 1 to 0 after accumulator-alias collapse.

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
; list are known. FMASK records byte-immediate candidates that may later widen;
; CMASK records occurrences of C that may be a condition rather than register C.

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

; Parenthesised numbers are absolute memory except in IN and OUT, where they are
; the immediate eight-bit port form.

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
; Enumerated operands encode their value in the class itself. Branches select a
; word or relative class. All remaining numbers start as flexible imm8.

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

; OUT (C),0 has a dedicated operand class. Other OUT numbers remain byte values
; and are validated by the complete form.

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

; RST accepts the eight vectors from 0 through 56 in steps of eight. Rotate the
; vector index down and add the first restart class.

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

; The enumerated class now carries the value, so clear the redundant word slot.

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

; Begin with imm8 and remember this operand in FMASK. If no byte-form candidate
; validates, PR_WFLEX widens every marked operand to imm16 and tries again.

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
; order is: provisional classes, each ambiguous C as condition, widened numeric
; classes, then condition alternatives on the widened record. Success returns
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
; Validate the current private instruction record without examining its values.

PR_VCUR:
    LD   IX,PR_SCRAT                 ; Point IX at the private record.
    JP   EN_VFORM                    ; Return the encoder validator's result.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY,HL
; Try each operand marked in CMASK as condition C. Change only one occurrence at
; a time, restore register C after a failed validation and stop at the first
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
; pass. The chosen form later determines each deferred reference's patch width.

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
; Check every resolved concrete value against its selected operand class. Values
; with a bit in UMASK remain zero placeholders and are checked later when their
; symbols resolve.

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

; Word and absolute classes need no further range conversion. Byte, relative and
; indexed classes have class-specific checks below.

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

; Convert an absolute branch target to target-(instruction address+length). The
; 16-bit addition and subtraction deliberately wrap at $FFFF, matching the Z80
; program counter, then the result must fit a signed byte.

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

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Turn private build references into public symbol-reference descriptions. The
; first pass locates the encoded field and final patch kind for each operand.

PR_FREFE:
    XOR  A
    LD   (PR_RSCAN),A
.LRLOOP:
    LD   A,(PR_RBCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.PREFEREN
    CALL PR_BRADR
    LD   HL,PR_BLDOP
    ADD  HL,DE
    LD   A,(HL)
    LD   IX,PR_SCRAT
    CALL PT_LOCAT
    JR   C,.UREF

; Save the locator's patch kind and byte offset while returning to the selected
; thirteen-byte build entry.

    LD   (PR_RKSCR),A
    LD   A,B
    LD   (PR_ROSCR),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BKIND
    ADD  HL,DE
    LD   A,(HL)
    CP   EX_FLO
    JR   Z,.LLREF
    CP   EX_FHI
    JR   Z,.LHREF
    LD   A,(PR_RKSCR)
    JR   .LSKIND
.LLREF:
    LD   A,PT_KLB
    JR   .LBFUNCTI
.LHREF:
    LD   A,PT_KHB
.LBFUNCTI:

; LOW/HIGH cannot transform relative or displacement patches. Relative fields
; subtract an address and both field types require signed-range semantics, not
; simple byte extraction.

    PUSH AF
    LD   A,(PR_RKSCR)
    CP   PT_KRELA
    JR   Z,.LBFINVAL
    CP   PT_KDISP
    JR   Z,.LBFINVAL
    POP  AF
.LSKIND:

; Store the final kind and encoded-field offset in the build record.

    LD   (HL),A
    INC  HL
    LD   A,(PR_ROSCR)
    LD   (HL),A
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .LRLOOP
.LBFINVAL:
    POP  AF
.UREF:
    LD   A,PR_SUNPA
    JP   PR_FREF
.PREFEREN:

; Count exact missing symbol records before inserting any. When both references
; share one key, only the first contributes to the capacity requirement.

    XOR  A
    LD   (PR_RMCNT),A
    LD   (PR_RSKEY),A
    LD   A,(PR_RBCNT)
    OR   A
    RET  Z
    CP   2
    JR   NZ,.PFIRST
    CALL PR_CRKEY

; Carry clear means equal keys. Convert that result to one in PR_RSKEY.

    SBC  A,A
    INC  A
    LD   (PR_RSKEY),A
.PFIRST:
    XOR  A
    LD   (PR_RSCAN),A
    CALL PR_PREF
    RET  C
    LD   A,(PR_RBCNT)
    CP   2
    JR   NZ,.PCAP
    LD   A,(PR_RSKEY)
    OR   A
    JR   NZ,.PCAP
    LD   A,1
    LD   (PR_RSCAN),A
    CALL PR_PREF
    RET  C
.PCAP:
    LD   A,(PR_RMCNT)
    OR   A
    JR   Z,.PREFERE1

; Each missing symbol needs one eight-byte record in the shared arena. Check the
; complete requirement against the gap between globals and private symbols.

    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   HL,(SY_LBEG)
    LD   DE,(SY_GEND)
    CALL AT_RHCAP
    JP   C,PR_SCFAI
.PREFERE1:

; Capacity is now proved. Resolve or insert every key and construct the public
; nine-byte descriptions in source operand order.

    XOR  A
    LD   (PR_RSCAN),A
.PRLOOP:
    LD   A,(PR_RBCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.PRCNT
    CALL PR_BRADR
    LD   H,D
    LD   L,E
    CALL SY_REF
    JP   C,PR_USFAI
    LD   A,B
    OR   A
    JR   Z,.RDREADY

; A newly inserted undefined record retains the first reference position in its
; otherwise-unused value word. Mark the matching pending kind as the diagnostic
; anchor that may report an undefined symbol at finalisation.

    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BSOFF
    ADD  HL,DE
    LD   A,(HL)
    LD   (IX+SY_VALLO),A
    INC  HL
    LD   A,(HL)
    LD   (IX+SY_VALHI),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   A,SY_DANCH
    LD   HL,PR_BKIND
    ADD  HL,DE
    OR   (HL)
    LD   (HL),A
.RDREADY:

; Public record: symbol pointer, addend, operand index, patch kind/anchor, encoded
; byte offset, source part and source offset.

    PUSH IX
    POP  BC
    LD   A,(PR_RSCAN)
    CALL PR_PRADR
    LD   (HL),C
    INC  HL
    LD   (HL),B
    INC  HL
    PUSH HL
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BADDE
    ADD  HL,DE
    POP  DE
    LD   BC,7
    LDIR
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .PRLOOP
.PRCNT:

; Publish the count only after every public record and symbol insertion succeeds.

    LD   A,(PR_RBCNT)
    LD   (PR_RCNT),A
    XOR  A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Inspect one build key without mutation. Not-found increments the exact missing
; count; scope and other symbol failures retain their nested status.

PR_PREF:
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   H,D
    LD   L,E
    CALL SY_FIND
    RET  NC
    CP   SY_SNFOU
    JR   NZ,PR_SFAIL
    LD   HL,PR_RMCNT
    INC  (HL)
    XOR  A
    RET
PR_SFAIL:
    LD   (PR_SSTAT),A
    LD   A,PR_SSYM
    JP   PR_FREF

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,B
; Compare the two six-byte packed keys. Carry clear means identical.

PR_CRKEY:
    LD   HL,PR_RBLD
    LD   DE,PR_RBLD+PR_BRB
    LD   B,6
.CRKLOOP:
    LD   A,(DE)
    CP   (HL)
    SCF
    RET  NZ
    INC  DE
    INC  HL
    DJNZ .CRKLOOP
    OR   A
    RET
PR_SCFAI:

; Translate the shared-arena capacity failure through the symbol error category.

    LD   A,SY_SSCAP
    JR   PR_SFAIL
PR_USFAI:

; SY_REF cannot fail after exact lookup and capacity preflight unless an internal
; invariant changed between the two phases.

    LD   (PR_SSTAT),A
    LD   A,PR_SINT
    JP   PR_FREF

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Return public-reference address A. Two fixed nine-byte slots cover the parser
; reference capacity.

PR_PRADR:
    LD   HL,PR_REFER
    OR   A
    RET  Z
    LD   DE,PR_PRB
    ADD  HL,DE
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO,IX
; Before any instruction byte is emitted, prove that the pending arena has room
; for every reference and that each symbol remains undefined. Each pending entry
; is seven bytes, including its full source-part ordinal; allocation happens in
; PR_QREFE after output accepts the instruction.

PR_CREFE:
    LD   A,(PR_RCNT)
    LD   B,A
    ADD  A,A
    ADD  A,B
    ADD  A,A
    ADD  A,B
    LD   B,A
    LD   HL,(SY_AEND1)
    LD   DE,(SY_NEXT)
    CALL AT_RHCAP
    JR   C,PR_QCAP
.QCSYMBOL:

; A symbol defined between parse and emission would make the already encoded
; placeholder invalid. Treat it as a defensive publication-state failure.

    XOR  A
    LD   (PR_RSCAN),A
.QCLOOP:
    LD   A,(PR_RCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.QPDONE
    CALL PR_PRADR
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    EX   DE,HL
    LD   DE,5
    ADD  HL,DE
    BIT  6,(HL)
    JR   NZ,PR_QADEF
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .QCLOOP
.QPDONE:
    XOR  A
    RET

;@ROUTINE IN DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Queue every public reference after the encoded bytes have been accepted. DE
; supplies the instruction's logical start address. A second preflight protects
; direct callers and keeps this entry self-contained.

PR_QREFE:
    LD   (PR_QBASE),DE
    CALL PR_CREFE
    RET  C
.QUEUECMT:
    XOR  A
    LD   (PR_RSCAN),A
.QLOOP:
    LD   A,(PR_RCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.QDONE
    CALL PR_PRADR

; Load the symbol pointer, signed addend, final kind, source part and encoded
; byte offset from the public record.

    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    PUSH DE
    POP  IX
    INC  HL
    LD   C,(HL)
    INC  HL
    INC  HL
    LD   B,(HL)
    INC  HL
    LD   A,(HL)
    LD   (PR_ROSCR),A
    INC  HL
    LD   A,(HL)
    LD   (PR_RKSCR),A
    LD   A,(PR_ROSCR)
    LD   HL,(PR_QBASE)
    LD   E,A
    LD   D,0
    ADD  HL,DE
    EX   DE,HL

; SY_ADD receives A=part, IX=symbol, DE=patch address, B=kind/anchor and C=addend.

    LD   A,(PR_RKSCR)
    CALL SY_ADD
    RET  C
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .QLOOP
.QDONE:
    XOR  A
    RET
PR_QCAP:

; Pending arena cannot hold the complete reference set. No record was appended.

    LD   A,SY_SPCAP
    SCF
    RET
PR_QADEF:

; Defensive status for a reference whose symbol became defined before queueing.

    LD   A,SY_SADEF
    SCF
    RET
PR_FESYM:

; Reference-build failures that arise directly from expression state use the
; evaluator's retained symbol position. PR_PUB callers diagnose at the enclosing
; statement position; PR_PARSE callers receive these parser error fields.

    LD   (PR_ESTAT),A
    LD   A,(EX_SPART)
    LD   (PR_EPART),A
    LD   HL,(EX_SOFF)
    LD   (PR_EOFF),HL
    LD   A,(PR_ESTAT)
    SCF
    RET
PR_FREF:

; Reference finalisation failures use the source position stored in the current
; build record selected by PR_RSCAN.

    LD   (PR_ESTAT),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BPART
    ADD  HL,DE
    LD   A,(HL)
    LD   (PR_EPART),A
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    LD   (PR_EOFF),DE
    LD   A,(PR_ESTAT)
    SCF
    RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Commit the fully validated private record to the caller's destination and
; return IX pointing at it. No earlier parser path writes the destination.

PR_CMT:
    LD   HL,PR_SCRAT
    LD   DE,(PR_DST)
    LD   BC,10
    LDIR
    LD   IX,(PR_DST)
    XOR  A
    RET

; Compact status adapters select the appropriate source anchor below.

PR_EMNEM:
    LD   A,PR_SEMNE
    JR   PR_FHERE
PR_UMNEM:
    LD   A,PR_SUMNE
    JR   PR_FHERE
PR_EXPOP:
    LD   A,PR_SEOP
    JR   PR_FHERE
PR_UOP:
    LD   A,PR_SUOP
    JR   PR_FHERE
PR_EDELI:
    LD   A,PR_SEDEL
    JR   PR_FHERE
PR_TMOPE:
    LD   A,PR_STMOP
    JR   PR_FHERE
PR_VRANG:
    LD   A,PR_SVRAN
    JR   PR_FHERE
PR_RRANG:
    LD   A,PR_SRRAN
    JR   PR_FBEG

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token position for token-local syntax and value failures.

PR_FHERE:
    LD   HL,TK_REC+TK_POFF
    JR   PR_FPOSI

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the instruction's mnemonic position for form and relative-range failures.
; PR_PARSE captures this position. The statement layer supplies its own outer
; position when it calls PR_PUB.

PR_FBEG:
    LD   HL,PR_IPART

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy a contiguous part-and-offset triple into the parser error fields, preserve
; the status in A and set carry.

PR_FPOSI:
    LD   (PR_ESTAT),A
    PUSH BC
    PUSH DE
    LD   DE,PR_EPART
    LD   BC,3
    LDIR
    POP  DE
    POP  BC
    LD   A,(PR_ESTAT)
    SCF
    RET
PR_RCEND:
PR_IBEG:

; Sorted RADIX-40 operand-word table. Each three-byte entry contains one packed
; word and its provisional encoder class. C maps to PR_GC because only complete
; form validation can distinguish register C from condition C.

PR_OWCNT EQU 27
PR_OWTAB:
    DW  $0640
    DB  EN_A
    DW  $0730
    DB  EN_AF
    DW  $0C80
    DB  EN_B
    DW  $0CF8
    DB  EN_BC
    DW  $12C0
    DB  PR_GC
    DW  $1900
    DB  EN_D
    DW  $19C8
    DB  EN_DE
    DW  $1F40
    DB  EN_E
    DW  $3200
    DB  EN_H
    DW  $33E0
    DB  EN_HL
    DW  $3840
    DB  EN_I
    DW  $3C00
    DB  EN_IX
    DW  $3C08
    DB  EN_IXH
    DW  $3C0C
    DB  EN_IXL
    DW  $3C28
    DB  EN_IY
    DW  $3C30
    DB  EN_IYH
    DW  $3C34
    DB  EN_IYL
    DW  $4B00
    DB  EN_L
    DW  $5140
    DB  EN_M
    DW  $57F8
    DB  EN_NC
    DW  $5B90
    DB  EN_NZ
    DW  $6400
    DB  EN_P
    DW  $64C8
    DB  EN_PE
    DW  $6658
    DB  EN_PO
    DW  $7080
    DB  EN_R
    DW  $7940
    DB  EN_SP
    DW  $A280
    DB  EN_Z
PR_OWTEN:
PR_IEND:
PR_CEND:
PR_WBEG:

; Per-call destinations and instruction identity. PR_ILEN is the length returned
; by EN_VFORM and is required for relative-target conversion.

PR_DST: DW 0                      ; Caller-owned ten-byte commit destination.
PR_IADR: DW 0                     ; Logical address of the current instruction.
PR_IPART: DB 0                    ; Source part containing the mnemonic.
PR_IOFF: DW 0                     ; Byte offset of the mnemonic in that part.
PR_ILEN: DB 0                     ; Validated encoded instruction length.
PR_OPCNT: DB 0                    ; Number of operands parsed, from zero to three.

; Shared scan index, ambiguity masks and selected class/value pointers used by
; operand normalisation and range checking.

PR_SINDE: DB 0                    ; Operand index used by normalisation loops.
PR_FMASK: DB 0                    ; Bits for byte values that may widen to words.
PR_CMASK: DB 0                    ; Bits for C operands that may be condition C.
PR_CPTR: DW 0                     ; Address of the selected operand-class byte.
PR_VPTR: DW 0                     ; Address of the selected operand-value word.
PR_LCLAS: DB 0                    ; Operand-word class saved across token fetch.
PR_MBASE: DB 0                    ; Parenthesised register or port base class.
PR_ICLAS: DB 0                    ; Indexed IX/IY class saved during parsing.

; Retained workspace byte with no caller in the current parser implementation.

PR_DSIGN: DB 0                    ; Reserved legacy displacement-sign scratch.

; Six-byte temporary packed operand key and private ten-byte instruction record.
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

; Reference publication state. PR_RBCNT counts private build entries; PR_RCNT is
; published only after their symbols and public records are complete.

PR_RCNT: DB 0                     ; Published reference-description count.
PR_RBCNT: DB 0                    ; Private build-reference count.
PR_UMASK: DB 0                    ; Bits marking unresolved operand values.
PR_RSCAN: DB 0                    ; Current reference index during publication.
PR_RMCNT: DB 0                    ; Missing symbols needed by this instruction.
PR_RSKEY: DB 0                    ; One when both build records share a key.
PR_RKSCR: DB 0                    ; Patch kind or queued source-part ordinal.
PR_ROSCR: DB 0                    ; Encoded field offset carried across lookup.
PR_RASCR: DW 0                    ; Signed expression addend before key copying.
PR_QBASE: DW 0                    ; Logical instruction base while queueing.

; Two thirteen-byte build entries followed by two nine-byte public entries. The
; complete fixed parser workspace is 92 bytes.

PR_RBLD: DS PR_BRB*PR_RCAP        ; Two private thirteen-byte build records.
PR_REFER: DS PR_PRB*PR_RCAP       ; Two public nine-byte reference records.
PR_WEND:
