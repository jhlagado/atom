;==============================================================================
;  Instruction and operand parser
;==============================================================================
;
;  PURPOSE
;  -------
;  Recognise one mnemonic, parse up to three operands and build the encoder's
;  ten-byte instruction record. The form layer completes validation and commits
;  the record only after the entire source instruction is valid.
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
;  six-byte packed key, signed-byte addend, operand index, transform and source
;  position. Validation and patch-field location happen before the symbol arena
;  changes. The successful parser then publishes at most two nine-byte reference
;  descriptions. Two are sufficient for `LD (IX+DISP),IMMEDIATE`, the only Z80
;  shape with two independently patchable fields.
;
;  The caller's instruction record is a commit destination: syntax, form,
;  range, symbol and reference failures leave it unchanged. Missing symbols are
;  inserted only after the whole form and the exact shared-arena capacity have
;  passed. Pending records are still deferred until PR_QREFE, after output has
;  accepted the encoded IMAGE bytes.
;
;  ABI AND OWNERSHIP
;  -----------------
;
;  Both entries preserve the caller's stack balance and may clobber every main
;  register except SP. They use fixed state declared in forms.asm and therefore
;  are not reentrant. The destination is caller-owned; symbol and pending arenas
;  belong to the build descriptor managed by the driver.

PR_CBEG:

; Public parser statuses returned in A. PR_SPCAP is retained in the ABI but the
; current eight-bit source-part ordinal needs no parser-side capacity check.

PR_SOK EQU 0
PR_SEOF EQU 1
PR_SLEXI EQU 2
PR_SEMNE EQU 3
PR_SUMNE EQU 4
PR_SEOP EQU 5
PR_SUOP EQU 6
PR_SEDEL EQU 7
PR_STMOP EQU 8
PR_SIFOR EQU 9
PR_SVRAN EQU 10
PR_SRRAN EQU 11
PR_SINT EQU 12
PR_SEXPR EQU 13
PR_SUNPA EQU 14
PR_SSYM EQU 15
PR_SRCAP EQU 16
PR_SPCAP EQU 17

; Reference and record geometry. The build form contains a packed key; the
; public form replaces it with a symbol-record pointer and omits build-only data.

PR_RCAP EQU 2
PR_BRB EQU 13
PR_PRB EQU 9
PR_BKEY EQU 0
PR_BADDE EQU 6
PR_BLDOP EQU 7
PR_BKIND EQU 8
PR_BPOFF EQU 9
PR_BPART EQU 10
PR_BSOFF EQU 11
PR_RSYM EQU 0
PR_RADDE EQU 2
PR_REFOP EQU 3
PR_RKIND EQU 4
PR_RPOFF EQU 5
PR_RPART EQU 6
PR_RSOFF EQU 7

; Temporary operand classes used before mnemonic-specific normalisation.

PR_GNUMB EQU 240
PR_GPNUM EQU 241
PR_GC EQU 242

;@ROUTINE IN A,BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Enter after the statement layer has recognised and consumed the mnemonic. A
; is its ordinal and TK_REC already contains the first operand or EOL.

PR_PUB:
    PUSH AF                         ; Preserve the recognised mnemonic ordinal.
    LD   (PR_IADR),BC               ; Retain the logical address used by `$`.
    LD   (PR_DST),DE                ; Remember the caller's commit destination.
    XOR  A                          ; Start with no published references.
    LD   (PR_RCNT),A                ; Clear the public-reference count.
    CALL PR_ISCRA                   ; Reset the private instruction record.
    POP  AF                         ; Recover the mnemonic ordinal.
    LD   (PR_SCRAT+EN_MNEM),A       ; Begin the record with that mnemonic.
    JR   PR_POPER                   ; Parse the token already in TK_REC.

;@ROUTINE IN BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Standalone entry: fetch, diagnose and recognise the mnemonic before joining
; the operand path shared with PR_PUB.

PR_PARSE:
    LD   (PR_IADR),BC               ; Retain the logical instruction address.
    LD   (PR_DST),DE                ; Retain the caller's output record address.
    XOR  A                          ; Start with no published references.
    LD   (PR_RCNT),A                ; Clear the public-reference count.
    CALL PR_ISCRA                   ; Reset all private instruction state.
    CALL PR_NTOK                    ; Fetch the mnemonic token.
    RET  C                          ; Return an exact tokenizer failure.
    LD   A,(TK_REC+TK_KOFF)         ; Inspect the token kind.
    CP   TK_EOF                     ; Did the source stream finish cleanly?
    JR   Z,PR_EOF                   ; Report successful end of input.
    CP   TK_NAME                    ; A mnemonic must be a name token.
    JP   NZ,PR_EMNEM                ; Diagnose any other token kind.
    LD   A,(TK_REC+TK_POFF)         ; Capture the mnemonic's source part.
    LD   (PR_IPART),A               ; Retain it for later diagnostics.
    LD   HL,(TK_REC+TK_SOFF)        ; Capture the mnemonic's source offset.
    LD   (PR_IOFF),HL               ; Retain the complete source position.
    CALL TK_LLEXE                   ; Load the mnemonic text and length.
    CALL EN_RECOG                   ; Translate the name to an ordinal.
    JP   C,PR_UMNEM                 ; Diagnose an unknown mnemonic.
    LD   (PR_SCRAT+EN_MNEM),A       ; Store the recognised mnemonic privately.

; Advance once so the shared path sees the first operand or EOL.

    CALL PR_NTOK                    ; Advance to the first operand or EOL.
    RET  C                          ; Preserve any tokenizer failure.
PR_POPER:

; Zero operands are valid candidates; the encoder validator decides whether the
; selected mnemonic permits them.

    LD   A,(TK_REC+TK_KOFF)         ; Inspect the first unconsumed token.
    CP   TK_EOL                     ; Is this a zero-operand instruction?
    JR   Z,PR_POPE1                 ; Validate the empty operand list.
PR_OLOOP:

; Select class/value slots for the next operand before parsing it. A fourth
; operand fails before any out-of-record pointer can be formed.

    LD   A,(PR_OPCNT)               ; Select the next operand index.
    CP   3                          ; The instruction record has three slots.
    JP   NC,PR_TMOPE                ; Refuse a fourth operand safely.
    CALL PR_SOP                     ; Point at this operand's class and value.
    CALL PR_POP                     ; Parse and classify the source operand.
    RET  C                          ; Stop on its precise diagnostic.
    LD   HL,PR_OPCNT                ; Address the operand count.
    INC  (HL)                       ; Publish one more private operand.

; Each parsed operand must be followed by EOL or a comma. A trailing comma is a
; distinct expected-operand error.

    LD   A,(TK_REC+TK_KOFF)         ; Inspect the delimiter after the operand.
    CP   TK_EOL                     ; Has the operand list ended?
    JR   Z,PR_POPE1                 ; Begin whole-record normalisation.
    CP   TK_COMMA                   ; Otherwise require a comma.
    JP   NZ,PR_EDELI                ; Diagnose the unexpected delimiter.
    CALL PR_NTOK                    ; Consume the comma and fetch the next token.
    RET  C                          ; Preserve any tokenizer failure.
    LD   A,(TK_REC+TK_KOFF)         ; Inspect the token after the comma.
    CP   TK_EOL                     ; A comma cannot terminate the line.
    JP   Z,PR_EXPOP                 ; Report the missing operand.
    JR   PR_OLOOP                   ; Parse the next operand.
PR_POPE1:

; Normalisation proceeds from source conveniences to an exact encoder record:
; accumulator aliases, numeric classes, candidate form selection, concrete
; ranges, deferred patch fields and finally destination commit.

    CALL PR_NAALI                   ; Normalise explicit-accumulator aliases.
    RET  C                          ; Reject a missing required accumulator.
    CALL PR_NNUMB                   ; Assign provisional numeric classes.
    RET  C                          ; Stop on a numeric range error.
    CALL PR_VCAND                   ; Validate the completed instruction form.
    RET  C                          ; Return the parser's invalid-form diagnostic.
    LD   (PR_ILEN),A                ; Retain the validated encoded length.
    CALL PR_CCVAL                   ; Check every resolved operand value.
    RET  C                          ; Stop before publishing invalid state.
    CALL PR_FREFE                   ; Resolve and preflight deferred symbols.
    RET  C                          ; Leave the destination untouched on failure.
    JP   PR_CMT                     ; Commit the complete instruction record.
PR_EOF:

; EOF is a successful non-instruction result for callers that iterate tokens.

    LD   A,PR_SEOF                  ; Select the successful EOF status.
    OR   A                          ; Clear carry while preserving nonzero A.
    RET                             ; Return without an instruction record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY
; Initialise the private ten-byte record to mnemonic 0, three EN_NONE operands
; and zero values. Clear every per-instruction mask and reference count.

PR_ISCRA:
    LD   HL,PR_SCRAT                ; Begin at the private mnemonic byte.
    XOR  A                          ; Mnemonic zero is the cleared value.
    LD   (HL),A                     ; Clear the mnemonic slot.
    INC  HL                         ; Advance to operand class zero.
    LD   B,3                        ; Clear all three class slots.
    LD   A,EN_NONE                  ; Missing operands use EN_NONE.
.IOPERAND:
    LD   (HL),A                     ; Mark this operand as absent.
    INC  HL                         ; Advance to the next class slot.
    DJNZ .IOPERAND                  ; Fill all three operand classes.
    XOR  A                          ; Operand values begin at zero.
    LD   B,6                        ; Three little-endian words follow.
.IVALUES:
    LD   (HL),A                     ; Clear one value byte.
    INC  HL                         ; Advance through the value area.
    DJNZ .IVALUES                   ; Clear all six value bytes.
    LD   (PR_OPCNT),A               ; No operands have been parsed.
    LD   (PR_FMASK),A               ; No operand is flexible yet.
    LD   (PR_CMASK),A               ; No operand is a condition candidate.
    LD   (PR_RBCNT),A               ; No build references exist.
    LD   (PR_UMASK),A               ; No operand remains unresolved.
    RET                             ; Return with clean private state.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch one token and translate tokenizer failures into parser status while
; preserving the tokenizer's exact source part and offset.

PR_NTOK:
    CALL TK_NEXT                    ; Ask the tokenizer for one complete token.
    RET  NC                         ; Return its successful token unchanged.
    LD   A,(TK_EPART)               ; Copy the tokenizer's source part.
    LD   (PR_EPART),A               ; Publish it as the parser error part.
    LD   HL,(TK_EOFF)               ; Copy the tokenizer's byte offset.
    LD   (PR_EOFF),HL               ; Preserve the exact failure position.
    LD   A,PR_SLEXI                 ; Report a lexical parser failure.
    SCF                             ; Mark the result as unsuccessful.
    RET                             ; Return with the location published.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Select operand A. PR_CPTR points at its class byte and PR_VPTR at its word
; value, allowing all later normalisers to operate on the selected slot.

PR_SOP:
    LD   E,A                        ; Use the operand index as a byte offset.
    LD   D,0                        ; Widen it for sixteen-bit address arithmetic.
    LD   HL,PR_SCRAT+EN_OP0         ; Begin at operand class zero.
    ADD  HL,DE                      ; Select this operand's class byte.
    LD   (PR_CPTR),HL               ; Retain the selected class pointer.
    LD   A,E                        ; Recover the operand index.
    ADD  A,A                        ; Each operand value occupies two bytes.
    LD   E,A                        ; Use the doubled index as its offset.
    LD   HL,PR_SCRAT+EN_VAL0        ; Begin at operand value zero.
    ADD  HL,DE                      ; Select this operand's value word.
    LD   (PR_VPTR),HL               ; Retain the selected value pointer.
    RET                             ; Return with both pointers installed.

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Carry clear identifies token kinds that can begin an expression without a
; leading name or parenthesis. Names and '(' are dispatched separately.

PR_IESTA:
    CP   TK_NUMBE                   ; A numeric literal starts an expression.
    RET  Z                          ; Return carry clear for this starter.
    CP   TK_CUR                     ; `$` starts an address expression.
    RET  Z                          ; Return carry clear for this starter.
    CP   TK_PLUS                    ; Unary plus starts an expression.
    RET  Z                          ; Return carry clear for this starter.
    CP   TK_MINUS                   ; Unary minus starts an expression.
    RET  Z                          ; Return carry clear for this starter.
    CP   TK_TILDE                   ; Bitwise complement starts an expression.
    RET  Z                          ; Return carry clear for this starter.
    SCF                             ; Reject every other token kind.
    RET                             ; Return carry set for a non-starter.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one selected operand. Short names first pass through the register and
; condition table. Other names and all numeric starters enter the expression
; evaluator. Parentheses select memory or port syntax.

PR_POP:
    LD   A,(TK_REC+TK_KOFF)         ; Inspect the operand's first token.
    CP   TK_NAME                    ; Names may be registers or expressions.
    JR   Z,.OPNAME                  ; Try the fixed operand-word table first.
    CALL PR_IESTA                   ; Test the non-name expression starters.
    JR   NC,.OPEXPR                 ; Parse a numeric or unary expression.
    CP   TK_LPARE                   ; Parentheses introduce memory or a port.
    JP   Z,PR_PMEMO                 ; Parse the indirect operand form.
    JP   PR_EXPOP                   ; Nothing else can begin an operand.
.OPNAME:
    CALL PR_LOW                     ; Try registers, conditions and special words.
    JR   C,.OPEXPR                  ; Treat an unrecognised name as a symbol.

; A recognised word supplies a provisional operand class. Most are final, but C
; remains ambiguous with condition C until form validation.

    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   (HL),A                     ; Store the provisional operand class.
    LD   (PR_LCLAS),A               ; Keep a copy across token consumption.
    CALL PR_NTOK                    ; Advance past the operand word.
    RET  C                          ; Preserve any tokenizer failure.
    LD   A,(PR_LCLAS)               ; Recover the provisional class.
    CP   EN_AF                      ; Only AF accepts a following apostrophe.
    JR   NZ,.OPPARSED               ; Other operand words are complete.

; AF followed immediately by apostrophe becomes the alternate register pair.

    LD   A,(TK_REC+TK_KOFF)         ; Inspect the token following AF.
    CP   TK_APOST                   ; Does it select the alternate pair?
    JR   NZ,.OPPARSED               ; Leave ordinary AF unchanged.
    LD   HL,(PR_CPTR)               ; Reopen the selected class slot.
    LD   (HL),EN_APRIM              ; Replace AF with the AF' class.
    JR   PR_NTOK                    ; Consume the apostrophe and continue.
.OPPARSED:
    XOR  A                          ; Clear carry for a parsed fixed operand.
    RET                             ; Leave the next token in TK_REC.
.OPEXPR:

; Expressions start as a generic number. Mnemonic-specific normalisation later
; chooses immediate width, relative, displacement, bit, mode or restart class.

    CALL PR_PEXPR                   ; Evaluate or defer the source expression.
    RET  C                          ; Preserve its exact diagnostic.
    LD   A,PR_GNUMB                 ; Mark it as a generic numeric operand.
    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   (HL),A                     ; Store the generic class for normalisation.
    XOR  A                          ; Return success with carry clear.
    RET                             ; Leave the following token in TK_REC.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Evaluate with caller-managed symbol publication. BC gives '$' its instruction
; address. Resolved values go directly to the selected value slot; unresolved
; values first become private build-reference records.

PR_PEXPR:
    LD   BC,(PR_IADR)               ; Supply `$` with the instruction address.
    CALL EX_PDEFR                   ; Parse with deferred symbol publication.
    JR   C,PR_EFAIL                 ; Translate an expression diagnostic.
    CP   EX_UNRES                   ; Did evaluation depend on a missing symbol?
    JR   Z,PR_AREF                  ; Build a private deferred reference.

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS DE,SIGN,PARITY,HALFCARRY,A
; Store the concrete word in HL at the selected operand value pointer.

PR_SHVAL:
    LD   DE,(PR_VPTR)               ; Load the selected value-slot address.
    LD   A,L                        ; Take the value's low byte.
    LD   (DE),A                     ; Store it in little-endian order.
    INC  DE                         ; Advance to the high byte.
    LD   A,H                        ; Take the value's high byte.
    LD   (DE),A                     ; Complete the stored word.
    XOR  A                          ; Return success with carry clear.
    RET                             ; Preserve the selected class slot.

;@ROUTINE IN IX,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX
; Append one thirteen-byte build reference. IX points at the expression key and
; HL carries its signed addend. The entry also captures operand index, transform
; and the evaluator's retained symbol position. The unresolved mask prevents
; concrete range checks from inspecting the placeholder zero value.

PR_AREF:
    LD   (PR_RASCR),HL              ; Save the expression's signed addend.
    LD   A,(PR_RBCNT)               ; Read the private reference count.
    CP   PR_RCAP                    ; Is another build record available?
    JR   NC,PR_RCFAI                ; Diagnose the impossible third reference.
    CALL PR_BRADR                   ; Address the next build-reference record.
    PUSH IX                         ; Move the expression key pointer to HL.
    POP  HL                         ; HL now addresses the packed symbol key.
    LD   BC,6                       ; A packed symbol key occupies six bytes.
    LDIR                            ; Copy the key and advance DE after it.
    LD   HL,(PR_RASCR)              ; Recover the signed expression addend.
    LD   A,L                        ; References retain its low byte only.
    LD   (DE),A                     ; Append the signed-byte addend.
    INC  DE                         ; Advance to the operand index.
    LD   A,(PR_OPCNT)               ; Identify the current operand slot.
    LD   (DE),A                     ; Append that operand index.
    INC  DE                         ; Advance to the transform kind.
    LD   A,(EX_RUNRE)               ; Read the unresolved expression transform.
    LD   (DE),A                     ; Append the transform for later resolution.
    INC  DE                         ; Advance to the provisional patch offset.

; The expression transform is retained as the provisional kind. The byte offset
; remains zero until validation and PT_LOCAT identify the encoded field.

    XOR  A                          ; The patch field is not known yet.
    LD   (DE),A                     ; Initialise its byte offset to zero.
    INC  DE                         ; Advance to the source-part ordinal.
    LD   A,(EX_SPART)               ; Read the missing symbol's source part.
    LD   (DE),A                     ; Append it for an exact diagnostic.
    INC  DE                         ; Advance to the source offset.
    LD   HL,(EX_SOFF)               ; Read the missing symbol's source offset.
    LD   A,L                        ; Take its low byte.
    LD   (DE),A                     ; Store the offset little-endian.
    INC  DE                         ; Advance to the high byte.
    LD   A,H                        ; Take the source offset's high byte.
    LD   (DE),A                     ; Complete the build-reference record.
    LD   A,(PR_OPCNT)               ; Recover the unresolved operand index.
    CALL PR_IBIT                    ; Convert it to a one-bit mask.
    LD   HL,PR_UMASK                ; Address the unresolved-operand mask.
    OR   (HL)                       ; Preserve earlier unresolved operands.
    LD   (HL),A                     ; Mark this operand unresolved.
    LD   HL,PR_RBCNT                ; Address the build-reference count.
    INC  (HL)                       ; Publish the new private record.

; Store a zero placeholder in the instruction record. Encoding happens before
; the final value exists and the pending patch will replace its field later.

    LD   HL,0                       ; Use zero until the symbol resolves.
    JR   PR_SHVAL                   ; Store the placeholder and return success.
PR_RCFAI:

; The Z80 form census proves that no valid instruction needs more than two
; deferred fields. Reaching a third is a diagnosed parser-capacity failure.

    LD   A,PR_SRCAP                 ; Select reference-capacity status.
    JP   PR_FESYM                   ; Fail at the unresolved symbol position.

;@ROUTINE IN A OUT DE CLOBBERS HL,A,F
; Return the address of build-reference A. Each record is thirteen bytes and the
; capacity is two, so a single conditional add selects the second record.

PR_BRADR:
    LD   DE,PR_RBLD                 ; Begin at build-reference record zero.
    OR   A                          ; Is record zero requested?
    RET  Z                          ; Return its base directly.
    LD   HL,PR_BRB                  ; Load the thirteen-byte record stride.
    ADD  HL,DE                      ; Advance to build-reference record one.
    EX   DE,HL                      ; Return its address in DE.
    RET                             ; A cannot exceed one at this call site.
PR_EFAIL:

; Preserve the nested expression status and exact expression error location,
; then return the parser's expression category.

    LD   (PR_ESTA1),A               ; Retain the expression subsystem status.
    LD   A,(EX_EPART)               ; Copy its source-part ordinal.
    LD   (PR_EPART),A               ; Publish the parser error part.
    LD   HL,(EX_EOFF)               ; Copy its source byte offset.
    LD   (PR_EOFF),HL               ; Publish the parser error offset.
    LD   A,PR_SEXPR                 ; Select the parser expression category.
    LD   (PR_ESTAT),A               ; Retain the public parser status.
    SCF                             ; Mark the parse as failed.
    RET                             ; Return both category and nested detail.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise short operand words such as registers and conditions. The tokenizer
; lexeme is packed case-insensitively and scanned against exact RADIX-40 values.
; Names of four or more characters cannot be operand words and fall through to
; expression parsing as symbols.

