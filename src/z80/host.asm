;=============================================================================
;  Fail-closed host-service defaults
;=============================================================================
;
;  These six output-service entries belong to the platform-neutral core.
;  The standalone version fails closed: each entry reaches one failure tail.
;  A platform image omits this module and supplies BEGIN, IMAGE, PATCH,
;  COMMIT and ABORT implementations at the same labels.
;
;  BEGIN receives IX = build descriptor. IMAGE/PATCH byte receive A = value,
;  C = output class and HL = logical address. PATCH word receives HL = value,
;  DE = logical address and C = class. COMMIT receives IX = descriptor,
;  HL = final cursor and DE = remaining capacity. ABORT has no inputs.
;
;  The separate NOPs preserve distinct hook addresses for host interception.
;  Without interception, HS_FCLOS returns A=$FF with carry set.

HS_SCBEG:

;@ROUTINE IN IX OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable BEGIN service entry and fail closed when unbound.

HS_BEG:
    NOP                     ; BEGIN hook; fall through if unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the IMAGE-byte entry; fail closed when unbound.

HS_IB:
    NOP                     ; IMAGE-byte hook; fall through unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-byte entry; fail closed when unbound.

HS_PB:
    NOP                     ; PATCH-byte hook; fall through unbound.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-word entry; fail closed when unbound.

HS_PW:
    NOP                     ; PATCH-word hook; fall through unbound.

;@ROUTINE IN IX,HL,DE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable COMMIT service entry and fail closed when unbound.

HS_CMT:
    NOP                     ; COMMIT hook; fall through if unbound.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable ABORT entry and return the common unbound failure.

HS_ABORT:
HS_FCLOS:

; One fail-closed tail serves every unbound operation.

    SCF                     ; Mark the host operation as failed.
    SBC  A,A                ; Convert the set carry into status $FF.
    RET                     ; Return failure to the platform-neutral core.
HS_SCEND:
HS_REND:
