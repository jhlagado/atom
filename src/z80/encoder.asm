;==============================================================================
;  Instruction encoder and RADIX-40 names
;==============================================================================
;
;  Convert one parser record into the exact one-to-four-byte Z80 instruction.
;  The encoder is deliberately independent of source syntax, symbols and output
;  services: it sees only a mnemonic ordinal, three operand classes and three
;  little-endian operand values.
;
;  Validation and encoding share one mnemonic-family dispatcher. The validator
;  checks record shape and returns its encoded length without reading values;
;  the parser uses that property while unresolved operands still contain zero
;  placeholders. EN_NAME validates again, encodes into private scratch and only
;  then copies the successful bytes to the caller's destination.
;
;  Most instruction families are equations over register, condition or bit
;  fields. Opcode/name lookup tables are retained for the genuinely irregular
;  core opcodes, IM modes and mnemonic names; two small address tables dispatch
;  the shared families. DD and FD forms are derived from the ordinary HL encoding
;  by adding a prefix and, for indexed memory, a displacement.
;
;  Principal entries:
;    EN_R40PK  pack one case-insensitive name into three RADIX-40 words
;    EN_RECOG  recognise mnemonic text and return its ordinal
;    EN_LEN    validate a form and return its encoded length
;    EN_VFORM  validate mnemonic and operand classes
;    EN_NAME   validate and encode into the caller's four-byte destination
;
;  EN_SCRAT is six bytes because the RADIX-40 packer needs three words. Encoding
;  uses at most its first four bytes. A failed pack or encode leaves the caller's
;  destination unchanged.

ORG 0
; Ten-byte parsed-instruction record shared with the parser and output layer.
EN_MNEM EQU 0
EN_OP0 EQU 1
EN_OP1 EQU 2
EN_OP2 EQU 3
EN_VAL0 EQU 4
EN_VAL1 EQU 6
EN_VAL2 EQU 8
; Operand-class ordinals. The register families deliberately mirror the Z80
; bit fields where possible: B..A are 0..7 and BC..SP are 8..11.
EN_B EQU 0
EN_C EQU 1
EN_D EQU 2
EN_E EQU 3
EN_H EQU 4
EN_L EQU 5
EN_MEMHL EQU 6
EN_A EQU 7
EN_BC EQU 8
EN_DE EQU 9
EN_HL EQU 10
EN_SP EQU 11
EN_AF EQU 15
EN_IX EQU 16
EN_IY EQU 17
EN_IXH EQU 20
EN_IXL EQU 21
EN_IYH EQU 28
EN_IYL EQU 29
EN_I EQU 32
EN_R EQU 33
EN_MEMBC EQU 40
EN_MEMDE EQU 41
EN_IIX EQU 48
EN_IIY EQU 49
EN_MABS EQU 50
EN_IMM8 EQU 51
EN_IMM16 EQU 52
EN_PORTC EQU 53
EN_REL8 EQU 54
EN_ZERO EQU 55
EN_MEMIX EQU 56
EN_MEMIY EQU 57
EN_MEMSP EQU 58
EN_APRIM EQU 59
EN_NZ EQU 64
EN_Z EQU 65
EN_NC EQU 66
EN_CC EQU 67
EN_PO EQU 68
EN_PE EQU 69
EN_P EQU 70
EN_M EQU 71
EN_BIT0 EQU 72
EN_BIT7 EQU 79
EN_RST0 EQU 80
EN_RST56 EQU 87
EN_IM0 EQU 88
EN_IM2 EQU 90
EN_NONE EQU 255
; Mnemonic ordinals are generated in compact-table order. Ordinals 1..34 are
; singleton core instructions; 35..69 form the dispatched instruction families.
AT_MNOP EQU 1
AT_MRET EQU 35
AT_MEX EQU 36
AT_MIM EQU 37
AT_MRST EQU 38
AT_MINC EQU 39
AT_MDEC EQU 40
AT_MPUSH EQU 41
AT_MPOP EQU 42
AT_MLD EQU 43
AT_MIN EQU 44
AT_MOUT EQU 45
AT_MBIT EQU 46
AT_MRES EQU 47
AT_MSET EQU 48
AT_MRLC EQU 49
AT_MSRL EQU 57
AT_MADD EQU 58
AT_MADC EQU 59
AT_MSUB EQU 60
AT_MSBC EQU 61
AT_MAND EQU 62
AT_MXOR EQU 63
AT_MOR EQU 64
AT_MCP EQU 65
AT_MJP EQU 66
AT_MCALL EQU 67
AT_MJR EQU 68
AT_MDJNZ EQU 69
AT_MLAST EQU AT_MDJNZ
EN_COREB:
EN_CODEB:
EN_R4CBE:
; Pack B source characters at HL into the caller's six bytes at DE. Names are
; one to eight characters, ASCII case-insensitive, and are committed only after
; every character is proved representable.
;@ROUTINE IN B,HL,DE OUT DE,CARRY MAYBE-OUT ZERO CLOBBERS A,BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
EN_R40PK:
LD   A,B
OR   A
JR   Z,.PINVALID
CP   9
JR   NC,.PINVALID
PUSH HL
PUSH BC
.PVLOOP:
LD   A,(HL)
CALL EN_R40CH
JR   C,.PVFAILED
INC  HL
DJNZ .PVLOOP
POP  BC
POP  HL
PUSH DE
LD   IX,EN_SCRAT
LD   A,B
; Encode characters 0..2 and 3..5 as complete RADIX-40 words. The final call
; stores characters 6..7 directly as c6*40+c7 in the third word.
CALL EN_PTHRE
CALL EN_PTHRE
LD   B,A
LD   C,2
;@EXPECTOUT DE
CALL EN_PGROU
LD   (IX+0),E
LD   (IX+1),D
POP  DE
LD   HL,EN_SCRAT
LD   BC,6
LDIR
OR   A
RET
.PVFAILED:
POP  BC
POP  HL
.PINVALID:
XOR  A
SCF
RET
;@ROUTINE IN A,HL,IX OUT A,HL,IX CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY,CARRY
EN_PTHRE:
; Consume up to three of the remaining A characters, write one word at IX and
; return the remaining count in A.
CP   3
JR   C,.PTSHORT
LD   B,3
SUB  3
JR   .PTREADY
.PTSHORT:
LD   B,A
XOR  A
.PTREADY:
PUSH AF
LD   C,3
;@EXPECTOUT DE
CALL EN_PGROU
LD   (IX+0),E
LD   (IX+1),D
INC  IX
INC  IX
POP  AF
RET
;@ROUTINE IN BC,HL OUT DE,HL,CARRY MAYBE-OUT ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY,BC,ZERO
EN_PGROU:
; Accumulate exactly C base-40 digits. B real characters are followed by zero
; padding, so each group has one canonical packed representation.
LD   DE,0
.PGLOOP:
LD   A,B
OR   A
JR   Z,.PGPADDIN
LD   A,(HL)
INC  HL
DEC  B
CALL EN_R40CH
JR   .PGAPPEND
.PGPADDIN:
XOR  A
.PGAPPEND:
CALL AT_MA40
DEC  C
JR   NZ,.PGLOOP
OR   A
RET
;@ROUTINE IN DE,A OUT DE CLOBBERS A,F
AT_MA40:
; DE = DE*40 + A. Five doublings and one add are smaller than a general multiply.
PUSH HL
LD   H,D
LD   L,E
ADD  HL,HL
ADD  HL,HL
ADD  HL,DE
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
ADD  A,L
LD   L,A
JR   NC,.MA4NCARR
INC  H
.MA4NCARR:
EX   DE,HL
POP  HL
RET
;@ROUTINE IN A OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
EN_R40CH:
; Map A-Z/a-z to 1..26, digits to 27..36 and underscore to 37. Codes 38 and 39
; remain unused; zero is reserved for padding.
CP   $61
JR   C,.R4UPPER
CP   $7A+1
JR   NC,.R4UPPER
SUB  $20
.R4UPPER:
CP   $41
JR   C,.R4DIGIT
CP   $5A+1
JR   NC,.R4DIGIT
SUB  $41-1
OR   A
RET
.R4DIGIT:
CP   $30
JR   C,.R4UNDERS
CP   $39+1
JR   NC,.R4UNDERS
SUB  $30-27
OR   A
RET
.R4UNDERS:
CP   $5F
JR   NZ,.R4BAD
LD   A,37
OR   A
RET
.R4BAD:
XOR  A
SCF
RET
EN_R4CEN:
EN_RCBEG:
; Recognise a one-to-four-character mnemonic. The compact table stores the first
; packed word and the significant high byte of the padded second word. Its table
; position plus one is the public mnemonic ordinal.
;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
EN_RECOG:
LD   A,B
CP   5
JR   NC,.RNFOUND
LD   DE,EN_SCRAT
CALL EN_R40PK
RET  C
LD   IX,EN_TABLE
LD   B,EN_CNT
LD   C,1
.RLOOP:
LD   A,(EN_SCRAT+0)
CP   (IX+0)
JR   NZ,.RNEXT
LD   A,(EN_SCRAT+1)
CP   (IX+1)
JR   NZ,.RNEXT
LD   A,(EN_SCRAT+3)
CP   (IX+2)
JR   NZ,.RNEXT
LD   A,C
OR   A
RET
.RNEXT:
INC  IX
INC  IX
INC  IX
INC  C
DJNZ .RLOOP
.RNFOUND:
XOR  A
SCF
RET
EN_RCEND:
EN_VCBEG:
; Dispatch mnemonic A through a family table based at DE. Core ordinals 1..34
; share family zero. Later dense ordinal ranges are mapped by EN_CENDS to the
; RET, EX, IM, RST, INC/DEC, stack, LD, I/O, bit, rotate, ALU and branch families.
;@ROUTINE IN A,DE CLOBBERS B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
AT_DMNEM:
LD   B,A
CP   AT_MRET
JR   NC,.DMAPPED
XOR  A
JR   .DREADY
.DMAPPED:
SUB  AT_MRET
PUSH BC
LD   HL,EN_CENDS
LD   C,1
.DCLOOP:
CP   (HL)
JR   C,.DCREADY
INC  HL
INC  C
JR   .DCLOOP
.DCREADY:
LD   A,C
POP  BC
.DREADY:
ADD  A,A
LD   L,A
LD   H,0
ADD  HL,DE
LD   E,(HL)
INC  HL
LD   D,(HL)
EX   DE,HL
LD   A,B
JP   (HL)
EN_CENDS:
; Exclusive cumulative family-end offsets from AT_MRET.
DB 1,2,3,4,6,8,9,10,11,14,23,31,32,33,34,35
; Validate only mnemonic and operand classes. No EN_VAL byte is read here, which
; lets unresolved records obtain an exact field layout and instruction length.
;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
EN_LEN:
EN_VFORM:
LD   A,(IX+EN_MNEM)
OR   A
JP   Z,AT_INVAL
CP   AT_MLAST+1
JP   NC,AT_INVAL
LD   DE,.VDTABLE
JR   AT_DMNEM
.VCORE:
; The first thirteen core opcodes are one byte; the remaining core group carries
; an ED prefix. All core instructions reject operands.
CALL AT_RNOPE
RET  C
LD   A,(IX+EN_MNEM)
CP   14
SBC  A,A
ADD  A,2
OR   A
RET
.VRET:
; RET is either operand-free or takes one of the eight condition classes.
LD   A,(IX+EN_OP0)
CP   EN_NONE
JR   Z,.VL1NOPER
CALL EN_ICOND
JP   NC,AT_INVAL
CALL AT_ROOP
RET  C
XOR  A
INC  A
RET
.VL1NOPER:
CALL AT_RNOPE
RET  C
XOR  A
INC  A
RET
.VEX:
; EX admits only AF,AF', DE,HL and (SP),HL/IX/IY.
CALL AT_RTOPE
RET  C
LD   A,(IX+EN_OP0)
CP   EN_AF
JR   Z,.VEAF
CP   EN_DE
JR   Z,.VEDE
CP   EN_MEMSP
JP   NZ,AT_INVAL
JP   .VLSP
.VEAF:
LD   A,(IX+EN_OP1)
CP   EN_APRIM
.VZL1:
JP   Z,EN_D1
JP   AT_INVAL
.VEDE:
LD   A,(IX+EN_OP1)
CP   EN_HL
JR   .VZL1
.VIM:
; IM mode is encoded in its enumerated operand class, not in the value word.
CALL AT_ROOP
RET  C
LD   A,(IX+EN_OP0)
CP   EN_IM0
JP   C,AT_INVAL
CP   EN_IM2+1
JP   NC,AT_INVAL
JP   EN_D2
.VRST:
CALL AT_ROOP
RET  C
LD   A,(IX+EN_OP0)
CP   EN_RST0
JP   C,AT_INVAL
CP   EN_RST56+1
JP   NC,AT_INVAL
JP   EN_D1
.VIDEC:
; INC/DEC cover r, rr, IX/IY, index halves, (HL), and indexed memory. Prefix and
; displacement determine the returned length.
CALL AT_ROOP
RET  C
LD   A,(IX+EN_OP0)
CALL EN_IR8
JP   C,EN_D1
LD   A,(IX+EN_OP0)
CALL EN_IR16
JP   C,EN_D1
LD   A,(IX+EN_OP0)
CP   EN_IX
JP   Z,EN_D2
CP   EN_IY
JP   Z,EN_D2
CALL EN_IHIND
JP   C,EN_D2
LD   A,(IX+EN_OP0)
CP   EN_MEMHL
JP   Z,EN_D1
CALL EN_IINDE
.VCL3:
JP   C,EN_D3
JP   AT_INVAL
.VSTACK:
; PUSH/POP accept the four ordinary stack pairs plus IX and IY.
CALL AT_ROOP
RET  C
LD   A,(IX+EN_OP0)
CP   EN_BC
JP   Z,EN_D1
CP   EN_DE
JP   Z,EN_D1
CP   EN_HL
JP   Z,EN_D1
CP   EN_AF
JP   Z,EN_D1
.VIL2:
CP   EN_IX
JP   Z,EN_D2
CP   EN_IY
.VZL2:
JP   Z,EN_D2
JP   AT_INVAL
EN_LVBEG EQU $
.VLD:
; LD is the broadest family. Dispatch first by destination class, then prove the
; exact source pairing and its length. Index-half rules are intentionally strict:
; two half registers must belong to the same IX or IY family, and ordinary H/L
; cannot mix with an index half. Indexed memory uses the real H/L register field.
CALL AT_RTOPE
RET  C
LD   A,(IX+EN_OP0)
CALL EN_IR8
JR   C,.VLR8
LD   A,(IX+EN_OP0)
CALL EN_IHIND
JP   C,.VLHALF
LD   A,(IX+EN_OP0)
CALL EN_IR16
JP   C,.VLR16
LD   A,(IX+EN_OP0)
CP   EN_IX
JP   Z,.VLI16
CP   EN_IY
JP   Z,.VLI16
CP   EN_I
JP   Z,.VLSPECIA
CP   EN_R
JP   Z,.VLSPECIA
CP   EN_MABS
JP   Z,.VLMABS
CP   EN_MEMBC
JP   Z,.VLMPAIR
CP   EN_MEMDE
JP   Z,.VLMPAIR
CP   EN_MEMHL
JP   Z,.VLMHL
CALL EN_IINDE
JP   C,.VLINDEXE
JP   AT_INVAL
.VLR8:
; Ordinary eight-bit destination: r, n, (HL), absolute/BC/DE memory when A, the
; special I/R transfers when A, indexed memory, or an index-half source.
LD   A,(IX+EN_OP1)
CALL EN_IR8
JP   C,EN_D1
LD   A,(IX+EN_OP1)
CP   EN_IMM8
JP   Z,EN_D2
CP   EN_MEMHL
JP   Z,EN_D1
CP   EN_MABS
JR   Z,.VLR8ABSO
CP   EN_MEMBC
JR   Z,.VLR8ACCU
CP   EN_MEMDE
JR   Z,.VLR8ACCU
CP   EN_I
JR   Z,.VLR8A2
CP   EN_R
JR   Z,.VLR8A2
CALL EN_IINDE
JP   C,EN_D3
LD   A,(IX+EN_OP1)
CALL EN_IHIND
JP   NC,AT_INVAL
LD   A,(IX+EN_OP0)
.VLNRHALF:
CP   EN_H
JP   Z,AT_INVAL
CP   EN_L
JP   Z,AT_INVAL
JP   EN_D2
.VLR8ABSO:
.VLR8ACCU:
LD   A,(IX+EN_OP0)
CP   EN_A
JP   NZ,AT_INVAL
LD   A,(IX+EN_OP1)
CP   EN_MABS
JP   Z,EN_D3
JP   EN_D1
.VLR8A2:
LD   A,(IX+EN_OP0)
CP   EN_A
.VNL2:
JP   NZ,AT_INVAL
JP   EN_D2
.VLHALF:
; Half-register forms require an index prefix and reject H/L collisions. XOR bit
; 3 below proves that source and destination belong to the same IX/IY family.
LD   A,(IX+EN_OP1)
CALL EN_IHIND
JR   C,.VLHFAMIL
LD   A,(IX+EN_OP1)
CALL EN_IR8
JP   NC,AT_INVAL
JR   .VLNRHALF
.VLHFAMIL:
LD   A,(IX+EN_OP0)
LD   B,A
LD   A,(IX+EN_OP1)
XOR  B
AND  $08
JR   .VNL2
.VLR16:
; Ordinary pair destinations accept immediate and absolute loads, LD SP,HL, and
; Atom's two pair-copy expansions from DE. IX/IY destinations branch separately.
LD   A,(IX+EN_OP1)
CP   EN_IMM16
JP   Z,EN_D3
CP   EN_MABS
JR   Z,.VLR1ABSO
LD   A,(IX+EN_OP0)
CP   EN_SP
JR   Z,.VLSP
CP   EN_HL
JR   Z,.VLLHL
CP   EN_BC
JR   Z,.VLLBC
JP   AT_INVAL
.VLR1ABSO:
LD   A,(IX+EN_OP0)
JR   .VLAPLEN
.VLSP:
LD   A,(IX+EN_OP1)
CP   EN_HL
JP   Z,EN_D1
JP   .VIL2
.VLLHL:
.VLLBC:
LD   A,(IX+EN_OP1)
CP   EN_DE
JP   .VZL2
.VLI16:
LD   A,(IX+EN_OP1)
CP   EN_IMM16
JP   Z,EN_D4
CP   EN_MABS
.VZL4:
JP   Z,EN_D4
JP   AT_INVAL
.VLSPECIA:
LD   A,(IX+EN_OP1)
CP   EN_A
JP   .VZL2
.VLMABS:
LD   A,(IX+EN_OP1)
CP   EN_A
JP   Z,EN_D3
CALL EN_IR16
JR   NC,.VLMAINDE
.VLAPLEN:
CP   EN_HL
JP   Z,EN_D3
JP   EN_D4
.VLMAINDE:
CP   EN_IX
JP   Z,EN_D4
CP   EN_IY
JR   .VZL4
.VLMPAIR:
LD   A,(IX+EN_OP1)
CP   EN_A
JP   .VZL1
.VLMHL:
LD   A,(IX+EN_OP1)
CALL EN_IR8
JP   C,EN_D1
CP   EN_IMM8
JP   .VZL2
.VLINDEXE:
LD   A,(IX+EN_OP1)
CALL EN_IR8
JP   C,EN_D3
CP   EN_IMM8
JR   .VZL4
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
AT_INVAL:
; All invalid forms return A=0 with carry set and publish no output.
XOR  A
SCF
RET
;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
AT_RNOPE:
; Cascading operand-count checks: no operands, at most one, or at most two.
LD   A,(IX+EN_OP0)
CP   EN_NONE
JR   NZ,AT_RBAD
;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
AT_ROOP:
LD   A,(IX+EN_OP1)
CP   EN_NONE
JR   NZ,AT_RBAD
;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
AT_RTOPE:
LD   A,(IX+EN_OP2)
CP   EN_NONE
JR   NZ,AT_RBAD
OR   A
RET
;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
AT_RBAD:
XOR  A
SCF
RET
;@ROUTINE IN A OUT CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
EN_IR8:
; Carry set means ordinary eight-bit register B..L or A; class 6 is (HL), so it
; is excluded from this predicate despite sharing the hardware field range.
CP   EN_MEMHL
RET  C
CP   EN_A
JR   Z,AT_PYES
CP   A
RET
;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
EN_IR16:
; Carry set means BC, DE, HL or SP.
CP   EN_BC
JR   C,AT_PNO
CP   EN_SP+1
RET
;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
EN_IHIND:
; Preserve A while recognising IXH/IXL/IYH/IYL through their shared bit pattern.
PUSH BC
LD   C,A
AND  $F6
CP   EN_IXH
LD   A,C
POP  BC
JR   Z,AT_PYES
JR   AT_PNO
;@ROUTINE IN A OUT CARRY,ZERO,SIGN,PARITY,HALFCARRY
EN_IINDE:
; Carry set means displacement-bearing (IX+d) or (IY+d).
CP   EN_IIX
JR   C,AT_PNO
CP   EN_IIY+1
RET
;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
EN_ICOND:
; All eight condition classes, in hardware field order.
CP   EN_NZ
JR   C,AT_PNO
CP   EN_M+1
RET
;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
EN_IRCON:
; The four condition classes implemented by JR.
CP   EN_NZ
JR   C,AT_PNO
CP   EN_CC+1
RET
;@ROUTINE IN A OUT CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
EN_IBIND:
; Enumerated bit-number classes BIT0..BIT7.
CP   EN_BIT0
JR   C,AT_PNO
CP   EN_BIT7+1
RET
;@ROUTINE IN A OUT CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
AT_PNO:
CP   A
RET
;@ROUTINE OUT CARRY CLOBBERS HALFCARRY
AT_PYES:
SCF
RET
EN_VCEND:
EN_RECBE:
; Validate and encode the record at IX, then commit its one-to-four bytes to DE.
; EN_CORE writes only EN_SCRAT; the caller destination is untouched on failure.
;@ROUTINE IN IX,DE OUT A,DE,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
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
; Encode a condition field into bits 3..5 and add the opcode-family base in B.
;@ROUTINE IN IX,B OUT A CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,CARRY
EN_COPCO:
LD   A,(IX+EN_OP0)
SUB  EN_NZ
ADD  A,A
ADD  A,A
ADD  A,A
ADD  A,B
RET
; Encode a record already proved by EN_VFORM. The mnemonic-family table mirrors
; the validator table so both paths make the same ordinal partition explicit.
;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,B,DE,HL
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
EN_D1:
XOR  A
INC  A
RET
;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
EN_D2:
LD   A,2
OR   A
RET
;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
EN_D3:
LD   A,3
OR   A
RET
;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
EN_D4:
LD   A,4
OR   A
RET
;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
AT_CV0TS:
; Copy operand zero's word after one opcode byte.
LD   L,(IX+EN_VAL0)
LD   H,(IX+EN_VAL0+1)
LD   (EN_SCRAT+1),HL
JR   EN_D3
;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
AT_CV0T1:
; Copy operand zero's word after a prefix/opcode pair.
LD   L,(IX+EN_VAL0)
LD   H,(IX+EN_VAL0+1)
LD   (EN_SCRAT+2),HL
JR   EN_D4
;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
AT_CV1TS:
; Copy operand one's word after one opcode byte.
LD   L,(IX+EN_VAL1)
LD   H,(IX+EN_VAL1+1)
LD   (EN_SCRAT+1),HL
JR   EN_D3
;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
AT_CV1T1:
; Copy operand one's word after a prefix/opcode pair.
LD   L,(IX+EN_VAL1)
LD   H,(IX+EN_VAL1+1)
LD   (EN_SCRAT+2),HL
JR   EN_D4
;@ROUTINE IN A
EN_SPPAF:
; Store the prefix chosen from operand class A while preserving A for field math.
PUSH AF
;@EXPECTOUT A
CALL EN_PFOP
LD   (EN_SCRAT+0),A
POP  AF
RET
;@ROUTINE IN A OUT A CLOBBERS F
EN_PFOP:
; Map IX-family classes and even indexed-memory classes to DD; IY-family classes
; and odd indexed-memory classes to FD. Validation guarantees A is prefixable.
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
