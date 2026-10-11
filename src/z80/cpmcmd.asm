CMD_CBEG: ; Beginning of command-tail parsing code.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept help, one source, or source plus output. One name selects the
; source and derives a COM output with the same basename. Names use CP/M 8.3.

CMD_READ: ; Read and validate the CCP command tail.
    XOR  A                              ; Clear command state.
    LD   (SRC_PART),A                   ; Drop any cached source-part ordinal.
    LD   A,(CMD_LEN)                    ; Read the CCP's command-tail byte count.
    LD   B,A                            ; Keep the remaining count beside the HL cursor.
    LD   HL,CMD_TAIL                    ; Start at the first command-tail character.
    CALL CMD_SKIP                       ; Skip leading spaces.
    JR   NZ,CMD_ARGS                    ; Parse a non-empty command tail.
CMD_HELP: ; Print help without opening source or output files.
    LD   DE,MSG_HELP                    ; Show the compact command syntax.
    CALL CP_PRINT                       ; Help performs no source or output file calls.
    LD   A,1                            ; Mark help-only success for CP_ENTRY.
    OR   A                              ; Clear carry without losing the help marker.
    RET                                 ; Skip source discovery and assembly.
CMD_ARGS: ; Parse one or two filename arguments.
    CALL CMD_NAME                       ; Parse the source argument as 8.3.
    JP   C,.BADSRC                      ; Distinguish a bad source name.
    CALL CMD_SKIP                       ; Look for a second name.
    JR   Z,.ONENAME                     ; Derive the output name and type.
    CALL CMD_NAME                       ; Validate the explicit output name.
    JP   C,.BADOUT                      ; Report malformed output fields separately.
    CALL CMD_SKIP                       ; Check for trailing text.
    JP   NZ,.USAGE                      ; Reject a third argument or trailing junk.
    JR   .GOTNAMES                      ; Continue with the CCP's normalised FCBs.
.ONENAME: ; Derive COM output from the sole source argument.

; The CCP populated default FCB 1 from the sole argument. Copy it to FCB 2 and
; replace only the extension, retaining the same normalised basename.

    LD   HL,$005C                       ; Address the CCP's default source FCB.
    LD   DE,$006C                       ; Address the second FCB used for output.
    LD   BC,12                          ; Copy drive, basename and extension bytes.
    LDIR                                ; Copy the source basename to output.
    LD   HL,CMD_COM                     ; Select the conventional `.COM` output type.
    LD   DE,$006C+9                     ; Point at the output FCB's three-byte type.
    LD   BC,3                           ; Copy exactly the extension bytes.
    LDIR                                ; Complete the one-argument output default.
.GOTNAMES: ; Retain the normalised source and output names.
    LD   HL,$005C                       ; Read the CCP-normalised source FCB.
    LD   DE,SRC_FCB                     ; Store a private copy for BDOS operations.
    LD   BC,12                          ; Include drive, basename and extension.
    LDIR                                ; Preserve the selected input filename.
    LD   A,(SRC_FCB+9)                  ; Inspect the first byte of its type field.
    CP   ' '                            ; A blank type means the argument omitted it.
    JR   NZ,.INTYPE                     ; Keep any explicit source extension.
    LD   HL,CMD_ASM                     ; Supply the native source extension `.ASM`.
    LD   DE,SRC_FCB+9                   ; Point at the private FCB's type field.
    LD   BC,3                           ; The CP/M type occupies three bytes.
    LDIR                                ; Complete the input FCB with its default type.
.INTYPE: ; Select output representation from its extension.
    LD   HL,$006C                       ; Read the CCP-normalised output FCB.
    LD   DE,PUB_NAME                    ; Store the selected output name.
    LD   BC,12                          ; Copy drive, basename and three-byte type.
    LDIR                                ; Retain the caller's requested output name.
    LD   HL,PUB_NAME+9                  ; Point at the output extension.
    LD   DE,CMD_COM                     ; Compare with the default COM format.
    CALL .SAMETYPE                      ; Check all three extension bytes.
    JR   Z,.COM                         ; Select format zero for COM.
    LD   HL,PUB_NAME+9                  ; Reuse HL for another extension comparison.
    LD   DE,CMD_BIN                     ; Compare with the raw binary format.
    CALL .SAMETYPE                      ; Check for an exact BIN extension.
    JR   Z,.BIN                         ; Select format one for BIN.
    LD   HL,PUB_NAME+9                  ; Test the last supported output extension.
    LD   DE,CMD_HEX                     ; Compare with the Intel HEX format.
    CALL .SAMETYPE                      ; Check for an exact HEX extension.
    JR   Z,.HEX                         ; Select Intel HEX when the type matches.
    LD   HL,PUB_NAME+9                  ; Reuse HL to test the ASO extension.
    LD   DE,CMD_ASO                     ; Compare with the serialized operation format.
    CALL .SAMETYPE                      ; Check all three ASO extension bytes.
    JR   NZ,.BADOUT                     ; Reject any other output type.
    LD   A,3                            ; Assign format code three to ASO.
    JR   .FORMAT                        ; Save the format and check names.
.HEX: ; Select Intel HEX output.
    LD   A,2                            ; Assign format code two to Intel HEX.
    JR   .FORMAT                        ; Save the format and check names.
.BIN: ; Select raw binary output.
    LD   A,1                            ; Assign format code one to raw BIN.
    JR   .FORMAT                        ; Save the type and continue filename checks.
.COM: ; Select CP/M COM output.
    XOR  A                              ; Assign format code zero to CP/M COM.
.FORMAT: ; Protect source and reserved transaction filenames.

; Preserve the normalised input and output names in adapter-owned FCB storage.
; Input defaults to ASM when no type was supplied. output type selects 0=COM,
; 1=BIN, 2=HEX or 3=ASO.

    LD   (PUB_KIND),A                   ; Save the selected output format.
    LD   HL,SRC_FCB                     ; Compare source and output identities.
    LD   DE,PUB_NAME                    ; Address the output's twelve-byte identity.
    CALL CMD_SAME                       ; Reject overwriting the file being assembled.
    JR   Z,.CLASH                       ; Source and output must be distinct files.
    CALL PUB_TEMP                       ; Build the transaction's temporary filename.
    CALL .CHKWORK                       ; Check for source collision or existing file.
    RET  C                              ; Stop on a temp-name conflict.
    CALL PUB_BAK                        ; Build the transaction's backup filename.
    CALL .CHKWORK                       ; Apply the same collision and existence checks.
    RET                                 ; Return the final preflight status in carry.

;@ROUTINE IN DE,HL OUT A,B,DE,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Compare the three-byte output-type selectors at DE and HL.

.SAMETYPE: ; Compare all three extension-selector bytes.
    LD   B,3                            ; Count the three bytes in a CP/M file type.
.TYPEBYTE: ; Compare the next extension character.
    LD   A,(DE)                         ; Read the candidate extension byte.
    CP   (HL)                           ; Compare it with the requested extension.
    RET  NZ                             ; Stop on the first mismatch, preserving NZ.
    INC  DE                             ; Advance to the next byte in the candidate.
    INC  HL                             ; Advance to the corresponding expected byte.
    DJNZ .TYPEBYTE                      ; Compare all three type bytes.
    RET                                 ; Return Z when every byte matched.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Prove the temporary name differs from the source and is not already present.

.CHKWORK: ; Protect the source from reserved work-name collisions.
    LD   HL,SRC_FCB                     ; Address the source name.
    LD   DE,CP_FCB                      ; Address the temporary or backup name.
    CALL CMD_SAME                       ; Test all drive, basename and type bytes.
    JR   Z,.CLASH                       ; Never let publication replace the source.
    JP   .UNUSED                        ; Require an unused work name.
.USAGE: ; Return command-usage detail.
    LD   DE,MSG_HELP                    ; Select the command syntax diagnostic.
    SCF                                 ; Return parser failure to CP_ENTRY.
    RET                                 ; Keep the message address in DE.
.BADSRC: ; Return invalid-source-name detail.
    LD   DE,MSG_SRC                     ; Select the source-name diagnostic.
    SCF                                 ; Mark the invalid source argument.
    RET                                 ; Return its message address in DE.
.BADOUT: ; Return invalid-output-name detail.
    LD   DE,MSG_OUT                     ; Select the output-name diagnostic.
    SCF                                 ; Mark the invalid output argument.
    RET                                 ; Return its message address in DE.
.CLASH: ; Return destructive filename-collision detail.
    LD   DE,MSG_DUP                     ; Select the name-conflict message.
    SCF                                 ; Refuse a colliding output or work filename.
    RET                                 ; Return the diagnostic address in DE.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require the auxiliary file named by CP_FCB not to exist.

.UNUSED: ; Require the reserved transaction name to be unused.
    LD   DE,CP_FCB                      ; Address the candidate temporary or backup FCB.
    LD   C,CP_OPEN                      ; Ask BDOS whether the named file already exists.
    CALL CP_BDOS                        ; FF means the file was not found.
    INC  A                              ; Convert the not-found result into zero.
    JR   Z,.FREE                        ; The name is free.
    LD   DE,CP_FCB                      ; Reuse the opened candidate FCB for closing it.
    LD   C,CP_CLOSE                     ; Select the matching CP/M close operation.
    CALL CP_BDOS                        ; Close the existing file.
    LD   DE,MSG_CRLF                    ; Start the diagnostic on a fresh line.
    CALL CP_PRINT                       ; Separate it from the echoed command.
    LD   HL,CP_FCB                      ; Name the leftover work file for the user.
    CALL CP_NAME                        ; Print it before the explanation.
    LD   DE,MSG_BUSY                    ; Select the collision diagnostic.
    SCF                                 ; Report that the auxiliary file is occupied.
    RET                                 ; Preserve its message pointer in DE.
.FREE: ; Accept an unused transaction filename.
    XOR  A                              ; Clear carry and status for an unused name.
    RET                                 ; Allow the caller to check or use the name.

;@ROUTINE IN B,HL OUT A,B,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Advance HL and reduce B past leading command-tail spaces.

CMD_SKIP: ; Skip spaces within the counted command tail.
    LD   A,B                            ; Check whether any command-tail bytes remain.
    OR   A                              ; Z marks the end of the tail.
    RET  Z                              ; Leave HL at the end when no bytes remain.
    LD   A,(HL)                         ; Inspect the next unconsumed character.
    CP   ' '                            ; CP/M command separators are ordinary spaces.
    RET  NZ                             ; Stop at the first non-space byte.
    INC  HL                             ; Consume one leading or separating space.
    DEC  B                              ; Keep the remaining-byte count in step with HL.
    JR   CMD_SKIP                       ; Skip a run of spaces before returning.

;@ROUTINE IN B,HL OUT A,B,HL,CARRY CLOBBERS C,D,ZERO,SIGN,PARITY,HALFCARRY
; Parse one unquoted, current-drive 8.3 filename without consuming its
; trailing space. Carry reports an empty, overlong, wildcard, drive-qualified,
; or otherwise invalid field.

CMD_NAME: ; Validate one current-drive unquoted 8.3 name.
    LD   D,8                            ; Start with the eight-character basename limit.
    LD   C,0                            ; Count characters in the current name field.
.BYTE: ; Inspect the next filename character.
    LD   A,B                            ; Check the remaining tail length.
    OR   A                              ; Z marks the end of the tail.
    JR   Z,.DONE                        ; Validate the final name or extension length.
    LD   A,(HL)                         ; Read the next unquoted filename character.
    CP   ' '                            ; Space terminates this name.
    JR   Z,.DONE                        ; Leave the separator for CMD_SKIP.
    CP   '.'                            ; A dot switches from basename to extension.
    JR   NZ,.DATA                       ; Validate an ordinary name byte.
    LD   A,D                            ; D holds the current field limit.
    CP   8                              ; Accept a dot only after the basename field.
    JR   NZ,.BAD                        ; Reject a second dot in the extension.
    LD   A,C                            ; Require at least one basename character.
    OR   A                              ; Test the current field's character count.
    JR   Z,.BAD                         ; Reject a leading dot and empty basename.
    LD   D,3                            ; Limit the extension to three bytes.
    LD   C,0                            ; Start counting extension characters.
    JR   .CONSUME                       ; Consume the separator dot without counting it.
.DATA: ; Validate and count an ordinary filename character.
    CALL CMD_CHAR                       ; Validate the name byte.
    RET  C                              ; Propagate an invalid byte.
    INC  C                              ; Count this character in the current field.
    LD   A,D                            ; Load the basename or extension capacity.
    CP   C                              ; Compare limit and new length.
    JR   C,.BAD                         ; Reject an overlong field.
.CONSUME: ; Consume a valid character or extension separator.
    INC  HL                             ; Advance past a validated character or the dot.
    DEC  B                              ; Reduce the remaining command-tail byte count.
    JR   .BYTE                          ; Continue until a separator or end of tail.
.DONE: ; Require a nonempty final filename field.
    LD   A,C                            ; Check the final field length.
    OR   A                              ; Set Z for an empty final field.
    JR   Z,.BAD                         ; Reject an empty name or a trailing dot.
    RET                                 ; Leave any separating space unconsumed.
.BAD: ; Reject an invalid filename field.
    SCF                                 ; Report an invalid name.
    RET                                 ; Return carry to the command parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Validate one character for use in a CP/M 8.3 filename.

CMD_CHAR: ; Check one printable CP/M filename character.
    CP   '!'                            ; Reject control characters and space below '!'.
    RET  C                              ; Reject bytes below '!'.
    CP   $7F                            ; Reject DEL and high-bit bytes.
    JR   NC,.BAD                        ; Not printable ASCII.
    CP   '*'                            ; Punctuation before '*' is allowed after '!'.
    JR   C,.UPPER                       ; Accept this punctuation range.
    CP   '-'                            ; Exclude '*', '+' and ',' before the hyphen.
    JR   C,.BAD                         ; Exclude '*', '+' and ','.
    CP   '/'                            ; Reject the path separator.
    JR   Z,.BAD                         ; Reject a path separator explicitly.
    CP   ':'                            ; Test the next punctuation range.
    JR   C,.UPPER                       ; Permit bytes below ':'.
    CP   '@'                            ; Exclude ':', ';', '<', '=', '>' and '?'.
    JR   C,.BAD                         ; These include drive and wildcard syntax.
.UPPER: ; Check the upper ASCII punctuation range.
    CP   '['                            ; Uppercase letters below '[' are accepted.
    JR   C,.OK                          ; Permit digits, punctuation and A through Z.
    CP   '^'                            ; Set the boundary after '[', backslash and ']'.
    JR   C,.BAD                         ; Exclude '[', '\\' and ']'.
    CP   '_'                            ; Check the underscore boundary explicitly.
    JR   Z,.BAD                         ; Do not admit underscore into an 8.3 field.
.OK: ; Return an accepted filename character.
    OR   A                              ; Clear carry. keep the valid byte.
    RET                                 ; Return the accepted character in A.
.BAD: ; Reject forbidden filename punctuation.
    SCF                                 ; Mark this character as invalid for a filename.
    RET                                 ; Return carry to CMD_NAME.

;@ROUTINE IN DE,HL OUT A,ZERO CLOBBERS B,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Compare two drive-plus-8.3-name records for exact equality.

CMD_SAME: ; Compare twelve-byte drive and 8.3 identities.
    LD   B,12                           ; Compare drive and eleven name/type bytes.
.BYTE: ; Compare each corresponding filename byte.
    LD   A,(DE)                         ; Read the first FCB's name byte.
    CP   (HL)                           ; Compare it with the corresponding second byte.
    RET  NZ                             ; Return immediately when the identities differ.
    INC  DE                             ; Advance the first name cursor.
    INC  HL                             ; Advance the second name cursor.
    DJNZ .BYTE                          ; Compare the complete twelve-byte identity.
    XOR  A                              ; Return Z after all bytes match.
    RET                                 ; Carry is clear for the equal-name result.
CMD_CEND: ; Exclusive end of command parsing code.
