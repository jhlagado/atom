            .org $2000
AtomSymbolOutputMode: .equ 0
            .include "atom-encoder.asm"

            .include "atom-symbols.asm"

AtomTokenizerResidentStart:
            .include "atom-tokenizer.asm"
AtomTokenizerResidentEnd:

            .org $8000
AtomTokenizerProofSourceStart:
AtomTokenizerSourceBefore: .db $3C
AtomTokenizerSource:       .ds 512
AtomTokenizerSourceLimit:
AtomTokenizerSourceAfter:  .db $C3
AtomTokenizerProofSourceEnd:

            .end
