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
            JR   AtomStatementAfterFirstName
AtomStatementNotMnemonic:
            XOR  A
            LD   (AtomStatementMnemonicValid),A

AtomStatementAfterFirstName:
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenColon
            JR   Z,AtomStatementLabel
            LD   A,(AtomStatementMnemonicValid)
            OR   A
            JR   NZ,AtomStatementInstructionPublished
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
            JP   C,AtomStatementExpectedSaved
            LD   (AtomStatementMnemonic),A
            CALL AtomTokenizerNext
            JP   C,AtomStatementLexicalFailure

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
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            CP   AtomTokenEol
            JP   NZ,AtomStatementEquateDelimiter
            LD   HL,AtomStatementKey
            LD   DE,(AtomStatementEquateValue)
            CALL AtomSymbolDeclare
            JP   C,AtomStatementSymbolFailure
            CALL AtomOutputResolveSymbol
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
            JP   AtomStatementExpectedSaved
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
AtomStatementWorkspaceEnd:
