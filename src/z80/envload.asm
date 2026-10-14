enLdVBeg    EQU     $                   ; Begin the LD-form validation handlers.
.vLd: ; Validate LD by destination class.

; LD is the broadest family. Dispatch by destination, then check the source
; pairing and length. Index-half rules are strict:
; two half registers must belong to the same IX or IY family, and ordinary H/L
; cannot mix with an index half. Indexed memory uses the real H/L field.

    CALL .twoOper                       ; Reject a third operand before class dispatch.
    RET  C                              ; Propagate an operand-count failure.
    LD   A,(IX+enOp0)                   ; Load destination class for family dispatch.
    CALL enIsReg8                       ; Carry marks an ordinary eight-bit register.
    JR   C,.vLR8                        ; Validate its source in the byte-register path.
    LD   A,(IX+enOp0)                   ; Reload the class after the register test.
    CALL enIsHalf                       ; Test for an IXH, IXL, IYH or IYL destination.
    JP   C,.vLHalf                      ; Check its source and index family.
    LD   A,(IX+enOp0)                   ; Reload the class for the ordinary pair test.
    CALL enIsPair                       ; Carry marks BC, DE, HL or SP.
    JP   C,.vLR16                       ; Validate the source in the pair-load path.
    LD   A,(IX+enOp0)                   ; Check the remaining special destinations.
    CP   enRegIX                        ; Select the IX pair destination.
    JP   Z,.vLIxIy                      ; IX accepts immediate or absolute memory.
    CP   enRegIY                        ; Select the IY pair destination.
    JP   Z,.vLIxIy                      ; IY uses the same validation and length rules.
    CP   enRegI                         ; The I register has an A-only source form.
    JP   Z,.vLIrA                       ; Share it with the corresponding R form.
    CP   enRegR                         ; The R register also loads only from A.
    JP   Z,.vLIrA                       ; Route special-register validation together.
    CP   enMemAbs                       ; Test for absolute memory destination (nn).
    JP   Z,.vLMAbs                      ; Check its A or register-pair source.
    CP   enMemBC                        ; Test for the indirect destination (BC).
    JP   Z,.vLMemRrA                    ; Its only source is A.
    CP   enMemDE                        ; Test for the indirect destination (DE).
    JP   Z,.vLMemRrA                    ; Reuse the A-only indirect-store check.
    CP   enMemHL                        ; Test for the indirect destination (HL).
    JP   Z,.vLMemHl                     ; Check its register or immediate source.
    CALL enIsDisp                       ; Test for a displaced IX/IY destination.
    JP   C,.vLMemIdx                    ; Validate the source in the indexed-memory path.
    JP   .invalid                       ; Reject every other destination class.
.vLR8: ; Validate sources for an ordinary byte register.

; Byte registers load from r, n, (HL), indexed memory, or an index half.
; Only A loads from (nn), (BC), (DE), I, or R.

    LD   A,(IX+enOp1)                   ; Load the source class for this byte register.
    CALL enIsReg8                       ; Test for an ordinary byte-register source.
    JP   C,enDone1                      ; Two byte registers encode in one byte.
    LD   A,(IX+enOp1)                   ; Reload the source class after the predicate.
    CP   enImm8                         ; Check for an immediate byte source.
    JP   Z,enDone2                      ; The opcode is followed by its immediate byte.
    CP   enMemHL                        ; Check for the unprefixed (HL) source.
    JP   Z,enDone1                      ; A register loaded from (HL) uses one byte.
    CP   enMemAbs                       ; Check for an absolute address source.
    JR   Z,.vLAAbs                      ; Share the accumulator-only memory checks.
    CP   enMemBC                        ; Check for the accumulator's (BC) source form.
    JR   Z,.vLAMemRr                    ; Route indirect accumulator sources together.
    CP   enMemDE                        ; Check for the accumulator's (DE) source form.
    JR   Z,.vLAMemRr                    ; Reuse the same accumulator-only check.
    CP   enRegI                         ; Check for a special-register source.
    JR   Z,.vLAIr                       ; LD A,I is the only valid destination pairing.
    CP   enRegR                         ; Check for the other special-register source.
    JR   Z,.vLAIr                       ; LD A,R follows the same two-byte rule.
    CALL enIsDisp                       ; Test for an indexed-memory source.
    JP   C,enDone3                      ; Indexed source uses a three-byte form.
    LD   A,(IX+enOp1)                   ; Reload the source class for index-half testing.
    CALL enIsHalf                       ; Check for IXH, IXL, IYH or IYL.
    JP   NC,.invalid                    ; Reject sources outside the forms tested above.
    LD   A,(IX+enOp0)                   ; Load destination for the H/L collision test.
.vLNotHl: ; Reject real H/L mixed with an index-half operand.
    CP   enRegH                         ; H cannot encode as an index half in this form.
    JP   Z,.invalid                     ; Reject the mixed real-H/index-half pairing.
    CP   enRegL                         ; L has the same index-half collision.
    JP   Z,.invalid                     ; Reject the mixed real-L/index-half pairing.
    JP   enDone2                        ; Other byte registers use a prefixed opcode.
.vLAAbs: ; Check the accumulator-only absolute-memory load.
.vLAMemRr: ; Require A for absolute or BC/DE-indirect sources.
    LD   A,(IX+enOp0)                   ; Load the destination for A-only memory forms.
    CP   enRegA                         ; Absolute and (BC)/(DE) forms require A.
    JP   NZ,.invalid                    ; Reject any other byte-register destination.
    LD   A,(IX+enOp1)                   ; Recover the source class after checking A.
    CP   enMemAbs                       ; Only (nn) carries a two-byte address.
    JP   Z,enDone3                      ; Prefix-free opcode plus the absolute address.
    JP   enDone1                        ; The (BC)/(DE) forms contain only the opcode.
.vLAIr: ; Require A for an I/R source.
    LD   A,(IX+enOp0)                   ; Load the destination for LD A,I/R.
    CP   enRegA                         ; The special-register forms require A.
.vNzBad2: ; Reject mismatch or return the two-byte length.
    JP   NZ,.invalid                    ; Reject unless the preceding test matched.
    JP   enDone2                        ; Return the shared two-byte form length.
.vLHalf: ; Validate a compatible source for an index-half destination.

; Half-register forms need an index prefix and reject H/L collisions. XOR bit
; 3 below proves that source and destination belong to the same IX/IY family.

    LD   A,(IX+enOp1)                   ; Load source class for the half-register test.
    CALL enIsHalf                       ; Carry identifies an IX/IY half-register source.
    JR   C,.vLFamily                    ; Require both halves to belong to IX or IY.
    LD   A,(IX+enOp1)                   ; Reload source for the ordinary-register test.
    CALL enIsReg8                       ; Carry accepts a real eight-bit register source.
    JP   NC,.invalid                    ; Reject immediate and memory sources for a half.
    JR   .vLNotHl                       ; Apply the H/L collision test before accepting.
.vLFamily: ; Require both halves to belong to the same index family.
    LD   A,(IX+enOp0)                   ; Load the destination half class.
    LD   B,A                            ; B retains it while the source class is loaded.
    LD   A,(IX+enOp1)                   ; Load the source half class for comparison.
    XOR  B                              ; Bit 3 differs only between IX and IY classes.
    AND  $08                            ; Keep the family bit and discard half selection.
    JR   .vNzBad2                       ; Require the index families to match.
.vLR16: ; Validate sources for ordinary register pairs.

; Ordinary pairs accept immediate and absolute loads, LD SP,HL, and
; two pair-copy expansions from DE. IX/IY destinations branch separately.

    LD   A,(IX+enOp1)                   ; Load the source class for an ordinary pair.
    CP   enImm16                        ; Check for a 16-bit immediate value.
    JP   Z,enDone3                      ; Opcode plus the little-endian word takes three.
    CP   enMemAbs                       ; Check for an absolute memory address source.
    JR   Z,.vLRrAbs                     ; Pair size determines its encoded length.
    LD   A,(IX+enOp0)                   ; Load the destination for pair-copy forms.
    CP   enRegSP                        ; SP has dedicated HL/IX/IY source forms.
    JR   Z,.vLSp                        ; Check prefixed sources and their lengths.
    CP   enRegHL                        ; HL may use Atom's DE pair-copy form.
    JR   Z,.vLHlDe                      ; Route HL through the DE-source pair-copy check.
    CP   enRegBC                        ; BC has the matching pair-copy form.
    JR   Z,.vLBcDe                      ; Route BC through the same source-pair check.
    JP   .invalid                       ; Reject other pair-to-pair combinations.
.vLRrAbs: ; Select the absolute-memory pair length.
    LD   A,(IX+enOp0)                   ; Keep the destination pair for length selection.
    JR   .vPairLen                      ; HL is three bytes; other pairs take four.
.vLSp: ; Accept HL, IX or IY as the second operand.
    LD   A,(IX+enOp1)                   ; Load the second operand for the HL/IX/IY check.
    CP   enRegHL                        ; Test for the unprefixed HL form.
    JP   Z,enDone1                      ; An HL operand selects the one-byte form.
    JP   .vIxIy2                        ; Shared tail checks the prefixed IX/IY forms.
.vLHlDe: ; Validate the DE-to-HL pair-copy expansion.
.vLBcDe: ; Validate the DE-to-BC pair-copy expansion.
    LD   A,(IX+enOp1)                   ; Load the source for either pair-copy form.
    CP   enRegDE                        ; Both accepted forms take DE as their source.
    JP   .vZLen2                        ; Return two bytes for a match, else reject it.
.vLIxIy: ; Accept an immediate word or absolute source for IX/IY.
    LD   A,(IX+enOp1)                   ; Load the source for an IX/IY destination.
    CP   enImm16                        ; Check for a 16-bit immediate source.
    JP   Z,enDone4                      ; Prefix, opcode and immediate word take four.
    CP   enMemAbs                       ; Check for an absolute address source.
.vZLen4: ; Return four bytes only when the preceding class matched.
    JP   Z,enDone4                      ; The preceding accepted form takes four bytes.
    JP   .invalid                       ; Reject the source class that failed the test.
.vLIrA: ; Require A as the source for I/R.
    LD   A,(IX+enOp1)                   ; Load the source for the special I/R register.
    CP   enRegA                         ; The only valid source is A.
    JP   .vZLen2                        ; Return two bytes on a match.
.vLMAbs: ; Validate an accumulator or pair stored to (nn).
    LD   A,(IX+enOp1)                   ; Load the source for absolute memory (nn).
    CP   enRegA                         ; A stores directly to the absolute address.
    JP   Z,enDone3                      ; Opcode plus the two-byte address takes three.
    CALL enIsPair                       ; Test whether the source is an ordinary pair.
    JR   NC,.vLAbsIdx                   ; IX and IY need the separate prefixed check.
.vPairLen: ; Select direct HL or prefixed pair-memory length.
    CP   enRegHL                        ; HL uses the unprefixed absolute-memory form.
    JP   Z,enDone3                      ; Its opcode plus address take three bytes.
    JP   enDone4                        ; Other accepted pairs need a prefix byte.
.vLAbsIdx: ; Accept an index pair stored to (nn).
    CP   enRegIX                        ; Check for an IX pair source.
    JP   Z,enDone4                      ; DD prefix, opcode and address take four bytes.
    CP   enRegIY                        ; Otherwise check for an IY pair source.
    JR   .vZLen4                        ; Reuse the common four-byte acceptance tail.
.vLMemRrA: ; Require A as the source for (BC)/(DE).
    LD   A,(IX+enOp1)                   ; Load the source for destination (BC) or (DE).
    CP   enRegA                         ; Both indirect stores require A.
    JP   .vZLen1                        ; Return one byte on a match.
.vLMemHl: ; Accept a byte register or immediate stored to (HL).
    LD   A,(IX+enOp1)                   ; Load the source for destination (HL).
    CALL enIsReg8                       ; Carry accepts an ordinary byte register.
    JP   C,enDone1                      ; A register stored through HL takes one byte.
    CP   enImm8                         ; Otherwise check for an immediate byte source.
    JP   .vZLen2                        ; Return two bytes if it matches.
.vLMemIdx: ; Accept a byte register or immediate indexed store.
    LD   A,(IX+enOp1)                   ; Load the source for destination (IX/IY+d).
    CALL enIsReg8                       ; Carry accepts an ordinary byte register.
    JP   C,enDone3                      ; Prefix, opcode and displacement take three.
    CP   enImm8                         ; Otherwise check for an immediate byte source.
    JR   .vZLen4                        ; That form adds a fourth byte for the value.
enLdVEnd    EQU     $                   ; End the LD-form validation handlers.
