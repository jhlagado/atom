            .org $2000
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 1
AtomSymbolOutputMode:       .equ 1
AtomParserStatementMode:    .equ 0
AtomSymbolStatementMode:    .equ 0
AtomDriverMode:             .equ 0

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"
            .include "atom-parser.asm"
            .include "atom-output.asm"

            .org $6000
AtomOutputProofAdapterStart:

.routine out A,carry clobbers HL,sign,parity,halfCarry,zero
AtomProofSinkReset:
            LD   HL,AtomOutputProofLog
            LD   (AtomOutputProofLogNext),HL
            XOR  A
            LD   (AtomOutputProofFailAfter),A
            RET

; Nucleus-model logical sink entry: A=byte, C=bank, HL=target address.
.routine in A,C,HL out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkImageByte:
            LD   E,1
            JR   AtomProofSinkByte

; Nucleus-model logical sink entry: A=byte, C=bank, HL=target address.
.routine in A,C,HL out A,carry clobbers DE,BC,HL,IX,IY,zero,sign,parity,halfCarry
AtomSinkPatchByte:
            LD   E,2
AtomProofSinkByte:
            LD   (AtomOutputProofSinkByte),A
            LD   A,E
            LD   (AtomOutputProofSinkKind),A
            LD   A,C
            LD   (AtomOutputProofSinkBank),A
            LD   (AtomOutputProofSinkAddress),HL
            CALL AtomProofSinkCheckFailure
            RET  C
            LD   A,7
            CALL AtomProofSinkReserve
            RET  C
            LD   HL,(AtomOutputProofLogNext)
            LD   A,(AtomOutputProofSinkKind)
            LD   (HL),A
            INC  HL
            LD   A,(AtomOutputProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomOutputProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),1
            INC  HL
            LD   (HL),0
            INC  HL
            LD   A,(AtomOutputProofSinkByte)
            LD   (HL),A
            INC  HL
            LD   (AtomOutputProofLogNext),HL
            XOR  A
            RET

; Nucleus-model logical sink entry: C=bank, DE=address, HL=word.
.routine in C,DE,HL out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomSinkPatchWord:
            LD   A,C
            LD   (AtomOutputProofSinkBank),A
            LD   (AtomOutputProofSinkAddress),DE
            LD   (AtomOutputProofSinkWord),HL
            CALL AtomProofSinkCheckFailure
            RET  C
            LD   A,8
            CALL AtomProofSinkReserve
            RET  C
            LD   HL,(AtomOutputProofLogNext)
            LD   (HL),2
            INC  HL
            LD   A,(AtomOutputProofSinkBank)
            LD   (HL),A
            INC  HL
            LD   DE,(AtomOutputProofSinkAddress)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (HL),2
            INC  HL
            LD   (HL),0
            INC  HL
            LD   DE,(AtomOutputProofSinkWord)
            LD   (HL),E
            INC  HL
            LD   (HL),D
            INC  HL
            LD   (AtomOutputProofLogNext),HL
            XOR  A
            RET

.routine out A,carry clobbers zero,sign,parity,halfCarry,HL
AtomProofSinkCheckFailure:
            LD   A,(AtomOutputProofFailAfter)
            OR   A
            RET  Z
            DEC  A
            LD   (AtomOutputProofFailAfter),A
            RET  NZ
            LD   A,$E1
            SCF
            RET

; Reserve A bytes in the half-open proof-log arena without changing its cursor.
.routine in A out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomProofSinkReserve:
            LD   B,A
            LD   HL,AtomOutputProofLogLimit
            LD   DE,(AtomOutputProofLogNext)
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

AtomOutputProofAdapterEnd:

AtomOutputProofAdapterWorkspaceStart:
AtomOutputProofLogNext:     .dw 0
AtomOutputProofFailAfter:   .db 0
AtomOutputProofSinkKind:    .db 0
AtomOutputProofSinkBank:    .db 0
AtomOutputProofSinkAddress: .dw 0
AtomOutputProofSinkByte:    .db 0
AtomOutputProofSinkWord:    .dw 0
AtomOutputProofAdapterWorkspaceEnd:

            .org $8000
AtomOutputProofSourceStart:
AtomOutputSourceBefore: .db $3C
AtomOutputSource:       .ds 128
AtomOutputSourceLimit:
AtomOutputSourceAfter:  .db $C3
AtomOutputProofSourceEnd:

AtomOutputProofRecordStart:
AtomOutputRecordBefore: .db $69
AtomOutputRecord:       .ds 10
AtomOutputRecordAfter:  .db $96
AtomOutputProofRecordEnd:

AtomOutputProofKeyStart:
AtomOutputKeyBefore:    .db $A6
AtomOutputKey:          .ds 6
AtomOutputKeyAfter:     .db $6A
AtomOutputProofKeyEnd:

            .org $9000
AtomOutputProofSymbolStart:
AtomOutputSymbolBefore: .db $39
AtomOutputSymbolArena:  .ds 128
AtomOutputSymbolLimit:
AtomOutputSymbolAfter:  .db $93
AtomOutputProofSymbolEnd:

            .org $9100
AtomOutputProofPendingStart:
AtomOutputPendingBefore:.db $4B
AtomOutputPendingArena: .ds 48
AtomOutputPendingLimit:
AtomOutputPendingAfter: .db $B4
AtomOutputProofPendingEnd:

            .org $9200
AtomOutputProofLogStart:
AtomOutputLogBefore:    .db $5A
AtomOutputProofLog:     .ds 256
AtomOutputProofLogLimit:
AtomOutputLogAfter:     .db $A5
AtomOutputProofLogEnd:

            .end
