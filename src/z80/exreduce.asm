;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the complete ten-byte working value after proving stack capacity. The
; entry includes a packed key even for concrete values, keeping stack
; movement uniform.

EX_VPUSH: ; Copy the current value into the next bounded stack slot.
    LD   A,(EX_VCNT)                    ; Read the number of live value records.
    CP   EX_VCAP                        ; Has the fixed sixteen-entry stack filled?
    JP   NC,EX_FULL                     ; Yes: report capacity at the current token.
    CALL EX_VSLOT                       ; Locate the first unused record.
    LD   D,H                            ; Copy its destination address high byte.
    LD   E,L                            ; Complete the destination pointer in DE.
    LD   HL,EX_RVAL                     ; Point at the current ten-byte value record.
    LD   BC,EX_VALB                     ; Select the complete fixed record size.
    LDIR                                ; Copy value, state and key to stack.
    LD   HL,EX_VCNT                     ; Address the live-depth counter.
    INC  (HL)                           ; Publish the newly copied record.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the stack entry for later reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the right operand into EX_RVAL.

EX_RPOP: ; Pop the newest value into the right/result record.
    LD   DE,EX_RVAL                     ; Select the right-value working record.
    JR   EX_POPTO                       ; Share bounded stack pop and copy.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the left operand into EX_LVAL. Fall through to the shared copy body.

EX_LPOP: ; Pop the next value into the left operand record.
    LD   DE,EX_LVAL                     ; Select the left-value working record.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Decrement value depth, locate the last entry and copy its ten bytes to
; destination DE. Empty-stack access is an internal parser fault.

EX_POPTO: ; Copy a popped value to DE or report internal underflow.
    PUSH DE                             ; Preserve the caller's selected destination.
    LD   A,(EX_VCNT)                    ; Read the current live value depth.
    OR   A                              ; Is the stack empty?
    JR   Z,.EMPTY                       ; Yes: report an internal parser fault.
    DEC  A                              ; Select the newest live record index.
    LD   (EX_VCNT),A                    ; Remove it logically before copying.
    CALL EX_VSLOT                       ; Convert the index into source address HL.
    POP  DE                             ; Restore the requested working destination.
    LD   BC,EX_VALB                     ; Select one complete value record.
    LDIR                                ; Copy it out of the stack.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the decremented depth published.
.EMPTY: ; Restore stack after value underflow.
    POP  DE                             ; Restore stack balance on the failure path.
    JR   EX_FAULT                       ; Report defensive value-stack underflow.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert value index A to EX_VALS + A*10 without multiplication support.

EX_VSLOT: ; Calculate the address of ten-byte value record A.
    LD   E,A                            ; Preserve the original index in low DE.
    LD   D,0                            ; Zero-extend it to sixteen bits.
    LD   H,D                            ; Initialise HL high byte to zero.
    LD   L,E                            ; Copy the index into HL.
    ADD  HL,HL                          ; Form index times two.
    ADD  HL,HL                          ; Form index times four.
    ADD  HL,HL                          ; Form index times eight.
    EX   DE,HL                          ; Keep index*8 in DE and restore index in HL.
    ADD  HL,HL                          ; Form the remaining index*2.
    ADD  HL,DE                          ; Combine them into index*10.
    LD   DE,EX_VALS                     ; Load the value-stack base address.
    ADD  HL,DE                          ; Return the selected record address.
    RET                                 ; Return record address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the current four-byte operator record after proving stack capacity.

EX_OPUSH: ; Publish a positioned operator after proving stack capacity.
    LD   A,(EX_OCNT)                    ; Read the number of live operator records.
    CP   EX_OCAP                        ; Has the fixed sixteen-entry stack filled?
    JR   NC,EX_FULL                     ; Yes: report capacity at the current token.
    CALL EX_OSLOT                       ; Locate the first unused operator record.
    LD   D,H                            ; Copy its destination address high byte.
    LD   E,L                            ; Complete the destination pointer in DE.
    LD   HL,EX_OPER                     ; Point at current operator record.
    LD   BC,EX_OPERB                    ; Select the complete fixed record size.
    LDIR                                ; Copy operator and position onto the stack.
    LD   HL,EX_OCNT                     ; Address the live-depth counter.
    INC  (HL)                           ; Publish the newly copied operator.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the record available to reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the most recent operator into EX_OPER. As with the value stack, an empty
; pop is an internal invariant failure rather than a source diagnostic.

EX_OPOP: ; Restore the newest positioned operator into EX_OPER.
    LD   A,(EX_OCNT)                    ; Read the current live operator depth.
    OR   A                              ; Is the stack empty?
    JR   Z,EX_FAULT                     ; Yes: report defensive underflow.
    DEC  A                              ; Select the newest live record index.
    LD   (EX_OCNT),A                    ; Remove it logically before copying.
    CALL EX_OSLOT                       ; Convert its index into source address HL.
    LD   DE,EX_OPER                     ; Select the current-operator destination.
    LD   BC,EX_OPERB                    ; Select one complete operator record.
    LDIR                                ; Restore operator and source position.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the decremented depth published.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert operator index A to EX_OPERS + A*4.

EX_OSLOT: ; Calculate the address of four-byte operator record A.
    LD   L,A                            ; Place the operator index in low HL.
    LD   H,0                            ; Zero-extend it to sixteen bits.
    ADD  HL,HL                          ; Form index times two.
    ADD  HL,HL                          ; Form index times four.
    LD   DE,EX_OPERS                    ; Load the operator-stack base.
    ADD  HL,DE                          ; Return the selected record address.
    RET                                 ; Return operator address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; Peek at newest operator byte without changing stack depth.
; Carry set reports an empty stack; otherwise A contains the encoded operator.

EX_OPEEK: ; Read the newest operator without changing stack depth.
    LD   A,(EX_OCNT)                    ; Read the live operator depth.
    OR   A                              ; Test whether any operator is available.
    SCF                                 ; Prepare the empty-stack failure result.
    RET  Z                              ; Return carry set when depth is zero.
    DEC  A                              ; Select the newest live record index.
    CALL EX_OSLOT                       ; Locate that record without changing depth.
    LD   A,(HL)                         ; Return its packed operator byte.
    OR   A                              ; Clear carry for a successful peek.
    RET                                 ; Leave the stack unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack-capacity failures use the current tokenizer position.

EX_FULL: ; Report a full bounded stack at the current token.
    LD   A,EX_SCAP                      ; Select the bounded-stack capacity category.
    JP   EX_FHERE                       ; Fail at the current tokenizer position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack underflow and unmatched internal markers are defensive failures. Valid
; source should reach a specific syntax status before this path.

EX_FAULT: ; Report an inconsistent parser or stack state.
    LD   A,EX_SINT                      ; Select the internal-invariant category.
    JP   EX_FHERE                       ; Fail at the current tokenizer position.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Save the current operator record while precedence reduction overwrites
; EX_OPER with older stack entries.

EX_STASH: ; Save the incoming operator before older operators are reduced.
    LD   HL,EX_OPER                     ; Select the current operator as copy source.
    LD   DE,EX_SAVED                    ; Select incoming-operator save storage.
    JR   EX_COPY                        ; Copy the complete positioned record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Restore the saved incoming operator before pushing it.

EX_FETCH: ; Restore the incoming operator after precedence reduction.
    LD   HL,EX_SAVED                    ; Select the saved incoming operator.
    LD   DE,EX_OPER                     ; Restore it as the current record.

;@ROUTINE IN HL,DE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Copy one complete four-byte operator record from HL to DE.

EX_COPY: ; Transfer a complete positioned operator from HL to DE.
    LD   BC,EX_OPERB                    ; Select all four operator-record bytes.
    LDIR                                ; Copy operator plus exact source position.
    RET                                 ; Return after the fixed-size transfer.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce stacked binary operators before accepting incoming operator.
; High nibbles hold precedence. A stacked operator reduces when its precedence
; is higher, or equal for the left-associative operator set used here.

EX_PRIOR: ; Reduce stacked operators that bind before the incoming operator.
.LOOP: ; Compare stacked and incoming precedence.
    CALL EX_OPEEK                       ; Peek at the newest stacked operator.
    JR   C,.DONE                        ; Empty stack leaves nothing to reduce.
    CP   EX_MARK                        ; Is the group marker on top?
    JR   Z,.DONE                        ; Never reduce across a parenthesis boundary.

; Compare only precedence nibbles. Lower numeric values bind less tightly.

    AND  $F0                            ; Keep only the stacked precedence nibble.
    LD   B,A                            ; Preserve it for comparison.
    LD   A,(EX_SAVED)                   ; Load the incoming packed operator.
    AND  $F0                            ; Keep only its precedence nibble.
    CP   B                              ; Compare incoming against stacked precedence.
    JR   C,.REDUCE                      ; Lower incoming precedence reduces now.
    RET  NZ                             ; Higher incoming precedence delays reduction.
.REDUCE: ; Reduce the currently exposed older operator.
    CALL EX_FOLD                        ; Equal or older-higher precedence reduces now.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .LOOP                          ; Compare the next stacked operator.
.DONE: ; Finish incoming-precedence reduction.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the saved incoming operator untouched.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce until the nearest left-parenthesis marker is exposed. The caller then
; pops the marker itself. Reaching the bottom first is an internal mismatch.

EX_GROUP: ; Reduce to the nearest left-parenthesis marker.
.LOOP: ; Reduce up to left parenthesis.
    CALL EX_OPEEK                       ; Peek at the newest stacked operator.
    JR   C,EX_FAULT                     ; No marker means inconsistent nesting state.
    CP   EX_MARK                        ; Has the nearest group boundary been exposed?
    RET  Z                              ; Yes: leave it for the caller to pop.
    CALL EX_FOLD                        ; Reduce one binary operator inside the group.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .LOOP                          ; Continue until the marker reaches the top.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Apply every consecutive unary marker above the newly published primary. A
; concrete value supports all five. A deferred value supports unary '+'
; and one LOW or HIGH transform only because the pending ABI stores no tree.

EX_UNARY: ; Apply consecutive unary operators to the current primary.
.LOOP: ; Inspect and apply the next stacked unary marker.
    CALL EX_OPEEK                       ; Peek at the operator above the new primary.
    JR   C,.DONE                        ; Empty stack means no prefix is pending.
    AND  $F0                            ; Isolate the operator's precedence band.
    CP   $70                            ; Does it belong to the unary/function band?
    JR   NZ,.DONE                       ; No: leave it for binary precedence handling.
    CALL EX_OPOP                        ; Pop unary operator and position.
    RET  C                              ; Preserve defensive underflow failure.
    CALL EX_RPOP                        ; Pop the operand into EX_RVAL.
    RET  C                              ; Preserve defensive value underflow.
    LD   A,(EX_RFORM)                   ; Read concrete/deferred operand state.
    OR   A                              ; Z identifies a concrete operand.
    JR   Z,.CONCRETE                    ; Dispatch full concrete unary semantics.

; Deferred minus and complement cannot be represented. LOW or HIGH can be
; applied only to a plain deferred symbol and become its patch transform.

    LD   A,(EX_OPER)                    ; Load the deferred operand's unary marker.
    CP   EX_UPLUS                       ; Unary plus leaves a deferred form unchanged.
    JR   Z,.PUBLISH                     ; Republish it directly.
    CP   EX_ULO                         ; Is this LOW(...) projection?
    JR   Z,.PENDLO                      ; Select the low-byte deferred transform.
    CP   EX_UHI                         ; Is this HIGH(...) projection?
    JR   Z,.PENDHI                      ; Select the high-byte deferred transform.
.BADFORM: ; Reject deferred form needing a tree.
    LD   A,EX_SFORM                     ; Report a form that needs an expression tree.
    JP   EX_FOPER                       ; Anchor failure at the unary operator.
.PENDLO: ; Select the deferred LOW transform.
    LD   B,EX_FLO                       ; Select the deferred LOW transform state.
    JR   .ATTACH                        ; Share single-transform validation.
.PENDHI: ; Select the deferred HIGH transform.
    LD   B,EX_FHI                       ; Select the deferred HIGH transform state.
.ATTACH: ; Validate and attach one deferred byte transform.
    LD   A,(EX_RFORM)                   ; Read existing deferred transform.
    CP   EX_FWORD                       ; Is it still the plain symbol form?
    JR   NZ,.BADFORM                    ; Reject nested LOW or HIGH.
    LD   A,B                            ; Recover the newly selected transform.
    LD   (EX_RFORM),A                   ; Attach it to the deferred result.
    JR   .PUBLISH                       ; Republish the transformed operand.
.CONCRETE: ; Dispatch concrete unary operation.

; Dispatch concrete unary operations. LOW clears the upper bytes; HIGH moves
; the middle byte down and clears the rest.

    LD   A,(EX_OPER)                    ; Load the concrete unary marker.
    CP   EX_UPLUS                       ; Is it the identity operation?
    JR   Z,.PUBLISH                     ; Yes: republish without arithmetic.
    CP   EX_UNEG                        ; Is it arithmetic negation?
    JR   Z,.NEGATE                      ; Negate modulo 24 bits.
    CP   EX_UNOT                        ; Is it bitwise complement?
    JR   Z,.INVERT                      ; Complement all three working bytes.
    CP   EX_ULO                         ; Is it LOW(...) projection?
    JR   Z,.LOWBYTE                     ; Keep only the low byte.
    CP   EX_UHI                         ; Is it HIGH(...) projection?
    JR   Z,.HIGHBYTE                    ; Move the middle byte down.
    JP   EX_FAULT                       ; Other marker is an invariant failure.
.NEGATE: ; Negate the concrete 24-bit operand.
    CALL EX_NEG                         ; Negate the concrete 24-bit result.
    JR   .CHECK                         ; Check arithmetic status before republishing.
.INVERT: ; Complement the concrete 24-bit operand.
    CALL EX_NOT                         ; Complement the concrete 24-bit result.
    JR   .CHECK                         ; Check arithmetic status before republishing.
.LOWBYTE: ; Keep only the concrete low byte.
    XOR  A                              ; Form zero for discarded upper bytes.
    LD   (EX_RVAL+1),A                  ; Clear the middle byte.
    LD   (EX_RVAL+2),A                  ; Clear the high/sign byte.
    JR   .CHECK                         ; Republish the projected low byte.
.HIGHBYTE: ; Select concrete word's high byte.
    LD   A,(EX_RVAL+1)                  ; Load the original value's middle byte.
    LD   (EX_RVAL),A                    ; Move it into the result low byte.
    XOR  A                              ; Form zero for discarded upper bytes.
    LD   (EX_RVAL+1),A                  ; Clear the result middle byte.
    LD   (EX_RVAL+2),A                  ; Clear the result high/sign byte.
.CHECK: ; Check concrete unary result.
    RET  C                              ; Preserve arithmetic failure.
.PUBLISH: ; Publish result for outer prefix.

; Publish the transformed value again so another outer unary marker can apply.

    CALL EX_VPUSH                       ; Push transformed value to stack.
    RET  C                              ; Preserve value-stack capacity failure.
    JP   .LOOP                          ; Apply any next outer unary marker.
.DONE: ; Return after all unary markers.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the next binary/group marker stacked.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Finish at the delimiter. Reduce remaining binary operators,
; reject an unmatched left parenthesis and require exactly one final value.

EX_DRAIN: ; Reduce the remaining operators and require a sole result.
.LOOP: ; Reduce remaining binary operators.
    CALL EX_OPEEK                       ; Peek at the newest remaining operator.
    JR   C,.RESULT                      ; Empty operator stack ends reduction.
    CP   EX_MARK                        ; Is a left parenthesis unmatched?
    JP   Z,EX_FAULT                     ; Yes: nesting state is inconsistent.
    CALL EX_FOLD                        ; Reduce one remaining binary operator.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .LOOP                          ; Drain the rest of the operator stack.
.RESULT: ; Pop and validate the sole final value.
    CALL EX_RPOP                        ; Pop the sole expected result into EX_RVAL.
    RET  C                              ; Preserve defensive value underflow.
    LD   A,(EX_VCNT)                    ; Read the depth after removing that result.
    OR   A                              ; Must no other value remain?
    JP   NZ,EX_FAULT                    ; Extra values are an internal fault.
    RET                                 ; Return success with final value in workspace.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Pop operator, right and left values, reduce into EX_RVAL then push
; the result. Right-before-left stack order preserves the source operand order
; for subtraction, division, remainder and shifts.

EX_FOLD: ; Pop right then left and reduce into the result record.
    CALL EX_OPOP                        ; Pop binary operator and position.
    RET  C                              ; Preserve defensive operator underflow.
    CALL EX_RPOP                        ; Pop the source-right operand into EX_RVAL.
    RET  C                              ; Preserve defensive value underflow.
    CALL EX_LPOP                        ; Pop the source-left operand into EX_LVAL.
    RET  C                              ; Preserve defensive value underflow.
    CALL .DISPATCH                      ; Reduce concrete or deferred operands.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JP   EX_VPUSH                       ; Push the result for later reductions.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Choose concrete or deferred reduction. Concrete operator ordinals index the
; address table after the low nibble has been range-checked.

.DISPATCH: ; Select concrete arithmetic or restricted deferred arithmetic.
    LD   A,(EX_LFORM)                   ; Read the left operand's resolution state.
    LD   B,A                            ; Preserve it while loading the right state.
    LD   A,(EX_RFORM)                   ; Read the right operand's resolution state.
    OR   B                              ; Is either operand deferred?
    JR   NZ,.FORWARD                    ; Yes: enforce the affine forward-form rules.
    LD   A,(EX_OPER)                    ; Load the packed concrete binary operator.
    AND  $0F                            ; Keep its reduction-table ordinal.
    CP   10                             ; Does it name one of the ten binary kernels?
    JP   NC,EX_FAULT                    ; Reject a corrupt operator record defensively.
    ADD  A,A                            ; Scale ordinal for a two-byte address entry.
    LD   L,A                            ; Place the table offset in low HL.
    LD   H,0                            ; Zero-extend the offset.
    LD   DE,.TABLE                      ; Point DE at the concrete reduction table.
    ADD  HL,DE                          ; Address the selected handler pointer.
    LD   E,(HL)                         ; Load the handler address low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the handler address in DE.
    EX   DE,HL                          ; Put target in indirect-jump HL.
    JP   (HL)                           ; Dispatch to the concrete arithmetic kernel.

; Order matches EX_OPOR through EX_OPREM in the operator byte's low nibble.

.TABLE: ; Dispatch concrete binary operations.
    DW   EX_OR,EX_XOR,EX_AND            ; Bitwise kernels for ordinals 0 through 2.
    DW   EX_SHL,EX_SHR                  ; Left and right shift kernels.
    DW   EX_ADD,EX_SUB                  ; Signed addition and subtraction kernels.
    DW   EX_MUL,EX_DIV                  ; Signed multiplication and division kernels.
    DW   EX_REM                         ; Signed remainder kernel.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce an expression containing one unresolved symbol. LOW and HIGH results
; cannot take further binary arithmetic. Plain forms permit symbol+constant,
; constant+symbol and symbol-constant only.

.FORWARD: ; Reduce a plain symbol and constant into an affine patch form.
; EX_FLO or EX_FHI means LOW/HIGH has already consumed the
; symbol form. Any binary operator outside that function is unsupported.

    LD   A,(EX_LFORM)                   ; Read the left deferred-transform state.
    CP   EX_FLO                         ; Was the left symbol projected?
    JR   NC,.BADFORM                    ; No later binary operation fits.
    LD   A,(EX_RFORM)                   ; Read the right deferred-transform state.
    CP   EX_FLO                         ; Was the right symbol projected?
    JR   NC,.BADFORM                    ; Yes: reject further binary arithmetic.
    LD   A,(EX_LFORM)                   ; Recheck for a left-side symbol.
    OR   A                              ; Z means the symbol, if any, is on the right.
    JR   Z,.RIGHTSYM                    ; Validate the constant-plus-symbol case.

; When the symbol is on the left, addition and subtraction both preserve one
; symbol. Concrete arithmetic updates the addend in EX_RVAL.

    LD   A,(EX_RFORM)                   ; Is the right operand concrete?
    OR   A                              ; Nonzero would mean two unresolved symbols.
    JR   NZ,.BADFORM                    ; Two symbols need an expression tree.
    LD   A,(EX_OPER)                    ; Load the packed binary operator.
    AND  $0F                            ; Keep its reduction ordinal.
    CP   EX_OPADD                       ; Is this symbol plus constant?
    JR   Z,.LEFTADD                     ; Yes: add the constant to the addend.
    CP   EX_OPSUB                       ; Is this symbol minus constant?
    JR   NZ,.BADFORM                    ; No other operation preserves one symbol.
    CALL EX_SUB                         ; Compute left addend minus right constant.
    JR   C,.RETURN                      ; Preserve signed overflow failure.
    JR   .LEFTKEY                       ; Restore the symbol key from the left operand.
.LEFTADD: ; Add constant to left-symbol addend.
    CALL EX_ADD                         ; Compute left addend plus right constant.
    JR   C,.RETURN                      ; Preserve signed overflow failure.
.LEFTKEY: ; Restore left operand's packed key.

; The left operand carried the symbol, so replace the right operand's concrete
; key bytes with the left packed key.

    LD   HL,EX_LKEY                     ; Point at left packed symbol key.
    LD   DE,EX_RKEY                     ; Select the result key destination.
    LD   BC,6                           ; Copy all three packed RADIX-40 words.
    LDIR                                ; Replace unused concrete key.
    JR   .FINISH                        ; Canonicalise and range-check the result.
.RIGHTSYM: ; Reduce constant plus symbol.

; A right-side symbol permits only constant+symbol. constant-symbol would
; require a negated symbol coefficient and cannot fit the pending record.

    LD   A,(EX_OPER)                    ; Load the packed binary operator.
    AND  $0F                            ; Keep its reduction ordinal.
    CP   EX_OPADD                       ; Is this constant plus symbol?
    JR   NZ,.BADFORM                    ; Other operations are unsupported.
    CALL EX_ADD                         ; Add constant to symbol addend.
    JR   C,.RETURN                      ; Preserve signed overflow failure.
.FINISH: ; Check final deferred result.

; Canonicalise the surviving result as a plain deferred symbol and prove that
; its computed addend fits the signed byte stored by the pending record.

    LD   A,EX_FWORD                     ; Select canonical plain deferred state.
    LD   (EX_RFORM),A                   ; Attach it to the surviving symbol/addend.
    CALL EX_BYTE                        ; Require the addend to fit signed eight bits.
.RETURN: ; Return deferred arithmetic status.
    RET                                 ; Return range status from arithmetic/checking.
.BADFORM: ; Report an unsupported binary forward form.
    LD   A,EX_SFORM                     ; Select unsupported-forward-form status.
    JP   EX_FOPER                       ; Anchor it at the binary operator.
