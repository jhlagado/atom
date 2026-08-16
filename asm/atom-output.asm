; atom Phase 2f Nucleus-model target output.
;
; The operating adapter provides AtomSinkImageByte, AtomSinkPatchByte, and
; AtomSinkPatchWord. It owns NOBJ framing, spools, commit, abort, and storage.

AtomOutputCodeStart:

AtomOutputStatusCapacity: .equ 1
AtomOutputStatusInternal: .equ 2
AtomOutputStatusValueRange:    .equ 3
AtomOutputStatusRelativeRange: .equ 4

; Initialize flat bank-zero output state.
;
; in HL=target start address, DE=mathematical byte capacity
.routine in DE,HL out A,carry clobbers sign,parity,halfCarry,zero
AtomOutputReset:
            LD   (AtomOutputCursor),HL
            LD   (AtomOutputRemaining),DE
            XOR  A
            RET

.if AtomParserStatementMode
; Check that a mathematical target span fits without changing output state.
; in HL=byte count
.routine in HL out A,carry clobbers DE,sign,parity,halfCarry,HL,zero
AtomOutputCheckCapacity:
            EX   DE,HL
            LD   HL,(AtomOutputRemaining)
            OR   A
            SBC  HL,DE
            JR   C,AtomOutputDataCapacityFailure
            XOR  A
            RET

; Submit one initialized data byte.
; in A=byte
.routine in A out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC,IX,IY
AtomOutputEmitByte:
            LD   (AtomOutputDataValue),A
            LD   HL,1
            CALL AtomOutputCheckCapacity
            RET  C
            LD   A,(AtomOutputDataValue)
            JP   AtomOutputEmitByteReady

; Submit one little-endian initialized data word.
; in HL=word
.routine in HL out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC,IX,IY
AtomOutputEmitWord:
            LD   (AtomOutputDataValue),HL
            LD   HL,2
            CALL AtomOutputCheckCapacity
            RET  C
            LD   A,(AtomOutputDataValue)
            CALL AtomOutputEmitByteReady
            RET  C
            LD   A,(AtomOutputDataValue+1)
            JP   AtomOutputEmitByteReady

; Advance over uninitialized reserved bytes without emitting IMAGE records.
; in HL=count
.routine in HL out A,carry clobbers DE,HL,zero,sign,parity,halfCarry
AtomOutputReserve:
            LD   (AtomOutputDataValue),HL
            CALL AtomOutputCheckCapacity
            RET  C
            LD   DE,(AtomOutputDataValue)
            LD   HL,(AtomOutputCursor)
            ADD  HL,DE
            LD   (AtomOutputCursor),HL
            LD   HL,(AtomOutputRemaining)
            OR   A
            SBC  HL,DE
            LD   (AtomOutputRemaining),HL
            XOR  A
            RET

; Select a new logical target address without emitting bytes.
; in HL=origin
.routine in HL out A,carry clobbers sign,parity,halfCarry,zero
AtomOutputSetOrigin:
            LD   (AtomOutputCursor),HL
            XOR  A
            RET

.routine in A out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomOutputEmitByteReady:
            LD   HL,(AtomOutputCursor)
            LD   C,0
            CALL AtomSinkImageByte
            RET  C
            LD   HL,(AtomOutputCursor)
            INC  HL
            LD   (AtomOutputCursor),HL
            LD   HL,(AtomOutputRemaining)
            DEC  HL
            LD   (AtomOutputRemaining),HL
            XOR  A
            RET
AtomOutputDataCapacityFailure:
            LD   A,AtomOutputStatusCapacity
            SCF
            RET
.endif

; Encode and submit one parsed instruction through the Nucleus image-byte
; sink. The parser's pending references are published after all bytes succeed.
;
; in IX=ten-byte parsed instruction
.routine in IX out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IX,IY
AtomOutputEmitInstruction:
            LD   HL,(AtomOutputCursor)
            LD   (AtomOutputInstructionStart),HL
            LD   DE,AtomOutputInstructionBytes
            CALL AtomEncode
            RET  C
            LD   (AtomOutputInstructionLength),A
            LD   B,A
            LD   HL,(AtomOutputRemaining)
            LD   A,H
            OR   A
            JR   NZ,_AtomOutputInstructionCapacityReady
            LD   A,L
            CP   B
            JR   C,_AtomOutputInstructionCapacityFailure
_AtomOutputInstructionCapacityReady:
            CALL AtomParserCheckReferences
            RET  C
            XOR  A
            LD   (AtomOutputInstructionScan),A
_AtomOutputInstructionLoop:
            LD   A,(AtomOutputInstructionLength)
            LD   B,A
            LD   A,(AtomOutputInstructionScan)
            CP   B
            JR   Z,_AtomOutputInstructionDone
            LD   E,A
            LD   D,0
            LD   HL,AtomOutputInstructionBytes
            ADD  HL,DE
            LD   A,(HL)
            LD   HL,(AtomOutputCursor)
            LD   C,0
            CALL AtomSinkImageByte
            RET  C
            LD   HL,(AtomOutputCursor)
            INC  HL
            LD   (AtomOutputCursor),HL
            LD   HL,(AtomOutputRemaining)
            DEC  HL
            LD   (AtomOutputRemaining),HL
            LD   HL,AtomOutputInstructionScan
            INC  (HL)
            JR   _AtomOutputInstructionLoop
_AtomOutputInstructionDone:
            LD   DE,(AtomOutputInstructionStart)
            CALL AtomParserQueueReferences
            RET
_AtomOutputInstructionCapacityFailure:
            LD   A,AtomOutputStatusCapacity
            SCF
            RET

; Resolve every pending reference to one newly defined symbol. Patch bytes go
; through the same logical sink boundary as Nucleus and each pending record is
; removed only after its sink call succeeds.
;
; in IX=defined symbol record
.routine in IX out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomOutputResolveSymbol:
            BIT  6,(IX+5)
            JP   Z,AtomOutputResolveInternal
            PUSH IX
            POP  HL
            LD   (AtomOutputResolveSymbolPointer),HL
_AtomOutputResolveLoop:
            LD   IX,(AtomOutputResolveSymbolPointer)
            .expectout A,carry,BC,DE
            CALL AtomPendingPeek
            JP   C,_AtomOutputResolvePeekFailure
            LD   (AtomOutputResolvePatchAddress),DE
            LD   A,B
.if AtomDriverMode
            AND  AtomPendingKindMask
.endif
            LD   (AtomOutputResolveKind),A
            LD   A,C
            LD   (AtomOutputResolveAddend),A

            LD   IX,(AtomOutputResolveSymbolPointer)
            LD   L,(IX+AtomSymbolValueLow)
            LD   H,(IX+AtomSymbolValueHigh)
.if AtomParserStatementMode
            XOR  A
            BIT  5,(IX+5)
            JR   Z,_AtomOutputResolveBaseReady
            DEC  A
_AtomOutputResolveBaseReady:
            LD   (AtomOutputResolveBaseHigh),A
.endif
            LD   A,(AtomOutputResolveAddend)
            LD   C,A
            LD   D,0
            BIT  7,C
            JR   Z,_AtomOutputResolveSignReady
            DEC  D
_AtomOutputResolveSignReady:
            LD   A,L
            ADD  A,C
            LD   (AtomOutputResolveValue),A
            LD   A,H
            ADC  A,D
            LD   (AtomOutputResolveValue+1),A
.if AtomParserStatementMode
            LD   A,(AtomOutputResolveBaseHigh)
.else
            LD   A,0
.endif
            ADC  A,D
            LD   (AtomOutputResolveValue+2),A
            CALL AtomOutputRequireWordDomain
            RET  C

            LD   A,(AtomOutputResolveKind)
            CP   AtomPatchKindByte
            JR   Z,_AtomOutputResolveByte
            CP   AtomPatchKindWord
            JR   Z,_AtomOutputResolveWord
            CP   AtomPatchKindRelative
            JR   Z,_AtomOutputResolveRelative
            CP   AtomPatchKindDisplacement
            JR   Z,_AtomOutputResolveDisplacement
.if AtomParserStatementMode
            CP   AtomPatchKindTruncateByte
            JR   Z,_AtomOutputResolveSubmitByte
.endif
            JP   AtomOutputResolveInternal

_AtomOutputResolveByte:
            LD   A,(AtomOutputResolveValue+2)
            OR   A
            JR   NZ,AtomOutputResolveValueRange
            LD   A,(AtomOutputResolveValue+1)
            OR   A
            JR   NZ,AtomOutputResolveValueRange
            JR   _AtomOutputResolveSubmitByte

_AtomOutputResolveDisplacement:
            LD   A,(AtomOutputResolveValue+2)
            OR   A
            JR   Z,_AtomOutputResolveDisplacementPositive
            INC  A
            JR   NZ,AtomOutputResolveValueRange
            LD   A,(AtomOutputResolveValue+1)
            INC  A
            JR   NZ,AtomOutputResolveValueRange
            LD   A,(AtomOutputResolveValue)
            BIT  7,A
            JR   Z,AtomOutputResolveValueRange
            JR   _AtomOutputResolveSubmitByte
_AtomOutputResolveDisplacementPositive:
            LD   A,(AtomOutputResolveValue+1)
            OR   A
            JR   NZ,AtomOutputResolveValueRange
            LD   A,(AtomOutputResolveValue)
            BIT  7,A
            JR   NZ,AtomOutputResolveValueRange
            JR   _AtomOutputResolveSubmitByte

_AtomOutputResolveRelative:
            LD   HL,(AtomOutputResolveValue)
            LD   DE,(AtomOutputResolvePatchAddress)
            INC  DE
            OR   A
            SBC  HL,DE
            LD   A,H
            OR   A
            JR   Z,_AtomOutputResolveRelativePositive
            INC  A
            JR   NZ,AtomOutputResolveRelativeRange
            BIT  7,L
            JR   Z,AtomOutputResolveRelativeRange
            LD   A,L
            JR   _AtomOutputResolveSubmitByteA
_AtomOutputResolveRelativePositive:
            BIT  7,L
            JR   NZ,AtomOutputResolveRelativeRange
            LD   A,L
            JR   _AtomOutputResolveSubmitByteA

_AtomOutputResolveSubmitByte:
            LD   A,(AtomOutputResolveValue)
_AtomOutputResolveSubmitByteA:
            LD   HL,(AtomOutputResolvePatchAddress)
            LD   C,0
            CALL AtomSinkPatchByte
            RET  C
            JR   _AtomOutputResolveRemove

_AtomOutputResolveWord:
            LD   HL,(AtomOutputResolveValue)
            LD   DE,(AtomOutputResolvePatchAddress)
            LD   C,0
            CALL AtomSinkPatchWord
            RET  C

_AtomOutputResolveRemove:
            LD   IX,(AtomOutputResolveSymbolPointer)
            CALL AtomPendingTake
            JR   C,AtomOutputResolveInternal
            JP   _AtomOutputResolveLoop

_AtomOutputResolvePeekFailure:
            CP   AtomStatusNotFound
            RET  NZ
            XOR  A
            RET
AtomOutputResolveValueRange:
            LD   A,AtomOutputStatusValueRange
            SCF
            RET
AtomOutputResolveRelativeRange:
            LD   A,AtomOutputStatusRelativeRange
            SCF
            RET
AtomOutputResolveInternal:
            LD   A,AtomOutputStatusInternal
            SCF
            RET

; The deferred expression value is an unsigned symbol word plus a signed-byte
; addend and must remain in Atom's accepted -32768..65535 word domain.
.routine out A,carry clobbers zero,sign,parity,halfCarry,BC,DE,HL,IX,IY
AtomOutputRequireWordDomain:
            LD   A,(AtomOutputResolveValue+2)
            OR   A
            RET  Z
            INC  A
            JR   NZ,AtomOutputResolveValueRange
            LD   A,(AtomOutputResolveValue+1)
            BIT  7,A
            RET  NZ
            JR   AtomOutputResolveValueRange

AtomOutputCodeEnd:

AtomOutputWorkspaceStart:
AtomOutputCursor:              .dw 0
AtomOutputRemaining:           .dw 0
AtomOutputInstructionStart:    .dw 0
AtomOutputInstructionBytes:    .ds 4
AtomOutputInstructionLength:   .db 0
AtomOutputInstructionScan:     .db 0
AtomOutputResolveSymbolPointer:.dw 0
AtomOutputResolvePatchAddress: .dw 0
AtomOutputResolveKind:         .db 0
AtomOutputResolveAddend:       .db 0
AtomOutputResolveValue:        .ds 3
.if AtomParserStatementMode
AtomOutputDataValue:           .dw 0
AtomOutputResolveBaseHigh:     .db 0
.endif
AtomOutputWorkspaceEnd:
