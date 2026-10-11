;@ROUTINE OUT A,CARRY CLOBBERS IX,DE,BC,ZERO,SIGN,PARITY,HALFCARRY,HL
; Check whether private scope may be discarded. Every private record must
; be defined and no pending record may still point into private storage. The
; second check also catches stale references to defined private names.

SY_VSCOP: ; Prove every private symbol and pending pointer permits eviction.
    LD   IX,(SY_LBEG)                   ; Start at first private record.
    LD   DE,(SY_AEND)                   ; Stop at the arena's exclusive end.
.PRIVLOOP: ; Check one private record per iteration.
    CALL AT_IXEND                       ; Reached the interval end?
    JR   Z,.PENDCHK                     ; Then inspect pending pointers.
    BIT  6,(IX+5)                       ; Is this private symbol defined?
    JR   Z,.UNDEF                       ; Keep undefined private names.
    LD   BC,SY_RECB                     ; Load the symbol-record stride.
    ADD  IX,BC                          ; Advance to the next private record.
    JR   .PRIVLOOP                      ; Continue through the current scope.
.PENDCHK: ; Validate every live pending symbol pointer.

; Walk the pending arena and inspect the private flag through each saved
; symbol pointer.

    LD   IX,(SY_PBASE)                  ; Start at the first pending record.
    LD   DE,(SY_NEXT)                   ; Stop at the pending publication cursor.
.PENDLOOP: ; Inspect one pending symbol pointer.
    CALL AT_IXEND                       ; Reached the pending scan end?
    JR   Z,.OK                          ; No private references remain.
    LD   L,(IX+0)                       ; Load the saved symbol pointer low byte.
    LD   H,(IX+1)                       ; Load its high byte.
    PUSH DE                             ; Preserve the pending scan end.
    LD   DE,5                           ; Select pointed record's flag byte.
    ADD  HL,DE                          ; Advance to its private flag.
    BIT  7,(HL)                         ; Does it point to a private name?
    POP  DE                             ; Restore the pending scan end.
    JR   NZ,.STALE                      ; Private pointer forbids eviction.
    LD   BC,SY_PENDB                    ; Load the pending-record stride.
    ADD  IX,BC                          ; Advance to the next pending record.
    JR   .PENDLOOP                      ; Continue through the complete live arena.
.OK: ; Current private scope is safe to discard.
    XOR  A                              ; Report safe eviction.
    RET                                 ; Publish no state changes.
.UNDEF: ; Return undefined-private-at-scope-close.
    LD   (SY_UPRIV),IX                  ; Name the undefined private label.
    LD   A,SY_SUNDF                     ; Select the undefined-private status.
    SCF                                 ; Mark validation as failed.
    RET                                 ; Preserve the complete private scope.
.STALE: ; Report stale private pending pointer.
    LD   A,SY_SPINV                     ; Select the internal pending-state status.
    SCF                                 ; Mark validation as failed.
    RET                                 ; Preserve both symbol and pending arenas.

;@ROUTINE IN A,IX,DE,BC OUT A,CARRY CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append one nine-byte pending record. Inputs are IX=symbol, DE=logical patch
; address, B=kind/anchor, C=signed addend, A=source-part ordinal and SY_ROFF=
; the reference's source offset. Defined symbols are rejected because their
; value should have been emitted directly.

SY_ADD: ; Append a complete patch description for an undefined symbol.
    BIT  6,(IX+5)                       ; Is this symbol already defined?
    JR   NZ,.DEFINED                    ; Reject that inconsistent request.
    PUSH AF                             ; Save source-part ordinal.
    PUSH BC                             ; Preserve kind/anchor and signed addend.
    PUSH DE                             ; Preserve the logical patch address.
    LD   HL,(SY_PTOP)                   ; Pending end is high bound.
    LD   DE,(SY_NEXT)                   ; Publication cursor is low bound.
    LD   B,SY_PENDB                     ; Require one complete record.
    CALL AT_ROOM                        ; Check capacity before writing.
    JR   C,.UNWIND                      ; Unwind saved inputs on exhaustion.
.HASCAP: ; Capacity is proved for every record field.

; Capacity is proved. Write fields in record order and publish SY_NEXT last.

    LD   HL,(SY_NEXT)                   ; Point to next free pending byte.
    PUSH IX                             ; Transfer symbol pointer to DE.
    POP  DE                             ; DE now carries the stable record address.
    LD   (HL),E                         ; Store the symbol pointer low byte.
    INC  HL                             ; Advance to its high byte field.
    LD   (HL),D                         ; Store the symbol pointer high byte.
    INC  HL                             ; Advance to the patch-address field.
    POP  DE                             ; Recover logical patch address.
    LD   (HL),E                         ; Store the patch address low byte.
    INC  HL                             ; Advance to its high byte field.
    LD   (HL),D                         ; Store the patch address high byte.
    INC  HL                             ; Advance to kind/anchor metadata.
    POP  BC                             ; Recover kind/anchor in B and addend in C.
    LD   (HL),B                         ; Store patch kind and anchor bit.
    INC  HL                             ; Advance to the signed addend field.
    LD   (HL),C                         ; Store the one-byte addend.
    INC  HL                             ; Advance to the source-part ordinal.
    POP  AF                             ; Recover the caller's full part byte.
    LD   (HL),A                         ; Store the diagnostic source-part ordinal.
    INC  HL                             ; Advance to the source-offset field.
    LD   DE,(SY_ROFF)                   ; Load the reference's source offset.
    LD   (HL),E                         ; Store its low byte.
    INC  HL                             ; Advance to its high byte.
    LD   (HL),D                         ; Store its high byte.
    INC  HL                             ; Form the next free pending address.
    LD   (SY_NEXT),HL                   ; Publish the complete record atomically.
    XOR  A                              ; Report append success.
    RET                                 ; All saved inputs consumed.
.UNWIND: ; Unwind a rejected append.
    POP  DE                             ; Discard the saved patch address.
    POP  BC                             ; Discard the saved kind and addend.
    POP  AF                             ; Restore stack and part value.
.NOCAP: ; Return pending-arena exhaustion.
    LD   A,SY_SPCAP                     ; Select the pending-capacity status code.
    SCF                                 ; Mark the append as failed.
    RET                                 ; Publish nothing on failure.
.DEFINED: ; Return pending-record-for-defined-symbol.
    LD   A,SY_SADEF                     ; Report defined-symbol invariant.
    SCF                                 ; Mark the append as failed.
    RET                                 ; Leave the pending arena untouched.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Non-mutating preflight for one additional pending record.

SY_CCAP: ; Check room for one pending record without allocating it.
    LD   HL,(SY_PTOP)                   ; Load the arena's exclusive high bound.
    LD   DE,(SY_NEXT)                   ; Load the next unpublished record address.
    PUSH BC                             ; Save caller metadata.
    LD   B,SY_PENDB                     ; Require one pending record.
    CALL AT_ROOM                        ; Compare gap with record size.
    POP  BC                             ; Restore caller kind/addend registers.
    JR   C,.NOCAP                       ; Report insufficient space.
    XOR  A                              ; Report capacity available.
    RET                                 ; Publish no pending-arena state.
.NOCAP: ; Return pending-capacity failure.
    LD   A,SY_SPCAP                     ; Select the pending-capacity status code.
    SCF                                 ; Mark the preflight as failed.
    RET                                 ; Leave all pending state unchanged.

;@ROUTINE IN IX OUT A,CARRY,BC,DE,IX CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
; Find the first pending record for symbol IX. On success IX points to it,
; DE=patch address, B=kind/anchor and C=signed addend. The part byte
; remains at (IX+6) for the caller to read before removal.

SY_PEEK: ; Find a matching pending record without removing it.
SY_PFIND: ; Shared search entry used by peek and take.
    PUSH IX                             ; Transfer requested symbol to HL.
    POP  HL                             ; HL now carries the exact record address.
    LD   (SY_OSYM),HL                   ; Preserve it across the arena scan.
    LD   IX,(SY_PBASE)                  ; Start at the first pending record.
    LD   DE,(SY_NEXT)                   ; Stop at the publication cursor.
.PEEKLOOP: ; Compare one pending symbol pointer.
    CALL AT_IXEND                       ; Has the scan reached the half-open end?
    JR   Z,SY_EMISS                     ; No matching record remains.
    LD   L,(IX+0)                       ; Read symbol pointer low byte.
    LD   H,(IX+1)                       ; Load its high byte.
    PUSH DE                             ; Protect the pending scan end.
    LD   DE,(SY_OSYM)                   ; Reload requested symbol pointer.
    OR   A                              ; Clear carry before comparison.
    SBC  HL,DE                          ; Compare the two stable record addresses.
    POP  DE                             ; Restore the pending scan end.
    JR   Z,.PFOUND                      ; IX identifies the first matching record.
    LD   BC,SY_PENDB                    ; Load the pending-record stride.
    ADD  IX,BC                          ; Advance to the next live record.
    JR   .PEEKLOOP                      ; Continue until a match or arena end.
.PFOUND: ; Return record and patch metadata.
    LD   E,(IX+2)                       ; Load the logical patch-address low byte.
    LD   D,(IX+3)                       ; Load its high byte.
    LD   B,(IX+4)                       ; Read kind and anchor bit.
    LD   C,(IX+5)                       ; Load the signed one-byte addend.
    XOR  A                              ; Report a match.
    RET                                 ; Preserve IX on the live pending record.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return shared not-found status.

SY_EMISS: ; Return the shared missing-symbol or missing-record status.
    LD   A,SY_SMISS                     ; Select the missing-record code.
    SCF                                 ; Mark the search as failed.
    RET                                 ; Return without changing either arena.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT BC,DE CLOBBERS HL,IX,SIGN,PARITY,HALFCARRY,BC,DE,ZERO
; Remove the first pending record for symbol IX after the caller has submitted
; its patch. Preserve metadata and fill any hole with the final live
; record so the arena remains dense without preserving record order.

SY_TAKE: ; Remove an accepted patch's record and compact the pending arena.
    CALL SY_PFIND                       ; Find first record for this symbol.
    RET  C                              ; Preserve the arena when none exists.
    PUSH BC                             ; Save kind/anchor and addend.
    PUSH DE                             ; Save the patch address for the caller.
    LD   HL,(SY_NEXT)                   ; Load end of live records.
    LD   DE,SY_PENDB                    ; Load the fixed pending-record size.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Address the final live record.
    LD   (SY_NEXT),HL                   ; Reclaim its bytes immediately.
    PUSH IX                             ; Move the matched record address into DE.
    POP  DE                             ; DE now identifies the hole to fill.
    OR   A                              ; Clear carry for address comparison.
    SBC  HL,DE                          ; Was the match the final record?
    JR   Z,.RESTORE                     ; No compaction is needed in that case.

; The removed record was not last: copy the last record over its slot.

    LD   HL,(SY_NEXT)                   ; Point to old final record.
    PUSH IX                             ; Move the matched-hole address into DE.
    POP  DE                             ; DE now receives the replacement record.
    LD   BC,SY_PENDB                    ; Copy every pending-record byte.
    LDIR                                ; Fill the hole with the old final record.
.RESTORE: ; Restore metadata from the removed record.
    POP  DE                             ; Return its logical patch address.
    POP  BC                             ; Return its kind/anchor and signed addend.
    XOR  A                              ; Report removal success.
    RET                                 ; IX is unspecified on return.

;@ROUTINE IN IX,DE OUT HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY CLOBBERS A
; Compare record cursor IX with half-open end DE.

AT_IXEND: ; Compare a record cursor with the interval's exclusive end.
    PUSH IX                             ; Move the current record pointer into HL.
    POP  HL                             ; HL now carries the cursor value.
    OR   A                              ; Clear carry before unsigned subtraction.
    SBC  HL,DE                          ; Zero means cursor reached end.
    RET                                 ; Return flags and difference in HL.

;@ROUTINE IN HL,DE,B OUT CARRY MAYBE-OUT ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Check that gap [DE,HL) has at least B bytes. A nonzero high byte is
; automatically sufficient because every current record size is below 256.

AT_ROOM: ; Check a half-open arena gap against the required record size.
    OR   A                              ; Clear carry before subtraction.
    SBC  HL,DE                          ; Calculate the available gap length.
    RET  C                              ; A reversed interval cannot hold a record.
    LD   A,H                            ; Read the nonnegative gap's high byte.
    OR   A                              ; Nonzero means at least 256 bytes.
    RET  NZ                             ; Enough room for a record.
    LD   A,L                            ; Load the exact small gap size.
    CP   B                              ; Carry means the gap is too small.
    RET                                 ; Return the capacity result in carry.
SY_CEND: ; Mark the end of executable symbol code.
SY_WBEG: ; Begin fixed symbol and pending workspace.

; Twenty-four bytes of fixed workspace. The first fourteen bytes hold
; symbol-arena cursors, current-scope state and transactional input. The final
; ten hold the pending arena's bounds, publication cursor, the source offset
; passed to SY_ADD and the private label a failed scope close left undefined.
; Symbol-arena cursors and current-scope state.

SY_ABASE:   DW      0                   ; Permanent base of the global symbol interval.
SY_AEND:    DW      0                   ; Exclusive end of the shared symbol arena.
SY_GEND:    DW      0                   ; First free byte above permanent globals.
SY_LBEG:    DW      0                   ; First live byte of current private records.
SY_SCOPE:   DB      0                   ; Private scope is active when nonzero.
SY_OKEY:    DW      0                   ; Saved packed-key pointer.
SY_OVAL:    DW      0                   ; Saved symbol value.
SY_OFLAG:   DB      0                   ; Insertion flags or allocation decision.

; Pending-arena cursors. SY_OSYM reuses the key pointer during pending scans.

SY_PBASE:   DW      0                   ; Base of the independent pending-record arena.
SY_PTOP:    DW      0                   ; Exclusive end of pending capacity.
SY_NEXT:    DW      0                   ; First free pending byte.
SY_ROFF:    DW      0                   ; Source offset for the next SY_ADD record.
SY_UPRIV:   DW      0                   ; Undefined private record at scope close.
SY_OSYM     EQU     SY_OKEY             ; Reuse key pointer during pending search.
SY_WEND: ; End fixed symbol and pending workspace.
