;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length one.

enDone1: ; Return successful length one.
    XOR  A                                                      ; Clear A and carry for success status.
    INC  A                                                      ; Return encoded length one.
    RET                                                         ; Finish with carry still clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length two.

enDone2: ; Return successful length two.
    LD   A,2                                                    ; Return encoded length two.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length three.

enDone3: ; Return successful length three.
    LD   A,3                                                    ; Return encoded length three.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length four.

enDone4: ; Return successful length four.
    LD   A,4                                                    ; Return encoded length four.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after one opcode byte.

enOp0At1: ; Write operand zero at byte one.
    LD   L,(IX+enVal0)                                          ; Load operand zero low byte.
    LD   H,(IX+enVal0+1)                                        ; Load target high byte.
    LD   (enTemp+1),HL                                          ; Store address after opcode.
    JR   enDone3                                                ; Return length three.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after a prefix/opcode pair.

enOp0At2: ; Write operand zero at byte two.
    LD   L,(IX+enVal0)                                          ; Load operand zero low byte.
    LD   H,(IX+enVal0+1)                                        ; Load target high byte.
    LD   (enTemp+2),HL                                          ; Store address after prefix/opcode.
    JR   enDone4                                                ; Return length four.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after one opcode byte.

enOp1At1: ; Write operand one at byte one.
    LD   L,(IX+enVal1)                                          ; Load operand one low byte.
    LD   H,(IX+enVal1+1)                                        ; Load target high byte.
    LD   (enTemp+1),HL                                          ; Store address after opcode.
    JR   enDone3                                                ; Return length three.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after a prefix/opcode pair.

enOp1At2: ; Write operand one at byte two.
    LD   L,(IX+enVal1)                                          ; Load operand one low byte.
    LD   H,(IX+enVal1+1)                                        ; Load target high byte.
    LD   (enTemp+2),HL                                          ; Store address after prefix/opcode.
    JR   enDone4                                                ; Return length four.

;@ROUTINE IN A
; Stage the prefix for class A and preserve A for field arithmetic.

enStage: ; Stage DD/FD while preserving class A.
    PUSH AF                                                     ; Save the operand class.
;@EXPECTOUT A
    CALL enIdxPfx                                               ; Select the index prefix.
    LD   (enTemp+0),A                                           ; Stage the selected index prefix.
    POP  AF                                                     ; Restore class for register-field math.
    RET                                                         ; Return with the original class in A.

;@ROUTINE IN A OUT A CLOBBERS F
; Map IX classes and even indexed-memory classes to DD; IY classes
; and odd indexed-memory classes to FD. Validation guarantees A is prefixable.

enIdxPfx: ; Map a validated index class to DD or FD.
    CP   enRegIXH                                               ; Index-half classes begin at IXH.
    JR   C,.ordinary                                            ; Pair/memory classes use their family bit.
    CP   enRegIXL+1                                             ; Check the end of IXH/IXL's class range.
    JR   C,.prefixIx                                            ; IX halves always select DD.
    CP   enRegIYH                                               ; Check whether this is below the IY-half range.
    JR   C,.ordinary                                            ; Other prefixable classes use their family tag.
    CP   enRegIYL+1                                             ; Check the end of IYH/IYL's class range.
    JR   C,.prefixIy                                            ; IY halves always select FD.
.ordinary: ; Use the low family bit for pair and memory classes.
    AND  1                                                      ; Even means IX; odd means IY.
    JR   NZ,.prefixIy                                           ; Select FD for an odd IY-family class.
.prefixIx: ; Return the DD prefix.
    LD   A,$DD                                                  ; Return the IX prefix byte.
    RET                                                         ; Finish prefix selection.
.prefixIy: ; Return the FD prefix.
    LD   A,$FD                                                  ; Return the IY prefix byte.
    RET                                                         ; Finish prefix selection.
enPutEnd: ; End staged instruction emission.
enEnd: ; End executable encoder code.
enRomBeg: ; Begin immutable encoder data.
enTabBeg: ; Begin irregular opcode tables.

; Irregular opcodes. The first thirteen are direct bytes.
; The remaining entries are ED suffixes.

enOpTab: ; Singleton opcodes followed by ED suffixes.
    DB   $00,$F3,$FB,$37,$3F,$2F,$27,$D9,$76,$07,$0F,$17,$1F    ; Core opcodes.
    DB   $44,$67,$6F,$A0,$B0,$A8,$B8,$A1,$B1,$A9,$B9,$A2        ; ED suffixes.
    DB   $B2,$AA,$BA,$A3,$B3,$AB,$BB,$4D,$45                    ; INIR..RETN suffixes.
enImTab:   DB      $46,$56,$5E                                  ; IM suffixes.
enTabEnd: ; End irregular opcode tables.
enRomEnd: ; End immutable encoder data.
enAllEnd: ; End encoder code and immutable data.
enRamLo: ; Begin shared encoder workspace.

; Scratch: six bytes for packed names; first four also stage opcodes.

enTemp:     DS      6                                           ; Packer scratch and opcode staging.
enRamHi: ; End shared encoder workspace.
