;==============================================================================
;  Streaming tokenizer
;==============================================================================
;
;  PURPOSE
;  -------
;  Pull one token at a time from a prepared source part. The interface uses only
;  a byte range and part ordinal, never a file. Every source byte is obtained
;  through TK_SREAD, allowing the same core to read memory, host-backed snapshots,
;  banked storage or an operating-system adapter.
;
;  PUBLIC ENTRY POINTS
;  -------------------
;
;+---------------------------------------------------------------------------+
;| TK_RESET - Select a source part and begin at logical offset zero.          |
;|                                                                           |
;| Entry: A = part ordinal; HL = source begin; DE = source end, exclusive.    |
;| Result: Carry clear, A = 0 and IX -> token record.                         |
;| Error: Carry set and A = TK_SBSRA if the range wraps backwards.           |
;| Atomicity: A rejected range changes no tokenizer state.                    |
;+---------------------------------------------------------------------------+
;
;+---------------------------------------------------------------------------+
;| TK_NEXT - Return the next token from the selected part.                   |
;|                                                                           |
;| Result: Carry clear, A = token kind and IX -> nine-byte token record.      |
;| Error: Carry set and A = TK_S* lexical status. TK_EPART/TK_EOFF locate    |
;|        the failed token. Previous record fields remain unchanged.          |
;| Lifetime: The returned lexeme pointer is valid only until the next call.  |
;+---------------------------------------------------------------------------+
;
;  TOKEN RECORD
;  ------------
;
;  +0   byte   token kind
;  +1   byte   source-part ordinal
;  +2   word   byte offset from the beginning of that part
;  +4   word   pointer into TK_TBUF
;  +6   byte   raw lexeme length
;  +7   word   decoded numeric value, otherwise zero
;
;  Names keep their source capitalisation. Mnemonic, directive and symbol
;  consumers perform case folding while recognising or packing them.
;
;  LINE BOUNDARIES
;  ---------------
;
;  Blank and comment-only lines emit no EOL. A non-empty final line without a
;  physical line ending emits one synthetic EOL before repeatable EOF. This
;  prevents the last token of one source part joining the first token of the
;  next part.
;
;  SOURCE SERVICE SEAM
;  -------------------
;
;  TK_SREAD receives A = part ordinal and HL = logical byte offset. The checked
;  core's implementation below reads the reset range directly. Platform builds
;  replace only the explicitly marked body with a jump to their provider.
;  Every offset below the validated part length must return successfully. This
;  seam has no read-error channel: TK_SPEEK reserves carry for end of part.

TK_CBEG:                       ; Begin executable tokenizer code and constants.

; Published token kinds. Punctuation values are also used by expression parsing.

TK_EOF EQU 0                   ; Repeatable end-of-source-part token.
TK_EOL EQU 1                   ; End of a non-empty source line, physical or synthetic.
TK_NAME EQU 2                  ; Name or private-name lexeme.
TK_DIR EQU 3                   ; Reserved directive kind retained for statement diagnostics.
TK_NUMBE EQU 4                 ; Decoded sixteen-bit numeric literal.
TK_STRIN EQU 5                 ; Raw quoted string lexeme.
TK_COMMA EQU 6                 ; Comma punctuation.
TK_COLON EQU 7                 ; Colon punctuation.
TK_LPARE EQU 8                 ; Left parenthesis punctuation.
TK_RPARE EQU 9                 ; Right parenthesis punctuation.
TK_PLUS EQU 10                 ; Addition or unary-plus operator.
TK_MINUS EQU 11                ; Subtraction or unary-minus operator.
TK_STAR EQU 12                 ; Multiplication operator.
TK_SLASH EQU 13                ; Division operator.
TK_PERCE EQU 14                ; Remainder operator when not a binary literal.
TK_AMPER EQU 15                ; Bitwise AND operator.
TK_CARET EQU 16                ; Bitwise XOR operator.
TK_PIPE EQU 17                 ; Bitwise OR operator.
TK_TILDE EQU 18                ; Bitwise complement operator.
TK_APOST EQU 19                ; Standalone apostrophe punctuation.
TK_LSHIF EQU 20                ; Two-character left-shift operator.
TK_RSHIF EQU 21                ; Two-character right-shift operator.
TK_CUR EQU 22                  ; Current logical output address marker.

; Lexical failure statuses returned with carry set.

TK_SIB EQU 1                   ; Invalid input byte.
TK_SNTLO EQU 2                 ; Name exceeds its accepted source length.
TK_SINUM EQU 3                 ; Malformed numeric literal.
TK_SNOVE EQU 4                 ; Numeric value exceeds sixteen bits.
TK_SUSTR EQU 5                 ; Unterminated string literal.
TK_SIESC EQU 6                 ; Unsupported string or character escape.
TK_SSTLO EQU 7                 ; String lexeme exceeds its byte limit.
TK_SBSRA EQU 8                 ; Reversed source range supplied to reset.
TK_SUDIR EQU 9                 ; Host preprocessor directive reached native Atom.
TK_SUCHA EQU 10                ; Unterminated character literal.
TK_SICHA EQU 11                ; Invalid character literal contents.

; Nine-byte token-record field offsets and total size.

TK_KOFF EQU 0                  ; Token-kind byte offset.
TK_POFF EQU 1                  ; Source-part ordinal byte offset.
TK_SOFF EQU 2                  ; Source-relative token offset word.
TK_LOFF EQU 4                  ; Lexeme-buffer pointer word.
TK_LOFF1 EQU 6                 ; Raw lexeme-length byte.
TK_VOFF EQU 7                  ; Decoded numeric-value word.
TK_RECB EQU 9                  ; Total published token-record size.

;@ROUTINE IN A,HL,DE OUT A,IX,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Preserve all proposed state until end - begin proves the half-open range does
; not wrap. HL becomes the part length when subtraction succeeds.

TK_RESET:
    PUSH AF                        ; Preserve the proposed source-part ordinal.
    PUSH HL                        ; Preserve the proposed range start.
    PUSH DE                        ; Preserve the proposed exclusive range end.
    EX   DE,HL                     ; Put end in HL and start in DE.
    OR   A                         ; Clear carry before unsigned range subtraction.
    SBC  HL,DE                    ; Calculate the proposed part length.
    JR   C,.RBSRANGE               ; Reject an end below the start atomically.

; Commit the validated length, then recover end, begin and ordinal from stack.

    LD   (TK_SEND),HL              ; Publish the validated source length.
    POP  DE                        ; Restore the caller's end value for its contract.
    POP  HL                        ; Restore and retain the absolute memory base.
    POP  AF                        ; Restore the source-part ordinal.
    LD   (TK_SPART),A              ; Publish the part used in tokens and service reads.
    LD   (TK_SRCBA),HL             ; Publish the memory-backed fallback base.

; Both physical read position and logical diagnostic offset begin at zero.

    XOR  A                         ; Construct the cleared offset and state value.
    LD   (TK_SCURS),A              ; Clear the physical read cursor low byte.
    LD   (TK_SCURS+1),A            ; Clear its high byte.
    LD   (TK_SOSTA),A              ; Clear the logical diagnostic offset low byte.
    LD   (TK_SOSTA+1),A            ; Clear its high byte.

; No token has appeared on the line, no synthetic EOL is pending and no error
; or previous record kind survives into the new part.

    LD   (TK_LHTOK),A              ; Mark the new physical line as token-free.
    LD   (TK_EPEND),A              ; Clear the synthetic-EOL pending flag.
    LD   (TK_ESTAT),A              ; Clear the previous lexical error status.
    LD   (TK_REC+TK_KOFF),A        ; Seed the public record with repeatable EOF.
    LD   IX,TK_REC                 ; Return the stable token-record address.
    RET                            ; Report reset success with carry clear.
.RBSRANGE:                     ; Unwind a reversed proposed interval.

; Restore the caller's proposed values without publishing any of them.

    POP  DE                        ; Restore the proposed exclusive end.
    POP  HL                        ; Restore the proposed start.
    POP  AF                        ; Restore the proposed part ordinal.
.BSRANGE:                      ; Return the public bad-source-range status.
    LD   A,TK_SBSRA                ; Select the reversed-range diagnostic.
    SCF                            ; Mark reset as failed.
    RET                            ; Leave all published tokenizer state unchanged.

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Compare the current relative cursor with the validated part length. Equality
; is EOF; a greater cursor is impossible while tokenizer invariants hold.

TK_SPEEK:
    LD   HL,(TK_SCURS)             ; Load the relative physical read cursor.
    LD   DE,(TK_SEND)              ; Load the validated part length.
    OR   A                         ; Clear carry before cursor-minus-length.
    SBC  HL,DE                    ; Set zero exactly at end of part.
    JR   Z,.SPEOF                  ; Report EOF without calling the source service.
    ADD  HL,DE                    ; Restore the relative cursor value in HL.
.SRCPEEKB:                     ; Invoke the configured source-byte provider.

; The service receives the part ordinal and logical offset. PEEK never advances
; either cursor or copies the returned byte into the token buffer.

    LD   A,(TK_SPART)              ; Supply the current source-part ordinal.
    CALL TK_SREAD                  ; Read the byte at A:HL without consuming it.
    OR   A                         ; Normalize carry clear while preserving the byte.
    RET                            ; Return the source byte in A.
.SPEOF:                        ; Report end of the current half-open interval.
    SCF                            ; Distinguish EOF from a real byte.
    RET                            ; Leave both source cursors unchanged.
;@@ATOM_SOURCE_READ_BEGIN@@

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Memory-backed fallback: translate the logical offset to an absolute address.

TK_SREAD:
    LD   DE,(TK_SRCBA)             ; Load the checked-core memory range base.
    ADD  HL,DE                    ; Translate the logical offset to a memory address.
    LD   A,(HL)                    ; Fetch the requested immutable source byte.
    OR   A                         ; Return it with carry clear and zero classified.
    RET                            ; Preserve no provider state in the tokenizer.
;@@ATOM_SOURCE_READ_END@@

;@ROUTINE OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Preserve BC because callers often use it as a length, radix or loop counter.

TK_STAKE:
    PUSH BC                        ; Preserve caller length, radix or loop state.
    CALL TK_SPEEK                  ; Read the current byte without advancing.
    JR   C,.STEOF                  ; Report EOF without changing cursors or buffer.

; Save the byte while both cursors advance. TK_SCURS selects the next source
; byte; TK_SOSTA is the logical offset reported for the next token.

    LD   D,A                       ; Preserve the consumed byte during cursor updates.
    LD   HL,(TK_SCURS)             ; Load the physical read cursor.
    INC  HL                        ; Advance to the next source byte.
    LD   (TK_SCURS),HL             ; Publish the new physical cursor.
    LD   HL,(TK_SOSTA)             ; Load the logical diagnostic offset.
    INC  HL                        ; Advance its one-byte source position.
    LD   (TK_SOSTA),HL             ; Publish the next token-start offset.

; Append the byte at TK_TBUF + current count. TK_STAKE itself permits the count
; to wrap: bounded token scanners reject the 256th byte immediately afterwards,
; while comment scanning deliberately discards buffered bytes and needs no length.

    LD   A,(TK_BCNT)               ; Load the tentative token's raw byte count.
    LD   C,A                       ; Move it into the low offset byte.
    LD   B,0                       ; Zero-extend the buffer index.
    LD   HL,TK_TBUF                ; Point at the start of the token buffer.
    ADD  HL,BC                    ; Select the next tentative byte slot.
    LD   A,D                       ; Restore the consumed source byte.
    LD   (HL),A                    ; Append it to the tentative lexeme.

; TK_PREV supports the apostrophe ambiguity after a name such as AF'.

    LD   (TK_PREV),A               ; Retain it for quote/apostrophe disambiguation.
    LD   A,(TK_BCNT)               ; Reload the raw byte count.
    INC  A                         ; Include the newly appended byte, possibly wrapping.
    LD   (TK_BCNT),A               ; Publish the new tentative count.
    LD   A,D                       ; Return the consumed byte to the caller.
    POP  BC                        ; Restore caller loop/radix state.

; Return the consumed byte and normalise carry clear through OR.

    OR   A                         ; Normalize carry clear and classify zero.
    RET                            ; Return after both cursors and buffer agree.
.STEOF:                        ; Unwind a consume attempted at EOF.
    POP  BC                        ; Restore caller state.
    SCF                            ; Report that no byte was consumed.
    RET                            ; Leave all tokenizer cursors unchanged.

;@ROUTINE OUT CARRY,ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Start a tentative token. Until TK_CMT runs, the public record still describes
; the preceding successful token.

TK_BEG:
    LD   HL,TK_TBUF                ; Point tentative lexeme storage at its fixed buffer.
    LD   (TK_SPTR),HL              ; Save the pointer for later record publication.
    LD   HL,(TK_SOSTA)             ; Capture the current logical source offset.
    LD   (TK_SOFF1),HL             ; Preserve it as this token's diagnostic start.

; Clear raw byte count, tentative length and decoded numeric value.

    XOR  A                         ; Construct cleared tentative token fields.
    LD   (TK_BCNT),A               ; Clear the number of consumed raw bytes.
    LD   (TK_SLEN),A               ; Clear the publishable lexeme length.
    LD   (TK_SVAL),A               ; Clear the decoded value low byte.
    LD   (TK_SVAL+1),A             ; Clear its high byte.
    RET                            ; Leave the previous public record untouched.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,SIGN,PARITY,HALFCARRY,ZERO
; Publish all record fields only after the scanner has accepted the token.

TK_CMT:
    LD   (TK_REC+TK_KOFF),A        ; Publish the accepted token kind.
    LD   A,(TK_SPART)              ; Load the current source-part ordinal.
    LD   (TK_REC+TK_POFF),A        ; Publish the token's part identity.
    LD   HL,(TK_SOFF1)             ; Load the saved tentative token offset.
    LD   (TK_REC+TK_SOFF),HL       ; Publish its source-relative position.
    LD   HL,(TK_SPTR)              ; Load the tentative lexeme-buffer pointer.
    LD   (TK_REC+TK_LOFF),HL       ; Publish the lexeme location.
    LD   A,(TK_SLEN)               ; Load the accepted raw lexeme length.
    LD   (TK_REC+TK_LOFF1),A       ; Publish its one-byte length.
    LD   HL,(TK_SVAL)              ; Load the decoded numeric value or zero.
    LD   (TK_REC+TK_VOFF),HL       ; Publish the token value word.

; Return a stable record pointer and mirror its kind into A. OR also clears carry.

    LD   IX,TK_REC                 ; Return the stable public record address.
    LD   A,(TK_REC+TK_KOFF)        ; Mirror its published kind into A.
    OR   A                         ; Clear carry and classify EOF kind zero.
    RET                            ; Return the complete token atomically.

;@ROUTINE IN A OUT A,IX,CARRY CLOBBERS HL,ZERO,SIGN,PARITY,HALFCARRY
; A completed non-EOL token marks this physical line as non-empty.

TK_FIN:
    PUSH AF                        ; Preserve the accepted token kind.
    LD   A,1                       ; Construct the line-has-token state.
    LD   (TK_LHTOK),A              ; Ensure the following line ending emits EOL.
    POP  AF                        ; Restore the accepted token kind.
    JR   TK_CMT                   ; Publish the complete token record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS HL,HALFCARRY,SIGN,PARITY,ZERO
; Retain the lexical status, then rewind both cursors to the token's first byte.
; This makes failure atomic with respect to source consumption and leaves the
; previously published token record untouched.

TK_FAIL:
    LD   (TK_ESTAT),A              ; Publish the detailed lexical status.
    LD   HL,(TK_SOFF1)             ; Reload the tentative token's first offset.
    LD   (TK_SCURS),HL             ; Rewind physical reads to that byte.
    LD   (TK_SOSTA),HL             ; Rewind logical diagnostics to the same byte.
    LD   A,(TK_SPART)              ; Load the current part ordinal.
    LD   (TK_EPART),A              ; Publish the error's source-part identity.
    LD   HL,(TK_SOFF1)             ; Reload the stable error offset.
    LD   (TK_EOFF),HL              ; Publish its low and high bytes.

; Reload the saved status after using A for the part ordinal.

    LD   A,(TK_ESTAT)              ; Return the original lexical status in A.
    SCF                            ; Mark tokenization as failed.
    RET                            ; Preserve the previous public token record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; ASCII case-folding by bit 5 maps A-Z and a-z into the same 0..25 interval.
; Carry from CP 26 is the routine's "is letter" result; A itself is restored.

TK_ILETT:
    PUSH BC                        ; Preserve caller BC while using C as scratch.
    LD   C,A                       ; Save the original byte for return.
    OR   $20                       ; Fold uppercase ASCII into the lowercase range.
    SUB  $61                       ; Map lowercase A..Z to 0..25.
    CP   26                        ; Carry denotes an index inside that interval.
    LD   A,C                       ; Restore the caller's original byte.
    POP  BC                        ; Restore caller BC without changing flags.
    RET                            ; Return the letter result in carry.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; A name may begin with an ASCII letter or underscore.

TK_INBEG:
    CALL TK_ILETT                  ; Accept either case of an ASCII letter.
    RET  C                         ; Return accepted with the original byte in A.
    CP   $5F                       ; Otherwise test underscore.
    JR   Z,TK_CYES                ; Return the shared carry-set result when equal.
    OR   A                         ; Clear carry for every other byte.
    RET                            ; Return not-a-name-start.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Continuation additionally permits decimal digits.

TK_INB:
    CALL TK_INBEG                  ; First accept letters and underscore.
    RET  C                         ; Preserve the accepted result.
    CP   $30                       ; Compare remaining bytes with ASCII zero.
    JR   C,TK_CNO                 ; Bytes below zero are not continuations.
    CP   $39+1                     ; Carry now denotes decimal digits 0..9.
    RET  C                         ; Return accepted for a digit.
TK_CNO:                        ; Return a false classifier result.
    OR   A                         ; Clear carry while preserving A.
    RET                            ; Report rejection.
TK_CYES:                       ; Return a true classifier result.
    SCF                            ; Set carry while preserving A.
    RET                            ; Report acceptance.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Convert one ASCII hexadecimal digit to 0..15. Carry set means valid.

TK_HDIGI:
    CP   $30                       ; Reject bytes below ASCII zero.
    JR   C,.HEXNO                  ; Return carry clear for that range.
    CP   $39+1                     ; Is the byte an ASCII decimal digit?
    JR   C,.HDECIMAL               ; Decode it through the decimal path.
    OR   $20                       ; Fold uppercase A..F to lowercase.
    SUB  $61                       ; Map A..F to candidate values 0..5.
    CP   6                         ; Accept only that six-value interval.
    JR   NC,.HEXNO                 ; Reject G and every later byte.
    ADD  A,10                     ; Convert the letter index to 10..15.
    SCF                            ; Mark the decoded hexadecimal digit as valid.
    RET                            ; Return its nibble value in A.
.HDECIMAL:                     ; Decode an ASCII decimal digit.
    SUB  $30                       ; Convert character 0..9 to numeric 0..9.
    SCF                            ; Mark the decoded digit as valid.
    RET                            ; Return its nibble value in A.
.HEXNO:                        ; Return invalid-hexadecimal classification.
    OR   A                         ; Clear carry while leaving a diagnostic value in A.
    RET                            ; Report rejection.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Global names allow eight raw bytes. A private name allows nine because its
; leading period is scope syntax rather than part of the eight-character name.

TK_SNAME:
    LD   C,8                       ; Set the raw limit for an eight-character global.
    CALL TK_SPEEK                  ; Inspect the first tentative source byte.
    CP   $2E                       ; Does a leading period select private scope?
    JR   NZ,.SNGLBL                ; Use global rules when no period is present.
    LD   C,9                       ; Permit period plus eight private payload bytes.
    CALL TK_STAKE                  ; Consume and buffer the private marker.

; A period by itself is not a name; the next byte must satisfy name-begin rules.

    CALL TK_SPEEK                  ; Inspect the first private payload byte.
    JP   C,TK_IB                   ; Diagnose a period at end of part.
    CALL TK_INBEG                  ; Require a legal first name character.
    JP   NC,TK_IB                  ; Diagnose a bare or malformed private prefix.
    LD   B,1                       ; Count the already consumed period.
    JR   .SNLOOP                  ; Enter the common continuation scan.
.SNGLBL:                       ; Begin an ordinary global-name scan.
    LD   B,0                       ; No raw source byte has been consumed yet.
.SNLOOP:                       ; Accept one legal name byte per iteration.

; B is the accepted raw length. Stop before the first non-name byte so the next
; tokenizer call can classify it independently.

    CALL TK_SPEEK                  ; Inspect the next source byte without consuming it.
    JR   C,.SNDONE                 ; Finish a name that reaches end of part.
    CALL TK_INB                    ; Classify a legal name continuation.
    JR   NC,.SNDONE                ; Leave the first delimiter for the next token.
    INC  B                         ; Include this accepted raw byte in the length.

; C is the maximum raw length for the selected global/private form. Comparing
; after increment detects the ninth significant byte before consuming it.

    LD   A,C                       ; Load the selected maximum raw length.
    CP   B                         ; Carry means the new byte exceeds that limit.
    JR   C,TK_NTLON                ; Fail before consuming the overlong byte.
    CALL TK_STAKE                  ; Append the accepted name byte and advance.
    JR   .SNLOOP                  ; Continue until delimiter or EOF.
.SNDONE:                       ; Publish the complete accepted name lexeme.

; Names carry their original bytes and no decoded value.

    LD   A,B                       ; Move the raw lexeme length into A.
    LD   (TK_SLEN),A               ; Save it for token-record publication.
    LD   A,TK_NAME                 ; Select the name token kind.
    JP   TK_FIN                    ; Mark the line non-empty and publish atomically.
TK_NTLON:                      ; Return an overlong-name lexical failure.
    LD   A,TK_SNTLO                ; Select the name-too-long status.
    JP   TK_FAIL                   ; Rewind to the token start and preserve prior record.

;@ROUTINE OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Scan the entire digit-led name-continuation sequence first. This lets Intel
; suffix forms such as 0FFFFH remain one token and makes malformed forms fail as
; a unit instead of splitting into a decimal token followed by a name.

TK_SDLED:
    LD   B,0                       ; Start the raw candidate length at zero.
.SDLLOOK:                      ; Consume the complete name-character run.
    CALL TK_SPEEK                  ; Inspect the next byte without advancing.
    JR   C,.SDLSELEC               ; End-of-part terminates the candidate.
    CALL TK_INB                    ; Accept letters, digits and underscore in the run.
    JR   NC,.SDLSELEC              ; Leave the first delimiter unconsumed.
    CALL TK_STAKE                  ; Append the accepted source byte.
    INC  B                         ; Increase the raw candidate length.

; A wrapped count means 256 bytes were consumed. The buffer has 256 slots, but
; the token record has only an eight-bit length, so that lexeme cannot publish.

    JP   Z,TK_INUMB                ; Diagnose a wrapped 256-byte candidate.
    JR   .SDLLOOK                 ; Continue scanning the candidate.
.SDLSELEC:                     ; Choose decimal or Intel-suffix interpretation.

; Save the tentative raw length, then inspect the final byte for H or B without
; regard to case. Successful scanned tokens publish their record fields through
; TK_CMT.

    LD   A,B                       ; Preserve the complete raw candidate length.
    LD   (TK_SLEN),A               ; Save it for any successful token publication.
    PUSH BC                        ; Preserve the raw length while calculating an index.
    LD   HL,TK_TBUF                ; Point at the first candidate byte.
    LD   C,B                       ; Move the byte count into the low offset register.
    LD   B,0                       ; Zero-extend it for address arithmetic.
    ADD  HL,BC                    ; Point one byte beyond the candidate.
    DEC  HL                        ; Select the candidate's final source byte.
    LD   A,(HL)                    ; Load the possible Intel suffix.
    POP  BC                        ; Restore the raw length in B.
    AND  $DF                       ; Fold a lowercase suffix to uppercase ASCII.

; C selects decimal (0), binary (1) or hexadecimal (4). Bit 2 is also a cheap
; hexadecimal discriminator used by the prefix scanner below.

    LD   C,0                       ; Default to unsuffixed decimal conversion.
    CP   $48                       ; Does the final byte contain H?
    JR   Z,.SDLHEX                 ; Select hexadecimal suffix conversion.
    CP   $42                       ; Does the final byte contain B?
    JR   NZ,.SDLPREPA              ; Otherwise convert the whole run as decimal.
    INC  C                         ; Select binary using discriminator value one.
    JR   .SDLSUFFI                ; Exclude the recognized suffix from conversion.
.SDLHEX:                       ; Select hexadecimal suffix conversion.
    LD   C,4                       ; Bit 2 marks the hexadecimal conversion path.
.SDLSUFFI:                     ; Remove the suffix from the digit count.

; Exclude the suffix itself from the number of digits to convert.

    DEC  B                         ; Count only the digits preceding H or B.
.SDLPREPA:                     ; Initialize the selected conversion loop.

; Every form requires at least one digit before an optional suffix.

    LD   A,B                       ; Inspect the number of digits to convert.
    OR   A                         ; A suffix by itself is not a number.
    JP   Z,TK_INUMB                ; Reject it as one complete malformed literal.
    LD   (TK_DSEEN),A              ; Store the remaining-digit loop count.
    LD   IX,(TK_SPTR)              ; Start conversion at the first buffered byte.
    LD   HL,0                      ; Initialize the sixteen-bit accumulator.
    LD   A,C                       ; Load the base discriminator.
    OR   A                         ; Zero selects ordinary decimal.
    JR   Z,.SDLDECIM               ; Enter the decimal conversion loop.
    CP   1                         ; One selects Intel binary suffix.
    JR   Z,.SDLBINAR               ; Enter the binary conversion loop.
.SDLHLOOP:                     ; Convert one Intel hexadecimal digit.

; Hexadecimal accumulation is value = value*16 + digit. Any high nibble already
; set before the shift proves the result would exceed 16 bits.

    LD   A,(IX+0)                  ; Load the next raw digit byte.
    CALL TK_HDIGI                  ; Decode 0..9 or A..F to a nibble.
    JP   NC,TK_INUMB               ; Reject any non-hexadecimal byte in the run.
    LD   E,A                       ; Preserve the decoded low nibble.
    LD   A,H                       ; Inspect the accumulator's high byte.
    AND  $F0                       ; Any occupied high nibble would shift past bit 15.
    JP   NZ,TK_NOVER               ; Report exact sixteen-bit overflow.
    ADD  HL,HL                    ; Multiply the accumulator by two.
    ADD  HL,HL                    ; Multiply it by four.
    ADD  HL,HL                    ; Multiply it by eight.
    ADD  HL,HL                    ; Multiply it by sixteen.
    LD   A,L                       ; Load the cleared low nibble.
    OR   E                         ; Merge the decoded digit into bits 0..3.
    LD   L,A                       ; Publish the new accumulator low byte.
    INC  IX                        ; Advance to the next buffered digit.

; TK_DSEEN counts unconverted digits for all three suffix/decimal loops.

    LD   A,(TK_DSEEN)              ; Load the remaining hexadecimal digit count.
    DEC  A                         ; Account for the digit just converted.
    LD   (TK_DSEEN),A              ; Publish the reduced count.
    JR   NZ,.SDLHLOOP              ; Continue until the suffix boundary.
    JR   .SDLFIN                  ; Publish the completed numeric value.
.SDLBINAR:                     ; Convert one Intel binary digit.

; Binary accepts only ASCII 0 or 1. Carry from the doubling detects bit 16.

    LD   A,(IX+0)                  ; Load the next raw digit byte.
    SUB  $30                       ; Map ASCII zero and one to numeric values.
    JP   C,TK_INUMB                ; Reject bytes below ASCII zero.
    CP   2                         ; Accept only values zero or one.
    JP   NC,TK_INUMB               ; Reject all other bytes in the candidate.
    LD   E,A                       ; Preserve the decoded bit.
    ADD  HL,HL                    ; Shift the accumulator left by one.
    JP   C,TK_NOVER                ; Carry reports an overflowing seventeenth bit.
    LD   A,L                       ; Load the low accumulator byte.
    OR   E                         ; Merge the decoded bit into bit zero.
    LD   L,A                       ; Publish the new accumulator value.
    INC  IX                        ; Advance to the next buffered digit.
    LD   A,(TK_DSEEN)              ; Load the remaining binary digit count.
    DEC  A                         ; Account for the digit just converted.
    LD   (TK_DSEEN),A              ; Publish the reduced count.
    JR   NZ,.SDLBINAR              ; Continue until the suffix boundary.
    JR   .SDLFIN                  ; Publish the completed numeric value.
.SDLDECIM:                     ; Convert one unsuffixed decimal digit.

; Reject a non-decimal byte anywhere before the optional suffix.

    LD   A,(IX+0)                  ; Load the next raw candidate byte.
    SUB  $30                       ; Convert ASCII zero..nine to 0..9.
    JP   C,TK_INUMB                ; Reject bytes below ASCII zero.
    CP   10                        ; Is the converted byte a decimal digit?
    JP   NC,TK_INUMB               ; Reject letters or underscore in the run.
    LD   C,A                       ; Preserve the decoded decimal digit.

; Before multiplying by ten, compare the accumulator with 6553. At equality the
; final digit may be at most five, the exact 65,535 boundary.

    LD   A,H                       ; Compare the accumulator with 1999H (6553).
    CP   $19                       ; A smaller high byte is always safe to multiply.
    JR   C,.SDLDACCU               ; Skip the remaining boundary checks.
    JP   NZ,TK_NOVER               ; A larger high byte must overflow on multiplication.
    LD   A,L                       ; High bytes are equal; compare the low byte.
    CP   $99                       ; 99H is the low byte of decimal 6553.
    JR   C,.SDLDACCU               ; A smaller accumulator remains safe.
    JP   NZ,TK_NOVER               ; A larger accumulator must overflow.
    LD   A,C                       ; At exactly 6553, inspect the final digit.
    CP   6                         ; Only digits zero through five remain within 65535.
    JP   NC,TK_NOVER               ; Reject six through nine as overflow.
.SDLDACCU:                     ; Accumulate one proved decimal digit.

; Compute value*10 + digit as two doublings, a third doubling, then add the saved
; value*2 and the zero-extended digit.

    LD   D,0                       ; Zero-extend the decoded digit into DE.
    LD   E,C                       ; Retain that digit while C becomes arithmetic scratch.
    ADD  HL,HL                    ; Form value times two.
    LD   B,H                       ; Save the high byte of value times two.
    LD   C,L                       ; Save its low byte.
    ADD  HL,HL                    ; Form value times four.
    ADD  HL,HL                    ; Form value times eight.
    ADD  HL,BC                    ; Add value times two to obtain value times ten.
    ADD  HL,DE                    ; Add the decoded decimal digit.
    INC  IX                        ; Advance to the next buffered candidate byte.
    LD   A,(TK_DSEEN)              ; Load the remaining decimal digit count.
    DEC  A                         ; Account for the digit just converted.
    LD   (TK_DSEEN),A              ; Publish the reduced count.
    JR   NZ,.SDLDECIM              ; Continue through the complete raw run.
.SDLFIN:                       ; Publish a successfully decoded numeric value.

; A successful numeric token publishes its decoded 16-bit value.

    LD   (TK_SVAL),HL              ; Save the decoded sixteen-bit value.
TK_FNUMB:                      ; Publish a numeric token from prepared fields.
    LD   A,TK_NUMBE                ; Select the numeric token kind.
    JP   TK_FIN                    ; Mark the line non-empty and commit the record.

;@ROUTINE IN BC OUT A,IX,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Scan a prefix form. Entry B already counts '$' or '%'; C is 4 for hex and 1
; for binary. HL accumulates the decoded value and TK_DSEEN records whether at
; least one digit followed the prefix.

TK_SBASE:
    LD   HL,0                      ; Initialize the sixteen-bit accumulator.
    XOR  A                         ; Construct the no-digit-seen state.
    LD   (TK_DSEEN),A              ; Clear the prefix digit-presence flag.
.SBLOOP:                       ; Inspect and accumulate one digit per iteration.

; Preserve the accumulator across PEEK, which uses HL for the source cursor.

    PUSH HL                        ; Preserve the accumulator across source lookup.
    CALL TK_SPEEK                  ; Inspect the next source byte.
    POP  HL                        ; Restore the accumulator without changing flags.
    JR   C,.SBEOF                  ; Finish or reject a prefix at end of part.
    LD   D,A                       ; Preserve the raw byte for delimiter validation.

; Bit 2 distinguishes hexadecimal from binary without another base constant.

    BIT  2,C                       ; Is this the hexadecimal prefix path?
    JR   Z,.SBDIGIT                ; Decode an Atom binary digit when clear.
    CALL TK_HDIGI                  ; Decode a hexadecimal nibble.
    JR   NC,.SBDONE                ; A non-digit terminates the prefix candidate.
    JR   .SBDIGIT1                ; Accumulate the valid nibble.
.SBDIGIT:                      ; Decode an Atom binary digit.
    SUB  $30                       ; Map ASCII zero and one to 0 and 1.
    JR   C,.SBDONE                 ; A byte below zero terminates the candidate.
    CP   2                         ; Accept only the two binary digit values.
    JR   NC,.SBDONE                ; Any other byte terminates the candidate.
.SBDIGIT1:                     ; Accumulate one normalized digit from A.
    LD   E,A                       ; Preserve the digit while shifting the accumulator.

; Hex shifts four places after proving its high nibble clear; binary shifts once
; and uses carry as the 17th-bit overflow indication.

    BIT  2,C                       ; Select hexadecimal or binary shift width.
    JR   Z,.SBSHIFT                ; Binary requires one left shift.
    LD   A,H                       ; Inspect the accumulator's high byte.
    AND  $F0                       ; A set high nibble would overflow on four shifts.
    JR   NZ,TK_NOVER               ; Report a value above sixteen bits.
    ADD  HL,HL                    ; Multiply hexadecimal accumulation by two.
    ADD  HL,HL                    ; Multiply it by four.
    ADD  HL,HL                    ; Multiply it by eight.
    ADD  HL,HL                    ; Multiply it by sixteen.
    JR   .SBMERGE                 ; Merge the decoded hexadecimal nibble.
.SBSHIFT:                      ; Shift binary accumulation by one bit.
    ADD  HL,HL                    ; Make room for the new low bit.
    JR   C,TK_NOVER                ; Carry reports an overflowing seventeenth bit.
.SBMERGE:                      ; Merge the normalized digit into the low bits.

; E is a normalised digit, so OR is equivalent to addition into cleared low bits.

    LD   A,L                       ; Load the accumulator's cleared low bits.
    OR   E                         ; Merge the normalized digit.
    LD   L,A                       ; Publish the updated accumulator.
    PUSH HL                        ; Preserve it across source consumption.
    CALL TK_STAKE                  ; Append and advance past the accepted digit.
    POP  HL                        ; Restore the accumulator.
    INC  B                         ; Increase the raw prefix-token length.

; Reject byte 256 because its wrapped count cannot be represented in the token
; record, even though that byte itself occupied the buffer's final slot.

    JR   Z,TK_INUMB                ; Reject a wrapped 256-byte raw token.
    LD   A,1                       ; Construct the digit-seen state.
    LD   (TK_DSEEN),A              ; Remember that the prefix has at least one digit.
    JR   .SBLOOP                  ; Continue until delimiter or EOF.
.SBDONE:                       ; Validate the first non-digit after a prefix value.

; A prefix requires at least one accepted digit. If the following byte could be
; part of a name, reject the complete token rather than silently splitting it.

    LD   A,(TK_DSEEN)              ; Has the prefix accepted any digit?
    OR   A                         ; Zero means bare '$' or '%'.
    JR   Z,TK_INUMB                ; Reject the bare prefix.
    LD   A,D                       ; Restore the first non-digit byte.
    CALL TK_INB                    ; Could it continue a digit-led name?
    JR   C,TK_INUMB                ; Reject rather than split an ambiguous run.
    JR   .SBFIN                   ; Publish the complete prefix value.
.SBEOF:                        ; Validate a prefix candidate at end of part.
    LD   A,(TK_DSEEN)              ; Inspect whether any digit was accepted.
    OR   A                         ; A bare prefix remains invalid at EOF.
    JR   Z,TK_INUMB                ; Diagnose it as malformed numeric input.
.SBFIN:                        ; Save a complete prefix numeric value.
    LD   (TK_SVAL),HL              ; Retain the decoded sixteen-bit accumulator.
TK_FNLEN:                      ; Publish a numeric token with raw length from B.

; Character literals share this finish path after placing their decoded byte in
; TK_SVAL; B supplies the raw lexeme length in both cases.

    LD   A,B                       ; Move the raw lexeme length into A.
    LD   (TK_SLEN),A               ; Save it in the tentative token fields.
    JR   TK_FNUMB                 ; Publish the numeric token.
TK_INUMB:                      ; Return malformed-numeric status.

; Invalid syntax and overflow are distinct diagnostics.

    LD   A,TK_SINUM                ; Select invalid numeric syntax.
    JP   TK_FAIL                   ; Rewind and preserve the previous public record.
TK_NOVER:                      ; Return numeric-overflow status.
    LD   A,TK_SNOVE                ; Select the sixteen-bit overflow diagnostic.
    JP   TK_FAIL                   ; Rewind and preserve the previous public record.

;@ROUTINE OUT A,IX,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY,BC
; B counts the complete raw token, including quotes and escape bytes. Consume the
; opening quote, then validate each byte without decoding the stored lexeme.

TK_SSTRI:
    LD   B,0                       ; Start the complete raw token length at zero.
    CALL TK_STAK1                  ; Consume and count the opening quote.
    JP   C,TK_FAIL                 ; Publish any EOF or length failure atomically.
.SSLOOP:                       ; Validate one raw string byte per iteration.
    CALL TK_STAK1                  ; Consume and count the next source byte.
    JP   C,TK_FAIL                 ; Translate EOF or length overflow to failure.
    CALL TK_ILEND                  ; Is this byte CR or LF?
    JR   Z,TK_USTRI                ; A physical line ending cannot terminate a string.

; Raw control bytes and DEL are never valid inside a quoted string.

    CP   $20                       ; Compare with the first printable ASCII byte.
    JR   C,TK_IB                   ; Reject other raw control bytes.
    CP   $7F                       ; Compare with DEL.
    JR   NC,TK_IB                  ; Reject DEL and all bytes above printable ASCII.
    CP   $22                       ; Is this the closing double quote?
    JR   Z,.SSDONE                 ; Finish after its already counted raw byte.

; Ordinary printable bytes need no further work. Backslash introduces either a
; table escape or the special two-digit hexadecimal escape.

    CP   $5C                       ; Is this an escape-introducing backslash?
    JR   NZ,.SSLOOP                ; Continue for an ordinary printable byte.
    CALL TK_STAK1                  ; Consume and count the escape selector.
    JP   C,TK_FAIL                 ; Diagnose an escape cut off by EOF or length.
    CP   $78                       ; Does lowercase x introduce a hex escape?
    JR   Z,.SHESCAPE               ; Validate exactly two hexadecimal digits.
    CALL TK_DESCA                  ; Validate a standard one-character escape.
    JR   C,TK_IESCA                ; Diagnose an unsupported selector.
    JR   .SSLOOP                  ; Continue after the complete escape.
.SHESCAPE:                     ; Validate the two digits following backslash-x.

; Both hexadecimal digits must be present and valid; their decoded value is left
; to the later statement emitter because string tokens retain raw source bytes.

    CALL TK_STAK1                  ; Consume and count the high hexadecimal digit.
    JP   C,TK_FAIL                 ; Diagnose a truncated escape or full buffer.
    CALL TK_HDIGI                  ; Require a hexadecimal value 0..15.
    JR   NC,TK_IESCA               ; Reject an invalid first digit.
    CALL TK_STAK1                  ; Consume and count the low hexadecimal digit.
    JP   C,TK_FAIL                 ; Diagnose a truncated escape or full buffer.
    CALL TK_HDIGI                  ; Require another hexadecimal value 0..15.
    JR   NC,TK_IESCA               ; Reject an invalid second digit.
    JR   .SSLOOP                  ; Resume raw string scanning.
.SSDONE:                       ; Publish the complete raw quoted lexeme.

; The closing quote has already been consumed and counted.

    LD   A,B                       ; Move the complete raw length into A.
    LD   (TK_SLEN),A               ; Save it for public token-record publication.
    LD   A,TK_STRIN                ; Select the string token kind.
    JP   TK_FIN                    ; Mark the line non-empty and publish atomically.

;@ROUTINE IN B OUT A,B,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Consume one string byte and increment its raw length. A zero result after INC
; means 256 bytes were attempted and the fixed token buffer is full.

TK_STAK1:
    CALL TK_STAKE                  ; Consume and buffer one raw string byte.
    JR   C,.STEOF                  ; Convert source EOF to unterminated-string status.
    INC  B                         ; Increase the complete raw string length.
    RET  NZ                        ; Return the consumed byte while length remains valid.
    LD   A,TK_SSTLO                ; A wrapped count denotes a 256-byte raw token.
    SCF                            ; Mark the string as too long.
    RET                            ; Let the caller route status through TK_FAIL.
.STEOF:                        ; Return EOF while inside a string token.

; EOF while a string scanner expects another byte is an unterminated string.

    LD   A,TK_SUSTR                ; Select unterminated-string status.
    SCF                            ; Mark bounded consumption as failed.
    RET                            ; Return for atomic failure publication.
TK_IESCA:                      ; Publish invalid-escape status.
    LD   A,TK_SIESC                ; Select the unsupported-escape diagnostic.
    JP   TK_FAIL                   ; Rewind to the token start.
TK_USTRI:                      ; Publish unterminated-string status.
    LD   A,TK_SUSTR                ; Select the missing-closing-quote diagnostic.
    JP   TK_FAIL                   ; Rewind to the opening quote.
TK_UCHAR:                      ; Publish unterminated-character status.
    LD   A,TK_SUCHA                ; Select the missing character quote diagnostic.
    JP   TK_FAIL                   ; Rewind to the opening apostrophe.
TK_ICHAR:                      ; Publish invalid-character status.
    LD   A,TK_SICHA                ; Select malformed character contents.
    JP   TK_FAIL                   ; Rewind to the opening apostrophe.
TK_IB:                         ; Publish invalid-input-byte status.
    LD   A,TK_SIB                  ; Select the general invalid-byte diagnostic.
    JP   TK_FAIL                   ; Rewind and preserve the previous token record.

;@ROUTINE OUT CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,A
; Enter semicolon-comment consumption.

TK_SCOMM:
.SCLOOP:                       ; Discard one non-line-ending byte per iteration.

; Discard comment bytes but leave CR/LF unconsumed. The ordinary line-ending path
; emits EOL only when TK_LHTOK records an earlier token on this physical line.

    CALL TK_SPEEK                  ; Inspect the next comment byte without consuming it.
    RET  C                         ; End the comment cleanly at source-part EOF.
    CALL TK_ILEND                  ; Is the byte CR or LF?
    RET  Z                         ; Leave line endings for the main token loop.
    CALL TK_STAKE                  ; Consume and discard the ordinary comment byte.
    JR   .SCLOOP                  ; Continue to the line boundary or EOF.
