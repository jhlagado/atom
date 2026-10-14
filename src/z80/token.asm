;=============================================================================
;  Tokenizer
;=============================================================================
;
;  Read source one byte at a time through tkRead and publish one token at a
;  time in tkRecord: a name, number, string, character, punctuation mark or
;  end of line. The tokenizer never sees a file. It reads a part ordinal and
;  a byte offset, so the host decides where the bytes come from.

    %INCLUDE "tokcore.asm"              ; Source reads, token publication and character classes.
    %INCLUDE "toknum.asm"               ; Names and numeric token scanning.
    %INCLUDE "tokstr.asm"               ; Quoted strings, escapes and comments.
    %INCLUDE "tokdisp.asm"              ; Dispatch tokens and publish records.
