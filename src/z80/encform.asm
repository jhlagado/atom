;==============================================================================
;  Instruction form validation
;==============================================================================
;
;  Check operand classes and arity, then return the exact instruction length.
;  This pass does not read operand values, so forward references can reserve
;  their final fields before their target addresses are known.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Validate only mnemonic and operand classes. No EN_VAL byte is read here, which
; lets unresolved records obtain an exact field layout and instruction length.

EN_LEN:
EN_VFORM:
    LD   A,(IX+EN_MNEM)     ; Load the parsed mnemonic ordinal.
    OR   A                   ; Test for the reserved zero ordinal.
    JP   Z,AT_INVAL          ; Reject zero before indexing a family table.
    CP   AT_MLAST+1          ; Compare with the exclusive upper bound.
    JP   NC,AT_INVAL         ; Reject ordinals outside the supported set.
    LD   DE,.VDTABLE         ; Select the validation-family address table.
    JR   AT_DMNEM             ; Dispatch with the record's original ordinal.
.VCORE:

; The first thirteen core opcodes are one byte; the remaining core group carries
; an ED prefix. All core instructions reject operands.

    CALL AT_RNOPE            ; Require all three operand slots to be empty.
    RET  C                   ; Keep the invalid-form result on any operand.
    LD   A,(IX+EN_MNEM)     ; Reload the ordinal after the arity check.
    CP   14                  ; Split one-byte and ED-prefixed core forms.
    SBC  A,A                 ; Set A to $FF below 14, or zero otherwise.
    ADD  A,2                 ; Convert that selector to an encoded length.
    OR   A                   ; Clear carry and set flags from the length.
    RET                      ; Return the one- or two-byte instruction length.
.VRET:

; RET is either operand-free or takes one of the eight condition classes.

    LD   A,(IX+EN_OP0)       ; Read the optional condition operand.
    CP   EN_NONE             ; The sentinel selects operand-free RET.
    JR   Z,.VL1NOPER         ; Check that all remaining slots are also empty.
    CALL EN_ICOND            ; Test the operand against all eight conditions.
    JP   NC,AT_INVAL         ; Reject a value outside the condition range.
    CALL AT_ROOP             ; Require the second and third slots to be empty.
    RET  C                   ; Preserve a malformed-arity failure.
    XOR  A                   ; Start the successful one-byte length result.
    INC  A                   ; Set the returned length to one.
    RET                      ; Return the conditional RET length.
.VL1NOPER:
    CALL AT_RNOPE            ; Require all three slots to be empty.
    RET  C                   ; Reject any hidden trailing operand.
    XOR  A                   ; Start the successful one-byte length result.
    INC  A                   ; Set the returned length to one.
    RET                      ; Return the operand-free RET length.
.VEX:

; EX admits only AF,AF', DE,HL and (SP),HL/IX/IY.

    CALL AT_RTOPE            ; Allow no more than two EX operands.
    RET  C                   ; Reject a third operand before pair checks.
    LD   A,(IX+EN_OP0)       ; Read the first member of the EX pair.
    CP   EN_AF               ; Check for the AF,AF' exchange form.
    JR   Z,.VEAF             ; Validate its second operand separately.
    CP   EN_DE               ; Check for the DE,HL exchange form.
    JR   Z,.VEDE             ; Validate HL as the second operand.
    CP   EN_MEMSP            ; The remaining form starts with (SP).
    JP   NZ,AT_INVAL         ; Reject every other first operand.
    JP   .VLSP               ; Validate HL/IX/IY and choose its length.
.VEAF:
    LD   A,(IX+EN_OP1)       ; Read the partner of the AF register pair.
    CP   EN_APRIM            ; Only AF' completes this exchange form.
.VZL1:
    JP   Z,EN_D1             ; Return one byte when the operand test matched.
    JP   AT_INVAL            ; Reject any second operand that did not match.
.VEDE:
    LD   A,(IX+EN_OP1)       ; Read the partner of DE.
    CP   EN_HL               ; Only HL completes the DE,HL form.
    JR   .VZL1               ; Reuse the shared match and length result.
.VIM:

; IM mode is encoded in its enumerated operand class, not in the value word.

    CALL AT_ROOP             ; Allow one operand and reject trailing slots.
    RET  C                   ; Stop if an extra operand was supplied.
    LD   A,(IX+EN_OP0)       ; The mode is carried by this operand class.
    CP   EN_IM0              ; Reject modes below IM 0.
    JP   C,AT_INVAL          ; Values below the first mode are invalid.
    CP   EN_IM2+1            ; Compare with the exclusive upper mode bound.
    JP   NC,AT_INVAL         ; Reject values above IM 2.
    JP   EN_D2               ; Every IM mode uses the same two-byte length.
.VRST:
    CALL AT_ROOP             ; Allow one operand and reject trailing slots.
    RET  C                   ; Stop if an extra operand was supplied.
    LD   A,(IX+EN_OP0)       ; Read the enumerated restart-vector class.
    CP   EN_RST0             ; Reject values below vector zero.
    JP   C,AT_INVAL          ; The vector classes begin at RST 0.
    CP   EN_RST56+1          ; Compare with the exclusive RST 56 bound.
    JP   NC,AT_INVAL         ; Reject classes above the final vector.
    JP   EN_D1               ; Every restart instruction encodes in one byte.
.VIDEC:

; INC/DEC cover byte registers, register pairs, IX/IY, index halves, (HL), and
; indexed memory. Prefix and displacement determine the returned length.

    CALL AT_ROOP             ; Allow one operand and reject trailing slots.
    RET  C                   ; Stop if more than one operand was supplied.
    LD   A,(IX+EN_OP0)       ; Test the operand as an ordinary byte register.
    CALL EN_IR8              ; Carry accepts B,C,D,E,H,L or A.
    JP   C,EN_D1             ; Ordinary byte registers need one opcode byte.
    LD   A,(IX+EN_OP0)       ; Reload the class for the 16-bit register test.
    CALL EN_IR16             ; Carry accepts BC,DE,HL or SP.
    JP   C,EN_D1             ; Ordinary pairs also need one opcode byte.
    LD   A,(IX+EN_OP0)       ; Check the index-register pair classes.
    CP   EN_IX               ; IX uses a DD-prefixed instruction.
    JP   Z,EN_D2             ; The prefix makes the instruction two bytes.
    CP   EN_IY               ; IY uses the corresponding FD prefix.
    JP   Z,EN_D2             ; Its instruction length is also two bytes.
    CALL EN_IHIND            ; Test for IXH, IXL, IYH or IYL.
    JP   C,EN_D2             ; An index half adds one prefix byte.
    LD   A,(IX+EN_OP0)       ; Reload the operand after the class predicate.
    CP   EN_MEMHL            ; Check for the unprefixed (HL) memory form.
    JP   Z,EN_D1             ; INC/DEC (HL) uses one opcode byte.
    CALL EN_IINDE            ; Test for indexed memory with a displacement.
.VCL3:
    JP   C,EN_D3             ; Prefix and displacement make a three-byte form.
    JP   AT_INVAL            ; Reject every operand class not accepted above.
.VSTACK:

; PUSH/POP accept the four ordinary stack pairs plus IX and IY.

    CALL AT_ROOP             ; Allow one operand and reject trailing slots.
    RET  C                   ; Stop if a second operand was supplied.
    LD   A,(IX+EN_OP0)       ; Read the stack-pair operand class.
    CP   EN_BC               ; Check the first ordinary stack pair.
    JP   Z,EN_D1             ; PUSH/POP BC needs one opcode byte.
    CP   EN_DE               ; Compare with the next ordinary pair.
    JP   Z,EN_D1             ; PUSH/POP DE also needs one opcode byte.
    CP   EN_HL               ; Compare with the HL stack pair.
    JP   Z,EN_D1             ; PUSH/POP HL needs one opcode byte.
    CP   EN_AF               ; AF is the fourth ordinary stack pair.
    JP   Z,EN_D1             ; PUSH/POP AF uses the unprefixed form.
.VIL2:
    CP   EN_IX               ; Check for the IX class.
    JP   Z,EN_D2             ; Accept IX as a two-byte form.
    CP   EN_IY               ; Check for the IY class.
.VZL2:
    JP   Z,EN_D2             ; Return two bytes when the prior test matched.
    JP   AT_INVAL            ; Reject the unmatched operand form.
EN_LVBEG EQU $
.VLD:

; LD is the broadest family. Dispatch first by destination class, then prove the
; exact source pairing and its length. Index-half rules are intentionally strict:
; two half registers must belong to the same IX or IY family, and ordinary H/L
; cannot mix with an index half. Indexed memory uses the real H/L register field.

    CALL AT_RTOPE            ; Reject a third operand before class dispatch.
    RET  C                   ; Propagate an operand-count failure.
    LD   A,(IX+EN_OP0)       ; Load destination class for family dispatch.
    CALL EN_IR8              ; Carry marks an ordinary eight-bit register.
    JR   C,.VLR8             ; Validate its source in the byte-register path.
    LD   A,(IX+EN_OP0)       ; Reload the class after the register test.
    CALL EN_IHIND            ; Test for an IXH, IXL, IYH or IYL destination.
    JP   C,.VLHALF           ; Check its source and index family.
    LD   A,(IX+EN_OP0)       ; Reload the class for the ordinary pair test.
    CALL EN_IR16             ; Carry marks BC, DE, HL or SP.
    JP   C,.VLR16            ; Validate the source in the pair-load path.
    LD   A,(IX+EN_OP0)       ; Check the remaining special destinations.
    CP   EN_IX               ; Select the IX pair destination.
    JP   Z,.VLI16            ; IX accepts immediate or absolute memory.
    CP   EN_IY               ; Select the IY pair destination.
    JP   Z,.VLI16            ; IY uses the same validation and length rules.
    CP   EN_I                ; The I register has an A-only source form.
    JP   Z,.VLSPECIA         ; Share it with the corresponding R form.
    CP   EN_R                ; The R register also loads only from A.
    JP   Z,.VLSPECIA         ; Route special-register validation together.
    CP   EN_MABS             ; Test for absolute memory destination (nn).
    JP   Z,.VLMABS           ; Check its A or register-pair source.
    CP   EN_MEMBC            ; Test for the indirect destination (BC).
    JP   Z,.VLMPAIR          ; Its only source is A.
    CP   EN_MEMDE            ; Test for the indirect destination (DE).
    JP   Z,.VLMPAIR          ; Reuse the A-only indirect-store check.
    CP   EN_MEMHL            ; Test for the indirect destination (HL).
    JP   Z,.VLMHL            ; Check its register or immediate source.
    CALL EN_IINDE            ; Test for a displaced IX/IY destination.
    JP   C,.VLINDEXE         ; Validate the source in the indexed-memory path.
    JP   AT_INVAL            ; Reject every other destination class.
.VLR8:

; Ordinary eight-bit destination: r, n, (HL), absolute/BC/DE memory when A, the
; special I/R transfers when A, indexed memory, or an index-half source.

    LD   A,(IX+EN_OP1)       ; Load the source class for this byte register.
    CALL EN_IR8              ; Test for an ordinary byte-register source.
    JP   C,EN_D1             ; Two byte registers encode in one byte.
    LD   A,(IX+EN_OP1)       ; Reload the source class after the predicate.
    CP   EN_IMM8             ; Check for an immediate byte source.
    JP   Z,EN_D2             ; The opcode is followed by its immediate byte.
    CP   EN_MEMHL            ; Check for the unprefixed (HL) source.
    JP   Z,EN_D1             ; A register loaded from (HL) uses one byte.
    CP   EN_MABS             ; Check for an absolute address source.
    JR   Z,.VLR8ABSO         ; Share the accumulator-only memory checks.
    CP   EN_MEMBC            ; Check for the accumulator's (BC) source form.
    JR   Z,.VLR8ACCU         ; Route indirect accumulator sources together.
    CP   EN_MEMDE            ; Check for the accumulator's (DE) source form.
    JR   Z,.VLR8ACCU         ; Reuse the same accumulator-only check.
    CP   EN_I                ; Check for a special-register source.
    JR   Z,.VLR8A2           ; LD A,I is the only valid destination pairing.
    CP   EN_R                ; Check for the other special-register source.
    JR   Z,.VLR8A2           ; LD A,R follows the same two-byte rule.
    CALL EN_IINDE            ; Test for an indexed-memory source.
    JP   C,EN_D3             ; Indexed source uses a three-byte form.
    LD   A,(IX+EN_OP1)       ; Reload the source class for index-half testing.
    CALL EN_IHIND            ; Check for IXH, IXL, IYH or IYL.
    JP   NC,AT_INVAL         ; Reject sources outside the forms tested above.
    LD   A,(IX+EN_OP0)       ; Load destination for the H/L collision test.
.VLNRHALF:
    CP   EN_H                ; H cannot encode as an index half in this form.
    JP   Z,AT_INVAL          ; Reject the mixed real-H/index-half pairing.
    CP   EN_L                ; L has the same index-half collision.
    JP   Z,AT_INVAL          ; Reject the mixed real-L/index-half pairing.
    JP   EN_D2               ; Other byte registers use a prefixed opcode.
.VLR8ABSO:
.VLR8ACCU:
    LD   A,(IX+EN_OP0)       ; Load the destination for A-only memory forms.
    CP   EN_A                ; Absolute and (BC)/(DE) forms require A.
    JP   NZ,AT_INVAL         ; Reject any other byte-register destination.
    LD   A,(IX+EN_OP1)       ; Recover the source class after checking A.
    CP   EN_MABS             ; Only (nn) carries a two-byte address.
    JP   Z,EN_D3             ; Prefix-free opcode plus the absolute address.
    JP   EN_D1               ; The (BC)/(DE) forms contain only the opcode.
.VLR8A2:
    LD   A,(IX+EN_OP0)       ; Load the destination for LD A,I/R.
    CP   EN_A                ; The special-register forms require A.
.VNL2:
    JP   NZ,AT_INVAL         ; Reject unless the preceding test matched.
    JP   EN_D2               ; Return the shared two-byte form length.
.VLHALF:

; Half-register forms require an index prefix and reject H/L collisions. XOR bit
; 3 below proves that source and destination belong to the same IX/IY family.

    LD   A,(IX+EN_OP1)       ; Load source class for the half-register test.
    CALL EN_IHIND            ; Carry identifies an IX/IY half-register source.
    JR   C,.VLHFAMIL         ; Require both halves to belong to IX or IY.
    LD   A,(IX+EN_OP1)       ; Reload source for the ordinary-register test.
    CALL EN_IR8              ; Carry accepts a real eight-bit register source.
    JP   NC,AT_INVAL         ; Reject immediate and memory sources for a half.
    JR   .VLNRHALF           ; Apply the H/L collision test before accepting.
.VLHFAMIL:
    LD   A,(IX+EN_OP0)       ; Load the destination half class.
    LD   B,A                 ; B retains it while the source class is loaded.
    LD   A,(IX+EN_OP1)       ; Load the source half class for comparison.
    XOR  B                   ; Bit 3 differs only between IX and IY classes.
    AND  $08                 ; Keep the family bit and discard half selection.
    JR   .VNL2               ; Require the index families to match.
.VLR16:

; Ordinary pair destinations accept immediate and absolute loads, LD SP,HL, and
; Atom's two pair-copy expansions from DE. IX/IY destinations branch separately.

    LD   A,(IX+EN_OP1)       ; Load the source class for an ordinary pair.
    CP   EN_IMM16            ; Check for a 16-bit immediate value.
    JP   Z,EN_D3             ; Opcode plus the little-endian word takes three.
    CP   EN_MABS             ; Check for an absolute memory address source.
    JR   Z,.VLR1ABSO         ; Pair size determines its encoded length.
    LD   A,(IX+EN_OP0)       ; Load the destination for pair-copy forms.
    CP   EN_SP               ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.VLSP             ; Check prefixed sources and their lengths.
    CP   EN_HL               ; HL may use Atom's DE pair-copy form.
    JR   Z,.VLLHL            ; Route HL through the DE-source pair-copy check.
    CP   EN_BC               ; BC has the matching pair-copy form.
    JR   Z,.VLLBC            ; Route BC through the same source-pair check.
    JP   AT_INVAL            ; Reject other pair-to-pair combinations.
.VLR1ABSO:
    LD   A,(IX+EN_OP0)       ; Keep the destination pair for length selection.
    JR   .VLAPLEN            ; HL is three bytes; other pairs take four.
.VLSP:
    LD   A,(IX+EN_OP1)       ; Load the second operand for the HL/IX/IY check.
    CP   EN_HL               ; Test for the unprefixed HL form.
    JP   Z,EN_D1             ; An HL operand selects the one-byte form.
    JP   .VIL2               ; Shared tail checks the prefixed IX/IY forms.
.VLLHL:
.VLLBC:
    LD   A,(IX+EN_OP1)       ; Load the source for either pair-copy form.
    CP   EN_DE               ; Both accepted forms take DE as their source.
    JP   .VZL2               ; Return two bytes for a match, else reject it.
.VLI16:
    LD   A,(IX+EN_OP1)       ; Load the source for an IX/IY destination.
    CP   EN_IMM16            ; Check for a 16-bit immediate source.
    JP   Z,EN_D4             ; Prefix, opcode and immediate word take four.
    CP   EN_MABS             ; Check for an absolute address source.
.VZL4:
    JP   Z,EN_D4             ; The preceding accepted form takes four bytes.
    JP   AT_INVAL            ; Reject the source class that failed the test.
.VLSPECIA:
    LD   A,(IX+EN_OP1)       ; Load the source for the special I/R register.
    CP   EN_A                ; The only valid source is A.
    JP   .VZL2               ; Return two bytes on a match.
.VLMABS:
    LD   A,(IX+EN_OP1)       ; Load the source for absolute memory (nn).
    CP   EN_A                ; A stores directly to the absolute address.
    JP   Z,EN_D3             ; Opcode plus the two-byte address takes three.
    CALL EN_IR16             ; Test whether the source is an ordinary pair.
    JR   NC,.VLMAINDE        ; IX and IY need the separate prefixed check.
.VLAPLEN:
    CP   EN_HL               ; HL uses the unprefixed absolute-memory form.
    JP   Z,EN_D3             ; Its opcode plus address take three bytes.
    JP   EN_D4               ; Other accepted pairs need a prefix byte.
.VLMAINDE:
    CP   EN_IX               ; Check for an IX pair source.
    JP   Z,EN_D4             ; DD prefix, opcode and address take four bytes.
    CP   EN_IY               ; Otherwise check for an IY pair source.
    JR   .VZL4               ; Reuse the common four-byte acceptance tail.
.VLMPAIR:
    LD   A,(IX+EN_OP1)       ; Load the source for destination (BC) or (DE).
    CP   EN_A                ; Both indirect stores require A.
    JP   .VZL1               ; Return one byte on a match.
.VLMHL:
    LD   A,(IX+EN_OP1)       ; Load the source for destination (HL).
    CALL EN_IR8              ; Carry accepts an ordinary byte register.
    JP   C,EN_D1             ; A register stored through HL takes one byte.
    CP   EN_IMM8             ; Otherwise check for an immediate byte source.
    JP   .VZL2               ; Return two bytes if it matches.
