;==============================================================================
;  Expression evaluator
;==============================================================================
;
;  Parse one expression from the tokenizer stream with bounded value and
;  operator stacks. The parser alternates between a primary and an operator,
;  reducing operators as precedence permits. It leaves the delimiter in
;  TK_REC for the caller.
;
;  Principal entries:
;    EX_PARSE  return a value or publish one missing symbol through SY_REF
;    EX_PDEFR  return a value or an unpublished packed key for caller commit
;    EX_QUEUE  append a previously published unresolved result to the pending
;              arena
;
;  BC supplies the logical address used by '$'. On success carry is clear and A
;  is EX_RESOL or EX_UNRES. A resolved result is the final word in HL. An
;  unresolved result is one exact symbol plus a signed-byte addend in HL;
;  EX_RUNRE records whether the later patch uses the plain word, LOW byte or
;  HIGH byte. EX_PARSE returns the symbol record in IX, while EX_PDEFR returns
;  IX pointing at the six-byte key in EX_RKEY.
;
;  Concrete operations use signed 24-bit working values before the final
;  -32768..65535 word check. Addition, subtraction and left shift detect signed
;  overflow. Multiplication detects carry beyond 24 bits, but currently permits
;  a positive magnitude whose bit 23 becomes set. A later right shift can expose
;  that wrapped negative intermediate. Deferred expressions are deliberately
;  smaller: one symbol, an addend from -128 through 127 and an optional LOW or
;  HIGH transform. Operations that need an expression tree are rejected with
;  EX_SFFOR.
;
;  Value entries are ten bytes: three value or addend bytes, one resolution or
;  transform byte and a six-byte packed key. Operator entries are four bytes:
;  one encoded operator, source-part ordinal and source offset. Both stacks
;  have sixteen entries. Every parse resets their depths, so a failed call does
;  not poison the next expression.

EX_CBEG:
; Public success and failure statuses returned in A.
EX_RESOL EQU 0
EX_UNRES EQU 1
EX_SLEXI EQU 2
EX_SEPRI EQU 3
EX_SERIG EQU 4
EX_SDZER EQU 5
EX_SRANG EQU 6
EX_SFFOR EQU 7
EX_SCAP EQU 8
EX_SSYM EQU 9
EX_SINT EQU 10
; Binary reduction ordinals stored in the low nibble of an operator byte.
EX_OPOR EQU 0
EX_OPXOR EQU 1
EX_OPAND EQU 2
EX_OLEFT EQU 3
EX_ORIGH EQU 4
EX_OPADD EQU 5
EX_OSUBT EQU 6
EX_OMULT EQU 7
EX_ODIVI EQU 8
EX_OREMA EQU 9
; Fixed record sizes and stack capacities.
EX_VALB EQU 10
EX_VCAP EQU 16
EX_OPERB EQU 4
EX_OCAP EQU 16
; Operator markers combine precedence in the high nibble with operation in the
; low nibble. $0F is a non-reducing parenthesis marker and $7x denotes unary.
EX_MLPAR EQU $0F
EX_UPLUS EQU $7A
EX_UMINU EQU $7B
EX_UTILD EQU $72
EX_ULO EQU $7D
EX_UHI EQU $7E
; Non-zero deferred-state values distinguish an ordinary affine symbol from its
; LOW and HIGH byte transforms.
EX_FPLAI EQU 1
EX_FLO EQU 2
EX_FHI EQU 3
; Parse and publish an unresolved symbol only after the complete expression has
; passed syntax, forward-form and addend checks. This is the direct evaluator
; entry used by the proof harness and other callers that can commit immediately.
;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_PARSE:
LD   A,1
LD   (EX_PSYM),A
JR   EX_PCOMM
; Parse without changing the symbol arena. The parser and statement layers use
; this entry so they can validate and reserve all later work before publication.
;@ROUTINE IN BC OUT A,HL,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,BC,DE,IY
EX_PDEFR:
XOR  A
LD   (EX_PSYM),A
EX_PCOMM:
; Save '$', clear all bounded-stack state and begin in primary position.
LD   (EX_CADR),BC
XOR  A
LD   (EX_VDEPT),A
LD   (EX_ODEPT),A
LD   (EX_PDEPT),A
INC  A
LD   (EX_EOP),A
.PLOOP:
; EX_EOP selects the grammar half. Primaries clear it after publishing a value;
; binary operators set it after consuming themselves.
LD   A,(EX_EOP)
OR   A
JR   Z,.POPER
CALL EX_POP
RET  C
JR   .PLOOP
.POPER:
CALL EX_POPER
RET  C
JR   NZ,.PLOOP
; A delimiter at parenthesis depth zero ends the expression. Reduce the
; remaining operators and require exactly one value.
CALL EX_FSTAC
RET  C
LD   A,(EX_RUNRE)
OR   A
JR   NZ,.FUNRESOL
CALL EX_REQW
RET  C
LD   HL,(EX_RVAL)
XOR  A
RET
.FUNRESOL:
; Only a signed-byte addend can be stored in a pending reference. The parser has
; already reduced the full expression before this range check.
CALL EX_RADDE
RET  C
LD   A,(EX_PSYM)
OR   A
JR   Z,.FINDEFR
; The publishing entry creates or reuses the undefined symbol record here, after
; every expression check has succeeded. Invalid source cannot leak a symbol.
LD   HL,EX_RKEY
CALL SY_REF
JR   C,EX_SFAIL
.RUNRESOL:
LD   HL,(EX_RVAL)
LD   A,EX_UNRES
OR   A
RET
.FINDEFR:
; The deferred entry returns a pointer into expression workspace. Its caller
; must copy the key before another expression operation reuses this storage.
LD   IX,EX_RKEY
JR   .RUNRESOL
; Preserve the nested symbol status for diagnostics and report the expression
; layer's symbol-error category at the original name position.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_SFAIL:
LD   (EX_SSTAT),A
LD   A,EX_SSYM
JP   EX_FSYM
; Adapt the expression result to the pending-reference ABI. SY_ADD expects the
; signed addend in C; all other carriers already match its register contract.
;@ROUTINE IN A,IX,HL,DE,B OUT A,CARRY CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
EX_QUEUE:
LD   C,L
JP   SY_ADD
; Recognise LOW(...) and the four-character HIG* prefix without consuming the
; following token. Only the first packed RADIX-40 word is compared, so LOW is
; exact but any valid four-character name beginning HIG currently selects the
; HIGH operation. The next non-space source byte must then be '('.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
EX_CFUNC:
; Length selects the only possible name and the unary marker returned in C.
LD   A,(TK_REC+TK_LOFF1)
CP   3
JR   Z,.CLSLO
CP   4
JR   NZ,.NFUNCTIO
LD   C,EX_UHI
LD   DE,$336F
JR   .CFPACK
.CLSLO:
LD   C,EX_ULO
LD   DE,$4D6F
.CFPACK:
; Pack the tokenizer lexeme into EX_RKEY and compare its first packed word with
; LOW or the HIG prefix selected above.
PUSH DE
PUSH BC
LD   HL,(TK_REC+TK_LOFF)
LD   B,A
LD   DE,EX_RKEY
CALL EN_R40PK
POP  BC
POP  DE
JR   C,.NFUNCTIO
LD   HL,(EX_RKEY)
OR   A
SBC  HL,DE
JR   NZ,.NFUNCTIO
; TK_SCURS starts immediately after the name. Read through horizontal space
; directly so classification does not advance or overwrite TK_REC.
LD   HL,(TK_SCURS)
LD   DE,(TK_SEND)
.FLOOKAHE:
LD   A,H
CP   D
JR   NZ,.FLB
LD   A,L
CP   E
JR   Z,.NFUNCTIO
.FLB:
PUSH DE
PUSH HL
LD   A,(TK_SPART)
CALL TK_SREAD
POP  HL
POP  DE
CP   $20
JR   Z,.FLSPACE
CP   $09
JR   Z,.FLSPACE
CP   $28
JR   NZ,.NFUNCTIO
LD   A,C
OR   A
RET
.FLSPACE:
INC  HL
JR   .FLOOKAHE
.NFUNCTIO:
SCF
RET
; Push the unary or function marker in A with the current token position. These
; markers occupy the highest precedence band and are reduced after their value.
;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
EX_PHOPE:
LD   (EX_OPER),A
CALL EX_COPOS
JP   EX_POPE1
; Parse a token that may begin a value. EX_EOP is set on entry. Prefix '+', '-'
; and '~' are converted to unary markers, while '(' is an operator-stack marker
; and increments the independent nesting depth.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
EX_POP:
LD   A,(TK_REC+TK_KOFF)
CP   TK_PLUS
JR   Z,.PUNARY
CP   TK_MINUS
JR   Z,.PUNARY
CP   TK_TILDE
JR   Z,.PUNARY
CP   TK_NUMBE
JR   Z,.PNUMBER
CP   TK_CUR
JR   Z,.PCUR
CP   TK_NAME
JR   Z,.PNAME
.RLPAREN:
; LOW or HIGH classification rejoins here after consuming the function name.
; The next token must begin its parenthesised argument.
CP   TK_LPARE
JR   Z,.PPAREN
LD   A,EX_SEPRI
JP   EX_FHERE
.PUNARY:
; Token ordinals for '+', '-' and '~' become their $7x unary forms by setting
; the precedence nibble.
OR   $70
CALL EX_PHOPE
RET  C
JP   EX_NTOK
.PPAREN:
LD   A,EX_MLPAR
LD   (EX_OPER),A
CALL EX_COPOS
CALL EX_POPE1
RET  C
LD   HL,EX_PDEPT
INC  (HL)
JP   EX_NTOK
.PNUMBER:
; Literal tokens already contain their checked 16-bit value. EX_SRW expands it
; to a resolved, positive 24-bit working value.
LD   HL,(TK_REC+TK_VOFF)
CALL EX_SRW
JR   .PFIN
.PCUR:
LD   HL,(EX_CADR)
CALL EX_SRW
JR   .PFIN
.PNAME:
; LOW and HIGH are identified before symbol packing. A normal name flows to the
; symbol resolver, which may produce a concrete value or a deferred key.
CALL EX_CFUNC
JR   NC,.PFUNCTIO
CALL EX_PNAME
RET  C
JR   .PPUBLISH
.PFIN:
; Numbers and '$' consume the next token before publishing the value stack
; entry. Symbol parsing performs its own token advance.
CALL EX_NTOK
RET  C
.PPUBLISH:
CALL EX_PVAL
RET  C
; Prefix operators are applied as soon as their primary is complete. This keeps
; the operator stack iterative rather than using Z80 recursion.
CALL EX_AUNAR
RET  C
XOR  A
LD   (EX_EOP),A
RET
.PFUNCTIO:
; Retain the LOW or HIGH marker, consume the name and feed the following '('
; back through the same parenthesis path used for ordinary grouping.
CALL EX_PHOPE
RET  C
CALL EX_NTOK
RET  C
LD   A,(TK_REC+TK_KOFF)
JR   .RLPAREN
; Parse the grammar half that follows a value. A recognised binary operator is
; compared with stacked precedence before it is pushed. A right parenthesis
; reduces back to its marker. Any other token is the caller's delimiter.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
EX_POPER:
LD   A,(TK_REC+TK_KOFF)
CP   TK_RPARE
JR   Z,.RPAREN
CALL EX_COPER
JR   C,.DELIMITE
; Preserve the incoming operator while older operators of higher precedence,
; or equal precedence for left-associative operators, are reduced.
CALL EX_SINCO
CALL EX_RINC1
RET  C
CALL EX_RINCO
CALL EX_POPE1
RET  C
LD   A,1
LD   (EX_EOP),A
CALL EX_NTOK
RET  C
XOR  A
INC  A
RET
.RPAREN:
; A ')' can close only an active group. Reduce to the marker, remove it, consume
; the token and then apply a preceding LOW, HIGH or other unary operator.
LD   A,(EX_PDEPT)
OR   A
JR   Z,.DELIMITE
CALL EX_RTPAR
RET  C
CALL EX_POPE2
RET  C
LD   HL,EX_PDEPT
DEC  (HL)
CALL EX_NTOK
RET  C
CALL EX_AUNAR
RET  C
XOR  A
INC  A
RET
.DELIMITE:
; A delimiter is valid only outside parentheses. Leave TK_REC unchanged so the
; statement or operand parser can interpret it.
LD   A,(EX_PDEPT)
OR   A
JR   Z,.DDONE
LD   A,EX_SERIG
JP   EX_FHERE
.DDONE:
XOR  A
RET
; Resolve the current name while retaining its exact source position for symbol
; diagnostics. The packed key stays in EX_RKEY for a possible deferred result.
;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE,IY
EX_PNAME:
LD   A,(TK_REC+TK_POFF)
LD   (EX_SPART),A
LD   HL,(TK_REC+TK_SOFF)
LD   (EX_SOFF),HL
CALL TK_LLEXE
LD   DE,EX_RKEY
CALL EN_PSYM
JP   C,EX_SFAIL
LD   HL,EX_RKEY
CALL SY_FIND
JR   C,.PMISSING
; Bit 6 marks a defined record. An undefined record and a missing name both
; become the same deferred value. Defined EQU records use bit 5 to retain the
; negative interpretation of their 16-bit stored value.
BIT  6,(IX+5)
JR   Z,.PUNRESOL
LD   L,(IX+SY_VALLO)
LD   H,(IX+SY_VALHI)
BIT  5,(IX+5)
JR   Z,.PPSYM
; Sign-extend a negative EQU into the 24-bit arithmetic domain.
LD   (EX_RVAL),HL
LD   A,$FF
LD   (EX_RVAL+2),A
XOR  A
JR   .SUNRESOL
.PPSYM:
CALL EX_SRW
JP   EX_NTOK
.PMISSING:
; SY_FIND errors other than not-found, such as a private name outside a global
; scope, retain their symbol status and fail immediately.
CP   SY_SNFOU
JR   Z,.PUNRESOL
JP   EX_SFAIL
.PUNRESOL:
; A missing or already-undefined symbol starts with addend zero and the plain
; deferred transform. A later reduction may adjust the addend or transform.
XOR  A
LD   (EX_RVAL),A
LD   (EX_RVAL+1),A
LD   (EX_RVAL+2),A
INC  A
.SUNRESOL:
LD   (EX_RUNRE),A
JP   EX_NTOK
; Map the contiguous tokenizer operator range to a packed byte. The high nibble
; is precedence and the low nibble is the reduction-table ordinal. Zero entries
; cover token kinds that are not binary expression operators.
;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,C,HL
EX_COPER:
LD   A,(TK_REC+TK_KOFF)
SUB  TK_PLUS
CP   12
JR   NC,.ODELIMIT
PUSH DE
LD   E,A
LD   D,0
LD   HL,EX_OTABL
ADD  HL,DE
LD   A,(HL)
POP  DE
OR   A
JR   Z,.ODELIMIT
LD   (EX_OPER),A
CALL EX_COPOS
OR   A
RET
.ODELIMIT:
SCF
RET
; Token order from TK_PLUS: +, -, *, /, %, &, ^, |, ~, apostrophe, <<, >>.
; Tilde is unary-only and apostrophe is a delimiter, so both table entries are
; zero.
EX_OTABL:
DB $55,$56,$67,$68,$69,$32,$21,$10,0,0,$43,$44
; Store the source position of the current operator beside its encoded byte.
; Arithmetic and forward-form failures later report this position.
;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
EX_COPOS:
LD   A,(TK_REC+TK_POFF)
LD   (EX_OPART),A
LD   HL,(TK_REC+TK_SOFF)
LD   (EX_OOFF),HL
RET
; Push the complete ten-byte working value after proving stack capacity. The
; entry includes the packed key even for a concrete value, which keeps all stack
; movement uniform.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_PVAL:
LD   A,(EX_VDEPT)
CP   EX_VCAP
JP   NC,EX_CFAIL
CALL EX_VADR
LD   D,H
LD   E,L
LD   HL,EX_RVAL
LD   BC,EX_VALB
LDIR
LD   HL,EX_VDEPT
INC  (HL)
XOR  A
RET
; Pop the right operand into EX_RVAL.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_PVAL1:
LD   DE,EX_RVAL
JR   EX_PVTO
; Pop the left operand into EX_LVAL. Fall through to the shared copy body.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_PLVAL:
LD   DE,EX_LVAL
; Decrement the value depth, locate the last live entry and copy its ten bytes to
; the destination in DE. Empty-stack access indicates an internal parser fault.
;@ROUTINE IN DE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_PVTO:
PUSH DE
LD   A,(EX_VDEPT)
OR   A
JR   Z,EX_PVEMP
DEC  A
LD   (EX_VDEPT),A
CALL EX_VADR
POP  DE
LD   BC,EX_VALB
LDIR
XOR  A
RET
EX_PVEMP:
POP  DE
JR   EX_IFAIL
; Convert value index A to EX_VSTAC + A*10 without multiplication support.
;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
EX_VADR:
LD   E,A
LD   D,0
LD   H,D
LD   L,E
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
EX   DE,HL
ADD  HL,HL
ADD  HL,DE
LD   DE,EX_VSTAC
ADD  HL,DE
RET
; Push the current four-byte operator record after proving stack capacity.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_POPE1:
LD   A,(EX_ODEPT)
CP   EX_OCAP
JR   NC,EX_CFAIL
CALL EX_OADR
LD   D,H
LD   E,L
LD   HL,EX_OPER
LD   BC,EX_OPERB
LDIR
LD   HL,EX_ODEPT
INC  (HL)
XOR  A
RET
; Pop the most recent operator into EX_OPER. As with the value stack, an empty
; pop is an internal invariant failure rather than a source diagnostic.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE
EX_POPE2:
LD   A,(EX_ODEPT)
OR   A
JR   Z,EX_IFAIL
DEC  A
LD   (EX_ODEPT),A
CALL EX_OADR
LD   DE,EX_OPER
LD   BC,EX_OPERB
LDIR
XOR  A
RET
; Convert operator index A to EX_OSTAC + A*4.
;@ROUTINE IN A OUT HL CLOBBERS DE,A,F
EX_OADR:
LD   L,A
LD   H,0
ADD  HL,HL
ADD  HL,HL
LD   DE,EX_OSTAC
ADD  HL,DE
RET
; Peek at the encoded byte of the newest operator without changing stack depth.
; Carry set reports an empty stack; otherwise A contains the encoded operator.
;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,DE,HL
EX_POPE3:
LD   A,(EX_ODEPT)
OR   A
SCF
RET  Z
DEC  A
CALL EX_OADR
LD   A,(HL)
OR   A
RET
; Capacity failures point at the token that could not be pushed.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_CFAIL:
LD   A,EX_SCAP
JP   EX_FHERE
; Stack underflow and unmatched internal markers are defensive failures. Valid
; source should reach a specific syntax status before this path.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_IFAIL:
LD   A,EX_SINT
JP   EX_FHERE
; Save the current operator record while precedence reduction overwrites
; EX_OPER with older stack entries.
;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
EX_SINCO:
LD   HL,EX_OPER
LD   DE,EX_INCOM
JR   EX_CINCO
; Restore the saved incoming operator before pushing it.
;@ROUTINE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
EX_RINCO:
LD   HL,EX_INCOM
LD   DE,EX_OPER
; Copy one complete four-byte operator record from HL to DE.
;@ROUTINE IN HL,DE OUT CARRY,ZERO CLOBBERS BC,DE,HL,PARITY,HALFCARRY,SIGN,A
EX_CINCO:
LD   BC,EX_OPERB
LDIR
RET
; Reduce stacked binary operators before accepting the saved incoming operator.
; High nibbles hold precedence. A stacked operator reduces when its precedence
; is higher, or equal for the left-associative operator set used here.
;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
EX_RINC1:
.RILOOP:
CALL EX_POPE3
JR   C,.RIDONE
CP   EX_MLPAR
JR   Z,.RIDONE
; Compare only precedence nibbles. Lower numeric values bind less tightly.
AND  $F0
LD   B,A
LD   A,(EX_INCOM)
AND  $F0
CP   B
JR   C,.RINOW
RET  NZ
.RINOW:
CALL EX_REDUC
RET  C
JR   .RILOOP
.RIDONE:
XOR  A
RET
; Reduce until the nearest left-parenthesis marker is exposed. The caller then
; pops the marker itself. Reaching the bottom first is an internal mismatch.
;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
EX_RTPAR:
.RTPLOOP:
CALL EX_POPE3
JR   C,EX_IFAIL
CP   EX_MLPAR
RET  Z
CALL EX_REDUC
RET  C
JR   .RTPLOOP
; Apply every consecutive unary marker above the newly published primary. A
; concrete value supports all five markers. A deferred value supports unary '+'
; and one LOW or HIGH transform only because the pending ABI stores no tree.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
EX_AUNAR:
.AULOOP:
CALL EX_POPE3
JR   C,.AUDONE
AND  $F0
CP   $70
JR   NZ,.AUDONE
CALL EX_POPE2
RET  C
CALL EX_PVAL1
RET  C
LD   A,(EX_RUNRE)
OR   A
JR   Z,.AUCONCRE
; Deferred unary minus and complement cannot be represented. LOW or HIGH can be
; applied only to a plain deferred symbol and become its patch transform.
LD   A,(EX_OPER)
CP   EX_UPLUS
JR   Z,.AUPUBLIS
CP   EX_ULO
JR   Z,.AUFLO
CP   EX_UHI
JR   Z,.AUFHI
.AUFFAIL:
LD   A,EX_SFFOR
JP   EX_FOPER
.AUFLO:
LD   B,EX_FLO
JR   .AUFFUNCT
.AUFHI:
LD   B,EX_FHI
.AUFFUNCT:
LD   A,(EX_RUNRE)
CP   EX_FPLAI
JR   NZ,.AUFFAIL
LD   A,B
LD   (EX_RUNRE),A
JR   .AUPUBLIS
.AUCONCRE:
; Dispatch concrete unary operations. LOW clears the upper bytes; HIGH moves
; the middle byte down and clears the rest.
LD   A,(EX_OPER)
CP   EX_UPLUS
JR   Z,.AUPUBLIS
CP   EX_UMINU
JR   Z,.AUNEGATE
CP   EX_UTILD
JR   Z,.AUCOMPLE
CP   EX_ULO
JR   Z,.AULO
CP   EX_UHI
JR   Z,.AUHI
JP   EX_IFAIL
.AUNEGATE:
CALL EX_NRES
JR   .AUCDONE
.AUCOMPLE:
CALL EX_CRES
JR   .AUCDONE
.AULO:
XOR  A
LD   (EX_RVAL+1),A
LD   (EX_RVAL+2),A
JR   .AUCDONE
.AUHI:
LD   A,(EX_RVAL+1)
LD   (EX_RVAL),A
XOR  A
LD   (EX_RVAL+1),A
LD   (EX_RVAL+2),A
.AUCDONE:
RET  C
.AUPUBLIS:
; Publish the transformed value again so another outer unary marker can apply.
CALL EX_PVAL
RET  C
JP   .AULOOP
.AUDONE:
XOR  A
RET
; Finish an expression at its delimiter. Reduce every remaining binary operator,
; reject an unmatched left parenthesis and require exactly one final value.
;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
EX_FSTAC:
.FREDUCE:
CALL EX_POPE3
JR   C,.FINVAL
CP   EX_MLPAR
JP   Z,EX_IFAIL
CALL EX_REDUC
RET  C
JR   .FREDUCE
.FINVAL:
CALL EX_PVAL1
RET  C
LD   A,(EX_VDEPT)
OR   A
JP   NZ,EX_IFAIL
RET
; Pop one operator and its right and left values, reduce into EX_RVAL then push
; the result. Right-before-left stack order preserves the source operand order
; for subtraction, division, remainder and shifts.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
EX_REDUC:
CALL EX_POPE2
RET  C
CALL EX_PVAL1
RET  C
CALL EX_PLVAL
RET  C
CALL EX_RLOAD
RET  C
JP   EX_PVAL
; Choose concrete or deferred reduction. Concrete operator ordinals index the
; address table after the low nibble has been range-checked.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_RLOAD:
LD   A,(EX_LUNRE)
LD   B,A
LD   A,(EX_RUNRE)
OR   B
JR   NZ,EX_RFORW
LD   A,(EX_OPER)
AND  $0F
CP   10
JP   NC,EX_IFAIL
ADD  A,A
LD   L,A
LD   H,0
LD   DE,EX_RTABL
ADD  HL,DE
LD   E,(HL)
INC  HL
LD   D,(HL)
EX   DE,HL
JP   (HL)
; Order matches EX_OPOR through EX_OREMA in the operator byte's low nibble.
EX_RTABL:
DW EX_OR,EX_XOR,EX_AND
DW EX_SLEFT,EX_SRIGH
DW EX_ADD,EX_SUBTR
DW EX_MULTI,EX_DIVID
DW EX_REMAI
; Reduce an expression containing one unresolved symbol. LOW and HIGH results
; cannot take further binary arithmetic. Plain forms permit symbol+constant,
; constant+symbol and symbol-constant only.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_RFORW:
; A transform value of EX_FLO or EX_FHI means LOW/HIGH has already consumed the
; symbol form. Any binary operator outside that function is unsupported.
LD   A,(EX_LUNRE)
CP   EX_FLO
JR   NC,.FFAIL
LD   A,(EX_RUNRE)
CP   EX_FLO
JR   NC,.FFAIL
LD   A,(EX_LUNRE)
OR   A
JR   Z,.FRIGHT
; When the symbol is on the left, addition and subtraction both preserve one
; symbol. Concrete arithmetic updates the addend in EX_RVAL.
LD   A,(EX_RUNRE)
OR   A
JR   NZ,.FFAIL
LD   A,(EX_OPER)
AND  $0F
CP   EX_OPADD
JR   Z,.FLADD
CP   EX_OSUBT
JR   NZ,.FFAIL
CALL EX_SUBTR
JR   C,.FRETURN
JR   .FULKEY
.FLADD:
CALL EX_ADD
JR   C,.FRETURN
.FULKEY:
; The left operand carried the symbol, so replace the right operand's concrete
; key bytes with the left packed key.
LD   HL,EX_LKEY
LD   DE,EX_RKEY
LD   BC,6
LDIR
JR   .FFIN
.FRIGHT:
; A symbol on the right is valid only for constant+symbol. constant-symbol would
; require a negated symbol coefficient and cannot fit the pending record.
LD   A,(EX_OPER)
AND  $0F
CP   EX_OPADD
JR   NZ,.FFAIL
CALL EX_ADD
JR   C,.FRETURN
.FFIN:
; Canonicalise the surviving result as a plain deferred symbol and prove that
; its computed addend fits the signed byte stored by the pending record.
LD   A,EX_FPLAI
LD   (EX_RUNRE),A
CALL EX_RADDE
.FRETURN:
RET
.FFAIL:
LD   A,EX_SFFOR
JP   EX_FOPER
; Load the low bytes and sign bytes used by the 24-bit add/subtract paths. A is
; the left low byte, HL points at the right result and B/C retain both signs.
;@ROUTINE OUT A,BC,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
EX_LARIT:
LD   A,(EX_LVAL+2)
LD   B,A
LD   A,(EX_RVAL+2)
LD   C,A
LD   A,(EX_LVAL)
LD   HL,EX_RVAL
RET
; Add signed 24-bit operands into EX_RVAL. Equal-sign inputs may overflow only
; if the result sign changes; mixed-sign inputs cannot overflow.
;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
EX_ADD:
CALL EX_LARIT
ADD  A,(HL)
LD   (HL),A
INC  HL
LD   A,(EX_LVAL+1)
ADC  A,(HL)
LD   (HL),A
INC  HL
LD   A,B
ADC  A,(HL)
LD   (HL),A
LD   D,A
LD   A,B
XOR  C
BIT  7,A
JR   NZ,EX_AOK
LD   A,B
XOR  D
BIT  7,A
JP   NZ,EX_ROPER
; Shared arithmetic success tail clears carry and returns EX_RESOL in A.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS SIGN,PARITY,HALFCARRY
EX_AOK:
XOR  A
RET
; Subtract EX_RVAL from EX_LVAL into EX_RVAL. Different-sign inputs may overflow
; only if the result sign differs from the left operand.
;@ROUTINE OUT A,CARRY CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO,IX,IY
EX_SUBTR:
CALL EX_LARIT
SUB  (HL)
LD   (HL),A
INC  HL
LD   A,(EX_LVAL+1)
SBC  A,(HL)
LD   (HL),A
INC  HL
LD   A,B
SBC  A,(HL)
LD   (HL),A
LD   D,A
LD   A,B
XOR  C
BIT  7,A
JR   Z,EX_AOK
LD   A,B
XOR  D
BIT  7,A
JP   NZ,EX_ROPER
JR   EX_AOK
; Apply bitwise AND to all three bytes of the 24-bit working values.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
EX_AND:
LD   HL,EX_RVAL
LD   DE,EX_LVAL
LD   B,3
.ANDLOOP:
LD   A,(DE)
AND  (HL)
LD   (HL),A
INC  DE
INC  HL
DJNZ .ANDLOOP
XOR  A
RET
; Apply bitwise XOR to all three bytes of the 24-bit working values.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
EX_XOR:
LD   HL,EX_RVAL
LD   DE,EX_LVAL
LD   B,3
.XORLOOP:
LD   A,(DE)
XOR  (HL)
LD   (HL),A
INC  DE
INC  HL
DJNZ .XORLOOP
XOR  A
RET
; Apply bitwise OR to all three bytes of the 24-bit working values.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
EX_OR:
LD   HL,EX_RVAL
LD   DE,EX_LVAL
LD   B,3
.ORLOOP:
LD   A,(DE)
OR   (HL)
LD   (HL),A
INC  DE
INC  HL
DJNZ .ORLOOP
XOR  A
RET
; Shift the little-endian 24-bit value at HL left by one bit. Carry propagates
; from low to high byte and reports the bit discarded from the sign byte.
;@ROUTINE IN HL OUT A,HL,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
EX_SL24:
LD   A,(HL)
SLA  A
LD   (HL),A
INC  HL
LD   A,(HL)
RL   A
LD   (HL),A
INC  HL
LD   A,(HL)
RL   A
LD   (HL),A
RET
; Validate the right operand as a count from 0 through 23, then shift the left
; operand repeatedly. A sign change on any step reports signed 24-bit overflow.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
EX_SLEFT:
CALL EX_SCNT
RET  C
LD   B,A
OR   A
JR   Z,.SLCOPY
.SLLOOP:
; C retains the sign byte before the shift so XOR detects a changed sign bit.
LD   A,(EX_LVAL+2)
LD   C,A
LD   HL,EX_LVAL
CALL EX_SL24
XOR  C
BIT  7,A
JP   NZ,EX_ROPER
DJNZ .SLLOOP
.SLCOPY:
; Binary reducers publish their result through EX_RVAL, so copy the shifted left
; operand there even when the count was zero.
LD   HL,EX_LVAL
LD   DE,EX_RVAL
LD   BC,3
LDIR
XOR  A
RET
; Copy the left operand to EX_RVAL, then perform an arithmetic right shift for
; each requested bit. SRA preserves the 24-bit sign in the high byte and RR
; propagates it through the lower sixteen bits.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
EX_SRIGH:
CALL EX_SCNT
RET  C
LD   B,A
PUSH BC
LD   HL,EX_LVAL
LD   DE,EX_RVAL
LD   BC,3
LDIR
POP  BC
LD   A,B
OR   A
JP   Z,EX_AOK
LD   B,A
.SRLOOP:
LD   HL,EX_RVAL+2
LD   A,(HL)
SRA  A
CALL EX_SRL16
DJNZ .SRLOOP
XOR  A
RET
; Accept only a non-negative 24-bit shift count less than 24. Any non-zero upper
; byte or low byte of 24 and above is a range error at the operator position.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_SCNT:
LD   A,(EX_RVAL+2)
OR   A
JP   NZ,EX_ROPER
LD   A,(EX_RVAL+1)
OR   A
JP   NZ,EX_ROPER
LD   A,(EX_RVAL)
CP   24
JP   NC,EX_ROPER
OR   A
RET
; Multiply signed 24-bit operands by shift and add. Magnitude preparation makes
; the loop unsigned; EX_SRES records whether the final result must be negated.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_MULTI:
CALL EX_PMAGN
XOR  A
LD   (EX_ACCUM),A
LD   (EX_ACCUM+1),A
LD   (EX_ACCUM+2),A
LD   A,24
LD   (EX_MCOUN),A
.MLOOP:
; Add the current multiplicand when the multiplier's low bit is set. Carry from
; the 24-bit accumulator is an overflow.
LD   A,(EX_MRIGH)
BIT  0,A
JR   Z,.MSADD
CALL EX_AALEF
JP   C,EX_ROPER
.MSADD:
CALL EX_MRSHI
; Stop as soon as the shifted multiplier becomes zero. This avoids needless
; remaining rounds without changing the fixed 24-bit result.
LD   A,(EX_MRIGH)
LD   C,A
LD   A,(EX_MRIGH+1)
OR   C
LD   C,A
LD   A,(EX_MRIGH+2)
OR   C
JR   Z,.MDONE
; A multiplicand with its top bit already set cannot be shifted left again in
; the positive-magnitude domain.
LD   A,(EX_MLEFT+2)
BIT  7,A
JP   NZ,EX_ROPER
CALL EX_MLSHI
LD   HL,EX_MCOUN
DEC  (HL)
JR   NZ,.MLOOP
.MDONE:
; Move the accumulated magnitude to the normal result slot and restore the
; computed sign.
LD   HL,EX_ACCUM
LD   DE,EX_RVAL
LD   BC,3
LDIR
LD   A,(EX_SRES)
OR   A
EX_ASRES:
CALL NZ,EX_NRES
RET  C
XOR  A
RET
; Select quotient mode and share the signed long-division implementation.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_DIVID:
XOR  A
LD   (EX_DRMOD),A
JR   EX_DCOMM
; Select remainder mode. The final remainder uses the dividend's sign rather
; than the quotient's XOR sign.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
EX_REMAI:
LD   A,1
LD   (EX_DRMOD),A
; Divide magnitudes with 24 rounds of restoring long division. EX_MLEFT is the
; shifting dividend, EX_MRIGH the divisor, EX_ACCUM the partial remainder and
; EX_QUOTI the quotient.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY,ZERO
EX_DCOMM:
; Reject zero before magnitude conversion.
LD   A,(EX_RVAL)
LD   B,A
LD   A,(EX_RVAL+1)
OR   B
LD   B,A
LD   A,(EX_RVAL+2)
OR   B
JR   Z,.DZERO
CALL EX_PMAGN
XOR  A
LD   (EX_ACCUM),A
LD   (EX_ACCUM+1),A
LD   (EX_ACCUM+2),A
LD   (EX_QUOTI),A
LD   (EX_QUOTI+1),A
LD   (EX_QUOTI+2),A
LD   B,24
.DLOOP:
; Shift the next dividend bit into the partial remainder and make room for the
; next quotient bit.
LD   HL,EX_MLEFT
CALL EX_SL24
LD   HL,EX_ACCUM
LD   A,(HL)
RL   A
LD   (HL),A
INC  HL
LD   A,(HL)
RL   A
LD   (HL),A
INC  HL
LD   A,(HL)
RL   A
LD   (HL),A
LD   HL,EX_QUOTI
CALL EX_SL24
; If remainder >= divisor, subtract the divisor and set the new quotient bit.
CALL EX_RALDI
JR   C,.DNEXT
CALL EX_RSDIV
LD   HL,EX_QUOTI
LD   A,(HL)
SET  0,A
LD   (HL),A
.DNEXT:
DJNZ .DLOOP
; Choose quotient or remainder storage and the corresponding sign bit.
LD   A,(EX_DRMOD)
OR   A
JR   NZ,.UREMAIND
LD   HL,EX_QUOTI
LD   A,(EX_SRES)
JR   .DSTORE
.UREMAIND:
LD   HL,EX_ACCUM
LD   A,(EX_SLEF1)
.DSTORE:
LD   DE,EX_RVAL
LD   BC,3
LDIR
OR   A
JP   EX_ASRES
.DZERO:
LD   A,EX_SDZER
JP   EX_FOPER
; Copy both signed operands to magnitude workspace, record their signs and
; negate negative inputs. The quotient/product sign is left-sign XOR right-sign.
;@ROUTINE OUT CARRY,ZERO CLOBBERS A,BC,DE,HL,IX,IY,SIGN,PARITY,HALFCARRY
EX_PMAGN:
LD   HL,EX_LVAL
LD   DE,EX_MLEFT
LD   BC,3
LDIR
LD   HL,EX_RVAL
LD   DE,EX_MRIGH
LD   BC,3
LDIR
LD   A,(EX_LVAL+2)
RLCA
AND  1
LD   (EX_SLEF1),A
OR   A
CALL NZ,EX_NMLEF
LD   A,(EX_RVAL+2)
RLCA
AND  1
LD   (EX_SRIG1),A
OR   A
CALL NZ,EX_NMRIG
LD   A,(EX_SLEF1)
LD   HL,EX_SRIG1
XOR  (HL)
LD   (EX_SRES),A
OR   A
RET
; Negate the normal result slot in place.
;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
EX_NRES:
LD   HL,EX_RVAL
JR   EX_NAHL
; Negate the copied left magnitude in place.
;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A,BC,DE,IX,IY
EX_NMLEF:
LD   HL,EX_MLEFT
JR   EX_NAHL
; Negate the copied right magnitude and fall through to the shared 24-bit body.
;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,A,BC,DE,IX,IY,SIGN,PARITY,HALFCARRY
EX_NMRIG:
LD   HL,EX_MRIGH
; Form the two's complement of the little-endian 24-bit value at HL.
;@ROUTINE IN HL OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
EX_NAHL:
LD   A,(HL)
CPL
ADD  A,1
LD   (HL),A
INC  HL
LD   A,(HL)
CPL
ADC  A,0
LD   (HL),A
INC  HL
LD   A,(HL)
CPL
ADC  A,0
LD   (HL),A
XOR  A
RET
; Complement all three bytes of EX_RVAL for unary '~'.
;@ROUTINE OUT CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,A
EX_CRES:
LD   HL,EX_RVAL
LD   A,(HL)
CPL
LD   (HL),A
INC  HL
LD   A,(HL)
CPL
LD   (HL),A
INC  HL
LD   A,(HL)
CPL
LD   (HL),A
XOR  A
RET
; Add EX_MLEFT to the 24-bit product accumulator. Carry reports unsigned
; overflow beyond the high byte.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_AALEF:
LD   HL,EX_ACCUM
LD   A,(EX_MLEFT)
ADD  A,(HL)
LD   (HL),A
INC  HL
LD   A,(EX_MLEFT+1)
ADC  A,(HL)
LD   (HL),A
INC  HL
LD   A,(EX_MLEFT+2)
ADC  A,(HL)
LD   (HL),A
RET
; Shift the multiplication multiplicand left by one bit.
;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
EX_MLSHI:
LD   HL,EX_MLEFT
JP   EX_SL24
; Shift the unsigned multiplier magnitude right by one bit. SRL clears the high
; sign position and the shared tail rotates carry through the low sixteen bits.
;@ROUTINE OUT CARRY,ZERO MAYBE-OUT BC,DE CLOBBERS A,HL,SIGN,PARITY,HALFCARRY,IX,IY,BC,DE
EX_MRSHI:
LD   HL,EX_MRIGH+2
LD   A,(HL)
SRL  A
; Store the already-shifted high byte in A, then rotate the two lower bytes at
; HL-1 and HL-2 through carry. The arithmetic right-shift path also enters here.
;@ROUTINE IN A,HL OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
EX_SRL16:
LD   (HL),A
DEC  HL
LD   A,(HL)
RR   A
LD   (HL),A
DEC  HL
LD   A,(HL)
RR   A
LD   (HL),A
RET
; Compare the partial remainder with the divisor as unsigned 24-bit magnitudes,
; most-significant byte first. Carry means remainder is smaller.
;@ROUTINE OUT A,CARRY,ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY
EX_RALDI:
LD   A,(EX_ACCUM+2)
LD   HL,EX_MRIGH+2
CP   (HL)
RET  NZ
LD   A,(EX_ACCUM+1)
DEC  HL
CP   (HL)
RET  NZ
LD   A,(EX_ACCUM)
DEC  HL
CP   (HL)
RET
; Subtract the divisor magnitude from the partial remainder in place.
;@ROUTINE OUT CARRY,ZERO CLOBBERS A,C,DE,HL,SIGN,PARITY,HALFCARRY
EX_RSDIV:
LD   HL,EX_ACCUM
LD   DE,EX_MRIGH
LD   A,(DE)
LD   C,A
LD   A,(HL)
SUB  C
LD   (HL),A
INC  HL
INC  DE
LD   A,(DE)
LD   C,A
LD   A,(HL)
SBC  A,C
LD   (HL),A
INC  HL
INC  DE
LD   A,(DE)
LD   C,A
LD   A,(HL)
SBC  A,C
LD   (HL),A
RET
; Expand the resolved word in HL into EX_RVAL and clear both the 24-bit high
; byte and the deferred-state marker.
;@ROUTINE IN HL OUT CARRY,ZERO CLOBBERS A,SIGN,PARITY,HALFCARRY
EX_SRW:
LD   (EX_RVAL),HL
XOR  A
LD   (EX_RVAL+2),A
LD   (EX_RUNRE),A
RET
; Require a resolved 24-bit result in the final word domain. Positive values may
; reach $00FFFF; negative values must be sign-extended from $FF8000..$FFFFFF.
;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL
EX_REQW:
LD   A,(EX_RVAL+2)
OR   A
RET  Z
INC  A
JR   NZ,.RHERE
LD   A,(EX_RVAL+1)
BIT  7,A
RET  NZ
.RHERE:
LD   A,EX_SRANG
JR   EX_FHERE
; Require the 24-bit deferred addend to be exactly sign-extended from one byte:
; $000000..$00007F or $FFFF80..$FFFFFF.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY,BC,DE,IX,IY
EX_RADDE:
LD   A,(EX_RVAL+2)
OR   A
JR   Z,.APOSITIV
INC  A
JR   NZ,EX_ROPER
LD   A,(EX_RVAL+1)
INC  A
JR   NZ,EX_ROPER
LD   A,(EX_RVAL)
BIT  7,A
RET  NZ
JR   EX_ROPER
.APOSITIV:
LD   A,(EX_RVAL+1)
OR   A
JR   NZ,EX_ROPER
LD   A,(EX_RVAL)
BIT  7,A
JR   NZ,EX_ROPER
OR   A
RET
; Advance the tokenizer. A lexical failure carries the tokenizer's own source
; position rather than the expression's current operator or token position.
;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
EX_NTOK:
CALL TK_NEXT
RET  NC
LD   A,EX_SLEXI
JR   EX_FTOKE
; Report a numeric range error at the operator whose calculation failed.
;@ROUTINE OUT A,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
EX_ROPER:
LD   A,EX_SRANG
JR   EX_FOPER
; Use the current token's stored source position for primary, delimiter and
; capacity failures.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
EX_FHERE:
LD   HL,TK_REC+TK_POFF
JR   EX_FPOSI
; Use the saved operator position for arithmetic and unsupported-form failures.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
EX_FOPER:
LD   HL,EX_OPART
JR   EX_FPOSI
; Use the saved name position for symbol packing and lookup failures.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
EX_FSYM:
LD   HL,EX_SPART
JR   EX_FPOSI
; Use the tokenizer's independently recorded failure position for lexical errors.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
EX_FTOKE:
LD   HL,TK_EPART
; Copy the contiguous part-and-offset triple at HL into the public expression
; error fields, preserve the status in A and set carry.
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
EX_FPOSI:
PUSH BC
PUSH DE
LD   DE,EX_EPART
LD   BC,3
LDIR
POP  DE
POP  BC
SCF
RET
EX_RCEND:
EX_CEND:
EX_WBEG:
; Persistent state for one parse. EX_CADR gives '$' its statement address and
; EX_PSYM selects direct publication or caller-managed deferred publication.
EX_CADR: DW 0
EX_PSYM: DB 0
; Current/right value record: signed 24-bit value or addend, deferred transform
; and six-byte exact packed key.
EX_RVAL: DS 3
EX_RUNRE: DB 0
EX_RKEY: DS 6
; Left value record loaded during binary reduction.
EX_LVAL: DS 3
EX_LUNRE: DB 0
EX_LKEY: DS 6
; Current operator record and a spare copy used while precedence reduction loads
; older operators from the stack.
EX_OPER: DB 0
EX_OPART: DB 0
EX_OOFF: DW 0
EX_INCOM: DS EX_OPERB
; Saved name diagnostics and nested symbol status. Multiply and divide reuse
; these bytes while reducing a concrete pair. Because the source position is not
; copied into a value-stack entry, a concrete subexpression evaluated after a
; deferred name can currently overwrite that name's later diagnostic anchor.
EX_SPART: DB 0
EX_SOFF: DW 0
EX_SSTAT: DB 0
EX_MCOUN EQU EX_SSTAT
; Bounded parser state. EX_EOP is one when the grammar requires a primary and
; zero when it requires an operator or delimiter.
EX_VDEPT: DB 0
EX_ODEPT: DB 0
EX_PDEPT: DB 0
EX_EOP: DB 0
; Multiply and divide overlay the two popped operand-key slots with magnitudes,
; accumulator and quotient. Both popped operands are concrete on these paths, so
; their keys are dead. The sign fields also overlay the saved name position as
; described above.
EX_SLEF1 EQU EX_SPART
EX_SRIG1 EQU EX_SOFF
EX_SRES EQU EX_SOFF+1
EX_DRMOD EQU EX_MCOUN
EX_MLEFT EQU EX_RKEY
EX_MRIGH EQU EX_RKEY+3
EX_ACCUM EQU EX_LKEY
EX_EPART EQU EX_ACCUM
EX_EOFF EQU EX_ACCUM+1
EX_QUOTI EQU EX_LKEY+3
; Sixteen ten-byte value entries followed by sixteen four-byte operator entries.
; The complete fixed expression workspace is 263 bytes.
EX_VSTAC: DS EX_VALB*EX_VCAP
EX_OSTAC: DS EX_OPERB*EX_OCAP
EX_WEND:
