; ATOM NATIVE SOURCE ENTRY POINT.

    %INCLUDE "core.asm"                 ; Assemble the platform-neutral core.
    %INCLUDE "hostmap.asm"              ; Place the front end's workspace.
    %INCLUDE "front.asm"                ; Apply includes, conditions and definitions.
    %INCLUDE "host.asm"                 ; Define services required from the host.
