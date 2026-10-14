;=============================================================================
;  Forward references
;=============================================================================
;
;  A single pass meets symbols before they are defined. The parser leaves a
;  placeholder and a build reference for each one. This stage finds the field
;  each reference patches, checks there is room in the pending arena and,
;  once the instruction's bytes are accepted, queues one pending reference
;  per field. The output layer resolves them when the symbol is defined.

    %INCLUDE "fixfield.asm"             ; Locate and transform pending fields.
    %INCLUDE "refbind.asm"              ; Deferred symbol binding and allocation preflight.
    %INCLUDE "refpend.asm"              ; Pending publication, diagnostics and parser storage.
