; atom Phase 2g streaming statement dispatcher.
;
; The host installs one source part with AtomTokenizerReset. This module then
; connects tokenization, symbols, instruction parsing, and logical output. It
; owns no source or symbol arena and performs no filesystem work.

AtomStatementCodeStart:

AtomStatementStatusOk:          .equ 0
AtomStatementStatusLexical:     .equ 1
AtomStatementStatusExpected:    .equ 2
AtomStatementStatusDirective:   .equ 3
AtomStatementStatusEquate:      .equ 4
AtomStatementStatusSymbol:      .equ 5
AtomStatementStatusInstruction: .equ 6
AtomStatementStatusOutput:      .equ 7
AtomStatementStatusUndefined:   .equ 8
AtomStatementStatusInternal:    .equ 9

AtomDirectiveEqu: .equ 1
AtomDirectiveOrg: .equ 2
AtomDirectiveDb:  .equ 3
AtomDirectiveDw:  .equ 4
AtomDirectiveDs:  .equ 5
AtomDirectiveCstr:.equ 6
AtomDirectivePstr:.equ 7
AtomDirectiveIstr:.equ 8
AtomDirectiveAlign:.equ 9
AtomDirectiveCount:.equ 9

; Assemble the source part already installed in the tokenizer. Part EOF is not
; final assembly EOF: a later source part may still define a global reference.
;
; out A=AtomStatementStatusOk and carry clear; otherwise category and carry set
.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomAssemblePart:
AtomStatementNext:
            CALL AtomStatementNextTokenKind
            JP   C,AtomStatementLexicalFailure
            CP   AtomTokenEof
            JP   Z,AtomStatementSuccess
            CP   AtomTokenEol
            JR   Z,AtomStatementNext
            CP   AtomTokenName
            JP   NZ,AtomStatementExpectedHere

            CALL AtomStatementCapturePosition
            CALL AtomTokenLoadLexeme
            LD   DE,AtomStatementKey
            CALL AtomPackSymbol
            JP   C,AtomStatementSymbolFailure

            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeMnemonic
            JR   C,AtomStatementNotMnemonic
            LD   (AtomStatementMnemonic),A
            LD   A,1
            LD   (AtomStatementMnemonicValid),A
            XOR  A
            LD   (AtomStatementDirectiveValid),A
            JR   AtomStatementAfterFirstName
AtomStatementNotMnemonic:
            XOR  A
            LD   (AtomStatementMnemonicValid),A
            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeDirective
            JR   C,AtomStatementNotDirective
            LD   (AtomStatementDirective),A
            LD   A,1
            LD   (AtomStatementDirectiveValid),A
            JR   AtomStatementAfterFirstName
AtomStatementNotDirective:
            XOR  A
            LD   (AtomStatementDirectiveValid),A

AtomStatementAfterFirstName:
            CALL AtomStatementNextTokenKind
            JP   C,AtomStatementLexicalFailure
            CP   AtomTokenColon
            JR   Z,AtomStatementLabel
            LD   A,(AtomStatementMnemonicValid)
            OR   A
            JP   NZ,AtomStatementInstructionPublished
            LD   A,(AtomStatementDirectiveValid)
            OR   A
            JR   Z,AtomStatementTryEquate
            LD   A,(AtomStatementDirective)
            JP   AtomStatementDirectivePublished
AtomStatementTryEquate:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenName
            JP   NZ,AtomStatementExpectedSaved
            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeDirective
            JP   C,AtomStatementExpectedSaved
            CP   AtomDirectiveEqu
            JP   NZ,AtomStatementExpectedSaved
            JP   AtomStatementEquate

AtomStatementLabel:
            CALL AtomStatementNextTokenKind
            JP   C,AtomStatementLexicalFailure
            CP   AtomTokenName
            JR   NZ,AtomStatementLabelPublish
            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeDirective
            JR   C,AtomStatementLabelPublish
            CP   AtomDirectiveEqu
            JR   Z,AtomStatementEquate
AtomStatementLabelPublish:
            LD   HL,AtomStatementKey+5
            BIT  7,(HL)
            LD   HL,AtomStatementKey
            LD   DE,(AtomOutputCursor)
            JR   NZ,AtomStatementPrivateLabel
            CALL AtomSymbolDeclareGlobalLabel
            JR   AtomStatementLabelDeclared
AtomStatementPrivateLabel:
            CALL AtomSymbolDeclare
AtomStatementLabelDeclared:
            JP   C,AtomStatementSymbolFailure
            CALL AtomOutputResolveSymbol
            JP   C,AtomStatementOutputFailure

            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   Z,AtomStatementNext
            CP   AtomTokenName
            JP   NZ,AtomStatementExpectedHere
            CALL AtomStatementCapturePosition
            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeMnemonic
            JR   C,AtomStatementLabelDirective
            LD   (AtomStatementMnemonic),A
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            JR   AtomStatementInstructionPublished
AtomStatementLabelDirective:
            CALL AtomTokenLoadLexeme
            CALL AtomRecognizeDirective
            JP   C,AtomStatementExpectedSaved
            LD   (AtomStatementDirective),A
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomStatementDirective)
            JR   AtomStatementDirectivePublished

AtomStatementInstructionPublished:
            LD   A,(AtomStatementMnemonic)
            LD   BC,(AtomOutputCursor)
            LD   DE,AtomStatementInstruction
            CALL AtomParserParsePublished
            JP   C,AtomStatementInstructionFailure
            CALL AtomOutputEmitInstruction
AtomStatementOutputThenNext:
            JP   C,AtomStatementOutputFailure
            JP   AtomStatementNext

AtomStatementEquate:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            CALL AtomStatementParseExpression
            JP   C,AtomStatementEquateFailure
            OR   A
            JP   NZ,AtomStatementEquateUnresolved
            LD   (AtomStatementEquateValue),HL
            XOR  A
            LD   HL,AtomExpressionResultValue+2
            CP   (HL)
            JR   Z,AtomStatementEquateSignReady
            INC  A
AtomStatementEquateSignReady:
            LD   (AtomStatementEquateSigned),A
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementEquateDelimiter
            LD   HL,AtomStatementKey
            LD   DE,(AtomStatementEquateValue)
            CALL AtomSymbolDeclare
            JP   C,AtomStatementSymbolFailure
            LD   A,(AtomStatementEquateSigned)
            OR   A
            JR   Z,AtomStatementEquateResolve
            SET  5,(IX+5)
AtomStatementEquateResolve:
            CALL AtomOutputResolveSymbol
            JP   AtomStatementOutputThenNext

AtomStatementDirectivePublished:
            SUB  AtomDirectiveOrg
            CP   8
            JP   NC,AtomStatementExpectedSaved
            ADD  A,A
            LD   L,A
            LD   H,0
            LD   DE,AtomStatementDirectiveDispatchTable
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            JP   (HL)

AtomStatementDirectiveDispatchTable:
            .dw AtomStatementOrg,AtomStatementDb,AtomStatementDw,AtomStatementDs
            .dw AtomStatementCstr,AtomStatementPstr,AtomStatementIstr
            .dw AtomStatementAlign

AtomStatementOrg:
            CALL AtomStatementParseExpression
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JP   NZ,AtomStatementDirectiveUnresolved
            LD   (AtomStatementDataValue),HL
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementDirectiveDelimiter
            LD   HL,(AtomStatementDataValue)
            CALL AtomOutputSetOrigin
            JP   AtomStatementOutputThenNext

AtomStatementDb:
            LD   A,1
            LD   (AtomStatementDataWidth),A
            LD   A,AtomPatchKindTruncateByte
            LD   (AtomStatementDataPatchKind),A
            JR   AtomStatementDataItem
AtomStatementDw:
            LD   A,2
            LD   (AtomStatementDataWidth),A
            LD   A,AtomPatchKindWord
            LD   (AtomStatementDataPatchKind),A
AtomStatementDataItem:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   Z,AtomStatementDirectiveExpected
            CP   AtomTokenString
            JR   NZ,AtomStatementDataExpression
            LD   A,(AtomStatementDataWidth)
            CP   1
            JP   NZ,AtomStatementDirectiveString
            XOR  A
            LD   (AtomStatementStringMode),A
            JP   AtomStatementDbString
AtomStatementDataExpression:
            CALL AtomStatementParseExpression
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JR   NZ,AtomStatementDataUnresolved
            LD   A,(AtomStatementDataWidth)
            CP   1
            JR   Z,AtomStatementDataResolvedByte
            CALL AtomOutputEmitWord
            JP   C,AtomStatementOutputFailure
.if AtomDriverMode
            JP   AtomStatementDataDelimiter
.else
            JP   AtomStatementDataDelimiter
.endif
AtomStatementDataResolvedByte:
            LD   A,L
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
.if AtomDriverMode
            JP   AtomStatementDataDelimiter
.else
            JR   AtomStatementDataDelimiter
.endif

AtomStatementDataUnresolved:
            LD   A,L
            LD   (AtomStatementDataAddend),A
            PUSH IX
            POP  HL
            LD   (AtomStatementDataKey),HL
            LD   A,(AtomStatementDataWidth)
            LD   L,A
            LD   H,0
            CALL AtomOutputCheckCapacity
            JP   C,AtomStatementOutputFailure
            CALL AtomPendingCheckCapacity
            JP   C,AtomStatementSymbolFailure
            LD   A,(AtomExpressionResultUnresolved)
            CP   AtomExpressionForwardLow
            JR   Z,AtomStatementDataPendingLow
            CP   AtomExpressionForwardHigh
            JR   Z,AtomStatementDataPendingHigh
            LD   A,(AtomStatementDataPatchKind)
            JR   AtomStatementDataPendingKindReady
AtomStatementDataPendingLow:
            LD   A,AtomPatchKindLowByte
            JR   AtomStatementDataPendingKindReady
AtomStatementDataPendingHigh:
            LD   A,AtomPatchKindHighByte
AtomStatementDataPendingKindReady:
            LD   (AtomStatementDataPendingKind),A
.if AtomDriverMode
            LD   A,(AtomExpressionSymbolPart)
            CP   16
            JP   NC,AtomStatementSymbolPartFailure
.endif
            LD   HL,(AtomStatementDataKey)
            CALL AtomSymbolReference
            JP   C,AtomStatementSymbolFailure
.if AtomDriverMode
            LD   A,B
            OR   A
            JR   Z,AtomStatementDataDiagnosticReady
            LD   HL,(AtomExpressionSymbolOffset)
            LD   (IX+AtomSymbolValueLow),L
            LD   (IX+AtomSymbolValueHigh),H
            LD   A,(AtomExpressionSymbolPart)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            OR   AtomPendingDiagnosticAnchor
            LD   HL,AtomStatementDataPendingKind
            OR   (HL)
            LD   (HL),A
AtomStatementDataDiagnosticReady:
.endif
            PUSH IX
            POP  HL
            LD   (AtomStatementDataSymbol),HL
            LD   HL,(AtomOutputCursor)
            LD   (AtomStatementDataAddress),HL
            LD   A,(AtomStatementDataWidth)
            CP   1
            JR   Z,AtomStatementDataPlaceholderByte
            LD   HL,0
            CALL AtomOutputEmitWord
            JP   C,AtomStatementOutputFailure
            JR   AtomStatementDataQueue
AtomStatementDataPlaceholderByte:
            XOR  A
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
AtomStatementDataQueue:
            LD   IX,(AtomStatementDataSymbol)
            LD   DE,(AtomStatementDataAddress)
            LD   A,(AtomStatementDataPendingKind)
            LD   B,A
            LD   A,(AtomStatementDataAddend)
            LD   C,A
            CALL AtomPendingAdd
            JP   C,AtomStatementSymbolFailure

AtomStatementDataDelimiter:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   Z,AtomStatementNext
            CP   AtomTokenComma
            JP   NZ,AtomStatementDirectiveDelimiter
            CALL AtomStatementNextTokenKind
            JP   C,AtomStatementLexicalFailure
            CP   AtomTokenEol
            JP   Z,AtomStatementDirectiveExpected
            JP   AtomStatementDataItem

AtomStatementDbString:
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            INC  HL
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            SUB  2
            LD   B,A
            LD   C,0
AtomStatementStringCountLoop:
            LD   A,B
            OR   A
            JR   Z,AtomStatementStringCountDone
            LD   A,(HL)
            INC  HL
            DEC  B
            CP   "\\"
            JR   NZ,AtomStatementStringCountOne
            LD   A,(HL)
            INC  HL
            DEC  B
            CP   "x"
            JR   NZ,AtomStatementStringCountOne
            INC  HL
            INC  HL
            DEC  B
            DEC  B
AtomStatementStringCountOne:
            INC  C
            JR   AtomStatementStringCountLoop
AtomStatementStringCountDone:
            LD   A,C
            LD   (AtomStatementStringCount),A
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            INC  HL
            LD   (AtomStatementStringPointer),HL
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            SUB  2
            LD   (AtomStatementStringRemaining),A
            LD   A,(AtomStatementStringMode)
            OR   A
            JR   Z,AtomStatementStringCapacity
            CALL AtomStatementNextTokenKind
            JP   C,AtomStatementLexicalFailure
            CP   AtomTokenEol
            JP   NZ,AtomStatementDirectiveDelimiter
AtomStatementStringCapacity:
            LD   A,(AtomStatementStringCount)
            LD   L,A
            LD   H,0
            LD   A,(AtomStatementStringMode)
            CP   1
            JR   Z,AtomStatementStringCapacityExtra
            CP   2
            JR   NZ,AtomStatementStringCapacityReady
AtomStatementStringCapacityExtra:
            INC  HL
AtomStatementStringCapacityReady:
            CALL AtomOutputCheckCapacity
            JP   C,AtomStatementOutputFailure
            LD   A,(AtomStatementStringMode)
            CP   2
            JR   NZ,AtomStatementStringEmitLoop
            LD   A,(AtomStatementStringCount)
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
AtomStatementStringEmitLoop:
            LD   A,(AtomStatementStringRemaining)
            OR   A
            JR   Z,AtomStatementStringDone
            CALL AtomStatementStringTake
            CP   "\\"
            JR   NZ,AtomStatementStringEmit
            CALL AtomStatementStringTake
            CP   "x"
            JR   Z,AtomStatementStringHex
            CALL AtomTokenDecodeEscape
            JP   C,AtomStatementDirectiveString
            JR   AtomStatementStringEmit
AtomStatementStringHex:
            CALL AtomStatementStringTake
            CALL AtomTokenHexDigit
            JP   NC,AtomStatementDirectiveString
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   (AtomStatementStringNibble),A
            CALL AtomStatementStringTake
            CALL AtomTokenHexDigit
            JP   NC,AtomStatementDirectiveString
            LD   HL,AtomStatementStringNibble
            OR   (HL)
AtomStatementStringEmit:
            LD   C,A
            LD   A,(AtomStatementStringMode)
            CP   3
            LD   A,C
            JR   NZ,AtomStatementStringEmitReady
            LD   HL,AtomStatementStringRemaining
            LD   A,(HL)
            OR   A
            LD   A,C
            JR   NZ,AtomStatementStringEmitReady
            OR   $80
AtomStatementStringEmitReady:
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
            JR   AtomStatementStringEmitLoop
AtomStatementStringDone:
            LD   A,(AtomStatementStringMode)
            OR   A
            JR   Z,AtomStatementStringDbDone
            CP   1
            JP   NZ,AtomStatementNext
            XOR  A
            CALL AtomOutputEmitByte
            JP   AtomStatementOutputThenNext
AtomStatementStringDbDone:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            JP   AtomStatementDataDelimiter

AtomStatementCstr:
            LD   A,1
            JR   AtomStatementStringDirective
AtomStatementPstr:
            LD   A,2
            JR   AtomStatementStringDirective
AtomStatementIstr:
            LD   A,3
AtomStatementStringDirective:
            LD   (AtomStatementStringMode),A
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenString
            JP   NZ,AtomStatementDirectiveString
            JP   AtomStatementDbString

AtomStatementDs:
            CALL AtomStatementParseExpression
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JP   NZ,AtomStatementDirectiveUnresolved
            LD   (AtomStatementDataCount),HL
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JR   Z,AtomStatementDsReserve
            CP   AtomTokenComma
            JP   NZ,AtomStatementDirectiveDelimiter
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            CALL AtomStatementParseExpression
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JP   NZ,AtomStatementDirectiveUnresolved
            LD   A,L
            LD   (AtomStatementDataFill),A
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementDirectiveDelimiter
            LD   HL,(AtomStatementDataCount)
            CALL AtomOutputCheckCapacity
            JP   C,AtomStatementOutputFailure
AtomStatementDsFillLoop:
            LD   HL,(AtomStatementDataCount)
            LD   A,H
            OR   L
            JP   Z,AtomStatementNext
            LD   A,(AtomStatementDataFill)
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
            LD   HL,(AtomStatementDataCount)
            DEC  HL
            LD   (AtomStatementDataCount),HL
            JR   AtomStatementDsFillLoop
AtomStatementDsReserve:
            LD   HL,(AtomStatementDataCount)
            CALL AtomOutputReserve
            JP   AtomStatementOutputThenNext

; ALIGN emits the same initialized zero padding as AZM. Any positive resolved
; word is accepted; alignment is not restricted to powers of two.
AtomStatementAlign:
            CALL AtomStatementParseExpression
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JP   NZ,AtomStatementDirectiveUnresolved
            LD   A,(AtomExpressionResultValue+2)
            OR   A
            JP   NZ,AtomStatementDirectiveRange
            LD   A,H
            OR   L
            JP   Z,AtomStatementDirectiveRange
            LD   (AtomStatementDataValue),HL
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementDirectiveDelimiter
            LD   HL,(AtomOutputCursor)
            LD   (AtomExpressionLeftValue),HL
            XOR  A
            LD   (AtomExpressionLeftValue+2),A
            LD   HL,(AtomStatementDataValue)
            LD   (AtomExpressionResultValue),HL
            LD   (AtomExpressionResultValue+2),A
            CALL AtomExpressionRemainder
            JP   C,AtomStatementDirectiveFailure
            LD   HL,(AtomExpressionResultValue)
            LD   A,H
            OR   L
            JR   Z,AtomStatementAlignCountReady
            EX   DE,HL
            LD   HL,(AtomStatementDataValue)
            OR   A
            SBC  HL,DE
AtomStatementAlignCountReady:
            LD   (AtomStatementDataCount),HL
            XOR  A
            LD   (AtomStatementDataFill),A
            LD   HL,(AtomStatementDataCount)
            CALL AtomOutputCheckCapacity
            JP   C,AtomStatementOutputFailure
            JR   AtomStatementDsFillLoop

AtomStatementSuccess:
            XOR  A
            RET

; Recognize the reserved bare assembler directives through the same
; case-insensitive RADIX-40 packing used by mnemonics and symbols.
;
; in HL=text, B=length; out A=directive ordinal and carry clear, or carry set
.routine in B,HL out A,carry clobbers BC,HL,IX,zero,sign,parity,halfCarry,DE
AtomRecognizeDirective:
            LD   A,B
            CP   6
            JR   NC,AtomRecognizeDirectiveNotFound
            LD   DE,AtomScratch
            CALL AtomRadix40Pack
            RET  C
            LD   IX,AtomStatementDirectiveTable
            LD   B,AtomDirectiveCount
AtomRecognizeDirectiveLoop:
            LD   A,(AtomScratch)
            CP   (IX+0)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(AtomScratch+1)
            CP   (IX+1)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(AtomScratch+2)
            CP   (IX+2)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(AtomScratch+3)
            CP   (IX+3)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(IX+4)
            OR   A
            RET
AtomRecognizeDirectiveNext:
            LD   DE,5
            ADD  IX,DE
            DJNZ AtomRecognizeDirectiveLoop
AtomRecognizeDirectiveNotFound:
            XOR  A
            SCF
            RET

AtomStatementDirectiveTable:
            .dw $21FD,$0000
            .db AtomDirectiveEqu
            .dw $6097,$0000
            .db AtomDirectiveOrg
            .dw $1950,$0000
            .db AtomDirectiveDb
            .dw $1C98,$0000
            .db AtomDirectiveDw
            .dw $1BF8,$0000
            .db AtomDirectiveDs
            .dw $15CC,$7080
            .db AtomDirectiveCstr
            .dw $670C,$7080
            .db AtomDirectivePstr
            .dw $3B4C,$7080
            .db AtomDirectiveIstr
            .dw $0829,$2DF0
            .db AtomDirectiveAlign

.routine out A clobbers HL,zero,sign,parity,halfCarry
AtomStatementStringTake:
            LD   HL,(AtomStatementStringPointer)
            LD   A,(HL)
            INC  HL
            LD   (AtomStatementStringPointer),HL
            LD   HL,AtomStatementStringRemaining
            DEC  (HL)
            RET

.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomStatementNextTokenKind:
            CALL AtomTokenizerNext
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            RET

.routine out A,HL,IX,carry clobbers BC,DE,IY,zero,sign,parity,halfCarry
AtomStatementParseExpression:
            LD   BC,(AtomOutputCursor)
            JP   AtomExpressionParseDeferred

.routine out carry clobbers A,HL,zero,sign,parity,halfCarry
AtomStatementCapturePosition:
            LD   A,(AtomTokenRecord+AtomTokenPartOffset)
            LD   (AtomStatementErrorPart),A
            LD   HL,(AtomTokenRecord+AtomTokenSourceOffset)
            LD   (AtomStatementErrorOffset),HL
            RET

.routine in A out A,carry clobbers HL,halfCarry,zero,sign,parity
AtomStatementLexicalFailure:
            LD   (AtomStatementDetail),A
            LD   A,(AtomTokenErrorPart)
            LD   (AtomStatementErrorPart),A
            LD   HL,(AtomTokenErrorOffset)
            LD   (AtomStatementErrorOffset),HL
            LD   A,AtomStatementStatusLexical
            SCF
            RET
.routine out A,carry clobbers C,HL,zero,sign,parity,halfCarry
AtomStatementExpectedHere:
            CALL AtomStatementCapturePosition
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenDirective
            JR   NZ,AtomStatementExpectedSaved
.routine out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementUnsupportedDirective:
            LD   A,AtomTokenDirective
            LD   C,AtomStatementStatusDirective
            JR   AtomStatementFailure
.routine out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementExpectedSaved:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            LD   C,AtomStatementStatusExpected
            JR   AtomStatementFailure
.routine in A out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementSymbolFailure:
            LD   C,AtomStatementStatusSymbol
            JR   AtomStatementFailure
.if AtomDriverMode
AtomStatementSymbolPartFailure:
            LD   A,AtomStatusPartCapacity
            JR   AtomStatementSymbolFailure
.endif
.routine in A out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementInstructionFailure:
            LD   C,AtomStatementStatusInstruction
            JR   AtomStatementFailure
.routine in A out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementOutputFailure:
            LD   C,AtomStatementStatusOutput
            JR   AtomStatementFailure
.routine in A out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementEquateFailure:
            LD   C,AtomStatementStatusEquate
            JR   AtomStatementFailure
AtomStatementEquateUnresolved:
            LD   A,AtomExpressionUnresolved
            JR   AtomStatementEquateFailure
AtomStatementEquateDelimiter:
            LD   A,AtomExpressionStatusExpectedPrimary
            JR   AtomStatementEquateFailure
.routine in A out A,carry clobbers C,halfCarry,zero,sign,parity
AtomStatementDirectiveFailure:
            LD   C,AtomStatementStatusDirective
.routine in A,C out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementFailure:
            LD   (AtomStatementDetail),A
            LD   A,C
            SCF
            RET
AtomStatementDirectiveUnresolved:
            LD   A,AtomExpressionUnresolved
            JR   AtomStatementDirectiveFailure
AtomStatementDirectiveRange:
            LD   A,AtomExpressionStatusRange
            JR   AtomStatementDirectiveFailure
AtomStatementDirectiveExpected:
            LD   A,AtomExpressionStatusExpectedPrimary
            JR   AtomStatementDirectiveFailure
AtomStatementDirectiveDelimiter:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            JR   AtomStatementDirectiveFailure
AtomStatementDirectiveString:
            LD   A,AtomTokenString
            JR   AtomStatementDirectiveFailure

AtomStatementCodeEnd:

AtomStatementWorkspaceStart:
AtomStatementKey:           .ds 6
AtomStatementInstruction:   .ds 10
AtomStatementMnemonic:      .db 0
AtomStatementMnemonicValid: .db 0
AtomStatementDetail:        .db 0
AtomStatementErrorPart:     .db 0
AtomStatementErrorOffset:   .dw 0
AtomStatementEquateValue:   .dw 0
AtomStatementEquateSigned:  .db 0
AtomStatementDirective:     .db 0
AtomStatementDirectiveValid:.db 0
AtomStatementDataWidth:     .db 0
AtomStatementDataPatchKind: .db 0
AtomStatementDataAddend:    .db 0
AtomStatementDataFill:      .db 0
AtomStatementDataValue:     .dw 0
AtomStatementDataPendingKind:.equ AtomStatementDataValue
AtomStatementDataCount:     .dw 0
AtomStatementDataKey:       .dw 0
AtomStatementDataSymbol:    .dw 0
AtomStatementDataAddress:   .dw 0
AtomStatementStringPointer: .dw 0
AtomStatementStringRemaining:.db 0
AtomStatementStringCount:   .db 0
AtomStatementStringNibble:  .db 0
AtomStatementStringMode:    .db 0
AtomStatementWorkspaceEnd:
