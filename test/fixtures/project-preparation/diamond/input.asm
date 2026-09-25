%IF DEBUG                         ; Select the active dependency using mixed case.
%include "hardware.asm"           ; Reuse the other side of the dependency diamond.
%ELSE                             ; Keep the missing file in an inactive branch.
%include "missing-inactive.asm"   ; Prove inactive includes are never resolved.
%endif                            ; End the conditional dependency header.
INPUT:                            ; Mark the input fixture's entry point.
    LD A,%1                       ; Exercise an Atom-style binary literal.
