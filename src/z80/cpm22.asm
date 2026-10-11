; CP/M 2.2 adapter. Read these routine groups in assembly order.
; Includes preserve shared global labels and local-label scopes.

    %INCLUDE "cpmentry.asm"             ; Define memory layout, run assembly and report diagnostics.
    %INCLUDE "cpmcmd.asm"               ; Parse the command tail and validate CP/M filenames.
    %INCLUDE "cpmgraph.asm"             ; Order source dependencies and scan binary directives.
    %INCLUDE "cpmbpars.asm"             ; Validate binary arguments and collect source metadata.
    %INCLUDE "cpmbsink.asm"             ; Filter binary directives and stream payload bytes.
    %INCLUDE "cpmread.asm"              ; Resolve includes and read cached, filtered source bytes.
    %INCLUDE "cpmpub.asm"               ; Bind output services and publish or roll back files.
    %INCLUDE "cpmdata.asm"              ; Print console values and define resident data.
