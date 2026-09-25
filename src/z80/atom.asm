; ATOM NATIVE SOURCE ENTRY POINT.

    %INCLUDE "encoder.asm"               ; Recognize mnemonics, validate forms and emit opcodes.
    %INCLUDE "symbols.asm"               ; Store symbols and track unresolved references.
    %INCLUDE "tokenizer.asm"             ; Read source bytes and scan complete lexemes.
    %INCLUDE "tokenizer-dispatch.asm"    ; Classify lexemes and publish token records.
    %INCLUDE "expression.asm"            ; Parse expressions and manage deferred values.
    %INCLUDE "expression-arithmetic.asm" ; Evaluate the arithmetic and logical operators.
    %INCLUDE "patch.asm"                 ; Locate encoded fields that need later patching.
    %INCLUDE "parser.asm"                ; Classify operands and build instruction records.
    %INCLUDE "output.asm"                ; Submit image bytes and resolved patches to host services.
    %INCLUDE "statements.asm"            ; Assemble labels, directives and instructions.
    %INCLUDE "driver.asm"                ; Validate a build request and drive every source part.
    %INCLUDE "host-services.asm"         ; Declare the platform services used by the core.
