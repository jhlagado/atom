; The parser's operand-name table and its fixed workspace, which also holds
; the build and public reference records.

prRuleTo: ; End parser rule code before its operand lookup table.
prRomBeg: ; Begin immutable parser operand-name data.

; Sorted RADIX-40 operand-word table. Each three-byte entry contains one
; packed word and its provisional encoder class. C maps to prAnyC because only
; complete form validation can distinguish register C from condition C.

prKeyCnt    EQU     27                  ; Number of three-byte operand-word entries.
prKeyTab: ; Packed operand words followed by provisional encoder classes.
    DW   $0640                          ; Packed operand word A.
    DB   enRegA                         ; Accumulator register class.
    DW   $0730                          ; Packed operand word AF.
    DB   enRegAF                        ; AF register-pair class.
    DW   $0C80                          ; Packed operand word B.
    DB   enRegB                         ; B register class.
    DW   $0CF8                          ; Packed operand word BC.
    DB   enRegBC                        ; BC register-pair class.
    DW   $12C0                          ; Packed operand word C.
    DB   prAnyC                         ; Ambiguous register or condition class.
    DW   $1900                          ; Packed operand word D.
    DB   enRegD                         ; D register class.
    DW   $19C8                          ; Packed operand word DE.
    DB   enRegDE                        ; DE register-pair class.
    DW   $1F40                          ; Packed operand word E.
    DB   enRegE                         ; E register class.
    DW   $3200                          ; Packed operand word H.
    DB   enRegH                         ; H register class.
    DW   $33E0                          ; Packed operand word HL.
    DB   enRegHL                        ; HL register-pair class.
    DW   $3840                          ; Packed operand word I.
    DB   enRegI                         ; Interrupt-vector register class.
    DW   $3C00                          ; Packed operand word IX.
    DB   enRegIX                        ; IX register-pair class.
    DW   $3C08                          ; Packed operand word IXH.
    DB   enRegIXH                       ; IX high-byte register class.
    DW   $3C0C                          ; Packed operand word IXL.
    DB   enRegIXL                       ; IX low-byte register class.
    DW   $3C28                          ; Packed operand word IY.
    DB   enRegIY                        ; IY register-pair class.
    DW   $3C30                          ; Packed operand word IYH.
    DB   enRegIYH                       ; IY high-byte register class.
    DW   $3C34                          ; Packed operand word IYL.
    DB   enRegIYL                       ; IY low-byte register class.
    DW   $4B00                          ; Packed operand word L.
    DB   enRegL                         ; L register class.
    DW   $5140                          ; Packed operand word M.
    DB   enCondM                        ; Minus condition class.
    DW   $57F8                          ; Packed operand word NC.
    DB   enCondNC                       ; No-carry condition class.
    DW   $5B90                          ; Packed operand word NZ.
    DB   enCondNZ                       ; Nonzero condition class.
    DW   $6400                          ; Packed operand word P.
    DB   enCondP                        ; Plus condition class.
    DW   $64C8                          ; Packed operand word PE.
    DB   enCondPE                       ; Parity-even condition class.
    DW   $6658                          ; Packed operand word PO.
    DB   enCondPO                       ; Parity-odd condition class.
    DW   $7080                          ; Packed operand word R.
    DB   enRegR                         ; Memory-refresh register class.
    DW   $7940                          ; Packed operand word SP.
    DB   enRegSP                        ; Stack-pointer class.
    DW   $A280                          ; Packed operand word Z.
    DB   enCondZ                        ; Zero condition class.
prKeyEnd: ; End the packed operand-word table.
prRomEnd: ; End immutable parser data.
prEnd: ; End parser and reference-publication code.
prRamLo: ; Begin fixed parser workspace.

; Per-call destinations and instruction identity. prInsLen is returned by
; enCheck and is required for relative-target conversion.

prDest:     DW      0                   ; Caller-owned ten-byte commit destination.
prInsPC:    DW      0                   ; Current instruction's logical address.
prMnPart:   DB      0                   ; Source part containing the mnemonic.
prMnOff:    DW      0                   ; Byte offset of the mnemonic in that part.
prInsLen:    DB      0                  ; Validated encoded instruction length.
prOpCnt:   DB      0                    ; Parsed operand count, zero to three.

; Shared scan index, ambiguity masks and selected class/value pointers used by
; operand normalisation and range checking.

prOpIdx:   DB      0                    ; Operand index used by normalisation loops.
prWideOk:   DB      0                   ; Byte-value fields that may widen to words.
prCcMask:   DB      0                   ; C fields that may be condition C.
prClsPtr:    DW      0                  ; Selected operand-class byte address.
prValPtr:    DW      0                  ; Selected operand-value word address.
prSavCls:   DB      0                   ; Operand class saved across token fetch.
prBase:    DB      0                    ; Parenthesised register or port base class.
prIxIy:    DB      0                    ; Indexed IX/IY class saved during parsing.

; Retained workspace byte with no caller in the current parser implementation.

prSpare:   DB      0                    ; Reserved legacy displacement-sign scratch.

; Six-byte packed operand key and private ten-byte instruction record.
; Selected scratch bytes are also reused for nested status and source fields.
; Terminal errors prevent commit, but a recovered short-word probe may leave
; ignored error bytes in unused operand-value slots of a successful record.

prKeyBuf:   DS      6                   ; Packed short operand-word key buffer.
prRec:     DS      10                   ; Private encoder-format instruction record.
prStatus    EQU     prRec+6             ; Public parser error status overlay.
prErrSrc    EQU     prRec+7             ; Public error source-part overlay.
prErrOff    EQU     prRec+8             ; Public error source-offset overlay.
prExDet     EQU     prRec+5             ; Nested expression status overlay.
prSymDet    EQU     prRec+5             ; Nested symbol status overlay.

; Reference publication state. prRawCnt counts private entries. prPubCnt is
; published after their symbols and public records are complete.

prPubCnt:   DB      0                   ; Published reference-description count.
prRawCnt:   DB      0                   ; Private build-reference count.
prAwait:   DB      0                    ; Bits marking unresolved operand values.
prRefIdx:    DB      0                  ; Reference index during publication.
prMissed:    DB      0                  ; Missing symbols for this instruction.
prSame:    DB      0                    ; One when both build records share a key.
prTemp:     DB      0                   ; Patch kind or queued source-part ordinal.
prField:   DB      0                    ; Encoded field offset across lookup.
prAddend:    DW      0                  ; Signed addend before key copying.
prBasePC:   DW      0                   ; Logical instruction base while queueing.

; Two thirteen-byte build entries and two nine-byte public entries complete
; the fixed 94-byte parser workspace.

prRelVal:    DW      0                  ; Offset of a rejected relative jump.
prRawRef:   DS      prRawLen*prRefCap   ; Two private thirteen-byte build records.
prPubRef:   DS      prPubLen*prRefCap   ; Two public nine-byte reference records.
prRamHi: ; End the fixed parser workspace extent.
