            .org $2000
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 1
AtomSymbolOutputMode:       .equ 1
AtomParserStatementMode:    .equ 1
AtomSymbolStatementMode:    .equ 1

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"
            .include "atom-parser.asm"

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

            .end
