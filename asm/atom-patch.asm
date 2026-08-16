; atom Phase 2e patch-field locator.
;
; A parsed operand class fixes both the width and byte position of every field
; that can be deferred in the six-byte pending-reference ABI.

AtomPatchCodeStart:

AtomPatchKindByte:         .equ 1
AtomPatchKindWord:         .equ 2
AtomPatchKindRelative:     .equ 3
AtomPatchKindDisplacement: .equ 4
AtomPatchKindTruncateByte: .equ 5
AtomPatchKindLowByte:      .equ 6
AtomPatchKindHighByte:     .equ 7

; Locate one patchable operand in an already validated instruction record.
;
; in IX=ten-byte parsed instruction, A=operand index 0..2
; out success: A=patch kind, B=byte offset from instruction start, carry clear
;     failure: A=0, carry set
.routine in IX,A out A,B,carry clobbers HL,sign,parity,halfCarry,DE,zero
AtomPatchLocate:
            CP   3
            JR   NC,_AtomPatchInvalid
            LD   E,A
            LD   D,0
            PUSH DE
            CALL AtomFormLength
            POP  DE
            JR   C,_AtomPatchInvalid
            LD   B,A
            LD   HL,AtomInstrOp0
            ADD  HL,DE
            PUSH IX
            POP  DE
            ADD  HL,DE
            LD   A,(HL)
            CP   AtomOpIndexIX
            JR   Z,_AtomPatchDisplacement
            CP   AtomOpIndexIY
            JR   Z,_AtomPatchDisplacement
            CP   AtomOpRel8
            JR   Z,_AtomPatchRelative
            CP   AtomOpImm8
            JR   Z,_AtomPatchByte
            CP   AtomOpImm16
            JR   Z,_AtomPatchWord
            CP   AtomOpMemAbs
            JR   Z,_AtomPatchWord
_AtomPatchInvalid:
            XOR  A
            SCF
            RET
_AtomPatchDisplacement:
            LD   B,2
            LD   A,AtomPatchKindDisplacement
            OR   A
            RET
_AtomPatchRelative:
            DEC  B
            LD   A,AtomPatchKindRelative
            OR   A
            RET
_AtomPatchByte:
            DEC  B
            LD   A,AtomPatchKindByte
            OR   A
            RET
_AtomPatchWord:
            DEC  B
            DEC  B
            LD   A,AtomPatchKindWord
            OR   A
            RET

AtomPatchCodeEnd:
