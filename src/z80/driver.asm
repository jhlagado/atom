; driver.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "drbuild.asm"              ; Multipart execution and descriptor validation.
    %INCLUDE "drfinish.asm"             ; Final reference checks, diagnostics and storage.
