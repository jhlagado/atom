            .org $2000
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 1
AtomSymbolOutputMode:       .equ 1
AtomParserStatementMode:    .equ 1
AtomSymbolStatementMode:    .equ 1
AtomDriverMode:             .equ 0

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"
            .include "atom-parser.asm"
            .include "atom-output.asm"
            .include "atom-statements.asm"

            .org $6000
AtomStatementProofAdapterStart:

.routine out A,carry clobbers HL,sign,parity,halfCarry,zero
AtomProofSinkReset:
            LD   HL,AtomStatementProofLog
            LD   (AtomStatementProofLogNext),HL
            XOR  A
            LD   (AtomStatementProofFailAfter),A
            RET

.routine in A,C,HL out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkImageByte:
            LD   E,1
            JR   AtomStatementProofSinkByte

.routine in A,C,HL out A,carry clobbers DE,BC,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkPatchByte:
            LD   E,2
AtomStatementProofSinkByte:
            LD   (AtomStatementProofSinkByteValue),A
            LD   A,E
            LD   (AtomStatementProofSinkKind),A
            LD   A,C
            LD   (AtomStatementProofSinkBank),A
            LD   (AtomStatementProofSinkAddress),HL
            CALL AtomStatementProofSinkCheckFailure
            RET  C
            LD   A,7
            CALL AtomStatementProofSinkReserve
            RET  C
            LD   HL,(AtomStatementProofLogNext)
            LD   A,(AtomStatementProofSinkKind)
            LD   (HL),A
            INC  HL
            LD   A,(AtomStatementProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomStatementProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),1
            INC  HL
            LD   (HL),0
            INC  HL
            LD   A,(AtomStatementProofSinkByteValue)
            LD   (HL),A
            INC  HL
            LD   (AtomStatementProofLogNext),HL
            XOR  A
            RET

.routine in C,DE,HL out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomSinkPatchWord:
            LD   A,C
            LD   (AtomStatementProofSinkBank),A
            LD   (AtomStatementProofSinkAddress),DE
            LD   (AtomStatementProofSinkWord),HL
            CALL AtomStatementProofSinkCheckFailure
            RET  C
            LD   A,8
            CALL AtomStatementProofSinkReserve
            RET  C
            LD   HL,(AtomStatementProofLogNext)
            LD   (HL),2
            INC  HL
            LD   A,(AtomStatementProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomStatementProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),2
            INC  HL
            LD   (HL),0
            INC  HL
            LD   DE,(AtomStatementProofSinkWord)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (AtomStatementProofLogNext),HL
            XOR  A
            RET

.routine out A,carry clobbers zero,sign,parity,halfCarry,HL
AtomStatementProofSinkCheckFailure:
            LD   A,(AtomStatementProofFailAfter)
            OR   A
            RET  Z
            DEC  A
            LD   (AtomStatementProofFailAfter),A
            RET  NZ
            LD   A,$E1
            SCF
            RET

.routine in A out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomStatementProofSinkReserve:
            LD   B,A
            LD   HL,AtomStatementProofLogLimit
            LD   DE,(AtomStatementProofLogNext)
            OR   A
            SBC  HL,DE
            JR   C,.capacity
            LD   A,H
            OR   A
            JR   NZ,.accepted
            LD   A,L
            CP   B
            JR   C,.capacity
.accepted:
            XOR  A
            RET
.capacity:
            LD   A,$E2
            SCF
            RET

AtomStatementProofAdapterEnd:

AtomStatementProofAdapterWorkspaceStart:
AtomStatementProofLogNext:      .dw 0
AtomStatementProofFailAfter:    .db 0
AtomStatementProofSinkKind:     .db 0
AtomStatementProofSinkBank:     .db 0
AtomStatementProofSinkAddress:  .dw 0
AtomStatementProofSinkByteValue:.db 0
AtomStatementProofSinkWord:     .dw 0
AtomStatementProofAdapterWorkspaceEnd:

            .org $8000
AtomStatementProofSourceStart:
AtomStatementSourceBefore: .db $3C
AtomStatementSource:       .ds 128
AtomStatementSourceLimit:
AtomStatementSourceAfter:  .db $C3
AtomStatementProofSourceEnd:

AtomStatementProofRecordStart:
AtomStatementRecordBefore: .db $69
AtomStatementRecord:       .ds 10
AtomStatementRecordAfter:  .db $96
AtomStatementProofRecordEnd:

            .org $9000
AtomStatementProofSymbolStart:
AtomStatementSymbolBefore: .db $39
AtomStatementSymbolArena:  .ds 128
AtomStatementSymbolLimit:
AtomStatementSymbolAfter:  .db $93
AtomStatementProofSymbolEnd:

            .org $9100
AtomStatementProofPendingStart:
AtomStatementPendingBefore:.db $4B
AtomStatementPendingArena: .ds 48
AtomStatementPendingLimit:
AtomStatementPendingAfter: .db $B4
AtomStatementProofPendingEnd:

            .org $9200
AtomStatementProofLogStart:
AtomStatementLogBefore: .db $5A
AtomStatementProofLog:  .ds 256
AtomStatementProofLogLimit:
AtomStatementLogAfter:  .db $A5
AtomStatementProofLogEnd:

            .end
