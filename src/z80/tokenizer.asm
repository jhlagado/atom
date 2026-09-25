;==============================================================================
;  Streaming tokenizer
;==============================================================================
;
;  PURPOSE
;  -------
;  Pull one token at a time from a prepared source part. The interface uses only
;  a byte range and part ordinal, never a file. Every source byte is obtained
;  through TK_SREAD, allowing the same core to read memory, host-backed snapshots,
;  banked storage or an operating-system adapter.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;+---------------------------------------------------------------------------+
;| TK_RESET - Select a source part and begin at logical offset zero.          |
;|                                                                           |
;| Entry: A = part ordinal; HL = source begin; DE = source end, exclusive.    |
;| Result: Carry clear, A = 0 and IX -> token record.                         |
;| Error: Carry set and A = TK_SBSRA if the range wraps backwards.           |
;| Atomicity: A rejected range changes no tokenizer state.                    |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| TK_NEXT - Return the next token from the selected part.                   |
;|                                                                           |
;| Result: Carry clear, A = token kind and IX -> nine-byte token record.      |
;| Error: Carry set and A = TK_S* lexical status. TK_EPART/TK_EOFF locate    |
;|        the failed token. Previous record fields remain unchanged.          |
;| Lifetime: The returned lexeme pointer is valid only until the next call.  |
;+---------------------------------------------------------------------------+
;
;  TOKEN RECORD
;  ------------
;
;  +0   byte   token kind
;  +1   byte   source-part ordinal
;  +2   word   byte offset from the beginning of that part
;  +4   word   pointer into TK_TBUF
;  +6   byte   raw lexeme length
;  +7   word   decoded numeric value, otherwise zero
;
;  Names keep their source capitalisation. Mnemonic, directive and symbol
;  consumers perform case folding while recognising or packing them.
;
;  LINE BOUNDARIES
;  ---------------
;
;  Blank and comment-only lines emit no EOL. A non-empty final line without a
;  physical line ending emits one synthetic EOL before repeatable EOF. This
;  prevents the last token of one source part joining the first token of the
;  next part.
;
;  SOURCE SERVICE SEAM
;  -------------------
;
;  TK_SREAD receives A = part ordinal and HL = logical byte offset. The checked
;  core's implementation below reads the reset range directly. Platform builds
;  replace only the explicitly marked body with a jump to their provider.

TK_CBEG:
; Published token kinds. Punctuation values are also used by expression parsing.
TK_EOF EQU 0
TK_EOL EQU 1
TK_NAME EQU 2
TK_DIR EQU 3
TK_NUMBE EQU 4
TK_STRIN EQU 5
TK_COMMA EQU 6
TK_COLON EQU 7
TK_LPARE EQU 8
TK_RPARE EQU 9
TK_PLUS EQU 10
TK_MINUS EQU 11
TK_STAR EQU 12
TK_SLASH EQU 13
TK_PERCE EQU 14
TK_AMPER EQU 15
TK_CARET EQU 16
TK_PIPE EQU 17
TK_TILDE EQU 18
TK_APOST EQU 19
TK_LSHIF EQU 20
TK_RSHIF EQU 21
TK_CUR EQU 22
; Lexical failure statuses returned with carry set.
TK_SIB EQU 1
TK_SNTLO EQU 2
TK_SINUM EQU 3
TK_SNOVE EQU 4
TK_SUSTR EQU 5
TK_SIESC EQU 6
TK_SSTLO EQU 7
TK_SBSRA EQU 8
TK_SUDIR EQU 9
TK_SUCHA EQU 10
TK_SICHA EQU 11
; Nine-byte token-record field offsets and total size.
TK_KOFF EQU 0
TK_POFF EQU 1
TK_SOFF EQU 2
TK_LOFF EQU 4
TK_LOFF1 EQU 6
TK_VOFF EQU 7
TK_RECB EQU 9

;@ROUTINE IN A,HL,DE OUT A,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
TK_RESET:
; Preserve all proposed state until end - begin proves the half-open range does
; not wrap. HL becomes the part length when subtraction succeeds.
PUSH AF
PUSH HL
PUSH DE
EX   DE,HL
OR   A
SBC  HL,DE
JR   C,.RBSRANGE
; Commit the validated length, then recover end, begin and ordinal from stack.
LD   (TK_SEND),HL
POP  DE
POP  HL
POP  AF
LD   (TK_SPART),A
LD   (TK_SRCBA),HL
; Both physical read position and logical diagnostic offset begin at zero.
XOR  A
LD   (TK_SCURS),A
LD   (TK_SCURS+1),A
LD   (TK_SOSTA),A
LD   (TK_SOSTA+1),A
; No token has appeared on the line, no synthetic EOL is pending and no error
; or previous record kind survives into the new part.
LD   (TK_LHTOK),A
LD   (TK_EPEND),A
LD   (TK_ESTAT),A
LD   (TK_REC+TK_KOFF),A
LD   IX,TK_REC
RET
.RBSRANGE:
; Restore the caller's proposed values without publishing any of them.
POP  DE
POP  HL
POP  AF
.BSRANGE:
LD   A,TK_SBSRA
SCF
RET

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
TK_SPEEK:
; Compare the current relative cursor with the validated part length. Equality
; is EOF; a greater cursor is impossible while tokenizer invariants hold.
LD   HL,(TK_SCURS)
LD   DE,(TK_SEND)
OR   A
SBC  HL,DE
JR   Z,.SPEOF
ADD  HL,DE
.SRCPEEKB:
; The service receives the part ordinal and logical offset. PEEK never advances
; either cursor or copies the returned byte into the token buffer.
LD   A,(TK_SPART)
CALL TK_SREAD
OR   A
RET
.SPEOF:
SCF
RET
;@@ATOM_SOURCE_READ_BEGIN@@

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
TK_SREAD:
; Memory-backed fallback: translate the logical offset to an absolute address.
LD   DE,(TK_SRCBA)
ADD  HL,DE
LD   A,(HL)
OR   A
RET
;@@ATOM_SOURCE_READ_END@@

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
TK_STAKE:
; Preserve BC because callers often use it as a length, radix or loop counter.
PUSH BC
CALL TK_SPEEK
JR   C,.STEOF
; Save the byte while both cursors advance. TK_SCURS selects the next source
; byte; TK_SOSTA is the logical offset reported for the next token.
LD   D,A
LD   HL,(TK_SCURS)
INC  HL
LD   (TK_SCURS),HL
LD   HL,(TK_SOSTA)
INC  HL
LD   (TK_SOSTA),HL
; Append the byte at TK_TBUF + current count. TK_STAKE itself permits the count
; to wrap: bounded token scanners reject the 256th byte immediately afterwards,
; while comment scanning deliberately discards buffered bytes and needs no length.
LD   A,(TK_BCNT)
LD   C,A
LD   B,0
LD   HL,TK_TBUF
ADD  HL,BC
LD   A,D
LD   (HL),A
; TK_PREV supports the apostrophe ambiguity after a name such as AF'.
LD   (TK_PREV),A
LD   A,(TK_BCNT)
INC  A
LD   (TK_BCNT),A
LD   A,D
POP  BC
; Return the consumed byte and normalise carry clear through OR.
OR   A
RET
.STEOF:
POP  BC
SCF
RET

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
TK_BEG:
; Start a tentative token. Until TK_CMT runs, the public record still describes
; the preceding successful token.
LD   HL,TK_TBUF
LD   (TK_SPTR),HL
LD   HL,(TK_SOSTA)
LD   (TK_SOFF1),HL
; Clear raw byte count, tentative length and decoded numeric value.
XOR  A
LD   (TK_BCNT),A
LD   (TK_SLEN),A
LD   (TK_SVAL),A
LD   (TK_SVAL+1),A
RET

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
TK_CMT:
; Publish all record fields only after the scanner has accepted the token.
LD   (TK_REC+TK_KOFF),A
LD   A,(TK_SPART)
LD   (TK_REC+TK_POFF),A
LD   HL,(TK_SOFF1)
LD   (TK_REC+TK_SOFF),HL
LD   HL,(TK_SPTR)
LD   (TK_REC+TK_LOFF),HL
LD   A,(TK_SLEN)
LD   (TK_REC+TK_LOFF1),A
LD   HL,(TK_SVAL)
LD   (TK_REC+TK_VOFF),HL
; Return a stable record pointer and mirror its kind into A. OR also clears carry.
LD   IX,TK_REC
LD   A,(TK_REC+TK_KOFF)
OR   A
RET

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
TK_FIN:
; A completed non-EOL token marks this physical line as non-empty.
PUSH AF
LD   A,1
LD   (TK_LHTOK),A
POP  AF
JR   TK_CMT

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,SIGN,PARITY,ZERO
TK_FAIL:
; Retain the lexical status, then rewind both cursors to the token's first byte.
; This makes failure atomic with respect to source consumption and leaves the
; previously published token record untouched.
LD   (TK_ESTAT),A
LD   HL,(TK_SOFF1)
LD   (TK_SCURS),HL
LD   (TK_SOSTA),HL
LD   A,(TK_SPART)
LD   (TK_EPART),A
LD   HL,(TK_SOFF1)
LD   (TK_EOFF),HL
; Reload the saved status after using A for the part ordinal.
LD   A,(TK_ESTAT)
SCF
RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
TK_ILETT:
; ASCII case-folding by bit 5 maps A-Z and a-z into the same 0..25 interval.
; Carry from CP 26 is the routine's "is letter" result; A itself is restored.
PUSH BC
LD   C,A
OR   $20
SUB  $61
CP   26
LD   A,C
POP  BC
RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
TK_INBEG:
; A name may begin with an ASCII letter or underscore.
CALL TK_ILETT
RET  C
CP   $5F
JR   Z,TK_CYES
OR   A
RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
TK_INB:
; Continuation additionally permits decimal digits.
CALL TK_INBEG
RET  C
CP   $30
JR   C,TK_CNO
CP   $39+1
RET  C
TK_CNO:
OR   A
RET
TK_CYES:
SCF
RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
TK_HDIGI:
; Convert one ASCII hexadecimal digit to 0..15. Carry set means valid.
CP   $30
JR   C,.HEXNO
CP   $39+1
JR   C,.HDECIMAL
OR   $20
SUB  $61
CP   6
JR   NC,.HEXNO
ADD  A,10
SCF
RET
.HDECIMAL:
SUB  $30
SCF
RET
.HEXNO:
OR   A
RET

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
TK_SNAME:
; Global names allow eight raw bytes. A private name allows nine because its
; leading period is scope syntax rather than part of the eight-character name.
LD   C,8
CALL TK_SPEEK
CP   $2E
JR   NZ,.SNGLBL
LD   C,9
CALL TK_STAKE
; A period by itself is not a name; the next byte must satisfy name-begin rules.
CALL TK_SPEEK
JP   C,TK_IB
CALL TK_INBEG
JP   NC,TK_IB
LD   B,1
JR   .SNLOOP
.SNGLBL:
LD   B,0
.SNLOOP:
; B is the accepted raw length. Stop before the first non-name byte so the next
; tokenizer call can classify it independently.
CALL TK_SPEEK
JR   C,.SNDONE
CALL TK_INB
JR   NC,.SNDONE
INC  B
; C is the maximum raw length for the selected global/private form. Comparing
; after increment detects the ninth significant byte before consuming it.
LD   A,C
CP   B
JR   C,TK_NTLON
CALL TK_STAKE
JR   .SNLOOP
.SNDONE:
; Names carry their original bytes and no decoded value.
LD   A,B
LD   (TK_SLEN),A
LD   A,TK_NAME
JP   TK_FIN
TK_NTLON:
LD   A,TK_SNTLO
JP   TK_FAIL

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
TK_SDLED:
; Scan the entire digit-led name-continuation sequence first. This lets Intel
; suffix forms such as 0FFFFH remain one token and makes malformed forms fail as
; a unit instead of splitting into a decimal token followed by a name.
LD   B,0
.SDLLOOK:
CALL TK_SPEEK
JR   C,.SDLSELEC
CALL TK_INB
JR   NC,.SDLSELEC
CALL TK_STAKE
INC  B
; A wrapped count means 256 bytes were consumed. The buffer has 256 slots, but
; the token record has only an eight-bit length, so that lexeme cannot publish.
JP   Z,TK_INUMB
JR   .SDLLOOK
.SDLSELEC:
; Save the tentative raw length, then inspect the final byte for H or B without
; regard to case. TK_CMT is the only routine that publishes record fields.
LD   A,B
LD   (TK_SLEN),A
PUSH BC
LD   HL,TK_TBUF
LD   C,B
LD   B,0
ADD  HL,BC
DEC  HL
LD   A,(HL)
POP  BC
AND  $DF
; C selects decimal (0), binary (1) or hexadecimal (4). Bit 2 is also a cheap
; hexadecimal discriminator used by the prefix scanner below.
LD   C,0
CP   $48
JR   Z,.SDLHEX
CP   $42
JR   NZ,.SDLPREPA
INC  C
JR   .SDLSUFFI
.SDLHEX:
LD   C,4
.SDLSUFFI:
; Exclude the suffix itself from the number of digits to convert.
DEC  B
.SDLPREPA:
; Every form requires at least one digit before an optional suffix.
LD   A,B
OR   A
JP   Z,TK_INUMB
LD   (TK_DSEEN),A
LD   IX,(TK_SPTR)
LD   HL,0
LD   A,C
OR   A
JR   Z,.SDLDECIM
CP   1
JR   Z,.SDLBINAR
.SDLHLOOP:
; Hexadecimal accumulation is value = value*16 + digit. Any high nibble already
; set before the shift proves the result would exceed 16 bits.
LD   A,(IX+0)
CALL TK_HDIGI
JP   NC,TK_INUMB
LD   E,A
LD   A,H
AND  $F0
JP   NZ,TK_NOVER
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
LD   A,L
OR   E
LD   L,A
INC  IX
; TK_DSEEN counts unconverted digits for all three suffix/decimal loops.
LD   A,(TK_DSEEN)
DEC  A
LD   (TK_DSEEN),A
JR   NZ,.SDLHLOOP
JR   .SDLFIN
.SDLBINAR:
; Binary accepts only ASCII 0 or 1. Carry from the doubling detects bit 16.
LD   A,(IX+0)
SUB  $30
JP   C,TK_INUMB
CP   2
JP   NC,TK_INUMB
LD   E,A
ADD  HL,HL
JP   C,TK_NOVER
LD   A,L
OR   E
LD   L,A
INC  IX
LD   A,(TK_DSEEN)
DEC  A
LD   (TK_DSEEN),A
JR   NZ,.SDLBINAR
JR   .SDLFIN
.SDLDECIM:
; Reject a non-decimal byte anywhere before the optional suffix.
LD   A,(IX+0)
SUB  $30
JP   C,TK_INUMB
CP   10
JP   NC,TK_INUMB
LD   C,A
; Before multiplying by ten, compare the accumulator with 6553. At equality the
; final digit may be at most five, the exact 65,535 boundary.
LD   A,H
CP   $19
JR   C,.SDLDACCU
JP   NZ,TK_NOVER
LD   A,L
CP   $99
JR   C,.SDLDACCU
JP   NZ,TK_NOVER
LD   A,C
CP   6
JP   NC,TK_NOVER
.SDLDACCU:
; Compute value*10 + digit as two doublings, a third doubling, then add the saved
; value*2 and the zero-extended digit.
LD   D,0
LD   E,C
ADD  HL,HL
LD   B,H
LD   C,L
ADD  HL,HL
ADD  HL,HL
ADD  HL,BC
ADD  HL,DE
INC  IX
LD   A,(TK_DSEEN)
DEC  A
LD   (TK_DSEEN),A
JR   NZ,.SDLDECIM
.SDLFIN:
; A successful numeric token publishes its decoded 16-bit value.
LD   (TK_SVAL),HL
TK_FNUMB:
LD   A,TK_NUMBE
JP   TK_FIN

;@ROUTINE IN BC OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
TK_SBASE:
; Scan a prefix form. Entry B already counts '$' or '%'; C is 4 for hex and 1
; for binary. HL accumulates the decoded value and TK_DSEEN records whether at
; least one digit followed the prefix.
LD   HL,0
XOR  A
LD   (TK_DSEEN),A
.SBLOOP:
; Preserve the accumulator across PEEK, which uses HL for the source cursor.
PUSH HL
CALL TK_SPEEK
POP  HL
JR   C,.SBEOF
LD   D,A
; Bit 2 distinguishes hexadecimal from binary without another base constant.
BIT  2,C
JR   Z,.SBDIGIT
CALL TK_HDIGI
JR   NC,.SBDONE
JR   .SBDIGIT1
.SBDIGIT:
SUB  $30
JR   C,.SBDONE
CP   2
JR   NC,.SBDONE
.SBDIGIT1:
LD   E,A
; Hex shifts four places after proving its high nibble clear; binary shifts once
; and uses carry as the 17th-bit overflow indication.
BIT  2,C
JR   Z,.SBSHIFT
LD   A,H
AND  $F0
JR   NZ,TK_NOVER
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
ADD  HL,HL
JR   .SBMERGE
.SBSHIFT:
ADD  HL,HL
JR   C,TK_NOVER
.SBMERGE:
; E is a normalised digit, so OR is equivalent to addition into cleared low bits.
LD   A,L
OR   E
LD   L,A
PUSH HL
CALL TK_STAKE
POP  HL
INC  B
; Reject byte 256 because its wrapped count cannot be represented in the token
; record, even though that byte itself occupied the buffer's final slot.
JR   Z,TK_INUMB
LD   A,1
LD   (TK_DSEEN),A
JR   .SBLOOP
.SBDONE:
; A prefix requires at least one accepted digit. If the following byte could be
; part of a name, reject the complete token rather than silently splitting it.
LD   A,(TK_DSEEN)
OR   A
JR   Z,TK_INUMB
LD   A,D
CALL TK_INB
JR   C,TK_INUMB
JR   .SBFIN
.SBEOF:
LD   A,(TK_DSEEN)
OR   A
JR   Z,TK_INUMB
.SBFIN:
LD   (TK_SVAL),HL
TK_FNLEN:
; Character literals share this finish path after placing their decoded byte in
; TK_SVAL; B supplies the raw lexeme length in both cases.
LD   A,B
LD   (TK_SLEN),A
JR   TK_FNUMB
TK_INUMB:
; Invalid syntax and overflow are distinct diagnostics.
LD   A,TK_SINUM
JP   TK_FAIL
TK_NOVER:
LD   A,TK_SNOVE
JP   TK_FAIL

