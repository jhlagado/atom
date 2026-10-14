;=============================================================================
;  Symbols and the pending-reference arena
;=============================================================================
;
;  Keep every symbol as an eight-byte record: the packed name and a value
;  word. Globals grow up from one end of the arena and private labels grow
;  down from the other, so a new global label can drop the old private scope
;  at once. A second arena holds pending references, each a description of
;  bytes to patch once its symbol is defined.

    %INCLUDE "symdefs.asm"              ; Symbol lookup, definitions and private scope.
    %INCLUDE "sympend.asm"              ; Pending records, arena checks and symbol storage.
