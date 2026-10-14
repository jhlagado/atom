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
;    fixField  map an operand index to its encoded field and patch kind

fixBeg: ; Begin patch-field code and kind constants.

; Patch kinds stored in the low three bits of a pending record. syAnchor may
; occupy the high bit without changing this value.

fixByte     EQU     1                   ; Replace one encoded byte.
fixWord     EQU     2                   ; Replace one little-endian word.
fixRel      EQU     3                   ; Replace one PC-relative displacement.
fixDisp     EQU     4                   ; Replace one IX/IY displacement.
fixTrunc    EQU     5                   ; Truncate a resolved word to its low byte.
fixLow      EQU     6                   ; Apply LOW to a resolved word.
fixHigh     EQU     7                   ; Apply HIGH to a resolved word.

;@ROUTINE IN IX,A OUT A,B,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; A is operand index 0..2. IX points at a validated record. Return A as
; base patch kind and B as byte offset from the instruction start.

fixField: ; Locate operand A's patch field within validated record IX.
    CP   3                              ; Only operand slots zero, one and two exist.
    JR   NC,.invalid                    ; Reject an index outside the instruction record.
    LD   E,A                            ; Retain the operand index as a table offset.
    LD   D,0                            ; Extend the index to 16 bits.
    PUSH DE                             ; Save the index across enLength.
    CALL enLength                       ; Validate the form and obtain its encoded length.
    POP  DE                             ; Restore the index, preserving carry.
    JR   C,.invalid                     ; A rejected form cannot have a patch field.

; enLength supplies the total byte length without reading operand values.

    LD   B,A                            ; Keep the instruction length for field placement.
    LD   HL,enOp0                       ; Start at operand zero's class-field offset.
    ADD  HL,DE                          ; Select the requested operand's class offset.
    PUSH IX                             ; Copy the instruction-record address into DE.
    POP  DE                             ; DE now addresses the validated record.
    ADD  HL,DE                          ; HL points at the selected operand class byte.
    LD   A,(HL)                         ; Read the operand class supplied by the parser.

; Patchable operand classes are the contiguous range (IX+d) through REL8. The
; table deliberately rejects PORT_C, which has no encoded value field.

    SUB  enDispIX                       ; Convert the first patchable class to index zero.
    CP   7                              ; Seven class slots feed the kind table.
    JR   NC,.invalid                    ; Classes outside that interval contain no field.
    LD   E,A                            ; Retain the bounded patch-kind table index.
    LD   D,0                            ; Widen it for address arithmetic.
    LD   HL,.kindTab                    ; Address the class-to-patch-kind table.
    ADD  HL,DE                          ; Select the entry for this operand class.
    LD   A,(HL)                         ; Load its base patch kind. Zero means no field.
    OR   A                              ; Test the table's rejection sentinel.
    JR   Z,.invalid                     ; PORT_C has no patchable value field.
    CP   fixDisp                        ; Indexed displacement has a fixed field position.
    JR   Z,.displace                    ; Return byte offset two for either index prefix.

; Ordinary byte fields end at length-1. Little-endian word fields begin at
; length-2. This also locates an indexed instruction's trailing immediate.

    DEC  B                              ; Place a byte field at the final encoded byte.
    CP   fixWord                        ; A word occupies the final two encoded bytes.
    JR   NZ,.ready                      ; Other kinds already have their correct offset.
    DEC  B                              ; Move from the high byte to the word's low byte.
.ready: ; Return the selected patch kind and encoded offset with carry clear.
    OR   A                              ; Return success with carry clear and kind in A.
    RET                                 ; B identifies the field within the instruction.
.invalid: ; Return no field with carry set for an invalid request.
    XOR  A                              ; Return no patch kind for an invalid request.
    SCF                                 ; Mark the lookup as failed.
    RET                                 ; B is undefined on failure.
.displace: ; Return fixed offset two for an indexed-memory displacement.

; Every DD/FD indexed-memory displacement is byte two. Ordinary forms are
; prefix, opcode, displacement. Indexed-CB forms are prefix, CB, displacement,
; opcode.

    LD   B,2                            ; Skip the index prefix and opcode or CB.
    OR   A                              ; Preserve fixDisp while clearing carry.
    RET                                 ; Return the fixed indexed-displacement position.
.kindTab: ; Map the contiguous patchable operand classes to base patch kinds.

; enDispIX, enDispIY, enMemAbs, enImm8, enImm16, enPortC, enRel8.

    DB   fixDisp,fixDisp                ; IX/IY memory operands patch their displacement.
    DB   fixWord,fixByte,fixWord        ; Absolute memory, byte immediate and word immediate.
    DB   0,fixRel                       ; Port C has no field. REL8 patches relatively.
fixEnd: ; End patch-field code and its immutable kind table.
