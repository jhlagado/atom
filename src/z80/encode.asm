;==============================================================================
;  Z80 instruction byte emission
;==============================================================================
;
;  Validate each record, encode its opcode in private scratch, then publish only
;  the successful one-to-four-byte result to the caller's destination.

EN_RECBE:

;@ROUTINE IN IX,DE OUT A,DE,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate and encode the record at IX, then commit its one-to-four bytes to DE.
; EN_CORE writes only EN_SCRAT; the caller destination is untouched on failure.

EN_NAME:
    PUSH DE
    CALL EN_VFORM
    POP  DE
    RET  C
    PUSH DE
;@EXPECTOUT A
    CALL EN_CORE
    POP  DE
    LD   C,A
    LD   B,0
    LD   HL,EN_SCRAT
    LDIR
    OR   A
    RET

;@ROUTINE IN IX,B OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Encode a condition field into bits 3..5 and add the opcode-family base in B.

EN_COPCO:
    LD   A,(IX+EN_OP0)
    SUB  EN_NZ
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    RET

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
; Encode a record already proved by EN_VFORM. The mnemonic-family table mirrors
; the validator table so both paths make the same ordinal partition explicit.

EN_CORE:
    LD   A,(IX+EN_MNEM)
    LD   DE,.EDTABLE
    JP   AT_DMNEM
.COPCODE:

; Core opcode ordinals index the irregular one-byte/ED-suffixed table. Ordinals
; 1..13 are direct bytes; 14..34 use the shared ED-prefix tail.

    LD   B,A
    DEC  A
    LD   E,A
    LD   D,0
    LD   HL,EN_COPC1
    ADD  HL,DE
    LD   A,B
    CP   14
    LD   A,(HL)
    JP   C,.SE1
    LD   B,A
    JP   .SEBE2
.RET:

; Conditional RET is C0 | cc<<3; plain RET is the singleton C9.

    LD   A,(IX+EN_OP0)
    CP   EN_NONE
    JR   Z,.RETPLAIN
    LD   B,$C0
    CALL EN_COPCO
    JP   .SE1
.RETPLAIN:
    LD   A,$C9
    JP   .SE1
.EX:

; EX AF,AF', EX DE,HL and EX (SP),HL are singletons. IX/IY stack exchange adds
; the selected prefix before the E3 opcode.

    LD   A,(IX+EN_OP0)
    CP   EN_AF
    JR   Z,.EXAF
    CP   EN_DE
    JR   Z,.EXDE
    LD   A,(IX+EN_OP1)
    CP   EN_HL
    JR   Z,.EXSPHL
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,$E3
    JP   .SS1E2
.EXAF:
    LD   A,$08
    JP   .SE1
.EXDE:
    LD   A,$EB
    JP   .SE1
.EXSPHL:
    LD   A,$E3
    JP   .SE1
.IM:

; IM's three enumerated classes select the irregular ED suffix table.

    LD   A,(IX+EN_OP0)
    SUB  EN_IM0
    LD   E,A
    LD   D,0
    LD   HL,EN_IOPCO
    ADD  HL,DE
    LD   A,(HL)
    LD   B,A
    JP   .SEBE2
.RST:

; RST classes are ordered vectors, so C7 | vector produces the opcode.

    LD   A,(IX+EN_OP0)
    SUB  EN_RST0
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$C7
    JP   .SE1
.INCDEC:

; B begins as the byte-field base 04/05. Pair handling replaces it with 03/0B;
; memory handling adds 30 to produce 34/35. Indexed forms add prefix/displacement.

    LD   A,(IX+EN_MNEM)
    SUB  AT_MINC-4
    LD   B,A
    LD   A,(IX+EN_OP0)
    CALL EN_IR8
    JR   C,.IDREGIST
    LD   A,(IX+EN_OP0)
    CALL EN_IR16
    JR   C,.IDPAIR
    LD   A,(IX+EN_OP0)
    CP   EN_IX
    JR   Z,.IDIPAIR
    CP   EN_IY
    JR   Z,.IDIPAIR
    CALL EN_IHIND
    JR   C,.IDHALF
    LD   A,(IX+EN_OP0)
    CP   EN_MEMHL
    JR   Z,.IDMHL
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,B
    ADD  A,$30
    LD   (EN_SCRAT+1),A
    LD   A,(IX+EN_VAL0)
.SS2E3:
    LD   (EN_SCRAT+2),A
    JP   EN_D3
.IDREGIST:

; INC/DEC r = base | r<<3.

    LD   A,(IX+EN_OP0)
.TSAB:
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    JP   .SE1
.IDPAIR:

; INC/DEC rr = 03/0B | pair<<4.

    LD   A,B
    CP   4
    LD   B,$03
    JR   Z,.IDPBREAD
    LD   B,$0B
.IDPBREAD:
    LD   A,(IX+EN_OP0)
.PFB:
    AND  3
    ADD  A,A
    JR   .TSAB
.IDIPAIR:

; IX/IY pair operations reuse the HL opcode behind DD/FD.

    CALL EN_SPPAF
    LD   A,B
    CP   4
    LD   A,$23
    JR   Z,.IDIPREAD
    LD   A,$2B
.IDIPREAD:
    JP   .SS1E2
.IDHALF:

; Index halves reuse H/L field values behind their family prefix.

    LD   A,(IX+EN_OP0)
    CALL EN_SPPAF
    AND  7
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    JP   .SS1E2
.IDMHL:
    LD   A,B
    ADD  A,$30
    JP   .SE1
.STACK:

; PUSH/POP use C5/C1 | pair<<4. IX/IY reuse the HL field behind DD/FD.

    LD   A,(IX+EN_MNEM)
    CP   AT_MPUSH
    LD   B,$C5
    JR   Z,.SBASE
    LD   B,$C1
.SBASE:
    LD   A,(IX+EN_OP0)
    CP   EN_IX
    JR   Z,.SINDEX
    CP   EN_IY
    JR   Z,.SINDEX
    JR   .PFB
.SINDEX:
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,B
    ADD  A,$20
    JP   .SS1E2
EN_LEBEG EQU $
.LD:

; Encoding follows the same destination-first partition as validation. Keeping
; these paths parallel makes the least regular Z80 family auditable.

    LD   A,(IX+EN_OP0)
    CALL EN_IR8
    JR   C,.LDREG8
    LD   A,(IX+EN_OP0)
    CALL EN_IHIND
    JP   C,.LDHALF
    LD   A,(IX+EN_OP0)
    CALL EN_IR16
    JP   C,.LDREG16
    LD   A,(IX+EN_OP0)
    CP   EN_IX
    JP   Z,.LI16
    CP   EN_IY
    JP   Z,.LI16
    CP   EN_I
    JP   Z,.LSTARGET
    CP   EN_R
    JP   Z,.LSTARGET
    CP   EN_MABS
    JP   Z,.LDMEMABS
    CP   EN_MEMBC
    JP   Z,.LMPAIR
    CP   EN_MEMDE
    JP   Z,.LMPAIR
    CP   EN_MEMHL
    JP   Z,.LDMEMHL
    JP   .LINDEXED
.LDREG8:

; Ordinary register destinations divide into register, immediate, memory,
; special-register, indexed-memory and index-half sources.

    LD   A,(IX+EN_OP1)
    CALL EN_IR8
    JR   C,.LDREGREG
    LD   A,(IX+EN_OP1)
    CP   EN_IMM8
    JR   Z,.LDREGIMM
    CP   EN_MEMHL
    JR   Z,.LRMHL
    CP   EN_MABS
    JR   Z,.LDAABS
    CP   EN_MEMBC
    JR   Z,.LAMPAIR
    CP   EN_MEMDE
    JR   Z,.LAMPAIR
    CP   EN_I
    JR   Z,.LASPECIA
    CP   EN_R
    JR   Z,.LASPECIA
    CALL EN_IINDE
    JR   C,.LRINDEXE
    JR   .LRHALF
.LDREGREG:

; LD r,r' = 40 | destination<<3 | source.

    LD   B,A
    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    ADD  A,$40
    JP   .SE1
.LDREGIMM:

; LD r,n = 06 | destination<<3, followed by the low value byte.

    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,6
.SAV1E2:
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_VAL1)
    JP   .SS1E2
.LRMHL:

; LD r,(HL) = 46 | destination<<3.

    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$46
    JP   .SE1
.LDAABS:

; LD A,(nn) is 3A followed by the absolute word.

    LD   A,$3A
.SAV1E3:
    LD   (EN_SCRAT+0),A
    JP   AT_CV1TS
.LAMPAIR:

; LD A,(BC/DE) uses 0A/1A, derived from the two memory classes.

    SUB  EN_MEMBC
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$0A
    JP   .SE1
.LASPECIA:

; LD A,I/R uses ED 57/5F.

    LD   B,$57
    CP   EN_I
    JR   Z,.LASREADY
    LD   B,$5F
.LASREADY:
.SEBE2:
    LD   A,$ED
.SPBE2:
    LD   (EN_SCRAT+0),A
    LD   A,B
    JP   .SS1E2
.LRINDEXE:

; Indexed memory reuses the (HL) opcode after DD/FD and inserts displacement.

    PUSH AF
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$46
    LD   (EN_SCRAT+1),A
    POP  AF
    LD   A,(IX+EN_VAL1)
    JP   .SS2E3
.LRHALF:

; An index-half source reuses H/L's source field behind the selected prefix.

    LD   A,(IX+EN_OP1)
    CALL EN_SPPAF
    AND  7
    LD   B,A
    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    JR   .LHOPCODE
.LDHALF:

; An index-half destination likewise reuses H/L's destination field. Validation
; has already proved that both halves, when present, use the same index family.

    CALL EN_SPPAF
    AND  7
    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   A,(IX+EN_OP1)
    AND  7
.LHOPCODE:
    ADD  A,B
    ADD  A,$40
    JP   .SS1E2
.LDREG16:

; Pair destinations cover immediate words and absolute loads. Atom also retains
; two pair-copy expansions: LD HL,DE emits LD H,D / LD L,E, while LD BC,DE emits
; LD B,D / LD C,E. LD SP,HL/IX/IY uses the hardware F9 form below.

    LD   A,(IX+EN_OP1)
    CP   EN_IMM16
    JR   Z,.LR1IMM
    CP   EN_MABS
    JR   Z,.LR1ABS
    LD   A,(IX+EN_OP0)
    CP   EN_SP
    JR   Z,.LDSP
    CP   EN_HL
    LD   A,$62
    JR   Z,.LDLEGACY
    LD   A,$42
.LDLEGACY:
    LD   (EN_SCRAT+0),A
    ADD  A,9
    JP   .SS1E2
.LR1IMM:

; LD rr,nn = 01 | rr<<4 followed by the word.

    LD   A,(IX+EN_OP0)
    AND  3
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    INC  A
    JP   .SAV1E3
.LR1ABS:

; HL has the direct 2A form; BC/DE/SP use ED 4B/5B/7B.

    LD   A,(IX+EN_OP0)
    CP   EN_HL
    JR   Z,.LDHLABS
    AND  3
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$4B
    LD   B,A
    LD   A,$ED
    LD   (EN_SCRAT+0),A
    LD   A,B
.SS1CV1TS:
    LD   (EN_SCRAT+1),A
    JP   AT_CV1T1
.LDHLABS:
    LD   A,$2A
    JP   .SAV1E3
.LDSP:

; LD SP,HL is F9; IX/IY use the same opcode behind their prefix.

    LD   A,(IX+EN_OP1)
    CP   EN_HL
    LD   A,$F9
    JP   Z,.SE1
    LD   A,(IX+EN_OP1)
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,$F9
    JP   .SS1E2
.LI16:

; LD IX/IY,nn and LD IX/IY,(nn) are prefixed HL forms 21 and 2A.

    CALL EN_SPPAF
    LD   A,(IX+EN_OP1)
    CP   EN_IMM16
    LD   A,$21
    JR   Z,.LI1OPCOD
    LD   A,$2A
.LI1OPCOD:
    JR   .SS1CV1TS
.LSTARGET:

; LD I/R,A uses ED 47/4F.

    LD   B,$47
    CP   EN_I
    JR   Z,.LSTREADY
    LD   B,$4F
.LSTREADY:
    JP   .SEBE2
.LDMEMABS:

; Absolute-memory stores select A, HL, ordinary pairs or IX/IY and append the
; destination address word from operand zero.

    LD   A,(IX+EN_OP1)
    CP   EN_A
    JR   Z,.LDABSA
    CALL EN_IR16
    JR   NC,.LAINDEX
    CP   EN_HL
    JR   Z,.LDABSHL
    AND  3
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$43
    LD   B,A
    LD   A,$ED
    LD   (EN_SCRAT+0),A
    LD   A,B
.SS1CV0TS:
    LD   (EN_SCRAT+1),A
    JP   AT_CV0T1
.LDABSA:
    LD   A,$32
.SAV0E3:
    LD   (EN_SCRAT+0),A
    JP   AT_CV0TS
.LDABSHL:
    LD   A,$22
    JR   .SAV0E3
.LAINDEX:
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,$22
    JR   .SS1CV0TS
.LMPAIR:

; LD (BC/DE),A uses 02/12.

    SUB  EN_MEMBC
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$02
    JP   .SE1
.LDMEMHL:

; LD (HL),r uses 70 | r; LD (HL),n is 36 n.

    LD   A,(IX+EN_OP1)
    CP   EN_IMM8
    JR   Z,.LMHIMM
    ADD  A,$70
    JP   .SE1
.LMHIMM:
    LD   A,$36
    JP   .SAV1E2
.LINDEXED:

; LD (IX/IY+d),r reuses 70 | r. The immediate form is four bytes because both
; displacement and immediate data follow the prefixed 36 opcode.

    LD   A,(IX+EN_OP0)
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_OP1)
    CP   EN_IMM8
    JR   Z,.LIIMM
    ADD  A,$70
.SS1V0E3:
    LD   (EN_SCRAT+1),A
    LD   A,(IX+EN_VAL0)
    JP   .SS2E3
.LIIMM:
    LD   A,$36
    LD   (EN_SCRAT+1),A
    LD   A,(IX+EN_VAL0)
    LD   (EN_SCRAT+2),A
    LD   A,(IX+EN_VAL1)
.SS3E4:
    LD   (EN_SCRAT+3),A
    JP   EN_D4
EN_LEEND EQU $
.IN:

; ED input forms encode the register field in bits 3..5. Immediate-port input is
; the singleton DB followed by the port byte.

    LD   A,(IX+EN_OP0)
    CP   EN_PORTC
    JR   Z,.INBARE
    LD   A,(IX+EN_OP1)
    CP   EN_IMM8
    JR   Z,.IIMMEDIA
    LD   A,(IX+EN_OP0)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$40
    JR   .INED
.INBARE:
    LD   A,$70
    JR   .INED
.IIMMEDIA:
    LD   A,$DB
    JP   .SAV1E2
.INED:
    LD   B,A
    JP   .SEBE2
.OUT:

; ED output forms mirror IN; OUT (C),0 has the dedicated ED 71 encoding.

    LD   A,(IX+EN_OP0)
    CP   EN_IMM8
    JR   Z,.OIMMEDIA
    LD   A,(IX+EN_OP1)
    CP   EN_ZERO
    LD   A,$71
    JR   Z,.INED
    LD   A,(IX+EN_OP1)
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$41
    JR   .INED
.OIMMEDIA:
    LD   A,$D3
.SS0V0E2:
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_VAL0)
    JP   .SS1E2
.BIT:

; CB bit families are operation<<6 | bit<<3 | register. Indexed memory emits
; DD/FD CB displacement opcode, with field 6 when no destination register exists.

    LD   A,(IX+EN_MNEM)
    SUB  AT_MBIT-1
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   A,(IX+EN_OP0)
    AND  7
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    LD   B,A
    LD   A,(IX+EN_OP1)
    CALL EN_IINDE
    JR   C,.BINDEXED
    LD   A,(IX+EN_OP1)
    JR   .CBPLAIN
.BINDEXED:
    LD   A,(IX+EN_OP2)
    CP   EN_NONE
    LD   A,6
    JR   Z,.BIC
    LD   A,(IX+EN_OP2)
    AND  7
.BIC:
    ADD  A,B
    LD   B,A
    LD   A,(IX+EN_OP1)
    LD   E,(IX+EN_VAL1)
    JR   .CITAIL
.ROTATE:

; Rotate/shift bases advance in steps of eight. SLS shares SLL's hardware base,
; so ordinals at and after the alias are folded down by one.

    LD   A,(IX+EN_MNEM)
    SUB  AT_MRLC
    CP   7
    JR   C,.RBASE
    DEC  A
.RBASE:
    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   A,(IX+EN_OP0)
    CALL EN_IINDE
    JR   C,.RINDEXED
    LD   A,(IX+EN_OP0)
.CBPLAIN:

; Plain register and (HL) forms are CB followed by base | register field.

    AND  7
    ADD  A,B
    LD   B,A
    LD   A,$CB
    JP   .SPBE2
.RINDEXED:

; Indexed rotate/shift can optionally copy the result to a register; otherwise
; field 6 denotes memory-only operation.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    LD   A,6
    JR   Z,.RIC
    LD   A,(IX+EN_OP1)
    AND  7
.RIC:
    ADD  A,B
    LD   B,A
    LD   A,(IX+EN_OP0)
    LD   E,(IX+EN_VAL0)
.CITAIL:

; Indexed CB byte order is prefix, CB, displacement, opcode.
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,$CB
    LD   (EN_SCRAT+1),A
    LD   A,E
    LD   (EN_SCRAT+2),A
    LD   A,B
    JP   .SS3E4
.ALU:

; The byte family ordinal is already the hardware operation field. One-operand
; records use register/memory/immediate equations; two-operand records are the
; separate 16-bit ADD/ADC/SBC forms.

    LD   A,(IX+EN_MNEM)
    SUB  AT_MADD
    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.ALU16
    LD   A,(IX+EN_OP0)
    CP   EN_IMM8
    JR   Z,.AIMMEDIA
    CALL EN_IHIND
    JR   C,.ALUHALF
    LD   A,(IX+EN_OP0)
    CALL EN_IINDE
    JR   C,.AINDEXED
    LD   A,(IX+EN_OP0)
    AND  7
    ADD  A,B
    ADD  A,$80
    JP   .SE1
.AIMMEDIA:

; ALU A,n = C6 | operation<<3 followed by the immediate byte.

    LD   A,B
    ADD  A,$C6
    JP   .SS0V0E2
.ALUHALF:

; IXH/IXL/IYH/IYL reuse H/L fields behind DD/FD.

    LD   A,(IX+EN_OP0)
    CALL EN_SPPAF
    AND  7
    ADD  A,B
    ADD  A,$80
    JP   .SS1E2
.AINDEXED:

; ALU A,(IX/IY+d) reuses the (HL) field 6 and inserts displacement.

    CALL EN_SPPAF
    LD   A,B
    ADD  A,$86
    JP   .SS1V0E3
.ALU16:

; ADC/SBC HL,rr use ED 4A/42 | rr<<4.

    LD   A,(IX+EN_MNEM)
    CP   AT_MADD
    JR   Z,.ADD16
    LD   B,$42
    CP   AT_MSBC
    JR   Z,.AS1READY
    LD   B,$4A
.AS1READY:
    LD   A,(IX+EN_OP1)
    AND  3
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,B
    LD   B,A
    JP   .SEBE2
.ADD16:

; ADD HL,rr is 09 | rr<<4. IX/IY use a prefix and map a self operand to the HL
; field while BC, DE and SP retain their ordinary pair fields.

    LD   A,(IX+EN_OP1)
    CP   EN_IX
    JR   Z,.A1SELF
    CP   EN_IY
    JR   Z,.A1SELF
    AND  3
    JR   .A1SREADY
.A1SELF:
    LD   A,2
.A1SREADY:
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,A
    ADD  A,$09
    LD   B,A
    LD   A,(IX+EN_OP0)
    CP   EN_HL
    LD   A,B
    JP   Z,.SE1
    LD   A,(IX+EN_OP0)
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,B
    JR   .SS1E2
.JP:

; Absolute JP is C3 nn; JP (HL) is E9 and IX/IY add their prefix.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.JCONDITI
    LD   A,(IX+EN_OP0)
    CP   EN_MEMHL
    JR   Z,.JPHL
    CP   EN_MEMIX
    JR   Z,.JPINDEX
    CP   EN_MEMIY
    JR   Z,.JPINDEX
    LD   A,$C3
    JP   .SAV0E3
.JCONDITI:

; JP cc,nn = C2 | cc<<3 followed by operand one's word.

    LD   B,$C2
    CALL EN_COPCO
    JP   .SAV1E3
.JPHL:
    LD   A,$E9
    JR   .SE1
.JPINDEX:
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    LD   A,$E9
    JR   .SS1E2
.CALL:

; CALL nn is CD nn; CALL cc,nn = C4 | cc<<3.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.CCONDITI
    LD   A,$CD
    JP   .SAV0E3
.CCONDITI:
    LD   B,$C4
    CALL EN_COPCO
    LD   (EN_SCRAT+0),A
    JR   AT_CV1TS
.JR:

; JR e is 18 e; JR cc,e = 20 | cc<<3 for the four accepted conditions.

    LD   A,(IX+EN_OP1)
    CP   EN_NONE
    JR   NZ,.JCONDIT1
    LD   A,$18
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_VAL0)
    JR   .SS1E2
.JCONDIT1:
    LD   B,$20
    CALL EN_COPCO
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_VAL1)
    JR   .SS1E2
.DJNZ:

; DJNZ is 10 followed by the parser-computed displacement.

    LD   A,$10
    LD   (EN_SCRAT+0),A
    LD   A,(IX+EN_VAL0)
.SS1E2:
    LD   (EN_SCRAT+1),A
    JR   EN_D2
.EDTABLE:

; Encoder family table selected by AT_DMNEM.

    DW .COPCODE,.RET,.EX
    DW .IM,.RST,.INCDEC
    DW .STACK,.LD,.IN
    DW .OUT,.BIT,.ROTATE
    DW .ALU,.JP,.CALL
    DW .JR,.DJNZ
.SE1:

; Common successful length returns. Carry is clear and A is the encoded length.

    LD   (EN_SCRAT+0),A

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length one.

EN_D1:
    XOR  A
    INC  A
    RET

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length two.

EN_D2:
    LD   A,2
    OR   A
    RET

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length three.

EN_D3:
    LD   A,3
    OR   A
    RET

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length four.

EN_D4:
    LD   A,4
    OR   A
    RET

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after one opcode byte.

AT_CV0TS:
    LD   L,(IX+EN_VAL0)
    LD   H,(IX+EN_VAL0+1)
    LD   (EN_SCRAT+1),HL
    JR   EN_D3

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after a prefix/opcode pair.

AT_CV0T1:
    LD   L,(IX+EN_VAL0)
    LD   H,(IX+EN_VAL0+1)
    LD   (EN_SCRAT+2),HL
    JR   EN_D4

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after one opcode byte.

AT_CV1TS:
    LD   L,(IX+EN_VAL1)
    LD   H,(IX+EN_VAL1+1)
    LD   (EN_SCRAT+1),HL
    JR   EN_D3

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after a prefix/opcode pair.

AT_CV1T1:
    LD   L,(IX+EN_VAL1)
    LD   H,(IX+EN_VAL1+1)
    LD   (EN_SCRAT+2),HL
    JR   EN_D4

;@ROUTINE IN A
; Store the prefix chosen from operand class A while preserving A for field math.

EN_SPPAF:
    PUSH AF
;@EXPECTOUT A
    CALL EN_PFOP
    LD   (EN_SCRAT+0),A
    POP  AF
    RET

;@ROUTINE IN A OUT A CLOBBERS F
; Map IX-family classes and even indexed-memory classes to DD; IY-family classes
; and odd indexed-memory classes to FD. Validation guarantees A is prefixable.

EN_PFOP:
    CP   EN_IXH
    JR   C,.PORDINAR
    CP   EN_IXL+1
    JR   C,.PREFIXIX
    CP   EN_IYH
    JR   C,.PORDINAR
    CP   EN_IYL+1
    JR   C,.PREFIXIY
.PORDINAR:
    AND  1
    JR   NZ,.PREFIXIY
.PREFIXIX:
    LD   A,$DD
    RET
.PREFIXIY:
    LD   A,$FD
    RET
EN_RECEN:
EN_CODEE:
EN_IBEG:
EN_CTBEG:

; Irregular core opcodes. The first thirteen are direct one-byte instructions;
; the remaining entries are suffixes emitted after ED.

EN_COPC1:
    DB $00,$F3,$FB,$37,$3F,$2F,$27,$D9,$76,$07,$0F,$17,$1F
    DB $44,$67,$6F,$A0,$B0,$A8,$B8,$A1,$B1,$A9,$B9,$A2
    DB $B2,$AA,$BA,$A3,$B3,$AB,$BB,$4D,$45
EN_IOPCO: DB $46,$56,$5E
EN_CTEND:
EN_CNT EQU 69

; Compact mnemonic table in ordinal order. Each three-byte entry stores the
; first packed RADIX-40 word and the significant high byte of the second word.

EN_TABLE:
    DW  $59E8
    DB  $00
    DW  $1A68
    DB  $00
    DW  $20A8
    DB  $00
    DW  $773E
    DB  $00
    DW  $133E
    DB  $00
    DW  $154C
    DB  $00
    DW  $1929
    DB  $00
    DW  $2318
    DB  $00
    DW  $3234
    DB  $7D
    DW  $7263
    DB  $06
    DW  $7353
    DB  $06
    DW  $7261
    DB  $00
    DW  $7351
    DB  $00
    DW  $584F
    DB  $00
    DW  $7354
    DB  $00
    DW  $7264
    DB  $00
    DW  $4BA9
    DB  $00
    DW  $4BA9
    DB  $70
    DW  $4BA4
    DB  $00
    DW  $4BA4
    DB  $70
    DW  $1549
    DB  $00
    DW  $1549
    DB  $70
    DW  $1544
    DB  $00
    DW  $1544
    DB  $70
    DW  $3A79
    DB  $00
    DW  $3A79
    DB  $70
    DW  $3A74
    DB  $00
    DW  $3A74
    DB  $70
    DW  $611C
    DB  $38
    DW  $60E9
    DB  $70
    DW  $611C
    DB  $19
    DW  $60E4
    DB  $70
    DW  $715C
    DB  $38
    DW  $715C
    DB  $57
    DW  $715C
    DB  $00
    DW  $2300
    DB  $00
    DW  $3A48
    DB  $00
    DW  $738C
    DB  $00
    DW  $3A73
    DB  $00
    DW  $19CB
    DB  $00
    DW  $675B
    DB  $32
    DW  $6668
    DB  $00
    DW  $4BA0
    DB  $00
    DW  $3A70
    DB  $00
    DW  $611C
    DB  $00
    DW  $0DFC
    DB  $00
    DW  $715B
    DB  $00
    DW  $779C
    DB  $00
    DW  $7263
    DB  $00
    DW  $7353
    DB  $00
    DW  $7260
    DB  $00
    DW  $7350
    DB  $00
    DW  $78A1
    DB  $00
    DW  $7991
    DB  $00
    DW  $78AC
    DB  $00
    DW  $78B3
    DB  $00
    DW  $799C
    DB  $00
    DW  $06E4
    DB  $00
    DW  $06E3
    DB  $00
    DW  $7A0A
    DB  $00
    DW  $7713
    DB  $00
    DW  $0874
    DB  $00
    DW  $986A
    DB  $00
    DW  $6090
    DB  $00
    DW  $1540
    DB  $00
    DW  $4100
    DB  $00
    DW  $12F4
    DB  $4B
    DW  $4150
    DB  $00
    DW  $1A9E
    DB  $A2
EN_TEND:
EN_IEND:
EN_COREE:
EN_WBEG:

; Shared private commit area: six bytes for packed names, first four for opcodes.

EN_SCRAT: DS 6
EN_WEND:
