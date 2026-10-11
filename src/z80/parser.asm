; parser.asm groups its source in assembly order.
; Each included file continues the same native symbol scope.

    %INCLUDE "prscan.asm"               ; Instruction entry, token state and operand dispatch.
    %INCLUDE "proper.asm"               ; Expression, deferred and indirect operands.
