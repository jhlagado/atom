;=============================================================================
;  Patch-field locator
;=============================================================================
;
;  Find the encoded field for one operand of a validated instruction.
;  Return its byte offset and base kind: byte, word, relative displacement
;  or index displacement. Patch records also support low-byte truncation
;  and LOW/HIGH transforms. DB selects truncation. Unresolved LOW/HIGH
;  expressions retain their transform until patching.
;
;  Principal entry:
;    PT_FIELD  map an operand index to its encoded field and patch kind

PT_CBEG: ; Begin patch-field code and kind constants.

; Patch kinds stored in the low three bits of a pending record. SY_DANCH may
; occupy the high bit without changing this value.

PT_KINDB    EQU     1                   ; Replace one encoded byte.
PT_KINDW    EQU     2                   ; Replace one little-endian word.
PT_KREL     EQU     3                   ; Replace one PC-relative displacement.
PT_KDISP    EQU     4                   ; Replace one IX/IY displacement.
PT_KTB      EQU     5                   ; Truncate a resolved word to its low byte.
PT_KLB      EQU     6                   ; Apply LOW to a resolved word.
PT_KHB      EQU     7                   ; Apply HIGH to a resolved word.

;@ROUTINE IN IX,A OUT A,B,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; A is operand index 0..2. IX points at a validated record. Return A as
; base patch kind and B as byte offset from the instruction start.

PT_FIELD: ; Locate operand A's patch field within validated record IX.
    CP   3                              ; Only operand slots zero, one and two exist.
    JR   NC,.INVALID                    ; Reject an index outside the instruction record.
    LD   E,A                            ; Retain the operand index as a table offset.
    LD   D,0                            ; Extend the index to 16 bits.
    PUSH DE                             ; Save the index across EN_LEN.
    CALL EN_LEN                         ; Validate the form and obtain its encoded length.
    POP  DE                             ; Restore the index, preserving carry.
    JR   C,.INVALID                     ; A rejected form cannot have a patch field.

; EN_LEN supplies the total byte length without reading operand values.

    LD   B,A                            ; Keep the instruction length for field placement.
    LD   HL,EN_OP0                      ; Start at operand zero's class-field offset.
    ADD  HL,DE                          ; Select the requested operand's class offset.
    PUSH IX                             ; Copy the instruction-record address into DE.
    POP  DE                             ; DE now addresses the validated record.
    ADD  HL,DE                          ; HL points at the selected operand class byte.
    LD   A,(HL)                         ; Read the operand class supplied by the parser.

; Patchable operand classes are the contiguous range (IX+d) through REL8. The
; table deliberately rejects PORT_C, which has no encoded value field.

    SUB  EN_IIX                         ; Convert the first patchable class to index zero.
    CP   7                              ; Seven class slots feed the kind table.
    JR   NC,.INVALID                    ; Classes outside that interval contain no field.
    LD   E,A                            ; Retain the bounded patch-kind table index.
    LD   D,0                            ; Widen it for address arithmetic.
    LD   HL,.KINDTAB                    ; Address the class-to-patch-kind table.
    ADD  HL,DE                          ; Select the entry for this operand class.
    LD   A,(HL)                         ; Load its base patch kind. Zero means no field.
    OR   A                              ; Test the table's rejection sentinel.
    JR   Z,.INVALID                     ; PORT_C has no patchable value field.
    CP   PT_KDISP                       ; Indexed displacement has a fixed field position.
    JR   Z,.DISPLACE                    ; Return byte offset two for either index prefix.

; Ordinary byte fields end at length-1. Little-endian word fields begin at
; length-2. This also locates an indexed instruction's trailing immediate.

    DEC  B                              ; Place a byte field at the final encoded byte.
    CP   PT_KINDW                       ; A word occupies the final two encoded bytes.
    JR   NZ,.READY                      ; Other kinds already have their correct offset.
    DEC  B                              ; Move from the high byte to the word's low byte.
.READY: ; Return the selected patch kind and encoded offset with carry clear.
    OR   A                              ; Return success with carry clear and kind in A.
    RET                                 ; B identifies the field within the instruction.
.INVALID: ; Return no field with carry set for an invalid request.
    XOR  A                              ; Return no patch kind for an invalid request.
    SCF                                 ; Mark the lookup as failed.
    RET                                 ; B is undefined on failure.
.DISPLACE: ; Return fixed offset two for an indexed-memory displacement.

; Every DD/FD indexed-memory displacement is byte two. Ordinary forms are
; prefix, opcode, displacement. Indexed-CB forms are prefix, CB, displacement,
; opcode.

    LD   B,2                            ; Skip the index prefix and opcode or CB.
    OR   A                              ; Preserve PT_KDISP while clearing carry.
    RET                                 ; Return the fixed indexed-displacement position.
.KINDTAB: ; Map the contiguous patchable operand classes to base patch kinds.

; EN_IIX, EN_IIY, EN_MABS, EN_IMM8, EN_IMM16, EN_PORTC, EN_REL8.

    DB   PT_KDISP,PT_KDISP              ; IX/IY memory operands patch their displacement.
    DB   PT_KINDW,PT_KINDB,PT_KINDW     ; Absolute memory, byte immediate and word immediate.
    DB   0,PT_KREL                      ; Port C has no field. REL8 patches relatively.
PT_CEND: ; End patch-field code and its immutable kind table.
