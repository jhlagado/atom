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
;| prParse - Parse one complete instruction from the token stream.          |
;|                                                                           |
;| Entry: BC = logical instruction address.                                  |
;|        DE -> caller-owned ten-byte destination record.                    |
;| Result: Carry clear, A = prOk and IX -> committed record.               |
;|         Carry clear, A = prAtEof when the next token is EOF.              |
;| Error: Carry set, A = parser status, prErrSrc:prErrOff = source position.  |
;| Effect: Advances the token stream and uses the parser/form workspace.     |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| prPostMn - Parse operands for an already recognised mnemonic.               |
;|                                                                           |
;| Entry: A = mnemonic ordinal.                                              |
;|        BC = logical instruction address.                                  |
;|        DE -> caller-owned ten-byte destination record.                    |
;|        tkRecord contains the first operand or EOL.                          |
;| Result: Carry clear, A = prOk and IX -> committed record.               |
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
;  passed. Pending records are still deferred until refQueue, after output has
;  accepted the encoded IMAGE bytes.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  Both entries preserve the caller's stack balance and may clobber every main
;  register except SP. They use fixed state in prforms.asm and are not
;  reentrant. The destination is caller-owned. Symbol and pending arenas
;  belong to the build descriptor managed by the driver.

prBeg: ; Begin the instruction parser's code and constants.

; Parser statuses returned in A. prSrcCap remains in the ABI, but the
; current eight-bit source-part ordinal needs no parser-side capacity check.

prOk        EQU     0                   ; Successful instruction parse.
prAtEof     EQU     1                   ; Successful end of the source stream.
prLexErr    EQU     2                   ; Tokenizer failure while parsing an instruction.
prNoMnem    EQU     3                   ; A mnemonic name was required at the instruction start.
prBadMn     EQU     4                   ; The name matched no supported mnemonic.
prNoOper    EQU     5                   ; An operand was required at this token.
prBadOp     EQU     6                   ; The operand syntax or class is unsupported.
prNoDlm     EQU     7                   ; An operand delimiter is missing or invalid.
prManyOp    EQU     8                   ; The instruction supplied more than three operands.
prNoForm    EQU     9                   ; The completed operand classes match no instruction form.
prBigVal    EQU     10                  ; A concrete operand exceeds its encoded field's range.
prFarRel    EQU     11                  ; A relative target exceeds the signed-byte displacement range.
prIntErr    EQU     12                  ; A parser publication invariant failed.
prExErr     EQU     13                  ; Expression evaluation failed with detail in prExDet.
prNoFix     EQU     14                  ; The unresolved expression cannot use this patch field.
prSymErr    EQU     15                  ; Symbol lookup or allocation failed with detail in prSymDet.
prRefMax    EQU     16                  ; The private reference array cannot hold another entry.
prSrcCap    EQU     17                  ; Retained status for source-part capacity in the public ABI.

; Temporary operand classes used before mnemonic-specific normalisation.

prAnyNum    EQU     240                 ; Numeric expression awaiting mnemonic-specific classification.
prAnyMem    EQU     241                 ; Parenthesised number awaiting memory or port classification.
prAnyC      EQU     242                 ; Operand C awaiting register or condition classification.

;@ROUTINE IN A,BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Enter after the statement layer has recognised and consumed the mnemonic. A
; is its ordinal and tkRecord already contains the first operand or EOL.

prPostMn: ; Parse operands after a caller has consumed the mnemonic.
    PUSH AF                             ; Save the mnemonic ordinal.
    LD   (prInsPC),BC                   ; Retain the logical address used by `$`.
    LD   (prDest),DE                    ; Save the commit destination.
    XOR  A                              ; Start with no published references.
    LD   (prPubCnt),A                   ; Clear the public-reference count.
    CALL prReset                        ; Reset the private instruction record.
    POP  AF                             ; Recover the mnemonic ordinal.
    LD   (prRec+enMnem),A               ; Begin the record with that mnemonic.
    JR   prOpList                       ; Parse the token already in tkRecord.

;@ROUTINE IN BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Standalone entry: fetch, diagnose and recognise the mnemonic before joining
; the operand path shared with prPostMn.

prParse: ; Fetch and recognise a mnemonic before parsing its operands.
    LD   (prInsPC),BC                   ; Retain the logical instruction address.
    LD   (prDest),DE                    ; Save the output record address.
    XOR  A                              ; Start with no published references.
    LD   (prPubCnt),A                   ; Clear the public-reference count.
    CALL prReset                        ; Reset all private instruction state.
    CALL prNext                         ; Fetch the mnemonic token.
    RET  C                              ; Return an exact tokenizer failure.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token kind.
    CP   tkEof                          ; Did the source stream finish cleanly?
    JR   Z,prRetEof                     ; Report successful end of input.
    CP   tkName                         ; A mnemonic must be a name token.
    JP   NZ,prLackMn                    ; Diagnose any other token kind.
    LD   A,(tkRecord+tkPartAt)          ; Capture the mnemonic's source part.
    LD   (prMnPart),A                   ; Retain it for later diagnostics.
    LD   HL,(tkRecord+tkOffAt)          ; Capture the mnemonic's source offset.
    LD   (prMnOff),HL                   ; Retain the complete source position.
    CALL tkText                         ; Load the mnemonic text and length.
    CALL mneFind                        ; Translate the name to an ordinal.
    JP   C,prDenyMn                     ; Diagnose an unknown mnemonic.
    LD   (prRec+enMnem),A               ; Store the recognised mnemonic privately.

; Advance once so the shared path sees the first operand or EOL.

    CALL prNext                         ; Advance to the first operand or EOL.
    RET  C                              ; Preserve any tokenizer failure.
prOpList: ; Parse the operand list shared by both public entries.

; Zero operands may be valid. Form validation decides whether the
; selected mnemonic permits them.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the first unconsumed token.
    CP   tkEol                          ; Is this a zero-operand instruction?
    JR   Z,.parsed                      ; Validate the empty operand list.
.opLoop: ; Select and parse the next of three operand slots.

; Select class/value slots for the next operand before parsing it. A fourth
; operand fails before any out-of-record pointer can be formed.

    LD   A,(prOpCnt)                    ; Select the next operand index.
    CP   3                              ; The instruction record has three slots.
    JP   NC,prExcess                    ; Refuse a fourth operand safely.
    CALL prSlot                         ; Point at this operand's class and value.
    CALL prOper                         ; Parse and classify the source operand.
    RET  C                              ; Stop on its precise diagnostic.
    LD   HL,prOpCnt                     ; Address the operand count.
    INC  (HL)                           ; Publish one more private operand.

; Each operand ends at EOL or a comma. A trailing comma is a
; distinct expected-operand error.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the delimiter after the operand.
    CP   tkEol                          ; Has the operand list ended?
    JR   Z,.parsed                      ; Begin whole-record normalisation.
    CP   tkComma                        ; Otherwise require a comma.
    JP   NZ,prBadSep                    ; Diagnose the unexpected delimiter.
    CALL prNext                         ; Read the token after the comma.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the token after the comma.
    CP   tkEol                          ; A comma cannot terminate the line.
    JP   Z,prLackOp                     ; Report the missing operand.
    JR   .opLoop                        ; Parse the next operand.
.parsed: ; Validate classes, ranges and references before record commit.

; Normalisation proceeds from source conveniences to an exact encoder record:
; accumulator aliases, numeric classes, candidate form selection, concrete
; ranges, deferred patch fields and finally destination commit.

    CALL prAlias                        ; Normalise explicit-accumulator aliases.
    RET  C                              ; Reject a missing required accumulator.
    CALL prClass                        ; Assign provisional numeric classes.
    RET  C                              ; Stop on a numeric range error.
    CALL prForm                         ; Validate the completed instruction form.
    RET  C                              ; Return the form diagnostic.
    LD   (prInsLen),A                   ; Retain the validated encoded length.
    CALL prRange                        ; Check every resolved operand value.
    RET  C                              ; Stop before publishing invalid state.
    CALL refBind                        ; Resolve and preflight deferred symbols.
    RET  C                              ; Leave destination untouched.
    JP   prCommit                       ; Commit the complete instruction record.
prRetEof: ; Return the successful non-instruction EOF result.

; EOF is a successful non-instruction result for callers that iterate tokens.

    LD   A,prAtEof                      ; Select the successful EOF status.
    OR   A                              ; Clear carry while preserving nonzero A.
    RET                                 ; Return without an instruction record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY
; Initialise the private ten-byte record to mnemonic 0, three enNone operands
; and zero values. Clear every per-instruction mask and reference count.

prReset: ; Clear the private record and per-instruction masks.
    LD   HL,prRec                       ; Begin at the private mnemonic byte.
    XOR  A                              ; Mnemonic zero is the cleared value.
    LD   (HL),A                         ; Clear the mnemonic slot.
    INC  HL                             ; Advance to operand class zero.
    LD   B,3                            ; Clear all three class slots.
    LD   A,enNone                       ; Missing operands use enNone.
.opLoop: ; Initialise one absent operand class per iteration.
    LD   (HL),A                         ; Mark this operand as absent.
    INC  HL                             ; Advance to the next class slot.
    DJNZ .opLoop                        ; Fill all three operand classes.
    XOR  A                              ; Operand values begin at zero.
    LD   B,6                            ; Three little-endian words follow.
.valLoop: ; Clear the six bytes occupied by operand values.
    LD   (HL),A                         ; Clear one value byte.
    INC  HL                             ; Advance through the value area.
    DJNZ .valLoop                       ; Clear all six value bytes.
    LD   (prOpCnt),A                    ; No operands have been parsed.
    LD   (prWideOk),A                   ; No operand is flexible yet.
    LD   (prCcMask),A                   ; No operand is a condition candidate.
    LD   (prRawCnt),A                   ; No build references exist.
    LD   (prAwait),A                    ; No operand remains unresolved.
    RET                                 ; Return with clean private state.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch one token and translate tokenizer failures into parser status while
; preserving the tokenizer's exact source part and offset.

prNext: ; Fetch a token and adapt lexical failure to parser diagnostics.
    CALL tkNext                         ; Read one complete token.
    RET  NC                             ; Return its successful token unchanged.
    LD   A,(tkErrPos)                   ; Copy the tokenizer's source part.
    LD   (prErrSrc),A                   ; Publish it as the parser error part.
    LD   HL,(tkErrOff)                  ; Copy the tokenizer's byte offset.
    LD   (prErrOff),HL                  ; Preserve the exact failure position.
    LD   A,prLexErr                     ; Report a lexical parser failure.
    SCF                                 ; Mark the result as unsuccessful.
    RET                                 ; Return with the location published.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Select operand A. prClsPtr points at its class byte and prValPtr at its word
; value, allowing all later normalisers to operate on the selected slot.

prSlot: ; Address the class and value fields for operand index A.
    LD   E,A                            ; Use the operand index as a byte offset.
    LD   D,0                            ; Extend it to 16 bits.
    LD   HL,prRec+enOp0                 ; Begin at operand class zero.
    ADD  HL,DE                          ; Select this operand's class byte.
    LD   (prClsPtr),HL                  ; Retain the selected class pointer.
    LD   A,E                            ; Recover the operand index.
    ADD  A,A                            ; Each operand value occupies two bytes.
    LD   E,A                            ; Use the doubled index as its offset.
    LD   HL,prRec+enVal0                ; Begin at operand value zero.
    ADD  HL,DE                          ; Select this operand's value word.
    LD   (prValPtr),HL                  ; Retain the selected value pointer.
    RET                                 ; Return with both pointers installed.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Carry clear identifies token kinds that can begin an expression without a
; leading name or parenthesis. Names and '(' are dispatched separately.

prIsExpr: ; Classify non-name expression starters through carry.
    CP   tkNum                          ; A numeric literal starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   tkHere                         ; `$` starts an address expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   tkPlus                         ; Unary plus starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   tkMinus                        ; Unary minus starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    CP   tkTilde                        ; Bitwise complement starts an expression.
    RET  Z                              ; Return carry clear for this starter.
    SCF                                 ; Reject every other token kind.
    RET                                 ; Return carry set for a non-starter.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one selected operand. Short names first pass through the register and
; condition table. Other names and all numeric starters enter the expression
; evaluator. Parentheses select memory or port syntax.

prOper: ; Choose fixed-word, expression or parenthesised operand parsing.
    LD   A,(tkRecord+tkKindAt)          ; Inspect the operand's first token.
    CP   tkName                         ; Names may be registers or expressions.
    JR   Z,.opName                      ; Try the fixed operand-word table first.
    CALL prIsExpr                       ; Test the non-name expression starters.
    JR   NC,.opExpr                     ; Parse a numeric or unary expression.
    CP   tkLParen                       ; Parentheses introduce memory or a port.
    JP   Z,prParen                      ; Parse the indirect operand form.
    JP   prLackOp                       ; Nothing else can begin an operand.
.opName: ; Test a name as a register or condition before symbol evaluation.
    CALL prMatch                        ; Try fixed operand words.
    JR   C,.opExpr                      ; Treat an unrecognised name as a symbol.

; A recognised word supplies a provisional class. Most are final, but C
; remains ambiguous with condition C until form validation.

    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   (HL),A                         ; Store the provisional operand class.
    LD   (prSavCls),A                   ; Keep a copy across token consumption.
    CALL prNext                         ; Advance past the operand word.
    RET  C                              ; Preserve any tokenizer failure.
    LD   A,(prSavCls)                   ; Recover the provisional class.
    CP   enRegAF                        ; Only AF accepts a following apostrophe.
    JR   NZ,.opParsed                   ; Other operand words are complete.

; AF followed immediately by apostrophe becomes the alternate register pair.

    LD   A,(tkRecord+tkKindAt)          ; Inspect the token following AF.
    CP   tkApost                        ; Does it select the alternate pair?
    JR   NZ,.opParsed                   ; Leave ordinary AF unchanged.
    LD   HL,(prClsPtr)                  ; Reopen the selected class slot.
    LD   (HL),enAltAF                   ; Replace AF with the AF' class.
    JR   prNext                         ; Consume the apostrophe and continue.
.opParsed: ; Finish a recognised register or condition operand.
    XOR  A                              ; Clear carry for a parsed fixed operand.
    RET                                 ; Leave the next token in tkRecord.
.opExpr: ; Evaluate an operand as a provisional numeric expression.

; Expressions start as a generic number. Mnemonic-specific normalisation later
; chooses immediate width, relative, displacement, bit, mode or restart class.

    CALL prEval                         ; Evaluate or defer the source expression.
    RET  C                              ; Preserve its exact diagnostic.
    LD   A,prAnyNum                     ; Mark it as a generic numeric operand.
    LD   HL,(prClsPtr)                  ; Address the selected class slot.
    LD   (HL),A                         ; Store the generic class.
    XOR  A                              ; Return success with carry clear.
    RET                                 ; Leave the following token in tkRecord.
