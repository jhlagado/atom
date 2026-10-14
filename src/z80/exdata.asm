; Expression workspace: the value and operator stacks and per-parse state.

exRamLo: ; Begin fixed expression workspace.

; Persistent state for one parse. exHere gives '$' its statement address and
; exDoPub selects direct publication or caller-managed deferred publication.

exHere:     DW      0                   ; Current address used when parsing '$'.
exDoPub:   DB      0                    ; Nonzero permits successful symbol publication.

; Right/current record: signed 24-bit value or addend, deferred transform
; and six-byte exact packed key.

exRVal:    DS      3                    ; Right/current 24-bit value or signed addend.
exRForm:   DB      0                    ; Concrete/plain/LOW/HIGH result state.
exRKey:    DS      6                    ; Exact packed key for a deferred right result.

; Left value record loaded during binary reduction.

exLVal:    DS      3                    ; Left 24-bit value or signed addend.
exLForm:   DB      0                    ; Left concrete/deferred transform state.
exLKey:    DS      6                    ; Exact packed key for a deferred left operand.

; Operator record and a spare copy used while precedence reduction loads
; older operators from the stack.

exOper:    DB      0                    ; Current packed precedence/operation byte.
exOpPart:   DB      0                   ; Current operator's source-part ordinal.
exOpOff:    DW      0                   ; Current operator's source-byte offset.
exSaveOp:   DS      exOpLen             ; Saved incoming operator during reduction.

; exIdPart/exIdOff hold the name being resolved and are dead once exName
; returns, so multiply and divide reuse them. exSrcPos/exSrcOff hold the
; deferred symbol's anchor and are written only when a name becomes pending.

exIdPart:   DB      0                   ; Current name's source-part ordinal.
exIdOff:    DW      0                   ; Current name's source-byte offset.
exSrcPos:   DB      0                   ; Deferred symbol source-part ordinal.
exSrcOff:    DW      0                  ; Deferred symbol source-byte offset.
exCause:   DB      0                    ; Nested symbol status for diagnostics.
exRndCnt    EQU     exCause             ; Multiplication round count overlay.

; Bounded parser state. exInTerm is one when the grammar requires a primary and
; zero when it requires an operator or delimiter.

exValCnt:    DB      0                  ; Number of live value-stack entries.
exOpCnt:    DB      0                   ; Number of live operator-stack entries.
exNest:    DB      0                    ; Open-parenthesis nesting depth.
exInTerm:    DB      0                  ; Nonzero in the primary half of expression parsing.

; Multiply/divide overlay popped operand-key slots with magnitudes,
; accumulator and quotient. Both popped operands are concrete, so
; their keys are dead. The sign fields overlay the current-name position,
; which is dead between names; the deferred anchor is never overlaid.

exLSign     EQU     exIdPart            ; Saved left/dividend sign overlay.
exRSign     EQU     exIdOff             ; Saved right/divisor sign overlay.
exSign      EQU     exIdOff+1           ; Product/quotient sign overlay.
exDivSel    EQU     exRndCnt            ; Quotient-versus-remainder selector overlay.
exLAbs      EQU     exRKey              ; Left operand magnitude overlay.
exRAbs      EQU     exRKey+3            ; Right operand magnitude overlay.
exAccum     EQU     exLKey              ; Product/partial-remainder accumulator overlay.
exErrPos    EQU     exAccum             ; Public error-part field overlay.
exErrOff    EQU     exAccum+1           ; Public error-offset field overlay.
exQuot      EQU     exLKey+3            ; Division quotient overlay.

; Sixteen ten-byte values followed by sixteen four-byte operators.
; The complete fixed expression workspace is 266 bytes.

exVals:    DS      exValLen*exValCap    ; Sixteen complete value records.
exOps:   DS      exOpLen*exOpCap        ; Sixteen positioned operator records.
exRamHi: ; End fixed expression workspace.
