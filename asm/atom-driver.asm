; atom Phase 3 native multipart assembly driver.
;
; The host or operating layer owns source discovery and storage. It supplies a
; validated build descriptor and immutable five-byte source-part descriptors.
; Atom owns native reset, ordered part assembly, final symbol validation, and
; the sink generation lifecycle.

AtomDriverCodeStart:

AtomDriverStatusOk:            .equ 0
AtomDriverStatusConfiguration: .equ 1
AtomDriverStatusSource:        .equ 2
AtomDriverStatusUndefined:     .equ 3
AtomDriverStatusOutput:        .equ 4
AtomDriverStatusInternal:      .equ 5

AtomDriverConfigPartCount:     .equ 1
AtomDriverConfigTableRange:    .equ 2
AtomDriverConfigPartOrdinal:   .equ 3
AtomDriverConfigSourceRange:   .equ 4
AtomDriverConfigSymbolRange:   .equ 5
AtomDriverConfigPendingRange:  .equ 6
AtomDriverConfigOutputRange:   .equ 7

AtomDriverPartCapacity:        .equ 16
AtomDriverPartDescriptorBytes: .equ 5
AtomDriverPartOrdinal:         .equ 0
AtomDriverPartStart:           .equ 1
AtomDriverPartEnd:             .equ 3

AtomDriverDescriptorPartCount:   .equ 0
AtomDriverDescriptorParts:       .equ 1
AtomDriverDescriptorSymbolStart: .equ 3
AtomDriverDescriptorSymbolEnd:   .equ 5
AtomDriverDescriptorPendingStart:.equ 7
AtomDriverDescriptorPendingEnd:  .equ 9
AtomDriverDescriptorTargetStart: .equ 11
AtomDriverDescriptorTargetBytes: .equ 13
AtomDriverDescriptorBytes:       .equ 15

; Assemble one complete ordered generation.
;
; in IX=15-byte build descriptor
; out A=driver status and carry clear on committed success; carry set on failure
;     AtomDriverDetail=nested configuration, statement, or sink status
;     source failures retain AtomStatementErrorPart/ErrorOffset
.routine in IX out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomAssemble:
            PUSH IX
            POP  HL
            LD   (AtomDriverDescriptor),HL
            XOR  A
            LD   (AtomDriverDetail),A
            LD   (AtomDriverUndefinedSymbol),A
            LD   (AtomDriverUndefinedSymbol+1),A
            CALL AtomDriverValidateDescriptor
            RET  C

            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorSymbolStart)
            LD   H,(IX+AtomDriverDescriptorSymbolStart+1)
            LD   E,(IX+AtomDriverDescriptorSymbolEnd)
            LD   D,(IX+AtomDriverDescriptorSymbolEnd+1)
            CALL AtomSymbolReset
            JP   C,AtomDriverInternalFailure
            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorPendingStart)
            LD   H,(IX+AtomDriverDescriptorPendingStart+1)
            LD   E,(IX+AtomDriverDescriptorPendingEnd)
            LD   D,(IX+AtomDriverDescriptorPendingEnd+1)
            CALL AtomPendingReset
            JP   C,AtomDriverInternalFailure
            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorTargetStart)
            LD   H,(IX+AtomDriverDescriptorTargetStart+1)
            LD   E,(IX+AtomDriverDescriptorTargetBytes)
            LD   D,(IX+AtomDriverDescriptorTargetBytes+1)
            CALL AtomOutputReset
            JP   C,AtomDriverInternalFailure

            LD   IX,(AtomDriverDescriptor)
            CALL AtomSinkBegin
            JP   C,AtomDriverBeginFailure

            LD   IX,(AtomDriverDescriptor)
            LD   A,(IX+AtomDriverDescriptorPartCount)
            LD   (AtomDriverPartsRemaining),A
            LD   L,(IX+AtomDriverDescriptorParts)
            LD   H,(IX+AtomDriverDescriptorParts+1)
            LD   (AtomDriverPartCursor),HL
            XOR  A
            LD   (AtomDriverPartIndex),A
AtomDriverPartLoop:
            LD   A,(AtomDriverPartsRemaining)
            OR   A
            JR   Z,AtomDriverFinish
            LD   HL,(AtomDriverPartCursor)
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            PUSH DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   (AtomDriverPartCursor),HL
            POP  HL
            LD   A,(AtomDriverPartIndex)
            CALL AtomTokenizerReset
            JP   C,AtomDriverInternalAbort
            CALL AtomAssemblePart
            JR   C,AtomDriverSourceFailure
            LD   HL,AtomDriverPartIndex
            INC  (HL)
            LD   HL,AtomDriverPartsRemaining
            DEC  (HL)
            JR   AtomDriverPartLoop

AtomDriverFinish:
            CALL AtomAssembleFinish
            JR   C,AtomDriverFinishFailure
            LD   IX,(AtomDriverDescriptor)
            LD   HL,(AtomOutputCursor)
            LD   DE,(AtomOutputRemaining)
            CALL AtomSinkCommit
            JR   C,AtomDriverCommitFailure
            XOR  A
            RET

