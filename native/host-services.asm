;==============================================================================
;  Fail-closed host-service defaults
;==============================================================================
;
;  Define the output service entry points used by the checked standalone core.
;  Every entry reports failure. A platform build omits this complete module and
;  supplies implementations for BEGIN, IMAGE byte, PATCH byte, PATCH word,
;  COMMIT and ABORT.

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
SCF
SBC  A,A
RET
HS_SCEND:
HS_REND:
