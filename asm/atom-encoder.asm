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
.routine in B,HL,DE out DE,carry maybe-out zero clobbers A,BC,HL,IX,sign,parity,halfCarry,zero
AtomRadix40Pack:
            LD   A,B
            OR   A
            JP   Z,_AtomPackInvalid
            CP   9
            JP   NC,_AtomPackInvalid

            ; Validate before touching even the scratch representation.
            PUSH HL
            PUSH BC
_AtomPackValidateLoop:
            LD   A,(HL)
            CALL AtomRadix40Character
            JP   C,_AtomPackValidateFailed
            INC  HL
            DJNZ _AtomPackValidateLoop
            POP  BC
            POP  HL

            PUSH DE
            LD   IX,AtomScratch
            LD   A,B

            ; First group: three positions.
            CP   3
            JR   C,_AtomPackFirstShort
            LD   B,3
            SUB  3
            JR   _AtomPackFirstReady
_AtomPackFirstShort:
            LD   B,A
            XOR  A
_AtomPackFirstReady:
            PUSH AF
            LD   C,3
            .expectout DE
            CALL AtomPackGroup
            LD   (IX+0),E
            LD   (IX+1),D
            POP  AF

            ; Second group: three positions.
            CP   3
            JR   C,_AtomPackSecondShort
            LD   B,3
            SUB  3
            JR   _AtomPackSecondReady
_AtomPackSecondShort:
            LD   B,A
            XOR  A
_AtomPackSecondReady:
            PUSH AF
            LD   C,3
            .expectout DE
            CALL AtomPackGroup
            LD   (IX+2),E
            LD   (IX+3),D
            POP  AF

            ; Final group: two positions, c6*40+c7.
            LD   B,A
            LD   C,2
            .expectout DE
            CALL AtomPackGroup
            LD   (IX+4),E
            LD   (IX+5),D

            POP  DE
            LD   HL,AtomScratch
            LD   BC,6
            LDIR
            OR   A
            RET

_AtomPackValidateFailed:
            POP  BC
            POP  HL
_AtomPackInvalid:
            XOR  A
            SCF
            RET

; Local helper: in HL=text, B=actual characters, C=field width (2 or 3)
; out DE=packed field, HL advanced by B, carry clear
.routine in BC,HL out DE,HL,carry maybe-out zero clobbers A,sign,parity,halfCarry,BC,zero
AtomPackGroup:
            LD   DE,0
_AtomPackGroupLoop:
            LD   A,B
            OR   A
            JR   Z,_AtomPackGroupPadding
            LD   A,(HL)
            INC  HL
            DEC  B
            CALL AtomRadix40Character
            JR   _AtomPackGroupAppend
_AtomPackGroupPadding:
            XOR  A
_AtomPackGroupAppend:
            CALL AtomMultiplyAdd40
            DEC  C
            JR   NZ,_AtomPackGroupLoop
            OR   A
            RET

; Local helper: in DE=value, A=digit; out DE=value*40+digit.
; Preserves HL,BC.
.routine in DE,A out DE clobbers A,F
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
            JR   NC,_AtomMultiplyAdd40NoCarry
            INC  H
_AtomMultiplyAdd40NoCarry:
            EX   DE,HL
            POP  HL
            RET

; Local helper. ASCII letters are folded to uppercase. Carry marks invalid.
.routine in A out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomRadix40Character:
            CP   "a"
            JR   C,_AtomRadix40Upper
            CP   "z"+1
            JR   NC,_AtomRadix40Upper
            SUB  $20
_AtomRadix40Upper:
            CP   "A"
            JR   C,_AtomRadix40Digit
            CP   "Z"+1
            JR   NC,_AtomRadix40Digit
            SUB  "A"-1
            OR   A
            RET
_AtomRadix40Digit:
            CP   "0"
            JR   C,_AtomRadix40Underscore
            CP   "9"+1
            JR   NC,_AtomRadix40Underscore
            SUB  "0"-27
            OR   A
            RET
_AtomRadix40Underscore:
            CP   "_"
            JR   NZ,_AtomRadix40Bad
            LD   A,37
            OR   A
            RET
_AtomRadix40Bad:
            XOR  A
            SCF
            RET

AtomRadix40CodeEnd:

; ---------------------------------------------------------------------------
; Case-insensitive mnemonic recognizer
; ---------------------------------------------------------------------------
AtomRecognitionCodeStart:

; in HL=text, B=length; out A=ordinal and carry clear, or A=0 and carry set
.routine in B,HL out A,carry clobbers BC,HL,IX,zero,sign,parity,halfCarry,DE
AtomRecognizeMnemonic:
            LD   DE,AtomScratch
            CALL AtomRadix40Pack
            RET  C
            XOR  A
            LD   (AtomSearchLow),A
            LD   A,AtomMnemonicCount
            LD   (AtomSearchHigh),A
_AtomRecognizeLoop:
            LD   A,(AtomSearchLow)
            LD   B,A
            LD   A,(AtomSearchHigh)
            CP   B
            JP   Z,_AtomRecognizeNotFound
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
            JR   C,_AtomRecognizeBefore
            JR   NZ,_AtomRecognizeAfter
            DEC  HL
            LD   A,(AtomScratch+0)
            CP   (HL)
            JR   C,_AtomRecognizeBefore
            JR   NZ,_AtomRecognizeAfter
            INC  HL
            INC  HL
            INC  HL
            LD   A,(AtomScratch+3)
            CP   (HL)
            JR   C,_AtomRecognizeBefore
            JR   NZ,_AtomRecognizeAfter
            DEC  HL
            LD   A,(AtomScratch+2)
            CP   (HL)
            JR   C,_AtomRecognizeBefore
            JR   NZ,_AtomRecognizeAfter
            INC  HL
            INC  HL
            LD   A,(HL)
            OR   A
            RET
_AtomRecognizeBefore:
            LD   A,(AtomSearchMid)
            LD   (AtomSearchHigh),A
            JR   _AtomRecognizeLoop
_AtomRecognizeAfter:
            LD   A,(AtomSearchMid)
            INC  A
            LD   (AtomSearchLow),A
            JR   _AtomRecognizeLoop
_AtomRecognizeNotFound:
            XOR  A
            SCF
            RET

AtomRecognitionCodeEnd:

; ---------------------------------------------------------------------------
; Form validation and length
; ---------------------------------------------------------------------------
AtomValidationCodeStart:

; Values at offsets 4..9 are never read by this routine.
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,B,DE,HL
AtomFormLength:
AtomValidateForm:
            LD   A,(IX+AtomInstrMnemonic)
            OR   A
            JP   Z,AtomInvalid
            CP   AtomMRet
            JP   C,_AtomValidateCore
            JP   Z,_AtomValidateRet
            CP   AtomMEx
            JP   Z,_AtomValidateEx
            CP   AtomMIm
            JP   Z,_AtomValidateIm
            CP   AtomMRst
            JP   Z,_AtomValidateRst
            CP   AtomMInc
            JP   Z,_AtomValidateIncDec
            CP   AtomMDec
            JP   Z,_AtomValidateIncDec
            CP   AtomMPush
            JP   Z,_AtomValidateStack
            CP   AtomMPop
            JP   Z,_AtomValidateStack
            CP   AtomMLd
            JP   Z,_AtomValidateLd
            CP   AtomMIn
            JP   Z,_AtomValidateIn
            CP   AtomMOut
            JP   Z,_AtomValidateOut
            CP   AtomMBit
            JP   C,AtomInvalid
            CP   AtomMSet+1
            JP   C,_AtomValidateBit
            CP   AtomMRlc
            JP   C,AtomInvalid
            CP   AtomMSrl+1
            JP   C,_AtomValidateRotate
            CP   AtomMAdd
            JP   C,AtomInvalid
            CP   AtomMCp+1
            JP   C,_AtomValidateAlu
            CP   AtomMJp
            JP   Z,_AtomValidateJp
            CP   AtomMCall
            JP   Z,_AtomValidateCall
            CP   AtomMJr
            JP   Z,_AtomValidateJr
            CP   AtomMDjnz
            JP   Z,_AtomValidateDjnz
            JP   AtomInvalid

_AtomValidateCore:
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

_AtomValidateRet:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JP   Z,_AtomValidateLength1NoOperands
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            CALL AtomRequireOneOperand
            RET  C
            LD   A,1
            OR   A
            RET

_AtomValidateLength1NoOperands:
            CALL AtomRequireNoOperands
            RET  C
            LD   A,1
            OR   A
            RET

_AtomValidateEx:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpAF
            JR   Z,_AtomValidateExAf
            CP   AtomOpDE
            JR   Z,_AtomValidateExDe
            CP   AtomOpMemSP
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpIX
            JP   Z,_AtomValidateLength2
            CP   AtomOpIY
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateExAf:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpAFPrime
            JP   Z,_AtomValidateLength1
            JP   AtomInvalid
_AtomValidateExDe:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,_AtomValidateLength1
            JP   AtomInvalid

_AtomValidateIm:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIm0
            JP   C,AtomInvalid
            CP   AtomOpIm2+1
            JP   NC,AtomInvalid
            JP   _AtomValidateLength2

_AtomValidateRst:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRst0
            JP   C,AtomInvalid
            CP   AtomOpRst56+1
            JP   NC,AtomInvalid
            JP   _AtomValidateLength1

_AtomValidateIncDec:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,_AtomValidateLength1
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,_AtomValidateLength1
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,_AtomValidateLength2
            CP   AtomOpIY
            JP   Z,_AtomValidateLength2
            CALL AtomIsHalfIndex
            JP   C,_AtomValidateLength2
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JP   Z,_AtomValidateLength1
            CALL AtomIsIndexed
            JP   C,_AtomValidateLength3
            JP   AtomInvalid

_AtomValidateStack:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpBC
            JP   Z,_AtomValidateLength1
            CP   AtomOpDE
            JP   Z,_AtomValidateLength1
            CP   AtomOpHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpAF
            JP   Z,_AtomValidateLength1
            CP   AtomOpIX
            JP   Z,_AtomValidateLength2
            CP   AtomOpIY
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid

AtomLdValidationStart .equ $
_AtomValidateLd:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,_AtomValidateLdReg8
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsHalfIndex
            JP   C,_AtomValidateLdHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,_AtomValidateLdReg16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,_AtomValidateLdIndex16
            CP   AtomOpIY
            JP   Z,_AtomValidateLdIndex16
            CP   AtomOpI
            JP   Z,_AtomValidateLdSpecial
            CP   AtomOpR
            JP   Z,_AtomValidateLdSpecial
            CP   AtomOpMemAbs
            JP   Z,_AtomValidateLdMemAbs
            CP   AtomOpMemBC
            JP   Z,_AtomValidateLdMemPair
            CP   AtomOpMemDE
            JP   Z,_AtomValidateLdMemPair
            CP   AtomOpMemHL
            JP   Z,_AtomValidateLdMemHL
            CALL AtomIsIndexed
            JP   C,_AtomValidateLdIndexed
            JP   AtomInvalid

_AtomValidateLdReg8:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,_AtomValidateLength1
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JP   Z,_AtomValidateLength2
            CP   AtomOpMemHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpMemAbs
            JR   Z,_AtomValidateLdReg8Absolute
            CP   AtomOpMemBC
            JR   Z,_AtomValidateLdReg8Accumulator
            CP   AtomOpMemDE
            JR   Z,_AtomValidateLdReg8Accumulator
            CP   AtomOpI
            JR   Z,_AtomValidateLdReg8Accumulator2
            CP   AtomOpR
            JR   Z,_AtomValidateLdReg8Accumulator2
            CALL AtomIsIndexed
            JP   C,_AtomValidateLength3
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpH
            JP   Z,AtomInvalid
            CP   AtomOpL
            JP   Z,AtomInvalid
            JP   _AtomValidateLength2
_AtomValidateLdReg8Absolute:
_AtomValidateLdReg8Accumulator:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpMemAbs
            JP   Z,_AtomValidateLength3
            JP   _AtomValidateLength1
_AtomValidateLdReg8Accumulator2:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   _AtomValidateLength2

_AtomValidateLdHalf:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JR   C,_AtomValidateLdHalfFamily
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   NC,AtomInvalid
            CP   AtomOpH
            JP   Z,AtomInvalid
            CP   AtomOpL
            JP   Z,AtomInvalid
            JP   _AtomValidateLength2
_AtomValidateLdHalfFamily:
            LD   A,(IX+AtomInstrOp0)
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            XOR  B
            AND  $08
            JP   NZ,AtomInvalid
            JP   _AtomValidateLength2

_AtomValidateLdReg16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength3
            CP   AtomOpMemAbs
            JR   Z,_AtomValidateLdReg16Absolute
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpSP
            JR   Z,_AtomValidateLdSp
            CP   AtomOpHL
            JR   Z,_AtomValidateLdLegacyHl
            CP   AtomOpBC
            JR   Z,_AtomValidateLdLegacyBc
            JP   AtomInvalid
_AtomValidateLdReg16Absolute:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JP   Z,_AtomValidateLength3
            JP   _AtomValidateLength4
_AtomValidateLdSp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpIX
            JP   Z,_AtomValidateLength2
            CP   AtomOpIY
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateLdLegacyHl:
_AtomValidateLdLegacyBc:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpDE
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid

_AtomValidateLdIndex16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength4
            CP   AtomOpMemAbs
            JP   Z,_AtomValidateLength4
            JP   AtomInvalid
_AtomValidateLdSpecial:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateLdMemAbs:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,_AtomValidateLength3
            CALL AtomIsReg16
            JR   NC,_AtomValidateLdMemAbsIndex
            CP   AtomOpHL
            JP   Z,_AtomValidateLength3
            JP   _AtomValidateLength4
_AtomValidateLdMemAbsIndex:
            CP   AtomOpIX
            JP   Z,_AtomValidateLength4
            CP   AtomOpIY
            JP   Z,_AtomValidateLength4
            JP   AtomInvalid
_AtomValidateLdMemPair:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,_AtomValidateLength1
            JP   AtomInvalid
_AtomValidateLdMemHL:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,_AtomValidateLength1
            CP   AtomOpImm8
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateLdIndexed:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,_AtomValidateLength3
            CP   AtomOpImm8
            JP   Z,_AtomValidateLength4
            JP   AtomInvalid
AtomLdValidationEnd .equ $

_AtomValidateIn:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,_AtomValidateInOne
            CALL AtomIsReg8
            JP   NC,AtomInvalid
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpPortC
            JP   Z,_AtomValidateLength2
            CP   AtomOpImm8
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   _AtomValidateLength2
_AtomValidateInOne:
            CALL AtomRequireOneOperand
            RET  C
            JP   _AtomValidateLength2

_AtomValidateOut:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,_AtomValidateOutC
            CP   AtomOpImm8
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            JP   _AtomValidateLength2
_AtomValidateOutC:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            JP   Z,_AtomValidateLength2
            CALL AtomIsReg8
            JP   C,_AtomValidateLength2
            JP   AtomInvalid

_AtomValidateBit:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsBitIndex
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JR   C,_AtomValidateBitPlain
            CP   AtomOpMemHL
            JR   Z,_AtomValidateBitPlain
            CALL AtomIsIndexed
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMBit
            JR   Z,_AtomValidateBitIndexedNoDestination
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            JP   Z,_AtomValidateLength4
            CALL AtomIsReg8
            JP   C,_AtomValidateLength4
            JP   AtomInvalid
_AtomValidateBitIndexedNoDestination:
            CALL AtomRequireTwoOperands
            RET  C
            JP   _AtomValidateLength4
_AtomValidateBitPlain:
            CALL AtomRequireTwoOperands
            RET  C
            JP   _AtomValidateLength2

_AtomValidateRotate:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,_AtomValidateRotatePlain
            CP   AtomOpMemHL
            JR   Z,_AtomValidateRotatePlain
            CALL AtomIsIndexed
            JP   NC,AtomInvalid
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JP   Z,_AtomValidateLength4
            CALL AtomIsReg8
            JP   C,_AtomValidateLength4
            JP   AtomInvalid
_AtomValidateRotatePlain:
            CALL AtomRequireOneOperand
            RET  C
            JP   _AtomValidateLength2

_AtomValidateAlu:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateAlu16
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,_AtomValidateLength1
            CP   AtomOpMemHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpImm8
            JP   Z,_AtomValidateLength2
            CALL AtomIsHalfIndex
            JP   C,_AtomValidateLength2
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JP   C,_AtomValidateLength3
            JP   AtomInvalid
_AtomValidateAlu16:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   Z,_AtomValidateAdd16
            CP   AtomMAdc
            JR   Z,_AtomValidateAdcSbc16
            CP   AtomMSbc
            JP   NZ,AtomInvalid
_AtomValidateAdcSbc16:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg16
            JP   C,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateAdd16:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JR   Z,_AtomValidateAddHl
            CP   AtomOpIX
            JR   Z,_AtomValidateAddIndex
            CP   AtomOpIY
            JP   NZ,AtomInvalid
_AtomValidateAddIndex:
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpBC
            JP   Z,_AtomValidateLength2
            CP   AtomOpDE
            JP   Z,_AtomValidateLength2
            CP   AtomOpSP
            JP   Z,_AtomValidateLength2
            CP   B
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateAddHl:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg16
            JP   C,_AtomValidateLength1
            JP   AtomInvalid

_AtomValidateJp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateJpConditional
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength3
            CP   AtomOpMemHL
            JP   Z,_AtomValidateLength1
            CP   AtomOpMemIX
            JP   Z,_AtomValidateLength2
            CP   AtomOpMemIY
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateJpConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength3
            JP   AtomInvalid

_AtomValidateCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateCallConditional
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength3
            JP   AtomInvalid
_AtomValidateCallConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,_AtomValidateLength3
            JP   AtomInvalid

_AtomValidateJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateJrConditional
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRel8
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid
_AtomValidateJrConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsRelativeCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpRel8
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid

_AtomValidateDjnz:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRel8
            JP   Z,_AtomValidateLength2
            JP   AtomInvalid

_AtomValidateLength1:
            LD   A,1
            OR   A
            RET
_AtomValidateLength2:
            LD   A,2
            OR   A
            RET
_AtomValidateLength3:
            LD   A,3
            OR   A
            RET
_AtomValidateLength4:
            LD   A,4
            OR   A
            RET
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomInvalid:
            XOR  A
            SCF
            RET

; Shape helpers reject hidden operands after the declared arity.
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry
AtomRequireNoOperands:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
            JP   AtomRequireOneOperand
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry
AtomRequireOneOperand:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
            JP   AtomRequireTwoOperands
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry
AtomRequireTwoOperands:
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
            OR   A
            RET
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomRequireBad:
            XOR  A
            SCF
            RET

.routine in A out carry clobbers sign,parity,halfCarry,zero
AtomIsReg8:
            CP   AtomOpMemHL
            JR   C,AtomPredicateYes
            CP   AtomOpA
            JR   Z,AtomPredicateYes
            CP   A
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsReg16:
            CP   AtomOpBC
            JR   C,AtomPredicateNo
            CP   AtomOpSP+1
            JR   C,AtomPredicateYes
            CP   A
            RET
.routine in A out carry,zero,sign,parity,halfCarry
AtomIsHalfIndex:
            CP   AtomOpIXH
            JR   Z,AtomPredicateYes
            CP   AtomOpIXL
            JR   Z,AtomPredicateYes
            CP   AtomOpIYH
            JR   Z,AtomPredicateYes
            CP   AtomOpIYL
            JR   Z,AtomPredicateYes
            CP   A
            RET
.routine in A out carry,zero,sign,parity,halfCarry
AtomIsIndexed:
            CP   AtomOpIndexIX
            JR   Z,AtomPredicateYes
            CP   AtomOpIndexIY
            JR   Z,AtomPredicateYes
            CP   A
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpM+1
            JR   C,AtomPredicateYes
            CP   A
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsRelativeCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpCC+1
            JR   C,AtomPredicateYes
            CP   A
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsBitIndex:
            CP   AtomOpBit0
            JR   C,AtomPredicateNo
            CP   AtomOpBit7+1
            JR   C,AtomPredicateYes
.routine in A out carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomPredicateNo:
            CP   A
            RET
.routine out carry clobbers halfCarry
AtomPredicateYes:
            SCF
            RET

AtomValidationCodeEnd:

; ---------------------------------------------------------------------------
; Rule-driven encoding. AtomEncodeCore is entered only after validation.
; ---------------------------------------------------------------------------
AtomRuleEncodingCodeStart:

; in IX=record, DE=output; out A=length, carry clear, DE advanced on success
.routine in IX,DE out A,DE,carry clobbers BC,HL,zero,sign,parity,halfCarry
AtomEncode:
            PUSH DE
            CALL AtomValidateForm
            POP  DE
            RET  C
            PUSH DE
            .expectout A
            CALL AtomEncodeCore
            POP  DE
            LD   C,A
            LD   B,0
            LD   HL,AtomScratch
            LDIR
            OR   A
            RET

.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,B,DE,HL
AtomEncodeCore:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMRet
            JP   C,_AtomEncodeCoreOpcode
            JP   Z,_AtomEncodeRet
            CP   AtomMEx
            JP   Z,_AtomEncodeEx
            CP   AtomMIm
            JP   Z,_AtomEncodeIm
            CP   AtomMRst
            JP   Z,_AtomEncodeRst
            CP   AtomMInc
            JP   Z,_AtomEncodeIncDec
            CP   AtomMDec
            JP   Z,_AtomEncodeIncDec
            CP   AtomMPush
            JP   Z,_AtomEncodeStack
            CP   AtomMPop
            JP   Z,_AtomEncodeStack
            CP   AtomMLd
            JP   Z,_AtomEncodeLd
            CP   AtomMIn
            JP   Z,_AtomEncodeIn
            CP   AtomMOut
            JP   Z,_AtomEncodeOut
            CP   AtomMBit
            JP   C,AtomInvalid
            CP   AtomMSet+1
            JP   C,_AtomEncodeBit
            CP   AtomMRlc
            JP   C,AtomInvalid
            CP   AtomMSrl+1
            JP   C,_AtomEncodeRotate
            CP   AtomMAdd
            JP   C,AtomInvalid
            CP   AtomMCp+1
            JP   C,_AtomEncodeAlu
            CP   AtomMJp
            JP   Z,_AtomEncodeJp
            CP   AtomMCall
            JP   Z,_AtomEncodeCall
            CP   AtomMJr
            JP   Z,_AtomEncodeJr
            JP   _AtomEncodeDjnz

_AtomEncodeCoreOpcode:
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
            JP   Z,_AtomEncoded1
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeRet:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JR   Z,_AtomEncodeRetPlain
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C0
            JP   _AtomStoreEncoded1
_AtomEncodeRetPlain:
            LD   A,$C9
            JP   _AtomStoreEncoded1

_AtomEncodeEx:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpAF
            JR   Z,_AtomEncodeExAf
            CP   AtomOpDE
            JR   Z,_AtomEncodeExDe
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JR   Z,_AtomEncodeExSpHl
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$E3
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeExAf:
            LD   A,$08
            JP   _AtomStoreEncoded1
_AtomEncodeExDe:
            LD   A,$EB
            JP   _AtomStoreEncoded1
_AtomEncodeExSpHl:
            LD   A,$E3
            JP   _AtomStoreEncoded1

_AtomEncodeIm:
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
            JP   _AtomEncoded2

_AtomEncodeRst:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpRst0
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C7
            JP   _AtomStoreEncoded1

_AtomEncodeIncDec:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMInc-4
            LD   B,A                 ; INC base 4, DEC base 5
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,_AtomEncodeIncDecRegister
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JR   C,_AtomEncodeIncDecPair
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JR   Z,_AtomEncodeIncDecIndexPair
            CP   AtomOpIY
            JR   Z,_AtomEncodeIncDecIndexPair
            CALL AtomIsHalfIndex
            JR   C,_AtomEncodeIncDecHalf
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JR   Z,_AtomEncodeIncDecMemHl
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            ADD  A,$30
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   _AtomEncoded3
_AtomEncodeIncDecRegister:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   _AtomStoreEncoded1
_AtomEncodeIncDecPair:
            LD   A,B
            CP   4
            LD   B,$03
            JR   Z,_AtomEncodeIncDecPairBaseReady
            LD   B,$0B
_AtomEncodeIncDecPairBaseReady:
            LD   A,(IX+AtomInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   _AtomStoreEncoded1
_AtomEncodeIncDecIndexPair:
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,B
            CP   4
            LD   A,$23
            JR   Z,_AtomEncodeIncDecIndexPairReady
            LD   A,$2B
_AtomEncodeIncDecIndexPairReady:
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeIncDecHalf:
            LD   A,(IX+AtomInstrOp0)
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeIncDecMemHl:
            LD   A,B
            ADD  A,$30
            JP   _AtomStoreEncoded1

_AtomEncodeStack:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMPush
            LD   B,$C5
            JR   Z,_AtomEncodeStackBase
            LD   B,$C1
_AtomEncodeStackBase:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JR   Z,_AtomEncodeStackIndex
            CP   AtomOpIY
            JR   Z,_AtomEncodeStackIndex
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   _AtomStoreEncoded1
_AtomEncodeStackIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            ADD  A,$20
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

AtomLdEncodingStart .equ $
_AtomEncodeLd:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,_AtomEncodeLdReg8
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsHalfIndex
            JP   C,_AtomEncodeLdHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,_AtomEncodeLdReg16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,_AtomEncodeLdIndex16
            CP   AtomOpIY
            JP   Z,_AtomEncodeLdIndex16
            CP   AtomOpI
            JP   Z,_AtomEncodeLdSpecialTarget
            CP   AtomOpR
            JP   Z,_AtomEncodeLdSpecialTarget
            CP   AtomOpMemAbs
            JP   Z,_AtomEncodeLdMemAbs
            CP   AtomOpMemBC
            JP   Z,_AtomEncodeLdMemPair
            CP   AtomOpMemDE
            JP   Z,_AtomEncodeLdMemPair
            CP   AtomOpMemHL
            JP   Z,_AtomEncodeLdMemHl
            JP   _AtomEncodeLdIndexed

_AtomEncodeLdReg8:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JR   C,_AtomEncodeLdRegReg
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeLdRegImm
            CP   AtomOpMemHL
            JR   Z,_AtomEncodeLdRegMemHl
            CP   AtomOpMemAbs
            JR   Z,_AtomEncodeLdAAbs
            CP   AtomOpMemBC
            JR   Z,_AtomEncodeLdAMemPair
            CP   AtomOpMemDE
            JR   Z,_AtomEncodeLdAMemPair
            CP   AtomOpI
            JR   Z,_AtomEncodeLdASpecial
            CP   AtomOpR
            JR   Z,_AtomEncodeLdASpecial
            CALL AtomIsIndexed
            JR   C,_AtomEncodeLdRegIndexed
            JP   _AtomEncodeLdRegHalf
_AtomEncodeLdRegReg:
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            JP   _AtomStoreEncoded1
_AtomEncodeLdRegImm:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,6
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeLdRegMemHl:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            JP   _AtomStoreEncoded1
_AtomEncodeLdAAbs:
            LD   A,$3A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   _AtomEncoded3
_AtomEncodeLdAMemPair:
            SUB  AtomOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$0A
            JP   _AtomStoreEncoded1
_AtomEncodeLdASpecial:
            LD   B,$57
            CP   AtomOpI
            JR   Z,_AtomEncodeLdASpecialReady
            LD   B,$5F
_AtomEncodeLdASpecialReady:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeLdRegIndexed:
            PUSH AF
            .expectout A
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
            JP   _AtomEncoded3
_AtomEncodeLdRegHalf:
            LD   A,(IX+AtomInstrOp1)
            PUSH AF
            .expectout A
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
            JP   _AtomEncoded2

_AtomEncodeLdHalf:
            PUSH AF
            .expectout A
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
            JP   _AtomEncoded2

_AtomEncodeLdReg16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JR   Z,_AtomEncodeLdReg16Imm
            CP   AtomOpMemAbs
            JR   Z,_AtomEncodeLdReg16Abs
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpSP
            JR   Z,_AtomEncodeLdSp
            CP   AtomOpHL
            LD   A,$62
            JR   Z,_AtomEncodeLdLegacy
            LD   A,$42
_AtomEncodeLdLegacy:
            LD   (AtomScratch+0),A
            ADD  A,9
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeLdReg16Imm:
            LD   A,(IX+AtomInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            INC  A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   _AtomEncoded3
_AtomEncodeLdReg16Abs:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            JR   Z,_AtomEncodeLdHlAbs
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
            JP   _AtomEncoded4
_AtomEncodeLdHlAbs:
            LD   A,$2A
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   _AtomEncoded3
_AtomEncodeLdSp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            LD   A,$F9
            JP   Z,_AtomStoreEncoded1
            LD   A,(IX+AtomInstrOp1)
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$F9
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeLdIndex16:
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            LD   A,$21
            JP   Z,_AtomEncodeLdIndex16Opcode
            LD   A,$2A
_AtomEncodeLdIndex16Opcode:
            LD   (AtomScratch+1),A
            CALL AtomCopyValue1ToScratch2
            JP   _AtomEncoded4
_AtomEncodeLdSpecialTarget:
            LD   B,$47
            CP   AtomOpI
            JP   Z,_AtomEncodeLdSpecialTargetReady
            LD   B,$4F
_AtomEncodeLdSpecialTargetReady:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeLdMemAbs:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JR   Z,_AtomEncodeLdAbsA
            CALL AtomIsReg16
            JR   NC,_AtomEncodeLdAbsIndex
            CP   AtomOpHL
            JR   Z,_AtomEncodeLdAbsHl
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
            JP   _AtomEncoded4
_AtomEncodeLdAbsA:
            LD   A,$32
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   _AtomEncoded3
_AtomEncodeLdAbsHl:
            LD   A,$22
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   _AtomEncoded3
_AtomEncodeLdAbsIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$22
            LD   (AtomScratch+1),A
            CALL AtomCopyValue0ToScratch2
            JP   _AtomEncoded4
_AtomEncodeLdMemPair:
            SUB  AtomOpMemBC
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$02
            JP   _AtomStoreEncoded1
_AtomEncodeLdMemHl:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeLdMemHlImm
            ADD  A,$70
            JP   _AtomStoreEncoded1
_AtomEncodeLdMemHlImm:
            LD   A,$36
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeLdIndexed:
            LD   A,(IX+AtomInstrOp0)
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeLdIndexedImm
            ADD  A,$70
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   _AtomEncoded3
_AtomEncodeLdIndexedImm:
            LD   A,$36
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+3),A
            JP   _AtomEncoded4
AtomLdEncodingEnd .equ $

_AtomEncodeIn:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,_AtomEncodeInBare
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeInImmediate
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$40
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeInBare:
            LD   A,$70
            JR   _AtomEncodeInEd
_AtomEncodeInImmediate:
            LD   A,$DB
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeInEd:
            LD   B,A
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeOut:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeOutImmediate
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            LD   A,$71
            JP   Z,_AtomEncodeInEd
            LD   A,(IX+AtomInstrOp1)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$41
            JR   _AtomEncodeInEd
_AtomEncodeOutImmediate:
            LD   A,$D3
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeBit:
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
            JR   C,_AtomEncodeBitIndexed
            LD   A,(IX+AtomInstrOp1)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeBitIndexed:
            LD   A,(IX+AtomInstrOp2)
            CP   AtomOpNone
            LD   A,6
            JR   Z,_AtomEncodeBitIndexedCode
            LD   A,(IX+AtomInstrOp2)
            AND  7
_AtomEncodeBitIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$CB
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+2),A
            LD   A,B
            LD   (AtomScratch+3),A
            JP   _AtomEncoded4

_AtomEncodeRotate:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMRlc
            LD   E,A
            LD   D,0
            LD   HL,AtomRotateBases
            ADD  HL,DE
            LD   B,(HL)
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JR   C,_AtomEncodeRotateIndexed
            LD   A,(IX+AtomInstrOp0)
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeRotateIndexed:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            LD   A,6
            JR   Z,_AtomEncodeRotateIndexedCode
            LD   A,(IX+AtomInstrOp1)
            AND  7
_AtomEncodeRotateIndexedCode:
            ADD  A,B
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$CB
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,B
            LD   (AtomScratch+3),A
            JP   _AtomEncoded4

_AtomEncodeAlu:
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
            JR   NZ,_AtomEncodeAlu16
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeAluImmediate
            CALL AtomIsHalfIndex
            JR   C,_AtomEncodeAluHalf
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JR   C,_AtomEncodeAluIndexed
            LD   A,(IX+AtomInstrOp0)
            AND  7
            ADD  A,B
            ADD  A,$80
            JP   _AtomStoreEncoded1
_AtomEncodeAluImmediate:
            LD   A,B
            ADD  A,$C6
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeAluHalf:
            LD   A,(IX+AtomInstrOp0)
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            AND  7
            ADD  A,B
            ADD  A,$80
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeAluIndexed:
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
            LD   A,B
            ADD  A,$86
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            JP   _AtomEncoded3
_AtomEncodeAlu16:
            LD   A,(IX+AtomInstrMnemonic)
            CP   AtomMAdd
            JR   Z,_AtomEncodeAdd16
            LD   B,$42
            CP   AtomMSbc
            JR   Z,_AtomEncodeAdcSbc16Ready
            LD   B,$4A
_AtomEncodeAdcSbc16Ready:
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
            JP   _AtomEncoded2
_AtomEncodeAdd16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpIX
            JR   Z,_AtomEncodeAdd16Self
            CP   AtomOpIY
            JR   Z,_AtomEncodeAdd16Self
            AND  3
            JR   _AtomEncodeAdd16SourceReady
_AtomEncodeAdd16Self:
            LD   A,2
_AtomEncodeAdd16SourceReady:
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$09
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpHL
            LD   A,B
            JP   Z,_AtomStoreEncoded1
            LD   A,(IX+AtomInstrOp0)
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeJp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomEncodeJpConditional
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JR   Z,_AtomEncodeJpHl
            CP   AtomOpMemIX
            JR   Z,_AtomEncodeJpIndex
            CP   AtomOpMemIY
            JR   Z,_AtomEncodeJpIndex
            LD   A,$C3
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   _AtomEncoded3
_AtomEncodeJpConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C2
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   _AtomEncoded3
_AtomEncodeJpHl:
            LD   A,$E9
            JP   _AtomStoreEncoded1
_AtomEncodeJpIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$E9
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomEncodeCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomEncodeCallConditional
            LD   A,$CD
            LD   (AtomScratch+0),A
            CALL AtomCopyValue0ToScratch1
            JP   _AtomEncoded3
_AtomEncodeCallConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$C4
            LD   (AtomScratch+0),A
            CALL AtomCopyValue1ToScratch1
            JP   _AtomEncoded3

_AtomEncodeJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomEncodeJrConditional
            LD   A,$18
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeJrConditional:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$20
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2
_AtomEncodeDjnz:
            LD   A,$10
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            JP   _AtomEncoded2

_AtomStoreEncoded1:
            LD   (AtomScratch+0),A
_AtomEncoded1:
            LD   A,1
            OR   A
            RET
_AtomEncoded2:
            LD   A,2
            OR   A
            RET
_AtomEncoded3:
            LD   A,3
            OR   A
            RET
_AtomEncoded4:
            LD   A,4
            OR   A
            RET

; Shared output helpers.
.routine in IX clobbers A
AtomCopyValue0ToScratch1:
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+2),A
            RET
.routine in IX clobbers A
AtomCopyValue0ToScratch2:
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+3),A
            RET
.routine in IX clobbers A
AtomCopyValue1ToScratch1:
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+2),A
            RET
.routine in IX clobbers A
AtomCopyValue1ToScratch2:
            LD   A,(IX+AtomInstrValue1)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+3),A
            RET

.routine in A out A clobbers F
AtomPrefixFromOperand:
            CP   AtomOpIXH
            JR   C,_AtomPrefixOrdinary
            CP   AtomOpIXL+1
            JR   C,_AtomPrefixIX
            CP   AtomOpIYH
            JR   C,_AtomPrefixOrdinary
            CP   AtomOpIYL+1
            JR   C,_AtomPrefixIY
_AtomPrefixOrdinary:
            AND  1
            JR   NZ,_AtomPrefixIY
_AtomPrefixIX:
            LD   A,$DD
            RET
_AtomPrefixIY:
            LD   A,$FD
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