;@ROUTINE OUT A,IX,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
TK_SSTRI:
; B counts the complete raw token, including quotes and escape bytes. Consume the
; opening quote, then validate each byte without decoding the stored lexeme.
LD   B,0
CALL TK_STAK1
JP   C,TK_FAIL
.SSLOOP:
CALL TK_STAK1
JP   C,TK_FAIL
CALL TK_ILEND
JR   Z,TK_USTRI
; Raw control bytes and DEL are never valid inside a quoted string.
CP   $20
JR   C,TK_IB
CP   $7F
JR   NC,TK_IB
CP   $22
JR   Z,.SSDONE
; Ordinary printable bytes need no further work. Backslash introduces either a
; table escape or the special two-digit hexadecimal escape.
CP   $5C
JR   NZ,.SSLOOP
CALL TK_STAK1
JP   C,TK_FAIL
CP   $78
JR   Z,.SHESCAPE
CALL TK_DESCA
JR   C,TK_IESCA
JR   .SSLOOP
.SHESCAPE:
; Both hexadecimal digits must be present and valid; their decoded value is left
; to the later statement emitter because string tokens retain raw source bytes.
CALL TK_STAK1
JP   C,TK_FAIL
CALL TK_HDIGI
JR   NC,TK_IESCA
CALL TK_STAK1
JP   C,TK_FAIL
CALL TK_HDIGI
JR   NC,TK_IESCA
JR   .SSLOOP
.SSDONE:
; The closing quote has already been consumed and counted.
LD   A,B
LD   (TK_SLEN),A
LD   A,TK_STRIN
JP   TK_FIN

;@ROUTINE IN B OUT A,B,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
TK_STAK1:
; Consume one string byte and increment its raw length. A zero result after INC
; means 256 bytes were attempted and the fixed token buffer is full.
CALL TK_STAKE
JR   C,.STEOF
INC  B
RET  NZ
LD   A,TK_SSTLO
SCF
RET
.STEOF:
; EOF while a string scanner expects another byte is an unterminated string.
LD   A,TK_SUSTR
SCF
RET
TK_IESCA:
LD   A,TK_SIESC
JP   TK_FAIL
TK_USTRI:
LD   A,TK_SUSTR
JP   TK_FAIL
TK_UCHAR:
LD   A,TK_SUCHA
JP   TK_FAIL
TK_ICHAR:
LD   A,TK_SICHA
JP   TK_FAIL
TK_IB:
LD   A,TK_SIB
JP   TK_FAIL

;@ROUTINE OUT CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,A
TK_SCOMM:
.SCLOOP:
; Discard comment bytes but leave CR/LF unconsumed. The ordinary line-ending path
; emits EOL only when TK_LHTOK records an earlier token on this physical line.
CALL TK_SPEEK
RET  C
CALL TK_ILEND
RET  Z
CALL TK_STAKE
JR   .SCLOOP

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IY
TK_NEXT:
.NEXTLOOP:
; Begin a tentative token at the current offset, then classify its first byte.
CALL TK_BEG
CALL TK_SPEEK
JP   C,.ATEOF
CP   $20
JR   Z,.SKIPB
CP   $09
JR   Z,.SKIPB
CP   $0A
JP   Z,.LF
CP   $0D
JP   Z,.CRLF
CP   $3B
JR   Z,.COMMENT
; Period always begins a private name; the name scanner diagnoses a bare period.
CP   $2E
JP   Z,TK_SNAME
CP   $22
JP   Z,TK_SSTRI
CP   $27
JP   Z,.APOSTROP
CP   $24
JR   Z,.DOLLAR
CP   $25
JR   Z,.PERCENT
CP   $3C
JP   Z,.LSHIFT
CP   $3E
JP   Z,.RSHIFT
CP   $30
JR   C,.TRYNAME
CP   $39+1
JP   C,TK_SDLED
.TRYNAME:
; Remaining ASCII name-start bytes enter the name scanner.
CALL TK_INBEG
JP   C,TK_SNAME
; Single-byte punctuation is a compact (character, token-kind) table. Shifts,
; quotes, '$' and '%' were separated above because they require lookahead.
LD   HL,TK_PTABL
LD   B,TK_PCNT
.PLOOP:
CP   (HL)
INC  HL
JR   Z,.PUNCTUAT
INC  HL
DJNZ .PLOOP
JR   TK_IB
.PUNCTUAT:
LD   C,(HL)
CALL TK_STAKE
LD   A,1
JR   .FPUNCTUA
.SKIPB:
; Spaces and tabs separate tokens but never appear in a token record.
CALL TK_STAKE
JR   .NEXTLOOP
.COMMENT:
CALL TK_SCOMM
JR   .NEXTLOOP
.DOLLAR:
; Consume '$' and inspect the next byte. A valid hexadecimal digit selects a
; prefixed number; otherwise a standalone '$' denotes the current location.
CALL TK_STAKE
CALL TK_SPEEK
JR   C,.CLOCATIO
LD   B,A
CALL TK_HDIGI
JR   C,.DNUMBER
; A following name-continuation byte makes the entire numeric-looking form
; invalid, preventing '$G' from becoming current-location followed by a name.
LD   A,B
CALL TK_INB
JP   C,TK_INUMB
.CLOCATIO:
LD   A,1
LD   (TK_SLEN),A
LD   A,TK_CUR
JP   TK_FIN
.DNUMBER:
; Raw length already includes '$'; bit 2 in C selects hexadecimal accumulation.
LD   B,1
LD   C,4
JP   TK_SBASE
.PERCENT:
; Percent begins binary only when followed by 0 or 1. Otherwise it is the
; remainder operator, subject to the leaked-host-directive guard below.
CALL TK_STAKE
CALL TK_SPEEK
JR   C,.PTOK
CP   $30
JR   Z,.PNUMBER
CP   $31
JR   Z,.PNUMBER
CALL TK_ILETT
JR   NC,.PTOK
; Before the first token on a line, "%" plus a letter can only be an unmasked
; host directive. Reject it explicitly rather than assembling it as an expression.
LD   A,(TK_LHTOK)
OR   A
JR   NZ,.PTOK
LD   A,TK_SUDIR
JP   TK_FAIL
.PTOK:
LD   A,1
LD   (TK_SLEN),A
LD   A,TK_PERCE
JP   TK_FIN
.PNUMBER:
; Raw length already includes '%'; C=1 selects binary accumulation.
LD   B,1
LD   C,1
JP   TK_SBASE
.LSHIFT:
LD   C,TK_LSHIF
JR   .SHIFT
.RSHIFT:
LD   C,TK_RSHIF
.SHIFT:
; A shift operator is valid only as a doubled matching character, << or >>.
LD   B,A
CALL TK_STAKE
CALL TK_SPEEK
JP   C,TK_IB
CP   B
JP   NZ,TK_IB
CALL TK_STAKE
LD   A,2
.FPUNCTUA:
LD   (TK_SLEN),A
LD   A,C
JP   TK_FIN
.LF:
; LF is one-byte line ending. CR must be followed by LF and is otherwise invalid.
CALL TK_STAKE
LD   A,1
LD   (TK_SLEN),A
JR   .FINLINE
.CRLF:
CALL TK_STAKE
CALL TK_SPEEK
JP   C,TK_IB
CP   $0A
JP   NZ,TK_IB
CALL TK_STAKE
LD   A,2
LD   (TK_SLEN),A
.FINLINE:
; A physical line ending clears synthetic-EOL state. If no token appeared on the
; line, suppress EOL and continue scanning the next physical line.
XOR  A
LD   (TK_EPEND),A
LD   A,(TK_LHTOK)
OR   A
JP   Z,.NEXTLOOP
XOR  A
LD   (TK_LHTOK),A
LD   A,TK_EOL
JP   TK_CMT
.ATEOF:
; EOF after a non-empty unterminated final line first publishes one synthetic
; EOL. TK_EPEND ensures the following and all later calls return EOF instead.
LD   A,(TK_EPEND)
OR   A
JR   NZ,.EMITEOF
LD   A,(TK_LHTOK)
OR   A
JR   Z,.EMITEOF
XOR  A
LD   (TK_LHTOK),A
INC  A
LD   (TK_EPEND),A
XOR  A
LD   (TK_SLEN),A
LD   A,TK_EOL
JP   TK_CMT
.EMITEOF:
; EOF has kind and length zero; TK_CMT fills in current part and offset.
XOR  A
LD   (TK_SLEN),A
JP   TK_CMT
.APOSTROP:
; Apostrophe is ambiguous with a character literal. At the beginning of a source
; part or after a non-name byte, it opens a character. Directly after a name
; byte it remains punctuation, preserving forms such as AF'.
LD   HL,(TK_SOFF1)
LD   A,H
OR   L
JR   Z,TK_SCHAR
LD   A,(TK_PREV)
CALL TK_INB
JR   NC,TK_SCHAR
; Emit the punctuation form as a one-byte token.
CALL TK_STAKE
LD   A,1
LD   (TK_SLEN),A
LD   A,TK_APOST
JP   TK_FIN

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
TK_SCHAR:
; B begins at one for the opening quote. Consume the quote and first payload byte.
; EOF or a line ending in this initial position is an unterminated character;
; line endings reached later inside an escape are invalid escapes instead.
LD   B,1
CALL TK_STAKE
CALL TK_STAKE
JP   C,TK_UCHAR
INC  B
CALL TK_ILEND
JP   Z,TK_UCHAR
; An immediate closing quote is an empty character literal. Backslash enters the
; shared escape language; an ordinary payload must be printable ASCII.
CP   $27
JP   Z,TK_ICHAR
CP   $5C
JR   Z,.SCESCAPE
CP   $20
JP   C,TK_IB
CP   $7F
JP   NC,TK_IB
LD   (TK_SVAL),A
JR   .SCCLOSE
.SCESCAPE:
; Count and decode the byte after backslash. The table form produces one value;
; \x consumes two additional hexadecimal digits.
CALL TK_STAKE
JP   C,TK_UCHAR
INC  B
CP   $78
JR   Z,.SCHEX
CALL TK_DESCA
JP   C,TK_IESCA
LD   (TK_SVAL),A
JR   .SCCLOSE
.SCHEX:
; Decode high nibble first and retain it in TK_SVAL while reading the low nibble.
CALL TK_STAKE
JP   C,TK_UCHAR
INC  B
CALL TK_HDIGI
JP   NC,TK_IESCA
ADD  A,A
ADD  A,A
ADD  A,A
ADD  A,A
LD   (TK_SVAL),A
CALL TK_STAKE
JP   C,TK_UCHAR
INC  B
CALL TK_HDIGI
JP   NC,TK_IESCA
LD   HL,TK_SVAL
OR   (HL)
LD   (TK_SVAL),A
.SCCLOSE:
; Exactly one decoded byte is now present. The next raw byte must be the closing
; apostrophe and becomes part of the published raw lexeme length.
CALL TK_STAKE
JP   C,TK_UCHAR
INC  B
CALL TK_ILEND
JP   Z,TK_UCHAR
CP   $27
JP   NZ,TK_ICHAR
JP   TK_FNLEN
TK_RCEND:

;@ROUTINE OUT A,B,HL
TK_LLEXE:
; Return the current token's buffered lexeme pointer and raw byte length. This is
; intentionally a borrowed view whose lifetime ends at the next TK_NEXT call.
LD   HL,(TK_REC+TK_LOFF)
LD   A,(TK_REC+TK_LOFF1)
LD   B,A
RET
TK_IBEG:
TK_PTABL:
; Single-byte punctuation table: raw ASCII byte followed by token kind.
DB $2C,TK_COMMA
DB $3A,TK_COLON
DB $28,TK_LPARE
DB $29,TK_RPARE
DB $2B,TK_PLUS
DB $2D,TK_MINUS
DB $2A,TK_STAR
DB $2F,TK_SLASH
DB $26,TK_AMPER
DB $5E,TK_CARET
DB $7C,TK_PIPE
DB $7E,TK_TILDE
DB $27,TK_APOST
TK_PEND:
TK_PCNT EQU (TK_PEND-TK_PTABL)/2
TK_ETABL:
; Escape table pairs source byte with decoded value: 0, n, r, t, quotes and
; backslash.
DB $30,0,$6E,$0A,$72,$0D,$74,$09,$27,$27,$22,$22,$5C,$5C
TK_ECNT EQU 7

;@ROUTINE IN A OUT A,CARRY CLOBBERS C,HL,ZERO,SIGN,PARITY,HALFCARRY
TK_DESCA:
; Search the seven fixed escape pairs. Matching CP leaves carry clear; not found
; returns carry set without inventing a decoded byte.
LD   HL,TK_ETABL
LD   C,TK_ECNT
.DELOOP:
CP   (HL)
JR   Z,.DEFOUND
INC  HL
INC  HL
DEC  C
JR   NZ,.DELOOP
SCF
RET
.DEFOUND:
INC  HL
LD   A,(HL)
RET

;@ROUTINE IN A OUT A,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
TK_ILEND:
; Zero is set for either accepted physical line-ending byte.
CP   $0A
RET  Z
CP   $0D
RET
TK_IEND:
TK_CEND:
TK_WBEG:
; Absolute base used only by the checked memory-backed source provider.
TK_SRCBA: DW 0
; Relative offset of the next unread source byte and validated part length.
TK_SCURS: DW 0
TK_SEND: DW 0
; Logical byte offset used for token starts and diagnostics.
TK_SOSTA: DW 0
; Current source-part ordinal supplied to every source-service call.
TK_SPART: DB 0
; Nonzero after at least one token on the current physical line.
TK_LHTOK: DB 0
; Nonzero after synthesizing the final EOL, preventing a second synthetic token.
TK_EPEND: DB 0
; Pointer to the fixed token buffer and current raw byte count.
TK_SPTR: DW 0
TK_BCNT: DB 0
; Most recently consumed raw byte, used to disambiguate apostrophe.
TK_PREV: DB 0
; Tentative token's starting logical offset, raw length and decoded value.
TK_SOFF1: DW 0
TK_SLEN: DB 0
TK_SVAL: DW 0
; Numeric prefix/suffix scanners use this byte as digit-seen or remaining count.
TK_DSEEN: DB 0
; On failure the temporary length/value/count cells become status, part and
; offset storage. The public token record remains untouched.
TK_ESTAT EQU TK_SLEN
TK_EPART EQU TK_SVAL
TK_EOFF EQU TK_SVAL+1
; Published token record, followed by its 256-byte transient lexeme buffer.
TK_REC: DS TK_RECB
TK_TBUF: DS 256
TK_WEND:
