;=============================================================================
;  Encoder: form validation and instruction bytes
;=============================================================================
;
;  Validate a parsed instruction record against the Z80's forms, then stage
;  its bytes in enTemp for the output layer.

    %INCLUDE "endisp.asm"               ; Dispatch a mnemonic to its family handler.
    %INCLUDE "envbasic.asm"             ; Validate basic instruction forms and lengths.
    %INCLUDE "envload.asm"              ; Validate register and memory load forms.
    %INCLUDE "envother.asm"             ; Validate remaining forms and operand combinations.
    %INCLUDE "enbasic.asm"              ; Dispatch instruction families and encode basic forms.
    %INCLUDE "enload.asm"               ; Encode register and memory load forms.
    %INCLUDE "enops.asm"                ; Encode I/O, arithmetic, bit and branch forms.
    %INCLUDE "entables.asm"             ; Share byte writers, tables and encoder workspace.