PR_LOW:
    CALL TK_LLEXE                   ; Load the current name text and length.
    CP   4                          ; Operand words contain at most three chars.
    JR   NC,.UOP                    ; Longer names can only be symbols.
    LD   DE,PR_NKEY                 ; Select the temporary packed-key buffer.
    CALL EN_R40PK                   ; Pack the name case-insensitively.
    JR   C,.UOP                     ; Treat an unrepresentable name as a symbol.
    LD   DE,(PR_NKEY)               ; Load the packed operand word.
    LD   HL,PR_OWTAB                ; Begin the exact operand-word table.
    LD   B,PR_OWCNT                 ; Scan every table entry at most once.
.LOLOOP:

; Each table entry is packed word followed by provisional operand class.

    LD   A,(HL)                     ; Read the packed low byte.
    CP   E                          ; Compare it with the source key.
    INC  HL                         ; Advance to the packed high byte.
    JR   NZ,.LOSHI                  ; Skip its comparison after a low mismatch.
    LD   A,(HL)                     ; Read the packed high byte.
    CP   D                          ; Compare it with the source key.
    JR   Z,.LOFOUND                 ; Both bytes identify the operand word.
.LOSHI:
    INC  HL                         ; Advance beyond the packed high byte.
    INC  HL                         ; Skip the associated operand class.
    DJNZ .LOLOOP                    ; Continue through the fixed table.
.UOP:
    LD   A,PR_SUOP                  ; Select unknown-operand status.
    JP   PR_FHERE                   ; Fail at the current token's position.
.LOFOUND:
    INC  HL                         ; Advance from the high byte to its class.
    LD   A,(HL)                     ; Return the provisional operand class.
    OR   A                          ; Clear carry for a recognised word.
    RET                             ; Leave the word token unconsumed.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a parenthesised operand after the opening '(' has been seen. The first
; inner token distinguishes a concrete memory/port word from an absolute
; expression or an IX/IY displacement expression.

PR_PMEMO:
    CALL PR_NTOK                    ; Consume '(' and fetch its first token.
    RET  C                          ; Preserve any tokenizer failure.
    LD   A,(TK_REC+TK_KOFF)         ; Inspect the first token inside parentheses.
    CALL PR_IESTA                   ; Does it begin a numeric expression?
    JR   NC,.MEXPR                  ; Parse the parenthesised expression.
    CP   TK_LPARE                   ; Expressions may start with another '('.
    JR   Z,.MEXPR                   ; Delegate nested parentheses to EX_PDEFR.
    CP   TK_NAME                    ; Fixed indirect bases are name tokens.
    JP   NZ,PR_EXPOP                ; Diagnose any other operand starter.
    CALL PR_LOW                     ; Recognise C, BC, DE, HL, SP, IX or IY.
    JR   C,.MEXPR                   ; Treat any other name as a symbol.

; Save the provisional base class before consuming its token.

    LD   (PR_MBASE),A               ; Preserve the base across token advance.
    CALL PR_NTOK                    ; Consume the base name.
    RET  C                          ; Preserve any tokenizer failure.
    LD   A,(PR_MBASE)               ; Recover the provisional base class.
    CP   PR_GC                      ; Was the ambiguous word C selected?
    JR   Z,.MPC                     ; Inside parentheses C means port C.
    CP   EN_BC                      ; Was register pair BC selected?
    JR   Z,.MEMORYBC                ; Convert it to indirect-memory BC.
    CP   EN_DE                      ; Was register pair DE selected?
    JR   Z,.MEMORYDE                ; Convert it to indirect-memory DE.
    CP   EN_HL                      ; Was register pair HL selected?
    JR   Z,.MEMORYHL                ; Convert it to indirect-memory HL.
    CP   EN_SP                      ; Was stack pointer SP selected?
    JR   Z,.MEMORYSP                ; Convert it to indirect-memory SP.
    CP   EN_IX                      ; Was index register IX selected?
    JR   Z,.MEMORYIX                ; Parse its optional displacement.
    CP   EN_IY                      ; Was index register IY selected?
    JR   Z,.MEMORYIY                ; Parse its optional displacement.
    JP   PR_UOP                     ; No other operand word may be indirect.
.MEXPR:

; A parenthesised expression becomes a generic memory number. IN and OUT later
; reinterpret this class as an eight-bit immediate port; other forms use an
; absolute-memory word.

    CALL PR_PEXPR                   ; Evaluate or defer the inner expression.
    RET  C                          ; Preserve its exact diagnostic.
    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   (HL),PR_GPNUM              ; Mark a generic parenthesised number.
    JR   PR_RRPAR                   ; Require and consume the closing ')'.
.MPC:

; `(C)` is the indirect port class, distinct from ordinary register C.

    LD   A,EN_PORTC                 ; Select the indirect port-C class.
    JR   .MSIMPLE                   ; Store it and require ')'.
.MEMORYBC:
    LD   A,EN_MEMBC                 ; Select the indirect BC class.
    JR   .MSIMPLE                   ; Store it and require ')'.
.MEMORYDE:
    LD   A,EN_MEMDE                 ; Select the indirect DE class.
    JR   .MSIMPLE                   ; Store it and require ')'.
.MEMORYHL:
    LD   A,EN_MEMHL                 ; Select the indirect HL class.
    JR   .MSIMPLE                   ; Store it and require ')'.
.MEMORYSP:
    LD   A,EN_MEMSP                 ; Select the indirect SP class.
.MSIMPLE:

; Store the fixed indirect class and require the closing parenthesis.

    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   (HL),A                     ; Store the fixed indirect class.
    JR   PR_RRPAR                   ; Require and consume the closing ')'.
.MEMORYIX:

; B retains the dedicated JP (IX) memory class. PR_ICLAS is the ordinary indexed
; class used for displacement-bearing forms and the zero-displacement alias.

    LD   B,EN_MEMIX                 ; Retain the dedicated JP (IX) class.
    LD   A,EN_IIX                   ; Select ordinary indexed-memory IX.
    LD   (PR_ICLAS),A               ; Retain it across displacement parsing.
    JR   .MINDEX                    ; Inspect the token after IX.
.MEMORYIY:
    LD   B,EN_MEMIY                 ; Retain the dedicated JP (IY) class.
    LD   A,EN_IIY                   ; Select ordinary indexed-memory IY.
    LD   (PR_ICLAS),A               ; Retain it across displacement parsing.
.MINDEX:

; A closing ')' is the implicit displacement-zero form. Otherwise only '+' or
; '-' may introduce the displacement expression.

    LD   A,(TK_REC+TK_KOFF)         ; Inspect the token after IX or IY.
    CP   TK_RPARE                   ; Is the displacement omitted?
    JR   Z,.MIPLAIN                 ; Use the implicit zero displacement.
    CP   TK_PLUS                    ; A plus may introduce the displacement.
    JR   Z,.MIEXPR                  ; Parse it as an expression.
    CP   TK_MINUS                   ; A minus may also introduce it.
    JP   NZ,PR_EDELI                ; Reject every other delimiter.
.MIEXPR:
    CALL PR_PEXPR                   ; Evaluate the signed displacement.
    RET  C                          ; Preserve its exact diagnostic.
    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   A,(PR_ICLAS)               ; Recover the IX/IY indexed class.
    LD   (HL),A                     ; Store the displacement-bearing class.
    JR   PR_RRPAR                   ; Require and consume the closing ')'.
.MIPLAIN:

; JP (IX/IY) uses the encoder's dedicated memory class. Other instructions use
; the ordinary indexed class with the already-zero value slot.

    LD   HL,(PR_CPTR)               ; Address the selected class slot.
    LD   A,(PR_SCRAT+EN_MNEM)       ; Read the current mnemonic ordinal.
    CP   AT_MJP                     ; Does JP require its dedicated class?
    LD   A,B                        ; Prepare the JP (IX/IY) class.
    JR   Z,.MIPSTORE                ; Keep it only for JP.
    LD   A,(PR_ICLAS)               ; Other mnemonics use indexed displacement 0.
.MIPSTORE:
    LD   (HL),A                     ; Publish the final indirect class.
    JP   PR_NTOK                    ; Consume ')' and fetch the next token.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Require and consume the closing ')' for an expression or fixed indirect form.

PR_RRPAR:
    LD   A,(TK_REC+TK_KOFF)         ; Inspect the unconsumed delimiter.
    CP   TK_RPARE                   ; Require a closing parenthesis.
    JP   NZ,PR_EDELI                ; Diagnose any other delimiter.
    JP   PR_NTOK                    ; Consume ')' and fetch the next token.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Copy the tokenizer's numeric word to the selected value slot. This retained
; helper has no caller in the current parser path.

PR_STVAL:
    LD   HL,(TK_REC+TK_VOFF)        ; Load the tokenizer's numeric value.
    JP   PR_SHVAL                   ; Store it in the selected operand slot.
