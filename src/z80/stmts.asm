; Statements, labels and directives
;
;  PURPOSE
;  -------
;  Turn one source part into labels, constants, directives and instructions.
;  This layer owns source-statement grammar. It leaves
;  token recognition, expression arithmetic, instruction forms, symbols and
;  output transactions to the modules below it.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
; DR_APART / ST_NEXT assembles the current source part.
; TK_RESET must first select its part and range. At EOF, carry is clear and
; A = 0. On error, carry is set and A holds an ST_S* category. ST_DETAI holds
; the nested status; ST_EPART/ST_EOFF hold the source location.
; Side effects: symbol declarations and IMAGE/PATCH output.
;
;  STATEMENT SHAPES
;  ----------------
;
;  Blank lines are ignored. A non-empty line begins with a name and follows
;  one of these forms:
;
;      NAME ':' [instruction-or-directive]
;      NAME EQU expression
;      NAME instruction-operands
;      NAME directive-operands
;
;  The first name is tested as a mnemonic and directive before the following
;  token is known. Those recognition results are cached so the colon/no-colon
;  decision never needs to rewind the stream.
;
;  Label declarations immediately call OU_RSLV. This emits patches for waiting
;  references. It removes pending records only after the sink accepts the
;  patch. EQU uses the same resolution path once its expression is concrete.
;
;  WORKSPACE AND REENTRANCY
;  ------------------------
;
;  ST_WUNIO is a 20-byte union. Statement forms execute serially, so mnemonic,
;  EQU, data and string temporaries deliberately overlap. The final four bytes
;  outside the union retain error position and string source-part identity.
;  This shared state makes the module non-reentrant.

ST_CBEG:

; Public statement categories returned to the multipart driver.

ST_SOK EQU 0               ; Completed the source part successfully.
ST_SLEXI EQU 1             ; Tokenizer rejected the source text.
ST_SEXP EQU 2              ; Statement grammar or expression failed.
ST_SDIR EQU 3              ; Directive arguments were invalid.
ST_SEQUA EQU 4             ; EQU expression or trailing-token check failed.
ST_SSYM EQU 5              ; Symbol declaration or reference failed.
ST_SINS EQU 6              ; Instruction parsing or validation failed.
ST_SOUT EQU 7              ; Output emission or patching failed.
ST_SUNDE EQU 8             ; Finalization found an undefined symbol.
ST_SINT EQU 9              ; An internal invariant was violated.

; Directive ordinals returned by EN_RDIR and used by the dispatch table.

ST_EQU EQU 1               ; Declare an immediate constant.
ST_ORG EQU 2               ; Move the output cursor.
ST_DB EQU 3                ; Emit byte expressions or strings.
ST_DW EQU 4                ; Emit little-endian word expressions.
ST_DS EQU 5                ; Reserve or fill a byte range.
ST_CSTR EQU 6              ; Emit a zero-terminated string.
ST_PSTR EQU 7              ; Emit a length-prefixed string.
ST_ISTR EQU 8              ; Emit a string with bit 7 on its final byte.
ST_ALIGN EQU 9             ; Advance to the next address boundary.
ST_CNT EQU 9               ; Number of recognized directive names.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Assemble the current source part through its EOF token.

DR_APART:
ST_NEXT:

; Fetch the first token. EOF finishes only this source part; an EOL
; is an empty statement and simply restarts the loop.

    CALL ST_NTKIN              ; Fetch the first token kind into A.
    JP   C,ST_LFAIL            ; Preserve an exact tokenizer failure location.
    CP   TK_EOF                ; Has this source part ended?
    JP   Z,ST_SUCCE            ; Yes: return success to the multipart driver.
    CP   TK_EOL                ; Is this an empty source line?
    JR   Z,ST_NEXT             ; Yes: ignore it and fetch the next statement.
    CP   TK_NAME               ; Does this statement start with a name?
    JP   NZ,ST_EHERE           ; Report the unexpected starting token.

; Preserve the statement's starting position before any nested parser advances
; the tokenizer. All later failures on this line report this stable location.

    CALL ST_CPOSI              ; Anchor later diagnostics at the leading name.

; Pack the leading name once as a possible label or EQU destination.

    CALL TK_LLEXE              ; Return the name text as HL plus byte count B.
    LD   DE,ST_KEY             ; Select the six-byte packed-name destination.
    CALL EN_PSYM               ; Pack and validate the possible symbol name.
    JP   C,ST_SFAIL            ; Translate packing failure to symbol status.

; Classify the same lexeme as a mnemonic. ST_MVALI marks ST_MNEM as valid;
; ordinal zero is not a validity sentinel.

    CALL TK_LLEXE              ; Reload the still-current leading lexeme.
    CALL EN_RECOG              ; Look for an exact mnemonic match.
    JR   C,ST_NMNEM            ; No mnemonic: try the directive table.
    LD   (ST_MNEM),A           ; Cache the recognized mnemonic ordinal.
    LD   A,1                   ; Form an explicit Boolean validity marker.
    LD   (ST_MVALI),A          ; Mark the cached mnemonic as usable.
    XOR  A                     ; Clear the alternative classification.
    LD   (ST_DVALI),A          ; Clear the directive-valid marker.
    JR   ST_AFNAM              ; Inspect the token following the leading name.
ST_NMNEM:

; If it was not a mnemonic, test the compact directive table and cache that
; result in the parallel ST_DIR/ST_DVALI pair.

    XOR  A                     ; Record that mnemonic recognition failed.
    LD   (ST_MVALI),A          ; Prevent stale mnemonic data being consumed.
    CALL TK_LLEXE              ; Reload the lexeme for directive lookup.
    CALL EN_RDIR               ; Search the compact directive-name table.
    JR   C,ST_NDIR             ; Leave both validity flags clear if absent.
    LD   (ST_DIR),A            ; Cache the directive ordinal.
    LD   A,1                   ; Form the directive-valid Boolean.
    LD   (ST_DVALI),A          ; Mark the cached directive as usable.
    JR   ST_AFNAM              ; Inspect the token following the leading name.
ST_NDIR:
    XOR  A                     ; Neither mnemonic nor directive matched.
    LD   (ST_DVALI),A          ; Clear the remaining validity flag.
ST_AFNAM:

; The token after the leading name determines whether the packed name is a
; declaration target or whether the name itself selects the statement kind.

    CALL ST_NTKIN              ; Advance beyond the leading name.
    JP   C,ST_LFAIL            ; Propagate a lexical failure at that token.
    CP   TK_COLON               ; Does the name introduce a label declaration?
    JR   Z,ST_LABEL             ; Yes: declare it before processing any tail.

; A recognized mnemonic without a colon begins an instruction immediately.

    LD   A,(ST_MVALI)          ; Test the cached mnemonic classification.
    OR   A                     ; Set Z when no mnemonic matched.
    JP   NZ,ST_IPUB            ; Matched: parse its operands.

; A recognized non-EQU directive without a colon goes to directive dispatch.

    LD   A,(ST_DVALI)          ; Test the cached directive classification.
    OR   A                     ; Set Z when no directive matched either.
    JR   Z,ST_TEQUA            ; Try the NAME EQU expression declaration form.
    LD   A,(ST_DIR)            ; Restore the cached directive ordinal.
    JP   ST_DPUB               ; Dispatch its operand grammar.
ST_TEQUA:

; An unrecognized leading name may still be the destination of colonless EQU.
; The current token must itself be the recognized EQU directive.

    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token after the constant name.
    CP   TK_NAME               ; Only another name can be the EQU directive.
    JP   NZ,ST_ESAVE           ; Otherwise report the unexpected token kind.
    CALL TK_LLEXE              ; Expose the second name's characters.
    CALL EN_RDIR               ; Classify it through the directive table.
    JP   C,ST_ESAVE            ; An unknown name is invalid in this position.
    CP   ST_EQU                ; Did the recognized directive equal EQU?
    JP   NZ,ST_ESAVE           ; No other directive may follow a bare name.
    JP   ST_EQUAT              ; Parse and declare the constant.
ST_LABEL:

; After a colon, recognize the special convenience form "label: EQU value".
; Any other token leaves the declaration as an address label.

    CALL ST_NTKIN              ; Consume colon and fetch the next token.
    JP   C,ST_LFAIL            ; Preserve any tokenizer error.
    CP   TK_NAME               ; A name here might be the EQU directive.
    JR   NZ,ST_LPUBL           ; Anything else leaves an address label.
    CALL TK_LLEXE              ; Expose the possible directive text.
    CALL EN_RDIR               ; Attempt directive recognition.
    JR   C,ST_LPUBL            ; No directive: declare an address label.
    CP   ST_EQU                ; Is this specifically EQU?
    JR   Z,ST_EQUAT            ; EQU: declare a constant.
ST_LPUBL:

; The packed key's private bit selects the declaration rule. A global address
; label closes the previous private scope; a private label remains within it.

    LD   HL,ST_KEY+5           ; Address the packed symbol's flag byte.
    BIT  7,(HL)                ; Test the private-name marker.
    LD   HL,ST_KEY             ; Supply the packed symbol key.
    LD   DE,(OU_CURSO)         ; Bind the label to the current output address.
    JR   NZ,ST_PLABE           ; Private names use the current global scope.
    CALL SY_DGLAB              ; Declare a global and open its private scope.
    JR   ST_LDECL              ; Share declaration and resolution checks.
ST_PLABE:
    CALL SY_DECL               ; Declare in the active private scope.
ST_LDECL:
    JP   C,ST_SFAIL            ; Report a symbol declaration failure.

; A newly known address may satisfy several forward references. Resolution is
; transactional with the sink and leaves diagnostics intact on failure.

    CALL OU_RSLV               ; Emit and retire this symbol's patches.
    JP   C,ST_OFAIL            ; Preserve transactional output failure.

; A bare label ends at EOL. Otherwise the same line may continue with exactly
; one instruction or directive name.

    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token after the label.
    CP   TK_EOL                ; Is the label the complete statement?
    JP   Z,ST_NEXT             ; Yes: begin the next line.
    CP   TK_NAME               ; A statement tail must start with a name.
    JP   NZ,ST_EHERE           ; Reject a non-name statement tail.
    CALL ST_CPOSI              ; Anchor errors at the operation name.
    CALL TK_LLEXE              ; Expose that name for mnemonic lookup.
    CALL EN_RECOG              ; Try to recognize an instruction.
    JR   C,ST_LDIR             ; If absent, try the directive table instead.

; Cache the mnemonic, consume its name and share the ordinary
; instruction path used by statements without a label.

    LD   (ST_MNEM),A           ; Cache the post-label mnemonic ordinal.
    CALL TK_NEXT               ; Consume the name; expose its first operand.
    JP   C,ST_LFAIL            ; Retain a lexical error in its operands.
    JR   ST_IPUB               ; Join ordinary instruction parsing.
ST_LDIR:

; The post-label name was not a mnemonic. It must be a recognized directive.

    CALL TK_LLEXE              ; Reload the name for directive lookup.
    CALL EN_RDIR               ; Look for an exact directive match.
    JP   C,ST_ESAVE            ; Unknown operation names are statement errors.
    LD   (ST_DIR),A            ; Save the directive across token advancement.
    CALL TK_NEXT               ; Consume the directive name.
    JP   C,ST_LFAIL            ; Preserve a lexical failure in its arguments.
    LD   A,(ST_DIR)            ; Restore the directive ordinal for dispatch.
    JR   ST_DPUB               ; Enter the common directive dispatcher.
ST_IPUB:

; Parse and validate operands into ST_INS. Use the output cursor as the
; instruction address. Relative expressions depend on that address.

    LD   A,(ST_MNEM)           ; Supply the recognized mnemonic ordinal.
    LD   BC,(OU_CURSO)         ; Supply the instruction's output address.
    LD   DE,ST_INS             ; Select the union's parsed-instruction record.
    CALL PR_PUB                ; Parse and validate the instruction form.
    JP   C,ST_IFAIL            ; Wrap a parser error as instruction failure.

; Emit one to four instruction bytes, then fetch the next line.

    CALL OU_EINS               ; Encode and publish the validated instruction.
ST_OTNEX:
    JP   C,ST_OFAIL            ; Convert any output error to statement status.
    JP   ST_NEXT               ; Continue with the next source statement.
ST_EQUAT:

; Consume EQU and evaluate its expression at the current output address.

    CALL TK_NEXT               ; Consume EQU; expose its expression.
    JP   C,ST_LFAIL            ; Preserve a lexical failure before evaluation.
    CALL ST_PEXPR              ; Evaluate at the current output address.
    JP   C,ST_EFAIL            ; Wrap an expression error as EQU failure.

; EQU must be known now. A forward EQU would require delayed expression
; evaluation rather than the byte patches used for address references.

    OR   A                     ; A is nonzero when the result is unresolved.
    JP   NZ,ST_EUNRE           ; EQU requires a value immediately.

; Save the low word. Derive its sign from the expression's high
; extension byte: zero is unsigned/non-negative, nonzero is negative.

    LD   (ST_EVAL),HL          ; Save the result's low sixteen bits.
    XOR  A                     ; Start with a non-negative sign flag.
    LD   HL,EX_RVAL+2          ; Address the expression's extension byte.
    CP   (HL)                  ; Is the extension zero?
    JR   Z,ST_ESREA            ; Yes: retain the clear sign flag.
    INC  A                     ; No: mark the constant as sign-extended.
ST_ESREA:
    LD   (ST_ESIGN),A          ; Preserve signedness across delimiter checks.

; No token may follow the EQU expression on the statement.

    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token left by expression parsing.
    CP   TK_EOL                ; Did the expression end at EOL?
    JP   NZ,ST_EDELI           ; Report any trailing delimiter or token.

