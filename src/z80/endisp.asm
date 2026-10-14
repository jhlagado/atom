enAllBeg: ; Begin the encoder code and immutable data range.
enBeg: ; Begin executable encoder code.
enVetBeg: ; Begin mnemonic dispatch and form-validation code.

;@ROUTINE IN A,DE CLOBBERS B,DE,HL,ZERO,SIGN,PARITY,HALFCARRY,CARRY
; Dispatch mnemonic A through a family table based at DE. Core ordinals 1..34
; share family zero. Later dense ordinal ranges are mapped by .families to the
; RET, EX, IM, RST, INC/DEC, stack, LD, I/O, bit, rotate, ALU and branches.

mneDisp: ; Select a handler from the table at DE using mnemonic A.
    LD   B,A                                        ; Preserve the mnemonic for the selected handler.
    CP   mneRet                                     ; Core ordinals all use family zero.
    JR   NC,.mapped                                 ; Later ordinals need a family-table lookup.
    XOR  A                                          ; Select entry zero for a core instruction.
    JR   .dispatch                                  ; Use the common address-table dispatch below.
.mapped: ; Convert a non-singleton ordinal to its family index.
    SUB  mneRet                                     ; Convert the ordinal to a zero-based offset.
    PUSH BC                                         ; Preserve the ordinal and caller's C register.
    LD   HL,.families                               ; Point at exclusive ends of family ranges.
    LD   C,1                                        ; Begin at family one; core uses family zero.
.loop: ; Find the first exclusive family boundary above this offset.
    CP   (HL)                                       ; Compare against this family's exclusive end.
    JR   C,.found                                   ; Select the first range containing the offset.
    INC  HL                                         ; Advance to the next family boundary.
    INC  C                                          ; Advance the corresponding family index.
    JR   .loop                                      ; Continue until a range contains the ordinal.
.found: ; Retain the family index and restore the original mnemonic.
    LD   A,C                                        ; Use the matching family index for dispatch.
    POP  BC                                         ; Restore the original ordinal in B.
.dispatch: ; Load the family handler and tail-jump with the mnemonic in A.
    ADD  A,A                                        ; Convert the family index to a word offset.
    LD   L,A                                        ; Place the offset in the low byte of HL.
    LD   H,0                                        ; Form the offset with a zero high byte.
    ADD  HL,DE                                      ; Address the selected handler pointer.
    LD   E,(HL)                                     ; Load the handler address's low byte.
    INC  HL                                         ; Advance to the high byte of that address.
    LD   D,(HL)                                     ; Complete the 16-bit handler address in DE.
    EX   DE,HL                                      ; Put the handler address in the jump register.
    LD   A,B                                        ; Restore the mnemonic ordinal for the handler.
    JP   (HL)                                       ; Enter the selected family handler.
.families: ; Exclusive cumulative ends for the non-singleton families.

; Exclusive cumulative family-end offsets from mneRet.

    DB   1,2,3,4,6,8,9,10,11,14,23,31,32,33,34,35   ; Family boundaries relative to mneRet, ending at DJNZ.
