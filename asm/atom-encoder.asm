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
            JR   Z,_AtomPackInvalid
            CP   9
            JR   NC,_AtomPackInvalid

            ; Validate before touching even the scratch representation.
            PUSH HL
            PUSH BC
_AtomPackValidateLoop:
            LD   A,(HL)
            CALL AtomRadix40Character
            JR   C,_AtomPackValidateFailed
            INC  HL
            DJNZ _AtomPackValidateLoop
            POP  BC
            POP  HL

            PUSH DE
            LD   IX,AtomScratch
            LD   A,B

            ; Two three-character groups share the same selector and store.
            CALL AtomPackThree
            CALL AtomPackThree

            ; Final group: two positions, c6*40+c7.
            LD   B,A
            LD   C,2
            .expectout DE
            CALL AtomPackGroup
            LD   (IX+0),E
            LD   (IX+1),D

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

; Pack up to three remaining characters and advance the scratch destination.
.routine in A,HL,IX out A,HL,IX clobbers BC,DE,zero,sign,parity,halfCarry,carry
AtomPackThree:
            CP   3
            JR   C,_AtomPackThreeShort
            LD   B,3
            SUB  3
            JR   _AtomPackThreeReady
_AtomPackThreeShort:
            LD   B,A
            XOR  A
_AtomPackThreeReady:
            PUSH AF
            LD   C,3
            .expectout DE
            CALL AtomPackGroup
            LD   (IX+0),E
            LD   (IX+1),D
            INC  IX
            INC  IX
            POP  AF
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
            LD   A,B
            CP   5
            JR   NC,_AtomRecognizeNotFound
            LD   DE,AtomScratch
            CALL AtomRadix40Pack
            RET  C
            LD   IX,AtomMnemonicTable
            LD   B,AtomMnemonicCount
            LD   C,1
_AtomRecognizeLoop:
            LD   A,(AtomScratch+0)
            CP   (IX+0)
            JR   NZ,_AtomRecognizeNext
            LD   A,(AtomScratch+1)
            CP   (IX+1)
            JR   NZ,_AtomRecognizeNext
            LD   A,(AtomScratch+3)
            CP   (IX+2)
            JR   NZ,_AtomRecognizeNext
            LD   A,C
            OR   A
            RET
_AtomRecognizeNext:
            INC  IX
            INC  IX
            INC  IX
            INC  C
            DJNZ _AtomRecognizeLoop
_AtomRecognizeNotFound:
            XOR  A
            SCF
            RET

AtomRecognitionCodeEnd:

; ---------------------------------------------------------------------------
; Form validation and length
; ---------------------------------------------------------------------------
AtomValidationCodeStart:

; Map a mnemonic to one of the shared validation/encoding families, then jump
; through the caller's seventeen-word handler table.
.routine in A,DE clobbers B,DE,HL,zero,sign,parity,halfCarry,carry
AtomDispatchMnemonic:
            LD   B,A
            CP   AtomMRet
            JR   NC,_AtomDispatchMapped
            XOR  A
            JR   _AtomDispatchReady
_AtomDispatchMapped:
            SUB  AtomMRet
            LD   L,A
            LD   H,0
            PUSH DE
            LD   DE,AtomMnemonicCategoryTable
            ADD  HL,DE
            LD   A,(HL)
            POP  DE
_AtomDispatchReady:
            ADD  A,A
            LD   L,A
            LD   H,0
            ADD  HL,DE
            LD   E,(HL)
            INC  HL
            LD   D,(HL)
            EX   DE,HL
            LD   A,B
            JP   (HL)

AtomMnemonicCategoryTable:
            .db 1,2,3,4,5,5,6,6,7,8,9
            .db 10,10,10
            .db 11,11,11,11,11,11,11,11,11
            .db 12,12,12,12,12,12,12,12
            .db 13,14,15,16

; Values at offsets 4..9 are never read by this routine.
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,B,DE,HL
AtomFormLength:
AtomValidateForm:
            LD   A,(IX+AtomInstrMnemonic)
            OR   A
            JP   Z,AtomInvalid
            CP   AtomMLast+1
            JP   NC,AtomInvalid
            LD   DE,_AtomValidationDispatchTable
            JR   AtomDispatchMnemonic

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
            JR   Z,_AtomValidateLength1NoOperands
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            CALL AtomRequireOneOperand
            RET  C
            XOR  A
            INC  A
            RET

_AtomValidateLength1NoOperands:
            CALL AtomRequireNoOperands
            RET  C
            XOR  A
            INC  A
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
            JP   _AtomValidateLdSp
_AtomValidateExAf:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpAFPrime
_AtomValidateZLength1:
            JP   Z,AtomEncoded1
            JP   AtomInvalid
_AtomValidateExDe:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   _AtomValidateZLength1

_AtomValidateIm:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIm0
            JP   C,AtomInvalid
            CP   AtomOpIm2+1
            JP   NC,AtomInvalid
            JP   AtomEncoded2

_AtomValidateRst:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRst0
            JP   C,AtomInvalid
            CP   AtomOpRst56+1
            JP   NC,AtomInvalid
            JP   AtomEncoded1

_AtomValidateIncDec:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomEncoded1
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg16
            JP   C,AtomEncoded1
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpIX
            JP   Z,AtomEncoded2
            CP   AtomOpIY
            JP   Z,AtomEncoded2
            CALL AtomIsHalfIndex
            JP   C,AtomEncoded2
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpMemHL
            JP   Z,AtomEncoded1
            CALL AtomIsIndexed
_AtomValidateCLength3:
            JP   C,AtomEncoded3
            JP   AtomInvalid

_AtomValidateStack:
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpBC
            JP   Z,AtomEncoded1
            CP   AtomOpDE
            JP   Z,AtomEncoded1
            CP   AtomOpHL
            JP   Z,AtomEncoded1
            CP   AtomOpAF
            JP   Z,AtomEncoded1
_AtomValidateIndexLength2:
            CP   AtomOpIX
            JP   Z,AtomEncoded2
            CP   AtomOpIY
_AtomValidateZLength2:
            JP   Z,AtomEncoded2
            JP   AtomInvalid

AtomLdValidationStart .equ $
_AtomValidateLd:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,_AtomValidateLdReg8
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
            JP   C,AtomEncoded1
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JP   Z,AtomEncoded2
            CP   AtomOpMemHL
            JP   Z,AtomEncoded1
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
            JP   C,AtomEncoded3
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
_AtomValidateLdNoRealHalf:
            CP   AtomOpH
            JP   Z,AtomInvalid
            CP   AtomOpL
            JP   Z,AtomInvalid
            JP   AtomEncoded2
_AtomValidateLdReg8Absolute:
_AtomValidateLdReg8Accumulator:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpMemAbs
            JP   Z,AtomEncoded3
            JP   AtomEncoded1
_AtomValidateLdReg8Accumulator2:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
_AtomValidateNzLength2:
            JP   NZ,AtomInvalid
            JP   AtomEncoded2

_AtomValidateLdHalf:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsHalfIndex
            JR   C,_AtomValidateLdHalfFamily
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   NC,AtomInvalid
            JR   _AtomValidateLdNoRealHalf
_AtomValidateLdHalfFamily:
            LD   A,(IX+AtomInstrOp0)
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            XOR  B
            AND  $08
            JP   _AtomValidateNzLength2

_AtomValidateLdReg16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomEncoded3
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
            JP   Z,AtomEncoded3
            JP   AtomEncoded4
_AtomValidateLdSp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpHL
            JP   Z,AtomEncoded1
            JP   _AtomValidateIndexLength2
_AtomValidateLdLegacyHl:
_AtomValidateLdLegacyBc:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpDE
            JP   _AtomValidateZLength2

_AtomValidateLdIndex16:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomEncoded4
            CP   AtomOpMemAbs
_AtomValidateZLength4:
            JP   Z,AtomEncoded4
            JP   AtomInvalid
_AtomValidateLdSpecial:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   _AtomValidateZLength2
_AtomValidateLdMemAbs:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   Z,AtomEncoded3
            CALL AtomIsReg16
            JR   NC,_AtomValidateLdMemAbsIndex
            CP   AtomOpHL
            JP   Z,AtomEncoded3
            JP   AtomEncoded4
_AtomValidateLdMemAbsIndex:
            CP   AtomOpIX
            JP   Z,AtomEncoded4
            CP   AtomOpIY
            JP   _AtomValidateZLength4
_AtomValidateLdMemPair:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpA
            JP   _AtomValidateZLength1
_AtomValidateLdMemHL:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,AtomEncoded1
            CP   AtomOpImm8
            JP   _AtomValidateZLength2
_AtomValidateLdIndexed:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg8
            JP   C,AtomEncoded3
            CP   AtomOpImm8
            JP   _AtomValidateZLength4
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
            JP   Z,AtomEncoded2
            CP   AtomOpImm8
            JP   NZ,AtomInvalid
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpA
            JP   _AtomValidateNzLength2
_AtomValidateInOne:
            CALL AtomRequireOneOperand
            RET  C
            JP   AtomEncoded2

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
            JP   _AtomValidateNzLength2
_AtomValidateOutC:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            JP   Z,AtomEncoded2
            CALL AtomIsReg8
_AtomValidateCLength2:
            JP   C,AtomEncoded2
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
            JR   _AtomValidateOptionalReg8Length4
_AtomValidateBitIndexedNoDestination:
            CALL AtomRequireTwoOperands
            RET  C
            JP   AtomEncoded4
_AtomValidateBitPlain:
            CALL AtomRequireTwoOperands
            RET  C
            JP   AtomEncoded2

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
_AtomValidateOptionalReg8Length4:
            CP   AtomOpNone
            JP   Z,AtomEncoded4
            CALL AtomIsReg8
            JP   C,AtomEncoded4
            JP   AtomInvalid
_AtomValidateRotatePlain:
            CALL AtomRequireOneOperand
            RET  C
            JP   AtomEncoded2

_AtomValidateAlu:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateAlu16
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JP   C,AtomEncoded1
            CP   AtomOpMemHL
            JP   Z,AtomEncoded1
            CP   AtomOpImm8
            JP   Z,AtomEncoded2
            CALL AtomIsHalfIndex
            JP   C,AtomEncoded2
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JP   _AtomValidateCLength3
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
            JP   _AtomValidateCLength2
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
            JP   Z,AtomEncoded2
            CP   AtomOpDE
            JP   Z,AtomEncoded2
            CP   AtomOpSP
            JP   Z,AtomEncoded2
            CP   B
            JP   _AtomValidateZLength2
_AtomValidateAddHl:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomIsReg16
            JP   C,AtomEncoded1
            JP   AtomInvalid

_AtomValidateJp:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateJpConditional
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,AtomEncoded3
            CP   AtomOpMemHL
            JP   Z,AtomEncoded1
            CP   AtomOpMemIX
            JP   Z,AtomEncoded2
            CP   AtomOpMemIY
            JP   _AtomValidateZLength2
_AtomValidateJpConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsCondition
            JP   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            JP   Z,AtomEncoded3
            JR   AtomInvalid

_AtomValidateCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateCallConditional
            CALL AtomRequireOneOperand
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm16
            JP   Z,AtomEncoded3
            JR   AtomInvalid
_AtomValidateCallConditional:
            JR   _AtomValidateJpConditional

_AtomValidateJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomValidateJrConditional
            CALL AtomRequireOneOperand
            RET  C
            JR   _AtomValidateRelativeOperand
_AtomValidateJrConditional:
            CALL AtomRequireTwoOperands
            RET  C
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsRelativeCondition
            JR   NC,AtomInvalid
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpRel8
            JP   Z,AtomEncoded2
            JR   AtomInvalid

_AtomValidateDjnz:
            CALL AtomRequireOneOperand
            RET  C
_AtomValidateRelativeOperand:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpRel8
            JP   Z,AtomEncoded2
            JR   AtomInvalid

_AtomValidationDispatchTable:
            .dw _AtomValidateCore,_AtomValidateRet,_AtomValidateEx
            .dw _AtomValidateIm,_AtomValidateRst,_AtomValidateIncDec
            .dw _AtomValidateStack,_AtomValidateLd,_AtomValidateIn
            .dw _AtomValidateOut,_AtomValidateBit,_AtomValidateRotate
            .dw _AtomValidateAlu,_AtomValidateJp,_AtomValidateCall
            .dw _AtomValidateJr,_AtomValidateDjnz

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
.routine in IX out A,carry clobbers zero,sign,parity,halfCarry
AtomRequireOneOperand:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,AtomRequireBad
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
            RET  C
            CP   AtomOpA
            JR   Z,AtomPredicateYes
            CP   A
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsReg16:
            CP   AtomOpBC
            JR   C,AtomPredicateNo
            CP   AtomOpSP+1
            RET
.routine in A out carry,zero,sign,parity,halfCarry
AtomIsHalfIndex:
            PUSH BC
            LD   C,A
            AND  $F6
            CP   AtomOpIXH
            LD   A,C
            POP  BC
            JR   Z,AtomPredicateYes
            JR   AtomPredicateNo
.routine in A out carry,zero,sign,parity,halfCarry
AtomIsIndexed:
            CP   AtomOpIndexIX
            JR   C,AtomPredicateNo
            CP   AtomOpIndexIY+1
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpM+1
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsRelativeCondition:
            CP   AtomOpNZ
            JR   C,AtomPredicateNo
            CP   AtomOpCC+1
            RET
.routine in A out carry clobbers zero,sign,parity,halfCarry
AtomIsBitIndex:
            CP   AtomOpBit0
            JR   C,AtomPredicateNo
            CP   AtomOpBit7+1
            RET
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

; Encode the condition in operand zero above the opcode base in B.
.routine in IX,B out A clobbers zero,sign,parity,halfCarry,carry
AtomEncodeConditionOpcode:
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpNZ
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            RET

.routine in IX out A,carry clobbers zero,sign,parity,halfCarry,B,DE,HL
AtomEncodeCore:
            LD   A,(IX+AtomInstrMnemonic)
            LD   DE,_AtomEncodingDispatchTable
            JP   AtomDispatchMnemonic

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
            JP   Z,AtomEncoded1
            JP   _AtomStoreScratch1Encoded2

_AtomEncodeRet:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpNone
            JR   Z,_AtomEncodeRetPlain
            LD   B,$C0
            CALL AtomEncodeConditionOpcode
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
            JP   _AtomStoreScratch1Encoded2
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
            LD   A,(IX+AtomInstrOp0)
            SUB  AtomOpIm0
            LD   E,A
            LD   D,0
            LD   HL,AtomImOpcodes
            ADD  HL,DE
            LD   A,(HL)
            LD   B,A
            JP   _AtomStoreEdBEncoded2

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
_AtomStoreScratch2Encoded3:
            LD   (AtomScratch+2),A
            JP   AtomEncoded3
_AtomEncodeIncDecRegister:
            LD   A,(IX+AtomInstrOp0)
_AtomEncodeThreeShiftAddB:
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
_AtomEncodePairFieldB:
            AND  3
            ADD  A,A
            JR   _AtomEncodeThreeShiftAddB
_AtomEncodeIncDecIndexPair:
            CALL AtomStorePrefixPreserveAF
            LD   A,B
            CP   4
            LD   A,$23
            JR   Z,_AtomEncodeIncDecIndexPairReady
            LD   A,$2B
_AtomEncodeIncDecIndexPairReady:
            JP   _AtomStoreScratch1Encoded2
_AtomEncodeIncDecHalf:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomStorePrefixPreserveAF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            JP   _AtomStoreScratch1Encoded2
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
            JP   _AtomEncodePairFieldB
_AtomEncodeStackIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,B
            ADD  A,$20
            JP   _AtomStoreScratch1Encoded2

AtomLdEncodingStart .equ $
_AtomEncodeLd:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsReg8
            JR   C,_AtomEncodeLdReg8
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
            JR   _AtomEncodeLdRegHalf
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
_AtomStoreAValue1Encoded2:
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            JP   _AtomStoreScratch1Encoded2
_AtomEncodeLdRegMemHl:
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$46
            JP   _AtomStoreEncoded1
_AtomEncodeLdAAbs:
            LD   A,$3A
_AtomStoreAValue1Encoded3:
            LD   (AtomScratch+0),A
            JP   AtomCopyValue1ToScratch1
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
_AtomStoreEdBEncoded2:
            LD   A,$ED
            LD   (AtomScratch+0),A
            LD   A,B
            JP   _AtomStoreScratch1Encoded2
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
            JP   _AtomStoreScratch2Encoded3
_AtomEncodeLdRegHalf:
            LD   A,(IX+AtomInstrOp1)
            CALL AtomStorePrefixPreserveAF
            AND  7
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,B
            ADD  A,$40
            JP   _AtomStoreScratch1Encoded2

_AtomEncodeLdHalf:
            CALL AtomStorePrefixPreserveAF
            AND  7
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+AtomInstrOp1)
            AND  7
            ADD  A,B
            ADD  A,$40
            JP   _AtomStoreScratch1Encoded2

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
            JP   _AtomStoreScratch1Encoded2
_AtomEncodeLdReg16Imm:
            LD   A,(IX+AtomInstrOp0)
            AND  3
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,A
            INC  A
            JP   _AtomStoreAValue1Encoded3
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
            JP   AtomCopyValue1ToScratch2
_AtomEncodeLdHlAbs:
            LD   A,$2A
            JP   _AtomStoreAValue1Encoded3
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
            JP   _AtomStoreScratch1Encoded2

_AtomEncodeLdIndex16:
            CALL AtomStorePrefixPreserveAF
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm16
            LD   A,$21
            JR   Z,_AtomEncodeLdIndex16Opcode
            LD   A,$2A
_AtomEncodeLdIndex16Opcode:
            LD   (AtomScratch+1),A
            JP   AtomCopyValue1ToScratch2
_AtomEncodeLdSpecialTarget:
            LD   B,$47
            CP   AtomOpI
            JR   Z,_AtomEncodeLdSpecialTargetReady
            LD   B,$4F
_AtomEncodeLdSpecialTargetReady:
            JP   _AtomStoreEdBEncoded2
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
            JP   AtomCopyValue0ToScratch2
_AtomEncodeLdAbsA:
            LD   A,$32
            LD   (AtomScratch+0),A
            JP   AtomCopyValue0ToScratch1
_AtomEncodeLdAbsHl:
            LD   A,$22
            LD   (AtomScratch+0),A
            JP   AtomCopyValue0ToScratch1
_AtomEncodeLdAbsIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$22
            LD   (AtomScratch+1),A
            JP   AtomCopyValue0ToScratch2
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
            JP   _AtomStoreAValue1Encoded2
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
            JP   _AtomStoreScratch2Encoded3
_AtomEncodeLdIndexedImm:
            LD   A,$36
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            LD   (AtomScratch+2),A
            LD   A,(IX+AtomInstrValue1)
_AtomStoreScratch3Encoded4:
            LD   (AtomScratch+3),A
            JP   AtomEncoded4
AtomLdEncodingEnd .equ $

_AtomEncodeIn:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpPortC
            JR   Z,_AtomEncodeInBare
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeInImmediate
            LD   A,(IX+AtomInstrOp0)
            ADD  A,A
            ADD  A,A
            ADD  A,A
            ADD  A,$40
            JR   _AtomEncodeInEd
_AtomEncodeInBare:
            LD   A,$70
            JR   _AtomEncodeInEd
_AtomEncodeInImmediate:
            LD   A,$DB
            JP   _AtomStoreAValue1Encoded2
_AtomEncodeInEd:
            LD   B,A
            JP   _AtomStoreEdBEncoded2

_AtomEncodeOut:
            LD   A,(IX+AtomInstrOp0)
            CP   AtomOpImm8
            JR   Z,_AtomEncodeOutImmediate
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpZero
            LD   A,$71
            JR   Z,_AtomEncodeInEd
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
            JP   _AtomStoreScratch1Encoded2

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
            JR   _AtomEncodeCbPlain
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
            LD   E,(IX+AtomInstrValue1)
            JR   _AtomEncodeCbIndexedTail

_AtomEncodeRotate:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMRlc
            CP   7
            JR   C,_AtomEncodeRotateBase
            DEC  A
_AtomEncodeRotateBase:
            ADD  A,A
            ADD  A,A
            ADD  A,A
            LD   B,A
            LD   A,(IX+AtomInstrOp0)
            CALL AtomIsIndexed
            JR   C,_AtomEncodeRotateIndexed
            LD   A,(IX+AtomInstrOp0)
_AtomEncodeCbPlain:
            AND  7
            ADD  A,B
            LD   B,A
            LD   A,$CB
            LD   (AtomScratch+0),A
            LD   A,B
            JP   _AtomStoreScratch1Encoded2
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
            LD   E,(IX+AtomInstrValue0)
_AtomEncodeCbIndexedTail:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$CB
            LD   (AtomScratch+1),A
            LD   A,E
            LD   (AtomScratch+2),A
            LD   A,B
            JP   _AtomStoreScratch3Encoded4

_AtomEncodeAlu:
            LD   A,(IX+AtomInstrMnemonic)
            SUB  AtomMAdd
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
            JP   _AtomStoreScratch1Encoded2
_AtomEncodeAluHalf:
            LD   A,(IX+AtomInstrOp0)
            CALL AtomStorePrefixPreserveAF
            AND  7
            ADD  A,B
            ADD  A,$80
            JP   _AtomStoreScratch1Encoded2
_AtomEncodeAluIndexed:
            CALL AtomStorePrefixPreserveAF
            LD   A,B
            ADD  A,$86
            LD   (AtomScratch+1),A
            LD   A,(IX+AtomInstrValue0)
            JP   _AtomStoreScratch2Encoded3
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
            JP   _AtomStoreEdBEncoded2
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
            JR   _AtomStoreScratch1Encoded2

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
            JP   AtomCopyValue0ToScratch1
_AtomEncodeJpConditional:
            LD   B,$C2
            CALL AtomEncodeConditionOpcode
            JP   _AtomStoreAValue1Encoded3
_AtomEncodeJpHl:
            LD   A,$E9
            JR   _AtomStoreEncoded1
_AtomEncodeJpIndex:
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            LD   A,$E9
            JR   _AtomStoreScratch1Encoded2

_AtomEncodeCall:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomEncodeCallConditional
            LD   A,$CD
            LD   (AtomScratch+0),A
            JR   AtomCopyValue0ToScratch1
_AtomEncodeCallConditional:
            LD   B,$C4
            CALL AtomEncodeConditionOpcode
            LD   (AtomScratch+0),A
            JR   AtomCopyValue1ToScratch1

_AtomEncodeJr:
            LD   A,(IX+AtomInstrOp1)
            CP   AtomOpNone
            JR   NZ,_AtomEncodeJrConditional
            LD   A,$18
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
            JR   _AtomStoreScratch1Encoded2
_AtomEncodeJrConditional:
            LD   B,$20
            CALL AtomEncodeConditionOpcode
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue1)
            JR   _AtomStoreScratch1Encoded2

_AtomEncodeDjnz:
            LD   A,$10
            LD   (AtomScratch+0),A
            LD   A,(IX+AtomInstrValue0)
_AtomStoreScratch1Encoded2:
            LD   (AtomScratch+1),A
            JR   AtomEncoded2

_AtomEncodingDispatchTable:
            .dw _AtomEncodeCoreOpcode,_AtomEncodeRet,_AtomEncodeEx
            .dw _AtomEncodeIm,_AtomEncodeRst,_AtomEncodeIncDec
            .dw _AtomEncodeStack,_AtomEncodeLd,_AtomEncodeIn
            .dw _AtomEncodeOut,_AtomEncodeBit,_AtomEncodeRotate
            .dw _AtomEncodeAlu,_AtomEncodeJp,_AtomEncodeCall
            .dw _AtomEncodeJr,_AtomEncodeDjnz

_AtomStoreEncoded1:
            LD   (AtomScratch+0),A
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomEncoded1:
            XOR  A
            INC  A
            RET
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomEncoded2:
            LD   A,2
            OR   A
            RET
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomEncoded3:
            LD   A,3
            OR   A
            RET
.routine out A,carry maybe-out zero clobbers sign,parity,halfCarry,zero
AtomEncoded4:
            LD   A,4
            OR   A
            RET

; Shared output helpers. Each is a tail entry that returns the encoded length.
.routine in IX out A,carry maybe-out zero clobbers HL,sign,parity,halfCarry,zero
AtomCopyValue0ToScratch1:
            LD   L,(IX+AtomInstrValue0)
            LD   H,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+1),HL
            JR   AtomEncoded3
.routine in IX out A,carry maybe-out zero clobbers HL,sign,parity,halfCarry,zero
AtomCopyValue0ToScratch2:
            LD   L,(IX+AtomInstrValue0)
            LD   H,(IX+AtomInstrValue0+1)
            LD   (AtomScratch+2),HL
            JR   AtomEncoded4
.routine in IX out A,carry maybe-out zero clobbers HL,sign,parity,halfCarry,zero
AtomCopyValue1ToScratch1:
            LD   L,(IX+AtomInstrValue1)
            LD   H,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+1),HL
            JR   AtomEncoded3
.routine in IX out A,carry maybe-out zero clobbers HL,sign,parity,halfCarry,zero
AtomCopyValue1ToScratch2:
            LD   L,(IX+AtomInstrValue1)
            LD   H,(IX+AtomInstrValue1+1)
            LD   (AtomScratch+2),HL
            JR   AtomEncoded4

.routine in A
AtomStorePrefixPreserveAF:
            PUSH AF
            .expectout A
            CALL AtomPrefixFromOperand
            LD   (AtomScratch+0),A
            POP  AF
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
AtomOpcodeTableEnd:

            .include "atom-mnemonics.inc"

AtomEncoderImmutableEnd:
AtomEncoderCoreEnd:

; Writable, non-reentrant workspace. The first four bytes are also the encoder
; commit buffer.
AtomEncoderWorkspaceStart:
AtomScratch:     .ds 6
AtomEncoderWorkspaceEnd:
