;@ROUTINE IN A OUT HL,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Convert one token to a 16-bit value or look it up in the bounded table.

PP_EVAL: ; Decode a numeric literal or existing definition.
    LD   A,(PP_TLEN)                                ; Empty values cannot reach the parser.
    OR   A                                          ; Keep a defensive check at this boundary.
    JP   Z,PP_FAIL                                  ; Return carry for an empty value.
    LD   A,(PP_TOKEN)                               ; Inspect the first normalised byte.
    CP   'A'                                        ; A leading letter selects a definition name.
    JR   C,.NOTNAME                                 ; Numbers start with a digit, '$' or '%'.
    CP   'Z'+1                                      ; Bound the first byte to ASCII letters.
    JP   C,.NAME                                    ; Resolve a case-folded preprocessor name.
.NOTNAME: ; Select radix from a numeric prefix or suffix.
    CP   '$'                                        ; A dollar prefix selects hexadecimal.
    JR   Z,.DOLLAR                                  ; Skip the prefix before digit parsing.
    CP   '%'                                        ; A percent prefix selects binary.
    JR   Z,.PERCENT                                 ; The host directive itself began earlier.
    CP   '0'                                        ; Decimal and Intel suffixes start with digits.
    JP   C,PP_FAIL                                  ; Reject punctuation outside the numeric grammar.
    CP   '9'+1                                      ; Digits stop before colon and alphabetic bytes.
    JP   NC,PP_FAIL                                 ; Reject a nonnumeric leading byte.
    LD   A,10                                       ; Unsuffixed digits use decimal.
    LD   (PP_BASE),A                                ; Store decimal as the default radix.
    XOR  A                                          ; Unsuffixed values begin at token byte zero.
    LD   (PP_FIRST),A                               ; Record the first digit's index.
    LD   A,(PP_TLEN)                                ; Decimal consumes the complete token.
    LD   (PP_COUNT),A                               ; The digit loop checks each byte's range.
    DEC  A                                          ; Address the final token byte.
    LD   C,A                                        ; Use it as a short buffer index.
    LD   B,0                                        ; Zero-extend the token index.
    LD   HL,PP_TOKEN                                ; Select the normalised token.
    ADD  HL,BC                                      ; Inspect a possible Intel suffix.
    LD   A,(HL)                                     ; Read the final token byte.
    CP   'H'                                        ; Intel hexadecimal ends in H.
    JR   Z,.SUFFIXH                                 ; Parse preceding digits as hexadecimal.
    CP   'B'                                        ; Intel binary ends in B.
    JR   Z,.SUFFIXB                                 ; Parse its preceding digits in base two.
    JR   .NUMBER                                    ; Keep decimal when neither suffix is present.
.DOLLAR: ; Parse hexadecimal digits after a dollar prefix.
    LD   A,16                                       ; Dollar-prefixed source uses hexadecimal.
    LD   (PP_BASE),A                                ; Store its radix.
    LD   A,1                                        ; Skip the leading dollar sign.
    LD   (PP_FIRST),A                               ; Begin digits immediately after '$'.
    LD   A,(PP_TLEN)                                ; Count all bytes in the token.
    DEC  A                                          ; The prefix is not a digit.
    LD   (PP_COUNT),A                               ; Parse every remaining hexadecimal digit.
    JR   .NUMBER                                    ; Convert and range-check the value.
.PERCENT: ; Parse binary digits after a percent prefix.
    LD   A,2                                        ; Percent-prefixed source uses binary.
    LD   (PP_BASE),A                                ; Store its radix.
    LD   A,1                                        ; Skip the leading percent sign.
    LD   (PP_FIRST),A                               ; Begin at the first binary digit.
    LD   A,(PP_TLEN)                                ; Count all bytes in the token.
    DEC  A                                          ; The prefix is not a digit.
    LD   (PP_COUNT),A                               ; Parse the remaining binary digits.
    JR   .NUMBER                                    ; Convert and range-check the value.
.SUFFIXH: ; Select radix sixteen for an H suffix.
    LD   A,16                                       ; H suffix selects hexadecimal.
    LD   (PP_BASE),A                                ; Replace the decimal default.
    JR   .SUFFIX                                    ; Exclude the suffix from the digits.
.SUFFIXB: ; Select radix two for a B suffix.
    LD   A,2                                        ; B suffix selects binary.
    LD   (PP_BASE),A                                ; Replace the decimal default.
.SUFFIX: ; Exclude the suffix from the digit count.
    LD   A,(PP_TLEN)                                ; The suffix is one byte.
    DEC  A                                          ; Count only the preceding digits.
    LD   (PP_COUNT),A                               ; Keep the existing zero start index.
.NUMBER: ; Initialise bounded numeric accumulation.
    LD   A,(PP_COUNT)                               ; Reject a prefix or suffix without digits.
    OR   A                                          ; Zero digits cannot encode a number.
    JP   Z,PP_FAIL                                  ; A token consisting of H or B is a name instead.
    XOR  A                                          ; Begin numeric accumulation at zero.
    LD   HL,0                                       ; HL is the unsigned 16-bit result.
    LD   (PP_VALUE),HL                              ; Keep the accumulator across helper calls.
    XOR  A                                          ; The digit index begins at zero.
    LD   (PP_INDEX),A                               ; Count digits, not source positions.
.LOOP: ; Convert and accumulate the next numeric digit.
    LD   A,(PP_INDEX)                               ; Read the next digit's token index.
    LD   C,A                                        ; Convert it to a pointer displacement.
    LD   B,0                                        ; The index fits in one byte.
    LD   A,(PP_FIRST)                               ; Include a possible '$' or '%' prefix.
    ADD  A,C                                        ; Form the complete token position.
    LD   C,A                                        ; Use the sum as the low pointer offset.
    LD   HL,PP_TOKEN                                ; Address the token's first byte.
    ADD  HL,BC                                      ; Select the next numeric digit.
    LD   A,(HL)                                     ; Read its normalised ASCII byte.
    CALL .DIGIT                                     ; Convert it under the selected radix.
    JP   C,PP_FAIL                                  ; Reject letters or digits outside the radix.
    LD   (PP_TMP),A                                 ; Save digit during multiply.
    LD   HL,(PP_VALUE)                              ; Load the accumulated prefix value.
    LD   A,(PP_BASE)                                ; Select the radix's multiply operation.
    CP   2                                          ; Binary values double before adding each digit.
    JR   Z,.DOUBLE                                  ; Use one checked shift.
    CP   16                                         ; Hexadecimal values multiply by sixteen.
    JR   Z,.TIMES16                                 ; Use four checked shifts.
    CALL .TENFOLD                                   ; Decimal values multiply by ten.
    JP   C,PP_FAIL                                  ; Reject an intermediate value above $FFFF.
    JR   .ADD                                       ; Add the already-validated decimal digit.
.DOUBLE: ; Multiply a binary prefix by two.
    ADD  HL,HL                                      ; Shift the binary prefix left by one bit.
    JP   C,PP_FAIL                                  ; Reject a high bit that would be lost.
    JR   .ADD                                       ; Add the next binary digit.
.TIMES16: ; Multiply a hexadecimal prefix by sixteen.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by one bit.
    JP   C,PP_FAIL                                  ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by two bits.
    JP   C,PP_FAIL                                  ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Shift the hexadecimal prefix by three bits.
    JP   C,PP_FAIL                                  ; Reject overflow before shifting again.
    ADD  HL,HL                                      ; Complete the four-bit hexadecimal shift.
    JP   C,PP_FAIL                                  ; Reject a value outside the 16-bit range.
.ADD: ; Add the validated digit to the prefix.
    LD   A,L                                        ; Start the addition with the low byte.
    LD   C,A                                        ; Keep that byte while loading the new digit.
    LD   A,(PP_TMP)                                 ; Read the validated digit value (0..15).
    ADD  A,C                                        ; Add the digit to the low byte.
    LD   L,A                                        ; Store the low result byte.
    JR   NC,.NEXT                                   ; No carry leaves the high byte unchanged.
    INC  H                                          ; Carry advances the high byte once.
    JP   Z,PP_FAIL                                  ; A wrapped high byte means value overflow.
.NEXT: ; Advance the checked numeric accumulator.
    LD   (PP_VALUE),HL                              ; Publish this fully checked prefix value.
    LD   HL,PP_INDEX                                ; Address the digit index.
    INC  (HL)                                       ; Count the digit just consumed.
    LD   A,(PP_INDEX)                               ; Compare with the total digit count.
    LD   B,A                                        ; Keep the current index in B.
    LD   A,(PP_COUNT)                               ; Load the number of remaining digits.
    CP   B                                          ; Continue while the index is smaller.
    JR   NZ,.LOOP                                   ; Parse the next digit.
    LD   HL,(PP_VALUE)                              ; Return the final 16-bit value.
    XOR  A                                          ; Clear carry for a successful conversion.
    RET                                             ; HL holds the result.
.NAME: ; Resolve a definition under current branch activity.
    CALL PP_VALID                                   ; Do not overwrite a staged DEFINE name.
    JP   C,PP_FAIL                                  ; Reject malformed or overlong identifiers.
    CALL PP_FIND                                    ; Resolve the prior entry-header definition.
    RET  NC                                         ; A found definition returns its value in HL.
    LD   A,(PP_LIVE)                                ; Ignore unknown names in inactive branches.
    OR   A                                          ; Active source requires an existing definition.
    JP   NZ,PP_FAIL                                 ; Reject a missing name in an active condition.
    LD   HL,0                                       ; Inactive nested conditions select false.
    XOR  A                                          ; Preserve that non-error result.
    RET                                             ; The outer inactive frame remains decisive.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Convert A from the selected base into a digit value in the range 0..15.

.DIGIT: ; Convert ASCII to a bounded digit value.
    CP   '0'                                        ; Digits begin at ASCII zero.
    JR   C,.NODIGIT                                 ; Reject punctuation below the digit range.
    CP   '9'+1                                      ; Decimal digits end before uppercase letters.
    JR   C,.DECIMAL                                 ; Convert '0' through '9'.
    CP   'A'                                        ; Hexadecimal letters start at A.
    JR   C,.NODIGIT                                 ; Reject punctuation between digits and letters.
    CP   'F'+1                                      ; Only A through F fit a hexadecimal nibble.
    JR   NC,.NODIGIT                                ; Reject letters beyond F.
    SUB  'A'-10                                     ; Convert A..F into 10..15.
    JR   .RADIX                                     ; Compare the value with the selected base.
.DECIMAL: ; Convert an ASCII decimal digit.
    SUB  '0'                                        ; Convert ASCII digit to its numeric value.
.RADIX: ; Require the digit to be below the radix.
    LD   C,A                                        ; Save the converted value during the radix check.
    LD   A,(PP_BASE)                                ; Binary, decimal or hexadecimal limit.
    LD   B,A                                        ; Keep the radix while comparing the digit.
    LD   A,C                                        ; Read the converted digit value.
    CP   B                                          ; Carry means this digit is below the radix.
    JR   NC,.NODIGIT                                ; Reject a digit equal to or above the radix.
    LD   A,C                                        ; Return the numeric digit.
    OR   A                                          ; Clear carry without changing its value.
    RET                                             ; A contains the accepted digit.
.NODIGIT: ; Reject a character outside the selected radix.
    SCF                                             ; Carry rejects the token under its radix.
    RET                                             ; The numeric parser selects a directive error.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Compute value*10 as value*8+value*2 with overflow checks at each addition.

.TENFOLD: ; Multiply a decimal prefix by ten with overflow checks.
    PUSH HL                                         ; Preserve the original value for the final sum.
    ADD  HL,HL                                      ; Form value*2.
    JR   C,.POPONE                                  ; Reject overflow. undo high word.
    PUSH HL                                         ; Save value*2 while constructing value*8.
    ADD  HL,HL                                      ; Form value*4.
    JR   C,.POPTWO                                  ; Remove both saved words.
    ADD  HL,HL                                      ; Form value*8.
    JR   C,.POPTWO                                  ; Remove both saved words.
    POP  DE                                         ; Recover value*2 into DE.
    ADD  HL,DE                                      ; Form value*10.
    JR   C,.POPONE                                  ; Reject a sum above $FFFF.
    POP  DE                                         ; Discard the preserved original value.
    OR   A                                          ; Return carry clear with the product in HL.
    RET                                             ; The caller adds its next decimal digit.
.POPTWO: ; Discard the second saved multiplication operand.
    POP  DE                                         ; Remove the saved value*2 from the stack.
.POPONE: ; Discard the first saved multiplication operand.
    POP  DE                                         ; Remove the saved original value.
    SCF                                             ; Carry signals an out-of-range decimal prefix.
    RET                                             ; Keep the caller's stack balanced.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find the token's uppercase name in the fixed twenty-byte definition records.

PP_FIND: ; Find a name in twenty-byte definition records.
    LD   A,(PP_TLEN)                                ; Check length against the name field.
    CP   PP_WIDTH+1                                 ; Reject names wider than the fixed field.
    JR   NC,.MISSING                                ; Treat an overlong name as missing.
    LD   A,(PP_NDEFS)                               ; A zero count means the table is empty.
    OR   A                                          ; Avoid an IX walk when no values exist.
    JR   Z,.MISSING                                 ; Let the caller decide if missing is legal.
    LD   B,A                                        ; Visit every preceding definition.
    LD   IX,PP_DEFS                                 ; Address the first fixed-width record.
.LOOP: ; Compare each occupied definition record.
    LD   A,(IX+0)                                   ; Read the stored name length.
    LD   C,A                                        ; Keep it while loading the query length.
    LD   A,(PP_TLEN)                                ; Read the current query's length.
    CP   C                                          ; Different lengths cannot match.
    JR   NZ,.NEXT                                   ; Try the next definition record.
    PUSH IX                                         ; Save the record base across name comparison.
    INC  IX                                         ; The first name byte follows the length field.
    LD   DE,PP_TOKEN                                ; Compare with the normalised query name.
    LD   A,(PP_TLEN)                                ; Match exactly the declared name length.
    LD   C,A                                        ; Use C as the character count.
.COMPARE: ; Compare every significant uppercase name byte.
    LD   A,(DE)                                     ; Read one requested name character.
    CP   (IX+0)                                     ; Compare it with this record's name byte.
    JR   NZ,.MISMATCH                               ; Continue searching on mismatch.
    INC  DE                                         ; Advance through the query name.
    INC  IX                                         ; Advance through the stored name.
    DEC  C                                          ; Count this matching character.
    JR   NZ,.COMPARE                                ; Compare the complete name.
    POP  IX                                         ; Restore the matching record's base.
    LD   L,(IX+18)                                  ; Read the definition value's low byte.
    LD   H,(IX+19)                                  ; Complete its unsigned 16-bit value.
    OR   A                                          ; Clear carry to report a successful lookup.
    RET                                             ; Return the value in HL.
.MISMATCH: ; Restore the record pointer after mismatch.
    POP  IX                                         ; Restore the record pointer after mismatch.
.NEXT: ; Advance to the next definition record.
    LD   DE,PP_REC                                  ; Advance by one full definition record.
    ADD  IX,DE                                      ; Advance to the next definition.
    DJNZ .LOOP                                      ; Stop after the published record count.
.MISSING: ; Return missing-definition status.
    SCF                                             ; Carry tells the caller no value was found.
    RET                                             ; HL has no meaning on this path.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a 1-17 character name and copy it to PP_NAME.

PP_STAGE: ; Validate and stage the definition name.
    LD   A,(PP_TLEN)                                ; Read the complete candidate length.
    OR   A                                          ; Empty names are invalid.
    JR   Z,PP_BADID                                 ; Reject an absent identifier.
    CP   PP_WIDTH+1                                 ; The name field holds at most 17 characters.
    JR   NC,PP_BADID                                ; Reject anything wider than its storage field.
    LD   (PP_NLEN),A                                ; Retain the length for lookup and insertion.
    LD   HL,PP_NAME                                 ; Fill unused name bytes with spaces.
    LD   B,PP_WIDTH                                 ; Compare the complete padded name field.
    LD   A,' '                                      ; Space padding makes comparisons deterministic.
.PADLOOP: ; Space-fill the complete staged name field.
    LD   (HL),A                                     ; Clear one staged name byte.
    INC  HL                                         ; Advance to the next name position.
    DJNZ .PADLOOP                                   ; Fill the full fixed-width field before copying.
    LD   A,(PP_NLEN)                                ; Reload the candidate's length.
    LD   B,A                                        ; Use B to count its characters.
    LD   C,0                                        ; C distinguishes first character from the rest.
    LD   DE,PP_TOKEN                                ; Start at the normalised candidate.
    LD   HL,PP_NAME                                 ; Store its canonical bytes separately.
.CHKLOOP: ; Validate and copy each staged character.
    LD   A,(DE)                                     ; Read the next uppercase character.
    LD   (PP_TMP),A                                 ; Save the byte without changing DE.
    LD   A,C                                        ; Zero marks the first character.
    OR   A                                          ; The first character must be a letter.
    LD   A,(PP_TMP)                                 ; Restore the candidate byte.
    JR   NZ,.LATER                                  ; Later bytes may include digits and underscore.
    CP   'A'                                        ; Test the inclusive first-letter lower bound.
    JR   C,PP_BADID                                 ; Reject leading digits and punctuation.
    CP   'Z'+1                                      ; Test the exclusive first-letter upper bound.
    JR   NC,PP_BADID                                ; Reject a leading underscore.
    JR   .STORE                                     ; A valid letter begins the staged name.
.LATER: ; Check characters after the initial letter.
    CP   'A'                                        ; A later uppercase letter is valid.
    JR   C,.NOTALPHA                                ; Check the other allowed classes.
    CP   'Z'+1                                      ; Bound the letter range.
    JR   C,.STORE                                   ; Store a valid later letter.
.NOTALPHA: ; Check digits or underscore after the initial letter.
    CP   '0'                                        ; Digits are permitted after the first byte.
    JR   C,.UNDERBAR                                ; Check underscore before other punctuation.
    CP   '9'+1                                      ; Bound the digit range.
    JR   C,.STORE                                   ; Store a valid later digit.
.UNDERBAR: ; Accept underscore as the remaining name character.
    CP   '_'                                        ; Underscore is allowed after the first byte.
    JR   NZ,PP_BADID                                ; Reject all other punctuation.
.STORE: ; Copy the accepted name character.
    LD   (HL),A                                     ; Store this character in the padded name.
    INC  HL                                         ; Advance the name destination.
    INC  DE                                         ; Advance the source token.
    INC  C                                          ; Mark subsequent characters as noninitial.
    DJNZ .CHKLOOP                                   ; Validate every remaining character.
    LD   A,(PP_NLEN)                                ; Return the accepted name length.
    OR   A                                          ; Clear carry on successful validation.
    RET                                             ; PP_NAME now holds uppercase padded bytes.
PP_BADID: ; Reject an invalid identifier.
    SCF                                             ; Carry marks invalid name syntax or length.
    RET                                             ; The source profile reports a directive error.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a lookup token without replacing the separately staged DEFINE name.

PP_VALID: ; Validate a lookup token without changing staged name.
    LD   A,(PP_TLEN)                                ; Read the complete query token length.
    OR   A                                          ; Empty identifiers cannot be looked up.
    JR   Z,PP_BADID                                 ; Reuse the common carry-set result.
    CP   PP_WIDTH+1                                 ; The fixed record bounds every lookup name.
    JR   NC,PP_BADID                                ; Reject a name the definition table cannot hold.
    LD   B,A                                        ; Count every validated token byte.
    LD   C,0                                        ; Zero identifies the leading character.
    LD   DE,PP_TOKEN                                ; Begin at the uppercase token buffer.
.LOOP: ; Validate each uppercase lookup character.
    LD   A,(DE)                                     ; Read one candidate character.
    LD   (PP_TMP),A                                 ; Preserve it without changing the DE cursor.
    LD   A,C                                        ; Check whether this is the first character.
    OR   A                                          ; A nonzero count permits more character classes.
    LD   A,(PP_TMP)                                 ; Reload the byte for its range checks.
    JR   NZ,.LATER                                  ; Later bytes allow digits and underscore.
    CP   'A'                                        ; A name must start with an uppercase letter.
    JR   C,PP_BADID                                 ; Reject an invalid first character.
    CP   'Z'+1                                      ; Test the exclusive end of the letter range.
    JR   NC,PP_BADID                                ; Reject an initial underscore.
    JR   .NEXT                                      ; The first letter passed validation.
.LATER: ; Check subsequent lookup characters.
    CP   'A'                                        ; Test the later-letter range first.
    JR   C,.NOTALPHA                                ; Check digits and underscore below.
    CP   'Z'+1                                      ; Bound the inclusive uppercase letters.
    JR   C,.NEXT                                    ; Advance past a valid later letter.
.NOTALPHA: ; Check digits or underscore in the lookup name.
    CP   '0'                                        ; Decimal digits may follow the initial letter.
    JR   C,.UNDERBAR                                ; Check underscore before punctuation.
    CP   '9'+1                                      ; Bound the decimal digit range.
    JR   C,.NEXT                                    ; Accept a digit after the first character.
.UNDERBAR: ; Accept underscore in the lookup name.
    CP   '_'                                        ; Underscore is the only other allowed byte.
    JR   NZ,PP_BADID                                ; Reject invalid identifier punctuation.
.NEXT: ; Advance after a valid lookup character.
    INC  DE                                         ; Advance to the following token character.
    INC  C                                          ; Mark all remaining bytes as noninitial.
    DJNZ .LOOP                                      ; Validate the complete identifier.
    XOR  A                                          ; Clear carry for a valid lookup name.
    RET                                             ; Leave token bytes intact for table lookup.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Copy a staged definition name to the query buffer for duplicate detection.

PP_COPY: ; Copy the staged name for duplicate lookup.
    LD   A,(PP_NLEN)                                ; Keep the name's significant length.
    LD   (PP_TLEN),A                                ; Configure the generic lookup routine.
    LD   HL,PP_NAME                                 ; Read the staged padded name.
    LD   DE,PP_TOKEN                                ; Write its bytes into the query buffer.
    LD   B,PP_WIDTH                                 ; Copy the complete canonical field.
.LOOP: ; Copy every byte of the padded name field.
    LD   A,(HL)                                     ; Read one uppercase name or padding byte.
    LD   (DE),A                                     ; Publish it in the lookup buffer.
    INC  HL                                         ; Advance the staged source.
    INC  DE                                         ; Advance the query destination.
    DJNZ .LOOP                                      ; Copy the complete padded name.
    RET                                             ; The value token is no longer needed.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Append one validated staged name and value to the bounded definition table.

PP_STORE: ; Append a complete name-and-value record.
    LD   A,(PP_NDEFS)                               ; Read the number of occupied records.
    CP   PP_CAP                                     ; The table is deliberately finite on CP/M.
    JP   NC,PP_FAIL                                 ; Reject a thirty-third distinct definition.
    LD   B,A                                        ; Advance over the occupied fixed-width records.
    LD   IX,PP_DEFS                                 ; Start with the first slot.
    OR   A                                          ; A zero count already selects that slot.
    JR   Z,.SLOT                                    ; The first record needs no pointer step.
.RECLOOP: ; Skip each occupied definition record.
    LD   DE,PP_REC                                  ; Advance by one complete record.
    ADD  IX,DE                                      ; Select the following definition slot.
    DJNZ .RECLOOP                                   ; Skip every occupied record.
.SLOT: ; Write the next unused definition slot.
    LD   A,(PP_NLEN)                                ; Store the exact significant-name length.
    LD   (IX+0),A                                   ; Record byte zero is the name length.
    INC  IX                                         ; Name bytes begin at record offset one.
    LD   HL,PP_NAME                                 ; Read the staged uppercase field.
    LD   B,PP_WIDTH                                 ; Copy every name and padding position.
.NAMELOOP: ; Copy the fixed-width uppercase name field.
    LD   A,(HL)                                     ; Read a name character or its space padding.
    LD   (IX+0),A                                   ; Store it in the current record position.
    INC  HL                                         ; Advance through the staged name.
    INC  IX                                         ; Advance through the record name field.
    DJNZ .NAMELOOP                                  ; Copy the complete fixed-width field.
    LD   HL,(PP_VALUE)                              ; Load the previously validated value.
    LD   (IX+0),L                                   ; Store its low byte at record offset eighteen.
    LD   (IX+1),H                                   ; Store its high byte at record offset nineteen.
    LD   HL,PP_NDEFS                                ; Address the number of published definitions.
    INC  (HL)                                       ; Make the complete record visible to IF lookup.
    XOR  A                                          ; Return success with carry clear.
    RET                                             ; Preserve every existing definition.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mask inactive source bytes while preserving every CR/LF byte and offset.

PP_MASK: ; Filter one raw source byte without moving offsets.
    PUSH BC                                         ; The source-provider boundary preserves BC.
    PUSH IX                                         ; Definition lookup uses IX internally.
    LD   (PP_POS),HL                                ; Save the byte's source position.
    LD   (PP_TMP),A                                 ; Keep the raw byte across directive detection.
    CP   '%'                                        ; Only a line-leading percent starts a directive.
    JR   NZ,.ORDINARY                               ; Ordinary bytes follow current activity.
    PUSH HL                                         ; The line-prefix check scans backwards.
    CALL SRC_LEAD                                   ; Ignore '%' in strings and expressions.
    POP  HL                                         ; Restore the exact byte offset.
    JR   NZ,.ORDINARY                               ; Return ordinary percent text unchanged.
    LD   DE,(PP_POS)                                ; Compare with last directive offset.
    LD   HL,(PP_LAST)                               ; A peek may request this byte again.
    OR   A                                          ; Clear carry before the equality subtraction.
    SBC  HL,DE                                      ; Has this source offset already changed state?
    JR   Z,.COMMENT                                 ; A repeated peek must not push twice.
    LD   HL,(PP_POS)                                ; Restore the directive's source location.
    INC  HL                                         ; Keyword text begins after the percent marker.
    CALL PP_APPLY                                   ; Apply IF/ELSE/ENDIF exactly once.
    JR   C,.FAIL                                    ; A changed source cannot be filtered safely.
    LD   HL,(PP_POS)                                ; Record the processed directive's offset.
    LD   (PP_LAST),HL                               ; Skip matching tokenizer consume.
.COMMENT: ; Hide a processed directive behind a comment marker.
    LD   A,';'                                      ; Atom skips this line as a comment.
    JR   .DONE                                      ; Do not expose directive tokens to the core.
.ORDINARY: ; Preserve active text or mask inactive text.
    LD   A,(PP_LIVE)                                ; Check whether this branch is active.
    OR   A                                          ; An active branch preserves its exact source.
    JR   NZ,.RAW                                    ; Return the original byte unchanged.
    LD   A,(PP_TMP)                                 ; Restore the original byte for newline checks.
    CP   13                                         ; CR remains visible to the Atom tokenizer.
    JR   Z,.RAW                                     ; Preserve the original line ending.
    CP   10                                         ; LF is also preserved byte-for-byte.
    JR   Z,.RAW                                     ; Keep CRLF and LF line counts unchanged.
    LD   A,' '                                      ; Inactive source becomes harmless whitespace.
    JR   .DONE                                      ; Preserve its byte offset and column.
.RAW: ; Lower active INCBIN text after conditional filtering.
    LD   HL,(PP_POS)                                ; Keep the source position with the byte.
    LD   A,(PP_TMP)                                 ; Restore the original active or line-end byte.
    CALL BIN_EDIT                                   ; Lower an active INCBIN line to its DS form.
    JR   C,.FAIL                                    ; A failed binary read aborts the generation.
.DONE: ; Restore caller state after a filtered byte.
    POP  IX                                         ; Restore the caller's index register.
    POP  BC                                         ; Restore the parser's byte and loop state.
    OR   A                                          ; Clear carry and classify a zero byte.
    RET                                             ; Return the filtered source byte.
.FAIL: ; Restore caller state and report a changed source.
    POP  IX                                         ; Restore index state on a rejected source change.
    POP  BC                                         ; Restore parser state before reporting failure.
    LD   A,2                                        ; Distinguish a preflight/runtime mismatch.
    SCF                                             ; Carry reports the unavailable source byte.
    RET                                             ; Atom aborts without committing its output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Return a generic carry-set failure for malformed stack or value state.

PP_FAIL: ; Return failure for malformed condition or value state.
    SCF                                             ; Report an invalid conditional or number.
    RET                                             ; The caller supplies the public diagnostic.

; Directive spellings are separate data so one matcher enforces exact tokens.
PP_KINCL:   DB      'I','N','C','L','U','D','E'     ; Include keyword.
PP_KDEF:    DB      'D','E','F','I','N','E'         ; Root numeric definition.
PP_KIF:     DB      'I','F'                         ; Conditional opener.
PP_KELSE:   DB      'E','L','S','E'                 ; Alternate branch.
PP_KEND:    DB      'E','N','D','I','F'             ; Conditional closer.
