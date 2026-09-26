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
;    EX_PDEFR  return a value or an unpublished packed key for caller commit
;    EX_QUEUE  append a previously published unresolved result to the pending
;              arena
;
;  BC supplies the address used by '$'. On success carry is clear and A
;  is EX_RESOL or EX_UNRES. A resolved result is the final word in HL. An
;  unresolved result is one exact symbol plus a signed-byte addend in HL;
;  EX_RUNRE records whether the later patch uses the plain word, LOW byte or
;  HIGH byte. EX_PARSE returns the symbol record in IX, while EX_PDEFR returns
;  IX pointing at the six-byte key in EX_RKEY.
;
;  Concrete operations use signed 24-bit working values before the final
;  -32768..65535 word check. Addition, subtraction and left shift detect
;  signed overflow. Multiplication detects carry beyond 24 bits, but permits
;  a positive magnitude with bit 23 set. A later right shift can expose
;  that wrapped negative intermediate. Deferred expressions are deliberately
;  smaller: one symbol, an addend from -128 through 127 and an optional LOW or
;  HIGH transform. Operations that need an expression tree are rejected with
;  EX_SFFOR.
;
;  Value entries are ten bytes: three value or addend bytes, one resolution or
;  transform byte and a six-byte packed key. Operator entries are four bytes:
;  one encoded operator, source-part ordinal and source offset. Both stacks
;  have sixteen entries. Every parse resets their depths, so failure does
;  not poison the next expression.

EX_CBEG:                    ; Begin expression code, constants and tables.

; Public success and failure statuses returned in A.

EX_RESOL EQU 0             ; Expression reduced to a concrete word.
EX_UNRES EQU 1             ; One deferred symbol and addend remain.
EX_SLEXI EQU 2             ; Tokenizer rejected source within the expression.
EX_SEPRI EQU 3             ; A primary value or prefix was expected.
EX_SERIG EQU 4             ; A closing parenthesis was expected.
EX_SDZER EQU 5             ; Division or remainder used a zero divisor.
EX_SRANG EQU 6             ; Arithmetic, shift, word or addend out of range.
EX_SFFOR EQU 7             ; Deferred expression cannot fit one patch record.
EX_SCAP EQU 8              ; A bounded value or operator stack is full.
EX_SSYM EQU 9              ; Symbol packing, lookup or scope failed.
EX_SINT EQU 10             ; An internal stack/parser invariant failed.

; Binary reduction ordinals stored in the low nibble of an operator byte.

EX_OPOR EQU 0              ; Bitwise OR reduction.
EX_OPXOR EQU 1             ; Bitwise XOR reduction.
EX_OPAND EQU 2             ; Bitwise AND reduction.
EX_OLEFT EQU 3             ; Arithmetic left shift reduction.
EX_ORIGH EQU 4             ; Arithmetic right shift reduction.
EX_OPADD EQU 5             ; Signed addition reduction.
EX_OSUBT EQU 6             ; Signed subtraction reduction.
EX_OMULT EQU 7             ; Signed multiplication reduction.
EX_ODIVI EQU 8             ; Signed division reduction.
EX_OREMA EQU 9             ; Signed remainder reduction.

; Fixed record sizes and stack capacities.

EX_VALB EQU 10             ; Bytes in one value-stack record.
EX_VCAP EQU 16             ; Maximum simultaneous values.
EX_OPERB EQU 4             ; Bytes in one operator-stack record.
EX_OCAP EQU 16             ; Maximum simultaneous operators.

; Operator markers combine precedence in the high nibble with operation in the
; low nibble. $0F is a non-reducing parenthesis marker and $7x denotes unary.

EX_MLPAR EQU $0F           ; Left-parenthesis stack marker.
EX_UPLUS EQU $7A           ; Unary positive marker.
EX_UMINU EQU $7B           ; Unary negation marker.
EX_UTILD EQU $72           ; Unary bitwise-complement marker.
EX_ULO EQU $7D             ; LOW(...) transform marker.
EX_UHI EQU $7E             ; HIGH(...) transform marker.

; Nonzero deferred states distinguish a plain affine symbol from its
; LOW and HIGH byte transforms.

EX_FPLAI EQU 1             ; Plain deferred symbol plus signed addend.
EX_FLO EQU 2               ; LOW byte of a deferred symbol expression.
EX_FHI EQU 3               ; HIGH byte of a deferred symbol expression.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Publish an unresolved symbol only after the full expression has
; passed syntax, forward-form and addend checks. This is the direct evaluator
; entry for callers that can commit immediately, including proofs.

EX_PARSE:
    LD   A,1                   ; Publish symbols after successful parsing.
    LD   (EX_PSYM),A           ; Record the direct-entry policy.
    JR   EX_PCOMM              ; Join common parser initialization.

;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IY
; Parse without changing the symbol arena. The parser and statement layers use
; this entry to validate and reserve work before publication.

EX_PDEFR:
    XOR  A                     ; Select deferred symbol publication.
    LD   (EX_PSYM),A           ; Leave symbol creation to the caller.
EX_PCOMM:                   ; Initialise state for both public entries.

; Save '$', clear all bounded-stack state and begin in primary position.

    LD   (EX_CADR),BC          ; Preserve the current address used by '$'.
    XOR  A                     ; Form the common zero initial state.
    LD   (EX_VDEPT),A          ; Empty the value stack logically.
    LD   (EX_ODEPT),A          ; Empty the operator stack logically.
    LD   (EX_PDEPT),A          ; Reset parenthesis nesting depth.
    INC  A                     ; Form true for “expect a primary”.
    LD   (EX_EOP),A            ; Begin in the primary half of the grammar.
.PLOOP:                     ; Alternate primary and operator grammar.

; EX_EOP selects the grammar half. Primaries clear it after publication;
; binary operators set it after consuming themselves.

    LD   A,(EX_EOP)            ; Read the current grammar half.
    OR   A                     ; Z selects the operator/delimiter half.
    JR   Z,.POPER              ; Parse what follows an existing value.
    CALL EX_POP                ; Parse and publish one primary expression.
    RET  C                     ; Return its positioned failure unchanged.
    JR   .PLOOP                ; Continue with an operator or delimiter.
.POPER:                     ; Parse after a completed value.
    CALL EX_POPER              ; Parse operator, ')' or delimiter.
    RET  C                     ; Return its positioned failure unchanged.
    JR   NZ,.PLOOP             ; Nonzero means an operator/group was consumed.

; A delimiter at parenthesis depth zero ends the expression. Reduce the
; remaining operators and require exactly one value.

    CALL EX_FSTAC              ; Reduce the stacks to one final value.
    RET  C                     ; Preserve reduction or invariant failure.
    LD   A,(EX_RUNRE)          ; Inspect the final value's resolution state.
    OR   A                     ; Z identifies a concrete 24-bit result.
    JR   NZ,.FUNRESOL          ; Complete one deferred symbol expression.
    CALL EX_REQW               ; Check public −32768..65535 word range.
    RET  C                     ; Return range failure at the delimiter.
    LD   HL,(EX_RVAL)          ; Return the concrete low sixteen bits.
    XOR  A                     ; Return EX_RESOL with carry clear.
    RET                        ; Complete the concrete expression.
.FUNRESOL:                  ; Finish one-symbol deferred expression.

; Pending references store only signed-byte addends. Parsing has
; already reduced the full expression before this range check.

    CALL EX_RADDE              ; Check signed-byte pending addend.
    RET  C                     ; Preserve a forward-form range failure.
    LD   A,(EX_PSYM)           ; Read the selected publication policy.
    OR   A                     ; Z means the caller owns publication.
    JR   Z,.FINDEFR            ; Return the packed key directly in that mode.

; The publishing entry creates or reuses an undefined symbol here, after
; every expression check has succeeded. Invalid source cannot leak a symbol.

    LD   HL,EX_RKEY            ; Supply the validated six-byte packed key.
    CALL SY_REF                ; Find or create its undefined symbol record.
    JR   C,EX_SFAIL            ; Wrap scope or symbol-capacity failure.
.RUNRESOL:                  ; Return unresolved symbol and addend.
    LD   HL,(EX_RVAL)          ; Return the signed addend in HL.
    LD   A,EX_UNRES            ; Report a deferred expression result.
    OR   A                     ; Clear carry while keeping A nonzero.
    RET                        ; Return symbol/addend carriers to the caller.
.FINDEFR:                   ; Return unpublished key to caller.

; The deferred entry returns a pointer into expression workspace. Its caller
; must copy the key before another expression operation reuses this storage.

    LD   IX,EX_RKEY            ; Point IX at the unpublished key.
    JR   .RUNRESOL             ; Share unresolved result completion.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Preserve the nested symbol status for diagnostics and report the expression
; layer's symbol-error category at the original name position.

EX_SFAIL:
    LD   (EX_SSTAT),A          ; Preserve the nested symbol status.
    LD   A,EX_SSYM             ; Select the public expression symbol category.
    JP   EX_FSYM               ; Fail at the original symbol-name position.

;@ROUTINE IN A,IX,HL,DE,B OUT A,CARRY CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Adapt the result to the pending-reference ABI. The caller supplies
; A=source part, DE=patch address and B=patch kind; parsing supplies IX=symbol
; and HL=signed addend. SY_ADD expects that addend in C.

EX_QUEUE:
    LD   C,L                   ; Put checked signed addend in C.
    JP   SY_ADD                ; Tail-call pending-record publication.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise LOW(...) and the four-character HIG* prefix without consuming the
; following token. Only the first packed RADIX-40 word is compared, so LOW is
; exact but any valid four-character name beginning HIG currently selects the
; HIGH operation. The next non-space source byte must then be '('.

EX_CFUNC:
; Length narrows candidates to LOW or four-character HIG* names.
; C holds the marker until a match returns it in A.

    LD   A,(TK_REC+TK_LOFF1)   ; Read the candidate name's byte length.
    CP   3                     ; Could it be LOW?
    JR   Z,.CLSLO              ; Yes: select the LOW signature.
    CP   4                     ; Could it be a four-character HIG* name?
    JR   NZ,.NFUNCTIO          ; Other lengths are ordinary symbols.
    LD   C,EX_UHI              ; Select the HIGH unary marker.
    LD   DE,$336F              ; Select the packed first word for HIG*.
    JR   .CFPACK               ; Pack and compare the candidate.
.CLSLO:                     ; Select LOW signature and marker.
    LD   C,EX_ULO              ; Select the LOW unary marker.
    LD   DE,$4D6F              ; Select the packed LOW signature.
.CFPACK:                    ; Pack and compare the prospective function name.

; Pack the lexeme into EX_RKEY and compare its first word with
; LOW or the HIG prefix selected above.

    PUSH DE                    ; Preserve the selected packed signature.
    PUSH BC                    ; Preserve the marker and caller register B.
    LD   HL,(TK_REC+TK_LOFF)   ; Load the candidate lexeme address.
    LD   B,A                   ; Supply its length to the RADIX-40 packer.
    LD   DE,EX_RKEY            ; Use result-key workspace as temporary output.
    CALL EN_R40PK              ; Pack case-insensitively for exact comparison.
    POP  BC                    ; Restore marker C and caller B.
    POP  DE                    ; Restore the selected signature.
    JR   C,.NFUNCTIO           ; Invalid packed text is not a function name.
    LD   HL,(EX_RKEY)          ; Load the candidate's first packed word.
    OR   A                     ; Clear carry before subtraction.
    SBC  HL,DE                 ; Compare it with LOW or HIG*.
    JR   NZ,.NFUNCTIO          ; A mismatch leaves it as an ordinary name.

; TK_SCURS starts immediately after the name. Read through horizontal space
; directly so classification does not advance or overwrite TK_REC.

    LD   HL,(TK_SCURS)         ; Start lookahead immediately after the name.
    LD   DE,(TK_SEND)          ; Load the source part's exclusive end offset.
.FLOOKAHE:                  ; Scan for opening parenthesis.
    LD   A,H                   ; Compare cursor and end high bytes first.
    CP   D                     ; Are they in the same 256-byte page?
    JR   NZ,.FLB               ; No: the cursor has not reached the exact end.
    LD   A,L                   ; Compare their low bytes.
    CP   E                     ; Has lookahead reached the exclusive end?
    JR   Z,.NFUNCTIO           ; Yes: no opening parenthesis follows.
.FLB:                       ; Read the next function-lookahead source byte.
    PUSH DE                    ; Preserve source end across host access.
    PUSH HL                    ; Preserve cursor across host access.
    LD   A,(TK_SPART)          ; Supply the active source-part ordinal.
    CALL TK_SREAD              ; Read without advancing tokenizer.
    POP  HL                    ; Restore the lookahead cursor.
    POP  DE                    ; Restore the source end.
    CP   $20                   ; Is this an ASCII space?
    JR   Z,.FLSPACE            ; Yes: skip it and continue looking.
    CP   $09                   ; Is this a horizontal tab?
    JR   Z,.FLSPACE            ; Yes: skip it too.
    CP   $28                   ; Is the next significant byte '('?
    JR   NZ,.NFUNCTIO          ; No: treat the name as an ordinary symbol.
    LD   A,C                   ; Return the selected LOW/HIGH marker.
    OR   A                     ; Clear carry to report function recognition.
    RET                        ; Leave the tokenizer record unchanged.
.FLSPACE:                   ; Skip one space or tab during function lookahead.
    INC  HL                    ; Advance past one horizontal-space byte.
    JR   .FLOOKAHE             ; Inspect the next source byte.
.NFUNCTIO:                  ; Treat name as an ordinary symbol.
    SCF                        ; Report that the name is not a byte function.
    RET                        ; Leave A unspecified for ordinary name.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push unary or function marker A with the token position. These markers
; have highest precedence and reduce after their value.

EX_PHOPE:
    LD   (EX_OPER),A           ; Store the encoded unary/function operator.
    CALL EX_COPOS              ; Attach the current token's source position.
    JP   EX_POPE1              ; Tail-call bounded operator-stack push.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Parse a value-starting token with EX_EOP set. '+', '-' and '~' become
; unary markers, while '(' is an operator-stack marker
; and increments the independent nesting depth.

EX_POP:
    LD   A,(TK_REC+TK_KOFF)    ; Read the current primary-position token kind.
    CP   TK_PLUS               ; Is it unary plus?
    JR   Z,.PUNARY             ; Encode and stack the prefix operator.
    CP   TK_MINUS              ; Is it unary minus?
    JR   Z,.PUNARY             ; Encode and stack the prefix operator.
    CP   TK_TILDE              ; Is it unary complement?
    JR   Z,.PUNARY             ; Encode and stack the prefix operator.
    CP   TK_NUMBE              ; Is it a numeric or character literal?
    JR   Z,.PNUMBER            ; Publish its tokenizer-provided value.
    CP   TK_CUR                ; Is it the current-address marker '$'?
    JR   Z,.PCUR               ; Publish the saved current address.
    CP   TK_NAME               ; Is it a symbol or LOW/HIGH function name?
    JR   Z,.PNAME              ; Classify and resolve it.
.RLPAREN:                   ; Check for required opening '('.

; LOW or HIGH classification rejoins here after consuming the function name.
; The next token must begin its parenthesised argument.

    CP   TK_LPARE              ; Is this an opening parenthesis?
    JR   Z,.PPAREN             ; Push a grouping marker when it is.
    LD   A,EX_SEPRI            ; Otherwise report a missing primary.
    JP   EX_FHERE              ; Anchor failure at the current token.
.PUNARY:                    ; Convert and push a prefix operator.

; Token ordinals for '+', '-' and '~' become their $7x unary forms by setting
; the precedence nibble.

    OR   $70                   ; Add unary precedence to token kind.
    CALL EX_PHOPE              ; Push it with its source position.
    RET  C                     ; Preserve operator-stack capacity failure.
    JP   EX_NTOK               ; Consume prefix and expect a primary.
.PPAREN:                    ; Open a parenthesized expression group.
    LD   A,EX_MLPAR            ; Select the non-reducing group marker.
    LD   (EX_OPER),A           ; Store it in the current operator record.
    CALL EX_COPOS              ; Attach the opening parenthesis position.
    CALL EX_POPE1              ; Push the complete marker record.
    RET  C                     ; Preserve stack-capacity failure.
    LD   HL,EX_PDEPT           ; Address the independent nesting depth.
    INC  (HL)                  ; Record one open group.
    JP   EX_NTOK               ; Consume '(' and expect its first primary.
.PNUMBER:                   ; Publish a numeric or character literal value.

; Literal tokens already contain their checked 16-bit value. EX_SRW expands it
; to a resolved, positive 24-bit working value.

    LD   HL,(TK_REC+TK_VOFF)   ; Load the tokenizer's checked literal value.
    CALL EX_SRW                ; Store resolved 24-bit value.
    JR   .PFIN                 ; Consume the token and publish the value.
.PCUR:                      ; Publish the saved current output address.
    LD   HL,(EX_CADR)          ; Load the expression's saved current address.
    CALL EX_SRW                ; Store resolved 24-bit value.
    JR   .PFIN                 ; Consume '$' and publish the value.
.PNAME:                     ; Distinguish a byte function from a symbol name.

; LOW and HIGH are identified before symbol packing. Other names use the
; symbol resolver, which may produce a concrete value or a deferred key.

    CALL EX_CFUNC              ; Recognize LOW/HIGH only when followed by '('.
    JR   NC,.PFUNCTIO          ; Stack the function marker when recognized.
    CALL EX_PNAME              ; Resolve or defer an ordinary symbol name.
    RET  C                     ; Preserve packing, scope or tokenizer failure.
    JR   .PPUBLISH             ; Symbol parsing consumed the name.
.PFIN:                      ; Advance before value publication.

; Numbers and '$' consume the next token before publishing the value stack
; entry. Symbol parsing performs its own token advance.

    CALL EX_NTOK               ; Advance beyond the literal or '$'.
    RET  C                     ; Preserve a lexical failure in the next token.
.PPUBLISH:                  ; Push primary and apply prefixes.
    CALL EX_PVAL               ; Push the complete ten-byte working value.
    RET  C                     ; Preserve value-stack capacity failure.

; Apply prefixes as soon as their primary is complete. This keeps
; the operator stack iterative rather than using Z80 recursion.

    CALL EX_AUNAR              ; Reduce prefixes above this primary.
    RET  C                     ; Preserve unary or forward-form failure.
    XOR  A                     ; Switch to the operator grammar half.
    LD   (EX_EOP),A            ; Record that one value is now available.
    RET                        ; Return to the main parse loop.
.PFUNCTIO:                  ; Stack LOW or HIGH and consume its function name.

; Retain the LOW or HIGH marker, consume the name and feed the following '('
; back through the same parenthesis path used for ordinary grouping.

    CALL EX_PHOPE              ; Push LOW/HIGH at function name.
    RET  C                     ; Preserve operator-stack capacity failure.
    CALL EX_NTOK               ; Consume the function name.
    RET  C                     ; Preserve lexical failure before its argument.
    LD   A,(TK_REC+TK_KOFF)    ; Read the required following token kind.
    JR   .RLPAREN              ; Reuse ordinary opening-parenthesis handling.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
; Parse the grammar half that follows a value. A recognised binary operator is
; compared with stacked precedence before it is pushed. A right parenthesis
; reduces back to its marker. Any other token is the caller's delimiter.

EX_POPER:
    LD   A,(TK_REC+TK_KOFF)    ; Read the token following a complete value.
    CP   TK_RPARE              ; Is it a closing parenthesis?
    JR   Z,.RPAREN             ; Reduce and close the current group.
    CALL EX_COPER              ; Classify a possible binary operator.
    JR   C,.DELIMITE           ; Non-operators terminate the expression.

; Preserve the incoming operator while older operators of higher precedence,
; or equal precedence for left-associative operators, are reduced.

    CALL EX_SINCO              ; Save the newly read operator record.
    CALL EX_RINC1              ; Reduce older operators that bind first.
    RET  C                     ; Preserve reduction failure.
    CALL EX_RINCO              ; Restore the incoming operator record.
    CALL EX_POPE1              ; Push it after capacity checking.
    RET  C                     ; Preserve operator-stack capacity failure.
    LD   A,1                   ; Switch back to primary grammar.
    LD   (EX_EOP),A            ; Record that a right operand is required.
    CALL EX_NTOK               ; Consume the binary operator.
    RET  C                     ; Preserve right-operand lexical failure.
    XOR  A                     ; Form carry-clear success flags.
    INC  A                     ; Return nonzero: parsing must continue.
    RET                        ; Return to the main parse loop.
.RPAREN:                    ; Reduce and close one parenthesized group.

; A ')' closes only an active group. Reduce to its marker, remove it, consume
; the token and then apply a preceding LOW, HIGH or other unary operator.

    LD   A,(EX_PDEPT)          ; Read the number of open groups.
    OR   A                     ; Is this ')' outside the expression's groups?
    JR   Z,.DELIMITE           ; Yes: leave it for the caller as a delimiter.
    CALL EX_RTPAR              ; Reduce back to the nearest group marker.
    RET  C                     ; Preserve reduction or invariant failure.
    CALL EX_POPE2              ; Remove that left-parenthesis marker.
    RET  C                     ; Preserve defensive stack-underflow failure.
    LD   HL,EX_PDEPT           ; Address the nesting depth.
    DEC  (HL)                  ; Close one group.
    CALL EX_NTOK               ; Consume the right parenthesis.
    RET  C                     ; Preserve lexical failure after the group.
    CALL EX_AUNAR              ; Apply a preceding unary or byte function.
    RET  C                     ; Preserve unary or forward-form failure.
    XOR  A                     ; Form carry-clear success flags.
    INC  A                     ; Return nonzero: parsing must continue.
    RET                        ; Return to the main parse loop.
.DELIMITE:                  ; Validate caller delimiter.

; A delimiter is valid only outside parentheses. Leave TK_REC unchanged so the
; statement or operand parser can interpret it.

    LD   A,(EX_PDEPT)          ; Check for an unclosed parenthesis group.
    OR   A                     ; Z means the expression is at outer depth.
    JR   Z,.DDONE              ; Accept the current token as caller delimiter.
    LD   A,EX_SERIG            ; Report missing right parenthesis.
    JP   EX_FHERE              ; Anchor it at the encountered delimiter.
.DDONE:                     ; Leave delimiter for caller.
    XOR  A                     ; Return zero to signal expression completion.
    RET                        ; Leave TK_REC on the caller's delimiter.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE,IY
; Resolve the name while retaining its exact source position for symbol
; diagnostics. The packed key stays in EX_RKEY for a possible deferred result.

EX_PNAME:
    LD   A,(TK_REC+TK_POFF)    ; Capture the name token's source-part ordinal.
    LD   (EX_SPART),A          ; Preserve it for errors and pending records.
    LD   HL,(TK_REC+TK_SOFF)   ; Capture the name token's source-byte offset.
    LD   (EX_SOFF),HL          ; Save symbol diagnostic position.
    CALL TK_LLEXE              ; Expose the current name text as HL/B.
    LD   DE,EX_RKEY            ; Select the six-byte packed-key workspace.
    CALL EN_PSYM               ; Pack and validate the symbol name.
    JP   C,EX_SFAIL            ; Wrap a naming or scope-independent failure.
    LD   HL,EX_RKEY            ; Supply the packed key for lookup.
    CALL SY_FIND               ; Search current global/private symbol state.
    JR   C,.PMISSING           ; Distinguish absence from other lookup errors.

; Bit 6 marks a defined record. An undefined record and a missing name both
; become the same deferred value. Defined EQU records use bit 5 to retain the
; negative interpretation of their 16-bit stored value.

    BIT  6,(IX+5)              ; Is the found record already defined?
    JR   Z,.PUNRESOL           ; No: carry it as a deferred symbol.
    LD   L,(IX+SY_VALLO)       ; Load its stored value low byte.
    LD   H,(IX+SY_VALHI)       ; Complete the stored sixteen-bit value.
    BIT  5,(IX+5)              ; Is this a negative EQU constant?
    JR   Z,.PPSYM              ; No: zero-extend the ordinary address/value.

; Sign-extend a negative EQU into the 24-bit arithmetic domain.

    LD   (EX_RVAL),HL          ; Store the constant's low sixteen bits.
    LD   A,$FF                 ; Form its negative sign-extension byte.
    LD   (EX_RVAL+2),A         ; Complete the signed 24-bit value.
    XOR  A                     ; Mark the result concrete.
    JR   .SUNRESOL             ; Store resolution state and consume the name.
.PPSYM:                     ; Publish a defined non-negative symbol value.
    CALL EX_SRW                ; Store concrete zero-extended word.
    JP   EX_NTOK               ; Consume the symbol token and return.
.PMISSING:                  ; Check why lookup failed.

; SY_FIND errors other than not-found, such as a private name outside a global
; scope, retain their symbol status and fail immediately.

    CP   SY_SNFOU              ; Was the only problem an absent record?
    JR   Z,.PUNRESOL           ; Yes: create a deferred value in workspace.
    JP   EX_SFAIL              ; Otherwise preserve the nested symbol failure.
.PUNRESOL:                  ; Initialise deferred symbol at zero.

; A missing or already-undefined symbol starts with addend zero and the plain
; deferred transform. A later reduction may adjust the addend or transform.

    XOR  A                     ; Form a zero initial addend.
    LD   (EX_RVAL),A           ; Clear addend low byte.
    LD   (EX_RVAL+1),A         ; Clear addend middle byte.
    LD   (EX_RVAL+2),A         ; Clear addend sign byte.
    INC  A                     ; Select EX_FPLAI deferred state.
.SUNRESOL:                  ; Store resolution state and consume token.
    LD   (EX_RUNRE),A          ; Record concrete/plain/LOW/HIGH result state.
    JP   EX_NTOK               ; Consume the name and return.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C,HL
; Map contiguous operator tokens to a packed byte. Its high nibble is
; precedence and its low nibble is the reduction ordinal. Zero entries
; cover token kinds that are not binary expression operators.

EX_COPER:
    LD   A,(TK_REC+TK_KOFF)    ; Load the prospective operator token kind.
    SUB  TK_PLUS               ; Normalise operator token range.
    CP   12                    ; Does it lie within the twelve-entry table?
    JR   NC,.ODELIMIT          ; No: it is an expression delimiter.
    PUSH DE                    ; Preserve caller DE during table addressing.
    LD   E,A                   ; Put the zero-based token index in DE.
    LD   D,0                   ; Zero-extend it for address arithmetic.
    LD   HL,EX_OTABL           ; Point at packed operator classifications.
    ADD  HL,DE                 ; Address the current token's classification.
    LD   A,(HL)                ; Load precedence and reduction ordinal.
    POP  DE                    ; Restore caller DE.
    OR   A                     ; Zero means “not binary”.
    JR   Z,.ODELIMIT           ; Treat unary-only tokens as delimiters here.
    LD   (EX_OPER),A           ; Start the current operator record.
    CALL EX_COPOS              ; Attach its exact source position.
    OR   A                     ; Clear carry to report recognition.
    RET                        ; Return packed operator in EX_OPER.
.ODELIMIT:                  ; Report a non-binary token.
    SCF                        ; Report that no binary operator matched.
    RET                        ; Leave the tokenizer record unchanged.

; Token order from TK_PLUS: +, -, *, /, %, &, ^, |, ~, apostrophe, <<, >>.
; Tilde is unary-only and apostrophe is a delimiter, so both table entries are
; zero.

EX_OTABL:                   ; Map token kinds to precedence and reduction.
    DB $55,$56,$67,$68,$69,$32,$21,$10,0,0,$43,$44  ; Operator fields.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Store the source position of the current operator beside its encoded byte.
; Arithmetic and forward-form failures later report this position.

EX_COPOS:
    LD   A,(TK_REC+TK_POFF)    ; Load operator source part.
    LD   (EX_OPART),A          ; Store it in the current operator record.
    LD   HL,(TK_REC+TK_SOFF)   ; Load the operator token's source-byte offset.
    LD   (EX_OOFF),HL          ; Complete the positioned operator record.
    RET                        ; Return without changing tokenizer state.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the complete ten-byte working value after proving stack capacity. The
; entry includes a packed key even for concrete values, keeping stack
; movement uniform.

EX_PVAL:
    LD   A,(EX_VDEPT)          ; Read the number of live value records.
    CP   EX_VCAP               ; Has the fixed sixteen-entry stack filled?
    JP   NC,EX_CFAIL           ; Yes: report capacity at the current token.
    CALL EX_VADR               ; Locate the first unused record.
    LD   D,H                   ; Copy its destination address high byte.
    LD   E,L                   ; Complete the destination pointer in DE.
    LD   HL,EX_RVAL            ; Point at the current ten-byte value record.
    LD   BC,EX_VALB            ; Select the complete fixed record size.
    LDIR                       ; Copy value, state and key to stack.
    LD   HL,EX_VDEPT           ; Address the live-depth counter.
    INC  (HL)                  ; Publish the newly copied record.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Preserve the stack entry for later reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the right operand into EX_RVAL.

EX_PVAL1:
    LD   DE,EX_RVAL            ; Select the right-value working record.
    JR   EX_PVTO               ; Share bounded stack pop and copy.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the left operand into EX_LVAL. Fall through to the shared copy body.

EX_PLVAL:
    LD   DE,EX_LVAL            ; Select the left-value working record.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Decrement value depth, locate the last entry and copy its ten bytes to
; destination DE. Empty-stack access is an internal parser fault.

EX_PVTO:
    PUSH DE                    ; Preserve the caller's selected destination.
    LD   A,(EX_VDEPT)          ; Read the current live value depth.
    OR   A                     ; Is the stack empty?
    JR   Z,EX_PVEMP            ; Yes: report an internal parser fault.
    DEC  A                     ; Select the newest live record index.
    LD   (EX_VDEPT),A          ; Remove it logically before copying.
    CALL EX_VADR               ; Convert the index into source address HL.
    POP  DE                    ; Restore the requested working destination.
    LD   BC,EX_VALB            ; Select one complete value record.
    LDIR                       ; Copy it out of the stack.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Leave the decremented depth published.
EX_PVEMP:                   ; Restore stack after value underflow.
    POP  DE                    ; Restore stack balance on the failure path.
    JR   EX_IFAIL              ; Report defensive value-stack underflow.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert value index A to EX_VSTAC + A*10 without multiplication support.

EX_VADR:
    LD   E,A                   ; Preserve the original index in low DE.
    LD   D,0                   ; Zero-extend it to sixteen bits.
    LD   H,D                   ; Initialize HL high byte to zero.
    LD   L,E                   ; Copy the index into HL.
    ADD  HL,HL                 ; Form index times two.
    ADD  HL,HL                 ; Form index times four.
    ADD  HL,HL                 ; Form index times eight.
    EX   DE,HL                 ; Keep index*8 in DE and restore index in HL.
    ADD  HL,HL                 ; Form the remaining index*2.
    ADD  HL,DE                 ; Combine them into index*10.
    LD   DE,EX_VSTAC           ; Load the value-stack base address.
    ADD  HL,DE                 ; Return the selected record address.
    RET                        ; Return record address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the current four-byte operator record after proving stack capacity.

EX_POPE1:
    LD   A,(EX_ODEPT)          ; Read the number of live operator records.
    CP   EX_OCAP               ; Has the fixed sixteen-entry stack filled?
    JR   NC,EX_CFAIL           ; Yes: report capacity at the current token.
    CALL EX_OADR               ; Locate the first unused operator record.
    LD   D,H                   ; Copy its destination address high byte.
    LD   E,L                   ; Complete the destination pointer in DE.
    LD   HL,EX_OPER            ; Point at current operator record.
    LD   BC,EX_OPERB           ; Select the complete fixed record size.
    LDIR                       ; Copy operator and position onto the stack.
    LD   HL,EX_ODEPT           ; Address the live-depth counter.
    INC  (HL)                  ; Publish the newly copied operator.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Leave the record available to reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the most recent operator into EX_OPER. As with the value stack, an empty
; pop is an internal invariant failure rather than a source diagnostic.

EX_POPE2:
    LD   A,(EX_ODEPT)          ; Read the current live operator depth.
    OR   A                     ; Is the stack empty?
    JR   Z,EX_IFAIL            ; Yes: report defensive underflow.
    DEC  A                     ; Select the newest live record index.
    LD   (EX_ODEPT),A          ; Remove it logically before copying.
    CALL EX_OADR               ; Convert its index into source address HL.
    LD   DE,EX_OPER            ; Select the current-operator destination.
    LD   BC,EX_OPERB           ; Select one complete operator record.
    LDIR                       ; Restore operator and source position.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Leave the decremented depth published.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert operator index A to EX_OSTAC + A*4.

EX_OADR:
    LD   L,A                   ; Place the operator index in low HL.
    LD   H,0                   ; Zero-extend it to sixteen bits.
    ADD  HL,HL                 ; Form index times two.
    ADD  HL,HL                 ; Form index times four.
    LD   DE,EX_OSTAC           ; Load the operator-stack base.
    ADD  HL,DE                 ; Return the selected record address.
    RET                        ; Return operator address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; Peek at newest operator byte without changing stack depth.
; Carry set reports an empty stack; otherwise A contains the encoded operator.

EX_POPE3:
    LD   A,(EX_ODEPT)          ; Read the live operator depth.
    OR   A                     ; Test whether any operator is available.
    SCF                        ; Prepare the empty-stack failure result.
    RET  Z                     ; Return carry set when depth is zero.
    DEC  A                     ; Select the newest live record index.
    CALL EX_OADR               ; Locate that record without changing depth.
    LD   A,(HL)                ; Return its packed operator byte.
    OR   A                     ; Clear carry for a successful peek.
    RET                        ; Leave the stack unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack-capacity failures use the current tokenizer position.

EX_CFAIL:
    LD   A,EX_SCAP             ; Select the bounded-stack capacity category.
    JP   EX_FHERE              ; Fail at the current tokenizer position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack underflow and unmatched internal markers are defensive failures. Valid
; source should reach a specific syntax status before this path.

EX_IFAIL:
    LD   A,EX_SINT             ; Select the internal-invariant category.
    JP   EX_FHERE              ; Fail at the current tokenizer position.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Save the current operator record while precedence reduction overwrites
; EX_OPER with older stack entries.

EX_SINCO:
    LD   HL,EX_OPER            ; Select the current operator as copy source.
    LD   DE,EX_INCOM           ; Select incoming-operator save storage.
    JR   EX_CINCO              ; Copy the complete positioned record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Restore the saved incoming operator before pushing it.

EX_RINCO:
    LD   HL,EX_INCOM           ; Select the saved incoming operator.
    LD   DE,EX_OPER            ; Restore it as the current record.

;@ROUTINE IN HL,DE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Copy one complete four-byte operator record from HL to DE.

EX_CINCO:
    LD   BC,EX_OPERB           ; Select all four operator-record bytes.
    LDIR                       ; Copy operator plus exact source position.
    RET                        ; Return after the fixed-size transfer.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce stacked binary operators before accepting incoming operator.
; High nibbles hold precedence. A stacked operator reduces when its precedence
; is higher, or equal for the left-associative operator set used here.

EX_RINC1:
.RILOOP:                    ; Compare stacked and incoming precedence.
    CALL EX_POPE3              ; Peek at the newest stacked operator.
    JR   C,.RIDONE             ; Empty stack leaves nothing to reduce.
    CP   EX_MLPAR              ; Is the group marker on top?
    JR   Z,.RIDONE             ; Never reduce across a parenthesis boundary.

; Compare only precedence nibbles. Lower numeric values bind less tightly.

    AND  $F0                   ; Keep only the stacked precedence nibble.
    LD   B,A                   ; Preserve it for comparison.
    LD   A,(EX_INCOM)          ; Load the incoming packed operator.
    AND  $F0                   ; Keep only its precedence nibble.
    CP   B                     ; Compare incoming against stacked precedence.
    JR   C,.RINOW              ; Lower incoming precedence reduces now.
    RET  NZ                    ; Higher incoming precedence delays reduction.
.RINOW:                     ; Reduce the currently exposed older operator.
    CALL EX_REDUC              ; Equal or older-higher precedence reduces now.
    RET  C                     ; Preserve arithmetic or forward-form failure.
    JR   .RILOOP               ; Compare the next stacked operator.
.RIDONE:                    ; Finish incoming-precedence reduction.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Leave the saved incoming operator untouched.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce until the nearest left-parenthesis marker is exposed. The caller then
; pops the marker itself. Reaching the bottom first is an internal mismatch.

EX_RTPAR:
.RTPLOOP:                   ; Reduce up to left parenthesis.
    CALL EX_POPE3              ; Peek at the newest stacked operator.
    JR   C,EX_IFAIL            ; No marker means inconsistent nesting state.
    CP   EX_MLPAR              ; Has the nearest group boundary been exposed?
    RET  Z                     ; Yes: leave it for the caller to pop.
    CALL EX_REDUC              ; Reduce one binary operator inside the group.
    RET  C                     ; Preserve arithmetic or forward-form failure.
    JR   .RTPLOOP              ; Continue until the marker reaches the top.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Apply every consecutive unary marker above the newly published primary. A
; concrete value supports all five. A deferred value supports unary '+'
; and one LOW or HIGH transform only because the pending ABI stores no tree.

EX_AUNAR:
.AULOOP:                    ; Inspect and apply the next stacked unary marker.
    CALL EX_POPE3              ; Peek at the operator above the new primary.
    JR   C,.AUDONE             ; Empty stack means no prefix is pending.
    AND  $F0                   ; Isolate the operator's precedence band.
    CP   $70                   ; Does it belong to the unary/function band?
    JR   NZ,.AUDONE            ; No: leave it for binary precedence handling.
    CALL EX_POPE2              ; Pop unary operator and position.
    RET  C                     ; Preserve defensive underflow failure.
    CALL EX_PVAL1              ; Pop the operand into EX_RVAL.
    RET  C                     ; Preserve defensive value underflow.
    LD   A,(EX_RUNRE)          ; Read concrete/deferred operand state.
    OR   A                     ; Z identifies a concrete operand.
    JR   Z,.AUCONCRE           ; Dispatch full concrete unary semantics.

; Deferred minus and complement cannot be represented. LOW or HIGH can be
; applied only to a plain deferred symbol and become its patch transform.

    LD   A,(EX_OPER)           ; Load the deferred operand's unary marker.
    CP   EX_UPLUS              ; Unary plus leaves a deferred form unchanged.
    JR   Z,.AUPUBLIS           ; Republish it directly.
    CP   EX_ULO                ; Is this LOW(...) projection?
    JR   Z,.AUFLO              ; Select the low-byte deferred transform.
    CP   EX_UHI                ; Is this HIGH(...) projection?
    JR   Z,.AUFHI              ; Select the high-byte deferred transform.
.AUFFAIL:                   ; Reject deferred form needing a tree.
    LD   A,EX_SFFOR            ; Report a form that needs an expression tree.
    JP   EX_FOPER              ; Anchor failure at the unary operator.
.AUFLO:                     ; Select the deferred LOW transform.
    LD   B,EX_FLO              ; Select the deferred LOW transform state.
    JR   .AUFFUNCT             ; Share single-transform validation.
.AUFHI:                     ; Select the deferred HIGH transform.
    LD   B,EX_FHI              ; Select the deferred HIGH transform state.
.AUFFUNCT:                  ; Validate and attach one deferred byte transform.
    LD   A,(EX_RUNRE)          ; Read existing deferred transform.
    CP   EX_FPLAI              ; Is it still the plain symbol form?
    JR   NZ,.AUFFAIL           ; Reject nested LOW or HIGH.
    LD   A,B                   ; Recover the newly selected transform.
    LD   (EX_RUNRE),A          ; Attach it to the deferred result.
    JR   .AUPUBLIS             ; Republish the transformed operand.
.AUCONCRE:                  ; Dispatch concrete unary operation.

; Dispatch concrete unary operations. LOW clears the upper bytes; HIGH moves
; the middle byte down and clears the rest.

    LD   A,(EX_OPER)           ; Load the concrete unary marker.
    CP   EX_UPLUS              ; Is it the identity operation?
    JR   Z,.AUPUBLIS           ; Yes: republish without arithmetic.
    CP   EX_UMINU              ; Is it arithmetic negation?
    JR   Z,.AUNEGATE           ; Negate modulo 24 bits.
    CP   EX_UTILD              ; Is it bitwise complement?
    JR   Z,.AUCOMPLE           ; Complement all three working bytes.
    CP   EX_ULO                ; Is it LOW(...) projection?
    JR   Z,.AULO               ; Keep only the low byte.
    CP   EX_UHI                ; Is it HIGH(...) projection?
    JR   Z,.AUHI               ; Move the middle byte down.
    JP   EX_IFAIL              ; Other marker is an invariant failure.
.AUNEGATE:                  ; Negate the concrete 24-bit operand.
    CALL EX_NRES               ; Negate the concrete 24-bit result.
    JR   .AUCDONE              ; Check arithmetic status before republishing.
.AUCOMPLE:                  ; Complement the concrete 24-bit operand.
    CALL EX_CRES               ; Complement the concrete 24-bit result.
    JR   .AUCDONE              ; Check arithmetic status before republishing.
.AULO:                      ; Keep only the concrete low byte.
    XOR  A                     ; Form zero for discarded upper bytes.
    LD   (EX_RVAL+1),A         ; Clear the middle byte.
    LD   (EX_RVAL+2),A         ; Clear the high/sign byte.
    JR   .AUCDONE              ; Republish the projected low byte.
.AUHI:                      ; Select concrete word's high byte.
    LD   A,(EX_RVAL+1)         ; Load the original value's middle byte.
    LD   (EX_RVAL),A           ; Move it into the result low byte.
    XOR  A                     ; Form zero for discarded upper bytes.
    LD   (EX_RVAL+1),A         ; Clear the result middle byte.
    LD   (EX_RVAL+2),A         ; Clear the result high/sign byte.
.AUCDONE:                   ; Check concrete unary result.
    RET  C                     ; Preserve arithmetic failure.
.AUPUBLIS:                  ; Publish result for outer prefix.

; Publish the transformed value again so another outer unary marker can apply.

    CALL EX_PVAL               ; Push transformed value to stack.
    RET  C                     ; Preserve value-stack capacity failure.
    JP   .AULOOP               ; Apply any next outer unary marker.
.AUDONE:                    ; Return after all unary markers.
    XOR  A                     ; Return success with carry clear.
    RET                        ; Leave the next binary/group marker stacked.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Finish at the delimiter. Reduce remaining binary operators,
; reject an unmatched left parenthesis and require exactly one final value.

EX_FSTAC:
.FREDUCE:                   ; Reduce remaining binary operators.
    CALL EX_POPE3              ; Peek at the newest remaining operator.
    JR   C,.FINVAL             ; Empty operator stack ends reduction.
    CP   EX_MLPAR              ; Is a left parenthesis unmatched?
    JP   Z,EX_IFAIL            ; Yes: nesting state is inconsistent.
    CALL EX_REDUC              ; Reduce one remaining binary operator.
    RET  C                     ; Preserve arithmetic or forward-form failure.
    JR   .FREDUCE              ; Drain the rest of the operator stack.
.FINVAL:                    ; Pop and validate the sole final value.
    CALL EX_PVAL1              ; Pop the sole expected result into EX_RVAL.
    RET  C                     ; Preserve defensive value underflow.
    LD   A,(EX_VDEPT)          ; Read the depth after removing that result.
    OR   A                     ; Must no other value remain?
    JP   NZ,EX_IFAIL           ; Extra values are an internal fault.
    RET                        ; Return success with final value in workspace.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Pop operator, right and left values, reduce into EX_RVAL then push
; the result. Right-before-left stack order preserves the source operand order
; for subtraction, division, remainder and shifts.

EX_REDUC:
    CALL EX_POPE2              ; Pop binary operator and position.
    RET  C                     ; Preserve defensive operator underflow.
    CALL EX_PVAL1              ; Pop the source-right operand into EX_RVAL.
    RET  C                     ; Preserve defensive value underflow.
    CALL EX_PLVAL              ; Pop the source-left operand into EX_LVAL.
    RET  C                     ; Preserve defensive value underflow.
    CALL EX_RLOAD              ; Reduce concrete or deferred operands.
    RET  C                     ; Preserve arithmetic or forward-form failure.
    JP   EX_PVAL               ; Push the result for later reductions.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Choose concrete or deferred reduction. Concrete operator ordinals index the
; address table after the low nibble has been range-checked.

EX_RLOAD:
    LD   A,(EX_LUNRE)          ; Read the left operand's resolution state.
    LD   B,A                   ; Preserve it while loading the right state.
    LD   A,(EX_RUNRE)          ; Read the right operand's resolution state.
    OR   B                     ; Is either operand deferred?
    JR   NZ,EX_RFORW           ; Yes: enforce the affine forward-form rules.
    LD   A,(EX_OPER)           ; Load the packed concrete binary operator.
    AND  $0F                   ; Keep its reduction-table ordinal.
    CP   10                    ; Does it name one of the ten binary kernels?
    JP   NC,EX_IFAIL           ; Reject a corrupt operator record defensively.
    ADD  A,A                   ; Scale ordinal for a two-byte address entry.
    LD   L,A                   ; Place the table offset in low HL.
    LD   H,0                   ; Zero-extend the offset.
    LD   DE,EX_RTABL           ; Point DE at the concrete reduction table.
    ADD  HL,DE                 ; Address the selected handler pointer.
    LD   E,(HL)                ; Load the handler address low byte.
    INC  HL                    ; Advance to the high byte.
    LD   D,(HL)                ; Complete the handler address in DE.
    EX   DE,HL                 ; Put target in indirect-jump HL.
    JP   (HL)                  ; Dispatch to the concrete arithmetic kernel.

; Order matches EX_OPOR through EX_OREMA in the operator byte's low nibble.

EX_RTABL:                   ; Dispatch concrete binary operations.
    DW EX_OR,EX_XOR,EX_AND     ; Bitwise kernels for ordinals 0 through 2.
    DW EX_SLEFT,EX_SRIGH       ; Left and right shift kernels.
    DW EX_ADD,EX_SUBTR         ; Signed addition and subtraction kernels.
    DW EX_MULTI,EX_DIVID       ; Signed multiplication and division kernels.
    DW EX_REMAI                ; Signed remainder kernel.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce an expression containing one unresolved symbol. LOW and HIGH results
; cannot take further binary arithmetic. Plain forms permit symbol+constant,
; constant+symbol and symbol-constant only.

EX_RFORW:
; EX_FLO or EX_FHI means LOW/HIGH has already consumed the
; symbol form. Any binary operator outside that function is unsupported.

    LD   A,(EX_LUNRE)          ; Read the left deferred-transform state.
    CP   EX_FLO                ; Was the left symbol projected?
    JR   NC,.FFAIL             ; No later binary operation fits.
    LD   A,(EX_RUNRE)          ; Read the right deferred-transform state.
    CP   EX_FLO                ; Was the right symbol projected?
    JR   NC,.FFAIL             ; Yes: reject further binary arithmetic.
    LD   A,(EX_LUNRE)          ; Recheck for a left-side symbol.
    OR   A                     ; Z means the symbol, if any, is on the right.
    JR   Z,.FRIGHT             ; Validate the constant-plus-symbol case.

; When the symbol is on the left, addition and subtraction both preserve one
; symbol. Concrete arithmetic updates the addend in EX_RVAL.

    LD   A,(EX_RUNRE)          ; Is the right operand concrete?
    OR   A                     ; Nonzero would mean two unresolved symbols.
    JR   NZ,.FFAIL             ; Two symbols need an expression tree.
    LD   A,(EX_OPER)           ; Load the packed binary operator.
    AND  $0F                   ; Keep its reduction ordinal.
    CP   EX_OPADD              ; Is this symbol plus constant?
    JR   Z,.FLADD              ; Yes: add the constant to the addend.
    CP   EX_OSUBT              ; Is this symbol minus constant?
    JR   NZ,.FFAIL             ; No other operation preserves one symbol.
    CALL EX_SUBTR              ; Compute left addend minus right constant.
    JR   C,.FRETURN            ; Preserve signed overflow failure.
    JR   .FULKEY               ; Restore the symbol key from the left operand.
.FLADD:                     ; Add constant to left-symbol addend.
    CALL EX_ADD                ; Compute left addend plus right constant.
    JR   C,.FRETURN            ; Preserve signed overflow failure.
.FULKEY:                    ; Restore left operand's packed key.

; The left operand carried the symbol, so replace the right operand's concrete
; key bytes with the left packed key.

    LD   HL,EX_LKEY            ; Point at left packed symbol key.
    LD   DE,EX_RKEY            ; Select the result key destination.
    LD   BC,6                  ; Copy all three packed RADIX-40 words.
    LDIR                       ; Replace unused concrete key.
    JR   .FFIN                 ; Canonicalize and range-check the result.
.FRIGHT:                    ; Reduce constant plus symbol.

; A right-side symbol permits only constant+symbol. constant-symbol would
; require a negated symbol coefficient and cannot fit the pending record.

    LD   A,(EX_OPER)           ; Load the packed binary operator.
    AND  $0F                   ; Keep its reduction ordinal.
    CP   EX_OPADD              ; Is this constant plus symbol?
    JR   NZ,.FFAIL             ; Other operations are unsupported.
    CALL EX_ADD                ; Add constant to symbol addend.
    JR   C,.FRETURN            ; Preserve signed overflow failure.
.FFIN:                      ; Check final deferred result.

; Canonicalise the surviving result as a plain deferred symbol and prove that
; its computed addend fits the signed byte stored by the pending record.

    LD   A,EX_FPLAI            ; Select canonical plain deferred state.
    LD   (EX_RUNRE),A          ; Attach it to the surviving symbol/addend.
    CALL EX_RADDE              ; Require the addend to fit signed eight bits.
.FRETURN:                   ; Return deferred arithmetic status.
    RET                        ; Return range status from arithmetic/checking.
.FFAIL:                     ; Report an unsupported binary forward form.
    LD   A,EX_SFFOR            ; Select unsupported-forward-form status.
    JP   EX_FOPER              ; Anchor it at the binary operator.
