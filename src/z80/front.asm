; The source front end: includes, conditions and definitions, applied as the
; stream of source bytes reaches them. It sits between the core's tkOpen and
; tkRead and the host's file services, so every platform reads its source
; the same way.

    %INCLUDE "frinc.asm"                ; Supply parts and follow includes as they are reached.
    %INCLUDE "ppctrl.asm"               ; Apply % directives at the end of their lines.
    %INCLUDE "ppvalue.asm"              ; Filter source bytes and evaluate definitions.

feEnd: ; Exclusive end of the front end's code and tables.
