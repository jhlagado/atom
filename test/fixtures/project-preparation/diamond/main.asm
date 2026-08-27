%DeFiNe DEBUG %1
%If DEBUG
%InClUdE "display.asm"
%else
%include "inactive.asm"
%endif
%include "input.asm"
MAIN:
    LD A,0FFFFH
%if 0
    CALL DeadCode
%else
    NOP
%endif
