; ATOM NATIVE SOURCE ENTRY POINT.

    %INCLUDE "encoder.asm"               ; Recognize mnemonics, validate forms and emit opcodes.
    %INCLUDE "symbols.asm"               ; Store symbols and track unresolved references.
    %INCLUDE "token.asm"                 ; Read source bytes and scan complete lexemes.
    %INCLUDE "tokdisp.asm"               ; Classify lexemes and publish token records.
    %INCLUDE "expr.asm"                  ; Parse expressions and manage deferred values.
    %INCLUDE "exprmath.asm"              ; Evaluate the arithmetic and logical operators.
    %INCLUDE "patch.asm"                 ; Locate encoded fields that need later patching.
    %INCLUDE "parser.asm"                ; Parse mnemonic and operand syntax.
    %INCLUDE "forms.asm"                 ; Normalize, validate and publish instruction records.
    %INCLUDE "output.asm"                ; Submit image bytes and resolved patches to host services.
    %INCLUDE "stmts.asm"                 ; Assemble labels, directives and instructions.
    %INCLUDE "driver.asm"                ; Validate a build request and drive every source part.
    %INCLUDE "host.asm"                  ; Declare the platform services used by the core.
