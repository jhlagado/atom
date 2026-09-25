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
    LD   DE,CP_INPUT_FCB ; Point at the input FCB's drive byte.
    XOR  A ; Select the logged-in drive by default.
    LD   (DE),A ; Store drive zero before filling the name.
    INC  DE ; Advance to the eleven name/type bytes.
    LD   B,11 ; Count all eight name and three type bytes.
    LD   A,' ' ; CP/M pads unused name fields with spaces.
    CALL CP_CLEAR_WORK_FCB ; Fill the complete name/type area.
    JP   CP_CLEAR_FCB_TAIL ; Clear the remaining FCB control fields.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reject output, temporary or backup names that collide with the source name.

CP_CHECK_SOURCE_CONFLICT:
    LD   HL,CP_INPUT_FCB ; Keep the original source identity in HL.
    LD   DE,CP_OUTPUT_NAME ; Compare it with the requested output name.
    CALL CP_NAMES_EQUAL ; Z means both twelve-byte FCB identities match.
    JR   Z,CP_SOURCE_NAME_CONFLICT ; Never let output replace the source file.
    CALL CP_SET_TEMP_FCB ; Construct the temporary output filename.
    LD   HL,CP_INPUT_FCB ; Restore the source FCB pointer for comparison.
    LD   DE,CP_WORK_FCB ; The temporary name occupies the work FCB.
    CALL CP_NAMES_EQUAL ; Reject a temporary name that aliases the source.
    JR   Z,CP_SOURCE_NAME_CONFLICT ; Preserve the source file.
    CALL CP_SET_BACKUP_FCB ; Construct the backup filename for the output.
    LD   HL,CP_INPUT_FCB ; Compare the source against that third identity.
    LD   DE,CP_WORK_FCB ; The backup candidate is now in the work FCB.
    CALL CP_NAMES_EQUAL ; Z again means the names would collide.
    JR   Z,CP_SOURCE_NAME_CONFLICT ; Refuse a source/output collision.
    XOR  A ; A=0 reports that all three names are distinct.
    RET ; Return clear carry with the success result.
CP_SOURCE_NAME_CONFLICT:
    LD   DE,CP_NAME_CONFLICT_TEXT ; Return the collision message in DE.
    SCF ; Mark the preflight check as failed.
    RET ; Leave file creation to the caller's error path.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Read one logical source byte through a 128-byte random-record cache. The
; pre-scan proves every requested record exists for the life of this transient.

CP_SOURCE_READ_BYTE:
    JP   CP_RESOLVED_READ_BYTE ; Expose the resolved source-byte reader.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve the root source and its leading %INCLUDE graph. Names are retained
; as exact CP/M 8.3 identities, while descriptors are emitted in dependency-
; first order. No intermediate source-order file is involved.

CP_RESOLVE_SOURCE:
    XOR  A ; Start with no published descriptors or order.
    LD   (CP_DESCRIPTOR),A ; The native core must not see a stale part count.
    LD   (CP_ORDER_COUNT),A ; No source has reached dependency order yet.
    LD   (CP_SCAN_INDEX),A ; Discovery begins at root ordinal zero.
    INC  A ; The root itself is the first retained name.
    LD   (CP_NAME_COUNT),A ; Record one known source part.
    LD   HL,CP_INPUT_FCB+1 ; Skip the drive byte and retain the 8.3 name.
    LD   DE,CP_PART_NAMES ; Store it in the root's ordinal-zero slot.
    LD   BC,11 ; FCB name and type fields occupy eleven bytes.
    LDIR ; Copy the root name into the resolver table.
    LD   A,$FF ; Prepare the source-selection field for this run.
    LD   (CP_ACTIVE_PART),A ; Clear any stale current-part selection.

; First discover every exact name reachable from the root.

CP_DISCOVER_PART:
    XOR  A ; Mode zero records newly found include names.
    LD   (CP_SCAN_MODE),A ; Discovery does not test dependency ordering.
    LD   A,(CP_SCAN_INDEX) ; Select the next retained source name.
    CALL CP_SCAN_PART ; Read its leading header and visit its includes.
; The scan helper reports malformed input, open failure or offset overflow.
    JP   C,CP_RESOLVE_FAILURE ; Stop on any reported scan failure.
    LD   HL,CP_SCAN_INDEX ; Advance the discovery cursor in place.
    INC  (HL) ; Each retained name is scanned for dependencies.
    LD   A,(CP_NAME_COUNT) ; New includes may have extended this count.
    CP   (HL) ; Compare the next ordinal with the live count.
    JR   NZ,CP_DISCOVER_PART ; Scan every discovered source part.

; Repeatedly emit a part whose dependencies have all been emitted. Bit 7 of the
; first retained-name byte records that state; comparisons and FCB reconstruction
; mask it away. Failure to make progress proves a cycle without recursion.

CP_TOPO_PASS:
    XOR  A ; Begin another pass over all discovered files.
    LD   (CP_SCAN_INDEX),A ; Restart at the root ordinal.
    LD   (CP_SCAN_PROGRESS),A ; Track whether this pass emits any source.
CP_TOPO_PART:
    LD   A,(CP_SCAN_INDEX) ; Read the candidate part's ordinal.
    CALL CP_NAME_POINTER ; HL points to its retained eleven-byte name.
    BIT  7,(HL) ; Bit 7 marks a part already placed in the order.
    JR   NZ,CP_TOPO_NEXT ; Do not emit a part twice.
    LD   A,1 ; Mode one checks whether the includes are ready.
    LD   (CP_SCAN_MODE),A ; The scanner reports one for a pending child.
    LD   A,(CP_SCAN_INDEX) ; Scan this candidate's leading include directives.
    CALL CP_SCAN_PART ; A=0 means every dependency is already ordered.
    JP   C,CP_RESOLVE_FAILURE ; Preserve scanner errors as resolver failures.
    OR   A ; Test whether an include still has an unordered child.
    JR   NZ,CP_TOPO_NEXT ; Defer this part until a later pass.
    LD   A,(CP_ORDER_COUNT) ; Append at the next dependency-order position.
    LD   E,A ; E is the byte offset into the order table.
    LD   D,CP_PART_ORDER/256 ; The table remains within its fixed page.
    LD   A,(CP_SCAN_INDEX) ; Store this source's original ordinal.
    LD   (DE),A ; The order table maps output order to part identity.
    CALL CP_NAME_POINTER ; Recover the name after writing the order byte.
    SET  7,(HL) ; Mark this name as emitted for later scans.
    LD   HL,CP_ORDER_COUNT ; Point to the number of ordered source parts.
    INC  (HL) ; Include the part just appended above.
    LD   A,1 ; Record that this pass made progress.
    LD   (CP_SCAN_PROGRESS),A ; Newly ready dependants can run next pass.
CP_TOPO_NEXT:
    LD   HL,CP_SCAN_INDEX ; Advance to the next discovered name.
    INC  (HL) ; The table follows original discovery order.
    LD   A,(CP_NAME_COUNT) ; Read the current count, including new includes.
    CP   (HL) ; Compare against the next candidate ordinal.
    JR   NZ,CP_TOPO_PART ; Continue this pass while names remain.
    LD   A,(CP_ORDER_COUNT) ; Count the parts already placed in order.
    LD   HL,CP_NAME_COUNT ; Compare it with the total discovered count.
    CP   (HL) ; Equality means every dependency was ordered.
    JR   Z,CP_BUILD_DESCRIPTORS ; Turn the order into native part descriptors.
    LD   A,(CP_SCAN_PROGRESS) ; Check whether this pass placed any source.
    OR   A ; A zero value means ordering made no progress.
    JR   NZ,CP_TOPO_PASS ; Retry now that some dependencies are ready.
    LD   DE,CP_INCLUDE_CYCLE_TEXT ; No progress with parts left means a cycle.
    JR   CP_RESOLVE_FAILURE ; Report it through the shared failure path.

; Measure the already validated parts in final order and build the ordinary
; native five-byte descriptors. Their start is logical zero and their end is the
; measured 16-bit byte length; source storage itself remains in CP/M files.

CP_BUILD_DESCRIPTORS:
    XOR  A ; Start at the first dependency-ordered part.
    LD   (CP_SCAN_INDEX),A ; This cursor indexes CP_PART_ORDER.
    LD   HL,CP_PART_DESCRIPTORS ; Point to the native part-descriptor array.
    LD   (CP_DESCRIPTOR_CURSOR),HL ; The append helper advances this pointer.
CP_BUILD_DESCRIPTOR:
    LD   A,(CP_SCAN_INDEX) ; Select the next output-order position.
    LD   E,A ; E indexes the one-byte order table.
    LD   D,CP_PART_ORDER/256 ; Address its fixed high-page storage.
    LD   A,(DE) ; Recover the original discovery ordinal.
    CALL CP_OPEN_PART ; Reopen it before measuring its logical length.
    JP   C,CP_RESOLVE_FAILURE ; Abort if the part cannot be reopened.
    LD   HL,0 ; Count source bytes from logical offset zero.
CP_MEASURE_BYTE:
    CALL CP_NEXT_SOURCE_BYTE ; Read one source byte and advance logical offset HL.
    JR   NC,CP_MEASURE_BYTE ; Carry clear means more source bytes remain.
    OR   A ; A=0 is EOF or a failed read; A=2 is offset overflow.
    JP   NZ,CP_RESOLVE_IO ; Report a source length beyond the 16-bit range.
    CALL CP_APPEND_DESCRIPTOR ; Store this ordinal and measured [0,HL) range.
    LD   HL,CP_SCAN_INDEX ; Advance the position in dependency order.
    INC  (HL) ; The order table has one entry per retained name.
    LD   A,(CP_NAME_COUNT) ; Compare with the total number of source parts.
    CP   (HL) ; Continue while another descriptor remains.
    JR   NZ,CP_BUILD_DESCRIPTOR ; Measure the next dependency-ordered file.
    LD   A,(CP_NAME_COUNT) ; Publish the final descriptor count to the core.
    LD   (CP_DESCRIPTOR),A ; Descriptors are complete and ready for assembly.
    XOR  A ; Return success with carry clear.
    RET ; Return success after publishing the descriptor count.
CP_RESOLVE_IO:
    LD   HL,CP_INPUT_FCB ; Identify the source that exceeded the offset range.
    CALL CP_PRINT_NAME ; Print its parsed 8.3 name before the error text.
    LD   DE,CP_READ_FAILED_TEXT ; Select the adapter's source-read error text.
CP_RESOLVE_FAILURE:
    CALL CP_PRINT ; Print the error selected in DE.
    SCF ; Return failure to the command entry point.
    RET ; No partial descriptor set reaches the core.

;@ROUTINE IN A OUT A,DE,CARRY CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Scan and validate one source header. Mode zero discovers names; mode one
; reports A=1 when any dependency has not yet been emitted.

CP_SCAN_PART:
    CALL CP_OPEN_PART ; Open the requested source part for scanning.
    JR   C,CP_SCAN_FAILURE ; Stop if the FCB cannot be opened.
    LD   A,1 ; The header accepts directives until code begins.
    LD   (CP_HEADER_OPEN),A ; A source statement closes this header.
    LD   HL,0 ; Begin at the first logical source byte.
CP_SCAN_LINE:

; Blank space, line endings and comment lines remain in the header. The first
; ordinary source byte closes it permanently; a later percent directive fails.

    CALL CP_NEXT_SOURCE_BYTE ; Read the byte at the current logical offset.
    JR   C,CP_SCAN_EOF ; Carry marks EOF, failed read or offset overflow.
    CP   ' ' ; A space does not close the leading header.
    JR   Z,CP_SCAN_LINE ; Continue over horizontal whitespace.
    CP   9 ; Tabs are also header whitespace.
    JR   Z,CP_SCAN_LINE ; Test the next byte without advancing a line.
    CP   13 ; CR remains inside a blank header line.
    JR   Z,CP_SCAN_LINE ; LF is checked separately for CR/LF and LF files.
    CP   10 ; LF remains inside the leading header as well.
    JR   Z,CP_SCAN_LINE ; Continue scanning after the line ending.
    CP   ';' ; Semicolon starts a full-line source comment here.
    JR   Z,CP_SCAN_SKIP_LINE ; Ignore the remainder of that physical line.
    CP   '%' ; A percent byte may begin an INCLUDE directive.
    JR   Z,CP_SCAN_DIRECTIVE ; Parse one while the header is still open.
    XOR  A ; Any ordinary source byte closes the header.
    LD   (CP_HEADER_OPEN),A ; A later percent directive is then invalid.
CP_SCAN_SKIP_LINE:
    CALL CP_SKIP_SOURCE_LINE ; Discard the rest of this physical line.
    JR   NC,CP_SCAN_LINE ; Carry clear means another line is available.
    OR   A ; A=0 is EOF or read failure; A=2 means the offset wrapped.
    JR   Z,CP_SCAN_COMPLETE ; Treat a zero status as the end of this source.
    JR   CP_SCAN_IO ; Reject a source offset outside the 16-bit range.
CP_SCAN_DIRECTIVE:
    LD   A,(CP_HEADER_OPEN) ; Check whether source has closed the header.
    OR   A ; A=0 means this percent directive came too late.
    JR   Z,CP_SCAN_INVALID ; Report a misplaced or unsupported directive.
    CALL CP_PARSE_INCLUDE ; Visit the include or test its ordering state.
    JR   C,CP_SCAN_FAILURE ; Parsing and file errors share this return path.
    OR   A ; In ordering mode A=1 means a child is not ready.
    JR   NZ,CP_SCAN_DONE ; Stop so the caller can defer this source part.
    JR   CP_SCAN_LINE ; Continue through the remaining header lines.
CP_SCAN_EOF:
    OR   A ; A=0 ends input; A=2 reports a 16-bit offset overflow.
    JR   NZ,CP_SCAN_IO ; Reject a source offset that wrapped.
CP_SCAN_COMPLETE:
    XOR  A ; Return zero unresolved dependencies at accepted end of input.
CP_SCAN_DONE:
    RET ; Preserve A for the discovery/order caller.
CP_SCAN_IO:
    LD   HL,CP_INPUT_FCB ; The open-part helper retains the current FCB here.
    CALL CP_PRINT_NAME ; Identify the file whose scan could not continue.
    LD   DE,CP_READ_FAILED_TEXT ; Select the source-read error message.
    JR   CP_SCAN_FAILURE ; Return the read error through the shared exit.
CP_SCAN_INVALID:
    LD   DE,CP_INVALID_INCLUDE_TEXT ; Select the malformed-header message.
CP_SCAN_FAILURE:
    SCF ; Carry marks failure independently of message text.
    RET ; Do not accept an incomplete dependency scan.

;@ROUTINE IN HL OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the resolved ordinal and measured byte range to the descriptor table.

CP_APPEND_DESCRIPTOR:
    LD   DE,(CP_DESCRIPTOR_CURSOR) ; Start the next five-byte descriptor.
    LD   A,(CP_SCAN_INDEX) ; Assign the next ordinal in resolved source order.
    LD   (DE),A ; Descriptor byte zero is that ordinal.
    INC  DE ; Advance to the logical start low byte.
    XOR  A ; Every file is exposed as a range starting at zero.
    LD   (DE),A ; Store the start low byte.
    INC  DE ; Advance to the logical start high byte.
    LD   (DE),A ; Store the start high byte.
    INC  DE ; Advance to the exclusive end low byte.
    LD   A,L ; HL holds the measured source length.
    LD   (DE),A ; Store the low byte of the half-open end.
    INC  DE ; Advance to the exclusive end high byte.
    LD   A,H ; Complete the 16-bit source length.
    LD   (DE),A ; Store the high byte of the half-open end.
    INC  DE ; Point at the following descriptor slot.
    LD   (CP_DESCRIPTOR_CURSOR),DE ; Save the cursor for the next descriptor.
    RET ; The caller advances order and measures another file.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse INCLUDE, one quoted current-drive 8.3 name and the rest of its line.
; Discovery records the child. Ordering checks whether it was emitted.

CP_PARSE_INCLUDE:
    LD   DE,CP_INCLUDE_WORD ; Point at the uppercase directive name.
    LD   B,7 ; Match all seven letters in INCLUDE.
CP_INCLUDE_WORD_BYTE:
    CALL CP_NEXT_SOURCE_BYTE ; Read the next directive-name byte.
    JP   C,CP_INCLUDE_INVALID ; A truncated name is not a directive.
    CP   'a' ; Test whether ASCII lowercase folding applies.
    JR   C,CP_INCLUDE_WORD_CASED ; Leave uppercase and punctuation unchanged.
    CP   'z'+1 ; Compare with the first byte above lowercase letters.
    JR   NC,CP_INCLUDE_WORD_CASED ; Leave bytes beyond 'z' unchanged.
    AND  $DF ; Convert this ASCII lowercase letter to uppercase.
CP_INCLUDE_WORD_CASED:
    EX   DE,HL ; Compare through DE without losing the source cursor.
    CP   (HL) ; Match the current byte against INCLUDE.
    INC  HL ; Advance to the next byte of the directive name.
    EX   DE,HL ; Restore HL as the source cursor.
    JP   NZ,CP_INCLUDE_INVALID ; Reject any mismatched directive byte.
    DJNZ CP_INCLUDE_WORD_BYTE ; Check the remaining keyword bytes.
    CALL CP_NEXT_SOURCE_BYTE ; Read the delimiter after INCLUDE.
    JP   C,CP_INCLUDE_INVALID ; The keyword must have a following delimiter.
    CP   ' ' ; Accept an ordinary space before the filename.
    JR   Z,CP_INCLUDE_SPACE ; Skip additional horizontal whitespace.
    CP   9 ; Also accept a horizontal tab as delimiter.
    JP   NZ,CP_INCLUDE_INVALID ; Require whitespace before the quote.
CP_INCLUDE_SPACE:
    CALL CP_NEXT_SOURCE_BYTE ; Read past the current whitespace byte.
    JP   C,CP_INCLUDE_INVALID ; A filename must follow the delimiter.
    CP   ' ' ; Check for another space before the filename.
    JR   Z,CP_INCLUDE_SPACE ; Continue across repeated spaces.
    CP   9 ; Check for a repeated tab.
    JR   Z,CP_INCLUDE_SPACE ; Continue across repeated tabs.
    CP   '"' ; The filename must begin with a double quote.
    JP   NZ,CP_INCLUDE_INVALID ; Reject unquoted include names.
    CALL CP_CLEAR_INCLUDE_FCB ; Prepare a blank current-drive filename.
    PUSH IX ; Preserve the caller's index while parsing the FCB name.
    CALL CP_PARSE_INCLUDE_NAME ; Store the quoted 8.3 name in the FCB.
    POP  IX ; Restore the caller's index after filename parsing.
    RET  C ; Propagate an invalid or incomplete filename.
CP_INCLUDE_TRAILING:
    CALL CP_NEXT_SOURCE_BYTE ; Read the next byte after the closing quote.
    JR   C,CP_INCLUDE_TRAILING_EOF ; Branch on EOF or offset overflow.
    CP   ' ' ; Permit spaces after the filename.
    JR   Z,CP_INCLUDE_TRAILING ; Skip trailing spaces.
    CP   9 ; Permit tabs after the filename.
    JR   Z,CP_INCLUDE_TRAILING ; Skip trailing tabs.
    CP   ';' ; A semicolon starts a trailing comment.
    JR   Z,CP_INCLUDE_SKIP_COMMENT ; Validate the rest of the comment line.
    CP   13 ; Accept a CR line ending.
    JR   Z,CP_INCLUDE_READY ; The include name is complete.
    CP   10 ; Also accept an LF line ending.
    JP   NZ,CP_INCLUDE_INVALID ; Reject any other trailing byte.
CP_INCLUDE_READY:

; Deduplicate the eleven-byte CP/M name. Discovery adds missing names.
; Ordering reports whether each child has already been emitted.

    PUSH IX ; Preserve the source reader's index across name lookup.
    PUSH HL ; Preserve the source cursor after the include line.
    CALL CP_FIND_OR_ADD_NAME ; Reuse a known child or append its name.
    POP  HL ; Restore the source cursor for the next scan step.
    POP  IX ; Restore the caller's index register.
    RET  C ; Return a name-capacity failure to the resolver.
    PUSH HL ; Preserve the source cursor across dependency-state lookup.
    CALL CP_VISIT_INCLUDED_CHILD ; Return the pending-child status.
    POP  HL ; Restore the cursor without changing the result flags.
    RET ; Return the child's pending status to the scan loop.
CP_INCLUDE_SKIP_COMMENT:
    CALL CP_SKIP_SOURCE_LINE ; Consume the trailing comment through line end.
    JR   C,CP_INCLUDE_TRAILING_EOF ; Check the carried end status.
    JR   CP_INCLUDE_READY ; The include line has no more source text.
CP_INCLUDE_TRAILING_EOF:
    OR   A ; Zero accepts end-of-input. NZ signals offset overflow.
    JP   NZ,CP_INCLUDE_INVALID ; Reject an offset that wrapped.
    JR   CP_INCLUDE_READY ; Accept the include at end of input.
CP_INCLUDE_INVALID:
    LD   DE,CP_INVALID_INCLUDE_TEXT ; Select the malformed-include message.
    SCF ; Mark the include directive as invalid.
    RET ; Return the message pointer and failure flag.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted include filename into the working CP/M FCB.

CP_PARSE_INCLUDE_NAME:
    LD   IX,CP_WORK_FCB+1 ; Begin writing the eight-byte base field.
    LD   D,8 ; Set the base-name capacity.
    LD   C,0 ; Count characters in the current name field.
CP_INCLUDE_NAME_BYTE:
    CALL CP_NEXT_SOURCE_BYTE ; Read the next quoted filename byte.
    JP   C,CP_INCLUDE_NAME_BAD ; Require a complete closing quote.
    CP   '"' ; Check for the end of the filename.
    JR   Z,CP_INCLUDE_NAME_DONE ; Validate that the final field is nonempty.
    CP   '.' ; Check for the single base/extension separator.
    JR   NZ,CP_INCLUDE_NAME_DATA ; Other bytes belong to the current field.
    LD   A,D ; Read the active field's maximum width.
    CP   8 ; A dot is legal only while parsing the base field.
    JP   NZ,CP_INCLUDE_NAME_BAD ; Reject repeated separators.
    LD   A,C ; Read the number of base-name characters.
    OR   A ; Set Z when the base field is empty.
    JP   Z,CP_INCLUDE_NAME_BAD ; Require at least one base character.
    LD   IX,CP_WORK_FCB+9 ; Continue writing at the three-byte type field.
    LD   D,3 ; Set the extension capacity.
    LD   C,0 ; Start the extension character count.
    JR   CP_INCLUDE_NAME_BYTE ; Read the first extension character.
CP_INCLUDE_NAME_DATA:
    CP   'a' ; Test for an ASCII lowercase filename letter.
    JR   C,CP_INCLUDE_NAME_CASED ; Keep non-lowercase bytes unchanged.
    CP   'z'+1 ; Compare with the exclusive lowercase upper bound.
    JR   NC,CP_INCLUDE_NAME_CASED ; Keep bytes above 'z' unchanged.
    AND  $DF ; Fold lowercase ASCII to uppercase for CP/M lookup.
CP_INCLUDE_NAME_CASED:
    CALL CP_FILENAME_CHAR ; Reject characters outside the CP/M name set.
    JP   C,CP_INCLUDE_NAME_BAD ; Carry marks a forbidden filename character.
    INC  C ; Include the validated byte in this field's length.
    LD   B,A ; Save the normalised byte while checking field capacity.
    LD   A,D ; Load the active base or extension limit.
    CP   C ; Compare the limit with the updated character count.
    JP   C,CP_INCLUDE_NAME_BAD ; Reject a field wider than 8.3 allows.
    LD   A,B ; Restore the normalized filename byte.
    LD   (IX+0),A ; Store it in the current FCB name field.
    INC  IX ; Advance to the next character slot.
    JR   CP_INCLUDE_NAME_BYTE ; Continue through the closing quote.
CP_INCLUDE_NAME_DONE:
    LD   A,C ; Read the character count of the final field.
    OR   A ; Set Z only when that field is empty.
    RET  NZ ; Accept a nonempty base or extension field.
CP_INCLUDE_NAME_BAD:
    LD   DE,CP_INVALID_INCLUDE_TEXT ; Select the malformed-include message.
    SCF ; Mark the filename as invalid.
    RET ; Return failure to the directive parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Visit a discovered include child when dependency scanning is active.

CP_VISIT_INCLUDED_CHILD:
    LD   E,A ; Keep the child ordinal across the mode check.
    LD   A,(CP_SCAN_MODE) ; Read whether this is discovery or ordering.
    OR   A ; Discovery mode is zero.
    RET  Z ; Discovery needs no pending-child result.
    LD   A,E ; Restore the child's retained-name ordinal.
    CALL CP_NAME_POINTER ; Address its eleven-byte name record.
    BIT  7,(HL) ; Test the emitted marker in the first name byte.
    LD   A,0 ; Use zero when the child has already been emitted.
    RET  NZ ; A set marker means no dependency remains pending.
    INC  A ; An unset marker means the child still needs emission.
    RET ; Return one for a pending child.

;@ROUTINE OUT A CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the working include FCB to a blank 8.3 filename.

CP_CLEAR_INCLUDE_FCB:
    LD   DE,CP_WORK_FCB ; Address the temporary working FCB.
    XOR  A ; Select the current drive.
    LD   (DE),A ; Clear the explicit drive byte.
    INC  DE ; Advance to the eleven-byte 8.3 name.
    LD   B,11 ; Clear all eight base and three extension bytes.
    LD   A,' ' ; CP/M represents unused name bytes with spaces.
    CALL CP_CLEAR_WORK_FCB ; Fill the name and extension fields.
    JP   CP_CLEAR_FCB_TAIL ; Clear the remaining FCB control bytes.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains.

CP_FIND_OR_ADD_NAME:
    LD   C,0 ; Start with retained-name ordinal zero.
CP_FIND_NAME_LOOP:
    LD   A,(CP_NAME_COUNT) ; Read the number of names already retained.
    CP   C ; Compare the count with the current candidate ordinal.
    JR   Z,CP_ADD_NAME ; Append when no existing slot remains to inspect.
    LD   A,C ; Select this retained name's ordinal.
    CALL CP_NAME_POINTER ; Address its eleven-byte name record.
    LD   IX,CP_WORK_FCB+1 ; Address the normalized candidate filename.
    LD   B,11 ; Compare the complete base and extension fields.
CP_FIND_NAME_BYTE:
    LD   A,(HL) ; Read one byte from the retained name.
    AND  $7F ; Ignore its high-bit emitted marker during comparison.
    CP   (IX+0) ; Compare with the corresponding candidate byte.
    JR   NZ,CP_FIND_NAME_NEXT ; Try the next ordinal on any mismatch.
    INC  HL ; Advance the retained-name cursor.
    INC  IX ; Advance the candidate-name cursor.
    DJNZ CP_FIND_NAME_BYTE ; Compare the remaining name bytes.
    LD   A,C ; Return the ordinal whose full name matched.
    OR   A ; Clear carry and set zero for ordinal zero.
    RET ; Report the existing name without adding another entry.
CP_FIND_NAME_NEXT:
    INC  C ; Advance to the next retained-name ordinal.
    JR   CP_FIND_NAME_LOOP ; Continue until a name matches or the table ends.
CP_ADD_NAME:

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C ; The next ordinal is the current number of names.
    CP   255 ; The byte-sized table has no ordinal 255 entry.
    JR   Z,CP_NAME_CAPACITY ; Reject a 256th distinct source file.
    PUSH AF ; Preserve the new zero-based ordinal across the copy.
    CALL CP_NAME_POINTER ; Address the next eleven-byte table slot.
    EX   DE,HL ; Put the slot destination in DE for LDIR.
    LD   HL,CP_WORK_FCB+1 ; Point to the normalized 8.3 name bytes.
    LD   BC,11 ; Copy the base and extension, excluding the drive byte.
    LDIR ; Store the new name in its ordinal slot.
    LD   HL,CP_NAME_COUNT ; Address the count published to the resolver.
    INC  (HL) ; Publish the slot only after all eleven bytes are copied.
    POP  AF ; Return the allocated ordinal.
    OR   A ; Clear carry to mark successful insertion.
    RET ; Return the new retained-name identity.
CP_NAME_CAPACITY:
    LD   DE,CP_SOURCE_CAPACITY_TEXT ; Select the part-capacity diagnostic.
    SCF ; Mark the resolver's name table as full.
    RET ; Return without changing the retained-name count.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

CP_NAME_POINTER:
    LD   L,A ; Place the ordinal in the low byte of HL.
    LD   H,0 ; Extend the ordinal to a 16-bit value.
    LD   D,H ; Clear the high byte of the temporary DE value.
    LD   E,L ; Copy the ordinal into DE for multiplication by eleven.
    ADD  HL,HL ; Compute twice the ordinal.
    ADD  HL,HL ; Compute four times the ordinal.
    ADD  HL,DE ; Combine to make five times the ordinal.
    ADD  HL,HL ; Compute ten times the ordinal.
    ADD  HL,DE ; Complete eleven times the ordinal.
    LD   DE,CP_PART_NAMES ; Load the base of the retained-name table.
    ADD  HL,DE ; Convert the byte offset to the slot address.
    RET ; Return the address of this eleven-byte name record.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the ordinary input FCB from one retained name.

CP_OPEN_PART:
    PUSH AF ; Preserve the source ordinal while clearing its input FCB.
    CALL CP_CLEAR_INPUT_FCB ; Reset the file-control block for this source.
    POP  AF ; Restore the ordinal used to find its retained name.
    CALL CP_NAME_POINTER ; Address the source's eleven-byte name record.
    LD   DE,CP_INPUT_FCB+1 ; Point past the drive byte to the 8.3 fields.
    LD   B,11 ; Copy the eight-character name and three-character type.
CP_OPEN_NAME_BYTE:
    LD   A,(HL) ; Read the next byte of the retained source name.
    AND  $7F ; Clear the high-bit ordering marker if this is the first byte.
    LD   (DE),A ; Copy the ordinary name byte into the input FCB.
    INC  HL ; Advance within the retained name record.
    INC  DE ; Advance within the input FCB name fields.
    DJNZ CP_OPEN_NAME_BYTE ; Copy all eleven name and type bytes.
    CALL CP_CHECK_SOURCE_CONFLICT ; Protect output and transaction files.
    RET  C ; Do not open a source that aliases an output name.
    LD   DE,CP_INPUT_FCB ; Pass the prepared FCB to CP/M.
    LD   C,CP_OPEN_FUNCTION ; Select the CP/M open-file service.
    CALL CP_BDOS ; Open the selected source file.
    INC  A ; Convert BDOS's $FF failure result to zero.
    JR   Z,CP_OPEN_FAILURE ; Report an unavailable source by name.
    LD   A,1 ; Choose a non-aligned cache key to force the next refill.
    LD   (CP_SOURCE_CACHE_KEY),A ; Aligned record offsets cannot equal one.
    XOR  A ; Return zero with carry clear on a successful open.
    RET ; Leave the opened input FCB ready for random reads.
CP_OPEN_FAILURE:
    LD   HL,CP_INPUT_FCB ; Address the filename that failed to open.
    CALL CP_PRINT_NAME ; Print its drive-independent 8.3 name.
    LD   DE,CP_READ_FAILED_TEXT ; Select the source-open error message.
    SCF ; Mark the open operation as failed.
    RET ; Return the message pointer with carry set.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the next raw source byte and advance HL. Carry with A=0 means EOF or
; an unsuccessful CP/M random read. Carry with A=2 means the 16-bit offset
; wrapped. BC and DE survive for parsers.
; A part is limited to 65,535 bytes so the next offset cannot wrap to zero.

CP_NEXT_SOURCE_BYTE:
    PUSH BC ; Preserve the parser's byte-sized working values.
    PUSH DE ; Preserve the parser's filename or pointer register.
    PUSH HL ; Keep the logical source offset across the raw read.
    CALL CP_RAW_SOURCE_BYTE ; Read from the current CP/M record cache.
    POP  HL ; Restore the logical offset before checking the result.
    POP  DE ; Restore the caller's DE value.
    POP  BC ; Restore the caller's BC value.
    RET  C ; Return EOF or a read failure without advancing HL.
    LD   (CP_NEXT_VALUE),A ; Save the byte while advancing the offset.
    INC  HL ; Prepare the logical offset of the following byte.
    LD   A,H ; Test the high byte of the advanced offset.
    OR   L ; Zero means the 16-bit offset wrapped.
    JR   Z,CP_SOURCE_TOO_LONG ; Reject a part that would exceed 65,535 bytes.
    LD   A,(CP_NEXT_VALUE) ; Restore the byte read from the source.
    OR   A ; Clear carry and set zero when the byte itself is zero.
    RET ; Return the byte with HL advanced to its next offset.
CP_SOURCE_TOO_LONG:
    LD   A,2 ; Distinguish offset overflow from ordinary end-of-input.
    SCF ; Report that the logical source offset wrapped.
    RET ; Return the overflow status to the resolver.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Align the logical offset to its 128-byte CP/M record base. The cache
; key stores that base; the FCB receives it divided by 128. On a miss,
; the routine installs the source cache as DMA and reads that record.
; It then uses the low seven bits to select the requested byte.

CP_RAW_SOURCE_BYTE:
    LD   (CP_RAW_OFFSET),HL ; Save the requested logical byte offset.
    LD   A,L ; Inspect the low byte of the requested offset.
    AND  $80 ; Keep its 128-byte record-boundary bit.
    LD   E,A ; Form the aligned offset's low byte.
    LD   D,H ; Form its high byte from the logical offset.
    LD   HL,(CP_SOURCE_CACHE_KEY) ; Read the offset currently in the cache.
    OR   A ; Clear carry before subtracting the requested base.
    SBC  HL,DE ; Compare the cached and requested record bases.
    JR   Z,CP_RAW_CACHE_READY ; Reuse the cache when both bases match.
CP_RAW_CACHE_MISS:
    LD   (CP_SOURCE_CACHE_KEY),DE ; Remember the aligned offset being loaded.
    RLC  E ; Move offset bit 7 into bit 0 of the record number.
    LD   A,D ; Load the high byte for the low record-number byte.
    ADD  A,A ; Shift its bits left one place.
    OR   E ; Add the original offset's bit 7.
    LD   (CP_INPUT_FCB+33),A ; Store the random record number's low byte.
    LD   A,D ; Reload the offset's high byte.
    RLCA ; Move offset bit 15 into bit 0.
    AND  1 ; Keep only the record number's high bit.
    LD   (CP_INPUT_FCB+34),A ; Store the random record number's high byte.
    LD   DE,CP_SOURCE_CACHE ; Select the 128-byte DMA buffer.
    LD   C,CP_DMA_FUNCTION ; Set the CP/M transfer address.
    CALL CP_BDOS ; Direct the next read into the source cache.
    LD   DE,CP_INPUT_FCB ; Pass the file and record number to CP/M.
    LD   C,CP_RANDOM_READ_FUNCTION ; Select a random-record read.
    CALL CP_BDOS ; Load the requested 128-byte source record.
    OR   A ; Zero means the random read succeeded.
    JR   NZ,CP_RAW_READ_EOF ; Treat a BDOS read failure as no source byte.
CP_RAW_CACHE_READY:
    LD   HL,(CP_RAW_OFFSET) ; Restore the byte's logical offset.
    SET  7,L ; Map its within-record offset into $80..$FF.
    LD   H,CP_SOURCE_CACHE/256 ; Select the source cache's memory page.
    LD   A,(HL) ; Read the byte from the cached record.
    CP   $1A ; Test CP/M's text-file end marker.
    JR   Z,CP_RAW_EOF ; Return end-of-input at control-Z.
    OR   A ; Clear carry while preserving the source byte in A.
    RET ; Return the raw byte to the caller.
CP_RAW_READ_EOF:
CP_RAW_EOF:
    XOR  A ; Return zero for a read failure or text-file end marker.
    SCF ; Carry reports that no source byte is available.
    RET ; Share one end-of-input result for both conditions.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Consume source bytes through the next CR, LF or end of file.

CP_SKIP_SOURCE_LINE:
    CALL CP_NEXT_SOURCE_BYTE ; Read the next byte in the current line.
    RET  C ; Stop at accepted end-of-input or report offset overflow.
    CP   13 ; Test for a carriage return.
    RET  Z ; Stop after consuming CR.
    CP   10 ; Test for a line feed.
    JR   NZ,CP_SKIP_SOURCE_LINE ; Continue until LF or another CR.
    RET ; Stop after consuming LF.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Open a part on ordinal change, then return one source byte.
; Preflight accepts only %INCLUDE. Its leading percent becomes a semicolon,
; so Atom reads the rest of that directive line as a comment.

CP_RESOLVED_READ_BYTE:
    LD   E,A ; Keep the resolved source-part ordinal.
    LD   A,(CP_ACTIVE_PART) ; Read the ordinal of the open source file.
    CP   E ; Compare it with the requested part.
    JR   Z,CP_RESOLVED_SOURCE_READY ; Reuse the file when ordinals match.
    PUSH BC ; Preserve the caller's byte-sized parser state.
    PUSH HL ; Preserve the logical byte offset across file open.
    LD   A,E ; Restore the requested resolved ordinal.
    LD   (CP_ACTIVE_PART),A ; Record which resolved part is now active.
    LD   D,CP_PART_ORDER/256 ; Address the order table's fixed memory page.
    LD   A,(DE) ; Map resolved order back to the discovered source ordinal.
    CALL CP_OPEN_PART ; Open the source named by that original ordinal.
    POP  HL ; Restore the byte offset in the newly opened file.
    POP  BC ; Restore the caller's parser state.
CP_RESOLVED_SOURCE_READY:
    PUSH BC ; Preserve parser state while the raw reader uses BC.
    PUSH HL ; Preserve the source offset across cache lookup.
    CALL CP_RAW_SOURCE_BYTE ; Read one byte from the active source file.
    POP  HL ; Restore the offset used by the host source interface.
    POP  BC ; Restore the caller's parser state.
    RET  C ; Return end-of-input or a failed read unchanged.
    CP   '%' ; Check for a possible preprocessor directive marker.
    JR   Z,CP_RESOLVED_PERCENT ; Test whether the percent is line-leading.
    OR   A ; Clear carry for an ordinary source byte.
    RET ; Return the byte without changing its contents.
CP_RESOLVED_PERCENT:
    PUSH HL ; Preserve the current offset during the backward scan.
    CALL CP_PERCENT_IS_DIRECTIVE ; Check preceding bytes for line start.
    POP  HL ; Restore the offset of the percent byte.
    JR   Z,CP_RESOLVED_DIRECTIVE ; Mask it only at the start of a line.
    LD   A,'%' ; Restore a percent used in ordinary source text.
    OR   A ; Clear carry and set flags from the returned byte.
    RET ; Return the unchanged percent character.
CP_RESOLVED_DIRECTIVE:
    LD   A,';' ; Make Atom's tokenizer ignore the rest of the directive line.
    OR   A ; Return the comment marker with carry clear.
    RET ; Preserve the original source offset in HL.

;@ROUTINE IN HL OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Decide whether a percent character begins a recognized host directive.

CP_PERCENT_IS_DIRECTIVE:
    LD   A,H ; Test the current source offset's high byte.
    OR   L ; Zero means the percent is the first source byte.
    RET  Z ; Report line start when no preceding byte exists.
    DEC  HL ; Begin scanning at the byte before the percent.
CP_PERCENT_PREFIX:
    PUSH HL ; Preserve the backward-scan cursor during the raw read.
    CALL CP_RAW_SOURCE_BYTE ; Read the preceding source byte.
    POP  HL ; Restore the offset used for the backward scan.
    CP   13 ; Check whether the percent follows a carriage return.
    JR   Z,CP_PERCENT_YES ; CR marks the start of a source line.
    CP   10 ; Check whether the percent follows a line feed.
    JR   Z,CP_PERCENT_YES ; LF also marks the start of a source line.
    CP   ' ' ; Check for a space before the percent.
    JR   Z,CP_PERCENT_PREVIOUS ; Skip whitespace while scanning backwards.
    CP   9 ; Check for a horizontal tab.
    RET  NZ ; Any other preceding byte makes this ordinary source text.
CP_PERCENT_PREVIOUS:
    LD   A,H ; Test whether the preceding whitespace reaches source byte zero.
    OR   L ; Zero means no non-whitespace byte precedes this position.
    JR   Z,CP_PERCENT_YES ; Only spaces or tabs precede the percent.
    DEC  HL ; Move to the byte before this whitespace character.
    JR   CP_PERCENT_PREFIX ; Continue until line start or ordinary text.
CP_PERCENT_YES:
    XOR  A ; Return A=0 and Z set to mark a line-leading percent.
    RET ; Carry is clear for the recognized line-start result.
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
