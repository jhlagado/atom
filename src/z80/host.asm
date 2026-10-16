;=============================================================================
;  Fail-closed host-service defaults
;=============================================================================
;
;  The core reads source through tkOpen and tkRead, binary files through
;  tkBin and tkBinRd, and writes output through six service entries. A platform
;  image omits this module and supplies those services at the same labels. The standalone version reads source from memory, and each output
;  entry fails closed through one failure tail.
;
;  Memory source: before drAsm, the caller points hsSrcTab at one begin/end
;  word pair per part, stores the part count in hsSrcCnt and clears hsSrcIdx.
;  tkOpen supplies those parts in order from offset zero.
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

;@ROUTINE OUT A,CARRY,DE,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Supply the next memory part from offset zero on line one, or carry with A=0 when none
; remains. A range whose end is below its begin fails with A=1.

tkOpen: ; Open the next memory-backed source part.
    LD   A,(hsSrcIdx)                   ; Select the next part.
    LD   HL,hsSrcCnt                    ; Compare with the number of parts.
    CP   (HL)                           ; Is every part supplied?
    JR   NC,.none                       ; Yes: report that none remains.
    LD   L,A                            ; Index its begin/end pair.
    LD   H,0                            ; Widen the ordinal.
    ADD  HL,HL                          ; Two bytes per word.
    ADD  HL,HL                          ; Two words per part.
    LD   DE,(hsSrcTab)                  ; Address the table.
    ADD  HL,DE                          ; Address this part's pair.
    LD   E,(HL)                         ; Read the begin's low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the begin.
    LD   (hsSrcBeg),DE                  ; Keep it as the part's base.
    INC  HL                             ; Advance to the end's low byte.
    LD   A,(HL)                         ; Read it.
    INC  HL                             ; Advance to the end's high byte.
    LD   H,(HL)                         ; Read it.
    LD   L,A                            ; Complete the end.
    OR   A                              ; Clear carry before end - begin.
    SBC  HL,DE                          ; Measure the part.
    JR   C,.bad                         ; The range is reversed.
    LD   (hsSrcLen),HL                  ; Keep the part's length.
    LD   HL,hsSrcIdx                    ; Address the part counter.
    LD   A,(HL)                         ; Return this part's ordinal.
    INC  (HL)                           ; Select the following part next time.
    LD   HL,0                           ; Every memory part starts at offset zero.
    LD   DE,1                           ; It starts on line one.
    OR   A                              ; Clear carry.
    RET                                 ; Return the part.
.none: ; Report that every part has been supplied.
    XOR  A                              ; A=0 means none remains.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; Assembly can finish.
.bad: ; Report a reversed source range.
    LD   A,1                            ; A nonzero status is a failure.
    SCF                                 ; Carry means no part was opened.
    RET                                 ; The driver aborts the build.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Memory-backed source: return the byte at logical offset HL of the open part,
; or carry with A=0 at its end.

tkRead: ; Read one byte from the memory-backed source interval.
    LD   DE,(hsSrcLen)                  ; Load the part's length.
    OR   A                              ; Clear carry before offset - length.
    SBC  HL,DE                          ; Is the offset inside the part?
    JR   NC,.end                        ; No: the part has ended.
    ADD  HL,DE                          ; Restore the offset.
    LD   DE,(hsSrcBeg)                  ; Load the part's memory base.
    ADD  HL,DE                          ; Translate offset to memory address.
    LD   A,(HL)                         ; Fetch the immutable source byte.
    OR   A                              ; Clear carry and classify zero.
    RET                                 ; Return the byte.
.end: ; Report the end of the part.
    XOR  A                              ; A=0 with carry means no byte remains.
    SCF                                 ; Carry marks the end of the part.
    RET                                 ; Leave the cursor where it is.

;@ROUTINE IN B,HL OUT A,CARRY,HL CLOBBERS BC,DE,HALFCARRY,ZERO,SIGN,PARITY
; Open the binary file named by the B bytes at HL for INCBIN. Return its
; length in HL with A=0, or A nonzero when the length cannot be told. Fail
; closed when unbound.

tkBin: ; Unbound INCBIN open entry.
    NOP                                 ; INCBIN open hook. fall through if unbound.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,HALFCARRY,ZERO,SIGN,PARITY
; Return the next byte of the open binary file. Fail closed when unbound.

tkBinRd: ; Unbound INCBIN read entry.
    NOP                                 ; INCBIN read hook. fall through if unbound.

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
hsRamLo: ; Beginning of the memory source's state.

; The caller's part table, and the part tkOpen supplies next.

hsSrcTab:   DW      0                   ; Address of the begin/end word pairs.
hsSrcCnt:   DB      0                   ; Number of parts in the table.
hsSrcIdx:   DB      0                   ; Ordinal of the next part to open.

; The open part's memory base and length.

hsSrcBeg:   DW      0                   ; Address of the open part's first byte.
hsSrcLen:   DW      0                   ; Length of the open part.
hsRamHi: ; Exclusive end of the memory source's state.
hsResEnd: ; Exclusive end of resident host module.
