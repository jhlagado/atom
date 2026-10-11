EN_LEBEG    EQU     $                   ; Begin the LD-form encoder handlers.
.LD: ; Dispatch LD by destination class.

; Destination-first dispatch mirrors the form validator. Each branch below
; handles a source class already accepted for that destination.

    LD   A,(IX+EN_OP0)                  ; Load the destination class.
    CALL EN_IR8                         ; Test ordinary byte register.
    JR   C,.LDREG8                      ; Carry selects byte-register destinations.
    LD   A,(IX+EN_OP0)                  ; Reload the class for the index-half test.
    CALL EN_IHALF                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,.LDHALF                      ; Index-half destinations need a prefix.
    LD   A,(IX+EN_OP0)                  ; Reload the class for the pair test.
    CALL EN_IR16                        ; Test for BC,DE,HL or SP.
    JP   C,.LDREG16                     ; Ordinary pairs use their shared encoder path.
    LD   A,(IX+EN_OP0)                  ; Check index pairs and special destinations.
    CP   EN_IX                          ; Check the IX pair destination.
    JP   Z,.LDIXIY                      ; Reuse the prefixed-pair encoder.
    CP   EN_IY                          ; IY has the same source forms as IX.
    JP   Z,.LDIXIY                      ; Reuse its prefix-aware path.
    CP   EN_I                           ; I loads only from A.
    JP   Z,.LDIRA                       ; Select the ED-prefixed special-register form.
    CP   EN_R                           ; R also loads only from A.
    JP   Z,.LDIRA                       ; Reuse the I/R transfer path.
    CP   EN_MABS                        ; Check for the absolute destination (nn).
    JP   Z,.LDMEMABS                    ; Its source selects the store opcode.
    CP   EN_MEMBC                       ; Check for the indirect destination (BC).
    JP   Z,.LDMEMRRA                    ; (BC) stores only A.
    CP   EN_MEMDE                       ; Check for the indirect destination (DE).
    JP   Z,.LDMEMRRA                    ; Reuse the matching (DE) store path.
    CP   EN_MEMHL                       ; Check for the unprefixed destination (HL).
    JP   Z,.LDMEMHL                     ; Encode its register or immediate source.
    JP   .LDMEMIDX                      ; Remaining accepted destinations are (IX/IY+d).
.LDREG8: ; Select the source for an ordinary byte register.

; Ordinary register destinations divide into register, immediate, memory,
; special-register, indexed-memory and index-half sources.

    LD   A,(IX+EN_OP1)                  ; Load this byte register's source class.
    CALL EN_IR8                         ; Test byte-register source.
    JR   C,.LDREGREG                    ; Carry selects the register-to-register form.
    LD   A,(IX+EN_OP1)                  ; Reload the source class.
    CP   EN_IMM8                        ; Check for an immediate byte.
    JR   Z,.LDREGIMM                    ; Emit opcode followed by the low value byte.
    CP   EN_MEMHL                       ; Check for the unprefixed (HL) source.
    JR   Z,.LDREGMHL                    ; Use the one-byte indirect load form.
    CP   EN_MABS                        ; Check for an absolute-memory source (nn).
    JR   Z,.LDAABS                      ; Validation allows this source only for A.
    CP   EN_MEMBC                       ; Check for the accumulator's (BC) source.
    JR   Z,.LDAMEMRR                    ; Select the 0A opcode family.
    CP   EN_MEMDE                       ; Check for the accumulator's (DE) source.
    JR   Z,.LDAMEMRR                    ; The adjacent class selects 1A in the same path.
    CP   EN_I                           ; Check for the I special-register source.
    JR   Z,.LDAIR                       ; Only A accepts this ED-prefixed transfer.
    CP   EN_R                           ; Check for the R special-register source.
    JR   Z,.LDAIR                       ; Reuse the same A-destination path.
    CALL EN_IDISP                       ; Test for indexed memory with a displacement.
    JR   C,.LDREGIDX                    ; Carry selects the DD/FD memory path.
    JR   .LDRHALF                       ; Validator leaves only an index-half source.
.LDREGREG: ; Combine register fields.

; LD r,r' = 40 | destination<<3 | source.

    LD   B,A                            ; Keep the source register field in B.
    LD   A,(IX+EN_OP0)                  ; Load destination field.
    ADD  A,A                            ; Move its field toward opcode bits 3..5.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,B                            ; Add the source register field in bits 0..2.
    ADD  A,$40                          ; Add LD base 40.
    JP   .LAST1                         ; Emit the one-byte register transfer.
.LDREGIMM: ; Form LD r,n opcode.

; LD r,n = 06 | destination<<3, followed by the low value byte.

    LD   A,(IX+EN_OP0)                  ; Load destination field.
    ADD  A,A                            ; Shift it toward opcode bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,6                            ; Add the immediate-load opcode base.
.V1BYTE2: ; Append source after opcode.
    LD   (EN_TMP+0),A                   ; Stage the opcode before the immediate value.
    LD   A,(IX+EN_VAL1)                 ; Load the source operand's low value byte.
    JP   .LAST2                         ; Append the value and return a two-byte length.
.LDREGMHL: ; Form LD r,(HL) opcode.

; LD r,(HL) = 46 | destination<<3.

    LD   A,(IX+EN_OP0)                  ; Load destination field.
    ADD  A,A                            ; Shift it toward opcode bits 3..5.
    ADD  A,A                            ; Continue the destination-field shift.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,$46                          ; Add the LD r,(HL) opcode base.
    JP   .LAST1                         ; Emit the one-byte indirect load.
.LDAABS: ; Select LD A,(nn).

; LD A,(nn) is 3A followed by the absolute word.

    LD   A,$3A                          ; Select LD A,(nn).
.V1WORD3: ; Append source after opcode.
    LD   (EN_TMP+0),A                   ; Stage opcode before operand one's value word.
    JP   EN_V1AT1                       ; Append operand one's word.
.LDAMEMRR: ; Select LD A,(BC/DE).

; LD A,(BC/DE) uses 0A/1A, derived from the two memory classes.

    SUB  EN_MEMBC                       ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                            ; Start shifting selector toward bit 4.
    ADD  A,A                            ; Continue shifting the selector.
    ADD  A,A                            ; Continue shifting the selector.
    ADD  A,A                            ; Finish the four-bit pair-field shift.
    ADD  A,$0A                          ; Add the LD A,(BC)/(DE) opcode base.
    JP   .LAST1                         ; Emit the one-byte accumulator load.
.LDAIR: ; Select LD A,I or LD A,R.

; LD A,I/R uses ED 57/5F.

    LD   B,$57                          ; Prepare LD A,I's ED suffix.
    CP   EN_I                           ; A still holds the source class I or R.
    JR   Z,.LDAIROP                     ; Keep 57 for I.
    LD   B,$5F                          ; Select 5F for R.
.LDAIROP: ; Continue with the selected I/R suffix in B.
.EDTAIL: ; Prefix suffix B with ED.
    LD   A,$ED                          ; Supply the ED prefix for the shared tail.
.PREFIXB: ; Stage a prefix and suffix B.
    LD   (EN_TMP+0),A                   ; Stage ED or CB before the selected opcode byte.
    LD   A,B                            ; Load the ED suffix or CB opcode byte.
    JP   .LAST2                         ; Append it and return a two-byte length.
.LDREGIDX: ; Encode a displaced indexed-memory load.

; Indexed memory reuses the (HL) opcode after DD/FD and inserts displacement.

    PUSH AF                             ; Preserve flags from the indexed-class test.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select the source index prefix.
    LD   (EN_TMP+0),A                   ; Stage the index prefix as byte zero.
    LD   A,(IX+EN_OP0)                  ; Load destination field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$46                          ; Form 46 | destination<<3 for indexed memory.
    LD   (EN_TMP+1),A                   ; Stage the prefixed LD opcode as byte one.
    POP  AF                             ; Restore entry flags after the field arithmetic.
    LD   A,(IX+EN_VAL1)                 ; Load the indexed source displacement.
    JP   .LAST3                         ; Append displacement and return length three.
