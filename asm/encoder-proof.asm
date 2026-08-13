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
AtomHarnessOutput: .db $A5,$A5,$A5,$A5,$A5,$A5,$A5
AtomHarnessInput:  .ds 10
AtomHarnessTextLength: .db 0
AtomHarnessText:   .ds 9
AtomHarnessEnd:
            .end
