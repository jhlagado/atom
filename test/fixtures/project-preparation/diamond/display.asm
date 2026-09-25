%if DEBUG                    ; Exercise case-insensitive conditional syntax.
%include "hardware.asm"      ; Form one side of the dependency diamond.
%endif                       ; End the active conditional header.
DISPLAY:                     ; Mark the display fixture's entry point.
    LD A,01110111B            ; Exercise an Intel-style binary literal.
