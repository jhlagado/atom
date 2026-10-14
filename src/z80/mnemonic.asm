; Mnemonic ordinals are generated in compact-table order. Ordinals 1..34 are
; core singletons; 35..69 form the dispatched instruction families.

mneNop      EQU     1                               ; First singleton ordinal and first compact mnemonic row.
mneRet      EQU     35                              ; First dispatched family ordinal, following the singletons.
mneEx       EQU     36                              ; Exchange family ordinal.
mneIm       EQU     37                              ; Interrupt-mode family ordinal.
mneRst      EQU     38                              ; Restart-vector family ordinal.
mneInc      EQU     39                              ; First INC/DEC ordinal.
mneDec      EQU     40                              ; Last INC/DEC ordinal.
mnePush     EQU     41                              ; First stack-family ordinal.
mnePop      EQU     42                              ; Last stack-family ordinal.
mneLd       EQU     43                              ; Load family ordinal.
mneIn       EQU     44                              ; Port input family ordinal.
mneOut      EQU     45                              ; Port output family ordinal.
mneBit      EQU     46                              ; First bit-operation ordinal.
mneRes      EQU     47                              ; Bit-reset ordinal within the bit family.
mneSet      EQU     48                              ; Last bit-operation ordinal.
mneRlc      EQU     49                              ; First rotate/shift ordinal.
mneSrl      EQU     57                              ; Last rotate/shift ordinal, after the SLS alias.
mneAdd      EQU     58                              ; First arithmetic/logical ordinal.
mneAdc      EQU     59                              ; Add-with-carry ordinal.
mneSub      EQU     60                              ; Subtract ordinal.
mneSbc      EQU     61                              ; Subtract-with-carry ordinal.
mneAnd      EQU     62                              ; Bitwise AND ordinal.
mneXor      EQU     63                              ; Bitwise XOR ordinal.
mneOr       EQU     64                              ; Bitwise OR ordinal.
mneCp       EQU     65                              ; Last arithmetic/logical ordinal.
mneJp       EQU     66                              ; Absolute-jump family ordinal.
mneCall     EQU     67                              ; Call family ordinal.
mneJr       EQU     68                              ; Relative-jump family ordinal.
mneDjnz     EQU     69                              ; Counted relative-jump family ordinal.
mneLast     EQU     mneDjnz                         ; Inclusive upper bound for supported mnemonic ordinals.
mneBeg: ; Begin mnemonic recognition code.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,HL,IX,ZERO,SIGN,PARITY,HALFCARRY,DE
; Recognise a mnemonic of up to four characters. The table stores the first
; packed word and the high byte of the padded second word. Its row
; position plus one is the public mnemonic ordinal.

mneFind: ; Match the packed name against three-byte mnemonic rows.
    LD   A,B                                        ; Check the text length before packing it.
    CP   5                                          ; Four characters is the longest mnemonic.
    JR   NC,.notFound                               ; Reject longer text without touching the table.
    LD   DE,enTemp                                  ; Use private scratch for the packed name.
    CALL nmPack                                     ; Validate and pack the case-folded text.
    RET  C                                          ; Propagate an invalid length or character.
    LD   IX,mneRows                                 ; Point at the first three-byte mnemonic entry.
    LD   B,mneCount                                 ; Compare against every supported mnemonic.
    LD   C,1                                        ; Entry zero represents mnemonic ordinal one.
.loop: ; Compare all three distinguishing bytes in this mnemonic row.
    LD   A,(enTemp+0)                               ; Read the first packed word's low byte.
    CP   (IX+0)                                     ; Compare it with this table entry.
    JR   NZ,.next                                   ; Skip the remaining comparisons on mismatch.
    LD   A,(enTemp+1)                               ; Read the first packed word's high byte.
    CP   (IX+1)                                     ; Compare the second byte of the packed name.
    JR   NZ,.next                                   ; A mismatch rejects this candidate mnemonic.
    LD   A,(enTemp+3)                               ; Read the padded word's high byte.
    CP   (IX+2)                                     ; Compare its stored high byte with the entry.
    JR   NZ,.next                                   ; Try the next mnemonic if this byte differs.
    LD   A,C                                        ; The table position is the mnemonic ordinal.
    OR   A                                          ; Clear carry to report a successful match.
    RET                                             ; Return the ordinal in A.
.next: ; Advance IX by a row and C by an ordinal.
    INC  IX                                         ; Move from the low to high byte of the entry.
    INC  IX                                         ; Move to the entry's distinguishing byte.
    INC  IX                                         ; Advance to the next three-byte entry.
    INC  C                                          ; Keep the ordinal aligned with the table row.
    DJNZ .loop                                      ; Check the remaining mnemonic entries.
.notFound: ; Return ordinal zero and carry set for an unknown mnemonic.
    XOR  A                                          ; Return zero when no mnemonic matches.
    SCF                                             ; Set carry to mark an unknown mnemonic.
    RET                                             ; Return the unrecognised-name result.
mneCount    EQU     69                                          ; Number of mnemonic ordinals in the table.

; Mnemonic table in ordinal order. Three-byte entries contain the
; first packed RADIX-40 word and the significant high byte of the second word.

mneRows: ; Packed mnemonic rows by ordinal.
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
mneRowHi: ; End the compact mnemonic table.

mneEnd: ; End mnemonic recognition code.
