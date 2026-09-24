;==============================================================================
;  Patch-field locator
;==============================================================================
;
;  Locate the byte field associated with one operand in a form that the encoder
;  has already validated. The result identifies the field offset and whether
;  resolution writes a byte, word, relative displacement, index displacement,
;  truncated byte, low byte or high byte.
;
;  Principal entry:
;    PT_LOCAT  map an operand index to its encoded field and patch kind

PT_CBEG:
PT_KINDB EQU 1
PT_KINDW EQU 2
PT_KRELA EQU 3
PT_KDISP EQU 4
PT_KTB EQU 5
PT_KLB EQU 6
PT_KHB EQU 7
;@ROUTINE IN IX,A OUT A,B,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,DE,ZERO
PT_LOCAT:
CP   3
JR   NC,.INVALID
LD   E,A
LD   D,0
PUSH DE
CALL EN_LEN
POP  DE
JR   C,.INVALID
LD   B,A
LD   HL,EN_OP0
ADD  HL,DE
PUSH IX
POP  DE
ADD  HL,DE
LD   A,(HL)
SUB  EN_IIX
CP   7
JR   NC,.INVALID
LD   E,A
LD   D,0
LD   HL,PT_OKIND
ADD  HL,DE
LD   A,(HL)
OR   A
JR   Z,.INVALID
CP   PT_KDISP
JR   Z,.DISPLACE
DEC  B
CP   PT_KINDW
JR   NZ,.READY
DEC  B
.READY:
OR   A
RET
.INVALID:
XOR  A
SCF
RET
.DISPLACE:
LD   B,2
OR   A
RET
PT_OKIND:
DB PT_KDISP,PT_KDISP
DB PT_KINDW,PT_KINDB,PT_KINDW
DB 0,PT_KRELA
PT_CEND:
