; atom Phase 2a symbol and pending-reference prototype.
;
; This module assumes AtomRadix40Pack is linked. It owns no symbol or pending
; arena: callers supply half-open regions to the reset routines. Global symbols
; grow upward and current-scope private symbols grow downward in one arena.

AtomSymbolCodeStart:

AtomSymbolRecordBytes:       .equ 8
AtomPendingRecordBytes:      .equ 6
AtomPendingKindMask:         .equ $07
AtomPendingPartMask:         .equ $78
AtomPendingDiagnosticAnchor: .equ $80

AtomSymbolNameBytes:         .equ 6
AtomSymbolValueLow:          .equ 6
AtomSymbolValueHigh:         .equ 7
AtomSymbolNameHighMask:      .equ $07
AtomSymbolFlagSigned:        .equ $20
AtomSymbolFlagDefined:       .equ $40
AtomSymbolFlagPrivate:       .equ $80

AtomStatusOk:                .equ 0
AtomStatusNotFound:          .equ 1
AtomStatusDuplicate:         .equ 2
AtomStatusSymbolCapacity:    .equ 3
AtomStatusPrivateNoScope:    .equ 4
AtomStatusUndefinedPrivate:  .equ 5
AtomStatusPendingCapacity:   .equ 6
AtomStatusPendingInvariant:  .equ 7
AtomStatusAlreadyDefined:    .equ 8
.if AtomDriverMode
AtomStatusPartCapacity:      .equ 9
.endif

; in HL=symbol arena start, DE=symbol arena end (half-open)
; out carry clear, A=AtomStatusOk
.routine in HL,DE out A,carry clobbers sign,parity,halfCarry,zero
AtomSymbolReset:
            LD   (AtomSymbolArenaBase),HL
            LD   (AtomSymbolGlobalEnd),HL
            LD   (AtomSymbolArenaEnd),DE
            LD   (AtomSymbolLocalBegin),DE
            XOR  A
            LD   (AtomSymbolScopeActive),A
            RET

; in HL=pending arena start, DE=pending arena end (half-open)
; out carry clear, A=AtomStatusOk
.routine in HL,DE out A,carry clobbers sign,parity,halfCarry,zero
AtomPendingReset:
            LD   (AtomPendingArenaBase),HL
            LD   (AtomPendingNext),HL
            LD   (AtomPendingArenaEnd),DE
            XOR  A
            RET

; Pack one source identifier into the six-byte exact key used by symbol
; records. A leading '.' is syntax: it is removed from the RADIX-40 payload
; and recorded in a flag bit. Thus globals have 1..8 source characters and
; private names have '.' plus 1..8 significant characters. Failure is atomic.
;
; in HL=text, B=source length, DE=six-byte destination
; out carry clear on success; carry set and A=AtomStatusNotFound on failure
.routine in B,HL,DE out A,DE,carry clobbers BC,HL,IX,sign,parity,halfCarry,zero
AtomPackSymbol:
            LD   A,B
            OR   A
            JR   Z,_AtomPackSymbolInvalid
            LD   A,(HL)
            CP   "."
            JR   NZ,_AtomPackSymbolGlobal
            DEC  B
            JR   Z,_AtomPackSymbolInvalid
            LD   A,B
            CP   9
            JR   NC,_AtomPackSymbolInvalid
            INC  HL
            .expectout DE,carry
            CALL AtomRadix40Pack
            JR   C,_AtomPackSymbolInvalid
            PUSH DE
            DEC  DE
            LD   A,(DE)
            OR   AtomSymbolFlagPrivate
            LD   (DE),A
            POP  DE
            XOR  A
            RET
_AtomPackSymbolGlobal:
            .expectout DE,carry
            CALL AtomRadix40Pack
            JR   C,_AtomPackSymbolInvalid
            XOR  A
            RET
_AtomPackSymbolInvalid:
            XOR  A
            INC  A
            SCF
            RET

