%IF DEBUG
%include "hardware.asm"
%ELSE
%include "missing-inactive.asm"
%endif
INPUT:
    LD A,%1
