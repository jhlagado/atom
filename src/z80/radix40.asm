; RADIX-40 name packing, shared by symbols, expressions and statements.

nmBeg: ; Begin RADIX-40 packing code.

;@ROUTINE IN B,HL,DE OUT DE,CARRY MAYBE-OUT ZERO CLOBBERS A,BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack B source characters at HL into the caller's six bytes at DE. Names
; are one to eight ASCII characters, without case distinction. Commit only
; after every character is proved representable.

nmPack: ; Validate and pack a name into the caller's six-byte destination.
    LD   A,B                                        ; Copy the character count for the bounds checks.
    OR   A                                          ; Set Z only when the name is empty.
    JR   Z,.invalid                                 ; Reject empty names before saving any state.
    CP   9                                          ; Compare with the maximum length plus one.
    JR   NC,.invalid                                ; Reject names longer than eight characters.
    PUSH HL                                         ; Preserve the caller's source pointer.
    PUSH BC                                         ; Preserve the count and caller's C value.
.charLoop: ; Validate every source character before writing the destination.
    LD   A,(HL)                                     ; Read the next name character for validation.
    CALL .charCode                                  ; Convert it to a valid RADIX-40 code.
    JR   C,.charFail                                ; Stop if a character is invalid.
    INC  HL                                         ; Advance to the next source character.
    DJNZ .charLoop                                  ; Validate exactly the original B characters.
    POP  BC                                         ; Restore the original length and C register.
    POP  HL                                         ; Restore the source pointer for packing.
    PUSH DE                                         ; Save the caller's destination during packing.
    LD   IX,enTemp                                  ; Stage the three words in private scratch space.
    LD   A,B                                        ; Pass the full name length to the first group.

; Encode characters 0..2 and 3..5 as complete RADIX-40 words. The final call
; stores characters 6..7 directly as c6*40+c7 in the third word.

    CALL .pack3                                     ; Pack characters zero through two.
    CALL .pack3                                     ; Pack characters three through five.
    LD   B,A                                        ; Pass the remaining count to the third group.
    LD   C,2                                        ; Encode the final two RADIX-40 positions.
;@EXPECTOUT DE
    CALL .packWord                                  ; Pack the last two characters with zero padding.
    LD   (IX+0),E                                   ; Stage the final word's low byte.
    LD   (IX+1),D                                   ; Stage the final word's high byte.
    POP  DE                                         ; Restore the caller's six-byte destination.
    LD   HL,enTemp                                  ; Point at the complete staged name.
    LD   BC,6                                       ; Copy all three packed words.
    LDIR                                            ; Publish only after the whole name is valid.
    OR   A                                          ; Clear carry to report successful packing.
    RET                                             ; Return with the destination fully written.
.charFail: ; Restore validation state after an invalid character.
    POP  BC                                         ; Restore the saved count after a failed scan.
    POP  HL                                         ; Restore the source pointer before returning.
.invalid: ; Return carry set while leaving the destination untouched.
    XOR  A                                          ; Return a zero code for every invalid name.
    SCF                                             ; Set carry to report an invalid name.
    RET                                             ; Leave the caller's destination untouched.

;@ROUTINE IN A,HL,IX OUT A,HL,IX CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Consume up to three of the remaining A characters, write one word at IX and
; return the remaining count in A.

.pack3: ; Pack a three-position group and return the remaining count.
    CP   3                                          ; Check for a full three-character group.
    JR   C,.short3                                  ; Handle zero, one or two characters.
    LD   B,3                                        ; Consume exactly three real characters.
    SUB  3                                          ; Keep the count for the following group in A.
    JR   .ready3                                    ; Both paths now share the group encoder.
.short3: ; Use all remaining characters and pad unused positions.
    LD   B,A                                        ; Consume every character that remains.
    XOR  A                                          ; Set the returned remaining count to zero.
.ready3: ; Encode this group with the remaining count saved on the stack.
    PUSH AF                                         ; Preserve the remaining count across packing.
    LD   C,3                                        ; This group has three base-40 positions.
;@EXPECTOUT DE
    CALL .packWord                                  ; Return this group's packed value in DE.
    LD   (IX+0),E                                   ; Store the packed word's low byte.
    LD   (IX+1),D                                   ; Store the packed word's high byte.
    INC  IX                                         ; Advance to this word's high byte.
    INC  IX                                         ; Point at the next packed-word slot.
    POP  AF                                         ; Restore the number of characters still unused.
    RET                                             ; Return the remaining count for the next group.

;@ROUTINE IN BC,HL OUT DE,HL,CARRY MAYBE-OUT ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY,BC,ZERO
; Accumulate exactly C base-40 digits. B real characters are followed by zero
; padding, so each group has one canonical packed representation.

.packWord: ; Accumulate the required base-40 positions into DE.
    LD   DE,0                                       ; Start this base-40 word at zero.
.wordLoop: ; Select a real character or a zero padding digit.
    LD   A,B                                        ; Check whether another real character remains.
    OR   A                                          ; Set Z when the group needs padding.
    JR   Z,.wordPad                                 ; Supply zero for unused positions at the end.
    LD   A,(HL)                                     ; Read the next source character.
    INC  HL                                         ; Advance the source pointer before conversion.
    DEC  B                                          ; Count the character consumed from this group.
    CALL .charCode                                  ; Convert the source byte to its RADIX-40 code.
    JR   .addDigit                                  ; Append the digit to the accumulated word.
.wordPad: ; Supply the padding code after the real characters end.
    XOR  A                                          ; Zero is the canonical RADIX-40 padding digit.
.addDigit: ; Append the selected code to the base-40 accumulator.
    CALL .mulAdd40                                  ; Replace DE with DE*40 plus this character code.
    DEC  C                                          ; Count down the positions in this packed word.
    JR   NZ,.wordLoop                               ; Continue until all positions are added.
    OR   A                                          ; Clear carry after the successful accumulation.
    RET                                             ; Return the packed word in DE.

;@ROUTINE IN DE,A OUT DE CLOBBERS A,F
; DE = DE*40 + A. Five doublings and one add avoid a general multiply.

.mulAdd40: ; Calculate DE*40+A while preserving the source pointer.
    PUSH HL                                         ; Preserve the caller's source or table pointer.
    LD   H,D                                        ; Copy the 16-bit accumulator into HL.
    LD   L,E                                        ; HL now contains the prior RADIX-40 value.
    ADD  HL,HL                                      ; Double it to obtain 2 times the value.
    ADD  HL,HL                                      ; Double again to obtain 4 times the value.
    ADD  HL,DE                                      ; Add the original value to obtain 5 times it.
    ADD  HL,HL                                      ; Double to obtain 10 times the value.
    ADD  HL,HL                                      ; Double to obtain 20 times the value.
    ADD  HL,HL                                      ; Double to obtain 40 times the value.
    ADD  A,L                                        ; Add this character code into the low byte.
    LD   L,A                                        ; Retain the low byte of the new accumulator.
    JR   NC,.noCarry                                ; Skip the high-byte correction without carry.
    INC  H                                          ; Propagate the low-byte addition's carry into H.
.noCarry: ; Return the completed base-40 accumulator in DE.
    EX   DE,HL                                      ; Return the updated 16-bit value in DE.
    POP  HL                                         ; Restore the source or table pointer.
    RET                                             ; Finish one multiply-and-add step.

;@ROUTINE IN A OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Map A-Z/a-z to 1..26, digits to 27..36 and underscore to 37. Codes 38 and 39
; remain unused; zero is reserved for padding.

.charCode: ; Fold ASCII case and map a valid name character to 1..37.
    CP   $61                                        ; Test whether the byte could be lowercase ASCII.
    JR   C,.upper                                   ; Bytes below 'a' need no case conversion.
    CP   $7A+1                                      ; Compare with the first byte after lowercase z.
    JR   NC,.upper                                  ; Bytes after 'z' also keep their original value.
    SUB  $20                                        ; Convert lowercase ASCII to its uppercase form.
.upper: ; Classify uppercase letters before digits and underscore.
    CP   $41                                        ; Test against uppercase ASCII A.
    JR   C,.digit                                   ; Values below A cannot encode as letters.
    CP   $5A+1                                      ; Compare with the first byte after uppercase Z.
    JR   NC,.digit                                  ; Values beyond Z continue to the digit test.
    SUB  $41-1                                      ; Map A..Z to the nonzero codes 1..26.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the packed letter value in A.
.digit: ; Map ASCII digits to RADIX-40 codes 27..36.
    CP   $30                                        ; Test against ASCII digit zero.
    JR   C,.underBar                                ; Lower bytes cannot encode as digits.
    CP   $39+1                                      ; Compare with the first byte after digit nine.
    JR   NC,.underBar                               ; Higher bytes continue to the underscore test.
    SUB  $30-27                                     ; Map ASCII 0..9 to RADIX-40 codes 27..36.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the packed digit value in A.
.underBar: ; Accept underscore as the sole punctuation character.
    CP   $5F                                        ; Test the one supported punctuation character.
    JR   NZ,.badChar                                ; Reject anything other than underscore.
    LD   A,37                                       ; Map underscore to the final assigned code.
    OR   A                                          ; Clear carry to report a valid character code.
    RET                                             ; Return the underscore value in A.
.badChar: ; Return an invalid-character result with carry set.
    XOR  A                                          ; Set the invalid-character result to zero.
    SCF                                             ; Mark invalid input with carry set.
    RET                                             ; Return the character-classification failure.
;@ROUTINE IN B,HL,DE OUT A,DE,CARRY CLOBBERS BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack a source symbol at HL/B into the caller's six-byte key at DE. A leading
; period selects private scope but is not part of the packed name, so both
; global and private payloads retain up to eight characters.

nmPackId: ; Pack a source name and mark private identity when prefixed by a dot.
    LD   A,B                            ; Inspect the complete source-name length.
    OR   A                              ; An empty name cannot form a symbol.
    JR   Z,.invalid                     ; Reject it before writing the destination.
    LD   A,(HL)                         ; Read the first source character.
    CP   $2E                            ; Does '.' mark a private name?
    JR   NZ,.global                     ; Pack an unprefixed global name.
    DEC  B                              ; Exclude the private marker.
    JR   Z,.invalid                     ; Reject a period with no following name.
    LD   A,B                            ; Check private payload length.
    CP   9                              ; Eight characters is the limit.
    JR   NC,.invalid                    ; Reject a longer name before writing.
    INC  HL                             ; Skip the period before RADIX-40 packing.
;@EXPECTOUT DE,CARRY
    CALL nmPack                         ; Pack the private name into six bytes.
    JR   C,.invalid                     ; Report invalid name syntax.
    PUSH DE                             ; Save the end of the packed key.
    DEC  DE                             ; Address the final packed-name byte.

; RADIX-40's final word uses only eleven bits. Mark private identity in
; the final byte without changing the packed name.

    LD   A,(DE)                         ; Read the byte with spare flag bits.
    OR   syFPriv                        ; Mark the packed key as private.
    LD   (DE),A                         ; Set the key's private flag.
    POP  DE                             ; Restore the caller's end-of-key pointer.
    XOR  A                              ; Report successful private-name packing.
    RET                                 ; Return with carry clear.
.global: ; Pack a global name exactly as supplied.
;@EXPECTOUT DE,CARRY
    CALL nmPack                         ; Pack and case-fold the global key.
    JR   C,.invalid                     ; Reject invalid name syntax.
    XOR  A                              ; Report successful global-name packing.
    RET                                 ; Return the packed-key end in DE.
.invalid: ; Return the private/public key syntax failure.
    XOR  A                              ; Construct status one compactly.
    INC  A                              ; A now identifies invalid symbol input.
    SCF                                 ; Mark the packing operation as failed.
    RET                                 ; Leave publication to the caller.

nmEnd: ; End RADIX-40 packing code.
