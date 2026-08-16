            .org $2000
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 0
AtomSymbolOutputMode:       .equ 0
AtomParserStatementMode:    .equ 0
AtomSymbolStatementMode:    .equ 0
AtomDriverMode:             .equ 0

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"

AtomIntegrationResidentStart:
            .include "atom-parser.asm"
AtomIntegrationResidentEnd:

            .org $8000
AtomIntegrationProofSourceStart:
AtomIntegrationSourceBefore: .db $3C
AtomIntegrationSource:       .ds 512
AtomIntegrationSourceLimit:
AtomIntegrationSourceAfter:  .db $C3
AtomIntegrationProofSourceEnd:

AtomIntegrationProofRecordStart:
AtomIntegrationRecordBefore: .db $69
AtomIntegrationRecord:       .ds 10
AtomIntegrationRecordAfter:  .db $96
AtomIntegrationProofRecordEnd:

AtomIntegrationProofOutputStart:
AtomIntegrationOutputBefore: .db $5A
AtomIntegrationOutput:       .ds 4
AtomIntegrationOutputAfter:  .db $A5
AtomIntegrationProofOutputEnd:

AtomIntegrationProofKeyStart:
AtomIntegrationKeyBefore:    .db $A6
AtomIntegrationKey:          .ds 6
AtomIntegrationKeyAfter:     .db $6A
AtomIntegrationProofKeyEnd:

            .org $9000
AtomIntegrationProofSymbolStart:
AtomIntegrationSymbolBefore: .db $39
AtomIntegrationSymbolArena:  .ds 128
AtomIntegrationSymbolLimit:
AtomIntegrationSymbolAfter:  .db $93
AtomIntegrationProofSymbolEnd:

            .org $9100
AtomIntegrationProofPendingStart:
AtomIntegrationPendingBefore:.db $4B
AtomIntegrationPendingArena: .ds 48
AtomIntegrationPendingLimit:
AtomIntegrationPendingAfter: .db $B4
AtomIntegrationProofPendingEnd:

            .end
