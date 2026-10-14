; Atom's platform-neutral core, in the order a statement flows through it.
;
; The tokenizer turns source bytes into tokens. Names are packed into
; RADIX-40 words, which the symbol table and the mnemonic recogniser both use.
; The expression evaluator reduces operands to values, or to one symbol plus
; a small addend when the symbol is not defined yet. The parser builds an
; instruction record, the encoder turns it into bytes and the output layer
; emits them. A value that is not known yet becomes a pending reference,
; which the output layer patches when its symbol is defined. The statement
; layer drives all of this one line at a time, and the driver runs every
; source part and the final checks.
;
; A platform root includes this file, then its own services.

    %INCLUDE "names.asm"                ; Pack names and recognise mnemonics.
    %INCLUDE "token.asm"                ; Read and scan source lexemes.
    %INCLUDE "symbols.asm"              ; Manage symbols and pending references.
    %INCLUDE "expr.asm"                 ; Parse and evaluate expressions.
    %INCLUDE "insrec.asm"               ; Define the parsed-instruction record.
    %INCLUDE "parser.asm"               ; Parse mnemonic and operand syntax.
    %INCLUDE "encoder.asm"              ; Validate forms and encode instruction bytes.
    %INCLUDE "refs.asm"                 ; Record and resolve forward references.
    %INCLUDE "output.asm"               ; Emit image bytes and resolved patches.
    %INCLUDE "stmts.asm"                ; Assemble labels, directives and code.
    %INCLUDE "driver.asm"               ; Validate requests and assemble all parts.
