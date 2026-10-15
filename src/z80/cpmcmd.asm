cmdBeg: ; Beginning of command-tail parsing code.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept help, one source, or source plus output. One name selects the
; source and derives a COM output with the same basename. Names use CP/M 8.3.

cmdRead: ; Read and validate the CCP command tail.
    XOR  A                              ; Clear command state.
    LD   (srcPart),A                    ; Drop any cached source-part ordinal.
    LD   A,(cmdLen)                     ; Read the CCP's command-tail byte count.
    LD   B,A                            ; Keep the remaining count beside the HL cursor.
    LD   HL,cmdTail                     ; Start at the first command-tail character.
    CALL cmdSkip                        ; Skip leading spaces.
    JR   NZ,cmdArgs                     ; Parse a non-empty command tail.
cmdHelp: ; Print help without opening source or output files.
    LD   DE,msgHelp                     ; Show the compact command syntax.
    CALL cpPrint                        ; Help performs no source or output file calls.
    LD   A,1                            ; Mark help-only success for cpEntry.
    OR   A                              ; Clear carry without losing the help marker.
    RET                                 ; Skip source discovery and assembly.
cmdArgs: ; Parse the source, output and symbol-file arguments.
    XOR  A                              ; No symbol file unless one is named.
    LD   (symOn),A                      ; Clear any request from an earlier command.
    CALL cmdName                        ; Parse the source argument as 8.3.
    JP   C,.badSrc                      ; Distinguish a bad source name.
    CALL cmdSkip                        ; Look for a second name.
    JR   Z,.oneName                     ; Derive the output name and type.
    CALL cmdName                        ; Validate the explicit output name.
    JP   C,.badOut                      ; Report malformed output fields separately.
    CALL cmdSkip                        ; Look for a symbol-file name.
    JR   Z,.gotNames                    ; Continue with the CCP's normalised FCBs.
    CALL .symbols                       ; Parse and keep the symbol-file name.
    RET  C                              ; Report an invalid symbol-file name.
    CALL cmdSkip                        ; Check for trailing text.
    JP   NZ,.usage                      ; Reject a fourth argument or trailing junk.
    JR   .gotNames                      ; Continue with the CCP's normalised FCBs.
.oneName: ; Derive COM output from the sole source argument.

; The CCP populated default FCB 1 from the sole argument. Copy it to FCB 2 and
; replace only the extension, retaining the same normalised basename.

    LD   HL,$005C                       ; Address the CCP's default source FCB.
    LD   DE,$006C                       ; Address the second FCB used for output.
    LD   BC,12                          ; Copy drive, basename and extension bytes.
    LDIR                                ; Copy the source basename to output.
    LD   HL,cmdCom                      ; Select the conventional `.com` output type.
    LD   DE,$006C+9                     ; Point at the output FCB's three-byte type.
    LD   BC,3                           ; Copy exactly the extension bytes.
    LDIR                                ; Complete the one-argument output default.
.gotNames: ; Retain the normalised source and output names.
    LD   HL,$005C                       ; Read the CCP-normalised source FCB.
    LD   DE,srcFcb                      ; Store a private copy for BDOS operations.
    LD   BC,12                          ; Include drive, basename and extension.
    LDIR                                ; Preserve the selected input filename.
    LD   A,(srcFcb+9)                   ; Inspect the first byte of its type field.
    CP   ' '                            ; A blank type means the argument omitted it.
    JR   NZ,.inType                     ; Keep any explicit source extension.
    LD   HL,cmdAsm                      ; Supply the native source extension `.ASM`.
    LD   DE,srcFcb+9                    ; Point at the private FCB's type field.
    LD   BC,3                           ; The CP/M type occupies three bytes.
    LDIR                                ; Complete the input FCB with its default type.
.inType: ; Select output representation from its extension.
    LD   HL,$006C                       ; Read the CCP-normalised output FCB.
    LD   DE,pubName                     ; Store the selected output name.
    LD   BC,12                          ; Copy drive, basename and three-byte type.
    LDIR                                ; Retain the caller's requested output name.
    LD   HL,pubName+9                   ; Point at the output extension.
    LD   DE,cmdCom                      ; Compare with the default COM format.
    CALL .sameType                      ; Check all three extension bytes.
    JR   Z,.com                         ; Select format zero for COM.
    LD   HL,pubName+9                   ; Reuse HL for another extension comparison.
    LD   DE,cmdBin                      ; Compare with the raw binary format.
    CALL .sameType                      ; Check for an exact BIN extension.
    JR   Z,.bin                         ; Select format one for BIN.
    LD   HL,pubName+9                   ; Test the last supported output extension.
    LD   DE,cmdHex                      ; Compare with the Intel HEX format.
    CALL .sameType                      ; Check for an exact HEX extension.
    JR   Z,.hex                         ; Select Intel HEX when the type matches.
    LD   HL,pubName+9                   ; Reuse HL to test the ASO extension.
    LD   DE,cmdAso                      ; Compare with the serialized operation format.
    CALL .sameType                      ; Check all three ASO extension bytes.
    JP   NZ,.badOut                     ; Reject any other output type.
    LD   A,3                            ; Assign format code three to ASO.
    JR   .format                        ; Save the format and check names.
.hex: ; Select Intel HEX output.
    LD   A,2                            ; Assign format code two to Intel HEX.
    JR   .format                        ; Save the format and check names.
.bin: ; Select raw binary output.
    LD   A,1                            ; Assign format code one to raw BIN.
    JR   .format                        ; Save the type and continue filename checks.
.com: ; Select CP/M COM output.
    XOR  A                              ; Assign format code zero to CP/M COM.
.format: ; Protect source and reserved transaction filenames.

; Preserve the normalised input and output names in adapter-owned FCB storage.
; Input defaults to ASM when no type was supplied. output type selects 0=COM,
; 1=BIN, 2=HEX or 3=ASO.

    LD   (pubKind),A                    ; Save the selected output format.
    LD   HL,srcFcb                      ; Compare source and output identities.
    LD   DE,pubName                     ; Address the output's twelve-byte identity.
    CALL cmdSame                        ; Reject overwriting the file being assembled.
    JP   Z,.clash                       ; Source and output must be distinct files.
    CALL pubTemp                        ; Build the transaction's temporary filename.
    CALL .testWork                      ; Check for source collision or existing file.
    RET  C                              ; Stop on a temp-name conflict.
    CALL pubBak                         ; Build the transaction's backup filename.
    CALL .testWork                      ; Apply the same collision and existence checks.
    RET  C                              ; Stop on a backup-name conflict.
    LD   A,(symOn)                      ; Was a symbol file named?
    OR   A                              ; Zero means no symbol file.
    RET  Z                              ; Nothing more to check.
    LD   HL,srcFcb                      ; The symbol file must not be the source.
    LD   DE,symName                     ; Address the symbol file's identity.
    CALL cmdSame                        ; Compare all twelve bytes.
    JP   Z,.clash                       ; Never overwrite the source.
    LD   HL,pubName                     ; Nor may it be the output.
    LD   DE,symName                     ; Address the symbol file's identity again.
    CALL cmdSame                        ; Compare all twelve bytes.
    JP   Z,.clash                       ; Two results cannot share one file.
    CALL symTemp                        ; Build the symbol file's work name.
    JR   .testWork                      ; Check it like the other work names.

;@ROUTINE IN DE,HL OUT A,B,DE,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Compare the three-byte output-type selectors at DE and HL.

.sameType: ; Compare all three extension-selector bytes.
    LD   B,3                            ; Count the three bytes in a CP/M file type.
.typeByte: ; Compare the next extension character.
    LD   A,(DE)                         ; Read the candidate extension byte.
    CP   (HL)                           ; Compare it with the requested extension.
    RET  NZ                             ; Stop on the first mismatch, preserving NZ.
    INC  DE                             ; Advance to the next byte in the candidate.
    INC  HL                             ; Advance to the corresponding expected byte.
    DJNZ .typeByte                      ; Compare all three type bytes.
    RET                                 ; Return Z when every byte matched.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
