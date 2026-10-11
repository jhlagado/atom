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
;  C = output class and HL = address. PATCH word receives HL = value, DE =
;  address and C = class. COMMIT receives IX, final cursor in HL, remaining
;  capacity in DE, high-water low word in BC and endpoint flags in A.
;  Bit 0 marks cursor $10000 and bit 1 marks high water $10000.
;  ABORT takes no inputs.
;
;  The separate NOPs preserve distinct hook addresses for host interception.
;  Without interception, HS_FAIL returns A=$FF with carry set.

HS_CBEG: ; Beginning of replaceable output-service hooks.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable BEGIN service entry and fail closed when unbound.

HS_BEG: ; Unbound BEGIN entry.
    NOP                                 ; BEGIN hook. fall through if unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the IMAGE-byte entry. fail closed when unbound.

HS_IB: ; Unbound IMAGE-byte entry.
    NOP                                 ; IMAGE-byte hook. fall through unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-byte entry. fail closed when unbound.

HS_PB: ; Unbound byte-PATCH entry.
    NOP                                 ; PATCH-byte hook. fall through unbound.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-word entry. fail closed when unbound.

HS_PW: ; Unbound word-PATCH entry.
    NOP                                 ; PATCH-word hook. fall through unbound.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable COMMIT service entry and fail closed when unbound.

HS_CMT: ; Unbound COMMIT entry.
    NOP                                 ; COMMIT hook. fall through if unbound.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable ABORT entry and return the common unbound failure.

HS_ABORT: ; Unbound ABORT entry.
HS_FAIL: ; Shared failure return for every unbound hook.

; One fail-closed tail serves every unbound operation.

    SCF                                 ; Mark the host operation as failed.
    SBC  A,A                            ; Convert the set carry into status $FF.
    RET                                 ; Return failure to the platform-neutral core.
HS_CEND: ; Exclusive end of host hook code.
HS_REND: ; Exclusive end of resident host module.
