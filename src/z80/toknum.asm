;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Global names allow eight raw bytes. A private name allows nine because its
; leading period is scope syntax rather than part of the eight-character name.

tkIdent: ; Scan a bounded global or private name.
    LD   C,8                            ; Limit globals to eight bytes.
    CALL tkPeek                         ; Inspect the first tentative source byte.
    CP   $2E                            ; Is this a private-name period?
    JR   NZ,.global                     ; No: use global rules.
    LD   C,9                            ; Allow period plus eight name bytes.
    CALL tkTake                         ; Consume and buffer the private marker.

; A period alone is not a name. The next byte must begin one.

    CALL tkPeek                         ; Inspect the first private payload byte.
    JP   C,tkErrSrc                     ; Diagnose a period at end of part.
    CALL tkLead                         ; Require a legal first name character.
    JP   NC,tkErrSrc                    ; Reject bare or malformed prefix.
    LD   B,1                            ; Count the already consumed period.
    JR   .loop                          ; Enter the common continuation scan.
.global: ; Begin an ordinary global-name scan.
    LD   B,0                            ; No raw source byte has been consumed yet.
.loop: ; Accept one legal name byte per iteration.

; B is accepted raw length. Stop before the first non-name byte so the next
; tokenizer call can classify it independently.

    CALL tkPeek                         ; Inspect next byte without consuming.
    JR   C,.done                        ; Finish a name that reaches end of part.
    CALL tkAlnum                        ; Classify a legal name continuation.
    JR   NC,.done                       ; Leave delimiter for next token.
    INC  B                              ; Count accepted raw byte.

; C is the maximum raw length for the selected global/private form. Comparing
; after increment detects the ninth significant byte before consuming it.

    LD   A,C                            ; Load the selected maximum raw length.
    CP   B                              ; Carry means raw length is too great.
    JR   C,.tooLong                     ; Fail before consuming the overlong byte.
    CALL tkTake                         ; Append name byte and advance.
    JR   .loop                          ; Continue until delimiter or EOF.
.done: ; Publish the complete accepted name lexeme.

; Names carry their original bytes and no decoded value.

    LD   A,B                            ; Move the raw lexeme length into A.
    LD   (tkLexLen),A                   ; Save it for token-record publication.
    LD   A,tkName                       ; Select the name token kind.
    JP   tkFinish                       ; Publish token and mark line nonempty.
.tooLong: ; Return an overlong-name lexical failure.
    LD   A,tkLong                       ; Select the name-too-long status.
    JP   tkFail                         ; Rewind and keep prior record.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Scan the entire digit-led name-continuation sequence first. This lets Intel
; suffix forms such as 0FFFFH remain one token. Malformed forms fail as
; a unit instead of splitting into a decimal token followed by a name.

tkNumber: ; Gather a digit-led candidate and decode its selected base.
    LD   B,0                            ; Start the raw candidate length at zero.
.gather: ; Consume the complete name-character run.
    CALL tkPeek                         ; Inspect the next byte without advancing.
    JR   C,.select                      ; End-of-part terminates the candidate.
    CALL tkAlnum                        ; Accept name-continuation bytes.
    JR   NC,.select                     ; Leave the first delimiter unconsumed.
    CALL tkTake                         ; Append the accepted source byte.
    INC  B                              ; Increase the raw candidate length.

; A wrapped count means 256 bytes were consumed. The buffer has 256 slots, but
; the record length has eight bits, so that lexeme cannot publish.

    JP   Z,tkErrNum                     ; Diagnose a wrapped 256-byte candidate.
    JR   .gather                        ; Continue scanning the candidate.
.select: ; Choose decimal or suffixed base.

; Save raw length, then inspect the final byte for H or B regardless of
; case. Successful tokens publish their record fields through
; tkCommit.

    LD   A,B                            ; Preserve candidate raw length.
    LD   (tkLexLen),A                   ; Save length for publication.
    PUSH BC                             ; Save length for index calculation.
    LD   HL,tkLexBuf                    ; Point at the first candidate byte.
    LD   C,B                            ; Move byte count into offset.
    LD   B,0                            ; Zero-extend it for address arithmetic.
    ADD  HL,BC                          ; Point one byte beyond the candidate.
    DEC  HL                             ; Select the candidate's final source byte.
    LD   A,(HL)                         ; Load the possible Intel suffix.
    POP  BC                             ; Restore the raw length in B.
    AND  $DF                            ; Fold suffix to uppercase.

; C selects decimal (0), binary (1) or hexadecimal (4). Bit 2 is also a cheap
; hexadecimal discriminator used by the prefix scanner below.

    LD   C,0                            ; Default to unsuffixed decimal conversion.
    CP   $48                            ; Does the final byte contain H?
    JR   Z,.hexSuff                     ; Select hexadecimal suffix conversion.
    CP   $42                            ; Does the final byte contain B?
    JR   NZ,.prepare                    ; Else convert whole run as decimal.
    INC  C                              ; Binary discriminator is one.
    JR   .suffix                        ; Exclude suffix from conversion.
.hexSuff: ; Select hexadecimal suffix conversion.
    LD   C,4                            ; Bit 2 selects hex conversion.
.suffix: ; Remove the suffix from the digit count.

; Exclude the suffix itself from the number of digits to convert.

    DEC  B                              ; Count only the digits preceding H or B.
.prepare: ; Initialise the selected conversion loop.

; Every form requires at least one digit before an optional suffix.

    LD   A,B                            ; Inspect the number of digits to convert.
    OR   A                              ; A suffix by itself is not a number.
    JP   Z,tkErrNum                     ; Reject malformed literal as a unit.
    LD   (tkDigits),A                   ; Store the remaining-digit loop count.
    LD   IX,(tkLexPtr)                  ; Start at first buffered byte.
    LD   HL,0                           ; Initialise the sixteen-bit accumulator.
    LD   A,C                            ; Load the base discriminator.
    OR   A                              ; Zero selects ordinary decimal.
    JR   Z,.decLoop                     ; Enter the decimal conversion loop.
    CP   1                              ; One selects Intel binary suffix.
    JR   Z,.binLoop                     ; Enter the binary conversion loop.
.hexLoop: ; Convert one Intel hexadecimal digit.

; Hex accumulation is value = value*16 + digit. Any high nibble already
; set before the shift proves the result would exceed 16 bits.

    LD   A,(IX+0)                       ; Load the next raw digit byte.
    CALL tkNibble                       ; Decode 0..9 or A..F to a nibble.
    JP   NC,tkErrNum                    ; Reject a non-hex byte.
    LD   E,A                            ; Preserve the decoded low nibble.
    LD   A,H                            ; Inspect the accumulator's high byte.
    AND  $F0                            ; High nibble would exceed bit 15.
    JP   NZ,tkErrBig                    ; Report exact sixteen-bit overflow.
    ADD  HL,HL                          ; Multiply the accumulator by two.
    ADD  HL,HL                          ; Multiply it by four.
    ADD  HL,HL                          ; Multiply it by eight.
    ADD  HL,HL                          ; Multiply it by sixteen.
    LD   A,L                            ; Load the cleared low nibble.
    OR   E                              ; Merge the decoded digit into bits 0..3.
    LD   L,A                            ; Publish the new accumulator low byte.
    INC  IX                             ; Advance to the next buffered digit.

; tkDigits counts unconverted digits for all three suffix/decimal loops.

    LD   A,(tkDigits)                   ; Load remaining hex digit count.
    DEC  A                              ; Account for the digit just converted.
    LD   (tkDigits),A                   ; Publish the reduced count.
    JR   NZ,.hexLoop                    ; Continue until the suffix boundary.
    JR   .done                          ; Publish the completed numeric value.
.binLoop: ; Convert one Intel binary digit.

; Binary accepts only ASCII 0 or 1. Carry from the doubling detects bit 16.

    LD   A,(IX+0)                       ; Load the next raw digit byte.
    SUB  $30                            ; Map ASCII zero and one to numeric values.
    JP   C,tkErrNum                     ; Reject bytes below ASCII zero.
    CP   2                              ; Accept only values zero or one.
    JP   NC,tkErrNum                    ; Reject all other bytes in the candidate.
    LD   E,A                            ; Preserve the decoded bit.
    ADD  HL,HL                          ; Shift the accumulator left by one.
    JP   C,tkErrBig                     ; Carry is overflow into bit 16.
    LD   A,L                            ; Load the low accumulator byte.
    OR   E                              ; Merge the decoded bit into bit zero.
    LD   L,A                            ; Publish the new accumulator value.
    INC  IX                             ; Advance to the next buffered digit.
    LD   A,(tkDigits)                   ; Load the remaining binary digit count.
    DEC  A                              ; Account for the digit just converted.
    LD   (tkDigits),A                   ; Publish the reduced count.
    JR   NZ,.binLoop                    ; Continue until the suffix boundary.
    JR   .done                          ; Publish the completed numeric value.
.decLoop: ; Convert one unsuffixed decimal digit.

; Reject a non-decimal byte anywhere before the optional suffix.

    LD   A,(IX+0)                       ; Load the next raw candidate byte.
    SUB  $30                            ; Convert ASCII zero..nine to 0..9.
    JP   C,tkErrNum                     ; Reject bytes below ASCII zero.
    CP   10                             ; Is the converted byte a decimal digit?
    JP   NC,tkErrNum                    ; Reject letters or underscore in the run.
    LD   C,A                            ; Preserve the decoded decimal digit.

; Before multiplying by ten, compare with 6553. At equality the
; final digit may be at most five, the exact 65,535 boundary.

    LD   A,H                            ; Compare accumulator with 1999H.
    CP   $19                            ; Smaller high byte is safe.
    JR   C,.decAdd                      ; Skip the remaining boundary checks.
    JP   NZ,tkErrBig                    ; Larger high byte will overflow.
    LD   A,L                            ; Compare low bytes when high match.
    CP   $99                            ; 99H is the low byte of decimal 6553.
    JR   C,.decAdd                      ; A smaller accumulator remains safe.
    JP   NZ,tkErrBig                    ; A larger accumulator must overflow.
    LD   A,C                            ; At exactly 6553, inspect the final digit.
    CP   6                              ; Digits 0..5 stay within 65535.
    JP   NC,tkErrBig                    ; Reject six through nine as overflow.
.decAdd: ; Accumulate one proved decimal digit.

; Compute value*10 + digit with three doublings, then add the saved
; value*2 and the zero-extended digit.

    LD   D,0                            ; Zero-extend the decoded digit into DE.
    LD   E,C                            ; Save digit while C becomes scratch.
    ADD  HL,HL                          ; Form value times two.
    LD   B,H                            ; Save the high byte of value times two.
    LD   C,L                            ; Save its low byte.
    ADD  HL,HL                          ; Form value times four.
    ADD  HL,HL                          ; Form value times eight.
    ADD  HL,BC                          ; Add value*2 to reach value*10.
    ADD  HL,DE                          ; Add the decoded decimal digit.
    INC  IX                             ; Advance to next buffered byte.
    LD   A,(tkDigits)                   ; Load the remaining decimal digit count.
    DEC  A                              ; Account for the digit just converted.
    LD   (tkDigits),A                   ; Publish the reduced count.
    JR   NZ,.decLoop                    ; Continue through the complete raw run.
.done: ; Publish a successfully decoded numeric value.

; A successful numeric token publishes its decoded 16-bit value.

    LD   (tkValue),HL                   ; Save the decoded sixteen-bit value.
tkPutNum: ; Publish a numeric token from prepared fields.
    LD   A,tkNum                        ; Select the numeric token kind.
    JP   tkFinish                       ; Commit and mark line nonempty.

;@ROUTINE IN BC OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Scan a prefix form. Entry B already counts '$' or '%'. C is 4 for hex and 1
; for binary. HL accumulates the decoded value and tkDigits records whether at
; least one digit followed the prefix.

tkRadix: ; Decode the digits following a dollar or percent prefix.
    LD   HL,0                           ; Initialise the sixteen-bit accumulator.
    XOR  A                              ; Construct the no-digit-seen state.
    LD   (tkDigits),A                   ; Clear the prefix digit-presence flag.
.loop: ; Accumulate one prefixed digit.

; Preserve the accumulator across PEEK, which uses HL for the source cursor.

    PUSH HL                             ; Save accumulator across source read.
    CALL tkPeek                         ; Inspect the next source byte.
    POP  HL                             ; Restore accumulator, preserving flags.
    JR   C,.eof                         ; Finish or reject a prefix at end of part.
    LD   D,A                            ; Save byte for delimiter check.

; Bit 2 distinguishes hexadecimal from binary without another base constant.

    BIT  2,C                            ; Is this the hexadecimal prefix path?
    JR   Z,.binary                      ; Decode an Atom binary digit when clear.
    CALL tkNibble                       ; Decode a hexadecimal nibble.
    JR   NC,.nonDigit                   ; Non-digit ends the candidate.
    JR   .digit                         ; Accumulate the valid nibble.
.binary: ; Decode an Atom binary digit.
    SUB  $30                            ; Map ASCII zero and one to 0 and 1.
    JR   C,.nonDigit                    ; Byte below zero ends candidate.
    CP   2                              ; Accept only the two binary digit values.
    JR   NC,.nonDigit                   ; Any other byte terminates the candidate.
.digit: ; Accumulate one normalised digit from A.
    LD   E,A                            ; Save digit during shift.

; Hex shifts four places after checking its high nibble. Binary shifts once
; and uses carry as the 17th-bit overflow indication.

    BIT  2,C                            ; Select hexadecimal or binary shift width.
    JR   Z,.binShift                    ; Binary requires one left shift.
    LD   A,H                            ; Inspect the accumulator's high byte.
    AND  $F0                            ; High nibble would overflow.
    JR   NZ,tkErrBig                    ; Report a value above sixteen bits.
    ADD  HL,HL                          ; Multiply hexadecimal accumulation by two.
    ADD  HL,HL                          ; Multiply it by four.
    ADD  HL,HL                          ; Multiply it by eight.
    ADD  HL,HL                          ; Multiply it by sixteen.
    JR   .merge                         ; Merge the decoded hexadecimal nibble.
.binShift: ; Shift binary accumulation by one bit.
    ADD  HL,HL                          ; Make room for the new low bit.
    JR   C,tkErrBig                     ; Carry is overflow into bit 16.
.merge: ; Merge the normalised digit into the low bits.

; E is a digit, so OR adds it into the cleared low bits.

    LD   A,L                            ; Load the accumulator's cleared low bits.
    OR   E                              ; Merge the normalised digit.
    LD   L,A                            ; Publish the updated accumulator.
    PUSH HL                             ; Preserve it across source consumption.
    CALL tkTake                         ; Append accepted digit and advance.
    POP  HL                             ; Restore the accumulator.
    INC  B                              ; Increase the raw prefix-token length.

; Reject byte 256 because its wrapped count cannot be represented in the token
; record, even though that byte itself occupied the buffer's final slot.

    JR   Z,tkErrNum                     ; Reject a wrapped 256-byte raw token.
    LD   A,1                            ; Construct the digit-seen state.
    LD   (tkDigits),A                   ; Mark at least one prefix digit.
    JR   .loop                          ; Continue until delimiter or EOF.
.nonDigit: ; Validate first non-digit.

; A prefix needs a digit. If the next byte could be
; part of a name, reject the complete token rather than silently splitting it.

    LD   A,(tkDigits)                   ; Has the prefix accepted any digit?
    OR   A                              ; Zero means bare '$' or '%'.
    JR   Z,tkErrNum                     ; Reject the bare prefix.
    LD   A,D                            ; Restore the first non-digit byte.
    CALL tkAlnum                        ; Could it continue a digit-led name?
    JR   C,tkErrNum                     ; Reject ambiguous run as a unit.
    JR   .done                          ; Publish the complete prefix value.
.eof: ; Validate a prefix candidate at end of part.
    LD   A,(tkDigits)                   ; Inspect whether any digit was accepted.
    OR   A                              ; A bare prefix remains invalid at EOF.
    JR   Z,tkErrNum                     ; Diagnose it as malformed numeric input.
.done: ; Save a complete prefix numeric value.
    LD   (tkValue),HL                   ; Save decoded sixteen-bit value.
tkPutLen: ; Publish number with raw length B.

; Character literals use this path after placing their decoded byte in
; tkValue. B supplies the raw lexeme length in both cases.

    LD   A,B                            ; Move the raw lexeme length into A.
    LD   (tkLexLen),A                   ; Save it in the tentative token fields.
    JR   tkPutNum                       ; Publish the numeric token.
tkErrNum: ; Return malformed-numeric status.

; Invalid syntax and overflow are distinct diagnostics.

    LD   A,tkBadNum                     ; Select invalid numeric syntax.
    JP   tkFail                         ; Rewind and keep prior record.
tkErrBig: ; Return numeric-overflow status.
    LD   A,tkNumBig                     ; Select sixteen-bit overflow.
    JP   tkFail                         ; Rewind and keep prior record.
