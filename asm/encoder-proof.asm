            .org $2000
            .include "zap-encoder.asm"

            .org $8000
ZapHarnessEntry:
            LD   SP,$FF00
            LD   IX,ZapHarnessInput
            LD   DE,ZapHarnessOutput
            CALL ZapEncode
            JP   ZapHarnessCapture

ZapHarnessLengthEntry:
            LD   SP,$FF00
            LD   IX,ZapHarnessInput
            CALL ZapFormLength
            JP   ZapHarnessCapture

ZapHarnessPackEntry:
            LD   SP,$FF00
            LD   HL,ZapHarnessText
            LD   A,(ZapHarnessTextLength)
            LD   B,A
            LD   DE,ZapHarnessOutput
            CALL ZapRadix40Pack
            JP   ZapHarnessCapture

ZapHarnessRecognizeEntry:
            LD   SP,$FF00
            LD   HL,ZapHarnessText
            LD   A,(ZapHarnessTextLength)
            LD   B,A
            CALL ZapRecognizeMnemonic
ZapHarnessCapture:
            LD   (ZapHarnessLength),A
            LD   A,0
            ADC  A,0
            LD   (ZapHarnessCarry),A
            HALT

ZapHarnessLength: .db 0
ZapHarnessCarry:  .db 0
ZapHarnessOutput: .db $A5,$A5,$A5,$A5,$A5,$A5,$A5
ZapHarnessInput:  .ds 10
ZapHarnessTextLength: .db 0
ZapHarnessText:   .ds 9
ZapHarnessEnd:
            .end
