; CP/M implementation of Atom's source-level definitions and conditions.
;
; The resolver evaluates directives before assembly to choose active includes.
; The source-byte adapter repeats only the conditional state changes while the
; tokenizer reads forward. Directive bytes become comments; inactive text
; becomes spaces, with every original line ending and byte offset preserved.
; Defines are numeric and case-insensitive; names hold up to 17 characters.
; native profile supports 32 definitions and 16 nested conditional levels.

;@ROUTINE IN CP_SCAN_INDEX OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Reset conditional state for one resolver scan. Root rescans rebuild defines.

CP_PP_SCAN_RESET:
    XOR  A                  ; A is the empty conditional depth.
    LD   (CP_PP_DEPTH),A    ; Each source part starts outside a conditional.
    INC  A                  ; Active source is the default branch.
    LD   (CP_PP_ACTIVE),A   ; No enclosing condition disables this file.
    LD   A,(CP_SCAN_INDEX)  ; Select the original source ordinal.
    OR   A                  ; Only ordinal zero is the entry file.
    JR   NZ,CP_PP_SCAN_DEPENDENCY  ; Includes cannot define host values.
    XOR  A                  ; Rebuild root definitions on each root scan.
    LD   (CP_PP_DEFINE_COUNT),A  ; Reset definitions for each scan.
    LD   A,1                ; Definitions may begin in the root header.
    LD   (CP_PP_DEFS_OPEN),A  ; Close the define header at its first boundary.
    RET                     ; Keep the empty table ready for root defines.
CP_PP_SCAN_DEPENDENCY:
    XOR  A                  ; A dependency cannot declare definitions.
    LD   (CP_PP_DEFS_OPEN),A  ; Its conditions use the root's table only.
    RET                     ; Return with root values still available.

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; Reset per-part runtime state without clearing the definitions found earlier.

CP_PP_RUNTIME_RESET:
    XOR  A                  ; Clear conditional depth and select its base.
    LD   (CP_PP_DEPTH),A    ; Nested conditions never cross a source part.
    INC  A                  ; The first line is active by default.
    LD   (CP_PP_ACTIVE),A   ; Show ordinary source until an IF disables it.
    LD   HL,$FFFF           ; Use a sentinel outside valid byte offsets.
    LD   (CP_PP_LAST_DIRECTIVE),HL  ; A repeated peek must not apply IF twice.
    RET                     ; Preserve the preflight definition table.

;@ROUTINE IN HL OUT A,CARRY,DE CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and apply one line-leading directive during graph preflight.
; HL enters after '%'; A=1 means an include is waiting for its child.

CP_PP_SCAN_DIRECTIVE:
    LD   (CP_PP_WORD_START),HL  ; Save the INCLUDE keyword position.
    CALL CP_PP_READ_TOKEN   ; Read the directive name into the shared buffer.
    JP   C,CP_PP_INVALID    ; Empty or overlong words are malformed.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Save the source position while matching.
    LD   HL,CP_PP_WORD_INCLUDE  ; Select the longest supported directive.
    LD   B,7                ; INCLUDE has seven letters.
    CALL CP_PP_MATCH_WORD   ; Compare case-folded token bytes.
    JR   Z,CP_PP_SCAN_INCLUDE  ; Reuse the established 8.3 include parser.
    LD   HL,CP_PP_WORD_DEFINE  ; Check for a root numeric definition.
    LD   B,6                ; DEFINE has six letters.
    CALL CP_PP_MATCH_WORD   ; Reject any other six-byte token later.
    JR   Z,CP_PP_SCAN_DEFINE  ; Validate scope, name and value.
    LD   HL,CP_PP_WORD_ENDIF  ; Check the five-byte closing directive.
    LD   B,5                ; ENDIF has five letters.
    CALL CP_PP_MATCH_WORD   ; Match the complete token, not a prefix.
    JR   Z,CP_PP_SCAN_ENDIF  ; Pop one condition after its line is valid.
    LD   HL,CP_PP_WORD_ELSE  ; Check the four-byte alternate directive.
    LD   B,4                ; ELSE has four letters.
    CALL CP_PP_MATCH_WORD   ; Match the full keyword.
    JR   Z,CP_PP_SCAN_ELSE  ; Toggle the current conditional branch.
    LD   HL,CP_PP_WORD_IF   ; Check the two-byte opening directive.
    LD   B,2                ; IF has two letters.
    CALL CP_PP_MATCH_WORD   ; Match the complete keyword.
    JR   Z,CP_PP_SCAN_IF    ; Evaluate and push a new condition.
CP_PP_INVALID:
    LD   DE,CP_INVALID_DIRECTIVE_TEXT  ; Select unsupported-directive detail.
    SCF                     ; Carry marks the incomplete source profile.
    RET                     ; No output generation has begun.
CP_PP_SCAN_INCLUDE:
    LD   A,(CP_HEADER_OPEN)  ; Includes belong to the leading header only.
    OR   A                  ; Test whether ordinary source already began.
    JR   Z,CP_PP_SCAN_BAD_INCLUDE  ; Reject late imports before opening files.
    XOR  A                  ; Any include closes the definition preamble.
    LD   (CP_PP_DEFS_OPEN),A  ; Defines must precede includes and conditions.
    LD   HL,(CP_PP_WORD_START)  ; Restore the cursor immediately after '%'.
    JP   CP_PARSE_INCLUDE   ; Parse its filename and active dependency.
CP_PP_SCAN_BAD_INCLUDE:
    LD   DE,CP_INVALID_INCLUDE_TEXT  ; Select malformed-include detail.
    SCF                     ; Carry rejects the source before output starts.
    RET                     ; Return the include-specific message.
CP_PP_SCAN_DEFINE:
    LD   A,(CP_SCAN_INDEX)  ; Only the entry source may define values.
    OR   A                  ; Dependency ordinal zero identifies the root.
    JP   NZ,CP_PP_INVALID   ; Reject definitions in included files.
    LD   A,(CP_HEADER_OPEN)  ; Require the root's leading header.
    OR   A                  ; Ordinary source permanently closes it.
    JP   Z,CP_PP_INVALID    ; Reject a late definition.
    LD   A,(CP_PP_DEFS_OPEN)  ; Defines must precede includes and IF blocks.
    OR   A                  ; Zero means the preamble is already closed.
    JP   Z,CP_PP_INVALID    ; Reject definitions after preprocessing begins.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Start after the DEFINE directive name.
    CALL CP_PP_PARSE_DEFINE  ; Store one unique name and numeric value.
    JP   C,CP_PP_INVALID    ; Select the public directive error on failure.
    XOR  A                  ; Definitions do not defer an include part.
    RET                     ; Continue scanning this source file.
CP_PP_SCAN_IF:
    XOR  A                  ; IF closes the definition preamble.
    LD   (CP_PP_DEFS_OPEN),A  ; No define may appear after conditional logic.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Start after the IF keyword.
    CALL CP_PP_PARSE_IF     ; Evaluate the condition and push its frame.
    JP   C,CP_PP_INVALID    ; Select the public directive error on failure.
    RET                     ; Continue with the newly selected branch.
CP_PP_SCAN_ELSE:
    XOR  A                  ; ELSE also closes the definition preamble.
    LD   (CP_PP_DEFS_OPEN),A  ; Close define header, even when inactive.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Start at the directive's trailing text.
    CALL CP_PP_CHECK_TRAILING  ; Require only whitespace or a comment.
    JP   C,CP_PP_INVALID    ; Reject arguments after ELSE.
    LD   (CP_PP_SCAN_CURSOR),HL  ; Save cursor before pushing frame.
    CALL CP_PP_SET_ELSE     ; Validate and activate the alternate branch.
    JP   C,CP_PP_INVALID    ; Report unmatched or duplicate ELSE consistently.
    XOR  A                  ; ELSE is a consumed directive, not a dependency.
    LD   HL,(CP_PP_SCAN_CURSOR)  ; Resume after the validated directive line.
    RET                     ; Continue with the new branch state.
CP_PP_SCAN_ENDIF:
    XOR  A                  ; ENDIF closes the definition preamble too.
    LD   (CP_PP_DEFS_OPEN),A  ; Header state is tracked separately.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Validate the rest of the physical line.
    CALL CP_PP_CHECK_TRAILING  ; ENDIF accepts no arguments.
    JP   C,CP_PP_INVALID    ; Reject extra words after ENDIF.
    LD   (CP_PP_SCAN_CURSOR),HL  ; Save cursor before popping frame.
    CALL CP_PP_POP_IF       ; Restore the parent branch's activity.
    JP   C,CP_PP_INVALID    ; Report an unmatched ENDIF consistently.
    XOR  A                  ; No dependency is pending after ENDIF.
    LD   HL,(CP_PP_SCAN_CURSOR)  ; Resume after the validated directive line.
    RET                     ; Continue scanning the current source.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; At runtime, apply conditional state once for a directive's source offset.

CP_PP_RUNTIME_DIRECTIVE:
    LD   (CP_PP_WORD_START),HL  ; Save the cursor immediately after '%'.
    CALL CP_PP_READ_TOKEN   ; Read the keyword without changing source bytes.
    JP   C,CP_PP_RUNTIME_BAD  ; Reject source that changed after preflight.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Save the cursor before testing keywords.
    LD   HL,CP_PP_WORD_IF   ; IF changes the active source state.
    LD   B,2                ; Match exactly the IF keyword.
    CALL CP_PP_MATCH_WORD   ; Keep the source cursor in workspace.
    JR   Z,CP_PP_RUNTIME_IF  ; Apply one frame for this offset.
    LD   HL,CP_PP_WORD_ELSE  ; ELSE selects the remaining branch.
    LD   B,4                ; Match exactly four letters.
    CALL CP_PP_MATCH_WORD   ; Do not accept an ELSE-like prefix.
    JR   Z,CP_PP_RUNTIME_ELSE  ; Validate and toggle the top frame.
    LD   HL,CP_PP_WORD_ENDIF  ; ENDIF restores its parent's activity.
    LD   B,5                ; Match exactly five letters.
    CALL CP_PP_MATCH_WORD   ; Keep IF stack boundaries explicit.
    JR   Z,CP_PP_RUNTIME_ENDIF  ; Pop one frame after checking arguments.
    LD   A,0                ; Other directives leave state unchanged.
    OR   A                  ; Clear carry for the source-byte adapter.
    RET                     ; INCLUDE and DEFINE remain comments at runtime.
CP_PP_RUNTIME_IF:
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Continue after the IF keyword.
    CALL CP_PP_PARSE_IF     ; Repeat the same value and nesting rules.
    RET                     ; Carry means the source changed after preflight.
CP_PP_RUNTIME_ELSE:
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Check trailing text before state changes.
    CALL CP_PP_CHECK_TRAILING  ; An ELSE argument is never silently ignored.
    JR   C,CP_PP_RUNTIME_BAD  ; Reject mutation after source preflight.
    CALL CP_PP_SET_ELSE     ; Toggle only a valid top-level frame.
    RET                     ; Preserve the condition result.
CP_PP_RUNTIME_ENDIF:
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Check the complete directive line first.
    CALL CP_PP_CHECK_TRAILING  ; ENDIF takes no operands.
    JR   C,CP_PP_RUNTIME_BAD  ; Reject changed or malformed input.
    CALL CP_PP_POP_IF       ; Restore the parent activity.
    RET                     ; Return the updated conditional state.
CP_PP_RUNTIME_BAD:
    LD   A,2                ; Signal that the source changed after preflight.
    SCF                     ; Report a source-read failure.
    RET                     ; Never assemble with uncertain condition state.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one root definition; the name and value occupy separate work buffers.

CP_PP_PARSE_DEFINE:
    CALL CP_PP_READ_TOKEN   ; Read the case-insensitive definition name.
    JP   C,CP_PP_INVALID    ; A definition needs a name.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Save delimiter while checking the name.
    CALL CP_PP_VALIDATE_NAME  ; Enforce the native name-field limit.
    JP   C,CP_PP_INVALID    ; Reject invalid or overlong names.
    LD   (CP_PP_NAME_LENGTH),A  ; Retain its length while reading the value.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Resume where the name token ended.
    CALL CP_PP_READ_TOKEN   ; Skip whitespace and read one numeric value.
    JP   C,CP_PP_INVALID    ; A definition needs a value.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Save delimiter while parsing the value.
    CALL CP_PP_PARSE_VALUE  ; Resolve numeric syntax or a previous name.
    JP   C,CP_PP_INVALID    ; Reject undefined names and values above 16 bits.
    LD   (CP_PP_NUM_VALUE),HL  ; Keep the value until the line end is checked.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Resume at the delimiter after the value.
    CALL CP_PP_CHECK_TRAILING  ; Only whitespace, a comment or EOL may follow.
    JP   C,CP_PP_INVALID    ; Reject additional define operands.
    LD   (CP_PP_SCAN_CURSOR),HL  ; Save the next source position for lookup.
    CALL CP_PP_NAME_TO_TOKEN  ; Reuse lookup with the staged name.
    CALL CP_PP_FIND_DEFINE  ; A pre-existing match is a duplicate definition.
    JP   NC,CP_PP_INVALID   ; Reject duplicates even when values are equal.
    CALL CP_PP_STORE_DEFINE  ; Append the new value to the bounded table.
    RET  C                  ; A full table is an explicit profile error.
    LD   HL,(CP_PP_SCAN_CURSOR)  ; Restore next source position.
    RET                     ; Carry reports a full definition table.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse an IF value, validate its line, then push the computed condition.

CP_PP_PARSE_IF:
    CALL CP_PP_READ_TOKEN   ; Read one number or prior definition name.
    JP   C,CP_PP_INVALID    ; IF requires exactly one value.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Keep delimiter until evaluation ends.
    CALL CP_PP_PARSE_VALUE  ; Unknown names fail only in an active parent.
    JP   C,CP_PP_INVALID    ; Reject invalid values or active unknown names.
    LD   (CP_PP_NUM_VALUE),HL  ; Keep the result while checking trailing text.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Resume at the trailing delimiter.
    CALL CP_PP_CHECK_TRAILING  ; Require the directive to end after one value.
    JP   C,CP_PP_INVALID    ; Reject operators and extra arguments.
    LD   (CP_PP_SCAN_CURSOR),HL  ; Save cursor before pushing the frame.
    LD   HL,(CP_PP_NUM_VALUE)  ; Restore the unsigned sixteen-bit value.
    LD   A,H                ; Test its high byte.
    OR   L                  ; Either nonzero byte selects a true branch.
    LD   A,0                ; Prepare the false condition.
    JR   Z,CP_PP_PARSE_IF_PUSH  ; Keep zero false.
    INC  A                  ; Convert any nonzero value to true.
CP_PP_PARSE_IF_PUSH:
    CALL CP_PP_PUSH_IF      ; Save parent state and update activity.
    RET  C                  ; Preserve a nesting-limit failure.
    LD   HL,(CP_PP_SCAN_CURSOR)  ; Continue after this physical line.
    RET                     ; Return condition state and source position.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Push parent activity and the condition result into a sixteen-byte stack.

CP_PP_PUSH_IF:
    LD   (CP_PP_NUM_DIGIT),A  ; Preserve the condition during pointer setup.
    LD   A,(CP_PP_DEPTH)    ; Read the number of existing frames.
    CP   16                 ; The fixed stack holds sixteen nested IFs.
    JP   NC,CP_PP_BAD_CARRY  ; Reject a seventeenth frame.
    LD   C,A                ; Use the depth as the frame's byte index.
    LD   B,0                ; Extend that index to a word.
    LD   HL,CP_PP_STACK     ; Begin at the first frame.
    ADD  HL,BC              ; Select the next empty frame.
    LD   A,(CP_PP_ACTIVE)   ; Capture the enclosing branch's activity.
    OR   A                  ; Normalize it to one bit.
    LD   A,0                ; A false parent stores no flag bits.
    JR   Z,CP_PP_PUSH_PARENT  ; Keep the inactive parent clear.
    INC  A                  ; Bit zero marks an active parent.
CP_PP_PUSH_PARENT:
    LD   (HL),A             ; Store the parent-active flag.
    LD   A,(CP_PP_NUM_DIGIT)  ; Read the condition selected by the directive.
    OR   A                  ; Zero leaves condition bit one clear.
    JR   Z,CP_PP_PUSH_ACTIVE  ; Store a false condition under this frame.
    LD   A,(HL)             ; Recover the frame's parent flag.
    OR   2                  ; Bit one records a true condition.
    LD   (HL),A             ; Preserve both frame facts.
CP_PP_PUSH_ACTIVE:
    LD   A,(HL)             ; Read parent and condition bits together.
    AND  3                  ; Both bits must be set for an active branch.
    CP   3                  ; Value three means active parent and true IF.
    LD   A,0                ; Prepare the inactive result.
    JR   NZ,CP_PP_PUSH_STORE  ; A false parent or condition stays inactive.
    INC  A                  ; Mark the selected IF body active.
CP_PP_PUSH_STORE:
    LD   (CP_PP_ACTIVE),A   ; Publish activity for following source bytes.
    LD   HL,CP_PP_DEPTH     ; Point at the one-byte frame count.
    INC  (HL)               ; The newly filled frame is now on the stack.
    XOR  A                  ; Return with carry clear.
    RET                     ; Preserve the new active-state byte in RAM.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate ELSE and select parent-active AND NOT original-condition.

CP_PP_SET_ELSE:
    LD   A,(CP_PP_DEPTH)    ; An ELSE needs one open IF frame.
    OR   A                  ; Zero denotes an unmatched directive.
    JP   Z,CP_PP_BAD_CARRY  ; Reject ELSE without IF.
    DEC  A                  ; Select the most recent frame.
    LD   C,A                ; Keep its stack index in C.
    LD   B,0                ; Extend the index to a word.
    LD   HL,CP_PP_STACK     ; Address the first frame.
    ADD  HL,BC              ; Select the current frame.
    BIT  2,(HL)             ; Test whether ELSE already appeared.
    JP   NZ,CP_PP_BAD_CARRY  ; Reject a second ELSE in one IF.
    SET  2,(HL)             ; Remember that this branch has been used.
    LD   A,(HL)             ; Load parent-active and original-condition.
    AND  3                  ; Ignore ELSE and include bookkeeping bits.
    CP   1                  ; Only active parent plus false IF selects ELSE.
    LD   A,0                ; Prepare an inactive alternate branch.
    JR   NZ,CP_PP_ELSE_STORE  ; All other combinations remain inactive.
    INC  A                  ; Enable the sole selected alternate case.
CP_PP_ELSE_STORE:
    LD   (CP_PP_ACTIVE),A   ; Publish activity for the alternate branch.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Keep the updated stack frame.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Pop one condition and restore the activity of its enclosing parent.

CP_PP_POP_IF:
    LD   A,(CP_PP_DEPTH)    ; An ENDIF needs an open frame.
    OR   A                  ; Zero denotes an unmatched directive.
    JP   Z,CP_PP_BAD_CARRY  ; Reject ENDIF without IF.
    DEC  A                  ; Select the frame being closed.
    LD   C,A                ; Keep its index while loading the frame.
    LD   B,0                ; Extend the index to sixteen bits.
    LD   HL,CP_PP_STACK     ; Address the first stack frame.
    ADD  HL,BC              ; Select the frame to pop.
    LD   A,(HL)             ; Bit zero is the enclosing activity.
    AND  1                  ; Discard every field local to the closing IF.
    LD   (CP_PP_ACTIVE),A   ; Restore the enclosing conditional state.
    LD   HL,CP_PP_DEPTH     ; Address the frame count.
    DEC  (HL)               ; Pop exactly one condition.
    XOR  A                  ; Return success with carry clear.
    RET                     ; The stale byte is ignored beyond the new depth.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mark every enclosing IF whose active header contains an include directive.

CP_PP_MARK_INCLUDE:
    PUSH HL                 ; The include parser owns the source cursor.
    LD   A,(CP_PP_DEPTH)    ; No frame needs a marker outside conditionals.
    OR   A                  ; Avoid touching the empty stack.
    JR   Z,CP_PP_MARK_INCLUDE_DONE  ; Unconditional include needs no frame.
    LD   B,A                ; Visit every open frame.
    LD   HL,CP_PP_STACK     ; Start with the outermost IF.
CP_PP_MARK_INCLUDE_LOOP:
    LD   A,(HL)             ; Load this frame's packed state.
    OR   8                  ; Bit three means its include has not closed yet.
    LD   (HL),A             ; Keep nested include scope on each parent.
    INC  HL                 ; Advance to the next one-byte frame.
    DJNZ CP_PP_MARK_INCLUDE_LOOP  ; Mark all active nesting ancestors.
CP_PP_MARK_INCLUDE_DONE:
    POP  HL                 ; Restore the cursor following the include name.
    RET                     ; The scanner checks these bits at source start.

;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return carry when ordinary source begins inside a conditional include.

CP_PP_CHECK_INCLUDE_SCOPE:
    PUSH HL                 ; Preserve the source reader's current offset.
    LD   A,(CP_HEADER_OPEN)  ; Restrict conditional imports to the header.
    OR   A                  ; A closed header cannot accept an import.
    JR   Z,CP_PP_CHECK_INCLUDE_DONE  ; Let the parser report a late import.
    LD   A,(CP_PP_DEPTH)    ; Closed frames no longer constrain source order.
    OR   A                  ; An empty stack makes ordinary source safe.
    JR   Z,CP_PP_CHECK_INCLUDE_DONE  ; Continue without scanning the table.
    LD   B,A                ; Examine the currently open frames.
    LD   HL,CP_PP_STACK     ; Begin at the outermost conditional.
CP_PP_CHECK_INCLUDE_LOOP:
    BIT  3,(HL)             ; Has this frame seen an include before ENDIF?
    JR   NZ,CP_PP_CHECK_INCLUDE_BAD  ; Reject ordinary source inside header.
    INC  HL                 ; Advance to the next frame.
    DJNZ CP_PP_CHECK_INCLUDE_LOOP  ; Check every still-open ancestor.
    XOR  A                  ; No include-bearing condition remains open.
    JR   CP_PP_CHECK_INCLUDE_DONE  ; Restore the source cursor on success.
CP_PP_CHECK_INCLUDE_BAD:
    SCF                     ; Mark ordinary source inside an import condition.
CP_PP_CHECK_INCLUDE_DONE:
    POP  HL                 ; Keep the caller's logical source offset intact.
    RET                     ; Return carry clear for ordinary source.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Read one whitespace-delimited ASCII token, leaving its delimiter unread.

CP_PP_READ_TOKEN:
    XOR  A                  ; Begin with an empty token.
    LD   (CP_PP_TOKEN_LENGTH),A  ; Reset the bounded token length.
CP_PP_READ_TOKEN_LOOP:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next raw source character.
    JR   C,CP_PP_READ_TOKEN_EOF  ; EOF ends a complete trailing token.
    CP   ' '                ; Horizontal spaces delimit tokens.
    JR   Z,CP_PP_READ_TOKEN_SPACE  ; Skip leading spaces or finish a token.
    CP   9                  ; Tabs have the same token-boundary meaning.
    JR   Z,CP_PP_READ_TOKEN_SPACE  ; Skip leading tabs or finish a token.
    CP   ';'                ; Semicolon begins a source comment.
    JR   Z,CP_PP_READ_TOKEN_END  ; Leave ';' for trailing-text validation.
    CP   13                 ; CR terminates this physical line.
    JR   Z,CP_PP_READ_TOKEN_END  ; Leave CR for the line validator.
    CP   10                 ; LF also terminates a directive line.
    JR   Z,CP_PP_READ_TOKEN_END  ; Preserve LF for the trailing validator.
    LD   B,A                ; Keep the character while checking capacity.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Read the token length so far.
    CP   17                 ; The fixed token buffer holds at most 17 bytes.
    JR   NC,CP_PP_READ_TOKEN_BAD  ; Reject a token beyond the native limit.
    LD   C,A                ; Use the current length as the array index.
    LD   A,B                ; Restore the source character.
    CP   'a'                ; Check for an ASCII lowercase letter.
    JR   C,CP_PP_READ_TOKEN_CASED  ; Keep uppercase and punctuation unchanged.
    CP   'z'+1              ; Check the exclusive lowercase upper bound.
    JR   NC,CP_PP_READ_TOKEN_CASED  ; Leave bytes beyond 'z' unchanged.
    AND  $DF                ; Fold lowercase ASCII to uppercase.
CP_PP_READ_TOKEN_CASED:
    LD   (CP_PP_NUM_DIGIT),A  ; Save the normalized byte during indexing.
    LD   (CP_PP_SOURCE_CURSOR),HL  ; Save the source cursor while indexing.
    LD   A,C                ; Load the token's current length.
    LD   C,A                ; Form its low-byte address offset.
    LD   B,0                ; The token index is less than eighteen.
    LD   HL,CP_PP_TOKEN     ; Select the fixed token buffer.
    ADD  HL,BC              ; Address the next available byte.
    LD   A,(CP_PP_NUM_DIGIT)  ; Restore the normalized character.
    LD   (HL),A             ; Append it without changing source offsets.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Resume after the token byte just read.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Reload the stored token length.
    INC  A                  ; Count the character just appended.
    LD   (CP_PP_TOKEN_LENGTH),A  ; Publish the new bounded length.
    JR   CP_PP_READ_TOKEN_LOOP  ; Continue until whitespace or line end.
CP_PP_READ_TOKEN_SPACE:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Determine whether a token has started.
    OR   A                  ; Leading whitespace is ignored.
    JR   Z,CP_PP_READ_TOKEN_LOOP  ; Keep looking for the first token byte.
CP_PP_READ_TOKEN_END:
    DEC  HL                 ; Leave the delimiter for the next parser.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Reject an empty token at comment or EOL.
    OR   A                  ; A zero length means a required value is absent.
    JR   Z,CP_PP_READ_TOKEN_BAD  ; Report the missing token.
    OR   A                  ; Clear carry and classify the token length.
    RET                     ; HL still points at its first trailing delimiter.
CP_PP_READ_TOKEN_EOF:
    OR   A                  ; A=0 is ordinary EOF; A=2 is source overflow.
    JR   NZ,CP_PP_READ_TOKEN_BAD  ; Do not accept a wrapped source cursor.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; An EOF may finish a nonempty token.
    OR   A                  ; Reject EOF before any required token.
    JR   Z,CP_PP_READ_TOKEN_BAD  ; The caller will print a directive error.
    OR   A                  ; Return the complete final token.
    RET                     ; The source cursor remains at EOF.
CP_PP_READ_TOKEN_BAD:
    SCF                     ; Carry reports malformed or overlong input.
    RET                     ; The caller selects the directive diagnostic.

;@ROUTINE IN HL,B OUT A,ZERO CLOBBERS BC,DE,HL
; Compare B token bytes with the uppercase word at HL.

CP_PP_MATCH_WORD:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Require an exact keyword length.
    CP   B                  ; A prefix must not match a directive.
    RET  NZ                 ; Leave the comparison result in flags.
    LD   DE,CP_PP_TOKEN     ; Start at the normalized directive token.
CP_PP_MATCH_WORD_LOOP:
    LD   A,(DE)             ; Read the next source token byte.
    CP   (HL)               ; Compare it with the selected keyword byte.
    RET  NZ                 ; Stop at the first mismatched character.
    INC  DE                 ; Advance through the token.
    INC  HL                 ; Advance through the keyword.
    DJNZ CP_PP_MATCH_WORD_LOOP  ; Compare every letter in the keyword.
    XOR  A                  ; Return Z for a complete keyword match.
    RET                     ; The caller can branch on exact equality.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Accept end of line or a complete trailing comment.

CP_PP_CHECK_TRAILING:
    CALL CP_NEXT_SOURCE_BYTE  ; Inspect the byte after the final token.
    JR   C,CP_PP_TRAILING_EOF  ; EOF is a valid directive terminator.
    CP   ' '                ; Permit trailing horizontal whitespace.
    JR   Z,CP_PP_CHECK_TRAILING  ; Skip another space.
    CP   9                  ; Permit trailing tabs as well.
    JR   Z,CP_PP_CHECK_TRAILING  ; Skip another tab.
    CP   ';'                ; An ordinary semicolon begins a comment.
    JR   Z,CP_PP_TRAILING_COMMENT  ; Consume its remaining physical line.
    CP   13                 ; Accept a carriage-return line ending.
    JR   Z,CP_PP_TRAILING_OK  ; Leave the next LF for the outer scanner.
    CP   10                 ; Accept LF-only source files.
    JR   Z,CP_PP_TRAILING_OK  ; The next byte begins a new physical line.
    SCF                     ; Any other byte is an extra argument.
    RET                     ; Reject it before the assembler sees it.
CP_PP_TRAILING_COMMENT:
    CALL CP_SKIP_SOURCE_LINE  ; Consume the validated trailing comment.
    JR   C,CP_PP_TRAILING_EOF  ; EOF is valid; overflow is not.
    XOR  A                  ; The comment ended at a normal line break.
    RET                     ; Continue scanning the following line.
CP_PP_TRAILING_EOF:
    OR   A                  ; A=0 means EOF; A=2 means offset overflow.
    RET  Z                  ; Accept an ordinary end of file.
    SCF                     ; Reject a source offset that wrapped.
    RET                     ; Leave the caller's source scan failed.
CP_PP_TRAILING_OK:
    XOR  A                  ; A normal line ending is valid.
    RET                     ; HL points beyond the consumed line-ending byte.

;@ROUTINE IN A OUT HL,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Convert one token to a 16-bit value or look it up in the bounded table.

CP_PP_PARSE_VALUE:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Empty values cannot reach the parser.
    OR   A                  ; Keep a defensive check at this boundary.
    JP   Z,CP_PP_BAD_CARRY  ; Return carry for an empty value.
    LD   A,(CP_PP_TOKEN)    ; Inspect the first normalized byte.
    CP   'A'                ; A leading letter selects a definition name.
    JR   C,CP_PP_VALUE_NOT_NAME  ; Numbers start with a digit, '$' or '%'.
    CP   'Z'+1              ; Bound the first byte to ASCII letters.
    JP   C,CP_PP_VALUE_NAME  ; Resolve a case-folded preprocessor name.
CP_PP_VALUE_NOT_NAME:
    CP   '$'                ; A dollar prefix selects hexadecimal.
    JR   Z,CP_PP_VALUE_HEX_PREFIX  ; Skip the prefix before digit parsing.
    CP   '%'                ; A percent prefix selects binary.
    JR   Z,CP_PP_VALUE_BIN_PREFIX  ; The host directive itself began earlier.
    CP   '0'                ; Decimal and Intel suffixes start with digits.
    JP   C,CP_PP_BAD_CARRY  ; Reject punctuation outside the numeric grammar.
    CP   '9'+1              ; Digits stop before colon and alphabetic bytes.
    JP   NC,CP_PP_BAD_CARRY  ; Reject a nonnumeric leading byte.
    LD   A,10               ; Unsuffixed digits use decimal.
    LD   (CP_PP_NUM_BASE),A  ; Store decimal as the default radix.
    XOR  A                  ; Unsuffixed values begin at token byte zero.
    LD   (CP_PP_NUM_START),A  ; Record the first digit's index.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Decimal consumes the complete token.
    LD   (CP_PP_NUM_COUNT),A  ; The digit loop checks each byte's range.
    DEC  A                  ; Address the final token byte.
    LD   C,A                ; Use it as a short buffer index.
    LD   B,0                ; Zero-extend the token index.
    LD   HL,CP_PP_TOKEN     ; Select the normalized token.
    ADD  HL,BC              ; Inspect a possible Intel suffix.
    LD   A,(HL)             ; Read the final token byte.
    CP   'H'                ; Intel hexadecimal ends in H.
    JR   Z,CP_PP_VALUE_HEX_SUFFIX  ; Parse preceding digits as hexadecimal.
    CP   'B'                ; Intel binary ends in B.
    JR   Z,CP_PP_VALUE_BIN_SUFFIX  ; Parse its preceding digits in base two.
    JR   CP_PP_PARSE_NUMERIC  ; Keep decimal when neither suffix is present.
CP_PP_VALUE_HEX_PREFIX:
    LD   A,16               ; Dollar-prefixed source uses hexadecimal.
    LD   (CP_PP_NUM_BASE),A  ; Store its radix.
    LD   A,1                ; Skip the leading dollar sign.
    LD   (CP_PP_NUM_START),A  ; Begin digits immediately after '$'.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Count all bytes in the token.
    DEC  A                  ; The prefix is not a digit.
    LD   (CP_PP_NUM_COUNT),A  ; Parse every remaining hexadecimal digit.
    JR   CP_PP_PARSE_NUMERIC  ; Convert and range-check the value.
CP_PP_VALUE_BIN_PREFIX:
    LD   A,2                ; Percent-prefixed source uses binary.
    LD   (CP_PP_NUM_BASE),A  ; Store its radix.
    LD   A,1                ; Skip the leading percent sign.
    LD   (CP_PP_NUM_START),A  ; Begin at the first binary digit.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Count all bytes in the token.
    DEC  A                  ; The prefix is not a digit.
    LD   (CP_PP_NUM_COUNT),A  ; Parse the remaining binary digits.
    JR   CP_PP_PARSE_NUMERIC  ; Convert and range-check the value.
CP_PP_VALUE_HEX_SUFFIX:
    LD   A,16               ; H suffix selects hexadecimal.
    LD   (CP_PP_NUM_BASE),A  ; Replace the decimal default.
    JR   CP_PP_VALUE_SUFFIX_COUNT  ; Exclude the suffix from the digits.
CP_PP_VALUE_BIN_SUFFIX:
    LD   A,2                ; B suffix selects binary.
    LD   (CP_PP_NUM_BASE),A  ; Replace the decimal default.
CP_PP_VALUE_SUFFIX_COUNT:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; The suffix is one byte.
    DEC  A                  ; Count only the preceding digits.
    LD   (CP_PP_NUM_COUNT),A  ; Keep the existing zero start index.
CP_PP_PARSE_NUMERIC:
    LD   A,(CP_PP_NUM_COUNT)  ; Reject a prefix or suffix without digits.
    OR   A                  ; Zero digits cannot encode a number.
    JP   Z,CP_PP_BAD_CARRY  ; A token consisting of H or B is a name instead.
    XOR  A                  ; Begin numeric accumulation at zero.
    LD   HL,0               ; HL is the unsigned 16-bit result.
    LD   (CP_PP_NUM_VALUE),HL  ; Keep the accumulator across helper calls.
    XOR  A                  ; The digit index begins at zero.
    LD   (CP_PP_NUM_INDEX),A  ; Count digits, not source positions.
CP_PP_NUMERIC_LOOP:
    LD   A,(CP_PP_NUM_INDEX)  ; Read the next digit's token index.
    LD   C,A                ; Convert it to a pointer displacement.
    LD   B,0                ; The index fits in one byte.
    LD   A,(CP_PP_NUM_START)  ; Include a possible '$' or '%' prefix.
    ADD  A,C                ; Form the complete token position.
    LD   C,A                ; Use the sum as the low pointer offset.
    LD   HL,CP_PP_TOKEN     ; Address the token's first byte.
    ADD  HL,BC              ; Select the next numeric digit.
    LD   A,(HL)             ; Read its normalized ASCII byte.
    CALL CP_PP_DIGIT_VALUE  ; Convert it under the selected radix.
    JP   C,CP_PP_BAD_CARRY  ; Reject letters or digits outside the radix.
    LD   (CP_PP_NUM_DIGIT),A  ; Save digit during multiply.
    LD   HL,(CP_PP_NUM_VALUE)  ; Load the accumulated prefix value.
    LD   A,(CP_PP_NUM_BASE)  ; Select the radix's multiply operation.
    CP   2                  ; Binary values double before adding each digit.
    JR   Z,CP_PP_MULTIPLY_TWO  ; Use one checked shift.
    CP   16                 ; Hexadecimal values multiply by sixteen.
    JR   Z,CP_PP_MULTIPLY_SIXTEEN  ; Use four checked shifts.
    CALL CP_PP_MULTIPLY_TEN  ; Decimal values multiply by ten.
    JP   C,CP_PP_BAD_CARRY  ; Reject an intermediate value above $FFFF.
    JR   CP_PP_ADD_DIGIT    ; Add the already-validated decimal digit.
CP_PP_MULTIPLY_TWO:
    ADD  HL,HL              ; Shift the binary prefix left by one bit.
    JP   C,CP_PP_BAD_CARRY  ; Reject a high bit that would be lost.
    JR   CP_PP_ADD_DIGIT    ; Add the next binary digit.
CP_PP_MULTIPLY_SIXTEEN:
    ADD  HL,HL              ; Shift the hexadecimal prefix by one bit.
    JP   C,CP_PP_BAD_CARRY  ; Reject overflow before shifting again.
    ADD  HL,HL              ; Shift the hexadecimal prefix by two bits.
    JP   C,CP_PP_BAD_CARRY  ; Reject overflow before shifting again.
    ADD  HL,HL              ; Shift the hexadecimal prefix by three bits.
    JP   C,CP_PP_BAD_CARRY  ; Reject overflow before shifting again.
    ADD  HL,HL              ; Complete the four-bit hexadecimal shift.
    JP   C,CP_PP_BAD_CARRY  ; Reject a value outside the 16-bit range.
CP_PP_ADD_DIGIT:
    LD   A,L                ; Start the addition with the low byte.
    LD   C,A                ; Keep that byte while loading the new digit.
    LD   A,(CP_PP_NUM_DIGIT)  ; Read the validated digit value (0..15).
    ADD  A,C                ; Add the digit to the low byte.
    LD   L,A                ; Store the low result byte.
    JR   NC,CP_PP_NUMERIC_STORE  ; No carry leaves the high byte unchanged.
    INC  H                  ; Carry advances the high byte once.
    JP   Z,CP_PP_BAD_CARRY  ; A wrapped high byte means value overflow.
CP_PP_NUMERIC_STORE:
    LD   (CP_PP_NUM_VALUE),HL  ; Publish this fully checked prefix value.
    LD   HL,CP_PP_NUM_INDEX  ; Address the digit index.
    INC  (HL)               ; Count the digit just consumed.
    LD   A,(CP_PP_NUM_INDEX)  ; Compare with the total digit count.
    LD   B,A                ; Keep the current index in B.
    LD   A,(CP_PP_NUM_COUNT)  ; Load the number of remaining digits.
    CP   B                  ; Continue while the index is smaller.
    JR   NZ,CP_PP_NUMERIC_LOOP  ; Parse the next digit.
    LD   HL,(CP_PP_NUM_VALUE)  ; Return the final 16-bit value.
    XOR  A                  ; Clear carry for a successful conversion.
    RET                     ; HL holds the result.
CP_PP_VALUE_NAME:
    CALL CP_PP_VALIDATE_TOKEN_NAME  ; Do not overwrite a staged DEFINE name.
    JP   C,CP_PP_BAD_CARRY  ; Reject malformed or overlong identifiers.
    CALL CP_PP_FIND_DEFINE  ; Resolve the prior entry-header definition.
    RET  NC                 ; A found definition returns its value in HL.
    LD   A,(CP_PP_ACTIVE)   ; Ignore unknown names in inactive branches.
    OR   A                  ; Active source requires an existing definition.
    JP   NZ,CP_PP_BAD_CARRY  ; Reject a missing name in an active condition.
    LD   HL,0               ; Inactive nested conditions select false.
    XOR  A                  ; Preserve that non-error result.
    RET                     ; The outer inactive frame remains decisive.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Convert A from the selected base into a digit value in the range 0..15.

CP_PP_DIGIT_VALUE:
    CP   '0'                ; Digits begin at ASCII zero.
    JR   C,CP_PP_DIGIT_BAD  ; Reject punctuation below the digit range.
    CP   '9'+1              ; Decimal digits end before uppercase letters.
    JR   C,CP_PP_DIGIT_DECIMAL  ; Convert '0' through '9'.
    CP   'A'                ; Hexadecimal letters start at A.
    JR   C,CP_PP_DIGIT_BAD  ; Reject punctuation between digits and letters.
    CP   'F'+1              ; Only A through F fit a hexadecimal nibble.
    JR   NC,CP_PP_DIGIT_BAD  ; Reject letters beyond F.
    SUB  'A'-10             ; Convert A..F into 10..15.
    JR   CP_PP_DIGIT_RANGE  ; Compare the value with the selected base.
CP_PP_DIGIT_DECIMAL:
    SUB  '0'                ; Convert ASCII digit to its numeric value.
CP_PP_DIGIT_RANGE:
    LD   C,A                ; Save the converted value during the radix check.
    LD   A,(CP_PP_NUM_BASE)  ; Binary, decimal or hexadecimal limit.
    LD   B,A                ; Keep the radix while comparing the digit.
    LD   A,C                ; Read the converted digit value.
    CP   B                  ; Carry means this digit is below the radix.
    JR   NC,CP_PP_DIGIT_BAD  ; Reject a digit equal to or above the radix.
    LD   A,C                ; Return the numeric digit.
    OR   A                  ; Clear carry without changing its value.
    RET                     ; A contains the accepted digit.
CP_PP_DIGIT_BAD:
    SCF                     ; Carry rejects the token under its radix.
    RET                     ; The numeric parser selects a directive error.

;@ROUTINE IN HL OUT HL,CARRY CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY
; Compute value*10 as value*8+value*2 with overflow checks at each addition.

CP_PP_MULTIPLY_TEN:
    PUSH HL                 ; Preserve the original value for the final sum.
    ADD  HL,HL              ; Form value*2.
    JR   C,CP_PP_MULTIPLY_TEN_BAD_ORIGINAL  ; Reject overflow; undo high word.
    PUSH HL                 ; Save value*2 while constructing value*8.
    ADD  HL,HL              ; Form value*4.
    JR   C,CP_PP_MULTIPLY_TEN_BAD_DOUBLE  ; Remove both saved words.
    ADD  HL,HL              ; Form value*8.
    JR   C,CP_PP_MULTIPLY_TEN_BAD_DOUBLE  ; Remove both saved words.
    POP  DE                 ; Recover value*2 into DE.
    ADD  HL,DE              ; Form value*10.
    JR   C,CP_PP_MULTIPLY_TEN_BAD_ORIGINAL  ; Reject a sum above $FFFF.
    POP  DE                 ; Discard the preserved original value.
    OR   A                  ; Return carry clear with the product in HL.
    RET                     ; The caller adds its next decimal digit.
CP_PP_MULTIPLY_TEN_BAD_DOUBLE:
    POP  DE                 ; Remove the saved value*2 from the stack.
CP_PP_MULTIPLY_TEN_BAD_ORIGINAL:
    POP  DE                 ; Remove the saved original value.
    SCF                     ; Carry signals an out-of-range decimal prefix.
    RET                     ; Keep the caller's stack balanced.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find the token's uppercase name in the fixed eleven-byte definition records.

CP_PP_FIND_DEFINE:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Check length against the name field.
    CP   CP_PP_NAME_BYTES+1  ; Reject names wider than the fixed field.
    JR   NC,CP_PP_DEFINE_MISSING  ; Treat an overlong name as missing.
    LD   A,(CP_PP_DEFINE_COUNT)  ; A zero count means the table is empty.
    OR   A                  ; Avoid an IX walk when no values exist.
    JR   Z,CP_PP_DEFINE_MISSING  ; Let the caller decide if missing is legal.
    LD   B,A                ; Visit every preceding definition.
    LD   IX,CP_PP_DEFINE_TABLE  ; Address the first fixed-width record.
CP_PP_FIND_DEFINE_LOOP:
    LD   A,(IX+0)           ; Read the stored name length.
    LD   C,A                ; Keep it while loading the query length.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Read the current query's length.
    CP   C                  ; Different lengths cannot match.
    JR   NZ,CP_PP_FIND_DEFINE_NEXT  ; Try the next definition record.
    PUSH IX                 ; Save the record base across name comparison.
    INC  IX                 ; The first name byte follows the length field.
    LD   DE,CP_PP_TOKEN     ; Compare with the normalized query name.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Match exactly the declared name length.
    LD   C,A                ; Use C as the character count.
CP_PP_FIND_DEFINE_NAME:
    LD   A,(DE)             ; Read one requested name character.
    CP   (IX+0)             ; Compare it with this record's name byte.
    JR   NZ,CP_PP_FIND_DEFINE_DIFFERENT  ; Continue searching on mismatch.
    INC  DE                 ; Advance through the query name.
    INC  IX                 ; Advance through the stored name.
    DEC  C                  ; Count this matching character.
    JR   NZ,CP_PP_FIND_DEFINE_NAME  ; Compare the complete name.
    POP  IX                 ; Restore the matching record's base.
    LD   L,(IX+18)          ; Read the definition value's low byte.
    LD   H,(IX+19)          ; Complete its unsigned 16-bit value.
    OR   A                  ; Clear carry to report a successful lookup.
    RET                     ; Return the value in HL.
CP_PP_FIND_DEFINE_DIFFERENT:
    POP  IX                 ; Restore the record pointer after mismatch.
CP_PP_FIND_DEFINE_NEXT:
    LD   DE,CP_PP_DEFINE_ENTRY_BYTES  ; Advance by one full definition record.
    ADD  IX,DE              ; Advance to the next definition.
    DJNZ CP_PP_FIND_DEFINE_LOOP  ; Stop after the published record count.
CP_PP_DEFINE_MISSING:
    SCF                     ; Carry tells the caller no value was found.
    RET                     ; HL has no meaning on this path.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a 1-17 character name and copy it to CP_PP_NAME.

CP_PP_VALIDATE_NAME:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Read the complete candidate length.
    OR   A                  ; Empty names are invalid.
    JR   Z,CP_PP_NAME_BAD   ; Reject an absent identifier.
    CP   CP_PP_NAME_BYTES+1  ; The name field holds at most 17 characters.
    JR   NC,CP_PP_NAME_BAD  ; Reject anything wider than its storage field.
    LD   (CP_PP_NAME_LENGTH),A  ; Retain the length for lookup and insertion.
    LD   HL,CP_PP_NAME      ; Fill unused name bytes with spaces.
    LD   B,CP_PP_NAME_BYTES  ; Compare the complete padded name field.
    LD   A,' '              ; Space padding makes comparisons deterministic.
CP_PP_NAME_CLEAR:
    LD   (HL),A             ; Clear one staged name byte.
    INC  HL                 ; Advance to the next name position.
    DJNZ CP_PP_NAME_CLEAR   ; Fill the full fixed-width field before copying.
    LD   A,(CP_PP_NAME_LENGTH)  ; Reload the candidate's length.
    LD   B,A                ; Use B to count its characters.
    LD   C,0                ; C distinguishes first character from the rest.
    LD   DE,CP_PP_TOKEN     ; Start at the normalized candidate.
    LD   HL,CP_PP_NAME      ; Store its canonical bytes separately.
CP_PP_NAME_CHECK:
    LD   A,(DE)             ; Read the next uppercase character.
    LD   (CP_PP_NUM_DIGIT),A  ; Save the byte without changing DE.
    LD   A,C                ; Zero marks the first character.
    OR   A                  ; The first character must be a letter.
    LD   A,(CP_PP_NUM_DIGIT)  ; Restore the candidate byte.
    JR   NZ,CP_PP_NAME_LATER  ; Later bytes may include digits and underscore.
    CP   'A'                ; Test the inclusive first-letter lower bound.
    JR   C,CP_PP_NAME_BAD   ; Reject leading digits and punctuation.
    CP   'Z'+1              ; Test the exclusive first-letter upper bound.
    JR   NC,CP_PP_NAME_BAD  ; Reject a leading underscore.
    JR   CP_PP_NAME_STORE   ; A valid letter begins the staged name.
CP_PP_NAME_LATER:
    CP   'A'                ; A later uppercase letter is valid.
    JR   C,CP_PP_NAME_NOT_ALPHA  ; Check the other allowed classes.
    CP   'Z'+1              ; Bound the letter range.
    JR   C,CP_PP_NAME_STORE  ; Store a valid later letter.
CP_PP_NAME_NOT_ALPHA:
    CP   '0'                ; Digits are permitted after the first byte.
    JR   C,CP_PP_NAME_UNDERSCORE  ; Check underscore before other punctuation.
    CP   '9'+1              ; Bound the digit range.
    JR   C,CP_PP_NAME_STORE  ; Store a valid later digit.
CP_PP_NAME_UNDERSCORE:
    CP   '_'                ; Underscore is allowed after the first byte.
    JR   NZ,CP_PP_NAME_BAD  ; Reject all other punctuation.
CP_PP_NAME_STORE:
    LD   (HL),A             ; Store this character in the padded name.
    INC  HL                 ; Advance the name destination.
    INC  DE                 ; Advance the source token.
    INC  C                  ; Mark subsequent characters as noninitial.
    DJNZ CP_PP_NAME_CHECK   ; Validate every remaining character.
    LD   A,(CP_PP_NAME_LENGTH)  ; Return the accepted name length.
    OR   A                  ; Clear carry on successful validation.
    RET                     ; CP_PP_NAME now holds uppercase padded bytes.
CP_PP_NAME_BAD:
    SCF                     ; Carry marks invalid name syntax or length.
    RET                     ; The source profile reports a directive error.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Validate a lookup token without replacing the separately staged DEFINE name.

CP_PP_VALIDATE_TOKEN_NAME:
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Read the complete query token length.
    OR   A                  ; Empty identifiers cannot be looked up.
    JR   Z,CP_PP_NAME_BAD   ; Reuse the common carry-set result.
    CP   CP_PP_NAME_BYTES+1  ; The fixed record bounds every lookup name.
    JR   NC,CP_PP_NAME_BAD  ; Reject a name the definition table cannot hold.
    LD   B,A                ; Count every validated token byte.
    LD   C,0                ; Zero identifies the leading character.
    LD   DE,CP_PP_TOKEN     ; Begin at the uppercase token buffer.
CP_PP_TOKEN_NAME_CHECK:
    LD   A,(DE)             ; Read one candidate character.
    LD   (CP_PP_NUM_DIGIT),A  ; Preserve it without changing the DE cursor.
    LD   A,C                ; Check whether this is the first character.
    OR   A                  ; A nonzero count permits more character classes.
    LD   A,(CP_PP_NUM_DIGIT)  ; Reload the byte for its range checks.
    JR   NZ,CP_PP_TOKEN_NAME_LATER  ; Later bytes allow digits and underscore.
    CP   'A'                ; A name must start with an uppercase letter.
    JR   C,CP_PP_NAME_BAD   ; Reject an invalid first character.
    CP   'Z'+1              ; Test the exclusive end of the letter range.
    JR   NC,CP_PP_NAME_BAD  ; Reject an initial underscore.
    JR   CP_PP_TOKEN_NAME_NEXT  ; The first letter passed validation.
CP_PP_TOKEN_NAME_LATER:
    CP   'A'                ; Test the later-letter range first.
    JR   C,CP_PP_TOKEN_NAME_NOT_ALPHA  ; Check digits and underscore below.
    CP   'Z'+1              ; Bound the inclusive uppercase letters.
    JR   C,CP_PP_TOKEN_NAME_NEXT  ; Advance past a valid later letter.
CP_PP_TOKEN_NAME_NOT_ALPHA:
    CP   '0'                ; Decimal digits may follow the initial letter.
    JR   C,CP_PP_TOKEN_NAME_UNDERSCORE  ; Check underscore before punctuation.
    CP   '9'+1              ; Bound the decimal digit range.
    JR   C,CP_PP_TOKEN_NAME_NEXT  ; Accept a digit after the first character.
CP_PP_TOKEN_NAME_UNDERSCORE:
    CP   '_'                ; Underscore is the only other allowed byte.
    JR   NZ,CP_PP_NAME_BAD  ; Reject invalid identifier punctuation.
CP_PP_TOKEN_NAME_NEXT:
    INC  DE                 ; Advance to the following token character.
    INC  C                  ; Mark all remaining bytes as noninitial.
    DJNZ CP_PP_TOKEN_NAME_CHECK  ; Validate the complete identifier.
    XOR  A                  ; Clear carry for a valid lookup name.
    RET                     ; Leave token bytes intact for table lookup.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Copy a staged definition name to the query buffer for duplicate detection.

CP_PP_NAME_TO_TOKEN:
    LD   A,(CP_PP_NAME_LENGTH)  ; Keep the name's significant length.
    LD   (CP_PP_TOKEN_LENGTH),A  ; Configure the generic lookup routine.
    LD   HL,CP_PP_NAME      ; Read the staged padded name.
    LD   DE,CP_PP_TOKEN     ; Write its bytes into the query buffer.
    LD   B,CP_PP_NAME_BYTES  ; Copy the complete canonical field.
CP_PP_NAME_TO_TOKEN_LOOP:
    LD   A,(HL)             ; Read one uppercase name or padding byte.
    LD   (DE),A             ; Publish it in the lookup buffer.
    INC  HL                 ; Advance the staged source.
    INC  DE                 ; Advance the query destination.
    DJNZ CP_PP_NAME_TO_TOKEN_LOOP  ; Copy the complete padded name.
    RET                     ; The value token is no longer needed.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Append one validated staged name and value to the bounded definition table.

CP_PP_STORE_DEFINE:
    LD   A,(CP_PP_DEFINE_COUNT)  ; Read the number of occupied records.
    CP   CP_PP_DEFINE_CAPACITY  ; The table is deliberately finite on CP/M.
    JP   NC,CP_PP_BAD_CARRY  ; Reject a thirty-third distinct definition.
    LD   B,A                ; Advance over the occupied fixed-width records.
    LD   IX,CP_PP_DEFINE_TABLE  ; Start with the first slot.
    OR   A                  ; A zero count already selects that slot.
    JR   Z,CP_PP_STORE_DEFINE_AT  ; The first record needs no pointer step.
CP_PP_STORE_DEFINE_NEXT:
    LD   DE,CP_PP_DEFINE_ENTRY_BYTES  ; Advance by one complete record.
    ADD  IX,DE              ; Select the following definition slot.
    DJNZ CP_PP_STORE_DEFINE_NEXT  ; Skip every occupied record.
CP_PP_STORE_DEFINE_AT:
    LD   A,(CP_PP_NAME_LENGTH)  ; Store the exact significant-name length.
    LD   (IX+0),A           ; Record byte zero is the name length.
    INC  IX                 ; Name bytes begin at record offset one.
    LD   HL,CP_PP_NAME      ; Read the staged uppercase field.
    LD   B,CP_PP_NAME_BYTES  ; Copy every name and padding position.
CP_PP_STORE_DEFINE_NAME:
    LD   A,(HL)             ; Read a name character or its space padding.
    LD   (IX+0),A           ; Store it in the current record position.
    INC  HL                 ; Advance through the staged name.
    INC  IX                 ; Advance through the record name field.
    DJNZ CP_PP_STORE_DEFINE_NAME  ; Copy the complete fixed-width field.
    LD   HL,(CP_PP_NUM_VALUE)  ; Load the previously validated value.
    LD   (IX+0),L           ; Store its low byte at record offset eighteen.
    LD   (IX+1),H           ; Store its high byte at record offset nineteen.
    LD   HL,CP_PP_DEFINE_COUNT  ; Address the number of published definitions.
    INC  (HL)               ; Make the complete record visible to IF lookup.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Preserve every existing definition.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Mask inactive source bytes while preserving every CR/LF byte and offset.

CP_PP_RUNTIME_FILTER:
    PUSH BC                 ; The source-provider boundary preserves BC.
    PUSH IX                 ; Definition lookup uses IX internally.
    LD   (CP_PP_CURRENT_OFFSET),HL  ; Save the byte's source position.
    LD   (CP_PP_NUM_DIGIT),A  ; Keep the raw byte across directive detection.
    CP   '%'                ; Only a line-leading percent starts a directive.
    JR   NZ,CP_PP_FILTER_ACTIVITY  ; Ordinary bytes follow current activity.
    PUSH HL                 ; The line-prefix check scans backwards.
    CALL CP_PERCENT_IS_DIRECTIVE  ; Ignore '%' in strings and expressions.
    POP  HL                 ; Restore the exact byte offset.
    JR   NZ,CP_PP_FILTER_ACTIVITY  ; Return ordinary percent text unchanged.
    LD   DE,(CP_PP_CURRENT_OFFSET)  ; Compare with last directive offset.
    LD   HL,(CP_PP_LAST_DIRECTIVE)  ; A peek may request this byte again.
    OR   A                  ; Clear carry before the equality subtraction.
    SBC  HL,DE              ; Has this source offset already changed state?
    JR   Z,CP_PP_FILTER_COMMENT  ; A repeated peek must not push twice.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Restore the directive's source location.
    INC  HL                 ; Keyword text begins after the percent marker.
    CALL CP_PP_RUNTIME_DIRECTIVE  ; Apply IF/ELSE/ENDIF exactly once.
    JR   C,CP_PP_FILTER_FAILURE  ; A changed source cannot be filtered safely.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Record the processed directive's offset.
    LD   (CP_PP_LAST_DIRECTIVE),HL  ; Skip matching tokenizer consume.
CP_PP_FILTER_COMMENT:
    LD   A,';'              ; Atom skips this line as a comment.
    JR   CP_PP_FILTER_RETURN  ; Do not expose directive tokens to the core.
CP_PP_FILTER_ACTIVITY:
    LD   A,(CP_PP_ACTIVE)   ; Check whether this branch is active.
    OR   A                  ; An active branch preserves its exact source.
    JR   NZ,CP_PP_FILTER_RAW  ; Return the original byte unchanged.
    LD   A,(CP_PP_NUM_DIGIT)  ; Restore the original byte for newline checks.
    CP   13                 ; CR remains visible to the Atom tokenizer.
    JR   Z,CP_PP_FILTER_RAW  ; Preserve the original line ending.
    CP   10                 ; LF is also preserved byte-for-byte.
    JR   Z,CP_PP_FILTER_RAW  ; Keep CRLF and LF line counts unchanged.
    LD   A,' '              ; Inactive source becomes harmless whitespace.
    JR   CP_PP_FILTER_RETURN  ; Preserve its byte offset and column.
CP_PP_FILTER_RAW:
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Keep the source position beside the byte.
    LD   A,(CP_PP_NUM_DIGIT)  ; Restore the original active or line-ending byte.
    CALL CP_BIN_RUNTIME_FILTER  ; Lower an active INCBIN line to its DS form.
    JR   C,CP_PP_FILTER_FAILURE  ; A failed binary read aborts the generation.
CP_PP_FILTER_RETURN:
    POP  IX                 ; Restore the caller's index register.
    POP  BC                 ; Restore the parser's byte and loop state.
    OR   A                  ; Clear carry and classify a zero byte.
    RET                     ; Return the filtered source byte.
CP_PP_FILTER_FAILURE:
    POP  IX                 ; Restore index state on a rejected source change.
    POP  BC                 ; Restore parser state before reporting failure.
    LD   A,2                ; Distinguish a preflight/runtime mismatch.
    SCF                     ; Carry reports the unavailable source byte.
    RET                     ; Atom aborts without committing its output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Return a generic carry-set failure for malformed stack or value state.

CP_PP_BAD_CARRY:
    SCF                     ; Report an invalid conditional or number.
    RET                     ; The caller supplies the public diagnostic.

; Directive spellings are separate data so one matcher enforces exact tokens.
CP_PP_WORD_INCLUDE: DB 'I','N','C','L','U','D','E'  ; Include keyword.
CP_PP_WORD_DEFINE: DB 'D','E','F','I','N','E'  ; Root numeric definition.
CP_PP_WORD_IF: DB 'I','F'   ; Conditional opener.
CP_PP_WORD_ELSE: DB 'E','L','S','E'  ; Alternate branch.
CP_PP_WORD_ENDIF: DB 'E','N','D','I','F'  ; Conditional closer.
