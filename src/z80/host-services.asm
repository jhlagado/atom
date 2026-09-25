;==============================================================================
;  Fail-closed host-service defaults
;==============================================================================
;
;  Define the six output-service entry points used by the platform-neutral Atom
;  core. This standalone implementation is deliberately unusable: every entry
;  falls through to one common failure return. A platform image omits this whole
;  module and supplies concrete BEGIN, IMAGE-byte, PATCH-byte, PATCH-word, COMMIT
;  and ABORT implementations at the same public labels.
;
;  BEGIN receives IX = build descriptor. IMAGE/PATCH byte receive A = value,
;  C = output class and HL = logical address. PATCH word receives HL = value,
;  DE = logical address and C = class. COMMIT receives IX = descriptor,
;  HL = final cursor and DE = remaining capacity. ABORT has no inputs.
;
;  The separate NOPs preserve distinct hook addresses for host interception.
;  Without interception, execution reaches HS_FCLOS and returns A=$FF, carry set.

HS_SCBEG:
;@ROUTINE IN IX OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_BEG:
NOP
;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_IB:
NOP
;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_PB:
NOP
;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_PW:
NOP
;@ROUTINE IN IX,HL,DE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_CMT:
NOP
;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
HS_ABORT:
HS_FCLOS:
; One fail-closed tail serves every unbound operation.
SCF
SBC  A,A
RET
HS_SCEND:
HS_REND:
