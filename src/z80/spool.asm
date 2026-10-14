; Spool and replay: write Atom's output operations to NAME.$$B, then replay
; them into a COM, BIN or HEX file. This code follows the resident adapter.
; Included files share the same symbol scope.

    %INCLUDE "aso.asm"                  ; Spool Atom's operations to NAME.$$B.
    %INCLUDE "mat.asm"                  ; Replay the spool into COM, BIN or HEX.
    %INCLUDE "cpmhex.asm"               ; Write Intel HEX records.

asoEnd: ; Exclusive end of the spool and replay code.
