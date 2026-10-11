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
; the nested status. ST_EPART/ST_EOFF hold the source location.
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
;  .UNION is a 20-byte union. Statement forms execute serially, so mnemonic,
;  EQU, data and string temporaries deliberately overlap. The final four bytes
;  outside the union retain error position and string source-part identity.
;  This shared state makes the module non-reentrant.

ST_CBEG: ; Begin statement code and directive constants.

; Public statement categories returned to the multipart driver.

ST_SOK      EQU     0                   ; Completed the source part successfully.
ST_SLEX     EQU     1                   ; Tokenizer rejected the source text.
ST_SEXP     EQU     2                   ; Statement grammar or expression failed.
ST_SDIR     EQU     3                   ; Directive arguments were invalid.
ST_SEQU     EQU     4                   ; EQU expression or trailing-token check failed.
ST_SSYM     EQU     5                   ; Symbol declaration or reference failed.
ST_SINS     EQU     6                   ; Instruction parsing or validation failed.
ST_SOUT     EQU     7                   ; Output emission or patching failed.
ST_SUDEF    EQU     8                   ; Finalization found an undefined symbol.
ST_SINT     EQU     9                   ; An internal invariant was violated.

; Statement failures that need no nested status set bit 7 of ST_DETAI and
; carry their message number from src/host/diagnostics.mjs in bits 0..6.

ST_XSTRT    EQU     $84                 ; Expected a label, instruction or directive.
ST_XNAME    EQU     $85                 ; Unknown instruction or directive.
ST_XTAIL    EQU     $86                 ; Unexpected text after the operands.
ST_XDWST    EQU     $87                 ; Strings are only allowed in DB.
ST_XNSTR    EQU     $88                 ; Expected a quoted string.
ST_XPCT     EQU     $89                 ; A % directive is not allowed here.

; Directive ordinals returned by EN_ISDIR and used by the dispatch table.

ST_EQU      EQU     1                   ; Declare an immediate constant.
ST_ORG      EQU     2                   ; Move the output cursor.
ST_DB       EQU     3                   ; Emit byte expressions or strings.
ST_DW       EQU     4                   ; Emit little-endian word expressions.
ST_DS       EQU     5                   ; Reserve or fill a byte range.
ST_CSTR     EQU     6                   ; Emit a zero-terminated string.
ST_PSTR     EQU     7                   ; Emit a length-prefixed string.
ST_ISTR     EQU     8                   ; Emit a string with bit 7 on its final byte.
ST_ALIGN    EQU     9                   ; Advance to the next address boundary.
ST_CNT      EQU     9                   ; Number of recognised directive names.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Assemble the current source part through its EOF token.

DR_APART: ; Driver alias for assembly of the current source part.
ST_NEXT: ; Fetch and assemble statements until source-part EOF.

; Fetch the first token. EOF finishes only this source part. An EOL
; is an empty statement and simply restarts the loop.

    CALL ST_TOKEN                       ; Fetch the first token kind into A.
    JP   C,ST_LFAIL                     ; Preserve an exact tokenizer failure location.
    CP   TK_EOF                         ; Has this source part ended?
    JP   Z,ST_DONE                      ; Yes: return success to the multipart driver.
    CP   TK_EOL                         ; Is this an empty source line?
    JR   Z,ST_NEXT                      ; Yes: ignore it and fetch the next statement.
    CP   TK_NAME                        ; Does this statement start with a name?
    JP   NZ,ST_STRAY                    ; Report the unexpected starting token.

; Preserve the statement's starting position before any nested parser advances
; the tokenizer. All later failures on this line report this stable location.

    CALL ST_MARK                        ; Anchor later diagnostics at the leading name.

; Pack the leading name once as a possible label or EQU destination.

    CALL TK_TEXT                        ; Return the name text as HL plus byte count B.
    LD   DE,ST_KEY                      ; Select the six-byte packed-name destination.
    CALL EN_PSYM                        ; Pack and validate the possible symbol name.
    JP   C,ST_SFAIL                     ; Translate packing failure to symbol status.

; Classify the same lexeme as a mnemonic. ST_MOK marks ST_MNEM as valid.
; ordinal zero is not a validity sentinel.

    CALL TK_TEXT                        ; Reload the still-current leading lexeme.
    CALL EN_RECOG                       ; Look for an exact mnemonic match.
    JR   C,.NOMNEM                      ; No mnemonic: try the directive table.
    LD   (ST_MNEM),A                    ; Cache the recognised mnemonic ordinal.
    LD   A,1                            ; Form an explicit Boolean validity marker.
    LD   (ST_MOK),A                     ; Mark the cached mnemonic as usable.
    XOR  A                              ; Clear the alternative classification.
    LD   (ST_DOK),A                     ; Clear the directive-valid marker.
    JR   .PASTNAME                      ; Inspect the token following the leading name.
.NOMNEM: ; Classify the leading name as a directive after mnemonic failure.

; If it was not a mnemonic, test the compact directive table and cache that
; result in the parallel ST_DIR/ST_DOK pair.

    XOR  A                              ; Record that mnemonic recognition failed.
    LD   (ST_MOK),A                     ; Prevent stale mnemonic data being consumed.
    CALL TK_TEXT                        ; Reload the lexeme for directive lookup.
    CALL EN_ISDIR                       ; Search the compact directive-name table.
    JR   C,.NODIR                       ; Leave both validity flags clear if absent.
    LD   (ST_DIR),A                     ; Cache the directive ordinal.
    LD   A,1                            ; Form the directive-valid Boolean.
    LD   (ST_DOK),A                     ; Mark the cached directive as usable.
    JR   .PASTNAME                      ; Inspect the token following the leading name.
.NODIR: ; Clear directive validity when both operation probes fail.
    XOR  A                              ; Neither mnemonic nor directive matched.
    LD   (ST_DOK),A                     ; Clear the remaining validity flag.
.PASTNAME: ; Use the following token to distinguish declaration from operation.

; The token after the leading name determines whether the packed name is a
; declaration target or whether the name itself selects the statement kind.

    CALL ST_TOKEN                       ; Advance beyond the leading name.
    JP   C,ST_LFAIL                     ; Propagate a lexical failure at that token.
    CP   TK_COLON                       ; Does the name introduce a label declaration?
    JR   Z,.LABEL                       ; Yes: declare it before processing any tail.

; A recognised mnemonic without a colon begins an instruction immediately.

    LD   A,(ST_MOK)                     ; Test the cached mnemonic classification.
    OR   A                              ; Set Z when no mnemonic matched.
    JP   NZ,.INSTR                      ; Matched: parse its operands.

; A recognised non-EQU directive without a colon goes to directive dispatch.

    LD   A,(ST_DOK)                     ; Test the cached directive classification.
    OR   A                              ; Set Z when no directive matched either.
    JR   Z,.TRYEQU                      ; Try the NAME EQU expression declaration form.
    LD   A,(ST_DIR)                     ; Restore the cached directive ordinal.
    JP   ST_DODIR                       ; Dispatch its operand grammar.
.TRYEQU: ; Test a colonless constant declaration for the EQU directive.

; An unrecognised leading name may still be the destination of colonless EQU.
; The current token must itself be the recognised EQU directive.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token after the constant name.
    CP   TK_NAME                        ; Only another name can be the EQU directive.
    JP   NZ,ST_UNOP                     ; A bare name must be an operation or EQU.
    CALL TK_TEXT                        ; Expose the second name's characters.
    CALL EN_ISDIR                       ; Classify it through the directive table.
    JP   C,ST_UNOP                      ; An unknown name is invalid in this position.
    CP   ST_EQU                         ; Did the recognised directive equal EQU?
    JP   NZ,ST_UNOP                     ; No other directive may follow a bare name.
    JP   ST_DOEQU                       ; Parse and declare the constant.
.LABEL: ; Inspect the token after a label's colon before declaration.

; After a colon, recognise the special convenience form "label: EQU value".
; Any other token leaves the declaration as an address label.

    CALL ST_TOKEN                       ; Consume colon and fetch the next token.
    JP   C,ST_LFAIL                     ; Preserve any tokenizer error.
    CP   TK_NAME                        ; A name here might be the EQU directive.
    JR   NZ,.DECLARE                    ; Anything else leaves an address label.
    CALL TK_TEXT                        ; Expose the possible directive text.
    CALL EN_ISDIR                       ; Attempt directive recognition.
    JR   C,.DECLARE                     ; No directive: declare an address label.
    CP   ST_EQU                         ; Is this specifically EQU?
    JR   Z,ST_DOEQU                     ; EQU: declare a constant.
.DECLARE: ; Bind an address label in global or current private scope.

; The packed key's private bit selects the declaration rule. A global address
; label closes the previous private scope. A private label remains within it.

    LD   HL,ST_KEY+5                    ; Address the packed symbol's flag byte.
    BIT  7,(HL)                         ; Test the private-name marker.
    LD   HL,ST_KEY                      ; Supply the packed symbol key.
    LD   DE,(OU_ADDR)                   ; Bind the label to the current output address.
    JR   NZ,.PRIVATE                    ; Private names use the current global scope.
    CALL SY_LABEL                       ; Declare a global and open its private scope.
    JR   .DECLARED                      ; Share declaration and resolution checks.
.PRIVATE: ; Declare the label within the active private scope.
    CALL SY_DECL                        ; Declare in the active private scope.
.DECLARED: ; Check declaration success before resolving its references.
    JP   C,ST_SFAIL                     ; Report a symbol declaration failure.

; A newly known address may satisfy several forward references. Resolution is
; transactional with the sink and leaves diagnostics intact on failure.

    CALL OU_RSLV                        ; Emit and retire this symbol's patches.
    JP   C,ST_OFAIL                     ; Preserve transactional output failure.

; A bare label ends at EOL. Otherwise the same line may continue with exactly
; one instruction or directive name.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token after the label.
    CP   TK_EOL                         ; Is the label the complete statement?
    JP   Z,ST_NEXT                      ; Yes: begin the next line.
    CP   TK_NAME                        ; A statement tail must start with a name.
    JP   NZ,ST_STRAY                    ; Reject a non-name statement tail.
    CALL ST_MARK                        ; Anchor errors at the operation name.
    CALL TK_TEXT                        ; Expose that name for mnemonic lookup.
    CALL EN_RECOG                       ; Try to recognise an instruction.
    JR   C,.TAILDIR                     ; If absent, try the directive table instead.

; Cache the mnemonic, consume its name and share the ordinary
; instruction path used by statements without a label.

    LD   (ST_MNEM),A                    ; Cache the post-label mnemonic ordinal.
    CALL TK_NEXT                        ; Consume the name. Expose its first operand.
    JP   C,ST_LFAIL                     ; Retain a lexical error in its operands.
    JR   .INSTR                         ; Join ordinary instruction parsing.
.TAILDIR: ; Recognise a directive following a label on the same line.

; The post-label name was not a mnemonic. It must be a recognised directive.

    CALL TK_TEXT                        ; Reload the name for directive lookup.
    CALL EN_ISDIR                       ; Look for an exact directive match.
    JP   C,ST_UNOP                      ; Unknown operation names are statement errors.
    LD   (ST_DIR),A                     ; Save the directive across token advancement.
    CALL TK_NEXT                        ; Consume the directive name.
    JP   C,ST_LFAIL                     ; Preserve a lexical failure in its arguments.
    LD   A,(ST_DIR)                     ; Restore the directive ordinal for dispatch.
    JR   ST_DODIR                       ; Enter the common directive dispatcher.
.INSTR: ; Parse and emit the recognised mnemonic's operands.

; Parse and validate operands into ST_INS. Use the output cursor as the
; instruction address. Relative expressions depend on that address.

    LD   A,(ST_MNEM)                    ; Supply the recognised mnemonic ordinal.
    LD   BC,(OU_ADDR)                   ; Supply the instruction's output address.
    LD   DE,ST_INS                      ; Select the union's parsed-instruction record.
    CALL PR_PUB                         ; Parse and validate the instruction form.
    JP   C,ST_IFAIL                     ; Wrap a parser error as instruction failure.

; Emit one to four instruction bytes, then fetch the next line.

    CALL OU_EMITI                       ; Encode and publish the validated instruction.
ST_OUTOK: ; Check output status before fetching the next statement.
    JP   C,ST_OFAIL                     ; Convert any output error to statement status.
    JP   ST_NEXT                        ; Continue with the next source statement.
ST_DOEQU: ; Evaluate and declare an immediate EQU constant.

; Consume EQU and evaluate its expression at the current output address.

    CALL TK_NEXT                        ; Consume EQU. Expose its expression.
    JP   C,ST_LFAIL                     ; Preserve a lexical failure before evaluation.
    CALL ST_PEXPR                       ; Evaluate at the current output address.
    JP   C,ST_EFAIL                     ; Wrap an expression error as EQU failure.

; EQU must be known now. A forward EQU would require delayed expression
; evaluation rather than the byte patches used for address references.

    OR   A                              ; A is nonzero when the result is unresolved.
    JP   NZ,ST_EUNRE                    ; EQU requires a value immediately.

; Save the low word. Derive its sign from the expression's high
; extension byte: zero is unsigned/non-negative, nonzero is negative.

    LD   (ST_EVAL),HL                   ; Save the result's low sixteen bits.
    XOR  A                              ; Start with a non-negative sign flag.
    LD   HL,EX_RVAL+2                   ; Address the expression's extension byte.
    CP   (HL)                           ; Is the extension zero?
    JR   Z,.SIGNSET                     ; Yes: retain the clear sign flag.
    INC  A                              ; No: mark the constant as sign-extended.
.SIGNSET: ; Retain the EQU result's sign-extension flag.
    LD   (ST_ESIGN),A                   ; Preserve signedness across delimiter checks.

; No token may follow the EQU expression on the statement.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token left by expression parsing.
    CP   TK_EOL                         ; Did the expression end at EOL?
    JP   NZ,ST_ETAIL                    ; Report any trailing delimiter or token.

; EQU declares in the current scope without opening a new global scope.

    LD   HL,ST_KEY                      ; Supply the packed constant name.
    LD   DE,(ST_EVAL)                   ; Supply its immediate sixteen-bit value.
    CALL SY_DECL                        ; Declare it without changing global scope.
    JP   C,ST_SFAIL                     ; Preserve a symbol declaration failure.

; Mark negative constants in the packed symbol record
; before resolving any waiting references to its newly concrete value.

    LD   A,(ST_ESIGN)                   ; Recover the saved sign-extension flag.
    OR   A                              ; Set Z for a non-negative constant.
    JR   Z,.RESOLVE                     ; Leave its symbol flags unchanged.
    SET  5,(IX+5)                       ; Mark it negative for later expressions.
.RESOLVE: ; Resolve pending uses after the constant becomes defined.
    CALL OU_RSLV                        ; Resolve pending uses of the new constant.
    JR   ST_OUTOK                       ; Check output status and continue.
ST_DODIR: ; Dispatch the contiguous ORG through ALIGN ordinals.

; EQU is handled by the declaration grammar above. Subtracting ST_ORG maps the
; remaining contiguous ordinals onto the eight-entry address table.

    SUB  ST_ORG                         ; Index ORG..ALIGN from zero.
    CP   8                              ; Is this one of eight table entries?
    JP   NC,ST_UNEXP                    ; Reject EQU or a corrupt/out-of-range ordinal.
    ADD  A,A                            ; Scale the index for a two-byte address entry.
    LD   L,A                            ; Place the scaled offset in HL.
    LD   H,0                            ; Zero-extend it to sixteen bits.
    LD   DE,.HANDLERS                   ; Point DE at the directive address table.
    ADD  HL,DE                          ; Address the selected little-endian entry.
    LD   E,(HL)                         ; Load the handler address low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the handler address in DE.
    EX   DE,HL                          ; Put the handler address in HL.
    JP   (HL)                           ; Dispatch without another comparison chain.
.HANDLERS: ; Little-endian handler addresses in directive ordinal order.

; ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN handlers in ordinal order.

    DW   .DOORG,.DODB,.DODW,ST_DODS     ; Numeric and storage directives.
    DW   ST_CMODE,ST_PMODE,ST_IMODE     ; Three standalone string formats.
    DW   ST_PAD                         ; Address-alignment directive.
.DOORG: ; Require a concrete origin and move the logical cursor.

; ORG requires one concrete expression and no trailing token. It changes the
; logical output cursor. The platform adapter owns extent and append policy.

    CALL ST_PEXPR                       ; Evaluate the absolute output address.
    JP   C,ST_DFAIL                     ; Preserve expression syntax or range detail.
    OR   A                              ; Test the unresolved-result flag.
    JP   NZ,ST_DUNRE                    ; ORG cannot wait for a forward definition.
    LD   (ST_DVAL),HL                   ; Save the address across delimiter validation.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token following the expression.
    CP   TK_EOL                         ; ORG accepts exactly one expression.
    JP   NZ,ST_DTAIL                    ; Report the unexpected trailing token.
    LD   HL,(ST_DVAL)                   ; Restore the requested origin.
    CALL OU_ORG                         ; Set the logical output cursor.
    JP   ST_OUTOK                       ; Check output status and continue.
.DODB: ; Select scalar byte width and truncating forward patches.

; Width and default patch kind distinguish DB from DW. Both
; then share the comma-separated item loop.

    LD   A,1                            ; Select one emitted byte per scalar item.
    LD   (ST_WIDTH),A                   ; Retain DB width for the shared list loop.
    LD   A,PT_KTB                       ; Select the ordinary byte patch kind.
    LD   (ST_DKIND),A                   ; Retain it for an unresolved expression.
    JR   ST_DITEM                       ; Enter the common data-item parser.
.DODW: ; Select scalar word width and full-word forward patches.
    LD   A,2                            ; Select two emitted bytes per scalar item.
    LD   (ST_WIDTH),A                   ; Retain DW width for the shared list loop.
    LD   A,PT_KINDW                     ; Select the ordinary word patch kind.
    LD   (ST_DKIND),A                   ; Retain it for an unresolved expression.
ST_DITEM: ; Parse the next scalar or quoted-string data item.

; A data list cannot be empty or end immediately after a comma.

    LD   A,(TK_REC+TK_RKIND)            ; Read the current prospective item token.
    CP   TK_EOL                         ; Did the list end before an item appeared?
    JP   Z,ST_DMISS                     ; Report the missing expression.

; Quoted strings are accepted only in DB. They use mode zero so the common
; string emitter returns to the data-list delimiter path, not the end of
; the whole statement.

    CP   TK_STR                         ; Is this item a quoted string?
    JR   NZ,.SCALAR                     ; No: parse it as a scalar expression.
    LD   A,(ST_WIDTH)                   ; Recover the active data width.
    CP   1                              ; Are we assembling DB rather than DW?
    JP   NZ,ST_DWSTR                    ; Reject strings in a word list.
    XOR  A                              ; Mode zero denotes an inline DB string.
    LD   (ST_SMODE),A                   ; Select list-aware completion behaviour.
    JP   ST_PUTS                        ; Count, preflight and emit the decoded string.
.SCALAR: ; Evaluate a scalar item or retain its unresolved symbol.

; A concrete expression emits its low byte or low word immediately.

    CALL ST_PEXPR                       ; Evaluate the scalar data item.
    JP   C,ST_DFAIL                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the expression waiting on a symbol?
    JR   NZ,.PENDING                    ; Yes: reserve bytes and queue a patch.
    LD   A,(ST_WIDTH)                   ; Recover the active DB/DW width.
    CP   1                              ; Does this item emit one byte?
    JR   Z,.ONEBYTE                     ; Yes: publish only L.
    CALL OU_EMITW                       ; Publish HL in little-endian order.
    JR   .EMITTED                       ; Share output checking and delimiter parsing.
.ONEBYTE: ; Emit the low byte of a resolved DB expression.
    LD   A,L                            ; Select the expression's low byte.
    CALL OU_EMITB                       ; Publish the byte through the output sink.
.EMITTED: ; Check scalar output before handling its list delimiter.
    JP   C,ST_OFAIL                     ; Preserve output capacity or sink failure.
    JP   ST_DMORE                       ; Require comma or end-of-line next.
.PENDING: ; Preflight storage and queue an unresolved data-item patch.

; A simple unresolved symbol may be represented by a pending patch. Save
; the addend and symbol pointer before a capacity or emission call can
; reuse IX, HL or the shared expression workspace.

    LD   A,L                            ; Capture the signed expression addend.
    LD   (ST_DELTA),A                   ; Preserve it for the pending record.
    PUSH IX                             ; Save the expression symbol pointer.
    POP  HL                             ; Receive that pointer in HL.
    LD   (ST_DKEY),HL                   ; Preserve it across capacity checks.
    LD   A,(ST_WIDTH)                   ; Recover the placeholder byte count.
    LD   L,A                            ; Put that count in low word byte.
    LD   H,0                            ; Zero-extend it for output preflight.

; Prove both output and pending-record capacity before publishing a zero
; placeholder. On failure, stream and symbol state remain unchanged.

    CALL OU_CAPOK                       ; Prove the placeholder fits the output range.
    JP   C,ST_OFAIL                     ; Fail before any visible write on exhaustion.
    CALL SY_CCAP                        ; Prove one pending record fits its arena.
    JP   C,ST_SFAIL                     ; Fail before emission if it does not.
    LD   A,(EX_RFORM)                   ; Read the unresolved projection form.
    CP   EX_FLO                         ; Was LOW(...) requested?
    JR   Z,.LOWBYTE                     ; Yes: use a low-byte patch.
    CP   EX_FHI                         ; Was HIGH(...) requested?
    JR   Z,.HIGHBYTE                    ; Yes: use a high-byte patch.

; Plain unresolved DB/DW uses the directive's width-specific patch kind. LOW
; and HIGH expression forms override that with the corresponding byte patch.

    LD   A,(ST_DKIND)                   ; Use the DB/DW default patch kind.
    JR   .KINDSET                       ; Store the selected kind.
.LOWBYTE: ; Select LOW extraction for the future resolved value.
    LD   A,PT_KLB                       ; Select low-byte extraction at resolution.
    JR   .KINDSET                       ; Store the selected kind.
.HIGHBYTE: ; Select HIGH extraction for the future resolved value.
    LD   A,PT_KHB                       ; Select high-byte extraction at resolution.
.KINDSET: ; Retain the selected patch transform across symbol lookup.
    LD   (ST_PKIND),A                   ; Preserve the kind across symbol lookup.

; Find or create the undefined symbol record. B reports whether this is the
; first reference, which is the one that must retain the diagnostic anchor.

    LD   HL,(ST_DKEY)                   ; Restore the packed unresolved symbol pointer.
    CALL SY_REF                         ; Find or create its undefined symbol record.
    JP   C,ST_SFAIL                     ; Preserve symbol arena or scope failure.
    LD   A,B                            ; B is nonzero only for the first reference.
    OR   A                              ; Set Z for a previously referenced symbol.
    JR   Z,.ANCHORED                    ; Reuse its existing diagnostic anchor.

; Store the first reference offset in the undefined symbol's value word
; and mark this pending record as its diagnostic anchor.

    LD   HL,(EX_SOFF)                   ; Recover the expression's source-byte offset.
    LD   (IX+SY_VALLO),L                ; Store its low byte in the undefined record.
    LD   (IX+SY_VALHI),H                ; Store its high byte to complete the anchor.
    LD   A,SY_DANCH                     ; Select the diagnostic-anchor flag.
    LD   HL,ST_PKIND                    ; Address the pending patch kind.
    OR   (HL)                           ; Add the anchor flag to the patch kind.
    LD   (HL),A                         ; Retain the combined pending metadata.
.ANCHORED: ; Preserve the symbol pointer and placeholder address for emission.

; Preserve the symbol and patch address while the placeholder is emitted.

    PUSH IX                             ; Copy the symbol-record pointer from IX.
    POP  HL                             ; Receive the pointer in HL for storage.
    LD   (ST_DSYM),HL                   ; Preserve it across placeholder emission.
    LD   HL,(OU_ADDR)                   ; Capture the placeholder's target address.
    LD   (ST_DADDR),HL                  ; Retain that address for the pending record.
    LD   A,(ST_WIDTH)                   ; Recover the placeholder width.
    CP   1                              ; Is this an unresolved DB item?
    JR   Z,.ZEROBYTE                    ; Yes: emit one zero byte.

; Emit a zero-filled placeholder. A later PATCH carries the final value.

    LD   HL,0                           ; Form a two-byte zero placeholder.
    CALL OU_EMITW                       ; Emit the preflighted two-byte placeholder.
    JP   C,ST_OFAIL                     ; Preserve any unexpected sink failure.
    JR   .ENQUEUE                       ; Append its pending patch record.
.ZEROBYTE: ; Emit the single zero placeholder used by unresolved DB.
    XOR  A                              ; Form a one-byte zero placeholder.
    CALL OU_EMITB                       ; Publish the reserved byte.
    JP   C,ST_OFAIL                     ; Preserve any unexpected sink failure.
.ENQUEUE: ; Append the pending record after placeholder acceptance.

; Append the pending record only after the placeholder emission succeeds. It
; captures symbol, target address, kind, addend and source position.

    LD   IX,(ST_DSYM)                   ; Restore the referenced symbol record.
    LD   DE,(ST_DADDR)                  ; Supply the placeholder target address.
    LD   A,(ST_PKIND)                   ; Recover the kind and possible anchor flag.
    LD   B,A                            ; Place pending metadata in its ABI register.
    LD   A,(ST_DELTA)                   ; Recover the signed expression addend.
    LD   C,A                            ; Place the addend in its ABI register.
    LD   HL,(EX_SOFF)                   ; Supply the reference's source offset.
    LD   (SY_ROFF),HL                   ; SY_ADD stores it with the record.
    LD   A,(EX_SPART)                   ; Supply the reference's source-part ordinal.
    CALL SY_ADD                         ; Append the fully described pending record.
    JP   C,ST_SFAIL                     ; Preserve capacity or invariant failure.
ST_DMORE: ; Require a comma or EOL after a data-list item.

; Accept EOL or comma followed by another item. A trailing comma reports
; a missing expression.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token following the emitted item.
    CP   TK_EOL                         ; Has the data list ended?
    JP   Z,ST_NEXT                      ; Yes: begin the next statement.
    CP   TK_COMMA                       ; Otherwise require an item separator.
    JP   NZ,ST_DTAIL                    ; Report the unexpected delimiter.
    CALL ST_TOKEN                       ; Consume the comma and fetch the next item.
    JP   C,ST_LFAIL                     ; Preserve a tokenizer failure after the comma.
    CP   TK_EOL                         ; Did the list end immediately after it?
    JP   Z,ST_DMISS                     ; Diagnose the missing item.
    JP   ST_DITEM                       ; Parse the next scalar or string item.