AtomDriverSourceFailure:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusSource
            JR   AtomDriverAbort
AtomDriverFinishFailure:
            LD   (AtomDriverDetail),A
            CP   AtomStatementStatusUndefined
            LD   A,AtomDriverStatusUndefined
            JR   Z,AtomDriverAbort
            LD   A,AtomDriverStatusInternal
            JR   AtomDriverAbort
AtomDriverInternalAbort:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusInternal
            JR   AtomDriverAbort
AtomDriverCommitFailure:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusOutput
AtomDriverAbort:
            PUSH AF
            CALL AtomSinkAbort
            POP  AF
            SCF
            RET
AtomDriverBeginFailure:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusOutput
            SCF
            RET
AtomDriverInternalFailure:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusInternal
            SCF
            RET

; Validate all caller-owned ranges and ordered part identities before opening
; a sink generation. Source-part ordinals are exactly zero through count-1.
.routine out A,carry clobbers BC,DE,IX,sign,parity,halfCarry,HL,zero,IY
AtomDriverValidateDescriptor:
            LD   IX,(AtomDriverDescriptor)
            LD   A,(IX+AtomDriverDescriptorPartCount)
            OR   A
            JP   Z,AtomDriverBadPartCount
            CP   AtomDriverPartCapacity+1
            JP   NC,AtomDriverBadPartCount
            LD   (AtomDriverPartsRemaining),A
            LD   L,(IX+AtomDriverDescriptorParts)
            LD   H,(IX+AtomDriverDescriptorParts+1)
            LD   (AtomDriverPartCursor),HL
            LD   C,A
            LD   B,0
            PUSH HL
            LD   H,B
            LD   L,C
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            POP  DE
            ADD  HL,DE
            JR   C,AtomDriverBadPartTable
            XOR  A
            LD   (AtomDriverPartIndex),A
AtomDriverValidatePartLoop:
            LD   A,(AtomDriverPartsRemaining)
            OR   A
            JR   Z,AtomDriverValidateArenas
            LD   HL,(AtomDriverPartCursor)
            LD   A,(AtomDriverPartIndex)
            CP   (HL)
            JR   NZ,AtomDriverBadPartOrdinal
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            INC  HL
            LD   C,(HL)
            INC  HL
            LD   B,(HL)
            INC  HL
            LD   (AtomDriverPartCursor),HL
            LD   H,B
            LD   L,C
            OR   A
            SBC  HL,DE
            JR   C,AtomDriverBadSourceRange
            LD   HL,AtomDriverPartIndex
            INC  (HL)
            LD   HL,AtomDriverPartsRemaining
            DEC  (HL)
            JR   AtomDriverValidatePartLoop

AtomDriverValidateArenas:
            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorSymbolStart)
            LD   H,(IX+AtomDriverDescriptorSymbolStart+1)
            LD   E,(IX+AtomDriverDescriptorSymbolEnd)
            LD   D,(IX+AtomDriverDescriptorSymbolEnd+1)
            CALL AtomDriverValidateRange
            JR   C,AtomDriverBadSymbolRange
            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorPendingStart)
            LD   H,(IX+AtomDriverDescriptorPendingStart+1)
            LD   E,(IX+AtomDriverDescriptorPendingEnd)
            LD   D,(IX+AtomDriverDescriptorPendingEnd+1)
            CALL AtomDriverValidateRange
            JR   C,AtomDriverBadPendingRange
            LD   IX,(AtomDriverDescriptor)
            LD   L,(IX+AtomDriverDescriptorTargetStart)
            LD   H,(IX+AtomDriverDescriptorTargetStart+1)
            LD   E,(IX+AtomDriverDescriptorTargetBytes)
            LD   D,(IX+AtomDriverDescriptorTargetBytes+1)
            ADD  HL,DE
            JR   C,AtomDriverBadOutputRange
            XOR  A
            RET

; in HL=start, DE=end; out carry clear exactly when end >= start
.routine in HL,DE out A,carry clobbers zero,sign,parity,halfCarry,HL,DE
AtomDriverValidateRange:
            EX   DE,HL
            OR   A
            SBC  HL,DE
            RET  NC
            SCF
            RET

AtomDriverBadPartCount:
            LD   A,AtomDriverConfigPartCount
            JR   AtomDriverConfigurationFailure
AtomDriverBadPartTable:
            LD   A,AtomDriverConfigTableRange
            JR   AtomDriverConfigurationFailure
AtomDriverBadPartOrdinal:
            LD   A,AtomDriverConfigPartOrdinal
            JR   AtomDriverConfigurationFailure
AtomDriverBadSourceRange:
            LD   A,AtomDriverConfigSourceRange
            JR   AtomDriverConfigurationFailure
AtomDriverBadSymbolRange:
            LD   A,AtomDriverConfigSymbolRange
            JR   AtomDriverConfigurationFailure
AtomDriverBadPendingRange:
            LD   A,AtomDriverConfigPendingRange
            JR   AtomDriverConfigurationFailure
AtomDriverBadOutputRange:
            LD   A,AtomDriverConfigOutputRange
AtomDriverConfigurationFailure:
            LD   (AtomDriverDetail),A
            LD   A,AtomDriverStatusConfiguration
            SCF
            RET

; Final assembly EOF. Undefined references retain one diagnostic anchor in the
; pending arena. Its high patch-kind bits carry the source part; the undefined
; symbol's otherwise-unused value word carries the exact source offset.
;
; out success A=0 and carry clear; failure returns statement status 8 or 9,
;     IX=undefined symbol for status 8, and exact statement error position
.routine out A,carry,IX clobbers DE,zero,sign,parity,halfCarry,HL,BC,IY
AtomAssembleFinish:
            LD   IX,(AtomPendingArenaBase)
            LD   DE,(AtomPendingNext)
            PUSH IX
            POP  HL
            OR   A
            SBC  HL,DE
            JR   Z,AtomFinishNoPending
AtomFinishPendingLoop:
            BIT  7,(IX+4)
            JR   NZ,AtomFinishAnchor
            LD   BC,AtomPendingRecordBytes
            ADD  IX,BC
            PUSH IX
            POP  HL
            OR   A
            SBC  HL,DE
            JR   NZ,AtomFinishPendingLoop
            JR   AtomFinishInternal

AtomFinishAnchor:
            LD   L,(IX+0)
            LD   H,(IX+1)
            LD   (AtomDriverUndefinedSymbol),HL
            CALL AtomDriverValidateSymbolPointer
            JR   C,AtomFinishInternal
            LD   IY,(AtomDriverUndefinedSymbol)
            BIT  6,(IY+5)
            JR   NZ,AtomFinishInternal
            LD   A,(IX+4)
            AND  AtomPendingKindMask
            JR   Z,AtomFinishInternal
            CP   AtomPatchKindTruncateByte+1
            JR   NC,AtomFinishInternal
            LD   A,(IX+4)
            AND  AtomPendingPartMask
            RRCA
            RRCA
            RRCA
            LD   (AtomStatementErrorPart),A
            LD   L,(IY+AtomSymbolValueLow)
            LD   H,(IY+AtomSymbolValueHigh)
            LD   (AtomStatementErrorOffset),HL
            XOR  A
            LD   (AtomStatementDetail),A
            LD   IX,(AtomDriverUndefinedSymbol)
            LD   A,AtomStatementStatusUndefined
            SCF
            RET

AtomFinishNoPending:
            CALL AtomSymbolValidateScope
            JR   C,AtomFinishInternal
            LD   IX,(AtomSymbolArenaBase)
            LD   DE,(AtomSymbolGlobalEnd)
AtomFinishGlobalLoop:
            PUSH IX
            POP  HL
            OR   A
            SBC  HL,DE
            JR   Z,AtomFinishSuccess
            BIT  6,(IX+5)
            JR   Z,AtomFinishInternal
            LD   BC,AtomSymbolRecordBytes
            ADD  IX,BC
            JR   AtomFinishGlobalLoop
AtomFinishSuccess:
            XOR  A
            RET
AtomFinishInternal:
            XOR  A
            LD   (AtomDriverUndefinedSymbol),A
            LD   (AtomDriverUndefinedSymbol+1),A
            LD   A,AtomStatementStatusInternal
            SCF
            RET

; Verify that one pending-record symbol pointer names an aligned live global or
; current-scope private record before dereferencing it.
;
; in HL=symbol pointer; out carry clear when valid
.routine in HL out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC
AtomDriverValidateSymbolPointer:
            PUSH HL
            LD   DE,(AtomSymbolArenaBase)
            OR   A
            SBC  HL,DE
            POP  HL
            JR   C,AtomDriverValidatePrivatePointer
            PUSH HL
            LD   DE,(AtomSymbolGlobalEnd)
            OR   A
            SBC  HL,DE
            POP  HL
            JR   NC,AtomDriverValidatePrivatePointer
            LD   DE,(AtomSymbolArenaBase)
            OR   A
            SBC  HL,DE
            LD   A,L
            AND  AtomSymbolRecordBytes-1
            RET  Z
            SCF
            RET
AtomDriverValidatePrivatePointer:
            PUSH HL
            LD   DE,(AtomSymbolLocalBegin)
            OR   A
            SBC  HL,DE
            POP  HL
            RET  C
            PUSH HL
            LD   DE,(AtomSymbolArenaEnd)
            OR   A
            SBC  HL,DE
            POP  HL
            JR   NC,AtomDriverInvalidSymbolPointer
            LD   DE,(AtomSymbolArenaEnd)
            EX   DE,HL
            OR   A
            SBC  HL,DE
            LD   A,L
            AND  AtomSymbolRecordBytes-1
            RET  Z
AtomDriverInvalidSymbolPointer:
            SCF
            RET

AtomDriverCodeEnd:

AtomDriverWorkspaceStart:
AtomDriverDescriptor:       .dw 0
AtomDriverPartCursor:       .dw 0
AtomDriverPartsRemaining:   .db 0
AtomDriverPartIndex:        .db 0
AtomDriverDetail:           .db 0
AtomDriverUndefinedSymbol:  .dw 0
AtomDriverWorkspaceEnd:
