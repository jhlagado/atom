;==============================================================================
;  Expression arithmetic and workspace
;==============================================================================
;
;  Concrete 24-bit arithmetic kernels used by expression.asm, followed by the
;  evaluator's fixed working state and bounded stacks. This is a separate source
;  part so the educational commentary remains within Atom's 16-bit per-part
;  source-offset range; it is assembled immediately after expression.asm.
;
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
;  Expression arithmetic and workspace
;==============================================================================
