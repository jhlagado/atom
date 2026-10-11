; token.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "tokcore.asm"              ; Source reads, token publication and character classes.
    %INCLUDE "toknum.asm"               ; Names and numeric token scanning.
    %INCLUDE "tokstr.asm"               ; Quoted strings, escapes and comments.
