            .org $2000
AtomExpressionDeferredMode: .equ 0
AtomParserExpressionMode:   .equ 0
AtomParserOutputMode:       .equ 0
AtomSymbolOutputMode:       .equ 0
AtomParserStatementMode:    .equ 0
AtomSymbolStatementMode:    .equ 0
AtomDriverMode:             .equ 0
            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-parser.asm"

AtomExpressionResidentStart:
            .include "atom-expression.asm"
AtomExpressionResidentEnd:

            .org $8000
AtomExpressionProofSourceStart:
AtomExpressionSourceBefore: .db $3C
AtomExpressionSource:       .ds 512
AtomExpressionSourceLimit:
AtomExpressionSourceAfter:  .db $C3
AtomExpressionProofSourceEnd:

AtomExpressionProofKeyStart:
AtomExpressionProofKeyBefore:.db $A6
AtomExpressionProofKey:      .ds 6
AtomExpressionProofKeyAfter: .db $6A
AtomExpressionProofKeyEnd:

            .org $9000
AtomExpressionProofSymbolStart:
AtomExpressionSymbolBefore: .db $69
AtomExpressionSymbolArena:  .ds 128
AtomExpressionSymbolLimit:
AtomExpressionSymbolAfter:  .db $96
AtomExpressionProofSymbolEnd:

            .org $9100
AtomExpressionProofPendingStart:
AtomExpressionPendingBefore:.db $5A
AtomExpressionPendingArena: .ds 48
AtomExpressionPendingLimit:
AtomExpressionPendingAfter: .db $A5
AtomExpressionProofPendingEnd:

            .end
