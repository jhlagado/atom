;==============================================================================
;  Patch-field locator
;==============================================================================
;
;  Locate the encoded field associated with one operand in a form the encoder has
;  already validated. The result identifies the field offset and its base patch
;  kind: byte, word, relative displacement or index displacement. Callers may
;  subsequently substitute truncate, LOW or HIGH byte transforms: statements
;  select truncation for DB, while the parser applies LOW/HIGH expressions.
;
;  Principal entry:
;    PT_LOCAT  map an operand index to its encoded field and patch kind

PT_CBEG:
; Patch kinds stored in the low three bits of a pending record. SY_DANCH may
; occupy the high bit without changing this value.
PT_KINDB EQU 1              ; Replace one encoded byte.
PT_KINDW EQU 2              ; Replace one little-endian word.
PT_KRELA EQU 3              ; Replace one PC-relative displacement.
PT_KDISP EQU 4              ; Replace one IX/IY displacement.
PT_KTB EQU 5                ; Truncate a resolved word to its low byte.
PT_KLB EQU 6                ; Apply LOW to a resolved word.
PT_KHB EQU 7                ; Apply HIGH to a resolved word.
; A is operand index 0..2 and IX is the validated instruction record. Return A as
; base patch kind and B as byte offset from the instruction start.

;@ROUTINE IN IX,A OUT A,B,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,DE,ZERO
PT_LOCAT:
    CP   3                  ; Only operand slots zero, one and two exist.
    JR   NC,.INVALID        ; Reject an index outside the instruction record.
    LD   E,A                ; Retain the operand index as a table offset.
    LD   D,0                ; Widen the index for sixteen-bit address arithmetic.
    PUSH DE                 ; Save the operand index across EN_LEN's DE clobber.
    CALL EN_LEN             ; Validate the form and obtain its encoded length.
    POP  DE                 ; Restore the operand index without changing carry.
    JR   C,.INVALID         ; A rejected form cannot have a patch field.
; EN_LEN supplies the total byte length without reading operand values.
    LD   B,A                ; Keep the instruction length for field placement.
    LD   HL,EN_OP0          ; Start at operand zero's class-field offset.
    ADD  HL,DE              ; Select the requested operand's class offset.
    PUSH IX                 ; Copy the instruction-record address into DE.
    POP  DE                 ; DE now addresses the validated record.
    ADD  HL,DE              ; HL points at the selected operand class byte.
    LD   A,(HL)             ; Read the operand class supplied by the parser.
; Patchable operand classes are the contiguous range (IX+d) through REL8. The
; table deliberately rejects PORT_C, which has no encoded value field.
    SUB  EN_IIX             ; Convert the first patchable class to index zero.
    CP   7                  ; Seven consecutive class slots feed the kind table.
    JR   NC,.INVALID        ; Classes outside that interval contain no field.
    LD   E,A                ; Retain the bounded patch-kind table index.
    LD   D,0                ; Widen it for address arithmetic.
    LD   HL,PT_OKIND        ; Address the class-to-patch-kind table.
    ADD  HL,DE              ; Select the entry for this operand class.
    LD   A,(HL)             ; Load its base patch kind; zero means no field.
    OR   A                  ; Test the table's rejection sentinel.
    JR   Z,.INVALID         ; PORT_C has no patchable value field.
    CP   PT_KDISP           ; Indexed displacement has a fixed field position.
    JR   Z,.DISPLACE        ; Return byte offset two for either index prefix.
; Ordinary byte fields end at length-1; little-endian word fields begin at
; length-2. This also locates an indexed instruction's trailing immediate.
    DEC  B                  ; Place a byte field at the final encoded byte.
    CP   PT_KINDW           ; A word occupies the final two encoded bytes.
    JR   NZ,.READY          ; Other kinds already have their correct offset.
    DEC  B                  ; Move from the high byte to the word's low byte.
.READY:
    OR   A                  ; Return success with carry clear and kind in A.
    RET                     ; B identifies the field within the instruction.
.INVALID:
    XOR  A                  ; Return no patch kind for an invalid request.
    SCF                     ; Mark the lookup as failed.
    RET                     ; B is undefined on failure.
.DISPLACE:
; Every DD/FD indexed-memory displacement is byte two. Ordinary forms are
; prefix, opcode, displacement; indexed-CB forms are prefix, CB, displacement,
; opcode.
    LD   B,2                ; Skip the index prefix and following opcode or CB.
    OR   A                  ; Preserve PT_KDISP while clearing carry.
    RET                     ; Return the fixed indexed-displacement position.
PT_OKIND:
; EN_IIX, EN_IIY, EN_MABS, EN_IMM8, EN_IMM16, EN_PORTC, EN_REL8.
    DB PT_KDISP,PT_KDISP    ; IX/IY memory operands patch their displacement.
    DB PT_KINDW,PT_KINDB,PT_KINDW ; Absolute, byte-immediate and word-immediate.
    DB 0,PT_KRELA           ; Port C has no field; REL8 patches relatively.
PT_CEND:
