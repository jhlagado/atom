; CP/M source preprocessor. Read these routine groups in assembly order.
; Includes preserve shared global labels and local-label scopes.

    %INCLUDE "ppctrl.asm"               ; Dispatch directives, manage conditional frames and read tokens.
    %INCLUDE "ppvalue.asm"              ; Decode values, manage definitions and filter source bytes.
