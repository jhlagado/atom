;@ROUTINE IN A OUT HL,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
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

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mask inactive source bytes while preserving every CR/LF byte and offset.

ppFilter: ; Filter one raw source byte without moving offsets.
    PUSH BC                                         ; The source-provider boundary preserves BC.
    PUSH IX                                         ; Definition lookup uses IX internally.
    LD   (ppPos),HL                                 ; Save the byte's source position.
    LD   (ppTemp),A                                 ; Keep the raw byte across directive detection.
    CP   '%'                                        ; Only a line-leading percent starts a directive.
    JR   NZ,.ordinary                               ; Ordinary bytes follow current activity.
    PUSH HL                                         ; The line-prefix check scans backwards.
    CALL srcLead                                    ; Ignore '%' in strings and expressions.
    POP  HL                                         ; Restore the exact byte offset.
    JR   NZ,.ordinary                               ; Return ordinary percent text unchanged.
    LD   DE,(ppPos)                                 ; Compare with last directive offset.
    LD   HL,(ppDirOff)                              ; A peek may request this byte again.
    OR   A                                          ; Clear carry before the equality subtraction.
    SBC  HL,DE                                      ; Has this source offset already changed state?
    JR   Z,.comment                                 ; A repeated peek must not push twice.
    LD   HL,(ppPos)                                 ; Restore the directive's source location.
    INC  HL                                         ; Keyword text begins after the percent marker.
    CALL ppApply                                    ; Apply IF/ELSE/ENDIF exactly once.
    JR   C,.fail                                    ; A changed source cannot be filtered safely.
    LD   HL,(ppPos)                                 ; Record the processed directive's offset.
    LD   (ppDirOff),HL                              ; Skip matching tokenizer consume.
.comment: ; Hide a processed directive behind a comment marker.
    LD   A,';'                                      ; Atom skips this line as a comment.
    JR   .done                                      ; Do not expose directive tokens to the core.
.ordinary: ; Preserve active text or mask inactive text.
    LD   A,(ppActive)                               ; Check whether this branch is active.
    OR   A                                          ; An active branch preserves its exact source.
    JR   NZ,.raw                                    ; Return the original byte unchanged.
    LD   A,(ppTemp)                                 ; Restore the original byte for newline checks.
    CP   13                                         ; CR remains visible to the Atom tokenizer.
    JR   Z,.raw                                     ; Preserve the original line ending.
    CP   10                                         ; LF is also preserved byte-for-byte.
    JR   Z,.raw                                     ; Keep CRLF and LF line counts unchanged.
    LD   A,' '                                      ; Inactive source becomes harmless whitespace.
    JR   .done                                      ; Preserve its byte offset and column.
.raw: ; Lower active INCBIN text after conditional filtering.
    LD   HL,(ppPos)                                 ; Keep the source position with the byte.
    LD   A,(ppTemp)                                 ; Restore the original active or line-end byte.
    CALL binEdit                                    ; Lower an active INCBIN line to its DS form.
    JR   C,.fail                                    ; A failed binary read aborts the generation.
.done: ; Restore caller state after a filtered byte.
    POP  IX                                         ; Restore the caller's index register.
    POP  BC                                         ; Restore the parser's byte and loop state.
    OR   A                                          ; Clear carry and classify a zero byte.
    RET                                             ; Return the filtered source byte.
.fail: ; Restore caller state and report a changed source.
    POP  IX                                         ; Restore index state on a rejected source change.
    POP  BC                                         ; Restore parser state before reporting failure.
    LD   A,2                                        ; Distinguish a preflight/runtime mismatch.
    SCF                                             ; Carry reports the unavailable source byte.
    RET                                             ; Atom aborts without committing its output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
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
