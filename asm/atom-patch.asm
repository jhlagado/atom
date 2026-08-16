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
            SUB  AtomOpIndexIX
            CP   7
            JR   NC,_AtomPatchInvalid
            LD   E,A
            LD   D,0
            LD   HL,AtomPatchOperandKinds
            ADD  HL,DE
            LD   A,(HL)
            OR   A
            JR   Z,_AtomPatchInvalid
            CP   AtomPatchKindDisplacement
            JR   Z,_AtomPatchDisplacement
            DEC  B
            CP   AtomPatchKindWord
            JR   NZ,_AtomPatchReady
            DEC  B
_AtomPatchReady:
            OR   A
            RET
_AtomPatchInvalid:
            XOR  A
            SCF
            RET
_AtomPatchDisplacement:
            LD   B,2
            OR   A
            RET

; Operand classes 48..54 map to patch kinds; zero is not patchable.
AtomPatchOperandKinds:
            .db AtomPatchKindDisplacement,AtomPatchKindDisplacement
            .db AtomPatchKindWord,AtomPatchKindByte,AtomPatchKindWord
            .db 0,AtomPatchKindRelative

AtomPatchCodeEnd:
