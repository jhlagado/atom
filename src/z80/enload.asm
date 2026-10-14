enLdEBeg    EQU     $                   ; Begin the LD-form encoder handlers.
.ld: ; Dispatch LD by destination class.

; Destination-first dispatch mirrors the form validator. Each branch below
; handles a source class already accepted for that destination.

    LD   A,(IX+enOp0)                   ; Load the destination class.
    CALL enIsReg8                       ; Test ordinary byte register.
    JR   C,.ldReg8                      ; Carry selects byte-register destinations.
    LD   A,(IX+enOp0)                   ; Reload the class for the index-half test.
    CALL enIsHalf                       ; Test for IXH, IXL, IYH or IYL.
    JP   C,.ldHalf                      ; Index-half destinations need a prefix.
    LD   A,(IX+enOp0)                   ; Reload the class for the pair test.
    CALL enIsPair                       ; Test for BC,DE,HL or SP.
    JP   C,.ldReg16                     ; Ordinary pairs use their shared encoder path.
    LD   A,(IX+enOp0)                   ; Check index pairs and special destinations.
    CP   enRegIX                        ; Check the IX pair destination.
    JP   Z,.ldIxIy                      ; Reuse the prefixed-pair encoder.
    CP   enRegIY                        ; IY has the same source forms as IX.
    JP   Z,.ldIxIy                      ; Reuse its prefix-aware path.
    CP   enRegI                         ; I loads only from A.
    JP   Z,.ldIrA                       ; Select the ED-prefixed special-register form.
    CP   enRegR                         ; R also loads only from A.
    JP   Z,.ldIrA                       ; Reuse the I/R transfer path.
    CP   enMemAbs                       ; Check for the absolute destination (nn).
    JP   Z,.ldMemAbs                    ; Its source selects the store opcode.
    CP   enMemBC                        ; Check for the indirect destination (BC).
    JP   Z,.ldMemRrA                    ; (BC) stores only A.
    CP   enMemDE                        ; Check for the indirect destination (DE).
    JP   Z,.ldMemRrA                    ; Reuse the matching (DE) store path.
    CP   enMemHL                        ; Check for the unprefixed destination (HL).
    JP   Z,.ldMemHl                     ; Encode its register or immediate source.
    JP   .ldMemIdx                      ; Remaining accepted destinations are (IX/IY+d).
.ldReg8: ; Select the source for an ordinary byte register.

; Ordinary register destinations divide into register, immediate, memory,
; special-register, indexed-memory and index-half sources.

    LD   A,(IX+enOp1)                   ; Load this byte register's source class.
    CALL enIsReg8                       ; Test byte-register source.
    JR   C,.ldRegReg                    ; Carry selects the register-to-register form.
    LD   A,(IX+enOp1)                   ; Reload the source class.
    CP   enImm8                         ; Check for an immediate byte.
    JR   Z,.ldRegImm                    ; Emit opcode followed by the low value byte.
    CP   enMemHL                        ; Check for the unprefixed (HL) source.
    JR   Z,.ldRegMHl                    ; Use the one-byte indirect load form.
    CP   enMemAbs                       ; Check for an absolute-memory source (nn).
    JR   Z,.ldAAbs                      ; Validation allows this source only for A.
    CP   enMemBC                        ; Check for the accumulator's (BC) source.
    JR   Z,.ldAMemRr                    ; Select the 0A opcode family.
    CP   enMemDE                        ; Check for the accumulator's (DE) source.
    JR   Z,.ldAMemRr                    ; The adjacent class selects 1A in the same path.
    CP   enRegI                         ; Check for the I special-register source.
    JR   Z,.ldAIr                       ; Only A accepts this ED-prefixed transfer.
    CP   enRegR                         ; Check for the R special-register source.
    JR   Z,.ldAIr                       ; Reuse the same A-destination path.
    CALL enIsDisp                       ; Test for indexed memory with a displacement.
    JR   C,.ldRegIdx                    ; Carry selects the DD/FD memory path.
    JR   .ldRHalf                       ; Validator leaves only an index-half source.
.ldRegReg: ; Combine register fields.

; LD r,r' = 40 | destination<<3 | source.

    LD   B,A                            ; Keep the source register field in B.
    LD   A,(IX+enOp0)                   ; Load destination field.
    ADD  A,A                            ; Move its field toward opcode bits 3..5.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,B                            ; Add the source register field in bits 0..2.
    ADD  A,$40                          ; Add LD base 40.
    JP   .last1                         ; Emit the one-byte register transfer.
.ldRegImm: ; Form LD r,n opcode.

; LD r,n = 06 | destination<<3, followed by the low value byte.

    LD   A,(IX+enOp0)                   ; Load destination field.
    ADD  A,A                            ; Shift it toward opcode bits 3..5.
    ADD  A,A                            ; Field reaches bits 2..4.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,6                            ; Add the immediate-load opcode base.
.v1Byte2: ; Append source after opcode.
    LD   (enTemp+0),A                   ; Stage the opcode before the immediate value.
    LD   A,(IX+enVal1)                  ; Load the source operand's low value byte.
    JP   .last2                         ; Append the value and return a two-byte length.
.ldRegMHl: ; Form LD r,(HL) opcode.

; LD r,(HL) = 46 | destination<<3.

    LD   A,(IX+enOp0)                   ; Load destination field.
    ADD  A,A                            ; Shift it toward opcode bits 3..5.
    ADD  A,A                            ; Continue the destination-field shift.
    ADD  A,A                            ; Destination reaches bits 3..5.
    ADD  A,$46                          ; Add the LD r,(HL) opcode base.
    JP   .last1                         ; Emit the one-byte indirect load.
.ldAAbs: ; Select LD A,(nn).

; LD A,(nn) is 3A followed by the absolute word.

    LD   A,$3A                          ; Select LD A,(nn).
.v1Word3: ; Append source after opcode.
    LD   (enTemp+0),A                   ; Stage opcode before operand one's value word.
    JP   enOp1At1                       ; Append operand one's word.
.ldAMemRr: ; Select LD A,(BC/DE).

; LD A,(BC/DE) uses 0A/1A, derived from the two memory classes.

    SUB  enMemBC                        ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                            ; Start shifting selector toward bit 4.
    ADD  A,A                            ; Continue shifting the selector.
    ADD  A,A                            ; Continue shifting the selector.
    ADD  A,A                            ; Finish the four-bit pair-field shift.
    ADD  A,$0A                          ; Add the LD A,(BC)/(DE) opcode base.
    JP   .last1                         ; Emit the one-byte accumulator load.
.ldAIr: ; Select LD A,I or LD A,R.

; LD A,I/R uses ED 57/5F.

    LD   B,$57                          ; Prepare LD A,I's ED suffix.
    CP   enRegI                         ; A still holds the source class I or R.
    JR   Z,.ldAIrOp                     ; Keep 57 for I.
    LD   B,$5F                          ; Select 5F for R.
.ldAIrOp: ; Continue with the selected I/R suffix in B.
.edTail: ; Prefix suffix B with ED.
    LD   A,$ED                          ; Supply the ED prefix for the shared tail.
.prefixB: ; Stage a prefix and suffix B.
    LD   (enTemp+0),A                   ; Stage ED or CB before the selected opcode byte.
    LD   A,B                            ; Load the ED suffix or CB opcode byte.
    JP   .last2                         ; Append it and return a two-byte length.
.ldRegIdx: ; Encode a displaced indexed-memory load.

; Indexed memory reuses the (HL) opcode after DD/FD and inserts displacement.

    PUSH AF                             ; Preserve flags from the indexed-class test.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the source index prefix.
    LD   (enTemp+0),A                   ; Stage the index prefix as byte zero.
    LD   A,(IX+enOp0)                   ; Load destination field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    ADD  A,$46                          ; Form 46 | destination<<3 for indexed memory.
    LD   (enTemp+1),A                   ; Stage the prefixed LD opcode as byte one.
    POP  AF                             ; Restore entry flags after the field arithmetic.
    LD   A,(IX+enVal1)                  ; Load the indexed source displacement.
    JP   .last3                         ; Append displacement and return length three.
.ldRHalf: ; Select index-half source.

; An index-half source reuses H/L's source field behind the selected prefix.

    LD   A,(IX+enOp1)                   ; Load IXH/IXL/IYH/IYL as the prefix selector.
    CALL enStage                        ; Stage DD/FD and restore the source class in A.
    AND  7                              ; Keep the source's H/L register field.
    LD   B,A                            ; Hold that field while forming the destination.
    LD   A,(IX+enOp0)                   ; Load the ordinary destination register field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    JR   .ldHalfOp                      ; Join the shared register-field calculation.
.ldHalf: ; Select index-half destination.

; An index-half destination reuses H/L's destination field. Validation has
; already matched the index family when both operands are index halves.

    CALL enStage                        ; Stage the destination's DD/FD prefix.
    AND  7                              ; Keep its H/L register field.
    ADD  A,A                            ; Register reaches bits 1..3.
    ADD  A,A                            ; Destination reaches bits 2..4.
    ADD  A,A                            ; Register reaches bits 3..5.
    LD   B,A                            ; Hold destination field while loading source.
    LD   A,(IX+enOp1)                   ; Load the validated source register class.
    AND  7                              ; Keep its three-bit register field.
.ldHalfOp: ; Finish prefixed LD r,r'.
    ADD  A,B                            ; Combine register fields.
    ADD  A,$40                          ; Add LD base 40.
    JP   .last2                         ; Append the opcode and return a two-byte length.
.ldReg16: ; Select pair-load form.

; Pair destinations cover immediate words and absolute loads. Two pair copies
; expand into byte-register transfers: HL,DE becomes H,D then L,E; BC,DE
; becomes B,D then C,E. LD SP,HL/IX/IY uses the F9 form below.

    LD   A,(IX+enOp1)                   ; Load the pair destination's source class.
    CP   enImm16                        ; Check for a 16-bit immediate source.
    JR   Z,.ldRrImm                     ; Encode its pair opcode and following word.
    CP   enMemAbs                       ; Check for an absolute-memory source.
    JR   Z,.ldRrAbs                     ; Select direct HL or ED-prefixed pair loading.
    LD   A,(IX+enOp0)                   ; Other accepted forms depend on the destination.
    CP   enRegSP                        ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.ldSp                        ; Encode LD SP,HL/IX/IY.
    CP   enRegHL                        ; HL selects Atom's DE-to-HL pair-copy form.
    LD   A,$62                          ; Prepare LD H,D, the first byte-register copy.
    JR   Z,.ldLegacy                    ; Keep 62 when the destination is HL.
    LD   A,$42                          ; BC instead starts with LD B,D.
.ldLegacy: ; Expand the DE pair copy.
    LD   (enTemp+0),A                   ; Stage LD H,D or LD B,D.
    ADD  A,9                            ; Form LD L,E or LD C,E as the second opcode.
    JP   .last2                         ; Return both expanded copy opcodes.
.ldRrImm: ; Form LD rr,nn opcode.

; LD rr,nn = 01 | rr<<4 followed by the word.

    LD   A,(IX+enOp0)                   ; Load the BC..SP pair class.
    AND  3                              ; Reduce it to the hardware pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Pair field now occupies bits 2..3.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Complete the shift above the low opcode bits.
    INC  A                              ; Add the LD rr,nn opcode base 01.
    JP   .v1Word3                       ; Append operand one's word.
.ldRrAbs: ; Select pair-memory opcode.

; HL has the direct 2A form; BC/DE/SP use ED 4B/5B/7B.

    LD   A,(IX+enOp0)                   ; HL has an unprefixed load opcode.
    CP   enRegHL                        ; Check whether the destination is HL.
    JR   Z,.ldHlAbs                     ; Select LD HL,(nn) when it is.
    AND  3                              ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Pair reaches bits 4..5.
    ADD  A,$4B                          ; Form ED 4B/5B/7B for BC/DE/SP.
    LD   B,A                            ; Keep the ED suffix while staging its prefix.
    LD   A,$ED                          ; Select the extended-instruction prefix.
    LD   (enTemp+0),A                   ; Stage ED before the pair-load suffix.
    LD   A,B                            ; Restore the suffix for the shared word tail.
.v1Word4: ; Append source after prefix/opcode.
    LD   (enTemp+1),A                   ; Stage the opcode after the first prefix byte.
    JP   enOp1At2                       ; Append operand one's word.
.ldHlAbs: ; Select LD HL,(nn).
    LD   A,$2A                          ; Select the direct LD HL,(nn) opcode.
    JP   .v1Word3                       ; Append operand one's word after opcode 2A.
.ldSp: ; Select LD SP,HL/IX/IY.

; LD SP,HL is F9; IX/IY use the same opcode behind their prefix.

    LD   A,(IX+enOp1)                   ; Load the validated HL/IX/IY source pair.
    CP   enRegHL                        ; HL uses F9 without a prefix.
    LD   A,$F9                          ; Prepare the common LD SP,pair opcode.
    JP   Z,.last1                       ; Emit the one-byte HL form when it matched.
    LD   A,(IX+enOp1)                   ; Reload IX or IY to select its prefix.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the source index prefix.
    LD   (enTemp+0),A                   ; Stage the index prefix.
    LD   A,$F9                          ; Both indexed forms reuse LD SP,HL's opcode.
    JP   .last2                         ; Append F9 and return a two-byte length.
.ldIxIy: ; Select indexed pair load.

; LD IX/IY,nn and LD IX/IY,(nn) are prefixed HL forms 21 and 2A.

    CALL enStage                        ; Stage DD/FD for the IX/IY destination pair.
    LD   A,(IX+enOp1)                   ; Read whether the source is immediate or memory.
    CP   enImm16                        ; Immediate pairs use opcode 21.
    LD   A,$21                          ; Prepare LD IX/IY,nn.
    JR   Z,.ldIxIyOp                    ; Keep 21 for the immediate form.
    LD   A,$2A                          ; Absolute memory uses the HL-form opcode 2A.
.ldIxIyOp: ; Finish indexed pair load.
    JR   .v1Word4                       ; Append opcode and operand one's value word.
.ldIrA: ; Select LD I,A or LD R,A.

; LD I/R,A uses ED 47/4F.

    LD   B,$47                          ; Prepare LD I,A's ED suffix.
    CP   enRegI                         ; A still holds the I or R destination class.
    JR   Z,.ldIrAOp                     ; Keep 47 for I.
    LD   B,$4F                          ; Select 4F for R.
.ldIrAOp: ; Emit the selected special-register suffix.
    JP   .edTail                        ; Emit ED and the selected I/R transfer suffix.
.ldMemAbs: ; Select absolute store.

; Absolute-memory stores select A, HL, ordinary pairs or IX/IY and append the
; destination address word from operand zero.

    LD   A,(IX+enOp1)                   ; Load absolute-store source.
    CP   enRegA                         ; A uses the direct 32 opcode.
    JR   Z,.ldAbsA                      ; Route the accumulator store to its tail.
    CALL enIsPair                       ; Test for BC, DE, HL or SP as the source pair.
    JR   NC,.ldAbsIdx                   ; Otherwise validation leaves IX or IY here.
    CP   enRegHL                        ; HL stores without the ED prefix.
    JR   Z,.ldAbsHl                     ; Select direct opcode 22 for HL.
    AND  3                              ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                            ; Pair reaches bits 1..2.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Pair reaches bits 3..4.
    ADD  A,A                            ; Pair reaches bits 4..5.
    ADD  A,$43                          ; Form ED 43/53/73 for BC/DE/SP.
    LD   B,A                            ; Keep the suffix while staging ED.
    LD   A,$ED                          ; Select the extended-instruction prefix.
    LD   (enTemp+0),A                   ; Stage ED before the pair-store suffix.
    LD   A,B                            ; Restore the suffix for the address tail.
.v0Word4: ; Append target after prefix/opcode.
    LD   (enTemp+1),A                   ; Stage the opcode after the prefix.
    JP   enOp0At2                       ; Append operand zero's word.
.ldAbsA: ; Select LD (nn),A.
    LD   A,$32                          ; Select LD (nn),A.
.v0Word3: ; Append target after opcode.
    LD   (enTemp+0),A                   ; Stage opcode before operand zero's value word.
    JP   enOp0At1                       ; Append operand zero's word.
.ldAbsHl: ; Select LD (nn),HL.
    LD   A,$22                          ; Select the direct LD (nn),HL opcode.
    JR   .v0Word3                       ; Append operand zero's value word.
.ldAbsIdx: ; Prefix LD (nn),IX/IY.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the source index prefix.
    LD   (enTemp+0),A                   ; Stage the index prefix before opcode 22.
    LD   A,$22                          ; The indexed store reuses LD (nn),HL's opcode.
    JR   .v0Word4                       ; Append opcode and operand zero's value word.
.ldMemRrA: ; Select LD (BC/DE),A.

; LD (BC/DE),A uses 02/12.

    SUB  enMemBC                        ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                            ; Start shifting selector toward bit 4.
    ADD  A,A                            ; Continue shifting the pair selector.
    ADD  A,A                            ; Advance pair bits left.
    ADD  A,A                            ; Complete the shift above opcode base 02.
    ADD  A,$02                          ; Form 02 for (BC) or 12 for (DE).
    JP   .last1                         ; Emit the one-byte accumulator store.
.ldMemHl: ; Select LD (HL),r/n.

; LD (HL),r uses 70 | r; LD (HL),n is 36 n.

    LD   A,(IX+enOp1)                   ; Load register/immediate source.
    CP   enImm8                         ; Immediate data uses opcode 36.
    JR   Z,.ldHlImm                     ; Route immediate stores to their two-byte form.
    ADD  A,$70                          ; Combine the register field with base 70.
    JP   .last1                         ; Emit LD (HL),r in one byte.
.ldHlImm: ; Select LD (HL),n.
    LD   A,$36                          ; Select LD (HL),n.
    JP   .v1Byte2                       ; Append the immediate byte after opcode 36.
.ldMemIdx: ; Select indexed store.

; LD (IX/IY+d),r reuses 70 | r. The immediate form is four bytes because both
; displacement and immediate data follow the prefixed 36 opcode.

    LD   A,(IX+enOp0)                   ; Load the destination's IX+d or IY+d class.
;@EXPECTOUT A
    CALL enIdxPfx                       ; Select the index prefix from destination class.
    LD   (enTemp+0),A                   ; Store the prefix as byte zero.
    LD   A,(IX+enOp1)                   ; Load register/immediate source.
    CP   enImm8                         ; Immediate stores need opcode 36 and four bytes.
    JR   Z,.ldIdxImm                    ; Route the immediate form to its four-byte path.
    ADD  A,$70                          ; Combine the real register field with base 70.
.v0Byte3: ; Append target after prefix/opcode.
    LD   (enTemp+1),A                   ; Stage the opcode after the prefix.
    LD   A,(IX+enVal0)                  ; Load operand zero's indexed displacement.
    JP   .last3                         ; Use the shared three-byte displacement tail.
.ldIdxImm: ; Stage displacement then data.
    LD   A,$36                          ; Select the indexed immediate-store opcode.
    LD   (enTemp+1),A                   ; Stage 36 after the index prefix.
    LD   A,(IX+enVal0)                  ; Load the indexed destination's displacement.
    LD   (enTemp+2),A                   ; Store displacement before immediate data.
    LD   A,(IX+enVal1)                  ; Load the immediate data byte.
.last4: ; Finish byte three and return length four.
    LD   (enTemp+3),A                   ; Store the final byte of the four-byte encoding.
    JP   enDone4                        ; Return length four.
enLdEEnd    EQU     $                   ; End the LD-form encoder handlers.
