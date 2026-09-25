;==============================================================================
;  Patch-field locator
;==============================================================================
;
;  Locate the encoded field associated with one operand in a form the encoder has
;  already validated. The result identifies the field offset and its base patch
;  kind: byte, word, relative displacement or index displacement. Callers may
;  subsequently substitute truncate, LOW or HIGH byte transforms: statements
;  select truncation for DB, while the parser applies LOW/HIGH expressions.
;
;  Principal entry:
;    PT_LOCAT  map an operand index to its encoded field and patch kind

PT_CBEG:
; Patch kinds stored in the low three bits of a pending record. SY_DANCH may
; occupy the high bit without changing this value.
PT_KINDB EQU 1
PT_KINDW EQU 2
PT_KRELA EQU 3
PT_KDISP EQU 4
PT_KTB EQU 5
PT_KLB EQU 6
PT_KHB EQU 7
; A is operand index 0..2 and IX is the validated instruction record. Return A as
; base patch kind and B as byte offset from the instruction start.
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
; EN_LEN supplies the total byte length without reading operand values.
LD   B,A
LD   HL,EN_OP0
ADD  HL,DE
PUSH IX
POP  DE
ADD  HL,DE
LD   A,(HL)
; Patchable operand classes are the contiguous range (IX+d) through REL8. The
; table deliberately rejects PORT_C, which has no encoded value field.
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
; Ordinary byte fields end at length-1; little-endian word fields begin at
; length-2. This also locates an indexed instruction's trailing immediate.
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
; Every DD/FD indexed-memory displacement is byte two. Ordinary forms are
; prefix, opcode, displacement; indexed-CB forms are prefix, CB, displacement,
; opcode.
LD   B,2
OR   A
RET
PT_OKIND:
; EN_IIX, EN_IIY, EN_MABS, EN_IMM8, EN_IMM16, EN_PORTC, EN_REL8.
DB PT_KDISP,PT_KDISP
DB PT_KINDW,PT_KINDB,PT_KINDW
DB 0,PT_KRELA
PT_CEND:
