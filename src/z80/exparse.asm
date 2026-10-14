;==========================================================================
;  Expression evaluator
;==========================================================================
;
;  Parse one expression from the tokenizer stream with bounded value and
;  operator stacks. The parser alternates between a primary and an operator,
;  reducing operators as precedence permits. It leaves the delimiter in
;  tkRecord for the caller.
;
;  Principal entries:
;    exParse  return a value or publish one missing symbol through syRef
;    exDefer  return a value or an unpublished packed key for caller commit
;    exQueue  append a previously published unresolved result to the pending
;              arena
;
;  BC supplies the address used by '$'. On success carry is clear and A
;  is exFinal or exPend. A resolved result is the final word in HL. An
;  unresolved result is one exact symbol plus a signed-byte addend in HL;
;  exRForm records whether the later patch uses the plain word, LOW byte or
;  HIGH byte. exParse returns the symbol record in IX, while exDefer returns
;  IX pointing at the six-byte key in exRKey.
;
;  Concrete operations use signed 24-bit working values before the final
;  -32768..65535 word check. Addition, subtraction and left shift detect
;  signed overflow. Multiplication detects carry beyond 24 bits, but permits
;  a positive magnitude with bit 23 set. A later right shift can expose
;  that wrapped negative intermediate. Deferred expressions are deliberately
;  smaller: one symbol, an addend from -128 through 127 and an optional LOW or
;  HIGH transform. Operations that need an expression tree are rejected with
;  exFrmErr.
;
;  Value entries are ten bytes: three value or addend bytes, one resolution or
;  transform byte and a six-byte packed key. Operator entries are four bytes:
;  one encoded operator, source-part ordinal and source offset. Both stacks
;  have sixteen entries. Every parse resets their depths, so failure does
;  not poison the next expression.

exBeg: ; Begin expression code, constants and tables.

; Public success and failure statuses returned in A.

exFinal     EQU     0                                   ; Expression reduced to a concrete word.
exPend      EQU     1                                   ; One deferred symbol and addend remain.
exLexErr    EQU     2                                   ; Tokenizer rejected source within the expression.
exNoTerm    EQU     3                                   ; A primary value or prefix was expected.
exParErr    EQU     4                                   ; A closing parenthesis was expected.
exDiv0      EQU     5                                   ; Division or remainder used a zero divisor.
exValErr    EQU     6                                   ; Arithmetic, shift, word or addend out of range.
exFrmErr    EQU     7                                   ; Deferred expression cannot fit one patch record.
exCapErr    EQU     8                                   ; A bounded value or operator stack is full.
exSymErr    EQU     9                                   ; Symbol packing, lookup or scope failed.
exIntErr    EQU     10                                  ; An internal stack/parser invariant failed.

; Binary reduction ordinals stored in the low nibble of an operator byte.

exOpOr      EQU     0                                   ; Bitwise OR reduction.
exOpXor     EQU     1                                   ; Bitwise XOR reduction.
exOpAnd     EQU     2                                   ; Bitwise AND reduction.
exOpShl     EQU     3                                   ; Arithmetic left shift reduction.
exOpShr     EQU     4                                   ; Arithmetic right shift reduction.
exOpAdd     EQU     5                                   ; Signed addition reduction.
exOpSub     EQU     6                                   ; Signed subtraction reduction.
exOpMul     EQU     7                                   ; Signed multiplication reduction.
exOpDiv     EQU     8                                   ; Signed division reduction.
exOpRem     EQU     9                                   ; Signed remainder reduction.

; Fixed record sizes and stack capacities.

exValLen    EQU     10                                  ; Bytes in one value-stack record.
exValCap    EQU     16                                  ; Maximum simultaneous values.
exOpLen     EQU     4                                   ; Bytes in one operator-stack record.
exOpCap     EQU     16                                  ; Maximum simultaneous operators.

; Operator markers combine precedence in the high nibble with operation in the
; low nibble. $0F is a non-reducing parenthesis marker and $7x denotes unary.

exLParen    EQU     $0F                                 ; Left-parenthesis stack marker.
exUPlus     EQU     $7A                                 ; Unary positive marker.
exUNeg      EQU     $7B                                 ; Unary negation marker.
exUNot      EQU     $72                                 ; Unary bitwise-complement marker.
exULow      EQU     $7D                                 ; LOW(...) transform marker.
exUHigh     EQU     $7E                                 ; HIGH(...) transform marker.

; Nonzero deferred states distinguish a plain affine symbol from its
; LOW and HIGH byte transforms.

exFWord     EQU     1                                   ; Plain deferred symbol plus signed addend.
exFLow      EQU     2                                   ; LOW byte of a deferred symbol expression.
exFHigh     EQU     3                                   ; HIGH byte of a deferred symbol expression.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Publish an unresolved symbol only after the full expression has
; passed syntax, forward-form and addend checks. This is the direct evaluator
; entry for callers that can commit immediately, where publication is immediate.

exParse: ; Evaluate with symbol publication after all checks pass.
    LD   A,1                                            ; Publish symbols after successful parsing.
    LD   (exDoPub),A                                    ; Record the direct-entry policy.
    JR   exEval                                         ; Join common parser initialisation.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IY
; Parse without changing the symbol arena. The parser and statement layers use
; this entry to validate and reserve work before publication.

exDefer: ; Evaluate while leaving symbol publication to the caller.
    XOR  A                                              ; Select deferred symbol publication.
    LD   (exDoPub),A                                    ; Leave symbol creation to the caller.
exEval: ; Initialise state for both public entries.

; Save '$', clear all bounded-stack state and begin in primary position.

    LD   (exHere),BC                                    ; Preserve the current address used by '$'.
    XOR  A                                              ; Form the common zero initial state.
    LD   (exValCnt),A                                   ; Empty the value stack logically.
    LD   (exOpCnt),A                                    ; Empty the operator stack logically.
    LD   (exNest),A                                     ; Reset parenthesis nesting depth.
    INC  A                                              ; Form true for 'expect a primary'.
    LD   (exInTerm),A                                   ; Begin in the primary half of the grammar.
.loop: ; Alternate primary and operator grammar.

; exInTerm selects the grammar half. Primaries clear it after publication;
; binary operators set it after consuming themselves.

    LD   A,(exInTerm)                                   ; Read the current grammar half.
    OR   A                                              ; Z selects the operator/delimiter half.
    JR   Z,.oper                                        ; Parse what follows an existing value.
    CALL exTerm                                         ; Parse and publish one primary expression.
    RET  C                                              ; Return its positioned failure unchanged.
    JR   .loop                                          ; Continue with an operator or delimiter.
.oper: ; Parse after a completed value.
    CALL exInfix                                        ; Parse operator, ')' or delimiter.
    RET  C                                              ; Return its positioned failure unchanged.
    JR   NZ,.loop                                       ; Nonzero means an operator/group was consumed.

; A delimiter at parenthesis depth zero ends the expression. Reduce the
; remaining operators and require exactly one value.

    CALL exDrain                                        ; Reduce the stacks to one final value.
    RET  C                                              ; Preserve reduction or invariant failure.
    LD   A,(exRForm)                                    ; Inspect the final value's resolution state.
    OR   A                                              ; Z identifies a concrete 24-bit result.
    JR   NZ,.deferred                                   ; Complete one deferred symbol expression.
    CALL exWordOk                                       ; Check public -32768..65535 word range.
    RET  C                                              ; Return range failure at the delimiter.
    LD   HL,(exRVal)                                    ; Return the concrete low sixteen bits.
    XOR  A                                              ; Return exFinal with carry clear.
    RET                                                 ; Complete the concrete expression.
.deferred: ; Finish one-symbol deferred expression.

; Pending references store only signed-byte addends. Parsing has
; already reduced the full expression before this range check.

    CALL exByteOk                                       ; Check signed-byte pending addend.
    RET  C                                              ; Preserve a forward-form range failure.
    LD   A,(exDoPub)                                    ; Read the selected publication policy.
    OR   A                                              ; Z means the caller owns publication.
    JR   Z,.unpub                                       ; Return the packed key directly in that mode.

; The publishing entry creates or reuses an undefined symbol here, after
; every expression check has succeeded. Invalid source cannot leak a symbol.

    LD   HL,exRKey                                      ; Supply the validated six-byte packed key.
    CALL syRef                                          ; Find or create its undefined symbol record.
    JR   C,exSyFail                                     ; Wrap scope or symbol-capacity failure.
.retPend: ; Return unresolved symbol and addend.
    LD   HL,(exRVal)                                    ; Return the signed addend in HL.
    LD   A,exPend                                       ; Report a deferred expression result.
    OR   A                                              ; Clear carry while keeping A nonzero.
    RET                                                 ; Return symbol/addend carriers to the caller.
.unpub: ; Return unpublished key to caller.

; The deferred entry returns a pointer into expression workspace. Its caller
; must copy the key before another expression operation reuses this storage.

    LD   IX,exRKey                                      ; Point IX at the unpublished key.
    JR   .retPend                                       ; Share unresolved result completion.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Preserve the nested symbol status for diagnostics and report the expression
; layer's symbol-error category at the original name position.

exSyFail: ; Convert a nested symbol failure into an expression diagnostic.
    LD   (exCause),A                                    ; Preserve the nested symbol status.
    LD   A,exSymErr                                     ; Select the public expression symbol category.
    JP   exAtSym                                        ; Fail at the original symbol-name position.

;@ROUTINE IN A,IX,HL,DE,B OUT A,CARRY CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Adapt the result to the pending-reference ABI. The caller supplies
; A=source part, DE=patch address and B=patch kind; parsing supplies IX=symbol
; and HL=signed addend. syAdd expects that addend in C.

exQueue: ; Publish the checked addend and patch site through syAdd.
    LD   C,L                                            ; Put checked signed addend in C.
    LD   HL,(exSrcOff)                                  ; The deferred name is the reference.
    LD   (syAddOff),HL                                  ; syAdd stores it with the record.
    JP   syAdd                                          ; Tail-call pending-record publication.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise LOW(...) and HIGH(...) without consuming the following token.
; The packed RADIX-40 key must match the operator name exactly, and the next
; non-space source byte must then be '('.

exLowHi: ; Recognise the exact LOW/HIGH names followed by a parenthesis.
; Length narrows candidates to three-character LOW or four-character HIGH.
; C holds the marker until a match returns it in A.

    LD   A,(tkRecord+tkLenAt)                           ; Read the candidate name's byte length.
    CP   3                                              ; Could it be LOW?
    JR   Z,.lowName                                     ; Yes: select the LOW signature.
    CP   4                                              ; Could it be HIGH?
    JR   NZ,.notFunc                                    ; Other lengths are ordinary symbols.
    LD   C,exUHigh                                      ; Select the HIGH unary marker.
    LD   DE,$336F                                       ; Select the packed first word, HIG.
    JR   .pack                                          ; Pack and compare the candidate.
.lowName: ; Select LOW signature and marker.
    LD   C,exULow                                       ; Select the LOW unary marker.
    LD   DE,$4D6F                                       ; Select the packed LOW signature.
.pack: ; Pack and compare the prospective function name.

; Pack the lexeme into exRKey and compare its first word with LOW or HIG.
; A three-character name has an empty second word, so LOW is then exact.
; HIGH also needs its second word, H, so that HIGX and similar stay symbols.

    PUSH DE                                             ; Preserve the selected packed signature.
    PUSH BC                                             ; Preserve the marker and caller register B.
    LD   HL,(tkRecord+tkLexAt)                          ; Load the candidate lexeme address.
    LD   B,A                                            ; Supply its length to the RADIX-40 packer.
    LD   DE,exRKey                                      ; Use result-key workspace as temporary output.
    CALL nmPack                                         ; Pack case-insensitively for exact comparison.
    POP  BC                                             ; Restore marker C and caller B.
    POP  DE                                             ; Restore the selected signature.
    JR   C,.notFunc                                     ; Invalid packed text is not a function name.
    LD   HL,(exRKey)                                    ; Load the candidate's first packed word.
    OR   A                                              ; Clear carry before subtraction.
    SBC  HL,DE                                          ; Compare it with LOW or HIG.
    JR   NZ,.notFunc                                    ; A mismatch leaves it as an ordinary name.
    LD   A,C                                            ; Recover the selected unary marker.
    CP   exUHigh                                        ; Only HIGH has a fourth character to check.
    JR   NZ,.look                                       ; LOW is already an exact match.
    LD   HL,(exRKey+2)                                  ; Load the candidate's second packed word.
    LD   DE,$3200                                       ; HIGH packs its final H as $3200.
    OR   A                                              ; Clear carry before subtraction.
    SBC  HL,DE                                          ; Compare the fourth character exactly.
    JR   NZ,.notFunc                                    ; HIGX and similar remain ordinary names.
.look: ; Look ahead for the opening parenthesis.

; tkHead starts immediately after the name. Read through horizontal space
; directly so classification does not advance or overwrite tkRecord.

    LD   HL,(tkHead)                                    ; Start lookahead immediately after the name.
    LD   DE,(tkSrcLen)                                  ; Load the source part's exclusive end offset.
.scan: ; Scan for opening parenthesis.
    LD   A,H                                            ; Compare cursor and end high bytes first.
    CP   D                                              ; Are they in the same 256-byte page?
    JR   NZ,.read                                       ; No: the cursor has not reached the exact end.
    LD   A,L                                            ; Compare their low bytes.
    CP   E                                              ; Has lookahead reached the exclusive end?
    JR   Z,.notFunc                                     ; Yes: no opening parenthesis follows.
.read: ; Read the next function-lookahead source byte.
    PUSH DE                                             ; Preserve source end across host access.
    PUSH HL                                             ; Preserve cursor across host access.
    LD   A,(tkPart)                                     ; Supply the active source-part ordinal.
    CALL tkRead                                         ; Read without advancing tokenizer.
    POP  HL                                             ; Restore the lookahead cursor.
    POP  DE                                             ; Restore the source end.
    CP   $20                                            ; Is this an ASCII space?
    JR   Z,.space                                       ; Yes: skip it and continue looking.
    CP   $09                                            ; Is this a horizontal tab?
    JR   Z,.space                                       ; Yes: skip it too.
    CP   $28                                            ; Is the next significant byte '('?
    JR   NZ,.notFunc                                    ; No: treat the name as an ordinary symbol.
    LD   A,C                                            ; Return the selected LOW/HIGH marker.
    OR   A                                              ; Clear carry to report function recognition.
    RET                                                 ; Leave the tokenizer record unchanged.
.space: ; Skip one space or tab during function lookahead.
    INC  HL                                             ; Advance past one horizontal-space byte.
    JR   .scan                                          ; Inspect the next source byte.
.notFunc: ; Treat name as an ordinary symbol.
    SCF                                                 ; Report that the name is not a byte function.
    RET                                                 ; Leave A unspecified for ordinary name.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push unary or function marker A with the token position. These markers
; have highest precedence and reduce after their value.

exUPush: ; Push a positioned unary marker on the bounded operator stack.
    LD   (exOper),A                                     ; Store the encoded unary/function operator.
    CALL exStamp                                        ; Attach the current token's source position.
    JP   exOpPush                                       ; Tail-call bounded operator-stack push.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Parse a value-starting token with exInTerm set. '+', '-' and '~' become
; unary markers, while '(' is an operator-stack marker
; and increments the independent nesting depth.

exTerm: ; Parse a primary while exInTerm indicates a value is required.
    LD   A,(tkRecord+tkKindAt)                          ; Read the current primary-position token kind.
    CP   tkPlus                                         ; Is it unary plus?
    JR   Z,.unary                                       ; Encode and stack the prefix operator.
    CP   tkMinus                                        ; Is it unary minus?
    JR   Z,.unary                                       ; Encode and stack the prefix operator.
    CP   tkTilde                                        ; Is it unary complement?
    JR   Z,.unary                                       ; Encode and stack the prefix operator.
    CP   tkNum                                          ; Is it a numeric or character literal?
    JR   Z,.number                                      ; Publish its tokenizer-provided value.
    CP   tkHere                                         ; Is it the current-address marker '$'?
    JR   Z,.current                                     ; Publish the saved current address.
    CP   tkName                                         ; Is it a symbol or LOW/HIGH function name?
    JR   Z,.name                                        ; Classify and resolve it.
.needOpen: ; Check for required opening '('.

; LOW or HIGH classification rejoins here after consuming the function name.
; The next token must begin its parenthesised argument.

    CP   tkLParen                                       ; Is this an opening parenthesis?
    JR   Z,.open                                        ; Push a grouping marker when it is.
    LD   A,exNoTerm                                     ; Otherwise report a missing primary.
    JP   exAtTok                                        ; Anchor failure at the current token.
.unary: ; Convert and push a prefix operator.

; Token ordinals for '+', '-' and '~' become their $7x unary forms by setting
; the precedence nibble.

    OR   $70                                            ; Add unary precedence to token kind.
    CALL exUPush                                        ; Push it with its source position.
    RET  C                                              ; Preserve operator-stack capacity failure.
    JP   exNext                                         ; Consume prefix and expect a primary.
.open: ; Open a parenthesised expression group.
    LD   A,exLParen                                     ; Select the non-reducing group marker.
    LD   (exOper),A                                     ; Store it in the current operator record.
    CALL exStamp                                        ; Attach the opening parenthesis position.
    CALL exOpPush                                       ; Push the complete marker record.
    RET  C                                              ; Preserve stack-capacity failure.
    LD   HL,exNest                                      ; Address the independent nesting depth.
    INC  (HL)                                           ; Record one open group.
    JP   exNext                                         ; Consume '(' and expect its first primary.
.number: ; Publish a numeric or character literal value.

; Literal tokens already hold their checked 16-bit value. exStore expands it
; to a resolved, positive 24-bit working value.

    LD   HL,(tkRecord+tkValAt)                          ; Load the tokenizer's checked literal value.
    CALL exStore                                        ; Store resolved 24-bit value.
    JR   .advance                                       ; Consume the token and publish the value.
.current: ; Publish the saved current output address.
    LD   HL,(exHere)                                    ; Load the expression's saved current address.
    CALL exStore                                        ; Store resolved 24-bit value.
    JR   .advance                                       ; Consume '$' and publish the value.
.name: ; Distinguish a byte function from a symbol name.

; LOW and HIGH are identified before symbol packing. Other names use the
; symbol resolver, which may produce a concrete value or a deferred key.

    CALL exLowHi                                        ; Recognise LOW/HIGH only when followed by '('.
    JR   NC,.function                                   ; Stack the function marker when recognised.
    CALL exName                                         ; Resolve or defer an ordinary symbol name.
    RET  C                                              ; Preserve packing, scope or tokenizer failure.
    JR   .publish                                       ; Symbol parsing consumed the name.
.advance: ; Advance before value publication.

; Numbers and '$' consume the next token before publishing the value stack
; entry. Symbol parsing performs its own token advance.

    CALL exNext                                         ; Advance beyond the literal or '$'.
    RET  C                                              ; Preserve a lexical failure in the next token.
.publish: ; Push primary and apply prefixes.
    CALL exPutVal                                       ; Push the complete ten-byte working value.
    RET  C                                              ; Preserve value-stack capacity failure.

; Apply prefixes as soon as their primary is complete. This keeps
; the operator stack iterative rather than using Z80 recursion.

    CALL exUnary                                        ; Reduce prefixes above this primary.
    RET  C                                              ; Preserve unary or forward-form failure.
    XOR  A                                              ; Switch to the operator grammar half.
    LD   (exInTerm),A                                   ; Record that one value is now available.
    RET                                                 ; Return to the main parse loop.
.function: ; Stack LOW or HIGH and consume its function name.

; Retain the LOW or HIGH marker, consume the name and feed the following '('
; back through the same parenthesis path used for ordinary grouping.

    CALL exUPush                                        ; Push LOW/HIGH at function name.
    RET  C                                              ; Preserve operator-stack capacity failure.
    CALL exNext                                         ; Consume the function name.
    RET  C                                              ; Preserve lexical failure before its argument.
    LD   A,(tkRecord+tkKindAt)                          ; Read the required following token kind.
    JR   .needOpen                                      ; Reuse ordinary opening-parenthesis handling.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Parse the grammar half that follows a value. A recognised binary operator is
; compared with stacked precedence before it is pushed. A right parenthesis
; reduces back to its marker. Any other token is the caller's delimiter.

exInfix: ; Parse a binary operator, closing group or caller delimiter.
    LD   A,(tkRecord+tkKindAt)                          ; Read the token following a complete value.
    CP   tkRParen                                       ; Is it a closing parenthesis?
    JR   Z,.rParen                                      ; Reduce and close the current group.
    CALL exClass                                        ; Classify a possible binary operator.
    JR   C,.delimit                                     ; Non-operators terminate the expression.

; Preserve the incoming operator while older operators of higher precedence,
; or equal precedence for left-associative operators, are reduced.

    CALL exStash                                        ; Save the newly read operator record.
    CALL exPrior                                        ; Reduce older operators that bind first.
    RET  C                                              ; Preserve reduction failure.
    CALL exFetch                                        ; Restore the incoming operator record.
    CALL exOpPush                                       ; Push it after capacity checking.
    RET  C                                              ; Preserve operator-stack capacity failure.
    LD   A,1                                            ; Switch back to primary grammar.
    LD   (exInTerm),A                                   ; Record that a right operand is required.
    CALL exNext                                         ; Consume the binary operator.
    RET  C                                              ; Preserve right-operand lexical failure.
    XOR  A                                              ; Form carry-clear success flags.
    INC  A                                              ; Return nonzero: parsing must continue.
    RET                                                 ; Return to the main parse loop.
.rParen: ; Reduce and close one parenthesised group.

; A ')' closes only an active group. Reduce to its marker, remove it, consume
; the token and then apply a preceding LOW, HIGH or other unary operator.

    LD   A,(exNest)                                     ; Read the number of open groups.
    OR   A                                              ; Is this ')' outside the expression's groups?
    JR   Z,.delimit                                     ; Yes: leave it for the caller as a delimiter.
    CALL exGroup                                        ; Reduce back to the nearest group marker.
    RET  C                                              ; Preserve reduction or invariant failure.
    CALL exOpPop                                        ; Remove that left-parenthesis marker.
    RET  C                                              ; Preserve defensive stack-underflow failure.
    LD   HL,exNest                                      ; Address the nesting depth.
    DEC  (HL)                                           ; Close one group.
    CALL exNext                                         ; Consume the right parenthesis.
    RET  C                                              ; Preserve lexical failure after the group.
    CALL exUnary                                        ; Apply a preceding unary or byte function.
    RET  C                                              ; Preserve unary or forward-form failure.
    XOR  A                                              ; Form carry-clear success flags.
    INC  A                                              ; Return nonzero: parsing must continue.
    RET                                                 ; Return to the main parse loop.
.delimit: ; Validate caller delimiter.

; A delimiter is valid only outside parentheses. Leave tkRecord unchanged so the
; statement or operand parser can interpret it.

    LD   A,(exNest)                                     ; Check for an unclosed parenthesis group.
    OR   A                                              ; Z means the expression is at outer depth.
    JR   Z,.accept                                      ; Accept the current token as caller delimiter.
    LD   A,exParErr                                     ; Report missing right parenthesis.
    JP   exAtTok                                        ; Anchor it at the encountered delimiter.
.accept: ; Leave delimiter for caller.
    XOR  A                                              ; Return zero to signal expression completion.
    RET                                                 ; Leave tkRecord on the caller's delimiter.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE,IY
; Resolve the name while retaining its exact source position for symbol
; diagnostics. The packed key stays in exRKey for a possible deferred result.

exName: ; Resolve the current name while retaining its diagnostic position.
    LD   A,(tkRecord+tkPartAt)                          ; Capture the name token's source-part ordinal.
    LD   (exIdPart),A                                   ; Hold it for this name's own failures.
    LD   HL,(tkRecord+tkOffAt)                          ; Capture the name token's source-byte offset.
    LD   (exIdOff),HL                                   ; Hold it until the name is resolved.
    CALL tkText                                         ; Expose the current name text as HL/B.
    LD   DE,exRKey                                      ; Select the six-byte packed-key workspace.
    CALL nmPackId                                       ; Pack and validate the symbol name.
    JP   C,exSyFail                                     ; Wrap a naming or scope-independent failure.
    LD   HL,exRKey                                      ; Supply the packed key for lookup.
    CALL syFind                                         ; Search current global/private symbol state.
    JR   C,.missing                                     ; Distinguish absence from other lookup errors.

; Bit 6 marks a defined record. An undefined record and a missing name both
; become the same deferred value. Defined EQU records use bit 5 to retain the
; negative interpretation of their 16-bit stored value.

    BIT  6,(IX+5)                                       ; Is the found record already defined?
    JR   Z,.pending                                     ; No: carry it as a deferred symbol.
    LD   L,(IX+syValLo)                                 ; Load its stored value low byte.
    LD   H,(IX+syValHi)                                 ; Complete the stored sixteen-bit value.
    BIT  5,(IX+5)                                       ; Is this a negative EQU constant?
    JR   Z,.defined                                     ; No: zero-extend the ordinary address/value.

; Sign-extend a negative EQU into the 24-bit arithmetic domain.

    LD   (exRVal),HL                                    ; Store the constant's low sixteen bits.
    LD   A,$FF                                          ; Form its negative sign-extension byte.
    LD   (exRVal+2),A                                   ; Complete the signed 24-bit value.
    XOR  A                                              ; Mark the result concrete.
    JR   .finish                                        ; Store resolution state and consume the name.
.defined: ; Publish a defined non-negative symbol value.
    CALL exStore                                        ; Store concrete zero-extended word.
    JP   exNext                                         ; Consume the symbol token and return.
.missing: ; Check why lookup failed.

; syFind errors other than not-found, such as a private name outside a global
; scope, retain their symbol status and fail immediately.

    CP   syMiss                                         ; Was the only problem an absent record?
    JR   Z,.pending                                     ; Yes: create a deferred value in workspace.
    JP   exSyFail                                       ; Otherwise preserve the nested symbol failure.
.pending: ; Initialise deferred symbol at zero.

; A missing or already-undefined symbol starts with addend zero and the plain
; deferred transform. A later reduction may adjust the addend or transform.
; Only this deferred name owns the saved anchor, so a defined name or a later
; concrete subexpression cannot move the undefined-symbol diagnostic.

    LD   HL,exIdPart                                    ; Copy this name's part and offset...
    LD   DE,exSrcPos                                    ; ...into the deferred symbol's anchor.
    LD   BC,3                                           ; One part byte and one offset word.
    LDIR                                                ; The anchor now names the pending symbol.
    XOR  A                                              ; Form a zero initial addend.
    LD   (exRVal),A                                     ; Clear addend low byte.
    LD   (exRVal+1),A                                   ; Clear addend middle byte.
    LD   (exRVal+2),A                                   ; Clear addend sign byte.
    INC  A                                              ; Select exFWord deferred state.
.finish: ; Store resolution state and consume token.
    LD   (exRForm),A                                    ; Record concrete/plain/LOW/HIGH result state.
    JP   exNext                                         ; Consume the name and return.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C,HL
; Map contiguous operator tokens to a packed byte. Its high nibble is
; precedence and its low nibble is the reduction ordinal. Zero entries
; cover token kinds that are not binary expression operators.

exClass: ; Map a binary token to precedence and arithmetic operation.
    LD   A,(tkRecord+tkKindAt)                          ; Load the prospective operator token kind.
    SUB  tkPlus                                         ; Normalise operator token range.
    CP   12                                             ; Does it lie within the twelve-entry table?
    JR   NC,.notOper                                    ; No: it is an expression delimiter.
    PUSH DE                                             ; Preserve caller DE during table addressing.
    LD   E,A                                            ; Put the zero-based token index in DE.
    LD   D,0                                            ; Zero-extend it for address arithmetic.
    LD   HL,.table                                      ; Point at packed operator classifications.
    ADD  HL,DE                                          ; Address the current token's classification.
    LD   A,(HL)                                         ; Load precedence and reduction ordinal.
    POP  DE                                             ; Restore caller DE.
    OR   A                                              ; Zero means 'not binary'.
    JR   Z,.notOper                                     ; Treat unary-only tokens as delimiters here.
    LD   (exOper),A                                     ; Start the current operator record.
    CALL exStamp                                        ; Attach its exact source position.
    OR   A                                              ; Clear carry to report recognition.
    RET                                                 ; Return packed operator in exOper.
.notOper: ; Report a non-binary token.
    SCF                                                 ; Report that no binary operator matched.
    RET                                                 ; Leave the tokenizer record unchanged.

; Token order from tkPlus: +, -, *, /, %, &, ^, |, ~, apostrophe, <<, >>.
; Tilde is unary-only and apostrophe is a delimiter, so both table entries are
; zero.

.table: ; Map token kinds to precedence and reduction.
    DB   $55,$56,$67,$68,$69,$32,$21,$10,0,0,$43,$44    ; Operator fields.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the source position of the current operator beside its encoded byte.
; Arithmetic and forward-form failures later report this position.

exStamp: ; Attach the current token position to exOper.
    LD   A,(tkRecord+tkPartAt)                          ; Load operator source part.
    LD   (exOpPart),A                                   ; Store it in the current operator record.
    LD   HL,(tkRecord+tkOffAt)                          ; Load the operator token's source-byte offset.
    LD   (exOpOff),HL                                   ; Complete the positioned operator record.
    RET                                                 ; Return without changing tokenizer state.
