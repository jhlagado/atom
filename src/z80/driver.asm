;=============================================================================
;  Driver
;=============================================================================
;
;  Run one complete assembly: check the build descriptor, reset every stage,
;  assemble each source part in order, check that every referenced symbol was
;  defined and commit the output. On failure, reduce the nested statuses to
;  one message number with its arguments.

    %INCLUDE "drbuild.asm"              ; Multipart execution and descriptor validation.
    %INCLUDE "drfinish.asm"             ; Final reference checks, diagnostics and storage.
