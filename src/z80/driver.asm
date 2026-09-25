;==============================================================================
;  Multipart assembly driver
;==============================================================================
;
;  PURPOSE
;  -------
;  Own the lifetime of one complete assembly. The driver validates the caller's
;  descriptor, resets the resident subsystems, opens an output generation,
;  assembles each ordered source part, performs the final symbol checks and
;  commits the generation.
;
;  The driver does not read files. Each part record supplies an ordinal and a
;  half-open source range. TK_RESET presents that range to the tokenizer, whose
;  byte service may be backed by memory, an emulator or a native host.
;
;  PUBLIC ENTRY POINT
;  ------------------
;
;+---------------------------------------------------------------------------+
;| DR_ASM - Assemble one ordered multipart source stream.                    |
;|                                                                           |
;| Entry: IX -> build descriptor described below.                            |
;| Result: Carry clear and A = 0 after a committed generation.               |
;| Error: Carry set and A = DR_S* status. DR_DETAI gives the subsystem or     |
;|        configuration detail. ST_EPART/ST_EOFF identify source failures.   |
;| Side effects: Resets all resident assembler state. A successful BEGIN is  |
;|               followed by exactly one COMMIT or one ABORT.                |
;+---------------------------------------------------------------------------+
;
;  BUILD DESCRIPTOR
;  ----------------
;
;  +0   byte   number of source parts; zero is invalid
;  +1   word   address of the first five-byte part record
;  +3   word   beginning of caller-owned symbol arena
;  +5   word   end of symbol arena, exclusive
;  +7   word   beginning of caller-owned pending-reference arena
;  +9   word   end of pending arena, exclusive
;  +11  word   target origin
;  +13  word   target extent in bytes
;
;  Each part record is: ordinal byte, source-begin word, source-end word.
;  Ordinals must be the dense sequence 0, 1, ... count-1. Source ranges are
;  half-open, so an empty part has begin = end.
;
;  FAILURE OWNERSHIP
;  -----------------
;
;  Descriptor and resident-reset failures happen before BEGIN and therefore do
;  not call ABORT. After BEGIN succeeds, every failure path calls ABORT exactly
;  once and preserves the status that caused it. COMMIT failure also aborts the
;  open generation.

DR_CBEG:
; Public assembly statuses returned in A.
DR_SOK EQU 0
DR_SCFG EQU 1
DR_SSRC EQU 2
DR_SUNDE EQU 3
DR_SOUT EQU 4
DR_SINT EQU 5
; Configuration detail values stored in DR_DETAI.
DR_CPCNT EQU 1
DR_CTRAN EQU 2
DR_CPORD EQU 3
DR_CSRAN EQU 4
DR_CSRA1 EQU 5
DR_CPRAN EQU 6
DR_CORAN EQU 7
; The ordinal is one byte, so a build can contain at most 255 parts.
DR_PCAP EQU 255
; Part-record size and field offsets.
DR_PDB EQU 5
DR_PORDI EQU 0
DR_PBEG EQU 1
DR_PEND EQU 3
; Build-descriptor field offsets.
DR_DPCNT EQU 0
DR_DPART EQU 1
DR_DSBEG EQU 3
DR_DSEND EQU 5
DR_DPBEG EQU 7
DR_DPEND EQU 9
DR_DTBEG EQU 11
DR_DTB EQU 13
DR_DESCB EQU 15
;@ROUTINE IN IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
DR_ASM:
; Keep the descriptor address in resident workspace. Later subsystem calls are
; free to use IX, so the entry register cannot remain its owner.
PUSH IX
POP  HL
LD   (DR_DESC),HL
; Clear the public detail fields before any operation can fail. DR_USYM is set
; only when finalisation identifies a particular unresolved symbol.
XOR  A
LD   (DR_DETAI),A
LD   (DR_USYM),A
LD   (DR_USYM+1),A
; Initialise the source location to part zero, offset zero. Configuration errors
; therefore have a deterministic location even though no source has been read.
LD   HL,ST_EPART
LD   (HL),A
INC  HL
LD   (HL),A
INC  HL
LD   (HL),A
; Reject an invalid descriptor before changing any subsystem or opening output.
CALL DR_VDESC
RET  C
; Reset the symbol table over the caller's half-open symbol arena.
LD   IX,(DR_DESC)
LD   C,DR_DSBEG
CALL DR_LRANG
CALL SY_RESET
JP   C,DR_IFAIL
; Reset the pending-reference table over its independent caller-owned arena.
LD   IX,(DR_DESC)
LD   C,DR_DPBEG
CALL DR_LRANG
CALL SY_RESE1
JP   C,DR_IFAIL
; Give the output layer the target origin in HL and target extent in DE.
LD   IX,(DR_DESC)
LD   C,DR_DTBEG
CALL DR_LRANG
CALL OU_RESET
JP   C,DR_IFAIL
; All resident state is now valid. BEGIN transfers generation ownership to the
; host sink. Failure here needs no ABORT because no generation was opened.
LD   IX,(DR_DESC)
CALL HS_BEG
JP   C,DR_BFAIL
; Establish the multipart loop state from the descriptor. DR_PREM counts down;
; DR_PINDE counts up and must match every record's stored ordinal.
LD   IX,(DR_DESC)
LD   A,(IX+DR_DPCNT)
LD   (DR_PREM),A
LD   L,(IX+DR_DPART)
LD   H,(IX+DR_DPART+1)
LD   (DR_PCURS),HL
XOR  A
LD   (DR_PINDE),A
DR_PLOOP:
; A zero remaining count means every declared part was assembled exactly once.
LD   A,(DR_PREM)
OR   A
JR   Z,DR_FIN
; Decode the next five-byte part record. The cursor advances to the following
; record while HL receives source begin and DE retains source end.
LD   HL,(DR_PCURS)
INC  HL
LD   E,(HL)
INC  HL
LD   D,(HL)
INC  HL
PUSH DE
LD   E,(HL)
INC  HL
LD   D,(HL)
INC  HL
LD   (DR_PCURS),HL
POP  HL
; Reset the tokenizer to this part's ordinal and half-open source range.
LD   A,(DR_PINDE)
CALL TK_RESET
JR   C,DR_IABOR
; Assemble statements until the tokenizer reports end of this part.
CALL DR_APART
JR   C,DR_SFAIL
; Advance both sides of the loop invariant: next expected ordinal, one fewer
; record remaining. Descriptor validation proved the record cursor stays valid.
LD   HL,DR_PINDE
INC  (HL)
LD   HL,DR_PREM
DEC  (HL)
JR   DR_PLOOP
DR_FIN:
; Close the last private scope and prove that no pending or undefined symbols
; remain before exposing the generation to the caller.
CALL DR_AFIN
JR   C,DR_FFAIL
; COMMIT receives the output cursor and remaining capacity, allowing the host to
; derive the final written range without duplicating output-layer arithmetic.
LD   IX,(DR_DESC)
LD   HL,(OU_CURSO)
LD   DE,(OU_REM)
CALL HS_CMT
JR   C,DR_CFAIL
; Carry clear is the sole success indication at the public boundary.
XOR  A
RET
DR_SFAIL:
; DR_APART returns the source-facing statement detail in A.
LD   (DR_DETAI),A
LD   A,DR_SSRC
JR   DR_ABORT
DR_FFAIL:
; Finalisation distinguishes an ordinary undefined symbol from a damaged
; internal record. Its detailed status remains available in DR_DETAI.
LD   (DR_DETAI),A
CP   ST_SUNDE
LD   A,DR_SUNDE
JR   Z,DR_ABORT
LD   A,DR_SINT
JR   DR_ABORT
DR_IABOR:
; TK_RESET can fail only if resident state or its source contract is broken.
LD   (DR_DETAI),A
LD   A,DR_SINT
JR   DR_ABORT
DR_CFAIL:
; A failed commit is still an output failure, and the generation remains open
; until ABORT gives the sink a chance to discard temporary state.
LD   (DR_DETAI),A
LD   A,DR_SOUT
DR_ABORT:
; HS_ABORT may change A and flags. Preserve the original public status across
; the cleanup call, then force the error carry expected by DR_ASM callers.
PUSH AF
CALL HS_ABORT
POP  AF
SCF
RET
DR_BFAIL:
; BEGIN itself failed, so no generation exists to abort.
LD   (DR_DETAI),A
LD   A,DR_SOUT
SCF
RET
DR_IFAIL:
; Resident reset failure is classified as internal and also precedes BEGIN.
LD   (DR_DETAI),A
LD   A,DR_SINT
SCF
RET
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,IX,SIGN,PARITY,HALFCARRY,HL,ZERO,IY
DR_VDESC:
; Reload the immutable descriptor and require at least one part. A byte count
; naturally limits accepted builds to 255 records.
LD   IX,(DR_DESC)
LD   A,(IX+DR_DPCNT)
OR   A
JP   Z,DR_BPCNT
; Seed the validation loop with the declared count and first-record address.
LD   (DR_PREM),A
LD   L,(IX+DR_DPART)
LD   H,(IX+DR_DPART+1)
LD   (DR_PCURS),HL
; Prove that base + count*5 is representable in 16 bits. The loop may then walk
; exactly count records without its cursor wrapping through address zero.
LD   C,A
LD   B,0
PUSH HL
LD   H,B
LD   L,C
ADD  HL,HL
ADD  HL,HL
ADD  HL,BC
POP  DE
ADD  HL,DE
JR   C,DR_BPTAB
; Every record must carry the ordinal implied by its position in the table.
XOR  A
LD   (DR_PINDE),A
DR_VPLOO:
LD   A,(DR_PREM)
OR   A
JR   Z,DR_VAREN
LD   HL,(DR_PCURS)
LD   A,(DR_PINDE)
CP   (HL)
JR   NZ,DR_BPORD
; Decode source begin into DE and source end into BC, then publish the next
; record cursor. No source byte is read during descriptor validation.
INC  HL
LD   E,(HL)
INC  HL
LD   D,(HL)
INC  HL
LD   C,(HL)
INC  HL
LD   B,(HL)
INC  HL
LD   (DR_PCURS),HL
; A half-open source range is valid when end - begin does not borrow. Equality
; is permitted and represents an empty source part.
LD   H,B
LD   L,C
OR   A
SBC  HL,DE
JR   C,DR_BSRAN
; Advance the expected ordinal and remaining-record count together.
LD   HL,DR_PINDE
INC  (HL)
LD   HL,DR_PREM
DEC  (HL)
JR   DR_VPLOO
DR_VAREN:
; Symbol and pending arenas are each ordinary non-wrapping half-open ranges.
; Empty arenas are structurally valid; later capacity checks reject insertions.
LD   IX,(DR_DESC)
LD   C,DR_DSBEG
CALL DR_LRANG
CALL DR_VRANG
JR   C,DR_BSRA1
LD   IX,(DR_DESC)
LD   C,DR_DPBEG
CALL DR_LRANG
CALL DR_VRANG
JR   C,DR_BPRAN
; The target descriptor uses origin plus a capacity, not begin and end. Accept
; a sum of exactly $10000, represented by carry with a wrapped result of zero,
; but reject every mathematical sum greater than $10000.
LD   IX,(DR_DESC)
LD   C,DR_DTBEG
CALL DR_LRANG
ADD  HL,DE
JR   NC,.RANGEOK
LD   A,H
OR   L
JR   NZ,DR_BORAN
.RANGEOK:
XOR  A
RET
;@ROUTINE IN IX,C OUT HL,DE CLOBBERS A,B,ZERO,SIGN,PARITY,HALFCARRY,CARRY
DR_LRANG:
; Address field C in the descriptor, read two adjacent little-endian words and
; return the first in HL and the second in DE. Keeping this decoding here makes
; all three range users agree on the descriptor layout.
PUSH IX
POP  HL
LD   B,0
ADD  HL,BC
LD   E,(HL)
INC  HL
LD   D,(HL)
INC  HL
LD   A,(HL)
INC  HL
LD   H,(HL)
LD   L,A
EX   DE,HL
RET
;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY,HL,DE
DR_VRANG:
; Compute end - begin. No borrow means the half-open range does not wrap.
EX   DE,HL
OR   A
SBC  HL,DE
RET  NC
SCF
RET
DR_BPCNT:
; The following stubs translate one failed structural check into a stable
; configuration-detail value, then share the public failure return.
LD   A,DR_CPCNT
JR   DR_CFAI1
DR_BPTAB:
LD   A,DR_CTRAN
JR   DR_CFAI1
DR_BPORD:
LD   A,DR_CPORD
JR   DR_CFAI1
DR_BSRAN:
LD   A,DR_CSRAN
JR   DR_CFAI1
DR_BSRA1:
LD   A,DR_CSRA1
JR   DR_CFAI1
DR_BPRAN:
LD   A,DR_CPRAN
JR   DR_CFAI1
DR_BORAN:
LD   A,DR_CORAN
DR_CFAI1:
LD   (DR_DETAI),A
LD   A,DR_SCFG
SCF
RET
;@ROUTINE OUT A,CARRY,IX CLOBBERS DE,ZERO,SIGN,PARITY,HALFCARRY,HL,BC,IY
DR_AFIN:
; Search the live pending arena for a diagnostic anchor. Exactly one pending
; record for each unresolved symbol has bit 7 set in its kind byte.
LD   IX,(SY_ABAS1)
LD   DE,(SY_NEXT)
CALL AT_CIDE
JR   Z,DR_FNPEN
DR_FPLOO:
BIT  7,(IX+4)
JR   NZ,DR_FANCH
; Non-anchor records cannot supply an undefined-symbol source location.
LD   BC,SY_RECB1
ADD  IX,BC
CALL AT_CIDE
JR   NZ,DR_FPLOO
JR   DR_FINT
DR_FANCH:
; Preserve the anchor's symbol-record pointer before validating it. A malformed
; pointer must never be dereferenced merely to improve a diagnostic.
LD   L,(IX+0)
LD   H,(IX+1)
LD   (DR_USYM),HL
CALL DR_VSPTR
JR   C,DR_FINT
; A live anchor must point at an undefined symbol. A defined target means the
; patch-resolution path left stale metadata and is therefore an internal fault.
LD   IY,(DR_USYM)
BIT  6,(IY+5)
JR   NZ,DR_FINT
; The low kind bits must name one of the patch field forms. Zero and values past
; PT_KHB are corrupt even when the diagnostic-anchor bit itself is valid.
LD   A,(IX+4)
AND  SY_KMASK
JR   Z,DR_FINT
CP   PT_KHB+1
JR   NC,DR_FINT
; Recover the exact source location: the anchor owns the part ordinal, while an
; undefined symbol's otherwise-unused value word retains the reference offset.
LD   A,(IX+SY_PMASK)
LD   (ST_EPART),A
LD   L,(IY+SY_VALLO)
LD   H,(IY+SY_VALHI)
LD   (ST_EOFF),HL
XOR  A
LD   (ST_DETAI),A
; Return both the public undefined status and the symbol pointer for diagnostic
; name unpacking. Carry marks the finalisation failure.
LD   IX,(DR_USYM)
LD   A,ST_SUNDE
SCF
RET
DR_FNPEN:
; With no pending records, close the final private-label scope. Any undefined
; private discovered here is inconsistent because it has no diagnostic anchor.
CALL SY_VSCOP
JR   C,DR_FINT
; Private validation succeeded and may evict that scope. Walk permanent globals
; and require every record's defined flag; an undefined global without pending
; metadata is likewise an internal invariant failure.
LD   IX,(SY_ABASE)
LD   DE,(SY_GEND)
DR_FGLOO:
CALL AT_CIDE
JR   Z,DR_FSUCC
BIT  6,(IX+5)
JR   Z,DR_FINT
LD   BC,SY_RECB
ADD  IX,BC
JR   DR_FGLOO
DR_FSUCC:
XOR  A
RET
DR_FINT:
; Do not expose a stale or unvalidated pointer on an internal failure.
XOR  A
LD   (DR_USYM),A
LD   (DR_USYM+1),A
LD   A,ST_SINT
SCF
RET
;@ROUTINE IN HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
DR_VSPTR:
; First test the upward-growing global range [SY_ABASE, SY_GEND). Preserve the
; candidate around each subtraction because the comparisons destroy HL.
PUSH HL
LD   DE,(SY_ABASE)
OR   A
SBC  HL,DE
POP  HL
JR   C,DR_VPPTR
PUSH HL
LD   DE,(SY_GEND)
OR   A
SBC  HL,DE
POP  HL
JR   NC,DR_VPPTR
; A global pointer is valid only at an eight-byte record boundary from the
; arena base. SY_RECB is a power of two, so a mask performs the modulus test.
LD   DE,(SY_ABASE)
OR   A
SBC  HL,DE
LD   A,L
AND  SY_RECB-1
RET  Z
SCF
RET
DR_VPPTR:
; Private records occupy [SY_LBEG, SY_AEND) and grow down from SY_AEND.
PUSH HL
LD   DE,(SY_LBEG)
OR   A
SBC  HL,DE
POP  HL
RET  C
PUSH HL
LD   DE,(SY_AEND)
OR   A
SBC  HL,DE
POP  HL
JR   NC,DR_ISPTR
; Measure backwards from the arena end to prove eight-byte alignment with the
; downward-growing record layout.
LD   DE,(SY_AEND)
EX   DE,HL
OR   A
SBC  HL,DE
LD   A,L
AND  SY_RECB-1
RET  Z
DR_ISPTR:
SCF
RET
DR_CEND:
DR_WBEG:
; Address of the immutable build descriptor supplied to DR_ASM.
DR_DESC: DW 0
; Address of the next five-byte part record during validation or assembly.
DR_PCURS: DW 0
; Number of part records still to validate or assemble.
DR_PREM: DB 0
; Dense ordinal expected for the current part record.
DR_PINDE: DB 0
; Subsystem or configuration detail associated with the public driver status.
DR_DETAI: DB 0
; Validated symbol-record pointer for an undefined-symbol diagnostic, else zero.
DR_USYM: DW 0
DR_WEND:
