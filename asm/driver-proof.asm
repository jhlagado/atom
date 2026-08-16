            .org $2000
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 1
AtomSymbolOutputMode:       .equ 1
AtomParserStatementMode:    .equ 1
AtomSymbolStatementMode:    .equ 1
AtomDriverMode:             .equ 1

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"
            .include "atom-parser.asm"
            .include "atom-output.asm"
            .include "atom-statements.asm"
            .include "atom-driver.asm"

            .org $6000
AtomDriverProofAdapterStart:

.routine out A,carry clobbers HL,sign,parity,halfCarry,zero
AtomProofDriverReset:
            LD   HL,AtomDriverProofLog
            LD   (AtomDriverProofLogNext),HL
            XOR  A
            LD   (AtomDriverProofFailAfter),A
            LD   (AtomDriverProofFailBegin),A
            LD   (AtomDriverProofFailCommit),A
            LD   (AtomDriverProofOpen),A
            LD   (AtomDriverProofBegan),A
            LD   (AtomDriverProofCommitted),A
            LD   (AtomDriverProofAborted),A
            RET

.routine in IX out A,carry clobbers HL,sign,parity,halfCarry,zero,BC,DE,IX,IY
AtomSinkBegin:
            LD   A,(AtomDriverProofFailBegin)
            OR   A
            JR   NZ,AtomDriverProofBeginFailure
            LD   A,(AtomDriverProofOpen)
            OR   A
            JP   NZ,AtomDriverProofLifecycleFailure
            PUSH IX
            POP  HL
            LD   (AtomDriverProofBeginDescriptor),HL
            LD   A,1
            LD   (AtomDriverProofOpen),A
            LD   HL,AtomDriverProofBegan
            INC  (HL)
            XOR  A
            RET
AtomDriverProofBeginFailure:
            LD   A,$E0
            SCF
            RET

.routine in A,C,HL out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkImageByte:
            LD   E,1
            JR   AtomDriverProofSinkByte

.routine in A,C,HL out A,carry clobbers DE,BC,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkPatchByte:
            LD   E,2
AtomDriverProofSinkByte:
            LD   (AtomDriverProofSinkByteValue),A
            LD   A,E
            LD   (AtomDriverProofSinkKind),A
            LD   A,C
            LD   (AtomDriverProofSinkBank),A
            LD   (AtomDriverProofSinkAddress),HL
            CALL AtomDriverProofSinkCheck
            RET  C
            LD   A,7
            CALL AtomDriverProofSinkReserve
            RET  C
            LD   HL,(AtomDriverProofLogNext)
            LD   A,(AtomDriverProofSinkKind)
            LD   (HL),A
            INC  HL
            LD   A,(AtomDriverProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomDriverProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),1
            INC  HL
            LD   (HL),0
            INC  HL
            LD   A,(AtomDriverProofSinkByteValue)
            LD   (HL),A
            INC  HL
            LD   (AtomDriverProofLogNext),HL
            XOR  A
            RET

.routine in C,DE,HL out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomSinkPatchWord:
            LD   A,C
            LD   (AtomDriverProofSinkBank),A
            LD   (AtomDriverProofSinkAddress),DE
            LD   (AtomDriverProofSinkWord),HL
            CALL AtomDriverProofSinkCheck
            RET  C
            LD   A,8
            CALL AtomDriverProofSinkReserve
            RET  C
            LD   HL,(AtomDriverProofLogNext)
            LD   (HL),2
            INC  HL
            LD   A,(AtomDriverProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomDriverProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),2
            INC  HL
            LD   (HL),0
            INC  HL
            LD   DE,(AtomDriverProofSinkWord)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (AtomDriverProofLogNext),HL
            XOR  A
            RET

.routine in IX,HL,DE out A,carry clobbers BC,sign,parity,halfCarry,zero,DE,HL,IX,IY
AtomSinkCommit:
            LD   A,(AtomDriverProofOpen)
            OR   A
            JR   Z,AtomDriverProofLifecycleFailure
            LD   A,(AtomDriverProofFailCommit)
            OR   A
            JR   NZ,AtomDriverProofCommitFailure
            PUSH IX
            POP  BC
            LD   (AtomDriverProofCommitDescriptor),BC
            LD   (AtomDriverProofCommitCursor),HL
            LD   (AtomDriverProofCommitRemaining),DE
            XOR  A
            LD   (AtomDriverProofOpen),A
            LD   A,1
            LD   (AtomDriverProofCommitted),A
            XOR  A
            RET
AtomDriverProofCommitFailure:
            LD   A,$E3
            SCF
            RET

.routine out A,carry clobbers HL,sign,parity,halfCarry,zero,BC,DE,IX,IY
AtomSinkAbort:
            LD   A,(AtomDriverProofOpen)
            OR   A
            JR   Z,AtomDriverProofLifecycleFailure
            XOR  A
            LD   (AtomDriverProofOpen),A
            LD   HL,AtomDriverProofAborted
            INC  (HL)
            XOR  A
            RET

.routine out A,carry clobbers zero,sign,parity,halfCarry,HL
AtomDriverProofSinkCheck:
            LD   A,(AtomDriverProofOpen)
            OR   A
            JR   Z,AtomDriverProofLifecycleFailure
            LD   A,(AtomDriverProofFailAfter)
            OR   A
            RET  Z
            DEC  A
            LD   (AtomDriverProofFailAfter),A
            RET  NZ
            LD   A,$E1
            SCF
            RET

.routine in A out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomDriverProofSinkReserve:
            LD   B,A
            LD   HL,AtomDriverProofLogLimit
            LD   DE,(AtomDriverProofLogNext)
            OR   A
            SBC  HL,DE
            JR   C,AtomDriverProofCapacityFailure
            LD   A,H
            OR   A
            JR   NZ,AtomDriverProofReserveReady
            LD   A,L
            CP   B
            JR   C,AtomDriverProofCapacityFailure
AtomDriverProofReserveReady:
            XOR  A
            RET
AtomDriverProofCapacityFailure:
            LD   A,$E2
            SCF
            RET
AtomDriverProofLifecycleFailure:
            LD   A,$EF
            SCF
            RET

AtomDriverProofAdapterEnd:

AtomDriverProofAdapterWorkspaceStart:
AtomDriverProofLogNext:          .dw 0
AtomDriverProofFailAfter:        .db 0
AtomDriverProofFailBegin:        .db 0
AtomDriverProofFailCommit:       .db 0
AtomDriverProofOpen:             .db 0
AtomDriverProofBegan:            .db 0
AtomDriverProofCommitted:        .db 0
AtomDriverProofAborted:          .db 0
AtomDriverProofBeginDescriptor:  .dw 0
AtomDriverProofCommitDescriptor: .dw 0
AtomDriverProofCommitCursor:     .dw 0
AtomDriverProofCommitRemaining:  .dw 0
AtomDriverProofSinkKind:         .db 0
AtomDriverProofSinkBank:         .db 0
AtomDriverProofSinkAddress:      .dw 0
AtomDriverProofSinkByteValue:    .db 0
AtomDriverProofSinkWord:         .dw 0
AtomDriverProofAdapterWorkspaceEnd:

            .org $8000
AtomDriverProofSourceStart:
AtomDriverSourceBefore: .db $3C
AtomDriverSource:       .ds 768
AtomDriverSourceLimit:
AtomDriverSourceAfter:  .db $C3
AtomDriverProofSourceEnd:

AtomDriverProofDescriptorStart:
AtomDriverDescriptorBefore:.db $69
AtomDriverBuildDescriptor: .ds AtomDriverDescriptorBytes
AtomDriverPartDescriptors: .ds AtomDriverPartDescriptorBytes*AtomDriverPartCapacity
AtomDriverDescriptorAfter: .db $96
AtomDriverProofDescriptorEnd:

            .org $9000
AtomDriverProofSymbolStart:
AtomDriverSymbolBefore: .db $39
AtomDriverSymbolArena:  .ds 256
AtomDriverSymbolLimit:
AtomDriverSymbolAfter:  .db $93
AtomDriverProofSymbolEnd:

            .org $9200
AtomDriverProofPendingStart:
AtomDriverPendingBefore:.db $4B
AtomDriverPendingArena: .ds 96
AtomDriverPendingLimit:
AtomDriverPendingAfter: .db $B4
AtomDriverProofPendingEnd:

            .org $9400
AtomDriverProofLogStart:
AtomDriverLogBefore: .db $5A
AtomDriverProofLog:  .ds 1024
AtomDriverProofLogLimit:
AtomDriverLogAfter:  .db $A5
AtomDriverProofLogEnd:

            .end
