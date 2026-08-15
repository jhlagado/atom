            .org $2000
AtomSymbolOutputMode: .equ 0
            .include "atom-encoder.asm"

AtomSymbolResidentStart:
            .include "atom-symbols.asm"
AtomSymbolResidentEnd:

            .org $8000
AtomSymbolProofDataStart:
AtomSymbolProofKeyBefore: .db $A6
AtomSymbolProofKey:       .ds 6
AtomSymbolProofKeyAfter:  .db $6A
AtomSymbolProofTextBefore:.db $C5
AtomSymbolProofText:      .ds 10
AtomSymbolProofTextAfter: .db $5C
AtomSymbolProofDataEnd:

            .org $9000
AtomSymbolArenaBefore:    .db $3C
AtomSymbolArena:          .ds 64
AtomSymbolArenaLimit:     
AtomSymbolArenaAfter:     .db $C3
AtomSymbolArenaProofEnd:

            .org $9100
AtomPendingArenaBefore:   .db $69
AtomPendingArena:         .ds 24
AtomPendingArenaLimit:    
AtomPendingArenaAfter:    .db $96
AtomPendingArenaProofEnd:

            .end