.LDRHALF: ; Select index-half source.

; An index-half source reuses H/L's source field behind the selected prefix.

    LD   A,(IX+EN_OP1)                  ; Load IXH/IXL/IYH/IYL as the prefix selector.
    CALL EN_STAGE                       ; Stage DD/FD and restore the source class in A.
    AND  7                              ; Keep the source's H/L register field.
    LD   B,A                            ; Hold that field while forming the destination.
    LD   A,(IX+EN_OP0)                  ; Load the ordinary destination register field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    JR   .LDHALFOP                      ; Join the shared register-field calculation.
.LDHALF: ; Select index-half destination.

; An index-half destination reuses H/L's destination field. Validation has
; already matched the index family when both operands are index halves.

    CALL EN_STAGE                       ; Stage the destination's DD/FD prefix.
    AND  7                              ; Keep its H/L register field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    LD   B,A                            ; Hold destination field while loading source.
    LD   A,(IX+EN_OP1)                  ; Load the validated source register class.
    AND  7                              ; Keep its three-bit register field.
.LDHALFOP: ; Finish prefixed LD r,r'.
    ADD  A,B                            ; Combine register fields.
    ADD  A,$40                          ; Add LD base 40.
    JP   .LAST2                         ; Append the opcode and return a two-byte length.
.LDREG16: ; Select pair-load form.

; Pair destinations cover immediate words and absolute loads. Two pair copies
; expand into byte-register transfers: HL,DE becomes H,D then L,E; BC,DE
; becomes B,D then C,E. LD SP,HL/IX/IY uses the F9 form below.

    LD   A,(IX+EN_OP1)                  ; Load the pair destination's source class.
    CP   EN_IMM16                       ; Check for a 16-bit immediate source.
    JR   Z,.LDRRIMM                     ; Encode its pair opcode and following word.
    CP   EN_MABS                        ; Check for an absolute-memory source.
    JR   Z,.LDRRABS                     ; Select direct HL or ED-prefixed pair loading.
    LD   A,(IX+EN_OP0)                  ; Other accepted forms depend on the destination.
    CP   EN_SP                          ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.LDSP                        ; Encode LD SP,HL/IX/IY.
    CP   EN_HL                          ; HL selects Atom's DE-to-HL pair-copy form.
    LD   A,$62                          ; Prepare LD H,D, the first byte-register copy.
    JR   Z,.LDLEGACY                    ; Keep 62 when the destination is HL.
    LD   A,$42                          ; BC instead starts with LD B,D.
.LDLEGACY: ; Expand the DE pair copy.
    LD   (EN_TMP+0),A                   ; Stage LD H,D or LD B,D.
    ADD  A,9                            ; Form LD L,E or LD C,E as the second opcode.
    JP   .LAST2                         ; Return both expanded copy opcodes.
.LDRRIMM: ; Form LD rr,nn opcode.

; LD rr,nn = 01 | rr<<4 followed by the word.

    LD   A,(IX+EN_OP0)                  ; Load the BC..SP pair class.
    AND  3                              ; Reduce it to the hardware pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Pair field now occupies bits 2..3.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Complete the shift above the low opcode bits.
    INC  A                              ; Add the LD rr,nn opcode base 01.
    JP   .V1WORD3                       ; Append operand one's word.
.LDRRABS: ; Select pair-memory opcode.

; HL has the direct 2A form; BC/DE/SP use ED 4B/5B/7B.

    LD   A,(IX+EN_OP0)                  ; HL has an unprefixed load opcode.
    CP   EN_HL                          ; Check whether the destination is HL.
    JR   Z,.LDHLABS                     ; Select LD HL,(nn) when it is.
    AND  3                              ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Pair reaches bits 4..5.
    ADD  A,$4B                          ; Form ED 4B/5B/7B for BC/DE/SP.
    LD   B,A                            ; Keep the ED suffix while staging its prefix.
    LD   A,$ED                          ; Select the extended-instruction prefix.
    LD   (EN_TMP+0),A                   ; Stage ED before the pair-load suffix.
    LD   A,B                            ; Restore the suffix for the shared word tail.
.V1WORD4: ; Append source after prefix/opcode.
    LD   (EN_TMP+1),A                   ; Stage the opcode after the first prefix byte.
    JP   EN_V1AT2                       ; Append operand one's word.
.LDHLABS: ; Select LD HL,(nn).
    LD   A,$2A                          ; Select the direct LD HL,(nn) opcode.
    JP   .V1WORD3                       ; Append operand one's word after opcode 2A.
.LDSP: ; Select LD SP,HL/IX/IY.

; LD SP,HL is F9; IX/IY use the same opcode behind their prefix.

    LD   A,(IX+EN_OP1)                  ; Load the validated HL/IX/IY source pair.
    CP   EN_HL                          ; HL uses F9 without a prefix.
    LD   A,$F9                          ; Prepare the common LD SP,pair opcode.
    JP   Z,.LAST1                       ; Emit the one-byte HL form when it matched.
    LD   A,(IX+EN_OP1)                  ; Reload IX or IY to select its prefix.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select the source index prefix.
    LD   (EN_TMP+0),A                   ; Stage the index prefix.
    LD   A,$F9                          ; Both indexed forms reuse LD SP,HL's opcode.
    JP   .LAST2                         ; Append F9 and return a two-byte length.
.LDIXIY: ; Select indexed pair load.

; LD IX/IY,nn and LD IX/IY,(nn) are prefixed HL forms 21 and 2A.

    CALL EN_STAGE                       ; Stage DD/FD for the IX/IY destination pair.
    LD   A,(IX+EN_OP1)                  ; Read whether the source is immediate or memory.
    CP   EN_IMM16                       ; Immediate pairs use opcode 21.
    LD   A,$21                          ; Prepare LD IX/IY,nn.
    JR   Z,.LDIXIYOP                    ; Keep 21 for the immediate form.
    LD   A,$2A                          ; Absolute memory uses the HL-form opcode 2A.
.LDIXIYOP: ; Finish indexed pair load.
    JR   .V1WORD4                       ; Append opcode and operand one's value word.
.LDIRA: ; Select LD I,A or LD R,A.

; LD I/R,A uses ED 47/4F.

    LD   B,$47                          ; Prepare LD I,A's ED suffix.
    CP   EN_I                           ; A still holds the I or R destination class.
    JR   Z,.LDIRAOP                     ; Keep 47 for I.
    LD   B,$4F                          ; Select 4F for R.
.LDIRAOP: ; Emit the selected special-register suffix.
    JP   .EDTAIL                        ; Emit ED and the selected I/R transfer suffix.
.LDMEMABS: ; Select absolute store.

; Absolute-memory stores select A, HL, ordinary pairs or IX/IY and append the
; destination address word from operand zero.

    LD   A,(IX+EN_OP1)                  ; Load absolute-store source.
    CP   EN_A                           ; A uses the direct 32 opcode.
    JR   Z,.LDABSA                      ; Route the accumulator store to its tail.
    CALL EN_IR16                        ; Test for BC, DE, HL or SP as the source pair.
    JR   NC,.LDABSIDX                   ; Otherwise validation leaves IX or IY here.
    CP   EN_HL                          ; HL stores without the ED prefix.
    JR   Z,.LDABSHL                     ; Select direct opcode 22 for HL.
    AND  3                              ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Pair reaches bits 4..5.
    ADD  A,$43                          ; Form ED 43/53/73 for BC/DE/SP.
    LD   B,A                            ; Keep the suffix while staging ED.
    LD   A,$ED                          ; Select the extended-instruction prefix.
    LD   (EN_TMP+0),A                   ; Stage ED before the pair-store suffix.
    LD   A,B                            ; Restore the suffix for the address tail.
.V0WORD4: ; Append target after prefix/opcode.
    LD   (EN_TMP+1),A                   ; Stage the opcode after the prefix.
    JP   EN_V0AT2                       ; Append operand zero's word.
.LDABSA: ; Select LD (nn),A.
    LD   A,$32                          ; Select LD (nn),A.
.V0WORD3: ; Append target after opcode.
    LD   (EN_TMP+0),A                   ; Stage opcode before operand zero's value word.
    JP   EN_V0AT1                       ; Append operand zero's word.
.LDABSHL: ; Select LD (nn),HL.
    LD   A,$22                          ; Select the direct LD (nn),HL opcode.
    JR   .V0WORD3                       ; Append operand zero's value word.
.LDABSIDX: ; Prefix LD (nn),IX/IY.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select the source index prefix.
    LD   (EN_TMP+0),A                   ; Stage the index prefix before opcode 22.
    LD   A,$22                          ; The indexed store reuses LD (nn),HL's opcode.
    JR   .V0WORD4                       ; Append opcode and operand zero's value word.
.LDMEMRRA: ; Select LD (BC/DE),A.

; LD (BC/DE),A uses 02/12.

    SUB  EN_MEMBC                       ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                            ; Start shifting selector toward bit 4.
    ADD  A,A                            ; Continue shifting the pair selector.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Complete the shift above opcode base 02.
    ADD  A,$02                          ; Form 02 for (BC) or 12 for (DE).
    JP   .LAST1                         ; Emit the one-byte accumulator store.
.LDMEMHL: ; Select LD (HL),r/n.

; LD (HL),r uses 70 | r; LD (HL),n is 36 n.

    LD   A,(IX+EN_OP1)                  ; Load register/immediate source.
    CP   EN_IMM8                        ; Immediate data uses opcode 36.
    JR   Z,.LDMEMHLN                    ; Route immediate stores to their two-byte form.
    ADD  A,$70                          ; Combine the register field with base 70.
    JP   .LAST1                         ; Emit LD (HL),r in one byte.
.LDMEMHLN: ; Select LD (HL),n.
    LD   A,$36                          ; Select LD (HL),n.
    JP   .V1BYTE2                       ; Append the immediate byte after opcode 36.
.LDMEMIDX: ; Select indexed store.

; LD (IX/IY+d),r reuses 70 | r. The immediate form is four bytes because both
; displacement and immediate data follow the prefixed 36 opcode.

    LD   A,(IX+EN_OP0)                  ; Load the destination's IX+d or IY+d class.
;@EXPECTOUT A
    CALL EN_DDFD                        ; Select the index prefix from destination class.
    LD   (EN_TMP+0),A                   ; Store the prefix as byte zero.
    LD   A,(IX+EN_OP1)                  ; Load register/immediate source.
    CP   EN_IMM8                        ; Immediate stores need opcode 36 and four bytes.
    JR   Z,.LDIDXIMM                    ; Route the immediate form to its four-byte path.
    ADD  A,$70                          ; Combine the real register field with base 70.
.V0BYTE3: ; Append target after prefix/opcode.
    LD   (EN_TMP+1),A                   ; Stage the opcode after the prefix.
    LD   A,(IX+EN_VAL0)                 ; Load operand zero's indexed displacement.
    JP   .LAST3                         ; Use the shared three-byte displacement tail.
.LDIDXIMM: ; Stage displacement then data.
    LD   A,$36                          ; Select the indexed immediate-store opcode.
    LD   (EN_TMP+1),A                   ; Stage 36 after the index prefix.
    LD   A,(IX+EN_VAL0)                 ; Load the indexed destination's displacement.
    LD   (EN_TMP+2),A                   ; Store displacement before immediate data.
    LD   A,(IX+EN_VAL1)                 ; Load the immediate data byte.
.LAST4: ; Finish byte three and return length four.
    LD   (EN_TMP+3),A                   ; Store the final byte of the four-byte encoding.
    JP   EN_D4                          ; Return length four.
EN_LEEND    EQU     $                   ; End the LD-form encoder handlers.
