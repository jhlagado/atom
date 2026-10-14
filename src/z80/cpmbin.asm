; INCBIN: find, validate and stream binary includes.
; Included files share the same symbol scope.

    %INCLUDE "cpmbscan.asm"             ; Find active INCBIN statements before assembly.
    %INCLUDE "cpmbpars.asm"             ; Validate binary arguments and collect source metadata.
    %INCLUDE "cpmbsink.asm"             ; Filter binary directives and stream payload bytes.
