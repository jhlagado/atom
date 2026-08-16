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
AtomTokenStatusUnprocessedDirective:.equ 9
AtomTokenStatusUnterminatedCharacter:.equ 10
AtomTokenStatusInvalidCharacter:  .equ 11

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

; Names are maximal. Globals are at most eight bytes. A private leading '.'
; admits the prefix plus eight significant bytes and is published as a name.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanName:
            LD   A,8
            LD   (AtomTokenNameLimit),A
            CALL AtomTokenSourcePeek
            CP   "."
            JR   NZ,_AtomTokenScanNameGlobal
            LD   A,9
            LD   (AtomTokenNameLimit),A
            CALL AtomTokenSourceTake
            CALL AtomTokenSourcePeek
            JP   C,AtomTokenInvalidByte
            CALL AtomTokenIsNameStart
            JP   NC,AtomTokenInvalidByte
            LD   B,1
            JR   _AtomTokenScanNameLoop
_AtomTokenScanNameGlobal:
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
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenName
            JP   AtomTokenFinish
AtomTokenNameTooLong:
            LD   A,AtomTokenStatusNameTooLong
            JP   AtomTokenFail

; Scan one maximal digit/name run, select decimal or an Intel H/B suffix, then
; accumulate only the selected grammar. Failure leaves the cursor unchanged.
.routine out A,IX,carry clobbers BC,DE,HL,zero,sign,parity,halfCarry
AtomTokenScanDigitLed:
            LD   HL,(AtomTokenSourceCursor)
            LD   DE,(AtomTokenSourceEnd)
            LD   B,0
_AtomTokenScanDigitLedLook:
            LD   A,H
            CP   D
            JR   NZ,_AtomTokenScanDigitLedByte
            LD   A,L
            CP   E
            JR   Z,_AtomTokenScanDigitLedSelected
_AtomTokenScanDigitLedByte:
            LD   A,(HL)
            CALL AtomTokenIsNameByte
            JR   NC,_AtomTokenScanDigitLedSelected
            INC  HL
            INC  B
            JP   Z,AtomTokenInvalidNumber
            JR   _AtomTokenScanDigitLedLook

_AtomTokenScanDigitLedSelected:
            LD   A,B
            LD   (AtomTokenScanLength),A
            DEC  HL
            LD   A,(HL)
            AND  $DF
            LD   C,0
            CP   "H"
            JR   Z,_AtomTokenScanDigitLedHex
            CP   "B"
            JR   NZ,_AtomTokenScanDigitLedPrepare
            INC  C
            JR   _AtomTokenScanDigitLedSuffix
_AtomTokenScanDigitLedHex:
            LD   C,4
_AtomTokenScanDigitLedSuffix:
            DEC  B
_AtomTokenScanDigitLedPrepare:
            LD   A,B
            OR   A
            JP   Z,AtomTokenInvalidNumber
            LD   (AtomTokenDigitsSeen),A
            LD   IX,(AtomTokenScanPointer)
            LD   HL,0
            LD   A,C
            OR   A
            JR   Z,_AtomTokenScanDigitLedDecimal
            CP   1
            JR   Z,_AtomTokenScanDigitLedBinary

_AtomTokenScanDigitLedHexLoop:
            LD   A,(IX+0)
            CALL AtomTokenHexDigit
            JP   NC,AtomTokenInvalidNumber
            LD   E,A
            LD   A,H
            AND  $F0
            JP   NZ,AtomTokenNumberOverflow
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            LD   A,L
            OR   E
            LD   L,A
            INC  IX
            LD   A,(AtomTokenDigitsSeen)
            DEC  A
            LD   (AtomTokenDigitsSeen),A
            JR   NZ,_AtomTokenScanDigitLedHexLoop
            JR   _AtomTokenScanDigitLedFinish

_AtomTokenScanDigitLedBinary:
            LD   A,(IX+0)
            SUB  "0"
            JP   C,AtomTokenInvalidNumber
            CP   2
            JP   NC,AtomTokenInvalidNumber
            LD   E,A
            ADD  HL,HL
            JP   C,AtomTokenNumberOverflow
            LD   A,L
            OR   E
            LD   L,A
            INC  IX
            LD   A,(AtomTokenDigitsSeen)
            DEC  A
            LD   (AtomTokenDigitsSeen),A
            JR   NZ,_AtomTokenScanDigitLedBinary
            JR   _AtomTokenScanDigitLedFinish

_AtomTokenScanDigitLedDecimal:
            LD   A,(IX+0)
            SUB  "0"
            JP   C,AtomTokenInvalidNumber
            CP   10
            JP   NC,AtomTokenInvalidNumber
            LD   C,A
            LD   A,H
            CP   $19
            JR   C,_AtomTokenScanDigitLedDecimalAccumulate
            JP   NZ,AtomTokenNumberOverflow
            LD   A,L
            CP   $99
            JR   C,_AtomTokenScanDigitLedDecimalAccumulate
            JP   NZ,AtomTokenNumberOverflow
            LD   A,C
            CP   6
            JP   NC,AtomTokenNumberOverflow
_AtomTokenScanDigitLedDecimalAccumulate:
            LD   D,0
            LD   E,C
            ADD  HL,HL
            LD   B,H
            LD   C,L
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,BC
            ADD  HL,DE
            INC  IX
            LD   A,(AtomTokenDigitsSeen)
            DEC  A
            LD   (AtomTokenDigitsSeen),A
            JR   NZ,_AtomTokenScanDigitLedDecimal

_AtomTokenScanDigitLedFinish:
            LD   (AtomTokenScanValue),HL
            LD   A,(AtomTokenScanLength)
            LD   C,A
            LD   B,0
            LD   HL,(AtomTokenScanPointer)
            ADD  HL,BC
            LD   (AtomTokenSourceCursor),HL
            LD   HL,(AtomTokenScanOffset)
            ADD  HL,BC
            LD   (AtomTokenSourceOffsetState),HL
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
AtomTokenUnterminatedCharacter:
            LD   A,AtomTokenStatusUnterminatedCharacter
            JP   AtomTokenFail
AtomTokenInvalidCharacter:
            LD   A,AtomTokenStatusInvalidCharacter
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
            JP   Z,AtomTokenScanName
            CP   $22
            JP   Z,AtomTokenScanString
            CP   $27
            JP   Z,_AtomTokenizerApostrophe
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
            JP   C,AtomTokenScanDigitLed
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
            CALL AtomTokenIsLetter
            JR   NC,_AtomTokenizerPercentToken
            LD   A,(AtomTokenLineHasToken)
            OR   A
            JR   NZ,_AtomTokenizerPercentToken
            LD   A,AtomTokenStatusUnprocessedDirective
            JP   AtomTokenFail
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

; An apostrophe adjacent to a name byte is the AF' register suffix. Every
; other apostrophe begins a one-byte character literal.
_AtomTokenizerApostrophe:
            LD   HL,(AtomTokenScanOffset)
            LD   A,H
            OR   L
            JP   Z,AtomTokenScanCharacter
            LD   HL,(AtomTokenScanPointer)
            DEC  HL
            LD   A,(HL)
            CALL AtomTokenIsNameByte
            JP   NC,AtomTokenScanCharacter
            CALL AtomTokenSourceTake
            LD   A,1
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenApostrophe
            JP   AtomTokenFinish

; Single-quoted character literals are published as ordinary numeric tokens,
; so every expression consumer receives them without another parser rule.
.routine out A,IX,carry clobbers BC,DE,HL,IY,zero,sign,parity,halfCarry
AtomTokenScanCharacter:
            LD   B,1
            CALL AtomTokenSourceTake
            CALL AtomTokenSourceTake
            JP   C,AtomTokenUnterminatedCharacter
            INC  B
            CP   $0A
            JP   Z,AtomTokenUnterminatedCharacter
            CP   $0D
            JP   Z,AtomTokenUnterminatedCharacter
            CP   $27
            JP   Z,AtomTokenInvalidCharacter
            CP   "\\"
            JR   Z,_AtomTokenScanCharacterEscape
            CP   $20
            JP   C,AtomTokenInvalidByte
            CP   $7F
            JP   NC,AtomTokenInvalidByte
            LD   (AtomTokenScanValue),A
            JR   _AtomTokenScanCharacterClose
_AtomTokenScanCharacterEscape:
            CALL AtomTokenSourceTake
            JP   C,AtomTokenUnterminatedCharacter
            INC  B
            CP   "x"
            JR   Z,_AtomTokenScanCharacterHex
            LD   HL,AtomTokenEscapeTable
            LD   C,AtomTokenEscapeCount
_AtomTokenScanCharacterEscapeLoop:
            CP   (HL)
            JR   Z,_AtomTokenScanCharacterEscapeFound
            INC  HL
            INC  HL
            DEC  C
            JR   NZ,_AtomTokenScanCharacterEscapeLoop
            JP   AtomTokenInvalidEscape
_AtomTokenScanCharacterEscapeFound:
            INC  HL
            LD   A,(HL)
            LD   (AtomTokenScanValue),A
            JR   _AtomTokenScanCharacterClose
_AtomTokenScanCharacterHex:
            CALL AtomTokenSourceTake
            JP   C,AtomTokenUnterminatedCharacter
            INC  B
            CALL AtomTokenHexDigit
            JP   NC,AtomTokenInvalidEscape
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   (AtomTokenScanValue),A
            CALL AtomTokenSourceTake
            JP   C,AtomTokenUnterminatedCharacter
            INC  B
            CALL AtomTokenHexDigit
            JP   NC,AtomTokenInvalidEscape
            LD   HL,AtomTokenScanValue
            OR   (HL)
            LD   (AtomTokenScanValue),A
_AtomTokenScanCharacterClose:
            CALL AtomTokenSourceTake
            JP   C,AtomTokenUnterminatedCharacter
            INC  B
            CP   $0A
            JP   Z,AtomTokenUnterminatedCharacter
            CP   $0D
            JP   Z,AtomTokenUnterminatedCharacter
            CP   $27
            JP   NZ,AtomTokenInvalidCharacter
            LD   A,B
            LD   (AtomTokenScanLength),A
            LD   A,AtomTokenNumber
            JP   AtomTokenFinish

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

AtomTokenEscapeTable:
            .db "0",0,"n",$0A,"r",$0D,"t",$09,$27,$27,$22,$22,"\\","\\"
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