;@ROUTINE IN B,HL OUT B,HL,CARRY CLOBBERS A,C,DE,ZERO,SIGN,PARITY,HALFCARRY
; Copy the third argument into symName. Its type defaults to SYM and must be
; SYM when given.

.symbols: ; Parse and keep the symbol-file name.
    PUSH HL                             ; Keep the name's first byte.
    CALL cmdName                        ; Validate the 8.3 name and pass it.
    POP  DE                             ; DE addresses the name's first byte.
    JR   C,.badOut                      ; Report a malformed name.
    PUSH HL                             ; Keep the tail position after the name.
    PUSH BC                             ; Keep the remaining tail count.
    OR   A                              ; Clear carry for the subtraction.
    SBC  HL,DE                          ; L is the name's length.
    LD   C,L                            ; C counts the bytes to copy.
    LD   HL,symName                     ; Start with a blank current-drive name.
    LD   (HL),0                         ; Drive zero is the current drive.
    LD   B,11                           ; Clear the name and type fields.
.blank: ; Fill one field byte with a space.
    INC  HL                             ; Advance to the next field byte.
    LD   (HL),' '                       ; CP/M pads names with spaces.
    DJNZ .blank                         ; Clear all eleven bytes.
    LD   HL,symName+1                   ; Copy the basename first.
.copy: ; Copy one name byte.
    LD   A,(DE)                         ; Read the next command-tail byte.
    INC  DE                             ; Advance along the tail.
    CP   '.'                            ; Does the type start here?
    JR   NZ,.store                      ; No: keep the byte.
    LD   HL,symName+9                   ; Write the type field next.
    JR   .next                          ; The dot itself is not stored.
.store: ; Store a name or type byte.
    LD   (HL),A                         ; Keep the byte in its field.
    INC  HL                             ; Advance within the field.
.next: ; Count the byte just read.
    DEC  C                              ; One fewer byte to copy.
    JR   NZ,.copy                       ; Copy the rest of the name.
    LD   A,(symName+9)                  ; Was a type given?
    CP   ' '                            ; A space means none.
    JR   NZ,.typed                      ; Check the type that was given.
    LD   HL,cmdSym                      ; Default to SYM.
    LD   DE,symName+9                   ; Point at the type field.
    LD   BC,3                           ; A type is three bytes.
    LDIR                                ; Supply the default type.
    JR   .named                         ; The name is complete.
.typed: ; Accept only the SYM type.
    LD   HL,symName+9                   ; Address the given type.
    LD   DE,cmdSym                      ; Compare it with SYM.
    CALL .sameType                      ; Check all three bytes.
    JR   Z,.named                       ; SYM is accepted.
    POP  BC                             ; Restore the tail count.
    POP  HL                             ; Restore the tail position.
    JR   .badOut                        ; Any other type is an error.
.named: ; Record that a symbol file was asked for.
    LD   A,1                            ; One means requested.
    LD   (symOn),A                      ; Write symbols at commit.
    POP  BC                             ; Restore the tail count.
    POP  HL                             ; Restore the tail position.
    OR   A                              ; Clear carry for success.
    RET                                 ; Return to the argument parser.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Prove the temporary name differs from the source and is not already present.

.testWork: ; Protect the source from reserved work-name collisions.
    LD   HL,srcFcb                      ; Address the source name.
    LD   DE,cpFcb                       ; Address the temporary or backup name.
    CALL cmdSame                        ; Test all drive, basename and type bytes.
    JR   Z,.clash                       ; Never let publication replace the source.
    JP   .unused                        ; Require an unused work name.
.usage: ; Return command-usage detail.
    LD   DE,msgHelp                     ; Select the command syntax diagnostic.
    SCF                                 ; Return parser failure to cpEntry.
    RET                                 ; Keep the message address in DE.
.badSrc: ; Return invalid-source-name detail.
    LD   DE,msgSrc                      ; Select the source-name diagnostic.
    SCF                                 ; Mark the invalid source argument.
    RET                                 ; Return its message address in DE.
.badOut: ; Return invalid-output-name detail.
    LD   DE,msgOut                      ; Select the output-name diagnostic.
    SCF                                 ; Mark the invalid output argument.
    RET                                 ; Return its message address in DE.
.clash: ; Return destructive filename-collision detail.
    LD   DE,msgDup                      ; Select the name-conflict message.
    SCF                                 ; Refuse a colliding output or work filename.
    RET                                 ; Return the diagnostic address in DE.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require the auxiliary file named by cpFcb not to exist.

.unused: ; Require the reserved transaction name to be unused.
    LD   DE,cpFcb                       ; Address the candidate temporary or backup FCB.
    LD   C,cpOpen                       ; Ask BDOS whether the named file already exists.
    CALL cpBdos                         ; FF means the file was not found.
    INC  A                              ; Convert the not-found result into zero.
    JR   Z,.free                        ; The name is free.
    LD   DE,cpFcb                       ; Reuse the opened candidate FCB for closing it.
    LD   C,cpClose                      ; Select the matching CP/M close operation.
    CALL cpBdos                         ; Close the existing file.
    LD   DE,msgCrlf                     ; Start the diagnostic on a fresh line.
    CALL cpPrint                        ; Separate it from the echoed command.
    LD   HL,cpFcb                       ; Name the leftover work file for the user.
    CALL cpPutFcb                       ; Print it before the explanation.
    LD   DE,msgBusy                     ; Select the collision diagnostic.
    SCF                                 ; Report that the auxiliary file is occupied.
    RET                                 ; Preserve its message pointer in DE.
.free: ; Accept an unused transaction filename.
    XOR  A                              ; Clear carry and status for an unused name.
    RET                                 ; Allow the caller to check or use the name.

;@ROUTINE IN B,HL OUT A,B,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Advance HL and reduce B past leading command-tail spaces.

cmdSkip: ; Skip spaces within the counted command tail.
    LD   A,B                            ; Check whether any command-tail bytes remain.
    OR   A                              ; Z marks the end of the tail.
    RET  Z                              ; Leave HL at the end when no bytes remain.
    LD   A,(HL)                         ; Inspect the next unconsumed character.
    CP   ' '                            ; CP/M command separators are ordinary spaces.
    RET  NZ                             ; Stop at the first non-space byte.
    INC  HL                             ; Consume one leading or separating space.
    DEC  B                              ; Keep the remaining-byte count in step with HL.
    JR   cmdSkip                        ; Skip a run of spaces before returning.

;@ROUTINE IN B,HL OUT A,B,HL,CARRY CLOBBERS C,D,ZERO,SIGN,PARITY,HALFCARRY
; Parse one unquoted, current-drive 8.3 filename without consuming its
; trailing space. Carry reports an empty, overlong, wildcard, drive-qualified,
; or otherwise invalid field.

cmdName: ; Validate one current-drive unquoted 8.3 name.
    LD   D,8                            ; Start with the eight-character basename limit.
    LD   C,0                            ; Count characters in the current name field.
.byte: ; Inspect the next filename character.
    LD   A,B                            ; Check the remaining tail length.
    OR   A                              ; Z marks the end of the tail.
    JR   Z,.done                        ; Validate the final name or extension length.
    LD   A,(HL)                         ; Read the next unquoted filename character.
    CP   ' '                            ; Space terminates this name.
    JR   Z,.done                        ; Leave the separator for cmdSkip.
    CP   '.'                            ; A dot switches from basename to extension.
    JR   NZ,.data                       ; Validate an ordinary name byte.
    LD   A,D                            ; D holds the current field limit.
    CP   8                              ; Accept a dot only after the basename field.
    JR   NZ,.bad                        ; Reject a second dot in the extension.
    LD   A,C                            ; Require at least one basename character.
    OR   A                              ; Test the current field's character count.
    JR   Z,.bad                         ; Reject a leading dot and empty basename.
    LD   D,3                            ; Limit the extension to three bytes.
    LD   C,0                            ; Start counting extension characters.
    JR   .consume                       ; Consume the separator dot without counting it.
