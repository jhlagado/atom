;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the complete ten-byte working value after proving stack capacity. The
; entry includes a packed key even for concrete values, keeping stack
; movement uniform.

exPutVal: ; Copy the current value into the next bounded stack slot.
    LD   A,(exValCnt)                   ; Read the number of live value records.
    CP   exValCap                       ; Has the fixed sixteen-entry stack filled?
    JP   NC,exFull                      ; Yes: report capacity at the current token.
    CALL exValRec                       ; Locate the first unused record.
    LD   D,H                            ; Copy its destination address high byte.
    LD   E,L                            ; Complete the destination pointer in DE.
    LD   HL,exRVal                      ; Point at the current ten-byte value record.
    LD   BC,exValLen                    ; Select the complete fixed record size.
    LDIR                                ; Copy value, state and key to stack.
    LD   HL,exValCnt                    ; Address the live-depth counter.
    INC  (HL)                           ; Publish the newly copied record.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Preserve the stack entry for later reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the right operand into exRVal.

exRPop: ; Pop the newest value into the right/result record.
    LD   DE,exRVal                      ; Select the right-value working record.
    JR   exPopTo                        ; Share bounded stack pop and copy.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the left operand into exLVal. Fall through to the shared copy body.

exLPop: ; Pop the next value into the left operand record.
    LD   DE,exLVal                      ; Select the left-value working record.

;@ROUTINE IN DE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Decrement value depth, locate the last entry and copy its ten bytes to
; destination DE. Empty-stack access is an internal parser fault.

exPopTo: ; Copy a popped value to DE or report internal underflow.
    PUSH DE                             ; Preserve the caller's selected destination.
    LD   A,(exValCnt)                   ; Read the current live value depth.
    OR   A                              ; Is the stack empty?
    JR   Z,.empty                       ; Yes: report an internal parser fault.
    DEC  A                              ; Select the newest live record index.
    LD   (exValCnt),A                   ; Remove it logically before copying.
    CALL exValRec                       ; Convert the index into source address HL.
    POP  DE                             ; Restore the requested working destination.
    LD   BC,exValLen                    ; Select one complete value record.
    LDIR                                ; Copy it out of the stack.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the decremented depth published.
.empty: ; Restore stack after value underflow.
    POP  DE                             ; Restore stack balance on the failure path.
    JR   exFault                        ; Report defensive value-stack underflow.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert value index A to exVals + A*10 without multiplication support.

exValRec: ; Calculate the address of ten-byte value record A.
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
    LD   DE,exVals                      ; Load the value-stack base address.
    ADD  HL,DE                          ; Return the selected record address.
    RET                                 ; Return record address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Push the current four-byte operator record after proving stack capacity.

exOpPush: ; Publish a positioned operator after proving stack capacity.
    LD   A,(exOpCnt)                    ; Read the number of live operator records.
    CP   exOpCap                        ; Has the fixed sixteen-entry stack filled?
    JR   NC,exFull                      ; Yes: report capacity at the current token.
    CALL exOpSlot                       ; Locate the first unused operator record.
    LD   D,H                            ; Copy its destination address high byte.
    LD   E,L                            ; Complete the destination pointer in DE.
    LD   HL,exOper                      ; Point at current operator record.
    LD   BC,exOpLen                     ; Select the complete fixed record size.
    LDIR                                ; Copy operator and position onto the stack.
    LD   HL,exOpCnt                     ; Address the live-depth counter.
    INC  (HL)                           ; Publish the newly copied operator.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the record available to reduction.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
; Pop the most recent operator into exOper. As with the value stack, an empty
; pop is an internal invariant failure rather than a source diagnostic.

exOpPop: ; Restore the newest positioned operator into exOper.
    LD   A,(exOpCnt)                    ; Read the current live operator depth.
    OR   A                              ; Is the stack empty?
    JR   Z,exFault                      ; Yes: report defensive underflow.
    DEC  A                              ; Select the newest live record index.
    LD   (exOpCnt),A                    ; Remove it logically before copying.
    CALL exOpSlot                       ; Convert its index into source address HL.
    LD   DE,exOper                      ; Select the current-operator destination.
    LD   BC,exOpLen                     ; Select one complete operator record.
    LDIR                                ; Restore operator and source position.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the decremented depth published.

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Convert operator index A to exOps + A*4.

exOpSlot: ; Calculate the address of four-byte operator record A.
    LD   L,A                            ; Place the operator index in low HL.
    LD   H,0                            ; Zero-extend it to sixteen bits.
    ADD  HL,HL                          ; Form index times two.
    ADD  HL,HL                          ; Form index times four.
    LD   DE,exOps                       ; Load the operator-stack base.
    ADD  HL,DE                          ; Return the selected record address.
    RET                                 ; Return operator address in HL.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,DE,HL
; Peek at newest operator byte without changing stack depth.
; Carry set reports an empty stack; otherwise A contains the encoded operator.

exOpPeek: ; Read the newest operator without changing stack depth.
    LD   A,(exOpCnt)                    ; Read the live operator depth.
    OR   A                              ; Test whether any operator is available.
    SCF                                 ; Prepare the empty-stack failure result.
    RET  Z                              ; Return carry set when depth is zero.
    DEC  A                              ; Select the newest live record index.
    CALL exOpSlot                       ; Locate that record without changing depth.
    LD   A,(HL)                         ; Return its packed operator byte.
    OR   A                              ; Clear carry for a successful peek.
    RET                                 ; Leave the stack unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack-capacity failures use the current tokenizer position.

exFull: ; Report a full bounded stack at the current token.
    LD   A,exCapErr                     ; Select the bounded-stack capacity category.
    JP   exAtTok                        ; Fail at the current tokenizer position.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Stack underflow and unmatched internal markers are defensive failures. Valid
; source should reach a specific syntax status before this path.

exFault: ; Report an inconsistent parser or stack state.
    LD   A,exIntErr                     ; Select the internal-invariant category.
    JP   exAtTok                        ; Fail at the current tokenizer position.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Save the current operator record while precedence reduction overwrites
; exOper with older stack entries.

exStash: ; Save the incoming operator before older operators are reduced.
    LD   HL,exOper                      ; Select the current operator as copy source.
    LD   DE,exSaveOp                    ; Select incoming-operator save storage.
    JR   exOpCopy                       ; Copy the complete positioned record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Restore the saved incoming operator before pushing it.

exFetch: ; Restore the incoming operator after precedence reduction.
    LD   HL,exSaveOp                    ; Select the saved incoming operator.
    LD   DE,exOper                      ; Restore it as the current record.

;@ROUTINE IN HL,DE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
; Copy one complete four-byte operator record from HL to DE.

exOpCopy: ; Transfer a complete positioned operator from HL to DE.
    LD   BC,exOpLen                     ; Select all four operator-record bytes.
    LDIR                                ; Copy operator plus exact source position.
    RET                                 ; Return after the fixed-size transfer.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce stacked binary operators before accepting incoming operator.
; High nibbles hold precedence. A stacked operator reduces when its precedence
; is higher, or equal for the left-associative operator set used here.

exPrior: ; Reduce stacked operators that bind before the incoming operator.
.loop: ; Compare stacked and incoming precedence.
    CALL exOpPeek                       ; Peek at the newest stacked operator.
    JR   C,.done                        ; Empty stack leaves nothing to reduce.
    CP   exLParen                       ; Is the group marker on top?
    JR   Z,.done                        ; Never reduce across a parenthesis boundary.

; Compare only precedence nibbles. Lower numeric values bind less tightly.

    AND  $F0                            ; Keep only the stacked precedence nibble.
    LD   B,A                            ; Preserve it for comparison.
    LD   A,(exSaveOp)                   ; Load the incoming packed operator.
    AND  $F0                            ; Keep only its precedence nibble.
    CP   B                              ; Compare incoming against stacked precedence.
    JR   C,.reduce                      ; Lower incoming precedence reduces now.
    RET  NZ                             ; Higher incoming precedence delays reduction.
.reduce: ; Reduce the currently exposed older operator.
    CALL exFold                         ; Equal or older-higher precedence reduces now.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .loop                          ; Compare the next stacked operator.
.done: ; Finish incoming-precedence reduction.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the saved incoming operator untouched.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Reduce until the nearest left-parenthesis marker is exposed. The caller then
; pops the marker itself. Reaching the bottom first is an internal mismatch.

exGroup: ; Reduce to the nearest left-parenthesis marker.
.loop: ; Reduce up to left parenthesis.
    CALL exOpPeek                       ; Peek at the newest stacked operator.
    JR   C,exFault                      ; No marker means inconsistent nesting state.
    CP   exLParen                       ; Has the nearest group boundary been exposed?
    RET  Z                              ; Yes: leave it for the caller to pop.
    CALL exFold                         ; Reduce one binary operator inside the group.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .loop                          ; Continue until the marker reaches the top.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Apply every consecutive unary marker above the newly published primary. A
; concrete value supports all five. A deferred value supports unary '+'
; and one LOW or HIGH transform only because the pending ABI stores no tree.

exUnary: ; Apply consecutive unary operators to the current primary.
.loop: ; Inspect and apply the next stacked unary marker.
    CALL exOpPeek                       ; Peek at the operator above the new primary.
    JR   C,.done                        ; Empty stack means no prefix is pending.
    AND  $F0                            ; Isolate the operator's precedence band.
    CP   $70                            ; Does it belong to the unary/function band?
    JR   NZ,.done                       ; No: leave it for binary precedence handling.
    CALL exOpPop                        ; Pop unary operator and position.
    RET  C                              ; Preserve defensive underflow failure.
    CALL exRPop                         ; Pop the operand into exRVal.
    RET  C                              ; Preserve defensive value underflow.
    LD   A,(exRForm)                    ; Read concrete/deferred operand state.
    OR   A                              ; Z identifies a concrete operand.
    JR   Z,.concrete                    ; Dispatch full concrete unary semantics.

; Deferred minus and complement cannot be represented. LOW or HIGH can be
; applied only to a plain deferred symbol and become its patch transform.

    LD   A,(exOper)                     ; Load the deferred operand's unary marker.
    CP   exUPlus                        ; Unary plus leaves a deferred form unchanged.
    JR   Z,.publish                     ; Republish it directly.
    CP   exULow                         ; Is this LOW(...) projection?
    JR   Z,.pendLo                      ; Select the low-byte deferred transform.
    CP   exUHigh                        ; Is this HIGH(...) projection?
    JR   Z,.pendHi                      ; Select the high-byte deferred transform.
.badForm: ; Reject deferred form needing a tree.
    LD   A,exFrmErr                     ; Report a form that needs an expression tree.
    JP   exAtOper                       ; Anchor failure at the unary operator.
.pendLo: ; Select the deferred LOW transform.
    LD   B,exFLow                       ; Select the deferred LOW transform state.
    JR   .attach                        ; Share single-transform validation.
.pendHi: ; Select the deferred HIGH transform.
    LD   B,exFHigh                      ; Select the deferred HIGH transform state.
.attach: ; Validate and attach one deferred byte transform.
    LD   A,(exRForm)                    ; Read existing deferred transform.
    CP   exFWord                        ; Is it still the plain symbol form?
    JR   NZ,.badForm                    ; Reject nested LOW or HIGH.
    LD   A,B                            ; Recover the newly selected transform.
    LD   (exRForm),A                    ; Attach it to the deferred result.
    JR   .publish                       ; Republish the transformed operand.
.concrete: ; Dispatch concrete unary operation.

; Dispatch concrete unary operations. LOW clears the upper bytes; HIGH moves
; the middle byte down and clears the rest.

    LD   A,(exOper)                     ; Load the concrete unary marker.
    CP   exUPlus                        ; Is it the identity operation?
    JR   Z,.publish                     ; Yes: republish without arithmetic.
    CP   exUNeg                         ; Is it arithmetic negation?
    JR   Z,.negate                      ; Negate modulo 24 bits.
    CP   exUNot                         ; Is it bitwise complement?
    JR   Z,.invert                      ; Complement all three working bytes.
    CP   exULow                         ; Is it LOW(...) projection?
    JR   Z,.lowByte                     ; Keep only the low byte.
    CP   exUHigh                        ; Is it HIGH(...) projection?
    JR   Z,.highByte                    ; Move the middle byte down.
    JP   exFault                        ; Other marker is an invariant failure.
.negate: ; Negate the concrete 24-bit operand.
    CALL exNeg                          ; Negate the concrete 24-bit result.
    JR   .check                         ; Check arithmetic status before republishing.
.invert: ; Complement the concrete 24-bit operand.
    CALL exNot                          ; Complement the concrete 24-bit result.
    JR   .check                         ; Check arithmetic status before republishing.
.lowByte: ; Keep only the concrete low byte.
    XOR  A                              ; Form zero for discarded upper bytes.
    LD   (exRVal+1),A                   ; Clear the middle byte.
    LD   (exRVal+2),A                   ; Clear the high/sign byte.
    JR   .check                         ; Republish the projected low byte.
.highByte: ; Select concrete word's high byte.
    LD   A,(exRVal+1)                   ; Load the original value's middle byte.
    LD   (exRVal),A                     ; Move it into the result low byte.
    XOR  A                              ; Form zero for discarded upper bytes.
    LD   (exRVal+1),A                   ; Clear the result middle byte.
    LD   (exRVal+2),A                   ; Clear the result high/sign byte.
.check: ; Check concrete unary result.
    RET  C                              ; Preserve arithmetic failure.
.publish: ; Publish result for outer prefix.

; Publish the transformed value again so another outer unary marker can apply.

    CALL exPutVal                       ; Push transformed value to stack.
    RET  C                              ; Preserve value-stack capacity failure.
    JP   .loop                          ; Apply any next outer unary marker.
.done: ; Return after all unary markers.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the next binary/group marker stacked.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
; Finish at the delimiter. Reduce remaining binary operators,
; reject an unmatched left parenthesis and require exactly one final value.

exDrain: ; Reduce the remaining operators and require a sole result.
.loop: ; Reduce remaining binary operators.
    CALL exOpPeek                       ; Peek at the newest remaining operator.
    JR   C,.result                      ; Empty operator stack ends reduction.
    CP   exLParen                       ; Is a left parenthesis unmatched?
    JP   Z,exFault                      ; Yes: nesting state is inconsistent.
    CALL exFold                         ; Reduce one remaining binary operator.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JR   .loop                          ; Drain the rest of the operator stack.
.result: ; Pop and validate the sole final value.
    CALL exRPop                         ; Pop the sole expected result into exRVal.
    RET  C                              ; Preserve defensive value underflow.
    LD   A,(exValCnt)                   ; Read the depth after removing that result.
    OR   A                              ; Must no other value remain?
    JP   NZ,exFault                     ; Extra values are an internal fault.
    RET                                 ; Return success with final value in workspace.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
; Pop operator, right and left values, reduce into exRVal then push
; the result. Right-before-left stack order preserves the source operand order
; for subtraction, division, remainder and shifts.

exFold: ; Pop right then left and reduce into the result record.
    CALL exOpPop                        ; Pop binary operator and position.
    RET  C                              ; Preserve defensive operator underflow.
    CALL exRPop                         ; Pop the source-right operand into exRVal.
    RET  C                              ; Preserve defensive value underflow.
    CALL exLPop                         ; Pop the source-left operand into exLVal.
    RET  C                              ; Preserve defensive value underflow.
    CALL .dispatch                      ; Reduce concrete or deferred operands.
    RET  C                              ; Preserve arithmetic or forward-form failure.
    JP   exPutVal                       ; Push the result for later reductions.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Choose concrete or deferred reduction. Concrete operator ordinals index the
; address table after the low nibble has been range-checked.

.dispatch: ; Select concrete arithmetic or restricted deferred arithmetic.
    LD   A,(exLForm)                    ; Read the left operand's resolution state.
    LD   B,A                            ; Preserve it while loading the right state.
    LD   A,(exRForm)                    ; Read the right operand's resolution state.
    OR   B                              ; Is either operand deferred?
    JR   NZ,.forward                    ; Yes: enforce the affine forward-form rules.
    LD   A,(exOper)                     ; Load the packed concrete binary operator.
    AND  $0F                            ; Keep its reduction-table ordinal.
    CP   10                             ; Does it name one of the ten binary kernels?
    JP   NC,exFault                     ; Reject a corrupt operator record defensively.
    ADD  A,A                            ; Scale ordinal for a two-byte address entry.
    LD   L,A                            ; Place the table offset in low HL.
    LD   H,0                            ; Zero-extend the offset.
    LD   DE,.table                      ; Point DE at the concrete reduction table.
    ADD  HL,DE                          ; Address the selected handler pointer.
    LD   E,(HL)                         ; Load the handler address low byte.
    INC  HL                             ; Advance to the high byte.
    LD   D,(HL)                         ; Complete the handler address in DE.
    EX   DE,HL                          ; Put target in indirect-jump HL.
    JP   (HL)                           ; Dispatch to the concrete arithmetic kernel.

; Order matches exOpOr through exOpRem in the operator byte's low nibble.

.table: ; Dispatch concrete binary operations.
    DW   exOr,exXor,exAnd               ; Bitwise kernels for ordinals 0 through 2.
    DW   exShl,exShr                    ; Left and right shift kernels.
    DW   exAdd,exSub                    ; Signed addition and subtraction kernels.
    DW   exMul,exDiv                    ; Signed multiplication and division kernels.
    DW   exRem                          ; Signed remainder kernel.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Reduce an expression containing one unresolved symbol. LOW and HIGH results
; cannot take further binary arithmetic. Plain forms permit symbol+constant,
; constant+symbol and symbol-constant only.

.forward: ; Reduce a plain symbol and constant into an affine patch form.
; exFLow or exFHigh means LOW/HIGH has already consumed the
; symbol form. Any binary operator outside that function is unsupported.

    LD   A,(exLForm)                    ; Read the left deferred-transform state.
    CP   exFLow                         ; Was the left symbol projected?
    JR   NC,.badForm                    ; No later binary operation fits.
    LD   A,(exRForm)                    ; Read the right deferred-transform state.
    CP   exFLow                         ; Was the right symbol projected?
    JR   NC,.badForm                    ; Yes: reject further binary arithmetic.
    LD   A,(exLForm)                    ; Recheck for a left-side symbol.
    OR   A                              ; Z means the symbol, if any, is on the right.
    JR   Z,.rightSym                    ; Validate the constant-plus-symbol case.

; When the symbol is on the left, addition and subtraction both preserve one
; symbol. Concrete arithmetic updates the addend in exRVal.

    LD   A,(exRForm)                    ; Is the right operand concrete?
    OR   A                              ; Nonzero would mean two unresolved symbols.
    JR   NZ,.badForm                    ; Two symbols need an expression tree.
    LD   A,(exOper)                     ; Load the packed binary operator.
    AND  $0F                            ; Keep its reduction ordinal.
    CP   exOpAdd                        ; Is this symbol plus constant?
    JR   Z,.leftAdd                     ; Yes: add the constant to the addend.
    CP   exOpSub                        ; Is this symbol minus constant?
    JR   NZ,.badForm                    ; No other operation preserves one symbol.
    CALL exSub                          ; Compute left addend minus right constant.
    JR   C,.return                      ; Preserve signed overflow failure.
    JR   .leftKey                       ; Restore the symbol key from the left operand.
.leftAdd: ; Add constant to left-symbol addend.
    CALL exAdd                          ; Compute left addend plus right constant.
    JR   C,.return                      ; Preserve signed overflow failure.
.leftKey: ; Restore left operand's packed key.

; The left operand carried the symbol, so replace the right operand's concrete
; key bytes with the left packed key.

    LD   HL,exLKey                      ; Point at left packed symbol key.
    LD   DE,exRKey                      ; Select the result key destination.
    LD   BC,6                           ; Copy all three packed RADIX-40 words.
    LDIR                                ; Replace unused concrete key.
    JR   .finish                        ; Canonicalise and range-check the result.
.rightSym: ; Reduce constant plus symbol.

; A right-side symbol permits only constant+symbol. constant-symbol would
; require a negated symbol coefficient and cannot fit the pending record.

    LD   A,(exOper)                     ; Load the packed binary operator.
    AND  $0F                            ; Keep its reduction ordinal.
    CP   exOpAdd                        ; Is this constant plus symbol?
    JR   NZ,.badForm                    ; Other operations are unsupported.
    CALL exAdd                          ; Add constant to symbol addend.
    JR   C,.return                      ; Preserve signed overflow failure.
.finish: ; Check final deferred result.

; Canonicalise the surviving result as a plain deferred symbol and prove that
; its computed addend fits the signed byte stored by the pending record.

    LD   A,exFWord                      ; Select canonical plain deferred state.
    LD   (exRForm),A                    ; Attach it to the surviving symbol/addend.
    CALL exByteOk                       ; Require the addend to fit signed eight bits.
.return: ; Return deferred arithmetic status.
    RET                                 ; Return range status from arithmetic/checking.
.badForm: ; Report an unsupported binary forward form.
    LD   A,exFrmErr                     ; Select unsupported-forward-form status.
    JP   exAtOper                       ; Anchor it at the binary operator.
