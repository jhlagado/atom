; atom Phase 2d constant-expression evaluator and forward-symbol handoff.
;
; The evaluator consumes the current token through the final expression token
; and leaves the first delimiter published. Concrete arithmetic uses signed
; 24-bit intermediates and must finish in Atom's accepted 16-bit domain.
; A deferred result is exactly one symbol plus a signed-byte addend, matching
; the six-byte pending-reference record without retaining an expression tree.
; AtomExpressionDeferredMode is supplied by the integration image. Zero keeps
; the Phase 2d standalone entry byte-for-byte stable; nonzero also exposes a
; deferred-key entry that does not publish a symbol record during parsing.

AtomExpressionCodeStart:

AtomExpressionResolved:              .equ 0
AtomExpressionUnresolved:            .equ 1
AtomExpressionStatusLexical:         .equ 2
AtomExpressionStatusExpectedPrimary: .equ 3
AtomExpressionStatusExpectedRight:   .equ 4
AtomExpressionStatusDivideZero:      .equ 5
AtomExpressionStatusRange:           .equ 6
AtomExpressionStatusForwardForm:     .equ 7
AtomExpressionStatusCapacity:        .equ 8
AtomExpressionStatusSymbol:          .equ 9
AtomExpressionStatusInternal:        .equ 10

AtomExpressionOpOr:        .equ 0
AtomExpressionOpXor:       .equ 1
AtomExpressionOpAnd:       .equ 2
AtomExpressionOpLeft:      .equ 3
AtomExpressionOpRight:     .equ 4
AtomExpressionOpAdd:       .equ 5
AtomExpressionOpSubtract:  .equ 6
AtomExpressionOpMultiply:  .equ 7
AtomExpressionOpDivide:    .equ 8
AtomExpressionOpRemainder: .equ 9

AtomExpressionValueBytes:       .equ 10
AtomExpressionValueCapacity:    .equ 16
AtomExpressionOperatorBytes:    .equ 4
AtomExpressionOperatorCapacity: .equ 16
AtomExpressionMarkerLeftParen:  .equ $0F
AtomExpressionUnaryPlus:        .equ $7A
AtomExpressionUnaryMinus:       .equ $7B
AtomExpressionUnaryTilde:       .equ $72
AtomExpressionUnaryLow:         .equ $7D
AtomExpressionUnaryHigh:        .equ $7E

AtomExpressionForwardPlain:     .equ 1
AtomExpressionForwardLow:       .equ 2
AtomExpressionForwardHigh:      .equ 3

; Parse one expression beginning at the current published token.
;
; in BC=current assembly address
; out resolved: A=AtomExpressionResolved, HL=value, carry clear
;     unresolved: A=AtomExpressionUnresolved, IX=symbol record,
;                 HL=sign-extended addend, carry clear
;     failure: A=status, carry set; no new symbol is published
.routine in BC out A,HL,IX,carry clobbers BC,DE,IY,zero,sign,parity,halfCarry
.if AtomExpressionDeferredMode
AtomExpressionParse:
            LD   A,1
            LD   (AtomExpressionPublishSymbol),A
            JR   AtomExpressionParseCommon

; Parse without inserting a missing symbol. On unresolved success IX points
; to the six-byte packed key in evaluator workspace instead of a symbol record.
.routine in BC out A,HL,IX,carry clobbers sign,parity,halfCarry,zero,BC,DE,IY
AtomExpressionParseDeferred:
            XOR  A
            LD   (AtomExpressionPublishSymbol),A
AtomExpressionParseCommon:
.else
AtomExpressionParse:
.endif
            LD   (AtomExpressionCurrentAddress),BC
            XOR  A
            LD   (AtomExpressionValueDepth),A
            LD   (AtomExpressionOperatorDepth),A
            LD   (AtomExpressionParenDepth),A
            INC  A
            LD   (AtomExpressionExpectOperand),A
_AtomExpressionParseLoop:
            LD   A,(AtomExpressionExpectOperand)
            OR   A
            JR   Z,_AtomExpressionParseOperator
            CALL AtomExpressionParseOperand
            RET  C
            JR   _AtomExpressionParseLoop
_AtomExpressionParseOperator:
            CALL AtomExpressionParseOperator
            RET  C
            JR   NZ,_AtomExpressionParseLoop
            CALL AtomExpressionFinishStacks
            RET  C
            LD   A,(AtomExpressionResultUnresolved)
            OR   A
            JR   NZ,_AtomExpressionFinishUnresolved
            CALL AtomExpressionRequireWord
            RET  C
            LD   HL,(AtomExpressionResultValue)
            XOR  A
            RET

_AtomExpressionFinishUnresolved:
            CALL AtomExpressionRequireAddend
            RET  C
.if AtomExpressionDeferredMode
            LD   A,(AtomExpressionPublishSymbol)
            OR   A
            JR   Z,_AtomExpressionFinishDeferred
.endif
            LD   HL,AtomExpressionResultKey
            CALL AtomSymbolReference
            JR   C,AtomExpressionSymbolFailure
_AtomExpressionReturnUnresolved:
            LD   HL,(AtomExpressionResultValue)
            LD   A,AtomExpressionUnresolved
            OR   A
            RET
.if AtomExpressionDeferredMode
_AtomExpressionFinishDeferred:
            LD   IX,AtomExpressionResultKey
            JR   _AtomExpressionReturnUnresolved
.endif
.routine in A out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionSymbolFailure:
            LD   (AtomExpressionSymbolStatus),A
            LD   A,AtomExpressionStatusSymbol
            JP   AtomExpressionFailSymbol

; Queue the unresolved result returned by AtomExpressionParse.
;
; in IX=symbol record, HL=sign-extended addend, DE=patch address, B=patch kind
; out AtomPendingAdd result
.routine in IX,HL,DE,B out A,carry clobbers C,DE,HL,zero,sign,parity,halfCarry
AtomExpressionQueue:
            LD   C,L
            JP   AtomPendingAdd

; LOW(...) and HIGH(...) are unary byte functions. AZM spells the same
; operations LSB(...) and MSB(...); Atom keeps the more familiar source names.
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry
AtomExpressionClassifyFunction:
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            CP   3
            JR   Z,_AtomExpressionClassifyLow
            CP   4
            JR   NZ,_AtomExpressionNotFunction
            LD   C,AtomExpressionUnaryHigh
            LD   DE,$336F
            JR   _AtomExpressionClassifyFunctionPack
_AtomExpressionClassifyLow:
            LD   C,AtomExpressionUnaryLow
            LD   DE,$4D6F
_AtomExpressionClassifyFunctionPack:
            PUSH DE
            PUSH BC
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   B,A
            LD   DE,AtomExpressionResultKey
            CALL AtomRadix40Pack
            POP  BC
            POP  DE
            JR   C,_AtomExpressionNotFunction
            LD   HL,(AtomExpressionResultKey)
            OR   A
            SBC  HL,DE
            JR   NZ,_AtomExpressionNotFunction
            LD   HL,(AtomTokenSourceCursor)
            LD   DE,(AtomTokenSourceEnd)
_AtomExpressionFunctionLookahead:
            LD   A,H
            CP   D
            JR   NZ,_AtomExpressionFunctionLookaheadByte
            LD   A,L
            CP   E
            JR   Z,_AtomExpressionNotFunction
_AtomExpressionFunctionLookaheadByte:
            LD   A,(HL)
            CP   " "
            JR   Z,_AtomExpressionFunctionLookaheadSpace
            CP   $09
            JR   Z,_AtomExpressionFunctionLookaheadSpace
            CP   "("
            JR   NZ,_AtomExpressionNotFunction
            LD   A,C
            OR   A
            RET
_AtomExpressionFunctionLookaheadSpace:
            INC  HL
            JR   _AtomExpressionFunctionLookahead
_AtomExpressionNotFunction:
            SCF
            RET

; Publish A as one precedence-seven unary/function operator.
.routine in A out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomExpressionPushHighOperator:
            LD   (AtomExpressionOperator),A
            CALL AtomExpressionCaptureOperatorPosition
            JP   AtomExpressionPushOperator

; Consume one operand, grouping marker, or unary operator. The operator and
; value stacks make the parser finite and non-recursive for strict proof.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE,IX,IY
AtomExpressionParseOperand:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenPlus
            JR   Z,_AtomExpressionPushUnary
            CP   AtomTokenMinus
            JR   Z,_AtomExpressionPushUnary
            CP   AtomTokenTilde
            JR   Z,_AtomExpressionPushUnary
            CP   AtomTokenNumber
            JR   Z,_AtomExpressionPrimaryNumber
            CP   AtomTokenCurrent
            JR   Z,_AtomExpressionPrimaryCurrent
            CP   AtomTokenName
            JR   Z,_AtomExpressionPrimaryName
_AtomExpressionRequireLeftParen:
            CP   AtomTokenLeftParen
            JR   Z,_AtomExpressionPushParen
            LD   A,AtomExpressionStatusExpectedPrimary
            JP   AtomExpressionFailHere
_AtomExpressionPushUnary:
            OR   $70
            CALL AtomExpressionPushHighOperator
            RET  C
            JP   AtomExpressionNextToken
_AtomExpressionPushParen:
            LD   A,AtomExpressionMarkerLeftParen
            LD   (AtomExpressionOperator),A
            CALL AtomExpressionCaptureOperatorPosition
            CALL AtomExpressionPushOperator
            RET  C
            LD   HL,AtomExpressionParenDepth
            INC  (HL)
            JP   AtomExpressionNextToken
_AtomExpressionPrimaryNumber:
            LD   HL,(AtomTokenRecord+AtomTokenValueOffset)
            CALL AtomExpressionSetResolvedWord
            JR   _AtomExpressionPrimaryFinish
_AtomExpressionPrimaryCurrent:
            LD   HL,(AtomExpressionCurrentAddress)
            CALL AtomExpressionSetResolvedWord
            JR   _AtomExpressionPrimaryFinish
_AtomExpressionPrimaryName:
            CALL AtomExpressionClassifyFunction
            JR   NC,_AtomExpressionPushFunction
            CALL AtomExpressionPrimaryName
            RET  C
            JR   _AtomExpressionPrimaryPublish
_AtomExpressionPrimaryFinish:
            CALL AtomExpressionNextToken
            RET  C
_AtomExpressionPrimaryPublish:
            CALL AtomExpressionPushValue
            RET  C
            CALL AtomExpressionApplyUnary
            RET  C
            XOR  A
            LD   (AtomExpressionExpectOperand),A
            RET

_AtomExpressionPushFunction:
            CALL AtomExpressionPushHighOperator
            RET  C
            CALL AtomExpressionNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            JR   _AtomExpressionRequireLeftParen

; Consume a binary operator or close one grouping level. Zero on return means
; the current token is an outer delimiter and parsing is complete.
.routine out A,carry,zero clobbers BC,DE,HL,IX,IY,sign,parity,halfCarry
AtomExpressionParseOperator:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenRightParen
            JR   Z,_AtomExpressionRightParen
            CALL AtomExpressionClassifyOperator
            JR   C,_AtomExpressionDelimiter
            CALL AtomExpressionSaveIncoming
            CALL AtomExpressionReduceIncoming
            RET  C
            CALL AtomExpressionRestoreIncoming
            CALL AtomExpressionPushOperator
            RET  C
            LD   A,1
            LD   (AtomExpressionExpectOperand),A
            CALL AtomExpressionNextToken
            RET  C
            XOR  A
            INC  A
            RET
_AtomExpressionRightParen:
            LD   A,(AtomExpressionParenDepth)
            OR   A
            JR   Z,_AtomExpressionDelimiter
            CALL AtomExpressionReduceToParen
            RET  C
            CALL AtomExpressionPopOperator
            RET  C
            LD   HL,AtomExpressionParenDepth
            DEC  (HL)
            CALL AtomExpressionNextToken
            RET  C
            CALL AtomExpressionApplyUnary
            RET  C
            XOR  A
            INC  A
            RET
_AtomExpressionDelimiter:
            LD   A,(AtomExpressionParenDepth)
            OR   A
            JR   Z,_AtomExpressionDelimiterDone
            LD   A,AtomExpressionStatusExpectedRight
            JP   AtomExpressionFailHere
_AtomExpressionDelimiterDone:
            XOR  A
            RET

; Resolve or retain one exact symbol key. Missing symbols are not inserted
; until the complete expression has passed.
.routine out A,carry clobbers BC,HL,IX,zero,sign,parity,halfCarry,DE,IY
AtomExpressionPrimaryName:
            LD   A,(AtomTokenRecord+AtomTokenPartOffset)
            LD   (AtomExpressionSymbolPart),A
            LD   HL,(AtomTokenRecord+AtomTokenSourceOffset)
            LD   (AtomExpressionSymbolOffset),HL
            CALL AtomTokenLoadLexeme
            LD   DE,AtomExpressionResultKey
            CALL AtomPackSymbol
            JP   C,AtomExpressionSymbolFailure
            LD   HL,AtomExpressionResultKey
            CALL AtomSymbolFind
            JR   C,_AtomExpressionPrimaryMissing
            BIT  6,(IX+5)
            JR   Z,_AtomExpressionPrimaryUnresolved
            LD   L,(IX+AtomSymbolValueLow)
            LD   H,(IX+AtomSymbolValueHigh)
.if AtomSymbolStatementMode
            BIT  5,(IX+5)
            JR   Z,_AtomExpressionPrimaryPositiveSymbol
            LD   (AtomExpressionResultValue),HL
            LD   A,$FF
            LD   (AtomExpressionResultValue+2),A
            XOR  A
            JR   _AtomExpressionStoreUnresolved
_AtomExpressionPrimaryPositiveSymbol:
.endif
            CALL AtomExpressionSetResolvedWord
            JP   AtomExpressionNextToken
_AtomExpressionPrimaryMissing:
            CP   AtomStatusNotFound
            JR   Z,_AtomExpressionPrimaryUnresolved
            JP   AtomExpressionSymbolFailure
_AtomExpressionPrimaryUnresolved:
            XOR  A
            LD   (AtomExpressionResultValue),A
            LD   (AtomExpressionResultValue+1),A
            LD   (AtomExpressionResultValue+2),A
            INC  A
_AtomExpressionStoreUnresolved:
            LD   (AtomExpressionResultUnresolved),A
            JP   AtomExpressionNextToken

; Classify the current token as a binary operator. Carry means delimiter.
.routine out A,carry clobbers zero,sign,parity,halfCarry,C,HL
AtomExpressionClassifyOperator:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            SUB  AtomTokenPlus
            CP   12
            JR   NC,_AtomExpressionOperatorDelimiter
            PUSH DE
            LD   E,A
            LD   D,0
            LD   HL,AtomExpressionOperatorTable
            ADD  HL,DE
            LD   A,(HL)
            POP  DE
            OR   A
            JR   Z,_AtomExpressionOperatorDelimiter
            LD   (AtomExpressionOperator),A
            CALL AtomExpressionCaptureOperatorPosition
            OR   A
            RET
_AtomExpressionOperatorDelimiter:
            SCF
            RET

; High nibble is precedence; low nibble is the internal operation ordinal.
AtomExpressionOperatorTable:
            .db $55,$56,$67,$68,$69,$32,$21,$10,0,0,$43,$44

.routine out carry,zero clobbers A,HL,sign,parity,halfCarry
AtomExpressionCaptureOperatorPosition:
            LD   A,(AtomTokenRecord+AtomTokenPartOffset)
            LD   (AtomExpressionOperatorPart),A
            LD   HL,(AtomTokenRecord+AtomTokenSourceOffset)
            LD   (AtomExpressionOperatorOffset),HL
            RET

; Bounded value stack. Each entry is the three-byte value, unresolved flag,
; and exact six-byte symbol key.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPushValue:
            LD   A,(AtomExpressionValueDepth)
            CP   AtomExpressionValueCapacity
            JP   NC,AtomExpressionCapacityFailure
            CALL AtomExpressionValueAddress
            LD   D,H
            LD   E,L
            LD   HL,AtomExpressionResultValue
            LD   BC,AtomExpressionValueBytes
            LDIR
            LD   HL,AtomExpressionValueDepth
            INC  (HL)
            XOR  A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPopValue:
            LD   DE,AtomExpressionResultValue
            JR   AtomExpressionPopValueTo

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPopLeftValue:
            LD   DE,AtomExpressionLeftValue

.routine in DE out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPopValueTo:
            PUSH DE
            LD   A,(AtomExpressionValueDepth)
            OR   A
            JR   Z,AtomExpressionPopValueEmpty
            DEC  A
            LD   (AtomExpressionValueDepth),A
            CALL AtomExpressionValueAddress
            POP  DE
            LD   BC,AtomExpressionValueBytes
            LDIR
            XOR  A
            RET
AtomExpressionPopValueEmpty:
            POP  DE
            JR   AtomExpressionInternalFailure

; A=value index, out HL=value address (index*10).
.routine in A out HL clobbers DE,A,F
AtomExpressionValueAddress:
            LD   E,A
            LD   D,0
            LD   H,D
            LD   L,E
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            EX   DE,HL
            ADD  HL,HL
            ADD  HL,DE
            LD   DE,AtomExpressionValueStack
            ADD  HL,DE
            RET

; Bounded operator stack. Entry is ordinal, precedence, source part, offset.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPushOperator:
            LD   A,(AtomExpressionOperatorDepth)
            CP   AtomExpressionOperatorCapacity
            JR   NC,AtomExpressionCapacityFailure
            CALL AtomExpressionOperatorAddress
            LD   D,H
            LD   E,L
            LD   HL,AtomExpressionOperator
            LD   BC,AtomExpressionOperatorBytes
            LDIR
            LD   HL,AtomExpressionOperatorDepth
            INC  (HL)
            XOR  A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE
AtomExpressionPopOperator:
            LD   A,(AtomExpressionOperatorDepth)
            OR   A
            JR   Z,AtomExpressionInternalFailure
            DEC  A
            LD   (AtomExpressionOperatorDepth),A
            CALL AtomExpressionOperatorAddress
            LD   DE,AtomExpressionOperator
            LD   BC,AtomExpressionOperatorBytes
            LDIR
            XOR  A
            RET

; A=operator index, out HL=operator address (index*5).
.routine in A out HL clobbers DE,A,F
AtomExpressionOperatorAddress:
            LD   L,A
            LD   H,0
            ADD  HL,HL
            ADD  HL,HL
            LD   DE,AtomExpressionOperatorStack
            ADD  HL,DE
            RET

; Load the top operator without changing its stack depth.
.routine out A,carry clobbers zero,sign,parity,halfCarry,DE,HL
AtomExpressionPeekOperator:
            LD   A,(AtomExpressionOperatorDepth)
            OR   A
            SCF
            RET  Z
            DEC  A
            CALL AtomExpressionOperatorAddress
            LD   A,(HL)
            OR   A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionCapacityFailure:
            LD   A,AtomExpressionStatusCapacity
            JP   AtomExpressionFailHere
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionInternalFailure:
            LD   A,AtomExpressionStatusInternal
            JP   AtomExpressionFailHere

; Save/restore an incoming binary operator while older operators reduce.
.routine out carry,zero clobbers BC,DE,HL,parity,halfCarry,sign,A
AtomExpressionSaveIncoming:
            LD   HL,AtomExpressionOperator
            LD   DE,AtomExpressionIncoming
            JR   AtomExpressionCopyIncoming
.routine out carry,zero clobbers BC,DE,HL,parity,halfCarry,sign,A
AtomExpressionRestoreIncoming:
            LD   HL,AtomExpressionIncoming
            LD   DE,AtomExpressionOperator
.routine in HL,DE out carry,zero clobbers BC,DE,HL,parity,halfCarry,sign,A
AtomExpressionCopyIncoming:
            LD   BC,AtomExpressionOperatorBytes
            LDIR
            RET

; Reduce stacked operators with precedence >= the saved incoming operator.
.routine out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC,IX,IY
AtomExpressionReduceIncoming:
_AtomExpressionReduceIncomingLoop:
            CALL AtomExpressionPeekOperator
            JR   C,_AtomExpressionReduceIncomingDone
            CP   AtomExpressionMarkerLeftParen
            JR   Z,_AtomExpressionReduceIncomingDone
            AND  $F0
            LD   B,A
            LD   A,(AtomExpressionIncoming)
            AND  $F0
            CP   B
            JR   C,_AtomExpressionReduceIncomingNow
            RET  NZ
_AtomExpressionReduceIncomingNow:
            CALL AtomExpressionReduce
            RET  C
            JR   _AtomExpressionReduceIncomingLoop
_AtomExpressionReduceIncomingDone:
            XOR  A
            RET

; Reduce until the top entry is a left-parenthesis marker.
.routine out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC,IX,IY
AtomExpressionReduceToParen:
_AtomExpressionReduceToParenLoop:
            CALL AtomExpressionPeekOperator
            JR   C,AtomExpressionInternalFailure
            CP   AtomExpressionMarkerLeftParen
            RET  Z
            CALL AtomExpressionReduce
            RET  C
            JR   _AtomExpressionReduceToParenLoop

; Apply all unary operators sitting immediately above a completed primary.
.routine out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IX,IY
AtomExpressionApplyUnary:
_AtomExpressionApplyUnaryLoop:
            CALL AtomExpressionPeekOperator
            JR   C,_AtomExpressionApplyUnaryDone
            AND  $F0
            CP   $70
            JR   NZ,_AtomExpressionApplyUnaryDone
            CALL AtomExpressionPopOperator
            RET  C
            CALL AtomExpressionPopValue
            RET  C
            LD   A,(AtomExpressionResultUnresolved)
            OR   A
            JR   Z,_AtomExpressionApplyUnaryConcrete
            LD   A,(AtomExpressionOperator)
            CP   AtomExpressionUnaryPlus
            JR   Z,_AtomExpressionApplyUnaryPublish
            CP   AtomExpressionUnaryLow
            JR   Z,_AtomExpressionApplyUnaryForwardLow
            CP   AtomExpressionUnaryHigh
            JR   Z,_AtomExpressionApplyUnaryForwardHigh
_AtomExpressionApplyUnaryForwardFailure:
            LD   A,AtomExpressionStatusForwardForm
            JP   AtomExpressionFailOperator
_AtomExpressionApplyUnaryForwardLow:
            LD   B,AtomExpressionForwardLow
            JR   _AtomExpressionApplyUnaryForwardFunction
_AtomExpressionApplyUnaryForwardHigh:
            LD   B,AtomExpressionForwardHigh
_AtomExpressionApplyUnaryForwardFunction:
            LD   A,(AtomExpressionResultUnresolved)
            CP   AtomExpressionForwardPlain
            JR   NZ,_AtomExpressionApplyUnaryForwardFailure
            LD   A,B
            LD   (AtomExpressionResultUnresolved),A
            JR   _AtomExpressionApplyUnaryPublish
_AtomExpressionApplyUnaryConcrete:
            LD   A,(AtomExpressionOperator)
            CP   AtomExpressionUnaryPlus
            JR   Z,_AtomExpressionApplyUnaryPublish
            CP   AtomExpressionUnaryMinus
            JR   Z,_AtomExpressionApplyUnaryNegate
            CP   AtomExpressionUnaryTilde
            JR   Z,_AtomExpressionApplyUnaryComplement
            CP   AtomExpressionUnaryLow
            JR   Z,_AtomExpressionApplyUnaryLow
            CP   AtomExpressionUnaryHigh
            JR   Z,_AtomExpressionApplyUnaryHigh
            JP   AtomExpressionInternalFailure
_AtomExpressionApplyUnaryNegate:
            CALL AtomExpressionNegateResult
            JR   _AtomExpressionApplyUnaryConcreteDone
_AtomExpressionApplyUnaryComplement:
            CALL AtomExpressionComplementResult
            JR   _AtomExpressionApplyUnaryConcreteDone
_AtomExpressionApplyUnaryLow:
            XOR  A
            LD   (AtomExpressionResultValue+1),A
            LD   (AtomExpressionResultValue+2),A
            JR   _AtomExpressionApplyUnaryConcreteDone
_AtomExpressionApplyUnaryHigh:
            LD   A,(AtomExpressionResultValue+1)
            LD   (AtomExpressionResultValue),A
            XOR  A
            LD   (AtomExpressionResultValue+1),A
            LD   (AtomExpressionResultValue+2),A
_AtomExpressionApplyUnaryConcreteDone:
            RET  C
_AtomExpressionApplyUnaryPublish:
            CALL AtomExpressionPushValue
            RET  C
            JP   _AtomExpressionApplyUnaryLoop
_AtomExpressionApplyUnaryDone:
            XOR  A
            RET

; Reduce all remaining binary operators and publish the sole value.
.routine out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC,IX,IY
AtomExpressionFinishStacks:
_AtomExpressionFinishReduce:
            CALL AtomExpressionPeekOperator
            JR   C,_AtomExpressionFinishValue
            CP   AtomExpressionMarkerLeftParen
            JP   Z,AtomExpressionInternalFailure
            CALL AtomExpressionReduce
            RET  C
            JR   _AtomExpressionFinishReduce
_AtomExpressionFinishValue:
            CALL AtomExpressionPopValue
            RET  C
            LD   A,(AtomExpressionValueDepth)
            OR   A
            JP   NZ,AtomExpressionInternalFailure
            RET

; Combine the two top values using the top binary operator.
.routine out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IX,IY
AtomExpressionReduce:
            CALL AtomExpressionPopOperator
            RET  C
            CALL AtomExpressionPopValue
            RET  C
            CALL AtomExpressionPopLeftValue
            RET  C
            CALL AtomExpressionReduceLoaded
            RET  C
            JP   AtomExpressionPushValue

.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomExpressionReduceLoaded:
            LD   A,(AtomExpressionLeftUnresolved)
            LD   B,A
            LD   A,(AtomExpressionResultUnresolved)
            OR   B
            JR   NZ,AtomExpressionReduceForward
            LD   A,(AtomExpressionOperator)
            AND  $0F
            CP   10
            JP   NC,AtomExpressionInternalFailure
            ADD  A,A
            LD   L,A
            LD   H,0
            LD   DE,AtomExpressionReductionTable
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            JP   (HL)

AtomExpressionReductionTable:
            .dw AtomExpressionOr,AtomExpressionXor,AtomExpressionAnd
            .dw AtomExpressionShiftLeft,AtomExpressionShiftRight
            .dw AtomExpressionAdd,AtomExpressionSubtract
            .dw AtomExpressionMultiply,AtomExpressionDivide
            .dw AtomExpressionRemainder

; Deferred expressions are one symbol plus or minus a resolved signed byte.
.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomExpressionReduceForward:
            LD   A,(AtomExpressionLeftUnresolved)
            CP   AtomExpressionForwardLow
            JR   NC,_AtomExpressionForwardFailure
            LD   A,(AtomExpressionResultUnresolved)
            CP   AtomExpressionForwardLow
            JR   NC,_AtomExpressionForwardFailure
            LD   A,(AtomExpressionLeftUnresolved)
            OR   A
            JR   Z,_AtomExpressionForwardRight
            LD   A,(AtomExpressionResultUnresolved)
            OR   A
            JR   NZ,_AtomExpressionForwardFailure
            LD   A,(AtomExpressionOperator)
            AND  $0F
            CP   AtomExpressionOpAdd
            JR   Z,_AtomExpressionForwardLeftAdd
            CP   AtomExpressionOpSubtract
            JR   NZ,_AtomExpressionForwardFailure
            CALL AtomExpressionSubtract
            JR   C,_AtomExpressionForwardReturn
            JR   _AtomExpressionForwardUseLeftKey
_AtomExpressionForwardLeftAdd:
            CALL AtomExpressionAdd
            JR   C,_AtomExpressionForwardReturn
_AtomExpressionForwardUseLeftKey:
            LD   HL,AtomExpressionLeftKey
            LD   DE,AtomExpressionResultKey
            LD   BC,6
            LDIR
            JR   _AtomExpressionForwardFinish
_AtomExpressionForwardRight:
            LD   A,(AtomExpressionOperator)
            AND  $0F
            CP   AtomExpressionOpAdd
            JR   NZ,_AtomExpressionForwardFailure
            CALL AtomExpressionAdd
            JR   C,_AtomExpressionForwardReturn
            ; The right key already occupies AtomExpressionResultKey.
_AtomExpressionForwardFinish:
            LD   A,AtomExpressionForwardPlain
            LD   (AtomExpressionResultUnresolved),A
            CALL AtomExpressionRequireAddend
_AtomExpressionForwardReturn:
            RET
_AtomExpressionForwardFailure:
            LD   A,AtomExpressionStatusForwardForm
            JP   AtomExpressionFailOperator

; Concrete 24-bit operations. Left op Result -> Result.
.routine out A,BC,HL clobbers carry,zero,sign,parity,halfCarry
AtomExpressionLoadArithmetic:
            LD   A,(AtomExpressionLeftValue+2)
            LD   B,A
            LD   A,(AtomExpressionResultValue+2)
            LD   C,A
            LD   A,(AtomExpressionLeftValue)
            LD   HL,AtomExpressionResultValue
            RET

.routine out A,carry clobbers BC,HL,sign,parity,halfCarry,DE,zero
AtomExpressionAdd:
            CALL AtomExpressionLoadArithmetic
            ADD  A,(HL)
            LD   (HL),A
            INC  HL
            LD   A,(AtomExpressionLeftValue+1)
            ADC  A,(HL)
            LD   (HL),A
            INC  HL
            LD   A,B
            ADC  A,(HL)
            LD   (HL),A
            LD   D,A
            LD   A,B
            XOR  C
            BIT  7,A
            JR   NZ,AtomExpressionArithmeticOk
            LD   A,B
            XOR  D
            BIT  7,A
            JP   NZ,AtomExpressionRangeOperator
.routine out A,carry,zero clobbers sign,parity,halfCarry
AtomExpressionArithmeticOk:
            XOR  A
            RET

.routine out A,carry clobbers BC,HL,sign,parity,halfCarry,DE,zero,IX,IY
AtomExpressionSubtract:
            CALL AtomExpressionLoadArithmetic
            SUB  (HL)
            LD   (HL),A
            INC  HL
            LD   A,(AtomExpressionLeftValue+1)
            SBC  A,(HL)
            LD   (HL),A
            INC  HL
            LD   A,B
            SBC  A,(HL)
            LD   (HL),A
            LD   D,A
            LD   A,B
            XOR  C
            BIT  7,A
            JR   Z,AtomExpressionArithmeticOk
            LD   A,B
            XOR  D
            BIT  7,A
            JP   NZ,AtomExpressionRangeOperator
            JR   AtomExpressionArithmeticOk

.routine out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomExpressionAnd:
            LD   HL,AtomExpressionResultValue
            LD   DE,AtomExpressionLeftValue
            LD   B,3
_AtomExpressionAndLoop:
            LD   A,(DE)
            AND  (HL)
            LD   (HL),A
            INC  DE
            INC  HL
            DJNZ _AtomExpressionAndLoop
            XOR  A
            RET

.routine out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomExpressionXor:
            LD   HL,AtomExpressionResultValue
            LD   DE,AtomExpressionLeftValue
            LD   B,3
_AtomExpressionXorLoop:
            LD   A,(DE)
            XOR  (HL)
            LD   (HL),A
            INC  DE
            INC  HL
            DJNZ _AtomExpressionXorLoop
            XOR  A
            RET

.routine out A,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomExpressionOr:
            LD   HL,AtomExpressionResultValue
            LD   DE,AtomExpressionLeftValue
            LD   B,3
_AtomExpressionOrLoop:
            LD   A,(DE)
            OR   (HL)
            LD   (HL),A
            INC  DE
            INC  HL
            DJNZ _AtomExpressionOrLoop
            XOR  A
            RET

; Shift the unsigned 24-bit word at HL left once, preserving the final carry.
.routine in HL out A,HL,carry clobbers zero,sign,parity,halfCarry
AtomExpressionShiftLeft24:
            LD   A,(HL)
            SLA  A
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            RL   A
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            RL   A
            LD   (HL),A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE,IX,IY
AtomExpressionShiftLeft:
            CALL AtomExpressionShiftCount
            RET  C
            LD   B,A
            OR   A
            JR   Z,_AtomExpressionShiftLeftCopy
_AtomExpressionShiftLeftLoop:
            LD   A,(AtomExpressionLeftValue+2)
            LD   C,A
            LD   HL,AtomExpressionLeftValue
            CALL AtomExpressionShiftLeft24
            XOR  C
            BIT  7,A
            JP   NZ,AtomExpressionRangeOperator
            DJNZ _AtomExpressionShiftLeftLoop
_AtomExpressionShiftLeftCopy:
            LD   HL,AtomExpressionLeftValue
            LD   DE,AtomExpressionResultValue
            LD   BC,3
            LDIR
            XOR  A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE,IX,IY
AtomExpressionShiftRight:
            CALL AtomExpressionShiftCount
            RET  C
            LD   B,A
            PUSH BC
            LD   HL,AtomExpressionLeftValue
            LD   DE,AtomExpressionResultValue
            LD   BC,3
            LDIR
            POP  BC
            LD   A,B
            OR   A
            JP   Z,AtomExpressionArithmeticOk
            LD   B,A
_AtomExpressionShiftRightLoop:
            LD   HL,AtomExpressionResultValue+2
            LD   A,(HL)
            SRA  A
            CALL AtomExpressionShiftRightLow16
            DJNZ _AtomExpressionShiftRightLoop
            XOR  A
            RET

; Shift count is the concrete right operand and must be 0..23.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionShiftCount:
            LD   A,(AtomExpressionResultValue+2)
            OR   A
            JP   NZ,AtomExpressionRangeOperator
            LD   A,(AtomExpressionResultValue+1)
            OR   A
            JP   NZ,AtomExpressionRangeOperator
            LD   A,(AtomExpressionResultValue)
            CP   24
            JP   NC,AtomExpressionRangeOperator
            OR   A
            RET

; Signed multiply through unsigned magnitudes with exact 24-bit overflow.
.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomExpressionMultiply:
            CALL AtomExpressionPrepareMagnitudes
            XOR  A
            LD   (AtomExpressionAccumulator),A
            LD   (AtomExpressionAccumulator+1),A
            LD   (AtomExpressionAccumulator+2),A
            LD   A,24
            LD   (AtomExpressionMultiplyCounter),A
_AtomExpressionMultiplyLoop:
            LD   A,(AtomExpressionMagnitudeRight)
            BIT  0,A
            JR   Z,_AtomExpressionMultiplySkipAdd
            CALL AtomExpressionAccumulatorAddLeft
            JP   C,AtomExpressionRangeOperator
_AtomExpressionMultiplySkipAdd:
            CALL AtomExpressionMagnitudeRightShift
            LD   A,(AtomExpressionMagnitudeRight)
            LD   C,A
            LD   A,(AtomExpressionMagnitudeRight+1)
            OR   C
            LD   C,A
            LD   A,(AtomExpressionMagnitudeRight+2)
            OR   C
            JR   Z,_AtomExpressionMultiplyDone
            LD   A,(AtomExpressionMagnitudeLeft+2)
            BIT  7,A
            JP   NZ,AtomExpressionRangeOperator
            CALL AtomExpressionMagnitudeLeftShift
            LD   HL,AtomExpressionMultiplyCounter
            DEC  (HL)
            JR   NZ,_AtomExpressionMultiplyLoop
_AtomExpressionMultiplyDone:
            LD   HL,AtomExpressionAccumulator
            LD   DE,AtomExpressionResultValue
            LD   BC,3
            LDIR
            LD   A,(AtomExpressionSignResult)
            OR   A
AtomExpressionApplySignResult:
            CALL NZ,AtomExpressionNegateResult
            RET  C
            XOR  A
            RET

.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomExpressionDivide:
            XOR  A
            LD   (AtomExpressionDivisionRemainderMode),A
            JR   AtomExpressionDivideCommon
.routine out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomExpressionRemainder:
            LD   A,1
            LD   (AtomExpressionDivisionRemainderMode),A
.routine out A,carry clobbers BC,DE,HL,IX,IY,sign,parity,halfCarry,zero
AtomExpressionDivideCommon:
            LD   A,(AtomExpressionResultValue)
            LD   B,A
            LD   A,(AtomExpressionResultValue+1)
            OR   B
            LD   B,A
            LD   A,(AtomExpressionResultValue+2)
            OR   B
            JR   Z,_AtomExpressionDivideZero
            CALL AtomExpressionPrepareMagnitudes
            XOR  A
            LD   (AtomExpressionAccumulator),A
            LD   (AtomExpressionAccumulator+1),A
            LD   (AtomExpressionAccumulator+2),A
            LD   (AtomExpressionQuotient),A
            LD   (AtomExpressionQuotient+1),A
            LD   (AtomExpressionQuotient+2),A
            LD   B,24
_AtomExpressionDivideLoop:
            LD   HL,AtomExpressionMagnitudeLeft
            CALL AtomExpressionShiftLeft24
            LD   HL,AtomExpressionAccumulator
            LD   A,(HL)
            RL   A
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            RL   A
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            RL   A
            LD   (HL),A
            LD   HL,AtomExpressionQuotient
            CALL AtomExpressionShiftLeft24
            CALL AtomExpressionRemainderAtLeastDivisor
            JR   C,_AtomExpressionDivideNext
            CALL AtomExpressionRemainderSubtractDivisor
            LD   HL,AtomExpressionQuotient
            LD   A,(HL)
            SET  0,A
            LD   (HL),A
_AtomExpressionDivideNext:
            DJNZ _AtomExpressionDivideLoop
            LD   A,(AtomExpressionDivisionRemainderMode)
            OR   A
            JR   NZ,_AtomExpressionUseRemainder
            LD   HL,AtomExpressionQuotient
            LD   A,(AtomExpressionSignResult)
            JR   _AtomExpressionDivisionStore
_AtomExpressionUseRemainder:
            LD   HL,AtomExpressionAccumulator
            LD   A,(AtomExpressionSignLeft)
_AtomExpressionDivisionStore:
            LD   DE,AtomExpressionResultValue
            LD   BC,3
            LDIR
            OR   A
            JP   AtomExpressionApplySignResult
_AtomExpressionDivideZero:
            LD   A,AtomExpressionStatusDivideZero
            JP   AtomExpressionFailOperator

; Prepare absolute 24-bit operands and their result sign.
.routine out carry,zero clobbers A,BC,DE,HL,IX,IY,sign,parity,halfCarry
AtomExpressionPrepareMagnitudes:
            LD   HL,AtomExpressionLeftValue
            LD   DE,AtomExpressionMagnitudeLeft
            LD   BC,3
            LDIR
            LD   HL,AtomExpressionResultValue
            LD   DE,AtomExpressionMagnitudeRight
            LD   BC,3
            LDIR
            LD   A,(AtomExpressionLeftValue+2)
            RLCA
            AND  1
            LD   (AtomExpressionSignLeft),A
            OR   A
            CALL NZ,AtomExpressionNegateMagnitudeLeft
            LD   A,(AtomExpressionResultValue+2)
            RLCA
            AND  1
            LD   (AtomExpressionSignRight),A
            OR   A
            CALL NZ,AtomExpressionNegateMagnitudeRight
            LD   A,(AtomExpressionSignLeft)
            LD   HL,AtomExpressionSignRight
            XOR  (HL)
            LD   (AtomExpressionSignResult),A
            OR   A
            RET

.routine out carry,zero clobbers HL,sign,parity,halfCarry,A,BC,DE,IX,IY
AtomExpressionNegateResult:
            LD   HL,AtomExpressionResultValue
            JR   AtomExpressionNegateAtHL
.routine out carry,zero clobbers HL,sign,parity,halfCarry,A,BC,DE,IX,IY
AtomExpressionNegateMagnitudeLeft:
            LD   HL,AtomExpressionMagnitudeLeft
            JR   AtomExpressionNegateAtHL
.routine out carry,zero clobbers HL,A,BC,DE,IX,IY,sign,parity,halfCarry
AtomExpressionNegateMagnitudeRight:
            LD   HL,AtomExpressionMagnitudeRight
.routine in HL out A,carry,zero clobbers HL,sign,parity,halfCarry
AtomExpressionNegateAtHL:
            LD   A,(HL)
            CPL
            ADD  A,1
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            CPL
            ADC  A,0
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            CPL
            ADC  A,0
            LD   (HL),A
            XOR  A
            RET

.routine out carry,zero clobbers HL,sign,parity,halfCarry,A
AtomExpressionComplementResult:
            LD   HL,AtomExpressionResultValue
            LD   A,(HL)
            CPL
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            CPL
            LD   (HL),A
            INC  HL
            LD   A,(HL)
            CPL
            LD   (HL),A
            XOR  A
            RET

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionAccumulatorAddLeft:
            LD   HL,AtomExpressionAccumulator
            LD   A,(AtomExpressionMagnitudeLeft)
            ADD  A,(HL)
            LD   (HL),A
            INC  HL
            LD   A,(AtomExpressionMagnitudeLeft+1)
            ADC  A,(HL)
            LD   (HL),A
            INC  HL
            LD   A,(AtomExpressionMagnitudeLeft+2)
            ADC  A,(HL)
            LD   (HL),A
            RET

.routine out carry,zero maybe-out BC,DE clobbers A,HL,sign,parity,halfCarry,IX,IY,BC,DE
AtomExpressionMagnitudeLeftShift:
            LD   HL,AtomExpressionMagnitudeLeft
            JP   AtomExpressionShiftLeft24
.routine out carry,zero maybe-out BC,DE clobbers A,HL,sign,parity,halfCarry,IX,IY,BC,DE
AtomExpressionMagnitudeRightShift:
            LD   HL,AtomExpressionMagnitudeRight+2
            LD   A,(HL)
            SRL  A

.routine in A,HL out carry,zero clobbers A,HL,sign,parity,halfCarry
AtomExpressionShiftRightLow16:
            LD   (HL),A
            DEC  HL
            LD   A,(HL)
            RR   A
            LD   (HL),A
            DEC  HL
            LD   A,(HL)
            RR   A
            LD   (HL),A
            RET

; Carry clear when unsigned remainder >= divisor.
.routine out A,carry,zero clobbers HL,sign,parity,halfCarry
AtomExpressionRemainderAtLeastDivisor:
            LD   A,(AtomExpressionAccumulator+2)
            LD   HL,AtomExpressionMagnitudeRight+2
            CP   (HL)
            RET  NZ
            LD   A,(AtomExpressionAccumulator+1)
            DEC  HL
            CP   (HL)
            RET  NZ
            LD   A,(AtomExpressionAccumulator)
            DEC  HL
            CP   (HL)
            RET

.routine out carry,zero clobbers A,C,DE,HL,sign,parity,halfCarry
AtomExpressionRemainderSubtractDivisor:
            LD   HL,AtomExpressionAccumulator
            LD   DE,AtomExpressionMagnitudeRight
            LD   A,(DE)
            LD   C,A
            LD   A,(HL)
            SUB  C
            LD   (HL),A
            INC  HL
            INC  DE
            LD   A,(DE)
            LD   C,A
            LD   A,(HL)
            SBC  A,C
            LD   (HL),A
            INC  HL
            INC  DE
            LD   A,(DE)
            LD   C,A
            LD   A,(HL)
            SBC  A,C
            LD   (HL),A
            RET

; Publish a concrete word as a positive 24-bit resolved result.
.routine in HL out carry,zero clobbers A,sign,parity,halfCarry
AtomExpressionSetResolvedWord:
            LD   (AtomExpressionResultValue),HL
            XOR  A
            LD   (AtomExpressionResultValue+2),A
            LD   (AtomExpressionResultUnresolved),A
            RET

; Concrete result must lie in AZM's accepted -32768..65535 word domain.
.routine out A,carry clobbers zero,sign,parity,halfCarry,HL
AtomExpressionRequireWord:
            LD   A,(AtomExpressionResultValue+2)
            OR   A
            RET  Z
            INC  A
            JR   NZ,_AtomExpressionRangeHere
            LD   A,(AtomExpressionResultValue+1)
            BIT  7,A
            RET  NZ
_AtomExpressionRangeHere:
            LD   A,AtomExpressionStatusRange
            JR   AtomExpressionFailHere

; Deferred addend must be exactly sign-extended signed byte.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE,IX,IY
AtomExpressionRequireAddend:
            LD   A,(AtomExpressionResultValue+2)
            OR   A
            JR   Z,_AtomExpressionAddendPositive
            INC  A
            JR   NZ,AtomExpressionRangeOperator
            LD   A,(AtomExpressionResultValue+1)
            INC  A
            JR   NZ,AtomExpressionRangeOperator
            LD   A,(AtomExpressionResultValue)
            BIT  7,A
            RET  NZ
            JR   AtomExpressionRangeOperator
_AtomExpressionAddendPositive:
            LD   A,(AtomExpressionResultValue+1)
            OR   A
            JR   NZ,AtomExpressionRangeOperator
            LD   A,(AtomExpressionResultValue)
            BIT  7,A
            JR   NZ,AtomExpressionRangeOperator
            OR   A
            RET

; Tokenizer handoff.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomExpressionNextToken:
            CALL AtomTokenizerNext
            RET  NC
            LD   A,AtomExpressionStatusLexical
            JR   AtomExpressionFailTokenizer

.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomExpressionRangeOperator:
            LD   A,AtomExpressionStatusRange
            JR   AtomExpressionFailOperator

; Failure positions.
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomExpressionFailHere:
            LD   HL,AtomTokenRecord+AtomTokenPartOffset
            JR   AtomExpressionFailPosition
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomExpressionFailOperator:
            LD   HL,AtomExpressionOperatorPart
            JR   AtomExpressionFailPosition
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomExpressionFailSymbol:
            LD   HL,AtomExpressionSymbolPart
            JR   AtomExpressionFailPosition
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomExpressionFailTokenizer:
            LD   HL,AtomTokenErrorPart

.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomExpressionFailPosition:
            PUSH BC
            PUSH DE
            LD   DE,AtomExpressionErrorPart
            LD   BC,3
            LDIR
            POP  DE
            POP  BC
            SCF
            RET

AtomExpressionRuleCodeEnd:
AtomExpressionCodeEnd:

AtomExpressionWorkspaceStart:
AtomExpressionCurrentAddress:       .dw 0
.if AtomExpressionDeferredMode
AtomExpressionPublishSymbol:        .db 0
.endif
AtomExpressionResultValue:          .ds 3
AtomExpressionResultUnresolved:     .db 0
AtomExpressionResultKey:            .ds 6
AtomExpressionLeftValue:            .ds 3
AtomExpressionLeftUnresolved:       .db 0
AtomExpressionLeftKey:              .ds 6
AtomExpressionOperator:             .db 0
AtomExpressionOperatorPart:         .db 0
AtomExpressionOperatorOffset:       .dw 0
AtomExpressionIncoming:             .ds AtomExpressionOperatorBytes
AtomExpressionSymbolPart:           .db 0
AtomExpressionSymbolOffset:         .dw 0
AtomExpressionSymbolStatus:         .db 0
AtomExpressionMultiplyCounter:      .equ AtomExpressionSymbolStatus
AtomExpressionValueDepth:           .db 0
AtomExpressionOperatorDepth:        .db 0
AtomExpressionParenDepth:           .db 0
AtomExpressionExpectOperand:        .db 0
AtomExpressionSignLeft:             .equ AtomExpressionSymbolPart
AtomExpressionSignRight:            .equ AtomExpressionSymbolOffset
AtomExpressionSignResult:           .equ AtomExpressionSymbolOffset+1
AtomExpressionDivisionRemainderMode:.equ AtomExpressionMultiplyCounter
AtomExpressionMagnitudeLeft:        .equ AtomExpressionResultKey
AtomExpressionMagnitudeRight:       .equ AtomExpressionResultKey+3
AtomExpressionAccumulator:          .equ AtomExpressionLeftKey
AtomExpressionErrorPart:            .equ AtomExpressionAccumulator
AtomExpressionErrorOffset:          .equ AtomExpressionAccumulator+1
AtomExpressionQuotient:             .equ AtomExpressionLeftKey+3
AtomExpressionValueStack:           .ds AtomExpressionValueBytes*AtomExpressionValueCapacity
AtomExpressionOperatorStack:        .ds AtomExpressionOperatorBytes*AtomExpressionOperatorCapacity
AtomExpressionWorkspaceEnd:
