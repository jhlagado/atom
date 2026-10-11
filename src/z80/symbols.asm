; symbols.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "symdefs.asm"              ; Symbol lookup, definitions and private scope.
    %INCLUDE "sympend.asm"              ; Pending records, arena checks and symbol storage.
