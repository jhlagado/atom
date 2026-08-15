            .org $2000
AtomParserExpressionMode: .equ 0
AtomParserOutputMode:     .equ 0
AtomSymbolOutputMode:     .equ 0
            .include "atom-encoder.asm"

            .include "atom-symbols.asm"

            .include "atom-tokenizer.asm"

AtomParserResidentStart:
            .include "atom-parser.asm"
AtomParserResidentEnd:

            .org $8000
AtomParserProofSourceStart:
AtomParserSourceBefore: .db $3C
AtomParserSource:       .ds 512
AtomParserSourceLimit:
AtomParserSourceAfter:  .db $C3
AtomParserProofSourceEnd:

AtomParserProofRecordStart:
AtomParserRecordBefore: .db $69
AtomParserRecord:       .ds 10
AtomParserRecordAfter:  .db $96
AtomParserProofRecordEnd:

AtomParserProofOutputStart:
AtomParserOutputBefore: .db $5A
AtomParserOutput:       .ds 4
AtomParserOutputAfter:  .db $A5
AtomParserProofOutputEnd:

            .end
