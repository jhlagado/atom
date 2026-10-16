; Memory for the Node host's front end. The front end's workspace sits above
; the pending arena, in RAM the host does not otherwise use.

feRamLo     EQU     $D000               ; The source front end's workspace.
incMax      EQU     8                   ; Deepest include nesting.
