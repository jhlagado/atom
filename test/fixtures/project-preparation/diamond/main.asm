%DeFiNe DEBUG %1                ; Exercise case folding and an Atom binary value.
%If DEBUG                      ; Select the active dependency branch.
%InClUdE "display.asm"         ; Include the display side of the diamond.
%else                          ; Retain an inactive alternative for masking tests.
%include "inactive.asm"        ; Prove inactive dependencies are not opened.
%endif                         ; Finish the first conditional block.
%include "input.asm"           ; Include the input side of the diamond.
MAIN:                           ; Mark the fixture's assembled entry point.
    LD A,0FFFFH                 ; Exercise an Intel-style hexadecimal literal.
%if 0                          ; Begin an inactive body within the source proper.
    CALL DeadCode               ; Prove inactive instructions are masked completely.
%else                          ; Select the live instruction instead.
    NOP                         ; Emit the fixture's live body byte.
%endif                         ; Finish the body conditional.
