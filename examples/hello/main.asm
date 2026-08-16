%define DEBUG 1
%if DEBUG
%include "layout.asm"
%else
%include "release-layout.asm"
%endif

Start:
    ld b,Count
_Loop:
    djnz _Loop
    jr Done
Buffer:
    DS 2,0AAH
    DS 2
Done:
    DW Start,Message