; EQU declares in the current scope without opening a new global scope.

    LD   HL,ST_KEY             ; Supply the packed constant name.
    LD   DE,(ST_EVAL)          ; Supply its immediate sixteen-bit value.
    CALL SY_DECL               ; Declare it without changing global scope.
    JP   C,ST_SFAIL            ; Preserve a symbol declaration failure.

; Mark negative constants in the packed symbol record
; before resolving any waiting references to its newly concrete value.

    LD   A,(ST_ESIGN)          ; Recover the saved sign-extension flag.
    OR   A                     ; Set Z for a non-negative constant.
    JR   Z,ST_ERSLV            ; Leave its symbol flags unchanged.
    SET  5,(IX+5)              ; Mark it negative for later expressions.
ST_ERSLV:
    CALL OU_RSLV               ; Resolve pending uses of the new constant.
    JR   ST_OTNEX              ; Check output status and continue.
ST_DPUB:

; EQU is handled by the declaration grammar above. Subtracting ST_ORG maps the
; remaining contiguous ordinals onto the eight-entry address table.

    SUB  ST_ORG                ; Index ORG..ALIGN from zero.
    CP   8                     ; Is this one of eight table entries?
    JP   NC,ST_ESAVE           ; Reject EQU or a corrupt/out-of-range ordinal.
    ADD  A,A                   ; Scale the index for a two-byte address entry.
    LD   L,A                   ; Place the scaled offset in HL.
    LD   H,0                   ; Zero-extend it to sixteen bits.
    LD   DE,ST_DDTAB           ; Point DE at the directive address table.
    ADD  HL,DE                 ; Address the selected little-endian entry.
    LD   E,(HL)                ; Load the handler address low byte.
    INC  HL                    ; Advance to its high byte.
    LD   D,(HL)                ; Complete the handler address in DE.
    EX   DE,HL                 ; Put the handler address in HL.
    JP   (HL)                  ; Dispatch without another comparison chain.
ST_DDTAB:

; ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN handlers in ordinal order.

    DW ST_ORG1,ST_DB1,ST_DW1,ST_DS1       ; Numeric and storage directives.
    DW ST_CSTR1,ST_PSTR1,ST_ISTR1         ; Three standalone string formats.
    DW ST_ALIG1                            ; Address-alignment directive.
ST_ORG1:

; ORG requires one concrete expression and no trailing token. It changes the
; logical output cursor; the platform adapter owns extent and append policy.

    CALL ST_PEXPR              ; Evaluate the absolute output address.
    JP   C,ST_DFAIL            ; Preserve expression syntax or range detail.
    OR   A                     ; Test the unresolved-result flag.
    JP   NZ,ST_DUNR1           ; ORG cannot wait for a forward definition.
    LD   (ST_DVAL),HL          ; Save the address across delimiter validation.
    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token following the expression.
    CP   TK_EOL                ; ORG accepts exactly one expression.
    JP   NZ,ST_DDEL1           ; Report the unexpected trailing token.
    LD   HL,(ST_DVAL)          ; Restore the requested origin.
    CALL OU_SORIG              ; Set the logical output cursor.
    JP   ST_OTNEX              ; Check output status and continue.
ST_DB1:

; Width and default patch kind distinguish DB from DW. Both
; then share the comma-separated item loop.

    LD   A,1                   ; Select one emitted byte per scalar item.
    LD   (ST_DWIDT),A          ; Retain DB width for the shared list loop.
    LD   A,PT_KTB              ; Select the ordinary byte patch kind.
    LD   (ST_DPKIN),A          ; Retain it for an unresolved expression.
    JR   ST_DITEM              ; Enter the common data-item parser.
ST_DW1:
    LD   A,2                   ; Select two emitted bytes per scalar item.
    LD   (ST_DWIDT),A          ; Retain DW width for the shared list loop.
    LD   A,PT_KINDW            ; Select the ordinary word patch kind.
    LD   (ST_DPKIN),A          ; Retain it for an unresolved expression.
ST_DITEM:

; A data list cannot be empty or end immediately after a comma.

    LD   A,(TK_REC+TK_KOFF)    ; Read the current prospective item token.
    CP   TK_EOL                ; Did the list end before an item appeared?
    JP   Z,ST_DEXP             ; Report the missing expression.

; Quoted strings are accepted only in DB. They use mode zero so the common
; string emitter returns to the data-list delimiter path, not the end of
; the whole statement.

    CP   TK_STRIN              ; Is this item a quoted string?
    JR   NZ,ST_DEXPR           ; No: parse it as a scalar expression.
    LD   A,(ST_DWIDT)          ; Recover the active data width.
    CP   1                     ; Are we assembling DB rather than DW?
    JP   NZ,ST_DSTR1           ; Reject strings in a word list.
    XOR  A                     ; Mode zero denotes an inline DB string.
    LD   (ST_SMODE),A          ; Select list-aware completion behavior.
    JP   ST_DSTRI              ; Count, preflight and emit the decoded string.
ST_DEXPR:

; A concrete expression emits its low byte or low word immediately.

    CALL ST_PEXPR              ; Evaluate the scalar data item.
    JP   C,ST_DFAIL            ; Preserve nested expression failure detail.
    OR   A                     ; Is the expression waiting on a symbol?
    JR   NZ,ST_DUNRE           ; Yes: reserve bytes and queue a patch.
    LD   A,(ST_DWIDT)          ; Recover the active DB/DW width.
    CP   1                     ; Does this item emit one byte?
    JR   Z,ST_DRB              ; Yes: publish only L.
    CALL OU_EMITW              ; Publish HL in little-endian order.
    JR   ST_DORES              ; Share output checking and delimiter parsing.
ST_DRB:
    LD   A,L                   ; Select the expression's low byte.
    CALL OU_EMITB              ; Publish the byte through the output sink.
ST_DORES:
    JP   C,ST_OFAIL            ; Preserve output capacity or sink failure.
    JP   ST_DDELI              ; Require comma or end-of-line next.
ST_DUNRE:

; A simple unresolved symbol may be represented by a pending patch. Save
; the addend and symbol pointer before a capacity or emission call can
; reuse IX, HL or the shared expression workspace.

    LD   A,L                   ; Capture the signed expression addend.
    LD   (ST_DADDE),A          ; Preserve it for the pending record.
    PUSH IX                    ; Save the expression symbol pointer.
    POP  HL                    ; Receive that pointer in HL.
    LD   (ST_DKEY),HL          ; Preserve it across capacity checks.
    LD   A,(ST_DWIDT)          ; Recover the placeholder byte count.
    LD   L,A                   ; Put that count in low word byte.
    LD   H,0                   ; Zero-extend it for output preflight.

; Prove both output and pending-record capacity before publishing a zero
; placeholder. On failure, stream and symbol state remain unchanged.

    CALL OU_CCAP               ; Prove the placeholder fits the output range.
    JP   C,ST_OFAIL            ; Fail before any visible write on exhaustion.
    CALL SY_CCAP               ; Prove one pending record fits its arena.
    JP   C,ST_SFAIL            ; Fail before emission if it does not.
    LD   A,(EX_RUNRE)          ; Read the unresolved projection form.
    CP   EX_FLO                ; Was LOW(...) requested?
    JR   Z,ST_DPLO             ; Yes: use a low-byte patch.
    CP   EX_FHI                ; Was HIGH(...) requested?
    JR   Z,ST_DPHI             ; Yes: use a high-byte patch.

; Plain unresolved DB/DW uses the directive's width-specific patch kind. LOW
; and HIGH expression forms override that with the corresponding byte patch.

    LD   A,(ST_DPKIN)          ; Use the DB/DW default patch kind.
    JR   ST_DPKRE              ; Store the selected kind.
ST_DPLO:
    LD   A,PT_KLB              ; Select low-byte extraction at resolution.
    JR   ST_DPKRE              ; Store the selected kind.
ST_DPHI:
    LD   A,PT_KHB              ; Select high-byte extraction at resolution.
ST_DPKRE:
    LD   (ST_DPKI1),A          ; Preserve the kind across symbol lookup.

; Find or create the undefined symbol record. B reports whether this is the
; first reference, which is the one that must retain the diagnostic anchor.

    LD   HL,(ST_DKEY)          ; Restore the packed unresolved symbol pointer.
    CALL SY_REF                ; Find or create its undefined symbol record.
    JP   C,ST_SFAIL            ; Preserve symbol arena or scope failure.
    LD   A,B                   ; B is nonzero only for the first reference.
    OR   A                     ; Set Z for a previously referenced symbol.
    JR   Z,ST_DDREA            ; Reuse its existing diagnostic anchor.

; Store the first reference offset in the undefined symbol's value word
; and mark this pending record as its diagnostic anchor.

    LD   HL,(EX_SOFF)          ; Recover the expression's source-byte offset.
    LD   (IX+SY_VALLO),L       ; Store its low byte in the undefined record.
    LD   (IX+SY_VALHI),H       ; Store its high byte to complete the anchor.
    LD   A,SY_DANCH            ; Select the diagnostic-anchor flag.
    LD   HL,ST_DPKI1           ; Address the pending patch kind.
    OR   (HL)                  ; Add the anchor flag to the patch kind.
    LD   (HL),A                ; Retain the combined pending metadata.
ST_DDREA:

; Preserve the symbol and patch address while the placeholder is emitted.

    PUSH IX                    ; Copy the symbol-record pointer from IX.
    POP  HL                    ; Receive the pointer in HL for storage.
    LD   (ST_DSYM),HL          ; Preserve it across placeholder emission.
    LD   HL,(OU_CURSO)         ; Capture the placeholder's target address.
    LD   (ST_DADR),HL          ; Retain that address for the pending record.
    LD   A,(ST_DWIDT)          ; Recover the placeholder width.
    CP   1                     ; Is this an unresolved DB item?
    JR   Z,ST_DPB              ; Yes: emit one zero byte.

; Emit a zero-filled placeholder. A later PATCH carries the final value.

    LD   HL,0                  ; Form a two-byte zero placeholder.
    CALL OU_EMITW              ; Emit the preflighted two-byte placeholder.
    JP   C,ST_OFAIL            ; Preserve any unexpected sink failure.
    JR   ST_DQUEU              ; Append its pending patch record.
ST_DPB:
    XOR  A                     ; Form a one-byte zero placeholder.
    CALL OU_EMITB              ; Publish the reserved byte.
    JP   C,ST_OFAIL            ; Preserve any unexpected sink failure.
ST_DQUEU:

; Append the seven-byte pending record only after the placeholder emission
; succeeds. It captures symbol, target address, kind, addend and source part.

    LD   IX,(ST_DSYM)          ; Restore the referenced symbol record.
    LD   DE,(ST_DADR)          ; Supply the placeholder target address.
    LD   A,(ST_DPKI1)         ; Recover the kind and possible anchor flag.
    LD   B,A                   ; Place pending metadata in its ABI register.
    LD   A,(ST_DADDE)          ; Recover the signed expression addend.
    LD   C,A                   ; Place the addend in its ABI register.
    LD   A,(EX_SPART)          ; Supply the reference's source-part ordinal.
    CALL SY_ADD                ; Append the fully described pending record.
    JP   C,ST_SFAIL            ; Preserve capacity or invariant failure.
ST_DDELI:

; Accept EOL or comma followed by another item. A trailing comma reports
; a missing expression.

    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token following the emitted item.
    CP   TK_EOL                ; Has the data list ended?
    JP   Z,ST_NEXT             ; Yes: begin the next statement.
    CP   TK_COMMA              ; Otherwise require an item separator.
    JP   NZ,ST_DDEL1           ; Report the unexpected delimiter.
    CALL ST_NTKIN              ; Consume the comma and fetch the next item.
    JP   C,ST_LFAIL            ; Preserve a tokenizer failure after the comma.
    CP   TK_EOL                ; Did the list end immediately after it?
    JP   Z,ST_DEXP             ; Diagnose the missing item.
    JP   ST_DITEM              ; Parse the next scalar or string item.
ST_DSTRI:

; First pass: count decoded bytes without emitting. The tokenizer has
; validated the closing quote and token length. HL is the raw offset,
; B the raw bytes remaining and C the decoded count.

    LD   HL,(TK_REC+TK_SOFF)   ; Start at the string token's opening quote.
    INC  HL                    ; Advance to its first raw content byte.
    LD   A,(TK_REC+TK_LOFF1)   ; Read the token's complete raw byte length.
    SUB  2                     ; Exclude the opening and closing quotes.
    LD   B,A                   ; Count raw content bytes remaining.
    LD   C,0                   ; Start the decoded output-byte count at zero.
ST_SCLOO:
    LD   A,B                   ; Test the remaining raw-byte count.
    OR   A                     ; Set Z after the final raw byte.
    JR   Z,ST_SCDON            ; Finish the counting pass.

; Read one raw byte through the source service. Preserve the offset across
; the call because TK_SREAD returns the byte in A but may clobber HL.

    PUSH HL                    ; Save the offset across the callback.
    LD   A,(TK_REC+TK_POFF)    ; Supply the string's source-part ordinal.
    CALL TK_SREAD              ; Read the raw byte at that logical offset.
    POP  HL                    ; Restore the current raw cursor.
    INC  HL                    ; Advance past the consumed raw byte.
    DEC  B                     ; Remove it from the remaining raw count.
    CP   $5C                   ; Was the byte a backslash escape introducer?
    JR   NZ,ST_SCONE           ; No: it decodes directly to one byte.

; A backslash escape consumes at least one more raw character while still
; producing one byte. A hexadecimal escape consumes two further digits.

    PUSH HL                    ; Save the cursor across the escape read.
    LD   A,(TK_REC+TK_POFF)    ; Reuse the string's source-part ordinal.
    CALL TK_SREAD              ; Read the character following the backslash.
    POP  HL                    ; Restore the raw cursor.
    INC  HL                    ; Advance past the escape code.
    DEC  B                     ; Remove that code from the remaining count.
    CP   $78                   ; Does this begin a hexadecimal escape, \xHH?
    JR   NZ,ST_SCONE           ; Other escapes consume no more raw bytes.
    INC  HL                    ; Skip the high hexadecimal digit.
    INC  HL                    ; Skip the low hexadecimal digit.
    DEC  B                     ; Remove the high digit from the raw count.
    DEC  B                     ; Remove the low digit from the raw count.
ST_SCONE:

; Count the decoded byte represented by the raw character or complete escape.

    INC  C                     ; Count one decoded output byte.
    JR   ST_SCLOO              ; Count the remaining encoded characters.
ST_SCDON:

; Rewind to the first character and retain all source-service state needed by
; the emission pass. Quotes themselves are excluded from ST_SREM.

    LD   A,C                   ; Recover the decoded payload length.
    LD   (ST_SCNT),A           ; Preserve it for capacity and PSTR prefix.
    LD   HL,(TK_REC+TK_SOFF)   ; Rewind to the opening quote.
    INC  HL                    ; Select the first raw content byte again.
    LD   (ST_SPTR),HL          ; Initialize the emission-pass cursor.
    LD   A,(TK_REC+TK_POFF)    ; Read the string's source-part ordinal.
    LD   (ST_SPART),A          ; Preserve it for all emission-pass reads.
    LD   A,(TK_REC+TK_LOFF1)   ; Reload the complete raw token length.
    SUB  2                     ; Exclude both quote bytes again.
    LD   (ST_SREM),A           ; Initialize raw bytes remaining for emission.

; Standalone strings occupy the rest of the statement. DB strings defer
; delimiter checking so the data list can continue.

    LD   A,(ST_SMODE)          ; Test whether this is embedded DB-string mode.
    OR   A                     ; Mode zero keeps the data-list grammar active.
    JR   Z,ST_SCAP             ; Delay delimiter handling for a DB string.
    CALL ST_NTKIN              ; Consume a standalone string token.
    JP   C,ST_LFAIL            ; Preserve a following tokenizer failure.
    CP   TK_EOL                ; Standalone string must finish the line.
    JP   NZ,ST_DDEL1           ; Reject any trailing token.
ST_SCAP:

; Capacity is decoded payload length plus one byte for CSTR's terminator or
; PSTR's prefix. ISTR and a DB string need no extra byte.

    LD   A,(ST_SCNT)           ; Load the decoded payload length.
    LD   L,A                   ; Place it in the low byte of capacity HL.
    LD   H,0                   ; Zero-extend the capacity request.
    LD   A,(ST_SMODE)          ; Inspect the selected string representation.
    CP   1                     ; Does CSTR need a terminating zero?
    JR   Z,ST_SCEXT            ; Yes: reserve one extra byte.
    CP   2                     ; Does PSTR need a length prefix?
    JR   NZ,ST_SCREA           ; No: payload capacity alone is sufficient.
ST_SCEXT:
    INC  HL                    ; Include the terminator or prefix byte.
ST_SCREA:
    CALL OU_CCAP               ; Preflight the complete string output.
    JP   C,ST_OFAIL            ; Fail before publishing any prefix or payload.

; PSTR writes its one-byte decoded length before the payload.

    LD   A,(ST_SMODE)          ; Test for length-prefixed representation.
    CP   2                     ; Is this PSTR mode?
    JR   NZ,ST_SELOO           ; No: begin directly with payload bytes.
    LD   A,(ST_SCNT)           ; Select the decoded one-byte length.
    CALL OU_EMITB              ; Emit it before the payload.
    JP   C,ST_OFAIL            ; Preserve an unexpected sink failure.
ST_SELOO:

; Emit decoded characters until every raw byte inside the quotes is consumed.

    LD   A,(ST_SREM)           ; Read raw bytes remaining in the quoted token.
    OR   A                     ; Have all raw bytes been consumed?
    JR   Z,ST_SDONE            ; Yes: finish according to the string mode.
    CALL ST_STAKE              ; Consume one raw source byte.
    CP   $5C                   ; Does it introduce an escape sequence?
    JR   NZ,ST_SEMIT           ; No: emit the byte literally.

; Translate a standard one-character escape through the tokenizer's escape
; table, except \x which has its own two-hex-digit path.

    CALL ST_STAKE              ; Consume the escape-code character.
    CP   $78                   ; Is it the hexadecimal escape marker x?
    JR   Z,ST_SHEX             ; Yes: decode the following two digits.
    CALL TK_DESCA              ; Translate a standard one-character escape.
    JP   C,ST_DSTR1            ; Defensively reject an unknown escape code.
    JR   ST_SEMIT              ; Emit the translated byte.
ST_SHEX:

; Form one byte from the high and low hexadecimal nibbles. TK_HDIGI signals a
; valid digit with carry set, hence the deliberately inverted-looking tests.

    CALL ST_STAKE              ; Consume the high hexadecimal digit.
    CALL TK_HDIGI              ; Convert it to a nibble.
    JP   NC,ST_DSTR1           ; Reject a non-hexadecimal character.
    ADD  A,A                   ; Shift the nibble left one bit.
    ADD  A,A                   ; Shift it left two bits total.
    ADD  A,A                   ; Shift it left three bits total.
    ADD  A,A                   ; Place it in the output byte's high nibble.
    LD   (ST_SNIBB),A          ; Preserve the shifted high nibble.
    CALL ST_STAKE              ; Consume the low hexadecimal digit.
    CALL TK_HDIGI              ; Convert it to a nibble.
    JP   NC,ST_DSTR1           ; Reject a non-hexadecimal character.
    LD   HL,ST_SNIBB           ; Address the saved high nibble.
    OR   (HL)                  ; Combine both nibbles into the decoded byte.
ST_SEMIT:

; ISTR sets bit 7 on its final decoded byte. ST_SREM counts raw bytes;
; after ST_STAKE finishes a character or escape, zero therefore identifies the
; final output character.

    LD   C,A                   ; Preserve the decoded byte during mode checks.
    LD   A,(ST_SMODE)          ; Read the active string representation.
    CP   3                     ; Is this high-bit-terminated ISTR mode?
    LD   A,C                   ; Restore the byte without changing flags.
    JR   NZ,ST_SEREA           ; Other modes emit it unchanged.
    LD   HL,ST_SREM            ; Address the raw-byte countdown.
    LD   A,(HL)                ; Read the remaining raw-byte count.
    OR   A                     ; Is this the last decoded character?
    LD   A,C                   ; Restore the decoded byte while retaining Z.
    JR   NZ,ST_SEREA           ; Not last: leave bit 7 untouched.
    OR   $80                   ; Last: mark the ISTR terminator bit.
ST_SEREA:
    CALL OU_EMITB              ; Publish the decoded payload byte.
    JP   C,ST_OFAIL            ; Preserve any sink failure.
    JR   ST_SELOO              ; Continue until raw content is exhausted.
ST_SDONE:

; DB mode returns to its comma/EOL grammar. CSTR appends a zero terminator.
; PSTR and ISTR are already complete and advance directly to the next line.

    LD   A,(ST_SMODE)          ; Select completion behavior by string format.
    OR   A                     ; Is this an inline DB string?
    JR   Z,ST_SDDON            ; Yes: check the data-list delimiter.
    CP   1                     ; Is this zero-terminated CSTR mode?
    JP   NZ,ST_NEXT            ; PSTR and ISTR are already complete.
    XOR  A                     ; Form CSTR's trailing zero byte.
    CALL OU_EMITB              ; Publish the terminator reserved by preflight.
    JP   ST_OTNEX              ; Check output status and continue.
ST_SDDON:
    CALL TK_NEXT               ; Consume the DB string token.
    JP   C,ST_LFAIL            ; Preserve a following tokenizer failure.
    JP   ST_DDELI              ; Require comma or end-of-line next.
ST_CSTR1:

; String modes: 1 = zero-terminated, 2 = length-prefixed, 3 = high-bit final.

    LD   A,1                   ; Select zero-terminated CSTR representation.
    JR   ST_SDIR1              ; Share standalone string validation.
ST_PSTR1:
    LD   A,2                   ; Select length-prefixed PSTR representation.
    JR   ST_SDIR1              ; Share standalone string validation.
ST_ISTR1:
    LD   A,3                   ; Select high-bit-terminated ISTR.
ST_SDIR1:
    LD   (ST_SMODE),A          ; Retain the string mode for emission.

; Standalone string directives accept exactly one quoted-string token.

    LD   A,(TK_REC+TK_KOFF)    ; Inspect the directive's sole argument token.
    CP   TK_STRIN              ; Is it a validated quoted string?
    JP   NZ,ST_DSTR1           ; Reject expressions and other token classes.
    JP   ST_DSTRI              ; Count, preflight and emit it.
ST_DS1:

; DS count must be concrete. Without comma it reserves a gap; with
; a comma it emits count copies of the fill byte.

    CALL ST_PEXPR              ; Evaluate the number of bytes to allocate.
    JP   C,ST_DFAIL            ; Preserve nested expression failure detail.
    OR   A                     ; Test whether the count is unresolved.
    JP   NZ,ST_DUNR1           ; DS requires a count immediately.
    LD   (ST_DCNT),HL          ; Preserve the sixteen-bit allocation count.
    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token following the count.
    CP   TK_EOL                ; Is this the uninitialized reserve form?
    JR   Z,ST_DRESE            ; Yes: advance without emitting IMAGE bytes.
    CP   TK_COMMA              ; Otherwise require a fill-value separator.
    JP   NZ,ST_DDEL1           ; Reject any other trailing token.

; Parse the optional fill expression and require an immediate low-byte value.

    CALL TK_NEXT               ; Consume comma; expose the fill value.
    JP   C,ST_LFAIL            ; Preserve a lexical failure after the comma.
    CALL ST_PEXPR              ; Evaluate the repeated fill byte.
    JP   C,ST_DFAIL            ; Preserve nested expression failure detail.
    OR   A                     ; Is the fill expression unresolved?
    JP   NZ,ST_DUNR1           ; A forward fill cannot use one patch.
    LD   A,L                   ; Select the expression's low byte as the fill.
    LD   (ST_DFILL),A          ; Preserve it across capacity preflight.
    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token after the fill value.
    CP   TK_EOL                ; DS accepts no third argument.
    JP   NZ,ST_DDEL1           ; Reject any trailing token.

; Preflight the full range so the byte loop cannot fail for capacity
; after publishing only a prefix.

    LD   HL,(ST_DCNT)          ; Supply the complete filled-range length.
    CALL OU_CCAP               ; Prove all bytes fit before the first write.
    JP   C,ST_OFAIL            ; Preserve atomic capacity failure.
ST_DFLOO:

; Emit one fill byte per iteration. ST_DCNT reaches zero before returning
; to the outer statement loop.

    LD   HL,(ST_DCNT)          ; Read the remaining fill-byte count.
    LD   A,H                   ; Fold the high count byte into the zero test.
    OR   L                     ; Z means every requested byte was emitted.
    JP   Z,ST_NEXT             ; Finish the directive and begin the next line.
    LD   A,(ST_DFILL)          ; Recover the repeated fill byte.
    CALL OU_EMITB              ; Publish one byte from the preflighted range.
    JP   C,ST_OFAIL            ; Preserve an unexpected sink failure.
    LD   HL,(ST_DCNT)          ; Reload the remaining count after the call.
    DEC  HL                    ; Account for the byte just emitted.
    LD   (ST_DCNT),HL          ; Persist the decremented count.
    JR   ST_DFLOO              ; Emit the rest of the range.
ST_DRESE:

; The no-fill form advances the output cursor without creating IMAGE bytes.

    LD   HL,(ST_DCNT)          ; Supply the byte count to reserve.
    CALL OU_RESER              ; Advance the cursor without IMAGE emission.
    JP   ST_OTNEX              ; Check output status and continue.
ST_ALIG1:

; ALIGN needs a positive 16-bit boundary. A nonzero extension or zero
; in the low word, is outside the directive's domain.

    CALL ST_PEXPR              ; Evaluate the requested alignment boundary.
    JP   C,ST_DFAIL            ; Preserve nested expression failure detail.
    OR   A                     ; Is the boundary unresolved?
    JP   NZ,ST_DUNR1           ; ALIGN requires an immediate value.
    LD   A,(EX_RVAL+2)         ; Read the expression's extension byte.
    OR   A                     ; Does the extension mark a negative boundary?
    JP   NZ,ST_DRANG           ; Reject it outside the address domain.
    LD   A,H                   ; Begin testing the low word for zero.
    OR   L                     ; Z identifies the invalid boundary zero.
    JP   Z,ST_DRANG            ; Reject division by a zero alignment.
    LD   (ST_DVAL),HL          ; Preserve the validated boundary.
    LD   A,(TK_REC+TK_KOFF)    ; Inspect the token following the expression.
    CP   TK_EOL                ; ALIGN accepts exactly one argument.
    JP   NZ,ST_DDEL1           ; Reject any trailing token.

; Use the expression divider for cursor modulo alignment. Both operands
; are explicitly zero-extended to 24 bits before EX_REMAI is called.

    LD   HL,(OU_CURSO)         ; Load the current output address as dividend.
    LD   (EX_LVAL),HL          ; Store the dividend's low word.
    XOR  A                     ; Form the common zero extension byte.
    LD   (EX_LVAL+2),A         ; Zero-extend the current address to 24 bits.
    LD   HL,(ST_DVAL)          ; Restore the alignment as divisor.
    LD   (EX_RVAL),HL          ; Store the divisor's low word.
    LD   (EX_RVAL+2),A         ; Zero-extend the divisor to 24 bits.
    CALL EX_REMAI              ; Replace EX_RVAL with cursor modulo boundary.
    JP   C,ST_DFAIL            ; Preserve any defensive arithmetic failure.

; A zero remainder is already aligned. Otherwise emit alignment - remainder
; zero bytes through the same preflighted fill loop used by DS count,fill.

    LD   HL,(EX_RVAL)          ; Load the sixteen-bit remainder.
    LD   A,H                   ; Begin testing whether it is zero.
    OR   L                     ; Z means the cursor is aligned.
    JR   Z,ST_ACREA            ; Emit no padding in that case.
    EX   DE,HL                 ; Preserve the nonzero remainder in DE.
    LD   HL,(ST_DVAL)          ; Reload the alignment boundary.
    OR   A                     ; Clear carry before unsigned subtraction.
    SBC  HL,DE                 ; Compute bytes to next boundary.
ST_ACREA:
    LD   (ST_DCNT),HL          ; Reuse the DS loop's remaining-byte counter.
    XOR  A                     ; ALIGN padding bytes are always zero.
    LD   (ST_DFILL),A          ; Select zero as the repeated fill value.
    LD   HL,(ST_DCNT)          ; Supply the complete padding length.
    CALL OU_CCAP               ; Preflight all padding before emitting any.
    JP   C,ST_OFAIL            ; Preserve atomic output failure.
    JR   ST_DFLOO              ; Emit through the shared fill loop.
ST_SUCCE:

; EOF is a successful end of this source part, not the end of private scope or
; the complete build. The driver decides whether another part follows.

    XOR  A                     ; Return ST_SOK with carry clear.
    RET                        ; Return control to the multipart driver.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Directive names have at most five characters. Pack the lexeme into the
; shared RADIX-40 scratch buffer for exact, case-insensitive comparison.

EN_RDIR:
    LD   A,B                   ; Load the lexeme length for the bound check.
    CP   6                     ; Is it at most five characters?
    JR   NC,EN_RDNFO           ; Six or more characters cannot match.
    LD   DE,EN_SCRAT           ; Select the shared four-byte packing buffer.
    CALL EN_R40PK              ; Pack case-insensitively into RADIX-40 words.
    RET  C                     ; Propagate a character or length rejection.
    LD   IX,ST_DTABL           ; Point at the first packed directive entry.
    LD   B,ST_CNT              ; Search every fixed-size table entry.
    LD   C,ST_EQU              ; Track the one-based ordinal alongside IX.
EN_RDLOO:

; Compare four packed bytes. C tracks the one-based directive ordinal as
; IX advances through the fixed table.

    LD   A,(EN_SCRAT)          ; Load packed byte zero.
    CP   (IX+0)                ; Compare it with the candidate entry.
    JR   NZ,EN_RDNEX           ; Any mismatch rejects this candidate.
    LD   A,(EN_SCRAT+1)        ; Load packed byte one.
    CP   (IX+1)                ; Compare it with the candidate entry.
    JR   NZ,EN_RDNEX           ; Reject on mismatch.
    LD   A,(EN_SCRAT+2)        ; Load packed byte two.
    CP   (IX+2)                ; Compare it with the candidate entry.
    JR   NZ,EN_RDNEX           ; Reject on mismatch.
    LD   A,(EN_SCRAT+3)        ; Load packed byte three.
    CP   (IX+3)                ; Compare the final packed byte.
    JR   NZ,EN_RDNEX           ; Reject on mismatch.
    LD   A,C                   ; Return the matching directive ordinal.
    OR   A                     ; Clear carry while preserving that ordinal.
    RET                        ; Report successful exact recognition.
EN_RDNEX:
    LD   DE,4                  ; Each packed directive occupies four bytes.
    ADD  IX,DE                 ; Advance to the next table entry.
    INC  C                     ; Advance the corresponding ordinal.
    DJNZ EN_RDLOO              ; Continue until every entry has been compared.
EN_RDNFO:

; Recognition failure returns carry set; A is deliberately cleared because no
; ordinal is valid.

    XOR  A                     ; Return no meaningful ordinal.
    SCF                        ; Mark recognition failure.
    RET                        ; Return to the statement classifier.
ST_DTABL:

; Packed RADIX-40 forms of EQU, ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN.

    DW $21FD,$0000             ; EQU
    DW $6097,$0000             ; ORG
    DW $1950,$0000             ; DB
    DW $1C98,$0000             ; DW
    DW $1BF8,$0000             ; DS
    DW $15CC,$7080             ; CSTR
    DW $670C,$7080             ; PSTR
    DW $3B4C,$7080             ; ISTR
    DW $0829,$2DF0             ; ALIGN

;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Consume one raw byte. The source service receives the original part
; in A and offset in HL. Advance workspace only after
; the read, leaving A as the consumed character.

ST_STAKE:
    LD   HL,(ST_SPTR)          ; Load the next logical source-byte offset.
    LD   A,(ST_SPART)          ; Supply its source-part ordinal.
    CALL TK_SREAD              ; Fetch the byte through source service.
    LD   HL,(ST_SPTR)          ; Reload the cursor after callback clobbering.
    INC  HL                    ; Advance to the following raw byte.
    LD   (ST_SPTR),HL          ; Persist the new cursor.
    LD   HL,ST_SREM            ; Address the raw-byte countdown.
    DEC  (HL)                  ; Account for the byte just consumed.
    RET                        ; Return it in A to the decoder.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch a token and mirror its kind into A for compact statement dispatch.

ST_NTKIN:
    CALL TK_NEXT               ; Fetch the next token record.
    LD   A,(TK_REC+TK_KOFF)    ; Mirror its kind into the dispatch register.
    RET                        ; Return kind and tokenizer carry.

;@ROUTINE OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
; Expressions see the current output address in BC so '$' and relative forms
; have statement-accurate meaning.

ST_PEXPR:
    LD   BC,(OU_CURSO)         ; Supply '$' as the current output address.
    JP   EX_PDEFR              ; Parse without a new symbol reference.

;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the current token's part and start offset as the diagnostic
; location before a nested component advances the token stream.

ST_CPOSI:
    LD   A,(TK_REC+TK_POFF)    ; Read the current token's source-part ordinal.
    LD   (ST_EPART),A          ; Save it as the diagnostic part.
    LD   HL,(TK_REC+TK_SOFF)   ; Read the token's zero-based source offset.
    LD   (ST_EOFF),HL          ; Save it as the diagnostic byte position.
    RET                        ; Return with the stable anchor recorded.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Lexical failures use the tokenizer's exact position rather than the
; outer statement start captured by ST_CPOSI.

ST_LFAIL:
    LD   (ST_DETAI),A          ; Retain the tokenizer's detailed status.
    LD   A,(TK_EPART)          ; Load its exact failing source part.
    LD   (ST_EPART),A          ; Replace the outer statement anchor with it.
    LD   HL,(TK_EOFF)          ; Load its exact failing byte offset.
    LD   (ST_EOFF),HL          ; Preserve that offset for the driver.
    LD   A,ST_SLEXI            ; Return the public lexical-failure category.
    SCF                        ; Mark statement failure.
    RET                        ; Return directly to the multipart driver.

;@ROUTINE OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
; A token that cannot begin or continue a statement is normally an expression
; syntax failure. A bare '%' token has a separate directive category.

ST_EHERE:
    CALL ST_CPOSI              ; Anchor the error at this token.
    LD   A,(TK_REC+TK_KOFF)    ; Read its token kind as detailed status.
    CP   TK_DIR                ; Is it a bare percent directive marker?
    JR   NZ,ST_ESAVE           ; No: report a syntax error.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report a bare or unsupported percent directive at the current token.

ST_UDIR:
    LD   A,TK_DIR              ; Report the unsupported directive token.
    LD   C,ST_SDIR             ; Select the public directive-failure category.
    JR   ST_FAIL               ; Store detail and return failure.

;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Report the current unexpected token as a statement-expression failure.

ST_ESAVE:
    LD   A,(TK_REC+TK_KOFF)    ; Report the unexpected token kind.
    LD   C,ST_SEXP             ; Select the statement/expression category.
    JR   ST_FAIL               ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a symbol-layer status as a statement failure.

ST_SFAIL:
    LD   C,ST_SSYM             ; Wrap A as a symbol-subsystem failure.
    JR   ST_FAIL               ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an instruction-parser status as a statement failure.

ST_IFAIL:
    LD   C,ST_SINS             ; Wrap A as an instruction/parser failure.
    JR   ST_FAIL               ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an output-layer status as a statement failure.

ST_OFAIL:
    LD   C,ST_SOUT             ; Wrap A as an output-subsystem failure.
    JR   ST_FAIL               ; Store detail and return failure.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap an EQU-expression status as an EQU statement failure.

ST_EFAIL:
    LD   C,ST_SEQUA            ; Wrap A as an EQU-specific failure.
    JR   ST_FAIL               ; Store detail and return failure.
ST_EUNRE:
    LD   A,EX_UNRES            ; Detail: EQU value remained unresolved.
    JR   ST_EFAIL              ; Return it through the EQU wrapper.
ST_EDELI:
    LD   A,EX_SEPRI            ; Detail: trailing token after EQU expression.
    JR   ST_EFAIL              ; Return it through the EQU wrapper.

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
; Wrap a directive-argument status as a directive statement failure.

ST_DFAIL:
    LD   C,ST_SDIR             ; Wrap A as a directive-argument failure.

;@ROUTINE IN A,C OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
; Failure adapters store component status from A, replace
; A with their outer statement category from C and set carry for the driver.

ST_FAIL:
    LD   (ST_DETAI),A          ; Preserve the nested subsystem status.
    LD   A,C                   ; Return the statement category.
    SCF                        ; Mark the statement as failed.
    RET                        ; Return to the multipart driver.
ST_DUNR1:
    LD   A,EX_UNRES            ; Detail: unresolved directive value.
    JR   ST_DFAIL              ; Return through the directive wrapper.
ST_DRANG:
    LD   A,EX_SRANG            ; Detail: directive value out of range.
    JR   ST_DFAIL              ; Return through the directive wrapper.
ST_DEXP:
    LD   A,EX_SEPRI            ; Detail: a required expression was absent.
    JR   ST_DFAIL              ; Return through the directive wrapper.
ST_DDEL1:
    LD   A,(TK_REC+TK_KOFF)    ; Detail: unexpected trailing token kind.
    JR   ST_DFAIL              ; Return through the directive wrapper.
ST_DSTR1:
    LD   A,TK_STRIN            ; Detail: quoted-string form was invalid here.
    JR   ST_DFAIL              ; Return through the directive wrapper.
ST_CEND:
ST_WBEG:

; Twenty bytes shared by mutually exclusive statement phases.

ST_WUNIO: DS 20            ; Union storage shared by all statement phases.

; Packed label/EQU name or instruction record at the same base.

ST_KEY EQU ST_WUNIO        ; Six-byte packed leading symbol key.
ST_INS EQU ST_WUNIO        ; Parsed instruction record at the same base.

; Cached mnemonic/directive ordinals and their explicit validity flags.

ST_MNEM EQU ST_WUNIO+6     ; Cached mnemonic ordinal.
ST_MVALI EQU ST_WUNIO+7    ; Mnemonic cache-valid Boolean.
ST_DIR EQU ST_WUNIO+8      ; Cached directive ordinal.
ST_DVALI EQU ST_WUNIO+9    ; Directive cache-valid Boolean.

; Nested subsystem status retained for the driver and public diagnostics.

ST_DETAI EQU ST_WUNIO+10   ; Nested subsystem status for diagnostics.

; EQU result and its negative/sign-extension flag.

ST_EVAL EQU ST_WUNIO+6     ; EQU low sixteen-bit value.
ST_ESIGN EQU ST_WUNIO+8    ; EQU sign-extension marker.

; Data-list element width, default patch kind, unresolved addend and DS fill.

ST_DWIDT EQU ST_WUNIO      ; Active DB/DW scalar width.
ST_DPKIN EQU ST_WUNIO+1    ; Default unresolved patch kind.
ST_DADDE EQU ST_WUNIO+2    ; Saved unresolved signed addend.
ST_DFILL EQU ST_WUNIO+3    ; DS/ALIGN repeated fill byte.

; General directive value; while queuing a patch, the chosen patch kind.

ST_DVAL EQU ST_WUNIO+4     ; General directive word value.
ST_DPKI1 EQU ST_DVAL       ; Selected patch kind overlaid on that word.

; DS/ALIGN byte count, followed by unresolved-expression state.

ST_DCNT EQU ST_WUNIO+6     ; DS/ALIGN remaining byte count.
ST_DKEY EQU ST_WUNIO+8     ; Saved unresolved packed-key pointer.
ST_DSYM EQU ST_WUNIO+10    ; Saved unresolved symbol-record pointer.
ST_DADR EQU ST_WUNIO+12    ; Saved placeholder target address.

; Raw quoted-string cursor, remaining raw bytes and decoded-byte count.

ST_SPTR EQU ST_WUNIO+14    ; String raw-source cursor.
ST_SREM EQU ST_WUNIO+16    ; String raw bytes remaining.
ST_SCNT EQU ST_WUNIO+17    ; String decoded-byte count.

; Saved high hexadecimal nibble and string mode selector.

ST_SNIBB EQU ST_WUNIO+18   ; Saved high nibble for \xHH decoding.
ST_SMODE EQU ST_WUNIO+19   ; DB/CSTR/PSTR/ISTR mode selector.

; Stable statement diagnostic position.

ST_EPART: DB 0             ; Stable diagnostic source-part ordinal.
ST_EOFF: DW 0              ; Stable zero-based source-byte offset.

; Source part retained while a quoted string is decoded through TK_SREAD.

ST_SPART: DB 0             ; Source part used by raw string reads.
ST_WEND:
