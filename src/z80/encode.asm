; Instruction encoding.
; Included files share the same symbol scope.

    %INCLUDE "enbasic.asm"              ; Dispatch instruction families and encode basic forms.
    %INCLUDE "enload.asm"               ; Encode register and memory load forms.
    %INCLUDE "enops.asm"                ; Encode I/O, arithmetic, bit and branch forms.
    %INCLUDE "encommon.asm"             ; Share byte writers, tables and encoder workspace.
