; atom Phase 2b memory-backed streaming tokenizer.
;
; The tokenizer consumes one caller-owned source part from left to right. It
; retains only a cursor, a one-token record, and diagnostic position state.
; A later manifest adapter may reset it for each ordered source part without
; changing the token ABI.

AtomTokenizerCodeStart:

; Token kinds. Zero is a stable EOF event. Punctuation kinds are deliberately
; dense so a later parser can dispatch them without another character table.
AtomTokenEof:          .equ 0
AtomTokenEol:          .equ 1
AtomTokenName:         .equ 2
AtomTokenDirective:    .equ 3
AtomTokenNumber:       .equ 4
AtomTokenString:       .equ 5
AtomTokenComma:        .equ 6
AtomTokenColon:        .equ 7
AtomTokenLeftParen:    .equ 8
AtomTokenRightParen:   .equ 9
AtomTokenPlus:         .equ 10
AtomTokenMinus:        .equ 11
AtomTokenStar:         .equ 12
AtomTokenSlash:        .equ 13
AtomTokenPercent:      .equ 14
AtomTokenAmpersand:    .equ 15
AtomTokenCaret:        .equ 16
AtomTokenPipe:         .equ 17
AtomTokenTilde:        .equ 18
AtomTokenApostrophe:   .equ 19
AtomTokenLeftShift:    .equ 20
AtomTokenRightShift:   .equ 21
AtomTokenCurrent:      .equ 22

; Failure status values. Carry distinguishes these from successful token kinds.
AtomTokenStatusInvalidByte:       .equ 1
AtomTokenStatusNameTooLong:       .equ 2
AtomTokenStatusInvalidNumber:     .equ 3
AtomTokenStatusNumberOverflow:    .equ 4
AtomTokenStatusUnterminatedString:.equ 5
AtomTokenStatusInvalidEscape:     .equ 6
AtomTokenStatusStringTooLong:     .equ 7
AtomTokenStatusBadSourceRange:    .equ 8

; Nine-byte token record returned in IX.
AtomTokenKindOffset:       .equ 0
AtomTokenPartOffset:       .equ 1
AtomTokenSourceOffset:     .equ 2
AtomTokenLexemeOffset:     .equ 4
AtomTokenLengthOffset:     .equ 6
AtomTokenValueOffset:      .equ 7
AtomTokenRecordBytes:      .equ 9

; Initialize one source part. The source interval is half-open. A reversed
; interval is rejected before any tokenizer state is changed.
;
; in A=source-part ordinal, HL=source start, DE=source end
; out A=0, IX=token record, carry clear; or A=status, carry set
.routine in A,HL,DE out A,IX,carry clobbers sign,parity,halfCarry,zero
AtomTokenizerReset:
            PUSH AF
            PUSH HL
            PUSH DE
            EX   DE,HL
            OR   A
            SBC  HL,DE
            JR   C,_AtomTokenRestoreBadSourceRange
            POP  DE
            POP  HL
            POP  AF

            LD   (AtomTokenSourcePart),A
            LD   (AtomTokenSourceCursor),HL
            LD   (AtomTokenSourceEnd),DE
            XOR  A
            LD   (AtomTokenSourceOffsetState),A
            LD   (AtomTokenSourceOffsetState+1),A
            LD   (AtomTokenLineHasToken),A
            LD   (AtomTokenEofPending),A
            LD   (AtomTokenErrorStatus),A
            LD   (AtomTokenRecord+AtomTokenKindOffset),A
            LD   IX,AtomTokenRecord
            RET
_AtomTokenRestoreBadSourceRange:
            POP  DE
            POP  HL
            POP  AF
_AtomTokenBadSourceRange:
            LD   A,AtomTokenStatusBadSourceRange
            SCF
            RET

; Return the current source byte without consuming it. Carry is the separate
; end-of-part event.
.routine out A,carry,zero clobbers DE,HL,sign,parity,halfCarry
AtomTokenSourcePeek:
            LD   HL,(AtomTokenSourceCursor)
            LD   DE,(AtomTokenSourceEnd)
            OR   A
            SBC  HL,DE
            JR   Z,_AtomTokenSourcePeekEof
            ADD  HL,DE
_AtomTokenSourcePeekByte:
            LD   A,(HL)
            OR   A
            RET
_AtomTokenSourcePeekEof:
            SCF
            RET

; Consume one byte and advance the 16-bit byte offset.
.routine out A,carry,zero clobbers DE,HL,sign,parity,halfCarry
AtomTokenSourceTake:
            PUSH BC
            CALL AtomTokenSourcePeek
            JR   C,_AtomTokenSourceTakeEof
            LD   B,A
            LD   HL,(AtomTokenSourceCursor)
            INC  HL
            LD   (AtomTokenSourceCursor),HL
            LD   HL,(AtomTokenSourceOffsetState)
            INC  HL
            LD   (AtomTokenSourceOffsetState),HL
            LD   A,B
            POP  BC
            OR   A
            RET
_AtomTokenSourceTakeEof:
            POP  BC
            SCF
            RET

; Snapshot the position of the next token without publishing it.
.routine out carry,zero clobbers A,HL,sign,parity,halfCarry
AtomTokenStart:
            LD   HL,(AtomTokenSourceCursor)
            LD   (AtomTokenScanPointer),HL
            LD   HL,(AtomTokenSourceOffsetState)
            LD   (AtomTokenScanOffset),HL
            XOR  A
            LD   (AtomTokenScanLength),A
            LD   (AtomTokenScanValue),A
            LD   (AtomTokenScanValue+1),A
            RET

; Publish the complete scratch token in one common suffix.
; in A=token kind
; out A=token kind, IX=record, carry clear
.routine in A out A,IX,carry clobbers HL,sign,parity,halfCarry,zero
AtomTokenCommit:
            LD   (AtomTokenRecord+AtomTokenKindOffset),A
            LD   A,(AtomTokenSourcePart)
            LD   (AtomTokenRecord+AtomTokenPartOffset),A
            LD   HL,(AtomTokenScanOffset)
            LD   (AtomTokenRecord+AtomTokenSourceOffset),HL
            LD   HL,(AtomTokenScanPointer)
            LD   (AtomTokenRecord+AtomTokenLexemeOffset),HL
            LD   A,(AtomTokenScanLength)
            LD   (AtomTokenRecord+AtomTokenLengthOffset),A
            LD   HL,(AtomTokenScanValue)
            LD   (AtomTokenRecord+AtomTokenValueOffset),HL
            LD   IX,AtomTokenRecord
            LD   A,(AtomTokenRecord+AtomTokenKindOffset)
            OR   A
            RET

; Ordinary source tokens mark their physical line as non-empty.
.routine in A out A,IX,carry clobbers HL,zero,sign,parity,halfCarry
AtomTokenFinish:
            LD   (AtomTokenPendingKind),A
            LD   A,1
            LD   (AtomTokenLineHasToken),A
            LD   A,(AtomTokenPendingKind)
            JP   AtomTokenCommit

; A failed scan publishes only a separate diagnostic position. The last
; successful token record remains byte-for-byte unchanged.
; in A=status
; out A=status, carry set
.routine in A out A,carry clobbers HL,halfCarry,sign,parity,zero
AtomTokenFail:
            LD   (AtomTokenErrorStatus),A
            LD   A,(AtomTokenSourcePart)
            LD   (AtomTokenErrorPart),A
            LD   HL,(AtomTokenScanOffset)
            LD   (AtomTokenErrorOffset),HL
            LD   A,(AtomTokenErrorStatus)
            SCF
            RET

; Carry is set for an ASCII letter. A is preserved.
.routine in A out A,carry clobbers C,sign,parity,halfCarry,zero
AtomTokenIsLetter:
            LD   C,A
            OR   $20
            SUB  "a"
            CP   26
            LD   A,C
            RET

; Carry is set for a name start: letter or underscore.
.routine in A out A,carry clobbers C,zero,sign,parity,halfCarry
AtomTokenIsNameStart:
            CALL AtomTokenIsLetter
            RET  C
            CP   "_"
            JR   Z,AtomTokenClassYes
            OR   A
            RET

; Carry is set for a name continuation byte.
.routine in A out A,carry clobbers C,zero,sign,parity,halfCarry
AtomTokenIsNameByte:
            CALL AtomTokenIsNameStart
            RET  C
            CP   "0"
            JR   C,AtomTokenClassNo
            CP   "9"+1
            RET  C
AtomTokenClassNo:
            OR   A
            RET
AtomTokenClassYes:
            SCF
            RET

; Carry is set and A is the decoded nibble for one hexadecimal digit.
.routine in A out A,carry clobbers zero,sign,parity,halfCarry
AtomTokenHexDigit:
            CP   "0"
            JR   C,_AtomTokenHexNo
            CP   "9"+1
            JR   C,_AtomTokenHexDecimal
            OR   $20
            SUB  "a"
            CP   6
            JR   NC,_AtomTokenHexNo
            ADD  A,10
            SCF
            RET
_AtomTokenHexDecimal:
            SUB  "0"
            SCF
            RET
_AtomTokenHexNo:
            OR   A
            RET

; Names are maximal. Globals are at most eight bytes; a private leading '_'
; admits the prefix plus eight significant bytes.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanName:
            LD   A,8
            LD   (AtomTokenNameLimit),A
            CALL AtomTokenSourcePeek
            CP   "_"
            JR   NZ,_AtomTokenScanNameLoopStart
            LD   A,9
            LD   (AtomTokenNameLimit),A
_AtomTokenScanNameLoopStart:
            LD   B,0
_AtomTokenScanNameLoop:
            CALL AtomTokenSourcePeek
            JR   C,_AtomTokenScanNameDone
            CALL AtomTokenIsNameByte
            JR   NC,_AtomTokenScanNameDone
            INC  B
            LD   A,(AtomTokenNameLimit)
            CP   B
            JR   C,AtomTokenNameTooLong
            CALL AtomTokenSourceTake
            JR   _AtomTokenScanNameLoop
_AtomTokenScanNameDone:
            LD   A,B
            CP   1
            JR   NZ,_AtomTokenNameReady
            LD   HL,(AtomTokenScanPointer)
            LD   A,(HL)
            CP   "_"
            JP   Z,AtomTokenInvalidByte
_AtomTokenNameReady:
            LD   A,B
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenName
            JP   AtomTokenFinish
AtomTokenNameTooLong:
            LD   A,AtomTokenStatusNameTooLong
            JP   AtomTokenFail

; Directives retain the name after '.', allowing the parser to compare or
; ignore host-only annotations without copying the line.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanDirective:
            CALL AtomTokenSourceTake
            LD   HL,(AtomTokenSourceCursor)
            LD   (AtomTokenScanPointer),HL
            CALL AtomTokenSourcePeek
            JP   C,AtomTokenInvalidByte
            CALL AtomTokenIsLetter
            JP   NC,AtomTokenInvalidByte
            LD   B,0
_AtomTokenScanDirectiveLoop:
            CALL AtomTokenSourcePeek
            JR   C,_AtomTokenScanDirectiveDone
            CALL AtomTokenIsNameByte
            JR   NC,_AtomTokenScanDirectiveDone
            INC  B
            JR   Z,AtomTokenNameTooLong
            CALL AtomTokenSourceTake
            JR   _AtomTokenScanDirectiveLoop
_AtomTokenScanDirectiveDone:
            LD   A,B
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenDirective
            JP   AtomTokenFinish

; Decimal accumulation is bounded exactly to 0..65535.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanDecimal:
            LD   HL,0
_AtomTokenScanDecimalLoop:
            PUSH HL
            CALL AtomTokenSourcePeek
            POP  HL
            JR   C,_AtomTokenScanDecimalEof
            CP   "0"
            JR   C,_AtomTokenScanDecimalDone
            CP   "9"+1
            JR   NC,_AtomTokenScanDecimalDone
            SUB  "0"
            LD   C,A
            LD   A,H
            CP   $19
            JR   C,_AtomTokenScanDecimalAccumulate
            JP   NZ,AtomTokenNumberOverflow
            LD   A,L
            CP   $99
            JR   C,_AtomTokenScanDecimalAccumulate
            JP   NZ,AtomTokenNumberOverflow
            LD   A,C
            CP   6
            JP   NC,AtomTokenNumberOverflow
_AtomTokenScanDecimalAccumulate:
            LD   D,0
            LD   E,C
            ADD  HL,HL
            LD   B,H
            LD   C,L
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            ADD  HL,DE
            PUSH HL
            CALL AtomTokenSourceTake
            POP  HL
            LD   A,(AtomTokenScanLength)
            INC  A
            LD   (AtomTokenScanLength),A
            JR   _AtomTokenScanDecimalLoop
_AtomTokenScanDecimalDone:
            CALL AtomTokenIsNameByte
            JR   C,AtomTokenInvalidNumber
_AtomTokenScanDecimalEof:
            LD   (AtomTokenScanValue),HL
            LD   A,AtomTokenNumber
            JP   AtomTokenFinish

; Scan binary or hexadecimal digits after a one-byte prefix. C is 1 for
; binary and 4 for hexadecimal; B already counts the prefix.
.routine in BC out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanBased:
            LD   HL,0
            XOR  A
            LD   (AtomTokenDigitsSeen),A
_AtomTokenScanBasedLoop:
            PUSH HL
            CALL AtomTokenSourcePeek
            POP  HL
            JR   C,_AtomTokenScanBasedEof
            LD   D,A
            BIT  2,C
            JR   Z,_AtomTokenScanBinaryDigit
            CALL AtomTokenHexDigit
            JR   NC,_AtomTokenScanBasedDone
            JR   _AtomTokenScanBasedDigit
_AtomTokenScanBinaryDigit:
            SUB  "0"
            JR   C,_AtomTokenScanBasedDone
            CP   2
            JR   NC,_AtomTokenScanBasedDone
_AtomTokenScanBasedDigit:
            LD   E,A
            BIT  2,C
            JR   Z,_AtomTokenScanBinaryShift
            LD   A,H
            AND  $F0
            JR   NZ,AtomTokenNumberOverflow
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            JR   _AtomTokenScanBasedMerge
_AtomTokenScanBinaryShift:
            ADD  HL,HL
            JR   C,AtomTokenNumberOverflow
_AtomTokenScanBasedMerge:
            LD   A,L
            OR   E
            LD   L,A
            PUSH HL
            CALL AtomTokenSourceTake
            POP  HL
            INC  B
            JR   Z,AtomTokenInvalidNumber
            LD   A,1
            LD   (AtomTokenDigitsSeen),A
            JR   _AtomTokenScanBasedLoop
_AtomTokenScanBasedDone:
            LD   A,(AtomTokenDigitsSeen)
            OR   A
            JR   Z,AtomTokenInvalidNumber
            LD   A,D
            CALL AtomTokenIsNameByte
            JR   C,AtomTokenInvalidNumber
            JR   _AtomTokenScanBasedFinish
_AtomTokenScanBasedEof:
            LD   A,(AtomTokenDigitsSeen)
            OR   A
            JR   Z,AtomTokenInvalidNumber
_AtomTokenScanBasedFinish:
            LD   (AtomTokenScanValue),HL
            LD   A,B
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenNumber
            JP   AtomTokenFinish

AtomTokenInvalidNumber:
            LD   A,AtomTokenStatusInvalidNumber
            JP   AtomTokenFail
AtomTokenNumberOverflow:
            LD   A,AtomTokenStatusNumberOverflow
            JP   AtomTokenFail

; Double-quoted byte strings retain their raw spelling. Escape validity is
; proved here; decoding belongs to the later directive/expression parser.
.routine out A,IX,carry clobbers DE,HL,zero,sign,parity,halfCarry,BC
AtomTokenScanString:
            LD   B,0
            CALL AtomTokenStringTake
            JP   C,AtomTokenFail
_AtomTokenScanStringLoop:
            CALL AtomTokenStringTake
            JP   C,AtomTokenFail
            CP   $0A
            JR   Z,AtomTokenUnterminatedString
            CP   $0D
            JR   Z,AtomTokenUnterminatedString
            CP   $20
            JR   C,AtomTokenInvalidByte
            CP   $7F
            JR   NC,AtomTokenInvalidByte
            CP   $22
            JR   Z,_AtomTokenScanStringDone
            CP   "\\"
            JR   NZ,_AtomTokenScanStringLoop
            CALL AtomTokenStringTake
            JP   C,AtomTokenFail
            CP   "x"
            JR   Z,_AtomTokenScanHexEscape
            LD   HL,AtomTokenEscapeTable
            LD   C,AtomTokenEscapeCount
_AtomTokenScanEscapeLoop:
            CP   (HL)
            JR   Z,_AtomTokenScanStringLoop
            INC  HL
            DEC  C
            JR   NZ,_AtomTokenScanEscapeLoop
            LD   A,AtomTokenStatusInvalidEscape
            JP   AtomTokenFail
_AtomTokenScanHexEscape:
            CALL AtomTokenStringTake
            JP   C,AtomTokenFail
            CALL AtomTokenHexDigit
            JR   NC,AtomTokenInvalidEscape
            CALL AtomTokenStringTake
            JP   C,AtomTokenFail
            CALL AtomTokenHexDigit
            JR   NC,AtomTokenInvalidEscape
            JR   _AtomTokenScanStringLoop
_AtomTokenScanStringDone:
            LD   A,B
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenString
            JP   AtomTokenFinish

; Consume one string byte and count the raw token length. Carry returns the
; exact unterminated or overlength status in A.
.routine in B out A,B,carry clobbers DE,HL,zero,sign,parity,halfCarry
AtomTokenStringTake:
            CALL AtomTokenSourceTake
            JR   C,_AtomTokenStringTakeEof
            INC  B
            RET  NZ
            LD   A,AtomTokenStatusStringTooLong
            SCF
            RET
_AtomTokenStringTakeEof:
            LD   A,AtomTokenStatusUnterminatedString
            SCF
            RET

AtomTokenInvalidEscape:
            LD   A,AtomTokenStatusInvalidEscape
            JP   AtomTokenFail
AtomTokenUnterminatedString:
            LD   A,AtomTokenStatusUnterminatedString
            JP   AtomTokenFail
AtomTokenInvalidByte:
            LD   A,AtomTokenStatusInvalidByte
            JP   AtomTokenFail

; Skip a semicolon comment but leave its physical line ending for the normal
; EOL path.
.routine out carry,zero clobbers DE,HL,sign,parity,halfCarry,A
AtomTokenSkipComment:
_AtomTokenSkipCommentLoop:
            CALL AtomTokenSourcePeek
            RET  C
            CP   $0A
            RET  Z
            CP   $0D
            RET  Z
            CALL AtomTokenSourceTake
            JR   _AtomTokenSkipCommentLoop

; Return the next token or a lexical status. Whitespace and comment-only lines
; do not surface; a non-empty final line receives one synthetic EOL before EOF.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry,IY
AtomTokenizerNext:
_AtomTokenizerNextLoop:
            CALL AtomTokenStart
            CALL AtomTokenSourcePeek
            JP   C,_AtomTokenizerAtEof
            CP   " "
            JR   Z,_AtomTokenizerSkipByte
            CP   $09
            JR   Z,_AtomTokenizerSkipByte
            CP   $0A
            JP   Z,_AtomTokenizerLf
            CP   $0D
            JP   Z,_AtomTokenizerCrLf
            CP   ";"
            JR   Z,_AtomTokenizerComment
            CP   "."
            JP   Z,AtomTokenScanDirective
            CP   $22
            JP   Z,AtomTokenScanString
            CP   "$"
            JP   Z,_AtomTokenizerDollar
            CP   "%"
            JP   Z,_AtomTokenizerPercent
            CP   "<"
            JP   Z,_AtomTokenizerLeftShift
            CP   ">"
            JP   Z,_AtomTokenizerRightShift
            CP   "0"
            JR   C,_AtomTokenizerTryName
            CP   "9"+1
            JP   C,AtomTokenScanDecimal
_AtomTokenizerTryName:
            CALL AtomTokenIsNameStart
            JP   C,AtomTokenScanName

            LD   HL,AtomTokenPunctuationTable
            LD   B,AtomTokenPunctuationCount
_AtomTokenizerPunctuationLoop:
            CP   (HL)
            INC  HL
            JR   Z,_AtomTokenizerPunctuation
            INC  HL
            DJNZ _AtomTokenizerPunctuationLoop
            JP   AtomTokenInvalidByte

_AtomTokenizerPunctuation:
            LD   C,(HL)
            CALL AtomTokenSourceTake
            LD   A,1
            LD   (AtomTokenScanLength),A
            LD   A,C
            JP   AtomTokenFinish

_AtomTokenizerSkipByte:
            CALL AtomTokenSourceTake
            JR   _AtomTokenizerNextLoop

_AtomTokenizerComment:
            CALL AtomTokenSkipComment
            JR   _AtomTokenizerNextLoop

_AtomTokenizerDollar:
            CALL AtomTokenSourceTake
            CALL AtomTokenSourcePeek
            JR   C,_AtomTokenizerCurrentLocation
            LD   B,A
            CALL AtomTokenHexDigit
            JR   C,_AtomTokenizerDollarNumber
            LD   A,B
            CALL AtomTokenIsNameByte
            JP   C,AtomTokenInvalidNumber
_AtomTokenizerCurrentLocation:
            LD   A,1
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenCurrent
            JP   AtomTokenFinish
_AtomTokenizerDollarNumber:
            LD   B,1
            LD   C,4
            JP   AtomTokenScanBased

_AtomTokenizerPercent:
            CALL AtomTokenSourceTake
            CALL AtomTokenSourcePeek
            JR   C,_AtomTokenizerPercentToken
            CP   "0"
            JR   Z,_AtomTokenizerPercentNumber
            CP   "1"
            JR   Z,_AtomTokenizerPercentNumber
_AtomTokenizerPercentToken:
            LD   A,1
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenPercent
            JP   AtomTokenFinish
_AtomTokenizerPercentNumber:
            LD   B,1
            LD   C,1
            JP   AtomTokenScanBased

_AtomTokenizerLeftShift:
            LD   C,AtomTokenLeftShift
            JR   _AtomTokenizerShift
_AtomTokenizerRightShift:
            LD   C,AtomTokenRightShift
_AtomTokenizerShift:
            LD   B,A
            CALL AtomTokenSourceTake
            CALL AtomTokenSourcePeek
            JP   C,AtomTokenInvalidByte
            CP   B
            JP   NZ,AtomTokenInvalidByte
            CALL AtomTokenSourceTake
            LD   A,2
            LD   (AtomTokenScanLength),A
            LD   A,C
            JP   AtomTokenFinish

_AtomTokenizerLf:
            CALL AtomTokenSourceTake
            LD   A,1
            LD   (AtomTokenScanLength),A
            JR   _AtomTokenizerFinishLine
_AtomTokenizerCrLf:
            CALL AtomTokenSourceTake
            CALL AtomTokenSourcePeek
            JP   C,AtomTokenInvalidByte
            CP   $0A
            JP   NZ,AtomTokenInvalidByte
            CALL AtomTokenSourceTake
            LD   A,2
            LD   (AtomTokenScanLength),A
_AtomTokenizerFinishLine:
            XOR  A
            LD   (AtomTokenEofPending),A
            LD   A,(AtomTokenLineHasToken)
            OR   A
            JP   Z,_AtomTokenizerNextLoop
            XOR  A
            LD   (AtomTokenLineHasToken),A
            LD   A,AtomTokenEol
            JP   AtomTokenCommit

_AtomTokenizerAtEof:
            LD   A,(AtomTokenEofPending)
            OR   A
            JR   NZ,_AtomTokenizerEmitEof
            LD   A,(AtomTokenLineHasToken)
            OR   A
            JR   Z,_AtomTokenizerEmitEof
            XOR  A
            LD   (AtomTokenLineHasToken),A
            INC  A
            LD   (AtomTokenEofPending),A
            XOR  A
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenEol
            JP   AtomTokenCommit
_AtomTokenizerEmitEof:
            XOR  A
            LD   (AtomTokenScanLength),A
            JP   AtomTokenCommit

AtomTokenizerRuleCodeEnd:
AtomTokenizerImmutableStart:
AtomTokenPunctuationTable:
            .db ",",AtomTokenComma
            .db ":",AtomTokenColon
            .db "(",AtomTokenLeftParen
            .db ")",AtomTokenRightParen
            .db "+",AtomTokenPlus
            .db "-",AtomTokenMinus
            .db "*",AtomTokenStar
            .db "/",AtomTokenSlash
            .db "&",AtomTokenAmpersand
            .db "^",AtomTokenCaret
            .db "|",AtomTokenPipe
            .db "~",AtomTokenTilde
            .db $27,AtomTokenApostrophe
AtomTokenPunctuationEnd:
AtomTokenPunctuationCount: .equ (AtomTokenPunctuationEnd-AtomTokenPunctuationTable)/2

AtomTokenEscapeTable: .db "0nrt",$27,$22,"\\"
AtomTokenEscapeCount: .equ 7
AtomTokenizerImmutableEnd:

AtomTokenizerCodeEnd:

; Fixed, non-reentrant source and token state. Source bytes remain caller-owned.
AtomTokenizerWorkspaceStart:
AtomTokenSourceCursor:       .dw 0
AtomTokenSourceEnd:          .dw 0
AtomTokenSourceOffsetState:  .dw 0
AtomTokenSourcePart:         .db 0
AtomTokenLineHasToken:       .db 0
AtomTokenEofPending:         .db 0
AtomTokenScanPointer:        .dw 0
AtomTokenScanOffset:         .dw 0
AtomTokenScanLength:         .db 0
AtomTokenScanValue:          .dw 0
AtomTokenDigitsSeen:         .db 0
AtomTokenNameLimit:          .db 0
AtomTokenPendingKind:        .db 0
AtomTokenErrorStatus:        .db 0
AtomTokenErrorPart:          .db 0
AtomTokenErrorOffset:        .dw 0
AtomTokenRecord:             .ds AtomTokenRecordBytes
AtomTokenizerWorkspaceEnd:
