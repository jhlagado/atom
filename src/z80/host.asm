;=============================================================================
;  Fail-closed host-service defaults
;=============================================================================
;
;  The core reads source through tkRead and writes output through six
;  service entries. A platform image omits this module and supplies tkRead
;  and the BEGIN, IMAGE, PATCH, COMMIT and ABORT services at the same labels.
;  The standalone version reads source from memory, and each output entry
;  fails closed through one failure tail.
;
;  BEGIN receives IX = build descriptor. IMAGE/PATCH byte receive A = value,
;  C = output class and HL = address. PATCH word receives HL = value, DE =
;  address and C = class. COMMIT receives IX, final cursor in HL, remaining
;  capacity in DE, high-water low word in BC and endpoint flags in A.
;  Bit 0 marks cursor $10000 and bit 1 marks high water $10000.
;  ABORT takes no inputs.
;  BEGIN may clobber BC, DE and HL, and COMMIT also IX and IY. The core
;  keeps nothing in them across these calls.
;
;  The separate NOPs preserve distinct hook addresses for host interception.
;  Without interception, hsFail returns A=$FF with carry set.

hsBeg: ; Beginning of replaceable host services.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Memory-backed source: translate the logical offset to an absolute address.

tkRead: ; Read one byte from the memory-backed source interval.
    LD   DE,(tkSrcBeg)                  ; Load the checked-core memory range base.
    ADD  HL,DE                          ; Translate offset to memory address.
    LD   A,(HL)                         ; Fetch the immutable source byte.
    OR   A                              ; Clear carry and classify zero.
    RET                                 ; Return without provider state.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable BEGIN service entry and fail closed when unbound.

hsBegin: ; Unbound BEGIN entry.
    NOP                                 ; BEGIN hook. fall through if unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the IMAGE-byte entry. fail closed when unbound.

hsByte: ; Unbound IMAGE-byte entry.
    NOP                                 ; IMAGE-byte hook. fall through unbound.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-byte entry. fail closed when unbound.

hsPatchB: ; Unbound byte-PATCH entry.
    NOP                                 ; PATCH-byte hook. fall through unbound.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the PATCH-word entry. fail closed when unbound.

hsPatchW: ; Unbound word-PATCH entry.
    NOP                                 ; PATCH-word hook. fall through unbound.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable COMMIT service entry and fail closed when unbound.

hsCommit: ; Unbound COMMIT entry.
    NOP                                 ; COMMIT hook. fall through if unbound.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Reserve the replaceable ABORT entry and return the common unbound failure.

hsAbort: ; Unbound ABORT entry.
hsFail: ; Shared failure return for every unbound hook.

; One fail-closed tail serves every unbound operation.

    SCF                                 ; Mark the host operation as failed.
    SBC  A,A                            ; Convert the set carry into status $FF.
    RET                                 ; Return failure to the platform-neutral core.
hsEnd: ; Exclusive end of host hook code.
hsResEnd: ; Exclusive end of resident host module.
