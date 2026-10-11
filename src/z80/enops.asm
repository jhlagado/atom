.IN: ; Select input port form.

; ED input forms put the register in bits 3..5. Immediate-port input is
; the singleton DB followed by the port byte.

    LD   A,(IX+EN_OP0)                  ; Read the destination or bare-port class.
    CP   EN_PORTC                       ; Bare IN (C) stores its port class in slot zero.
    JR   Z,.INBARE                      ; Route that form to its fixed ED suffix.
    LD   A,(IX+EN_OP1)                  ; Otherwise inspect the source-port class.
    CP   EN_IMM8                        ; An immediate port selects the DB opcode.
    JR   Z,.INIMM                       ; Emit DB followed by the port byte.
    LD   A,(IX+EN_OP0)                  ; Load the destination register class.
    ADD  A,A                            ; Shift its register field toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$40                          ; Add the ED IN r,(C) opcode base.
    JR   .INOUTED                       ; Add ED before this computed suffix.
.INBARE: ; Select bare IN (C).
    LD   A,$70                          ; Select the special IN (C) suffix.
    JR   .INOUTED                       ; Emit it behind the ED prefix.
.INIMM: ; Append the immediate input port.
    LD   A,$DB                          ; Select IN A,(n).
    JP   .V1BYTE2                       ; Append the immediate port byte.
.INOUTED: ; Emit I/O ED suffix.
    LD   B,A                            ; Pass the computed ED suffix to the common tail.
    JP   .EDTAIL                        ; Stage ED and suffix, then return length two.
.OUT: ; Select output port form.

; ED output forms mirror IN; OUT (C),0 has the dedicated ED 71 encoding.

    LD   A,(IX+EN_OP0)                  ; Read the output-port class.
    CP   EN_IMM8                        ; Immediate port selects D3.
    JR   Z,.OUTIMM                      ; Route OUT (n),A to its byte-value tail.
    LD   A,(IX+EN_OP1)                  ; Read the value sent to port C.
    CP   EN_ZERO                        ; Check the special zero-output form.
    LD   A,$71                          ; Prepare the suffix for OUT (C),0.
    JR   Z,.INOUTED                     ; Emit ED 71 when the zero class matched.
    LD   A,(IX+EN_OP1)                  ; Load the ordinary output register class.
    ADD  A,A                            ; Shift its register number toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$41                          ; Add the ED OUT (C),r opcode base.
    JR   .INOUTED                       ; Emit the computed suffix after ED.
.OUTIMM: ; Select OUT (n),A.
    LD   A,$D3                          ; Select OUT (n),A.
.V0BYTE2: ; Append target after opcode.
    LD   (EN_TMP+0),A                   ; Stage the opcode before the immediate.
    LD   A,(IX+EN_VAL0)                 ; Load operand zero's immediate byte.
    JP   .LAST2                         ; Append immediate; return length two.
.BIT: ; Combine CB bit fields.

; CB bit families are operation<<6 | bit<<3 | register. Indexed memory emits
; DD/FD CB displacement opcode, with field 6 when no register is given.

    LD   A,(IX+EN_MNEM)                 ; Read BIT, RES or SET's ordinal.
    SUB  AT_MBIT-1                      ; Map the family to the operation field.
    ADD  A,A                            ; Shift the operation field toward bits 6..7.
    ADD  A,A                            ; Continue moving it into its opcode position.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Advance operation bits left.
    ADD  A,A                            ; Finish operation<<6.
    LD   B,A                            ; Keep the operation field while building others.
    LD   A,(IX+EN_OP0)                  ; Read the enumerated bit-number operand.
    AND  7                              ; Keep bit index 0..7.
    ADD  A,A                            ; Move the bit number into bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish bit<<3.
    ADD  A,B                            ; Combine operation and bit fields.
    LD   B,A                            ; Save both fields for the register field.
    LD   A,(IX+EN_OP1)                  ; Read the register or memory target.
    CALL EN_IDISP                       ; Test indexed-memory target.
    JR   C,.BITINDEX                    ; Indexed forms need prefix and displacement.
    LD   A,(IX+EN_OP1)                  ; Reload the unindexed target class.
    JR   .CBPLAIN                       ; Add its register field to the CB opcode.
.BITINDEX: ; Select indexed copy field.
    LD   A,(IX+EN_OP2)                  ; Read optional copy register.
    CP   EN_NONE                        ; Check for a memory-only indexed operation.
    LD   A,6                            ; Register field 6 encodes memory as the target.
    JR   Z,.BITIDXOP                    ; Keep field 6 when no result register is given.
    LD   A,(IX+EN_OP2)                  ; Otherwise read the destination register class.
    AND  7                              ; Use its three-bit register number.
.BITIDXOP: ; Finish indexed bit operation.
    ADD  A,B                            ; Add the target register field to prior fields.
    LD   B,A                            ; Save the completed second opcode byte.
    LD   A,(IX+EN_OP1)                  ; Reload the indexed memory operand class.
    LD   E,(IX+EN_VAL1)                 ; Save its indexed displacement.
    JR   .CBINDEX                       ; Emit prefix, CB, displacement then opcode.
.ROTATE: ; Map rotate/shift field.

; Rotate/shift bases advance by eight. SLS shares SLL's hardware base,
; so the alias slot is removed before looking up either SLS or SRL.

    LD   A,(IX+EN_MNEM)                 ; Read the rotate/shift mnemonic ordinal.
    SUB  AT_MRLC                        ; Convert it to a zero-based family index.
    CP   7                              ; SLS and SRL need the alias slot removed.
    JR   C,.ROTBASE                     ; Earlier operations use their direct index.
    DEC  A                              ; Map SLS to SLL and SRL to hardware index seven.
.ROTBASE: ; Form rotate/shift bits.
    ADD  A,A                            ; Multiply the operation index by two.
    ADD  A,A                            ; Continue the shift by two bits.
    ADD  A,A                            ; Finish operation<<3.
    LD   B,A                            ; Preserve the operation field for the target.
    LD   A,(IX+EN_OP0)                  ; Read the register or memory operand class.
    CALL EN_IDISP                       ; Test indexed-memory target.
    JR   C,.ROTINDEX                    ; Indexed forms need a four-byte layout.
    LD   A,(IX+EN_OP0)                  ; Reload an unindexed register or (HL) class.
.CBPLAIN: ; Emit plain CB operation.

; Plain register and (HL) forms are CB followed by base | register field.

    AND  7                              ; Extract the target's three-bit register field.
    ADD  A,B                            ; Add target and operation fields.
    LD   B,A                            ; Keep the second CB opcode byte.
    LD   A,$CB                          ; Select the CB prefix.
    JP   .PREFIXB                       ; Store CB and the operation byte.
.ROTINDEX: ; Select indexed copy target.

; Indexed rotate/shift can optionally copy the result to a register; otherwise
; field 6 denotes memory-only operation.

    LD   A,(IX+EN_OP1)                  ; Read optional copy register.
    CP   EN_NONE                        ; Check for memory-only indexed operation.
    LD   A,6                            ; Use register field 6 for memory-only form.
    JR   Z,.ROTIDXOP                    ; Keep that field when there is no copy target.
    LD   A,(IX+EN_OP1)                  ; Otherwise read the copy-target register class.
    AND  7                              ; Extract its three-bit register number.
.ROTIDXOP: ; Finish indexed shift opcode.
    ADD  A,B                            ; Add destination to operation base.
    LD   B,A                            ; Save the indexed CB opcode byte.
    LD   A,(IX+EN_OP0)                  ; Reload the indexed memory class for its prefix.
    LD   E,(IX+EN_VAL0)                 ; Preserve the signed displacement byte.
.CBINDEX: ; Emit DD/FD, CB, displacement then opcode.

; Indexed CB byte order is prefix, CB, displacement, opcode.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select DD for IX or FD for IY.
    LD   (EN_TMP+0),A                   ; Store the index prefix.
    LD   A,$CB                          ; Select the indexed-CB prefix byte.
    LD   (EN_TMP+1),A                   ; Store CB after DD/FD.
    LD   A,E                            ; Load the previously saved displacement.
    LD   (EN_TMP+2),A                   ; Store displacement before the CB opcode.
    LD   A,B                            ; Load the computed bit/rotate opcode byte.
    JP   .LAST4                         ; Store it last and return a four-byte length.
.ALU: ; Select ALU width.

; The byte family ordinal is already the hardware operation field. One-operand
; records use register/memory/immediate equations; two-operand records are the
; separate 16-bit ADD/ADC/SBC forms.

    LD   A,(IX+EN_MNEM)                 ; Read the ALU mnemonic ordinal.
    SUB  AT_MADD                        ; Convert ADD..CP to an operation field.
    ADD  A,A                            ; Move the field toward bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Finish operation<<3.
    LD   B,A                            ; Preserve the operation field.
    LD   A,(IX+EN_OP1)                  ; Check whether a second operand is present.
    CP   EN_NONE                        ; No second operand means the byte-ALU form.
    JR   NZ,.ALU16                      ; Otherwise encode a 16-bit arithmetic form.
    LD   A,(IX+EN_OP0)                  ; Read the byte operand class.
    CP   EN_IMM8                        ; Immediate bytes have a fixed opcode base.
    JR   Z,.ALUIMM                      ; Route the immediate form.
    CALL EN_IHALF                       ; Test whether the operand is an index half.
    JR   C,.ALUHALF                     ; Index halves need DD/FD before the ALU opcode.
    LD   A,(IX+EN_OP0)                  ; Reload the operand class for indexed memory.
    CALL EN_IDISP                       ; Check for (IX/IY+d).
    JR   C,.ALUINDEX                    ; Indexed memory needs prefix and offset.
    LD   A,(IX+EN_OP0)                  ; Reload the register or (HL) class.
    AND  7                              ; Extract the three-bit register field.
    ADD  A,B                            ; Combine register and operation fields.
    ADD  A,$80                          ; Select the register/(HL) ALU opcode range.
    JP   .LAST1                         ; Store and return the one-byte form.
.ALUIMM: ; Select immediate ALU.

; ALU A,n = C6 | operation<<3 followed by the immediate byte.

    LD   A,B                            ; Load operation<<3.
    ADD  A,$C6                          ; Form C6 | operation<<3 for ALU A,n.
    JP   .V0BYTE2                       ; Store opcode then immediate byte.
.ALUHALF: ; Prefix an H/L ALU field.

; IXH/IXL/IYH/IYL reuse H/L fields behind DD/FD.

    LD   A,(IX+EN_OP0)                  ; Load IXH/IXL/IYH/IYL class for prefix choice.
    CALL EN_STAGE                       ; Store DD/FD while preserving the class in A.
    AND  7                              ; Reuse the H/L register field.
    ADD  A,B                            ; Combine index-half and ALU operation fields.
    ADD  A,$80                          ; Form the ordinary register ALU opcode.
    JP   .LAST2                         ; Append it after DD/FD and return length two.
.ALUINDEX: ; Prefix displaced ALU.

; ALU A,(IX/IY+d) reuses the (HL) field 6 and inserts displacement.

    CALL EN_STAGE                       ; Store DD/FD selected from the memory class.
    LD   A,B                            ; Load operation<<3.
    ADD  A,$86                          ; Use register field 6 for indexed memory.
    JP   .V0BYTE3                       ; Append displacement and return length three.
.ALU16: ; Select ADD or ED-prefixed ADC/SBC.

; ADC/SBC HL,rr use ED 4A/42 | rr<<4.

    LD   A,(IX+EN_MNEM)                 ; Read the 16-bit arithmetic mnemonic.
    CP   AT_MADD                        ; Test for ADD's distinct pair form.
    JR   Z,.ADD16                       ; Encode ADD HL/IX/IY,rr separately.
    LD   B,$42                          ; SBC HL,rr uses ED 42 plus pair field.
    CP   AT_MSBC                        ; Select SBC's base opcode.
    JR   Z,.ADCSBC16                    ; Keep 42 for SBC.
    LD   B,$4A                          ; ADC HL,rr uses ED 4A plus pair field.
.ADCSBC16: ; Form pair ADC/SBC opcode.
    LD   A,(IX+EN_OP1)                  ; Read BC, DE, HL or SP source-pair class.
    AND  3                              ; Keep its two-bit register-pair number.
    ADD  A,A                            ; Move the pair field toward bits 4..5.
    ADD  A,A                            ; Continue shifting the field.
    ADD  A,A                            ; Continue shifting the field.
    ADD  A,A                            ; Finish pair<<4.
    ADD  A,B                            ; Combine pair field with ADC/SBC base.
    LD   B,A                            ; Pass the ED suffix to the shared prefix tail.
    JP   .EDTAIL                        ; Emit ED and the computed suffix.
.ADD16: ; Select pair ADD source.

; ADD HL,rr is 09 | rr<<4. IX/IY use a prefix and map a self operand to the HL
; field while BC, DE and SP retain their ordinary pair fields.

    LD   A,(IX+EN_OP1)                  ; Read the source pair class.
    CP   EN_IX                          ; IX's self-pair uses the HL field.
    JR   Z,.ADDSELF                     ; Map IX to pair number two.
    CP   EN_IY                          ; IY's self-pair also uses the HL field.
    JR   Z,.ADDSELF                     ; Map IY to pair number two.
    AND  3                              ; Keep BC, DE, HL or SP pair number.
    JR   .ADD16SRC                      ; Build the 09 + pair<<4 opcode.
.ADDSELF: ; Map IX/IY self-add to the HL field.
    LD   A,2                            ; Select the HL pair field for IX/IY self-add.
.ADD16SRC: ; Form pair ADD opcode.
    ADD  A,A                            ; Shift the source pair field toward bits 4..5.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Finish pair<<4.
    ADD  A,$09                          ; Add the 16-bit ADD opcode base.
    LD   B,A                            ; Save opcode while checking destination.
    LD   A,(IX+EN_OP0)                  ; Read the destination pair class.
    CP   EN_HL                          ; HL needs no index prefix.
    LD   A,B                            ; Restore the computed ADD opcode.
    JP   Z,.LAST1                       ; Emit the unprefixed HL pair form.
    LD   A,(IX+EN_OP0)                  ; Reload IX/IY destination to select its prefix.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Choose DD or FD from destination IX/IY.
    LD   (EN_TMP+0),A                   ; Store the index prefix.
    LD   A,B                            ; Restore the computed ADD pair opcode.
    JR   .LAST2                         ; Append it and return length two.
.JP: ; Select absolute or indirect unconditional JP.

; Absolute JP is C3 nn; JP (HL) is E9 and IX/IY add their prefix.

    LD   A,(IX+EN_OP1)                  ; Test for a condition operand.
    CP   EN_NONE                        ; No second operand selects unconditional JP.
    JR   NZ,.JPCC                       ; Otherwise encode JP cc,nn.
    LD   A,(IX+EN_OP0)                  ; Read the target class for indirect JP.
    CP   EN_MEMHL                       ; JP (HL) uses E9 without a prefix.
    JR   Z,.JPHL                        ; Emit the one-byte indirect form.
    CP   EN_MEMIX                       ; JP (IX) uses the index prefix plus E9.
    JR   Z,.JPINDEX                     ; Share the indexed indirect encoding.
    CP   EN_MEMIY                       ; JP (IY) follows the same form with FD.
    JR   Z,.JPINDEX                     ; Share the indexed indirect encoding.
    LD   A,$C3                          ; Select the absolute JP opcode.
    JP   .V0WORD3                       ; Append target word; return length three.
.JPCC: ; Encode JP condition/target.

; JP cc,nn = C2 | cc<<3 followed by operand one's word.

    LD   B,$C2                          ; Conditional JP base is C2.
    CALL EN_CCOP                        ; Insert condition code in bits 3..5.
    JP   .V1WORD3                       ; Append operand one's address word.
.JPHL: ; Emit JP (HL).
    LD   A,$E9                          ; Select JP (HL).
    JR   .LAST1                         ; Store the single opcode byte.
.JPINDEX: ; Emit JP (IX/IY).
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select DD for IX or FD for IY.
    LD   (EN_TMP+0),A                   ; Store the index prefix.
    LD   A,$E9                          ; Indexed indirect JP uses the same E9 opcode.
    JR   .LAST2                         ; Append E9 and return a two-byte length.
.CALL: ; Select plain or conditional CALL.

; CALL nn is CD nn; CALL cc,nn = C4 | cc<<3.

    LD   A,(IX+EN_OP1)                  ; Test for a condition operand.
    CP   EN_NONE                        ; No second operand selects unconditional CALL.
    JR   NZ,.CALLCC                     ; Otherwise encode CALL cc,nn.
    LD   A,$CD                          ; Select the unconditional CALL opcode.
    JP   .V0WORD3                       ; Append target word; return length three.
.CALLCC: ; Encode CALL condition.
    LD   B,$C4                          ; Conditional CALL base is C4.
    CALL EN_CCOP                        ; Insert condition code in bits 3..5.
    LD   (EN_TMP+0),A                   ; Stage the conditional CALL opcode.
    JR   EN_V1AT1                       ; Append operand one's target word.
.JR: ; Select plain or conditional relative jump.

; JR e is 18 e; JR cc,e = 20 | cc<<3 for the four accepted conditions.

    LD   A,(IX+EN_OP1)                  ; Test for a condition operand.
    CP   EN_NONE                        ; No condition selects unconditional JR.
    JR   NZ,.JRCC                       ; Otherwise encode JR cc,e.
    LD   A,$18                          ; Select unconditional relative-jump opcode.
    LD   (EN_TMP+0),A                   ; Stage the opcode before the displacement.
    LD   A,(IX+EN_VAL0)                 ; Load the assembler-computed relative offset.
    JR   .LAST2                         ; Append the offset and return length two.
.JRCC: ; Encode JR condition/offset.
    LD   B,$20                          ; Conditional JR base is 20.
    CALL EN_CCOP                        ; Insert the condition code in bits 3..5.
    LD   (EN_TMP+0),A                   ; Stage the conditional JR opcode.
    LD   A,(IX+EN_VAL1)                 ; Load operand one's computed displacement.
    JR   .LAST2                         ; Append it and return length two.
.DJNZ: ; Append DJNZ displacement.

; DJNZ is 10 followed by the parser-computed displacement.

    LD   A,$10                          ; Select DJNZ's relative-branch opcode.
    LD   (EN_TMP+0),A                   ; Stage the opcode.
    LD   A,(IX+EN_VAL0)                 ; Load the assembler-computed displacement.
.LAST2: ; Finish byte one and return length two.
    LD   (EN_TMP+1),A                   ; Store the second instruction byte.
    JR   EN_D2                          ; Return successful length two.
.EDTABLE: ; Mnemonic-family handlers.

; Encoder family table selected by AT_DMNEM.

    DW   .COREOP,.RET,.EX               ; Core, return and exchange handlers.
    DW   .IM,.RST,.INCDEC               ; IM, RST and byte/pair INC/DEC.
    DW   .STACK,.LD,.IN                 ; Stack pairs, load and port input.
    DW   .OUT,.BIT,.ROTATE              ; Port output, bit operations and shifts.
    DW   .ALU,.JP,.CALL                 ; Arithmetic and absolute control flow.
    DW   .JR,.DJNZ                      ; Relative branches and decrement-and-branch.
.LAST1: ; Stage a single opcode and return length one.

; Successful returns: carry clear, A = encoded length.

    LD   (EN_TMP+0),A                   ; Stage the one-byte opcode.
