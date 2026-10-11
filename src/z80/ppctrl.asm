; CP/M implementation of Atom's source-level definitions and conditions.
;
; The resolver evaluates directives before assembly to choose active includes.
; The source-byte adapter repeats only the conditional state changes while the
; tokenizer reads forward. Directive bytes become comments. inactive text
; becomes spaces, with every original line ending and byte offset preserved.
; Defines are numeric and case-insensitive. names hold up to 17 characters.
; The native profile supports 32 definitions and 16 nested conditional levels.

;@ROUTINE IN INC_IDX OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Reset conditional state for one resolver scan. Root rescans rebuild defines.

PP_CLEAR: ; Reset preflight conditions and root definitions.
    XOR  A                              ; A is the empty conditional depth.
    LD   (PP_DEPTH),A                   ; Each source part starts outside a conditional.
    INC  A                              ; Active source is the default branch.
    LD   (PP_LIVE),A                    ; No enclosing condition disables this file.
    LD   A,(INC_IDX)                    ; Select the original source ordinal.
    OR   A                              ; Only ordinal zero is the entry file.
    JR   NZ,.NOTROOT                    ; Includes cannot define host values.
    XOR  A                              ; Rebuild root definitions on each root scan.
    LD   (PP_NDEFS),A                   ; Reset definitions for each scan.
    LD   A,1                            ; Definitions may begin in the root header.
    LD   (PP_DEFOK),A                   ; Close the define header at its first boundary.
    RET                                 ; Keep the empty table ready for root defines.
.NOTROOT: ; Keep root definitions while scanning a dependency.
    XOR  A                              ; A dependency cannot declare definitions.
    LD   (PP_DEFOK),A                   ; Its conditions use the root's table only.
    RET                                 ; Return with root values still available.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Reset per-part runtime state without clearing the definitions found earlier.

PP_RESET: ; Reset runtime conditions for a new source part.
    XOR  A                              ; Clear conditional depth and select its base.
    LD   (PP_DEPTH),A                   ; Nested conditions never cross a source part.
    INC  A                              ; The first line is active by default.
    LD   (PP_LIVE),A                    ; Show ordinary source until an IF disables it.
    LD   HL,$FFFF                       ; Use a sentinel outside valid byte offsets.
    LD   (PP_LAST),HL                   ; A repeated peek must not apply IF twice.
    RET                                 ; Preserve the preflight definition table.

;@ROUTINE IN HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and apply one line-leading directive during graph preflight.
; HL enters after '%'. A=1 means an include is waiting for its child.

PP_SCAN: ; Dispatch a line-leading preflight directive.
    LD   (PP_WORD),HL                   ; Save the INCLUDE keyword position.
    CALL PP_READ                        ; Read the directive name into the shared buffer.
    JP   C,PP_ERR                       ; Empty or overlong words are malformed.
    LD   (PP_SRC),HL                    ; Save the source position while matching.
    LD   HL,PP_KINCL                    ; Select the longest supported directive.
    LD   B,7                            ; INCLUDE has seven letters.
    CALL PP_MATCH                       ; Compare case-folded token bytes.
    JR   Z,PP_INCL                      ; Reuse the established 8.3 include parser.
    LD   HL,PP_KDEF                     ; Check for a root numeric definition.
    LD   B,6                            ; DEFINE has six letters.
    CALL PP_MATCH                       ; Reject any other six-byte token later.
    JR   Z,PP_DEF                       ; Validate scope, name and value.
    LD   HL,PP_KEND                     ; Check the five-byte closing directive.
    LD   B,5                            ; ENDIF has five letters.
    CALL PP_MATCH                       ; Match the complete token, not a prefix.
    JR   Z,PP_ENDIF                     ; Pop one condition after its line is valid.
    LD   HL,PP_KELSE                    ; Check the four-byte alternate directive.
    LD   B,4                            ; ELSE has four letters.
    CALL PP_MATCH                       ; Match the full keyword.
    JR   Z,PP_ELSE                      ; Toggle the current conditional branch.
    LD   HL,PP_KIF                      ; Check the two-byte opening directive.
    LD   B,2                            ; IF has two letters.
    CALL PP_MATCH                       ; Match the complete keyword.
    JR   Z,PP_IF                        ; Evaluate and push a new condition.
PP_ERR: ; Return invalid-directive detail.
    LD   DE,MSG_DIR                     ; Select unsupported-directive detail.
    SCF                                 ; Carry marks the incomplete source profile.
    RET                                 ; No output generation has begun.
PP_INCL: ; Validate an include in the source header.
    LD   A,(INC_HEAD)                   ; Includes belong to the leading header only.
    OR   A                              ; Test whether ordinary source already began.
    JR   Z,.LATE                        ; Reject late imports before opening files.
    XOR  A                              ; Any include closes the definition preamble.
    LD   (PP_DEFOK),A                   ; Defines must precede includes and conditions.
    LD   HL,(PP_WORD)                   ; Restore the cursor immediately after '%'.
    JP   INC_LINE                       ; Parse its filename and active dependency.
.LATE: ; Reject an include after ordinary source.
    LD   DE,MSG_INC                     ; Select malformed-include detail.
    SCF                                 ; Carry rejects the source before output starts.
    RET                                 ; Return the include-specific message.
PP_DEF: ; Validate an entry-header numeric definition.
    LD   A,(INC_IDX)                    ; Only the entry source may define values.
    OR   A                              ; Source ordinal zero identifies the root.
    JP   NZ,PP_ERR                      ; Reject definitions in included files.
    LD   A,(INC_HEAD)                   ; Require the root's leading header.
    OR   A                              ; Ordinary source permanently closes it.
    JP   Z,PP_ERR                       ; Reject a late definition.
    LD   A,(PP_DEFOK)                   ; Defines must precede includes and IF blocks.
    OR   A                              ; Zero means the preamble is already closed.
    JP   Z,PP_ERR                       ; Reject definitions after preprocessing begins.
    LD   HL,(PP_SRC)                    ; Start after the DEFINE directive name.
    CALL PP_PARSE                       ; Store one unique name and numeric value.
    JP   C,PP_ERR                       ; Select the public directive error on failure.
    XOR  A                              ; Definitions do not defer an include part.
    RET                                 ; Continue scanning this source file.
PP_IF: ; Evaluate and push a preflight IF.
    XOR  A                              ; IF closes the definition preamble.
    LD   (PP_DEFOK),A                   ; No define may appear after conditional logic.
    LD   HL,(PP_SRC)                    ; Start after the IF keyword.
    CALL PP_PUSH                        ; Evaluate the condition and push its frame.
    JP   C,PP_ERR                       ; Select the public directive error on failure.
    RET                                 ; Continue with the newly selected branch.
PP_ELSE: ; Validate and select a preflight ELSE.
    XOR  A                              ; ELSE also closes the definition preamble.
    LD   (PP_DEFOK),A                   ; Close define header, even when inactive.
    LD   HL,(PP_SRC)                    ; Start at the directive's trailing text.
    CALL PP_EOL                         ; Require only whitespace or a comment.
    JP   C,PP_ERR                       ; Reject arguments after ELSE.
    LD   (PP_AFTER),HL                  ; Save cursor while changing the branch.
    CALL PP_FLIP                        ; Validate and activate the alternate branch.
    JP   C,PP_ERR                       ; Report unmatched or duplicate ELSE consistently.
    XOR  A                              ; ELSE is a consumed directive, not a dependency.
    LD   HL,(PP_AFTER)                  ; Resume after the validated directive line.
    RET                                 ; Continue with the new branch state.
PP_ENDIF: ; Validate and close a preflight IF.
    XOR  A                              ; ENDIF closes the definition preamble too.
    LD   (PP_DEFOK),A                   ; Header state is tracked separately.
    LD   HL,(PP_SRC)                    ; Validate the rest of the physical line.
    CALL PP_EOL                         ; ENDIF accepts no arguments.
    JP   C,PP_ERR                       ; Reject extra words after ENDIF.
    LD   (PP_AFTER),HL                  ; Save cursor before popping frame.
    CALL PP_POP                         ; Restore the parent branch's activity.
    JP   C,PP_ERR                       ; Report an unmatched ENDIF consistently.
    XOR  A                              ; No dependency is pending after ENDIF.
    LD   HL,(PP_AFTER)                  ; Resume after the validated directive line.
    RET                                 ; Continue scanning the current source.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; At runtime, apply conditional state once for a directive's source offset.

PP_APPLY: ; Replay a directive state change during source reads.
    LD   (PP_WORD),HL                   ; Save the cursor immediately after '%'.
    CALL PP_READ                        ; Read the keyword without changing source bytes.
    JP   C,.CHANGED                     ; Reject source that changed after preflight.
    LD   (PP_SRC),HL                    ; Save the cursor before testing keywords.
    LD   HL,PP_KIF                      ; IF changes the active source state.
    LD   B,2                            ; Match exactly the IF keyword.
    CALL PP_MATCH                       ; Keep the source cursor in workspace.
    JR   Z,.IF                          ; Apply one frame for this offset.
    LD   HL,PP_KELSE                    ; ELSE selects the remaining branch.
    LD   B,4                            ; Match exactly four letters.
    CALL PP_MATCH                       ; Do not accept an ELSE-like prefix.
    JR   Z,.ELSE                        ; Validate and toggle the top frame.
    LD   HL,PP_KEND                     ; ENDIF restores its parent's activity.
    LD   B,5                            ; Match exactly five letters.
    CALL PP_MATCH                       ; Keep IF stack boundaries explicit.
    JR   Z,.ENDIF                       ; Pop one frame after checking arguments.
    LD   A,0                            ; Other directives leave state unchanged.
    OR   A                              ; Clear carry for the source-byte adapter.
    RET                                 ; INCLUDE and DEFINE remain comments at runtime.
.IF: ; Evaluate the runtime IF condition.
    LD   HL,(PP_SRC)                    ; Continue after the IF keyword.
    CALL PP_PUSH                        ; Repeat the same value and nesting rules.
    RET                                 ; Carry means the source changed after preflight.
.ELSE: ; Validate the runtime ELSE line.
    LD   HL,(PP_SRC)                    ; Check trailing text before state changes.
    CALL PP_EOL                         ; An ELSE argument is never silently ignored.
    JR   C,.CHANGED                     ; Reject mutation after source preflight.
    CALL PP_FLIP                        ; Toggle only a valid top-level frame.
    RET                                 ; Preserve the condition result.
.ENDIF: ; Validate the runtime ENDIF line.
    LD   HL,(PP_SRC)                    ; Check the complete directive line first.
    CALL PP_EOL                         ; ENDIF takes no operands.
    JR   C,.CHANGED                     ; Reject changed or malformed input.
    CALL PP_POP                         ; Restore the parent activity.
    RET                                 ; Return the updated conditional state.
.CHANGED: ; Reject source changes after preflight.
    LD   A,2                            ; Signal that the source changed after preflight.
    SCF                                 ; Report a source-read failure.
    RET                                 ; Never assemble with uncertain condition state.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one root definition. the name and value occupy separate work buffers.

PP_PARSE: ; Parse and insert a unique root definition.
    CALL PP_READ                        ; Read the case-insensitive definition name.
    JP   C,PP_ERR                       ; A definition needs a name.
    LD   (PP_SRC),HL                    ; Save delimiter while checking the name.
    CALL PP_STAGE                       ; Enforce the native name-field limit.
    JP   C,PP_ERR                       ; Reject invalid or overlong names.
    LD   (PP_NLEN),A                    ; Retain its length while reading the value.
    LD   HL,(PP_SRC)                    ; Resume where the name token ended.
    CALL PP_READ                        ; Skip whitespace and read one numeric value.
    JP   C,PP_ERR                       ; A definition needs a value.
    LD   (PP_SRC),HL                    ; Save delimiter while parsing the value.
    CALL PP_EVAL                        ; Resolve numeric syntax or a previous name.
    JP   C,PP_ERR                       ; Reject undefined names and values above 16 bits.
    LD   (PP_VALUE),HL                  ; Keep the value until the line end is checked.
    LD   HL,(PP_SRC)                    ; Resume at the delimiter after the value.
    CALL PP_EOL                         ; Only whitespace, a comment or EOL may follow.
    JP   C,PP_ERR                       ; Reject additional define operands.
    LD   (PP_AFTER),HL                  ; Save the next source position for lookup.
    CALL PP_COPY                        ; Reuse lookup with the staged name.
    CALL PP_FIND                        ; A pre-existing match is a duplicate definition.
    JP   NC,PP_ERR                      ; Reject duplicates even when values are equal.
    CALL PP_STORE                       ; Append the new value to the bounded table.
    RET  C                              ; A full table is an explicit profile error.
    LD   HL,(PP_AFTER)                  ; Restore next source position.
    RET                                 ; Carry reports a full definition table.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an IF value, validate its line, then push the computed condition.

PP_PUSH: ; Evaluate an IF and validate its trailing text.
    CALL PP_READ                        ; Read one number or prior definition name.
    JP   C,PP_ERR                       ; IF requires exactly one value.
    LD   (PP_SRC),HL                    ; Keep delimiter until evaluation ends.
    CALL PP_EVAL                        ; Unknown names fail only in an active parent.
    JP   C,PP_ERR                       ; Reject invalid values or active unknown names.
    LD   (PP_VALUE),HL                  ; Keep the result while checking trailing text.
    LD   HL,(PP_SRC)                    ; Resume at the trailing delimiter.
    CALL PP_EOL                         ; Require the directive to end after one value.
    JP   C,PP_ERR                       ; Reject operators and extra arguments.
    LD   (PP_AFTER),HL                  ; Save cursor before pushing the frame.
    LD   HL,(PP_VALUE)                  ; Restore the unsigned sixteen-bit value.
    LD   A,H                            ; Test its high byte.
    OR   L                              ; Either nonzero byte selects a true branch.
    LD   A,0                            ; Prepare the false condition.
    JR   Z,.PUSH                        ; Keep zero false.
    INC  A                              ; Convert any nonzero value to true.
.PUSH: ; Push the normalised truth value.
    CALL .FRAME                         ; Save parent state and update activity.
    RET  C                              ; Preserve a nesting-limit failure.
    LD   HL,(PP_AFTER)                  ; Continue after this physical line.
    RET                                 ; Return condition state and source position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push parent activity and the condition result into a sixteen-byte stack.

.FRAME: ; Encode one conditional-stack frame.
    LD   (PP_TMP),A                     ; Preserve the condition during pointer setup.
    LD   A,(PP_DEPTH)                   ; Read the number of existing frames.
    CP   16                             ; The fixed stack holds sixteen nested IFs.
    JP   NC,PP_FAIL                     ; Reject a seventeenth frame.
    LD   C,A                            ; Use the depth as the frame's byte index.
    LD   B,0                            ; Extend that index to a word.
    LD   HL,PP_STACK                    ; Begin at the first frame.
    ADD  HL,BC                          ; Select the next empty frame.
    LD   A,(PP_LIVE)                    ; Capture the enclosing branch's activity.
    OR   A                              ; Normalize it to one bit.
    LD   A,0                            ; A false parent stores no flag bits.
    JR   Z,.PARENT                      ; Keep the inactive parent clear.
    INC  A                              ; Bit zero marks an active parent.
.PARENT: ; Store the parent activity bit.
    LD   (HL),A                         ; Store the parent-active flag.
    LD   A,(PP_TMP)                     ; Read the condition selected by the directive.
    OR   A                              ; Zero leaves condition bit one clear.
    JR   Z,.RESULT                      ; Store a false condition under this frame.
    LD   A,(HL)                         ; Recover the frame's parent flag.
    OR   2                              ; Bit one records a true condition.
    LD   (HL),A                         ; Preserve both frame facts.
.RESULT: ; Combine parent and condition activity.
    LD   A,(HL)                         ; Read parent and condition bits together.
    AND  3                              ; Both bits must be set for an active branch.
    CP   3                              ; Value three means active parent and true IF.
    LD   A,0                            ; Prepare the inactive result.
    JR   NZ,.STORE                      ; A false parent or condition stays inactive.
    INC  A                              ; Mark the selected IF body active.
.STORE: ; Publish the selected branch activity.
    LD   (PP_LIVE),A                    ; Publish activity for following source bytes.
    LD   HL,PP_DEPTH                    ; Point at the one-byte frame count.
    INC  (HL)                           ; The newly filled frame is now on the stack.
    XOR  A                              ; Return with carry clear.
    RET                                 ; Preserve the new active-state byte in RAM.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate ELSE and select parent-active AND NOT original-condition.

PP_FLIP: ; Select the unused ELSE branch.
    LD   A,(PP_DEPTH)                   ; An ELSE needs one open IF frame.
    OR   A                              ; Zero denotes an unmatched directive.
    JP   Z,PP_FAIL                      ; Reject ELSE without IF.
    DEC  A                              ; Select the most recent frame.
    LD   C,A                            ; Keep its stack index in C.
    LD   B,0                            ; Extend the index to a word.
    LD   HL,PP_STACK                    ; Address the first frame.
    ADD  HL,BC                          ; Select the current frame.
    BIT  2,(HL)                         ; Test whether ELSE already appeared.
    JP   NZ,PP_FAIL                     ; Reject a second ELSE in one IF.
    SET  2,(HL)                         ; Record that ELSE has selected this frame.
    LD   A,(HL)                         ; Load parent-active and original-condition.
    AND  3                              ; Ignore ELSE and include bookkeeping bits.
    CP   1                              ; Only active parent plus false IF selects ELSE.
    LD   A,0                            ; Prepare an inactive alternate branch.
    JR   NZ,.STORE                      ; All other combinations remain inactive.
    INC  A                              ; Enable the sole selected alternate case.
.STORE: ; Publish activity for the alternate branch.
    LD   (PP_LIVE),A                    ; Publish activity for the alternate branch.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Keep the updated stack frame.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pop one condition and restore the activity of its enclosing parent.

PP_POP: ; Pop one frame and restore its parent activity.
    LD   A,(PP_DEPTH)                   ; An ENDIF needs an open frame.
    OR   A                              ; Zero denotes an unmatched directive.
    JP   Z,PP_FAIL                      ; Reject ENDIF without IF.
    DEC  A                              ; Select the frame being closed.
    LD   C,A                            ; Keep its index while loading the frame.
    LD   B,0                            ; Extend the index to sixteen bits.
    LD   HL,PP_STACK                    ; Address the first stack frame.
    ADD  HL,BC                          ; Select the frame to pop.
    LD   A,(HL)                         ; Bit zero is the enclosing activity.
    AND  1                              ; Discard every field local to the closing IF.
    LD   (PP_LIVE),A                    ; Restore the enclosing conditional state.
    LD   HL,PP_DEPTH                    ; Address the frame count.
    DEC  (HL)                           ; Pop exactly one condition.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; The stale byte is ignored beyond the new depth.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mark every enclosing IF whose active header contains an include directive.

PP_MARK: ; Mark open frames containing a header include.
    PUSH HL                             ; The include parser owns the source cursor.
    LD   A,(PP_DEPTH)                   ; No frame needs a marker outside conditionals.
    OR   A                              ; Avoid touching the empty stack.
    JR   Z,.DONE                        ; Unconditional include needs no frame.
    LD   B,A                            ; Visit every open frame.
    LD   HL,PP_STACK                    ; Start with the outermost IF.
.LOOP: ; Mark each enclosing frame.
    LD   A,(HL)                         ; Load this frame's packed state.
    OR   8                              ; Bit three means its include has not closed yet.
    LD   (HL),A                         ; Keep nested include scope on each parent.
    INC  HL                             ; Advance to the next one-byte frame.
    DJNZ .LOOP                          ; Mark all active nesting ancestors.
.DONE: ; Restore the include source cursor.
    POP  HL                             ; Restore the cursor following the include name.
    RET                                 ; The scanner checks these bits at source start.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return carry when ordinary source begins inside a conditional include.

PP_SCOPE: ; Check ordinary source against include-bearing IF frames.
    PUSH HL                             ; Preserve the source reader's current offset.
    LD   A,(INC_HEAD)                   ; Restrict conditional imports to the header.
    OR   A                              ; A closed header cannot accept an import.
    JR   Z,.DONE                        ; Let the parser report a late import.
    LD   A,(PP_DEPTH)                   ; Closed frames no longer constrain source order.
    OR   A                              ; An empty stack makes ordinary source safe.
    JR   Z,.DONE                        ; Continue without scanning the table.
    LD   B,A                            ; Examine the currently open frames.
    LD   HL,PP_STACK                    ; Begin at the outermost conditional.
.LOOP: ; Inspect each still-open frame.
    BIT  3,(HL)                         ; Has this frame seen an include before ENDIF?
    JR   NZ,.BAD                        ; Reject ordinary source inside header.
    INC  HL                             ; Advance to the next frame.
    DJNZ .LOOP                          ; Check every still-open ancestor.
    XOR  A                              ; No include-bearing condition remains open.
    JR   .DONE                          ; Restore the source cursor on success.
.BAD: ; Reject source inside an import condition.
    SCF                                 ; Mark ordinary source inside an import condition.
.DONE: ; Restore the caller source cursor.
    POP  HL                             ; Keep the caller's logical source offset intact.
    RET                                 ; Return carry clear for ordinary source.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Read one whitespace-delimited ASCII token, leaving its delimiter unread.

PP_READ: ; Read one bounded uppercase token.
    XOR  A                              ; Begin with an empty token.
    LD   (PP_TLEN),A                    ; Reset the bounded token length.
.LOOP: ; Scan token characters or leading whitespace.
    CALL SRC_NEXT                       ; Read the next raw source character.
    JR   C,.EOF                         ; EOF ends a complete trailing token.
    CP   ' '                            ; Horizontal spaces delimit tokens.
    JR   Z,.SPACE                       ; Skip leading spaces or finish a token.
    CP   9                              ; Tabs have the same token-boundary meaning.
    JR   Z,.SPACE                       ; Skip leading tabs or finish a token.
    CP   ';'                            ; Semicolon begins a source comment.
    JR   Z,.END                         ; Leave ';' for trailing-text validation.
    CP   13                             ; CR terminates this physical line.
    JR   Z,.END                         ; Leave CR for the line validator.
    CP   10                             ; LF also terminates a directive line.
    JR   Z,.END                         ; Preserve LF for the trailing validator.
    LD   B,A                            ; Keep the character while checking capacity.
    LD   A,(PP_TLEN)                    ; Read the token length so far.
    CP   17                             ; The fixed token buffer holds at most 17 bytes.
    JR   NC,.BAD                        ; Reject a token beyond the native limit.
    LD   C,A                            ; Use the current length as the array index.
    LD   A,B                            ; Restore the source character.
    CP   'a'                            ; Check for an ASCII lowercase letter.
    JR   C,.APPEND                      ; Keep uppercase and punctuation unchanged.
    CP   'z'+1                          ; Check the exclusive lowercase upper bound.
    JR   NC,.APPEND                     ; Leave bytes beyond 'z' unchanged.
    AND  $DF                            ; Fold lowercase ASCII to uppercase.
.APPEND: ; Append one normalised token byte.
    LD   (PP_TMP),A                     ; Save the normalised byte during indexing.
    LD   (PP_SRC),HL                    ; Save the source cursor while indexing.
    LD   A,C                            ; Load the token's current length.
    LD   C,A                            ; Form its low-byte address offset.
    LD   B,0                            ; The token index is less than eighteen.
    LD   HL,PP_TOKEN                    ; Select the fixed token buffer.
    ADD  HL,BC                          ; Address the next available byte.
    LD   A,(PP_TMP)                     ; Restore the normalised character.
    LD   (HL),A                         ; Append it without changing source offsets.
    LD   HL,(PP_SRC)                    ; Resume after the token byte just read.
    LD   A,(PP_TLEN)                    ; Reload the stored token length.
    INC  A                              ; Count the character just appended.
    LD   (PP_TLEN),A                    ; Publish the new bounded length.
    JR   .LOOP                          ; Continue until whitespace or line end.
.SPACE: ; Distinguish leading from trailing whitespace.
    LD   A,(PP_TLEN)                    ; Determine whether a token has started.
    OR   A                              ; Leading whitespace is ignored.
    JR   Z,.LOOP                        ; Keep looking for the first token byte.
.END: ; Leave the delimiter unread for its caller.
    DEC  HL                             ; Leave the delimiter for the next parser.
    LD   A,(PP_TLEN)                    ; Reject an empty token at comment or EOL.
    OR   A                              ; A zero length means a required value is absent.
    JR   Z,.BAD                         ; Report the missing token.
    OR   A                              ; Clear carry and classify the token length.
    RET                                 ; HL still points at its first trailing delimiter.
.EOF: ; Complete a token at ordinary EOF.
    OR   A                              ; A=0 is ordinary EOF. A=2 is source overflow.
    JR   NZ,.BAD                        ; Do not accept a wrapped source cursor.
    LD   A,(PP_TLEN)                    ; An EOF may finish a nonempty token.
    OR   A                              ; Reject EOF before any required token.
    JR   Z,.BAD                         ; The caller will print a directive error.
    OR   A                              ; Return the complete final token.
    RET                                 ; The source cursor remains at EOF.
.BAD: ; Reject an absent or overlong token.
    SCF                                 ; Carry reports malformed or overlong input.
    RET                                 ; The caller selects the directive diagnostic.

;@ROUTINE IN HL,B OUT A,ZERO CLOBBERS BC,DE,HL
; Compare B token bytes with the uppercase word at HL.

PP_MATCH: ; Match the complete uppercase directive keyword.
    LD   A,(PP_TLEN)                    ; Require an exact keyword length.
    CP   B                              ; A prefix must not match a directive.
    RET  NZ                             ; Leave the comparison result in flags.
    LD   DE,PP_TOKEN                    ; Start at the normalised directive token.
.LOOP: ; Compare corresponding token and keyword bytes.
    LD   A,(DE)                         ; Read the next source token byte.
    CP   (HL)                           ; Compare it with the selected keyword byte.
    RET  NZ                             ; Stop at the first mismatched character.
    INC  DE                             ; Advance through the token.
    INC  HL                             ; Advance through the keyword.
    DJNZ .LOOP                          ; Compare every letter in the keyword.
    XOR  A                              ; Return Z for a complete keyword match.
    RET                                 ; The caller can branch on exact equality.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Accept end of line or a complete trailing comment.

PP_EOL: ; Validate whitespace, comment or line end.
    CALL SRC_NEXT                       ; Inspect the byte after the final token.
    JR   C,.EOF                         ; EOF is a valid directive terminator.
    CP   ' '                            ; Permit trailing horizontal whitespace.
    JR   Z,PP_EOL                       ; Skip another space.
    CP   9                              ; Permit trailing tabs as well.
    JR   Z,PP_EOL                       ; Skip another tab.
    CP   ';'                            ; An ordinary semicolon begins a comment.
    JR   Z,.COMMENT                     ; Consume its remaining physical line.
    CP   13                             ; Accept a carriage-return line ending.
    JR   Z,.OK                          ; Leave the next LF for the outer scanner.
    CP   10                             ; Accept LF-only source files.
    JR   Z,.OK                          ; The next byte begins a new physical line.
    SCF                                 ; Any other byte is an extra argument.
    RET                                 ; Reject it before the assembler processes it.
.COMMENT: ; Consume a trailing source comment.
    CALL SRC_SKIP                       ; Consume the validated trailing comment.
    JR   C,.EOF                         ; EOF is valid. overflow is not.
    XOR  A                              ; The comment ended at a normal line break.
    RET                                 ; Continue scanning the following line.
.EOF: ; Accept EOF unless the source offset overflowed.
    OR   A                              ; A=0 means EOF. A=2 means offset overflow.
    RET  Z                              ; Accept an ordinary end of file.
    SCF                                 ; Reject a source offset that wrapped.
    RET                                 ; Leave the caller's source scan failed.
.OK: ; Accept a consumed line ending.
    XOR  A                              ; A normal line ending is valid.
    RET                                 ; HL points beyond the consumed line-ending byte.
