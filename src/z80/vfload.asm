EN_LVBEG    EQU     $                   ; Begin the LD-form validation handlers.
.VLD: ; Validate LD by destination class.

; LD is the broadest family. Dispatch by destination, then check the source
; pairing and length. Index-half rules are strict:
; two half registers must belong to the same IX or IY family, and ordinary H/L
; cannot mix with an index half. Indexed memory uses the real H/L field.

    CALL .TWOOPER                       ; Reject a third operand before class dispatch.
    RET  C                              ; Propagate an operand-count failure.
    LD   A,(IX+EN_OP0)                  ; Load destination class for family dispatch.
    CALL EN_IR8                         ; Carry marks an ordinary eight-bit register.
    JR   C,.VLR8                        ; Validate its source in the byte-register path.
    LD   A,(IX+EN_OP0)                  ; Reload the class after the register test.
    CALL EN_IHALF                       ; Test for an IXH, IXL, IYH or IYL destination.
    JP   C,.VLHALF                      ; Check its source and index family.
    LD   A,(IX+EN_OP0)                  ; Reload the class for the ordinary pair test.
    CALL EN_IR16                        ; Carry marks BC, DE, HL or SP.
    JP   C,.VLR16                       ; Validate the source in the pair-load path.
    LD   A,(IX+EN_OP0)                  ; Check the remaining special destinations.
    CP   EN_IX                          ; Select the IX pair destination.
    JP   Z,.VLIXIY                      ; IX accepts immediate or absolute memory.
    CP   EN_IY                          ; Select the IY pair destination.
    JP   Z,.VLIXIY                      ; IY uses the same validation and length rules.
    CP   EN_I                           ; The I register has an A-only source form.
    JP   Z,.VLIRA                       ; Share it with the corresponding R form.
    CP   EN_R                           ; The R register also loads only from A.
    JP   Z,.VLIRA                       ; Route special-register validation together.
    CP   EN_MABS                        ; Test for absolute memory destination (nn).
    JP   Z,.VLMABS                      ; Check its A or register-pair source.
    CP   EN_MEMBC                       ; Test for the indirect destination (BC).
    JP   Z,.VLMEMRRA                    ; Its only source is A.
    CP   EN_MEMDE                       ; Test for the indirect destination (DE).
    JP   Z,.VLMEMRRA                    ; Reuse the A-only indirect-store check.
    CP   EN_MEMHL                       ; Test for the indirect destination (HL).
    JP   Z,.VLMEMHL                     ; Check its register or immediate source.
    CALL EN_IDISP                       ; Test for a displaced IX/IY destination.
    JP   C,.VLMEMIDX                    ; Validate the source in the indexed-memory path.
    JP   .INVALID                       ; Reject every other destination class.
.VLR8: ; Validate sources for an ordinary byte register.

; Byte registers load from r, n, (HL), indexed memory, or an index half.
; Only A loads from (nn), (BC), (DE), I, or R.

    LD   A,(IX+EN_OP1)                  ; Load the source class for this byte register.
    CALL EN_IR8                         ; Test for an ordinary byte-register source.
    JP   C,EN_D1                        ; Two byte registers encode in one byte.
    LD   A,(IX+EN_OP1)                  ; Reload the source class after the predicate.
    CP   EN_IMM8                        ; Check for an immediate byte source.
    JP   Z,EN_D2                        ; The opcode is followed by its immediate byte.
    CP   EN_MEMHL                       ; Check for the unprefixed (HL) source.
    JP   Z,EN_D1                        ; A register loaded from (HL) uses one byte.
    CP   EN_MABS                        ; Check for an absolute address source.
    JR   Z,.VLAABS                      ; Share the accumulator-only memory checks.
    CP   EN_MEMBC                       ; Check for the accumulator's (BC) source form.
    JR   Z,.VLAMEMRR                    ; Route indirect accumulator sources together.
    CP   EN_MEMDE                       ; Check for the accumulator's (DE) source form.
    JR   Z,.VLAMEMRR                    ; Reuse the same accumulator-only check.
    CP   EN_I                           ; Check for a special-register source.
    JR   Z,.VLAIR                       ; LD A,I is the only valid destination pairing.
    CP   EN_R                           ; Check for the other special-register source.
    JR   Z,.VLAIR                       ; LD A,R follows the same two-byte rule.
    CALL EN_IDISP                       ; Test for an indexed-memory source.
    JP   C,EN_D3                        ; Indexed source uses a three-byte form.
    LD   A,(IX+EN_OP1)                  ; Reload the source class for index-half testing.
    CALL EN_IHALF                       ; Check for IXH, IXL, IYH or IYL.
    JP   NC,.INVALID                    ; Reject sources outside the forms tested above.
    LD   A,(IX+EN_OP0)                  ; Load destination for the H/L collision test.
.VLNOTHL: ; Reject real H/L mixed with an index-half operand.
    CP   EN_H                           ; H cannot encode as an index half in this form.
    JP   Z,.INVALID                     ; Reject the mixed real-H/index-half pairing.
    CP   EN_L                           ; L has the same index-half collision.
    JP   Z,.INVALID                     ; Reject the mixed real-L/index-half pairing.
    JP   EN_D2                          ; Other byte registers use a prefixed opcode.
.VLAABS: ; Check the accumulator-only absolute-memory load.
.VLAMEMRR: ; Require A for absolute or BC/DE-indirect sources.
    LD   A,(IX+EN_OP0)                  ; Load the destination for A-only memory forms.
    CP   EN_A                           ; Absolute and (BC)/(DE) forms require A.
    JP   NZ,.INVALID                    ; Reject any other byte-register destination.
    LD   A,(IX+EN_OP1)                  ; Recover the source class after checking A.
    CP   EN_MABS                        ; Only (nn) carries a two-byte address.
    JP   Z,EN_D3                        ; Prefix-free opcode plus the absolute address.
    JP   EN_D1                          ; The (BC)/(DE) forms contain only the opcode.
.VLAIR: ; Require A for an I/R source.
    LD   A,(IX+EN_OP0)                  ; Load the destination for LD A,I/R.
    CP   EN_A                           ; The special-register forms require A.
.VNZBAD2: ; Reject mismatch or return the two-byte length.
    JP   NZ,.INVALID                    ; Reject unless the preceding test matched.
    JP   EN_D2                          ; Return the shared two-byte form length.
.VLHALF: ; Validate a compatible source for an index-half destination.

; Half-register forms need an index prefix and reject H/L collisions. XOR bit
; 3 below proves that source and destination belong to the same IX/IY family.

    LD   A,(IX+EN_OP1)                  ; Load source class for the half-register test.
    CALL EN_IHALF                       ; Carry identifies an IX/IY half-register source.
    JR   C,.VLFAMILY                    ; Require both halves to belong to IX or IY.
    LD   A,(IX+EN_OP1)                  ; Reload source for the ordinary-register test.
    CALL EN_IR8                         ; Carry accepts a real eight-bit register source.
    JP   NC,.INVALID                    ; Reject immediate and memory sources for a half.
    JR   .VLNOTHL                       ; Apply the H/L collision test before accepting.
.VLFAMILY: ; Require both halves to belong to the same index family.
    LD   A,(IX+EN_OP0)                  ; Load the destination half class.
    LD   B,A                            ; B retains it while the source class is loaded.
    LD   A,(IX+EN_OP1)                  ; Load the source half class for comparison.
    XOR  B                              ; Bit 3 differs only between IX and IY classes.
    AND  $08                            ; Keep the family bit and discard half selection.
    JR   .VNZBAD2                       ; Require the index families to match.
.VLR16: ; Validate sources for ordinary register pairs.

; Ordinary pairs accept immediate and absolute loads, LD SP,HL, and
; two pair-copy expansions from DE. IX/IY destinations branch separately.

    LD   A,(IX+EN_OP1)                  ; Load the source class for an ordinary pair.
    CP   EN_IMM16                       ; Check for a 16-bit immediate value.
    JP   Z,EN_D3                        ; Opcode plus the little-endian word takes three.
    CP   EN_MABS                        ; Check for an absolute memory address source.
    JR   Z,.VLRRABS                     ; Pair size determines its encoded length.
    LD   A,(IX+EN_OP0)                  ; Load the destination for pair-copy forms.
    CP   EN_SP                          ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.VLSP                        ; Check prefixed sources and their lengths.
    CP   EN_HL                          ; HL may use Atom's DE pair-copy form.
    JR   Z,.VLHLDE                      ; Route HL through the DE-source pair-copy check.
    CP   EN_BC                          ; BC has the matching pair-copy form.
    JR   Z,.VLBCDE                      ; Route BC through the same source-pair check.
    JP   .INVALID                       ; Reject other pair-to-pair combinations.
.VLRRABS: ; Select the absolute-memory pair length.
    LD   A,(IX+EN_OP0)                  ; Keep the destination pair for length selection.
    JR   .VPAIRLEN                      ; HL is three bytes; other pairs take four.
.VLSP: ; Accept HL, IX or IY as the second operand.
    LD   A,(IX+EN_OP1)                  ; Load the second operand for the HL/IX/IY check.
    CP   EN_HL                          ; Test for the unprefixed HL form.
    JP   Z,EN_D1                        ; An HL operand selects the one-byte form.
    JP   .VIXIY2                        ; Shared tail checks the prefixed IX/IY forms.
.VLHLDE: ; Validate the DE-to-HL pair-copy expansion.
.VLBCDE: ; Validate the DE-to-BC pair-copy expansion.
    LD   A,(IX+EN_OP1)                  ; Load the source for either pair-copy form.
    CP   EN_DE                          ; Both accepted forms take DE as their source.
    JP   .VZLEN2                        ; Return two bytes for a match, else reject it.
.VLIXIY: ; Accept an immediate word or absolute source for IX/IY.
    LD   A,(IX+EN_OP1)                  ; Load the source for an IX/IY destination.
    CP   EN_IMM16                       ; Check for a 16-bit immediate source.
    JP   Z,EN_D4                        ; Prefix, opcode and immediate word take four.
    CP   EN_MABS                        ; Check for an absolute address source.
.VZLEN4: ; Return four bytes only when the preceding class matched.
    JP   Z,EN_D4                        ; The preceding accepted form takes four bytes.
    JP   .INVALID                       ; Reject the source class that failed the test.
.VLIRA: ; Require A as the source for I/R.
    LD   A,(IX+EN_OP1)                  ; Load the source for the special I/R register.
    CP   EN_A                           ; The only valid source is A.
    JP   .VZLEN2                        ; Return two bytes on a match.
.VLMABS: ; Validate an accumulator or pair stored to (nn).
    LD   A,(IX+EN_OP1)                  ; Load the source for absolute memory (nn).
    CP   EN_A                           ; A stores directly to the absolute address.
    JP   Z,EN_D3                        ; Opcode plus the two-byte address takes three.
    CALL EN_IR16                        ; Test whether the source is an ordinary pair.
    JR   NC,.VLABSIDX                   ; IX and IY need the separate prefixed check.
.VPAIRLEN: ; Select direct HL or prefixed pair-memory length.
    CP   EN_HL                          ; HL uses the unprefixed absolute-memory form.
    JP   Z,EN_D3                        ; Its opcode plus address take three bytes.
    JP   EN_D4                          ; Other accepted pairs need a prefix byte.
.VLABSIDX: ; Accept an index pair stored to (nn).
    CP   EN_IX                          ; Check for an IX pair source.
    JP   Z,EN_D4                        ; DD prefix, opcode and address take four bytes.
    CP   EN_IY                          ; Otherwise check for an IY pair source.
    JR   .VZLEN4                        ; Reuse the common four-byte acceptance tail.
.VLMEMRRA: ; Require A as the source for (BC)/(DE).
    LD   A,(IX+EN_OP1)                  ; Load the source for destination (BC) or (DE).
    CP   EN_A                           ; Both indirect stores require A.
    JP   .VZLEN1                        ; Return one byte on a match.
.VLMEMHL: ; Accept a byte register or immediate stored to (HL).
    LD   A,(IX+EN_OP1)                  ; Load the source for destination (HL).
    CALL EN_IR8                         ; Carry accepts an ordinary byte register.
    JP   C,EN_D1                        ; A register stored through HL takes one byte.
    CP   EN_IMM8                        ; Otherwise check for an immediate byte source.
    JP   .VZLEN2                        ; Return two bytes if it matches.
.VLMEMIDX: ; Accept a byte register or immediate indexed store.
    LD   A,(IX+EN_OP1)                  ; Load the source for destination (IX/IY+d).
    CALL EN_IR8                         ; Carry accepts an ordinary byte register.
    JP   C,EN_D3                        ; Prefix, opcode and displacement take three.
    CP   EN_IMM8                        ; Otherwise check for an immediate byte source.
    JR   .VZLEN4                        ; That form adds a fourth byte for the value.
EN_LVEND    EQU     $                   ; End the LD-form validation handlers.
