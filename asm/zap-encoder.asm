; zap Phase 1 parsed-instruction encoder.
; Link after selecting an origin. Writable workspace is declared after the
; immutable core so it is excluded from ZapEncoderCoreEnd.

            .include "zap-abi.asmi"

ZapEncoderCoreStart:
ZapEncoderCodeStart:

; ---------------------------------------------------------------------------
; RADIX-40 packer
; ---------------------------------------------------------------------------
ZapRadix40CodeStart:

; in HL=text, B=length 1..8, DE=destination
; out carry clear and three packed words committed; carry set leaves DE intact
.routine in B,DE,HL out carry clobbers zero,sign,parity,halfCarry,A,BC,DE,HL,IX
ZapRadix40Pack:
            LD   A,B
            OR   A
            JP   Z,ZapPackInvalid
            CP   9
            JP   NC,ZapPackInvalid

            ; Validate before touching even the scratch representation.
            PUSH HL
            PUSH BC
ZapPackValidateLoop:
            LD   A,(HL)
            CALL ZapRadix40Character
            JP   C,ZapPackValidateFailed
            INC  HL
            DJNZ ZapPackValidateLoop
            POP  BC
            POP  HL

            PUSH DE
            LD   IX,ZapScratch
            LD   A,B

            ; First group: three positions.
            CP   3
            JR   C,ZapPackFirstShort
            LD   B,3
            SUB  3
            JR   ZapPackFirstReady
ZapPackFirstShort:
            LD   B,A
            XOR  A
ZapPackFirstReady:
            PUSH AF
            LD   C,3
            CALL ZapPackGroup
            LD   (IX+0),E
            LD   (IX+1),D
            POP  AF

            ; Second group: three positions.
            CP   3
            JR   C,ZapPackSecondShort
            LD   B,3
            SUB  3
            JR   ZapPackSecondReady
ZapPackSecondShort:
            LD   B,A
            XOR  A
ZapPackSecondReady:
            PUSH AF
            LD   C,3
            CALL ZapPackGroup
            LD   (IX+2),E
            LD   (IX+3),D
            POP  AF

            ; Final group: two positions, c6*40+c7.
            LD   B,A
            LD   C,2
            CALL ZapPackGroup
            LD   (IX+4),E
            LD   (IX+5),D

            POP  DE
            LD   HL,ZapScratch
            LD   BC,6
            LDIR
            OR   A
            RET

ZapPackValidateFailed:
            POP  BC
            POP  HL
ZapPackInvalid:
            XOR  A
            SCF
            RET

; in HL=text, B=actual characters, C=field width (2 or 3)
; out DE=packed field, HL advanced by B, carry clear
.routine in B,C,HL out DE,HL,carry clobbers zero,sign,parity,halfCarry,A,BC
ZapPackGroup:
            LD   DE,0
ZapPackGroupLoop:
            LD   A,B
            OR   A
            JR   Z,ZapPackGroupPadding
            LD   A,(HL)
            INC  HL
            DEC  B
            CALL ZapRadix40Character
            JR   ZapPackGroupAppend
ZapPackGroupPadding:
            XOR  A
ZapPackGroupAppend:
            CALL ZapMultiplyAdd40
            DEC  C
            JR   NZ,ZapPackGroupLoop
            OR   A
            RET

; in DE=value, A=digit; out DE=value*40+digit. Preserves HL,BC.
.routine in A,DE out DE clobbers carry,zero,sign,parity,halfCarry,A
ZapMultiplyAdd40:
            PUSH HL
            LD   H,D
            LD   L,E
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,DE
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,HL
            ADD  A,L
            LD   L,A
            JR   NC,ZapMultiplyAdd40NoCarry
            INC  H
ZapMultiplyAdd40NoCarry:
            EX   DE,HL
            POP  HL
            RET

; ASCII letters are folded to uppercase. Carry marks an invalid character.
.routine in A out A,carry clobbers zero,sign,parity,halfCarry
ZapRadix40Character:
            CP   "a"
            JR   C,ZapRadix40Upper
            CP   "z"+1
            JR   NC,ZapRadix40Upper
            SUB  $20
ZapRadix40Upper:
            CP   "A"
            JR   C,ZapRadix40Digit
            CP   "Z"+1
            JR   NC,ZapRadix40Digit
            SUB  "A"-1
            OR   A
            RET
ZapRadix40Digit:
            CP   "0"
            JR   C,ZapRadix40Underscore
            CP   "9"+1
            JR   NC,ZapRadix40Underscore
            SUB  "0"-27
            OR   A
            RET
ZapRadix40Underscore:
            CP   "_"
            JR   NZ,ZapRadix40Bad
            LD   A,37
            OR   A
            RET
ZapRadix40Bad:
            XOR  A
            SCF
            RET

ZapRadix40CodeEnd:

; ---------------------------------------------------------------------------
; Case-insensitive mnemonic recognizer
; ---------------------------------------------------------------------------
ZapRecognitionCodeStart:

; in HL=text, B=length; out A=ordinal and carry clear, or A=0 and carry set
.routine in B,HL out A,carry clobbers zero,sign,parity,halfCarry,BC,DE,HL,IX
ZapRecognizeMnemonic:
            LD   DE,ZapScratch
            CALL ZapRadix40Pack
            RET  C
            XOR  A
            LD   (ZapSearchLow),A
            LD   A,ZapMnemonicCount
            LD   (ZapSearchHigh),A
ZapRecognizeLoop:
            LD   A,(ZapSearchLow)
            LD   B,A
            LD   A,(ZapSearchHigh)
            CP   B
            JP   Z,ZapRecognizeNotFound
            ADD  A,B
            RRCA
            AND  $7F
            LD   (ZapSearchMid),A

            ; HL = table + mid*5.
            LD   E,A
            LD   D,0
            LD   H,D
            LD   L,E
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,DE
            LD   DE,ZapMnemonicTable
            ADD  HL,DE

            ; Compare packed words as unsigned integers, high byte first.
            INC  HL
            LD   A,(ZapScratch+1)
            CP   (HL)
            JR   C,ZapRecognizeBefore
            JR   NZ,ZapRecognizeAfter
            DEC  HL
            LD   A,(ZapScratch+0)
            CP   (HL)
            JR   C,ZapRecognizeBefore
            JR   NZ,ZapRecognizeAfter
            INC  HL
            INC  HL
            INC  HL
            LD   A,(ZapScratch+3)
            CP   (HL)
            JR   C,ZapRecognizeBefore
            JR   NZ,ZapRecognizeAfter
            DEC  HL
            LD   A,(ZapScratch+2)
            CP   (HL)
            JR   C,ZapRecognizeBefore
            JR   NZ,ZapRecognizeAfter
            INC  HL
            INC  HL
            LD   A,(HL)
            OR   A
            RET
ZapRecognizeBefore:
            LD   A,(ZapSearchMid)
            LD   (ZapSearchHigh),A
            JR   ZapRecognizeLoop
ZapRecognizeAfter:
            LD   A,(ZapSearchMid)
            INC  A
            LD   (ZapSearchLow),A
            JR   ZapRecognizeLoop
ZapRecognizeNotFound:
            XOR  A
            SCF
            RET

ZapRecognitionCodeEnd:

; ---------------------------------------------------------------------------
; Form validation and length
; ---------------------------------------------------------------------------
ZapValidationCodeStart:

; Values at offsets 4..9 are never read by this routine.
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,BC,DE,HL
ZapFormLength:
ZapValidateForm:
            LD   A,(IX+ZapInstrMnemonic)
            OR   A
            JP   Z,ZapInvalid
            CP   ZapMRet
            JP   C,ZapValidateCore
            JP   Z,ZapValidateRet
            CP   ZapMEx
            JP   Z,ZapValidateEx
            CP   ZapMIm
            JP   Z,ZapValidateIm
            CP   ZapMRst
            JP   Z,ZapValidateRst
            CP   ZapMInc
            JP   Z,ZapValidateIncDec
            CP   ZapMDec
            JP   Z,ZapValidateIncDec
            CP   ZapMPush
            JP   Z,ZapValidateStack
            CP   ZapMPop
            JP   Z,ZapValidateStack
            CP   ZapMLd
            JP   Z,ZapValidateLd
            CP   ZapMIn
            JP   Z,ZapValidateIn
            CP   ZapMOut
            JP   Z,ZapValidateOut
            CP   ZapMBit
            JP   C,ZapInvalid
            CP   ZapMSet+1
            JP   C,ZapValidateBit
            CP   ZapMRlc
            JP   C,ZapInvalid
            CP   ZapMSrl+1
            JP   C,ZapValidateRotate
            CP   ZapMAdd
            JP   C,ZapInvalid
            CP   ZapMCp+1
            JP   C,ZapValidateAlu
            CP   ZapMJp
            JP   Z,ZapValidateJp
            CP   ZapMCall
            JP   Z,ZapValidateCall
            CP   ZapMJr
            JP   Z,ZapValidateJr
            CP   ZapMDjnz
            JP   Z,ZapValidateDjnz
            JP   ZapInvalid

ZapValidateCore:
            CALL ZapRequireNoOperands
            RET  C
            LD   A,(IX+ZapInstrMnemonic)
            DEC  A
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,ZapCoreOpcodes+1
            ADD  HL,DE
            LD   A,(HL)
            OR   A
            LD   A,1
            RET  Z
            INC  A
            RET

ZapValidateRet:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpNone
            JP   Z,ZapValidateLength1NoOperands
            CALL ZapIsCondition
            JP   NC,ZapInvalid
            CALL ZapRequireOneOperand
            RET  C
            LD   A,1
            OR   A
            RET

ZapValidateLength1NoOperands:
            CALL ZapRequireNoOperands
            RET  C
            LD   A,1
            OR   A
            RET

ZapValidateEx:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpAF
            JR   Z,ZapValidateExAf
            CP   ZapOpDE
            JR   Z,ZapValidateExDe
            CP   ZapOpMemSP
            JP   NZ,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpHL
            JP   Z,ZapValidateLength1
            CP   ZapOpIX
            JP   Z,ZapValidateLength2
            CP   ZapOpIY
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateExAf:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpAFPrime
            JP   Z,ZapValidateLength1
            JP   ZapInvalid
ZapValidateExDe:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpHL
            JP   Z,ZapValidateLength1
            JP   ZapInvalid

ZapValidateIm:
            CALL ZapRequireOneOperand
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIm0
            JP   C,ZapInvalid
            CP   ZapOpIm2+1
            JP   NC,ZapInvalid
            JP   ZapValidateLength2

ZapValidateRst:
            CALL ZapRequireOneOperand
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpRst0
            JP   C,ZapInvalid
            CP   ZapOpRst56+1
            JP   NC,ZapInvalid
            JP   ZapValidateLength1

ZapValidateIncDec:
            CALL ZapRequireOneOperand
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JP   C,ZapValidateLength1
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg16
            JP   C,ZapValidateLength1
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIX
            JP   Z,ZapValidateLength2
            CP   ZapOpIY
            JP   Z,ZapValidateLength2
            CALL ZapIsHalfIndex
            JP   C,ZapValidateLength2
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpMemHL
            JP   Z,ZapValidateLength1
            CALL ZapIsIndexed
            JP   C,ZapValidateLength3
            JP   ZapInvalid

ZapValidateStack:
            CALL ZapRequireOneOperand
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpBC
            JP   Z,ZapValidateLength1
            CP   ZapOpDE
            JP   Z,ZapValidateLength1
            CP   ZapOpHL
            JP   Z,ZapValidateLength1
            CP   ZapOpAF
            JP   Z,ZapValidateLength1
            CP   ZapOpIX
            JP   Z,ZapValidateLength2
            CP   ZapOpIY
            JP   Z,ZapValidateLength2
            JP   ZapInvalid

ZapLdValidationStart:
ZapValidateLd:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JP   C,ZapValidateLdReg8
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsHalfIndex
            JP   C,ZapValidateLdHalf
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg16
            JP   C,ZapValidateLdReg16
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIX
            JP   Z,ZapValidateLdIndex16
            CP   ZapOpIY
            JP   Z,ZapValidateLdIndex16
            CP   ZapOpI
            JP   Z,ZapValidateLdSpecial
            CP   ZapOpR
            JP   Z,ZapValidateLdSpecial
            CP   ZapOpMemAbs
            JP   Z,ZapValidateLdMemAbs
            CP   ZapOpMemBC
            JP   Z,ZapValidateLdMemPair
            CP   ZapOpMemDE
            JP   Z,ZapValidateLdMemPair
            CP   ZapOpMemHL
            JP   Z,ZapValidateLdMemHL
            CALL ZapIsIndexed
            JP   C,ZapValidateLdIndexed
            JP   ZapInvalid

ZapValidateLdReg8:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JP   C,ZapValidateLength1
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm8
            JP   Z,ZapValidateLength2
            CP   ZapOpMemHL
            JP   Z,ZapValidateLength1
            CP   ZapOpMemAbs
            JR   Z,ZapValidateLdReg8Absolute
            CP   ZapOpMemBC
            JR   Z,ZapValidateLdReg8Accumulator
            CP   ZapOpMemDE
            JR   Z,ZapValidateLdReg8Accumulator
            CP   ZapOpI
            JR   Z,ZapValidateLdReg8Accumulator2
            CP   ZapOpR
            JR   Z,ZapValidateLdReg8Accumulator2
            CALL ZapIsIndexed
            JP   C,ZapValidateLength3
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsHalfIndex
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpH
            JP   Z,ZapInvalid
            CP   ZapOpL
            JP   Z,ZapInvalid
            JP   ZapValidateLength2
ZapValidateLdReg8Absolute:
ZapValidateLdReg8Accumulator:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpA
            JP   NZ,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpMemAbs
            JP   Z,ZapValidateLength3
            JP   ZapValidateLength1
ZapValidateLdReg8Accumulator2:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpA
            JP   NZ,ZapInvalid
            JP   ZapValidateLength2

ZapValidateLdHalf:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsHalfIndex
            JR   C,ZapValidateLdHalfFamily
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JP   NC,ZapInvalid
            CP   ZapOpH
            JP   Z,ZapInvalid
            CP   ZapOpL
            JP   Z,ZapInvalid
            JP   ZapValidateLength2
ZapValidateLdHalfFamily:
            LD   A,(IX+ZapInstrOp0)
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            XOR  B
            AND  $08
            JP   NZ,ZapInvalid
            JP   ZapValidateLength2

ZapValidateLdReg16:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength3
            CP   ZapOpMemAbs
            JR   Z,ZapValidateLdReg16Absolute
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpSP
            JR   Z,ZapValidateLdSp
            CP   ZapOpHL
            JR   Z,ZapValidateLdLegacyHl
            CP   ZapOpBC
            JR   Z,ZapValidateLdLegacyBc
            JP   ZapInvalid
ZapValidateLdReg16Absolute:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpHL
            JP   Z,ZapValidateLength3
            JP   ZapValidateLength4
ZapValidateLdSp:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpHL
            JP   Z,ZapValidateLength1
            CP   ZapOpIX
            JP   Z,ZapValidateLength2
            CP   ZapOpIY
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateLdLegacyHl:
ZapValidateLdLegacyBc:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpDE
            JP   Z,ZapValidateLength2
            JP   ZapInvalid

ZapValidateLdIndex16:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength4
            CP   ZapOpMemAbs
            JP   Z,ZapValidateLength4
            JP   ZapInvalid
ZapValidateLdSpecial:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpA
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateLdMemAbs:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpA
            JP   Z,ZapValidateLength3
            CALL ZapIsReg16
            JR   NC,ZapValidateLdMemAbsIndex
            CP   ZapOpHL
            JP   Z,ZapValidateLength3
            JP   ZapValidateLength4
ZapValidateLdMemAbsIndex:
            CP   ZapOpIX
            JP   Z,ZapValidateLength4
            CP   ZapOpIY
            JP   Z,ZapValidateLength4
            JP   ZapInvalid
ZapValidateLdMemPair:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpA
            JP   Z,ZapValidateLength1
            JP   ZapInvalid
ZapValidateLdMemHL:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JP   C,ZapValidateLength1
            CP   ZapOpImm8
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateLdIndexed:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JP   C,ZapValidateLength3
            CP   ZapOpImm8
            JP   Z,ZapValidateLength4
            JP   ZapInvalid
ZapLdValidationEnd:

ZapValidateIn:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpPortC
            JR   Z,ZapValidateInOne
            CALL ZapIsReg8
            JP   NC,ZapInvalid
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpPortC
            JP   Z,ZapValidateLength2
            CP   ZapOpImm8
            JP   NZ,ZapInvalid
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpA
            JP   NZ,ZapInvalid
            JP   ZapValidateLength2
ZapValidateInOne:
            CALL ZapRequireOneOperand
            RET  C
            JP   ZapValidateLength2

ZapValidateOut:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpPortC
            JR   Z,ZapValidateOutC
            CP   ZapOpImm8
            JP   NZ,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpA
            JP   NZ,ZapInvalid
            JP   ZapValidateLength2
ZapValidateOutC:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpZero
            JP   Z,ZapValidateLength2
            CALL ZapIsReg8
            JP   C,ZapValidateLength2
            JP   ZapInvalid

ZapValidateBit:
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsBitIndex
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JR   C,ZapValidateBitPlain
            CP   ZapOpMemHL
            JR   Z,ZapValidateBitPlain
            CALL ZapIsIndexed
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrMnemonic)
            CP   ZapMBit
            JR   Z,ZapValidateBitIndexedNoDestination
            LD   A,(IX+ZapInstrOp2)
            CP   ZapOpNone
            JP   Z,ZapValidateLength4
            CALL ZapIsReg8
            JP   C,ZapValidateLength4
            JP   ZapInvalid
ZapValidateBitIndexedNoDestination:
            CALL ZapRequireTwoOperands
            RET  C
            JP   ZapValidateLength4
ZapValidateBitPlain:
            CALL ZapRequireTwoOperands
            RET  C
            JP   ZapValidateLength2

ZapValidateRotate:
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JR   C,ZapValidateRotatePlain
            CP   ZapOpMemHL
            JR   Z,ZapValidateRotatePlain
            CALL ZapIsIndexed
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JP   Z,ZapValidateLength4
            CALL ZapIsReg8
            JP   C,ZapValidateLength4
            JP   ZapInvalid
ZapValidateRotatePlain:
            CALL ZapRequireOneOperand
            RET  C
            JP   ZapValidateLength2

ZapValidateAlu:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapValidateAlu16
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JP   C,ZapValidateLength1
            CP   ZapOpMemHL
            JP   Z,ZapValidateLength1
            CP   ZapOpImm8
            JP   Z,ZapValidateLength2
            CALL ZapIsHalfIndex
            JP   C,ZapValidateLength2
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsIndexed
            JP   C,ZapValidateLength3
            JP   ZapInvalid
ZapValidateAlu16:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrMnemonic)
            CP   ZapMAdd
            JR   Z,ZapValidateAdd16
            CP   ZapMAdc
            JR   Z,ZapValidateAdcSbc16
            CP   ZapMSbc
            JP   NZ,ZapInvalid
ZapValidateAdcSbc16:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpHL
            JP   NZ,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg16
            JP   C,ZapValidateLength2
            JP   ZapInvalid
ZapValidateAdd16:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpHL
            JR   Z,ZapValidateAddHl
            CP   ZapOpIX
            JR   Z,ZapValidateAddIndex
            CP   ZapOpIY
            JP   NZ,ZapInvalid
ZapValidateAddIndex:
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpBC
            JP   Z,ZapValidateLength2
            CP   ZapOpDE
            JP   Z,ZapValidateLength2
            CP   ZapOpSP
            JP   Z,ZapValidateLength2
            CP   B
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateAddHl:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg16
            JP   C,ZapValidateLength1
            JP   ZapInvalid

ZapValidateJp:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapValidateJpConditional
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength3
            CP   ZapOpMemHL
            JP   Z,ZapValidateLength1
            CP   ZapOpMemIX
            JP   Z,ZapValidateLength2
            CP   ZapOpMemIY
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateJpConditional:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsCondition
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength3
            JP   ZapInvalid

ZapValidateCall:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapValidateCallConditional
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength3
            JP   ZapInvalid
ZapValidateCallConditional:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsCondition
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            JP   Z,ZapValidateLength3
            JP   ZapInvalid

ZapValidateJr:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapValidateJrConditional
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpRel8
            JP   Z,ZapValidateLength2
            JP   ZapInvalid
ZapValidateJrConditional:
            CALL ZapRequireTwoOperands
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsRelativeCondition
            JP   NC,ZapInvalid
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpRel8
            JP   Z,ZapValidateLength2
            JP   ZapInvalid

ZapValidateDjnz:
            CALL ZapRequireOneOperand
            RET  C
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpRel8
            JP   Z,ZapValidateLength2
            JP   ZapInvalid

ZapValidateLength1:
            LD   A,1
            OR   A
            RET
ZapValidateLength2:
            LD   A,2
            OR   A
            RET
ZapValidateLength3:
            LD   A,3
            OR   A
            RET
ZapValidateLength4:
            LD   A,4
            OR   A
            RET
ZapInvalid:
            XOR  A
            SCF
            RET

; Shape helpers reject hidden operands after the declared arity.
ZapRequireNoOperands:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpNone
            JR   NZ,ZapRequireBad
ZapRequireOneOperand:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapRequireBad
ZapRequireTwoOperands:
            LD   A,(IX+ZapInstrOp2)
            CP   ZapOpNone
            RET  Z
ZapRequireBad:
            XOR  A
            SCF
            RET

ZapIsReg8:
            CP   ZapOpMemHL
            JR   C,ZapPredicateYes
            CP   ZapOpA
            JR   Z,ZapPredicateYes
            OR   A
            RET
ZapIsReg16:
            CP   ZapOpBC
            JR   C,ZapPredicateNo
            CP   ZapOpSP+1
            JR   C,ZapPredicateYes
            OR   A
            RET
ZapIsHalfIndex:
            CP   ZapOpIXH
            JR   Z,ZapPredicateYes
            CP   ZapOpIXL
            JR   Z,ZapPredicateYes
            CP   ZapOpIYH
            JR   Z,ZapPredicateYes
            CP   ZapOpIYL
            JR   Z,ZapPredicateYes
            OR   A
            RET
ZapIsIndexed:
            CP   ZapOpIndexIX
            JR   Z,ZapPredicateYes
            CP   ZapOpIndexIY
            JR   Z,ZapPredicateYes
            OR   A
            RET
ZapIsCondition:
            CP   ZapOpNZ
            JR   C,ZapPredicateNo
            CP   ZapOpM+1
            JR   C,ZapPredicateYes
            OR   A
            RET
ZapIsRelativeCondition:
            CP   ZapOpNZ
            JR   C,ZapPredicateNo
            CP   ZapOpCC+1
            JR   C,ZapPredicateYes
            OR   A
            RET
ZapIsBitIndex:
            CP   ZapOpBit0
            JR   C,ZapPredicateNo
            CP   ZapOpBit7+1
            JR   C,ZapPredicateYes
ZapPredicateNo:
            OR   A
            RET
ZapPredicateYes:
            SCF
            RET

ZapValidationCodeEnd:

; ---------------------------------------------------------------------------
; Rule-driven encoding. ZapEncodeCore is entered only after validation.
; ---------------------------------------------------------------------------
ZapRuleEncodingCodeStart:

; in IX=record, DE=output; out A=length, carry clear, DE advanced on success
.routine in DE,IX out A,DE,carry clobbers zero,sign,parity,halfCarry,BC,HL
ZapEncode:
            PUSH DE
            CALL ZapValidateForm
            POP  DE
            RET  C
            PUSH DE
            CALL ZapEncodeCore
            POP  DE
            LD   C,A
            LD   B,0
            LD   HL,ZapScratch
            LDIR
            OR   A
            RET

ZapEncodeCore:
            LD   A,(IX+ZapInstrMnemonic)
            CP   ZapMRet
            JP   C,ZapEncodeCoreOpcode
            JP   Z,ZapEncodeRet
            CP   ZapMEx
            JP   Z,ZapEncodeEx
            CP   ZapMIm
            JP   Z,ZapEncodeIm
            CP   ZapMRst
            JP   Z,ZapEncodeRst
            CP   ZapMInc
            JP   Z,ZapEncodeIncDec
            CP   ZapMDec
            JP   Z,ZapEncodeIncDec
            CP   ZapMPush
            JP   Z,ZapEncodeStack
            CP   ZapMPop
            JP   Z,ZapEncodeStack
            CP   ZapMLd
            JP   Z,ZapEncodeLd
            CP   ZapMIn
            JP   Z,ZapEncodeIn
            CP   ZapMOut
            JP   Z,ZapEncodeOut
            CP   ZapMBit
            JP   C,ZapInvalid
            CP   ZapMSet+1
            JP   C,ZapEncodeBit
            CP   ZapMRlc
            JP   C,ZapInvalid
            CP   ZapMSrl+1
            JP   C,ZapEncodeRotate
            CP   ZapMAdd
            JP   C,ZapInvalid
            CP   ZapMCp+1
            JP   C,ZapEncodeAlu
            CP   ZapMJp
            JP   Z,ZapEncodeJp
            CP   ZapMCall
            JP   Z,ZapEncodeCall
            CP   ZapMJr
            JP   Z,ZapEncodeJr
            JP   ZapEncodeDjnz

ZapEncodeCoreOpcode:
            DEC  A
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,ZapCoreOpcodes
            ADD  HL,DE
            LD   A,(HL)
            LD   (ZapScratch+0),A
            INC  HL
            LD   A,(HL)
            OR   A
            JP   Z,ZapEncoded1
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeRet:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpNone
            JR   Z,ZapEncodeRetPlain
            SUB  ZapOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C0
            JP   ZapStoreEncoded1
ZapEncodeRetPlain:
            LD   A,$C9
            JP   ZapStoreEncoded1

ZapEncodeEx:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpAF
            JR   Z,ZapEncodeExAf
            CP   ZapOpDE
            JR   Z,ZapEncodeExDe
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpHL
            JR   Z,ZapEncodeExSpHl
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$E3
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeExAf:
            LD   A,$08
            JP   ZapStoreEncoded1
ZapEncodeExDe:
            LD   A,$EB
            JP   ZapStoreEncoded1
ZapEncodeExSpHl:
            LD   A,$E3
            JP   ZapStoreEncoded1

ZapEncodeIm:
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrOp0)
            SUB  ZapOpIm0
            LD   E,A
            LD   D,0
            LD   HL,ZapImOpcodes
            ADD  HL,DE
            LD   A,(HL)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeRst:
            LD   A,(IX+ZapInstrOp0)
            SUB  ZapOpRst0
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C7
            JP   ZapStoreEncoded1

ZapEncodeIncDec:
            LD   A,(IX+ZapInstrMnemonic)
            SUB  ZapMInc-4
            LD   B,A                 ; INC base 4, DEC base 5
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JR   C,ZapEncodeIncDecRegister
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg16
            JR   C,ZapEncodeIncDecPair
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIX
            JR   Z,ZapEncodeIncDecIndexPair
            CP   ZapOpIY
            JR   Z,ZapEncodeIncDecIndexPair
            CALL ZapIsHalfIndex
            JR   C,ZapEncodeIncDecHalf
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpMemHL
            JR   Z,ZapEncodeIncDecMemHl
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,B
            ADD  A,$30
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            JP   ZapEncoded3
ZapEncodeIncDecRegister:
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   ZapStoreEncoded1
ZapEncodeIncDecPair:
            LD   A,B
            CP   4
            LD   B,$03
            JR   Z,ZapEncodeIncDecPairBaseReady
            LD   B,$0B
ZapEncodeIncDecPairBaseReady:
            LD   A,(IX+ZapInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   ZapStoreEncoded1
ZapEncodeIncDecIndexPair:
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            LD   A,B
            CP   4
            LD   A,$23
            JR   Z,ZapEncodeIncDecIndexPairReady
            LD   A,$2B
ZapEncodeIncDecIndexPairReady:
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeIncDecHalf:
            LD   A,(IX+ZapInstrOp0)
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeIncDecMemHl:
            LD   A,B
            ADD  A,$30
            JP   ZapStoreEncoded1

ZapEncodeStack:
            LD   A,(IX+ZapInstrMnemonic)
            CP   ZapMPush
            LD   B,$C5
            JR   Z,ZapEncodeStackBase
            LD   B,$C1
ZapEncodeStackBase:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIX
            JR   Z,ZapEncodeStackIndex
            CP   ZapOpIY
            JR   Z,ZapEncodeStackIndex
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   ZapStoreEncoded1
ZapEncodeStackIndex:
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,B
            ADD  A,$20
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapLdEncodingStart:
ZapEncodeLd:
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg8
            JP   C,ZapEncodeLdReg8
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsHalfIndex
            JP   C,ZapEncodeLdHalf
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsReg16
            JP   C,ZapEncodeLdReg16
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpIX
            JP   Z,ZapEncodeLdIndex16
            CP   ZapOpIY
            JP   Z,ZapEncodeLdIndex16
            CP   ZapOpI
            JP   Z,ZapEncodeLdSpecialTarget
            CP   ZapOpR
            JP   Z,ZapEncodeLdSpecialTarget
            CP   ZapOpMemAbs
            JP   Z,ZapEncodeLdMemAbs
            CP   ZapOpMemBC
            JP   Z,ZapEncodeLdMemPair
            CP   ZapOpMemDE
            JP   Z,ZapEncodeLdMemPair
            CP   ZapOpMemHL
            JP   Z,ZapEncodeLdMemHl
            JP   ZapEncodeLdIndexed

ZapEncodeLdReg8:
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsReg8
            JR   C,ZapEncodeLdRegReg
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm8
            JR   Z,ZapEncodeLdRegImm
            CP   ZapOpMemHL
            JR   Z,ZapEncodeLdRegMemHl
            CP   ZapOpMemAbs
            JR   Z,ZapEncodeLdAAbs
            CP   ZapOpMemBC
            JR   Z,ZapEncodeLdAMemPair
            CP   ZapOpMemDE
            JR   Z,ZapEncodeLdAMemPair
            CP   ZapOpI
            JR   Z,ZapEncodeLdASpecial
            CP   ZapOpR
            JR   Z,ZapEncodeLdASpecial
            CALL ZapIsIndexed
            JR   C,ZapEncodeLdRegIndexed
            JP   ZapEncodeLdRegHalf
ZapEncodeLdRegReg:
            LD   B,A
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            JP   ZapStoreEncoded1
ZapEncodeLdRegImm:
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,6
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeLdRegMemHl:
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            JP   ZapStoreEncoded1
ZapEncodeLdAAbs:
            LD   A,$3A
            LD   (ZapScratch+0),A
            CALL ZapCopyValue1ToScratch1
            JP   ZapEncoded3
ZapEncodeLdAMemPair:
            SUB  ZapOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$0A
            JP   ZapStoreEncoded1
ZapEncodeLdASpecial:
            LD   B,$57
            CP   ZapOpI
            JR   Z,ZapEncodeLdASpecialReady
            LD   B,$5F
ZapEncodeLdASpecialReady:
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeLdRegIndexed:
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            LD   (ZapScratch+1),A
            POP  AF
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+2),A
            JP   ZapEncoded3
ZapEncodeLdRegHalf:
            LD   A,(IX+ZapInstrOp1)
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            AND  7
            LD   B,A
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeLdHalf:
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            AND  7
            ADD  A,B
            ADD  A,$40
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeLdReg16:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            JR   Z,ZapEncodeLdReg16Imm
            CP   ZapOpMemAbs
            JR   Z,ZapEncodeLdReg16Abs
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpSP
            JR   Z,ZapEncodeLdSp
            CP   ZapOpHL
            LD   A,$62
            JR   Z,ZapEncodeLdLegacy
            LD   A,$42
ZapEncodeLdLegacy:
            LD   (ZapScratch+0),A
            ADD  A,9
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeLdReg16Imm:
            LD   A,(IX+ZapInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            INC  A
            LD   (ZapScratch+0),A
            CALL ZapCopyValue1ToScratch1
            JP   ZapEncoded3
ZapEncodeLdReg16Abs:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpHL
            JR   Z,ZapEncodeLdHlAbs
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$4B
            LD   B,A
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            CALL ZapCopyValue1ToScratch2
            JP   ZapEncoded4
ZapEncodeLdHlAbs:
            LD   A,$2A
            LD   (ZapScratch+0),A
            CALL ZapCopyValue1ToScratch1
            JP   ZapEncoded3
ZapEncodeLdSp:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpHL
            LD   A,$F9
            JP   Z,ZapStoreEncoded1
            LD   A,(IX+ZapInstrOp1)
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$F9
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeLdIndex16:
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm16
            LD   A,$21
            JP   Z,ZapEncodeLdIndex16Opcode
            LD   A,$2A
ZapEncodeLdIndex16Opcode:
            LD   (ZapScratch+1),A
            CALL ZapCopyValue1ToScratch2
            JP   ZapEncoded4
ZapEncodeLdSpecialTarget:
            LD   B,$47
            CP   ZapOpI
            JP   Z,ZapEncodeLdSpecialTargetReady
            LD   B,$4F
ZapEncodeLdSpecialTargetReady:
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeLdMemAbs:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpA
            JR   Z,ZapEncodeLdAbsA
            CALL ZapIsReg16
            JR   NC,ZapEncodeLdAbsIndex
            CP   ZapOpHL
            JR   Z,ZapEncodeLdAbsHl
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$43
            LD   B,A
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            CALL ZapCopyValue0ToScratch2
            JP   ZapEncoded4
ZapEncodeLdAbsA:
            LD   A,$32
            LD   (ZapScratch+0),A
            CALL ZapCopyValue0ToScratch1
            JP   ZapEncoded3
ZapEncodeLdAbsHl:
            LD   A,$22
            LD   (ZapScratch+0),A
            CALL ZapCopyValue0ToScratch1
            JP   ZapEncoded3
ZapEncodeLdAbsIndex:
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$22
            LD   (ZapScratch+1),A
            CALL ZapCopyValue0ToScratch2
            JP   ZapEncoded4
ZapEncodeLdMemPair:
            SUB  ZapOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$02
            JP   ZapStoreEncoded1
ZapEncodeLdMemHl:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm8
            JR   Z,ZapEncodeLdMemHlImm
            ADD  A,$70
            JP   ZapStoreEncoded1
ZapEncodeLdMemHlImm:
            LD   A,$36
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeLdIndexed:
            LD   A,(IX+ZapInstrOp0)
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm8
            JR   Z,ZapEncodeLdIndexedImm
            ADD  A,$70
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            JP   ZapEncoded3
ZapEncodeLdIndexedImm:
            LD   A,$36
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+3),A
            JP   ZapEncoded4
ZapLdEncodingEnd:

ZapEncodeIn:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpPortC
            JR   Z,ZapEncodeInBare
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpImm8
            JR   Z,ZapEncodeInImmediate
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$40
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeInBare:
            LD   A,$70
            JR   ZapEncodeInEd
ZapEncodeInImmediate:
            LD   A,$DB
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeInEd:
            LD   B,A
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeOut:
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpImm8
            JR   Z,ZapEncodeOutImmediate
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpZero
            LD   A,$71
            JP   Z,ZapEncodeInEd
            LD   A,(IX+ZapInstrOp1)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$41
            JR   ZapEncodeInEd
ZapEncodeOutImmediate:
            LD   A,$D3
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeBit:
            LD   A,(IX+ZapInstrMnemonic)
            SUB  ZapMBit-1
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+ZapInstrOp0)
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            CALL ZapIsIndexed
            JR   C,ZapEncodeBitIndexed
            LD   A,(IX+ZapInstrOp1)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeBitIndexed:
            LD   A,(IX+ZapInstrOp2)
            CP   ZapOpNone
            LD   A,6
            JR   Z,ZapEncodeBitIndexedCode
            LD   A,(IX+ZapInstrOp2)
            AND  7
ZapEncodeBitIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$CB
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+2),A
            LD   A,B
            LD   (ZapScratch+3),A
            JP   ZapEncoded4

ZapEncodeRotate:
            LD   A,(IX+ZapInstrMnemonic)
            SUB  ZapMRlc
            LD   E,A
            LD   D,0
            LD   HL,ZapRotateBases
            ADD  HL,DE
            LD   B,(HL)
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsIndexed
            JR   C,ZapEncodeRotateIndexed
            LD   A,(IX+ZapInstrOp0)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeRotateIndexed:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            LD   A,6
            JR   Z,ZapEncodeRotateIndexedCode
            LD   A,(IX+ZapInstrOp1)
            AND  7
ZapEncodeRotateIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+ZapInstrOp0)
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$CB
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            LD   A,B
            LD   (ZapScratch+3),A
            JP   ZapEncoded4

ZapEncodeAlu:
            LD   A,(IX+ZapInstrMnemonic)
            SUB  ZapMAdd
            LD   E,A
            LD   D,0
            LD   HL,ZapAluOrder
            ADD  HL,DE
            LD   A,(HL)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapEncodeAlu16
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpImm8
            JR   Z,ZapEncodeAluImmediate
            CALL ZapIsHalfIndex
            JR   C,ZapEncodeAluHalf
            LD   A,(IX+ZapInstrOp0)
            CALL ZapIsIndexed
            JR   C,ZapEncodeAluIndexed
            LD   A,(IX+ZapInstrOp0)
            AND  7
            ADD  A,B
            ADD  A,$80
            JP   ZapStoreEncoded1
ZapEncodeAluImmediate:
            LD   A,B
            ADD  A,$C6
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeAluHalf:
            LD   A,(IX+ZapInstrOp0)
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            AND  7
            ADD  A,B
            ADD  A,$80
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeAluIndexed:
            PUSH AF
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            POP  AF
            LD   A,B
            ADD  A,$86
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            JP   ZapEncoded3
ZapEncodeAlu16:
            LD   A,(IX+ZapInstrMnemonic)
            CP   ZapMAdd
            JR   Z,ZapEncodeAdd16
            LD   B,$42
            CP   ZapMSbc
            JR   Z,ZapEncodeAdcSbc16Ready
            LD   B,$4A
ZapEncodeAdcSbc16Ready:
            LD   A,(IX+ZapInstrOp1)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   B,A
            LD   A,$ED
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeAdd16:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpIX
            JR   Z,ZapEncodeAdd16Self
            CP   ZapOpIY
            JR   Z,ZapEncodeAdd16Self
            AND  3
            JR   ZapEncodeAdd16SourceReady
ZapEncodeAdd16Self:
            LD   A,2
ZapEncodeAdd16SourceReady:
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$09
            LD   B,A
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpHL
            LD   A,B
            JP   Z,ZapStoreEncoded1
            LD   A,(IX+ZapInstrOp0)
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,B
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeJp:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapEncodeJpConditional
            LD   A,(IX+ZapInstrOp0)
            CP   ZapOpMemHL
            JR   Z,ZapEncodeJpHl
            CP   ZapOpMemIX
            JR   Z,ZapEncodeJpIndex
            CP   ZapOpMemIY
            JR   Z,ZapEncodeJpIndex
            LD   A,$C3
            LD   (ZapScratch+0),A
            CALL ZapCopyValue0ToScratch1
            JP   ZapEncoded3
ZapEncodeJpConditional:
            LD   A,(IX+ZapInstrOp0)
            SUB  ZapOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C2
            LD   (ZapScratch+0),A
            CALL ZapCopyValue1ToScratch1
            JP   ZapEncoded3
ZapEncodeJpHl:
            LD   A,$E9
            JP   ZapStoreEncoded1
ZapEncodeJpIndex:
            CALL ZapPrefixFromOperand
            LD   (ZapScratch+0),A
            LD   A,$E9
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

ZapEncodeCall:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapEncodeCallConditional
            LD   A,$CD
            LD   (ZapScratch+0),A
            CALL ZapCopyValue0ToScratch1
            JP   ZapEncoded3
ZapEncodeCallConditional:
            LD   A,(IX+ZapInstrOp0)
            SUB  ZapOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C4
            LD   (ZapScratch+0),A
            CALL ZapCopyValue1ToScratch1
            JP   ZapEncoded3

ZapEncodeJr:
            LD   A,(IX+ZapInstrOp1)
            CP   ZapOpNone
            JR   NZ,ZapEncodeJrConditional
            LD   A,$18
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeJrConditional:
            LD   A,(IX+ZapInstrOp0)
            SUB  ZapOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$20
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2
ZapEncodeDjnz:
            LD   A,$10
            LD   (ZapScratch+0),A
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+1),A
            JP   ZapEncoded2

; Shared output helpers.
ZapCopyValue0ToScratch1:
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue0+1)
            LD   (ZapScratch+2),A
            RET
ZapCopyValue0ToScratch2:
            LD   A,(IX+ZapInstrValue0)
            LD   (ZapScratch+2),A
            LD   A,(IX+ZapInstrValue0+1)
            LD   (ZapScratch+3),A
            RET
ZapCopyValue1ToScratch1:
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+1),A
            LD   A,(IX+ZapInstrValue1+1)
            LD   (ZapScratch+2),A
            RET
ZapCopyValue1ToScratch2:
            LD   A,(IX+ZapInstrValue1)
            LD   (ZapScratch+2),A
            LD   A,(IX+ZapInstrValue1+1)
            LD   (ZapScratch+3),A
            RET

ZapPrefixFromOperand:
            CP   ZapOpIXH
            JR   C,ZapPrefixOrdinary
            CP   ZapOpIXL+1
            JR   C,ZapPrefixIX
            CP   ZapOpIYH
            JR   C,ZapPrefixOrdinary
            CP   ZapOpIYL+1
            JR   C,ZapPrefixIY
ZapPrefixOrdinary:
            AND  1
            JR   NZ,ZapPrefixIY
ZapPrefixIX:
            LD   A,$DD
            RET
ZapPrefixIY:
            LD   A,$FD
            RET

ZapStoreEncoded1:
            LD   (ZapScratch+0),A
ZapEncoded1:
            LD   A,1
            OR   A
            RET
ZapEncoded2:
            LD   A,2
            OR   A
            RET
ZapEncoded3:
            LD   A,3
            OR   A
            RET
ZapEncoded4:
            LD   A,4
            OR   A
            RET

ZapRuleEncodingCodeEnd:
ZapEncoderCodeEnd:

; ---------------------------------------------------------------------------
; Immutable data
; ---------------------------------------------------------------------------
ZapEncoderImmutableStart:
ZapOpcodeTableStart:

; Two bytes per no-operand mnemonic. A zero second byte marks length one.
ZapCoreOpcodes:
            .db $00,$00 ; NOP
            .db $F3,$00 ; DI
            .db $FB,$00 ; EI
            .db $37,$00 ; SCF
            .db $3F,$00 ; CCF
            .db $2F,$00 ; CPL
            .db $27,$00 ; DAA
            .db $D9,$00 ; EXX
            .db $76,$00 ; HALT
            .db $07,$00 ; RLCA
            .db $0F,$00 ; RRCA
            .db $17,$00 ; RLA
            .db $1F,$00 ; RRA
            .db $ED,$44 ; NEG
            .db $ED,$67 ; RRD
            .db $ED,$6F ; RLD
            .db $ED,$A0 ; LDI
            .db $ED,$B0 ; LDIR
            .db $ED,$A8 ; LDD
            .db $ED,$B8 ; LDDR
            .db $ED,$A1 ; CPI
            .db $ED,$B1 ; CPIR
            .db $ED,$A9 ; CPD
            .db $ED,$B9 ; CPDR
            .db $ED,$A2 ; INI
            .db $ED,$B2 ; INIR
            .db $ED,$AA ; IND
            .db $ED,$BA ; INDR
            .db $ED,$A3 ; OUTI
            .db $ED,$B3 ; OTIR
            .db $ED,$AB ; OUTD
            .db $ED,$BB ; OTDR
            .db $ED,$4D ; RETI
            .db $ED,$45 ; RETN

ZapImOpcodes:  .db $46,$56,$5E
ZapRotateBases: .db $00,$08,$10,$18,$20,$28,$30,$30,$38
; Ordinal order is ADD ADC SUB SBC AND XOR OR CP; values are hardware op fields.
ZapAluOrder:    .db 0,1,2,3,4,5,6,7

ZapOpcodeTableEnd:

            .include "zap-mnemonics.inc"

ZapEncoderImmutableEnd:
ZapEncoderCoreEnd:

; Writable, non-reentrant workspace. The first four bytes are also the encoder
; commit buffer. Search state overlays the unused tail after packing.
ZapEncoderWorkspaceStart:
ZapScratch:     .ds 6
ZapSearchLow:   .ds 1
ZapSearchHigh:  .ds 1
ZapSearchMid:   .ds 1
ZapEncoderWorkspaceEnd:
