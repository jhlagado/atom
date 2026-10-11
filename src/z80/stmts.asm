; stmts.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "stparse.asm"              ; Statement dispatch, equates and scalar data lists.
    %INCLUDE "ststring.asm"             ; String counting, decoding and emission.
    %INCLUDE "stdata.asm"               ; Reservations, alignment, diagnostics and storage.
