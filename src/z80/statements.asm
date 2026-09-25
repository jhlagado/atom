;==============================================================================
;  Statements, labels and directives
;==============================================================================
;
;  PURPOSE
;  -------
;  Turn the token stream for one source part into labels, constants, directives
;  and encoded instructions. This layer owns source-statement grammar; it leaves
;  token recognition, expression arithmetic, instruction forms, symbols and
;  output transactions to the modules below it.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
;+---------------------------------------------------------------------------+
;| DR_APART / ST_NEXT - Assemble the current source part.                    |
;|                                                                           |
;| Entry: TK_RESET has selected a source part and range.                     |
;| Result: Carry clear and A = 0 after that part reaches EOF.                 |
;| Error: Carry set and A = ST_S* category. ST_DETAI contains the nested      |
;|        subsystem status; ST_EPART/ST_EOFF retain the statement location.  |
;| Side effects: Declares symbols and emits IMAGE/PATCH operations.           |
;+---------------------------------------------------------------------------+
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
;  references and removes their pending records only after the sink accepts the
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
ST_SOK EQU 0
ST_SLEXI EQU 1
ST_SEXP EQU 2
ST_SDIR EQU 3
ST_SEQUA EQU 4
ST_SSYM EQU 5
ST_SINS EQU 6
ST_SOUT EQU 7
ST_SUNDE EQU 8
ST_SINT EQU 9
; Directive ordinals returned by EN_RDIR and used by the dispatch table.
ST_EQU EQU 1
ST_ORG EQU 2
ST_DB EQU 3
ST_DW EQU 4
ST_DS EQU 5
ST_CSTR EQU 6
ST_PSTR EQU 7
ST_ISTR EQU 8
ST_ALIGN EQU 9
ST_CNT EQU 9
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
DR_APART:
ST_NEXT:
; Fetch the first significant token. EOF finishes only this source part; an EOL
; is an empty statement and simply restarts the loop.
CALL ST_NTKIN
JP   C,ST_LFAIL
CP   TK_EOF
JP   Z,ST_SUCCE
CP   TK_EOL
JR   Z,ST_NEXT
CP   TK_NAME
JP   NZ,ST_EHERE
; Preserve the statement's starting position before any nested parser advances
; the tokenizer. All later failures on this line report this stable location.
CALL ST_CPOSI
; Pack the leading name once as a possible label or EQU destination.
CALL TK_LLEXE
LD   DE,ST_KEY
CALL EN_PSYM
JP   C,ST_SFAIL
; Independently classify the same lexeme as a mnemonic. ST_MVALI records whether
; ST_MNEM is meaningful; an ordinal of zero is not used as a validity sentinel.
CALL TK_LLEXE
CALL EN_RECOG
JR   C,ST_NMNEM
LD   (ST_MNEM),A
LD   A,1
LD   (ST_MVALI),A
XOR  A
LD   (ST_DVALI),A
JR   ST_AFNAM
ST_NMNEM:
; If it was not a mnemonic, test the compact directive table and cache that
; result in the parallel ST_DIR/ST_DVALI pair.
XOR  A
LD   (ST_MVALI),A
CALL TK_LLEXE
CALL EN_RDIR
JR   C,ST_NDIR
LD   (ST_DIR),A
LD   A,1
LD   (ST_DVALI),A
JR   ST_AFNAM
ST_NDIR:
XOR  A
LD   (ST_DVALI),A
ST_AFNAM:
; The token after the leading name determines whether the packed name is a
; declaration target or whether the name itself selects the statement kind.
CALL ST_NTKIN
JP   C,ST_LFAIL
CP   TK_COLON
JR   Z,ST_LABEL
; A recognized mnemonic without a colon begins an instruction immediately.
LD   A,(ST_MVALI)
OR   A
JP   NZ,ST_IPUB
; A recognized non-EQU directive without a colon goes to directive dispatch.
LD   A,(ST_DVALI)
OR   A
JR   Z,ST_TEQUA
LD   A,(ST_DIR)
JP   ST_DPUB
ST_TEQUA:
; An unrecognized leading name may still be the destination of colonless EQU.
; The current token must itself be the recognized EQU directive.
LD   A,(TK_REC+TK_KOFF)
CP   TK_NAME
JP   NZ,ST_ESAVE
CALL TK_LLEXE
CALL EN_RDIR
JP   C,ST_ESAVE
CP   ST_EQU
JP   NZ,ST_ESAVE
JP   ST_EQUAT
ST_LABEL:
; After a colon, recognize the special convenience form "label: EQU value".
; Any other token leaves the declaration as an address label.
CALL ST_NTKIN
JP   C,ST_LFAIL
CP   TK_NAME
JR   NZ,ST_LPUBL
CALL TK_LLEXE
CALL EN_RDIR
JR   C,ST_LPUBL
CP   ST_EQU
JR   Z,ST_EQUAT
ST_LPUBL:
; The packed key's private bit selects the declaration rule. A global address
; label closes the previous private scope; a private label remains within it.
LD   HL,ST_KEY+5
BIT  7,(HL)
LD   HL,ST_KEY
LD   DE,(OU_CURSO)
JR   NZ,ST_PLABE
CALL SY_DGLAB
JR   ST_LDECL
ST_PLABE:
CALL SY_DECL
ST_LDECL:
JP   C,ST_SFAIL
; A newly known address may satisfy several forward references. Resolution is
; transactional with the sink and leaves diagnostics intact on failure.
CALL OU_RSLV
JP   C,ST_OFAIL
; A bare label ends at EOL. Otherwise the same line may continue with exactly
; one instruction or directive name.
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   Z,ST_NEXT
CP   TK_NAME
JP   NZ,ST_EHERE
CALL ST_CPOSI
CALL TK_LLEXE
CALL EN_RECOG
JR   C,ST_LDIR
; Publish the recognized mnemonic, consume the name token and share the ordinary
; instruction path used by statements without a label.
LD   (ST_MNEM),A
CALL TK_NEXT
JP   C,ST_LFAIL
JR   ST_IPUB
ST_LDIR:
; The post-label name was not a mnemonic. It must be a recognized directive.
CALL TK_LLEXE
CALL EN_RDIR
JP   C,ST_ESAVE
LD   (ST_DIR),A
CALL TK_NEXT
JP   C,ST_LFAIL
LD   A,(ST_DIR)
JR   ST_DPUB
ST_IPUB:
; Parse and validate operands into ST_INS using the current output cursor as the
; instruction address. Relative expressions depend on that address.
LD   A,(ST_MNEM)
LD   BC,(OU_CURSO)
LD   DE,ST_INS
CALL PR_PUB
JP   C,ST_IFAIL
; Emit the validated instruction's one-to-four bytes, then fetch the next line.
CALL OU_EINS
ST_OTNEX:
JP   C,ST_OFAIL
JP   ST_NEXT
ST_EQUAT:
; Consume EQU and evaluate its expression at the current output address.
CALL TK_NEXT
JP   C,ST_LFAIL
CALL ST_PEXPR
JP   C,ST_EFAIL
; EQU must be known now. Allowing a forward EQU would require delayed expression
; evaluation rather than the byte patches used for address references.
OR   A
JP   NZ,ST_EUNRE
; Save the low 16-bit value and derive its signedness from the expression's high
; extension byte: zero is unsigned/non-negative, nonzero is negative.
LD   (ST_EVAL),HL
XOR  A
LD   HL,EX_RVAL+2
CP   (HL)
JR   Z,ST_ESREA
INC  A
ST_ESREA:
LD   (ST_ESIGN),A
; No token may follow the EQU expression on the statement.
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   NZ,ST_EDELI
; EQU declares within the current scope but never opens a new global-label scope.
LD   HL,ST_KEY
LD   DE,(ST_EVAL)
CALL SY_DECL
JP   C,ST_SFAIL
; Preserve a negative constant's sign-extension flag in the packed symbol record
; before resolving any waiting references to its newly concrete value.
LD   A,(ST_ESIGN)
OR   A
JR   Z,ST_ERSLV
SET  5,(IX+5)
ST_ERSLV:
CALL OU_RSLV
JR   ST_OTNEX
ST_DPUB:
; EQU is handled by the declaration grammar above. Subtracting ST_ORG maps the
; remaining contiguous ordinals onto the eight-entry address table.
SUB  ST_ORG
CP   8
JP   NC,ST_ESAVE
ADD  A,A
LD   L,A
LD   H,0
LD   DE,ST_DDTAB
ADD  HL,DE
LD   E,(HL)
INC  HL
LD   D,(HL)
EX   DE,HL
JP   (HL)
ST_DDTAB:
; ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN handlers in ordinal order.
DW ST_ORG1,ST_DB1,ST_DW1,ST_DS1
DW ST_CSTR1,ST_PSTR1,ST_ISTR1
DW ST_ALIG1
ST_ORG1:
; ORG requires one concrete expression and no trailing token. The output layer
; enforces target bounds and represents any gap according to the sink contract.
CALL ST_PEXPR
JP   C,ST_DFAIL
OR   A
JP   NZ,ST_DUNR1
LD   (ST_DVAL),HL
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   NZ,ST_DDEL1
LD   HL,(ST_DVAL)
CALL OU_SORIG
JP   ST_OTNEX
ST_DB1:
; Data-list width and default unresolved patch kind distinguish DB from DW; both
; then share the comma-separated item loop.
LD   A,1
LD   (ST_DWIDT),A
LD   A,PT_KTB
LD   (ST_DPKIN),A
JR   ST_DITEM
ST_DW1:
LD   A,2
LD   (ST_DWIDT),A
LD   A,PT_KINDW
LD   (ST_DPKIN),A
ST_DITEM:
; A data list cannot be empty or end immediately after a comma.
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   Z,ST_DEXP
; Quoted strings are accepted only in DB. They use mode zero so the common
; string emitter returns to the data-list delimiter path rather than ending the
; whole statement.
CP   TK_STRIN
JR   NZ,ST_DEXPR
LD   A,(ST_DWIDT)
CP   1
JP   NZ,ST_DSTR1
XOR  A
LD   (ST_SMODE),A
JP   ST_DSTRI
ST_DEXPR:
; A concrete expression emits its low byte or low word immediately.
CALL ST_PEXPR
JP   C,ST_DFAIL
OR   A
JR   NZ,ST_DUNRE
LD   A,(ST_DWIDT)
CP   1
JR   Z,ST_DRB
CALL OU_EMITW
JR   ST_DORES
ST_DRB:
LD   A,L
CALL OU_EMITB
ST_DORES:
JP   C,ST_OFAIL
JP   ST_DDELI
ST_DUNRE:
; A simple unresolved symbol may be represented by a pending patch. Save the
; expression addend and symbol pointer before any capacity or emission call can
; reuse IX, HL or the shared expression workspace.
LD   A,L
LD   (ST_DADDE),A
PUSH IX
POP  HL
LD   (ST_DKEY),HL
LD   A,(ST_DWIDT)
LD   L,A
LD   H,0
; Prove both output and pending-record capacity before publishing a zero
; placeholder. Failure therefore leaves neither stream nor symbol state changed.
CALL OU_CCAP
JP   C,ST_OFAIL
CALL SY_CCAP
JP   C,ST_SFAIL
LD   A,(EX_RUNRE)
CP   EX_FLO
JR   Z,ST_DPLO
CP   EX_FHI
JR   Z,ST_DPHI
; Plain unresolved DB/DW uses the directive's width-specific patch kind. LOW
; and HIGH expression forms override that with the corresponding byte patch.
LD   A,(ST_DPKIN)
JR   ST_DPKRE
ST_DPLO:
LD   A,PT_KLB
JR   ST_DPKRE
ST_DPHI:
LD   A,PT_KHB
ST_DPKRE:
LD   (ST_DPKI1),A
; Find or create the undefined symbol record. B reports whether this is the
; first reference, which is the one that must retain the diagnostic anchor.
LD   HL,(ST_DKEY)
CALL SY_REF
JP   C,ST_SFAIL
LD   A,B
OR   A
JR   Z,ST_DDREA
; Store the first reference's source offset in the undefined symbol's value word
; and mark this pending record as its diagnostic anchor.
LD   HL,(EX_SOFF)
LD   (IX+SY_VALLO),L
LD   (IX+SY_VALHI),H
LD   A,SY_DANCH
LD   HL,ST_DPKI1
OR   (HL)
LD   (HL),A
ST_DDREA:
; Preserve the symbol and patch address while the placeholder is emitted.
PUSH IX
POP  HL
LD   (ST_DSYM),HL
LD   HL,(OU_CURSO)
LD   (ST_DADR),HL
LD   A,(ST_DWIDT)
CP   1
JR   Z,ST_DPB
; The reserved bytes are zero. A later PATCH operation carries the final value.
LD   HL,0
CALL OU_EMITW
JP   C,ST_OFAIL
JR   ST_DQUEU
ST_DPB:
XOR  A
CALL OU_EMITB
JP   C,ST_OFAIL
ST_DQUEU:
; Append the seven-byte pending record only after the placeholder emission
; succeeds. It captures symbol, target address, kind, addend and source part.
LD   IX,(ST_DSYM)
LD   DE,(ST_DADR)
LD   A,(ST_DPKI1)
LD   B,A
LD   A,(ST_DADDE)
LD   C,A
LD   A,(EX_SPART)
CALL SY_ADD
JP   C,ST_SFAIL
ST_DDELI:
; Accept EOL or a comma followed by another item. A trailing comma is diagnosed
; as a missing expression by returning to ST_DITEM with EOL current.
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   Z,ST_NEXT
CP   TK_COMMA
JP   NZ,ST_DDEL1
CALL ST_NTKIN
JP   C,ST_LFAIL
CP   TK_EOL
JP   Z,ST_DEXP
JP   ST_DITEM
ST_DSTRI:
; First pass over the quoted token: count decoded output bytes without emitting.
; The tokenizer has already validated the closing quote and token length. HL is
; the raw character offset, B the raw bytes remaining, and C the decoded count.
LD   HL,(TK_REC+TK_SOFF)
INC  HL
LD   A,(TK_REC+TK_LOFF1)
SUB  2
LD   B,A
LD   C,0
ST_SCLOO:
LD   A,B
OR   A
JR   Z,ST_SCDON
; Read one raw character through the source service. Preserve the offset across
; the call because TK_SREAD returns the byte in A but may clobber HL.
PUSH HL
LD   A,(TK_REC+TK_POFF)
CALL TK_SREAD
POP  HL
INC  HL
DEC  B
CP   $5C
JR   NZ,ST_SCONE
; A backslash escape consumes at least one additional raw character while still
; producing one byte. A hexadecimal escape consumes two further digits.
PUSH HL
LD   A,(TK_REC+TK_POFF)
CALL TK_SREAD
POP  HL
INC  HL
DEC  B
CP   $78
JR   NZ,ST_SCONE
INC  HL
INC  HL
DEC  B
DEC  B
ST_SCONE:
; Count the decoded byte represented by the raw character or complete escape.
INC  C
JR   ST_SCLOO
ST_SCDON:
; Rewind to the first character and retain all source-service state needed by
; the emission pass. Quotes themselves are excluded from ST_SREM.
LD   A,C
LD   (ST_SCNT),A
LD   HL,(TK_REC+TK_SOFF)
INC  HL
LD   (ST_SPTR),HL
LD   A,(TK_REC+TK_POFF)
LD   (ST_SPART),A
LD   A,(TK_REC+TK_LOFF1)
SUB  2
LD   (ST_SREM),A
; Standalone string directives must occupy the rest of the statement. DB string
; mode deliberately postpones delimiter checking so the data list can continue.
LD   A,(ST_SMODE)
OR   A
JR   Z,ST_SCAP
CALL ST_NTKIN
JP   C,ST_LFAIL
CP   TK_EOL
JP   NZ,ST_DDEL1
ST_SCAP:
; Capacity is decoded payload length plus one byte for CSTR's terminator or
; PSTR's prefix. ISTR and a DB string need no extra byte.
LD   A,(ST_SCNT)
LD   L,A
LD   H,0
LD   A,(ST_SMODE)
CP   1
JR   Z,ST_SCEXT
CP   2
JR   NZ,ST_SCREA
ST_SCEXT:
INC  HL
ST_SCREA:
CALL OU_CCAP
JP   C,ST_OFAIL
; PSTR writes its one-byte decoded length before the payload.
LD   A,(ST_SMODE)
CP   2
JR   NZ,ST_SELOO
LD   A,(ST_SCNT)
CALL OU_EMITB
JP   C,ST_OFAIL
ST_SELOO:
; Emit decoded characters until every raw byte inside the quotes is consumed.
LD   A,(ST_SREM)
OR   A
JR   Z,ST_SDONE
CALL ST_STAKE
CP   $5C
JR   NZ,ST_SEMIT
; Translate a standard one-character escape through the tokenizer's escape
; table, except \x which has its own two-hex-digit path.
CALL ST_STAKE
CP   $78
JR   Z,ST_SHEX
CALL TK_DESCA
JP   C,ST_DSTR1
JR   ST_SEMIT
ST_SHEX:
; Form one byte from the high and low hexadecimal nibbles. TK_HDIGI signals a
; valid digit with carry set, hence the deliberately inverted-looking tests.
CALL ST_STAKE
CALL TK_HDIGI
JP   NC,ST_DSTR1
ADD  A,A
ADD  A,A
ADD  A,A
ADD  A,A
LD   (ST_SNIBB),A
CALL ST_STAKE
CALL TK_HDIGI
JP   NC,ST_DSTR1
LD   HL,ST_SNIBB
OR   (HL)
ST_SEMIT:
; ISTR marks its final decoded byte by setting bit 7. ST_SREM counts raw bytes;
; after ST_STAKE finishes a character or escape, zero therefore identifies the
; final output character.
LD   C,A
LD   A,(ST_SMODE)
CP   3
LD   A,C
JR   NZ,ST_SEREA
LD   HL,ST_SREM
LD   A,(HL)
OR   A
LD   A,C
JR   NZ,ST_SEREA
OR   $80
ST_SEREA:
CALL OU_EMITB
JP   C,ST_OFAIL
JR   ST_SELOO
ST_SDONE:
; DB mode returns to its comma/EOL grammar. CSTR appends a zero terminator.
; PSTR and ISTR are already complete and advance directly to the next line.
LD   A,(ST_SMODE)
OR   A
JR   Z,ST_SDDON
CP   1
JP   NZ,ST_NEXT
XOR  A
CALL OU_EMITB
JP   ST_OTNEX
ST_SDDON:
CALL TK_NEXT
JP   C,ST_LFAIL
JP   ST_DDELI
ST_CSTR1:
; String modes: 1 = zero-terminated, 2 = length-prefixed, 3 = high-bit final.
LD   A,1
JR   ST_SDIR1
ST_PSTR1:
LD   A,2
JR   ST_SDIR1
ST_ISTR1:
LD   A,3
ST_SDIR1:
LD   (ST_SMODE),A
; Standalone string directives accept exactly one quoted-string token.
LD   A,(TK_REC+TK_KOFF)
CP   TK_STRIN
JP   NZ,ST_DSTR1
JP   ST_DSTRI
ST_DS1:
; DS count must be concrete. With no comma it reserves an unwritten range; with
; a comma it emits count copies of the fill byte.
CALL ST_PEXPR
JP   C,ST_DFAIL
OR   A
JP   NZ,ST_DUNR1
LD   (ST_DCNT),HL
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JR   Z,ST_DRESE
CP   TK_COMMA
JP   NZ,ST_DDEL1
; Parse the optional fill expression and require an immediate low-byte value.
CALL TK_NEXT
JP   C,ST_LFAIL
CALL ST_PEXPR
JP   C,ST_DFAIL
OR   A
JP   NZ,ST_DUNR1
LD   A,L
LD   (ST_DFILL),A
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   NZ,ST_DDEL1
; Preflight the complete filled range so the byte loop cannot fail for capacity
; after publishing only a prefix.
LD   HL,(ST_DCNT)
CALL OU_CCAP
JP   C,ST_OFAIL
ST_DFLOO:
; Emit one fill byte per iteration. ST_DCNT reaches zero before control returns
; to the outer statement loop.
LD   HL,(ST_DCNT)
LD   A,H
OR   L
JP   Z,ST_NEXT
LD   A,(ST_DFILL)
CALL OU_EMITB
JP   C,ST_OFAIL
LD   HL,(ST_DCNT)
DEC  HL
LD   (ST_DCNT),HL
JR   ST_DFLOO
ST_DRESE:
; The no-fill form advances the output cursor without creating IMAGE bytes.
LD   HL,(ST_DCNT)
CALL OU_RESER
JP   ST_OTNEX
ST_ALIG1:
; ALIGN accepts a positive 16-bit boundary. A nonzero 24-bit extension, or zero
; in the low word, is outside the directive's domain.
CALL ST_PEXPR
JP   C,ST_DFAIL
OR   A
JP   NZ,ST_DUNR1
LD   A,(EX_RVAL+2)
OR   A
JP   NZ,ST_DRANG
LD   A,H
OR   L
JP   Z,ST_DRANG
LD   (ST_DVAL),HL
LD   A,(TK_REC+TK_KOFF)
CP   TK_EOL
JP   NZ,ST_DDEL1
; Reuse the expression divider to compute cursor modulo alignment. Both operands
; are explicitly zero-extended to 24 bits before EX_REMAI is called.
LD   HL,(OU_CURSO)
LD   (EX_LVAL),HL
XOR  A
LD   (EX_LVAL+2),A
LD   HL,(ST_DVAL)
LD   (EX_RVAL),HL
LD   (EX_RVAL+2),A
CALL EX_REMAI
JP   C,ST_DFAIL
; A zero remainder is already aligned. Otherwise emit alignment - remainder
; zero bytes through the same preflighted fill loop used by DS count,fill.
LD   HL,(EX_RVAL)
LD   A,H
OR   L
JR   Z,ST_ACREA
EX   DE,HL
LD   HL,(ST_DVAL)
OR   A
SBC  HL,DE
ST_ACREA:
LD   (ST_DCNT),HL
XOR  A
LD   (ST_DFILL),A
LD   HL,(ST_DCNT)
CALL OU_CCAP
JP   C,ST_OFAIL
JR   ST_DFLOO
ST_SUCCE:
; EOF is a successful end of this source part, not the end of private scope or
; the complete build. The driver decides whether another part follows.
XOR  A
RET
;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
EN_RDIR:
; Directive names are at most five characters. Pack the current lexeme into the
; shared RADIX-40 scratch buffer for exact, case-insensitive comparison.
LD   A,B
CP   6
JR   NC,EN_RDNFO
LD   DE,EN_SCRAT
CALL EN_R40PK
RET  C
LD   IX,ST_DTABL
LD   B,ST_CNT
LD   C,ST_EQU
EN_RDLOO:
; Compare all four packed bytes. C tracks the one-based directive ordinal while
; IX advances through the fixed table.
LD   A,(EN_SCRAT)
CP   (IX+0)
JR   NZ,EN_RDNEX
LD   A,(EN_SCRAT+1)
CP   (IX+1)
JR   NZ,EN_RDNEX
LD   A,(EN_SCRAT+2)
CP   (IX+2)
JR   NZ,EN_RDNEX
LD   A,(EN_SCRAT+3)
CP   (IX+3)
JR   NZ,EN_RDNEX
LD   A,C
OR   A
RET
EN_RDNEX:
LD   DE,4
ADD  IX,DE
INC  C
DJNZ EN_RDLOO
EN_RDNFO:
; Recognition failure returns carry set; A is deliberately cleared because no
; ordinal is valid.
XOR  A
SCF
RET
ST_DTABL:
; Packed RADIX-40 forms of EQU, ORG, DB, DW, DS, CSTR, PSTR, ISTR and ALIGN.
DW $21FD,$0000
DW $6097,$0000
DW $1950,$0000
DW $1C98,$0000
DW $1BF8,$0000
DW $15CC,$7080
DW $670C,$7080
DW $3B4C,$7080
DW $0829,$2DF0
;@ROUTINE OUT A CLOBBERS DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
ST_STAKE:
; Consume one raw byte from the saved string cursor. The source service receives
; the original part ordinal in A and offset in HL; workspace advances only after
; the read, leaving A as the consumed character.
LD   HL,(ST_SPTR)
LD   A,(ST_SPART)
CALL TK_SREAD
LD   HL,(ST_SPTR)
INC  HL
LD   (ST_SPTR),HL
LD   HL,ST_SREM
DEC  (HL)
RET
;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
ST_NTKIN:
; Fetch a token and mirror its kind into A for compact statement dispatch.
CALL TK_NEXT
LD   A,(TK_REC+TK_KOFF)
RET
;@ROUTINE OUT A,HL,IX,CARRY CLOBBERS BC,DE,IY,ZERO,SIGN,PARITY,HALFCARRY
ST_PEXPR:
; Expressions see the current output address in BC so '$' and relative forms
; have statement-accurate meaning.
LD   BC,(OU_CURSO)
JP   EX_PDEFR
;@ROUTINE OUT CARRY CLOBBERS A,HL,ZERO,SIGN,PARITY,HALFCARRY
ST_CPOSI:
; Snapshot the current token's part and start offset as the statement diagnostic
; location before a nested component advances the token stream.
LD   A,(TK_REC+TK_POFF)
LD   (ST_EPART),A
LD   HL,(TK_REC+TK_SOFF)
LD   (ST_EOFF),HL
RET
;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,ZERO,SIGN,PARITY
ST_LFAIL:
; Lexical failures use the tokenizer's own exact error position rather than the
; outer statement start captured by ST_CPOSI.
LD   (ST_DETAI),A
LD   A,(TK_EPART)
LD   (ST_EPART),A
LD   HL,(TK_EOFF)
LD   (ST_EOFF),HL
LD   A,ST_SLEXI
SCF
RET
;@ROUTINE OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
ST_EHERE:
; A token that cannot begin or continue a statement is normally an expression
; syntax failure. Preserve a dedicated directive category for a bare '%' token.
CALL ST_CPOSI
LD   A,(TK_REC+TK_KOFF)
CP   TK_DIR
JR   NZ,ST_ESAVE
;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_UDIR:
LD   A,TK_DIR
LD   C,ST_SDIR
JR   ST_FAIL
;@ROUTINE OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_ESAVE:
LD   A,(TK_REC+TK_KOFF)
LD   C,ST_SEXP
JR   ST_FAIL
;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_SFAIL:
LD   C,ST_SSYM
JR   ST_FAIL
;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_IFAIL:
LD   C,ST_SINS
JR   ST_FAIL
;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_OFAIL:
LD   C,ST_SOUT
JR   ST_FAIL
;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_EFAIL:
LD   C,ST_SEQUA
JR   ST_FAIL
ST_EUNRE:
LD   A,EX_UNRES
JR   ST_EFAIL
ST_EDELI:
LD   A,EX_SEPRI
JR   ST_EFAIL
;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HALFCARRY,ZERO,SIGN,PARITY
ST_DFAIL:
LD   C,ST_SDIR
;@ROUTINE IN A,C OUT A,CARRY CLOBBERS HALFCARRY,ZERO,SIGN,PARITY
ST_FAIL:
; All nested failure adapters store the detailed component status from A, replace
; A with their outer statement category from C and set carry for the driver.
LD   (ST_DETAI),A
LD   A,C
SCF
RET
ST_DUNR1:
LD   A,EX_UNRES
JR   ST_DFAIL
ST_DRANG:
LD   A,EX_SRANG
JR   ST_DFAIL
ST_DEXP:
LD   A,EX_SEPRI
JR   ST_DFAIL
ST_DDEL1:
LD   A,(TK_REC+TK_KOFF)
JR   ST_DFAIL
ST_DSTR1:
LD   A,TK_STRIN
JR   ST_DFAIL
ST_CEND:
ST_WBEG:
; Twenty bytes shared by mutually exclusive statement phases.
ST_WUNIO: DS 20
; Packed leading label/EQU name, or parsed instruction record at the same base.
ST_KEY EQU ST_WUNIO
ST_INS EQU ST_WUNIO
; Cached mnemonic/directive ordinals and their explicit validity flags.
ST_MNEM EQU ST_WUNIO+6
ST_MVALI EQU ST_WUNIO+7
ST_DIR EQU ST_WUNIO+8
ST_DVALI EQU ST_WUNIO+9
; Nested subsystem status retained for the driver and public diagnostics.
ST_DETAI EQU ST_WUNIO+10
; EQU result and its negative/sign-extension flag.
ST_EVAL EQU ST_WUNIO+6
ST_ESIGN EQU ST_WUNIO+8
; Data-list element width, default patch kind, unresolved addend and DS fill.
ST_DWIDT EQU ST_WUNIO
ST_DPKIN EQU ST_WUNIO+1
ST_DADDE EQU ST_WUNIO+2
ST_DFILL EQU ST_WUNIO+3
; General directive value; while queuing a patch, the chosen patch kind.
ST_DVAL EQU ST_WUNIO+4
ST_DPKI1 EQU ST_DVAL
; DS/ALIGN byte count, followed by unresolved-expression state.
ST_DCNT EQU ST_WUNIO+6
ST_DKEY EQU ST_WUNIO+8
ST_DSYM EQU ST_WUNIO+10
ST_DADR EQU ST_WUNIO+12
; Raw quoted-string cursor, remaining raw bytes and decoded-byte count.
ST_SPTR EQU ST_WUNIO+14
ST_SREM EQU ST_WUNIO+16
ST_SCNT EQU ST_WUNIO+17
; Saved high hexadecimal nibble and string mode selector.
ST_SNIBB EQU ST_WUNIO+18
ST_SMODE EQU ST_WUNIO+19
; Stable statement diagnostic position.
ST_EPART: DB 0
ST_EOFF: DW 0
; Source part retained while a quoted string is decoded through TK_SREAD.
ST_SPART: DB 0
ST_WEND:
