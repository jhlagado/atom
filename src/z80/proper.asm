;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Evaluate before publishing symbols. BC gives '$' its instruction
; address. Resolved values go directly to the selected value slot. Unresolved
; values first become private build-reference records.

PR_EVAL: ; Evaluate at the instruction address with deferred symbols.
    LD   BC,(PR_IADR)                   ; Supply `$` with the instruction address.
    CALL EX_DEFER                       ; Parse with deferred symbol publication.
    JR   C,PR_FEXPR                     ; Translate an expression diagnostic.
    CP   EX_PEND                        ; Did a symbol remain unresolved?
    JR   Z,PR_DEFER                     ; Build a private deferred reference.

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS DE,SIGN,PARITY,HALFCARRY,A
; Store the concrete word in HL at the selected operand value pointer.

PR_STORE: ; Store a resolved or placeholder word in the selected value slot.
    LD   DE,(PR_VPTR)                   ; Load the selected value-slot address.
    LD   A,L                            ; Take the value's low byte.
    LD   (DE),A                         ; Store it in little-endian order.
    INC  DE                             ; Advance to the high byte.
    LD   A,H                            ; Take the value's high byte.
    LD   (DE),A                         ; Complete the stored word.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the selected class slot.

;@ROUTINE IN IX,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX
; Append a thirteen-byte build reference. IX points at the packed key. HL
; carries its signed addend. Record operand index, transform
; and the evaluator's retained symbol position. The unresolved mask prevents
; concrete range checks from inspecting the placeholder zero value.

PR_DEFER: ; Build a private reference before any symbol-arena publication.
    LD   (PR_ADDW),HL                   ; Save the expression's signed addend.
    LD   A,(PR_BRCNT)                   ; Read the private reference count.
    CP   PR_RCAP                        ; Is another build record available?
    JR   NC,.FULL                       ; Diagnose the impossible third reference.
    CALL PR_BRADR                       ; Address the next build-reference record.
    PUSH IX                             ; Move the expression key pointer to HL.
    POP  HL                             ; HL now addresses the packed symbol key.
    LD   BC,6                           ; A packed symbol key occupies six bytes.
    LDIR                                ; Copy the key and advance DE after it.
    LD   HL,(PR_ADDW)                   ; Recover the signed expression addend.
    LD   A,L                            ; References retain its low byte only.
    LD   (DE),A                         ; Append the signed-byte addend.
    INC  DE                             ; Advance to the operand index.
    LD   A,(PR_OPCNT)                   ; Identify the current operand slot.
    LD   (DE),A                         ; Append that operand index.
    INC  DE                             ; Advance to the transform kind.
    LD   A,(EX_RFORM)                   ; Read the deferred transform.
    LD   (DE),A                         ; Save it for resolution.
    INC  DE                             ; Advance to the provisional patch offset.

; Retain the expression transform as provisional kind. The byte offset
; remains zero until validation and PT_FIELD identify the encoded field.

    XOR  A                              ; The patch field is not known yet.
    LD   (DE),A                         ; Initialise its byte offset to zero.
    INC  DE                             ; Advance to the source-part ordinal.
    LD   A,(EX_SPART)                   ; Read the missing symbol's source part.
    LD   (DE),A                         ; Append it for an exact diagnostic.
    INC  DE                             ; Advance to the source offset.
    LD   HL,(EX_SOFF)                   ; Read the missing symbol's source offset.
    LD   A,L                            ; Take its low byte.
    LD   (DE),A                         ; Store the offset little-endian.
    INC  DE                             ; Advance to the high byte.
    LD   A,H                            ; Take the source offset's high byte.
    LD   (DE),A                         ; Complete the build-reference record.
    LD   A,(PR_OPCNT)                   ; Recover the unresolved operand index.
    CALL PR_MASK                        ; Convert it to a one-bit mask.
    LD   HL,PR_UMASK                    ; Address the unresolved-operand mask.
    OR   (HL)                           ; Preserve earlier unresolved operands.
    LD   (HL),A                         ; Mark this operand unresolved.
    LD   HL,PR_BRCNT                    ; Address the build-reference count.
    INC  (HL)                           ; Publish the new private record.

; Store a zero placeholder in the instruction record. Encoding happens before
; the final value exists and the pending patch will replace its field later.

    LD   HL,0                           ; Use zero until the symbol resolves.
    JR   PR_STORE                       ; Store zero placeholder.
.FULL: ; Reject a third deferred field at its symbol position.

; The Z80 form census proves that no valid instruction needs more than two
; deferred fields. Reaching a third is a diagnosed parser-capacity failure.

    LD   A,PR_SRCAP                     ; Select reference-capacity status.
    JP   PR_FMISS                       ; Fail at the unresolved symbol position.

;@ROUTINE IN A OUT DE CLOBBERS HL,A,F
; Return the address of build-reference A in DE. Each record is thirteen
; bytes. Capacity two needs only one conditional add.

PR_BRADR: ; Address one of the two thirteen-byte private references.
    LD   DE,PR_BREFS                    ; Begin at build-reference record zero.
    OR   A                              ; Is record zero requested?
    RET  Z                              ; Return its base directly.
    LD   HL,PR_BRB                      ; Load the thirteen-byte record stride.
    ADD  HL,DE                          ; Advance to build-reference record one.
    EX   DE,HL                          ; Return its address in DE.
    RET                                 ; A cannot exceed one at this call site.
PR_FEXPR: ; Copy an expression diagnostic into the parser error fields.

; Preserve the nested expression status and exact expression error location,
; then return the parser's expression category.

    LD   (PR_EXERR),A                   ; Retain the expression subsystem status.
    LD   A,(EX_EPART)                   ; Copy its source-part ordinal.
    LD   (PR_EPART),A                   ; Publish the parser error part.
    LD   HL,(EX_EOFF)                   ; Copy its source byte offset.
    LD   (PR_EOFF),HL                   ; Publish the parser error offset.
    LD   A,PR_SEXPR                     ; Select the parser expression category.
    LD   (PR_ESTAT),A                   ; Retain the public parser status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return both category and nested detail.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise short operand words such as registers and conditions. Pack
; the token case-insensitively and compare exact RADIX-40 values.
; Names of four or more characters cannot be operand words and fall through to
; expression parsing as symbols.

PR_MATCH: ; Search the packed register and condition word table.
    CALL TK_TEXT                        ; Load the current name text and length.
    CP   4                              ; Operand words have at most three chars.
    JR   NC,.NOMATCH                    ; Longer names can only be symbols.
    LD   DE,PR_OWKEY                    ; Select the temporary packed-key buffer.
    CALL EN_R40PK                       ; Pack the name case-insensitively.
    JR   C,.NOMATCH                     ; Treat other names as symbols.
    LD   DE,(PR_OWKEY)                  ; Load the packed operand word.
    LD   HL,PR_OWTAB                    ; Begin the exact operand-word table.
    LD   B,PR_OWCNT                     ; Scan every table entry at most once.
.LOOP: ; Compare one packed word and its provisional operand class.

; Each table entry is packed word followed by provisional operand class.

    LD   A,(HL)                         ; Read the packed low byte.
    CP   E                              ; Compare it with the source key.
    INC  HL                             ; Advance to the packed high byte.
    JR   NZ,.SKIP                       ; Skip after a low-byte mismatch.
    LD   A,(HL)                         ; Read the packed high byte.
    CP   D                              ; Compare it with the source key.
    JR   Z,.FOUND                       ; Both bytes identify the operand word.
.SKIP: ; Skip the class byte after a packed-key mismatch.
    INC  HL                             ; Advance beyond the packed high byte.
    INC  HL                             ; Skip the associated operand class.
    DJNZ .LOOP                          ; Continue through the fixed table.
.NOMATCH: ; Return a failed fixed-word probe for expression fallback.
    LD   A,PR_SBADO                     ; Select unknown-operand status.
    JP   PR_FHERE                       ; Fail at the current token's position.
.FOUND: ; Return the class associated with the matched operand word.
    INC  HL                             ; Advance from the high byte to its class.
    LD   A,(HL)                         ; Return the provisional operand class.
    OR   A                              ; Clear carry for a recognised word.
    RET                                 ; Leave the word token unconsumed.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a parenthesised operand after the opening '(' has been seen. The first
; inner token distinguishes a concrete memory/port word from an absolute
; expression or an IX/IY displacement expression.

PR_PAREN: ; Parse indirect memory, port or indexed operand syntax.
    CALL PR_NEXT                        ; Consume '(' and fetch its first token.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the first inner token.
    CALL PR_ISEXP                       ; Does it begin a numeric expression?
    JR   NC,.EXPR                       ; Parse the parenthesised expression.
    CP   TK_LPAR                        ; Expressions may start with another '('.
    JR   Z,.EXPR                        ; Delegate nested parentheses to EX_DEFER.
    CP   TK_NAME                        ; Fixed indirect bases are name tokens.
    JP   NZ,PR_FNOOP                    ; Diagnose any other operand starter.
    CALL PR_MATCH                       ; Recognise C, BC, DE, HL, SP, IX or IY.
    JR   C,.EXPR                        ; Treat any other name as a symbol.

; Save the provisional base class before consuming its token.

    LD   (PR_BASE),A                    ; Preserve the base across token advance.
    CALL PR_NEXT                        ; Consume the base name.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(PR_BASE)                    ; Recover the provisional base class.
    CP   PR_GC                          ; Was the ambiguous word C selected?
    JR   Z,.PORTC                       ; Inside parentheses C means port C.
    CP   EN_BC                          ; Was register pair BC selected?
    JR   Z,.MEMBC                       ; Convert it to indirect-memory BC.
    CP   EN_DE                          ; Was register pair DE selected?
    JR   Z,.MEMDE                       ; Convert it to indirect-memory DE.
    CP   EN_HL                          ; Was register pair HL selected?
    JR   Z,.MEMHL                       ; Convert it to indirect-memory HL.
    CP   EN_SP                          ; Was stack pointer SP selected?
    JR   Z,.MEMSP                       ; Convert it to indirect-memory SP.
    CP   EN_IX                          ; Was index register IX selected?
    JR   Z,.MEMIX                       ; Parse its optional displacement.
    CP   EN_IY                          ; Was index register IY selected?
    JR   Z,.MEMIY                       ; Parse its optional displacement.
    JP   PR_FBADO                       ; No other operand word may be indirect.
.EXPR: ; Evaluate an absolute memory or immediate port expression.

; A parenthesised expression becomes a generic memory number. IN and OUT later
; reinterpret this class as an eight-bit immediate port. Other forms use an
; absolute-memory word.

    CALL PR_EVAL                        ; Evaluate or defer the inner expression.
    RET  C                              ; Preserve its exact diagnostic.
    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   (HL),PR_GPNUM                  ; Mark a generic parenthesised number.
    JR   .CLOSE                         ; Require and consume the closing ')'.
.PORTC: ; Select indirect port C rather than ordinary register C.

; `(C)` is the indirect port class, distinct from ordinary register C.

    LD   A,EN_PORTC                     ; Select the indirect port-C class.
    JR   .FIXED                         ; Store it and require ')'.
.MEMBC: ; Select memory addressed by register pair BC.
    LD   A,EN_MEMBC                     ; Select the indirect BC class.
    JR   .FIXED                         ; Store it and require ')'.
.MEMDE: ; Select memory addressed by register pair DE.
    LD   A,EN_MEMDE                     ; Select the indirect DE class.
    JR   .FIXED                         ; Store it and require ')'.
.MEMHL: ; Select memory addressed by register pair HL.
    LD   A,EN_MEMHL                     ; Select the indirect HL class.
    JR   .FIXED                         ; Store it and require ')'.
.MEMSP: ; Select memory addressed by the stack pointer.
    LD   A,EN_MEMSP                     ; Select the indirect SP class.
.FIXED: ; Store a fixed indirect class before checking its closing bracket.

; Store the fixed indirect class and require the closing parenthesis.

    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   (HL),A                         ; Store the fixed indirect class.
    JR   .CLOSE                         ; Require and consume the closing ')'.
.MEMIX: ; Retain the IX classes used by JP and indexed memory forms.

; B holds the JP (IX) memory class. PR_IXIY is the ordinary indexed
; class used for displacement-bearing forms and the zero-displacement alias.

    LD   B,EN_MEMIX                     ; Retain the dedicated JP (IX) class.
    LD   A,EN_IIX                       ; Select ordinary indexed-memory IX.
    LD   (PR_IXIY),A                    ; Retain it across displacement parsing.
    JR   .INDEX                         ; Inspect the token after IX.
.MEMIY: ; Retain the IY classes used by JP and indexed memory forms.
    LD   B,EN_MEMIY                     ; Retain the dedicated JP (IY) class.
    LD   A,EN_IIY                       ; Select ordinary indexed-memory IY.
    LD   (PR_IXIY),A                    ; Retain it across displacement parsing.
.INDEX: ; Choose an explicit displacement or an implicit zero offset.

; A closing ')' is the implicit displacement-zero form. Otherwise only '+' or
; '-' may introduce the displacement expression.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token after IX or IY.
    CP   TK_RPAR                        ; Is the displacement omitted?
    JR   Z,.NODISP                      ; Use the implicit zero displacement.
    CP   TK_PLUS                        ; A plus may introduce the displacement.
    JR   Z,.DISP                        ; Parse it as an expression.
    CP   TK_MINUS                       ; A minus may also introduce it.
    JP   NZ,PR_FNODL                    ; Reject every other delimiter.
.DISP: ; Evaluate the signed IX/IY displacement expression.
    CALL PR_EVAL                        ; Evaluate the signed displacement.
    RET  C                              ; Preserve its exact diagnostic.
    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   A,(PR_IXIY)                    ; Recover the IX/IY indexed class.
    LD   (HL),A                         ; Store the displacement-bearing class.
    JR   .CLOSE                         ; Require and consume the closing ')'.
.NODISP: ; Choose JP's indirect class or ordinary indexed displacement zero.

; JP (IX/IY) uses the encoder's dedicated memory class. Other instructions use
; the ordinary indexed class with the already-zero value slot.

    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   A,(PR_REC+EN_MNEM)             ; Read the current mnemonic ordinal.
    CP   AT_MJP                         ; Does JP require its dedicated class?
    LD   A,B                            ; Prepare the JP (IX/IY) class.
    JR   Z,.STORE                       ; Keep it only for JP.
    LD   A,(PR_IXIY)                    ; Other forms use index offset zero.
.STORE: ; Store the selected indirect class and consume the close.
    LD   (HL),A                         ; Publish the final indirect class.
    JP   PR_NEXT                        ; Consume ')' and fetch the next token.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Consume the closing ')' after an expression or fixed indirect form.

.CLOSE: ; Require the closing parenthesis left by inner parsing.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the unconsumed delimiter.
    CP   TK_RPAR                        ; Require a closing parenthesis.
    JP   NZ,PR_FNODL                    ; Diagnose any other delimiter.
    JP   PR_NEXT                        ; Consume ')' and fetch the next token.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Copy the tokenizer's numeric word to the selected value slot. This retained
; helper has no caller in the current parser path.

PR_TKVAL: ; Retained helper for copying a tokenizer numeric word.
    LD   HL,(TK_REC+TK_RVAL)            ; Load the tokenizer's numeric value.
    JP   PR_STORE                       ; Store it in the selected operand slot.
