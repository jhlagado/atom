%DEFINE DEBUG 1                   ; Choose the debug source layout for this build.
%IF DEBUG                        ; Select one layout before Atom sees the source.
%INCLUDE "layout.asm"            ; Load the debug origin, count and message.
%ELSE                            ; Use the release layout when DEBUG is zero.
%INCLUDE "release-layout.asm"    ; Load the release origin, count and message.
%ENDIF                           ; Finish the host-side conditional block.

START:                            ; Enter the assembled example here.
    LD B,COUNT                    ; Load the selected delay-loop count.
.LOOP:                            ; Repeat at this private label until B reaches zero.
    DJNZ .LOOP                    ; Decrement B and continue while it is nonzero.
    JR DONE                       ; Skip over the reserved working buffer.
BUFFER:                           ; Reserve four bytes of example storage.
    DS 2,0AAH                     ; Fill the first two bytes with AAH.
    DS 2                          ; Reserve two more bytes without emitting data.
DONE:                             ; Continue after the reserved storage.
    DW START,MESSAGE              ; Emit addresses for the entry point and message.
