;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length one.

EN_D1: ; Return successful length one.
    XOR  A                                                      ; Clear A and carry for success status.
    INC  A                                                      ; Return encoded length one.
    RET                                                         ; Finish with carry still clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length two.

EN_D2: ; Return successful length two.
    LD   A,2                                                    ; Return encoded length two.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length three.

EN_D3: ; Return successful length three.
    LD   A,3                                                    ; Return encoded length three.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE OUT A,CARRY MAYBE-OUT ZERO CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Return successful encoding length four.

EN_D4: ; Return successful length four.
    LD   A,4                                                    ; Return encoded length four.
    OR   A                                                      ; Clear carry and retain length.
    RET                                                         ; Finish with carry clear.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after one opcode byte.

EN_V0AT1: ; Write operand zero at byte one.
    LD   L,(IX+EN_VAL0)                                         ; Load operand zero low byte.
    LD   H,(IX+EN_VAL0+1)                                       ; Load target high byte.
    LD   (EN_TMP+1),HL                                          ; Store address after opcode.
    JR   EN_D3                                                  ; Return length three.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand zero's word after a prefix/opcode pair.

EN_V0AT2: ; Write operand zero at byte two.
    LD   L,(IX+EN_VAL0)                                         ; Load operand zero low byte.
    LD   H,(IX+EN_VAL0+1)                                       ; Load target high byte.
    LD   (EN_TMP+2),HL                                          ; Store address after prefix/opcode.
    JR   EN_D4                                                  ; Return length four.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after one opcode byte.

EN_V1AT1: ; Write operand one at byte one.
    LD   L,(IX+EN_VAL1)                                         ; Load operand one low byte.
    LD   H,(IX+EN_VAL1+1)                                       ; Load target high byte.
    LD   (EN_TMP+1),HL                                          ; Store address after opcode.
    JR   EN_D3                                                  ; Return length three.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT ZERO CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Copy operand one's word after a prefix/opcode pair.

EN_V1AT2: ; Write operand one at byte two.
    LD   L,(IX+EN_VAL1)                                         ; Load operand one low byte.
    LD   H,(IX+EN_VAL1+1)                                       ; Load target high byte.
    LD   (EN_TMP+2),HL                                          ; Store address after prefix/opcode.
    JR   EN_D4                                                  ; Return length four.

;@ROUTINE IN A
; Stage the prefix for class A and preserve A for field arithmetic.

EN_STAGE: ; Stage DD/FD while preserving class A.
    PUSH AF                                                     ; Save the operand class.
;@EXPECTOUT A
    CALL EN_DDFD                                                ; Select the index prefix.
    LD   (EN_TMP+0),A                                           ; Stage the selected index prefix.
    POP  AF                                                     ; Restore class for register-field math.
    RET                                                         ; Return with the original class in A.

;@ROUTINE IN A OUT A CLOBBERS F
; Map IX classes and even indexed-memory classes to DD; IY classes
; and odd indexed-memory classes to FD. Validation guarantees A is prefixable.

EN_DDFD: ; Map a validated index class to DD or FD.
    CP   EN_IXH                                                 ; Index-half classes begin at IXH.
    JR   C,.ORDINARY                                            ; Pair/memory classes use their family bit.
    CP   EN_IXL+1                                               ; Check the end of IXH/IXL's class range.
    JR   C,.PREFIXIX                                            ; IX halves always select DD.
    CP   EN_IYH                                                 ; Check whether this is below the IY-half range.
    JR   C,.ORDINARY                                            ; Other prefixable classes use their family tag.
    CP   EN_IYL+1                                               ; Check the end of IYH/IYL's class range.
    JR   C,.PREFIXIY                                            ; IY halves always select FD.
.ORDINARY: ; Use the low family bit for pair and memory classes.
    AND  1                                                      ; Even means IX; odd means IY.
    JR   NZ,.PREFIXIY                                           ; Select FD for an odd IY-family class.
.PREFIXIX: ; Return the DD prefix.
    LD   A,$DD                                                  ; Return the IX prefix byte.
    RET                                                         ; Finish prefix selection.
.PREFIXIY: ; Return the FD prefix.
    LD   A,$FD                                                  ; Return the IY prefix byte.
    RET                                                         ; Finish prefix selection.
EN_EMITE: ; End staged instruction emission.
EN_CODEE: ; End executable encoder code.
EN_IBEG: ; Begin immutable encoder data.
EN_CTBEG: ; Begin irregular opcode tables.

; Irregular opcodes. The first thirteen are direct bytes.
; The remaining entries are ED suffixes.

EN_OPTAB: ; Singleton opcodes followed by ED suffixes.
    DB   $00,$F3,$FB,$37,$3F,$2F,$27,$D9,$76,$07,$0F,$17,$1F    ; Core opcodes.
    DB   $44,$67,$6F,$A0,$B0,$A8,$B8,$A1,$B1,$A9,$B9,$A2        ; ED suffixes.
    DB   $B2,$AA,$BA,$A3,$B3,$AB,$BB,$4D,$45                    ; INIR..RETN suffixes.
EN_IMTAB:   DB      $46,$56,$5E                                 ; IM suffixes.
EN_CTEND: ; End irregular opcode tables.
EN_CNT      EQU     69                                          ; Number of mnemonic ordinals in the table.

; Mnemonic table in ordinal order. Three-byte entries contain the
; first packed RADIX-40 word and the significant high byte of the second word.

EN_TABLE: ; Packed mnemonic rows by ordinal.
    DW   $59E8                                                  ; NOP name word.
    DB   $00                                                    ; NOP packed tail byte.
    DW   $1A68                                                  ; DI name word.
    DB   $00                                                    ; DI packed tail byte.
    DW   $20A8                                                  ; EI name word.
    DB   $00                                                    ; EI packed tail byte.
    DW   $773E                                                  ; SCF name word.
    DB   $00                                                    ; SCF packed tail byte.
    DW   $133E                                                  ; CCF name word.
    DB   $00                                                    ; CCF packed tail byte.
    DW   $154C                                                  ; CPL name word.
    DB   $00                                                    ; CPL packed tail byte.
    DW   $1929                                                  ; DAA name word.
    DB   $00                                                    ; DAA packed tail byte.
    DW   $2318                                                  ; EXX name word.
    DB   $00                                                    ; EXX packed tail byte.
    DW   $3234                                                  ; HALT name word.
    DB   $7D                                                    ; HALT packed tail byte.
    DW   $7263                                                  ; RLCA name word.
    DB   $06                                                    ; RLCA packed tail byte.
    DW   $7353                                                  ; RRCA name word.
    DB   $06                                                    ; RRCA packed tail byte.
    DW   $7261                                                  ; RLA name word.
    DB   $00                                                    ; RLA packed tail byte.
    DW   $7351                                                  ; RRA name word.
    DB   $00                                                    ; RRA packed tail byte.
    DW   $584F                                                  ; NEG name word.
    DB   $00                                                    ; NEG packed tail byte.
    DW   $7354                                                  ; RRD name word.
    DB   $00                                                    ; RRD packed tail byte.
    DW   $7264                                                  ; RLD name word.
    DB   $00                                                    ; RLD packed tail byte.
    DW   $4BA9                                                  ; LDI name word.
    DB   $00                                                    ; LDI packed tail byte.
    DW   $4BA9                                                  ; LDIR name word.
    DB   $70                                                    ; LDIR packed tail byte.
    DW   $4BA4                                                  ; LDD name word.
    DB   $00                                                    ; LDD packed tail byte.
    DW   $4BA4                                                  ; LDDR name word.
    DB   $70                                                    ; LDDR packed tail byte.
    DW   $1549                                                  ; CPI name word.
    DB   $00                                                    ; CPI packed tail byte.
    DW   $1549                                                  ; CPIR name word.
    DB   $70                                                    ; CPIR packed tail byte.
    DW   $1544                                                  ; CPD name word.
    DB   $00                                                    ; CPD packed tail byte.
    DW   $1544                                                  ; CPDR name word.
    DB   $70                                                    ; CPDR packed tail byte.
    DW   $3A79                                                  ; INI name word.
    DB   $00                                                    ; INI packed tail byte.
    DW   $3A79                                                  ; INIR name word.
    DB   $70                                                    ; INIR packed tail byte.
    DW   $3A74                                                  ; IND name word.
    DB   $00                                                    ; IND packed tail byte.
    DW   $3A74                                                  ; INDR name word.
    DB   $70                                                    ; INDR packed tail byte.
    DW   $611C                                                  ; OUTI name word.
    DB   $38                                                    ; OUTI packed tail byte.
    DW   $60E9                                                  ; OTIR name word.
    DB   $70                                                    ; OTIR packed tail byte.
    DW   $611C                                                  ; OUTD name word.
    DB   $19                                                    ; OUTD packed tail byte.
    DW   $60E4                                                  ; OTDR name word.
    DB   $70                                                    ; OTDR packed tail byte.
    DW   $715C                                                  ; RETI name word.
    DB   $38                                                    ; RETI packed tail byte.
    DW   $715C                                                  ; RETN name word.
    DB   $57                                                    ; RETN packed tail byte.
    DW   $715C                                                  ; RET name word.
    DB   $00                                                    ; RET packed tail byte.
    DW   $2300                                                  ; EX name word.
    DB   $00                                                    ; EX packed tail byte.
    DW   $3A48                                                  ; IM name word.
    DB   $00                                                    ; IM packed tail byte.
    DW   $738C                                                  ; RST name word.
    DB   $00                                                    ; RST packed tail byte.
    DW   $3A73                                                  ; INC name word.
    DB   $00                                                    ; INC packed tail byte.
    DW   $19CB                                                  ; DEC name word.
    DB   $00                                                    ; DEC packed tail byte.
    DW   $675B                                                  ; PUSH name word.
    DB   $32                                                    ; PUSH packed tail byte.
    DW   $6668                                                  ; POP name word.
    DB   $00                                                    ; POP packed tail byte.
    DW   $4BA0                                                  ; LD name word.
    DB   $00                                                    ; LD packed tail byte.
    DW   $3A70                                                  ; IN name word.
    DB   $00                                                    ; IN packed tail byte.
    DW   $611C                                                  ; OUT name word.
    DB   $00                                                    ; OUT packed tail byte.
    DW   $0DFC                                                  ; BIT name word.
    DB   $00                                                    ; BIT packed tail byte.
    DW   $715B                                                  ; RES name word.
    DB   $00                                                    ; RES packed tail byte.
    DW   $779C                                                  ; SET name word.
    DB   $00                                                    ; SET packed tail byte.
    DW   $7263                                                  ; RLC name word.
    DB   $00                                                    ; RLC packed tail byte.
    DW   $7353                                                  ; RRC name word.
    DB   $00                                                    ; RRC packed tail byte.
    DW   $7260                                                  ; RL name word.
    DB   $00                                                    ; RL packed tail byte.
    DW   $7350                                                  ; RR name word.
    DB   $00                                                    ; RR packed tail byte.
    DW   $78A1                                                  ; SLA name word.
    DB   $00                                                    ; SLA packed tail byte.
    DW   $7991                                                  ; SRA name word.
    DB   $00                                                    ; SRA packed tail byte.
    DW   $78AC                                                  ; SLL name word.
    DB   $00                                                    ; SLL packed tail byte.
    DW   $78B3                                                  ; SLS name word.
    DB   $00                                                    ; SLS packed tail byte.
    DW   $799C                                                  ; SRL name word.
    DB   $00                                                    ; SRL packed tail byte.
    DW   $06E4                                                  ; ADD name word.
    DB   $00                                                    ; ADD packed tail byte.
    DW   $06E3                                                  ; ADC name word.
    DB   $00                                                    ; ADC packed tail byte.
    DW   $7A0A                                                  ; SUB name word.
    DB   $00                                                    ; SUB packed tail byte.
    DW   $7713                                                  ; SBC name word.
    DB   $00                                                    ; SBC packed tail byte.
    DW   $0874                                                  ; AND name word.
    DB   $00                                                    ; AND packed tail byte.
    DW   $986A                                                  ; XOR name word.
    DB   $00                                                    ; XOR packed tail byte.
    DW   $6090                                                  ; OR name word.
    DB   $00                                                    ; OR packed tail byte.
    DW   $1540                                                  ; CP name word.
    DB   $00                                                    ; CP packed tail byte.
    DW   $4100                                                  ; JP name word.
    DB   $00                                                    ; JP packed tail byte.
    DW   $12F4                                                  ; CALL name word.
    DB   $4B                                                    ; CALL packed tail byte.
    DW   $4150                                                  ; JR name word.
    DB   $00                                                    ; JR packed tail byte.
    DW   $1A9E                                                  ; DJNZ name word.
    DB   $A2                                                    ; DJNZ packed tail byte.
EN_TEND: ; End the compact mnemonic table.
EN_IEND: ; End immutable encoder data.
EN_COREE: ; End encoder code and immutable data.
EN_WBEG: ; Begin shared encoder workspace.

; Scratch: six bytes for packed names; first four also stage opcodes.

EN_TMP:     DS      6                                           ; Packer scratch and opcode staging.
EN_WEND: ; End shared encoder workspace.
