;==========================================================================
;  Expression evaluator
;==========================================================================
;
;  Parse one expression from the tokenizer stream with bounded value and
;  operator stacks. The parser alternates between a primary and an operator,
;  reducing operators as precedence permits. It leaves the delimiter in
;  TK_REC for the caller.
;
;  Principal entries:
;    EX_PARSE  return a value or publish one missing symbol through SY_REF
;    EX_DEFER  return a value or an unpublished packed key for caller commit
;    EX_QUEUE  append a previously published unresolved result to the pending
;              arena
;
;  BC supplies the address used by '$'. On success carry is clear and A
;  is EX_FINAL or EX_PEND. A resolved result is the final word in HL. An
;  unresolved result is one exact symbol plus a signed-byte addend in HL;
;  EX_RFORM records whether the later patch uses the plain word, LOW byte or
;  HIGH byte. EX_PARSE returns the symbol record in IX, while EX_DEFER returns
;  IX pointing at the six-byte key in EX_RKEY.
;
;  Concrete operations use signed 24-bit working values before the final
;  -32768..65535 word check. Addition, subtraction and left shift detect
;  signed overflow. Multiplication detects carry beyond 24 bits, but permits
;  a positive magnitude with bit 23 set. A later right shift can expose
;  that wrapped negative intermediate. Deferred expressions are deliberately
;  smaller: one symbol, an addend from -128 through 127 and an optional LOW or
;  HIGH transform. Operations that need an expression tree are rejected with
;  EX_SFORM.
;
;  Value entries are ten bytes: three value or addend bytes, one resolution or
;  transform byte and a six-byte packed key. Operator entries are four bytes:
;  one encoded operator, source-part ordinal and source offset. Both stacks
;  have sixteen entries. Every parse resets their depths, so failure does
;  not poison the next expression.

EX_CBEG: ; Begin expression code, constants and tables.

; Public success and failure statuses returned in A.

EX_FINAL    EQU     0                                   ; Expression reduced to a concrete word.
EX_PEND     EQU     1                                   ; One deferred symbol and addend remain.
EX_SLEX     EQU     2                                   ; Tokenizer rejected source within the expression.
EX_STERM    EQU     3                                   ; A primary value or prefix was expected.
EX_SOPEN    EQU     4                                   ; A closing parenthesis was expected.
EX_SZERO    EQU     5                                   ; Division or remainder used a zero divisor.
EX_SRNG     EQU     6                                   ; Arithmetic, shift, word or addend out of range.
EX_SFORM    EQU     7                                   ; Deferred expression cannot fit one patch record.
EX_SCAP     EQU     8                                   ; A bounded value or operator stack is full.
EX_SSYM     EQU     9                                   ; Symbol packing, lookup or scope failed.
EX_SINT     EQU     10                                  ; An internal stack/parser invariant failed.

; Binary reduction ordinals stored in the low nibble of an operator byte.

EX_OPOR     EQU     0                                   ; Bitwise OR reduction.
EX_OPXOR    EQU     1                                   ; Bitwise XOR reduction.
EX_OPAND    EQU     2                                   ; Bitwise AND reduction.
EX_OPSHL    EQU     3                                   ; Arithmetic left shift reduction.
EX_OPSHR    EQU     4                                   ; Arithmetic right shift reduction.
EX_OPADD    EQU     5                                   ; Signed addition reduction.
EX_OPSUB    EQU     6                                   ; Signed subtraction reduction.
EX_OPMUL    EQU     7                                   ; Signed multiplication reduction.
EX_OPDIV    EQU     8                                   ; Signed division reduction.
EX_OPREM    EQU     9                                   ; Signed remainder reduction.

; Fixed record sizes and stack capacities.

EX_VALB     EQU     10                                  ; Bytes in one value-stack record.
EX_VCAP     EQU     16                                  ; Maximum simultaneous values.
EX_OPERB    EQU     4                                   ; Bytes in one operator-stack record.
EX_OCAP     EQU     16                                  ; Maximum simultaneous operators.

; Operator markers combine precedence in the high nibble with operation in the
; low nibble. $0F is a non-reducing parenthesis marker and $7x denotes unary.

EX_MARK     EQU     $0F                                 ; Left-parenthesis stack marker.
EX_UPLUS    EQU     $7A                                 ; Unary positive marker.
EX_UNEG     EQU     $7B                                 ; Unary negation marker.
EX_UNOT     EQU     $72                                 ; Unary bitwise-complement marker.
EX_ULO      EQU     $7D                                 ; LOW(...) transform marker.
EX_UHI      EQU     $7E                                 ; HIGH(...) transform marker.

; Nonzero deferred states distinguish a plain affine symbol from its
; LOW and HIGH byte transforms.

EX_FWORD    EQU     1                                   ; Plain deferred symbol plus signed addend.
EX_FLO      EQU     2                                   ; LOW byte of a deferred symbol expression.
EX_FHI      EQU     3                                   ; HIGH byte of a deferred symbol expression.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Publish an unresolved symbol only after the full expression has
; passed syntax, forward-form and addend checks. This is the direct evaluator
; entry for callers that can commit immediately, where publication is immediate.

EX_PARSE: ; Evaluate with symbol publication after all checks pass.
    LD   A,1                                            ; Publish symbols after successful parsing.
    LD   (EX_DOPUB),A                                   ; Record the direct-entry policy.
    JR   EX_EVAL                                        ; Join common parser initialisation.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IY
; Parse without changing the symbol arena. The parser and statement layers use
; this entry to validate and reserve work before publication.

EX_DEFER: ; Evaluate while leaving symbol publication to the caller.
    XOR  A                                              ; Select deferred symbol publication.
    LD   (EX_DOPUB),A                                   ; Leave symbol creation to the caller.
EX_EVAL: ; Initialise state for both public entries.

; Save '$', clear all bounded-stack state and begin in primary position.

    LD   (EX_LOC),BC                                    ; Preserve the current address used by '$'.
    XOR  A                                              ; Form the common zero initial state.
    LD   (EX_VCNT),A                                    ; Empty the value stack logically.
    LD   (EX_OCNT),A                                    ; Empty the operator stack logically.
    LD   (EX_NEST),A                                    ; Reset parenthesis nesting depth.
    INC  A                                              ; Form true for 'expect a primary'.
    LD   (EX_HALF),A                                    ; Begin in the primary half of the grammar.
.LOOP: ; Alternate primary and operator grammar.

; EX_HALF selects the grammar half. Primaries clear it after publication;
; binary operators set it after consuming themselves.

    LD   A,(EX_HALF)                                    ; Read the current grammar half.
    OR   A                                              ; Z selects the operator/delimiter half.
    JR   Z,.OPER                                        ; Parse what follows an existing value.
    CALL EX_TERM                                        ; Parse and publish one primary expression.
    RET  C                                              ; Return its positioned failure unchanged.
    JR   .LOOP                                          ; Continue with an operator or delimiter.
.OPER: ; Parse after a completed value.
    CALL EX_INFIX                                       ; Parse operator, ')' or delimiter.
    RET  C                                              ; Return its positioned failure unchanged.
    JR   NZ,.LOOP                                       ; Nonzero means an operator/group was consumed.

; A delimiter at parenthesis depth zero ends the expression. Reduce the
; remaining operators and require exactly one value.

    CALL EX_DRAIN                                       ; Reduce the stacks to one final value.
    RET  C                                              ; Preserve reduction or invariant failure.
    LD   A,(EX_RFORM)                                   ; Inspect the final value's resolution state.
    OR   A                                              ; Z identifies a concrete 24-bit result.
    JR   NZ,.DEFERRED                                   ; Complete one deferred symbol expression.
    CALL EX_WORD                                        ; Check public -32768..65535 word range.
    RET  C                                              ; Return range failure at the delimiter.
    LD   HL,(EX_RVAL)                                   ; Return the concrete low sixteen bits.
    XOR  A                                              ; Return EX_FINAL with carry clear.
    RET                                                 ; Complete the concrete expression.
.DEFERRED: ; Finish one-symbol deferred expression.

; Pending references store only signed-byte addends. Parsing has
; already reduced the full expression before this range check.

    CALL EX_BYTE                                        ; Check signed-byte pending addend.
    RET  C                                              ; Preserve a forward-form range failure.
    LD   A,(EX_DOPUB)                                   ; Read the selected publication policy.
    OR   A                                              ; Z means the caller owns publication.
    JR   Z,.UNPUB                                       ; Return the packed key directly in that mode.

; The publishing entry creates or reuses an undefined symbol here, after
; every expression check has succeeded. Invalid source cannot leak a symbol.

    LD   HL,EX_RKEY                                     ; Supply the validated six-byte packed key.
    CALL SY_REF                                         ; Find or create its undefined symbol record.
    JR   C,EX_SYERR                                     ; Wrap scope or symbol-capacity failure.
.RETPEND: ; Return unresolved symbol and addend.
    LD   HL,(EX_RVAL)                                   ; Return the signed addend in HL.
    LD   A,EX_PEND                                      ; Report a deferred expression result.
    OR   A                                              ; Clear carry while keeping A nonzero.
    RET                                                 ; Return symbol/addend carriers to the caller.
.UNPUB: ; Return unpublished key to caller.

; The deferred entry returns a pointer into expression workspace. Its caller
; must copy the key before another expression operation reuses this storage.

    LD   IX,EX_RKEY                                     ; Point IX at the unpublished key.
    JR   .RETPEND                                       ; Share unresolved result completion.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Preserve the nested symbol status for diagnostics and report the expression
; layer's symbol-error category at the original name position.

EX_SYERR: ; Convert a nested symbol failure into an expression diagnostic.
    LD   (EX_CAUSE),A                                   ; Preserve the nested symbol status.
    LD   A,EX_SSYM                                      ; Select the public expression symbol category.
    JP   EX_FSYM                                        ; Fail at the original symbol-name position.

;@ROUTINE IN A,IX,HL,DE,B OUT A,CARRY CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Adapt the result to the pending-reference ABI. The caller supplies
; A=source part, DE=patch address and B=patch kind; parsing supplies IX=symbol
; and HL=signed addend. SY_ADD expects that addend in C.

EX_QUEUE: ; Publish the checked addend and patch site through SY_ADD.
    LD   C,L                                            ; Put checked signed addend in C.
    LD   HL,(EX_SOFF)                                   ; The deferred name is the reference.
    LD   (SY_ROFF),HL                                   ; SY_ADD stores it with the record.
    JP   SY_ADD                                         ; Tail-call pending-record publication.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise LOW(...) and HIGH(...) without consuming the following token.
; The packed RADIX-40 key must match the operator name exactly, and the next
; non-space source byte must then be '('.

EX_LOWHI: ; Recognise the exact LOW/HIGH names followed by a parenthesis.
; Length narrows candidates to three-character LOW or four-character HIGH.
; C holds the marker until a match returns it in A.

    LD   A,(TK_REC+TK_RLEN)                             ; Read the candidate name's byte length.
    CP   3                                              ; Could it be LOW?
    JR   Z,.LOWNAME                                     ; Yes: select the LOW signature.
    CP   4                                              ; Could it be HIGH?
    JR   NZ,.NOTFUNC                                    ; Other lengths are ordinary symbols.
    LD   C,EX_UHI                                       ; Select the HIGH unary marker.
    LD   DE,$336F                                       ; Select the packed first word, HIG.
    JR   .PACK                                          ; Pack and compare the candidate.
.LOWNAME: ; Select LOW signature and marker.
    LD   C,EX_ULO                                       ; Select the LOW unary marker.
    LD   DE,$4D6F                                       ; Select the packed LOW signature.
.PACK: ; Pack and compare the prospective function name.

; Pack the lexeme into EX_RKEY and compare its first word with LOW or HIG.
; A three-character name has an empty second word, so LOW is then exact.
; HIGH also needs its second word, H, so that HIGX and similar stay symbols.

    PUSH DE                                             ; Preserve the selected packed signature.
    PUSH BC                                             ; Preserve the marker and caller register B.
    LD   HL,(TK_REC+TK_RLEX)                            ; Load the candidate lexeme address.
    LD   B,A                                            ; Supply its length to the RADIX-40 packer.
    LD   DE,EX_RKEY                                     ; Use result-key workspace as temporary output.
    CALL EN_R40PK                                       ; Pack case-insensitively for exact comparison.
    POP  BC                                             ; Restore marker C and caller B.
    POP  DE                                             ; Restore the selected signature.
    JR   C,.NOTFUNC                                     ; Invalid packed text is not a function name.
    LD   HL,(EX_RKEY)                                   ; Load the candidate's first packed word.
    OR   A                                              ; Clear carry before subtraction.
    SBC  HL,DE                                          ; Compare it with LOW or HIG.
    JR   NZ,.NOTFUNC                                    ; A mismatch leaves it as an ordinary name.
    LD   A,C                                            ; Recover the selected unary marker.
    CP   EX_UHI                                         ; Only HIGH has a fourth character to check.
    JR   NZ,.LOOK                                       ; LOW is already an exact match.
    LD   HL,(EX_RKEY+2)                                 ; Load the candidate's second packed word.
    LD   DE,$3200                                       ; HIGH packs its final H as $3200.
    OR   A                                              ; Clear carry before subtraction.
    SBC  HL,DE                                          ; Compare the fourth character exactly.
    JR   NZ,.NOTFUNC                                    ; HIGX and similar remain ordinary names.
.LOOK: ; Look ahead for the opening parenthesis.

; TK_HEAD starts immediately after the name. Read through horizontal space
; directly so classification does not advance or overwrite TK_REC.

    LD   HL,(TK_HEAD)                                   ; Start lookahead immediately after the name.
    LD   DE,(TK_LIMIT)                                  ; Load the source part's exclusive end offset.
.SCAN: ; Scan for opening parenthesis.
    LD   A,H                                            ; Compare cursor and end high bytes first.
    CP   D                                              ; Are they in the same 256-byte page?
    JR   NZ,.READ                                       ; No: the cursor has not reached the exact end.
    LD   A,L                                            ; Compare their low bytes.
    CP   E                                              ; Has lookahead reached the exclusive end?
    JR   Z,.NOTFUNC                                     ; Yes: no opening parenthesis follows.
.READ: ; Read the next function-lookahead source byte.
    PUSH DE                                             ; Preserve source end across host access.
    PUSH HL                                             ; Preserve cursor across host access.
    LD   A,(TK_PART)                                    ; Supply the active source-part ordinal.
    CALL TK_SREAD                                       ; Read without advancing tokenizer.
    POP  HL                                             ; Restore the lookahead cursor.
    POP  DE                                             ; Restore the source end.
    CP   $20                                            ; Is this an ASCII space?
    JR   Z,.SPACE                                       ; Yes: skip it and continue looking.
    CP   $09                                            ; Is this a horizontal tab?
    JR   Z,.SPACE                                       ; Yes: skip it too.
    CP   $28                                            ; Is the next significant byte '('?
    JR   NZ,.NOTFUNC                                    ; No: treat the name as an ordinary symbol.
    LD   A,C                                            ; Return the selected LOW/HIGH marker.
    OR   A                                              ; Clear carry to report function recognition.
    RET                                                 ; Leave the tokenizer record unchanged.
.SPACE: ; Skip one space or tab during function lookahead.
    INC  HL                                             ; Advance past one horizontal-space byte.
    JR   .SCAN                                          ; Inspect the next source byte.
.NOTFUNC: ; Treat name as an ordinary symbol.
    SCF                                                 ; Report that the name is not a byte function.
    RET                                                 ; Leave A unspecified for ordinary name.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push unary or function marker A with the token position. These markers
; have highest precedence and reduce after their value.

EX_UPUSH: ; Push a positioned unary marker on the bounded operator stack.
    LD   (EX_OPER),A                                    ; Store the encoded unary/function operator.
    CALL EX_STAMP                                       ; Attach the current token's source position.
    JP   EX_OPUSH                                       ; Tail-call bounded operator-stack push.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Parse a value-starting token with EX_HALF set. '+', '-' and '~' become
; unary markers, while '(' is an operator-stack marker
; and increments the independent nesting depth.

EX_TERM: ; Parse a primary while EX_HALF indicates a value is required.
    LD   A,(TK_REC+TK_RKIND)                            ; Read the current primary-position token kind.
    CP   TK_PLUS                                        ; Is it unary plus?
    JR   Z,.UNARY                                       ; Encode and stack the prefix operator.
    CP   TK_MINUS                                       ; Is it unary minus?
    JR   Z,.UNARY                                       ; Encode and stack the prefix operator.
    CP   TK_TILDE                                       ; Is it unary complement?
    JR   Z,.UNARY                                       ; Encode and stack the prefix operator.
    CP   TK_NUM                                         ; Is it a numeric or character literal?
    JR   Z,.NUMBER                                      ; Publish its tokenizer-provided value.
    CP   TK_CUR                                         ; Is it the current-address marker '$'?
    JR   Z,.CURRENT                                     ; Publish the saved current address.
    CP   TK_NAME                                        ; Is it a symbol or LOW/HIGH function name?
    JR   Z,.NAME                                        ; Classify and resolve it.
.NEEDOPEN: ; Check for required opening '('.

; LOW or HIGH classification rejoins here after consuming the function name.
; The next token must begin its parenthesised argument.

    CP   TK_LPAR                                        ; Is this an opening parenthesis?
    JR   Z,.OPEN                                        ; Push a grouping marker when it is.
    LD   A,EX_STERM                                     ; Otherwise report a missing primary.
    JP   EX_FHERE                                       ; Anchor failure at the current token.
.UNARY: ; Convert and push a prefix operator.

; Token ordinals for '+', '-' and '~' become their $7x unary forms by setting
; the precedence nibble.

    OR   $70                                            ; Add unary precedence to token kind.
    CALL EX_UPUSH                                       ; Push it with its source position.
    RET  C                                              ; Preserve operator-stack capacity failure.
    JP   EX_NEXT                                        ; Consume prefix and expect a primary.
.OPEN: ; Open a parenthesised expression group.
    LD   A,EX_MARK                                      ; Select the non-reducing group marker.
    LD   (EX_OPER),A                                    ; Store it in the current operator record.
    CALL EX_STAMP                                       ; Attach the opening parenthesis position.
    CALL EX_OPUSH                                       ; Push the complete marker record.
    RET  C                                              ; Preserve stack-capacity failure.
    LD   HL,EX_NEST                                     ; Address the independent nesting depth.
    INC  (HL)                                           ; Record one open group.
    JP   EX_NEXT                                        ; Consume '(' and expect its first primary.
.NUMBER: ; Publish a numeric or character literal value.

; Literal tokens already hold their checked 16-bit value. EX_STORE expands it
; to a resolved, positive 24-bit working value.

    LD   HL,(TK_REC+TK_RVAL)                            ; Load the tokenizer's checked literal value.
    CALL EX_STORE                                       ; Store resolved 24-bit value.
    JR   .ADVANCE                                       ; Consume the token and publish the value.
.CURRENT: ; Publish the saved current output address.
    LD   HL,(EX_LOC)                                    ; Load the expression's saved current address.
    CALL EX_STORE                                       ; Store resolved 24-bit value.
    JR   .ADVANCE                                       ; Consume '$' and publish the value.
.NAME: ; Distinguish a byte function from a symbol name.

; LOW and HIGH are identified before symbol packing. Other names use the
; symbol resolver, which may produce a concrete value or a deferred key.

    CALL EX_LOWHI                                       ; Recognise LOW/HIGH only when followed by '('.
    JR   NC,.FUNCTION                                   ; Stack the function marker when recognised.
    CALL EX_NAME                                        ; Resolve or defer an ordinary symbol name.
    RET  C                                              ; Preserve packing, scope or tokenizer failure.
    JR   .PUBLISH                                       ; Symbol parsing consumed the name.
.ADVANCE: ; Advance before value publication.

; Numbers and '$' consume the next token before publishing the value stack
; entry. Symbol parsing performs its own token advance.

    CALL EX_NEXT                                        ; Advance beyond the literal or '$'.
    RET  C                                              ; Preserve a lexical failure in the next token.
.PUBLISH: ; Push primary and apply prefixes.
    CALL EX_VPUSH                                       ; Push the complete ten-byte working value.
    RET  C                                              ; Preserve value-stack capacity failure.

; Apply prefixes as soon as their primary is complete. This keeps
; the operator stack iterative rather than using Z80 recursion.

    CALL EX_UNARY                                       ; Reduce prefixes above this primary.
    RET  C                                              ; Preserve unary or forward-form failure.
    XOR  A                                              ; Switch to the operator grammar half.
    LD   (EX_HALF),A                                    ; Record that one value is now available.
    RET                                                 ; Return to the main parse loop.
.FUNCTION: ; Stack LOW or HIGH and consume its function name.

; Retain the LOW or HIGH marker, consume the name and feed the following '('
; back through the same parenthesis path used for ordinary grouping.

    CALL EX_UPUSH                                       ; Push LOW/HIGH at function name.
    RET  C                                              ; Preserve operator-stack capacity failure.
    CALL EX_NEXT                                        ; Consume the function name.
    RET  C                                              ; Preserve lexical failure before its argument.
    LD   A,(TK_REC+TK_RKIND)                            ; Read the required following token kind.
    JR   .NEEDOPEN                                      ; Reuse ordinary opening-parenthesis handling.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Parse the grammar half that follows a value. A recognised binary operator is
; compared with stacked precedence before it is pushed. A right parenthesis
; reduces back to its marker. Any other token is the caller's delimiter.

EX_INFIX: ; Parse a binary operator, closing group or caller delimiter.
    LD   A,(TK_REC+TK_RKIND)                            ; Read the token following a complete value.
    CP   TK_RPAR                                        ; Is it a closing parenthesis?
    JR   Z,.RPAREN                                      ; Reduce and close the current group.
    CALL EX_CLASS                                       ; Classify a possible binary operator.
    JR   C,.DELIMIT                                     ; Non-operators terminate the expression.

; Preserve the incoming operator while older operators of higher precedence,
; or equal precedence for left-associative operators, are reduced.

    CALL EX_STASH                                       ; Save the newly read operator record.
    CALL EX_PRIOR                                       ; Reduce older operators that bind first.
    RET  C                                              ; Preserve reduction failure.
    CALL EX_FETCH                                       ; Restore the incoming operator record.
    CALL EX_OPUSH                                       ; Push it after capacity checking.
    RET  C                                              ; Preserve operator-stack capacity failure.
    LD   A,1                                            ; Switch back to primary grammar.
    LD   (EX_HALF),A                                    ; Record that a right operand is required.
    CALL EX_NEXT                                        ; Consume the binary operator.
    RET  C                                              ; Preserve right-operand lexical failure.
    XOR  A                                              ; Form carry-clear success flags.
    INC  A                                              ; Return nonzero: parsing must continue.
    RET                                                 ; Return to the main parse loop.
.RPAREN: ; Reduce and close one parenthesised group.

; A ')' closes only an active group. Reduce to its marker, remove it, consume
; the token and then apply a preceding LOW, HIGH or other unary operator.

    LD   A,(EX_NEST)                                    ; Read the number of open groups.
    OR   A                                              ; Is this ')' outside the expression's groups?
    JR   Z,.DELIMIT                                     ; Yes: leave it for the caller as a delimiter.
    CALL EX_GROUP                                       ; Reduce back to the nearest group marker.
    RET  C                                              ; Preserve reduction or invariant failure.
    CALL EX_OPOP                                        ; Remove that left-parenthesis marker.
    RET  C                                              ; Preserve defensive stack-underflow failure.
    LD   HL,EX_NEST                                     ; Address the nesting depth.
    DEC  (HL)                                           ; Close one group.
    CALL EX_NEXT                                        ; Consume the right parenthesis.
    RET  C                                              ; Preserve lexical failure after the group.
    CALL EX_UNARY                                       ; Apply a preceding unary or byte function.
    RET  C                                              ; Preserve unary or forward-form failure.
    XOR  A                                              ; Form carry-clear success flags.
    INC  A                                              ; Return nonzero: parsing must continue.
    RET                                                 ; Return to the main parse loop.
.DELIMIT: ; Validate caller delimiter.

; A delimiter is valid only outside parentheses. Leave TK_REC unchanged so the
; statement or operand parser can interpret it.

    LD   A,(EX_NEST)                                    ; Check for an unclosed parenthesis group.
    OR   A                                              ; Z means the expression is at outer depth.
    JR   Z,.ACCEPT                                      ; Accept the current token as caller delimiter.
    LD   A,EX_SOPEN                                     ; Report missing right parenthesis.
    JP   EX_FHERE                                       ; Anchor it at the encountered delimiter.
.ACCEPT: ; Leave delimiter for caller.
    XOR  A                                              ; Return zero to signal expression completion.
    RET                                                 ; Leave TK_REC on the caller's delimiter.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE,IY
; Resolve the name while retaining its exact source position for symbol
; diagnostics. The packed key stays in EX_RKEY for a possible deferred result.

EX_NAME: ; Resolve the current name while retaining its diagnostic position.
    LD   A,(TK_REC+TK_RPART)                            ; Capture the name token's source-part ordinal.
    LD   (EX_NPART),A                                   ; Hold it for this name's own failures.
    LD   HL,(TK_REC+TK_ROFF)                            ; Capture the name token's source-byte offset.
    LD   (EX_NOFF),HL                                   ; Hold it until the name is resolved.
    CALL TK_TEXT                                        ; Expose the current name text as HL/B.
    LD   DE,EX_RKEY                                     ; Select the six-byte packed-key workspace.
    CALL EN_PSYM                                        ; Pack and validate the symbol name.
    JP   C,EX_SYERR                                     ; Wrap a naming or scope-independent failure.
    LD   HL,EX_RKEY                                     ; Supply the packed key for lookup.
    CALL SY_FIND                                        ; Search current global/private symbol state.
    JR   C,.MISSING                                     ; Distinguish absence from other lookup errors.

; Bit 6 marks a defined record. An undefined record and a missing name both
; become the same deferred value. Defined EQU records use bit 5 to retain the
; negative interpretation of their 16-bit stored value.

    BIT  6,(IX+5)                                       ; Is the found record already defined?
    JR   Z,.PENDING                                     ; No: carry it as a deferred symbol.
    LD   L,(IX+SY_VALLO)                                ; Load its stored value low byte.
    LD   H,(IX+SY_VALHI)                                ; Complete the stored sixteen-bit value.
    BIT  5,(IX+5)                                       ; Is this a negative EQU constant?
    JR   Z,.DEFINED                                     ; No: zero-extend the ordinary address/value.

; Sign-extend a negative EQU into the 24-bit arithmetic domain.

    LD   (EX_RVAL),HL                                   ; Store the constant's low sixteen bits.
    LD   A,$FF                                          ; Form its negative sign-extension byte.
    LD   (EX_RVAL+2),A                                  ; Complete the signed 24-bit value.
    XOR  A                                              ; Mark the result concrete.
    JR   .FINISH                                        ; Store resolution state and consume the name.
.DEFINED: ; Publish a defined non-negative symbol value.
    CALL EX_STORE                                       ; Store concrete zero-extended word.
    JP   EX_NEXT                                        ; Consume the symbol token and return.
.MISSING: ; Check why lookup failed.

; SY_FIND errors other than not-found, such as a private name outside a global
; scope, retain their symbol status and fail immediately.

    CP   SY_SMISS                                       ; Was the only problem an absent record?
    JR   Z,.PENDING                                     ; Yes: create a deferred value in workspace.
    JP   EX_SYERR                                       ; Otherwise preserve the nested symbol failure.
.PENDING: ; Initialise deferred symbol at zero.

; A missing or already-undefined symbol starts with addend zero and the plain
; deferred transform. A later reduction may adjust the addend or transform.
; Only this deferred name owns the saved anchor, so a defined name or a later
; concrete subexpression cannot move the undefined-symbol diagnostic.

    LD   HL,EX_NPART                                    ; Copy this name's part and offset...
    LD   DE,EX_SPART                                    ; ...into the deferred symbol's anchor.
    LD   BC,3                                           ; One part byte and one offset word.
    LDIR                                                ; The anchor now names the pending symbol.
    XOR  A                                              ; Form a zero initial addend.
    LD   (EX_RVAL),A                                    ; Clear addend low byte.
    LD   (EX_RVAL+1),A                                  ; Clear addend middle byte.
    LD   (EX_RVAL+2),A                                  ; Clear addend sign byte.
    INC  A                                              ; Select EX_FWORD deferred state.
.FINISH: ; Store resolution state and consume token.
    LD   (EX_RFORM),A                                   ; Record concrete/plain/LOW/HIGH result state.
    JP   EX_NEXT                                        ; Consume the name and return.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C,HL
; Map contiguous operator tokens to a packed byte. Its high nibble is
; precedence and its low nibble is the reduction ordinal. Zero entries
; cover token kinds that are not binary expression operators.

EX_CLASS: ; Map a binary token to precedence and arithmetic operation.
    LD   A,(TK_REC+TK_RKIND)                            ; Load the prospective operator token kind.
    SUB  TK_PLUS                                        ; Normalise operator token range.
    CP   12                                             ; Does it lie within the twelve-entry table?
    JR   NC,.NOTOPER                                    ; No: it is an expression delimiter.
    PUSH DE                                             ; Preserve caller DE during table addressing.
    LD   E,A                                            ; Put the zero-based token index in DE.
    LD   D,0                                            ; Zero-extend it for address arithmetic.
    LD   HL,.TABLE                                      ; Point at packed operator classifications.
    ADD  HL,DE                                          ; Address the current token's classification.
    LD   A,(HL)                                         ; Load precedence and reduction ordinal.
    POP  DE                                             ; Restore caller DE.
    OR   A                                              ; Zero means 'not binary'.
    JR   Z,.NOTOPER                                     ; Treat unary-only tokens as delimiters here.
    LD   (EX_OPER),A                                    ; Start the current operator record.
    CALL EX_STAMP                                       ; Attach its exact source position.
    OR   A                                              ; Clear carry to report recognition.
    RET                                                 ; Return packed operator in EX_OPER.
.NOTOPER: ; Report a non-binary token.
    SCF                                                 ; Report that no binary operator matched.
    RET                                                 ; Leave the tokenizer record unchanged.

; Token order from TK_PLUS: +, -, *, /, %, &, ^, |, ~, apostrophe, <<, >>.
; Tilde is unary-only and apostrophe is a delimiter, so both table entries are
; zero.

.TABLE: ; Map token kinds to precedence and reduction.
    DB   $55,$56,$67,$68,$69,$32,$21,$10,0,0,$43,$44    ; Operator fields.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the source position of the current operator beside its encoded byte.
; Arithmetic and forward-form failures later report this position.

EX_STAMP: ; Attach the current token position to EX_OPER.
    LD   A,(TK_REC+TK_RPART)                            ; Load operator source part.
    LD   (EX_OPART),A                                   ; Store it in the current operator record.
    LD   HL,(TK_REC+TK_ROFF)                            ; Load the operator token's source-byte offset.
    LD   (EX_OOFF),HL                                   ; Complete the positioned operator record.
    RET                                                 ; Return without changing tokenizer state.
