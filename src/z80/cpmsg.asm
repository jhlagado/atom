; Atom diagnostic messages for CP/M. Generated from
; src/host/diagnostics.mjs by npm run build.
; Edit the messages there and rebuild.
;
; msgIdx holds one sentence number per message number. msgText holds
; the sentences in order, each ended by 0. Bytes 1, 2 and 3 inside a
; sentence stand for the symbol name, the signed value and the related
; line.

msgNum      EQU     80                                                          ; Message numbers in msgIdx.
msgOver     EQU     12                                                          ; The stack-overflow message.

msgIdx: ; Map each diagnostic number to its stored sentence.
    DB   0,1,2,3,4,5,6,7,8,9,10,11,12,0,13,14                                   ; Sentence indices for messages 0-15.
    DB   15,16,17,18,19,0,9,20,21,0,22,0,23,24,25,26                            ; Sentence indices for messages 16-31.
    DB   27,28,0,0,0,29,30,31,32,33,34,0,0,0,0,0                                ; Sentence indices for messages 32-47.
    DB   0,35,36,37,38,39,40,41,42,43,0,0,44,0,45,34                            ; Sentence indices for messages 48-63.
    DB   0,46,0,47,43,48,49,50,51,52,53,54,55,56,57,58                          ; Sentence indices for messages 64-79.
msgText: ; Zero-terminated sentences with argument marker bytes.
    DB   "internal error in Atom; please report it",0                           ; Diagnostic sentence 0.
    DB   "undefined symbol ",1,0                                                ; Diagnostic sentence 1.
    DB   "could not write the output",0                                         ; Diagnostic sentence 2.
    DB   "invalid build description",0                                          ; Diagnostic sentence 3.
    DB   "expected a label, instruction or directive",0                         ; Diagnostic sentence 4.
    DB   "unknown instruction or directive",0                                   ; Diagnostic sentence 5.
    DB   "unexpected text after the operands",0                                 ; Diagnostic sentence 6.
    DB   "strings are only allowed in DB",0                                     ; Diagnostic sentence 7.
    DB   "expected a quoted string",0                                           ; Diagnostic sentence 8.
    DB   "% directive is not allowed here",0                                    ; Diagnostic sentence 9.
    DB   "relative jump to ",1," is out of range (offset ",2,"); ",1            ; Diagnostic sentence 10.
    DB   " is on line ",3,0                                                     ; Continue diagnostic sentence 10.
    DB   "value of ",1," (",2,") is out of range for this operand",0            ; Diagnostic sentence 11.
    DB   "stack overflow",0                                                     ; Diagnostic sentence 12.
    DB   "invalid character",0                                                  ; Diagnostic sentence 13.
    DB   "name is longer than 8 characters",0                                   ; Diagnostic sentence 14.
    DB   "malformed number",0                                                   ; Diagnostic sentence 15.
    DB   "number does not fit in 16 bits",0                                     ; Diagnostic sentence 16.
    DB   "unterminated string",0                                                ; Diagnostic sentence 17.
    DB   "unsupported escape sequence",0                                        ; Diagnostic sentence 18.
    DB   "string is too long",0                                                 ; Diagnostic sentence 19.
    DB   "unterminated character constant",0                                    ; Diagnostic sentence 20.
    DB   "invalid character constant",0                                         ; Diagnostic sentence 21.
    DB   "value uses a symbol that is not defined yet",0                        ; Diagnostic sentence 22.
    DB   "expected a value",0                                                   ; Diagnostic sentence 23.
    DB   "missing closing parenthesis",0                                        ; Diagnostic sentence 24.
    DB   "division by zero",0                                                   ; Diagnostic sentence 25.
    DB   "value is out of range",0                                              ; Diagnostic sentence 26.
    DB   "a forward reference here must be one symbol plus or minus a "         ; Diagnostic sentence 27.
    DB   "small number",0                                                       ; Continue diagnostic sentence 27.
    DB   "expression is too complex",0                                          ; Diagnostic sentence 28.
    DB   "symbol not found",0                                                   ; Diagnostic sentence 29.
    DB   "symbol is already defined",0                                          ; Diagnostic sentence 30.
    DB   "too many symbols",0                                                   ; Diagnostic sentence 31.
    DB   "private label used before any global label",0                         ; Diagnostic sentence 32.
    DB   "private label ",1," is not defined before this global label",0        ; Diagnostic sentence 33.
    DB   "too many forward references",0                                        ; Diagnostic sentence 34.
    DB   "expected an instruction",0                                            ; Diagnostic sentence 35.
    DB   "unknown instruction",0                                                ; Diagnostic sentence 36.
    DB   "expected an operand",0                                                ; Diagnostic sentence 37.
    DB   "this operand cannot be used in brackets",0                            ; Diagnostic sentence 38.
    DB   "expected a comma or the end of the line",0                            ; Diagnostic sentence 39.
    DB   "too many operands",0                                                  ; Diagnostic sentence 40.
    DB   "operands are not valid for this instruction",0                        ; Diagnostic sentence 41.
    DB   "value is out of range for this operand",0                             ; Diagnostic sentence 42.
    DB   "relative jump is out of range (offset ",2,")",0                       ; Diagnostic sentence 43.
    DB   "this operand cannot refer to a symbol defined later",0                ; Diagnostic sentence 44.
    DB   "too many forward references in one instruction",0                     ; Diagnostic sentence 45.
    DB   "program does not fit in the output range",0                           ; Diagnostic sentence 46.
    DB   "value ",2," is out of range for this operand",0                       ; Diagnostic sentence 47.
    DB   "could not read the INCBIN file",0                                     ; Diagnostic sentence 48.
    DB   "INCBIN needs a byte count here",0                                     ; Diagnostic sentence 49.
    DB   "INCBIN count is larger than the file",0                               ; Diagnostic sentence 50.
    DB   "invalid source directive",0                                           ; Diagnostic sentence 51.
    DB   "invalid %INCLUDE",0                                                   ; Diagnostic sentence 52.
    DB   "include cycle",0                                                      ; Diagnostic sentence 53.
    DB   "includes are nested too deeply",0                                     ; Diagnostic sentence 54.
    DB   "too many source files",0                                              ; Diagnostic sentence 55.
    DB   "could not read the included file",0                                   ; Diagnostic sentence 56.
    DB   "source file is longer than 65,535 bytes",0                            ; Diagnostic sentence 57.
    DB   "could not read the source file",0                                     ; Diagnostic sentence 58.
msgEnd: ; First byte after the diagnostic text table.