.data: ; Validate and count an ordinary filename character.
    CALL cmdChar                        ; Validate the name byte.
    RET  C                              ; Propagate an invalid byte.
    INC  C                              ; Count this character in the current field.
    LD   A,D                            ; Load the basename or extension capacity.
    CP   C                              ; Compare limit and new length.
    JR   C,.bad                         ; Reject an overlong field.
.consume: ; Consume a valid character or extension separator.
    INC  HL                             ; Advance past a validated character or the dot.
    DEC  B                              ; Reduce the remaining command-tail byte count.
    JR   .byte                          ; Continue until a separator or end of tail.
.done: ; Require a nonempty final filename field.
    LD   A,C                            ; Check the final field length.
    OR   A                              ; Set Z for an empty final field.
    JR   Z,.bad                         ; Reject an empty name or a trailing dot.
    RET                                 ; Leave any separating space unconsumed.
.bad: ; Reject an invalid filename field.
    SCF                                 ; Report an invalid name.
    RET                                 ; Return carry to the command parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Validate one character for use in a CP/M 8.3 filename.

cmdChar: ; Check one printable CP/M filename character.
    CP   '!'                            ; Reject control characters and space below '!'.
    RET  C                              ; Reject bytes below '!'.
    CP   $7F                            ; Reject DEL and high-bit bytes.
    JR   NC,.bad                        ; Not printable ASCII.
    CP   '*'                            ; Punctuation before '*' is allowed after '!'.
    JR   C,.upper                       ; Accept this punctuation range.
    CP   '-'                            ; Exclude '*', '+' and ',' before the hyphen.
    JR   C,.bad                         ; Exclude '*', '+' and ','.
    CP   '/'                            ; Reject the path separator.
    JR   Z,.bad                         ; Reject a path separator explicitly.
    CP   ':'                            ; Test the next punctuation range.
    JR   C,.upper                       ; Permit bytes below ':'.
    CP   '@'                            ; Exclude ':', ';', '<', '=', '>' and '?'.
    JR   C,.bad                         ; These include drive and wildcard syntax.
.upper: ; Check the upper ASCII punctuation range.
    CP   '['                            ; Uppercase letters below '[' are accepted.
    JR   C,.ok                          ; Permit digits, punctuation and A through Z.
    CP   '^'                            ; Set the boundary after '[', backslash and ']'.
    JR   C,.bad                         ; Exclude '[', '\\' and ']'.
    CP   '_'                            ; Check the underscore boundary explicitly.
    JR   Z,.bad                         ; Do not admit underscore into an 8.3 field.
.ok: ; Return an accepted filename character.
    OR   A                              ; Clear carry. keep the valid byte.
    RET                                 ; Return the accepted character in A.
.bad: ; Reject forbidden filename punctuation.
    SCF                                 ; Mark this character as invalid for a filename.
    RET                                 ; Return carry to cmdName.

;@ROUTINE IN DE,HL OUT A,ZERO CLOBBERS B,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Compare two drive-plus-8.3-name records for exact equality.

cmdSame: ; Compare twelve-byte drive and 8.3 identities.
    LD   B,12                           ; Compare drive and eleven name/type bytes.
.byte: ; Compare each corresponding filename byte.
    LD   A,(DE)                         ; Read the first FCB's name byte.
    CP   (HL)                           ; Compare it with the corresponding second byte.
    RET  NZ                             ; Return immediately when the identities differ.
    INC  DE                             ; Advance the first name cursor.
    INC  HL                             ; Advance the second name cursor.
    DJNZ .byte                          ; Compare the complete twelve-byte identity.
    XOR  A                              ; Return Z after all bytes match.
    RET                                 ; Carry is clear for the equal-name result.
cmdEnd: ; Exclusive end of command parsing code.
