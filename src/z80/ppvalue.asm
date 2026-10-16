;@ROUTINE IN A OUT HL,CARRY CLOBBERS A,BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Convert one token to a 16-bit value or look it up in the bounded table.

ppEval: ; Decode a numeric literal or existing definition.
    LD   A,(ppTokLen)                               ; Empty values cannot reach the parser.
    OR   A                                          ; Keep a defensive check at this boundary.
    JP   Z,ppFail                                   ; Return carry for an empty value.
    LD   A,(ppToken)                                ; Inspect the first normalised byte.
    CP   'A'                                        ; A leading letter selects a definition name.
    JR   C,.notName                                 ; Numbers start with a digit, '$' or '%'.
    CP   'Z'+1                                      ; Bound the first byte to ASCII letters.
    JP   C,.name                                    ; Resolve a case-folded preprocessor name.
.notName: ; Select radix from a numeric prefix or suffix.
    CP   '$'                                        ; A dollar prefix selects hexadecimal.
    JR   Z,.dollar                                  ; Skip the prefix before digit parsing.
    CP   '%'                                        ; A percent prefix selects binary.
    JR   Z,.percent                                 ; The host directive itself began earlier.
    CP   '0'                                        ; Decimal and Intel suffixes start with digits.
    JP   C,ppFail                                   ; Reject punctuation outside the numeric grammar.
    CP   '9'+1                                      ; Digits stop before colon and alphabetic bytes.
    JP   NC,ppFail                                  ; Reject a nonnumeric leading byte.
    LD   A,10                                       ; Unsuffixed digits use decimal.
    LD   (ppRadix),A                                ; Store decimal as the default radix.
    XOR  A                                          ; Unsuffixed values begin at token byte zero.
    LD   (ppFirst),A                                ; Record the first digit's index.
    LD   A,(ppTokLen)                               ; Decimal consumes the complete token.
    LD   (ppDigits),A                               ; The digit loop checks each byte's range.
    DEC  A                                          ; Address the final token byte.
    LD   C,A                                        ; Use it as a short buffer index.
    LD   B,0                                        ; Zero-extend the token index.
    LD   HL,ppToken                                 ; Select the normalised token.
    ADD  HL,BC                                      ; Inspect a possible Intel suffix.
    LD   A,(HL)                                     ; Read the final token byte.
    CP   'H'                                        ; Intel hexadecimal ends in H.
    JR   Z,.suffixH                                 ; Parse preceding digits as hexadecimal.
    CP   'B'                                        ; Intel binary ends in B.
    JR   Z,.suffixB                                 ; Parse its preceding digits in base two.
    JR   .number                                    ; Keep decimal when neither suffix is present.
.dollar: ; Parse hexadecimal digits after a dollar prefix.
    LD   A,16                                       ; Dollar-prefixed source uses hexadecimal.
    LD   (ppRadix),A                                ; Store its radix.
    LD   A,1                                        ; Skip the leading dollar sign.
    LD   (ppFirst),A                                ; Begin digits immediately after '$'.
    LD   A,(ppTokLen)                               ; Count all bytes in the token.
    DEC  A                                          ; The prefix is not a digit.
    LD   (ppDigits),A                               ; Parse every remaining hexadecimal digit.
    JR   .number                                    ; Convert and range-check the value.
.percent: ; Parse binary digits after a percent prefix.
    LD   A,2                                        ; Percent-prefixed source uses binary.
    LD   (ppRadix),A                                ; Store its radix.
    LD   A,1                                        ; Skip the leading percent sign.
    LD   (ppFirst),A                                ; Begin at the first binary digit.
    LD   A,(ppTokLen)                               ; Count all bytes in the token.
    DEC  A                                          ; The prefix is not a digit.
    LD   (ppDigits),A                               ; Parse the remaining binary digits.
    JR   .number                                    ; Convert and range-check the value.
.suffixH: ; Select radix sixteen for an H suffix.
    LD   A,16                                       ; H suffix selects hexadecimal.
    LD   (ppRadix),A                                ; Replace the decimal default.
    JR   .suffix                                    ; Exclude the suffix from the digits.
.suffixB: ; Select radix two for a B suffix.
    LD   A,2                                        ; B suffix selects binary.
    LD   (ppRadix),A                                ; Replace the decimal default.
.suffix: ; Exclude the suffix from the digit count.
    LD   A,(ppTokLen)                               ; The suffix is one byte.
    DEC  A                                          ; Count only the preceding digits.
    LD   (ppDigits),A                               ; Keep the existing zero start index.
.number: ; Initialise bounded numeric accumulation.
    LD   A,(ppDigits)                               ; Reject a prefix or suffix without digits.
    OR   A                                          ; Zero digits cannot encode a number.
    JP   Z,ppFail                                   ; A token consisting of H or B is a name instead.
    XOR  A                                          ; Begin numeric accumulation at zero.
    LD   HL,0                                       ; HL is the unsigned 16-bit result.
    LD   (ppValue),HL                               ; Keep the accumulator across helper calls.
    XOR  A                                          ; The digit index begins at zero.
    LD   (ppIndex),A                                ; Count digits, not source positions.
.loop: ; Convert and accumulate the next numeric digit.
    LD   A,(ppIndex)                                ; Read the next digit's token index.
    LD   C,A                                        ; Convert it to a pointer displacement.
    LD   B,0                                        ; The index fits in one byte.
    LD   A,(ppFirst)                                ; Include a possible '$' or '%' prefix.
    ADD  A,C                                        ; Form the complete token position.
    LD   C,A                                        ; Use the sum as the low pointer offset.
    LD   HL,ppToken                                 ; Address the token's first byte.
    ADD  HL,BC                                      ; Select the next numeric digit.
    LD   A,(HL)                                     ; Read its normalised ASCII byte.
    CALL .digit                                     ; Convert it under the selected radix.
    JP   C,ppFail                                   ; Reject letters or digits outside the radix.
    LD   (ppTemp),A                                 ; Save digit during multiply.
    LD   HL,(ppValue)                               ; Load the accumulated prefix value.
    LD   A,(ppRadix)                                ; Select the radix's multiply operation.
    CP   2                                          ; Binary values double before adding each digit.
    JR   Z,.double                                  ; Use one checked shift.
    CP   16                                         ; Hexadecimal values multiply by sixteen.
    JR   Z,.times16                                 ; Use four checked shifts.
    CALL .tenfold                                   ; Decimal values multiply by ten.
    JP   C,ppFail                                   ; Reject an intermediate value above $FFFF.
    JR   .add                                       ; Add the already-validated decimal digit.
.double: ; Multiply a binary prefix by two.
    ADD  HL,HL                                      ; Shift the binary prefix left by one bit.
    JP   C,ppFail                                   ; Reject a high bit that would be lost.
    JR   .add                                       ; Add the next binary digit.
.times16: ; Multiply a hexadecimal prefix by sixteen.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by one bit.
    JP   C,ppFail                                   ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by two bits.
    JP   C,ppFail                                   ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by three bits.
    JP   C,ppFail                                   ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Complete the four-bit hexadecimal shift.
    JP   C,ppFail                                   ; Reject a value outside the 16-bit range.
.add: ; Add the validated digit to the prefix.
    LD   A,L                                        ; Start the addition with the low byte.
    LD   C,A                                        ; Keep that byte while loading the new digit.
    LD   A,(ppTemp)                                 ; Read the validated digit value (0..15).
    ADD  A,C                                        ; Add the digit to the low byte.
    LD   L,A                                        ; Store the low result byte.
    JR   NC,.next                                   ; No carry leaves the high byte unchanged.
    INC  H                                          ; Carry advances the high byte once.
    JP   Z,ppFail                                   ; A wrapped high byte means value overflow.
.next: ; Advance the checked numeric accumulator.
    LD   (ppValue),HL                               ; Publish this fully checked prefix value.
    LD   HL,ppIndex                                 ; Address the digit index.
    INC  (HL)                                       ; Count the digit just consumed.
    LD   A,(ppIndex)                                ; Compare with the total digit count.
    LD   B,A                                        ; Keep the current index in B.
    LD   A,(ppDigits)                               ; Load the number of remaining digits.
    CP   B                                          ; Continue while the index is smaller.
    JR   NZ,.loop                                   ; Parse the next digit.
    LD   HL,(ppValue)                               ; Return the final 16-bit value.
    XOR  A                                          ; Clear carry for a successful conversion.
    RET                                             ; HL holds the result.
.name: ; Resolve a definition under current branch activity.
    CALL ppValid                                    ; Do not overwrite a staged DEFINE name.
    JP   C,ppFail                                   ; Reject malformed or overlong identifiers.
    CALL ppFind                                     ; Resolve the prior entry-header definition.
    RET  NC                                         ; A found definition returns its value in HL.
    LD   A,(ppActive)                               ; Ignore unknown names in inactive branches.
    OR   A                                          ; Active source requires an existing definition.
    JP   NZ,ppFail                                  ; Reject a missing name in an active condition.
    LD   HL,0                                       ; Inactive nested conditions select false.
    XOR  A                                          ; Preserve that non-error result.
    RET                                             ; The outer inactive frame remains decisive.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Convert A from the selected base into a digit value in the range 0..15.

.digit: ; Convert ASCII to a bounded digit value.
    CP   '0'                                        ; Digits begin at ASCII zero.
    JR   C,.noDigit                                 ; Reject punctuation below the digit range.
    CP   '9'+1                                      ; Decimal digits end before uppercase letters.
    JR   C,.decimal                                 ; Convert '0' through '9'.
    CP   'A'                                        ; Hexadecimal letters start at A.
    JR   C,.noDigit                                 ; Reject punctuation between digits and letters.
    CP   'F'+1                                      ; Only A through F fit a hexadecimal nibble.
    JR   NC,.noDigit                                ; Reject letters beyond F.
    SUB  'A'-10                                     ; Convert A..F into 10..15.
    JR   .radix                                     ; Compare the value with the selected base.
.decimal: ; Convert an ASCII decimal digit.
    SUB  '0'                                        ; Convert ASCII digit to its numeric value.
.radix: ; Require the digit to be below the radix.
    LD   C,A                                        ; Save the converted value during the radix check.
    LD   A,(ppRadix)                                ; Binary, decimal or hexadecimal limit.
    LD   B,A                                        ; Keep the radix while comparing the digit.
    LD   A,C                                        ; Read the converted digit value.
    CP   B                                          ; Carry means this digit is below the radix.
    JR   NC,.noDigit                                ; Reject a digit equal to or above the radix.
    LD   A,C                                        ; Return the numeric digit.
    OR   A                                          ; Clear carry without changing its value.
    RET                                             ; A contains the accepted digit.
.noDigit: ; Reject a character outside the selected radix.
    SCF                                             ; Carry rejects the token under its radix.
    RET                                             ; The numeric parser selects a directive error.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Compute value*10 as value*8+value*2 with overflow checks at each addition.

.tenfold: ; Multiply a decimal prefix by ten with overflow checks.
    PUSH HL                                         ; Preserve the original value for the final sum.
    ADD  HL,HL                                      ; Form value*2.
    JR   C,.popOne                                  ; Reject overflow. undo high word.
    PUSH HL                                         ; Save value*2 while constructing value*8.
    ADD  HL,HL                                      ; Form value*4.
    JR   C,.popTwo                                  ; Remove both saved words.
    ADD  HL,HL                                      ; Form value*8.
    JR   C,.popTwo                                  ; Remove both saved words.
    POP  DE                                         ; Recover value*2 into DE.
    ADD  HL,DE                                      ; Form value*10.
    JR   C,.popOne                                  ; Reject a sum above $FFFF.
    POP  DE                                         ; Discard the preserved original value.
    OR   A                                          ; Return carry clear with the product in HL.
    RET                                             ; The caller adds its next decimal digit.
.popTwo: ; Discard the second saved multiplication operand.
    POP  DE                                         ; Remove the saved value*2 from the stack.
.popOne: ; Discard the first saved multiplication operand.
    POP  DE                                         ; Remove the saved original value.
    SCF                                             ; Carry signals an out-of-range decimal prefix.
    RET                                             ; Keep the caller's stack balanced.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find the token's uppercase name in the fixed twenty-byte definition records.

ppFind: ; Find a name in twenty-byte definition records.
    LD   A,(ppTokLen)                               ; Check length against the name field.
    CP   ppWidth+1                                  ; Reject names wider than the fixed field.
    JR   NC,.missing                                ; Treat an overlong name as missing.
    LD   A,(ppDefCnt)                               ; A zero count means the table is empty.
    OR   A                                          ; Avoid an IX walk when no values exist.
    JR   Z,.missing                                 ; Let the caller decide if missing is legal.
    LD   B,A                                        ; Visit every preceding definition.
    LD   IX,ppDefBeg                                ; Address the first fixed-width record.
.loop: ; Compare each occupied definition record.
    LD   A,(IX+0)                                   ; Read the stored name length.
    LD   C,A                                        ; Keep it while loading the query length.
    LD   A,(ppTokLen)                               ; Read the current query's length.
    CP   C                                          ; Different lengths cannot match.
    JR   NZ,.next                                   ; Try the next definition record.
    PUSH IX                                         ; Save the record base across name comparison.
    INC  IX                                         ; The first name byte follows the length field.
    LD   DE,ppToken                                 ; Compare with the normalised query name.
    LD   A,(ppTokLen)                               ; Match exactly the declared name length.
    LD   C,A                                        ; Use C as the character count.
.compare: ; Compare every significant uppercase name byte.
    LD   A,(DE)                                     ; Read one requested name character.
    CP   (IX+0)                                     ; Compare it with this record's name byte.
    JR   NZ,.mismatch                               ; Continue searching on mismatch.
    INC  DE                                         ; Advance through the query name.
    INC  IX                                         ; Advance through the stored name.
    DEC  C                                          ; Count this matching character.
    JR   NZ,.compare                                ; Compare the complete name.
    POP  IX                                         ; Restore the matching record's base.
    LD   L,(IX+18)                                  ; Read the definition value's low byte.
    LD   H,(IX+19)                                  ; Complete its unsigned 16-bit value.
    OR   A                                          ; Clear carry to report a successful lookup.
    RET                                             ; Return the value in HL.
.mismatch: ; Restore the record pointer after mismatch.
    POP  IX                                         ; Restore the record pointer after mismatch.
.next: ; Advance to the next definition record.
    LD   DE,ppRecLen                                ; Advance by one full definition record.
    ADD  IX,DE                                      ; Advance to the next definition.
    DJNZ .loop                                      ; Stop after the published record count.
.missing: ; Return missing-definition status.
    SCF                                             ; Carry tells the caller no value was found.
    RET                                             ; HL has no meaning on this path.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a 1-17 character name and copy it to ppName.

ppStage: ; Validate and stage the definition name.
    LD   A,(ppTokLen)                               ; Read the complete candidate length.
    OR   A                                          ; Empty names are invalid.
    JR   Z,ppBadId                                  ; Reject an absent identifier.
    CP   ppWidth+1                                  ; The name field holds at most 17 characters.
    JR   NC,ppBadId                                 ; Reject anything wider than its storage field.
    LD   (ppLength),A                               ; Retain the length for lookup and insertion.
    LD   HL,ppName                                  ; Fill unused name bytes with spaces.
    LD   B,ppWidth                                  ; Compare the complete padded name field.
    LD   A,' '                                      ; Space padding makes comparisons deterministic.
.padLoop: ; Space-fill the complete staged name field.
    LD   (HL),A                                     ; Clear one staged name byte.
    INC  HL                                         ; Advance to the next name position.
    DJNZ .padLoop                                   ; Fill the full fixed-width field before copying.
    LD   A,(ppLength)                               ; Reload the candidate's length.
    LD   B,A                                        ; Use B to count its characters.
    LD   C,0                                        ; C distinguishes first character from the rest.
    LD   DE,ppToken                                 ; Start at the normalised candidate.
    LD   HL,ppName                                  ; Store its canonical bytes separately.
.charLoop: ; Validate and copy each staged character.
    LD   A,(DE)                                     ; Read the next uppercase character.
    LD   (ppTemp),A                                 ; Save the byte without changing DE.
    LD   A,C                                        ; Zero marks the first character.
    OR   A                                          ; The first character must be a letter.
    LD   A,(ppTemp)                                 ; Restore the candidate byte.
    JR   NZ,.later                                  ; Later bytes may include digits and underscore.
    CP   'A'                                        ; Test the inclusive first-letter lower bound.
    JR   C,ppBadId                                  ; Reject leading digits and punctuation.
    CP   'Z'+1                                      ; Test the exclusive first-letter upper bound.
    JR   NC,ppBadId                                 ; Reject a leading underscore.
    JR   .store                                     ; A valid letter begins the staged name.
.later: ; Check characters after the initial letter.
    CP   'A'                                        ; A later uppercase letter is valid.
    JR   C,.notAlpha                                ; Check the other allowed classes.
    CP   'Z'+1                                      ; Bound the letter range.
    JR   C,.store                                   ; Store a valid later letter.
.notAlpha: ; Check digits or underscore after the initial letter.
    CP   '0'                                        ; Digits are permitted after the first byte.
    JR   C,.underBar                                ; Check underscore before other punctuation.
    CP   '9'+1                                      ; Bound the digit range.
    JR   C,.store                                   ; Store a valid later digit.
.underBar: ; Accept underscore as the remaining name character.
    CP   '_'                                        ; Underscore is allowed after the first byte.
    JR   NZ,ppBadId                                 ; Reject all other punctuation.
.store: ; Copy the accepted name character.
    LD   (HL),A                                     ; Store this character in the padded name.
    INC  HL                                         ; Advance the name destination.
    INC  DE                                         ; Advance the source token.
    INC  C                                          ; Mark subsequent characters as noninitial.
    DJNZ .charLoop                                  ; Validate every remaining character.
    LD   A,(ppLength)                               ; Return the accepted name length.
    OR   A                                          ; Clear carry on successful validation.
    RET                                             ; ppName now holds uppercase padded bytes.
ppBadId: ; Reject an invalid identifier.
    SCF                                             ; Carry marks invalid name syntax or length.
    RET                                             ; The source profile reports a directive error.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a lookup token without replacing the separately staged DEFINE name.

ppValid: ; Validate a lookup token without changing staged name.
    LD   A,(ppTokLen)                               ; Read the complete query token length.
    OR   A                                          ; Empty identifiers cannot be looked up.
    JR   Z,ppBadId                                  ; Reuse the common carry-set result.
    CP   ppWidth+1                                  ; The fixed record bounds every lookup name.
    JR   NC,ppBadId                                 ; Reject a name the definition table cannot hold.
    LD   B,A                                        ; Count every validated token byte.
    LD   C,0                                        ; Zero identifies the leading character.
    LD   DE,ppToken                                 ; Begin at the uppercase token buffer.
.loop: ; Validate each uppercase lookup character.
    LD   A,(DE)                                     ; Read one candidate character.
    LD   (ppTemp),A                                 ; Preserve it without changing the DE cursor.
    LD   A,C                                        ; Check whether this is the first character.
    OR   A                                          ; A nonzero count permits more character classes.
    LD   A,(ppTemp)                                 ; Reload the byte for its range checks.
    JR   NZ,.later                                  ; Later bytes allow digits and underscore.
    CP   'A'                                        ; A name must start with an uppercase letter.
    JR   C,ppBadId                                  ; Reject an invalid first character.
    CP   'Z'+1                                      ; Test the exclusive end of the letter range.
    JR   NC,ppBadId                                 ; Reject an initial underscore.
    JR   .next                                      ; The first letter passed validation.
.later: ; Check subsequent lookup characters.
    CP   'A'                                        ; Test the later-letter range first.
    JR   C,.notAlpha                                ; Check digits and underscore below.
    CP   'Z'+1                                      ; Bound the inclusive uppercase letters.
    JR   C,.next                                    ; Advance past a valid later letter.
.notAlpha: ; Check digits or underscore in the lookup name.
    CP   '0'                                        ; Decimal digits may follow the initial letter.
    JR   C,.underBar                                ; Check underscore before punctuation.
    CP   '9'+1                                      ; Bound the decimal digit range.
    JR   C,.next                                    ; Accept a digit after the first character.
.underBar: ; Accept underscore in the lookup name.
    CP   '_'                                        ; Underscore is the only other allowed byte.
    JR   NZ,ppBadId                                 ; Reject invalid identifier punctuation.
.next: ; Advance after a valid lookup character.
    INC  DE                                         ; Advance to the following token character.
    INC  C                                          ; Mark all remaining bytes as noninitial.
    DJNZ .loop                                      ; Validate the complete identifier.
    XOR  A                                          ; Clear carry for a valid lookup name.
    RET                                             ; Leave token bytes intact for table lookup.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Copy a staged definition name to the query buffer for duplicate detection.

ppCopy: ; Copy the staged name for duplicate lookup.
    LD   A,(ppLength)                               ; Keep the name's significant length.
    LD   (ppTokLen),A                               ; Configure the generic lookup routine.
    LD   HL,ppName                                  ; Read the staged padded name.
    LD   DE,ppToken                                 ; Write its bytes into the query buffer.
    LD   B,ppWidth                                  ; Copy the complete canonical field.
.loop: ; Copy every byte of the padded name field.
    LD   A,(HL)                                     ; Read one uppercase name or padding byte.
    LD   (DE),A                                     ; Publish it in the lookup buffer.
    INC  HL                                         ; Advance the staged source.
    INC  DE                                         ; Advance the query destination.
    DJNZ .loop                                      ; Copy the complete padded name.
    RET                                             ; The value token is no longer needed.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Append one validated staged name and value to the bounded definition table.

ppStore: ; Append a complete name-and-value record.
    LD   A,(ppDefCnt)                               ; Read the number of occupied records.
    CP   ppDefMax                                   ; The table is deliberately finite on CP/M.
    JP   NC,ppFail                                  ; Reject a thirty-third distinct definition.
    LD   B,A                                        ; Advance over the occupied fixed-width records.
    LD   IX,ppDefBeg                                ; Start with the first slot.
    OR   A                                          ; A zero count already selects that slot.
    JR   Z,.slot                                    ; The first record needs no pointer step.
.recLoop: ; Skip each occupied definition record.
    LD   DE,ppRecLen                                ; Advance by one complete record.
    ADD  IX,DE                                      ; Select the following definition slot.
    DJNZ .recLoop                                   ; Skip every occupied record.
.slot: ; Write the next unused definition slot.
    LD   A,(ppLength)                               ; Store the exact significant-name length.
    LD   (IX+0),A                                   ; Record byte zero is the name length.
    INC  IX                                         ; Name bytes begin at record offset one.
    LD   HL,ppName                                  ; Read the staged uppercase field.
    LD   B,ppWidth                                  ; Copy every name and padding position.
.nameLoop: ; Copy the fixed-width uppercase name field.
    LD   A,(HL)                                     ; Read a name character or its space padding.
    LD   (IX+0),A                                   ; Store it in the current record position.
    INC  HL                                         ; Advance through the staged name.
    INC  IX                                         ; Advance through the record name field.
    DJNZ .nameLoop                                  ; Copy the complete fixed-width field.
    LD   HL,(ppValue)                               ; Load the previously validated value.
    LD   (IX+0),L                                   ; Store its low byte at record offset eighteen.
    LD   (IX+1),H                                   ; Store its high byte at record offset nineteen.
    LD   HL,ppDefCnt                                ; Address the number of published definitions.
    INC  (HL)                                       ; Make the complete record visible to IF lookup.
    XOR  A                                          ; Return success with carry clear.
    RET                                             ; Preserve every existing definition.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Filter the source byte at offset HL. The core reads each byte once, in
; order, so the filter is a state machine over the stream. It tracks line
; starts and lines, turns a line-leading '%' into ';' while capturing the
; directive, and applies the directive at the line's end. Inactive text
; becomes spaces. Every line ending and byte offset is preserved. Carry with
; A=0 ends the part: at an include, or after a failure recorded for tkOpen.

ppFilter: ; Filter one source byte read in order.

; Most bytes are ordinary text in the middle of an active line. Return those
; at once, before any state is saved.

    CP   13                                         ; CR ends a line.
    JR   Z,.full                                    ; Line ends take the full path.
    CP   10                                         ; LF ends a line too.
    JR   Z,.full                                    ; Take the full path.
    LD   E,A                                        ; Keep the byte.
    LD   A,(ppMode)                                 ; At a line start or in a directive?
    OR   A                                          ; Zero means neither.
    JR   NZ,.restore                                ; Take the full path.
    LD   A,(ppActive)                               ; Is this branch active?
    OR   A                                          ; Zero means inactive text.
    LD   A,E                                        ; Recover the byte.
    JR   Z,.space                                   ; Mask inactive text.
    OR   A                                          ; Clear carry and classify zero.
    RET                                             ; Return the source byte.
.space: ; Return a space for inactive text.
    LD   A,' '                                      ; Inactive source becomes whitespace.
    OR   A                                          ; Clear carry.
    RET                                             ; Its offset and column are kept.
.restore: ; Recover the byte for the full path.
    LD   A,E                                        ; Recover the byte.
.full: ; Save state and filter the byte in full.
    PUSH BC                                         ; The source-provider boundary preserves BC.
    PUSH IX                                         ; Definition lookup uses IX internally.
    PUSH IY                                         ; Include names are parsed through IY.
    LD   C,A                                        ; Keep the byte in C.
    LD   (ppPos),HL                                 ; Keep its offset.
    CP   13                                         ; CR?
    JP   Z,.eol                                     ; End the line.
    CP   10                                         ; LF?
    JP   Z,.eol                                     ; End the line.
    XOR  A                                          ; Any other byte ends a CRLF pair.
    LD   (ppLastCr),A                               ; The previous byte is no longer CR.
    LD   A,(ppMode)                                 ; Inspect the line state.
    BIT  1,A                                        ; Capturing a directive?
    JR   NZ,.capture                                ; Keep its bytes.
    BIT  0,A                                        ; At the line's start?
    JR   Z,.text                                    ; No: ordinary text.
    LD   A,C                                        ; Leading whitespace keeps the line start.
    CP   ' '                                        ; A space?
    JR   Z,.text                                    ; Still at the start.
    CP   9                                          ; A tab?
    JR   Z,.text                                    ; Still at the start.
    LD   A,(ppMode)                                 ; The line's first text has arrived.
    AND  $FE                                        ; Clear the line-start bit.
    LD   (ppMode),A                                 ; Later bytes are mid-line.
    LD   A,C                                        ; Recover the byte.
    CP   '%'                                        ; A directive?
    JR   Z,.start                                   ; Capture it.
    CP   ';'                                        ; A comment line?
    JR   Z,.text                                    ; It leaves the header open.
    LD   A,(ppActive)                               ; Inactive text leaves it open too.
    OR   A                                          ; Zero means inactive.
    JR   Z,.text                                    ; Mask it.
    LD   A,(incHead)                                ; Is the header still open?
    OR   A                                          ; Zero means it closed earlier.
    JR   Z,.text                                    ; Return the byte.

; Ordinary source closes the header. An IF that contains an include must
; close inside the header, so no such IF may still be open here.

    PUSH BC                                         ; Keep the byte.
    CALL ppScope                                    ; Check the open IF frames.
    POP  BC                                         ; Recover it.
    JP   C,.badHead                                 ; Ordinary source inside one.
    XOR  A                                          ; Close the header.
    LD   (incHead),A                                ; Later includes are rejected.
    LD   (ppDefOk),A                                ; Later definitions are too.
.text: ; Return active text or mask inactive text.
    LD   A,(ppActive)                               ; Is this branch active?
    OR   A                                          ; Zero means inactive.
    LD   A,C                                        ; Recover the byte.
    JP   NZ,.done                                   ; Return active text unchanged.
    LD   A,' '                                      ; Inactive text becomes a space.
    JP   .done                                      ; Its offset is kept.
.start: ; Begin capturing a directive.
    LD   A,(ppMode)                                 ; Mark the directive.
    OR   2                                          ; Bit 1 captures until the line ends.
    LD   (ppMode),A                                 ; Keep the mode.
    XOR  A                                          ; Nothing is captured yet.
    LD   (ppCapLen),A                               ; Start at the buffer's first byte.
    LD   HL,(ppPos)                                 ; Remember where it starts.
    LD   (ppDirAt),HL                               ; Failures are reported here.
    LD   HL,(ppLine)                                ; And on this line.
    LD   (ppDirLn),HL                               ; Keep it.
    LD   A,';'                                      ; Atom reads the directive as a comment.
    JP   .done                                      ; Return it.
.capture: ; Keep one directive byte.
    LD   A,(ppCapLen)                               ; Bytes captured so far.
    CP   $FE                                        ; Overflowed, or ended at a comment?
    JR   NC,.text                                   ; Then this byte is not kept.
    LD   E,A                                        ; Index the next free byte.
    LD   D,0                                        ; Widen the index.
    LD   HL,ppLnBuf                                 ; Address the buffer.
    ADD  HL,DE                                      ; Address the free byte.
    LD   A,C                                        ; Recover the byte.
    CP   '"'                                        ; A quote opens or closes a name?
    JR   NZ,.semi                                   ; No: check for a comment.
    LD   A,(ppMode)                                 ; Bit 2 marks a quoted name.
    XOR  4                                          ; Enter or leave it.
    LD   (ppMode),A                                 ; Keep the mode.
    LD   A,C                                        ; Recover the quote.
    JR   .keep                                      ; Keep it.
.semi: ; A semicolon outside quotes starts a comment.
    CP   ';'                                        ; Does a comment start here?
    JR   NZ,.keep                                   ; No: keep the byte.
    LD   A,(ppMode)                                 ; Inside a quoted name?
    BIT  2,A                                        ; Bit 2 means yes.
    LD   A,C                                        ; Recover the semicolon.
    JR   Z,.close                                   ; No: end the directive before it.
.keep: ; Keep one byte of the directive.
    LD   (HL),A                                     ; Keep the byte.
    LD   A,E                                        ; Count it.
    INC  A                                          ; One more byte.
    CP   ppLnMax                                    ; Is the buffer full?
    JR   C,.kept                                    ; No: keep the count.
    LD   A,$FE                                      ; Mark the overflow.
.kept: ; Record the count.
    LD   (ppCapLen),A                               ; Keep it.
    JR   .text                                      ; Return the byte.
.close: ; End the directive at its comment.
    LD   (HL),13                                    ; End it with CR.
    LD   A,$FF                                      ; The comment is not kept.
    LD   (ppCapLen),A                               ; Mark the directive complete.
    JR   .text                                      ; Return the semicolon.
.eol: ; Finish a line.
    LD   A,(ppMode)                                 ; Was a directive captured?
    BIT  1,A                                        ; Bit 1 means yes.
    JR   Z,.count                                   ; No: count the line.
    PUSH BC                                         ; Keep the line ending.
    CALL ppApply                                    ; Apply the directive.
    POP  BC                                         ; Recover the line ending.
    JR   C,.bad                                     ; A malformed directive ends the part.
    OR   A                                          ; Does an include end it here?
    JR   NZ,.cut                                    ; Yes: the parent resumes at this byte.
.count: ; Count CR, LF or CRLF as one line ending.
    LD   A,C                                        ; Recover the line ending.
    CP   13                                         ; CR always ends a line.
    JR   Z,.cr                                      ; Count it.
    LD   A,(ppLastCr)                               ; Does this LF complete CRLF?
    OR   A                                          ; Nonzero means it does.
    JR   NZ,.lf                                     ; It was counted at the CR.
    CALL .line                                      ; Count a lone LF.
.lf: ; Forget the CR.
    XOR  A                                          ; The pair is complete.
    LD   (ppLastCr),A                               ; Clear the CR state.
    JR   .bol                                       ; A new line starts.
.cr: ; Count a CR.
    CALL .line                                      ; Count it.
    LD   A,1                                        ; Remember it for a following LF.
    LD   (ppLastCr),A                               ; Keep the CR state.
.bol: ; Start the next line.
    LD   A,1                                        ; The directive is finished.
    LD   (ppMode),A                                 ; The next byte starts a line.
    LD   A,C                                        ; Return the line ending unchanged.
.done: ; Restore caller state and return the byte.
    POP  IY                                         ; Restore the caller's second index register.
    POP  IX                                         ; Restore the caller's index register.
    POP  BC                                         ; Restore the parser's byte and loop state.
    OR   A                                          ; Clear carry and classify a zero byte.
    RET                                             ; Return the filtered source byte.
.line: ; Count one line ending.
    LD   HL,(ppLine)                                ; Load the line count.
    INC  HL                                         ; The next byte starts a new line.
    LD   (ppLine),HL                                ; Keep it.
    RET                                             ; Return to the line-end code.
.badHead: ; Reject ordinary source inside an include's IF.
    LD   HL,(ppPos)                                 ; Report the ordinary source.
    LD   (ppDirAt),HL                               ; At its offset.
    LD   HL,(ppLine)                                ; And line.
    LD   (ppDirLn),HL                               ; Keep both.
    LD   A,ppBadDir                                 ; The directive structure is malformed.
.bad: ; Record failure A for tkOpen.
    CALL incFail                                    ; Keep the first failure and where it was.
.cut: ; End the part here.
    POP  IY                                         ; Restore the caller's second index register.
    POP  IX                                         ; Restore the caller's index register.
    POP  BC                                         ; Restore the parser's byte and loop state.
    XOR  A                                          ; A=0 with carry ends the part.
    SCF                                             ; Carry marks the end.
    RET                                             ; tkOpen supplies what comes next.

;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; The part has no more bytes after offset HL. Apply a directive on its final
; line, then require its conditions to be closed and mark the file finished.
; An include on that final line ends the part first. It is checked when it
; resumes at this offset. Always returns carry with A=0.

ppEnd: ; Finish a part at its end of file.
    PUSH IX                                         ; Definition lookup uses IX internally.
    PUSH IY                                         ; Include names are parsed through IY.
    LD   (ppPos),HL                                 ; An include resumes here.
    LD   A,(ppEnded)                                ; Was the end already checked?
    OR   A                                          ; Nonzero means yes.
    JR   NZ,.end                                    ; Report the end again.
    LD   A,(ppMode)                                 ; Was a directive being captured?
    BIT  1,A                                        ; Bit 1 means yes.
    JR   Z,.check                                   ; No: check the conditions.
    CALL ppApply                                    ; Apply the final directive.
    JR   C,.bad                                     ; Report a malformed one.
    OR   A                                          ; Did it start an include?
    JR   NZ,.end                                    ; Yes: finish this part later.
.check: ; Require this part's conditions to be closed.
    LD   A,(ppBase)                                 ; Conditions open at the include.
    LD   B,A                                        ; Keep them.
    LD   A,(ppDepth)                                ; Conditions open now.
    CP   B                                          ; Every IF of this part must be closed.
    JR   NZ,.open                                   ; Report an unclosed IF.
    LD   A,1                                        ; The end has been checked.
    LD   (ppEnded),A                                ; Do not check it twice.
    CALL incDone                                    ; Mark the file finished.
    JR   .end                                       ; End the part.
.open: ; Report an IF still open at the end of the file.
    LD   HL,(ppPos)                                 ; Report the end of the file.
    LD   (ppDirAt),HL                               ; At its offset.
    LD   HL,(ppLine)                                ; And line.
    LD   (ppDirLn),HL                               ; Keep both.
    LD   A,ppBadDir                                 ; The conditions are malformed.
.bad: ; Record failure A for tkOpen.
    CALL incFail                                    ; Keep the first failure and where it was.
.end: ; End the part.
    POP  IY                                         ; Restore the caller's second index register.
    POP  IX                                         ; Restore the caller's index register.
    XOR  A                                          ; A=0 with carry ends the part.
    SCF                                             ; Carry marks the end.
    RET                                             ; tkOpen supplies what comes next.

;@ROUTINE OUT CARRY CLOBBERS HALFCARRY
; Return a generic carry-set failure for malformed stack or value state.

ppFail: ; Return failure for malformed condition or value state.
    SCF                                             ; Report an invalid conditional or number.
    RET                                             ; The caller supplies the public diagnostic.

; Directive spellings are separate data so one matcher enforces exact tokens.
ppKeyInc:   DB      'I','N','C','L','U','D','E'     ; Include keyword.
ppKeyDef:    DB      'D','E','F','I','N','E'        ; Root numeric definition.
ppKeyIf:     DB      'I','F'                        ; Conditional opener.
ppKeyAlt:   DB      'E','L','S','E'                 ; Alternate branch.
ppKeyEnd:    DB      'E','N','D','I','F'            ; Conditional closer.
