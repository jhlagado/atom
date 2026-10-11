; nobj.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "objread.asm"              ; Named-object requests and cached source reads.
    %INCLUDE "objwrite.asm"             ; Output writes, transaction callbacks and adapter storage.
