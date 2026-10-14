;=============================================================================
;  Statements
;=============================================================================
;
;  Read one source part line by line. A line holds a label, an EQU, a
;  directive or an instruction. Directives reserve, fill and align space or
;  emit data. Instructions go to the parser and encoder, and their bytes to
;  the output layer.

    %INCLUDE "stparse.asm"              ; Statement dispatch, equates and scalar data lists.
    %INCLUDE "ststring.asm"             ; String counting, decoding and emission.
    %INCLUDE "stdata.asm"               ; Reservations, alignment, diagnostics and storage.