.VLINDEXE:
    LD   A,(IX+EN_OP1)       ; Load the source for destination (IX/IY+d).
    CALL EN_IR8              ; Carry accepts an ordinary byte register.
    JP   C,EN_D3             ; Prefix, opcode and displacement take three.
    CP   EN_IMM8             ; Otherwise check for an immediate byte source.
    JR   .VZL4               ; That form adds a fourth byte for the value.
EN_LVEND EQU $
.VIN:

; IN r,(C), IN (C), or IN A,(n). Bare IN (C) has one parsed operand.

    LD   A,(IX+EN_OP0)
    CP   EN_PORTC
    JR   Z,.VIONE
    CALL EN_IR8
    JP   NC,AT_INVAL
    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_OP1)
    CP   EN_PORTC
    JP   Z,EN_D2
    CP   EN_IMM8
    JP   NZ,AT_INVAL
    LD   A,(IX+EN_OP0)
    CP   EN_A
    JP   .VNL2
.VIONE:
    CALL AT_ROOP
    RET  C
    JP   EN_D2
.VOUT:

; OUT (C),r, OUT (C),0, or OUT (n),A.

    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_OP0)
    CP   EN_PORTC
    JR   Z,.VOC
    CP   EN_IMM8
    JP   NZ,AT_INVAL
    LD   A,(IX+EN_OP1)
    CP   EN_A
    JP   .VNL2
.VOC:
    LD   A,(IX+EN_OP1)
    CP   EN_ZERO
    JP   Z,EN_D2
    CALL EN_IR8
.VCL2:
    JP   C,EN_D2
    JP   AT_INVAL
.VBIT:

; BIT/RES/SET use an enumerated bit class followed by register, (HL), or indexed
; memory. Indexed RES/SET may carry a third destination register; BIT may not.

    LD   A,(IX+EN_OP0)
    CALL EN_IBIND
    JP   NC,AT_INVAL
    LD   A,(IX+EN_OP1)
    CALL EN_IR8
    JR   C,.VBPLAIN
    CP   EN_MEMHL
    JR   Z,.VBPLAIN
    CALL EN_IINDE
    JP   NC,AT_INVAL
    LD   A,(IX+EN_MNEM)
    CP   AT_MBIT
    JR   Z,.VBINDST
    LD   A,(IX+EN_OP2)
    JR   .VOR8L4
.VBINDST:
    CALL AT_RTOPE
    RET  C
    JP   EN_D4
.VBPLAIN:
    CALL AT_RTOPE
    RET  C
    JP   EN_D2
.VROTATE:

; Rotate/shift takes an ordinary register, (HL), or indexed memory. Indexed forms
; may optionally copy the result to an ordinary register.

    LD   A,(IX+EN_OP0)
    CALL EN_IR8
    JR   C,.VRPLAIN
    CP   EN_MEMHL
    JR   Z,.VRPLAIN
    CALL EN_IINDE
    JP   NC,AT_INVAL
    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_OP1)
.VOR8L4:
    CP   EN_NONE
    JP   Z,EN_D4
    CALL EN_IR8
    JP   C,EN_D4
    JP   AT_INVAL
.VRPLAIN:
    JP   .VIONE
.VALU:

; One-operand ALU forms cover byte register/memory/immediate operands. The parser
; has already removed an explicit A alias. Two-operand records are the 16-bit
; ADD/ADC/SBC families and retain their explicit destination.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.VA16
    CALL AT_ROOP
    RET  C
    LD   A,(IX+EN_OP0)
    CALL EN_IR8
    JP   C,EN_D1
    CP   EN_MEMHL
    JP   Z,EN_D1
    CP   EN_IMM8
    JP   Z,EN_D2
    CALL EN_IHIND
    JP   C,EN_D2
    LD   A,(IX+EN_OP0)
    CALL EN_IINDE
    JP   .VCL3
.VA16:
    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_MNEM)
    CP   AT_MADD
    JR   Z,.VA161
    CP   AT_MADC
    JR   Z,.VAS16
    CP   AT_MSBC
    JP   NZ,AT_INVAL
.VAS16:
    LD   A,(IX+EN_OP0)
    CP   EN_HL
    JP   NZ,AT_INVAL
    LD   A,(IX+EN_OP1)
    CALL EN_IR16
    JP   .VCL2
.VA161:
    LD   A,(IX+EN_OP0)
    CP   EN_HL
    JR   Z,.VAHL
    CP   EN_IX
    JR   Z,.VAINDEX
    CP   EN_IY
    JP   NZ,AT_INVAL
.VAINDEX:
    LD   B,A
    LD   A,(IX+EN_OP1)
    CP   EN_BC
    JP   Z,EN_D2
    CP   EN_DE
    JP   Z,EN_D2
    CP   EN_SP
    JP   Z,EN_D2
    CP   B
    JP   .VZL2
.VAHL:
    LD   A,(IX+EN_OP1)
    CALL EN_IR16
    JP   C,EN_D1
    JP   AT_INVAL
.VJP:

; JP accepts an absolute word, (HL), (IX), (IY), or condition plus absolute word.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.VJCONDIT
    CALL AT_ROOP
    RET  C
    LD   A,(IX+EN_OP0)
    CP   EN_IMM16
    JP   Z,EN_D3
    CP   EN_MEMHL
    JP   Z,EN_D1
    CP   EN_MEMIX
    JP   Z,EN_D2
    CP   EN_MEMIY
    JP   .VZL2
.VJCONDIT:
    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_OP0)
    CALL EN_ICOND
    JR   NC,AT_INVAL
    LD   A,(IX+EN_OP1)
.VAL3:
    CP   EN_IMM16
    JP   Z,EN_D3
    JR   AT_INVAL
.VCALL:
    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.VCCONDIT
    CALL AT_ROOP
    RET  C
    LD   A,(IX+EN_OP0)
    JR   .VAL3
.VCCONDIT:
    JR   .VJCONDIT
.VJR:

; JR has an unconditional relative form and only the four hardware-supported
; conditions NZ, Z, NC and C.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.VJCONDI1
    CALL AT_ROOP
    RET  C
    JR   .VROP
.VJCONDI1:
    CALL AT_RTOPE
    RET  C
    LD   A,(IX+EN_OP0)
    CALL EN_IRCON
    JR   NC,AT_INVAL
    LD   A,(IX+EN_OP1)
    CP   EN_REL8
    JP   Z,EN_D2
    JR   AT_INVAL
.VDJNZ:
    CALL AT_ROOP
    RET  C
.VROP:
    LD   A,(IX+EN_OP0)
    CP   EN_REL8
    JP   Z,EN_D2
    JR   AT_INVAL
.VDTABLE:

; Validator family table selected by AT_DMNEM.

    DW .VCORE,.VRET,.VEX
    DW .VIM,.VRST,.VIDEC
    DW .VSTACK,.VLD,.VIN
    DW .VOUT,.VBIT,.VROTATE
    DW .VALU,.VJP,.VCALL
    DW .VJR,.VDJNZ

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; All invalid forms return A=0 with carry set and publish no output.

AT_INVAL:
    XOR  A                   ; Clear the length returned for an invalid form.
    SCF                      ; Mark validation failure in carry.
    RET                      ; Return without publishing encoded bytes.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Cascading operand-count checks: no operands, at most one, or at most two.

AT_RNOPE:
    LD   A,(IX+EN_OP0)      ; Read the first operand slot.
    CP   EN_NONE             ; The sentinel means that the slot is empty.
    JR   NZ,AT_RBAD          ; Reject any operand in this no-operand form.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slots one and two to be empty, allowing at most one operand.

AT_ROOP:
    LD   A,(IX+EN_OP1)      ; Read the second operand slot.
    CP   EN_NONE             ; A one-operand form leaves this slot empty.
    JR   NZ,AT_RBAD          ; Reject a second operand when one is disallowed.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Require operand slot two to be empty, allowing at most two operands.

AT_RTOPE:
    LD   A,(IX+EN_OP2)      ; Read the third and final operand slot.
    CP   EN_NONE             ; Require the third operand slot to be empty.
    JR   NZ,AT_RBAD          ; Reject a supplied third operand.
    OR   A                   ; Clear carry to report valid operand count.
    RET                      ; Return the successful arity check.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common invalid-form result with carry set.

AT_RBAD:
    XOR  A                   ; Clear the length for an invalid operand count.
    SCF                      ; Mark the arity check as failed.
    RET                      ; Return the shared invalid-form result.

;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Carry set means ordinary eight-bit register B..L or A; class 6 is (HL), so it
; is excluded from this predicate despite sharing the hardware field range.

EN_IR8:
    CP   EN_MEMHL            ; Values below class six are B through L.
    RET  C                   ; Accept those ordinary register classes.
    CP   EN_A                ; Check the remaining ordinary register class.
    JR   Z,AT_PYES           ; Accept A, but not the (HL) class at six.
    CP   A                   ; Clear carry for every class not accepted above.
    RET                      ; Return the predicate result in carry.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Carry set means BC, DE, HL or SP.

EN_IR16:
    CP   EN_BC               ; Reject classes below the first register pair.
    JR   C,AT_PNO            ; Values below BC are not 16-bit pairs.
    CP   EN_SP+1             ; Compare against the exclusive pair upper bound.
    RET                      ; Carry accepts BC, DE, HL and SP.

;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Preserve A while recognising IXH/IXL/IYH/IYL through their shared bit pattern.

EN_IHIND:
    PUSH BC                  ; Preserve BC while C holds the original class.
    LD   C,A                 ; Save the operand class before masking A.
    AND  $F6                 ; Map all four index halves to one bit pattern.
    CP   EN_IXH              ; Compare with the shared IXH pattern.
    LD   A,C                 ; Restore the operand class for the caller.
    POP  BC                  ; Restore the caller's BC value.
    JR   Z,AT_PYES           ; Accept when the reduced pattern matched.
    JR   AT_PNO              ; Return carry clear for every other class.

;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Carry set means displacement-bearing (IX+d) or (IY+d).

EN_IINDE:
    CP   EN_IIX              ; Reject classes below indexed IX memory.
    JR   C,AT_PNO            ; Only IX+d and IY+d belong to this range.
    CP   EN_IIY+1            ; Compare against the exclusive IY+d bound.
    RET                      ; Carry is set only for the two indexed classes.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; All eight condition classes, in hardware field order.

EN_ICOND:
    CP   EN_NZ               ; Reject classes before the condition range.
    JR   C,AT_PNO            ; NZ is the first encoded condition class.
    CP   EN_M+1              ; Compare against the exclusive condition bound.
    RET                      ; Carry accepts all eight Z80 conditions.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; The four condition classes implemented by JR.

EN_IRCON:
    CP   EN_NZ               ; Reject classes before the JR condition range.
    JR   C,AT_PNO            ; NZ is the first condition supported by JR.
    CP   EN_CC+1             ; Stop after C, the last JR condition class.
    RET                      ; Carry accepts NZ, Z, NC and C.

;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Enumerated bit-number classes BIT0..BIT7.

EN_IBIND:
    CP   EN_BIT0             ; Reject classes below enumerated bit zero.
    JR   C,AT_PNO            ; Only the eight bit-number classes are accepted.
    CP   EN_BIT7+1           ; Compare against the exclusive bit-number bound.
    RET                      ; Carry accepts BIT0 through BIT7.

;@ROUTINE IN A OUT CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return the common predicate result for a value outside the accepted range.

AT_PNO:
    CP   A                   ; Compare A with itself to clear carry.
    RET                      ; Return the predicate's rejected result.

;@ROUTINE OUT CARRY CLOBBERS HALFCARRY
; Return the common predicate result for a value inside the accepted range.

AT_PYES:
    SCF                      ; Set carry to mark the predicate as successful.
    RET                      ; Return the accepted-class result.
EN_VCEND:
