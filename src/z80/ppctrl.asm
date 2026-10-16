; CP/M implementation of Atom's source-level definitions and conditions.
;
; The filter in ppvalue.asm captures each line-leading % directive as the
; tokenizer reads it as a comment. At the line's end ppApply applies it: IF,
; ELSE and ENDIF change which lines are active, DEFINE adds a root value and
; INCLUDE starts another source part. Inactive text becomes spaces, with every
; line ending and byte offset preserved. Defines are numeric and
; case-insensitive. names hold up to 17 characters. The native profile
; supports 32 definitions and 16 nested conditional levels.

;@ROUTINE IN A CLOBBERS A,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Begin filtering a part from its first byte. A is its ordinal. Only the root
; header may define values. A child's conditions nest inside the condition
; that was open at its include, which it cannot close.

ppStart: ; Reset per-part state for a part's first byte.
    LD   (srcPart),A                    ; This part is now being read.
    OR   A                              ; Is it the root, ordinal zero?
    LD   A,0                            ; Prepare zero without changing Z.
    JR   NZ,.child                      ; A child cannot define values.
    INC  A                              ; The root header may.
.child: ; Record whether definitions are allowed.
    LD   (ppDefOk),A                    ; Definitions end at the first include or IF.
    LD   A,(ppDepth)                    ; Conditions open at the include remain open.
    LD   (ppBase),A                     ; This part's frames begin above them.
    LD   A,1                            ; The part starts at a line start.
    LD   (ppMode),A                     ; Not in a directive.
    LD   (incHead),A                    ; Every part starts in its header.
    XOR  A                              ; Clear the remaining part state.
    LD   (ppLastCr),A                   ; No byte precedes the first.
    LD   (ppEnded),A                    ; Its end has not been checked.
    LD   (ppLine),A                     ; Lines count from one.
    LD   (ppLine+1),A                   ; Clear the high byte.
    INC  A                              ; Form one.
    LD   (ppLine),A                     ; The first line.
    RET                                 ; Filtering can begin.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Apply the directive captured in ppLnBuf. Carry means it failed, with its
; message number in A. A=1 means an include or %LINE ends this part here.
; A=0 means the part continues.

ppApply: ; Apply one captured directive at its line's end.
    LD   A,(ppMode)                     ; The directive is complete.
    AND  $FD                            ; Clear the capture bit.
    LD   (ppMode),A                     ; Later bytes are ordinary again.
    LD   A,(ppCapLen)                   ; How did the capture end?
    CP   $FE                            ; Overflow?
    JP   Z,ppErr                        ; A directive must fit the buffer.
    CP   $FF                            ; Already ended at its comment?
    JR   Z,.ended                       ; Its CR is in place.
    LD   E,A                            ; Index the byte after the directive.
    LD   D,0                            ; Widen it.
    LD   HL,ppLnBuf                     ; Address the buffer.
    ADD  HL,DE                          ; Address the end.
    LD   (HL),13                        ; End the directive with CR.
.ended: ; Read the directive's keyword.
    LD   HL,ppLnBuf                     ; Start after the '%'.
    CALL ppGetTok                       ; Read the keyword.
    JP   C,ppErr                        ; Empty or overlong words are malformed.
    LD   (ppSrcPtr),HL                  ; Save the cursor while matching.
    LD   HL,ppKeyInc                    ; Select the longest supported directive.
    LD   B,7                            ; INCLUDE has seven letters.
    CALL ppMatch                        ; Compare case-folded token bytes.
    JP   Z,ppIncl                       ; Start the included part.
    LD   HL,ppKeyDef                    ; Check for a root numeric definition.
    LD   B,6                            ; DEFINE has six letters.
    CALL ppMatch                        ; Reject any other six-byte token later.
    JR   Z,ppDefine                     ; Validate scope, name and value.
    LD   HL,ppKeyLin                    ; Check for a line marker.
    LD   B,4                            ; LINE has four letters.
    CALL ppMatch                        ; Match the full keyword.
    JP   Z,ppSetLn                      ; Name the lines that follow.
    XOR  A                              ; IF, ELSE and ENDIF close the definitions.
    LD   (ppDefOk),A                    ; No define may follow conditional logic.
    LD   HL,ppKeyEnd                    ; Check the five-byte closing directive.
    LD   B,5                            ; ENDIF has five letters.
    CALL ppMatch                        ; Match the complete token, not a prefix.
    JR   Z,ppEndIf                      ; Pop one condition after its line is valid.
    LD   HL,ppKeyAlt                    ; Check the four-byte alternate directive.
    LD   B,4                            ; ELSE has four letters.
    CALL ppMatch                        ; Match the full keyword.
    JR   Z,ppElse                       ; Toggle the current conditional branch.
    LD   HL,ppKeyIf                     ; Check the two-byte opening directive.
    LD   B,2                            ; IF has two letters.
    CALL ppMatch                        ; Match the complete keyword.
    JR   Z,ppIf                         ; Evaluate and push a new condition.
ppErr: ; Return invalid-directive detail.
    LD   A,ppBadDir                     ; Select unsupported-directive detail.
    SCF                                 ; Carry marks the malformed directive.
    RET                                 ; The filter records where it was.
ppDefine: ; Validate an entry-header numeric definition.
    LD   A,(srcPart)                    ; Only the entry source may define values.
    OR   A                              ; Source ordinal zero identifies the root.
    JP   NZ,ppErr                       ; Reject definitions in included files.
    LD   A,(incHead)                    ; Require the root's leading header.
    OR   A                              ; Ordinary source permanently closes it.
    JP   Z,ppErr                        ; Reject a late definition.
    LD   A,(ppDefOk)                    ; Defines must precede includes and IF blocks.
    OR   A                              ; Zero means the preamble is already closed.
    JP   Z,ppErr                        ; Reject definitions after preprocessing begins.
    LD   HL,(ppSrcPtr)                  ; Start after the DEFINE directive name.
    CALL ppAddDef                       ; Store one unique name and numeric value.
    JP   C,ppErr                        ; Select the public directive error on failure.
    XOR  A                              ; The part continues.
    RET                                 ; Return carry clear.
ppIf: ; Evaluate and push an IF.
    LD   HL,(ppSrcPtr)                  ; Start after the IF keyword.
    CALL ppPush                         ; Evaluate the condition and push its frame.
    JP   C,ppErr                        ; Select the public directive error on failure.
    XOR  A                              ; The part continues.
    RET                                 ; Continue with the newly selected branch.
ppElse: ; Validate and select an ELSE.
    LD   HL,(ppSrcPtr)                  ; Start at the directive's trailing text.
    CALL ppEol                          ; Require only whitespace.
    JP   C,ppErr                        ; Reject arguments after ELSE.
    CALL ppFlip                         ; Validate and activate the alternate branch.
    JP   C,ppErr                        ; Report unmatched or duplicate ELSE consistently.
    XOR  A                              ; The part continues.
    RET                                 ; Continue with the new branch state.
ppEndIf: ; Validate and close an IF.
    LD   HL,(ppSrcPtr)                  ; Validate the rest of the line.
    CALL ppEol                          ; ENDIF accepts no arguments.
    JP   C,ppErr                        ; Reject extra words after ENDIF.
    CALL ppPop                          ; Restore the parent branch's activity.
    JP   C,ppErr                        ; Report an unmatched ENDIF consistently.
    XOR  A                              ; The part continues.
    RET                                 ; Continue with the parent's activity.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one root definition. the name and value occupy separate work buffers.

ppAddDef: ; Parse and insert a unique root definition.
    CALL ppGetTok                       ; Read the case-insensitive definition name.
    JP   C,ppErr                        ; A definition needs a name.
    LD   (ppSrcPtr),HL                  ; Save delimiter while checking the name.
    CALL ppStage                        ; Enforce the native name-field limit.
    JP   C,ppErr                        ; Reject invalid or overlong names.
    LD   (ppLength),A                   ; Retain its length while reading the value.
    LD   HL,(ppSrcPtr)                  ; Resume where the name token ended.
    CALL ppGetTok                       ; Skip whitespace and read one numeric value.
    JP   C,ppErr                        ; A definition needs a value.
    LD   (ppSrcPtr),HL                  ; Save delimiter while parsing the value.
    CALL ppEval                         ; Resolve numeric syntax or a previous name.
    JP   C,ppErr                        ; Reject undefined names and values above 16 bits.
    LD   (ppValue),HL                   ; Keep the value until the line end is checked.
    LD   HL,(ppSrcPtr)                  ; Resume at the delimiter after the value.
    CALL ppEol                          ; Only whitespace, a comment or EOL may follow.
    JP   C,ppErr                        ; Reject additional define operands.
    LD   (ppAfter),HL                   ; Save the next source position for lookup.
    CALL ppCopy                         ; Reuse lookup with the staged name.
    CALL ppFind                         ; A pre-existing match is a duplicate definition.
    JP   NC,ppErr                       ; Reject duplicates even when values are equal.
    CALL ppStore                        ; Append the new value to the bounded table.
    RET  C                              ; A full table is an explicit profile error.
    LD   HL,(ppAfter)                   ; Restore next source position.
    RET                                 ; Carry reports a full definition table.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse an IF value, validate its line, then push the computed condition.

ppPush: ; Evaluate an IF and validate its trailing text.
    CALL ppGetTok                       ; Read one number or prior definition name.
    JP   C,ppErr                        ; IF requires exactly one value.
    LD   (ppSrcPtr),HL                  ; Keep delimiter until evaluation ends.
    CALL ppEval                         ; Unknown names fail only in an active parent.
    JP   C,ppErr                        ; Reject invalid values or active unknown names.
    LD   (ppValue),HL                   ; Keep the result while checking trailing text.
    LD   HL,(ppSrcPtr)                  ; Resume at the trailing delimiter.
    CALL ppEol                          ; Require the directive to end after one value.
    JP   C,ppErr                        ; Reject operators and extra arguments.
    LD   (ppAfter),HL                   ; Save cursor before pushing the frame.
    LD   HL,(ppValue)                   ; Restore the unsigned sixteen-bit value.
    LD   A,H                            ; Test its high byte.
    OR   L                              ; Either nonzero byte selects a true branch.
    LD   A,0                            ; Prepare the false condition.
    JR   Z,.push                        ; Keep zero false.
    INC  A                              ; Convert any nonzero value to true.
.push: ; Push the normalised truth value.
    CALL .frame                         ; Save parent state and update activity.
    RET  C                              ; Preserve a nesting-limit failure.
    LD   HL,(ppAfter)                   ; Continue after this physical line.
    RET                                 ; Return condition state and source position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push parent activity and the condition result into a sixteen-byte stack.

.frame: ; Encode one conditional-stack frame.
    LD   (ppTemp),A                     ; Preserve the condition during pointer setup.
    LD   A,(ppDepth)                    ; Read the number of existing frames.
    CP   16                             ; The fixed stack holds sixteen nested IFs.
    JP   NC,ppFail                      ; Reject a seventeenth frame.
    LD   C,A                            ; Use the depth as the frame's byte index.
    LD   B,0                            ; Extend that index to a word.
    LD   HL,ppStack                     ; Begin at the first frame.
    ADD  HL,BC                          ; Select the next empty frame.
    LD   A,(ppActive)                   ; Capture the enclosing branch's activity.
    OR   A                              ; Normalize it to one bit.
    LD   A,0                            ; A false parent stores no flag bits.
    JR   Z,.parent                      ; Keep the inactive parent clear.
    INC  A                              ; Bit zero marks an active parent.
.parent: ; Store the parent activity bit.
    LD   (HL),A                         ; Store the parent-active flag.
    LD   A,(ppTemp)                     ; Read the condition selected by the directive.
    OR   A                              ; Zero leaves condition bit one clear.
    JR   Z,.result                      ; Store a false condition under this frame.
    LD   A,(HL)                         ; Recover the frame's parent flag.
    OR   2                              ; Bit one records a true condition.
    LD   (HL),A                         ; Preserve both frame facts.
.result: ; Combine parent and condition activity.
    LD   A,(HL)                         ; Read parent and condition bits together.
    AND  3                              ; Both bits must be set for an active branch.
    CP   3                              ; Value three means active parent and true IF.
    LD   A,0                            ; Prepare the inactive result.
    JR   NZ,.store                      ; A false parent or condition stays inactive.
    INC  A                              ; Mark the selected IF body active.
.store: ; Publish the selected branch activity.
    LD   (ppActive),A                   ; Publish activity for following source bytes.
    LD   HL,ppDepth                     ; Point at the one-byte frame count.
    INC  (HL)                           ; The newly filled frame is now on the stack.
    XOR  A                              ; Return with carry clear.
    RET                                 ; Preserve the new active-state byte in RAM.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate ELSE and select parent-active AND NOT original-condition.

ppFlip: ; Select the unused ELSE branch.
    LD   A,(ppBase)                     ; This part's frames begin above its base.
    LD   B,A                            ; Keep the base.
    LD   A,(ppDepth)                    ; An ELSE needs one open IF frame of this part.
    CP   B                              ; Equal means none is open here.
    JP   Z,ppFail                       ; Reject ELSE without IF.
    DEC  A                              ; Select the most recent frame.
    LD   C,A                            ; Keep its stack index in C.
    LD   B,0                            ; Extend the index to a word.
    LD   HL,ppStack                     ; Address the first frame.
    ADD  HL,BC                          ; Select the current frame.
    BIT  2,(HL)                         ; Test whether ELSE already appeared.
    JP   NZ,ppFail                      ; Reject a second ELSE in one IF.
    SET  2,(HL)                         ; Record that ELSE has selected this frame.
    LD   A,(HL)                         ; Load parent-active and original-condition.
    AND  3                              ; Ignore ELSE and include bookkeeping bits.
    CP   1                              ; Only active parent plus false IF selects ELSE.
    LD   A,0                            ; Prepare an inactive alternate branch.
    JR   NZ,.store                      ; All other combinations remain inactive.
    INC  A                              ; Enable the sole selected alternate case.
.store: ; Publish activity for the alternate branch.
    LD   (ppActive),A                   ; Publish activity for the alternate branch.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Keep the updated stack frame.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pop one condition and restore the activity of its enclosing parent.

ppPop: ; Pop one frame and restore its parent activity.
    LD   A,(ppBase)                     ; This part's frames begin above its base.
    LD   B,A                            ; Keep the base.
    LD   A,(ppDepth)                    ; An ENDIF needs an open frame of this part.
    CP   B                              ; Equal means none is open here.
    JP   Z,ppFail                       ; Reject ENDIF without IF.
    DEC  A                              ; Select the frame being closed.
    LD   C,A                            ; Keep its index while loading the frame.
    LD   B,0                            ; Extend the index to sixteen bits.
    LD   HL,ppStack                     ; Address the first stack frame.
    ADD  HL,BC                          ; Select the frame to pop.
    LD   A,(HL)                         ; Bit zero is the enclosing activity.
    AND  1                              ; Discard every field local to the closing IF.
    LD   (ppActive),A                   ; Restore the enclosing conditional state.
    LD   HL,ppDepth                     ; Address the frame count.
    DEC  (HL)                           ; Pop exactly one condition.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The stale byte is ignored beyond the new depth.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mark every enclosing IF whose active header contains an include directive.

ppMark: ; Mark open frames containing a header include.
    PUSH HL                             ; The include parser owns the source cursor.
    CALL ppOwn                          ; Address this part's open frames.
    JR   Z,.done                        ; Unconditional include needs no frame.
.loop: ; Mark each enclosing frame.
    LD   A,(HL)                         ; Load this frame's packed state.
    OR   8                              ; Bit three means its include has not closed yet.
    LD   (HL),A                         ; Keep nested include scope on each parent.
    INC  HL                             ; Advance to the next one-byte frame.
    DJNZ .loop                          ; Mark all active nesting ancestors.
.done: ; Restore the include source cursor.
    POP  HL                             ; Restore the cursor following the include name.
    RET                                 ; The scanner checks these bits at source start.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return carry when ordinary source begins inside a conditional include.

ppScope: ; Check ordinary source against include-bearing IF frames.
    PUSH HL                             ; Preserve the source reader's current offset.
    LD   A,(incHead)                    ; Restrict conditional imports to the header.
    OR   A                              ; A closed header cannot accept an import.
    JR   Z,.done                        ; Let the parser report a late import.
    CALL ppOwn                          ; Address this part's open frames.
    JR   Z,.done                        ; None constrains its source order.
.loop: ; Inspect each still-open frame.
    BIT  3,(HL)                         ; Has this frame seen an include before ENDIF?
    JR   NZ,.bad                        ; Reject ordinary source inside header.
    INC  HL                             ; Advance to the next frame.
    DJNZ .loop                          ; Check every still-open ancestor.
    XOR  A                              ; No include-bearing condition remains open.
    JR   .done                          ; Restore the source cursor on success.
.bad: ; Reject source inside an import condition.
    SCF                                 ; Mark ordinary source inside an import condition.
.done: ; Restore the caller source cursor.
    POP  HL                             ; Keep the caller's logical source offset intact.
    RET                                 ; Return carry clear for ordinary source.


;@ROUTINE OUT A,B,HL,CARRY,ZERO CLOBBERS DE,SIGN,PARITY,HALFCARRY
; Address this part's open IF frames: those above its condition base. HL
; is the first and B the count. Z means there are none.

ppOwn: ; Address the current part's open conditional frames.
    LD   A,(ppBase)                     ; Frames below the base belong to includers.
    LD   E,A                            ; Index the part's first frame.
    LD   D,0                            ; Widen it.
    LD   HL,ppStack                     ; Address the stack.
    ADD  HL,DE                          ; Address the part's first frame.
    LD   A,(ppDepth)                    ; Count the part's frames.
    SUB  E                              ; Depth less base.
    LD   B,A                            ; Return the count.
    RET                                 ; Z when it is zero.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the directive byte at HL and advance HL. The captured line ends in
; CR, so a parser never reads past it.

ppNext: ; Read the next byte of the captured directive.
    LD   A,(HL)                         ; Read the byte.
    INC  HL                             ; Advance the cursor.
    OR   A                              ; Clear carry.
    RET                                 ; Return it.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Read one whitespace-delimited ASCII token, leaving its delimiter unread.

ppGetTok: ; Read one bounded uppercase token.
    XOR  A                              ; Begin with an empty token.
    LD   (ppTokLen),A                   ; Reset the bounded token length.
.loop: ; Scan token characters or leading whitespace.
    CALL ppNext                         ; Read the next directive character.
    CP   ' '                            ; Horizontal spaces delimit tokens.
    JR   Z,.space                       ; Skip leading spaces or finish a token.
    CP   9                              ; Tabs have the same token-boundary meaning.
    JR   Z,.space                       ; Skip leading tabs or finish a token.
    CP   13                             ; CR ends the directive.
    JR   Z,.end                         ; Leave it for the line validator.
    LD   B,A                            ; Keep the character while checking capacity.
    LD   A,(ppTokLen)                   ; Read the token length so far.
    CP   17                             ; The fixed token buffer holds at most 17 bytes.
    JR   NC,.bad                        ; Reject a token beyond the native limit.
    LD   C,A                            ; Use the current length as the array index.
    LD   A,B                            ; Restore the character.
    CP   'a'                            ; Check for an ASCII lowercase letter.
    JR   C,.append                      ; Keep uppercase and punctuation unchanged.
    CP   'z'+1                          ; Check the exclusive lowercase upper bound.
    JR   NC,.append                     ; Leave bytes beyond 'z' unchanged.
    AND  $DF                            ; Fold lowercase ASCII to uppercase.
.append: ; Append one normalised token byte.
    PUSH HL                             ; Keep the directive cursor.
    LD   B,0                            ; The token index is less than eighteen.
    LD   HL,ppToken                     ; Select the fixed token buffer.
    ADD  HL,BC                          ; Address the next available byte.
    LD   (HL),A                         ; Append the character.
    POP  HL                             ; Restore the directive cursor.
    LD   A,(ppTokLen)                   ; Reload the stored token length.
    INC  A                              ; Count the character just appended.
    LD   (ppTokLen),A                   ; Publish the new bounded length.
    JR   .loop                          ; Continue until whitespace or line end.
.space: ; Distinguish leading from trailing whitespace.
    LD   A,(ppTokLen)                   ; Determine whether a token has started.
    OR   A                              ; Leading whitespace is ignored.
    JR   Z,.loop                        ; Keep looking for the first token byte.
.end: ; Leave the delimiter unread for its caller.
    DEC  HL                             ; Leave the delimiter for the next parser.
    LD   A,(ppTokLen)                   ; Reject an empty token at the line end.
    OR   A                              ; A zero length means a required value is absent.
    JR   Z,.bad                         ; Report the missing token.
    OR   A                              ; Clear carry and classify the token length.
    RET                                 ; HL still points at its first trailing delimiter.
.bad: ; Reject an absent or overlong token.
    SCF                                 ; Carry reports malformed or overlong input.
    RET                                 ; The caller selects the directive diagnostic.

;@ROUTINE IN HL,B OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Compare B token bytes with the uppercase word at HL.

ppMatch: ; Match the complete uppercase directive keyword.
    LD   A,(ppTokLen)                   ; Require an exact keyword length.
    CP   B                              ; A prefix must not match a directive.
    RET  NZ                             ; Leave the comparison result in flags.
    LD   DE,ppToken                     ; Start at the normalised directive token.
.loop: ; Compare corresponding token and keyword bytes.
    LD   A,(DE)                         ; Read the next source token byte.
    CP   (HL)                           ; Compare it with the selected keyword byte.
    RET  NZ                             ; Stop at the first mismatched character.
    INC  DE                             ; Advance through the token.
    INC  HL                             ; Advance through the keyword.
    DJNZ .loop                          ; Compare every letter in the keyword.
    XOR  A                              ; Return Z for a complete keyword match.
    RET                                 ; The caller can branch on exact equality.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Accept only whitespace before the directive's end. A trailing comment was
; left out when the directive was captured.

ppEol: ; Validate whitespace to the line end.
    CALL ppNext                         ; Inspect the byte after the final token.
    CP   ' '                            ; Permit trailing horizontal whitespace.
    JR   Z,ppEol                        ; Skip another space.
    CP   9                              ; Permit trailing tabs as well.
    JR   Z,ppEol                        ; Skip another tab.
    CP   13                             ; The directive must end here.
    RET  Z                              ; Accept it with carry clear.
    SCF                                 ; Any other byte is an extra argument.
    RET                                 ; Reject it.
