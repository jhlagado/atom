; CP/M implementation of Atom's source-level definitions and conditions.
;
; The resolver evaluates directives before assembly to choose active includes.
; The source-byte adapter repeats only the conditional state changes while the
; tokenizer reads forward. Directive bytes become comments. inactive text
; becomes spaces, with every original line ending and byte offset preserved.
; Defines are numeric and case-insensitive. names hold up to 17 characters.
; The native profile supports 32 definitions and 16 nested conditional levels.

;@ROUTINE IN incIdx OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Reset conditional state for one resolver scan. Root rescans rebuild defines.

ppClear: ; Reset preflight conditions and root definitions.
    XOR  A                              ; A is the empty conditional depth.
    LD   (ppDepth),A                    ; Each source part starts outside a conditional.
    INC  A                              ; Active source is the default branch.
    LD   (ppActive),A                   ; No enclosing condition disables this file.
    LD   A,(incIdx)                     ; Select the original source ordinal.
    OR   A                              ; Only ordinal zero is the entry file.
    JR   NZ,.notRoot                    ; Includes cannot define host values.
    XOR  A                              ; Rebuild root definitions on each root scan.
    LD   (ppDefCnt),A                   ; Reset definitions for each scan.
    LD   A,1                            ; Definitions may begin in the root header.
    LD   (ppDefOk),A                    ; Close the define header at its first boundary.
    RET                                 ; Keep the empty table ready for root defines.
.notRoot: ; Keep root definitions while scanning a dependency.
    XOR  A                              ; A dependency cannot declare definitions.
    LD   (ppDefOk),A                    ; Its conditions use the root's table only.
    RET                                 ; Return with root values still available.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Reset per-part runtime state without clearing the definitions found earlier.

ppReset: ; Reset runtime conditions for a new source part.
    XOR  A                              ; Clear conditional depth and select its base.
    LD   (ppDepth),A                    ; Nested conditions never cross a source part.
    INC  A                              ; The first line is active by default.
    LD   (ppActive),A                   ; Show ordinary source until an IF disables it.
    LD   HL,$FFFF                       ; Use a sentinel outside valid byte offsets.
    LD   (ppDirOff),HL                  ; A repeated peek must not apply IF twice.
    RET                                 ; Preserve the preflight definition table.

;@ROUTINE IN HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and apply one line-leading directive during graph preflight.
; HL enters after '%'. A=1 means an include is waiting for its child.

ppScan: ; Dispatch a line-leading preflight directive.
    LD   (ppWord),HL                    ; Save the INCLUDE keyword position.
    CALL ppGetTok                       ; Read the directive name into the shared buffer.
    JP   C,ppErr                        ; Empty or overlong words are malformed.
    LD   (ppSrcPtr),HL                  ; Save the source position while matching.
    LD   HL,ppKeyInc                    ; Select the longest supported directive.
    LD   B,7                            ; INCLUDE has seven letters.
    CALL ppMatch                        ; Compare case-folded token bytes.
    JR   Z,ppIncl                       ; Reuse the established 8.3 include parser.
    LD   HL,ppKeyDef                    ; Check for a root numeric definition.
    LD   B,6                            ; DEFINE has six letters.
    CALL ppMatch                        ; Reject any other six-byte token later.
    JR   Z,ppDefine                     ; Validate scope, name and value.
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
    LD   DE,msgDir                      ; Select unsupported-directive detail.
    SCF                                 ; Carry marks the incomplete source profile.
    RET                                 ; No output generation has begun.
ppIncl: ; Validate an include in the source header.
    LD   A,(incHead)                    ; Includes belong to the leading header only.
    OR   A                              ; Test whether ordinary source already began.
    JR   Z,.late                        ; Reject late imports before opening files.
    XOR  A                              ; Any include closes the definition preamble.
    LD   (ppDefOk),A                    ; Defines must precede includes and conditions.
    LD   HL,(ppWord)                    ; Restore the cursor immediately after '%'.
    JP   incLine                        ; Parse its filename and active dependency.
.late: ; Reject an include after ordinary source.
    LD   DE,msgInc                      ; Select malformed-include detail.
    SCF                                 ; Carry rejects the source before output starts.
    RET                                 ; Return the include-specific message.
ppDefine: ; Validate an entry-header numeric definition.
    LD   A,(incIdx)                     ; Only the entry source may define values.
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
    XOR  A                              ; Definitions do not defer an include part.
    RET                                 ; Continue scanning this source file.
ppIf: ; Evaluate and push a preflight IF.
    XOR  A                              ; IF closes the definition preamble.
    LD   (ppDefOk),A                    ; No define may appear after conditional logic.
    LD   HL,(ppSrcPtr)                  ; Start after the IF keyword.
    CALL ppPush                         ; Evaluate the condition and push its frame.
    JP   C,ppErr                        ; Select the public directive error on failure.
    RET                                 ; Continue with the newly selected branch.
ppElse: ; Validate and select a preflight ELSE.
    XOR  A                              ; ELSE also closes the definition preamble.
    LD   (ppDefOk),A                    ; Close define header, even when inactive.
    LD   HL,(ppSrcPtr)                  ; Start at the directive's trailing text.
    CALL ppEol                          ; Require only whitespace or a comment.
    JP   C,ppErr                        ; Reject arguments after ELSE.
    LD   (ppAfter),HL                   ; Save cursor while changing the branch.
    CALL ppFlip                         ; Validate and activate the alternate branch.
    JP   C,ppErr                        ; Report unmatched or duplicate ELSE consistently.
    XOR  A                              ; ELSE is a consumed directive, not a dependency.
    LD   HL,(ppAfter)                   ; Resume after the validated directive line.
    RET                                 ; Continue with the new branch state.
ppEndIf: ; Validate and close a preflight IF.
    XOR  A                              ; ENDIF closes the definition preamble too.
    LD   (ppDefOk),A                    ; Header state is tracked separately.
    LD   HL,(ppSrcPtr)                  ; Validate the rest of the physical line.
    CALL ppEol                          ; ENDIF accepts no arguments.
    JP   C,ppErr                        ; Reject extra words after ENDIF.
    LD   (ppAfter),HL                   ; Save cursor before popping frame.
    CALL ppPop                          ; Restore the parent branch's activity.
    JP   C,ppErr                        ; Report an unmatched ENDIF consistently.
    XOR  A                              ; No dependency is pending after ENDIF.
    LD   HL,(ppAfter)                   ; Resume after the validated directive line.
    RET                                 ; Continue scanning the current source.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; At runtime, apply conditional state once for a directive's source offset.

ppApply: ; Replay a directive state change during source reads.
    LD   (ppWord),HL                    ; Save the cursor immediately after '%'.
    CALL ppGetTok                       ; Read the keyword without changing source bytes.
    JP   C,.changed                     ; Reject source that changed after preflight.
    LD   (ppSrcPtr),HL                  ; Save the cursor before testing keywords.
    LD   HL,ppKeyIf                     ; IF changes the active source state.
    LD   B,2                            ; Match exactly the IF keyword.
    CALL ppMatch                        ; Keep the source cursor in workspace.
    JR   Z,.if                          ; Apply one frame for this offset.
    LD   HL,ppKeyAlt                    ; ELSE selects the remaining branch.
    LD   B,4                            ; Match exactly four letters.
    CALL ppMatch                        ; Do not accept an ELSE-like prefix.
    JR   Z,.else                        ; Validate and toggle the top frame.
    LD   HL,ppKeyEnd                    ; ENDIF restores its parent's activity.
    LD   B,5                            ; Match exactly five letters.
    CALL ppMatch                        ; Keep IF stack boundaries explicit.
    JR   Z,.endIf                       ; Pop one frame after checking arguments.
    LD   A,0                            ; Other directives leave state unchanged.
    OR   A                              ; Clear carry for the source-byte adapter.
    RET                                 ; INCLUDE and DEFINE remain comments at runtime.
.if: ; Evaluate the runtime IF condition.
    LD   HL,(ppSrcPtr)                  ; Continue after the IF keyword.
    CALL ppPush                         ; Repeat the same value and nesting rules.
    RET                                 ; Carry means the source changed after preflight.
.else: ; Validate the runtime ELSE line.
    LD   HL,(ppSrcPtr)                  ; Check trailing text before state changes.
    CALL ppEol                          ; An ELSE argument is never silently ignored.
    JR   C,.changed                     ; Reject mutation after source preflight.
    CALL ppFlip                         ; Toggle only a valid top-level frame.
    RET                                 ; Preserve the condition result.
.endIf: ; Validate the runtime ENDIF line.
    LD   HL,(ppSrcPtr)                  ; Check the complete directive line first.
    CALL ppEol                          ; ENDIF takes no operands.
    JR   C,.changed                     ; Reject changed or malformed input.
    CALL ppPop                          ; Restore the parent activity.
    RET                                 ; Return the updated conditional state.
.changed: ; Reject source changes after preflight.
    LD   A,2                            ; Signal that the source changed after preflight.
    SCF                                 ; Report a source-read failure.
    RET                                 ; Never assemble with uncertain condition state.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
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

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
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
    LD   A,(ppDepth)                    ; An ELSE needs one open IF frame.
    OR   A                              ; Zero denotes an unmatched directive.
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
    LD   A,(ppDepth)                    ; An ENDIF needs an open frame.
    OR   A                              ; Zero denotes an unmatched directive.
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

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mark every enclosing IF whose active header contains an include directive.

ppMark: ; Mark open frames containing a header include.
    PUSH HL                             ; The include parser owns the source cursor.
    LD   A,(ppDepth)                    ; No frame needs a marker outside conditionals.
    OR   A                              ; Avoid touching the empty stack.
    JR   Z,.done                        ; Unconditional include needs no frame.
    LD   B,A                            ; Visit every open frame.
    LD   HL,ppStack                     ; Start with the outermost IF.
.loop: ; Mark each enclosing frame.
    LD   A,(HL)                         ; Load this frame's packed state.
    OR   8                              ; Bit three means its include has not closed yet.
    LD   (HL),A                         ; Keep nested include scope on each parent.
    INC  HL                             ; Advance to the next one-byte frame.
    DJNZ .loop                          ; Mark all active nesting ancestors.
.done: ; Restore the include source cursor.
    POP  HL                             ; Restore the cursor following the include name.
    RET                                 ; The scanner checks these bits at source start.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return carry when ordinary source begins inside a conditional include.

ppScope: ; Check ordinary source against include-bearing IF frames.
    PUSH HL                             ; Preserve the source reader's current offset.
    LD   A,(incHead)                    ; Restrict conditional imports to the header.
    OR   A                              ; A closed header cannot accept an import.
    JR   Z,.done                        ; Let the parser report a late import.
    LD   A,(ppDepth)                    ; Closed frames no longer constrain source order.
    OR   A                              ; An empty stack makes ordinary source safe.
    JR   Z,.done                        ; Continue without scanning the table.
    LD   B,A                            ; Examine the currently open frames.
    LD   HL,ppStack                     ; Begin at the outermost conditional.
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

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Read one whitespace-delimited ASCII token, leaving its delimiter unread.

ppGetTok: ; Read one bounded uppercase token.
    XOR  A                              ; Begin with an empty token.
    LD   (ppTokLen),A                   ; Reset the bounded token length.
.loop: ; Scan token characters or leading whitespace.
    CALL srcNext                        ; Read the next raw source character.
    JR   C,.eof                         ; EOF ends a complete trailing token.
    CP   ' '                            ; Horizontal spaces delimit tokens.
    JR   Z,.space                       ; Skip leading spaces or finish a token.
    CP   9                              ; Tabs have the same token-boundary meaning.
    JR   Z,.space                       ; Skip leading tabs or finish a token.
    CP   ';'                            ; Semicolon begins a source comment.
    JR   Z,.end                         ; Leave ';' for trailing-text validation.
    CP   13                             ; CR terminates this physical line.
    JR   Z,.end                         ; Leave CR for the line validator.
    CP   10                             ; LF also terminates a directive line.
    JR   Z,.end                         ; Preserve LF for the trailing validator.
    LD   B,A                            ; Keep the character while checking capacity.
    LD   A,(ppTokLen)                   ; Read the token length so far.
    CP   17                             ; The fixed token buffer holds at most 17 bytes.
    JR   NC,.bad                        ; Reject a token beyond the native limit.
    LD   C,A                            ; Use the current length as the array index.
    LD   A,B                            ; Restore the source character.
    CP   'a'                            ; Check for an ASCII lowercase letter.
    JR   C,.append                      ; Keep uppercase and punctuation unchanged.
    CP   'z'+1                          ; Check the exclusive lowercase upper bound.
    JR   NC,.append                     ; Leave bytes beyond 'z' unchanged.
    AND  $DF                            ; Fold lowercase ASCII to uppercase.
.append: ; Append one normalised token byte.
    LD   (ppTemp),A                     ; Save the normalised byte during indexing.
    LD   (ppSrcPtr),HL                  ; Save the source cursor while indexing.
    LD   A,C                            ; Load the token's current length.
    LD   C,A                            ; Form its low-byte address offset.
    LD   B,0                            ; The token index is less than eighteen.
    LD   HL,ppToken                     ; Select the fixed token buffer.
    ADD  HL,BC                          ; Address the next available byte.
    LD   A,(ppTemp)                     ; Restore the normalised character.
    LD   (HL),A                         ; Append it without changing source offsets.
    LD   HL,(ppSrcPtr)                  ; Resume after the token byte just read.
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
    LD   A,(ppTokLen)                   ; Reject an empty token at comment or EOL.
    OR   A                              ; A zero length means a required value is absent.
    JR   Z,.bad                         ; Report the missing token.
    OR   A                              ; Clear carry and classify the token length.
    RET                                 ; HL still points at its first trailing delimiter.
.eof: ; Complete a token at ordinary EOF.
    OR   A                              ; A=0 is ordinary EOF. A=2 is source overflow.
    JR   NZ,.bad                        ; Do not accept a wrapped source cursor.
    LD   A,(ppTokLen)                   ; An EOF may finish a nonempty token.
    OR   A                              ; Reject EOF before any required token.
    JR   Z,.bad                         ; The caller will print a directive error.
    OR   A                              ; Return the complete final token.
    RET                                 ; The source cursor remains at EOF.
.bad: ; Reject an absent or overlong token.
    SCF                                 ; Carry reports malformed or overlong input.
    RET                                 ; The caller selects the directive diagnostic.

;@ROUTINE IN HL,B OUT A,ZERO CLOBBERS BC,DE,HL
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

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Accept end of line or a complete trailing comment.

ppEol: ; Validate whitespace, comment or line end.
    CALL srcNext                        ; Inspect the byte after the final token.
    JR   C,.eof                         ; EOF is a valid directive terminator.
    CP   ' '                            ; Permit trailing horizontal whitespace.
    JR   Z,ppEol                        ; Skip another space.
    CP   9                              ; Permit trailing tabs as well.
    JR   Z,ppEol                        ; Skip another tab.
    CP   ';'                            ; An ordinary semicolon begins a comment.
    JR   Z,.comment                     ; Consume its remaining physical line.
    CP   13                             ; Accept a carriage-return line ending.
    JR   Z,.ok                          ; Leave the next LF for the outer scanner.
    CP   10                             ; Accept LF-only source files.
    JR   Z,.ok                          ; The next byte begins a new physical line.
    SCF                                 ; Any other byte is an extra argument.
    RET                                 ; Reject it before the assembler processes it.
.comment: ; Consume a trailing source comment.
    CALL srcSkip                        ; Consume the validated trailing comment.
    JR   C,.eof                         ; EOF is valid. overflow is not.
    XOR  A                              ; The comment ended at a normal line break.
    RET                                 ; Continue scanning the following line.
.eof: ; Accept EOF unless the source offset overflowed.
    OR   A                              ; A=0 means EOF. A=2 means offset overflow.
    RET  Z                              ; Accept an ordinary end of file.
    SCF                                 ; Reject a source offset that wrapped.
    RET                                 ; Leave the caller's source scan failed.
.ok: ; Accept a consumed line ending.
    XOR  A                              ; A normal line ending is valid.
    RET                                 ; HL points beyond the consumed line-ending byte.
