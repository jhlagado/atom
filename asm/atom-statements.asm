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
AtomDirectiveCount:.equ 5

; Assemble the source part already installed in the tokenizer. Part EOF is not
; final assembly EOF: a later source part may still define a global reference.
;
; out A=AtomStatementStatusOk and carry clear; otherwise category and carry set
.routine out A,carry clobbers BC,DE,HL,IX,IY,zero,sign,parity,halfCarry
AtomAssemblePart:
AtomStatementNext:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEof
            JP   Z,AtomStatementSuccess
            CP   AtomTokenEol
            JP   Z,AtomStatementNext
            CP   AtomTokenName
            JP   NZ,AtomStatementExpectedHere

            CALL AtomStatementCapturePosition
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            LD   DE,AtomStatementKey
            CALL AtomPackSymbol
            JP   C,AtomStatementSymbolFailure

            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
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
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
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
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
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
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            CALL AtomRecognizeDirective
            JP   C,AtomStatementExpectedSaved
            CP   AtomDirectiveEqu
            JP   NZ,AtomStatementExpectedSaved
            JP   AtomStatementEquate

AtomStatementLabel:
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

            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   Z,AtomStatementNext
            CP   AtomTokenName
            JP   NZ,AtomStatementExpectedHere
            CALL AtomStatementCapturePosition
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            CALL AtomRecognizeMnemonic
            JR   C,AtomStatementLabelDirective
            LD   (AtomStatementMnemonic),A
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            JR   AtomStatementInstructionPublished
AtomStatementLabelDirective:
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            LD   B,A
            CALL AtomRecognizeDirective
            JP   C,AtomStatementExpectedSaved
            CP   AtomDirectiveEqu
            JP   Z,AtomStatementExpectedSaved
            LD   (AtomStatementDirective),A
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomStatementDirective)
            JP   AtomStatementDirectivePublished

AtomStatementInstructionPublished:
            LD   A,(AtomStatementMnemonic)
            LD   BC,(AtomOutputCursor)
            LD   DE,AtomStatementInstruction
            CALL AtomParserParsePublished
            JP   C,AtomStatementInstructionFailure
            CALL AtomOutputEmitInstruction
            JP   C,AtomStatementOutputFailure
            JP   AtomStatementNext

AtomStatementEquate:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   BC,(AtomOutputCursor)
            CALL AtomExpressionParseDeferred
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
            JP   C,AtomStatementOutputFailure
            JP   AtomStatementNext

AtomStatementDirectivePublished:
            CP   AtomDirectiveOrg
            JR   Z,AtomStatementOrg
            CP   AtomDirectiveDb
            JR   Z,AtomStatementDb
            CP   AtomDirectiveDw
            JR   Z,AtomStatementDw
            CP   AtomDirectiveDs
            JP   Z,AtomStatementDs
            JP   AtomStatementExpectedSaved

AtomStatementOrg:
            LD   BC,(AtomOutputCursor)
            CALL AtomExpressionParseDeferred
            JP   C,AtomStatementDirectiveFailure
            OR   A
            JP   NZ,AtomStatementDirectiveUnresolved
            LD   (AtomStatementDataValue),HL
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementDirectiveDelimiter
            LD   HL,(AtomStatementDataValue)
            CALL AtomOutputSetOrigin
            JP   C,AtomStatementOutputFailure
            JP   AtomStatementNext

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
            JP   Z,AtomStatementDbString
            JP   AtomStatementDirectiveString
AtomStatementDataExpression:
            LD   BC,(AtomOutputCursor)
            CALL AtomExpressionParseDeferred
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
            JR   AtomStatementDataDelimiter
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
.if AtomDriverMode
            LD   A,(AtomExpressionSymbolPart)
            CP   16
            JP   NC,AtomStatementSymbolPartFailure
            LD   A,(AtomStatementDataPatchKind)
            LD   (AtomStatementDataPendingKind),A
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
.if AtomDriverMode
            LD   A,(AtomStatementDataPendingKind)
.else
            LD   A,(AtomStatementDataPatchKind)
.endif
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
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
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
            LD   L,A
            LD   H,0
            CALL AtomOutputCheckCapacity
            JP   C,AtomStatementOutputFailure
            LD   HL,(AtomTokenRecord+AtomTokenLexemeOffset)
            INC  HL
            LD   (AtomStatementStringPointer),HL
            LD   A,(AtomTokenRecord+AtomTokenLengthOffset)
            SUB  2
            LD   (AtomStatementStringRemaining),A
AtomStatementStringEmitLoop:
            LD   A,(AtomStatementStringRemaining)
            OR   A
            JR   Z,AtomStatementStringDone
            CALL AtomStatementStringTake
            CP   "\\"
            JR   NZ,AtomStatementStringEmit
            CALL AtomStatementStringTake
            CP   "0"
            JR   Z,AtomStatementStringZero
            CP   "n"
            JR   Z,AtomStatementStringNewline
            CP   "r"
            JR   Z,AtomStatementStringReturn
            CP   "t"
            JR   Z,AtomStatementStringTab
            CP   "x"
            JR   Z,AtomStatementStringHex
            JR   AtomStatementStringEmit
AtomStatementStringZero:
            XOR  A
            JR   AtomStatementStringEmit
AtomStatementStringNewline:
            LD   A,$0A
            JR   AtomStatementStringEmit
AtomStatementStringReturn:
            LD   A,$0D
            JR   AtomStatementStringEmit
AtomStatementStringTab:
            LD   A,$09
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
            CALL AtomOutputEmitByte
            JP   C,AtomStatementOutputFailure
            JR   AtomStatementStringEmitLoop
AtomStatementStringDone:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            JP   AtomStatementDataDelimiter

AtomStatementDs:
            LD   BC,(AtomOutputCursor)
            CALL AtomExpressionParseDeferred
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
            LD   BC,(AtomOutputCursor)
            CALL AtomExpressionParseDeferred
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
            JP   C,AtomStatementOutputFailure
            JP   AtomStatementNext

AtomStatementSuccess:
            XOR  A
            RET

; Recognize the five reserved bare assembler directives through the same
; case-insensitive RADIX-40 packing used by mnemonics and symbols.
;
; in HL=text, B=length; out A=directive ordinal and carry clear, or carry set
.routine in B,HL out A,carry clobbers BC,HL,IX,zero,sign,parity,halfCarry,DE
AtomRecognizeDirective:
            LD   A,B
            LD   (AtomStatementDirectiveLength),A
            LD   DE,AtomScratch
            CALL AtomRadix40Pack
            RET  C
            LD   IX,AtomStatementDirectiveTable
            LD   B,AtomDirectiveCount
AtomRecognizeDirectiveLoop:
            LD   A,(AtomStatementDirectiveLength)
            CP   (IX+2)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(AtomScratch)
            CP   (IX+0)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(AtomScratch+1)
            CP   (IX+1)
            JR   NZ,AtomRecognizeDirectiveNext
            LD   A,(IX+3)
            OR   A
            RET
AtomRecognizeDirectiveNext:
            LD   DE,4
            ADD  IX,DE
            DJNZ AtomRecognizeDirectiveLoop
            XOR  A
            SCF
            RET

AtomStatementDirectiveTable:
            .dw $21FD
            .db 3,AtomDirectiveEqu
            .dw $6097
            .db 3,AtomDirectiveOrg
            .dw $1950
            .db 2,AtomDirectiveDb
            .dw $1C98
            .db 2,AtomDirectiveDw
            .dw $1BF8
            .db 2,AtomDirectiveDs

.routine out A clobbers HL,zero,sign,parity,halfCarry
AtomStatementStringTake:
            LD   HL,(AtomStatementStringPointer)
            LD   A,(HL)
            INC  HL
            LD   (AtomStatementStringPointer),HL
            LD   HL,AtomStatementStringRemaining
            DEC  (HL)
            RET

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
.routine out A,carry clobbers HL,zero,sign,parity,halfCarry
AtomStatementExpectedHere:
            CALL AtomStatementCapturePosition
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenDirective
            JR   Z,AtomStatementUnsupportedDirective
            JP   AtomStatementExpectedSaved
.routine out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementUnsupportedDirective:
            LD   A,AtomTokenDirective
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusDirective
            SCF
            RET
.routine out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementExpectedSaved:
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusExpected
            SCF
            RET
.routine in A out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementSymbolFailure:
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusSymbol
            SCF
            RET
.if AtomDriverMode
AtomStatementSymbolPartFailure:
            LD   A,AtomStatusPartCapacity
            JR   AtomStatementSymbolFailure
.endif
.routine in A out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementInstructionFailure:
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusInstruction
            SCF
            RET
.routine in A out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementOutputFailure:
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusOutput
            SCF
            RET
.routine in A out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementEquateFailure:
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusEquate
            SCF
            RET
AtomStatementEquateUnresolved:
            LD   A,AtomExpressionUnresolved
            JR   AtomStatementEquateFailure
AtomStatementEquateDelimiter:
            LD   A,AtomExpressionStatusExpectedPrimary
            JR   AtomStatementEquateFailure
.routine in A out A,carry clobbers halfCarry,zero,sign,parity
AtomStatementDirectiveFailure:
            LD   (AtomStatementDetail),A
            LD   A,AtomStatementStatusDirective
            SCF
            RET
AtomStatementDirectiveUnresolved:
            LD   A,AtomExpressionUnresolved
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
AtomStatementDirectiveLength:.db 0
AtomStatementEquateValue:   .dw 0
AtomStatementEquateSigned:  .db 0
AtomStatementDirective:     .db 0
AtomStatementDirectiveValid:.db 0
AtomStatementDataWidth:     .db 0
AtomStatementDataPatchKind: .db 0
AtomStatementDataAddend:    .db 0
AtomStatementDataFill:      .db 0
AtomStatementDataValue:     .dw 0
.if AtomDriverMode
AtomStatementDataPendingKind:.equ AtomStatementDataValue
.endif
AtomStatementDataCount:     .dw 0
AtomStatementDataKey:       .dw 0
AtomStatementDataSymbol:    .dw 0
AtomStatementDataAddress:   .dw 0
AtomStatementStringPointer: .dw 0
AtomStatementStringRemaining:.db 0
AtomStatementStringCount:   .db 0
AtomStatementStringNibble:  .db 0
AtomStatementWorkspaceEnd:
