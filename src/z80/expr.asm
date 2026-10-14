;=============================================================================
;  Expressions
;=============================================================================
;
;  Evaluate one expression with a value stack and an operator stack,
;  reducing by precedence. The result is a value, or for a symbol that is not
;  defined yet, that symbol plus a small addend. Arithmetic works on signed
;  24-bit values and checks the final word fits -32768..65535.

    %INCLUDE "exparse.asm"              ; Parse terms, operators and expression syntax.
    %INCLUDE "exreduce.asm"             ; Manage stacks and reduce parsed expressions.
    %INCLUDE "exarith.asm"              ; Evaluate arithmetic, bitwise and shift operations.
    %INCLUDE "exnum.asm"                ; Signed magnitudes, multiply, divide and diagnostics.
    %INCLUDE "exdata.asm"               ; Expression stacks and workspace.
