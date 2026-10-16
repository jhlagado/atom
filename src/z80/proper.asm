;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Evaluate before publishing symbols. BC gives '$' its instruction
; address. Resolved values go directly to the selected value slot. Unresolved
; values first become private build-reference records.

prEval: ; Evaluate at the instruction address with deferred symbols.
    LD   BC,(prInsPC)                   ; Supply `$` with the instruction address.
    CALL exDefer                        ; Parse with deferred symbol publication.
    JR   C,prAtExpr                     ; Translate an expression diagnostic.
    CP   exPend                         ; Did a symbol remain unresolved?
    JR   Z,prDefer                      ; Build a private deferred reference.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS DE,SIGN,PARITY,HALFCARRY
; Store the concrete word in HL at the selected operand value pointer.

prStore: ; Store a resolved or placeholder word in the selected value slot.
    LD   DE,(prValPtr)                  ; Load the selected value-slot address.
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

prDefer: ; Build a private reference before any symbol-arena publication.
    LD   (prAddend),HL                  ; Save the expression's signed addend.
    LD   A,(prRawCnt)                   ; Read the private reference count.
    CP   prRefCap                       ; Is another build record available?
    JR   NC,.full                       ; Diagnose the impossible third reference.
    CALL prRawPtr                       ; Address the next build-reference record.
    PUSH IX                             ; Move the expression key pointer to HL.
    POP  HL                             ; HL now addresses the packed symbol key.
    LD   BC,6                           ; A packed symbol key occupies six bytes.
    LDIR                                ; Copy the key and advance DE after it.
    LD   HL,(prAddend)                  ; Recover the signed expression addend.
    LD   A,L                            ; References retain its low byte only.
    LD   (DE),A                         ; Append the signed-byte addend.
    INC  DE                             ; Advance to the operand index.
    LD   A,(prOpCnt)                    ; Identify the current operand slot.
    LD   (DE),A                         ; Append that operand index.
    INC  DE                             ; Advance to the transform kind.
    LD   A,(exRForm)                    ; Read the deferred transform.
    LD   (DE),A                         ; Save it for resolution.
    INC  DE                             ; Advance to the provisional patch offset.

; Retain the expression transform as provisional kind. The byte offset
; remains zero until validation and fixField identify the encoded field.

    XOR  A                              ; The patch field is not known yet.
    LD   (DE),A                         ; Initialise its byte offset to zero.
    INC  DE                             ; Advance to the source-part ordinal.
    LD   A,(exSrcPos)                   ; Read the missing symbol's source part.
    LD   (DE),A                         ; Append it for an exact diagnostic.
    INC  DE                             ; Advance to the source offset.
    LD   HL,(exSrcOff)                  ; Read the missing symbol's source offset.
    LD   A,L                            ; Take its low byte.
    LD   (DE),A                         ; Store the offset little-endian.
    INC  DE                             ; Advance to the high byte.
    LD   A,H                            ; Take the source offset's high byte.
    LD   (DE),A                         ; Store it.
    INC  DE                             ; Advance to the line.
    LD   HL,(exSrcLn)                   ; Read the missing symbol's line.
    LD   A,L                            ; Take its low byte.
    LD   (DE),A                         ; Store the line little-endian.
    INC  DE                             ; Advance to the high byte.
    LD   A,H                            ; Take the line's high byte.
    LD   (DE),A                         ; Complete the build-reference record.
    LD   A,(prOpCnt)                    ; Recover the unresolved operand index.
    CALL prOpBit                        ; Convert it to a one-bit mask.
    LD   HL,prAwait                     ; Address the unresolved-operand mask.
    OR   (HL)                           ; Preserve earlier unresolved operands.
    LD   (HL),A                         ; Mark this operand unresolved.
    LD   HL,prRawCnt                    ; Address the build-reference count.
    INC  (HL)                           ; Publish the new private record.

; Store a zero placeholder in the instruction record. Encoding happens before
; the final value exists and the pending patch will replace its field later.

    LD   HL,0                           ; Use zero until the symbol resolves.
    JR   prStore                        ; Store zero placeholder.
.full: ; Reject a third deferred field at its symbol position.

; The Z80 form census proves that no valid instruction needs more than two
; deferred fields. Reaching a third is a diagnosed parser-capacity failure.

    LD   A,prRefMax                     ; Select reference-capacity status.
    JP   prAtSym                        ; Fail at the unresolved symbol position.

;@ROUTINE IN A OUT DE CLOBBERS HL,A,F
; Return the address of build-reference A in DE. Each record is thirteen
; bytes. Capacity two needs only one conditional add.

prRawPtr: ; Address one of the two fifteen-byte private references.
    LD   DE,prRawRef                    ; Begin at build-reference record zero.
    OR   A                              ; Is record zero requested?
    RET  Z                              ; Return its base directly.
    LD   HL,prRawLen                    ; Load the fifteen-byte record stride.
    ADD  HL,DE                          ; Advance to build-reference record one.
    EX   DE,HL                          ; Return its address in DE.
    RET                                 ; A cannot exceed one at this call site.
prAtExpr: ; Copy an expression diagnostic into the parser error fields.

; Preserve the nested expression status and exact expression error location,
; then return the parser's expression category.

    LD   (prExDet),A                    ; Retain the expression subsystem status.
    LD   A,(exErrPos)                   ; Copy its source-part ordinal.
    LD   (prErrSrc),A                   ; Publish the parser error part.
    LD   HL,(exErrOff)                  ; Copy its source byte offset.
    LD   (prErrOff),HL                  ; Publish the parser error offset.
    LD   A,prExErr                      ; Select the parser expression category.
    LD   (prStatus),A                   ; Retain the public parser status.
    SCF                                 ; Mark the parse as failed.
    RET                                 ; Return both category and nested detail.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise short operand words such as registers and conditions. Pack
; the token case-insensitively and compare exact RADIX-40 values.
; Names of four or more characters cannot be operand words and fall through to
; expression parsing as symbols.

prMatch: ; Search the packed register and condition word table.
    CALL tkText                         ; Load the current name text and length.
    CP   4                              ; Operand words have at most three chars.
    JR   NC,.noMatch                    ; Longer names can only be symbols.
    LD   DE,prKeyBuf                    ; Select the temporary packed-key buffer.
    CALL nmPack                         ; Pack the name case-insensitively.
    JR   C,.noMatch                     ; Treat other names as symbols.
    LD   DE,(prKeyBuf)                  ; Load the packed operand word.
    LD   HL,prKeyTab                    ; Begin the exact operand-word table.
    LD   B,prKeyCnt                     ; Scan every table entry at most once.
.loop: ; Compare one packed word and its provisional operand class.

; Each table entry is packed word followed by provisional operand class.

    LD   A,(HL)                         ; Read the packed low byte.
    CP   E                              ; Compare it with the source key.
    INC  HL                             ; Advance to the packed high byte.
    JR   NZ,.skip                       ; Skip after a low-byte mismatch.
    LD   A,(HL)                         ; Read the packed high byte.
    CP   D                              ; Compare it with the source key.
    JR   Z,.found                       ; Both bytes identify the operand word.
.skip: ; Skip the class byte after a packed-key mismatch.
    INC  HL                             ; Advance beyond the packed high byte.
    INC  HL                             ; Skip the associated operand class.
    DJNZ .loop                          ; Continue through the fixed table.
.noMatch: ; Return a failed fixed-word probe for expression fallback.
    LD   A,prBadOp                      ; Select unknown-operand status.
    JP   prAtTok                        ; Fail at the current token's position.
.found: ; Return the class associated with the matched operand word.
    INC  HL                             ; Advance from the high byte to its class.
    LD   A,(HL)                         ; Return the provisional operand class.
    OR   A                              ; Clear carry for a recognised word.
    RET                                 ; Leave the word token unconsumed.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a parenthesised operand after the opening '(' has been seen. The first
; inner token distinguishes a concrete memory/port word from an absolute
; expression or an IX/IY displacement expression.

prParen: ; Parse indirect memory, port or indexed operand syntax.
    CALL prNext                         ; Consume '(' and fetch its first token.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the first inner token.
    CALL prIsExpr                       ; Does it begin a numeric expression?
    JR   NC,.expr                       ; Parse the parenthesised expression.
    CP   tkLParen                       ; Expressions may start with another '('.
    JR   Z,.expr                        ; Delegate nested parentheses to exDefer.
    CP   tkName                         ; Fixed indirect bases are name tokens.
    JP   NZ,prLackOp                    ; Diagnose any other operand starter.
    CALL prMatch                        ; Recognise C, BC, DE, HL, SP, IX or IY.
    JR   C,.expr                        ; Treat any other name as a symbol.

; Save the provisional base class before consuming its token.

    LD   (prBase),A                     ; Preserve the base across token advance.
    CALL prNext                         ; Consume the base name.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(prBase)                     ; Recover the provisional base class.
    CP   prAnyC                         ; Was the ambiguous word C selected?
    JR   Z,.portC                       ; Inside parentheses C means port C.
    CP   enRegBC                        ; Was register pair BC selected?
    JR   Z,.memBc                       ; Convert it to indirect-memory BC.
    CP   enRegDE                        ; Was register pair DE selected?
    JR   Z,.memDe                       ; Convert it to indirect-memory DE.
    CP   enRegHL                        ; Was register pair HL selected?
    JR   Z,.memHl                       ; Convert it to indirect-memory HL.
    CP   enRegSP                        ; Was stack pointer SP selected?
    JR   Z,.memSp                       ; Convert it to indirect-memory SP.
    CP   enRegIX                        ; Was index register IX selected?
    JR   Z,.memIx                       ; Parse its optional displacement.
    CP   enRegIY                        ; Was index register IY selected?
    JR   Z,.memIy                       ; Parse its optional displacement.
    JP   prDenyOp                       ; No other operand word may be indirect.
.expr: ; Evaluate an absolute memory or immediate port expression.

; A parenthesised expression becomes a generic memory number. IN and OUT later
; reinterpret this class as an eight-bit immediate port. Other forms use an
; absolute-memory word.

    CALL prEval                         ; Evaluate or defer the inner expression.
    RET  C                              ; Preserve its exact diagnostic.
    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   (HL),prAnyMem                  ; Mark a generic parenthesised number.
    JR   .close                         ; Require and consume the closing ')'.
.portC: ; Select indirect port C rather than ordinary register C.

; `(C)` is the indirect port class, distinct from ordinary register C.

    LD   A,enPortC                      ; Select the indirect port-C class.
    JR   .fixed                         ; Store it and require ')'.
.memBc: ; Select memory addressed by register pair BC.
    LD   A,enMemBC                      ; Select the indirect BC class.
    JR   .fixed                         ; Store it and require ')'.
.memDe: ; Select memory addressed by register pair DE.
    LD   A,enMemDE                      ; Select the indirect DE class.
    JR   .fixed                         ; Store it and require ')'.
.memHl: ; Select memory addressed by register pair HL.
    LD   A,enMemHL                      ; Select the indirect HL class.
    JR   .fixed                         ; Store it and require ')'.
.memSp: ; Select memory addressed by the stack pointer.
    LD   A,enMemSP                      ; Select the indirect SP class.
.fixed: ; Store a fixed indirect class before checking its closing bracket.

; Store the fixed indirect class and require the closing parenthesis.

    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   (HL),A                         ; Store the fixed indirect class.
    JR   .close                         ; Require and consume the closing ')'.
.memIx: ; Retain the IX classes used by JP and indexed memory forms.

; B holds the JP (IX) memory class. prIxIy is the ordinary indexed
; class used for displacement-bearing forms and the zero-displacement alias.

    LD   B,enMemIX                      ; Retain the dedicated JP (IX) class.
    LD   A,enDispIX                     ; Select ordinary indexed-memory IX.
    LD   (prIxIy),A                     ; Retain it across displacement parsing.
    JR   .index                         ; Inspect the token after IX.
.memIy: ; Retain the IY classes used by JP and indexed memory forms.
    LD   B,enMemIY                      ; Retain the dedicated JP (IY) class.
    LD   A,enDispIY                     ; Select ordinary indexed-memory IY.
    LD   (prIxIy),A                     ; Retain it across displacement parsing.
.index: ; Choose an explicit displacement or an implicit zero offset.

; A closing ')' is the implicit displacement-zero form. Otherwise only '+' or
; '-' may introduce the displacement expression.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token after IX or IY.
    CP   tkRParen                       ; Is the displacement omitted?
    JR   Z,.noDisp                      ; Use the implicit zero displacement.
    CP   tkPlus                         ; A plus may introduce the displacement.
    JR   Z,.disp                        ; Parse it as an expression.
    CP   tkMinus                        ; A minus may also introduce it.
    JP   NZ,prBadSep                    ; Reject every other delimiter.
.disp: ; Evaluate the signed IX/IY displacement expression.
    CALL prEval                         ; Evaluate the signed displacement.
    RET  C                              ; Preserve its exact diagnostic.
    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   A,(prIxIy)                     ; Recover the IX/IY indexed class.
    LD   (HL),A                         ; Store the displacement-bearing class.
    JR   .close                         ; Require and consume the closing ')'.
.noDisp: ; Choose JP's indirect class or ordinary indexed displacement zero.

; JP (IX/IY) uses the encoder's dedicated memory class. Other instructions use
; the ordinary indexed class with the already-zero value slot.

    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   A,(prRec+enMnem)               ; Read the current mnemonic ordinal.
    CP   mneJp                          ; Does JP require its dedicated class?
    LD   A,B                            ; Prepare the JP (IX/IY) class.
    JR   Z,.store                       ; Keep it only for JP.
    LD   A,(prIxIy)                     ; Other forms use index offset zero.
.store: ; Store the selected indirect class and consume the close.
    LD   (HL),A                         ; Publish the final indirect class.
    JP   prNext                         ; Consume ')' and fetch the next token.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Consume the closing ')' after an expression or fixed indirect form.

.close: ; Require the closing parenthesis left by inner parsing.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the unconsumed delimiter.
    CP   tkRParen                       ; Require a closing parenthesis.
    JP   NZ,prBadSep                    ; Diagnose any other delimiter.
    JP   prNext                         ; Consume ')' and fetch the next token.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Copy the tokenizer's numeric word to the selected value slot. This retained
; helper has no caller in the current parser path.

prTokVal: ; Retained helper for copying a tokenizer numeric word.
    LD   HL,(tkRecord+tkValAt)          ; Load the tokenizer's numeric value.
    JP   prStore                        ; Store it in the selected operand slot.
