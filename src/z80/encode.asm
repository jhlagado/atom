;=============================================================================
;  Z80 instruction byte emission
;=============================================================================
;
;  Validate the record at IX, stage its encoding, then publish the complete
;  one-to-four-byte result to the caller's destination.

EN_RECBE:

;@ROUTINE IN IX,DE OUT A,DE,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and encode the record at IX, then commit its bytes to DE.
; EN_CORE stages into EN_SCRAT; failure leaves the destination untouched.

EN_NAME:
    PUSH DE                  ; Preserve the caller's destination pointer.
    CALL EN_VFORM            ; Check form and arity before encoding.
    POP  DE                  ; Recover the destination after validation.
    RET  C                   ; Leave the destination unchanged on failure.
    PUSH DE                  ; Save it while EN_CORE uses the register pair.
;@EXPECTOUT A
    CALL EN_CORE             ; Stage bytes and return their count in A.
    POP  DE                  ; Restore the caller's output address.
    LD   C,A                 ; Supply LDIR with the encoded byte count.
    LD   B,0                 ; The maximum instruction length is four.
    LD   HL,EN_SCRAT         ; Point at the complete staged instruction.
    LDIR                     ; Commit only after validation and encoding pass.
    OR   A                   ; Preserve the length and clear carry on success.
    RET                      ; Return length and the advanced output pointer.

;@ROUTINE IN IX,B OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Encode a condition field into bits 3..5 and add the opcode-family base in B.

EN_COPCO:
    LD   A,(IX+EN_OP0)       ; Read the validated condition ordinal.
    SUB  EN_NZ               ; NZ..M becomes the three-bit condition field.
    ADD  A,A                 ; Begin shifting the condition toward bits 3..5.
    ADD  A,A                 ; Continue the three-bit shift.
    ADD  A,A                 ; Finish placing the condition field.
    ADD  A,B                 ; Add the caller's opcode-family base.
    RET                      ; Return the complete opcode in A.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Encode a record already accepted by EN_VFORM. The family table mirrors the
; validator table so both paths use the same mnemonic-ordinal partition.

EN_CORE:
    LD   A,(IX+EN_MNEM)      ; Read the ordinal already accepted by EN_VFORM.
    LD   DE,.EDTABLE         ; Select the matching encoder-family table.
    JP   AT_DMNEM            ; Dispatch by ordinal and enter that family.
.COPCODE:

; Core ordinals index direct opcode bytes or ED suffixes. Ordinals 1..13 are
; direct; 14..34 use the shared ED-prefix tail.

    LD   B,A                 ; Keep the one-based ordinal for the prefix test.
    DEC  A                   ; Convert the ordinal to a table byte offset.
    LD   E,A                 ; Place the low index byte in DE.
    LD   D,0                 ; Clear the high byte for this byte-sized index.
    LD   HL,EN_COPC1          ; Point to the irregular core-opcode table.
    ADD  HL,DE               ; Select the entry for this mnemonic ordinal.
    LD   A,B                 ; Recover the ordinal for the direct/ED split.
    CP   14                  ; Separate direct opcodes from ED suffixes.
    LD   A,(HL)              ; Load the opcode or suffix selected above.
    JP   C,.SE1              ; Ordinals 1..13 emit this byte directly.
    LD   B,A                 ; Pass the ED suffix to the shared prefix tail.
    JP   .SEBE2              ; Emit ED followed by the selected suffix.
.RET:

; Conditional RET is C0 | cc<<3; plain RET is the singleton C9.

    LD   A,(IX+EN_OP0)       ; Read the optional condition operand.
    CP   EN_NONE             ; The sentinel selects ordinary RET.
    JR   Z,.RETPLAIN         ; Emit C9 when no condition was supplied.
    LD   B,$C0               ; Set the base for RET NZ through RET M.
    CALL EN_COPCO            ; Insert the condition into bits 3..5.
    JP   .SE1                ; Emit the completed one-byte opcode.
.RETPLAIN:
    LD   A,$C9               ; Select the unconditional RET opcode.
    JP   .SE1                ; Use the common one-byte emitter.
.EX:

; EX AF,AF', EX DE,HL and EX (SP),HL are singletons. IX/IY stack exchange adds
; the selected prefix before the E3 opcode.

    LD   A,(IX+EN_OP0)       ; Check the first operand for AF or DE.
    CP   EN_AF               ; AF,AF' has its own one-byte opcode.
    JR   Z,.EXAF              ; Select that singleton when matched.
    CP   EN_DE               ; DE,HL is the other unprefixed register swap.
    JR   Z,.EXDE              ; Select its one-byte opcode when matched.
    LD   A,(IX+EN_OP1)       ; The remaining forms test the second operand.
    CP   EN_HL               ; HL selects EX (SP),HL without a prefix.
    JR   Z,.EXSPHL            ; Emit E3 for the unprefixed stack exchange.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD for the validated index pair.
    LD   (EN_SCRAT+0),A      ; Stage the IX/IY prefix before the opcode.
    LD   A,$E3               ; The indexed stack exchange reuses E3.
    JP   .SS1E2              ; Append E3 and return a two-byte length.
.EXAF:
    LD   A,$08               ; Select EX AF,AF'.
    JP   .SE1                ; Emit the one-byte form.
.EXDE:
    LD   A,$EB               ; Select EX DE,HL.
    JP   .SE1                ; Emit the one-byte form.
.EXSPHL:
    LD   A,$E3               ; Select EX (SP),HL.
    JP   .SE1                ; Emit the one-byte form.
.IM:

; IM's three enumerated classes select the irregular ED suffix table.

    LD   A,(IX+EN_OP0)       ; Read the validated IM 0..IM 2 class.
    SUB  EN_IM0              ; Convert it to a zero-based table offset.
    LD   E,A                 ; Place the offset in DE for address addition.
    LD   D,0                 ; Clear the high byte of the table offset.
    LD   HL,EN_IOPCO          ; Point to the three irregular ED suffixes.
    ADD  HL,DE               ; Select the suffix for this interrupt mode.
    LD   A,(HL)              ; Load the selected suffix byte.
    LD   B,A                 ; Pass it to the common ED-prefix emitter.
    JP   .SEBE2              ; Emit ED and the selected mode suffix.
.RST:

; RST classes are ordered vectors, so C7 | vector produces the opcode.

    LD   A,(IX+EN_OP0)       ; Read one of the eight validated vector classes.
    SUB  EN_RST0             ; Convert RST 0..RST 56 to values zero..seven.
    ADD  A,A                 ; Begin shifting the vector toward bits 3..5.
    ADD  A,A                 ; Continue the three-bit shift.
    ADD  A,A                 ; Finish forming the vector field.
    ADD  A,$C7               ; Combine the field with the RST opcode base.
    JP   .SE1                ; Emit the completed one-byte opcode.
.INCDEC:

; B starts at the byte-register base 04/05. Pair forms use 03/0B and memory
; forms add 30 for 34/35. Index forms add a prefix; indexed memory also adds
; its displacement.

    LD   A,(IX+EN_MNEM)      ; Read INC or DEC from the validated record.
    SUB  AT_MINC-4           ; Derive the byte-register opcode base 04 or 05.
    LD   B,A                 ; Keep the selected base during class checks.
    LD   A,(IX+EN_OP0)       ; Test the operand as an ordinary byte register.
    CALL EN_IR8              ; Carry marks B,C,D,E,H,L or A.
    JR   C,.IDREGIST         ; Encode a byte register in bits 3..5.
    LD   A,(IX+EN_OP0)       ; Reload the class for the register-pair test.
    CALL EN_IR16             ; Carry marks BC,DE,HL or SP.
    JR   C,.IDPAIR           ; Route ordinary pairs to shared field logic.
    LD   A,(IX+EN_OP0)       ; Check whether the operand is IX or IY.
    CP   EN_IX               ; Compare with the IX pair class.
    JR   Z,.IDIPAIR          ; Encode IX behind its DD prefix.
    CP   EN_IY               ; Compare with the IY pair class.
    JR   Z,.IDIPAIR          ; Encode IY behind its FD prefix.
    CALL EN_IHIND            ; Test for IXH, IXL, IYH or IYL.
    JR   C,.IDHALF           ; Index halves reuse the H/L register field.
    LD   A,(IX+EN_OP0)       ; Reload the class for the memory-form test.
    CP   EN_MEMHL            ; Compare with the unprefixed (HL) class.
    JR   Z,.IDMHL            ; Keep (HL) on the one-byte path.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD from the indexed class.
    LD   (EN_SCRAT+0),A      ; Stage the index prefix before the opcode.
    LD   A,B                 ; Restore the INC/DEC family base.
    ADD  A,$30               ; Form the indexed-memory opcode 34 or 35.
    LD   (EN_SCRAT+1),A      ; Stage the opcode after its prefix.
    LD   A,(IX+EN_VAL0)      ; Read the displacement selected during parsing.
.SS2E3:
    LD   (EN_SCRAT+2),A      ; Store the displacement as the third byte.
    JP   EN_D3               ; Return the three-byte indexed form.
.IDREGIST:

; INC/DEC r = base | r<<3.

    LD   A,(IX+EN_OP0)       ; Load the register number for bits 3..5.
.TSAB:
    ADD  A,A                 ; Shift one bit toward the opcode field.
    ADD  A,A                 ; Continue the shared field shift.
    ADD  A,A                 ; Complete the three doublings in this tail.
    ADD  A,B                 ; Add the selected opcode-family base in B.
    JP   .SE1                ; Emit the one-byte register form.
.IDPAIR:

; INC/DEC rr = 03/0B | pair<<4.

    LD   A,B                 ; Compare the family base to distinguish INC.
    CP   4                   ; INC starts at 04; DEC starts at 05.
    LD   B,$03               ; Prepare the INC rr opcode base.
    JR   Z,.IDPBREAD         ; Preserve the comparison result through LD.
    LD   B,$0B               ; Select DEC rr when the mnemonic is DEC.
.IDPBREAD:
    LD   A,(IX+EN_OP0)       ; Reload BC,DE,HL or SP as the pair number.
.PFB:
    AND  3                   ; Keep the pair number in the low two bits.
    ADD  A,A                 ; Start shifting the pair field into bits 4..5.
    JR   .TSAB               ; The common tail supplies three more doublings.
.IDIPAIR:

; IX/IY pair operations reuse the HL opcode behind DD/FD.

    CALL EN_SPPAF            ; Stage DD/FD and restore the IX/IY class in A.
    LD   A,B                 ; Read the family base to distinguish INC/DEC.
    CP   4                   ; INC uses 23; DEC uses 2B behind the prefix.
    LD   A,$23               ; Prepare the IX/IY increment opcode.
    JR   Z,.IDIPREAD         ; Keep 23 when the family base was 04.
    LD   A,$2B               ; Select the decrement opcode for base 05.
.IDIPREAD:
    JP   .SS1E2              ; Emit prefix and opcode as a two-byte form.
.IDHALF:

; Index halves reuse H/L field values behind their family prefix.

    LD   A,(IX+EN_OP0)       ; Load IXH/IXL/IYH/IYL as a register class.
    CALL EN_SPPAF            ; Stage its prefix and restore the class in A.
    AND  7                   ; Reduce the class to the H or L register field.
    ADD  A,A                 ; Move that field toward opcode bits 3..5.
    ADD  A,A                 ; Continue the three-bit field shift.
    ADD  A,A                 ; Finish placing the register field.
    ADD  A,B                 ; Add the INC/DEC base to the H/L field.
    JP   .SS1E2              ; Emit the prefix and one-byte opcode.
.IDMHL:
    LD   A,B                 ; Restore the INC/DEC family base.
    ADD  A,$30               ; Form the (HL) opcode 34 or 35.
    JP   .SE1                ; Emit this unprefixed one-byte form.
.STACK:

; PUSH/POP use C5/C1 | pair<<4. IX/IY reuse the HL field behind DD/FD.

    LD   A,(IX+EN_MNEM)      ; Read whether this is PUSH or POP.
    CP   AT_MPUSH            ; Set Z for PUSH; POP selects the other base.
    LD   B,$C5               ; Prepare the PUSH pair-opcode base.
    JR   Z,.SBASE            ; Keep C5 when the mnemonic is PUSH.
    LD   B,$C1               ; Select C1 for POP when the test did not match.
.SBASE:
    LD   A,(IX+EN_OP0)       ; Read the validated stack-pair class.
    CP   EN_IX               ; IX uses the HL field behind DD.
    JR   Z,.SINDEX           ; Stage that prefix before forming the opcode.
    CP   EN_IY               ; IY uses the corresponding field behind FD.
    JR   Z,.SINDEX           ; Route both index pairs through the prefix path.
    JR   .PFB                ; Ordinary pairs share the low-field calculation.
.SINDEX:
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD from the IX/IY class.
    LD   (EN_SCRAT+0),A      ; Stage the prefix before the stack opcode.
    LD   A,B                 ; Restore the PUSH/POP base after prefix lookup.
    ADD  A,$20               ; Convert C5/C1 to indexed E5/E1.
    JP   .SS1E2              ; Emit the prefix and indexed stack opcode.
EN_LEBEG EQU $              ; Begin the LD-form encoder handlers.
.LD:

; Destination-first dispatch mirrors the form validator. Each branch below
; handles a source class already accepted for that destination.

    LD   A,(IX+EN_OP0)       ; Load the destination class.
    CALL EN_IR8              ; Test for an ordinary eight-bit register.
    JR   C,.LDREG8           ; Carry selects byte-register destinations.
    LD   A,(IX+EN_OP0)       ; Reload the class for the index-half test.
    CALL EN_IHIND            ; Test for IXH, IXL, IYH or IYL.
    JP   C,.LDHALF           ; Index-half destinations need a prefix.
    LD   A,(IX+EN_OP0)       ; Reload the class for the pair test.
    CALL EN_IR16             ; Test for BC,DE,HL or SP.
    JP   C,.LDREG16          ; Ordinary pairs use their shared encoder path.
    LD   A,(IX+EN_OP0)       ; Check index pairs and special destinations.
    CP   EN_IX               ; Check the IX pair destination.
    JP   Z,.LI16             ; Reuse the prefixed-pair encoder.
    CP   EN_IY               ; IY has the same source forms as IX.
    JP   Z,.LI16             ; Reuse its prefix-aware path.
    CP   EN_I                ; I loads only from A.
    JP   Z,.LSTARGET          ; Select the ED-prefixed special-register form.
    CP   EN_R                ; R also loads only from A.
    JP   Z,.LSTARGET          ; Reuse the I/R transfer path.
    CP   EN_MABS             ; Check for the absolute destination (nn).
    JP   Z,.LDMEMABS         ; Its source selects the store opcode.
    CP   EN_MEMBC            ; Check for the indirect destination (BC).
    JP   Z,.LMPAIR           ; (BC) stores only A.
    CP   EN_MEMDE            ; Check for the indirect destination (DE).
    JP   Z,.LMPAIR           ; Reuse the matching (DE) store path.
    CP   EN_MEMHL            ; Check for the unprefixed destination (HL).
    JP   Z,.LDMEMHL          ; Encode its register or immediate source.
    JP   .LINDEXED           ; Remaining accepted destinations are (IX/IY+d).
.LDREG8:

; Ordinary register destinations divide into register, immediate, memory,
; special-register, indexed-memory and index-half sources.

    LD   A,(IX+EN_OP1)       ; Load the source class for this byte register.
    CALL EN_IR8              ; Test for an ordinary byte-register source.
    JR   C,.LDREGREG         ; Carry selects the register-to-register form.
    LD   A,(IX+EN_OP1)       ; Reload source for the remaining tests.
    CP   EN_IMM8             ; Check for an immediate byte.
    JR   Z,.LDREGIMM         ; Emit opcode followed by the low value byte.
    CP   EN_MEMHL            ; Check for the unprefixed (HL) source.
    JR   Z,.LRMHL            ; Use the one-byte indirect load form.
    CP   EN_MABS             ; Check for an absolute-memory source (nn).
    JR   Z,.LDAABS           ; Validation allows this source only for A.
    CP   EN_MEMBC            ; Check for the accumulator's (BC) source.
    JR   Z,.LAMPAIR          ; Select the 0A opcode family.
    CP   EN_MEMDE            ; Check for the accumulator's (DE) source.
    JR   Z,.LAMPAIR          ; The adjacent class selects 1A in the same path.
    CP   EN_I                ; Check for the I special-register source.
    JR   Z,.LASPECIA         ; Only A accepts this ED-prefixed transfer.
    CP   EN_R                ; Check for the R special-register source.
    JR   Z,.LASPECIA         ; Reuse the same A-destination path.
    CALL EN_IINDE            ; Test for indexed memory with a displacement.
    JR   C,.LRINDEXE         ; Carry selects the DD/FD memory path.
    JR   .LRHALF             ; Validator leaves only an index-half source.
.LDREGREG:

; LD r,r' = 40 | destination<<3 | source.

    LD   B,A                 ; Keep the source register field in B.
    LD   A,(IX+EN_OP0)       ; Load the destination register field.
    ADD  A,A                 ; Move its field toward opcode bits 3..5.
    ADD  A,A                 ; Continue shifting the destination field.
    ADD  A,A                 ; Finish placing the destination field.
    ADD  A,B                 ; Add the source register field in bits 0..2.
    ADD  A,$40               ; Add the LD r,r' opcode-family base.
    JP   .SE1                ; Emit the one-byte register transfer.
.LDREGIMM:

; LD r,n = 06 | destination<<3, followed by the low value byte.

    LD   A,(IX+EN_OP0)       ; Load the destination register field.
    ADD  A,A                 ; Shift it toward opcode bits 3..5.
    ADD  A,A                 ; Continue the three-bit field shift.
    ADD  A,A                 ; Finish placing the destination field.
    ADD  A,6                 ; Add the immediate-load opcode base.
.SAV1E2:
    LD   (EN_SCRAT+0),A      ; Stage the opcode before the immediate value.
    LD   A,(IX+EN_VAL1)      ; Load the source operand's low value byte.
    JP   .SS1E2              ; Append the value and return a two-byte length.
.LRMHL:

; LD r,(HL) = 46 | destination<<3.

    LD   A,(IX+EN_OP0)       ; Load the destination register field.
    ADD  A,A                 ; Shift it toward opcode bits 3..5.
    ADD  A,A                 ; Continue the destination-field shift.
    ADD  A,A                 ; Finish placing the destination field.
    ADD  A,$46               ; Add the LD r,(HL) opcode base.
    JP   .SE1                ; Emit the one-byte indirect load.
.LDAABS:

; LD A,(nn) is 3A followed by the absolute word.

    LD   A,$3A               ; Select LD A,(nn).
.SAV1E3:
    LD   (EN_SCRAT+0),A      ; Stage opcode before operand one's value word.
    JP   AT_CV1TS            ; Append operand one's 16-bit value.
.LAMPAIR:

; LD A,(BC/DE) uses 0A/1A, derived from the two memory classes.

    SUB  EN_MEMBC            ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                 ; Start shifting selector toward bit 4.
    ADD  A,A                 ; Continue shifting the selector.
    ADD  A,A                 ; Continue shifting the selector.
    ADD  A,A                 ; Finish the four-bit pair-field shift.
    ADD  A,$0A               ; Add the LD A,(BC)/(DE) opcode base.
    JP   .SE1                ; Emit the one-byte accumulator load.
.LASPECIA:

; LD A,I/R uses ED 57/5F.

    LD   B,$57               ; Prepare LD A,I's ED suffix.
    CP   EN_I                ; A still holds the source class I or R.
    JR   Z,.LASREADY         ; Keep 57 for I.
    LD   B,$5F               ; Select 5F for R.
.LASREADY:
.SEBE2:
    LD   A,$ED               ; Supply the ED prefix for the shared tail.
.SPBE2:
    LD   (EN_SCRAT+0),A      ; Stage ED or CB before the selected opcode byte.
    LD   A,B                 ; Load the ED suffix or CB opcode byte.
    JP   .SS1E2              ; Append it and return a two-byte length.
.LRINDEXE:

; Indexed memory reuses the (HL) opcode after DD/FD and inserts displacement.

    PUSH AF                  ; Preserve flags from the indexed-class test.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD from the indexed source class.
    LD   (EN_SCRAT+0),A      ; Stage the index prefix as byte zero.
    LD   A,(IX+EN_OP0)       ; Load the destination register field.
    ADD  A,A                 ; Begin shifting toward opcode bits 3..5.
    ADD  A,A                 ; Continue shifting the destination field.
    ADD  A,A                 ; Complete the field shift.
    ADD  A,$46               ; Form 46 | destination<<3 for indexed memory.
    LD   (EN_SCRAT+1),A      ; Stage the prefixed LD opcode as byte one.
    POP  AF                  ; Restore entry flags after the field arithmetic.
    LD   A,(IX+EN_VAL1)      ; Load the indexed source displacement.
    JP   .SS2E3              ; Append displacement and return length three.
.LRHALF:

; An index-half source reuses H/L's source field behind the selected prefix.

    LD   A,(IX+EN_OP1)       ; Load IXH/IXL/IYH/IYL as the prefix selector.
    CALL EN_SPPAF            ; Stage DD/FD and restore the source class in A.
    AND  7                   ; Keep the source's H/L register field.
    LD   B,A                 ; Hold that field while forming the destination.
    LD   A,(IX+EN_OP0)       ; Load the ordinary destination register field.
    ADD  A,A                 ; Begin shifting toward opcode bits 3..5.
    ADD  A,A                 ; Continue shifting the destination field.
    ADD  A,A                 ; Complete the field shift.
    JR   .LHOPCODE            ; Join the shared register-field calculation.
.LDHALF:

; An index-half destination reuses H/L's destination field. Validation has
; already matched the index family when both operands are index halves.

    CALL EN_SPPAF            ; Stage the destination's DD/FD prefix.
    AND  7                   ; Keep its H/L register field.
    ADD  A,A                 ; Begin shifting toward opcode bits 3..5.
    ADD  A,A                 ; Continue shifting the destination field.
    ADD  A,A                 ; Complete the field shift.
    LD   B,A                 ; Hold destination field while loading source.
    LD   A,(IX+EN_OP1)       ; Load the validated source register class.
    AND  7                   ; Keep its three-bit register field.
.LHOPCODE:
    ADD  A,B                 ; Combine source and destination register fields.
    ADD  A,$40               ; Add the LD r,r' opcode-family base.
    JP   .SS1E2              ; Append the opcode and return a two-byte length.
.LDREG16:

; Pair destinations cover immediate words and absolute loads. Two pair copies
; expand into byte-register transfers: HL,DE becomes H,D then L,E; BC,DE
; becomes B,D then C,E. LD SP,HL/IX/IY uses the F9 form below.

    LD   A,(IX+EN_OP1)       ; Load the pair destination's source class.
    CP   EN_IMM16            ; Check for a 16-bit immediate source.
    JR   Z,.LR1IMM           ; Encode its pair opcode and following word.
    CP   EN_MABS             ; Check for an absolute-memory source.
    JR   Z,.LR1ABS           ; Select direct HL or ED-prefixed pair loading.
    LD   A,(IX+EN_OP0)       ; Other accepted forms depend on the destination.
    CP   EN_SP               ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.LDSP             ; Encode LD SP,HL/IX/IY.
    CP   EN_HL               ; HL selects Atom's DE-to-HL pair-copy form.
    LD   A,$62               ; Prepare LD H,D, the first byte-register copy.
    JR   Z,.LDLEGACY         ; Keep 62 when the destination is HL.
    LD   A,$42               ; BC instead starts with LD B,D.
.LDLEGACY:
    LD   (EN_SCRAT+0),A      ; Stage LD H,D or LD B,D.
    ADD  A,9                 ; Form LD L,E or LD C,E as the second opcode.
    JP   .SS1E2              ; Return both expanded copy opcodes.
.LR1IMM:

; LD rr,nn = 01 | rr<<4 followed by the word.

    LD   A,(IX+EN_OP0)       ; Load the validated BC/DE/HL/SP pair class.
    AND  3                   ; Reduce it to the hardware pair field.
    ADD  A,A                 ; Begin shifting the pair field toward bits 4..5.
    ADD  A,A                 ; Continue the four-bit field shift.
    ADD  A,A                 ; Continue shifting the pair field.
    ADD  A,A                 ; Complete the shift above the low opcode bits.
    INC  A                   ; Add the LD rr,nn opcode base 01.
    JP   .SAV1E3             ; Append operand one's 16-bit value.
.LR1ABS:

; HL has the direct 2A form; BC/DE/SP use ED 4B/5B/7B.

    LD   A,(IX+EN_OP0)       ; HL has an unprefixed load opcode.
    CP   EN_HL               ; Check whether the destination is HL.
    JR   Z,.LDHLABS          ; Select LD HL,(nn) when it is.
    AND  3                   ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                 ; Begin shifting the pair field toward bits 4..5.
    ADD  A,A                 ; Continue the four-bit shift.
    ADD  A,A                 ; Continue shifting the pair field.
    ADD  A,A                 ; Complete the pair-field shift.
    ADD  A,$4B               ; Form ED 4B/5B/7B for BC/DE/SP.
    LD   B,A                 ; Keep the ED suffix while staging its prefix.
    LD   A,$ED               ; Select the extended-instruction prefix.
    LD   (EN_SCRAT+0),A      ; Stage ED before the pair-load suffix.
    LD   A,B                 ; Restore the suffix for the shared word tail.
.SS1CV1TS:
    LD   (EN_SCRAT+1),A      ; Stage the opcode after the first prefix byte.
    JP   AT_CV1T1            ; Append operand one's 16-bit value.
.LDHLABS:
    LD   A,$2A               ; Select the direct LD HL,(nn) opcode.
    JP   .SAV1E3             ; Append operand one's word after opcode 2A.
.LDSP:

; LD SP,HL is F9; IX/IY use the same opcode behind their prefix.

    LD   A,(IX+EN_OP1)       ; Load the validated HL/IX/IY source pair.
    CP   EN_HL               ; HL uses F9 without a prefix.
    LD   A,$F9               ; Prepare the common LD SP,pair opcode.
    JP   Z,.SE1              ; Emit the one-byte HL form when it matched.
    LD   A,(IX+EN_OP1)       ; Reload IX or IY to select its prefix.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD from the source pair.
    LD   (EN_SCRAT+0),A      ; Stage the index prefix.
    LD   A,$F9               ; Both indexed forms reuse LD SP,HL's opcode.
    JP   .SS1E2              ; Append F9 and return a two-byte length.
.LI16:

; LD IX/IY,nn and LD IX/IY,(nn) are prefixed HL forms 21 and 2A.

    CALL EN_SPPAF            ; Stage DD/FD for the IX/IY destination pair.
    LD   A,(IX+EN_OP1)       ; Read whether the source is immediate or memory.
    CP   EN_IMM16            ; Immediate pairs use opcode 21.
    LD   A,$21               ; Prepare LD IX/IY,nn.
    JR   Z,.LI1OPCOD         ; Keep 21 for the immediate form.
    LD   A,$2A               ; Absolute memory uses the HL-form opcode 2A.
.LI1OPCOD:
    JR   .SS1CV1TS           ; Append opcode and operand one's value word.
.LSTARGET:

; LD I/R,A uses ED 47/4F.

    LD   B,$47               ; Prepare LD I,A's ED suffix.
    CP   EN_I                ; A still holds the I or R destination class.
    JR   Z,.LSTREADY         ; Keep 47 for I.
    LD   B,$4F               ; Select 4F for R.
.LSTREADY:
    JP   .SEBE2              ; Emit ED and the selected I/R transfer suffix.
.LDMEMABS:

; Absolute-memory stores select A, HL, ordinary pairs or IX/IY and append the
; destination address word from operand zero.

    LD   A,(IX+EN_OP1)       ; Load the source for the absolute destination.
    CP   EN_A                ; A uses the direct 32 opcode.
    JR   Z,.LDABSA           ; Route the accumulator store to its tail.
    CALL EN_IR16             ; Test for BC, DE, HL or SP as the source pair.
    JR   NC,.LAINDEX         ; Otherwise validation leaves IX or IY here.
    CP   EN_HL               ; HL stores without the ED prefix.
    JR   Z,.LDABSHL          ; Select direct opcode 22 for HL.
    AND  3                   ; Reduce BC/DE/SP to the ED pair field.
    ADD  A,A                 ; Begin shifting the pair field toward bits 4..5.
    ADD  A,A                 ; Continue the four-bit shift.
    ADD  A,A                 ; Continue shifting the pair field.
    ADD  A,A                 ; Complete the pair-field shift.
    ADD  A,$43               ; Form ED 43/53/73 for BC/DE/SP.
    LD   B,A                 ; Keep the suffix while staging ED.
    LD   A,$ED               ; Select the extended-instruction prefix.
    LD   (EN_SCRAT+0),A      ; Stage ED before the pair-store suffix.
    LD   A,B                 ; Restore the suffix for the address tail.
.SS1CV0TS:
    LD   (EN_SCRAT+1),A      ; Stage the opcode after the prefix.
    JP   AT_CV0T1            ; Append operand zero's 16-bit value.
.LDABSA:
    LD   A,$32               ; Select LD (nn),A.
.SAV0E3:
    LD   (EN_SCRAT+0),A      ; Stage opcode before operand zero's value word.
    JP   AT_CV0TS            ; Append operand zero's 16-bit value.
.LDABSHL:
    LD   A,$22               ; Select the direct LD (nn),HL opcode.
    JR   .SAV0E3             ; Append operand zero's value word.
.LAINDEX:
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD or FD from the IX/IY source pair.
    LD   (EN_SCRAT+0),A      ; Stage the index prefix before opcode 22.
    LD   A,$22               ; The indexed store reuses LD (nn),HL's opcode.
    JR   .SS1CV0TS           ; Append opcode and operand zero's value word.
.LMPAIR:

; LD (BC/DE),A uses 02/12.

    SUB  EN_MEMBC            ; Convert (BC)/(DE) to selector zero or one.
    ADD  A,A                 ; Start shifting selector toward bit 4.
    ADD  A,A                 ; Continue shifting the pair selector.
    ADD  A,A                 ; Continue the four-bit shift.
    ADD  A,A                 ; Complete the shift above opcode base 02.
    ADD  A,$02               ; Form 02 for (BC) or 12 for (DE).
    JP   .SE1                ; Emit the one-byte accumulator store.
.LDMEMHL:

; LD (HL),r uses 70 | r; LD (HL),n is 36 n.

    LD   A,(IX+EN_OP1)       ; Load the register or immediate source class.
    CP   EN_IMM8             ; Immediate data uses opcode 36.
    JR   Z,.LMHIMM           ; Route immediate stores to their two-byte form.
    ADD  A,$70               ; Combine the register field with base 70.
    JP   .SE1                ; Emit LD (HL),r in one byte.
.LMHIMM:
    LD   A,$36               ; Select LD (HL),n.
    JP   .SAV1E2             ; Append the immediate byte after opcode 36.
.LINDEXED:

; LD (IX/IY+d),r reuses 70 | r. The immediate form is four bytes because both
; displacement and immediate data follow the prefixed 36 opcode.

    LD   A,(IX+EN_OP0)       ; Load the destination's IX+d or IY+d class.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select the index prefix from destination class.
    LD   (EN_SCRAT+0),A      ; Store the prefix as byte zero.
    LD   A,(IX+EN_OP1)       ; Load the register or immediate source class.
    CP   EN_IMM8             ; Immediate stores need opcode 36 and four bytes.
    JR   Z,.LIIMM            ; Route the immediate form to its four-byte path.
    ADD  A,$70               ; Combine the real register field with base 70.
.SS1V0E3:
    LD   (EN_SCRAT+1),A      ; Stage the opcode after the prefix.
    LD   A,(IX+EN_VAL0)      ; Load operand zero's indexed displacement.
    JP   .SS2E3              ; Use the shared three-byte displacement tail.
.LIIMM:
    LD   A,$36               ; Select the indexed immediate-store opcode.
    LD   (EN_SCRAT+1),A      ; Stage 36 after the index prefix.
    LD   A,(IX+EN_VAL0)      ; Load the indexed destination's displacement.
    LD   (EN_SCRAT+2),A      ; Store displacement before immediate data.
    LD   A,(IX+EN_VAL1)      ; Load the immediate data byte.
.SS3E4:
    LD   (EN_SCRAT+3),A      ; Store the final byte of the four-byte encoding.
    JP   EN_D4               ; Return the four-byte instruction length.
EN_LEEND EQU $              ; End the LD-form encoder handlers.
.IN:

; ED input forms put the register in bits 3..5. Immediate-port input is
; the singleton DB followed by the port byte.

    LD   A,(IX+EN_OP0)       ; Read the destination or bare-port class.
    CP   EN_PORTC            ; Bare IN (C) stores its port class in slot zero.
    JR   Z,.INBARE           ; Route that form to its fixed ED suffix.
    LD   A,(IX+EN_OP1)       ; Otherwise inspect the source-port class.
    CP   EN_IMM8             ; An immediate port selects the DB opcode.
    JR   Z,.IIMMEDIA         ; Emit DB followed by the port byte.
    LD   A,(IX+EN_OP0)       ; Load the destination register class.
    ADD  A,A                 ; Shift its register field toward bits 3..5.
    ADD  A,A                 ; Continue the three-bit field shift.
    ADD  A,A                 ; Finish placing the register field.
    ADD  A,$40               ; Add the ED IN r,(C) opcode base.
    JR   .INED               ; Add ED before this computed suffix.
.INBARE:
    LD   A,$70               ; Select the special IN (C) suffix.
    JR   .INED               ; Emit it behind the ED prefix.
.IIMMEDIA:
    LD   A,$DB               ; Select IN A,(n).
    JP   .SAV1E2             ; Append the immediate port byte.
.INED:
    LD   B,A                 ; Pass the computed ED suffix to the common tail.
    JP   .SEBE2              ; Stage ED and suffix, then return length two.
.OUT:

; ED output forms mirror IN; OUT (C),0 has the dedicated ED 71 encoding.

    LD   A,(IX+EN_OP0)       ; Read the output-port class.
    CP   EN_IMM8             ; Immediate port selects D3.
    JR   Z,.OIMMEDIA         ; Route OUT (n),A to its byte-value tail.
    LD   A,(IX+EN_OP1)       ; Read the value sent to port C.
    CP   EN_ZERO             ; Check the special zero-output form.
    LD   A,$71               ; Prepare the suffix for OUT (C),0.
    JR   Z,.INED             ; Emit ED 71 when the zero class matched.
    LD   A,(IX+EN_OP1)       ; Load the ordinary output register class.
    ADD  A,A                 ; Shift its register number toward bits 3..5.
    ADD  A,A                 ; Continue the three-bit field shift.
    ADD  A,A                 ; Finish placing the register field.
    ADD  A,$41               ; Add the ED OUT (C),r opcode base.
    JR   .INED               ; Emit the computed suffix after ED.
.OIMMEDIA:
    LD   A,$D3               ; Select OUT (n),A.
.SS0V0E2:
    LD   (EN_SCRAT+0),A      ; Stage the opcode before the immediate.
    LD   A,(IX+EN_VAL0)      ; Load operand zero's immediate byte.
    JP   .SS1E2              ; Append immediate; return length two.
.BIT:

; CB bit families are operation<<6 | bit<<3 | register. Indexed memory emits
; DD/FD CB displacement opcode, with field 6 when no register is given.

    LD   A,(IX+EN_MNEM)      ; Read BIT, RES or SET's ordinal.
    SUB  AT_MBIT-1           ; Map the family to the operation field.
    ADD  A,A                 ; Shift the operation field toward bits 6..7.
    ADD  A,A                 ; Continue moving it into its opcode position.
    ADD  A,A                 ; Continue the six-bit shift.
    ADD  A,A                 ; Continue the six-bit shift.
    ADD  A,A                 ; Continue the six-bit shift.
    ADD  A,A                 ; Finish operation<<6.
    LD   B,A                 ; Keep the operation field while building others.
    LD   A,(IX+EN_OP0)       ; Read the enumerated bit-number operand.
    AND  7                   ; Keep bit index 0..7.
    ADD  A,A                 ; Move the bit number into bits 3..5.
    ADD  A,A                 ; Continue the three-bit shift.
    ADD  A,A                 ; Finish bit<<3.
    ADD  A,B                 ; Combine operation and bit fields.
    LD   B,A                 ; Save both fields for the register field.
    LD   A,(IX+EN_OP1)       ; Read the register or memory target.
    CALL EN_IINDE            ; Test whether the target is indexed memory.
    JR   C,.BINDEXED         ; Indexed forms need prefix and displacement.
    LD   A,(IX+EN_OP1)       ; Reload the unindexed target class.
    JR   .CBPLAIN            ; Add its register field to the CB opcode.
.BINDEXED:
    LD   A,(IX+EN_OP2)       ; Read the optional result-register class.
    CP   EN_NONE             ; Check for a memory-only indexed operation.
    LD   A,6                 ; Register field 6 encodes memory as the target.
    JR   Z,.BIC              ; Keep field 6 when no result register is given.
    LD   A,(IX+EN_OP2)       ; Otherwise read the destination register class.
    AND  7                   ; Use its three-bit register number.
.BIC:
    ADD  A,B                 ; Add the target register field to prior fields.
    LD   B,A                 ; Save the completed second opcode byte.
    LD   A,(IX+EN_OP1)       ; Reload the indexed memory operand class.
    LD   E,(IX+EN_VAL1)      ; Save its indexed displacement.
    JR   .CITAIL             ; Emit prefix, CB, displacement, and opcode.
.ROTATE:

; Rotate/shift bases advance by eight. SLS shares SLL's hardware base,
; so the alias slot is removed before looking up either SLS or SRL.

    LD   A,(IX+EN_MNEM)      ; Read the rotate/shift mnemonic ordinal.
    SUB  AT_MRLC             ; Convert it to a zero-based family index.
    CP   7                   ; SLS and SRL need the alias slot removed.
    JR   C,.RBASE            ; Earlier operations use their direct index.
    DEC  A                   ; Map SLS to SLL and SRL to hardware index seven.
.RBASE:
    ADD  A,A                 ; Multiply the operation index by two.
    ADD  A,A                 ; Continue the shift by two bits.
    ADD  A,A                 ; Finish operation<<3.
    LD   B,A                 ; Preserve the operation field for the target.
    LD   A,(IX+EN_OP0)       ; Read the register or memory operand class.
    CALL EN_IINDE            ; Test whether the target is indexed memory.
    JR   C,.RINDEXED         ; Indexed forms need a four-byte layout.
    LD   A,(IX+EN_OP0)       ; Reload an unindexed register or (HL) class.
.CBPLAIN:

; Plain register and (HL) forms are CB followed by base | register field.

    AND  7                   ; Extract the target's three-bit register field.
    ADD  A,B                 ; Add target and operation fields.
    LD   B,A                 ; Keep the second CB opcode byte.
    LD   A,$CB               ; Select the CB prefix.
    JP   .SPBE2              ; Store CB and the operation byte.
.RINDEXED:

; Indexed rotate/shift can optionally copy the result to a register; otherwise
; field 6 denotes memory-only operation.

    LD   A,(IX+EN_OP1)       ; Read the optional result-register class.
    CP   EN_NONE             ; Check for memory-only indexed operation.
    LD   A,6                 ; Use register field 6 for memory-only form.
    JR   Z,.RIC              ; Keep that field when there is no copy target.
    LD   A,(IX+EN_OP1)       ; Otherwise read the copy-target register class.
    AND  7                   ; Extract its three-bit register number.
.RIC:
    ADD  A,B                 ; Add destination to operation base.
    LD   B,A                 ; Save the indexed CB opcode byte.
    LD   A,(IX+EN_OP0)       ; Reload the indexed memory class for its prefix.
    LD   E,(IX+EN_VAL0)      ; Preserve the signed displacement byte.
.CITAIL:

; Indexed CB byte order is prefix, CB, displacement, opcode.
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD for IX or FD for IY.
    LD   (EN_SCRAT+0),A      ; Store the index prefix.
    LD   A,$CB               ; Select the indexed-CB prefix byte.
    LD   (EN_SCRAT+1),A      ; Store CB after DD/FD.
    LD   A,E                 ; Load the previously saved displacement.
    LD   (EN_SCRAT+2),A      ; Store displacement before the CB opcode.
    LD   A,B                 ; Load the computed bit/rotate opcode byte.
    JP   .SS3E4               ; Store it last and return a four-byte length.
.ALU:

; The byte family ordinal is already the hardware operation field. One-operand
; records use register/memory/immediate equations; two-operand records are the
; separate 16-bit ADD/ADC/SBC forms.

    LD   A,(IX+EN_MNEM)      ; Read the ALU mnemonic ordinal.
    SUB  AT_MADD             ; Convert ADD..CP to an operation field.
    ADD  A,A                 ; Move the field toward bits 3..5.
    ADD  A,A                 ; Continue the three-bit shift.
    ADD  A,A                 ; Finish operation<<3.
    LD   B,A                 ; Preserve the operation field.
    LD   A,(IX+EN_OP1)       ; Check whether a second operand is present.
    CP   EN_NONE             ; No second operand means the byte-ALU form.
    JR   NZ,.ALU16            ; Otherwise encode a 16-bit arithmetic form.
    LD   A,(IX+EN_OP0)       ; Read the byte operand class.
    CP   EN_IMM8             ; Immediate bytes have a fixed opcode base.
    JR   Z,.AIMMEDIA          ; Route the immediate form.
    CALL EN_IHIND            ; Test whether the operand is an index half.
    JR   C,.ALUHALF           ; Index halves need DD/FD before the ALU opcode.
    LD   A,(IX+EN_OP0)       ; Reload the operand class for indexed memory.
    CALL EN_IINDE            ; Check for (IX/IY+d).
    JR   C,.AINDEXED          ; Indexed memory needs prefix and offset.
    LD   A,(IX+EN_OP0)       ; Reload the register or (HL) class.
    AND  7                   ; Extract the three-bit register field.
    ADD  A,B                 ; Combine register and operation fields.
    ADD  A,$80               ; Select the register/(HL) ALU opcode range.
    JP   .SE1                ; Store and return the one-byte form.
.AIMMEDIA:

; ALU A,n = C6 | operation<<3 followed by the immediate byte.

    LD   A,B                 ; Load operation<<3.
    ADD  A,$C6               ; Form C6 | operation<<3 for ALU A,n.
    JP   .SS0V0E2            ; Store opcode then immediate byte.
.ALUHALF:

; IXH/IXL/IYH/IYL reuse H/L fields behind DD/FD.

    LD   A,(IX+EN_OP0)       ; Load IXH/IXL/IYH/IYL class for prefix choice.
    CALL EN_SPPAF            ; Store DD/FD while preserving the class in A.
    AND  7                   ; Reuse the H/L register field.
    ADD  A,B                 ; Combine index-half and ALU operation fields.
    ADD  A,$80               ; Form the ordinary register ALU opcode.
    JP   .SS1E2              ; Append it after DD/FD and return length two.
.AINDEXED:

; ALU A,(IX/IY+d) reuses the (HL) field 6 and inserts displacement.

    CALL EN_SPPAF            ; Store DD/FD selected from the memory class.
    LD   A,B                 ; Load operation<<3.
    ADD  A,$86               ; Use register field 6 for indexed memory.
    JP   .SS1V0E3            ; Append displacement and return length three.
.ALU16:

; ADC/SBC HL,rr use ED 4A/42 | rr<<4.

    LD   A,(IX+EN_MNEM)      ; Read the 16-bit arithmetic mnemonic.
    CP   AT_MADD             ; Test for ADD's distinct pair form.
    JR   Z,.ADD16            ; Encode ADD HL/IX/IY,rr separately.
    LD   B,$42               ; SBC HL,rr uses ED 42 plus pair field.
    CP   AT_MSBC             ; Select SBC's base opcode.
    JR   Z,.AS1READY          ; Keep 42 for SBC.
    LD   B,$4A               ; ADC HL,rr uses ED 4A plus pair field.
.AS1READY:
    LD   A,(IX+EN_OP1)       ; Read BC, DE, HL or SP source-pair class.
    AND  3                   ; Keep its two-bit register-pair number.
    ADD  A,A                 ; Move the pair field toward bits 4..5.
    ADD  A,A                 ; Continue shifting the field.
    ADD  A,A                 ; Continue shifting the field.
    ADD  A,A                 ; Finish pair<<4.
    ADD  A,B                 ; Combine pair field with ADC/SBC base.
    LD   B,A                 ; Pass the ED suffix to the shared prefix tail.
    JP   .SEBE2              ; Emit ED and the computed suffix.
.ADD16:

; ADD HL,rr is 09 | rr<<4. IX/IY use a prefix and map a self operand to the HL
; field while BC, DE and SP retain their ordinary pair fields.

    LD   A,(IX+EN_OP1)       ; Read the source pair class.
    CP   EN_IX               ; IX's self-pair uses the HL field.
    JR   Z,.A1SELF           ; Map IX to pair number two.
    CP   EN_IY               ; IY's self-pair also uses the HL field.
    JR   Z,.A1SELF           ; Map IY to pair number two.
    AND  3                   ; Keep BC, DE, HL or SP pair number.
    JR   .A1SREADY           ; Build the 09 + pair<<4 opcode.
.A1SELF:
    LD   A,2                 ; Select the HL pair field for IX/IY self-add.
.A1SREADY:
    ADD  A,A                 ; Shift the source pair field toward bits 4..5.
    ADD  A,A                 ; Continue the four-bit shift.
    ADD  A,A                 ; Continue the four-bit shift.
    ADD  A,A                 ; Finish pair<<4.
    ADD  A,$09               ; Add the 16-bit ADD opcode base.
    LD   B,A                 ; Save opcode while checking destination.
    LD   A,(IX+EN_OP0)       ; Read the destination pair class.
    CP   EN_HL               ; HL needs no index prefix.
    LD   A,B                 ; Restore the computed ADD opcode.
    JP   Z,.SE1              ; Emit the unprefixed HL pair form.
    LD   A,(IX+EN_OP0)       ; Reload IX/IY destination to select its prefix.
;@EXPECTOUT A
    CALL EN_PFOP             ; Choose DD or FD from destination IX/IY.
    LD   (EN_SCRAT+0),A      ; Store the index prefix.
    LD   A,B                 ; Restore the computed ADD pair opcode.
    JR   .SS1E2              ; Append it and return length two.
.JP:

; Absolute JP is C3 nn; JP (HL) is E9 and IX/IY add their prefix.

    LD   A,(IX+EN_OP1)       ; Check whether a condition operand is present.
    CP   EN_NONE             ; No second operand selects unconditional JP.
    JR   NZ,.JCONDITI         ; Otherwise encode JP cc,nn.
    LD   A,(IX+EN_OP0)       ; Read the target class for indirect JP.
    CP   EN_MEMHL            ; JP (HL) uses E9 without a prefix.
    JR   Z,.JPHL             ; Emit the one-byte indirect form.
    CP   EN_MEMIX            ; JP (IX) uses the index prefix plus E9.
    JR   Z,.JPINDEX           ; Share the indexed indirect encoding.
    CP   EN_MEMIY            ; JP (IY) follows the same form with FD.
    JR   Z,.JPINDEX           ; Share the indexed indirect encoding.
    LD   A,$C3               ; Select the absolute JP opcode.
    JP   .SAV0E3              ; Append target word; return length three.
.JCONDITI:

; JP cc,nn = C2 | cc<<3 followed by operand one's word.

    LD   B,$C2               ; Conditional JP base is C2.
    CALL EN_COPCO            ; Insert condition code in bits 3..5.
    JP   .SAV1E3              ; Append operand one's address word.
.JPHL:
    LD   A,$E9               ; Select JP (HL).
    JR   .SE1                ; Store the single opcode byte.
.JPINDEX:
;@EXPECTOUT A
    CALL EN_PFOP             ; Select DD for IX or FD for IY.
    LD   (EN_SCRAT+0),A      ; Store the index prefix.
    LD   A,$E9               ; Indexed indirect JP uses the same E9 opcode.
    JR   .SS1E2              ; Append E9 and return a two-byte length.
.CALL:

; CALL nn is CD nn; CALL cc,nn = C4 | cc<<3.

    LD   A,(IX+EN_OP1)       ; Check whether a condition operand is present.
    CP   EN_NONE             ; No second operand selects unconditional CALL.
    JR   NZ,.CCONDITI         ; Otherwise encode CALL cc,nn.
    LD   A,$CD               ; Select the unconditional CALL opcode.
    JP   .SAV0E3              ; Append target word; return length three.
.CCONDITI:
    LD   B,$C4               ; Conditional CALL base is C4.
    CALL EN_COPCO            ; Insert condition code in bits 3..5.
    LD   (EN_SCRAT+0),A      ; Stage the conditional CALL opcode.
    JR   AT_CV1TS            ; Append operand one's target word.
.JR:

; JR e is 18 e; JR cc,e = 20 | cc<<3 for the four accepted conditions.

    LD   A,(IX+EN_OP1)       ; Check whether a condition operand is present.
    CP   EN_NONE             ; No condition selects unconditional JR.
    JR   NZ,.JCONDIT1         ; Otherwise encode JR cc,e.
    LD   A,$18               ; Select unconditional relative-jump opcode.
    LD   (EN_SCRAT+0),A      ; Stage the opcode before the displacement.
    LD   A,(IX+EN_VAL0)      ; Load the assembler-computed relative offset.
    JR   .SS1E2              ; Append the offset and return length two.
.JCONDIT1:
    LD   B,$20               ; Conditional JR base is 20.
    CALL EN_COPCO            ; Insert the condition code in bits 3..5.
    LD   (EN_SCRAT+0),A      ; Stage the conditional JR opcode.
    LD   A,(IX+EN_VAL1)      ; Load operand one's computed displacement.
    JR   .SS1E2              ; Append it and return length two.
.DJNZ:

; DJNZ is 10 followed by the parser-computed displacement.

    LD   A,$10               ; Select DJNZ's relative-branch opcode.
    LD   (EN_SCRAT+0),A      ; Stage the opcode.
    LD   A,(IX+EN_VAL0)      ; Load the assembler-computed displacement.
.SS1E2:
    LD   (EN_SCRAT+1),A      ; Store the second instruction byte.
    JR   EN_D2               ; Return successful length two.
.EDTABLE:

; Encoder family table selected by AT_DMNEM.

    DW .COPCODE,.RET,.EX       ; Core, return, and exchange handlers.
    DW .IM,.RST,.INCDEC        ; IM, RST, and byte/pair INC/DEC.
    DW .STACK,.LD,.IN          ; Stack pairs, load, and port input.
    DW .OUT,.BIT,.ROTATE       ; Port output, bit operations, and shifts.
    DW .ALU,.JP,.CALL          ; Arithmetic and absolute control flow.
    DW .JR,.DJNZ               ; Relative branches and decrement-and-branch.
.SE1:

; Successful returns: carry clear, A = encoded length.

    LD   (EN_SCRAT+0),A      ; Stage the one-byte opcode.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length one.

EN_D1:
    XOR  A                    ; Clear A and carry for success status.
    INC  A                    ; Return encoded length one.
    RET                       ; Finish with carry still clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length two.

EN_D2:
    LD   A,2                  ; Return encoded length two.
    OR   A                    ; Clear carry without changing the length.
    RET                       ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length three.

EN_D3:
    LD   A,3                  ; Return encoded length three.
    OR   A                    ; Clear carry without changing the length.
    RET                       ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length four.

EN_D4:
    LD   A,4                  ; Return encoded length four.
    OR   A                    ; Clear carry without changing the length.
    RET                       ; Finish with carry clear.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after one opcode byte.

AT_CV0TS:
    LD   L,(IX+EN_VAL0)      ; Load operand zero's address low byte.
    LD   H,(IX+EN_VAL0+1)    ; Load its address high byte.
    LD   (EN_SCRAT+1),HL     ; Store the address after a one-byte opcode.
    JR   EN_D3               ; Return the three-byte instruction length.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after a prefix/opcode pair.

AT_CV0T1:
    LD   L,(IX+EN_VAL0)      ; Load operand zero's address low byte.
    LD   H,(IX+EN_VAL0+1)    ; Load its address high byte.
    LD   (EN_SCRAT+2),HL     ; Store address after prefix/opcode.
    JR   EN_D4               ; Return the four-byte instruction length.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after one opcode byte.

AT_CV1TS:
    LD   L,(IX+EN_VAL1)      ; Load operand one's address low byte.
    LD   H,(IX+EN_VAL1+1)    ; Load its address high byte.
    LD   (EN_SCRAT+1),HL     ; Store the address after a one-byte opcode.
    JR   EN_D3               ; Return the three-byte instruction length.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after a prefix/opcode pair.

AT_CV1T1:
    LD   L,(IX+EN_VAL1)      ; Load operand one's address low byte.
    LD   H,(IX+EN_VAL1+1)    ; Load its address high byte.
    LD   (EN_SCRAT+2),HL     ; Store address after prefix/opcode.
    JR   EN_D4               ; Return the four-byte instruction length.

;@ROUTINE IN A
; Store the prefix chosen by operand class A. Preserve A for field math.

EN_SPPAF:
    PUSH AF                  ; Save the operand class.
;@EXPECTOUT A
    CALL EN_PFOP             ; Convert the operand class to DD or FD.
    LD   (EN_SCRAT+0),A      ; Stage the selected index prefix.
    POP  AF                  ; Restore class for register-field math.
    RET                      ; Return with the original class in A.

;@ROUTINE IN A OUT A CLOBBERS F
; Map IX classes and even indexed-memory classes to DD; IY classes
; and odd indexed-memory classes to FD. Validation guarantees A is prefixable.

EN_PFOP:
    CP   EN_IXH              ; Index-half classes begin at IXH.
    JR   C,.PORDINAR         ; Pair/memory classes use their family bit.
    CP   EN_IXL+1            ; Check the end of IXH/IXL's class range.
    JR   C,.PREFIXIX         ; IX halves always select DD.
    CP   EN_IYH              ; Check whether this is below the IY-half range.
    JR   C,.PORDINAR         ; Other prefixable classes use their family tag.
    CP   EN_IYL+1            ; Check the end of IYH/IYL's class range.
    JR   C,.PREFIXIY         ; IY halves always select FD.
.PORDINAR:
    AND  1                   ; Even means IX; odd means IY.
    JR   NZ,.PREFIXIY        ; Select FD for an odd IY-family class.
.PREFIXIX:
    LD   A,$DD               ; Return the IX prefix byte.
    RET                      ; Finish prefix selection.
.PREFIXIY:
    LD   A,$FD               ; Return the IY prefix byte.
    RET                      ; Finish prefix selection.
EN_RECEN:
EN_CODEE:
EN_IBEG:
EN_CTBEG:

; Irregular core opcodes. The first thirteen are direct one-byte instructions;
; the remaining entries are suffixes emitted after ED.

EN_COPC1:
    DB $00,$F3,$FB,$37,$3F,$2F,$27,$D9,$76,$07,$0F,$17,$1F  ; Core opcodes.
    DB $44,$67,$6F,$A0,$B0,$A8,$B8,$A1,$B1,$A9,$B9,$A2  ; ED suffixes.
    DB $B2,$AA,$BA,$A3,$B3,$AB,$BB,$4D,$45             ; INIR..RETN suffixes.
EN_IOPCO: DB $46,$56,$5E                                  ; IM suffixes.
EN_CTEND:
EN_CNT EQU 69                ; Number of mnemonic ordinals in the table.

; Compact mnemonic table in ordinal order. Each three-byte entry stores the
; first packed RADIX-40 word and the significant high byte of the second word.

EN_TABLE:
    DW  $59E8                ; NOP packed mnemonic key, low two bytes.
    DB  $00                  ; NOP packed mnemonic key, final byte.
    DW  $1A68                ; DI packed mnemonic key, low two bytes.
    DB  $00                  ; DI packed mnemonic key, final byte.
    DW  $20A8                ; EI packed mnemonic key, low two bytes.
    DB  $00                  ; EI packed mnemonic key, final byte.
    DW  $773E                ; SCF packed mnemonic key, low two bytes.
    DB  $00                  ; SCF packed mnemonic key, final byte.
    DW  $133E                ; CCF packed mnemonic key, low two bytes.
    DB  $00                  ; CCF packed mnemonic key, final byte.
    DW  $154C                ; CPL packed mnemonic key, low two bytes.
    DB  $00                  ; CPL packed mnemonic key, final byte.
    DW  $1929                ; DAA packed mnemonic key, low two bytes.
    DB  $00                  ; DAA packed mnemonic key, final byte.
    DW  $2318                ; EXX packed mnemonic key, low two bytes.
    DB  $00                  ; EXX packed mnemonic key, final byte.
    DW  $3234                ; HALT packed mnemonic key, low two bytes.
    DB  $7D                  ; HALT packed mnemonic key, final byte.
    DW  $7263                ; RLCA packed mnemonic key, low two bytes.
    DB  $06                  ; RLCA packed mnemonic key, final byte.
    DW  $7353                ; RRCA packed mnemonic key, low two bytes.
    DB  $06                  ; RRCA packed mnemonic key, final byte.
    DW  $7261                ; RLA packed mnemonic key, low two bytes.
    DB  $00                  ; RLA packed mnemonic key, final byte.
    DW  $7351                ; RRA packed mnemonic key, low two bytes.
    DB  $00                  ; RRA packed mnemonic key, final byte.
    DW  $584F                ; NEG packed mnemonic key, low two bytes.
    DB  $00                  ; NEG packed mnemonic key, final byte.
    DW  $7354                ; RRD packed mnemonic key, low two bytes.
    DB  $00                  ; RRD packed mnemonic key, final byte.
    DW  $7264                ; RLD packed mnemonic key, low two bytes.
    DB  $00                  ; RLD packed mnemonic key, final byte.
    DW  $4BA9                ; LDI packed mnemonic key, low two bytes.
    DB  $00                  ; LDI packed mnemonic key, final byte.
    DW  $4BA9                ; LDIR packed mnemonic key, low two bytes.
    DB  $70                  ; LDIR packed mnemonic key, final byte.
    DW  $4BA4                ; LDD packed mnemonic key, low two bytes.
    DB  $00                  ; LDD packed mnemonic key, final byte.
    DW  $4BA4                ; LDDR packed mnemonic key, low two bytes.
    DB  $70                  ; LDDR packed mnemonic key, final byte.
    DW  $1549                ; CPI packed mnemonic key, low two bytes.
    DB  $00                  ; CPI packed mnemonic key, final byte.
    DW  $1549                ; CPIR packed mnemonic key, low two bytes.
    DB  $70                  ; CPIR packed mnemonic key, final byte.
    DW  $1544                ; CPD packed mnemonic key, low two bytes.
    DB  $00                  ; CPD packed mnemonic key, final byte.
    DW  $1544                ; CPDR packed mnemonic key, low two bytes.
    DB  $70                  ; CPDR packed mnemonic key, final byte.
    DW  $3A79                ; INI packed mnemonic key, low two bytes.
    DB  $00                  ; INI packed mnemonic key, final byte.
    DW  $3A79                ; INIR packed mnemonic key, low two bytes.
    DB  $70                  ; INIR packed mnemonic key, final byte.
    DW  $3A74                ; IND packed mnemonic key, low two bytes.
    DB  $00                  ; IND packed mnemonic key, final byte.
    DW  $3A74                ; INDR packed mnemonic key, low two bytes.
    DB  $70                  ; INDR packed mnemonic key, final byte.
    DW  $611C                ; OUTI packed mnemonic key, low two bytes.
    DB  $38                  ; OUTI packed mnemonic key, final byte.
    DW  $60E9                ; OTIR packed mnemonic key, low two bytes.
    DB  $70                  ; OTIR packed mnemonic key, final byte.
    DW  $611C                ; OUTD packed mnemonic key, low two bytes.
    DB  $19                  ; OUTD packed mnemonic key, final byte.
    DW  $60E4                ; OTDR packed mnemonic key, low two bytes.
    DB  $70                  ; OTDR packed mnemonic key, final byte.
    DW  $715C                ; RETI packed mnemonic key, low two bytes.
    DB  $38                  ; RETI packed mnemonic key, final byte.
    DW  $715C                ; RETN packed mnemonic key, low two bytes.
    DB  $57                  ; RETN packed mnemonic key, final byte.
    DW  $715C                ; RET packed mnemonic key, low two bytes.
    DB  $00                  ; RET packed mnemonic key, final byte.
    DW  $2300                ; EX packed mnemonic key, low two bytes.
    DB  $00                  ; EX packed mnemonic key, final byte.
    DW  $3A48                ; IM packed mnemonic key, low two bytes.
    DB  $00                  ; IM packed mnemonic key, final byte.
    DW  $738C                ; RST packed mnemonic key, low two bytes.
    DB  $00                  ; RST packed mnemonic key, final byte.
    DW  $3A73                ; INC packed mnemonic key, low two bytes.
    DB  $00                  ; INC packed mnemonic key, final byte.
    DW  $19CB                ; DEC packed mnemonic key, low two bytes.
    DB  $00                  ; DEC packed mnemonic key, final byte.
    DW  $675B                ; PUSH packed mnemonic key, low two bytes.
    DB  $32                  ; PUSH packed mnemonic key, final byte.
    DW  $6668                ; POP packed mnemonic key, low two bytes.
    DB  $00                  ; POP packed mnemonic key, final byte.
    DW  $4BA0                ; LD packed mnemonic key, low two bytes.
    DB  $00                  ; LD packed mnemonic key, final byte.
    DW  $3A70                ; IN packed mnemonic key, low two bytes.
    DB  $00                  ; IN packed mnemonic key, final byte.
    DW  $611C                ; OUT packed mnemonic key, low two bytes.
    DB  $00                  ; OUT packed mnemonic key, final byte.
    DW  $0DFC                ; BIT packed mnemonic key, low two bytes.
    DB  $00                  ; BIT packed mnemonic key, final byte.
    DW  $715B                ; RES packed mnemonic key, low two bytes.
    DB  $00                  ; RES packed mnemonic key, final byte.
    DW  $779C                ; SET packed mnemonic key, low two bytes.
    DB  $00                  ; SET packed mnemonic key, final byte.
    DW  $7263                ; RLC packed mnemonic key, low two bytes.
    DB  $00                  ; RLC packed mnemonic key, final byte.
    DW  $7353                ; RRC packed mnemonic key, low two bytes.
    DB  $00                  ; RRC packed mnemonic key, final byte.
    DW  $7260                ; RL packed mnemonic key, low two bytes.
    DB  $00                  ; RL packed mnemonic key, final byte.
    DW  $7350                ; RR packed mnemonic key, low two bytes.
    DB  $00                  ; RR packed mnemonic key, final byte.
    DW  $78A1                ; SLA packed mnemonic key, low two bytes.
    DB  $00                  ; SLA packed mnemonic key, final byte.
    DW  $7991                ; SRA packed mnemonic key, low two bytes.
    DB  $00                  ; SRA packed mnemonic key, final byte.
    DW  $78AC                ; SLL packed mnemonic key, low two bytes.
    DB  $00                  ; SLL packed mnemonic key, final byte.
    DW  $78B3                ; SLS packed mnemonic key, low two bytes.
    DB  $00                  ; SLS packed mnemonic key, final byte.
    DW  $799C                ; SRL packed mnemonic key, low two bytes.
    DB  $00                  ; SRL packed mnemonic key, final byte.
    DW  $06E4                ; ADD packed mnemonic key, low two bytes.
    DB  $00                  ; ADD packed mnemonic key, final byte.
    DW  $06E3                ; ADC packed mnemonic key, low two bytes.
    DB  $00                  ; ADC packed mnemonic key, final byte.
    DW  $7A0A                ; SUB packed mnemonic key, low two bytes.
    DB  $00                  ; SUB packed mnemonic key, final byte.
    DW  $7713                ; SBC packed mnemonic key, low two bytes.
    DB  $00                  ; SBC packed mnemonic key, final byte.
    DW  $0874                ; AND packed mnemonic key, low two bytes.
    DB  $00                  ; AND packed mnemonic key, final byte.
    DW  $986A                ; XOR packed mnemonic key, low two bytes.
    DB  $00                  ; XOR packed mnemonic key, final byte.
    DW  $6090                ; OR packed mnemonic key, low two bytes.
    DB  $00                  ; OR packed mnemonic key, final byte.
    DW  $1540                ; CP packed mnemonic key, low two bytes.
    DB  $00                  ; CP packed mnemonic key, final byte.
    DW  $4100                ; JP packed mnemonic key, low two bytes.
    DB  $00                  ; JP packed mnemonic key, final byte.
    DW  $12F4                ; CALL packed mnemonic key, low two bytes.
    DB  $4B                  ; CALL packed mnemonic key, final byte.
    DW  $4150                ; JR packed mnemonic key, low two bytes.
    DB  $00                  ; JR packed mnemonic key, final byte.
    DW  $1A9E                ; DJNZ packed mnemonic key, low two bytes.
    DB  $A2                  ; DJNZ packed mnemonic key, final byte.
EN_TEND:
EN_IEND:
EN_COREE:
EN_WBEG:

; Scratch: six bytes for packed names; first four also stage opcodes.

EN_SCRAT: DS 6                ; Packer scratch and opcode staging.
EN_WEND:
