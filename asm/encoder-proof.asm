            .org $2000
            .include "atom-encoder.asm"

            .org $8000
AtomHarnessEntry:
            LD   SP,$FF00
            LD   IX,AtomHarnessInput
            LD   DE,AtomHarnessOutput
            CALL AtomEncode
            JP   AtomHarnessCapture

AtomHarnessLengthEntry:
            LD   SP,$FF00
            LD   IX,AtomHarnessInput
            CALL AtomFormLength
            JP   AtomHarnessCapture

AtomHarnessPackEntry:
            LD   SP,$FF00
            LD   HL,AtomHarnessText
            LD   A,(AtomHarnessTextLength)
            LD   B,A
            LD   DE,AtomHarnessOutput
            CALL AtomRadix40Pack
            JP   AtomHarnessCapture

AtomHarnessRecognizeEntry:
            LD   SP,$FF00
            LD   HL,AtomHarnessText
            LD   A,(AtomHarnessTextLength)
            LD   B,A
            CALL AtomRecognizeMnemonic
AtomHarnessCapture:
            LD   (AtomHarnessLength),A
            LD   A,0
            ADC  A,0
            LD   (AtomHarnessCarry),A
            HALT

AtomHarnessLength: .db 0
AtomHarnessCarry:  .db 0
AtomHarnessOutputBefore: .db $3C
AtomHarnessOutput: .db $A5,$A5,$A5,$A5,$A5,$A5,$A5
AtomHarnessOutputAfter: .db $C3
AtomHarnessInputBefore: .db $5A
AtomHarnessInput:  .ds 10
AtomHarnessInputAfter: .db $A5
AtomHarnessTextLength: .db 0
AtomHarnessTextBefore: .db $69
AtomHarnessText:   .ds 9
AtomHarnessTextAfter: .db $96
AtomHarnessEnd:
            .end