; Find an exact key in the current namespace. Global records occupy
; [base,globalEnd); private records occupy [localBegin,end).
;
; in HL=six-byte packed key
; out IX=record, A=AtomStatusOk and carry clear; or A=status and carry set
.routine in HL out A,carry,IX clobbers BC,HL,sign,parity,halfCarry,DE,zero
AtomSymbolFind:
            LD   (AtomSymbolOperationKey),HL
            PUSH HL
            LD   DE,5
            ADD  HL,DE
            BIT  7,(HL)
            POP  HL
            JR   Z,_AtomSymbolFindGlobal
            LD   A,(AtomSymbolScopeActive)
            OR   A
            JR   Z,_AtomSymbolPrivateNoScope
            LD   IX,(AtomSymbolLocalBegin)
            LD   DE,(AtomSymbolArenaEnd)
            JR   _AtomSymbolFindLoop
_AtomSymbolFindGlobal:
            LD   IX,(AtomSymbolArenaBase)
            LD   DE,(AtomSymbolGlobalEnd)
_AtomSymbolFindLoop:
            CALL AtomCompareIxDe
            JR   Z,_AtomSymbolNotFound
            PUSH DE
            .expectout zero
            CALL AtomSymbolKeyEquals
            POP  DE
            JR   Z,_AtomSymbolFound
            LD   BC,AtomSymbolRecordBytes
            ADD  IX,BC
            JR   _AtomSymbolFindLoop
_AtomSymbolFound:
            XOR  A
            RET
_AtomSymbolNotFound:
            LD   A,AtomStatusNotFound
            SCF
            RET
_AtomSymbolPrivateNoScope:
            LD   A,AtomStatusPrivateNoScope
            SCF
            RET

; in IX=record; compares against AtomSymbolOperationKey
; out Z when equal; flags otherwise. Clobbers A,B,DE,HL.
.routine in IX out zero clobbers DE,HL,sign,parity,halfCarry,B,carry,A
AtomSymbolKeyEquals:
            PUSH IX
            POP  DE
            LD   HL,(AtomSymbolOperationKey)
            LD   B,5
_AtomSymbolKeyEqualsLoop:
            LD   A,(DE)
            CP   (HL)
            RET  NZ
            INC  DE
            INC  HL
            DJNZ _AtomSymbolKeyEqualsLoop
            LD   A,(DE)
            XOR  (HL)
            AND  AtomSymbolNameHighMask
            RET

; Declare a global or current-scope private symbol. A matching forward symbol
; becomes defined; a second definition is rejected without changing it.
;
; in HL=six-byte packed key, DE=value
; out IX=record, A=AtomStatusOk and carry clear; or A=status and carry set
.routine in HL,DE out A,carry,IX clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomSymbolDeclare:
            LD   (AtomSymbolOperationKey),HL
            LD   (AtomSymbolOperationValue),DE
            .expectout A,carry,IX
            CALL AtomSymbolFind
            JR   C,_AtomSymbolDeclareMissing
            BIT  6,(IX+5)
            JR   NZ,_AtomSymbolDuplicate
            LD   DE,(AtomSymbolOperationValue)
            LD   (IX+AtomSymbolValueLow),E
            LD   (IX+AtomSymbolValueHigh),D
            LD   A,(IX+5)
            OR   AtomSymbolFlagDefined
            LD   (IX+5),A
            XOR  A
            RET
_AtomSymbolDuplicate:
            LD   A,AtomStatusDuplicate
            SCF
            RET
_AtomSymbolDeclareMissing:
            CP   AtomStatusNotFound
            JR   Z,_AtomSymbolDeclareInsert
            SCF
            RET
_AtomSymbolDeclareInsert:
            LD   A,AtomSymbolFlagDefined
            .expectout A,carry,IX
            JR   AtomSymbolInsert

; Reference a global or current-scope private symbol, creating an undefined
; exact-name record when necessary.
;
; in HL=six-byte packed key
; out IX=record, A=AtomStatusOk and carry clear; or A=status and carry set.
; Driver builds additionally return B=1 only when this call inserted the record.
.if AtomDriverMode
.routine in HL out A,carry,IX,B clobbers C,DE,HL,zero,sign,parity,halfCarry
.else
.routine in HL out A,carry,IX clobbers BC,DE,HL,zero,sign,parity,halfCarry
.endif
AtomSymbolReference:
            LD   (AtomSymbolOperationKey),HL
            .expectout A,carry,IX
            CALL AtomSymbolFind
.if AtomDriverMode
            JR   C,_AtomSymbolReferenceMissing
            LD   B,0
            RET
_AtomSymbolReferenceMissing:
.else
            RET  NC
.endif
            CP   AtomStatusNotFound
            JR   Z,_AtomSymbolReferenceInsert
            SCF
            RET
_AtomSymbolReferenceInsert:
            XOR  A
            LD   (AtomSymbolOperationValue),A
            LD   (AtomSymbolOperationValue+1),A
            .expectout A,carry,IX
            CALL AtomSymbolInsert
.if AtomDriverMode
            RET  C
            LD   B,1
.endif
            RET

; Internal insertion. A contains flags to add (currently DEFINED or zero).
; The key and value are in operation workspace. All capacity checks precede
; writes and cursor publication.
.routine in A out A,carry,IX clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomSymbolInsert:
            LD   (AtomSymbolOperationFlags),A
            LD   HL,(AtomSymbolLocalBegin)
            LD   DE,(AtomSymbolGlobalEnd)
            LD   B,AtomSymbolRecordBytes
            CALL AtomRegionHasCapacity
            JR   C,_AtomSymbolNoCapacity
_AtomSymbolHasCapacity:
            LD   HL,(AtomSymbolOperationKey)
            LD   DE,5
            ADD  HL,DE
            BIT  7,(HL)
            JR   NZ,_AtomSymbolInsertPrivate

            LD   IX,(AtomSymbolGlobalEnd)
            PUSH IX
            POP  HL
            LD   DE,AtomSymbolRecordBytes
            ADD  HL,DE
            LD   (AtomSymbolGlobalEnd),HL
            JR   _AtomSymbolCommitInsert

_AtomSymbolInsertPrivate:
            LD   HL,(AtomSymbolLocalBegin)
            LD   DE,AtomSymbolRecordBytes
            OR   A
            SBC  HL,DE
            LD   (AtomSymbolLocalBegin),HL
            PUSH HL
            POP  IX

_AtomSymbolCommitInsert:
            LD   HL,(AtomSymbolOperationKey)
            PUSH IX
            POP  DE
            LD   BC,AtomSymbolNameBytes
            LDIR
            LD   A,(AtomSymbolOperationFlags)
            OR   (IX+5)
            LD   (IX+5),A
            LD   DE,(AtomSymbolOperationValue)
            LD   (IX+AtomSymbolValueLow),E
            LD   (IX+AtomSymbolValueHigh),D
            XOR  A
            RET
_AtomSymbolNoCapacity:
            LD   A,AtomStatusSymbolCapacity
            SCF
            RET

; Validate and evict the current private namespace, then open the next one.
; Undefined private symbols are ordinary source errors. A pending entry that
; points at an already-defined private symbol is a distinct internal invariant
; failure: the output layer should have consumed it at definition time.
;
; out A=AtomStatusOk and carry clear; or A=status and carry set, state unchanged
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry
AtomSymbolAdvanceScope:
.if AtomSymbolStatementMode
            CALL AtomSymbolValidateScope
            RET  C
AtomSymbolCommitScope:
            LD   HL,(AtomSymbolArenaEnd)
            LD   (AtomSymbolLocalBegin),HL
            LD   A,1
            LD   (AtomSymbolScopeActive),A
            XOR  A
            RET
.else
            LD   IX,(AtomSymbolLocalBegin)
            LD   DE,(AtomSymbolArenaEnd)
_AtomSymbolScopeCheckLoop:
            CALL AtomCompareIxDe
            JR   Z,_AtomSymbolScopeCheckPending
            BIT  6,(IX+5)
            JR   Z,_AtomSymbolUndefinedPrivate
            LD   BC,AtomSymbolRecordBytes
            ADD  IX,BC
            JR   _AtomSymbolScopeCheckLoop

_AtomSymbolScopeCheckPending:
            LD   IX,(AtomPendingArenaBase)
            LD   DE,(AtomPendingNext)
_AtomSymbolPendingLocalLoop:
            CALL AtomCompareIxDe
            JR   Z,_AtomSymbolCommitScope
            LD   L,(IX+0)
            LD   H,(IX+1)
            PUSH DE
            LD   DE,5
            ADD  HL,DE
            BIT  7,(HL)
            POP  DE
            JR   NZ,_AtomSymbolPendingInvariant
            LD   BC,AtomPendingRecordBytes
            ADD  IX,BC
            JR   _AtomSymbolPendingLocalLoop

_AtomSymbolCommitScope:
            LD   HL,(AtomSymbolArenaEnd)
            LD   (AtomSymbolLocalBegin),HL
            LD   A,1
            LD   (AtomSymbolScopeActive),A
            XOR  A
            RET
_AtomSymbolUndefinedPrivate:
            LD   A,AtomStatusUndefinedPrivate
            SCF
            RET
_AtomSymbolPendingInvariant:
            LD   A,AtomStatusPendingInvariant
            SCF
            RET
.endif

.if AtomSymbolStatementMode
; Close the current private scope and declare one global address label as one
; transaction. Capacity is checked after the validated private eviction, so a
; reusable private record cannot cause a false global-capacity failure.
;
; in HL=six-byte global key, DE=address
; out IX=defined record, A=AtomStatusOk and carry clear; or status and carry set
.routine in HL,DE out A,carry,IX clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomSymbolDeclareGlobalLabel:
            LD   (AtomSymbolOperationKey),HL
            LD   (AtomSymbolOperationValue),DE
            LD   DE,5
            ADD  HL,DE
            BIT  7,(HL)
            JR   NZ,AtomSymbolGlobalLabelPrivate
            LD   HL,(AtomSymbolOperationKey)
            CALL AtomSymbolFind
            JR   C,AtomSymbolGlobalLabelMissing
            BIT  6,(IX+5)
            JR   NZ,AtomSymbolGlobalLabelDuplicate
            XOR  A
            LD   (AtomSymbolOperationFlags),A
            JR   AtomSymbolGlobalLabelValidate
AtomSymbolGlobalLabelMissing:
            CP   AtomStatusNotFound
            RET  NZ
            LD   A,1
            LD   (AtomSymbolOperationFlags),A
AtomSymbolGlobalLabelValidate:
            CALL AtomSymbolValidateScope
            RET  C
            LD   A,(AtomSymbolOperationFlags)
            OR   A
            JR   Z,AtomSymbolGlobalLabelCommit
            LD   HL,(AtomSymbolArenaEnd)
            LD   DE,(AtomSymbolGlobalEnd)
            LD   B,AtomSymbolRecordBytes
            CALL AtomRegionHasCapacity
            JR   C,AtomSymbolGlobalLabelCapacity
AtomSymbolGlobalLabelCommit:
            LD   HL,(AtomSymbolArenaEnd)
            LD   (AtomSymbolLocalBegin),HL
            LD   A,1
            LD   (AtomSymbolScopeActive),A
            LD   HL,(AtomSymbolOperationKey)
            LD   DE,(AtomSymbolOperationValue)
            CALL AtomSymbolDeclare
            RET  NC
            LD   A,AtomStatusPendingInvariant
            SCF
            RET
AtomSymbolGlobalLabelPrivate:
            LD   A,AtomStatusPrivateNoScope
            SCF
            RET
AtomSymbolGlobalLabelDuplicate:
            LD   A,AtomStatusDuplicate
            SCF
            RET
AtomSymbolGlobalLabelCapacity:
            LD   A,AtomStatusSymbolCapacity
            SCF
            RET

; Read-only validation shared by scope advance and the atomic global-label
; transaction. No cursor or record is changed on failure.
.routine out A,carry clobbers IX,DE,BC,zero,sign,parity,halfCarry,HL
AtomSymbolValidateScope:
            LD   IX,(AtomSymbolLocalBegin)
            LD   DE,(AtomSymbolArenaEnd)
AtomSymbolValidateScopeLoop:
            CALL AtomCompareIxDe
            JR   Z,AtomSymbolValidatePending
            BIT  6,(IX+5)
            JR   Z,AtomSymbolValidateUndefined
            LD   BC,AtomSymbolRecordBytes
            ADD  IX,BC
            JR   AtomSymbolValidateScopeLoop
AtomSymbolValidatePending:
            LD   IX,(AtomPendingArenaBase)
            LD   DE,(AtomPendingNext)
AtomSymbolValidatePendingLoop:
            CALL AtomCompareIxDe
            JR   Z,AtomSymbolValidateOk
            LD   L,(IX+0)
            LD   H,(IX+1)
            PUSH DE
            LD   DE,5
            ADD  HL,DE
            BIT  7,(HL)
            POP  DE
            JR   NZ,AtomSymbolValidateInvariant
            LD   BC,AtomPendingRecordBytes
            ADD  IX,BC
            JR   AtomSymbolValidatePendingLoop
AtomSymbolValidateOk:
            XOR  A
            RET
AtomSymbolValidateUndefined:
            LD   A,AtomStatusUndefinedPrivate
            SCF
            RET
AtomSymbolValidateInvariant:
            LD   A,AtomStatusPendingInvariant
            SCF
            RET
.endif

; Add a six-byte pending reference. The symbol must still be undefined.
;
; in IX=symbol record, DE=patch address, B=patch kind, C=auxiliary byte
; out A=AtomStatusOk and carry clear; or A=status and carry set
.routine in IX,DE,BC out A,carry clobbers DE,HL,sign,parity,halfCarry,zero
AtomPendingAdd:
            BIT  6,(IX+5)
            JR   NZ,_AtomPendingAlreadyDefined
            PUSH BC
            PUSH DE
            LD   HL,(AtomPendingArenaEnd)
            LD   DE,(AtomPendingNext)
            LD   B,AtomPendingRecordBytes
            CALL AtomRegionHasCapacity
            JR   C,_AtomPendingNoCapacityStack
_AtomPendingHasCapacity:
            LD   HL,(AtomPendingNext)
            PUSH IX
            POP  DE
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            POP  DE
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            POP  BC
            LD   (HL),B
            INC  HL
            LD   (HL),C
            INC  HL
            LD   (AtomPendingNext),HL
            XOR  A
            RET
_AtomPendingNoCapacityStack:
            POP  DE
            POP  BC
_AtomPendingNoCapacity:
            LD   A,AtomStatusPendingCapacity
            SCF
            RET
_AtomPendingAlreadyDefined:
            LD   A,AtomStatusAlreadyDefined
            SCF
            RET

.if AtomSymbolStatementMode
; Check room for one pending record without publishing it.
.routine out A,carry clobbers DE,HL,zero,sign,parity,halfCarry
AtomPendingCheckCapacity:
            LD   HL,(AtomPendingArenaEnd)
            LD   DE,(AtomPendingNext)
            PUSH BC
            LD   B,AtomPendingRecordBytes
            CALL AtomRegionHasCapacity
            POP  BC
            JR   C,AtomPendingCheckNoCapacity
            XOR  A
            RET
AtomPendingCheckNoCapacity:
            LD   A,AtomStatusPendingCapacity
            SCF
            RET
.endif

; Remove and return one pending entry for a symbol. Removal is O(1) after the
; scan: the final live record fills the hole, so the arena always measures the
; current unresolved count rather than the total references seen.
;
; in IX=symbol record
; out DE=patch address, B=kind, C=aux, A=AtomStatusOk and carry clear;
;     or A=AtomStatusNotFound and carry set
; Inspect one pending entry without removing it. Phase 2f uses this entry to
; validate and submit a patch before it reclaims the record with PendingTake.
.routine in IX out A,carry,BC,DE,IX clobbers sign,parity,halfCarry,zero,HL
.if AtomSymbolOutputMode
AtomPendingPeek:
.endif
AtomPendingFind:
            PUSH IX
            POP  HL
            LD   (AtomPendingOperationSymbol),HL
            LD   IX,(AtomPendingArenaBase)
            LD   DE,(AtomPendingNext)
_AtomPendingPeekLoop:
            CALL AtomCompareIxDe
            JR   Z,_AtomPendingPeekNotFound
            LD   L,(IX+0)
            LD   H,(IX+1)
            PUSH DE
            LD   DE,(AtomPendingOperationSymbol)
            OR   A
            SBC  HL,DE
            POP  DE
            JR   Z,_AtomPendingPeekFound
            LD   BC,AtomPendingRecordBytes
            ADD  IX,BC
            JR   _AtomPendingPeekLoop
_AtomPendingPeekFound:
            LD   E,(IX+2)
            LD   D,(IX+3)
            LD   B,(IX+4)
            LD   C,(IX+5)
            XOR  A
            RET
_AtomPendingPeekNotFound:
            LD   A,AtomStatusNotFound
            SCF
            RET

.routine in IX out A,carry maybe-out BC,DE clobbers HL,IX,sign,parity,halfCarry,BC,DE,zero
AtomPendingTake:
            CALL AtomPendingFind
            RET  C
            PUSH BC
            PUSH DE

            LD   HL,(AtomPendingNext)
            LD   DE,AtomPendingRecordBytes
            OR   A
            SBC  HL,DE
            LD   (AtomPendingNext),HL
            PUSH IX
            POP  DE
            OR   A
            SBC  HL,DE
            JR   Z,_AtomPendingTakeReturn

            ; Copy the old final record over the removed hole.
            LD   HL,(AtomPendingNext)
            PUSH IX
            POP  DE
            LD   BC,AtomPendingRecordBytes
            LDIR
_AtomPendingTakeReturn:
            POP  DE
            POP  BC
            XOR  A
            RET

.routine in IX,DE out HL,carry,zero,sign,parity,halfCarry clobbers A
AtomCompareIxDe:
            PUSH IX
            POP  HL
            OR   A
            SBC  HL,DE
            RET

; Carry clear when the unsigned region [DE,HL) contains at least B bytes.
.routine in HL,DE,B out carry maybe-out zero clobbers A,HL,sign,parity,halfCarry
AtomRegionHasCapacity:
            OR   A
            SBC  HL,DE
            RET  C
            LD   A,H
            OR   A
            RET  NZ
            LD   A,L
            CP   B
            RET

AtomSymbolCodeEnd:

; Fixed control state only. Symbol and pending records remain in caller-owned
; arenas and are accounted separately as capacity, never hidden as code.
AtomSymbolWorkspaceStart:
AtomSymbolArenaBase:          .dw 0
AtomSymbolArenaEnd:           .dw 0
AtomSymbolGlobalEnd:          .dw 0
AtomSymbolLocalBegin:         .dw 0
AtomSymbolScopeActive:        .db 0
AtomSymbolOperationKey:       .dw 0
AtomSymbolOperationValue:     .dw 0
AtomSymbolOperationFlags:     .db 0
AtomPendingArenaBase:         .dw 0
AtomPendingArenaEnd:          .dw 0
AtomPendingNext:              .dw 0
AtomPendingOperationSymbol:   .dw 0
AtomSymbolWorkspaceEnd:
