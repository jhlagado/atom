.in: ; Select input port form.

; ED input forms put the register in bits 3..5. Immediate-port input is
; the singleton DB followed by the port byte.

    LD   A,(IX+enOp0)                   ; Read the destination or bare-port class.
    CP   enPortC                        ; Bare IN (C) stores its port class in slot zero.
    JR   Z,.inBare                      ; Route that form to its fixed ED suffix.
    LD   A,(IX+enOp1)                   ; Otherwise inspect the source-port class.
    CP   enImm8                         ; An immediate port selects the DB opcode.
    JR   Z,.inImm                       ; Emit DB followed by the port byte.
    LD   A,(IX+enOp0)                   ; Load the destination register class.
    ADD  A,A                            ; Shift its register field toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$40                          ; Add the ED IN r,(C) opcode base.
    JR   .inOutEd                       ; Add ED before this computed suffix.
.inBare: ; Select bare IN (C).
    LD   A,$70                          ; Select the special IN (C) suffix.
    JR   .inOutEd                       ; Emit it behind the ED prefix.
.inImm: ; Append the immediate input port.
    LD   A,$DB                          ; Select IN A,(n).
    JP   .v1Byte2                       ; Append the immediate port byte.
.inOutEd: ; Emit I/O ED suffix.
    LD   B,A                            ; Pass the computed ED suffix to the common tail.
    JP   .edTail                        ; Stage ED and suffix, then return length two.
.out: ; Select output port form.

; ED output forms mirror IN; OUT (C),0 has the dedicated ED 71 encoding.

    LD   A,(IX+enOp0)                   ; Read the output-port class.
    CP   enImm8                         ; Immediate port selects D3.
    JR   Z,.outImm                      ; Route OUT (n),A to its byte-value tail.
    LD   A,(IX+enOp1)                   ; Read the value sent to port C.
    CP   enZero                         ; Check the special zero-output form.
    LD   A,$71                          ; Prepare the suffix for OUT (C),0.
    JR   Z,.inOutEd                     ; Emit ED 71 when the zero class matched.
    LD   A,(IX+enOp1)                   ; Load the ordinary output register class.
    ADD  A,A                            ; Shift its register number toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$41                          ; Add the ED OUT (C),r opcode base.
    JR   .inOutEd                       ; Emit the computed suffix after ED.
.outImm: ; Select OUT (n),A.
    LD   A,$D3                          ; Select OUT (n),A.
.v0Byte2: ; Append target after opcode.
    LD   (enTemp+0),A                   ; Stage the opcode before the immediate.
    LD   A,(IX+enVal0)                  ; Load operand zero's immediate byte.
    JP   .last2                         ; Append immediate; return length two.
.bit: ; Combine CB bit fields.

; CB bit families are operation<<6 | bit<<3 | register. Indexed memory emits
; DD/FD CB displacement opcode, with field 6 when no register is given.

    LD   A,(IX+enMnem)                  ; Read BIT, RES or SET's ordinal.
    SUB  mneBit-1                       ; Map the family to the operation field.
    ADD  A,A                            ; Shift the operation field toward bits 6..7.
    ADD  A,A                            ; Continue moving it into its opcode position.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Finish operation<<6.
    LD   B,A                            ; Keep the operation field while building others.
    LD   A,(IX+enOp0)                   ; Read the enumerated bit-number operand.
    AND  7                              ; Keep bit index 0..7.
    ADD  A,A                            ; Move the bit number into bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish bit<<3.
    ADD  A,B                            ; Combine operation and bit fields.
    LD   B,A                            ; Save both fields for the register field.
    LD   A,(IX+enOp1)                   ; Read the register or memory target.
    CALL enIsDisp                       ; Test indexed-memory target.
    JR   C,.bitIndex                    ; Indexed forms need prefix and displacement.
    LD   A,(IX+enOp1)                   ; Reload the unindexed target class.
    JR   .cbPlain                       ; Add its register field to the CB opcode.
.bitIndex: ; Select indexed copy field.
    LD   A,(IX+enOp2)                   ; Read optional copy register.
    CP   enNone                         ; Check for a memory-only indexed operation.
    LD   A,6                            ; Register field 6 encodes memory as the target.
    JR   Z,.bitIdxOp                    ; Keep field 6 when no result register is given.
    LD   A,(IX+enOp2)                   ; Otherwise read the destination register class.
    AND  7                              ; Use its three-bit register number.
.bitIdxOp: ; Finish indexed bit operation.
    ADD  A,B                            ; Add the target register field to prior fields.
    LD   B,A                            ; Save the completed second opcode byte.
    LD   A,(IX+enOp1)                   ; Reload the indexed memory operand class.
    LD   E,(IX+enVal1)                  ; Save its indexed displacement.
    JR   .cbIndex                       ; Emit prefix, CB, displacement then opcode.
.rotate: ; Map rotate/shift field.

; Rotate/shift bases advance by eight. SLS shares SLL's hardware base,
; so the alias slot is removed before looking up either SLS or SRL.

    LD   A,(IX+enMnem)                  ; Read the rotate/shift mnemonic ordinal.
    SUB  mneRlc                         ; Convert it to a zero-based family index.
    CP   7                              ; SLS and SRL need the alias slot removed.
    JR   C,.rotBase                     ; Earlier operations use their direct index.
    DEC  A                              ; Map SLS to SLL and SRL to hardware index seven.
.rotBase: ; Form rotate/shift bits.
    ADD  A,A                            ; Multiply the operation index by two.
    ADD  A,A                            ; Continue the shift by two bits.
    ADD  A,A                            ; Finish operation<<3.
    LD   B,A                            ; Preserve the operation field for the target.
    LD   A,(IX+enOp0)                   ; Read the register or memory operand class.
    CALL enIsDisp                       ; Test indexed-memory target.
    JR   C,.rotIndex                    ; Indexed forms need a four-byte layout.
    LD   A,(IX+enOp0)                   ; Reload an unindexed register or (HL) class.
.cbPlain: ; Emit plain CB operation.

; Plain register and (HL) forms are CB followed by base | register field.

    AND  7                              ; Extract the target's three-bit register field.
    ADD  A,B                            ; Add target and operation fields.
    LD   B,A                            ; Keep the second CB opcode byte.
    LD   A,$CB                          ; Select the CB prefix.
    JP   .prefixB                       ; Store CB and the operation byte.
.rotIndex: ; Select indexed copy target.

; Indexed rotate/shift can optionally copy the result to a register; otherwise
; field 6 denotes memory-only operation.

    LD   A,(IX+enOp1)                   ; Read optional copy register.
    CP   enNone                         ; Check for memory-only indexed operation.
    LD   A,6                            ; Use register field 6 for memory-only form.
    JR   Z,.rotIdxOp                    ; Keep that field when there is no copy target.
    LD   A,(IX+enOp1)                   ; Otherwise read the copy-target register class.
    AND  7                              ; Extract its three-bit register number.
.rotIdxOp: ; Finish indexed shift opcode.
    ADD  A,B                            ; Add destination to operation base.
    LD   B,A                            ; Save the indexed CB opcode byte.
    LD   A,(IX+enOp0)                   ; Reload the indexed memory class for its prefix.
    LD   E,(IX+enVal0)                  ; Preserve the signed displacement byte.
.cbIndex: ; Emit DD/FD, CB, displacement then opcode.

; Indexed CB byte order is prefix, CB, displacement, opcode.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select DD for IX or FD for IY.
    LD   (enTemp+0),A                   ; Store the index prefix.
    LD   A,$CB                          ; Select the indexed-CB prefix byte.
    LD   (enTemp+1),A                   ; Store CB after DD/FD.
    LD   A,E                            ; Load the previously saved displacement.
    LD   (enTemp+2),A                   ; Store displacement before the CB opcode.
    LD   A,B                            ; Load the computed bit/rotate opcode byte.
    JP   .last4                         ; Store it last and return a four-byte length.
.alu: ; Select ALU width.

; The byte family ordinal is already the hardware operation field. One-operand
; records use register/memory/immediate equations; two-operand records are the
; separate 16-bit ADD/ADC/SBC forms.

    LD   A,(IX+enMnem)                  ; Read the ALU mnemonic ordinal.
    SUB  mneAdd                         ; Convert ADD..CP to an operation field.
    ADD  A,A                            ; Move the field toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish operation<<3.
    LD   B,A                            ; Preserve the operation field.
    LD   A,(IX+enOp1)                   ; Check whether a second operand is present.
    CP   enNone                         ; No second operand means the byte-ALU form.
    JR   NZ,.alu16                      ; Otherwise encode a 16-bit arithmetic form.
    LD   A,(IX+enOp0)                   ; Read the byte operand class.
    CP   enImm8                         ; Immediate bytes have a fixed opcode base.
    JR   Z,.aluImm                      ; Route the immediate form.
    CALL enIsHalf                       ; Test whether the operand is an index half.
    JR   C,.aluHalf                     ; Index halves need DD/FD before the ALU opcode.
    LD   A,(IX+enOp0)                   ; Reload the operand class for indexed memory.
    CALL enIsDisp                       ; Check for (IX/IY+d).
    JR   C,.aluIndex                    ; Indexed memory needs prefix and offset.
    LD   A,(IX+enOp0)                   ; Reload the register or (HL) class.
    AND  7                              ; Extract the three-bit register field.
    ADD  A,B                            ; Combine register and operation fields.
    ADD  A,$80                          ; Select the register/(HL) ALU opcode range.
    JP   .last1                         ; Store and return the one-byte form.
.aluImm: ; Select immediate ALU.

; ALU A,n = C6 | operation<<3 followed by the immediate byte.

    LD   A,B                            ; Load operation<<3.
    ADD  A,$C6                          ; Form C6 | operation<<3 for ALU A,n.
    JP   .v0Byte2                       ; Store opcode then immediate byte.
.aluHalf: ; Prefix an H/L ALU field.

; IXH/IXL/IYH/IYL reuse H/L fields behind DD/FD.

    LD   A,(IX+enOp0)                   ; Load IXH/IXL/IYH/IYL class for prefix choice.
    CALL enStage                        ; Store DD/FD while preserving the class in A.
    AND  7                              ; Reuse the H/L register field.
    ADD  A,B                            ; Combine index-half and ALU operation fields.
    ADD  A,$80                          ; Form the ordinary register ALU opcode.
    JP   .last2                         ; Append it after DD/FD and return length two.
.aluIndex: ; Prefix displaced ALU.

; ALU A,(IX/IY+d) reuses the (HL) field 6 and inserts displacement.

    CALL enStage                        ; Store DD/FD selected from the memory class.
    LD   A,B                            ; Load operation<<3.
    ADD  A,$86                          ; Use register field 6 for indexed memory.
    JP   .v0Byte3                       ; Append displacement and return length three.
.alu16: ; Select ADD or ED-prefixed ADC/SBC.

; ADC/SBC HL,rr use ED 4A/42 | rr<<4.

    LD   A,(IX+enMnem)                  ; Read the 16-bit arithmetic mnemonic.
    CP   mneAdd                         ; Test for ADD's distinct pair form.
    JR   Z,.add16                       ; Encode ADD HL/IX/IY,rr separately.
    LD   B,$42                          ; SBC HL,rr uses ED 42 plus pair field.
    CP   mneSbc                         ; Select SBC's base opcode.
    JR   Z,.adcSbc16                    ; Keep 42 for SBC.
    LD   B,$4A                          ; ADC HL,rr uses ED 4A plus pair field.
.adcSbc16: ; Form pair ADC/SBC opcode.
    LD   A,(IX+enOp1)                   ; Read BC, DE, HL or SP source-pair class.
    AND  3                              ; Keep its two-bit register-pair number.
    ADD  A,A                            ; Move the pair field toward bits 4..5.
    ADD  A,A                            ; Continue shifting the field.
    ADD  A,A                            ; Continue shifting the field.
    ADD  A,A                            ; Finish pair<<4.
    ADD  A,B                            ; Combine pair field with ADC/SBC base.
    LD   B,A                            ; Pass the ED suffix to the shared prefix tail.
    JP   .edTail                        ; Emit ED and the computed suffix.
.add16: ; Select pair ADD source.

; ADD HL,rr is 09 | rr<<4. IX/IY use a prefix and map a self operand to the HL
; field while BC, DE and SP retain their ordinary pair fields.

    LD   A,(IX+enOp1)                   ; Read the source pair class.
    CP   enRegIX                        ; IX's self-pair uses the HL field.
    JR   Z,.addSelf                     ; Map IX to pair number two.
    CP   enRegIY                        ; IY's self-pair also uses the HL field.
    JR   Z,.addSelf                     ; Map IY to pair number two.
    AND  3                              ; Keep BC, DE, HL or SP pair number.
    JR   .add16Src                      ; Build the 09 + pair<<4 opcode.
.addSelf: ; Map IX/IY self-add to the HL field.
    LD   A,2                            ; Select the HL pair field for IX/IY self-add.
.add16Src: ; Form pair ADD opcode.
    ADD  A,A                            ; Shift the source pair field toward bits 4..5.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Finish pair<<4.
    ADD  A,$09                          ; Add the 16-bit ADD opcode base.
    LD   B,A                            ; Save opcode while checking destination.
    LD   A,(IX+enOp0)                   ; Read the destination pair class.
    CP   enRegHL                        ; HL needs no index prefix.
    LD   A,B                            ; Restore the computed ADD opcode.
    JP   Z,.last1                       ; Emit the unprefixed HL pair form.
    LD   A,(IX+enOp0)                   ; Reload IX/IY destination to select its prefix.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Choose DD or FD from destination IX/IY.
    LD   (enTemp+0),A                   ; Store the index prefix.
    LD   A,B                            ; Restore the computed ADD pair opcode.
    JR   .last2                         ; Append it and return length two.
.jp: ; Select absolute or indirect unconditional JP.

; Absolute JP is C3 nn; JP (HL) is E9 and IX/IY add their prefix.

    LD   A,(IX+enOp1)                   ; Test for a condition operand.
    CP   enNone                         ; No second operand selects unconditional JP.
    JR   NZ,.jpCc                       ; Otherwise encode JP cc,nn.
    LD   A,(IX+enOp0)                   ; Read the target class for indirect JP.
    CP   enMemHL                        ; JP (HL) uses E9 without a prefix.
    JR   Z,.jpHl                        ; Emit the one-byte indirect form.
    CP   enMemIX                        ; JP (IX) uses the index prefix plus E9.
    JR   Z,.jpIndex                     ; Share the indexed indirect encoding.
    CP   enMemIY                        ; JP (IY) follows the same form with FD.
    JR   Z,.jpIndex                     ; Share the indexed indirect encoding.
    LD   A,$C3                          ; Select the absolute JP opcode.
    JP   .v0Word3                       ; Append target word; return length three.
.jpCc: ; Encode JP condition/target.

; JP cc,nn = C2 | cc<<3 followed by operand one's word.

    LD   B,$C2                          ; Conditional JP base is C2.
    CALL enCondOp                       ; Insert condition code in bits 3..5.
    JP   .v1Word3                       ; Append operand one's address word.
.jpHl: ; Emit JP (HL).
    LD   A,$E9                          ; Select JP (HL).
    JR   .last1                         ; Store the single opcode byte.
.jpIndex: ; Emit JP (IX/IY).
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select DD for IX or FD for IY.
    LD   (enTemp+0),A                   ; Store the index prefix.
    LD   A,$E9                          ; Indexed indirect JP uses the same E9 opcode.
    JR   .last2                         ; Append E9 and return a two-byte length.
.call: ; Select plain or conditional CALL.

; CALL nn is CD nn; CALL cc,nn = C4 | cc<<3.

    LD   A,(IX+enOp1)                   ; Test for a condition operand.
    CP   enNone                         ; No second operand selects unconditional CALL.
    JR   NZ,.callCc                     ; Otherwise encode CALL cc,nn.
    LD   A,$CD                          ; Select the unconditional CALL opcode.
    JP   .v0Word3                       ; Append target word; return length three.
.callCc: ; Encode CALL condition.
    LD   B,$C4                          ; Conditional CALL base is C4.
    CALL enCondOp                       ; Insert condition code in bits 3..5.
    LD   (enTemp+0),A                   ; Stage the conditional CALL opcode.
    JR   enOp1At1                       ; Append operand one's target word.
.jr: ; Select plain or conditional relative jump.

; JR e is 18 e; JR cc,e = 20 | cc<<3 for the four accepted conditions.

    LD   A,(IX+enOp1)                   ; Test for a condition operand.
    CP   enNone                         ; No condition selects unconditional JR.
    JR   NZ,.jrCc                       ; Otherwise encode JR cc,e.
    LD   A,$18                          ; Select unconditional relative-jump opcode.
    LD   (enTemp+0),A                   ; Stage the opcode before the displacement.
    LD   A,(IX+enVal0)                  ; Load the assembler-computed relative offset.
    JR   .last2                         ; Append the offset and return length two.
.jrCc: ; Encode JR condition/offset.
    LD   B,$20                          ; Conditional JR base is 20.
    CALL enCondOp                       ; Insert the condition code in bits 3..5.
    LD   (enTemp+0),A                   ; Stage the conditional JR opcode.
    LD   A,(IX+enVal1)                  ; Load operand one's computed displacement.
    JR   .last2                         ; Append it and return length two.
.djnz: ; Append DJNZ displacement.

; DJNZ is 10 followed by the parser-computed displacement.

    LD   A,$10                          ; Select DJNZ's relative-branch opcode.
    LD   (enTemp+0),A                   ; Stage the opcode.
    LD   A,(IX+enVal0)                  ; Load the assembler-computed displacement.
.last2: ; Finish byte one and return length two.
    LD   (enTemp+1),A                   ; Store the second instruction byte.
    JR   enDone2                        ; Return successful length two.
.edTable: ; Mnemonic-family handlers.

; Encoder family table selected by mneDisp.

    DW   .coreOp,.ret,.ex               ; Core, return and exchange handlers.
    DW   .im,.rst,.incDec               ; IM, RST and byte/pair INC/DEC.
    DW   .stack,.ld,.in                 ; Stack pairs, load and port input.
    DW   .out,.bit,.rotate              ; Port output, bit operations and shifts.
    DW   .alu,.jp,.call                 ; Arithmetic and absolute control flow.
    DW   .jr,.djnz                      ; Relative branches and decrement-and-branch.
.last1: ; Stage a single opcode and return length one.

; Successful returns: carry clear, A = encoded length.

    LD   (enTemp+0),A                   ; Stage the one-byte opcode.
