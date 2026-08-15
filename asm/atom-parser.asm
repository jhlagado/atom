; atom instruction parser. Phase 2c assembles the concrete-only path;
; Phase 2e enables expression and forward-reference integration.
;
; This module consumes one tokenized instruction line and commits the existing
; ten-byte encoder record only after syntax, form, and concrete ranges pass.
; Symbols and general expressions belong to a later phase.

AtomParserCodeStart:

AtomParserStatusOk:              .equ 0
AtomParserStatusEof:             .equ 1
AtomParserStatusLexical:         .equ 2
AtomParserStatusExpectedMnemonic:.equ 3
AtomParserStatusUnknownMnemonic: .equ 4
AtomParserStatusExpectedOperand: .equ 5
AtomParserStatusUnknownOperand:  .equ 6
AtomParserStatusExpectedDelimiter:.equ 7
AtomParserStatusTooManyOperands: .equ 8
AtomParserStatusInvalidForm:     .equ 9
AtomParserStatusValueRange:      .equ 10
AtomParserStatusRelativeRange:   .equ 11
AtomParserStatusInternal:        .equ 12
.if AtomParserExpressionMode
AtomParserStatusExpression:      .equ 13
AtomParserStatusUnpatchable:     .equ 14
AtomParserStatusSymbol:          .equ 15
AtomParserStatusReferenceCapacity:.equ 16

AtomParserReferenceCapacity:     .equ 2
AtomParserBuildReferenceBytes:   .equ 13
AtomParserPublicReferenceBytes:  .equ 9
AtomParserBuildKey:              .equ 0
AtomParserBuildAddend:           .equ 6
AtomParserBuildOperand:          .equ 7
AtomParserBuildKind:             .equ 8
AtomParserBuildPatchOffset:      .equ 9
AtomParserBuildPart:             .equ 10
AtomParserBuildSourceOffset:     .equ 11
AtomParserReferenceSymbol:       .equ 0
AtomParserReferenceAddend:       .equ 2
AtomParserReferenceOperand:      .equ 3
AtomParserReferenceKind:         .equ 4
AtomParserReferencePatchOffset:  .equ 5
AtomParserReferencePart:         .equ 6
AtomParserReferenceSourceOffset: .equ 7
.endif

; Scratch-only operand classes. They can never reach the committed record.
AtomParserGenericNumber:       .equ 240
AtomParserGenericParenNumber:  .equ 241
AtomParserGenericC:            .equ 242

; Parse the next instruction line.
;
; in BC=current instruction address, DE=ten-byte destination
; out success: A=0, IX=destination, carry clear
;     EOF: A=AtomParserStatusEof, carry clear, destination unchanged
;     failure: A=status, carry set, destination unchanged
.routine in BC,DE out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomParserParse:
            LD   (AtomParserInstructionAddress),BC
            LD   (AtomParserDestination),DE
.if AtomParserExpressionMode
            XOR  A
            LD   (AtomParserReferenceCount),A
.endif
            CALL AtomParserInitializeScratch
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEof
            JR   Z,_AtomParserEof
            CP   AtomTokenName
            JP   NZ,AtomParserExpectedMnemonic

            LD   A,(AtomTokenRecord+AtomTokenPartOffset)
            LD   (AtomParserInstructionPart),A
            LD   HL,(AtomTokenRecord+AtomTokenSourceOffset)
            LD   (AtomParserInstructionOffset),HL

            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            CALL AtomRecognizeMnemonic
            JP   C,AtomParserUnknownMnemonic
            LD   (AtomParserScratch+AtomInstrMnemonic),A

            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JR   Z,_AtomParserParsedOperands

_AtomParserOperandLoop:
            LD   A,(AtomParserOperandCount)
            CP   3
            JP   NC,AtomParserTooManyOperands
            CALL AtomParserSelectOperand
            CALL AtomParserParseOperand
            RET  C
            LD   HL,AtomParserOperandCount
            INC  (HL)
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JR   Z,_AtomParserParsedOperands
            CP   AtomTokenComma
            JP   NZ,AtomParserExpectedDelimiter
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   Z,AtomParserExpectedOperand
            JR   _AtomParserOperandLoop

_AtomParserParsedOperands:
            CALL AtomParserNormalizeAccumulatorAlias
            RET  C
            CALL AtomParserNormalizeNumbers
            RET  C
            CALL AtomParserValidateCandidates
            RET  C
            LD   (AtomParserInstructionLength),A
            CALL AtomParserCheckConcreteValues
            RET  C
.if AtomParserExpressionMode
            CALL AtomParserFinalizeReferences
            RET  C
.endif
            JP   AtomParserCommit

_AtomParserEof:
            LD   A,AtomParserStatusEof
            OR   A
            RET

; Clear the private record and per-instruction state.
.routine out carry,zero clobbers A,B,HL,sign,parity,halfCarry
AtomParserInitializeScratch:
            LD   HL,AtomParserScratch
            XOR  A
            LD   (HL),A
            INC  HL
            LD   B,3
            LD   A,AtomOpNone
_AtomParserInitializeOperands:
            LD   (HL),A
            INC  HL
            DJNZ _AtomParserInitializeOperands
            XOR  A
            LD   B,6
_AtomParserInitializeValues:
            LD   (HL),A
            INC  HL
            DJNZ _AtomParserInitializeValues
            LD   (AtomParserOperandCount),A
            LD   (AtomParserFlexibleMask),A
            LD   (AtomParserConditionMask),A
.if AtomParserExpressionMode
            LD   (AtomParserReferenceBuildCount),A
            LD   (AtomParserUnresolvedMask),A
.endif
            RET

; Map tokenizer failure to one parser status while retaining its exact source
; part and offset.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomParserNextToken:
            CALL AtomTokenizerNext
            RET  NC
            LD   A,(AtomTokenErrorPart)
            LD   (AtomParserErrorPart),A
            LD   HL,(AtomTokenErrorOffset)
            LD   (AtomParserErrorOffset),HL
            LD   A,AtomParserStatusLexical
            SCF
            RET

; Select class and value slots for operand index A.
.routine in A out carry,zero clobbers A,DE,HL,sign,parity,halfCarry
AtomParserSelectOperand:
            LD   E,A
            LD   D,0
            LD   HL,AtomParserScratch+AtomInstrOp0
            ADD  HL,DE
            LD   (AtomParserClassPointer),HL
            LD   A,E
            ADD  A,A
            LD   E,A
            LD   HL,AtomParserScratch+AtomInstrValue0
            ADD  HL,DE
            LD   (AtomParserValuePointer),HL
            RET

; Parse one operand and leave the following comma or EOL as current token.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomParserParseOperand:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenName
            JR   Z,_AtomParserOperandName
            CP   AtomTokenNumber
.if AtomParserExpressionMode
            JR   Z,_AtomParserOperandExpression
            CP   AtomTokenCurrent
            JR   Z,_AtomParserOperandExpression
            CP   AtomTokenPlus
            JR   Z,_AtomParserOperandExpression
            CP   AtomTokenMinus
            JR   Z,_AtomParserOperandExpression
            CP   AtomTokenTilde
            JR   Z,_AtomParserOperandExpression
.else
            JR   Z,_AtomParserOperandNumber
.endif
            CP   AtomTokenLeftParen
            JP   Z,AtomParserParseMemory
            JP   AtomParserExpectedOperand

_AtomParserOperandName:
            CALL AtomParserLookupOperandWord
.if AtomParserExpressionMode
            JR   C,_AtomParserOperandExpression
.else
            RET  C
.endif
            LD   HL,(AtomParserClassPointer)
            LD   (HL),A
            LD   (AtomParserLastClass),A
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomParserLastClass)
            CP   AtomOpAF
            JR   NZ,_AtomParserOperandParsed
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenApostrophe
            JR   NZ,_AtomParserOperandParsed
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpAFPrime
            JP   AtomParserNextToken
_AtomParserOperandParsed:
            XOR  A
            RET

.if AtomParserExpressionMode
_AtomParserOperandExpression:
            CALL AtomParserParseExpression
            RET  C
            LD   A,AtomParserGenericNumber
            LD   HL,(AtomParserClassPointer)
            LD   (HL),A
            XOR  A
            RET
.else
_AtomParserOperandNumber:
            LD   A,AtomParserGenericNumber
            LD   HL,(AtomParserClassPointer)
            LD   (HL),A
            CALL AtomParserStoreTokenValue
            JP   AtomParserNextToken
.endif

.if AtomParserExpressionMode
; Parse one general expression beginning at the current token. Concrete words
; enter the selected value slot. A forward affine expression enters the
; private two-entry build list without publishing its symbol record.
.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomParserParseExpression:
            LD   BC,(AtomParserInstructionAddress)
            CALL AtomExpressionParseDeferred
            JR   C,AtomParserExpressionFailure
            CP   AtomExpressionUnresolved
            JR   Z,AtomParserAddReference
            JP   AtomParserStoreHLValue

.routine in HL out carry,zero clobbers DE,sign,parity,halfCarry,A
AtomParserStoreHLValue:
            LD   DE,(AtomParserValuePointer)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            XOR  A
            RET

.routine in IX,HL out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IX
AtomParserAddReference:
            LD   (AtomParserReferenceAddendScratch),HL
            LD   A,(AtomParserReferenceBuildCount)
            CP   AtomParserReferenceCapacity
            JR   NC,AtomParserReferenceCapacityFailure
            CALL AtomParserBuildReferenceAddress
            PUSH IX
            POP  HL
            LD   BC,6
            LDIR
            LD   HL,(AtomParserReferenceAddendScratch)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,(AtomParserOperandCount)
            LD   (DE),A
            INC  DE
            XOR  A
            LD   (DE),A
            INC  DE
            LD   (DE),A
            INC  DE
            LD   A,(AtomExpressionSymbolPart)
            LD   (DE),A
            INC  DE
            LD   HL,(AtomExpressionSymbolOffset)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            LD   A,(AtomParserOperandCount)
            CALL AtomParserIndexBit
            LD   HL,AtomParserUnresolvedMask
            OR   (HL)
            LD   (HL),A
            LD   HL,AtomParserReferenceBuildCount
            INC  (HL)
            LD   HL,0
            JP   AtomParserStoreHLValue

AtomParserReferenceCapacityFailure:
            LD   A,AtomParserStatusReferenceCapacity
            JP   AtomParserFailExpressionSymbol

; A=build-reference index 0..1, out DE=entry address.
.routine in A out DE clobbers HL,A,F
AtomParserBuildReferenceAddress:
            LD   DE,AtomParserReferenceBuild
            OR   A
            RET  Z
            LD   HL,AtomParserBuildReferenceBytes
            ADD  HL,DE
            EX   DE,HL
            RET

AtomParserExpressionFailure:
            LD   (AtomParserExpressionStatus),A
            LD   A,(AtomExpressionErrorPart)
            LD   (AtomParserErrorPart),A
            LD   HL,(AtomExpressionErrorOffset)
            LD   (AtomParserErrorOffset),HL
            LD   A,AtomParserStatusExpression
            LD   (AtomParserErrorStatus),A
            SCF
            RET
.endif

; Look up the current one-to-three-character operand word.
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry
AtomParserLookupOperandWord:
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            CP   4
            JR   NC,_AtomParserUnknownOperand
            LD   DE,AtomParserNameKey
            CALL AtomRadix40Pack
            JR   C,_AtomParserUnknownOperand
            LD   DE,(AtomParserNameKey)
            LD   HL,AtomParserOperandWordTable
            LD   B,AtomParserOperandWordCount
_AtomParserLookupOperandLoop:
            LD   A,(HL)
            CP   E
            INC  HL
            JR   NZ,_AtomParserLookupOperandSkipHigh
            LD   A,(HL)
            CP   D
            JR   Z,_AtomParserLookupOperandFound
_AtomParserLookupOperandSkipHigh:
            INC  HL
            INC  HL
            DJNZ _AtomParserLookupOperandLoop
_AtomParserUnknownOperand:
            LD   A,AtomParserStatusUnknownOperand
            JP   AtomParserFailHere
_AtomParserLookupOperandFound:
            INC  HL
            LD   A,(HL)
            OR   A
            RET

; Parse a parenthesized register, absolute number, or IX/IY displacement.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomParserParseMemory:
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenNumber
.if AtomParserExpressionMode
            JR   Z,_AtomParserMemoryExpression
            CP   AtomTokenCurrent
            JR   Z,_AtomParserMemoryExpression
            CP   AtomTokenPlus
            JR   Z,_AtomParserMemoryExpression
            CP   AtomTokenMinus
            JR   Z,_AtomParserMemoryExpression
            CP   AtomTokenTilde
            JR   Z,_AtomParserMemoryExpression
            CP   AtomTokenLeftParen
            JR   Z,_AtomParserMemoryExpression
.else
            JR   Z,_AtomParserMemoryNumber
.endif
            CP   AtomTokenName
            JP   NZ,AtomParserExpectedOperand
            CALL AtomParserLookupOperandWord
.if AtomParserExpressionMode
            JR   C,_AtomParserMemoryExpression
.else
            RET  C
.endif
            LD   (AtomParserMemoryBase),A
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomParserMemoryBase)
            CP   AtomParserGenericC
            JR   Z,_AtomParserMemoryPortC
            CP   AtomOpBC
            JR   Z,_AtomParserMemoryBC
            CP   AtomOpDE
            JR   Z,_AtomParserMemoryDE
            CP   AtomOpHL
            JR   Z,_AtomParserMemoryHL
            CP   AtomOpSP
            JR   Z,_AtomParserMemorySP
            CP   AtomOpIX
            JR   Z,_AtomParserMemoryIX
            CP   AtomOpIY
            JR   Z,_AtomParserMemoryIY
            JP   AtomParserUnknownOperand

.if AtomParserExpressionMode
_AtomParserMemoryExpression:
            CALL AtomParserParseExpression
            RET  C
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomParserGenericParenNumber
            JP   AtomParserRequireRightParen
.else
_AtomParserMemoryNumber:
            CALL AtomParserStoreTokenValue
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomParserGenericParenNumber
            CALL AtomParserNextToken
            RET  C
            JP   AtomParserRequireRightParen
.endif

_AtomParserMemoryPortC:
            LD   A,AtomOpPortC
            JR   _AtomParserMemorySimple
_AtomParserMemoryBC:
            LD   A,AtomOpMemBC
            JR   _AtomParserMemorySimple
_AtomParserMemoryDE:
            LD   A,AtomOpMemDE
            JR   _AtomParserMemorySimple
_AtomParserMemoryHL:
            LD   A,AtomOpMemHL
            JR   _AtomParserMemorySimple
_AtomParserMemorySP:
            LD   A,AtomOpMemSP
_AtomParserMemorySimple:
            LD   HL,(AtomParserClassPointer)
            LD   (HL),A
            JP   AtomParserRequireRightParen

_AtomParserMemoryIX:
            LD   B,AtomOpMemIX
            LD   A,AtomOpIndexIX
            LD   (AtomParserIndexClass),A
            JR   _AtomParserMemoryIndex
_AtomParserMemoryIY:
            LD   B,AtomOpMemIY
            LD   A,AtomOpIndexIY
            LD   (AtomParserIndexClass),A
_AtomParserMemoryIndex:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenRightParen
            JR   Z,_AtomParserMemoryIndexPlain
            CP   AtomTokenPlus
.if AtomParserExpressionMode
            JR   Z,_AtomParserMemoryIndexExpression
            CP   AtomTokenMinus
            JP   NZ,AtomParserExpectedDelimiter
_AtomParserMemoryIndexExpression:
            CALL AtomParserParseExpression
            RET  C
            LD   HL,(AtomParserClassPointer)
            LD   A,(AtomParserIndexClass)
            LD   (HL),A
            JP   AtomParserRequireRightParen
.else
            JR   Z,_AtomParserMemoryIndexPositive
            CP   AtomTokenMinus
            JP   NZ,AtomParserExpectedDelimiter
            LD   A,$FF
            JR   _AtomParserMemoryIndexSign
_AtomParserMemoryIndexPositive:
            XOR  A
_AtomParserMemoryIndexSign:
            LD   (AtomParserDisplacementSign),A
            CALL AtomParserNextToken
            RET  C
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenNumber
            JP   NZ,AtomParserExpectedOperand
            LD   HL,(AtomTokenRecord+AtomTokenValueOffset)
            LD   A,H
            OR   A
            JP   NZ,AtomParserValueRange
            LD   A,(AtomParserDisplacementSign)
            OR   A
            JR   NZ,_AtomParserMemoryIndexNegative
            BIT  7,L
            JP   NZ,AtomParserValueRange
            JR   _AtomParserMemoryIndexValueReady
_AtomParserMemoryIndexNegative:
            LD   A,L
            CP   $81
            JP   NC,AtomParserValueRange
            OR   A
            JR   Z,_AtomParserMemoryIndexValueReady
            XOR  A
            SUB  L
            LD   L,A
            LD   H,$FF
_AtomParserMemoryIndexValueReady:
            LD   DE,(AtomParserValuePointer)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            LD   HL,(AtomParserClassPointer)
            LD   A,(AtomParserIndexClass)
            LD   (HL),A
            CALL AtomParserNextToken
            RET  C
            JP   AtomParserRequireRightParen
.endif
_AtomParserMemoryIndexPlain:
            LD   HL,(AtomParserClassPointer)
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMJp
            LD   A,B
            JR   Z,_AtomParserMemoryIndexPlainStore
            LD   A,(AtomParserIndexClass)
_AtomParserMemoryIndexPlainStore:
            LD   (HL),A
            JP   AtomParserNextToken

; Current token must be ')'; consume it on success.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomParserRequireRightParen:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenRightParen
            JP   NZ,AtomParserExpectedDelimiter
            JP   AtomParserNextToken

; Copy the current token's numeric word to the selected operand value.
.routine out carry,zero clobbers A,DE,HL,sign,parity,halfCarry
AtomParserStoreTokenValue:
            LD   HL,(AtomTokenRecord+AtomTokenValueOffset)
            LD   DE,(AtomParserValuePointer)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            RET

; The source spelling A,source is an alias for the one-operand accumulator ABI.
; ADD, ADC, and SBC still reject a genuinely unary source spelling.
.routine out A,carry clobbers sign,parity,halfCarry,HL,zero,BC,DE
AtomParserNormalizeAccumulatorAlias:
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   C,_AtomParserAccumulatorSuccess
            CP   AtomMCp+1
            JR   NC,_AtomParserAccumulatorSuccess
            LD   A,(AtomParserOperandCount)
            CP   1
            JR   NZ,_AtomParserMaybeAccumulatorAlias
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   Z,_AtomParserRequiredAccumulator
            CP   AtomMAdc
            JR   Z,_AtomParserRequiredAccumulator
            CP   AtomMSbc
            JR   Z,_AtomParserRequiredAccumulator
            JR   _AtomParserAccumulatorSuccess
_AtomParserRequiredAccumulator:
            LD   A,AtomParserStatusInvalidForm
            JP   AtomParserFailStart
_AtomParserMaybeAccumulatorAlias:
            CP   2
            JR   NZ,_AtomParserAccumulatorSuccess
            LD   A,(AtomParserScratch+AtomInstrOp0)
            CP   AtomOpA
            JR   NZ,_AtomParserAccumulatorSuccess
            LD   A,(AtomParserScratch+AtomInstrOp1)
            LD   (AtomParserScratch+AtomInstrOp0),A
            LD   HL,(AtomParserScratch+AtomInstrValue1)
            LD   (AtomParserScratch+AtomInstrValue0),HL
            LD   A,AtomOpNone
            LD   (AtomParserScratch+AtomInstrOp1),A
            XOR  A
            LD   (AtomParserScratch+AtomInstrValue1),A
            LD   (AtomParserScratch+AtomInstrValue1+1),A
            INC  A
            LD   (AtomParserOperandCount),A
.if AtomParserExpressionMode
            LD   A,(AtomParserUnresolvedMask)
            AND  2
            JR   Z,_AtomParserAccumulatorSuccess
            LD   A,1
            LD   (AtomParserUnresolvedMask),A
            CALL AtomParserRemapAliasReference
.endif
_AtomParserAccumulatorSuccess:
            XOR  A
            RET

.if AtomParserExpressionMode
.routine out carry,zero clobbers B,sign,parity,halfCarry,DE,HL,A
AtomParserRemapAliasReference:
            XOR  A
            LD   B,A
_AtomParserRemapAliasLoop:
            LD   A,(AtomParserReferenceBuildCount)
            CP   B
            RET  Z
            LD   A,B
            CALL AtomParserBuildReferenceAddress
            LD   HL,AtomParserBuildOperand
            ADD  HL,DE
            LD   A,(HL)
            CP   1
            JR   NZ,_AtomParserRemapAliasNext
            LD   (HL),0
_AtomParserRemapAliasNext:
            INC  B
            JR   _AtomParserRemapAliasLoop
.endif

; Convert generic numeric syntax to fixed encoder classes. Flexible immediates
; begin as imm8 and may be retried as imm16 if the form matrix rejects imm8.
.routine out A,carry clobbers BC,zero,sign,parity,halfCarry,DE,HL,IX,IY
AtomParserNormalizeNumbers:
            XOR  A
            LD   (AtomParserFlexibleMask),A
            LD   (AtomParserConditionMask),A
            LD   (AtomParserScanIndex),A
_AtomParserNormalizeLoop:
            LD   A,(AtomParserScanIndex)
            LD   B,A
            LD   A,(AtomParserOperandCount)
            CP   B
            RET  Z
            LD   A,B
            CALL AtomParserSelectOperand
            LD   HL,(AtomParserClassPointer)
            LD   A,(HL)
            CP   AtomParserGenericC
            JR   Z,_AtomParserNormalizeC
            CP   AtomParserGenericParenNumber
            JR   Z,_AtomParserNormalizeParenNumber
            CP   AtomParserGenericNumber
            JR   NZ,_AtomParserNormalizeNext
            CALL AtomParserNormalizeBareNumber
            RET  C
            JR   _AtomParserNormalizeNext

_AtomParserNormalizeC:
            LD   (HL),AtomOpC
            LD   A,(AtomParserScanIndex)
            CALL AtomParserIndexBit
            LD   HL,AtomParserConditionMask
            OR   (HL)
            LD   (HL),A
            JR   _AtomParserNormalizeNext

_AtomParserNormalizeParenNumber:
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMIn
            JR   Z,_AtomParserNormalizeParenByte
            CP   AtomMOut
            JR   Z,_AtomParserNormalizeParenByte
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpMemAbs
            JR   _AtomParserNormalizeNext
_AtomParserNormalizeParenByte:
            CALL AtomParserRequireByteValue
            RET  C
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpImm8

_AtomParserNormalizeNext:
            LD   HL,AtomParserScanIndex
            INC  (HL)
            JR   _AtomParserNormalizeLoop

; Normalize one bare numeric operand selected by AtomParserScanIndex.
.routine out A,carry clobbers HL,sign,parity,halfCarry,zero,BC,DE
AtomParserNormalizeBareNumber:
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMIm
            JR   Z,_AtomParserNormalizeIm
            CP   AtomMRst
            JR   Z,_AtomParserNormalizeRst
            CP   AtomMBit
            JR   C,_AtomParserNormalizeBranch
            CP   AtomMSet+1
            JR   C,_AtomParserNormalizeBit
_AtomParserNormalizeBranch:
            LD   A,(AtomParserScratch+AtomInstrMnemonic)
            CP   AtomMJp
            JR   Z,_AtomParserNormalizeWord
            CP   AtomMCall
            JR   Z,_AtomParserNormalizeWord
            CP   AtomMJr
            JR   Z,_AtomParserNormalizeRelative
            CP   AtomMDjnz
            JR   Z,_AtomParserNormalizeRelative
            CP   AtomMOut
            JR   NZ,_AtomParserNormalizeFlexible
            CALL AtomParserSelectedValue
            LD   A,H
            OR   L
            JR   NZ,_AtomParserNormalizeFlexible
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpZero
            XOR  A
            RET

_AtomParserNormalizeIm:
            CALL AtomParserSelectedValue
            LD   A,H
            OR   A
            JP   NZ,AtomParserValueRange
            LD   A,L
            CP   3
            JP   NC,AtomParserValueRange
            ADD  A,AtomOpIm0
            JR   _AtomParserStoreEnum
_AtomParserNormalizeRst:
            CALL AtomParserSelectedValue
            LD   A,H
            OR   A
            JP   NZ,AtomParserValueRange
            LD   A,L
            CP   57
            JP   NC,AtomParserValueRange
            AND  7
            JP   NZ,AtomParserValueRange
            LD   A,L
            RRCA
            RRCA
            RRCA
            AND  7
            ADD  A,AtomOpRst0
            JR   _AtomParserStoreEnum
_AtomParserNormalizeBit:
            LD   A,(AtomParserScanIndex)
            OR   A
            JR   NZ,_AtomParserNormalizeFlexible
            CALL AtomParserSelectedValue
            LD   A,H
            OR   A
            JP   NZ,AtomParserValueRange
            LD   A,L
            CP   8
            JP   NC,AtomParserValueRange
            ADD  A,AtomOpBit0
_AtomParserStoreEnum:
            LD   HL,(AtomParserClassPointer)
            LD   (HL),A
            CALL AtomParserClearSelectedValue
            XOR  A
            RET
_AtomParserNormalizeWord:
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpImm16
            XOR  A
            RET
_AtomParserNormalizeRelative:
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpRel8
            XOR  A
            RET
_AtomParserNormalizeFlexible:
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpImm8
            LD   A,(AtomParserScanIndex)
            CALL AtomParserIndexBit
            LD   HL,AtomParserFlexibleMask
            OR   (HL)
            LD   (HL),A
            XOR  A
            RET

; Return selected value in HL.
.routine out HL clobbers A
AtomParserSelectedValue:
            LD   HL,(AtomParserValuePointer)
            LD   A,(HL)
            INC  HL
            LD   H,(HL)
            LD   L,A
            RET

.routine out carry,zero clobbers A,HL,sign,parity,halfCarry
AtomParserClearSelectedValue:
            LD   HL,(AtomParserValuePointer)
            XOR  A
            LD   (HL),A
            INC  HL
            LD   (HL),A
            RET

; Carry set if selected value exceeds one byte.
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry,BC,DE,IX,IY
AtomParserRequireByteValue:
            CALL AtomParserSelectedValue
            LD   A,H
            OR   A
            RET  Z
            JP   AtomParserValueRange

; A=operand index, out A=1<<index.
.routine in A out A,carry clobbers zero,sign,parity,halfCarry
AtomParserIndexBit:
            OR   A
            JR   Z,_AtomParserIndexBitReady
            DEC  A
            JR   Z,_AtomParserIndexBitOne
            LD   A,4
            RET
_AtomParserIndexBitOne:
            LD   A,2
            RET
_AtomParserIndexBitReady:
            INC  A
            RET

; Try the current classes, each C-as-condition alternative, then flexible
; immediates widened to imm16 with the same condition alternatives.
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry
AtomParserValidateCandidates:
            CALL AtomParserValidateCurrent
            RET  NC
            CALL AtomParserTryConditions
            RET  NC
            LD   A,(AtomParserFlexibleMask)
            OR   A
            JR   Z,_AtomParserInvalidForm
            CALL AtomParserWidenFlexible
            CALL AtomParserValidateCurrent
            RET  NC
            CALL AtomParserTryConditions
            RET  NC
_AtomParserInvalidForm:
            LD   A,AtomParserStatusInvalidForm
            JP   AtomParserFailStart

.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry
AtomParserValidateCurrent:
            LD   IX,AtomParserScratch
            JP   AtomValidateForm

; Try each ambiguous C operand as condition code C. No valid Z80 form contains
; two condition operands, so individual trials cover the complete ambiguity.
.routine out A,carry clobbers BC,DE,IX,zero,sign,parity,halfCarry,HL
AtomParserTryConditions:
            XOR  A
            LD   (AtomParserScanIndex),A
_AtomParserTryConditionLoop:
            LD   A,(AtomParserScanIndex)
            CP   3
            JR   Z,_AtomParserTryConditionFailed
            LD   B,A
            CALL AtomParserIndexBit
            LD   HL,AtomParserConditionMask
            AND  (HL)
            JR   Z,_AtomParserTryConditionNext
            LD   A,B
            CALL AtomParserSelectOperand
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpCC
            PUSH HL
            CALL AtomParserValidateCurrent
            POP  HL
            RET  NC
            LD   (HL),AtomOpC
_AtomParserTryConditionNext:
            LD   HL,AtomParserScanIndex
            INC  (HL)
            JR   _AtomParserTryConditionLoop
_AtomParserTryConditionFailed:
            SCF
            RET

.routine out carry,zero clobbers sign,parity,halfCarry,B,DE,HL,A
AtomParserWidenFlexible:
            XOR  A
            LD   (AtomParserScanIndex),A
_AtomParserWidenLoop:
            LD   A,(AtomParserScanIndex)
            CP   3
            RET  Z
            LD   B,A
            CALL AtomParserIndexBit
            LD   HL,AtomParserFlexibleMask
            AND  (HL)
            JR   Z,_AtomParserWidenNext
            LD   A,B
            CALL AtomParserSelectOperand
            LD   HL,(AtomParserClassPointer)
            LD   (HL),AtomOpImm16
_AtomParserWidenNext:
            LD   HL,AtomParserScanIndex
            INC  (HL)
            JR   _AtomParserWidenLoop

; Enforce concrete byte widths and convert absolute JR/DJNZ targets to signed
; displacements from address+encodedLength.
.routine out A,carry clobbers BC,zero,sign,parity,halfCarry,DE,HL,IX,IY
AtomParserCheckConcreteValues:
            XOR  A
            LD   (AtomParserScanIndex),A
_AtomParserCheckValueLoop:
            LD   A,(AtomParserScanIndex)
            LD   B,A
            LD   A,(AtomParserOperandCount)
            CP   B
            RET  Z
            LD   A,B
            CALL AtomParserSelectOperand
.if AtomParserExpressionMode
            LD   A,(AtomParserScanIndex)
            CALL AtomParserIndexBit
            LD   HL,AtomParserUnresolvedMask
            AND  (HL)
            JR   NZ,_AtomParserCheckValueNext
.endif
            LD   HL,(AtomParserClassPointer)
            LD   A,(HL)
            CP   AtomOpImm8
            JR   Z,_AtomParserCheckByte
            CP   AtomOpRel8
            JR   Z,_AtomParserCheckRelative
.if AtomParserExpressionMode
            CP   AtomOpIndexIX
            JR   Z,_AtomParserCheckDisplacement
            CP   AtomOpIndexIY
            JR   Z,_AtomParserCheckDisplacement
.endif
_AtomParserCheckValueNext:
            LD   HL,AtomParserScanIndex
            INC  (HL)
            JR   _AtomParserCheckValueLoop
_AtomParserCheckByte:
            CALL AtomParserRequireByteValue
            RET  C
            JR   _AtomParserCheckValueNext
.if AtomParserExpressionMode
_AtomParserCheckDisplacement:
            CALL AtomParserSelectedValue
            LD   A,H
            OR   A
            JR   Z,_AtomParserCheckDisplacementPositive
            INC  A
            JP   NZ,AtomParserValueRange
            BIT  7,L
            JP   Z,AtomParserValueRange
            JR   _AtomParserCheckValueNext
_AtomParserCheckDisplacementPositive:
            BIT  7,L
            JP   NZ,AtomParserValueRange
            JR   _AtomParserCheckValueNext
.endif
_AtomParserCheckRelative:
            CALL AtomParserSelectedValue
            LD   DE,(AtomParserInstructionAddress)
            LD   A,(AtomParserInstructionLength)
            ADD  A,E
            LD   E,A
            JR   NC,_AtomParserRelativeBaseReady
            INC  D
_AtomParserRelativeBaseReady:
            OR   A
            SBC  HL,DE
            LD   A,H
            OR   A
            JR   Z,_AtomParserRelativePositive
            INC  A
            JP   NZ,AtomParserRelativeRange
            BIT  7,L
            JP   Z,AtomParserRelativeRange
            JR   _AtomParserRelativeStore
_AtomParserRelativePositive:
            BIT  7,L
            JP   NZ,AtomParserRelativeRange
_AtomParserRelativeStore:
            LD   DE,(AtomParserValuePointer)
            LD   A,L
            LD   (DE),A
            INC  DE
            LD   A,H
            LD   (DE),A
            JR   _AtomParserCheckValueNext

.if AtomParserExpressionMode
; Convert each private unresolved operand into stable public metadata, then
; publish all referenced symbol records after one exact shared-arena preflight.
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry,IY
AtomParserFinalizeReferences:
            XOR  A
            LD   (AtomParserReferenceScan),A
_AtomParserLocateReferenceLoop:
            LD   A,(AtomParserReferenceBuildCount)
            LD   B,A
            LD   A,(AtomParserReferenceScan)
            CP   B
            JR   Z,_AtomParserPreflightReferences
            CALL AtomParserBuildReferenceAddress
            LD   HL,AtomParserBuildOperand
            ADD  HL,DE
            LD   A,(HL)
            LD   IX,AtomParserScratch
            CALL AtomPatchLocate
            JR   C,_AtomParserUnpatchableReference
            LD   (AtomParserReferenceKindScratch),A
            LD   A,B
            LD   (AtomParserReferenceOffsetScratch),A
            LD   A,(AtomParserReferenceScan)
            CALL AtomParserBuildReferenceAddress
            LD   HL,AtomParserBuildKind
            ADD  HL,DE
            LD   A,(AtomParserReferenceKindScratch)
            LD   (HL),A
            INC  HL
            LD   A,(AtomParserReferenceOffsetScratch)
            LD   (HL),A
            LD   HL,AtomParserReferenceScan
            INC  (HL)
            JR   _AtomParserLocateReferenceLoop

_AtomParserUnpatchableReference:
            LD   A,AtomParserStatusUnpatchable
            JP   AtomParserFailReference

_AtomParserPreflightReferences:
            XOR  A
            LD   (AtomParserReferenceMissingCount),A
            LD   (AtomParserReferenceSameKey),A
            LD   A,(AtomParserReferenceBuildCount)
            OR   A
            RET  Z
            CP   2
            JR   NZ,_AtomParserPreflightFirst
            CALL AtomParserCompareReferenceKeys
            LD   A,0
            ADC  A,0
            XOR  1
            LD   (AtomParserReferenceSameKey),A
_AtomParserPreflightFirst:
            XOR  A
            LD   (AtomParserReferenceScan),A
            CALL AtomParserPreflightReference
            RET  C
            LD   A,(AtomParserReferenceBuildCount)
            CP   2
            JR   NZ,_AtomParserPreflightCapacity
            LD   A,(AtomParserReferenceSameKey)
            OR   A
            JR   NZ,_AtomParserPreflightCapacity
            LD   A,1
            LD   (AtomParserReferenceScan),A
            CALL AtomParserPreflightReference
            RET  C
_AtomParserPreflightCapacity:
            LD   A,(AtomParserReferenceMissingCount)
            OR   A
            JR   Z,_AtomParserPublishReferences
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   HL,(AtomSymbolLocalBegin)
            LD   DE,(AtomSymbolGlobalEnd)
            OR   A
            SBC  HL,DE
            JR   C,AtomParserSymbolCapacityFailure
            LD   A,H
            OR   A
            JR   NZ,_AtomParserPublishReferences
            LD   A,L
            CP   B
            JR   C,AtomParserSymbolCapacityFailure

_AtomParserPublishReferences:
            XOR  A
            LD   (AtomParserReferenceScan),A
_AtomParserPublishReferenceLoop:
            LD   A,(AtomParserReferenceBuildCount)
            LD   B,A
            LD   A,(AtomParserReferenceScan)
            CP   B
            JR   Z,_AtomParserPublishReferenceCount
            CALL AtomParserBuildReferenceAddress
            LD   H,D
            LD   L,E
            CALL AtomSymbolReference
            JR   C,AtomParserUnexpectedSymbolFailure
            PUSH IX
            POP  BC
            LD   A,(AtomParserReferenceScan)
            CALL AtomParserPublicReferenceAddress
            LD   (HL),C
            INC  HL
            LD   (HL),B
            INC  HL
            PUSH HL
            LD   A,(AtomParserReferenceScan)
            CALL AtomParserBuildReferenceAddress
            LD   HL,AtomParserBuildAddend
            ADD  HL,DE
            POP  DE
            LD   BC,7
            LDIR
            LD   HL,AtomParserReferenceScan
            INC  (HL)
            JR   _AtomParserPublishReferenceLoop
_AtomParserPublishReferenceCount:
            LD   A,(AtomParserReferenceBuildCount)
            LD   (AtomParserReferenceCount),A
            XOR  A
            RET

; Preflight the key selected by AtomParserReferenceScan.
.routine out A,carry clobbers BC,DE,HL,IX,zero,sign,parity,halfCarry,IY
AtomParserPreflightReference:
            LD   A,(AtomParserReferenceScan)
            CALL AtomParserBuildReferenceAddress
            LD   H,D
            LD   L,E
            CALL AtomSymbolFind
            RET  NC
            CP   AtomStatusNotFound
            JR   NZ,_AtomParserPreflightSymbolFailure
            LD   HL,AtomParserReferenceMissingCount
            INC  (HL)
            XOR  A
            RET
_AtomParserPreflightSymbolFailure:
            LD   (AtomParserSymbolStatus),A
            LD   A,AtomParserStatusSymbol
            JP   AtomParserFailReference

; Carry clear when the two build keys are equal, carry set otherwise.
.routine out A,carry clobbers DE,HL,zero,sign,parity,halfCarry,B
AtomParserCompareReferenceKeys:
            LD   HL,AtomParserReferenceBuild
            LD   DE,AtomParserReferenceBuild+AtomParserBuildReferenceBytes
            LD   B,6
_AtomParserCompareReferenceKeyLoop:
            LD   A,(DE)
            CP   (HL)
            SCF
            RET  NZ
            INC  DE
            INC  HL
            DJNZ _AtomParserCompareReferenceKeyLoop
            OR   A
            RET

AtomParserSymbolCapacityFailure:
            LD   A,AtomStatusSymbolCapacity
            LD   (AtomParserSymbolStatus),A
            LD   A,AtomParserStatusSymbol
            JP   AtomParserFailReference
AtomParserUnexpectedSymbolFailure:
            LD   (AtomParserSymbolStatus),A
            LD   A,AtomParserStatusInternal
            JP   AtomParserFailReference

; A=public-reference index 0..1, out HL=entry address.
.routine in A out HL clobbers DE,A,F
AtomParserPublicReferenceAddress:
            LD   HL,AtomParserReferences
            OR   A
            RET  Z
            LD   DE,AtomParserPublicReferenceBytes
            ADD  HL,DE
            RET

; Queue every published reference after proving the complete pending capacity.
;
; in DE=logical instruction output address
; out A=Atom status, carry clear on success; carry set on failure
.routine in DE out A,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IX
AtomParserQueueReferences:
            LD   (AtomParserQueueBase),DE
            LD   A,(AtomParserReferenceCount)
            LD   B,A
            ADD  A,A
            ADD  A,B
            ADD  A,A
            LD   B,A
            LD   HL,(AtomPendingArenaEnd)
            LD   DE,(AtomPendingNext)
            OR   A
            SBC  HL,DE
            JR   C,_AtomParserQueueCapacity
            LD   A,H
            OR   A
            JR   NZ,_AtomParserQueueCheckSymbols
            LD   A,L
            CP   B
            JR   C,_AtomParserQueueCapacity
_AtomParserQueueCheckSymbols:
            XOR  A
            LD   (AtomParserReferenceScan),A
_AtomParserQueueCheckLoop:
            LD   A,(AtomParserReferenceCount)
            LD   B,A
            LD   A,(AtomParserReferenceScan)
            CP   B
            JR   Z,_AtomParserQueueCommit
            CALL AtomParserPublicReferenceAddress
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            LD   DE,5
            ADD  HL,DE
            BIT  6,(HL)
            JR   NZ,_AtomParserQueueAlreadyDefined
            LD   HL,AtomParserReferenceScan
            INC  (HL)
            JR   _AtomParserQueueCheckLoop
_AtomParserQueueCommit:
            XOR  A
            LD   (AtomParserReferenceScan),A
_AtomParserQueueLoop:
            LD   A,(AtomParserReferenceCount)
            LD   B,A
            LD   A,(AtomParserReferenceScan)
            CP   B
            JR   Z,_AtomParserQueueDone
            CALL AtomParserPublicReferenceAddress
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            PUSH DE
            POP  IX
            INC  HL
            LD   C,(HL)
            INC  HL
            INC  HL
            LD   B,(HL)
            INC  HL
            LD   A,(HL)
            LD   HL,(AtomParserQueueBase)
            LD   E,A
            LD   D,0
            ADD  HL,DE
            EX   DE,HL
            CALL AtomPendingAdd
            RET  C
            LD   HL,AtomParserReferenceScan
            INC  (HL)
            JR   _AtomParserQueueLoop
_AtomParserQueueDone:
            XOR  A
            RET
_AtomParserQueueCapacity:
            LD   A,AtomStatusPendingCapacity
            SCF
            RET
_AtomParserQueueAlreadyDefined:
            LD   A,AtomStatusAlreadyDefined
            SCF
            RET

AtomParserFailExpressionSymbol:
            LD   (AtomParserErrorStatus),A
            LD   A,(AtomExpressionSymbolPart)
            LD   (AtomParserErrorPart),A
            LD   HL,(AtomExpressionSymbolOffset)
            LD   (AtomParserErrorOffset),HL
            LD   A,(AtomParserErrorStatus)
            SCF
            RET

; A=parser status; source position comes from AtomParserReferenceScan.
AtomParserFailReference:
            LD   (AtomParserErrorStatus),A
            LD   A,(AtomParserReferenceScan)
            CALL AtomParserBuildReferenceAddress
            LD   HL,AtomParserBuildPart
            ADD  HL,DE
            LD   A,(HL)
            LD   (AtomParserErrorPart),A
            INC  HL
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            LD   (AtomParserErrorOffset),DE
            LD   A,(AtomParserErrorStatus)
            SCF
            RET
.endif

; Commit exactly ten bytes after every check succeeds.
.routine out A,IX,carry clobbers BC,DE,HL,sign,parity,halfCarry,zero
AtomParserCommit:
            LD   HL,AtomParserScratch
            LD   DE,(AtomParserDestination)
            LD   BC,10
            LDIR
            LD   IX,(AtomParserDestination)
            XOR  A
            RET

AtomParserExpectedMnemonic:
            LD   A,AtomParserStatusExpectedMnemonic
            JP   AtomParserFailHere
AtomParserUnknownMnemonic:
            LD   A,AtomParserStatusUnknownMnemonic
            JP   AtomParserFailHere
AtomParserExpectedOperand:
            LD   A,AtomParserStatusExpectedOperand
            JP   AtomParserFailHere
AtomParserUnknownOperand:
            LD   A,AtomParserStatusUnknownOperand
            JP   AtomParserFailHere
AtomParserExpectedDelimiter:
            LD   A,AtomParserStatusExpectedDelimiter
            JP   AtomParserFailHere
AtomParserTooManyOperands:
            LD   A,AtomParserStatusTooManyOperands
            JP   AtomParserFailHere
AtomParserValueRange:
            LD   A,AtomParserStatusValueRange
            JP   AtomParserFailHere
AtomParserRelativeRange:
            LD   A,AtomParserStatusRelativeRange
            JP   AtomParserFailStart

; Record an error at the current token.
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomParserFailHere:
            LD   (AtomParserErrorStatus),A
            LD   A,(AtomTokenRecord+AtomTokenPartOffset)
            LD   (AtomParserErrorPart),A
            LD   HL,(AtomTokenRecord+AtomTokenSourceOffset)
            LD   (AtomParserErrorOffset),HL
            LD   A,(AtomParserErrorStatus)
            SCF
            RET

; Record a whole-form error at the mnemonic.
.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomParserFailStart:
            LD   (AtomParserErrorStatus),A
            LD   A,(AtomParserInstructionPart)
            LD   (AtomParserErrorPart),A
            LD   HL,(AtomParserInstructionOffset)
            LD   (AtomParserErrorOffset),HL
            LD   A,(AtomParserErrorStatus)
            SCF
            RET

AtomParserRuleCodeEnd:
AtomParserImmutableStart:
            .include "atom-operands.inc"
AtomParserImmutableEnd:
AtomParserCodeEnd:

AtomParserWorkspaceStart:
AtomParserDestination:        .dw 0
AtomParserInstructionAddress: .dw 0
AtomParserInstructionPart:    .db 0
AtomParserInstructionOffset:  .dw 0
AtomParserInstructionLength:  .db 0
AtomParserOperandCount:       .db 0
AtomParserScanIndex:          .db 0
AtomParserFlexibleMask:       .db 0
AtomParserConditionMask:      .db 0
AtomParserClassPointer:       .dw 0
AtomParserValuePointer:       .dw 0
AtomParserLastClass:          .db 0
AtomParserMemoryBase:         .db 0
AtomParserIndexClass:         .db 0
AtomParserDisplacementSign:   .db 0
AtomParserNameKey:            .ds 6
AtomParserErrorStatus:        .db 0
AtomParserErrorPart:          .db 0
AtomParserErrorOffset:        .dw 0
AtomParserScratch:            .ds 10
.if AtomParserExpressionMode
AtomParserExpressionStatus:   .db 0
AtomParserSymbolStatus:       .db 0
AtomParserReferenceCount:     .db 0
AtomParserReferenceBuildCount:.db 0
AtomParserUnresolvedMask:     .db 0
AtomParserReferenceScan:      .db 0
AtomParserReferenceMissingCount:.db 0
AtomParserReferenceSameKey:   .db 0
AtomParserReferenceKindScratch:.db 0
AtomParserReferenceOffsetScratch:.db 0
AtomParserReferenceAddendScratch:.dw 0
AtomParserQueueBase:          .dw 0
AtomParserReferenceBuild:     .ds AtomParserBuildReferenceBytes*AtomParserReferenceCapacity
AtomParserReferences:         .ds AtomParserPublicReferenceBytes*AtomParserReferenceCapacity
.endif
AtomParserWorkspaceEnd:
