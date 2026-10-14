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
; drDoPart / stNext assembles the current source part.
; tkReset must first select its part and range. At EOF, carry is clear and
; A = 0. On error, carry is set and A holds a statement status category.
; stDetail holds the nested status. stAtPart/stAtOff hold the source location.
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
;  Label declarations immediately call outFixUp. This emits patches for waiting
;  references. It removes pending records only after the sink accepts the
;  patch. EQU uses the same resolution path once its expression is concrete.
;
;  WORKSPACE AND REENTRANCY
;  ------------------------
;
;  .union is a 20-byte union. Statement forms execute serially, so mnemonic,
;  EQU, data and string temporaries deliberately overlap. The final four bytes
;  outside the union retain error position and string source-part identity.
;  This shared state makes the module non-reentrant.

stBeg: ; Begin statement code and directive constants.

; Public statement categories returned to the multipart driver.

stOk        EQU     0                   ; Completed the source part successfully.
stBadLex    EQU     1                   ; Tokenizer rejected the source text.
stSyntax    EQU     2                   ; Statement grammar or expression failed.
stBadDir    EQU     3                   ; Directive arguments were invalid.
stBadEqu    EQU     4                   ; EQU expression or trailing-token check failed.
stBadSym    EQU     5                   ; Symbol declaration or reference failed.
stBadIns    EQU     6                   ; Instruction parsing or validation failed.
stBadOut    EQU     7                   ; Output emission or patching failed.
stUndef     EQU     8                   ; Finalization found an undefined symbol.
stIntErr    EQU     9                   ; An internal invariant was violated.

; Statement failures that need no nested status set bit 7 of stDetail and
; carry their message number from src/host/diagnostics.mjs in bits 0..6.

stNoStmt    EQU     $84                 ; Expected a label, instruction or directive.
stUnkOp     EQU     $85                 ; Unknown instruction or directive.
stJunk      EQU     $86                 ; Unexpected text after the operands.
stDbOnly    EQU     $87                 ; Strings are only allowed in DB.
stNoStr     EQU     $88                 ; Expected a quoted string.
stNoHost    EQU     $89                 ; A % directive is not allowed here.

; Directive ordinals returned by stIsDir and used by the dispatch table.

stEqu       EQU     1                   ; Declare an immediate constant.
stOrg       EQU     2                   ; Move the output cursor.
stDb        EQU     3                   ; Emit byte expressions or strings.
stDw        EQU     4                   ; Emit little-endian word expressions.
stDs        EQU     5                   ; Reserve or fill a byte range.
stCstr      EQU     6                   ; Emit a zero-terminated string.
stPstr      EQU     7                   ; Emit a length-prefixed string.
stIstr      EQU     8                   ; Emit a string with bit 7 on its final byte.
stAlign     EQU     9                   ; Advance to the next address boundary.
stNumDir    EQU     9                   ; Number of recognised directive names.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Assemble the current source part through its EOF token.

drDoPart: ; Driver alias for assembly of the current source part.
stNext: ; Fetch and assemble statements until source-part EOF.

; Fetch the first token. EOF finishes only this source part. An EOL
; is an empty statement and simply restarts the loop.

    CALL stToken                        ; Fetch the first token kind into A.
    JP   C,stLexErr                     ; Preserve an exact tokenizer failure location.
    CP   tkEof                          ; Has this source part ended?
    JP   Z,stDone                       ; Yes: return success to the multipart driver.
    CP   tkEol                          ; Is this an empty source line?
    JR   Z,stNext                       ; Yes: ignore it and fetch the next statement.
    CP   tkName                         ; Does this statement start with a name?
    JP   NZ,stStray                     ; Report the unexpected starting token.

; Preserve the statement's starting position before any nested parser advances
; the tokenizer. All later failures on this line report this stable location.

    CALL stMark                         ; Anchor later diagnostics at the leading name.

; Pack the leading name once as a possible label or EQU destination.

    CALL tkText                         ; Return the name text as HL plus byte count B.
    LD   DE,stKey                       ; Select the six-byte packed-name destination.
    CALL nmPackId                       ; Pack and validate the possible symbol name.
    JP   C,stSymErr                     ; Translate packing failure to symbol status.

; Classify the same lexeme as a mnemonic. stMnemOk marks stMnem as valid.
; ordinal zero is not a validity sentinel.

    CALL tkText                         ; Reload the still-current leading lexeme.
    CALL mneFind                        ; Look for an exact mnemonic match.
    JR   C,.noMnem                      ; No mnemonic: try the directive table.
    LD   (stMnem),A                     ; Cache the recognised mnemonic ordinal.
    LD   A,1                            ; Form an explicit Boolean validity marker.
    LD   (stMnemOk),A                   ; Mark the cached mnemonic as usable.
    XOR  A                              ; Clear the alternative classification.
    LD   (stDirOk),A                    ; Clear the directive-valid marker.
    JR   .pastName                      ; Inspect the token following the leading name.
.noMnem: ; Classify the leading name as a directive after mnemonic failure.

; If it was not a mnemonic, test the compact directive table and cache that
; result in the parallel stDir/stDirOk pair.

    XOR  A                              ; Record that mnemonic recognition failed.
    LD   (stMnemOk),A                   ; Prevent stale mnemonic data being consumed.
    CALL tkText                         ; Reload the lexeme for directive lookup.
    CALL stIsDir                        ; Search the compact directive-name table.
    JR   C,.noDir                       ; Leave both validity flags clear if absent.
    LD   (stDir),A                      ; Cache the directive ordinal.
    LD   A,1                            ; Form the directive-valid Boolean.
    LD   (stDirOk),A                    ; Mark the cached directive as usable.
    JR   .pastName                      ; Inspect the token following the leading name.
.noDir: ; Clear directive validity when both operation probes fail.
    XOR  A                              ; Neither mnemonic nor directive matched.
    LD   (stDirOk),A                    ; Clear the remaining validity flag.
.pastName: ; Use the following token to distinguish declaration from operation.

; The token after the leading name determines whether the packed name is a
; declaration target or whether the name itself selects the statement kind.

    CALL stToken                        ; Advance beyond the leading name.
    JP   C,stLexErr                     ; Propagate a lexical failure at that token.
    CP   tkColon                        ; Does the name introduce a label declaration?
    JR   Z,.label                       ; Yes: declare it before processing any tail.

; A recognised mnemonic without a colon begins an instruction immediately.

    LD   A,(stMnemOk)                   ; Test the cached mnemonic classification.
    OR   A                              ; Set Z when no mnemonic matched.
    JP   NZ,.instr                      ; Matched: parse its operands.

; A recognised non-EQU directive without a colon goes to directive dispatch.

    LD   A,(stDirOk)                    ; Test the cached directive classification.
    OR   A                              ; Set Z when no directive matched either.
    JR   Z,.tryEqu                      ; Try the NAME EQU expression declaration form.
    LD   A,(stDir)                      ; Restore the cached directive ordinal.
    JP   stDoDir                        ; Dispatch its operand grammar.
.tryEqu: ; Test a colonless constant declaration for the EQU directive.

; An unrecognised leading name may still be the destination of colonless EQU.
; The current token must itself be the recognised EQU directive.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token after the constant name.
    CP   tkName                         ; Only another name can be the EQU directive.
    JP   NZ,stBadOp                     ; A bare name must be an operation or EQU.
    CALL tkText                         ; Expose the second name's characters.
    CALL stIsDir                        ; Classify it through the directive table.
    JP   C,stBadOp                      ; An unknown name is invalid in this position.
    CP   stEqu                          ; Did the recognised directive equal EQU?
    JP   NZ,stBadOp                     ; No other directive may follow a bare name.
    JP   stDoEqu                        ; Parse and declare the constant.
.label: ; Inspect the token after a label's colon before declaration.

; After a colon, recognise the special convenience form "label: EQU value".
; Any other token leaves the declaration as an address label.

    CALL stToken                        ; Consume colon and fetch the next token.
    JP   C,stLexErr                     ; Preserve any tokenizer error.
    CP   tkName                         ; A name here might be the EQU directive.
    JR   NZ,.declare                    ; Anything else leaves an address label.
    CALL tkText                         ; Expose the possible directive text.
    CALL stIsDir                        ; Attempt directive recognition.
    JR   C,.declare                     ; No directive: declare an address label.
    CP   stEqu                          ; Is this specifically EQU?
    JR   Z,stDoEqu                      ; EQU: declare a constant.
.declare: ; Bind an address label in global or current private scope.

; The packed key's private bit selects the declaration rule. A global address
; label closes the previous private scope. A private label remains within it.

    LD   HL,stKey+5                     ; Address the packed symbol's flag byte.
    BIT  7,(HL)                         ; Test the private-name marker.
    LD   HL,stKey                       ; Supply the packed symbol key.
    LD   DE,(outAddr)                   ; Bind the label to the current output address.
    JR   NZ,.private                    ; Private names use the current global scope.
    CALL syLabel                        ; Declare a global and open its private scope.
    JR   .declared                      ; Share declaration and resolution checks.
.private: ; Declare the label within the active private scope.
    CALL syDecl                         ; Declare in the active private scope.
.declared: ; Check declaration success before resolving its references.
    JP   C,stSymErr                     ; Report a symbol declaration failure.

; A newly known address may satisfy several forward references. Resolution is
; transactional with the sink and leaves diagnostics intact on failure.

    CALL outFixUp                       ; Emit and retire this symbol's patches.
    JP   C,stOutErr                     ; Preserve transactional output failure.

; A bare label ends at EOL. Otherwise the same line may continue with exactly
; one instruction or directive name.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token after the label.
    CP   tkEol                          ; Is the label the complete statement?
    JP   Z,stNext                       ; Yes: begin the next line.
    CP   tkName                         ; A statement tail must start with a name.
    JP   NZ,stStray                     ; Reject a non-name statement tail.
    CALL stMark                         ; Anchor errors at the operation name.
    CALL tkText                         ; Expose that name for mnemonic lookup.
    CALL mneFind                        ; Try to recognise an instruction.
    JR   C,.tailDir                     ; If absent, try the directive table instead.

; Cache the mnemonic, consume its name and share the ordinary
; instruction path used by statements without a label.

    LD   (stMnem),A                     ; Cache the post-label mnemonic ordinal.
    CALL tkNext                         ; Consume the name. Expose its first operand.
    JP   C,stLexErr                     ; Retain a lexical error in its operands.
    JR   .instr                         ; Join ordinary instruction parsing.
.tailDir: ; Recognise a directive following a label on the same line.

; The post-label name was not a mnemonic. It must be a recognised directive.

    CALL tkText                         ; Reload the name for directive lookup.
    CALL stIsDir                        ; Look for an exact directive match.
    JP   C,stBadOp                      ; Unknown operation names are statement errors.
    LD   (stDir),A                      ; Save the directive across token advancement.
    CALL tkNext                         ; Consume the directive name.
    JP   C,stLexErr                     ; Preserve a lexical failure in its arguments.
    LD   A,(stDir)                      ; Restore the directive ordinal for dispatch.
    JR   stDoDir                        ; Enter the common directive dispatcher.
.instr: ; Parse and emit the recognised mnemonic's operands.

; Parse and validate operands into stIns. Use the output cursor as the
; instruction address. Relative expressions depend on that address.

    LD   A,(stMnem)                     ; Supply the recognised mnemonic ordinal.
    LD   BC,(outAddr)                   ; Supply the instruction's output address.
    LD   DE,stIns                       ; Select the union's parsed-instruction record.
    CALL prPostMn                       ; Parse and validate the instruction form.
    JP   C,stInsErr                     ; Wrap a parser error as instruction failure.

; Emit one to four instruction bytes, then fetch the next line.

    CALL outEmitI                       ; Encode and publish the validated instruction.
stOutOk: ; Check output status before fetching the next statement.
    JP   C,stOutErr                     ; Convert any output error to statement status.
    JP   stNext                         ; Continue with the next source statement.
stDoEqu: ; Evaluate and declare an immediate EQU constant.

; Consume EQU and evaluate its expression at the current output address.

    CALL tkNext                         ; Consume EQU. Expose its expression.
    JP   C,stLexErr                     ; Preserve a lexical failure before evaluation.
    CALL stPcExpr                       ; Evaluate at the current output address.
    JP   C,stEqErr                      ; Wrap an expression error as EQU failure.

; EQU must be known now. A forward EQU would require delayed expression
; evaluation rather than the byte patches used for address references.

    OR   A                              ; A is nonzero when the result is unresolved.
    JP   NZ,stEqFwd                     ; EQU requires a value immediately.

; Save the low word. Derive its sign from the expression's high
; extension byte: zero is unsigned/non-negative, nonzero is negative.

    LD   (stEqVal),HL                   ; Save the result's low sixteen bits.
    XOR  A                              ; Start with a non-negative sign flag.
    LD   HL,exRVal+2                    ; Address the expression's extension byte.
    CP   (HL)                           ; Is the extension zero?
    JR   Z,.signSet                     ; Yes: retain the clear sign flag.
    INC  A                              ; No: mark the constant as sign-extended.
.signSet: ; Retain the EQU result's sign-extension flag.
    LD   (stEqSign),A                   ; Preserve signedness across delimiter checks.

; No token may follow the EQU expression on the statement.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token left by expression parsing.
    CP   tkEol                          ; Did the expression end at EOL?
    JP   NZ,stEqTail                    ; Report any trailing delimiter or token.

; EQU declares in the current scope without opening a new global scope.

    LD   HL,stKey                       ; Supply the packed constant name.
    LD   DE,(stEqVal)                   ; Supply its immediate sixteen-bit value.
    CALL syDecl                         ; Declare it without changing global scope.
    JP   C,stSymErr                     ; Preserve a symbol declaration failure.

; Mark negative constants in the packed symbol record
; before resolving any waiting references to its newly concrete value.

    LD   A,(stEqSign)                   ; Recover the saved sign-extension flag.
    OR   A                              ; Set Z for a non-negative constant.
    JR   Z,.resolve                     ; Leave its symbol flags unchanged.
    SET  5,(IX+5)                       ; Mark it negative for later expressions.
.resolve: ; Resolve pending uses after the constant becomes defined.
    CALL outFixUp                       ; Resolve pending uses of the new constant.
    JR   stOutOk                        ; Check output status and continue.
stDoDir: ; Dispatch the contiguous ORG through ALIGN ordinals.

; EQU is handled by the declaration grammar above. Subtracting stOrg maps the
; remaining contiguous ordinals onto the eight-entry address table.

    SUB  stOrg                          ; Index ORG..ALIGN from zero.
    CP   8                              ; Is this one of eight table entries?
    JP   NC,stUnexp                     ; Reject EQU or a corrupt/out-of-range ordinal.
    ADD  A,A                            ; Scale the index for a two-byte address entry.
    LD   L,A                            ; Place the scaled offset in HL.
    LD   H,0                            ; Zero-extend it to sixteen bits.
    LD   DE,.handlers                   ; Point DE at the directive address table.
    ADD  HL,DE                          ; Address the selected little-endian entry.
    LD   E,(HL)                         ; Load the handler address low byte.
    INC  HL                             ; Advance to its high byte.
    LD   D,(HL)                         ; Complete the handler address in DE.
    EX   DE,HL                          ; Put the handler address in HL.
    JP   (HL)                           ; Dispatch without another comparison chain.
.handlers: ; Little-endian handler addresses in directive ordinal order.

; ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN handlers in ordinal order.

    DW   .doOrg,.doDb,.doDw,stDoDs      ; Numeric and storage directives.
    DW   stCMode,stPMode,stIMode        ; Three standalone string formats.
    DW   stPad                          ; Address-alignment directive.
.doOrg: ; Require a concrete origin and move the logical cursor.

; ORG requires one concrete expression and no trailing token. It changes the
; logical output cursor. The platform adapter owns extent and append policy.

    CALL stPcExpr                       ; Evaluate the absolute output address.
    JP   C,stDirErr                     ; Preserve expression syntax or range detail.
    OR   A                              ; Test the unresolved-result flag.
    JP   NZ,stDirFwd                    ; ORG cannot wait for a forward definition.
    LD   (stDirVal),HL                  ; Save the address across delimiter validation.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token following the expression.
    CP   tkEol                          ; ORG accepts exactly one expression.
    JP   NZ,stExtra                     ; Report the unexpected trailing token.
    LD   HL,(stDirVal)                  ; Restore the requested origin.
    CALL outOrg                         ; Set the logical output cursor.
    JP   stOutOk                        ; Check output status and continue.
.doDb: ; Select scalar byte width and truncating forward patches.

; Width and default patch kind distinguish DB from DW. Both
; then share the comma-separated item loop.

    LD   A,1                            ; Select one emitted byte per scalar item.
    LD   (stWidth),A                    ; Retain DB width for the shared list loop.
    LD   A,fixTrunc                     ; Select the ordinary byte patch kind.
    LD   (stFixDef),A                   ; Retain it for an unresolved expression.
    JR   stItem                         ; Enter the common data-item parser.
.doDw: ; Select scalar word width and full-word forward patches.
    LD   A,2                            ; Select two emitted bytes per scalar item.
    LD   (stWidth),A                    ; Retain DW width for the shared list loop.
    LD   A,fixWord                      ; Select the ordinary word patch kind.
    LD   (stFixDef),A                   ; Retain it for an unresolved expression.
stItem: ; Parse the next scalar or quoted-string data item.

; A data list cannot be empty or end immediately after a comma.

    LD   A,(tkRecord+tkKindAt)          ; Read the current prospective item token.
    CP   tkEol                          ; Did the list end before an item appeared?
    JP   Z,stNoExpr                     ; Report the missing expression.

; Quoted strings are accepted only in DB. They use mode zero so the common
; string emitter returns to the data-list delimiter path, not the end of
; the whole statement.

    CP   tkStr                          ; Is this item a quoted string?
    JR   NZ,.scalar                     ; No: parse it as a scalar expression.
    LD   A,(stWidth)                    ; Recover the active data width.
    CP   1                              ; Are we assembling DB rather than DW?
    JP   NZ,stDwStr                     ; Reject strings in a word list.
    XOR  A                              ; Mode zero denotes an inline DB string.
    LD   (stStrFmt),A                   ; Select list-aware completion behaviour.
    JP   stPuts                         ; Count, preflight and emit the decoded string.
.scalar: ; Evaluate a scalar item or retain its unresolved symbol.

; A concrete expression emits its low byte or low word immediately.

    CALL stPcExpr                       ; Evaluate the scalar data item.
    JP   C,stDirErr                     ; Preserve nested expression failure detail.
    OR   A                              ; Is the expression waiting on a symbol?
    JR   NZ,.pending                    ; Yes: reserve bytes and queue a patch.
    LD   A,(stWidth)                    ; Recover the active DB/DW width.
    CP   1                              ; Does this item emit one byte?
    JR   Z,.oneByte                     ; Yes: publish only L.
    CALL outEmitW                       ; Publish HL in little-endian order.
    JR   .emitted                       ; Share output checking and delimiter parsing.
.oneByte: ; Emit the low byte of a resolved DB expression.
    LD   A,L                            ; Select the expression's low byte.
    CALL outEmitB                       ; Publish the byte through the output sink.
.emitted: ; Check scalar output before handling its list delimiter.
    JP   C,stOutErr                     ; Preserve output capacity or sink failure.
    JP   stMore                         ; Require comma or end-of-line next.
.pending: ; Preflight storage and queue an unresolved data-item patch.

; A simple unresolved symbol may be represented by a pending patch. Save
; the addend and symbol pointer before a capacity or emission call can
; reuse IX, HL or the shared expression workspace.

    LD   A,L                            ; Capture the signed expression addend.
    LD   (stDelta),A                    ; Preserve it for the pending record.
    PUSH IX                             ; Save the expression symbol pointer.
    POP  HL                             ; Receive that pointer in HL.
    LD   (stFwdKey),HL                  ; Preserve it across capacity checks.
    LD   A,(stWidth)                    ; Recover the placeholder byte count.
    LD   L,A                            ; Put that count in low word byte.
    LD   H,0                            ; Zero-extend it for output preflight.

; Prove both output and pending-record capacity before publishing a zero
; placeholder. On failure, stream and symbol state remain unchanged.

    CALL outCapOk                       ; Prove the placeholder fits the output range.
    JP   C,stOutErr                     ; Fail before any visible write on exhaustion.
    CALL syFitRef                       ; Prove one pending record fits its arena.
    JP   C,stSymErr                     ; Fail before emission if it does not.
    LD   A,(exRForm)                    ; Read the unresolved projection form.
    CP   exFLow                         ; Was LOW(...) requested?
    JR   Z,.lowByte                     ; Yes: use a low-byte patch.
    CP   exFHigh                        ; Was HIGH(...) requested?
    JR   Z,.highByte                    ; Yes: use a high-byte patch.

; Plain unresolved DB/DW uses the directive's width-specific patch kind. LOW
; and HIGH expression forms override that with the corresponding byte patch.

    LD   A,(stFixDef)                   ; Use the DB/DW default patch kind.
    JR   .kindSet                       ; Store the selected kind.
.lowByte: ; Select LOW extraction for the future resolved value.
    LD   A,fixLow                       ; Select low-byte extraction at resolution.
    JR   .kindSet                       ; Store the selected kind.
.highByte: ; Select HIGH extraction for the future resolved value.
    LD   A,fixHigh                      ; Select high-byte extraction at resolution.
.kindSet: ; Retain the selected patch transform across symbol lookup.
    LD   (stKind),A                     ; Preserve the kind across symbol lookup.

; Find or create the undefined symbol record. B reports whether this is the
; first reference, which is the one that must retain the diagnostic anchor.

    LD   HL,(stFwdKey)                  ; Restore the packed unresolved symbol pointer.
    CALL syRef                          ; Find or create its undefined symbol record.
    JP   C,stSymErr                     ; Preserve symbol arena or scope failure.
    LD   A,B                            ; B is nonzero only for the first reference.
    OR   A                              ; Set Z for a previously referenced symbol.
    JR   Z,.anchored                    ; Reuse its existing diagnostic anchor.

; Store the first reference offset in the undefined symbol's value word
; and mark this pending record as its diagnostic anchor.

    LD   HL,(exSrcOff)                  ; Recover the expression's source-byte offset.
    LD   (IX+syValLo),L                 ; Store its low byte in the undefined record.
    LD   (IX+syValHi),H                 ; Store its high byte to complete the anchor.
    LD   A,syAnchor                     ; Select the diagnostic-anchor flag.
    LD   HL,stKind                      ; Address the pending patch kind.
    OR   (HL)                           ; Add the anchor flag to the patch kind.
    LD   (HL),A                         ; Retain the combined pending metadata.
.anchored: ; Preserve the symbol pointer and placeholder address for emission.

; Preserve the symbol and patch address while the placeholder is emitted.

    PUSH IX                             ; Copy the symbol-record pointer from IX.
    POP  HL                             ; Receive the pointer in HL for storage.
    LD   (stFwdSym),HL                  ; Preserve it across placeholder emission.
    LD   HL,(outAddr)                   ; Capture the placeholder's target address.
    LD   (stFwdAt),HL                   ; Retain that address for the pending record.
    LD   A,(stWidth)                    ; Recover the placeholder width.
    CP   1                              ; Is this an unresolved DB item?
    JR   Z,.zeroByte                    ; Yes: emit one zero byte.

; Emit a zero-filled placeholder. A later PATCH carries the final value.

    LD   HL,0                           ; Form a two-byte zero placeholder.
    CALL outEmitW                       ; Emit the preflighted two-byte placeholder.
    JP   C,stOutErr                     ; Preserve any unexpected sink failure.
    JR   .enqueue                       ; Append its pending patch record.
.zeroByte: ; Emit the single zero placeholder used by unresolved DB.
    XOR  A                              ; Form a one-byte zero placeholder.
    CALL outEmitB                       ; Publish the reserved byte.
    JP   C,stOutErr                     ; Preserve any unexpected sink failure.
.enqueue: ; Append the pending record after placeholder acceptance.

; Append the pending record only after the placeholder emission succeeds. It
; captures symbol, target address, kind, addend and source position.

    LD   IX,(stFwdSym)                  ; Restore the referenced symbol record.
    LD   DE,(stFwdAt)                   ; Supply the placeholder target address.
    LD   A,(stKind)                     ; Recover the kind and possible anchor flag.
    LD   B,A                            ; Place pending metadata in its ABI register.
    LD   A,(stDelta)                    ; Recover the signed expression addend.
    LD   C,A                            ; Place the addend in its ABI register.
    LD   HL,(exSrcOff)                  ; Supply the reference's source offset.
    LD   (syAddOff),HL                  ; syAdd stores it with the record.
    LD   A,(exSrcPos)                   ; Supply the reference's source-part ordinal.
    CALL syAdd                          ; Append the fully described pending record.
    JP   C,stSymErr                     ; Preserve capacity or invariant failure.
stMore: ; Require a comma or EOL after a data-list item.

; Accept EOL or comma followed by another item. A trailing comma reports
; a missing expression.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token following the emitted item.
    CP   tkEol                          ; Has the data list ended?
    JP   Z,stNext                       ; Yes: begin the next statement.
    CP   tkComma                        ; Otherwise require an item separator.
    JP   NZ,stExtra                     ; Report the unexpected delimiter.
    CALL stToken                        ; Consume the comma and fetch the next item.
    JP   C,stLexErr                     ; Preserve a tokenizer failure after the comma.
    CP   tkEol                          ; Did the list end immediately after it?
    JP   Z,stNoExpr                     ; Diagnose the missing item.
    JP   stItem                         ; Parse the next scalar or string item.
