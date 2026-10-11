;=============================================================================
;  Instruction and operand parser
;=============================================================================
;
;  PURPOSE
;  -------
;  Recognise one mnemonic, parse up to three operands and build the encoder's
;  ten-byte instruction record. Form validation commits it only after the
;  entire source instruction is valid.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;+---------------------------------------------------------------------------+
;| PR_PARSE - Parse one complete instruction from the token stream.          |
;|                                                                           |
;| Entry: BC = logical instruction address.                                  |
;|        DE -> caller-owned ten-byte destination record.                    |
;| Result: Carry clear, A = PR_SOK and IX -> committed record.               |
;|         Carry clear, A = PR_SEOF when the next token is EOF.              |
;| Error: Carry set, A = parser status, PR_EPART:PR_EOFF = source position.  |
;| Effect: Advances the token stream and uses the parser/form workspace.     |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| PR_PUB - Parse operands for an already recognised mnemonic.               |
;|                                                                           |
;| Entry: A = mnemonic ordinal.                                              |
;|        BC = logical instruction address.                                  |
;|        DE -> caller-owned ten-byte destination record.                    |
;|        TK_REC contains the first operand or EOL.                          |
;| Result: Carry clear, A = PR_SOK and IX -> committed record.               |
;| Error: Carry set, A = parser status.                                      |
;| Effect: Advances the token stream and uses the parser/form workspace.     |
;+---------------------------------------------------------------------------+
;
;  RECORD AND FAILURE RULES
;  ------------------------
;
;  Operand classes occupy bytes 1..3 of the record and their little-endian
;  values occupy bytes 4..9. A missing symbol is retained initially as a
;  six-byte packed key, signed addend, operand index, transform and source
;  position. Form and patch-field checks precede symbol-arena changes.
;  The successful parser publishes at most two nine-byte reference
;  descriptions. Two are sufficient for `LD (IX+DISP),IMMEDIATE`, the only Z80
;  shape with two independently patchable fields.
;
;  The caller's instruction record is a commit destination: syntax, form,
;  range, symbol and reference failures leave it unchanged. Missing symbols
;  are inserted only after the form and shared-arena capacity checks have
;  passed. Pending records are still deferred until PR_QUEUE, after output has
;  accepted the encoded IMAGE bytes.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  Both entries preserve the caller's stack balance and may clobber every main
;  register except SP. They use fixed state in forms.asm and are not
;  reentrant. The destination is caller-owned. Symbol and pending arenas
;  belong to the build descriptor managed by the driver.

PR_CBEG: ; Begin the instruction parser's code and constants.

; Parser statuses returned in A. PR_SPCAP remains in the ABI, but the
; current eight-bit source-part ordinal needs no parser-side capacity check.

PR_SOK      EQU     0                   ; Successful instruction parse.
PR_SEOF     EQU     1                   ; Successful end of the source stream.
PR_SLEX     EQU     2                   ; Tokenizer failure while parsing an instruction.
PR_SNOMN    EQU     3                   ; A mnemonic name was required at the instruction start.
PR_SBADM    EQU     4                   ; The name matched no supported mnemonic.
PR_SNOOP    EQU     5                   ; An operand was required at this token.
PR_SBADO    EQU     6                   ; The operand syntax or class is unsupported.
PR_SNODL    EQU     7                   ; An operand delimiter is missing or invalid.
PR_SMANY    EQU     8                   ; The instruction supplied more than three operands.
PR_SFORM    EQU     9                   ; The completed operand classes match no instruction form.
PR_SVRNG    EQU     10                  ; A concrete operand exceeds its encoded field's range.
PR_SRRNG    EQU     11                  ; A relative target exceeds the signed-byte displacement range.
PR_SINT     EQU     12                  ; A parser publication invariant failed.
PR_SEXPR    EQU     13                  ; Expression evaluation failed with detail in PR_EXERR.
PR_SUNPA    EQU     14                  ; The unresolved expression cannot use this patch field.
PR_SSYM     EQU     15                  ; Symbol lookup or allocation failed with detail in PR_SYERR.
PR_SRCAP    EQU     16                  ; The private reference array cannot hold another entry.
PR_SPCAP    EQU     17                  ; Retained status for source-part capacity in the public ABI.

; Reference and record geometry. The build form contains a packed key. The
; public form uses a symbol-record pointer and omits build-only data.

PR_RCAP     EQU     2                   ; At most two independently deferred fields per instruction.
PR_BRB      EQU     13                  ; Bytes in a private reference with its packed symbol key.
PR_PRB      EQU     9                   ; Bytes in a public reference with its symbol-record pointer.
PR_BKEY     EQU     0                   ; Packed six-byte key begins the private reference.
PR_BADD     EQU     6                   ; Signed addend byte within the private reference.
PR_BOPER    EQU     7                   ; Operand index byte within the private reference.
PR_BKIND    EQU     8                   ; Transform kind byte within the private reference.
PR_BPOFF    EQU     9                   ; Encoded field offset byte within the private reference.
PR_BPART    EQU     10                  ; Diagnostic source-part byte within the private reference.
PR_BSOFF    EQU     11                  ; Diagnostic source-offset word within the private reference.
PR_RSYM     EQU     0                   ; Symbol pointer word begins the public reference.
PR_RADD     EQU     2                   ; Signed addend byte within the public reference.
PR_ROPER    EQU     3                   ; Operand index byte within the public reference.
PR_RKIND    EQU     4                   ; Final patch-kind byte within the public reference.
PR_RPOFF    EQU     5                   ; Encoded field offset byte within the public reference.
PR_RPART    EQU     6                   ; Diagnostic source-part byte within the public reference.
PR_RSOFF    EQU     7                   ; Diagnostic source-offset word within the public reference.

; Temporary operand classes used before mnemonic-specific normalisation.

PR_GNUM     EQU     240                 ; Numeric expression awaiting mnemonic-specific classification.
PR_GPNUM    EQU     241                 ; Parenthesised number awaiting memory or port classification.
PR_GC       EQU     242                 ; Operand C awaiting register or condition classification.

;@ROUTINE IN A,BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Enter after the statement layer has recognised and consumed the mnemonic. A
; is its ordinal and TK_REC already contains the first operand or EOL.

PR_PUB: ; Parse operands after a caller has consumed the mnemonic.
    PUSH AF                             ; Save the mnemonic ordinal.
    LD   (PR_IADR),BC                   ; Retain the logical address used by `$`.
    LD   (PR_DST),DE                    ; Save the commit destination.
    XOR  A                              ; Start with no published references.
    LD   (PR_PRCNT),A                   ; Clear the public-reference count.
    CALL PR_RESET                       ; Reset the private instruction record.
    POP  AF                             ; Recover the mnemonic ordinal.
    LD   (PR_REC+EN_MNEM),A             ; Begin the record with that mnemonic.
    JR   PR_OPERS                       ; Parse the token already in TK_REC.

;@ROUTINE IN BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Standalone entry: fetch, diagnose and recognise the mnemonic before joining
; the operand path shared with PR_PUB.

PR_PARSE: ; Fetch and recognise a mnemonic before parsing its operands.
    LD   (PR_IADR),BC                   ; Retain the logical instruction address.
    LD   (PR_DST),DE                    ; Save the output record address.
    XOR  A                              ; Start with no published references.
    LD   (PR_PRCNT),A                   ; Clear the public-reference count.
    CALL PR_RESET                       ; Reset all private instruction state.
    CALL PR_NEXT                        ; Fetch the mnemonic token.
    RET  C                              ; Return an exact tokenizer failure.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token kind.
    CP   TK_EOF                         ; Did the source stream finish cleanly?
    JR   Z,PR_EOF                       ; Report successful end of input.
    CP   TK_NAME                        ; A mnemonic must be a name token.
    JP   NZ,PR_FNOMN                    ; Diagnose any other token kind.
    LD   A,(TK_REC+TK_RPART)            ; Capture the mnemonic's source part.
    LD   (PR_IPART),A                   ; Retain it for later diagnostics.
    LD   HL,(TK_REC+TK_ROFF)            ; Capture the mnemonic's source offset.
    LD   (PR_IOFF),HL                   ; Retain the complete source position.
    CALL TK_TEXT                        ; Load the mnemonic text and length.
    CALL EN_RECOG                       ; Translate the name to an ordinal.
    JP   C,PR_FBADM                     ; Diagnose an unknown mnemonic.
    LD   (PR_REC+EN_MNEM),A             ; Store the recognised mnemonic privately.

; Advance once so the shared path sees the first operand or EOL.

    CALL PR_NEXT                        ; Advance to the first operand or EOL.
    RET  C                              ; Preserve any tokenizer failure.
PR_OPERS: ; Parse the operand list shared by both public entries.

; Zero operands may be valid. Form validation decides whether the
; selected mnemonic permits them.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the first unconsumed token.
    CP   TK_EOL                         ; Is this a zero-operand instruction?
    JR   Z,.PARSED                      ; Validate the empty operand list.
.OPLOOP: ; Select and parse the next of three operand slots.

; Select class/value slots for the next operand before parsing it. A fourth
; operand fails before any out-of-record pointer can be formed.

    LD   A,(PR_OPCNT)                   ; Select the next operand index.
    CP   3                              ; The instruction record has three slots.
    JP   NC,PR_FMANY                    ; Refuse a fourth operand safely.
    CALL PR_SLOT                        ; Point at this operand's class and value.
    CALL PR_POP                         ; Parse and classify the source operand.
    RET  C                              ; Stop on its precise diagnostic.
    LD   HL,PR_OPCNT                    ; Address the operand count.
    INC  (HL)                           ; Publish one more private operand.

; Each operand ends at EOL or a comma. A trailing comma is a
; distinct expected-operand error.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the delimiter after the operand.
    CP   TK_EOL                         ; Has the operand list ended?
    JR   Z,.PARSED                      ; Begin whole-record normalisation.
    CP   TK_COMMA                       ; Otherwise require a comma.
    JP   NZ,PR_FNODL                    ; Diagnose the unexpected delimiter.
    CALL PR_NEXT                        ; Read the token after the comma.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token after the comma.
    CP   TK_EOL                         ; A comma cannot terminate the line.
    JP   Z,PR_FNOOP                     ; Report the missing operand.
    JR   .OPLOOP                        ; Parse the next operand.
.PARSED: ; Validate classes, ranges and references before record commit.

; Normalisation proceeds from source conveniences to an exact encoder record:
; accumulator aliases, numeric classes, candidate form selection, concrete
; ranges, deferred patch fields and finally destination commit.

    CALL PR_ALIAS                       ; Normalise explicit-accumulator aliases.
    RET  C                              ; Reject a missing required accumulator.
    CALL PR_CLASS                       ; Assign provisional numeric classes.
    RET  C                              ; Stop on a numeric range error.
    CALL PR_FORM                        ; Validate the completed instruction form.
    RET  C                              ; Return the form diagnostic.
    LD   (PR_ILEN),A                    ; Retain the validated encoded length.
    CALL PR_RANGE                       ; Check every resolved operand value.
    RET  C                              ; Stop before publishing invalid state.
    CALL PR_BIND                        ; Resolve and preflight deferred symbols.
    RET  C                              ; Leave destination untouched.
    JP   PR_CMT                         ; Commit the complete instruction record.
PR_EOF: ; Return the successful non-instruction EOF result.

; EOF is a successful non-instruction result for callers that iterate tokens.

    LD   A,PR_SEOF                      ; Select the successful EOF status.
    OR   A                              ; Clear carry while preserving nonzero A.
    RET                                 ; Return without an instruction record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY
; Initialise the private ten-byte record to mnemonic 0, three EN_NONE operands
; and zero values. Clear every per-instruction mask and reference count.

PR_RESET: ; Clear the private record and per-instruction masks.
    LD   HL,PR_REC                      ; Begin at the private mnemonic byte.
    XOR  A                              ; Mnemonic zero is the cleared value.
    LD   (HL),A                         ; Clear the mnemonic slot.
    INC  HL                             ; Advance to operand class zero.
    LD   B,3                            ; Clear all three class slots.
    LD   A,EN_NONE                      ; Missing operands use EN_NONE.
.OPLOOP: ; Initialise one absent operand class per iteration.
    LD   (HL),A                         ; Mark this operand as absent.
    INC  HL                             ; Advance to the next class slot.
    DJNZ .OPLOOP                        ; Fill all three operand classes.
    XOR  A                              ; Operand values begin at zero.
    LD   B,6                            ; Three little-endian words follow.
.VALLOOP: ; Clear the six bytes occupied by operand values.
    LD   (HL),A                         ; Clear one value byte.
    INC  HL                             ; Advance through the value area.
    DJNZ .VALLOOP                       ; Clear all six value bytes.
    LD   (PR_OPCNT),A                   ; No operands have been parsed.
    LD   (PR_FMASK),A                   ; No operand is flexible yet.
    LD   (PR_CMASK),A                   ; No operand is a condition candidate.
    LD   (PR_BRCNT),A                   ; No build references exist.
    LD   (PR_UMASK),A                   ; No operand remains unresolved.
    RET                                 ; Return with clean private state.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch one token and translate tokenizer failures into parser status while
; preserving the tokenizer's exact source part and offset.

PR_NEXT: ; Fetch a token and adapt lexical failure to parser diagnostics.
    CALL TK_NEXT                        ; Read one complete token.
    RET  NC                             ; Return its successful token unchanged.
    LD   A,(TK_EPART)                   ; Copy the tokenizer's source part.
    LD   (PR_EPART),A                   ; Publish it as the parser error part.
    LD   HL,(TK_EOFF)                   ; Copy the tokenizer's byte offset.
    LD   (PR_EOFF),HL                   ; Preserve the exact failure position.
    LD   A,PR_SLEX                      ; Report a lexical parser failure.
    SCF                                 ; Mark the result as unsuccessful.
    RET                                 ; Return with the location published.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Select operand A. PR_CPTR points at its class byte and PR_VPTR at its word
; value, allowing all later normalisers to operate on the selected slot.

PR_SLOT: ; Address the class and value fields for operand index A.
    LD   E,A                            ; Use the operand index as a byte offset.
    LD   D,0                            ; Extend it to 16 bits.
    LD   HL,PR_REC+EN_OP0               ; Begin at operand class zero.
    ADD  HL,DE                          ; Select this operand's class byte.
    LD   (PR_CPTR),HL                   ; Retain the selected class pointer.
    LD   A,E                            ; Recover the operand index.
    ADD  A,A                            ; Each operand value occupies two bytes.
    LD   E,A                            ; Use the doubled index as its offset.
    LD   HL,PR_REC+EN_VAL0              ; Begin at operand value zero.
    ADD  HL,DE                          ; Select this operand's value word.
    LD   (PR_VPTR),HL                   ; Retain the selected value pointer.
    RET                                 ; Return with both pointers installed.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Carry clear identifies token kinds that can begin an expression without a
; leading name or parenthesis. Names and '(' are dispatched separately.

PR_ISEXP: ; Classify non-name expression starters through carry.
    CP   TK_NUM                         ; A numeric literal starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   TK_CUR                         ; `$` starts an address expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   TK_PLUS                        ; Unary plus starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   TK_MINUS                       ; Unary minus starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   TK_TILDE                       ; Bitwise complement starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    SCF                                 ; Reject every other token kind.
    RET                                 ; Return carry set for a non-starter.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one selected operand. Short names first pass through the register and
; condition table. Other names and all numeric starters enter the expression
; evaluator. Parentheses select memory or port syntax.

PR_POP: ; Choose fixed-word, expression or parenthesised operand parsing.
    LD   A,(TK_REC+TK_RKIND)            ; Inspect the operand's first token.
    CP   TK_NAME                        ; Names may be registers or expressions.
    JR   Z,.OPNAME                      ; Try the fixed operand-word table first.
    CALL PR_ISEXP                       ; Test the non-name expression starters.
    JR   NC,.OPEXPR                     ; Parse a numeric or unary expression.
    CP   TK_LPAR                        ; Parentheses introduce memory or a port.
    JP   Z,PR_PAREN                     ; Parse the indirect operand form.
    JP   PR_FNOOP                       ; Nothing else can begin an operand.
.OPNAME: ; Test a name as a register or condition before symbol evaluation.
    CALL PR_MATCH                       ; Try fixed operand words.
    JR   C,.OPEXPR                      ; Treat an unrecognised name as a symbol.

; A recognised word supplies a provisional class. Most are final, but C
; remains ambiguous with condition C until form validation.

    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   (HL),A                         ; Store the provisional operand class.
    LD   (PR_SAVED),A                   ; Keep a copy across token consumption.
    CALL PR_NEXT                        ; Advance past the operand word.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(PR_SAVED)                   ; Recover the provisional class.
    CP   EN_AF                          ; Only AF accepts a following apostrophe.
    JR   NZ,.OPPARSED                   ; Other operand words are complete.

; AF followed immediately by apostrophe becomes the alternate register pair.

    LD   A,(TK_REC+TK_RKIND)            ; Inspect the token following AF.
    CP   TK_APOST                       ; Does it select the alternate pair?
    JR   NZ,.OPPARSED                   ; Leave ordinary AF unchanged.
    LD   HL,(PR_CPTR)                   ; Reopen the selected class slot.
    LD   (HL),EN_APRIM                  ; Replace AF with the AF' class.
    JR   PR_NEXT                        ; Consume the apostrophe and continue.
.OPPARSED: ; Finish a recognised register or condition operand.
    XOR  A                              ; Clear carry for a parsed fixed operand.
    RET                                 ; Leave the next token in TK_REC.
.OPEXPR: ; Evaluate an operand as a provisional numeric expression.

; Expressions start as a generic number. Mnemonic-specific normalisation later
; chooses immediate width, relative, displacement, bit, mode or restart class.

    CALL PR_EVAL                        ; Evaluate or defer the source expression.
    RET  C                              ; Preserve its exact diagnostic.
    LD   A,PR_GNUM                      ; Mark it as a generic numeric operand.
    LD   HL,(PR_CPTR)                   ; Address the selected class slot.
    LD   (HL),A                         ; Store the generic class.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the following token in TK_REC.
