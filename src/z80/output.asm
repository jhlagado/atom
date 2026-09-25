;==============================================================================
;  Logical output and patch submission
;==============================================================================
;
;  Maintain the logical target cursor and initial-capacity account. IMAGE
;  operations append bytes as statements are assembled; reservations advance the
;  cursor without initializing bytes, and ORG selects a new logical address.
;  Defining a referenced symbol calculates each final field value and submits a
;  PATCH operation before the corresponding pending record is removed.
;
;  Principal entries:
;    OU_RESET  initialise logical output state
;    OU_EMITB  emit one IMAGE byte
;    OU_EMITW  emit one little-endian IMAGE word
;    OU_RESER  reserve a target interval
;    OU_SORIG  change the logical origin
;    OU_EINS   encode and emit one parsed instruction
;    OU_RSLV   resolve and submit every pending patch for a symbol
;
;  IMAGE cursor movement occurs only after sink acceptance. A multi-byte helper
;  may therefore have a partial tentative generation if a later byte fails; the
;  driver aborts that generation. PATCH failure never removes its pending record.

OU_CBEG:
; Module statuses: capacity, internal invariant, concrete value range and
; relative displacement range.
OU_SCAP EQU 1
OU_SINT EQU 2
OU_SVRAN EQU 3
OU_SRRAN EQU 4
; Start a logical output interval at HL with DE bytes of remaining capacity.

;@ROUTINE IN DE,HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
OU_RESET:
LD   (OU_CURSO),HL
LD   (OU_REM),DE
XOR  A
RET
; Non-mutating check that the remaining-capacity word can cover HL bytes.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,SIGN,PARITY,HALFCARRY,HL,ZERO
OU_CCAP:
EX   DE,HL
LD   HL,(OU_REM)
OR   A
SBC  HL,DE
JR   C,OU_DCFAI
XOR  A
RET
; Emit one IMAGE byte from A. Preflight the byte before calling the common sink
; and cursor-commit tail.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
OU_EMITB:
LD   B,A
LD   HL,1
CALL OU_CCAP
RET  C
LD   A,B
JR   OU_EBREA
; Emit HL little-endian as two IMAGE operations. Capacity for both bytes is
; proved first; sink failure on the second byte leaves the first tentative IMAGE
; accepted and the cursor advanced by one for the driver to abort.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC,IX,IY
OU_EMITW:
LD   B,H
LD   C,L
LD   HL,2
CALL OU_CCAP
RET  C
LD   A,C
PUSH BC
CALL OU_EBREA
POP  BC
RET  C
LD   A,B
JR   OU_EBREA
; Reserve HL logical bytes without IMAGE operations. Commit the cursor and
; remaining-capacity change only after the complete interval passes preflight.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
OU_RESER:
PUSH HL
CALL OU_CCAP
POP  DE
RET  C
LD   HL,(OU_CURSO)
ADD  HL,DE
LD   (OU_CURSO),HL
LD   HL,(OU_REM)
OR   A
SBC  HL,DE
LD   (OU_REM),HL
XOR  A
RET
; Select a new logical origin. The platform sink validates the complete target
; extent and append-only policy at IMAGE submission or final commit.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
OU_SORIG:
LD   (OU_CURSO),HL
XOR  A
RET
; Submit A as one IMAGE byte at the current cursor. C=0 is the base output class.
; Publish cursor and capacity changes only after HS_IB accepts the operation.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,HL,ZERO,SIGN,PARITY,HALFCARRY,DE,IX,IY
OU_EBREA:
LD   HL,(OU_CURSO)
LD   C,0
CALL HS_IB
RET  C
LD   HL,(OU_CURSO)
INC  HL
LD   (OU_CURSO),HL
LD   HL,(OU_REM)
DEC  HL
LD   (OU_REM),HL
XOR  A
RET
OU_DCFAI:
LD   A,OU_SCAP
SCF
RET
; Encode and emit the parsed instruction at IX. The encoder commits into the
; private four-byte buffer; output and pending capacity are both proved before
; the first IMAGE operation is submitted.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,IX,IY
OU_EINS:
LD   HL,(OU_CURSO)
LD   (OU_IBEG),HL
LD   DE,OU_INSB
CALL EN_NAME
RET  C
LD   (OU_ILEN),A
; Compare the returned length against remaining capacity without changing it.
LD   B,A
LD   HL,(OU_REM)
LD   A,H
OR   A
JR   NZ,.ICREADY
LD   A,L
CP   B
JR   C,.ICFAIL
.ICREADY:
CALL PR_CREFE
RET  C
; Emit the exact encoded byte sequence. A sink failure leaves only already
; accepted tentative IMAGE operations; no pending reference has yet been queued.
XOR  A
LD   (OU_ISCAN),A
.INSLOOP:
LD   A,(OU_ILEN)
LD   B,A
LD   A,(OU_ISCAN)
CP   B
JR   Z,.INSDONE
LD   E,A
LD   D,0
LD   HL,OU_INSB
ADD  HL,DE
LD   A,(HL)
CALL OU_EBREA
RET  C
LD   HL,OU_ISCAN
INC  (HL)
JR   .INSLOOP
.INSDONE:
; Queue deferred references only after every byte succeeds. Patch addresses are
; derived from the instruction start saved before encoding.
LD   DE,(OU_IBEG)
JP   PR_QREFE
.ICFAIL:
LD   A,OU_SCAP
SCF
RET
; Resolve every pending record for the defined symbol at IX. Each loop peeks one
; record, computes and submits its final bytes, then removes that exact record.

;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
OU_RSLV:
; Resolution is valid only after the symbol has a final value.
BIT  6,(IX+5)
JP   Z,OU_RINT
PUSH IX
POP  HL
LD   (OU_RSPTR),HL
.RSLVLOOP:
LD   IX,(OU_RSPTR)
;@EXPECTOUT A,CARRY,BC,DE
CALL SY_PEEK
JP   C,.RPFAIL
LD   (OU_RPADR),DE
LD   A,B
AND  SY_KMASK
LD   (OU_RKIND),A
LD   A,C
LD   (OU_RADDE),A
; Sign-extend the symbol value to 24 bits when its equate carries SY_FSIGN.
LD   IX,(OU_RSPTR)
LD   L,(IX+SY_VALLO)
LD   H,(IX+SY_VALHI)
XOR  A
BIT  5,(IX+5)
JR   Z,.RBREADY
DEC  A
.RBREADY:
LD   (OU_RBHI),A
; Sign-extend the pending one-byte addend and add it to the 24-bit base. The
; third byte retains overflow information for the domain/range checks below.
LD   A,(OU_RADDE)
LD   C,A
LD   D,0
BIT  7,C
JR   Z,.RSREADY
DEC  D
.RSREADY:
LD   A,L
ADD  A,C
LD   (OU_RVAL),A
LD   A,H
ADC  A,D
LD   (OU_RVAL+1),A
LD   A,(OU_RBHI)
ADC  A,D
LD   (OU_RVAL+2),A
CALL OU_RWDOM
RET  C
; Dispatch the stored patch transform. Truncate and LOW both select the low byte;
; HIGH selects the second byte. Direct byte/displacement/relative forms enforce
; their distinct ranges before submission.
LD   A,(OU_RKIND)
CP   PT_KINDB
JR   Z,.RSLVB
CP   PT_KINDW
JR   Z,.RSLVW
CP   PT_KRELA
JR   Z,.RRELATIV
CP   PT_KDISP
JR   Z,.RDISPLAC
CP   PT_KTB
JR   Z,.RSB
CP   PT_KLB
JR   Z,.RSB
CP   PT_KHB
JP   NZ,OU_RINT
.RSLVHIB:
LD   A,(OU_RVAL+1)
JR   .RSBA
.RSLVB:
; An ordinary byte patch accepts only 0..255.
LD   A,(OU_RVAL+2)
OR   A
JR   NZ,OU_RVRAN
LD   A,(OU_RVAL+1)
OR   A
JR   NZ,OU_RVRAN
JR   .RSB
.RDISPLAC:
; Indexed displacement accepts a fully sign-extended -128..-1 or 0..127.
LD   A,(OU_RVAL+2)
OR   A
JR   Z,.RDPOSITI
INC  A
JR   NZ,OU_RVRAN
LD   A,(OU_RVAL+1)
INC  A
JR   NZ,OU_RVRAN
LD   A,(OU_RVAL)
BIT  7,A
JR   Z,OU_RVRAN
JR   .RSB
.RDPOSITI:
LD   A,(OU_RVAL+1)
OR   A
JR   NZ,OU_RVRAN
LD   A,(OU_RVAL)
BIT  7,A
JR   NZ,OU_RVRAN
JR   .RSB
.RRELATIV:
; Relative fields store target-(patch-address+1). Sixteen-bit subtraction wraps
; with the Z80 program counter before the signed-byte range check.
LD   HL,(OU_RVAL)
LD   DE,(OU_RPADR)
INC  DE
OR   A
SBC  HL,DE
LD   A,H
OR   A
JR   Z,.RRPOSITI
INC  A
JR   NZ,OU_RRRAN
BIT  7,L
JR   Z,OU_RRRAN
LD   A,L
JR   .RSBA
.RRPOSITI:
BIT  7,L
JR   NZ,OU_RRRAN
LD   A,L
JR   .RSBA
.RSB:
LD   A,(OU_RVAL)
.RSBA:
; Submit a one-byte PATCH at the saved logical field address. C=0 is the base
; output class. Do not remove the pending record if the sink rejects it.
LD   HL,(OU_RPADR)
LD   C,0
CALL HS_PB
RET  C
JR   .RREMOVE
.RSLVW:
; Word patches submit the low sixteen bits little-endian after domain validation.
LD   HL,(OU_RVAL)
LD   DE,(OU_RPADR)
LD   C,0
CALL HS_PW
RET  C
.RREMOVE:
; Sink acceptance makes removal safe. SY_TAKE preserves the metadata returned by
; SY_PEEK while compacting the pending arena.
LD   IX,(OU_RSPTR)
;@EXPECTOUT A,CARRY,BC,DE
CALL SY_TAKE
JR   C,OU_RINT
JP   .RSLVLOOP
.RPFAIL:
; SY_PEEK reports SY_SNFOU when no matching record remains. Translate that
; exhaustion status to successful completion of this symbol's resolution loop.
CP   SY_SNFOU
RET  NZ
XOR  A
RET
OU_RVRAN:
LD   A,OU_SVRAN
SCF
RET
OU_RRRAN:
LD   A,OU_SRRAN
SCF
RET
OU_RINT:
LD   A,OU_SINT
SCF
RET
; Require the signed/unsigned 16-bit expression domain -32768..65535. A zero top
; byte admits non-negative words; FF is valid only with bit 15 set.

;@ROUTINE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,BC,DE,HL,IX,IY
OU_RWDOM:
LD   A,(OU_RVAL+2)
OR   A
RET  Z
INC  A
JR   NZ,OU_RVRAN
LD   A,(OU_RVAL+1)
BIT  7,A
RET  NZ
JR   OU_RVRAN
OU_CEND:
OU_WBEG:
; Fourteen bytes of fixed workspace. Cursor/capacity occupy four bytes. The ten-
; byte union is an instruction buffer during emission and resolution state while
; draining one symbol's pending patches.
OU_CURSO: DW 0
OU_REM: DW 0
OU_WUNIO: DS 10
OU_IBEG EQU OU_WUNIO
OU_INSB EQU OU_WUNIO+2
OU_ILEN EQU OU_WUNIO+6
OU_ISCAN EQU OU_WUNIO+7
OU_RSPTR EQU OU_WUNIO
OU_RPADR EQU OU_WUNIO+2
OU_RKIND EQU OU_WUNIO+4
OU_RADDE EQU OU_WUNIO+5
OU_RVAL EQU OU_WUNIO+6
OU_RBHI EQU OU_WUNIO+9
OU_WEND:
