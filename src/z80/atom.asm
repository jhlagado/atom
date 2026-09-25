; ATOM NATIVE SOURCE ENTRY POINT.

    %INCLUDE "encoder.asm"      ; Pack names and recognise mnemonics.
    %INCLUDE "encform.asm"      ; Validate forms and lengths.
    %INCLUDE "encode.asm"       ; Emit validated instruction bytes.
    %INCLUDE "symbols.asm"      ; Manage symbols and pending references.
    %INCLUDE "token.asm"        ; Read and scan source lexemes.
    %INCLUDE "tokdisp.asm"      ; Dispatch tokens and publish records.
    %INCLUDE "expr.asm"         ; Parse expressions and deferred values.
    %INCLUDE "exprmath.asm"     ; Evaluate arithmetic and expression logic.
    %INCLUDE "patch.asm"        ; Locate and transform pending fields.
    %INCLUDE "parser.asm"       ; Parse mnemonic and operand syntax.
    %INCLUDE "forms.asm"        ; Select and validate instruction forms.
    %INCLUDE "refs.asm"         ; Publish references and commit records.
    %INCLUDE "output.asm"       ; Emit image bytes and resolved patches.
    %INCLUDE "stmts.asm"        ; Assemble labels, directives and code.
    %INCLUDE "driver.asm"       ; Validate requests and assemble all parts.
    %INCLUDE "host.asm"         ; Define services required from the host.
