;=============================================================================
;  Parser
;=============================================================================
;
;  Parse a mnemonic and up to three operands into the instruction record
;  defined in insrec.asm. Each operand gets a class, such as a register,
;  memory form or value. An operand that names a later symbol becomes a
;  build reference, which the reference stage publishes once the instruction
;  is accepted.

    %INCLUDE "prscan.asm"               ; Instruction entry, token state and operand dispatch.
    %INCLUDE "proper.asm"               ; Expression, deferred and indirect operands.
    %INCLUDE "prforms.asm"              ; Normalise, classify and range-check operands.
    %INCLUDE "prdone.asm"               ; Commit the record or report a failure.
    %INCLUDE "prdata.asm"               ; Operand names and parser workspace.
