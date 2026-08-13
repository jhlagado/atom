; atom Phase 1 parsed-instruction encoder.
; Link after selecting an origin. Writable workspace is declared after the
; immutable core so it is excluded from AtomEncoderCoreEnd.

            .include "atom-abi.asmi"

AtomEncoderCoreStart:
AtomEncoderCodeStart:

; ---------------------------------------------------------------------------
; RADIX-40 packer
; ---------------------------------------------------------------------------
AtomRadix40CodeStart:

; in HL=text, B=length 1..8, DE=destination
; out carry clear and three packed words committed; carry set leaves DE intact
.routine in B,DE,HL out carry clobbers zero,sign,parity,halfCarry,A,BC,DE,HL,IX
AtomRadix40Pack:
            LD   A,B
            OR   A
            JP   Z,AtomPackInvalid
            CP   9
            JP   NC,AtomPackInvalid

            ; Validate before touching even the scratch representation.
            PUSH HL
            PUSH BC
AtomPackValidateLoop:
            LD   A,(HL)
            CALL AtomRadix40Character
            JP   C,AtomPackValidateFailed
            INC  HL
            DJNZ AtomPackValidateLoop
            POP  BC
            POP  HL

            PUSH DE
            LD   IX,AtomScratch
            LD   A,B

            ; First group: three positions.
            CP   3
            JR   C,AtomPackFirstShort
            LD   B,3
            SUB  3
            JR   AtomPackFirstReady
AtomPackFirstShort:
            LD   B,A
            XOR  A
AtomPackFirstReady:
            PUSH AF
            LD   C,3
            CALL AtomPackGroup
            LD   (IX+0),E
            LD   (IX+1),D
            POP  AF

            ; Second group: three positions.
            CP   3
            JR   C,AtomPackSecondShort
            LD   B,3
            SUB  3
            JR   AtomPackSecondReady
AtomPackSecondShort:
            LD   B,A
            XOR  A
AtomPackSecondReady:
            PUSH AF
            LD   C,3
            CALL AtomPackGroup
            LD   (IX+2),E
            LD   (IX+3),D
            POP  AF

            ; Final group: two positions, c6*40+c7.
            LD   B,A
            LD   C,2
            CALL AtomPackGroup
            LD   (IX+4),E
            LD   (IX+5),D

            POP  DE
            LD   HL,AtomScratch
            LD   BC,6
            LDIR
            OR   A
            RET

AtomPackValidateFailed:
            POP  BC
            POP  HL
AtomPackInvalid:
            XOR  A
            SCF
            RET

; in HL=text, B=actual characters, C=field width (2 or 3)
; out DE=packed field, HL advanced by B, carry clear
.routine in B,C,HL out DE,HL,carry clobbers zero,sign,parity,halfCarry,A,BC
AtomPackGroup:
            LD   DE,0
AtomPackGroupLoop:
            LD   A,B
            OR   A
            JR   Z,AtomPackGroupPadding
            LD   A,(HL)
            INC  HL
            DEC  B
            CALL AtomRadix40Character
            JR   AtomPackGroupAppend
AtomPackGroupPadding:
            XOR  A
AtomPackGroupAppend:
            CALL AtomMultiplyAdd40
            DEC  C
            JR   NZ,AtomPackGroupLoop
            OR   A
            RET

; in DE=value, A=digit; out DE=value*40+digit. Preserves HL,BC.
.routine in A,DE out DE clobbers carry,zero,sign,parity,halfCarry,A
AtomMultiplyAdd40:
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
            JR   NC,AtomMultiplyAdd40NoCarry
            INC  H
AtomMultiplyAdd40NoCarry:
            EX   DE,HL
            POP  HL
            RET

; ASCII letters are folded to uppercase. Carry marks an invalid character.
.routine in A out A,carry clobbers zero,sign,parity,halfCarry
AtomRadix40Character:
            CP   "a"
            JR   C,AtomRadix40Upper
            CP   "z"+1
            JR   NC,AtomRadix40Upper
            SUB  $20
AtomRadix40Upper:
            CP   "A"
            JR   C,AtomRadix40Digit
            CP   "Z"+1
            JR   NC,AtomRadix40Digit
            SUB  "A"-1
            OR   A
            RET
AtomRadix40Digit:
            CP   "0"
            JR   C,AtomRadix40Underscore
            CP   "9"+1
            JR   NC,AtomRadix40Underscore
            SUB  "0"-27
            OR   A
            RET
AtomRadix40Underscore:
            CP   "_"
            JR   NZ,AtomRadix40Bad
            LD   A,37
            OR   A
            RET
AtomRadix40Bad:
            XOR  A
            SCF
            RET

AtomRadix40CodeEnd:

; ---------------------------------------------------------------------------
; Case-insensitive mnemonic recognizer
; ---------------------------------------------------------------------------
AtomRecognitionCodeStart:

; in HL=text, B=length; out A=ordinal and carry clear, or A=0 and carry set
.routine in B,HL out A,carry clobbers zero,sign,parity,halfCarry,BC,DE,HL,IX
AtomRecognizeMnemonic:
            LD   DE,AtomScratch
            CALL AtomRadix40Pack
            RET  C
            XOR  A
            LD   (AtomSearchLow),A
            LD   A,AtomMnemonicCount
            LD   (AtomSearchHigh),A
AtomRecognizeLoop:
            LD   A,(AtomSearchLow)
            LD   B,A
            LD   A,(AtomSearchHigh)
            CP   B
            JP   Z,AtomRecognizeNotFound
            ADD  A,B
            RRCA
            AND  $7F
            LD   (AtomSearchMid),A

            ; HL = table + mid*5.
            LD   E,A
            LD   D,0
            LD   H,D
            LD   L,E
            ADD  HL,HL
            ADD  HL,HL
            ADD  HL,DE
            LD   DE,AtomMnemonicTable
            ADD  HL,DE

            ; Compare packed words as unsigned integers, high byte first.
            INC  HL
            LD   A,(AtomScratch+1)
            CP   (HL)
            JR   C,AtomRecognizeBefore
            JR   NZ,AtomRecognizeAfter
            DEC  HL
            LD   A,(AtomScratch+0)
            CP   (HL)
            JR   C,AtomRecognizeBefore
            JR   NZ,AtomRecognizeAfter
            INC  HL
            INC  HL
            INC  HL
            LD   A,(AtomScratch+3)
            CP   (HL)
            JR   C,AtomRecognizeBefore
            JR   NZ,AtomRecognizeAfter
            DEC  HL
            LD   A,(AtomScratch+2)
            CP   (HL)
            JR   C,AtomRecognizeBefore
            JR   NZ,AtomRecognizeAfter
            INC  HL
            INC  HL
            LD   A,(HL)
            OR   A
            RET
AtomRecognizeBefore:
            LD   A,(AtomSearchMid)
            LD   (AtomSearchHigh),A
            JR   AtomRecognizeLoop
AtomRecognizeAfter:
            LD   A,(AtomSearchMid)
            INC  A
            LD   (AtomSearchLow),A
            JR   AtomRecognizeLoop
AtomRecognizeNotFound:
            XOR  A
            SCF
            RET

AtomRecognitionCodeEnd:

; ---------------------------------------------------------------------------
; Form validation and length
; ---------------------------------------------------------------------------
AtomValidationCodeStart:

; Values at offsets 4..9 are never read by this routine.
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,BC,DE,HL
AtomFormLength:
AtomValidateForm:
            LD   A,(IX+AtomInstrMnemonic)
            OR   A
            JP   Z,AtomInvalid
            CP   AtomMRet
            JP   C,AtomValidateCore
            JP   Z,AtomValidateRet
            CP   AtomMEx
            JP   Z,AtomValidateEx
            CP   AtomMIm
            JP   Z,AtomValidateIm
            CP   AtomMRst
            JP   Z,AtomValidateRst
            CP   AtomMInc
            JP   Z,AtomValidateIncDec
            CP   AtomMDec
            JP   Z,AtomValidateIncDec
            CP   AtomMPush
            JP   Z,AtomValidateStack
            CP   AtomMPop
            JP   Z,AtomValidateStack
            CP   AtomMLd
            JP   Z,AtomValidateLd
            CP   AtomMIn
            JP   Z,AtomValidateIn
            CP   AtomMOut
            JP   Z,AtomValidateOut
            CP   AtomMBit
            JP   C,AtomInvalid
            CP   AtomMSet+1
            JP   C,AtomValidateBit
            CP   AtomMRlc
            JP   C,AtomInvalid
            CP   AtomMSrl+1
            JP   C,AtomValidateRotate
            CP   AtomMAdd
            JP   C,AtomInvalid
            CP   AtomMCp+1
            JP   C,AtomValidateAlu
            CP   AtomMJp
            JP   Z,AtomValidateJp
            CP   AtomMCall
            JP   Z,AtomValidateCall
            CP   AtomMJr
            JP   Z,AtomValidateJr
            CP   AtomMDjnz
            JP   Z,AtomValidateDjnz
            JP   AtomInvalid

AtomValidateCore:
            CALL AtomRequireNoOperands
            RET  C
            LD   A,(IX+AtomInstrMnemonic)
            DEC  A
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,AtomCoreOpcodes+1
            ADD  HL,DE
            LD   A,(HL)
            OR   A
            LD   A,1
            RET  Z
            INC  A
            RET

AtomValidateRet:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JP   Z,AtomValidateLength1NoOperands
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            CALL AtomRequireOneOperand
            RET  C
            LD   A,1
            OR   A
            RET

AtomValidateLength1NoOperands:
            CALL AtomRequireNoOperands
            RET  C
            LD   A,1
            OR   A
            RET

AtomValidateEx:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpAF
            JR   Z,AtomValidateExAf
            CP   AtomOpDE
            JR   Z,AtomValidateExDe
            CP   AtomOpMemSP
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,AtomValidateLength1
            CP   AtomOpIX
            JP   Z,AtomValidateLength2
            CP   AtomOpIY
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateExAf:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpAFPrime
            JP   Z,AtomValidateLength1
            JP   AtomInvalid
AtomValidateExDe:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,AtomValidateLength1
            JP   AtomInvalid

AtomValidateIm:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIm0
            JP   C,AtomInvalid
            CP   AtomOpIm2+1
            JP   NC,AtomInvalid
            JP   AtomValidateLength2

AtomValidateRst:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRst0
            JP   C,AtomInvalid
            CP   AtomOpRst56+1
            JP   NC,AtomInvalid
            JP   AtomValidateLength1

AtomValidateIncDec:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomValidateLength1
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,AtomValidateLength1
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,AtomValidateLength2
            CP   AtomOpIY
            JP   Z,AtomValidateLength2
            CALL AtomIsHalfIndex
            JP   C,AtomValidateLength2
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JP   Z,AtomValidateLength1
            CALL AtomIsIndexed
            JP   C,AtomValidateLength3
            JP   AtomInvalid

AtomValidateStack:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpBC
            JP   Z,AtomValidateLength1
            CP   AtomOpDE
            JP   Z,AtomValidateLength1
            CP   AtomOpHL
            JP   Z,AtomValidateLength1
            CP   AtomOpAF
            JP   Z,AtomValidateLength1
            CP   AtomOpIX
            JP   Z,AtomValidateLength2
            CP   AtomOpIY
            JP   Z,AtomValidateLength2
            JP   AtomInvalid

AtomLdValidationStart:
AtomValidateLd:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomValidateLdReg8
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsHalfIndex
            JP   C,AtomValidateLdHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,AtomValidateLdReg16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,AtomValidateLdIndex16
            CP   AtomOpIY
            JP   Z,AtomValidateLdIndex16
            CP   AtomOpI
            JP   Z,AtomValidateLdSpecial
            CP   AtomOpR
            JP   Z,AtomValidateLdSpecial
            CP   AtomOpMemAbs
            JP   Z,AtomValidateLdMemAbs
            CP   AtomOpMemBC
            JP   Z,AtomValidateLdMemPair
            CP   AtomOpMemDE
            JP   Z,AtomValidateLdMemPair
            CP   AtomOpMemHL
            JP   Z,AtomValidateLdMemHL
            CALL AtomIsIndexed
            JP   C,AtomValidateLdIndexed
            JP   AtomInvalid

AtomValidateLdReg8:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,AtomValidateLength1
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JP   Z,AtomValidateLength2
            CP   AtomOpMemHL
            JP   Z,AtomValidateLength1
            CP   AtomOpMemAbs
            JR   Z,AtomValidateLdReg8Absolute
            CP   AtomOpMemBC
            JR   Z,AtomValidateLdReg8Accumulator
            CP   AtomOpMemDE
            JR   Z,AtomValidateLdReg8Accumulator
            CP   AtomOpI
            JR   Z,AtomValidateLdReg8Accumulator2
            CP   AtomOpR
            JR   Z,AtomValidateLdReg8Accumulator2
            CALL AtomIsIndexed
            JP   C,AtomValidateLength3
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpH
            JP   Z,AtomInvalid
            CP   AtomOpL
            JP   Z,AtomInvalid
            JP   AtomValidateLength2
AtomValidateLdReg8Absolute:
AtomValidateLdReg8Accumulator:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpMemAbs
            JP   Z,AtomValidateLength3
            JP   AtomValidateLength1
AtomValidateLdReg8Accumulator2:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   AtomValidateLength2

AtomValidateLdHalf:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JR   C,AtomValidateLdHalfFamily
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   NC,AtomInvalid
            CP   AtomOpH
            JP   Z,AtomInvalid
            CP   AtomOpL
            JP   Z,AtomInvalid
            JP   AtomValidateLength2
AtomValidateLdHalfFamily:
            LD   A,(IX+AtomInstrOp0)
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            XOR  B
            AND  $08
            JP   NZ,AtomInvalid
            JP   AtomValidateLength2

AtomValidateLdReg16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength3
            CP   AtomOpMemAbs
            JR   Z,AtomValidateLdReg16Absolute
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpSP
            JR   Z,AtomValidateLdSp
            CP   AtomOpHL
            JR   Z,AtomValidateLdLegacyHl
            CP   AtomOpBC
            JR   Z,AtomValidateLdLegacyBc
            JP   AtomInvalid
AtomValidateLdReg16Absolute:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JP   Z,AtomValidateLength3
            JP   AtomValidateLength4
AtomValidateLdSp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,AtomValidateLength1
            CP   AtomOpIX
            JP   Z,AtomValidateLength2
            CP   AtomOpIY
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateLdLegacyHl:
AtomValidateLdLegacyBc:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpDE
            JP   Z,AtomValidateLength2
            JP   AtomInvalid

AtomValidateLdIndex16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength4
            CP   AtomOpMemAbs
            JP   Z,AtomValidateLength4
            JP   AtomInvalid
AtomValidateLdSpecial:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateLdMemAbs:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,AtomValidateLength3
            CALL AtomIsReg16
            JR   NC,AtomValidateLdMemAbsIndex
            CP   AtomOpHL
            JP   Z,AtomValidateLength3
            JP   AtomValidateLength4
AtomValidateLdMemAbsIndex:
            CP   AtomOpIX
            JP   Z,AtomValidateLength4
            CP   AtomOpIY
            JP   Z,AtomValidateLength4
            JP   AtomInvalid
AtomValidateLdMemPair:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,AtomValidateLength1
            JP   AtomInvalid
AtomValidateLdMemHL:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,AtomValidateLength1
            CP   AtomOpImm8
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateLdIndexed:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,AtomValidateLength3
            CP   AtomOpImm8
            JP   Z,AtomValidateLength4
            JP   AtomInvalid
AtomLdValidationEnd:

AtomValidateIn:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,AtomValidateInOne
            CALL AtomIsReg8
            JP   NC,AtomInvalid
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpPortC
            JP   Z,AtomValidateLength2
            CP   AtomOpImm8
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   AtomValidateLength2
AtomValidateInOne:
            CALL AtomRequireOneOperand
            RET  C
            JP   AtomValidateLength2

AtomValidateOut:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,AtomValidateOutC
            CP   AtomOpImm8
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   AtomValidateLength2
AtomValidateOutC:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            JP   Z,AtomValidateLength2
            CALL AtomIsReg8
            JP   C,AtomValidateLength2
            JP   AtomInvalid

AtomValidateBit:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsBitIndex
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JR   C,AtomValidateBitPlain
            CP   AtomOpMemHL
            JR   Z,AtomValidateBitPlain
            CALL AtomIsIndexed
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMBit
            JR   Z,AtomValidateBitIndexedNoDestination
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            JP   Z,AtomValidateLength4
            CALL AtomIsReg8
            JP   C,AtomValidateLength4
            JP   AtomInvalid
AtomValidateBitIndexedNoDestination:
            CALL AtomRequireTwoOperands
            RET  C
            JP   AtomValidateLength4
AtomValidateBitPlain:
            CALL AtomRequireTwoOperands
            RET  C
            JP   AtomValidateLength2

AtomValidateRotate:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,AtomValidateRotatePlain
            CP   AtomOpMemHL
            JR   Z,AtomValidateRotatePlain
            CALL AtomIsIndexed
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JP   Z,AtomValidateLength4
            CALL AtomIsReg8
            JP   C,AtomValidateLength4
            JP   AtomInvalid
AtomValidateRotatePlain:
            CALL AtomRequireOneOperand
            RET  C
            JP   AtomValidateLength2

AtomValidateAlu:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomValidateAlu16
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomValidateLength1
            CP   AtomOpMemHL
            JP   Z,AtomValidateLength1
            CP   AtomOpImm8
            JP   Z,AtomValidateLength2
            CALL AtomIsHalfIndex
            JP   C,AtomValidateLength2
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JP   C,AtomValidateLength3
            JP   AtomInvalid
AtomValidateAlu16:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   Z,AtomValidateAdd16
            CP   AtomMAdc
            JR   Z,AtomValidateAdcSbc16
            CP   AtomMSbc
            JP   NZ,AtomInvalid
AtomValidateAdcSbc16:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg16
            JP   C,AtomValidateLength2
            JP   AtomInvalid
AtomValidateAdd16:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JR   Z,AtomValidateAddHl
            CP   AtomOpIX
            JR   Z,AtomValidateAddIndex
            CP   AtomOpIY
            JP   NZ,AtomInvalid
AtomValidateAddIndex:
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpBC
            JP   Z,AtomValidateLength2
            CP   AtomOpDE
            JP   Z,AtomValidateLength2
            CP   AtomOpSP
            JP   Z,AtomValidateLength2
            CP   B
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateAddHl:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg16
            JP   C,AtomValidateLength1
            JP   AtomInvalid

AtomValidateJp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomValidateJpConditional
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength3
            CP   AtomOpMemHL
            JP   Z,AtomValidateLength1
            CP   AtomOpMemIX
            JP   Z,AtomValidateLength2
            CP   AtomOpMemIY
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateJpConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength3
            JP   AtomInvalid

AtomValidateCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomValidateCallConditional
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength3
            JP   AtomInvalid
AtomValidateCallConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomValidateLength3
            JP   AtomInvalid

AtomValidateJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomValidateJrConditional
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRel8
            JP   Z,AtomValidateLength2
            JP   AtomInvalid
AtomValidateJrConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsRelativeCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpRel8
            JP   Z,AtomValidateLength2
            JP   AtomInvalid

AtomValidateDjnz:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRel8
            JP   Z,AtomValidateLength2
            JP   AtomInvalid

AtomValidateLength1:
            LD   A,1
            OR   A
            RET
AtomValidateLength2:
            LD   A,2
            OR   A
            RET
AtomValidateLength3:
            LD   A,3
            OR   A
            RET
AtomValidateLength4:
            LD   A,4
            OR   A
            RET
AtomInvalid:
            XOR  A
            SCF
            RET

; Shape helpers reject hidden operands after the declared arity.
AtomRequireNoOperands:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
AtomRequireOneOperand:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
AtomRequireTwoOperands:
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            RET  Z
AtomRequireBad:
            XOR  A
            SCF
            RET

AtomIsReg8:
            CP   AtomOpMemHL
            JR   C,AtomPredicateYes
            CP   AtomOpA
            JR   Z,AtomPredicateYes
            OR   A
            RET
AtomIsReg16:
            CP   AtomOpBC
            JR   C,AtomPredicateNo
            CP   AtomOpSP+1
            JR   C,AtomPredicateYes
            OR   A
            RET
AtomIsHalfIndex:
            CP   AtomOpIXH
            JR   Z,AtomPredicateYes
            CP   AtomOpIXL
            JR   Z,AtomPredicateYes
            CP   AtomOpIYH
            JR   Z,AtomPredicateYes
            CP   AtomOpIYL
            JR   Z,AtomPredicateYes
            OR   A
            RET
AtomIsIndexed:
            CP   AtomOpIndexIX
            JR   Z,AtomPredicateYes
            CP   AtomOpIndexIY
            JR   Z,AtomPredicateYes
            OR   A
            RET
AtomIsCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpM+1
            JR   C,AtomPredicateYes
            OR   A
            RET
AtomIsRelativeCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpCC+1
            JR   C,AtomPredicateYes
            OR   A
            RET
AtomIsBitIndex:
            CP   AtomOpBit0
            JR   C,AtomPredicateNo
            CP   AtomOpBit7+1
            JR   C,AtomPredicateYes
AtomPredicateNo:
            OR   A
            RET
AtomPredicateYes:
            SCF
            RET

AtomValidationCodeEnd:

; ---------------------------------------------------------------------------
; Rule-driven encoding. AtomEncodeCore is entered only after validation.
; ---------------------------------------------------------------------------
AtomRuleEncodingCodeStart:

; in IX=record, DE=output; out A=length, carry clear, DE advanced on success
.routine in DE,IX out A,DE,carry clobbers zero,sign,parity,halfCarry,BC,HL
AtomEncode:
            PUSH DE
            CALL AtomValidateForm
            POP  DE
            RET  C
            PUSH DE
            CALL AtomEncodeCore
            POP  DE
            LD   C,A
            LD   B,0
            LD   HL,AtomScratch
            LDIR
            OR   A
            RET

AtomEncodeCore:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMRet
            JP   C,AtomEncodeCoreOpcode
            JP   Z,AtomEncodeRet
            CP   AtomMEx
            JP   Z,AtomEncodeEx
            CP   AtomMIm
            JP   Z,AtomEncodeIm
            CP   AtomMRst
            JP   Z,AtomEncodeRst
            CP   AtomMInc
            JP   Z,AtomEncodeIncDec
            CP   AtomMDec
            JP   Z,AtomEncodeIncDec
            CP   AtomMPush
            JP   Z,AtomEncodeStack
            CP   AtomMPop
            JP   Z,AtomEncodeStack
            CP   AtomMLd
            JP   Z,AtomEncodeLd
            CP   AtomMIn
            JP   Z,AtomEncodeIn
            CP   AtomMOut
            JP   Z,AtomEncodeOut
            CP   AtomMBit
            JP   C,AtomInvalid
            CP   AtomMSet+1
            JP   C,AtomEncodeBit
            CP   AtomMRlc
            JP   C,AtomInvalid
            CP   AtomMSrl+1
            JP   C,AtomEncodeRotate
            CP   AtomMAdd
            JP   C,AtomInvalid
            CP   AtomMCp+1
            JP   C,AtomEncodeAlu
            CP   AtomMJp
            JP   Z,AtomEncodeJp
            CP   AtomMCall
            JP   Z,AtomEncodeCall
            CP   AtomMJr
            JP   Z,AtomEncodeJr
            JP   AtomEncodeDjnz

AtomEncodeCoreOpcode:
            DEC  A
            ADD  A,A
            LD   E,A
            LD   D,0
            LD   HL,AtomCoreOpcodes
            ADD  HL,DE
            LD   A,(HL)
            LD   (AtomScratch+0),A
            INC  HL
            LD   A,(HL)
            OR   A
            JP   Z,AtomEncoded1
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeRet:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JR   Z,AtomEncodeRetPlain
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C0
            JP   AtomStoreEncoded1
AtomEncodeRetPlain:
            LD   A,$C9
            JP   AtomStoreEncoded1

AtomEncodeEx:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpAF
            JR   Z,AtomEncodeExAf
            CP   AtomOpDE
            JR   Z,AtomEncodeExDe
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JR   Z,AtomEncodeExSpHl
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$E3
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeExAf:
            LD   A,$08
            JP   AtomStoreEncoded1
AtomEncodeExDe:
            LD   A,$EB
            JP   AtomStoreEncoded1
AtomEncodeExSpHl:
            LD   A,$E3
            JP   AtomStoreEncoded1

AtomEncodeIm:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpIm0
            LD   E,A
            LD   D,0
            LD   HL,AtomImOpcodes
            ADD  HL,DE
            LD   A,(HL)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeRst:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpRst0
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C7
            JP   AtomStoreEncoded1

AtomEncodeIncDec:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMInc-4
            LD   B,A                 ; INC base 4, DEC base 5
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,AtomEncodeIncDecRegister
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JR   C,AtomEncodeIncDecPair
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JR   Z,AtomEncodeIncDecIndexPair
            CP   AtomOpIY
            JR   Z,AtomEncodeIncDecIndexPair
            CALL AtomIsHalfIndex
            JR   C,AtomEncodeIncDecHalf
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JR   Z,AtomEncodeIncDecMemHl
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            ADD  A,$30
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   AtomEncoded3
AtomEncodeIncDecRegister:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   AtomStoreEncoded1
AtomEncodeIncDecPair:
            LD   A,B
            CP   4
            LD   B,$03
            JR   Z,AtomEncodeIncDecPairBaseReady
            LD   B,$0B
AtomEncodeIncDecPairBaseReady:
            LD   A,(IX+AtomInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   AtomStoreEncoded1
AtomEncodeIncDecIndexPair:
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,B
            CP   4
            LD   A,$23
            JR   Z,AtomEncodeIncDecIndexPairReady
            LD   A,$2B
AtomEncodeIncDecIndexPairReady:
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeIncDecHalf:
            LD   A,(IX+AtomInstrOp0)
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeIncDecMemHl:
            LD   A,B
            ADD  A,$30
            JP   AtomStoreEncoded1

AtomEncodeStack:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMPush
            LD   B,$C5
            JR   Z,AtomEncodeStackBase
            LD   B,$C1
AtomEncodeStackBase:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JR   Z,AtomEncodeStackIndex
            CP   AtomOpIY
            JR   Z,AtomEncodeStackIndex
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   AtomStoreEncoded1
AtomEncodeStackIndex:
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            ADD  A,$20
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomLdEncodingStart:
AtomEncodeLd:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomEncodeLdReg8
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsHalfIndex
            JP   C,AtomEncodeLdHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,AtomEncodeLdReg16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,AtomEncodeLdIndex16
            CP   AtomOpIY
            JP   Z,AtomEncodeLdIndex16
            CP   AtomOpI
            JP   Z,AtomEncodeLdSpecialTarget
            CP   AtomOpR
            JP   Z,AtomEncodeLdSpecialTarget
            CP   AtomOpMemAbs
            JP   Z,AtomEncodeLdMemAbs
            CP   AtomOpMemBC
            JP   Z,AtomEncodeLdMemPair
            CP   AtomOpMemDE
            JP   Z,AtomEncodeLdMemPair
            CP   AtomOpMemHL
            JP   Z,AtomEncodeLdMemHl
            JP   AtomEncodeLdIndexed

AtomEncodeLdReg8:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JR   C,AtomEncodeLdRegReg
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,AtomEncodeLdRegImm
            CP   AtomOpMemHL
            JR   Z,AtomEncodeLdRegMemHl
            CP   AtomOpMemAbs
            JR   Z,AtomEncodeLdAAbs
            CP   AtomOpMemBC
            JR   Z,AtomEncodeLdAMemPair
            CP   AtomOpMemDE
            JR   Z,AtomEncodeLdAMemPair
            CP   AtomOpI
            JR   Z,AtomEncodeLdASpecial
            CP   AtomOpR
            JR   Z,AtomEncodeLdASpecial
            CALL AtomIsIndexed
            JR   C,AtomEncodeLdRegIndexed
            JP   AtomEncodeLdRegHalf
AtomEncodeLdRegReg:
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            JP   AtomStoreEncoded1
AtomEncodeLdRegImm:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,6
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeLdRegMemHl:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            JP   AtomStoreEncoded1
AtomEncodeLdAAbs:
            LD   A,$3A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   AtomEncoded3
AtomEncodeLdAMemPair:
            SUB  AtomOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$0A
            JP   AtomStoreEncoded1
AtomEncodeLdASpecial:
            LD   B,$57
            CP   AtomOpI
            JR   Z,AtomEncodeLdASpecialReady
            LD   B,$5F
AtomEncodeLdASpecialReady:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeLdRegIndexed:
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            LD   (AtomScratch+1),A
            POP  AF
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+2),A
            JP   AtomEncoded3
AtomEncodeLdRegHalf:
            LD   A,(IX+AtomInstrOp1)
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeLdHalf:
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            AND  7
            ADD  A,B
            ADD  A,$40
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeLdReg16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JR   Z,AtomEncodeLdReg16Imm
            CP   AtomOpMemAbs
            JR   Z,AtomEncodeLdReg16Abs
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpSP
            JR   Z,AtomEncodeLdSp
            CP   AtomOpHL
            LD   A,$62
            JR   Z,AtomEncodeLdLegacy
            LD   A,$42
AtomEncodeLdLegacy:
            LD   (AtomScratch+0),A
            ADD  A,9
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeLdReg16Imm:
            LD   A,(IX+AtomInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            INC  A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   AtomEncoded3
AtomEncodeLdReg16Abs:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JR   Z,AtomEncodeLdHlAbs
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$4B
            LD   B,A
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            CALL AtomCopyValue1ToScratch2
            JP   AtomEncoded4
AtomEncodeLdHlAbs:
            LD   A,$2A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   AtomEncoded3
AtomEncodeLdSp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            LD   A,$F9
            JP   Z,AtomStoreEncoded1
            LD   A,(IX+AtomInstrOp1)
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$F9
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeLdIndex16:
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            LD   A,$21
            JP   Z,AtomEncodeLdIndex16Opcode
            LD   A,$2A
AtomEncodeLdIndex16Opcode:
            LD   (AtomScratch+1),A
            CALL AtomCopyValue1ToScratch2
            JP   AtomEncoded4
AtomEncodeLdSpecialTarget:
            LD   B,$47
            CP   AtomOpI
            JP   Z,AtomEncodeLdSpecialTargetReady
            LD   B,$4F
AtomEncodeLdSpecialTargetReady:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeLdMemAbs:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JR   Z,AtomEncodeLdAbsA
            CALL AtomIsReg16
            JR   NC,AtomEncodeLdAbsIndex
            CP   AtomOpHL
            JR   Z,AtomEncodeLdAbsHl
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$43
            LD   B,A
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            CALL AtomCopyValue0ToScratch2
            JP   AtomEncoded4
AtomEncodeLdAbsA:
            LD   A,$32
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   AtomEncoded3
AtomEncodeLdAbsHl:
            LD   A,$22
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   AtomEncoded3
AtomEncodeLdAbsIndex:
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$22
            LD   (AtomScratch+1),A
            CALL AtomCopyValue0ToScratch2
            JP   AtomEncoded4
AtomEncodeLdMemPair:
            SUB  AtomOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$02
            JP   AtomStoreEncoded1
AtomEncodeLdMemHl:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,AtomEncodeLdMemHlImm
            ADD  A,$70
            JP   AtomStoreEncoded1
AtomEncodeLdMemHlImm:
            LD   A,$36
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeLdIndexed:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,AtomEncodeLdIndexedImm
            ADD  A,$70
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   AtomEncoded3
AtomEncodeLdIndexedImm:
            LD   A,$36
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+3),A
            JP   AtomEncoded4
AtomLdEncodingEnd:

AtomEncodeIn:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,AtomEncodeInBare
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,AtomEncodeInImmediate
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$40
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeInBare:
            LD   A,$70
            JR   AtomEncodeInEd
AtomEncodeInImmediate:
            LD   A,$DB
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeInEd:
            LD   B,A
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeOut:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm8
            JR   Z,AtomEncodeOutImmediate
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            LD   A,$71
            JP   Z,AtomEncodeInEd
            LD   A,(IX+AtomInstrOp1)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$41
            JR   AtomEncodeInEd
AtomEncodeOutImmediate:
            LD   A,$D3
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeBit:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMBit-1
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsIndexed
            JR   C,AtomEncodeBitIndexed
            LD   A,(IX+AtomInstrOp1)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeBitIndexed:
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            LD   A,6
            JR   Z,AtomEncodeBitIndexedCode
            LD   A,(IX+AtomInstrOp2)
            AND  7
AtomEncodeBitIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$CB
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+2),A
            LD   A,B
            LD   (AtomScratch+3),A
            JP   AtomEncoded4

AtomEncodeRotate:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMRlc
            LD   E,A
            LD   D,0
            LD   HL,AtomRotateBases
            ADD  HL,DE
            LD   B,(HL)
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JR   C,AtomEncodeRotateIndexed
            LD   A,(IX+AtomInstrOp0)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeRotateIndexed:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            LD   A,6
            JR   Z,AtomEncodeRotateIndexedCode
            LD   A,(IX+AtomInstrOp1)
            AND  7
AtomEncodeRotateIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$CB
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,B
            LD   (AtomScratch+3),A
            JP   AtomEncoded4

AtomEncodeAlu:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMAdd
            LD   E,A
            LD   D,0
            LD   HL,AtomAluOrder
            ADD  HL,DE
            LD   A,(HL)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomEncodeAlu16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm8
            JR   Z,AtomEncodeAluImmediate
            CALL AtomIsHalfIndex
            JR   C,AtomEncodeAluHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JR   C,AtomEncodeAluIndexed
            LD   A,(IX+AtomInstrOp0)
            AND  7
            ADD  A,B
            ADD  A,$80
            JP   AtomStoreEncoded1
AtomEncodeAluImmediate:
            LD   A,B
            ADD  A,$C6
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeAluHalf:
            LD   A,(IX+AtomInstrOp0)
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            ADD  A,B
            ADD  A,$80
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeAluIndexed:
            PUSH AF
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,B
            ADD  A,$86
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   AtomEncoded3
AtomEncodeAlu16:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   Z,AtomEncodeAdd16
            LD   B,$42
            CP   AtomMSbc
            JR   Z,AtomEncodeAdcSbc16Ready
            LD   B,$4A
AtomEncodeAdcSbc16Ready:
            LD   A,(IX+AtomInstrOp1)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   B,A
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeAdd16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpIX
            JR   Z,AtomEncodeAdd16Self
            CP   AtomOpIY
            JR   Z,AtomEncodeAdd16Self
            AND  3
            JR   AtomEncodeAdd16SourceReady
AtomEncodeAdd16Self:
            LD   A,2
AtomEncodeAdd16SourceReady:
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$09
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            LD   A,B
            JP   Z,AtomStoreEncoded1
            LD   A,(IX+AtomInstrOp0)
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeJp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomEncodeJpConditional
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JR   Z,AtomEncodeJpHl
            CP   AtomOpMemIX
            JR   Z,AtomEncodeJpIndex
            CP   AtomOpMemIY
            JR   Z,AtomEncodeJpIndex
            LD   A,$C3
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   AtomEncoded3
AtomEncodeJpConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C2
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   AtomEncoded3
AtomEncodeJpHl:
            LD   A,$E9
            JP   AtomStoreEncoded1
AtomEncodeJpIndex:
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$E9
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

AtomEncodeCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomEncodeCallConditional
            LD   A,$CD
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   AtomEncoded3
AtomEncodeCallConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C4
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   AtomEncoded3

AtomEncodeJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomEncodeJrConditional
            LD   A,$18
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeJrConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$20
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2
AtomEncodeDjnz:
            LD   A,$10
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   AtomEncoded2

; Shared output helpers.
AtomCopyValue0ToScratch1:
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+2),A
            RET
AtomCopyValue0ToScratch2:
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+3),A
            RET
AtomCopyValue1ToScratch1:
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+2),A
            RET
AtomCopyValue1ToScratch2:
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+3),A
            RET

AtomPrefixFromOperand:
            CP   AtomOpIXH
            JR   C,AtomPrefixOrdinary
            CP   AtomOpIXL+1
            JR   C,AtomPrefixIX
            CP   AtomOpIYH
            JR   C,AtomPrefixOrdinary
            CP   AtomOpIYL+1
            JR   C,AtomPrefixIY
AtomPrefixOrdinary:
            AND  1
            JR   NZ,AtomPrefixIY
AtomPrefixIX:
            LD   A,$DD
            RET
AtomPrefixIY:
            LD   A,$FD
            RET

AtomStoreEncoded1:
            LD   (AtomScratch+0),A
AtomEncoded1:
            LD   A,1
            OR   A
            RET
AtomEncoded2:
            LD   A,2
            OR   A
            RET
AtomEncoded3:
            LD   A,3
            OR   A
            RET
AtomEncoded4:
            LD   A,4
            OR   A
            RET

AtomRuleEncodingCodeEnd:
AtomEncoderCodeEnd:

; ---------------------------------------------------------------------------
; Immutable data
; ---------------------------------------------------------------------------
AtomEncoderImmutableStart:
AtomOpcodeTableStart:

; Two bytes per no-operand mnemonic. A zero second byte marks length one.
AtomCoreOpcodes:
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

AtomImOpcodes:  .db $46,$56,$5E
AtomRotateBases: .db $00,$08,$10,$18,$20,$28,$30,$30,$38
; Ordinal order is ADD ADC SUB SBC AND XOR OR CP; values are hardware op fields.
AtomAluOrder:    .db 0,1,2,3,4,5,6,7

AtomOpcodeTableEnd:

            .include "atom-mnemonics.inc"

AtomEncoderImmutableEnd:
AtomEncoderCoreEnd:

; Writable, non-reentrant workspace. The first four bytes are also the encoder
; commit buffer. Search state overlays the unused tail after packing.
AtomEncoderWorkspaceStart:
AtomScratch:     .ds 6
AtomSearchLow:   .ds 1
AtomSearchHigh:  .ds 1
AtomSearchMid:   .ds 1
AtomEncoderWorkspaceEnd:
