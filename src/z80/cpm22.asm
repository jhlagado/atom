;==============================================================================
; Atom CP/M 2.2 transient adapter
;==============================================================================
;
; The generated COM places the native Atom core at $0110. The first sixteen
; bytes are supplied by scripts/generate-cpm22.mjs. Source bytes are read from
; BDOS through one random-record cache; output is patched in TPA and published
; through a temporary file only after Atom commits.
;
; The adapter owns five jobs outside the assembler core:
;   1. parse a compact CP/M command tail and choose COM, BIN or Intel HEX;
;   2. discover leading %INCLUDE directives and derive dependency-first parts;
;   3. serve random source bytes from CP/M files through a 128-byte cache;
;   4. materialize IMAGE/PATCH operations in a fixed TPA output window; and
;   5. publish that image transactionally through temporary/backup filenames.
;
; Atom itself remains filesystem-blind. Its ordinary five-byte part descriptors
; use the half-open logical range [0,length); CP_SOURCE_READ_BYTE maps the ordinal
; through the derived order, opens the corresponding FCB and supplies the byte.

; Fixed transient memory plan. Code/immutable data ends below CP_SOURCE_CACHE;
; retained include identities and generated part descriptors occupy the gap up
; to the symbol arena. Symbols, pending records, output image and private stack
; then occupy disjoint high-memory intervals.

CP_BDOS_ENTRY       EQU $0005
CP_SYMBOL_START     EQU $5000
CP_SYMBOL_END       EQU $8000
CP_PENDING_START    EQU $8000
CP_PENDING_END      EQU $9000
CP_OUTPUT_START     EQU $9000
CP_OUTPUT_END       EQU $D780
CP_SOURCE_CACHE     EQU $3E80
CP_SOURCE_CACHE_END EQU $3F00
CP_PART_ORDER       EQU $3F00
CP_PART_ORDER_END   EQU $4000
CP_PART_NAMES       EQU $4000
CP_PART_NAMES_END   EQU $4AF5
CP_PART_DESCRIPTORS EQU $4AF5
CP_PART_DESCRIPTORS_END EQU $4FF0
CP_NAME_COUNT       EQU $4FF0
CP_ORDER_COUNT      EQU $4FF1
CP_DESCRIPTOR_CURSOR EQU $4FF2
CP_ACTIVE_PART      EQU $4FF4
CP_SCAN_MODE        EQU $4FF5
CP_SCAN_INDEX       EQU $4FF6
CP_SCAN_PROGRESS    EQU $4FF7
CP_HEADER_OPEN      EQU $4FF8
CP_RAW_OFFSET       EQU $4FF9
CP_NEXT_VALUE       EQU $4FFB
CP_TARGET_START     EQU $0100
CP_TARGET_CAPACITY  EQU $4780
CP_STACK_TOP        EQU $E400
CP_DMA_FUNCTION     EQU 26
CP_OPEN_FUNCTION    EQU 15
CP_CLOSE_FUNCTION   EQU 16
CP_DELETE_FUNCTION  EQU 19
CP_READ_FUNCTION    EQU 20
CP_RANDOM_READ_FUNCTION EQU 33
CP_WRITE_FUNCTION   EQU 21
CP_MAKE_FUNCTION    EQU 22
CP_RENAME_FUNCTION  EQU 23
CP_PRINT_FUNCTION   EQU 9
CP_COMMAND_LENGTH   EQU $0080
CP_COMMAND_START    EQU $0081

CP_ADAPTER_CODE_START:

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; CP/M standardizes only the 8080 register set. Preserve the Z80 index
; registers promised by Atom's private tool-service client adapter.

CP_BDOS:
    PUSH IX                    ; Protect Atom's first index register from BDOS.
    PUSH IY                    ; Protect the second index register as well.
    CALL CP_BDOS_ENTRY         ; Enter the CP/M dispatcher with function in C.
    POP  IY                    ; Restore IY before returning to the caller.
    POP  IX                    ; Restore IX after the 8080-compatible service.
    RET                        ; Return the BDOS result and flags unchanged.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Move off the CCP stack, parse the command, resolve the source graph, clear the
; tentative RAM image and invoke the unchanged native driver. Only a successful
; sink commit prints the selected output name. Return 0 for success or help, 1
; for resolution/assembly failure, and 2 for command parsing/preflight failure.

CP_ENTRY:
    LD   (CP_SAVED_SP),SP      ; Retain the CCP stack for the final return.
    LD   SP,CP_STACK_TOP       ; Move calls and local pushes to private stack RAM.
    CALL CP_PARSE_COMMAND     ; Validate arguments and prepare input/output names.
    JR   C,CP_COMMAND_FAILED  ; Report a usage or filename error before I/O.
    OR   A                    ; Test whether parsing selected help-only mode.
    JR   NZ,CP_SUCCESS        ; Help was printed; return success without assembly.
    CALL CP_RESOLVE_SOURCE    ; Validate includes and measure each source part.
    JR   C,CP_BUILD_FAILED    ; Stop before assembly if the source graph is invalid.
    LD   HL,CP_OUTPUT_START   ; Point HL at the first byte of the tentative image.
    LD   DE,CP_OUTPUT_START+1 ; Point DE at the next byte to initialise.
    LD   BC,CP_OUTPUT_END-CP_OUTPUT_START-1 ; Count the remaining image bytes.
    LD   (HL),0               ; Initialise the first image byte to zero.
    LDIR                     ; Clear the rest so gaps and reservations are zero.
    LD   IX,CP_DESCRIPTOR     ; Supply the measured source and arena descriptor.
    CALL DR_ASM               ; Assemble all parts into the private RAM image.
    JR   C,CP_ASSEMBLY_FAILED ; Keep the old output untouched after a source error.
    LD   DE,CP_NEWLINE_TEXT   ; Select a leading line break for the success message.
    CALL CP_PRINT             ; Separate the result from any command echo.
    LD   HL,CP_OUTPUT_NAME    ; Point at the selected output's normalized name.
    CALL CP_PRINT_NAME        ; Print the basename and any nonblank extension.
    LD   DE,CP_WRITTEN_TEXT   ; Select the completion suffix.
    CALL CP_PRINT             ; Report success after the sink has committed.
CP_SUCCESS:
    XOR  A                    ; Return status zero for success or help.
    JR   CP_RETURN            ; Restore the CCP stack through the common exit.
CP_COMMAND_FAILED:
    CALL CP_PRINT             ; DE still points at the parser's diagnostic text.
    LD   A,2                  ; Distinguish argument errors from build failures.
    JR   CP_RETURN            ; Restore the CCP stack and return status two.
CP_ASSEMBLY_FAILED:
    PUSH AF                   ; Preserve Atom's status while printing the label.
    LD   DE,CP_ASSEMBLY_TEXT  ; Point at the diagnostic prefix.
    CALL CP_PRINT             ; Print `Atom error ` before the hexadecimal status.
    POP  AF                   ; Recover the original assembler status.
    CALL CP_PRINT_HEX         ; Print the status as two hexadecimal digits.
    LD   A,' '                ; Separate status from the source-part ordinal.
    CALL CP_PUTC              ; Emit the field separator.
    LD   A,(ST_EPART)         ; Load the zero-based source-part ordinal.
    CALL CP_PRINT_HEX         ; Print the part ordinal in hexadecimal.
    LD   A,' '                ; Separate the part from the byte offset.
    CALL CP_PUTC              ; Emit the second field separator.
    LD   HL,(ST_EOFF)         ; Load the source's zero-based byte offset.
    PUSH HL                   ; Preserve its low byte while printing the high byte.
    LD   A,H                  ; Select the high byte of the offset.
    CALL CP_PRINT_HEX         ; Print the high byte first.
    POP  HL                   ; Restore the offset and recover its low byte.
    LD   A,L                  ; Select the low byte of the offset.
    CALL CP_PRINT_HEX         ; Complete the four-digit hexadecimal offset.
    LD   DE,CP_NEWLINE_TEXT   ; Point at the terminating line break.
    CALL CP_PRINT             ; Finish the diagnostic line.
CP_BUILD_FAILED:
    LD   A,1                  ; Return status one for resolution or assembly failure.
CP_RETURN:

; Restore the CCP's original stack before returning its conventional status.

    LD   SP,(CP_SAVED_SP)     ; Restore the caller's command-processor stack.
    RET                       ; Return the status in A to the CCP.

CP_COMMAND_CODE_START:

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept no arguments, one source name, two explicit names, or `?`. With no
; names the checked defaults are INPUT.ASM and OUTPUT.COM. One source derives an
; output name with COM extension. All names are current-drive CP/M 8.3 names.

CP_PARSE_COMMAND:
    XOR  A                    ; Start command parsing with a clear part-state value.
    LD   (CP_ACTIVE_PART),A   ; Discard the previous command's cached part ordinal.
    LD   A,(CP_COMMAND_LENGTH) ; Read the CCP's command-tail byte count.
    LD   B,A                  ; Keep the remaining count beside the HL cursor.
    LD   HL,CP_COMMAND_START  ; Start at the first command-tail character.
    CALL CP_SKIP_SPACES       ; Ignore leading spaces before counting arguments.
    JP   Z,CP_CHECK_AUXILIARY_NAMES ; Empty tail uses the two checked defaults.
    LD   A,B                  ; Inspect the non-space argument length.
    CP   1                    ; A lone question mark is the only help form.
    JR   NZ,CP_COMMAND_SOURCE ; Longer input must begin with a source name.
    LD   A,(HL)               ; Read the sole non-space character.
    CP   '?'                  ; Select help only for the exact `?` argument.
    JR   NZ,CP_COMMAND_SOURCE ; Otherwise validate it as a filename.
    LD   DE,CP_USAGE_TEXT     ; Point at the compact command syntax.
    CALL CP_PRINT             ; Print help without opening files or assembling.
    XOR  A                    ; Start with success status for the help request.
    INC  A                    ; Return nonzero to tell CP_ENTRY to skip assembly.
    RET                       ; Preserve that help marker in A.
CP_COMMAND_SOURCE:
    CALL CP_PARSE_FILENAME    ; Validate the first argument as an 8.3 source name.
    JP   C,CP_BAD_SOURCE_NAME ; Keep source-name errors distinct from output ones.
    CALL CP_SKIP_SPACES       ; Check whether a second name follows the source.
    JR   Z,CP_SINGLE_NAME     ; With one name, derive the output name and type.
    CALL CP_PARSE_FILENAME    ; Validate the explicit output name.
    JP   C,CP_BAD_OUTPUT_NAME ; Report malformed output fields separately.
    CALL CP_SKIP_SPACES       ; Consume separator spaces and test for extra text.
    JP   NZ,CP_BAD_USAGE      ; Reject a third argument or trailing junk.
    JR   CP_COMMAND_NAMES_READY ; Continue with the CCP's normalized FCBs.
CP_SINGLE_NAME:

; The CCP populated default FCB 1 from the sole argument. Copy it to default FCB
; 2 and replace only the extension, retaining the same normalized basename.

    LD   HL,$005C             ; Address the CCP's default source FCB.
    LD   DE,$006C             ; Address the second FCB used for output.
    LD   BC,12                ; Copy drive, basename and extension bytes.
    LDIR                     ; Derive output basename from the source argument.
    LD   HL,CP_COM_EXTENSION  ; Select the conventional `.COM` output type.
    LD   DE,$006C+9           ; Point at the output FCB's three-byte type.
    LD   BC,3                 ; Copy exactly the extension bytes.
    LDIR                     ; Complete the one-argument output default.
CP_COMMAND_NAMES_READY:
    LD   HL,$005C             ; Read the CCP-normalized source FCB.
    LD   DE,CP_INPUT_FCB      ; Store a private copy for BDOS operations.
    LD   BC,12                ; Include drive, basename and extension.
    LDIR                     ; Preserve the selected input filename.
    LD   A,(CP_INPUT_FCB+9)  ; Inspect the first byte of its type field.
    CP   ' '                  ; A blank type means the argument omitted it.
    JR   NZ,CP_INPUT_TYPE_READY ; Keep any explicit source extension.
    LD   HL,CP_ASM_EXTENSION  ; Supply the native source extension `.ASM`.
    LD   DE,CP_INPUT_FCB+9   ; Point at the private FCB's type field.
    LD   BC,3                 ; The CP/M type occupies three bytes.
    LDIR                     ; Complete the input FCB with its default type.
CP_INPUT_TYPE_READY:
    LD   HL,$006C             ; Read the CCP-normalized output FCB.
    LD   DE,CP_OUTPUT_NAME    ; Store its drive-plus-name form for publication.
    LD   BC,12                ; Copy drive, basename and three-byte type.
    LDIR                     ; Retain the caller's requested output name.
    LD   HL,CP_OUTPUT_NAME+9 ; Point at the output extension.
    LD   DE,CP_COM_EXTENSION ; Compare with the default COM format.
    CALL CP_OUTPUT_TYPE_EQUAL ; Check all three extension bytes.
    JR   Z,CP_OUTPUT_TYPE_COM ; Select format zero for COM.
    LD   HL,CP_OUTPUT_NAME+9 ; Reuse HL for another extension comparison.
    LD   DE,CP_BIN_EXTENSION ; Compare with the raw binary format.
    CALL CP_OUTPUT_TYPE_EQUAL ; Check for an exact BIN extension.
    JR   Z,CP_OUTPUT_TYPE_BIN ; Select format one for BIN.
    LD   HL,CP_OUTPUT_NAME+9 ; Test the last supported output extension.
    LD   DE,CP_HEX_EXTENSION ; Compare with the Intel HEX format.
    CALL CP_OUTPUT_TYPE_EQUAL ; Check for an exact HEX extension.
    JR   NZ,CP_BAD_OUTPUT_NAME ; Reject any other output type.
    LD   A,2                  ; Assign format code two to Intel HEX.
    JR   CP_OUTPUT_TYPE_READY ; Save the selected type and preflight filenames.
CP_OUTPUT_TYPE_BIN:
    LD   A,1                  ; Assign format code one to raw BIN.
    JR   CP_OUTPUT_TYPE_READY ; Save the type and continue filename checks.
CP_OUTPUT_TYPE_COM:
    XOR  A                    ; Assign format code zero to CP/M COM.
CP_OUTPUT_TYPE_READY:

; Preserve the normalized input and output names in adapter-owned FCB storage.
; Input defaults to ASM when no type was supplied; output type selects 0=COM,
; 1=BIN or 2=HEX.

    LD   (CP_OUTPUT_FORMAT),A ; Retain the format selected from the extension.
    LD   HL,CP_INPUT_FCB      ; Compare the source identity with the output name.
    LD   DE,CP_OUTPUT_NAME    ; Compare complete twelve-byte drive-plus-name identities.
    CALL CP_NAMES_EQUAL       ; Reject overwriting the file being assembled.
    JR   Z,CP_BAD_NAME_CONFLICT ; Source and output must be distinct files.
    CALL CP_SET_TEMP_FCB      ; Build the transaction's temporary filename.
    CALL CP_CHECK_WORK_NAME   ; Prove it cannot collide with source or existing work.
    RET  C                    ; Stop if temporary-file preflight found a conflict.
    CALL CP_SET_BACKUP_FCB    ; Build the transaction's backup filename.
    CALL CP_CHECK_WORK_NAME   ; Apply the same collision and existence checks.
    RET                       ; Return the final preflight status in carry.

;@ROUTINE IN DE,HL OUT A,B,DE,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Compare the three-byte output-type selectors at DE and HL.

CP_OUTPUT_TYPE_EQUAL:
    LD   B,3                  ; Count the three bytes in a CP/M file type.
CP_OUTPUT_TYPE_BYTE:
    LD   A,(DE)               ; Read the candidate extension byte.
    CP   (HL)                 ; Compare it with the requested extension.
    RET  NZ                   ; Stop on the first mismatch, preserving NZ.
    INC  DE                   ; Advance to the next byte in the candidate.
    INC  HL                   ; Advance to the corresponding expected byte.
    DJNZ CP_OUTPUT_TYPE_BYTE  ; Check all three bytes before reporting equality.
    RET                       ; Return with Z from the final matching comparison.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Prove the temporary name differs from the source and is not already present.

CP_CHECK_WORK_NAME:
    LD   HL,CP_INPUT_FCB      ; Compare the source with the temporary or backup.
    LD   DE,CP_WORK_FCB       ; CP_WORK_FCB holds the auxiliary candidate name.
    CALL CP_NAMES_EQUAL       ; Test all drive, basename and type bytes.
    JR   Z,CP_BAD_NAME_CONFLICT ; Never let publication replace the source.
    JP   CP_AUXILIARY_MUST_NOT_EXIST ; Also require the candidate file to be absent.
CP_BAD_USAGE:
    LD   DE,CP_USAGE_TEXT     ; Select the command syntax diagnostic.
    SCF                      ; Return parser failure to CP_ENTRY.
    RET                       ; Keep the message address in DE.
CP_BAD_SOURCE_NAME:
    LD   DE,CP_SOURCE_NAME_TEXT ; Select the source-name diagnostic.
    SCF                      ; Mark the invalid source argument.
    RET                       ; Return its message address in DE.
CP_BAD_OUTPUT_NAME:
    LD   DE,CP_OUTPUT_NAME_TEXT ; Select the output-name diagnostic.
    SCF                      ; Mark the invalid output argument.
    RET                       ; Return its message address in DE.
CP_BAD_NAME_CONFLICT:
    LD   DE,CP_NAME_CONFLICT_TEXT ; Select the source/output conflict diagnostic.
    SCF                      ; Refuse a colliding output or work filename.
    RET                       ; Return the diagnostic address in DE.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Refuse to claim pre-existing temporary or backup files. CP/M is
; single-tasking, so successful preflight reserves both names until return.

CP_CHECK_AUXILIARY_NAMES:
    CALL CP_SET_TEMP_FCB      ; Build the temporary name for the first check.
    CALL CP_AUXILIARY_MUST_NOT_EXIST ; Reject a pre-existing temporary file.
    RET  C                    ; Do not continue after a collision or I/O error.
    CALL CP_SET_BACKUP_FCB    ; Prepare the backup name for the fall-through check.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require the auxiliary file named by CP_WORK_FCB not to exist.

CP_AUXILIARY_MUST_NOT_EXIST:
    LD   DE,CP_WORK_FCB      ; Address the candidate temporary or backup FCB.
    LD   C,CP_OPEN_FUNCTION  ; Ask BDOS whether the named file already exists.
    CALL CP_BDOS             ; A=FF means no matching directory entry was found.
    INC  A                   ; Convert the not-found result into zero.
    JR   Z,CP_AUXILIARY_AVAILABLE ; Permit publication when the name is unused.
    LD   DE,CP_WORK_FCB      ; Reuse the opened candidate FCB for closing it.
    LD   C,CP_CLOSE_FUNCTION ; Select the matching CP/M close operation.
    CALL CP_BDOS             ; Close the existing candidate file before reporting it.
    LD   DE,CP_AUXILIARY_EXISTS_TEXT ; Select the collision diagnostic.
    SCF                      ; Report that the auxiliary file is occupied.
    RET                       ; Preserve its message pointer in DE.
CP_AUXILIARY_AVAILABLE:
    XOR  A                    ; Clear carry and status for an unused name.
    RET                       ; Allow the caller to check or use the name.

;@ROUTINE IN B,HL OUT A,B,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Advance HL and reduce B past leading command-tail spaces.

CP_SKIP_SPACES:
    LD   A,B                  ; Check whether any command-tail bytes remain.
    OR   A                    ; Set Z when the cursor has reached the tail end.
    RET  Z                    ; Leave HL at the end when no bytes remain.
    LD   A,(HL)               ; Inspect the next unconsumed character.
    CP   ' '                  ; CP/M command separators are ordinary spaces.
    RET  NZ                   ; Stop at the first non-space argument character.
    INC  HL                   ; Consume one leading or separating space.
    DEC  B                    ; Keep the remaining-byte count in step with HL.
    JR   CP_SKIP_SPACES       ; Skip a run of spaces before returning.

;@ROUTINE IN B,HL OUT A,B,HL,CARRY CLOBBERS C,D,ZERO,SIGN,PARITY,HALFCARRY
; Parse one unquoted, current-drive 8.3 filename without consuming its
; trailing space. Carry reports an empty, overlong, wildcard, drive-qualified,
; or otherwise invalid field.

CP_PARSE_FILENAME:
    LD   D,8                  ; Start with the eight-character basename limit.
    LD   C,0                  ; Count characters in the current name field.
CP_PARSE_FILENAME_BYTE:
    LD   A,B                  ; Check whether another tail character is available.
    OR   A                    ; Set Z only when the bounded command field ends.
    JR   Z,CP_FILENAME_DONE   ; Validate the final name or extension length.
    LD   A,(HL)               ; Read the next unquoted filename character.
    CP   ' '                  ; A space ends this filename without consuming it.
    JR   Z,CP_FILENAME_DONE   ; Leave the separator for CP_SKIP_SPACES.
    CP   '.'                  ; A dot switches from basename to extension.
    JR   NZ,CP_FILENAME_DATA  ; Otherwise validate a character in the current field.
    LD   A,D                  ; D is 8 for the basename or 3 for the extension.
    CP   8                    ; Accept a dot only after the basename field.
    JR   NZ,CP_FILENAME_FAILURE ; Reject a second dot in the extension.
    LD   A,C                  ; Require at least one basename character.
    OR   A                    ; Test the current field's character count.
    JR   Z,CP_FILENAME_FAILURE ; Reject a leading dot and empty basename.
    LD   D,3                  ; Apply the CP/M three-character extension limit.
    LD   C,0                  ; Start counting extension characters.
    JR   CP_FILENAME_CONSUME  ; Consume the separator dot without counting it.
CP_FILENAME_DATA:
    CALL CP_FILENAME_CHAR    ; Reject characters outside the permitted CP/M set.
    RET  C                    ; Propagate an invalid-character result immediately.
    INC  C                    ; Count this character in the current field.
    LD   A,D                  ; Load the basename or extension capacity.
    CP   C                    ; Compare capacity against the new character count.
    JR   C,CP_FILENAME_FAILURE ; Reject the first character beyond that capacity.
CP_FILENAME_CONSUME:
    INC  HL                   ; Advance past a validated character or the dot.
    DEC  B                    ; Reduce the remaining command-tail byte count.
    JR   CP_PARSE_FILENAME_BYTE ; Continue until a separator or end of tail.
CP_FILENAME_DONE:
    LD   A,C                  ; Inspect the final basename or extension length.
    OR   A                    ; Set Z for an empty final field.
    JR   Z,CP_FILENAME_FAILURE ; Reject an empty name or a trailing dot.
    RET                       ; Leave any separating space unconsumed.
CP_FILENAME_FAILURE:
    SCF                      ; Report the empty, invalid or overlong name field.
    RET                       ; Return carry to the command parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Validate one character for use in a CP/M 8.3 filename.

CP_FILENAME_CHAR:
    CP   '!'                  ; Reject control characters and space below '!'.
    RET  C                    ; Carry identifies a character below the allowed set.
    CP   $7F                  ; Exclude DEL and all bytes above the 7-bit range.
    JR   NC,CP_FILENAME_CHAR_BAD ; Reject those non-printable or extended bytes.
    CP   '*'                  ; Punctuation before '*' is allowed after '!'.
    JR   C,CP_FILENAME_CHAR_HIGH ; Continue checking printable letters and symbols.
    CP   '-'                  ; Exclude '*', '+' and ',' before the hyphen.
    JR   C,CP_FILENAME_CHAR_BAD ; CP/M treats these as wildcard or field syntax.
    CP   '/'                  ; The slash is not a current-drive filename character.
    JR   Z,CP_FILENAME_CHAR_BAD ; Reject a path separator explicitly.
    CP   ':'                  ; Characters below ':' pass this punctuation range.
    JR   C,CP_FILENAME_CHAR_HIGH ; Skip reserved punctuation when the byte is below ':'.
    CP   '@'                  ; Exclude ':', ';', '<', '=', '>' and '?'.
    JR   C,CP_FILENAME_CHAR_BAD ; These include drive and wildcard syntax.
CP_FILENAME_CHAR_HIGH:
    CP   '['                  ; Uppercase letters below '[' are accepted.
    JR   C,CP_FILENAME_CHAR_OK ; Permit digits, punctuation and A through Z.
    CP   '^'                  ; Set the boundary after '[', backslash and ']'.
    JR   C,CP_FILENAME_CHAR_BAD ; Those bytes conflict with CP/M name conventions.
    CP   '_'                  ; Check the underscore boundary explicitly.
    JR   Z,CP_FILENAME_CHAR_BAD ; Do not admit underscore into an 8.3 field.
CP_FILENAME_CHAR_OK:
    OR   A                    ; Clear carry while retaining the validated byte.
    RET                       ; Return the accepted character in A.
CP_FILENAME_CHAR_BAD:
    SCF                      ; Mark this character as invalid for a filename.
    RET                       ; Return carry to CP_PARSE_FILENAME.

;@ROUTINE IN DE,HL OUT A,ZERO CLOBBERS B,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Compare two drive-plus-8.3-name records for exact equality.

CP_NAMES_EQUAL:
    LD   B,12                 ; Compare the drive byte and eleven name/type bytes.
CP_NAMES_EQUAL_BYTE:
    LD   A,(DE)               ; Read one byte from the first normalized FCB name.
    CP   (HL)                 ; Compare it with the corresponding second byte.
    RET  NZ                   ; Return immediately when the identities differ.
    INC  DE                   ; Advance the first name cursor.
    INC  HL                   ; Advance the second name cursor.
    DJNZ CP_NAMES_EQUAL_BYTE  ; Compare the complete twelve-byte identity.
    XOR  A                    ; Return Z after all bytes match.
    RET                       ; Carry is clear for the equal-name result.
CP_COMMAND_CODE_END:

CP_SOURCE_CODE_START:

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare a blank ordinary FCB whose name/type fields are space-filled.

CP_CLEAR_INPUT_FCB:
    LD   DE,CP_INPUT_FCB
    XOR  A
    LD   (DE),A
    INC  DE
    LD   B,11
    LD   A,' '
    CALL CP_CLEAR_WORK_FCB
    JP   CP_CLEAR_FCB_TAIL

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reject output, temporary or backup names that collide with the source name.

CP_CHECK_SOURCE_CONFLICT:
    LD   HL,CP_INPUT_FCB
    LD   DE,CP_OUTPUT_NAME
    CALL CP_NAMES_EQUAL
    JR   Z,CP_SOURCE_NAME_CONFLICT
    CALL CP_SET_TEMP_FCB
    LD   HL,CP_INPUT_FCB
    LD   DE,CP_WORK_FCB
    CALL CP_NAMES_EQUAL
    JR   Z,CP_SOURCE_NAME_CONFLICT
    CALL CP_SET_BACKUP_FCB
    LD   HL,CP_INPUT_FCB
    LD   DE,CP_WORK_FCB
    CALL CP_NAMES_EQUAL
    JR   Z,CP_SOURCE_NAME_CONFLICT
    XOR  A
    RET
CP_SOURCE_NAME_CONFLICT:
    LD   DE,CP_NAME_CONFLICT_TEXT
    SCF
    RET

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Read one logical source byte through a 128-byte random-record cache. The
; pre-scan proves every requested record exists for the life of this transient.

CP_SOURCE_READ_BYTE:
    JP   CP_RESOLVED_READ_BYTE

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve the root source and its leading %INCLUDE graph. Names are retained
; as exact CP/M 8.3 identities, while descriptors are emitted in dependency-
; first order. No intermediate source-order file is involved.

CP_RESOLVE_SOURCE:
    XOR  A
    LD   (CP_DESCRIPTOR),A
    LD   (CP_ORDER_COUNT),A
    LD   (CP_SCAN_INDEX),A
    INC  A
    LD   (CP_NAME_COUNT),A
    LD   HL,CP_INPUT_FCB+1
    LD   DE,CP_PART_NAMES
    LD   BC,11
    LDIR
    LD   A,$FF
    LD   (CP_ACTIVE_PART),A

; First discover every exact name reachable from the root.

CP_DISCOVER_PART:
    XOR  A
    LD   (CP_SCAN_MODE),A
    LD   A,(CP_SCAN_INDEX)
    CALL CP_SCAN_PART
    JP   C,CP_RESOLVE_FAILURE
    LD   HL,CP_SCAN_INDEX
    INC  (HL)
    LD   A,(CP_NAME_COUNT)
    CP   (HL)
    JR   NZ,CP_DISCOVER_PART

; Repeatedly emit a part whose dependencies have all been emitted. Bit 7 of the
; first retained-name byte records that state; comparisons and FCB reconstruction
; mask it away. Failure to make progress proves a cycle without recursion.

CP_TOPO_PASS:
    XOR  A
    LD   (CP_SCAN_INDEX),A
    LD   (CP_SCAN_PROGRESS),A
CP_TOPO_PART:
    LD   A,(CP_SCAN_INDEX)
    CALL CP_NAME_POINTER
    BIT  7,(HL)
    JR   NZ,CP_TOPO_NEXT
    LD   A,1
    LD   (CP_SCAN_MODE),A
    LD   A,(CP_SCAN_INDEX)
    CALL CP_SCAN_PART
    JP   C,CP_RESOLVE_FAILURE
    OR   A
    JR   NZ,CP_TOPO_NEXT
    LD   A,(CP_ORDER_COUNT)
    LD   E,A
    LD   D,CP_PART_ORDER/256
    LD   A,(CP_SCAN_INDEX)
    LD   (DE),A
    CALL CP_NAME_POINTER
    SET  7,(HL)
    LD   HL,CP_ORDER_COUNT
    INC  (HL)
    LD   A,1
    LD   (CP_SCAN_PROGRESS),A
CP_TOPO_NEXT:
    LD   HL,CP_SCAN_INDEX
    INC  (HL)
    LD   A,(CP_NAME_COUNT)
    CP   (HL)
    JR   NZ,CP_TOPO_PART
    LD   A,(CP_ORDER_COUNT)
    LD   HL,CP_NAME_COUNT
    CP   (HL)
    JR   Z,CP_BUILD_DESCRIPTORS
    LD   A,(CP_SCAN_PROGRESS)
    OR   A
    JR   NZ,CP_TOPO_PASS
    LD   DE,CP_INCLUDE_CYCLE_TEXT
    JR   CP_RESOLVE_FAILURE

; Measure the already validated parts in final order and build the ordinary
; native five-byte descriptors. Their start is logical zero and their end is the
; measured 16-bit byte length; source storage itself remains in CP/M files.

CP_BUILD_DESCRIPTORS:
    XOR  A
    LD   (CP_SCAN_INDEX),A
    LD   HL,CP_PART_DESCRIPTORS
    LD   (CP_DESCRIPTOR_CURSOR),HL
CP_BUILD_DESCRIPTOR:
    LD   A,(CP_SCAN_INDEX)
    LD   E,A
    LD   D,CP_PART_ORDER/256
    LD   A,(DE)
    CALL CP_OPEN_PART
    JP   C,CP_RESOLVE_FAILURE
    LD   HL,0
CP_MEASURE_BYTE:
    CALL CP_NEXT_SOURCE_BYTE
    JR   NC,CP_MEASURE_BYTE
    OR   A
    JP   NZ,CP_RESOLVE_IO
    CALL CP_APPEND_DESCRIPTOR
    LD   HL,CP_SCAN_INDEX
    INC  (HL)
    LD   A,(CP_NAME_COUNT)
    CP   (HL)
    JR   NZ,CP_BUILD_DESCRIPTOR
    LD   A,(CP_NAME_COUNT)
    LD   (CP_DESCRIPTOR),A
    XOR  A
    RET
CP_RESOLVE_IO:
    LD   HL,CP_INPUT_FCB
    CALL CP_PRINT_NAME
    LD   DE,CP_READ_FAILED_TEXT
CP_RESOLVE_FAILURE:
    CALL CP_PRINT
    SCF
    RET

;@ROUTINE IN A OUT A,DE,CARRY CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Scan and validate one source header. Mode zero discovers names; mode one
; reports A=1 when any dependency has not yet been emitted.

CP_SCAN_PART:
    CALL CP_OPEN_PART
    JR   C,CP_SCAN_FAILURE
    LD   A,1
    LD   (CP_HEADER_OPEN),A
    LD   HL,0
CP_SCAN_LINE:

; Blank space, line endings and comment lines remain in the header. The first
; ordinary source byte closes it permanently; a later percent directive fails.

    CALL CP_NEXT_SOURCE_BYTE
    JR   C,CP_SCAN_EOF
    CP   ' '
    JR   Z,CP_SCAN_LINE
    CP   9
    JR   Z,CP_SCAN_LINE
    CP   13
    JR   Z,CP_SCAN_LINE
    CP   10
    JR   Z,CP_SCAN_LINE
    CP   ';'
    JR   Z,CP_SCAN_SKIP_LINE
    CP   '%'
    JR   Z,CP_SCAN_DIRECTIVE
    XOR  A
    LD   (CP_HEADER_OPEN),A
CP_SCAN_SKIP_LINE:
    CALL CP_SKIP_SOURCE_LINE
    JR   NC,CP_SCAN_LINE
    OR   A
    JR   Z,CP_SCAN_COMPLETE
    JR   CP_SCAN_IO
CP_SCAN_DIRECTIVE:
    LD   A,(CP_HEADER_OPEN)
    OR   A
    JR   Z,CP_SCAN_INVALID
    CALL CP_PARSE_INCLUDE
    JR   C,CP_SCAN_FAILURE
    OR   A
    JR   NZ,CP_SCAN_DONE
    JR   CP_SCAN_LINE
CP_SCAN_EOF:
    OR   A
    JR   NZ,CP_SCAN_IO
CP_SCAN_COMPLETE:
    XOR  A
CP_SCAN_DONE:
    RET
CP_SCAN_IO:
    LD   HL,CP_INPUT_FCB
    CALL CP_PRINT_NAME
    LD   DE,CP_READ_FAILED_TEXT
    JR   CP_SCAN_FAILURE
CP_SCAN_INVALID:
    LD   DE,CP_INVALID_INCLUDE_TEXT
CP_SCAN_FAILURE:
    SCF
    RET

;@ROUTINE IN HL OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the current source ordinal and byte range to the part descriptor table.

CP_APPEND_DESCRIPTOR:
    LD   DE,(CP_DESCRIPTOR_CURSOR)
    LD   A,(CP_SCAN_INDEX)
    LD   (DE),A
    INC  DE
    XOR  A
    LD   (DE),A
    INC  DE
    LD   (DE),A
    INC  DE
    LD   A,L
    LD   (DE),A
    INC  DE
    LD   A,H
    LD   (DE),A
    INC  DE
    LD   (CP_DESCRIPTOR_CURSOR),DE
    RET

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse INCLUDE, one quoted current-drive 8.3 filename, and the rest of its
; directive line. Discovery records the child; ordering checks its emitted bit.

CP_PARSE_INCLUDE:
    LD   DE,CP_INCLUDE_WORD
    LD   B,7
CP_INCLUDE_WORD_BYTE:
    CALL CP_NEXT_SOURCE_BYTE
    JP   C,CP_INCLUDE_INVALID
    CP   'a'
    JR   C,CP_INCLUDE_WORD_CASED
    CP   'z'+1
    JR   NC,CP_INCLUDE_WORD_CASED
    AND  $DF
CP_INCLUDE_WORD_CASED:
    EX   DE,HL
    CP   (HL)
    INC  HL
    EX   DE,HL
    JP   NZ,CP_INCLUDE_INVALID
    DJNZ CP_INCLUDE_WORD_BYTE
    CALL CP_NEXT_SOURCE_BYTE
    JP   C,CP_INCLUDE_INVALID
    CP   ' '
    JR   Z,CP_INCLUDE_SPACE
    CP   9
    JP   NZ,CP_INCLUDE_INVALID
CP_INCLUDE_SPACE:
    CALL CP_NEXT_SOURCE_BYTE
    JP   C,CP_INCLUDE_INVALID
    CP   ' '
    JR   Z,CP_INCLUDE_SPACE
    CP   9
    JR   Z,CP_INCLUDE_SPACE
    CP   '"'
    JP   NZ,CP_INCLUDE_INVALID
    CALL CP_CLEAR_INCLUDE_FCB
    PUSH IX
    CALL CP_PARSE_INCLUDE_NAME
    POP  IX
    RET  C
CP_INCLUDE_TRAILING:
    CALL CP_NEXT_SOURCE_BYTE
    JR   C,CP_INCLUDE_TRAILING_EOF
    CP   ' '
    JR   Z,CP_INCLUDE_TRAILING
    CP   9
    JR   Z,CP_INCLUDE_TRAILING
    CP   ';'
    JR   Z,CP_INCLUDE_SKIP_COMMENT
    CP   13
    JR   Z,CP_INCLUDE_READY
    CP   10
    JP   NZ,CP_INCLUDE_INVALID
CP_INCLUDE_READY:

; Deduplicate by normalized eleven-byte CP/M identity. During discovery this may
; append a name; during ordering it reports whether the child is already emitted.

    PUSH IX
    PUSH HL
    CALL CP_FIND_OR_ADD_NAME
    POP  HL
    POP  IX
    RET  C
    PUSH HL
    CALL CP_VISIT_INCLUDED_CHILD
    POP  HL
    RET
CP_INCLUDE_SKIP_COMMENT:
    CALL CP_SKIP_SOURCE_LINE
    JR   C,CP_INCLUDE_TRAILING_EOF
    JR   CP_INCLUDE_READY
CP_INCLUDE_TRAILING_EOF:
    OR   A
    JP   NZ,CP_INCLUDE_INVALID
    JR   CP_INCLUDE_READY
CP_INCLUDE_INVALID:
    LD   DE,CP_INVALID_INCLUDE_TEXT
    SCF
    RET

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted include filename into the working CP/M FCB.

CP_PARSE_INCLUDE_NAME:
    LD   IX,CP_WORK_FCB+1
    LD   D,8
    LD   C,0
CP_INCLUDE_NAME_BYTE:
    CALL CP_NEXT_SOURCE_BYTE
    JP   C,CP_INCLUDE_NAME_BAD
    CP   '"'
    JR   Z,CP_INCLUDE_NAME_DONE
    CP   '.'
    JR   NZ,CP_INCLUDE_NAME_DATA
    LD   A,D
    CP   8
    JP   NZ,CP_INCLUDE_NAME_BAD
    LD   A,C
    OR   A
    JP   Z,CP_INCLUDE_NAME_BAD
    LD   IX,CP_WORK_FCB+9
    LD   D,3
    LD   C,0
    JR   CP_INCLUDE_NAME_BYTE
CP_INCLUDE_NAME_DATA:
    CP   'a'
    JR   C,CP_INCLUDE_NAME_CASED
    CP   'z'+1
    JR   NC,CP_INCLUDE_NAME_CASED
    AND  $DF
CP_INCLUDE_NAME_CASED:
    CALL CP_FILENAME_CHAR
    JP   C,CP_INCLUDE_NAME_BAD
    INC  C
    LD   B,A
    LD   A,D
    CP   C
    JP   C,CP_INCLUDE_NAME_BAD
    LD   A,B
    LD   (IX+0),A
    INC  IX
    JR   CP_INCLUDE_NAME_BYTE
CP_INCLUDE_NAME_DONE:
    LD   A,C
    OR   A
    RET  NZ
CP_INCLUDE_NAME_BAD:
    LD   DE,CP_INVALID_INCLUDE_TEXT
    SCF
    RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Visit a discovered include child when dependency scanning is active.

CP_VISIT_INCLUDED_CHILD:
    LD   E,A
    LD   A,(CP_SCAN_MODE)
    OR   A
    RET  Z
    LD   A,E
    CALL CP_NAME_POINTER
    BIT  7,(HL)
    LD   A,0
    RET  NZ
    INC  A
    RET

;@ROUTINE OUT A CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the working include FCB to a blank 8.3 filename.

CP_CLEAR_INCLUDE_FCB:
    LD   DE,CP_WORK_FCB
    XOR  A
    LD   (DE),A
    INC  DE
    LD   B,11
    LD   A,' '
    CALL CP_CLEAR_WORK_FCB
    JP   CP_CLEAR_FCB_TAIL

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains.

CP_FIND_OR_ADD_NAME:
    LD   C,0
CP_FIND_NAME_LOOP:
    LD   A,(CP_NAME_COUNT)
    CP   C
    JR   Z,CP_ADD_NAME
    LD   A,C
    CALL CP_NAME_POINTER
    LD   IX,CP_WORK_FCB+1
    LD   B,11
CP_FIND_NAME_BYTE:
    LD   A,(HL)
    AND  $7F
    CP   (IX+0)
    JR   NZ,CP_FIND_NAME_NEXT
    INC  HL
    INC  IX
    DJNZ CP_FIND_NAME_BYTE
    LD   A,C
    OR   A
    RET
CP_FIND_NAME_NEXT:
    INC  C
    JR   CP_FIND_NAME_LOOP
CP_ADD_NAME:

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C
    CP   255
    JR   Z,CP_NAME_CAPACITY
    PUSH AF
    CALL CP_NAME_POINTER
    EX   DE,HL
    LD   HL,CP_WORK_FCB+1
    LD   BC,11
    LDIR
    LD   HL,CP_NAME_COUNT
    INC  (HL)
    POP  AF
    OR   A
    RET
CP_NAME_CAPACITY:
    LD   DE,CP_SOURCE_CAPACITY_TEXT
    SCF
    RET

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

CP_NAME_POINTER:
    LD   L,A
    LD   H,0
    LD   D,H
    LD   E,L
    ADD  HL,HL
    ADD  HL,HL
    ADD  HL,DE
    ADD  HL,HL
    ADD  HL,DE
    LD   DE,CP_PART_NAMES
    ADD  HL,DE
    RET

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the ordinary input FCB from one retained name.

CP_OPEN_PART:
    PUSH AF
    CALL CP_CLEAR_INPUT_FCB
    POP  AF
    CALL CP_NAME_POINTER
    LD   DE,CP_INPUT_FCB+1
    LD   B,11
CP_OPEN_NAME_BYTE:
    LD   A,(HL)
    AND  $7F
    LD   (DE),A
    INC  HL
    INC  DE
    DJNZ CP_OPEN_NAME_BYTE
    CALL CP_CHECK_SOURCE_CONFLICT
    RET  C
    LD   DE,CP_INPUT_FCB
    LD   C,CP_OPEN_FUNCTION
    CALL CP_BDOS
    INC  A
    JR   Z,CP_OPEN_FAILURE
    LD   A,1
    LD   (CP_SOURCE_CACHE_KEY),A
    XOR  A
    RET
CP_OPEN_FAILURE:
    LD   HL,CP_INPUT_FCB
    CALL CP_PRINT_NAME
    LD   DE,CP_READ_FAILED_TEXT
    SCF
    RET

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the next raw source byte and advance HL. Carry with A=0 is EOF or an
; unsuccessful CP/M random read; carry with A=2 means the 16-bit offset wrapped.
; BC and DE survive for parsers.

CP_NEXT_SOURCE_BYTE:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL CP_RAW_SOURCE_BYTE
    POP  HL
    POP  DE
    POP  BC
    RET  C
    LD   (CP_NEXT_VALUE),A
    INC  HL
    LD   A,H
    OR   L
    JR   Z,CP_SOURCE_TOO_LONG
    LD   A,(CP_NEXT_VALUE)
    OR   A
    RET
CP_SOURCE_TOO_LONG:

; Wrapping after a successful byte would require a 65,536-byte part, outside the
; native 16-bit logical-offset contract.

    LD   A,2
    SCF
    RET

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Align the logical offset to its 128-byte CP/M record base. The cache key stores
; that aligned byte offset; the FCB receives the same value divided by 128. A miss
; installs the source cache as DMA, reads the record, then uses the low seven bits.

CP_RAW_SOURCE_BYTE:
    LD   (CP_RAW_OFFSET),HL
    LD   A,L
    AND  $80
    LD   E,A
    LD   D,H
    LD   HL,(CP_SOURCE_CACHE_KEY)
    OR   A
    SBC  HL,DE
    JR   Z,CP_RAW_CACHE_READY
CP_RAW_CACHE_MISS:
    LD   (CP_SOURCE_CACHE_KEY),DE
    RLC  E
    LD   A,D
    ADD  A,A
    OR   E
    LD   (CP_INPUT_FCB+33),A
    LD   A,D
    RLCA
    AND  1
    LD   (CP_INPUT_FCB+34),A
    LD   DE,CP_SOURCE_CACHE
    LD   C,CP_DMA_FUNCTION
    CALL CP_BDOS
    LD   DE,CP_INPUT_FCB
    LD   C,CP_RANDOM_READ_FUNCTION
    CALL CP_BDOS
    OR   A
    JR   NZ,CP_RAW_READ_EOF
CP_RAW_CACHE_READY:
    LD   HL,(CP_RAW_OFFSET)
    SET  7,L
    LD   H,CP_SOURCE_CACHE/256
    LD   A,(HL)
    CP   $1A
    JR   Z,CP_RAW_EOF
    OR   A
    RET
CP_RAW_READ_EOF:
CP_RAW_EOF:
    XOR  A
    SCF
    RET

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Consume source bytes through the next CR, LF or end of file.

CP_SKIP_SOURCE_LINE:
    CALL CP_NEXT_SOURCE_BYTE
    RET  C
    CP   13
    RET  Z
    CP   10
    JR   NZ,CP_SKIP_SOURCE_LINE
    RET

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Open a part on ordinal change, then return one byte. A line-leading percent
; is changed to a semicolon after preflight has proved it is %INCLUDE.

CP_RESOLVED_READ_BYTE:
    LD   E,A
    LD   A,(CP_ACTIVE_PART)
    CP   E
    JR   Z,CP_RESOLVED_SOURCE_READY
    PUSH BC
    PUSH HL
    LD   A,E
    LD   (CP_ACTIVE_PART),A
    LD   D,CP_PART_ORDER/256
    LD   A,(DE)
    CALL CP_OPEN_PART
    POP  HL
    POP  BC
CP_RESOLVED_SOURCE_READY:
    PUSH BC
    PUSH HL
    CALL CP_RAW_SOURCE_BYTE
    POP  HL
    POP  BC
    RET  C
    CP   '%'
    JR   Z,CP_RESOLVED_PERCENT
    OR   A
    RET
CP_RESOLVED_PERCENT:
    PUSH HL
    CALL CP_PERCENT_IS_DIRECTIVE
    POP  HL
    JR   Z,CP_RESOLVED_DIRECTIVE
    LD   A,'%'
    OR   A
    RET
CP_RESOLVED_DIRECTIVE:

; Masking only the leading percent is sufficient: Atom's tokenizer treats the
; complete remainder of the directive line as a semicolon comment.

    LD   A,';'
    OR   A
    RET

;@ROUTINE IN HL OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Decide whether a percent character begins a recognized host directive.

CP_PERCENT_IS_DIRECTIVE:
    LD   A,H
    OR   L
    RET  Z
    DEC  HL
CP_PERCENT_PREFIX:
    PUSH HL
    CALL CP_RAW_SOURCE_BYTE
    POP  HL
    CP   13
    JR   Z,CP_PERCENT_YES
    CP   10
    JR   Z,CP_PERCENT_YES
    CP   ' '
    JR   Z,CP_PERCENT_PREVIOUS
    CP   9
    RET  NZ
CP_PERCENT_PREVIOUS:
    LD   A,H
    OR   L
    JR   Z,CP_PERCENT_YES
    DEC  HL
    JR   CP_PERCENT_PREFIX
CP_PERCENT_YES:
    XOR  A
    RET
CP_SOURCE_CODE_END:

; Atom sink entries supplied directly in place of the fail-closed host stubs. The
; fixed RAM image makes IMAGE and PATCH constant-time memory writes; filesystem
; publication is delayed until COMMIT.

CP_OUTPUT_CODE_START:
HS_SCBEG:

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a fresh tentative generation. No file is created until COMMIT.

HS_BEG:
    XOR  A
    LD   (CP_OUTPUT_OPEN),A
    LD   (CP_BACKED_UP),A
    RET

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Store one IMAGE or byte-PATCH value in the private CP/M target image.

HS_IB:
HS_PB:

; IMAGE and byte PATCH share the same address translation because both write the
; still-private TPA image. The core has already proved capacity and patch order.

    PUSH AF
    LD   DE,CP_OUTPUT_START-CP_TARGET_START
    ADD  HL,DE
    POP  AF
    LD   (HL),A
    XOR  A
    RET

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Store one little-endian word at its translated logical address.

HS_PW:
    EX   DE,HL
    LD   BC,CP_OUTPUT_START-CP_TARGET_START
    ADD  HL,BC
    LD   (HL),E
    INC  HL
    LD   (HL),D
    XOR  A
    RET

;@ROUTINE IN IX,HL,DE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Convert the final logical cursor to image length, create the temporary file and
; serialize the selected format. COM and BIN write CP/M records from the RAM
; image; HEX streams records through the shared final-image helper below.

HS_CMT:
    LD   DE,CP_TARGET_START
    OR   A
    SBC  HL,DE
    LD   (CP_OUTPUT_REMAINING),HL
    LD   HL,CP_OUTPUT_START
    LD   (CP_OUTPUT_CURSOR),HL
    CALL CP_SET_TEMP_FCB
    LD   DE,CP_WORK_FCB
    LD   C,CP_DELETE_FUNCTION
    CALL CP_BDOS
    CALL CP_SET_TEMP_FCB
    LD   DE,CP_WORK_FCB
    LD   C,CP_MAKE_FUNCTION
    CALL CP_BDOS
    INC  A
    JP   Z,CP_COMMIT_FAILURE
    LD   A,1
    LD   (CP_OUTPUT_OPEN),A
    LD   A,(CP_OUTPUT_FORMAT)
    CP   2
    JR   NZ,CP_WRITE_LOOP
    CALL CP_WRITE_HEX
    JP   C,CP_COMMIT_FAILURE
    JR   CP_WRITE_CLOSE
CP_WRITE_LOOP:
    LD   HL,(CP_OUTPUT_REMAINING)
    LD   A,H
    OR   L
    JR   Z,CP_WRITE_CLOSE
    LD   DE,(CP_OUTPUT_CURSOR)
    LD   C,CP_DMA_FUNCTION
    CALL CP_BDOS
    LD   DE,CP_WORK_FCB
    LD   C,CP_WRITE_FUNCTION
    CALL CP_BDOS
    OR   A
    JP   NZ,CP_COMMIT_FAILURE
    LD   HL,(CP_OUTPUT_CURSOR)
    LD   DE,128
    ADD  HL,DE
    LD   (CP_OUTPUT_CURSOR),HL
    LD   HL,(CP_OUTPUT_REMAINING)
    LD   DE,128
    OR   A
    SBC  HL,DE
    JR   NC,CP_WRITE_MORE
    LD   HL,0
CP_WRITE_MORE:
    LD   (CP_OUTPUT_REMAINING),HL
    JR   CP_WRITE_LOOP
CP_WRITE_CLOSE:

; Publication transaction: close temp, defensively remove the backup name that
; preflight required to be absent, rename an existing output to backup, rename
; temp to final, then delete the backup.

    LD   DE,CP_WORK_FCB
    LD   C,CP_CLOSE_FUNCTION
    CALL CP_BDOS
    INC  A
    JP   Z,CP_COMMIT_FAILURE
    XOR  A
    LD   (CP_OUTPUT_OPEN),A
    CALL CP_SET_BACKUP_FCB
    LD   DE,CP_WORK_FCB
    LD   C,CP_DELETE_FUNCTION
    CALL CP_BDOS
    LD   HL,CP_OUTPUT_NAME
    LD   DE,CP_WORK_FCB
    CALL CP_BUILD_RENAME
    LD   DE,CP_RENAME_FCB
    LD   C,CP_RENAME_FUNCTION
    CALL CP_BDOS
    INC  A
    JR   Z,CP_NO_BACKUP
    LD   A,1
    LD   (CP_BACKED_UP),A
CP_NO_BACKUP:
    CALL CP_SET_TEMP_FCB
    LD   HL,CP_WORK_FCB
    LD   DE,CP_OUTPUT_NAME
    CALL CP_BUILD_RENAME
    LD   DE,CP_RENAME_FCB
    LD   C,CP_RENAME_FUNCTION
    CALL CP_BDOS
    INC  A
    JP   Z,CP_COMMIT_FAILURE
    CALL CP_SET_BACKUP_FCB
    LD   DE,CP_WORK_FCB
    LD   C,CP_DELETE_FUNCTION
    CALL CP_BDOS
    XOR  A
    LD   (CP_BACKED_UP),A
    RET
CP_COMMIT_FAILURE:
    LD   A,1
    SCF
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close/delete any temporary output and restore the backup if commit had already
; moved the previous final file aside. Cleanup is idempotent for early failures.

HS_ABORT:
    LD   A,(CP_OUTPUT_OPEN)
    OR   A
    JR   Z,CP_ABORT_DELETE
    LD   DE,CP_WORK_FCB
    LD   C,CP_CLOSE_FUNCTION
    CALL CP_BDOS
CP_ABORT_DELETE:
    CALL CP_SET_TEMP_FCB
    LD   DE,CP_WORK_FCB
    LD   C,CP_DELETE_FUNCTION
    CALL CP_BDOS
    LD   A,(CP_BACKED_UP)
    OR   A
    JR   Z,CP_ABORT_DONE
    CALL CP_SET_BACKUP_FCB
    LD   HL,CP_WORK_FCB
    LD   DE,CP_OUTPUT_NAME
    CALL CP_BUILD_RENAME
    LD   DE,CP_RENAME_FCB
    LD   C,CP_RENAME_FUNCTION
    CALL CP_BDOS
CP_ABORT_DONE:
    XOR  A
    LD   (CP_OUTPUT_OPEN),A
    LD   (CP_BACKED_UP),A
    RET

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Convert the tentative binary image to Intel HEX while streaming 128-byte
; CP/M records from the source cache. The binary image remains in place for
; PATCH application until Atom calls this routine.

CP_WRITE_HEX:
    CALL ZTS_CPM_HEX_BEGIN
    LD   HL,CP_TARGET_START
    LD   (CP_HEX_ADDRESS),HL
    CALL ZTS_CPM_HEX_SEGMENT
    JP   ZTS_CPM_HEX_END

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Route final-image writer requests through the index-preserving BDOS wrapper.

ZTS_CPM_FINAL_BDOS:
    JP   CP_BDOS
ZTS_CPM_FINAL_FCB EQU CP_WORK_FCB
ZTS_CPM_FINAL_DMA EQU CP_SOURCE_CACHE
ZTS_CPM_FINAL_SOURCE_CURSOR EQU CP_OUTPUT_CURSOR
ZTS_CPM_FINAL_REMAINING EQU CP_OUTPUT_REMAINING
ZTS_CPM_FINAL_ADDRESS EQU CP_HEX_ADDRESS
ZTS_CPM_FINAL_DMA_CURSOR EQU CP_HEX_CURSOR
ZTS_CPM_FINAL_DMA_COUNT EQU CP_HEX_COUNT
ZTS_CPM_FINAL_ERROR EQU CP_HEX_ERROR
ZTS_CPM_FINAL_SUM EQU CP_HEX_SUM
ZTS_CPM_FINAL_SIZE EQU CP_HEX_SIZE
ZTS_CPM_FINAL_DATA_LEFT EQU CP_HEX_DATA_LEFT
;@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild the single ordinary output FCB before each new BDOS operation phase.

CP_COPY_OUTPUT_FCB:
    LD   HL,CP_OUTPUT_NAME
    LD   DE,CP_WORK_FCB
    LD   BC,12
    LDIR

;@ROUTINE IN DE OUT A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the unused tail of the current CP/M file-control block.

CP_CLEAR_FCB_TAIL:
    XOR  A
    LD   B,24

;@ROUTINE IN A,B,DE OUT B,DE
; Fill B bytes at DE with A while advancing the destination pointer.

CP_CLEAR_WORK_FCB:
    LD   (DE),A
    INC  DE
    DJNZ CP_CLEAR_WORK_FCB
    RET

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's temporary filename from the requested output name.

CP_SET_TEMP_FCB:
    CALL CP_COPY_OUTPUT_FCB
    LD   HL,$2424
    LD   (CP_WORK_FCB+9),HL
    LD   A,'$'
    LD   (CP_WORK_FCB+11),A
    RET

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's backup filename from the requested output name.

CP_SET_BACKUP_FCB:
    CALL CP_COPY_OUTPUT_FCB
    LD   HL,$4142
    LD   (CP_WORK_FCB+9),HL
    LD   A,'K'
    LD   (CP_WORK_FCB+11),A
    RET

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Construct a CP/M rename FCB in the input FCB's dead storage. HL addresses
; the old 12-byte name and DE the new 12-byte name.

CP_BUILD_RENAME:
    PUSH HL
    PUSH DE
    LD   DE,CP_RENAME_FCB
    XOR  A
    LD   B,36
    CALL CP_CLEAR_WORK_FCB
    POP  DE
    POP  HL
    PUSH DE
    LD   DE,CP_RENAME_FCB
    LD   BC,12
    LDIR
    POP  HL
    LD   DE,CP_RENAME_FCB+16
    LD   BC,12
    LDIR
    RET

CP_OUTPUT_CODE_END:

;@ROUTINE IN DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a dollar-terminated string through CP/M BDOS function 9.

CP_PRINT:
    LD   C,CP_PRINT_FUNCTION
    JP   CP_BDOS

;@ROUTINE IN HL OUT A CLOBBERS B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the non-space characters of one drive-plus-8.3 filename record.

CP_PRINT_NAME:
    INC  HL
    LD   B,8
CP_PRINT_NAME_BYTE:
    LD   A,(HL)
    INC  HL
    CP   ' '
    CALL NZ,CP_PUTC
    DJNZ CP_PRINT_NAME_BYTE
    LD   A,(HL)
    CP   ' '
    RET  Z
    LD   A,'.'
    CALL CP_PUTC
    LD   B,3
CP_PRINT_TYPE_BYTE:
    LD   A,(HL)
    INC  HL
    CP   ' '
    CALL NZ,CP_PUTC
    DJNZ CP_PRINT_TYPE_BYTE
    RET

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print one character while preserving the caller's working registers.

CP_PUTC:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   E,A
    LD   C,2
    CALL CP_BDOS
    POP  HL
    POP  DE
    POP  BC
    RET

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print A as two uppercase hexadecimal digits.

CP_PRINT_HEX:
    PUSH AF
    RRCA
    RRCA
    RRCA
    RRCA
    CALL CP_PRINT_NIBBLE
    POP  AF

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the low nibble of A as one uppercase hexadecimal digit.

CP_PRINT_NIBBLE:
    AND  $0F
    ADD  A,'0'
    CP   '9'+1
    JR   C,CP_PUTC
    ADD  A,7
    JR   CP_PUTC

CP_ADAPTER_CODE_END:

; Descriptor and FCB workspace retained for the complete command. The 36-byte
; rename FCB overlays the complete input FCB after all source reads are finished.

CP_ADAPTER_WORKSPACE1_START:
CP_DESCRIPTOR:
    DB   1
    DW   CP_PART_DESCRIPTORS
    DW   CP_SYMBOL_START,CP_SYMBOL_END
    DW   CP_PENDING_START,CP_PENDING_END
    DW   CP_TARGET_START,CP_TARGET_CAPACITY

CP_RENAME_FCB:
CP_INPUT_FCB:
    DB 0,'I','N','P','U','T',' ',' ',' ','A','S','M'
    DS 24
CP_WORK_FCB:
    DB 0,'O','U','T','P','U','T',' ',' ','$','$','$'
    DS 24
CP_OUTPUT_NAME:
    DB 0,'O','U','T','P','U','T',' ',' ','C','O','M'
CP_ADAPTER_WORKSPACE1_END:

CP_ADAPTER_IMMUTABLE_START:
CP_WRITTEN_TEXT: DB ' ','w','r','i','t','t','e','n',13,10,'$'
CP_READ_FAILED_TEXT: DB ' ','r','e','a','d',' ','f','a','i','l','e','d',13,10,'$'
CP_ASSEMBLY_TEXT: DB 13,10,'A','t','o','m',' ','e','r','r','o','r',' ','$'
CP_NEWLINE_TEXT: DB 13,10,'$'
CP_USAGE_TEXT: DB 13,10,'U','s','a','g','e',':',' ','A','T','O','M',' ','[','S','O','U','R','C','E',' ','[','O','U','T','P','U','T',']',']',13,10,'$'
CP_SOURCE_NAME_TEXT: DB 13,10,'I','n','v','a','l','i','d',' ','s','o','u','r','c','e',' ','n','a','m','e',13,10,'$'
CP_OUTPUT_NAME_TEXT: DB 13,10,'I','n','v','a','l','i','d',' ','o','u','t','p','u','t',' ','n','a','m','e',13,10,'$'
CP_NAME_CONFLICT_TEXT: DB 13,10,'S','o','u','r','c','e','/','o','u','t','p','u','t',' ','c','o','n','f','l','i','c','t',13,10,'$'
CP_AUXILIARY_EXISTS_TEXT: DB 13,10,'T','e','m','p','/','b','a','c','k','u','p',' ','f','i','l','e',' ','e','x','i','s','t','s',13,10,'$'
CP_INVALID_INCLUDE_TEXT: DB 13,10,'I','n','v','a','l','i','d',' ','%','I','N','C','L','U','D','E',13,10,'$'
CP_INCLUDE_CYCLE_TEXT: DB 13,10,'I','n','c','l','u','d','e',' ','c','y','c','l','e',13,10,'$'
CP_SOURCE_CAPACITY_TEXT: DB 13,10,'T','o','o',' ','m','a','n','y',' ','s','o','u','r','c','e','s',13,10,'$'
CP_INCLUDE_WORD: DB 'I','N','C','L','U','D','E'
CP_ASM_EXTENSION: DB 'A','S','M'
CP_COM_EXTENSION: DB 'C','O','M'
CP_BIN_EXTENSION: DB 'B','I','N'
CP_HEX_EXTENSION: DB 'H','E','X'
CP_ADAPTER_IMMUTABLE_END:
CP_ADAPTER_WORKSPACE2_START:

; Small execution state. CP_OUTPUT_CURSOR overlays the source-cache key because
; all assembler source reads and patching finish before COMMIT publishes output.

CP_SAVED_SP: DW 0
CP_OUTPUT_CURSOR: DW 0
CP_SOURCE_CACHE_KEY EQU CP_OUTPUT_CURSOR
CP_OUTPUT_REMAINING: DW 0
CP_OUTPUT_OPEN: DB 0
CP_BACKED_UP: DB 0
CP_OUTPUT_FORMAT: DB 0
CP_HEX_ADDRESS: DW 0
CP_HEX_CURSOR: DW 0
CP_HEX_COUNT: DB 0
CP_HEX_ERROR: DB 0
CP_HEX_SUM: DB 0
CP_HEX_SIZE: DB 0
CP_HEX_DATA_LEFT: DB 0
CP_ADAPTER_WORKSPACE2_END:
HS_SCEND:
HS_REND:
CP_RESIDENT_END:
