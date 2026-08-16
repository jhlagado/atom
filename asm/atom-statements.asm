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
            JP   Z,AtomStatementExpectedSaved
            JP   AtomStatementInstructionPublished

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

AtomStatementSuccess:
            XOR  A
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

AtomStatementCodeEnd:

AtomStatementWorkspaceStart:
AtomStatementKey:           .ds 6
AtomStatementInstruction:   .ds 10
AtomStatementMnemonic:      .db 0
AtomStatementMnemonicValid: .db 0
AtomStatementDetail:        .db 0
AtomStatementErrorPart:     .db 0
AtomStatementErrorOffset:   .dw 0
AtomStatementWorkspaceEnd:
