; refs.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "prbind.asm"               ; Deferred symbol binding and allocation preflight.
    %INCLUDE "prpatch.asm"              ; Pending publication, diagnostics and parser storage.
