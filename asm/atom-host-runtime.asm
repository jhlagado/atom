; Atom native core linked for the Debug80-backed Mac host.
;
; The six sink entries fail closed when executed as Z80 instructions. The host
; runner intercepts their entry addresses and implements the calls from the
; documented register ABI. Missing interception therefore cannot publish an
; apparently successful build.

            .org 0
AtomExpressionDeferredMode: .equ 1
AtomParserExpressionMode:   .equ 1
AtomParserOutputMode:       .equ 1
AtomSymbolOutputMode:       .equ 1
AtomParserStatementMode:    .equ 1
AtomSymbolStatementMode:    .equ 1
AtomDriverMode:             .equ 1

            .include "atom-encoder.asm"
            .include "atom-symbols.asm"
            .include "atom-tokenizer.asm"
            .include "atom-expression.asm"
            .include "atom-patch.asm"
            .include "atom-parser.asm"
            .include "atom-output.asm"
            .include "atom-statements.asm"
            .include "atom-driver.asm"

AtomHostServiceCodeStart:

.routine in IX out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkBegin:
            JR   AtomSinkFailClosed

.routine in A,C,HL out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkImageByte:
            JR   AtomSinkFailClosed

.routine in A,C,HL out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkPatchByte:
            JR   AtomSinkFailClosed

.routine in C,DE,HL out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkPatchWord:
            JR   AtomSinkFailClosed

.routine in IX,HL,DE out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkCommit:
            JR   AtomSinkFailClosed

.routine out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkAbort:
            JR   AtomSinkFailClosed
.routine out A,carry clobbers halfCarry,zero,sign,parity
AtomSinkFailClosed:
            SCF
            SBC  A,A
            RET

AtomHostServiceCodeEnd:
AtomHostResidentEnd:

            .end
