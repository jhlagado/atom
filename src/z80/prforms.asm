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
;  This is an internal continuation of parser.asm. .parsed calls the pipeline
;  below after syntax parsing succeeds. refs.asm owns deferred-reference
;  publication, final commit, diagnostics, tables and shared parser workspace.
;
;  INTERNAL PIPELINE
;  -----------------
;
;  prAlias handles accumulator aliases. prClass assigns provisional numeric
;  classes. prForm chooses a form; prRange checks its concrete values.
;  refBind in refs.asm then prepares deferred references.
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

prAlias: ; Collapse an explicit A into the canonical byte-ALU operand.
    LD   A,(prRec+enMnem)               ; Read the current mnemonic ordinal.
    CP   mneAdd                         ; Is it below the contiguous ALU family?
    JR   C,.done                        ; Leave non-ALU instructions unchanged.
    CP   mneCp+1                        ; Is it above the last ALU mnemonic?
    JR   NC,.done                       ; Leave non-ALU instructions unchanged.
    LD   A,(prOpCnt)                    ; Read the parsed operand count.
    CP   1                              ; Does the source contain one operand?
    JR   NZ,.twoOps                     ; Two operands may contain explicit A.

; A one-operand ADD/ADC/SBC is invalid because it omits the explicit A.

    LD   A,(prRec+enMnem)               ; Recover the one-operand ALU mnemonic.
    CP   mneAdd                         ; ADD requires an explicit accumulator.
    JR   Z,.needA                       ; Reject the omitted accumulator.
    CP   mneAdc                         ; ADC has the same source requirement.
    JR   Z,.needA                       ; Reject the omitted accumulator.
    CP   mneSbc                         ; SBC also requires the explicit A.
    JR   NZ,.done                       ; Other one-operand forms are canonical.
.needA: ; Diagnose a byte ADD/ADC/SBC with the required A omitted.
    LD   A,prNoForm                     ; Select the invalid-form status.
    JP   prAtMnem                       ; Diagnose it at the mnemonic position.
.twoOps: ; Check whether two ALU operands qualify for accumulator collapse.
    CP   2                              ; Only two operands qualify for collapse.
    JR   NZ,.done                       ; Leave every other arity unchanged.
    LD   A,(prRec+enOp0)                ; Inspect the first operand class.
    CP   enRegA                         ; Is the explicit destination A?
    JR   NZ,.done                       ; Preserve another destination.
    LD   A,(prRec+enOp1)                ; Load the source operand class to move.

; Shift operand 1's class and value into operand 0, then clear operand 1 and
; reduce the arity to one.

    LD   (prRec+enOp0),A                ; Move the source class into slot zero.
    LD   HL,(prRec+enVal1)              ; Load source operand one's value.
    LD   (prRec+enVal0),HL              ; Move it into canonical value slot zero.
    LD   A,enNone                       ; Prepare the absent-operand class.
    LD   (prRec+enOp1),A                ; Clear the former source class.
    XOR  A                              ; Prepare zero bytes and count base.
    LD   (prRec+enVal1),A               ; Clear the former value's low byte.
    LD   (prRec+enVal1+1),A             ; Clear the former value's high byte.
    INC  A                              ; The canonical record has one operand.
    LD   (prOpCnt),A                    ; Publish its reduced arity.

; If operand one held a deferred reference, retarget it to operand zero and
; shift the unresolved mask to match the canonical record.

    LD   A,(prAwait)                    ; Read the unresolved-operand mask.
    AND  2                              ; Did operand one carry a reference?
    JR   Z,.done                        ; No reference metadata needs remapping.
    LD   A,1                            ; Operand zero is now unresolved instead.
    LD   (prAwait),A                    ; Publish the shifted mask.
    CALL .remap                         ; Retarget matching build records.
.done: ; Return successful normalisation with carry clear.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Continue with numeric normalisation.

;@ROUTINE OUT CARRY,ZERO CLOBBERS B,SIGN,PARITY,HALFCARRY,DE,HL,A
; Retarget build-reference operand 1 to 0 after accumulator-alias collapse.

.remap: ; Move deferred metadata from operand one to operand zero.
    XOR  A                              ; Start at build-reference index zero.
    LD   B,A                            ; B is the current record index.
.loop: ; Scan the private deferred-reference records.
    LD   A,(prRawCnt)                   ; Read the private record count.
    CP   B                              ; Have all records been visited?
    RET  Z                              ; Return when index equals count.
    LD   A,B                            ; Select the current build record.
    CALL prRawPtr                       ; Return its base address in DE.
    LD   HL,prBOper                     ; Load the operand-index field offset.
    ADD  HL,DE                          ; Address that field in the record.
    LD   A,(HL)                         ; Read the referenced operand index.
    CP   1                              ; Did it name removed operand one?
    JR   NZ,.next                       ; Leave other references untouched.
    LD   (HL),0                         ; Retarget it to canonical operand zero.
.next: ; Advance after retargeting or retaining this reference.
    INC  B                              ; Advance to the next build record.
    JR   .loop                          ; Continue within the proved count.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Resolve provisional numeric classes after the mnemonic and complete operand
; list are known. FMASK tracks byte candidates that may widen; CMASK tracks C
; operands that could also mean condition C.

prClass: ; Classify numeric operands and record ambiguous C alternatives.
    XOR  A                              ; Initialise pass masks and index.
    LD   (prWideOk),A                   ; No numeric operand is flexible yet.
    LD   (prCcMask),A                   ; No C operand is ambiguous yet.
    LD   (prOpIdx),A                    ; Begin with operand index zero.
.loop: ; Visit each operand within the parsed count.
    LD   A,(prOpIdx)                    ; Load the current operand index.
    LD   B,A                            ; Keep it across the count load.
    LD   A,(prOpCnt)                    ; Read the number of parsed operands.
    CP   B                              ; Has the loop reached that count?
    RET  Z                              ; Return after the final operand.
    LD   A,B                            ; Restore the current operand index.
    CALL prSlot                         ; Select its class and value slots.
    LD   HL,(prClsPtr)                  ; Address the provisional class.
    LD   A,(HL)                         ; Read that class.
    CP   prAnyC                         ; Is it ambiguous register/condition C?
    JR   Z,.regC                        ; Record both possible meanings.
    CP   prAnyMem                       ; Is it a parenthesised generic number?
    JR   Z,.paren                       ; Choose memory or immediate-port class.
    CP   prAnyNum                       ; Is it a bare generic number?
    JR   NZ,.next                       ; Fixed classes need no conversion.
    CALL .bare                          ; Classify the bare numeric operand.
    RET  C                              ; Preserve an enum range error.
    JR   .next                          ; Advance after classification.
.regC: ; Start with register C and retain condition C as an alternative.

; Prefer register C initially and record the alternative condition meaning for
; candidate validation.

    LD   (HL),enRegC                    ; Prefer ordinary register C initially.
    LD   A,(prOpIdx)                    ; Recover its operand index.
    CALL prOpBit                        ; Convert the index to a one-hot bit.
    LD   HL,prCcMask                    ; Address the condition-candidate mask.
    OR   (HL)                           ; Preserve any earlier ambiguous C.
    LD   (HL),A                         ; Mark this operand as a candidate.
    JR   .next                          ; Continue with the next operand.
.paren: ; Select absolute memory or an immediate I/O port.

; Parenthesised numbers mean absolute memory, except IN and OUT use them as an
; immediate eight-bit port.

    LD   A,(prRec+enMnem)               ; Read the instruction mnemonic.
    CP   mneIn                          ; Does IN use an immediate port number?
    JR   Z,.port                        ; Require an unsigned byte port.
    CP   mneOut                         ; Does OUT use an immediate port number?
    JR   Z,.port                        ; Require an unsigned byte port.
    LD   HL,(prClsPtr)                  ; Reopen the selected class slot.
    LD   (HL),enMemAbs                  ; Otherwise use absolute memory.
    JR   .next                          ; Continue with the next operand.
.port: ; Check the concrete port number before selecting imm8.
    CALL prIsByte                       ; Require a byte-sized concrete port.
    RET  C                              ; Return its value-range diagnostic.
    LD   HL,(prClsPtr)                  ; Reopen the selected class slot.
    LD   (HL),enImm8                    ; Use the immediate-byte port class.
.next: ; Advance to the next operand class slot.
    LD   HL,prOpIdx                     ; Address the operand scan index.
    INC  (HL)                           ; Advance to the next operand.
    JR   .loop                          ; Repeat within the parsed operand count.

;@ROUTINE OUT A,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Convert one bare generic number according to its mnemonic and operand index.
; Enumerated operands encode their value in the class itself. Branch targets
; select word or relative classes; other numbers begin as flexible imm8.

.bare: ; Select an enum, branch target or flexible numeric class.
    LD   A,(prRec+enMnem)               ; Read the value's mnemonic context.
    CP   mneIm                          ; Does IM require an enumerated mode?
    JR   Z,.imMode                      ; Convert values 0..2 into IM classes.
    CP   mneRst                         ; Does RST require an enumerated vector?
    JR   Z,.rstVec                      ; Convert eight legal vectors to classes.
    CP   mneBit                         ; Is the mnemonic below BIT/RES/SET?
    JR   C,.branch                      ; Try branch and general numbers.
    CP   mneSet+1                       ; Is it in the BIT through SET family?
    JR   C,.bitNum                      ; Classify operand zero as a bit number.
.branch: ; Choose absolute words for JP/CALL or relative bytes for JR/DJNZ.

; Absolute JP and CALL retain the target word. JR and DJNZ are converted to a
; signed displacement only after the final instruction length is known.

    LD   A,(prRec+enMnem)               ; Reload the mnemonic for branch classes.
    CP   mneJp                          ; JP targets are absolute words.
    JR   Z,.word                        ; Select the immediate-word class.
    CP   mneCall                        ; CALL targets are also absolute words.
    JR   Z,.word                        ; Select the immediate-word class.
    CP   mneJr                          ; JR targets become relative bytes.
    JR   Z,.relative                    ; Defer displacement calculation.
    CP   mneDjnz                        ; DJNZ uses the same relative form.
    JR   Z,.relative                    ; Defer displacement calculation.
    CP   mneOut                         ; OUT admits the special literal zero.
    JR   NZ,.flexible                   ; Other numbers start as flexible bytes.

; OUT (C),0 has a dedicated class. Other OUT values remain bytes and are
; checked by the complete form.

    CALL prGetVal                       ; Load the concrete OUT operand value.
    LD   A,H                            ; Combine both bytes to test for zero.
    OR   L                              ; Z means the complete word is zero.
    JR   NZ,.flexible                   ; Nonzero uses ordinary byte handling.
    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   (HL),enZero                    ; Encode the dedicated OUT (C),0 class.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The zero word is already canonical.
.imMode: ; Map interrupt mode 0..2 into an operand class.

; IM accepts only the enumerated values 0, 1 and 2.

    CALL prGetVal                       ; Load the requested interrupt mode.
    LD   A,H                            ; A legal mode has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,prTooBig                    ; Reject a nonzero high byte.
    LD   A,L                            ; Recover the low-byte mode number.
    CP   3                              ; Modes 0, 1 and 2 are the entire domain.
    JP   NC,prTooBig                    ; Reject mode 3 or above.
    ADD  A,enIm0                        ; Convert the value to its enum class.
    JR   .enum                          ; Store class and clear its value.
.rstVec: ; Map an aligned restart vector 0..56 into its class.

; RST vectors run from 0 to 56 by eights. Divide the vector value by eight to
; obtain its class index, then add the first restart class.

    CALL prGetVal                       ; Load the requested restart vector.
    LD   A,H                            ; A legal vector has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,prTooBig                    ; Reject a value above 255 immediately.
    LD   A,L                            ; Recover the low-byte vector address.
    CP   57                             ; The largest legal vector is 56.
    JP   NC,prTooBig                    ; Reject 57 and above.
    AND  7                              ; Legal vectors are multiples of eight.
    JP   NZ,prTooBig                    ; Reject a non-aligned vector.
    LD   A,L                            ; Reload the validated vector.
    RRCA                                ; Shift the aligned vector right once.
    RRCA                                ; The value is now vector / 4.
    RRCA                                ; Vector / 8 gives restart index 0..7.
    AND  7                              ; Keep the three-bit restart index.
    ADD  A,enRst0                       ; Convert the index to its restart class.
    JR   .enum                          ; Store class and clear its value.
.bitNum: ; Map operand zero of BIT/RES/SET into bit class 0..7.

; BIT, RES and SET encode their first operand in the class and require 0..7.

    LD   A,(prOpIdx)                    ; Read this numeric operand's index.
    OR   A                              ; Is it operand zero, the bit number?
    JR   NZ,.flexible                   ; Later operands use ordinary handling.
    CALL prGetVal                       ; Load the requested bit number.
    LD   A,H                            ; A legal bit has no high byte.
    OR   A                              ; Set Z only when the high byte is zero.
    JP   NZ,prTooBig                    ; Reject values above 255.
    LD   A,L                            ; Recover the low-byte bit number.
    CP   8                              ; Bit numbers range from zero to seven.
    JP   NC,prTooBig                    ; Reject eight and above.
    ADD  A,enBit0                       ; Convert the number to its enum class.
.enum: ; Store the enum class and clear its redundant value word.

; The enum class carries the value, so clear its redundant word slot.

    LD   HL,(prClsPtr)                  ; Address the selected operand class.
    LD   (HL),A                         ; Store the value-bearing enum class.
    CALL prClrVal                       ; Clear the now-redundant value word.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Continue with the next operand.
.word: ; Keep an absolute branch target as an immediate word.
    LD   HL,(prClsPtr)                  ; Address the selected operand class.
    LD   (HL),enImm16                   ; Mark an absolute sixteen-bit target.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the target value word.
.relative: ; Retain the target until the final instruction length is known.
    LD   HL,(prClsPtr)                  ; Address the selected operand class.
    LD   (HL),enRel8                    ; Mark a relative target.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the absolute target for now.
.flexible: ; Try imm8 first and retain a possible imm16 alternative.

; Start with imm8 and mark this operand in FMASK. If no byte form validates,
; prWiden widens marked values to imm16 and retries.

    LD   HL,(prClsPtr)                  ; Address the selected operand class.
    LD   (HL),enImm8                    ; Try the shortest numeric class first.
    LD   A,(prOpIdx)                    ; Recover the operand index.
    CALL prOpBit                        ; Convert it to a one-hot bit.
    LD   HL,prWideOk                    ; Address the flexible-value mask.
    OR   (HL)                           ; Preserve earlier flexible operands.
    LD   (HL),A                         ; Mark this one for possible widening.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Validation chooses the final width.

;@ROUTINE OUT HL CLOBBERS A
; Load the selected operand's little-endian word into HL.

prGetVal: ; Read the selected little-endian operand word into HL.
    LD   HL,(prValPtr)                  ; Load the selected value-slot address.
    LD   A,(HL)                         ; Read its little-endian low byte.
    INC  HL                             ; Advance to the high byte.
    LD   H,(HL)                         ; Place the high byte in H.
    LD   L,A                            ; Complete the value in HL.
    RET                                 ; Return the concrete operand word.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Clear the selected value once its information has moved into an enum class.

prClrVal: ; Erase the value word after its enum class carries the value.
    LD   HL,(prValPtr)                  ; Load the selected value-slot address.
    XOR  A                              ; Prepare a zero for both bytes.
    LD   (HL),A                         ; Clear the low byte.
    INC  HL                             ; Advance to the high byte.
    LD   (HL),A                         ; Clear the high byte.
    RET                                 ; The class now carries the value.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require the selected value to fit unsigned eight-bit range.

prIsByte: ; Require the selected word to be within 0..255.
    CALL prGetVal                       ; Load the selected concrete value.
    LD   A,H                            ; An unsigned byte needs high byte zero.
    OR   A                              ; Set Z when the value is within 0..255.
    RET  Z                              ; Return success with carry clear.
    JP   prTooBig                       ; Report an out-of-range value otherwise.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return a one-hot bit for operand index A: 0 -> 1, 1 -> 2, 2 -> 4.

prOpBit: ; Convert operand index 0, 1 or 2 into bit 1, 2 or 4.
    OR   A                              ; Is the operand index zero?
    JR   NZ,.double                     ; Double either nonzero index.
    INC  A                              ; Convert index zero to bit value one.
    RET                                 ; Return the one-hot mask.
.double: ; Map either nonzero operand index to its mask bit.
    ADD  A,A                            ; Convert index one/two to bit two/four.
    RET                                 ; Return the one-hot mask.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Select an encoder-valid interpretation for the normalised record. Candidate
; order is provisional classes, ambiguous C as condition, widened numeric
; classes, then condition alternatives for the widened record. Success returns
; the encoder-reported length in A.

prForm: ; Try the candidate classes in a fixed order until one validates.
    CALL prTry                          ; Try provisional register/byte classes.
    RET  NC                             ; Keep the first complete valid form.
    CALL prTryCc                        ; Try each ambiguous C as condition C.
    RET  NC                             ; Keep the first valid condition form.
    LD   A,(prWideOk)                   ; Read the flexible numeric-operand mask.
    OR   A                              ; Can any byte class widen to a word?
    JR   Z,.invalid                     ; No remaining form can validate.
    CALL prWiden                        ; Widen every marked byte candidate.
    CALL prTry                          ; Validate the widened register-C form.
    RET  NC                             ; Keep it when valid.
    CALL prTryCc                        ; Retry condition C after widening.
    RET  NC                             ; Keep the first complete valid form.
.invalid: ; Report that no complete instruction form validated.
    LD   A,prNoForm                     ; Select invalid-form status.
    JP   prAtMnem                       ; Diagnose it at the mnemonic position.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate the private instruction record without examining operand values.

prTry: ; Validate the private record without reading numeric values.
    LD   IX,prRec                       ; Point IX at the private record.
    JP   enCheck                        ; Return the encoder validator's result.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY,HL
; Try each operand marked in CMASK as condition C. Change one candidate at a
; time, restore register C after failure and stop at the first
; complete valid form.

prTryCc: ; Try each ambiguous C as a condition and restore failed choices.
    XOR  A                              ; Begin with operand index zero.
    LD   (prOpIdx),A                    ; Publish the condition scan index.
.loop: ; Scan the three operand slots for a C ambiguity.
    LD   A,(prOpIdx)                    ; Load the current operand index.
    CP   3                              ; Have all three record slots been tried?
    JR   Z,.fail                        ; No condition form validated.
    LD   B,A                            ; Preserve index across conversion.
    CALL prOpBit                        ; Convert the index to a one-hot mask.
    LD   HL,prCcMask                    ; Address the ambiguous-C mask.
    AND  (HL)                           ; Is this operand an ambiguity candidate?
    JR   Z,.next                        ; Skip fixed operands.
    LD   A,B                            ; Restore the candidate operand index.
    CALL prSlot                         ; Select its class slot.
    LD   HL,(prClsPtr)                  ; Load the selected class address.
    LD   (HL),enCondC                   ; Temporarily interpret C as condition C.
    PUSH HL                             ; Preserve the class address.
    CALL prTry                          ; Test the complete modified record.
    POP  HL                             ; Recover it without changing flags.
    RET  NC                             ; Keep enCondC when the form validates.
    LD   (HL),enRegC                    ; Restore register C after failure.
.next: ; Advance past this fixed or rejected candidate.
    LD   HL,prOpIdx                     ; Address the condition scan index.
    INC  (HL)                           ; Advance to the next operand slot.
    JR   .loop                          ; Continue until a candidate validates.
.fail: ; Return failure with every rejected candidate restored to register C.
    SCF                                 ; Report every condition choice failed.
    RET                                 ; Ambiguous slots are register C again.

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,A
; Widen every flexible imm8 candidate to imm16 before the second validation
; pass. The chosen form determines each deferred reference's patch width.

prWiden: ; Convert all flexible byte classes to immediate-word classes.
    XOR  A                              ; Begin with operand index zero.
    LD   (prOpIdx),A                    ; Publish the widening scan index.
.loop: ; Scan all three slots for numeric widening candidates.
    LD   A,(prOpIdx)                    ; Load the current operand index.
    CP   3                              ; Have all record slots been visited?
    RET  Z                              ; Return after the final slot.
    LD   B,A                            ; Preserve index across conversion.
    CALL prOpBit                        ; Convert the index to a one-hot mask.
    LD   HL,prWideOk                    ; Address the flexible-value mask.
    AND  (HL)                           ; Was this a byte candidate?
    JR   Z,.next                        ; Leave fixed classes unchanged.
    LD   A,B                            ; Restore the flexible operand index.
    CALL prSlot                         ; Select its class slot.
    LD   HL,(prClsPtr)                  ; Load the selected class address.
    LD   (HL),enImm16                   ; Widen it to a word immediate.
.next: ; Advance after retaining or widening this operand.
    LD   HL,prOpIdx                     ; Address the widening scan index.
    INC  (HL)                           ; Advance to the next operand slot.
    JR   .loop                          ; Continue through the fixed three slots.

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Check each resolved value against its selected class. UMASK bits mark
; placeholders checked after their symbols resolve.

prRange: ; Check concrete operands and defer unresolved placeholders.
    XOR  A                              ; Begin with operand index zero.
    LD   (prOpIdx),A                    ; Publish the concrete-value scan index.
.loop: ; Check each value within the parsed operand count.
    LD   A,(prOpIdx)                    ; Load the current operand index.
    LD   B,A                            ; Preserve it across the count load.
    LD   A,(prOpCnt)                    ; Read the number of parsed operands.
    CP   B                              ; Has the loop reached that count?
    RET  Z                              ; Return after the final value.
    LD   A,B                            ; Restore the current operand index.
    CALL prSlot                         ; Select its class and value slots.
    LD   A,(prOpIdx)                    ; Reload the index for mask conversion.
    CALL prOpBit                        ; Convert it to a one-hot bit.
    LD   HL,prAwait                     ; Address the unresolved-value mask.
    AND  (HL)                           ; Is this value still a placeholder?
    JR   NZ,.next                       ; Defer its range check until resolution.

; Word and absolute classes need no conversion. Byte, relative and indexed
; classes need the checks below.

    LD   HL,(prClsPtr)                  ; Address the selected operand class.
    LD   A,(HL)                         ; Read the class that defines its range.
    CP   enImm8                         ; Does it require an unsigned byte?
    JR   Z,.byte                        ; Check the value against 0..255.
    CP   enRel8                         ; Is it a relative-branch target?
    JR   Z,.relative                    ; Convert and check signed displacement.
    CP   enDispIX                       ; Is it an IX signed displacement?
    JR   Z,.disp                        ; Check the signed-byte representation.
    CP   enDispIY                       ; Is it an IY signed displacement?
    JR   Z,.disp                        ; Check the same signed-byte range.
.next: ; Continue after accepting or deferring this value.
    LD   HL,prOpIdx                     ; Address the concrete-value scan index.
    INC  (HL)                           ; Advance to the next operand.
    JR   .loop                          ; Continue within the operand count.
.byte: ; Validate an unsigned immediate byte.
    CALL prIsByte                       ; Require an unsigned eight-bit value.
    RET  C                              ; Preserve the range diagnostic.
    JR   .next                          ; Continue after a valid byte.
.disp: ; Validate a sign-extended indexed displacement.

; IX/IY displacement accepts exactly -128..127 represented as a sign-extended
; word or a positive low byte.

    CALL prGetVal                       ; Load the signed displacement word.
    LD   A,H                            ; Inspect its sign-extension byte.
    OR   A                              ; Zero denotes a non-negative value.
    JR   Z,.dispPos                     ; Check the positive half separately.
    INC  A                              ; $FF wraps for negative candidates.
    JP   NZ,prTooBig                    ; Reject any other high byte.
    BIT  7,L                            ; Negative low bytes need bit 7 set.
    JP   Z,prTooBig                     ; Reject -256..-129 representations.
    JR   .next                          ; Accept -128..-1 and continue.
.dispPos: ; Require a non-negative indexed displacement below 128.
    BIT  7,L                            ; Positive bytes must be below $80.
    JP   NZ,prTooBig                    ; Reject 128..255.
    JR   .next                          ; Accept 0..127 and continue.
.relative: ; Compute target minus the address following the instruction.

; Convert target to target-(instruction address+length). The 16-bit arithmetic
; wraps at $FFFF like the Z80 PC; the result must fit a signed byte.

    CALL prGetVal                       ; Load the absolute branch target.
    LD   DE,(prInsPC)                   ; Load the instruction's logical address.
    LD   A,(prInsLen)                   ; Read its validated encoded length.
    ADD  A,E                            ; Add length to the address low byte.
    LD   E,A                            ; Store the next-PC low byte.
    JR   NC,.base                       ; Skip when no carry occurred.
    INC  D                              ; Carry into the address high byte.
.base: ; Subtract the computed next PC from the absolute target.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Subtract the next-instruction address.
    LD   A,H                            ; Inspect the displacement high byte.
    OR   A                              ; Zero means non-negative displacement.
    JR   Z,.relPos                      ; Check the positive half separately.
    INC  A                              ; $FF wraps for negative candidates.
    JP   NZ,prTooFar                    ; Reject missing sign extension.
    BIT  7,L                            ; Negative bytes need bit 7 set.
    JP   Z,prTooFar                     ; Reject values below -128.
    JR   .relStore                      ; Accept -128..-1.
.relPos: ; Require a non-negative branch displacement below 128.
    BIT  7,L                            ; Positive bytes must be below $80.
    JP   NZ,prTooFar                    ; Reject displacements above 127.
.relStore: ; Replace the target word with the validated displacement.

; Replace the absolute target with the encoded displacement for enEmit.

    CALL prStore                        ; Store the signed displacement word.
    JR   .next                          ; Continue checking later operands.
