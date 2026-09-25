;==============================================================================
;  Instruction and operand parser
;==============================================================================
;
;  Convert one source instruction into the encoder's ten-byte record. The parser
;  recognises a mnemonic, classifies up to three operands, normalises ambiguous
;  source forms, validates the complete record and then publishes any deferred
;  symbol descriptions required by the output layer.
;
;  Principal entries:
;    PR_PARSE  fetch a mnemonic, parse its operands and commit the record
;    PR_PUB    parse operands for a mnemonic already recognised by statements
;    PR_CREFE  preflight pending capacity before instruction bytes are emitted
;    PR_QREFE  queue references after every instruction byte is accepted
;
;  PR_PARSE receives BC = logical instruction address and DE = ten-byte
;  destination. It begins by fetching the mnemonic token. PR_PUB additionally
;  receives the mnemonic ordinal in A and begins with TK_REC already holding the
;  first operand or EOL. Successful calls return carry clear, A = PR_SOK and IX
;  pointing at the committed destination. PR_PARSE returns PR_SEOF with carry
;  clear when the fetched token is EOF.
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
    PUSH AF
    LD   (PR_IADR),BC
    LD   (PR_DST),DE
    XOR  A
    LD   (PR_RCNT),A
    CALL PR_ISCRA
    POP  AF
    LD   (PR_SCRAT+EN_MNEM),A
    JR   PR_POPER

;@ROUTINE IN BC,DE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Standalone entry: fetch, diagnose and recognise the mnemonic before joining
; the operand path shared with PR_PUB.

PR_PARSE:
    LD   (PR_IADR),BC
    LD   (PR_DST),DE
    XOR  A
    LD   (PR_RCNT),A
    CALL PR_ISCRA
    CALL PR_NTOK
    RET  C
    LD   A,(TK_REC+TK_KOFF)
    CP   TK_EOF
    JR   Z,PR_EOF
    CP   TK_NAME
    JP   NZ,PR_EMNEM
    LD   A,(TK_REC+TK_POFF)
    LD   (PR_IPART),A
    LD   HL,(TK_REC+TK_SOFF)
    LD   (PR_IOFF),HL
    CALL TK_LLEXE
    CALL EN_RECOG
    JP   C,PR_UMNEM
    LD   (PR_SCRAT+EN_MNEM),A

; Advance once so the shared path sees the first operand or EOL.

    CALL PR_NTOK
    RET  C
PR_POPER:

; Zero operands are valid candidates; the encoder validator decides whether the
; selected mnemonic permits them.

    LD   A,(TK_REC+TK_KOFF)
    CP   TK_EOL
    JR   Z,PR_POPE1
PR_OLOOP:

; Select class/value slots for the next operand before parsing it. A fourth
; operand fails before any out-of-record pointer can be formed.

    LD   A,(PR_OPCNT)
    CP   3
    JP   NC,PR_TMOPE
    CALL PR_SOP
    CALL PR_POP
    RET  C
    LD   HL,PR_OPCNT
    INC  (HL)

; Each parsed operand must be followed by EOL or a comma. A trailing comma is a
; distinct expected-operand error.

    LD   A,(TK_REC+TK_KOFF)
    CP   TK_EOL
    JR   Z,PR_POPE1
    CP   TK_COMMA
    JP   NZ,PR_EDELI
    CALL PR_NTOK
    RET  C
    LD   A,(TK_REC+TK_KOFF)
    CP   TK_EOL
    JP   Z,PR_EXPOP
    JR   PR_OLOOP
PR_POPE1:

; Normalisation proceeds from source conveniences to an exact encoder record:
; accumulator aliases, numeric classes, candidate form selection, concrete
; ranges, deferred patch fields and finally destination commit.

    CALL PR_NAALI
    RET  C
    CALL PR_NNUMB
    RET  C
    CALL PR_VCAND
    RET  C
    LD   (PR_ILEN),A
    CALL PR_CCVAL
    RET  C
    CALL PR_FREFE
    RET  C
    JP   PR_CMT
PR_EOF:

; EOF is a successful non-instruction result for callers that iterate tokens.

    LD   A,PR_SEOF
    OR   A
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,B,HL,SIGN,PARITY,HALFCARRY
; Initialise the private ten-byte record to mnemonic 0, three EN_NONE operands
; and zero values. Clear every per-instruction mask and reference count.

PR_ISCRA:
    LD   HL,PR_SCRAT
    XOR  A
    LD   (HL),A
    INC  HL
    LD   B,3
    LD   A,EN_NONE
.IOPERAND:
    LD   (HL),A
    INC  HL
    DJNZ .IOPERAND
    XOR  A
    LD   B,6
.IVALUES:
    LD   (HL),A
    INC  HL
    DJNZ .IVALUES
    LD   (PR_OPCNT),A
    LD   (PR_FMASK),A
    LD   (PR_CMASK),A
    LD   (PR_RBCNT),A
    LD   (PR_UMASK),A
    RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Fetch one token and translate tokenizer failures into parser status while
; preserving the tokenizer's exact source part and offset.

PR_NTOK:
    CALL TK_NEXT
    RET  NC
    LD   A,(TK_EPART)
    LD   (PR_EPART),A
    LD   HL,(TK_EOFF)
    LD   (PR_EOFF),HL
    LD   A,PR_SLEXI
    SCF
    RET

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Select operand A. PR_CPTR points at its class byte and PR_VPTR at its word
; value, allowing all later normalisers to operate on the selected slot.

PR_SOP:
    LD   E,A
    LD   D,0
    LD   HL,PR_SCRAT+EN_OP0
    ADD  HL,DE
    LD   (PR_CPTR),HL
    LD   A,E
    ADD  A,A
    LD   E,A
    LD   HL,PR_SCRAT+EN_VAL0
    ADD  HL,DE
    LD   (PR_VPTR),HL
    RET

;@ROUTINE IN A OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
; Carry clear identifies token kinds that can begin an expression without a
; leading name or parenthesis. Names and '(' are dispatched separately.

PR_IESTA:
    CP   TK_NUMBE
    RET  Z
    CP   TK_CUR
    RET  Z
    CP   TK_PLUS
    RET  Z
    CP   TK_MINUS
    RET  Z
    CP   TK_TILDE
    RET  Z
    SCF
    RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one selected operand. Short names first pass through the register and
; condition table. Other names and all numeric starters enter the expression
; evaluator. Parentheses select memory or port syntax.

PR_POP:
    LD   A,(TK_REC+TK_KOFF)
    CP   TK_NAME
    JR   Z,.OPNAME
    CALL PR_IESTA
    JR   NC,.OPEXPR
    CP   TK_LPARE
    JP   Z,PR_PMEMO
    JP   PR_EXPOP
.OPNAME:
    CALL PR_LOW
    JR   C,.OPEXPR

; A recognised word supplies a provisional operand class. Most are final, but C
; remains ambiguous with condition C until form validation.

    LD   HL,(PR_CPTR)
    LD   (HL),A
    LD   (PR_LCLAS),A
    CALL PR_NTOK
    RET  C
    LD   A,(PR_LCLAS)
    CP   EN_AF
    JR   NZ,.OPPARSED

; AF followed immediately by apostrophe becomes the alternate register pair.

    LD   A,(TK_REC+TK_KOFF)
    CP   TK_APOST
    JR   NZ,.OPPARSED
    LD   HL,(PR_CPTR)
    LD   (HL),EN_APRIM
    JR   PR_NTOK
.OPPARSED:
    XOR  A
    RET
.OPEXPR:

; Expressions start as a generic number. Mnemonic-specific normalisation later
; chooses immediate width, relative, displacement, bit, mode or restart class.

    CALL PR_PEXPR
    RET  C
    LD   A,PR_GNUMB
    LD   HL,(PR_CPTR)
    LD   (HL),A
    XOR  A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Evaluate with caller-managed symbol publication. BC gives '$' its instruction
; address. Resolved values go directly to the selected value slot; unresolved
; values first become private build-reference records.

PR_PEXPR:
    LD   BC,(PR_IADR)
    CALL EX_PDEFR
    JR   C,PR_EFAIL
    CP   EX_UNRES
    JR   Z,PR_AREF

;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS DE,SIGN,PARITY,HALFCARRY,A
; Store the concrete word in HL at the selected operand value pointer.

PR_SHVAL:
    LD   DE,(PR_VPTR)
    LD   A,L
    LD   (DE),A
    INC  DE
    LD   A,H
    LD   (DE),A
    XOR  A
    RET

;@ROUTINE IN IX,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX
; Append one thirteen-byte build reference. IX points at the expression key and
; HL carries its signed addend. The entry also captures operand index, transform
; and the evaluator's retained symbol position. The unresolved mask prevents
; concrete range checks from inspecting the placeholder zero value.

PR_AREF:
    LD   (PR_RASCR),HL
    LD   A,(PR_RBCNT)
    CP   PR_RCAP
    JR   NC,PR_RCFAI
    CALL PR_BRADR
    PUSH IX
    POP  HL
    LD   BC,6
    LDIR
    LD   HL,(PR_RASCR)
    LD   A,L
    LD   (DE),A
    INC  DE
    LD   A,(PR_OPCNT)
    LD   (DE),A
    INC  DE
    LD   A,(EX_RUNRE)
    LD   (DE),A
    INC  DE

; The expression transform is retained as the provisional kind. The byte offset
; remains zero until validation and PT_LOCAT identify the encoded field.

    XOR  A
    LD   (DE),A
    INC  DE
    LD   A,(EX_SPART)
    LD   (DE),A
    INC  DE
    LD   HL,(EX_SOFF)
    LD   A,L
    LD   (DE),A
    INC  DE
    LD   A,H
    LD   (DE),A
    LD   A,(PR_OPCNT)
    CALL PR_IBIT
    LD   HL,PR_UMASK
    OR   (HL)
    LD   (HL),A
    LD   HL,PR_RBCNT
    INC  (HL)

; Store a zero placeholder in the instruction record. Encoding happens before
; the final value exists and the pending patch will replace its field later.

    LD   HL,0
    JR   PR_SHVAL
PR_RCFAI:

; The Z80 form census proves that no valid instruction needs more than two
; deferred fields. Reaching a third is a diagnosed parser-capacity failure.

    LD   A,PR_SRCAP
    JP   PR_FESYM

;@ROUTINE IN A OUT DE CLOBBERS HL,A,F
; Return the address of build-reference A. Each record is thirteen bytes and the
; capacity is two, so a single conditional add selects the second record.

PR_BRADR:
    LD   DE,PR_RBLD
    OR   A
    RET  Z
    LD   HL,PR_BRB
    ADD  HL,DE
    EX   DE,HL
    RET
PR_EFAIL:

; Preserve the nested expression status and exact expression error location,
; then return the parser's expression category.

    LD   (PR_ESTA1),A
    LD   A,(EX_EPART)
    LD   (PR_EPART),A
    LD   HL,(EX_EOFF)
    LD   (PR_EOFF),HL
    LD   A,PR_SEXPR
    LD   (PR_ESTAT),A
    SCF
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Recognise short operand words such as registers and conditions. The tokenizer
; lexeme is packed case-insensitively and scanned against exact RADIX-40 values.
; Names of four or more characters cannot be operand words and fall through to
; expression parsing as symbols.

PR_LOW:
    CALL TK_LLEXE
    CP   4
    JR   NC,.UOP
    LD   DE,PR_NKEY
    CALL EN_R40PK
    JR   C,.UOP
    LD   DE,(PR_NKEY)
    LD   HL,PR_OWTAB
    LD   B,PR_OWCNT
.LOLOOP:

; Each table entry is packed word followed by provisional operand class.

    LD   A,(HL)
    CP   E
    INC  HL
    JR   NZ,.LOSHI
    LD   A,(HL)
    CP   D
    JR   Z,.LOFOUND
.LOSHI:
    INC  HL
    INC  HL
    DJNZ .LOLOOP
.UOP:
    LD   A,PR_SUOP
    JP   PR_FHERE
.LOFOUND:
    INC  HL
    LD   A,(HL)
    OR   A
    RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Parse a parenthesised operand after the opening '(' has been seen. The first
; inner token distinguishes a concrete memory/port word from an absolute
; expression or an IX/IY displacement expression.

PR_PMEMO:
    CALL PR_NTOK
    RET  C
    LD   A,(TK_REC+TK_KOFF)
    CALL PR_IESTA
    JR   NC,.MEXPR
    CP   TK_LPARE
    JR   Z,.MEXPR
    CP   TK_NAME
    JP   NZ,PR_EXPOP
    CALL PR_LOW
    JR   C,.MEXPR

; Save the provisional base class before consuming its token.

    LD   (PR_MBASE),A
    CALL PR_NTOK
    RET  C
    LD   A,(PR_MBASE)
    CP   PR_GC
    JR   Z,.MPC
    CP   EN_BC
    JR   Z,.MEMORYBC
    CP   EN_DE
    JR   Z,.MEMORYDE
    CP   EN_HL
    JR   Z,.MEMORYHL
    CP   EN_SP
    JR   Z,.MEMORYSP
    CP   EN_IX
    JR   Z,.MEMORYIX
    CP   EN_IY
    JR   Z,.MEMORYIY
    JP   PR_UOP
.MEXPR:

; A parenthesised expression becomes a generic memory number. IN and OUT later
; reinterpret this class as an eight-bit immediate port; other forms use an
; absolute-memory word.

    CALL PR_PEXPR
    RET  C
    LD   HL,(PR_CPTR)
    LD   (HL),PR_GPNUM
    JR   PR_RRPAR
.MPC:

; `(C)` is the indirect port class, distinct from ordinary register C.

    LD   A,EN_PORTC
    JR   .MSIMPLE
.MEMORYBC:
    LD   A,EN_MEMBC
    JR   .MSIMPLE
.MEMORYDE:
    LD   A,EN_MEMDE
    JR   .MSIMPLE
.MEMORYHL:
    LD   A,EN_MEMHL
    JR   .MSIMPLE
.MEMORYSP:
    LD   A,EN_MEMSP
.MSIMPLE:

; Store the fixed indirect class and require the closing parenthesis.

    LD   HL,(PR_CPTR)
    LD   (HL),A
    JR   PR_RRPAR
.MEMORYIX:

; B retains the dedicated JP (IX) memory class. PR_ICLAS is the ordinary indexed
; class used for displacement-bearing forms and the zero-displacement alias.

    LD   B,EN_MEMIX
    LD   A,EN_IIX
    LD   (PR_ICLAS),A
    JR   .MINDEX
.MEMORYIY:
    LD   B,EN_MEMIY
    LD   A,EN_IIY
    LD   (PR_ICLAS),A
.MINDEX:

; A closing ')' is the implicit displacement-zero form. Otherwise only '+' or
; '-' may introduce the displacement expression.

    LD   A,(TK_REC+TK_KOFF)
    CP   TK_RPARE
    JR   Z,.MIPLAIN
    CP   TK_PLUS
    JR   Z,.MIEXPR
    CP   TK_MINUS
    JP   NZ,PR_EDELI
.MIEXPR:
    CALL PR_PEXPR
    RET  C
    LD   HL,(PR_CPTR)
    LD   A,(PR_ICLAS)
    LD   (HL),A
    JR   PR_RRPAR
.MIPLAIN:

; JP (IX/IY) uses the encoder's dedicated memory class. Other instructions use
; the ordinary indexed class with the already-zero value slot.

    LD   HL,(PR_CPTR)
    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MJP
    LD   A,B
    JR   Z,.MIPSTORE
    LD   A,(PR_ICLAS)
.MIPSTORE:
    LD   (HL),A
    JP   PR_NTOK

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Require and consume the closing ')' for an expression or fixed indirect form.

PR_RRPAR:
    LD   A,(TK_REC+TK_KOFF)
    CP   TK_RPARE
    JP   NZ,PR_EDELI
    JP   PR_NTOK

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,DE,HL,SIGN,PARITY,HALFCARRY
; Copy the tokenizer's numeric word to the selected value slot. This retained
; helper has no caller in the current parser path.

PR_STVAL:
    LD   HL,(TK_REC+TK_VOFF)
    JP   PR_SHVAL

;@ROUTINE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,HL,ZERO,BC,DE
; Normalise the optional explicit accumulator used by the ALU mnemonic family.
; ADD, ADC and SBC require an explicit accumulator when using their eight-bit
; form. Any two-operand ALU form whose first operand is A is collapsed to the
; encoder's canonical one-operand record.

PR_NAALI:
    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MADD
    JR   C,.ASUCCESS
    CP   AT_MCP+1
    JR   NC,.ASUCCESS
    LD   A,(PR_OPCNT)
    CP   1
    JR   NZ,.MAALIAS

; A one-operand ADD/ADC/SBC would silently imply A, which Atom does not permit.

    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MADD
    JR   Z,.RACCUMUL
    CP   AT_MADC
    JR   Z,.RACCUMUL
    CP   AT_MSBC
    JR   NZ,.ASUCCESS
.RACCUMUL:
    LD   A,PR_SIFOR
    JP   PR_FBEG
.MAALIAS:
    CP   2
    JR   NZ,.ASUCCESS
    LD   A,(PR_SCRAT+EN_OP0)
    CP   EN_A
    JR   NZ,.ASUCCESS
    LD   A,(PR_SCRAT+EN_OP1)

; Shift operand 1's class and value into operand 0, then clear operand 1 and
; reduce the arity to one.

    LD   (PR_SCRAT+EN_OP0),A
    LD   HL,(PR_SCRAT+EN_VAL1)
    LD   (PR_SCRAT+EN_VAL0),HL
    LD   A,EN_NONE
    LD   (PR_SCRAT+EN_OP1),A
    XOR  A
    LD   (PR_SCRAT+EN_VAL1),A
    LD   (PR_SCRAT+EN_VAL1+1),A
    INC  A
    LD   (PR_OPCNT),A

; If the removed second operand carried a deferred reference, remap its operand
; index from one to zero and shift the unresolved mask with the record.

    LD   A,(PR_UMASK)
    AND  2
    JR   Z,.ASUCCESS
    LD   A,1
    LD   (PR_UMASK),A
    CALL PR_RAREF
.ASUCCESS:
    XOR  A
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS B,SIGN,PARITY,HALFCARRY,DE,HL,A
; Rewrite build-reference operand index 1 to 0 after accumulator-alias collapse.

PR_RAREF:
    XOR  A
    LD   B,A
.RALOOP:
    LD   A,(PR_RBCNT)
    CP   B
    RET  Z
    LD   A,B
    CALL PR_BRADR
    LD   HL,PR_BLDOP
    ADD  HL,DE
    LD   A,(HL)
    CP   1
    JR   NZ,.RANEXT
    LD   (HL),0
.RANEXT:
    INC  B
    JR   .RALOOP

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Resolve provisional numeric classes after the mnemonic and complete operand
; list are known. FMASK records byte-immediate candidates that may later widen;
; CMASK records occurrences of C that may be a condition rather than register C.

PR_NNUMB:
    XOR  A
    LD   (PR_FMASK),A
    LD   (PR_CMASK),A
    LD   (PR_SINDE),A
.NLOOP:
    LD   A,(PR_SINDE)
    LD   B,A
    LD   A,(PR_OPCNT)
    CP   B
    RET  Z
    LD   A,B
    CALL PR_SOP
    LD   HL,(PR_CPTR)
    LD   A,(HL)
    CP   PR_GC
    JR   Z,.NC
    CP   PR_GPNUM
    JR   Z,.NPNUMBER
    CP   PR_GNUMB
    JR   NZ,.NNEXT
    CALL PR_NBNUM
    RET  C
    JR   .NNEXT
.NC:

; Prefer register C initially and record the alternative condition meaning for
; candidate validation.

    LD   (HL),EN_C
    LD   A,(PR_SINDE)
    CALL PR_IBIT
    LD   HL,PR_CMASK
    OR   (HL)
    LD   (HL),A
    JR   .NNEXT
.NPNUMBER:

; Parenthesised numbers are absolute memory except in IN and OUT, where they are
; the immediate eight-bit port form.

    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MIN
    JR   Z,.NPB
    CP   AT_MOUT
    JR   Z,.NPB
    LD   HL,(PR_CPTR)
    LD   (HL),EN_MABS
    JR   .NNEXT
.NPB:
    CALL PR_RBVAL
    RET  C
    LD   HL,(PR_CPTR)
    LD   (HL),EN_IMM8
.NNEXT:
    LD   HL,PR_SINDE
    INC  (HL)
    JR   .NLOOP

;@ROUTINE OUT A,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO,BC,DE
; Convert one bare generic number according to its mnemonic and operand index.
; Enumerated operands encode their value in the class itself. Branches select a
; word or relative class. All remaining numbers start as flexible imm8.

PR_NBNUM:
    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MIM
    JR   Z,.NIM
    CP   AT_MRST
    JR   Z,.NRST
    CP   AT_MBIT
    JR   C,.NBRANCH
    CP   AT_MSET+1
    JR   C,.NBIT
.NBRANCH:

; Absolute JP and CALL retain the target word. JR and DJNZ are converted to a
; signed displacement only after the final instruction length is known.

    LD   A,(PR_SCRAT+EN_MNEM)
    CP   AT_MJP
    JR   Z,.NW
    CP   AT_MCALL
    JR   Z,.NW
    CP   AT_MJR
    JR   Z,.NRELATIV
    CP   AT_MDJNZ
    JR   Z,.NRELATIV
    CP   AT_MOUT
    JR   NZ,.NFLEXIBL

; OUT (C),0 has a dedicated operand class. Other OUT numbers remain byte values
; and are validated by the complete form.

    CALL PR_SVAL
    LD   A,H
    OR   L
    JR   NZ,.NFLEXIBL
    LD   HL,(PR_CPTR)
    LD   (HL),EN_ZERO
    XOR  A
    RET
.NIM:

; IM accepts only the enumerated values 0, 1 and 2.

    CALL PR_SVAL
    LD   A,H
    OR   A
    JP   NZ,PR_VRANG
    LD   A,L
    CP   3
    JP   NC,PR_VRANG
    ADD  A,EN_IM0
    JR   .SENUM
.NRST:

; RST accepts the eight vectors from 0 through 56 in steps of eight. Rotate the
; vector index down and add the first restart class.

    CALL PR_SVAL
    LD   A,H
    OR   A
    JP   NZ,PR_VRANG
    LD   A,L
    CP   57
    JP   NC,PR_VRANG
    AND  7
    JP   NZ,PR_VRANG
    LD   A,L
    RRCA
    RRCA
    RRCA
    AND  7
    ADD  A,EN_RST0
    JR   .SENUM
.NBIT:

; BIT, RES and SET encode their first operand in the class and require 0..7.

    LD   A,(PR_SINDE)
    OR   A
    JR   NZ,.NFLEXIBL
    CALL PR_SVAL
    LD   A,H
    OR   A
    JP   NZ,PR_VRANG
    LD   A,L
    CP   8
    JP   NC,PR_VRANG
    ADD  A,EN_BIT0
.SENUM:

; The enumerated class now carries the value, so clear the redundant word slot.

    LD   HL,(PR_CPTR)
    LD   (HL),A
    CALL PR_CSVAL
    XOR  A
    RET
.NW:
    LD   HL,(PR_CPTR)
    LD   (HL),EN_IMM16
    XOR  A
    RET
.NRELATIV:
    LD   HL,(PR_CPTR)
    LD   (HL),EN_REL8
    XOR  A
    RET
.NFLEXIBL:

; Begin with imm8 and remember this operand in FMASK. If no byte-form candidate
; validates, PR_WFLEX widens every marked operand to imm16 and tries again.

    LD   HL,(PR_CPTR)
    LD   (HL),EN_IMM8
    LD   A,(PR_SINDE)
    CALL PR_IBIT
    LD   HL,PR_FMASK
    OR   (HL)
    LD   (HL),A
    XOR  A
    RET

;@ROUTINE OUT HL CLOBBERS A
; Load the selected operand's little-endian word into HL.

PR_SVAL:
    LD   HL,(PR_VPTR)
    LD   A,(HL)
    INC  HL
    LD   H,(HL)
    LD   L,A
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Clear the selected value once its information has moved into an enum class.

PR_CSVAL:
    LD   HL,(PR_VPTR)
    XOR  A
    LD   (HL),A
    INC  HL
    LD   (HL),A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
; Require the selected value to fit unsigned eight-bit range.

PR_RBVAL:
    CALL PR_SVAL
    LD   A,H
    OR   A
    RET  Z
    JP   PR_VRANG

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return a one-hot bit for operand index A: 0 -> 1, 1 -> 2, 2 -> 4.

PR_IBIT:
    OR   A
    JR   NZ,.IBDOUBLE
    INC  A
    RET
.IBDOUBLE:
    ADD  A,A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Select an encoder-valid interpretation for the normalised record. Candidate
; order is: provisional classes, each ambiguous C as condition, widened numeric
; classes, then condition alternatives on the widened record. Success returns
; the encoder-reported length in A.

PR_VCAND:
    CALL PR_VCUR
    RET  NC
    CALL PR_TCOND
    RET  NC
    LD   A,(PR_FMASK)
    OR   A
    JR   Z,.IFORM
    CALL PR_WFLEX
    CALL PR_VCUR
    RET  NC
    CALL PR_TCOND
    RET  NC
.IFORM:
    LD   A,PR_SIFOR
    JP   PR_FBEG

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate the current private instruction record without examining its values.

PR_VCUR:
    LD   IX,PR_SCRAT
    JP   EN_VFORM

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY,HL
; Try each operand marked in CMASK as condition C. Change only one occurrence at
; a time, restore register C after a failed validation and stop at the first
; complete valid form.

PR_TCOND:
    XOR  A
    LD   (PR_SINDE),A
.TCLOOP:
    LD   A,(PR_SINDE)
    CP   3
    JR   Z,.TCFAILED
    LD   B,A
    CALL PR_IBIT
    LD   HL,PR_CMASK
    AND  (HL)
    JR   Z,.TCNEXT
    LD   A,B
    CALL PR_SOP
    LD   HL,(PR_CPTR)
    LD   (HL),EN_CC
    PUSH HL
    CALL PR_VCUR
    POP  HL
    RET  NC
    LD   (HL),EN_C
.TCNEXT:
    LD   HL,PR_SINDE
    INC  (HL)
    JR   .TCLOOP
.TCFAILED:
    SCF
    RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY,B,DE,HL,A
; Widen every flexible imm8 candidate to imm16 before the second validation
; pass. The chosen form later determines each deferred reference's patch width.

PR_WFLEX:
    XOR  A
    LD   (PR_SINDE),A
.WLOOP:
    LD   A,(PR_SINDE)
    CP   3
    RET  Z
    LD   B,A
    CALL PR_IBIT
    LD   HL,PR_FMASK
    AND  (HL)
    JR   Z,.WNEXT
    LD   A,B
    CALL PR_SOP
    LD   HL,(PR_CPTR)
    LD   (HL),EN_IMM16
.WNEXT:
    LD   HL,PR_SINDE
    INC  (HL)
    JR   .WLOOP

;@ROUTINE OUT A,CARRY CLOBBERS BC,ZERO,SIGN,PARITY,HALFCARRY,DE,HL,IX,IY
; Check every resolved concrete value against its selected operand class. Values
; with a bit in UMASK remain zero placeholders and are checked later when their
; symbols resolve.

PR_CCVAL:
    XOR  A
    LD   (PR_SINDE),A
.CVLOOP:
    LD   A,(PR_SINDE)
    LD   B,A
    LD   A,(PR_OPCNT)
    CP   B
    RET  Z
    LD   A,B
    CALL PR_SOP
    LD   A,(PR_SINDE)
    CALL PR_IBIT
    LD   HL,PR_UMASK
    AND  (HL)
    JR   NZ,.CVNEXT

; Word and absolute classes need no further range conversion. Byte, relative and
; indexed classes have class-specific checks below.

    LD   HL,(PR_CPTR)
    LD   A,(HL)
    CP   EN_IMM8
    JR   Z,.CHKB
    CP   EN_REL8
    JR   Z,.CRELATIV
    CP   EN_IIX
    JR   Z,.CDISPLAC
    CP   EN_IIY
    JR   Z,.CDISPLAC
.CVNEXT:
    LD   HL,PR_SINDE
    INC  (HL)
    JR   .CVLOOP
.CHKB:
    CALL PR_RBVAL
    RET  C
    JR   .CVNEXT
.CDISPLAC:

; IX/IY displacement accepts exactly -128..127 represented as a sign-extended
; word or a positive low byte.

    CALL PR_SVAL
    LD   A,H
    OR   A
    JR   Z,.CDPOSITI
    INC  A
    JP   NZ,PR_VRANG
    BIT  7,L
    JP   Z,PR_VRANG
    JR   .CVNEXT
.CDPOSITI:
    BIT  7,L
    JP   NZ,PR_VRANG
    JR   .CVNEXT
.CRELATIV:

; Convert an absolute branch target to target-(instruction address+length). The
; 16-bit addition and subtraction deliberately wrap at $FFFF, matching the Z80
; program counter, then the result must fit a signed byte.

    CALL PR_SVAL
    LD   DE,(PR_IADR)
    LD   A,(PR_ILEN)
    ADD  A,E
    LD   E,A
    JR   NC,.RBREADY
    INC  D
.RBREADY:
    OR   A
    SBC  HL,DE
    LD   A,H
    OR   A
    JR   Z,.RPOSITIV
    INC  A
    JP   NZ,PR_RRANG
    BIT  7,L
    JP   Z,PR_RRANG
    JR   .RSTORE
.RPOSITIV:
    BIT  7,L
    JP   NZ,PR_RRANG
.RSTORE:

; Replace the absolute target with the encoded displacement for EN_NAME.

    CALL PR_SHVAL
    JR   .CVNEXT

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Turn private build references into public symbol-reference descriptions. The
; first pass locates the encoded field and final patch kind for each operand.

PR_FREFE:
    XOR  A
    LD   (PR_RSCAN),A
.LRLOOP:
    LD   A,(PR_RBCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.PREFEREN
    CALL PR_BRADR
    LD   HL,PR_BLDOP
    ADD  HL,DE
    LD   A,(HL)
    LD   IX,PR_SCRAT
    CALL PT_LOCAT
    JR   C,.UREF

; Save the locator's patch kind and byte offset while returning to the selected
; thirteen-byte build entry.

    LD   (PR_RKSCR),A
    LD   A,B
    LD   (PR_ROSCR),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BKIND
    ADD  HL,DE
    LD   A,(HL)
    CP   EX_FLO
    JR   Z,.LLREF
    CP   EX_FHI
    JR   Z,.LHREF
    LD   A,(PR_RKSCR)
    JR   .LSKIND
.LLREF:
    LD   A,PT_KLB
    JR   .LBFUNCTI
.LHREF:
    LD   A,PT_KHB
.LBFUNCTI:

; LOW/HIGH cannot transform relative or displacement patches. Relative fields
; subtract an address and both field types require signed-range semantics, not
; simple byte extraction.

    PUSH AF
    LD   A,(PR_RKSCR)
    CP   PT_KRELA
    JR   Z,.LBFINVAL
    CP   PT_KDISP
    JR   Z,.LBFINVAL
    POP  AF
.LSKIND:

; Store the final kind and encoded-field offset in the build record.

    LD   (HL),A
    INC  HL
    LD   A,(PR_ROSCR)
    LD   (HL),A
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .LRLOOP
.LBFINVAL:
    POP  AF
.UREF:
    LD   A,PR_SUNPA
    JP   PR_FREF
.PREFEREN:

; Count exact missing symbol records before inserting any. When both references
; share one key, only the first contributes to the capacity requirement.

    XOR  A
    LD   (PR_RMCNT),A
    LD   (PR_RSKEY),A
    LD   A,(PR_RBCNT)
    OR   A
    RET  Z
    CP   2
    JR   NZ,.PFIRST
    CALL PR_CRKEY

; Carry clear means equal keys. Convert that result to one in PR_RSKEY.

    SBC  A,A
    INC  A
    LD   (PR_RSKEY),A
.PFIRST:
    XOR  A
    LD   (PR_RSCAN),A
    CALL PR_PREF
    RET  C
    LD   A,(PR_RBCNT)
    CP   2
    JR   NZ,.PCAP
    LD   A,(PR_RSKEY)
    OR   A
    JR   NZ,.PCAP
    LD   A,1
    LD   (PR_RSCAN),A
    CALL PR_PREF
    RET  C
.PCAP:
    LD   A,(PR_RMCNT)
    OR   A
    JR   Z,.PREFERE1

; Each missing symbol needs one eight-byte record in the shared arena. Check the
; complete requirement against the gap between globals and private symbols.

    ADD  A,A
    ADD  A,A
    ADD  A,A
    LD   B,A
    LD   HL,(SY_LBEG)
    LD   DE,(SY_GEND)
    CALL AT_RHCAP
    JP   C,PR_SCFAI
.PREFERE1:

; Capacity is now proved. Resolve or insert every key and construct the public
; nine-byte descriptions in source operand order.

    XOR  A
    LD   (PR_RSCAN),A
.PRLOOP:
    LD   A,(PR_RBCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.PRCNT
    CALL PR_BRADR
    LD   H,D
    LD   L,E
    CALL SY_REF
    JP   C,PR_USFAI
    LD   A,B
    OR   A
    JR   Z,.RDREADY

; A newly inserted undefined record retains the first reference position in its
; otherwise-unused value word. Mark the matching pending kind as the diagnostic
; anchor that may report an undefined symbol at finalisation.

    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BSOFF
    ADD  HL,DE
    LD   A,(HL)
    LD   (IX+SY_VALLO),A
    INC  HL
    LD   A,(HL)
    LD   (IX+SY_VALHI),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   A,SY_DANCH
    LD   HL,PR_BKIND
    ADD  HL,DE
    OR   (HL)
    LD   (HL),A
.RDREADY:

; Public record: symbol pointer, addend, operand index, patch kind/anchor, encoded
; byte offset, source part and source offset.

    PUSH IX
    POP  BC
    LD   A,(PR_RSCAN)
    CALL PR_PRADR
    LD   (HL),C
    INC  HL
    LD   (HL),B
    INC  HL
    PUSH HL
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BADDE
    ADD  HL,DE
    POP  DE
    LD   BC,7
    LDIR
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .PRLOOP
.PRCNT:

; Publish the count only after every public record and symbol insertion succeeds.

    LD   A,(PR_RBCNT)
    LD   (PR_RCNT),A
    XOR  A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,IY
; Inspect one build key without mutation. Not-found increments the exact missing
; count; scope and other symbol failures retain their nested status.

PR_PREF:
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   H,D
    LD   L,E
    CALL SY_FIND
    RET  NC
    CP   SY_SNFOU
    JR   NZ,PR_SFAIL
    LD   HL,PR_RMCNT
    INC  (HL)
    XOR  A
    RET
PR_SFAIL:
    LD   (PR_SSTAT),A
    LD   A,PR_SSYM
    JP   PR_FREF

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,B
; Compare the two six-byte packed keys. Carry clear means identical.

PR_CRKEY:
    LD   HL,PR_RBLD
    LD   DE,PR_RBLD+PR_BRB
    LD   B,6
.CRKLOOP:
    LD   A,(DE)
    CP   (HL)
    SCF
    RET  NZ
    INC  DE
    INC  HL
    DJNZ .CRKLOOP
    OR   A
    RET
PR_SCFAI:

; Translate the shared-arena capacity failure through the symbol error category.

    LD   A,SY_SSCAP
    JR   PR_SFAIL
PR_USFAI:

; SY_REF cannot fail after exact lookup and capacity preflight unless an internal
; invariant changed between the two phases.

    LD   (PR_SSTAT),A
    LD   A,PR_SINT
    JP   PR_FREF

;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
; Return public-reference address A. Two fixed nine-byte slots cover the parser
; reference capacity.

PR_PRADR:
    LD   HL,PR_REFER
    OR   A
    RET  Z
    LD   DE,PR_PRB
    ADD  HL,DE
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO,IX
; Before any instruction byte is emitted, prove that the pending arena has room
; for every reference and that each symbol remains undefined. Each pending entry
; is seven bytes, including its full source-part ordinal; allocation happens in
; PR_QREFE after output accepts the instruction.

PR_CREFE:
    LD   A,(PR_RCNT)
    LD   B,A
    ADD  A,A
    ADD  A,B
    ADD  A,A
    ADD  A,B
    LD   B,A
    LD   HL,(SY_AEND1)
    LD   DE,(SY_NEXT)
    CALL AT_RHCAP
    JR   C,PR_QCAP
.QCSYMBOL:

; A symbol defined between parse and emission would make the already encoded
; placeholder invalid. Treat it as a defensive publication-state failure.

    XOR  A
    LD   (PR_RSCAN),A
.QCLOOP:
    LD   A,(PR_RCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.QPDONE
    CALL PR_PRADR
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    EX   DE,HL
    LD   DE,5
    ADD  HL,DE
    BIT  6,(HL)
    JR   NZ,PR_QADEF
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .QCLOOP
.QPDONE:
    XOR  A
    RET

;@ROUTINE IN DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Queue every public reference after the encoded bytes have been accepted. DE
; supplies the instruction's logical start address. A second preflight protects
; direct callers and keeps this entry self-contained.

PR_QREFE:
    LD   (PR_QBASE),DE
    CALL PR_CREFE
    RET  C
.QUEUECMT:
    XOR  A
    LD   (PR_RSCAN),A
.QLOOP:
    LD   A,(PR_RCNT)
    LD   B,A
    LD   A,(PR_RSCAN)
    CP   B
    JR   Z,.QDONE
    CALL PR_PRADR

; Load the symbol pointer, signed addend, final kind, source part and encoded
; byte offset from the public record.

    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    PUSH DE
    POP  IX
    INC  HL
    LD   C,(HL)
    INC  HL
    INC  HL
    LD   B,(HL)
    INC  HL
    LD   A,(HL)
    LD   (PR_ROSCR),A
    INC  HL
    LD   A,(HL)
    LD   (PR_RKSCR),A
    LD   A,(PR_ROSCR)
    LD   HL,(PR_QBASE)
    LD   E,A
    LD   D,0
    ADD  HL,DE
    EX   DE,HL

; SY_ADD receives A=part, IX=symbol, DE=patch address, B=kind/anchor and C=addend.

    LD   A,(PR_RKSCR)
    CALL SY_ADD
    RET  C
    LD   HL,PR_RSCAN
    INC  (HL)
    JR   .QLOOP
.QDONE:
    XOR  A
    RET
PR_QCAP:

; Pending arena cannot hold the complete reference set. No record was appended.

    LD   A,SY_SPCAP
    SCF
    RET
PR_QADEF:

; Defensive status for a reference whose symbol became defined before queueing.

    LD   A,SY_SADEF
    SCF
    RET
PR_FESYM:

; Reference-build failures that arise directly from expression state use the
; evaluator's retained symbol position. PR_PUB callers diagnose at the enclosing
; statement position; PR_PARSE callers receive these parser error fields.

    LD   (PR_ESTAT),A
    LD   A,(EX_SPART)
    LD   (PR_EPART),A
    LD   HL,(EX_SOFF)
    LD   (PR_EOFF),HL
    LD   A,(PR_ESTAT)
    SCF
    RET
PR_FREF:

; Reference finalisation failures use the source position stored in the current
; build record selected by PR_RSCAN.

    LD   (PR_ESTAT),A
    LD   A,(PR_RSCAN)
    CALL PR_BRADR
    LD   HL,PR_BPART
    ADD  HL,DE
    LD   A,(HL)
    LD   (PR_EPART),A
    INC  HL
    LD   E,(HL)
    INC  HL
    LD   D,(HL)
    LD   (PR_EOFF),DE
    LD   A,(PR_ESTAT)
    SCF
    RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Commit the fully validated private record to the caller's destination and
; return IX pointing at it. No earlier parser path writes the destination.

PR_CMT:
    LD   HL,PR_SCRAT
    LD   DE,(PR_DST)
    LD   BC,10
    LDIR
    LD   IX,(PR_DST)
    XOR  A
    RET

; Compact status adapters select the appropriate source anchor below.

PR_EMNEM:
    LD   A,PR_SEMNE
    JR   PR_FHERE
PR_UMNEM:
    LD   A,PR_SUMNE
    JR   PR_FHERE
PR_EXPOP:
    LD   A,PR_SEOP
    JR   PR_FHERE
PR_UOP:
    LD   A,PR_SUOP
    JR   PR_FHERE
PR_EDELI:
    LD   A,PR_SEDEL
    JR   PR_FHERE
PR_TMOPE:
    LD   A,PR_STMOP
    JR   PR_FHERE
PR_VRANG:
    LD   A,PR_SVRAN
    JR   PR_FHERE
PR_RRANG:
    LD   A,PR_SRRAN
    JR   PR_FBEG

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the current token position for token-local syntax and value failures.

PR_FHERE:
    LD   HL,TK_REC+TK_POFF
    JR   PR_FPOSI

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Use the instruction's mnemonic position for form and relative-range failures.
; PR_PARSE captures this position. The statement layer supplies its own outer
; position when it calls PR_PUB.

PR_FBEG:
    LD   HL,PR_IPART

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
; Copy a contiguous part-and-offset triple into the parser error fields, preserve
; the status in A and set carry.

PR_FPOSI:
    LD   (PR_ESTAT),A
    PUSH BC
    PUSH DE
    LD   DE,PR_EPART
    LD   BC,3
    LDIR
    POP  DE
    POP  BC
    LD   A,(PR_ESTAT)
    SCF
    RET
PR_RCEND:
PR_IBEG:

; Sorted RADIX-40 operand-word table. Each three-byte entry contains one packed
; word and its provisional encoder class. C maps to PR_GC because only complete
; form validation can distinguish register C from condition C.

PR_OWCNT EQU 27
PR_OWTAB:
    DW  $0640
    DB  EN_A
    DW  $0730
    DB  EN_AF
    DW  $0C80
    DB  EN_B
    DW  $0CF8
    DB  EN_BC
    DW  $12C0
    DB  PR_GC
    DW  $1900
    DB  EN_D
    DW  $19C8
    DB  EN_DE
    DW  $1F40
    DB  EN_E
    DW  $3200
    DB  EN_H
    DW  $33E0
    DB  EN_HL
    DW  $3840
    DB  EN_I
    DW  $3C00
    DB  EN_IX
    DW  $3C08
    DB  EN_IXH
    DW  $3C0C
    DB  EN_IXL
    DW  $3C28
    DB  EN_IY
    DW  $3C30
    DB  EN_IYH
    DW  $3C34
    DB  EN_IYL
    DW  $4B00
    DB  EN_L
    DW  $5140
    DB  EN_M
    DW  $57F8
    DB  EN_NC
    DW  $5B90
    DB  EN_NZ
    DW  $6400
    DB  EN_P
    DW  $64C8
    DB  EN_PE
    DW  $6658
    DB  EN_PO
    DW  $7080
    DB  EN_R
    DW  $7940
    DB  EN_SP
    DW  $A280
    DB  EN_Z
PR_OWTEN:
PR_IEND:
PR_CEND:
PR_WBEG:

; Per-call destinations and instruction identity. PR_ILEN is the length returned
; by EN_VFORM and is required for relative-target conversion.

PR_DST: DW 0
PR_IADR: DW 0
PR_IPART: DB 0
PR_IOFF: DW 0
PR_ILEN: DB 0
PR_OPCNT: DB 0

; Shared scan index, ambiguity masks and selected class/value pointers used by
; operand normalisation and range checking.

PR_SINDE: DB 0
PR_FMASK: DB 0
PR_CMASK: DB 0
PR_CPTR: DW 0
PR_VPTR: DW 0
PR_LCLAS: DB 0
PR_MBASE: DB 0
PR_ICLAS: DB 0

; Retained workspace byte with no caller in the current parser implementation.

PR_DSIGN: DB 0

; Six-byte temporary packed operand key and private ten-byte instruction record.
; Selected scratch bytes are also reused for nested status and source fields.
; Terminal errors prevent commit, but a recovered short-word probe may leave
; ignored error bytes in unused operand-value slots of a successful record.

PR_NKEY: DS 6
PR_SCRAT: DS 10
PR_ESTAT EQU PR_SCRAT+6
PR_EPART EQU PR_SCRAT+7
PR_EOFF EQU PR_SCRAT+8
PR_ESTA1 EQU PR_SCRAT+5
PR_SSTAT EQU PR_SCRAT+5

; Reference publication state. PR_RBCNT counts private build entries; PR_RCNT is
; published only after their symbols and public records are complete.

PR_RCNT: DB 0
PR_RBCNT: DB 0
PR_UMASK: DB 0
PR_RSCAN: DB 0
PR_RMCNT: DB 0
PR_RSKEY: DB 0
PR_RKSCR: DB 0
PR_ROSCR: DB 0
PR_RASCR: DW 0
PR_QBASE: DW 0

; Two thirteen-byte build entries followed by two nine-byte public entries. The
; complete fixed parser workspace is 92 bytes.

PR_RBLD: DS PR_BRB*PR_RCAP
PR_REFER: DS PR_PRB*PR_RCAP
PR_WEND:
