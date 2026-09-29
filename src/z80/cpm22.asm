; Atom CP/M 2.2 transient adapter
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
;   4. spool ordered operations, then materialize COM/BIN/HEX through a fixed
;      TPA output window or retain explicit ASO output; and
;   5. publish completed output through temporary/backup filenames.
;
; Atom itself has no filesystem calls. Its five-byte part descriptors use the
; half-open logical range [0,length). CP_SOURCE_READ_BYTE maps the ordinal
; through the derived order, opens the matching FCB and supplies the byte.

; The COM contains code through the ASO writer/materialiser. Its writable
; arenas begin at CP_WORKSPACE_START and are initialised before use, so they
; need addresses in the TPA but no bytes in the loaded file. The output window
; and private stack remain above those arenas.

CP_BDOS_ENTRY       EQU $0005
CP_WORKSPACE_START  EQU $5400
CP_PART_ORDER       EQU CP_WORKSPACE_START
CP_PART_ORDER_END   EQU CP_PART_ORDER+$100
CP_SOURCE_CACHE     EQU CP_PART_ORDER_END
CP_SOURCE_CACHE_END EQU CP_SOURCE_CACHE+$80
CP_PART_NAMES       EQU CP_SOURCE_CACHE_END
CP_PART_NAMES_END   EQU CP_PART_NAMES+$AF5
CP_PART_DESCRIPTORS EQU CP_PART_NAMES_END
CP_PART_DESCRIPTORS_END EQU CP_PART_DESCRIPTORS+$4FB
CP_NAME_COUNT       EQU CP_PART_DESCRIPTORS_END
CP_ORDER_COUNT      EQU CP_NAME_COUNT+1
CP_DESCRIPTOR_CURSOR EQU CP_ORDER_COUNT+1
CP_ACTIVE_PART      EQU CP_DESCRIPTOR_CURSOR+2
CP_SCAN_MODE        EQU CP_ACTIVE_PART+1
CP_SCAN_INDEX       EQU CP_SCAN_MODE+1
CP_SCAN_PROGRESS    EQU CP_SCAN_INDEX+1
CP_HEADER_OPEN      EQU CP_SCAN_PROGRESS+1
CP_RAW_OFFSET       EQU CP_HEADER_OPEN+1
CP_NEXT_VALUE       EQU CP_RAW_OFFSET+2
CP_PP_DEPTH         EQU CP_NEXT_VALUE+1
CP_PP_ACTIVE        EQU CP_PP_DEPTH+1
CP_PP_DEFS_OPEN     EQU CP_PP_ACTIVE+1
CP_PP_DEFINE_COUNT  EQU CP_PP_DEFS_OPEN+1
CP_PP_TOKEN_LENGTH  EQU CP_PP_DEFINE_COUNT+1
CP_PP_NUM_BASE      EQU CP_PP_TOKEN_LENGTH+1
CP_PP_NUM_START     EQU CP_PP_NUM_BASE+1
CP_PP_NUM_COUNT     EQU CP_PP_NUM_START+1
CP_PP_NUM_INDEX     EQU CP_PP_NUM_COUNT+1
CP_PP_NUM_DIGIT     EQU CP_PP_NUM_INDEX+1
CP_PP_ALLOW_UNDEFINED EQU CP_PP_NUM_DIGIT+1
CP_PP_LAST_DIRECTIVE EQU CP_PP_ALLOW_UNDEFINED+1
CP_PP_SOURCE_CURSOR EQU CP_PP_LAST_DIRECTIVE+2
CP_PP_WORD_START    EQU CP_PP_SOURCE_CURSOR+2
CP_PP_CURRENT_OFFSET EQU CP_PP_WORD_START+2
CP_PP_SCAN_CURSOR   EQU CP_PP_CURRENT_OFFSET+2
CP_PP_NUM_VALUE     EQU CP_PP_SCAN_CURSOR+2
CP_PP_NAME_LENGTH   EQU CP_PP_NUM_VALUE+2
CP_PP_STATE_END     EQU CP_PP_NAME_LENGTH+1
CP_PP_STACK         EQU CP_PP_STATE_END
CP_PP_STACK_END     EQU CP_PP_STACK+16
    CP_PP_DEFINE_ENTRY_BYTES EQU 20
    CP_PP_DEFINE_CAPACITY EQU 32
    CP_PP_DEFINE_TABLE  EQU CP_PP_STACK_END
    CP_PP_DEFINE_BYTES EQU CP_PP_DEFINE_ENTRY_BYTES*CP_PP_DEFINE_CAPACITY
    CP_PP_DEFINE_TABLE_END EQU CP_PP_DEFINE_TABLE+CP_PP_DEFINE_BYTES
CP_PP_TOKEN         EQU CP_PP_DEFINE_TABLE_END
CP_PP_TOKEN_END     EQU CP_PP_TOKEN+17
CP_PP_NAME          EQU CP_PP_TOKEN_END
CP_PP_NAME_BYTES    EQU 17
CP_RESOLVER_WORKSPACE_END EQU CP_PP_NAME+CP_PP_NAME_BYTES
; Each binary include keeps its source position, explicit byte count, CP/M
; filename and ten-byte DS replacement. Thirty-two rows bound native use.
CP_BIN_CAPACITY     EQU 32
CP_BIN_ENTRY_BYTES  EQU 28
CP_BIN_FILENAME     EQU 7
CP_BIN_REPLACEMENT  EQU 18
CP_BIN_REPLACEMENT_BYTES EQU 10
CP_BIN_COUNT        EQU CP_RESOLVER_WORKSPACE_END
CP_BIN_TABLE        EQU CP_BIN_COUNT+1
CP_BIN_TABLE_END    EQU CP_BIN_TABLE+CP_BIN_CAPACITY*CP_BIN_ENTRY_BYTES
CP_BIN_WORKSPACE    EQU CP_BIN_TABLE_END
CP_BIN_ENABLED      EQU CP_BIN_WORKSPACE
CP_BIN_FILTER_INDEX EQU CP_BIN_ENABLED+1
CP_BIN_FILTER_PTR   EQU CP_BIN_FILTER_INDEX+1
CP_BIN_FILTER_LAST_PART EQU CP_BIN_FILTER_PTR+2
CP_BIN_FILTER_LAST_OFFSET EQU CP_BIN_FILTER_LAST_PART+1
CP_BIN_SINK_INDEX   EQU CP_BIN_FILTER_LAST_OFFSET+2
CP_BIN_SINK_PTR     EQU CP_BIN_SINK_INDEX+1
CP_BIN_SINK_ACTIVE  EQU CP_BIN_SINK_PTR+2
CP_BIN_SINK_PART    EQU CP_BIN_SINK_ACTIVE+1
CP_BIN_SINK_OFFSET  EQU CP_BIN_SINK_PART+1
CP_BIN_SINK_REMAIN  EQU CP_BIN_SINK_OFFSET+2
CP_BIN_SINK_VALUE   EQU CP_BIN_SINK_REMAIN+2
; These two live flags must survive replay, which reuses the high workspace.
CP_BIN_ERROR        EQU CP_BIN_RESIDENT_ERROR
CP_BIN_OPEN         EQU CP_BIN_RESIDENT_OPEN
CP_BIN_RECORD_LEFT  EQU CP_BIN_SINK_VALUE+1
CP_BIN_RECORD_PTR   EQU CP_BIN_RECORD_LEFT+1
CP_BIN_SCAN_PART    EQU CP_BIN_RECORD_PTR+2
CP_BIN_SCAN_OFFSET  EQU CP_BIN_SCAN_PART+1
CP_BIN_SCAN_DESC    EQU CP_BIN_SCAN_OFFSET+2
CP_BIN_SCAN_END     EQU CP_BIN_SCAN_DESC+2
CP_BIN_STATEMENT    EQU CP_BIN_SCAN_END+2
CP_BIN_TOKEN_OFFSET EQU CP_BIN_STATEMENT+2
CP_BIN_LINE_END     EQU CP_BIN_TOKEN_OFFSET+2
CP_BIN_COUNT_VALUE  EQU CP_BIN_LINE_END+2
CP_BIN_NAME         EQU CP_BIN_COUNT_VALUE+2
CP_BIN_BYTE_TEMP    EQU CP_BIN_NAME+11
CP_BIN_BUILD_PTR    EQU CP_BIN_BYTE_TEMP+1
CP_BIN_FCB          EQU CP_BIN_BUILD_PTR+2
CP_BIN_FCB_END      EQU CP_BIN_FCB+36
CP_BIN_WORKSPACE_END EQU CP_BIN_FCB_END
CP_SYMBOL_START     EQU CP_BIN_WORKSPACE_END
CP_SYMBOL_END       EQU CP_SYMBOL_START+$3000
CP_PENDING_START    EQU CP_SYMBOL_END
CP_PENDING_END      EQU CP_PENDING_START+$1000
CP_OUTPUT_START     EQU CP_PENDING_END
CP_OUTPUT_END       EQU $D780
; The operation writer owns high TPA buffers only during assembly. Once the
; ASO file is closed, the old part-order page becomes materializer workspace.
CP_ASO_FCB          EQU CP_OUTPUT_START
CP_ASO_RUN          EQU CP_ASO_FCB+36
CP_ASO_RECORD       EQU CP_ASO_RUN+128
CP_MAT_FCB          EQU CP_PART_ORDER
CP_MAT_RECORD       EQU CP_MAT_FCB+36
CP_MAT_STATE        EQU CP_MAT_RECORD+128
CP_MAT_READ_PTR     EQU CP_MAT_STATE+1
CP_MAT_READ_LEFT    EQU CP_MAT_STATE+3
CP_MAT_BYTE         EQU CP_MAT_STATE+4
CP_MAT_FILL         EQU CP_MAT_STATE+5
CP_MAT_WINDOW_START EQU CP_MAT_STATE+6
CP_MAT_WINDOW_LENGTH EQU CP_MAT_STATE+8
CP_MAT_WINDOW_LEFT  EQU CP_MAT_STATE+10
CP_MAT_WINDOW_CURSOR EQU CP_MAT_STATE+12
CP_MAT_OUTPUT_LEFT  EQU CP_MAT_STATE+14
CP_MAT_RECORD_KIND  EQU CP_MAT_STATE+16
CP_MAT_RECORD_LENGTH EQU CP_MAT_STATE+17
CP_MAT_RECORD_LEFT  EQU CP_MAT_STATE+18
CP_MAT_RECORD_ADDRESS EQU CP_MAT_STATE+19
CP_MAT_RECORD_OFFSET EQU CP_MAT_STATE+21
CP_MAT_RECORD_END   EQU CP_MAT_STATE+23
CP_MAT_IMAGE_END    EQU CP_MAT_STATE+25
CP_MAT_IMAGE_TOP    EQU CP_MAT_STATE+27
CP_MAT_PREVIOUS_KIND EQU CP_MAT_STATE+28
CP_MAT_PREVIOUS_LENGTH EQU CP_MAT_STATE+29
CP_MAT_ENDPOINT_TOP EQU CP_MAT_STATE+30
CP_MAT_SCRATCH_END  EQU CP_MAT_STATE+31
CP_TARGET_START     EQU $0100
CP_ASO_TARGET_CAPACITY EQU $FF00
CP_MAT_WINDOW       EQU CP_SOURCE_CACHE_END
CP_STACK_TOP        EQU $E400
CP_DMA_FUNCTION     EQU 26
CP_OPEN_FUNCTION    EQU 15
CP_CLOSE_FUNCTION   EQU 16
CP_DELETE_FUNCTION  EQU 19
CP_READ_FUNCTION    EQU 20
CP_RANDOM_READ_FUNCTION EQU 33
CP_WRITE_FUNCTION   EQU 21
CP_RANDOM_WRITE_FUNCTION EQU 34
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
    PUSH IX                 ; Preserve IX across BDOS.
    PUSH IY                 ; Protect the second index register as well.
    CALL CP_BDOS_ENTRY      ; Enter the CP/M dispatcher with function in C.
    POP  IY                 ; Restore IY before returning to the caller.
    POP  IX                 ; Restore IX after the 8080-compatible service.
    RET                     ; Return the BDOS result and flags unchanged.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Check available transient memory before leaving the CCP stack. The accepted
; layout may overlay CCP, so every exit uses warm boot rather than RET.
; A at the exit records 0 for success, 1 for failure or 2 for bad arguments.

CP_ENTRY:
    LD   HL,($0006)         ; Read CP/M's advertised BDOS memory boundary.
    LD   DE,CP_STACK_TOP    ; Require the fixed workspace and stack.
    OR   A                  ; Clear borrow before the unsigned comparison.
    SBC  HL,DE              ; Is the private region entirely below BDOS?
    JR   NC,CP_MEMORY_OK    ; Equality accepts the exclusive stack top.
    LD   DE,CP_MEMORY_TEXT  ; Explain rejection before opening any files.
    LD   C,9                ; Select string output on the original CCP stack.
    CALL CP_BDOS_ENTRY      ; Use BDOS before installing the private stack.
    LD   A,1                ; Record the rejection for diagnostic probes.
    JP   CP_RETURN          ; Warm boot without touching private arenas.
CP_MEMORY_OK:
    LD   SP,CP_STACK_TOP    ; Use private RAM for calls and pushes.
    CALL CP_PARSE_COMMAND   ; Parse source and output names.
    JR   C,CP_COMMAND_FAILED  ; Report a usage or filename error before I/O.
    OR   A                  ; Test whether parsing selected help-only mode.
    JR   NZ,CP_SUCCESS      ; Help returns success without assembly.
    CALL CP_RESOLVE_SOURCE  ; Resolve includes and measure all parts.
    JP   C,CP_BUILD_FAILED  ; Report source-graph failure.
    LD   HL,CP_ASO_TARGET_CAPACITY  ; All output modes cover $0100..$10000.
    LD   (CP_DESCRIPTOR+13),HL  ; Install the selected target extent.
    LD   IX,CP_DESCRIPTOR   ; Pass the measured source descriptor.
    CALL DR_ASM             ; Assemble all parts into the private RAM image.
    JR   C,CP_ASSEMBLY_FAILED  ; Leave the old output intact on failure.
    LD   DE,CP_NEWLINE_TEXT  ; Lead the success message with a newline.
    CALL CP_PRINT           ; Separate the result from any command echo.
    LD   HL,CP_OUTPUT_NAME  ; Point at the selected output name.
    CALL CP_PRINT_NAME      ; Print the basename and any nonblank extension.
    LD   DE,CP_WRITTEN_TEXT  ; Select the completion suffix.
    CALL CP_PRINT           ; Report success after the sink has committed.
CP_SUCCESS:
    XOR  A                  ; Record status zero for success or help.
    JR   CP_RETURN          ; Reload CCP through the common warm-boot exit.
CP_COMMAND_FAILED:
    CALL CP_PRINT           ; DE holds the parser's diagnostic text.
    LD   A,2                ; Use status two for argument errors.
    JR   CP_RETURN          ; Finish through the common warm-boot exit.
CP_ASSEMBLY_FAILED:
    PUSH AF                 ; Save Atom's status while printing.
    LD   A,(CP_BIN_ERROR)   ; A rejected IMAGE byte is not a source syntax error.
    OR   A                  ; Binary I/O keeps its own source-aware diagnostic.
    JR   NZ,CP_BIN_ASSEMBLY_FAILED  ; Report it with the output-failure code.
    POP  AF                 ; Restore the original Atom status before classifying.
    PUSH AF                 ; Keep it for the established output/source split.
    CP   DR_SOUT            ; Did the sink fail after source processing ended?
    JR   Z,CP_OUTPUT_FAILED  ; Source state is reclaimed after assembly.
    LD   DE,CP_ASSEMBLY_TEXT  ; Point at the diagnostic prefix.
    CALL CP_PRINT           ; Print the assembly-error prefix.
    POP  AF                 ; Recover the original public error status.
    CALL CP_PRINT_HEX       ; Print its two-digit hexadecimal status.
    LD   A,' '              ; Separate status from its source location.
    CALL CP_PUTC            ; Emit the field separator.
    CALL CP_PRINT_ERROR_LOCATION  ; Print name and one-based position.
    LD   DE,CP_NEWLINE_TEXT  ; Point at the terminating line break.
    CALL CP_PRINT           ; Finish the diagnostic line.
    JP   CP_BUILD_FAILED    ; Return failure without touching source again.
CP_BIN_ASSEMBLY_FAILED:
    POP  AF                 ; Discard Atom's statement-facing wrapper status.
    LD   DE,CP_ASSEMBLY_TEXT  ; Keep the public CP/M error prefix consistent.
    CALL CP_PRINT           ; Start the diagnostic with "Atom error".
    LD   A,DR_SOUT          ; Classify binary stream failure as output error 04.
    CALL CP_PRINT_HEX       ; Preserve the public sink-failure number.
    LD   A,' '              ; Separate the code from its source location.
    CALL CP_PUTC            ; Keep the existing diagnostic field layout.
    JP   CP_BIN_OUTPUT_FAILED  ; Add source location and binary filename.
CP_OUTPUT_FAILED:
    POP  AF                 ; Recover the public output error code.
    PUSH AF                 ; Keep the status while the prefix is printed.
    LD   DE,CP_ASSEMBLY_TEXT  ; Keep the established Atom error prefix.
    CALL CP_PRINT           ; Print the error label before the status byte.
    POP  AF                 ; Restore the output status after BDOS output.
    CALL CP_PRINT_HEX       ; Preserve DR_SOUT as the numeric code 04.
    LD   A,' '              ; Separate the code from the destination name.
    CALL CP_PUTC            ; Emit the field separator.
    LD   A,(CP_BIN_ERROR)   ; Did a binary source fail inside the IMAGE sink?
    OR   A                  ; Zero keeps the ordinary output-name diagnostic.
    JR   NZ,CP_BIN_OUTPUT_FAILED  ; Keep the source location for INCBIN errors.
    LD   HL,CP_OUTPUT_NAME  ; Identify the selected destination file.
    CALL CP_PRINT_NAME      ; Print its normalized CP/M filename.
    LD   DE,CP_NEWLINE_TEXT  ; Point at the terminating line break.
    CALL CP_PRINT           ; Finish without consulting source tables.
    JP   CP_BUILD_FAILED    ; Return failure after the ordinary sink message.
CP_BIN_OUTPUT_FAILED:
    CALL CP_PRINT_ERROR_LOCATION  ; Report the source file and line:column.
    LD   A,' '              ; Separate the source operation from its payload.
    CALL CP_PUTC            ; Emit the field separator.
    LD   HL,CP_BIN_FCB      ; The dedicated FCB retains the binary filename.
    CALL CP_PRINT_NAME      ; Identify the failed binary input.
    LD   DE,CP_BIN_READ_TEXT  ; Explain that its payload could not be read.
    CALL CP_PRINT           ; Finish the binary-source diagnostic.
CP_BUILD_FAILED:
    LD   A,1                ; Record status one for build failure.
CP_RETURN:

; The private regions may have overwritten CCP and its original return stack.
; Warm boot reloads the command processor; never return through those bytes.

    JP   $0000              ; Reload CP/M's command processor through BIOS.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Map Atom's source ordinal to the retained CP/M filename, then reread only
; the bytes before the failing position. If the file cannot be read, keep the
; original byte offset instead of printing a guessed line or column.

CP_PRINT_ERROR_LOCATION:
    LD   A,(ST_EPART)       ; Select the failed dependency-order part.
    LD   HL,CP_DESCRIPTOR   ; Read the count of valid part ordinals.
    CP   (HL)               ; Reject an impossible ordinal defensively.
    JR   NC,CP_ERROR_RAW_PART  ; Retain the original numeric diagnostic.
    LD   E,A                ; Index the dependency-order table.
    LD   D,CP_PART_ORDER/256  ; The table occupies one fixed page.
    LD   A,(DE)             ; Recover the retained-name ordinal.
    CALL CP_OPEN_PART       ; Reopen its source for position counting.
    JR   C,CP_ERROR_OPEN_OFFSET  ; Its name was printed; retain the offset.
    CALL CP_COUNT_ERROR_LOCATION  ; Convert the byte offset in this file.
    JR   C,CP_ERROR_BYTE_OFFSET  ; Report the raw offset on a read failure.
    LD   HL,CP_INPUT_FCB    ; Address the reopened file's 8.3 name.
    CALL CP_PRINT_NAME      ; Print the physical source filename.
    LD   A,':'              ; Separate filename from line number.
    CALL CP_PUTC            ; Print the first colon.
    LD   HL,(CP_DIAG_LINE)  ; Load the one-based source line.
    CALL CP_PRINT_DECIMAL   ; Print it without leading zeroes.
    LD   A,':'              ; Separate line from source column.
    CALL CP_PUTC            ; Print the second colon.
    LD   HL,(CP_DIAG_COLUMN)  ; Load the one-based byte column.
    JP   CP_PRINT_DECIMAL   ; Finish the location and return.
CP_ERROR_BYTE_OFFSET:
    LD   HL,CP_INPUT_FCB    ; The filename remains in the opened FCB.
    CALL CP_PRINT_NAME      ; Identify the unreadable source part.
CP_ERROR_OPEN_OFFSET:
    LD   DE,CP_BYTE_OFFSET_TEXT  ; Mark the fallback as a byte offset.
    CALL CP_PRINT           ; Never confuse it with line and column.
    JR   CP_ERROR_RAW_OFFSET  ; Print the unchanged hexadecimal offset.
CP_ERROR_RAW_PART:
    LD   A,(ST_EPART)       ; Recover the impossible source ordinal.
    CALL CP_PRINT_HEX       ; Preserve its two-digit hexadecimal form.
    LD   A,' '              ; Separate ordinal from byte offset.
    CALL CP_PUTC            ; Print the separator.
CP_ERROR_RAW_OFFSET:
    LD   HL,(ST_EOFF)       ; Recover Atom's original byte offset.
    PUSH HL                 ; Save it across printing its high byte.
    LD   A,H                ; Select the high byte first.
    CALL CP_PRINT_HEX       ; Emit two hexadecimal digits.
    POP  HL                 ; Restore the offset's low byte.
    LD   A,L                ; Select its remaining byte.
    JP   CP_PRINT_HEX       ; Finish the four-digit offset and return.

;@ROUTINE OUT CARRY CLOBBERS A,BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Count physical line breaks and byte columns before the reported offset.
; CRLF is one break; lone CR and lone LF are each one break. Counters start
; at one, and zero represents the sole possible overflow value, 65,536.

CP_COUNT_ERROR_LOCATION:
    LD   HL,1               ; Both positions are one-based.
    LD   (CP_DIAG_LINE),HL  ; Begin on the first source line.
    LD   (CP_DIAG_COLUMN),HL  ; Begin at its first byte column.
    LD   HL,0               ; Scan from the first source byte.
    LD   (CP_DIAG_CURSOR),HL  ; Store the current zero-based offset.
    XOR  A                  ; No preceding byte was CR.
    LD   (CP_DIAG_CR),A     ; Clear the CRLF state.
CP_DIAG_SCAN:
    LD   HL,(CP_DIAG_CURSOR)  ; Read the next byte offset.
    LD   DE,(ST_EOFF)       ; Read the failing offset as an exclusive end.
    OR   A                  ; Clear carry before comparing positions.
    SBC  HL,DE              ; Stop before consuming the failing byte.
    JR   Z,CP_DIAG_SCAN_DONE  ; The counters now describe that byte.
    LD   HL,(CP_DIAG_CURSOR)  ; Address the current source byte.
    CALL CP_RAW_SOURCE_BYTE  ; Read it through the existing CP/M cache.
    RET  C                  ; Changed or unreadable input needs a fallback.
    LD   B,A                ; Preserve the byte across cursor update.
    LD   HL,(CP_DIAG_CURSOR)  ; Advance by exactly one source byte.
    INC  HL                 ; Move to the following zero-based offset.
    LD   (CP_DIAG_CURSOR),HL  ; Save the advanced cursor.
    LD   A,B                ; Classify the byte just consumed.
    CP   13                 ; A carriage return always starts a new line.
    JR   Z,CP_DIAG_CR_BYTE  ; Remember it for an optional following LF.
    CP   10                 ; A lone line feed also starts a new line.
    JR   Z,CP_DIAG_LF_BYTE  ; Avoid double-counting CRLF.
    XOR  A                  ; Ordinary text ends CRLF lookbehind.
    LD   (CP_DIAG_CR),A     ; The preceding byte is not CR.
    LD   HL,(CP_DIAG_COLUMN)  ; Move one byte to the right.
    INC  HL                 ; Advance the one-based column.
    LD   (CP_DIAG_COLUMN),HL  ; Keep its full 16-bit value.
    JR   CP_DIAG_SCAN       ; Continue toward the error offset.
CP_DIAG_CR_BYTE:
    LD   A,1                ; Remember a preceding CR.
    LD   (CP_DIAG_CR),A     ; The next LF belongs to this break.
    CALL CP_DIAG_NEWLINE    ; Start the next line at column one.
    JR   CP_DIAG_SCAN       ; Continue after the CR byte.
CP_DIAG_LF_BYTE:
    LD   A,(CP_DIAG_CR)     ; Check whether CR already advanced the line.
    OR   A                  ; Z means this LF is a lone break.
    CALL Z,CP_DIAG_NEWLINE  ; Count a lone LF exactly once.
    XOR  A                  ; The lookbehind ends at this LF.
    LD   (CP_DIAG_CR),A     ; Clear it before another source byte.
    JR   CP_DIAG_SCAN       ; Continue after the LF byte.
CP_DIAG_SCAN_DONE:
    OR   A                  ; Return success with carry clear.
    RET                     ; Leave the computed line and column in RAM.

;@ROUTINE CLOBBERS A,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Advance to a physical source line and reset its byte column.

CP_DIAG_NEWLINE:
    LD   HL,(CP_DIAG_LINE)  ; Load the current line number.
    INC  HL                 ; Move to the next line.
    LD   (CP_DIAG_LINE),HL  ; Keep the complete 16-bit result.
    LD   HL,1               ; The first byte has column one.
    LD   (CP_DIAG_COLUMN),HL  ; Reset the column for that line.
    RET                     ; Return to the source-byte classifier.

CP_COMMAND_CODE_START:

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Accept help, one source, or source plus output. A single name derives COM.
; source derives a COM name. Names use CP/M 8.3.

CP_PARSE_COMMAND:
    XOR  A                  ; Clear command state.
    LD   (CP_ACTIVE_PART),A  ; Drop any cached source-part ordinal.
    LD   A,(CP_COMMAND_LENGTH)  ; Read the CCP's command-tail byte count.
    LD   B,A                ; Keep the remaining count beside the HL cursor.
    LD   HL,CP_COMMAND_START  ; Start at the first command-tail character.
    CALL CP_SKIP_SPACES     ; Skip leading spaces.
    JR   NZ,CP_COMMAND_SOURCE  ; Parse a non-empty command tail.
CP_COMMAND_HELP:
    LD   DE,CP_USAGE_TEXT   ; Show the compact command syntax.
    CALL CP_PRINT           ; Help performs no source or output file calls.
    LD   A,1                ; Mark help-only success for CP_ENTRY.
    OR   A                  ; Clear carry without losing the help marker.
    RET                     ; Skip source discovery and assembly.
CP_COMMAND_SOURCE:
    CALL CP_PARSE_FILENAME  ; Parse the source argument as 8.3.
    JP   C,CP_BAD_SOURCE_NAME  ; Distinguish a bad source name.
    CALL CP_SKIP_SPACES     ; Look for a second name.
    JR   Z,CP_SINGLE_NAME   ; Derive the output name and type.
    CALL CP_PARSE_FILENAME  ; Validate the explicit output name.
    JP   C,CP_BAD_OUTPUT_NAME  ; Report malformed output fields separately.
    CALL CP_SKIP_SPACES     ; Check for trailing text.
    JP   NZ,CP_BAD_USAGE    ; Reject a third argument or trailing junk.
    JR   CP_COMMAND_NAMES_READY  ; Continue with the CCP's normalized FCBs.
CP_SINGLE_NAME:

; The CCP populated default FCB 1 from the sole argument. Copy it to FCB 2 and
; replace only the extension, retaining the same normalized basename.

    LD   HL,$005C           ; Address the CCP's default source FCB.
    LD   DE,$006C           ; Address the second FCB used for output.
    LD   BC,12              ; Copy drive, basename and extension bytes.
    LDIR                    ; Copy the source basename to output.
    LD   HL,CP_COM_EXTENSION  ; Select the conventional `.COM` output type.
    LD   DE,$006C+9         ; Point at the output FCB's three-byte type.
    LD   BC,3               ; Copy exactly the extension bytes.
    LDIR                    ; Complete the one-argument output default.
CP_COMMAND_NAMES_READY:
    LD   HL,$005C           ; Read the CCP-normalized source FCB.
    LD   DE,CP_INPUT_FCB    ; Store a private copy for BDOS operations.
    LD   BC,12              ; Include drive, basename and extension.
    LDIR                    ; Preserve the selected input filename.
    LD   A,(CP_INPUT_FCB+9)  ; Inspect the first byte of its type field.
    CP   ' '                ; A blank type means the argument omitted it.
    JR   NZ,CP_INPUT_TYPE_READY  ; Keep any explicit source extension.
    LD   HL,CP_ASM_EXTENSION  ; Supply the native source extension `.ASM`.
    LD   DE,CP_INPUT_FCB+9  ; Point at the private FCB's type field.
    LD   BC,3               ; The CP/M type occupies three bytes.
    LDIR                    ; Complete the input FCB with its default type.
CP_INPUT_TYPE_READY:
    LD   HL,$006C           ; Read the CCP-normalized output FCB.
    LD   DE,CP_OUTPUT_NAME  ; Store the selected output name.
    LD   BC,12              ; Copy drive, basename and three-byte type.
    LDIR                    ; Retain the caller's requested output name.
    LD   HL,CP_OUTPUT_NAME+9  ; Point at the output extension.
    LD   DE,CP_COM_EXTENSION  ; Compare with the default COM format.
    CALL CP_OUTPUT_TYPE_EQUAL  ; Check all three extension bytes.
    JR   Z,CP_OUTPUT_TYPE_COM  ; Select format zero for COM.
    LD   HL,CP_OUTPUT_NAME+9  ; Reuse HL for another extension comparison.
    LD   DE,CP_BIN_EXTENSION  ; Compare with the raw binary format.
    CALL CP_OUTPUT_TYPE_EQUAL  ; Check for an exact BIN extension.
    JR   Z,CP_OUTPUT_TYPE_BIN  ; Select format one for BIN.
    LD   HL,CP_OUTPUT_NAME+9  ; Test the last supported output extension.
    LD   DE,CP_HEX_EXTENSION  ; Compare with the Intel HEX format.
    CALL CP_OUTPUT_TYPE_EQUAL  ; Check for an exact HEX extension.
    JR   Z,CP_OUTPUT_TYPE_HEX  ; Select Intel HEX when the type matches.
    LD   HL,CP_OUTPUT_NAME+9  ; Reuse HL to test the ASO extension.
    LD   DE,CP_ASO_EXTENSION  ; Compare with the serialized operation format.
    CALL CP_OUTPUT_TYPE_EQUAL  ; Check all three ASO extension bytes.
    JR   NZ,CP_BAD_OUTPUT_NAME  ; Reject any other output type.
    LD   A,3                ; Assign format code three to ASO.
    JR   CP_OUTPUT_TYPE_READY  ; Save the format and check names.
CP_OUTPUT_TYPE_HEX:
    LD   A,2                ; Assign format code two to Intel HEX.
    JR   CP_OUTPUT_TYPE_READY  ; Save the format and check names.
CP_OUTPUT_TYPE_BIN:
    LD   A,1                ; Assign format code one to raw BIN.
    JR   CP_OUTPUT_TYPE_READY  ; Save the type and continue filename checks.
CP_OUTPUT_TYPE_COM:
    XOR  A                  ; Assign format code zero to CP/M COM.
CP_OUTPUT_TYPE_READY:

; Preserve the normalized input and output names in adapter-owned FCB storage.
; Input defaults to ASM when no type was supplied; output type selects 0=COM,
; 1=BIN, 2=HEX or 3=ASO.

    LD   (CP_OUTPUT_FORMAT),A  ; Save the selected output format.
    LD   HL,CP_INPUT_FCB    ; Compare source and output identities.
    LD   DE,CP_OUTPUT_NAME  ; Address the output's twelve-byte identity.
    CALL CP_NAMES_EQUAL     ; Reject overwriting the file being assembled.
    JR   Z,CP_BAD_NAME_CONFLICT  ; Source and output must be distinct files.
    CALL CP_SET_TEMP_FCB    ; Build the transaction's temporary filename.
    CALL CP_CHECK_WORK_NAME  ; Check for source collision or existing file.
    RET  C                  ; Stop on a temp-name conflict.
    CALL CP_SET_BACKUP_FCB  ; Build the transaction's backup filename.
    CALL CP_CHECK_WORK_NAME  ; Apply the same collision and existence checks.
    RET                     ; Return the final preflight status in carry.

;@ROUTINE IN DE,HL OUT A,B,DE,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Compare the three-byte output-type selectors at DE and HL.

CP_OUTPUT_TYPE_EQUAL:
    LD   B,3                ; Count the three bytes in a CP/M file type.
CP_OUTPUT_TYPE_BYTE:
    LD   A,(DE)             ; Read the candidate extension byte.
    CP   (HL)               ; Compare it with the requested extension.
    RET  NZ                 ; Stop on the first mismatch, preserving NZ.
    INC  DE                 ; Advance to the next byte in the candidate.
    INC  HL                 ; Advance to the corresponding expected byte.
    DJNZ CP_OUTPUT_TYPE_BYTE  ; Compare all three type bytes.
    RET                     ; Return Z when every byte matched.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Prove the temporary name differs from the source and is not already present.

CP_CHECK_WORK_NAME:
    LD   HL,CP_INPUT_FCB    ; Address the source name.
    LD   DE,CP_WORK_FCB     ; Address the temporary or backup name.
    CALL CP_NAMES_EQUAL     ; Test all drive, basename and type bytes.
    JR   Z,CP_BAD_NAME_CONFLICT  ; Never let publication replace the source.
    JP   CP_AUXILIARY_MUST_NOT_EXIST  ; Require an unused work name.
CP_BAD_USAGE:
    LD   DE,CP_USAGE_TEXT   ; Select the command syntax diagnostic.
    SCF                     ; Return parser failure to CP_ENTRY.
    RET                     ; Keep the message address in DE.
CP_BAD_SOURCE_NAME:
    LD   DE,CP_SOURCE_NAME_TEXT  ; Select the source-name diagnostic.
    SCF                     ; Mark the invalid source argument.
    RET                     ; Return its message address in DE.
CP_BAD_OUTPUT_NAME:
    LD   DE,CP_OUTPUT_NAME_TEXT  ; Select the output-name diagnostic.
    SCF                     ; Mark the invalid output argument.
    RET                     ; Return its message address in DE.
CP_BAD_NAME_CONFLICT:
    LD   DE,CP_NAME_CONFLICT_TEXT  ; Select the name-conflict message.
    SCF                     ; Refuse a colliding output or work filename.
    RET                     ; Return the diagnostic address in DE.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require the auxiliary file named by CP_WORK_FCB not to exist.

CP_AUXILIARY_MUST_NOT_EXIST:
    LD   DE,CP_WORK_FCB     ; Address the candidate temporary or backup FCB.
    LD   C,CP_OPEN_FUNCTION  ; Ask BDOS whether the named file already exists.
    CALL CP_BDOS            ; FF means the file was not found.
    INC  A                  ; Convert the not-found result into zero.
    JR   Z,CP_AUXILIARY_AVAILABLE  ; The name is free.
    LD   DE,CP_WORK_FCB     ; Reuse the opened candidate FCB for closing it.
    LD   C,CP_CLOSE_FUNCTION  ; Select the matching CP/M close operation.
    CALL CP_BDOS            ; Close the existing file.
    LD   DE,CP_AUXILIARY_EXISTS_TEXT  ; Select the collision diagnostic.
    SCF                     ; Report that the auxiliary file is occupied.
    RET                     ; Preserve its message pointer in DE.
CP_AUXILIARY_AVAILABLE:
    XOR  A                  ; Clear carry and status for an unused name.
    RET                     ; Allow the caller to check or use the name.

;@ROUTINE IN B,HL OUT A,B,HL,ZERO CLOBBERS CARRY,SIGN,PARITY,HALFCARRY
; Advance HL and reduce B past leading command-tail spaces.

CP_SKIP_SPACES:
    LD   A,B                ; Check whether any command-tail bytes remain.
    OR   A                  ; Z marks the end of the tail.
    RET  Z                  ; Leave HL at the end when no bytes remain.
    LD   A,(HL)             ; Inspect the next unconsumed character.
    CP   ' '                ; CP/M command separators are ordinary spaces.
    RET  NZ                 ; Stop at the first non-space byte.
    INC  HL                 ; Consume one leading or separating space.
    DEC  B                  ; Keep the remaining-byte count in step with HL.
    JR   CP_SKIP_SPACES     ; Skip a run of spaces before returning.

;@ROUTINE IN B,HL OUT A,B,HL,CARRY CLOBBERS C,D,ZERO,SIGN,PARITY,HALFCARRY
; Parse one unquoted, current-drive 8.3 filename without consuming its
; trailing space. Carry reports an empty, overlong, wildcard, drive-qualified,
; or otherwise invalid field.

CP_PARSE_FILENAME:
    LD   D,8                ; Start with the eight-character basename limit.
    LD   C,0                ; Count characters in the current name field.
CP_PARSE_FILENAME_BYTE:
    LD   A,B                ; Check the remaining tail length.
    OR   A                  ; Z marks the end of the tail.
    JR   Z,CP_FILENAME_DONE  ; Validate the final name or extension length.
    LD   A,(HL)             ; Read the next unquoted filename character.
    CP   ' '                ; Space terminates this name.
    JR   Z,CP_FILENAME_DONE  ; Leave the separator for CP_SKIP_SPACES.
    CP   '.'                ; A dot switches from basename to extension.
    JR   NZ,CP_FILENAME_DATA  ; Validate an ordinary name byte.
    LD   A,D                ; D holds the current field limit.
    CP   8                  ; Accept a dot only after the basename field.
    JR   NZ,CP_FILENAME_FAILURE  ; Reject a second dot in the extension.
    LD   A,C                ; Require at least one basename character.
    OR   A                  ; Test the current field's character count.
    JR   Z,CP_FILENAME_FAILURE  ; Reject a leading dot and empty basename.
    LD   D,3                ; Limit the extension to three bytes.
    LD   C,0                ; Start counting extension characters.
    JR   CP_FILENAME_CONSUME  ; Consume the separator dot without counting it.
CP_FILENAME_DATA:
    CALL CP_FILENAME_CHAR   ; Validate the name byte.
    RET  C                  ; Propagate an invalid byte.
    INC  C                  ; Count this character in the current field.
    LD   A,D                ; Load the basename or extension capacity.
    CP   C                  ; Compare limit and new length.
    JR   C,CP_FILENAME_FAILURE  ; Reject an overlong field.
CP_FILENAME_CONSUME:
    INC  HL                 ; Advance past a validated character or the dot.
    DEC  B                  ; Reduce the remaining command-tail byte count.
    JR   CP_PARSE_FILENAME_BYTE  ; Continue until a separator or end of tail.
CP_FILENAME_DONE:
    LD   A,C                ; Check the final field length.
    OR   A                  ; Set Z for an empty final field.
    JR   Z,CP_FILENAME_FAILURE  ; Reject an empty name or a trailing dot.
    RET                     ; Leave any separating space unconsumed.
CP_FILENAME_FAILURE:
    SCF                     ; Report an invalid name.
    RET                     ; Return carry to the command parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Validate one character for use in a CP/M 8.3 filename.

CP_FILENAME_CHAR:
    CP   '!'                ; Reject control characters and space below '!'.
    RET  C                  ; Reject bytes below '!'.
    CP   $7F                ; Reject DEL and high-bit bytes.
    JR   NC,CP_FILENAME_CHAR_BAD  ; Not printable ASCII.
    CP   '*'                ; Punctuation before '*' is allowed after '!'.
    JR   C,CP_FILENAME_CHAR_HIGH  ; Accept this punctuation range.
    CP   '-'                ; Exclude '*', '+' and ',' before the hyphen.
    JR   C,CP_FILENAME_CHAR_BAD  ; Exclude '*', '+' and ','.
    CP   '/'                ; Reject the path separator.
    JR   Z,CP_FILENAME_CHAR_BAD  ; Reject a path separator explicitly.
    CP   ':'                ; Test the next punctuation range.
    JR   C,CP_FILENAME_CHAR_HIGH  ; Permit bytes below ':'.
    CP   '@'                ; Exclude ':', ';', '<', '=', '>' and '?'.
    JR   C,CP_FILENAME_CHAR_BAD  ; These include drive and wildcard syntax.
CP_FILENAME_CHAR_HIGH:
    CP   '['                ; Uppercase letters below '[' are accepted.
    JR   C,CP_FILENAME_CHAR_OK  ; Permit digits, punctuation and A through Z.
    CP   '^'                ; Set the boundary after '[', backslash and ']'.
    JR   C,CP_FILENAME_CHAR_BAD  ; Exclude '[', '\\' and ']'.
    CP   '_'                ; Check the underscore boundary explicitly.
    JR   Z,CP_FILENAME_CHAR_BAD  ; Do not admit underscore into an 8.3 field.
CP_FILENAME_CHAR_OK:
    OR   A                  ; Clear carry; keep the valid byte.
    RET                     ; Return the accepted character in A.
CP_FILENAME_CHAR_BAD:
    SCF                     ; Mark this character as invalid for a filename.
    RET                     ; Return carry to CP_PARSE_FILENAME.

;@ROUTINE IN DE,HL OUT A,ZERO CLOBBERS B,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Compare two drive-plus-8.3-name records for exact equality.

CP_NAMES_EQUAL:
    LD   B,12               ; Compare drive and eleven name/type bytes.
CP_NAMES_EQUAL_BYTE:
    LD   A,(DE)             ; Read the first FCB's name byte.
    CP   (HL)               ; Compare it with the corresponding second byte.
    RET  NZ                 ; Return immediately when the identities differ.
    INC  DE                 ; Advance the first name cursor.
    INC  HL                 ; Advance the second name cursor.
    DJNZ CP_NAMES_EQUAL_BYTE  ; Compare the complete twelve-byte identity.
    XOR  A                  ; Return Z after all bytes match.
    RET                     ; Carry is clear for the equal-name result.
CP_COMMAND_CODE_END:

CP_SOURCE_CODE_START:

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Prepare a blank ordinary FCB whose name/type fields are space-filled.

CP_CLEAR_INPUT_FCB:
    LD   DE,CP_INPUT_FCB    ; Point at the input FCB's drive byte.
    XOR  A                  ; Select the logged-in drive by default.
    LD   (DE),A             ; Store drive zero before filling the name.
    INC  DE                 ; Advance to the eleven name/type bytes.
    LD   B,11               ; Count all eight name and three type bytes.
    LD   A,' '              ; CP/M pads unused name fields with spaces.
    CALL CP_CLEAR_WORK_FCB  ; Fill the complete name/type area.
    JP   CP_CLEAR_FCB_TAIL  ; Clear the remaining FCB control fields.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Reject output, temporary or backup names that collide with the source name.

CP_CHECK_SOURCE_CONFLICT:
    LD   HL,CP_INPUT_FCB    ; Keep the original source identity in HL.
    LD   DE,CP_OUTPUT_NAME  ; Compare it with the requested output name.
    CALL CP_NAMES_EQUAL     ; Z means both twelve-byte FCB identities match.
    JR   Z,CP_SOURCE_NAME_CONFLICT  ; Never replace the source file.
    CALL CP_SET_TEMP_FCB    ; Construct the temporary output filename.
    LD   HL,CP_INPUT_FCB    ; Restore the source FCB pointer for comparison.
    LD   DE,CP_WORK_FCB     ; The temporary name occupies the work FCB.
    CALL CP_NAMES_EQUAL     ; Reject a temporary name that aliases the source.
    JR   Z,CP_SOURCE_NAME_CONFLICT  ; Preserve the source file.
    CALL CP_SET_BACKUP_FCB  ; Construct the backup filename for the output.
    LD   HL,CP_INPUT_FCB    ; Compare the source against that third identity.
    LD   DE,CP_WORK_FCB     ; The backup candidate is now in the work FCB.
    CALL CP_NAMES_EQUAL     ; Z again means the names would collide.
    JR   Z,CP_SOURCE_NAME_CONFLICT  ; Refuse a source/output collision.
    XOR  A                  ; A=0 reports that all three names are distinct.
    RET                     ; Return clear carry with the success result.
CP_SOURCE_NAME_CONFLICT:
    LD   DE,CP_NAME_CONFLICT_TEXT  ; Return the collision message in DE.
    SCF                     ; Mark the preflight check as failed.
    RET                     ; Leave file creation to the caller's error path.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Read one logical source byte through a 128-byte random-record cache. The
; pre-scan proves each requested record exists until this command returns.

CP_SOURCE_READ_BYTE:
    JP   CP_RESOLVED_READ_BYTE  ; Expose the resolved source-byte reader.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Resolve the root source and its leading %INCLUDE graph. Names are retained
; as exact CP/M 8.3 identities, while descriptors are emitted in dependency-
; first order. No intermediate source-order file is involved.

CP_RESOLVE_SOURCE:
    XOR  A                  ; Start with no published descriptors or order.
    LD   (CP_DESCRIPTOR),A  ; The native core must not see a stale part count.
    LD   (CP_ORDER_COUNT),A  ; No source has reached dependency order yet.
    LD   (CP_SCAN_INDEX),A  ; Discovery begins at root ordinal zero.
    INC  A                  ; The root itself is the first retained name.
    LD   (CP_NAME_COUNT),A  ; Record one known source part.
    LD   HL,CP_INPUT_FCB+1  ; Skip the drive byte and retain the 8.3 name.
    LD   DE,CP_PART_NAMES   ; Store it in the root's ordinal-zero slot.
    LD   BC,11              ; FCB name and type fields occupy eleven bytes.
    LDIR                    ; Copy the root name into the resolver table.
    LD   A,$FF              ; Prepare the source-selection field for this run.
    LD   (CP_ACTIVE_PART),A  ; Clear any stale current-part selection.

; First discover every exact name reachable from the root.

CP_DISCOVER_PART:
    XOR  A                  ; Mode zero records newly found include names.
    LD   (CP_SCAN_MODE),A   ; Discovery does not test dependency ordering.
    LD   A,(CP_SCAN_INDEX)  ; Select the next retained source name.
    CALL CP_SCAN_PART       ; Read its leading header and visit its includes.
; The scan helper reports malformed input, open failure or offset overflow.
    JP   C,CP_RESOLVE_FAILURE  ; Stop on any reported scan failure.
    LD   HL,CP_SCAN_INDEX   ; Advance the discovery cursor in place.
    INC  (HL)               ; Each retained name is scanned for dependencies.
    LD   A,(CP_NAME_COUNT)  ; New includes may have extended this count.
    CP   (HL)               ; Compare the next ordinal with the live count.
    JR   NZ,CP_DISCOVER_PART  ; Scan every discovered source part.

; Emit parts after their dependencies. Bit 7 of the first retained-name byte
; marks an emitted part. Name comparisons and FCB reconstruction mask it away.
; A pass with no progress proves a cycle without recursion.

CP_TOPO_PASS:
    XOR  A                  ; Begin another pass over all discovered files.
    LD   (CP_SCAN_INDEX),A  ; Restart at the root ordinal.
    LD   (CP_SCAN_PROGRESS),A  ; Track whether this pass emits any source.
CP_TOPO_PART:
    LD   A,(CP_SCAN_INDEX)  ; Read the candidate part's ordinal.
    CALL CP_NAME_POINTER    ; HL points to its retained eleven-byte name.
    BIT  7,(HL)             ; Bit 7 marks a part already placed in the order.
    JR   NZ,CP_TOPO_NEXT    ; Do not emit a part twice.
    LD   A,1                ; Mode one checks whether the includes are ready.
    LD   (CP_SCAN_MODE),A   ; The scanner reports one for a pending child.
    LD   A,(CP_SCAN_INDEX)  ; Scan this part's include header.
    CALL CP_SCAN_PART       ; A=0 means every dependency is already ordered.
    JP   C,CP_RESOLVE_FAILURE  ; Preserve scanner errors as resolver failures.
    OR   A                  ; Is an included child still unordered?
    JR   NZ,CP_TOPO_NEXT    ; Defer this part until a later pass.
    LD   A,(CP_ORDER_COUNT)  ; Append at the next dependency-order position.
    LD   E,A                ; E is the byte offset into the order table.
    LD   D,CP_PART_ORDER/256  ; The table remains within its fixed page.
    LD   A,(CP_SCAN_INDEX)  ; Store this source's original ordinal.
    LD   (DE),A             ; Map output order to source identity.
    CALL CP_NAME_POINTER    ; Recover the name after writing the order byte.
    SET  7,(HL)             ; Mark this name as emitted for later scans.
    LD   HL,CP_ORDER_COUNT  ; Point to the number of ordered source parts.
    INC  (HL)               ; Include the part just appended above.
    LD   A,1                ; Record that this pass made progress.
    LD   (CP_SCAN_PROGRESS),A  ; Newly ready dependants can run next pass.
CP_TOPO_NEXT:
    LD   HL,CP_SCAN_INDEX   ; Advance to the next discovered name.
    INC  (HL)               ; The table follows original discovery order.
    LD   A,(CP_NAME_COUNT)  ; Read the current count, including new includes.
    CP   (HL)               ; Compare against the next candidate ordinal.
    JR   NZ,CP_TOPO_PART    ; Continue this pass while names remain.
    LD   A,(CP_ORDER_COUNT)  ; Count the parts already placed in order.
    LD   HL,CP_NAME_COUNT   ; Compare it with the total discovered count.
    CP   (HL)               ; Equality means every dependency was ordered.
    JR   Z,CP_BUILD_DESCRIPTORS  ; Build the native part descriptors.
    LD   A,(CP_SCAN_PROGRESS)  ; Check whether this pass placed any source.
    OR   A                  ; A zero value means ordering made no progress.
    JR   NZ,CP_TOPO_PASS    ; Retry now that some dependencies are ready.
    LD   DE,CP_INCLUDE_CYCLE_TEXT  ; No progress means an include cycle.
    JR   CP_RESOLVE_FAILURE  ; Report it through the shared failure path.

; Measure the already validated parts in final order and build the ordinary
; native five-byte descriptors. Each starts at logical zero and ends at the
; measured 16-bit byte length; source storage itself remains in CP/M files.

CP_BUILD_DESCRIPTORS:
    XOR  A                  ; Start at the first dependency-ordered part.
    LD   (CP_SCAN_INDEX),A  ; This cursor indexes CP_PART_ORDER.
    LD   HL,CP_PART_DESCRIPTORS  ; Point to the native part-descriptor array.
    LD   (CP_DESCRIPTOR_CURSOR),HL  ; The append helper advances this pointer.
CP_BUILD_DESCRIPTOR:
    LD   A,(CP_SCAN_INDEX)  ; Select the next output-order position.
    LD   E,A                ; E indexes the one-byte order table.
    LD   D,CP_PART_ORDER/256  ; Address its fixed high-page storage.
    LD   A,(DE)             ; Recover the original discovery ordinal.
    CALL CP_OPEN_PART       ; Reopen it before measuring its logical length.
    JP   C,CP_RESOLVE_FAILURE  ; Abort if the part cannot be reopened.
    LD   HL,0               ; Count source bytes from logical offset zero.
CP_MEASURE_BYTE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read a byte and advance logical offset HL.
    JR   NC,CP_MEASURE_BYTE  ; Carry clear means more source bytes remain.
    OR   A                  ; A=0 means EOF/read failure; A=2 overflow.
    JP   NZ,CP_RESOLVE_IO   ; Report a source length beyond the 16-bit range.
    CALL CP_APPEND_DESCRIPTOR  ; Store this ordinal and measured [0,HL) range.
    LD   HL,CP_SCAN_INDEX   ; Advance the position in dependency order.
    INC  (HL)               ; The order table has one entry per retained name.
    LD   A,(CP_NAME_COUNT)  ; Compare with the total number of source parts.
    CP   (HL)               ; Continue while another descriptor remains.
    JR   NZ,CP_BUILD_DESCRIPTOR  ; Measure the next dependency-ordered file.
    LD   A,(CP_NAME_COUNT)  ; Publish the final descriptor count to the core.
    LD   (CP_DESCRIPTOR),A  ; Descriptors are complete and ready for assembly.
    CALL CP_BIN_PREPARE    ; Validate active binary includes before assembly.
    JP   C,CP_RESOLVE_FAILURE  ; No output transaction begins after preflight fail.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Return after publishing the count.
CP_RESOLVE_IO:
    LD   HL,CP_INPUT_FCB    ; Identify the overlong source.
    CALL CP_PRINT_NAME      ; Print its parsed 8.3 name before the error text.
    LD   DE,CP_READ_FAILED_TEXT  ; Select the source-read error text.
CP_RESOLVE_FAILURE:
    CALL CP_PRINT           ; Print the error selected in DE.
    SCF                     ; Return failure to the command entry point.
    RET                     ; No partial descriptor set reaches the core.

; Preflight active INCBIN statements after dependency order and definitions
; are final. The scan records exact source anchors before the core starts.

CP_BIN_PREPARE:
    XOR  A                  ; Disable rewriting until the table is complete.
    LD   (CP_BIN_ENABLED),A ; No partially collected row may reach assembly.
    LD   (CP_BIN_COUNT),A   ; Start with an empty binary-include table.
    LD   (CP_BIN_ERROR),A   ; Clear the source-sink failure discriminator.
    LD   HL,CP_BIN_TABLE    ; Select the first fixed-width metadata row.
    LD   (CP_BIN_BUILD_PTR),HL  ; The collector appends rows in source order.
    XOR  A                  ; Rescan the root to rebuild its numeric defines.
    LD   (CP_SCAN_INDEX),A  ; Root discovery ordinal is always zero.
    LD   A,1                ; Ordering mode verifies every header child is ready.
    LD   (CP_SCAN_MODE),A   ; Root definitions are rebuilt during this scan.
    XOR  A                  ; Scan the root header from its first source byte.
    CALL CP_SCAN_PART       ; Rebuild definitions without changing part order.
    RET  C                  ; Preserve a header, include or file-read failure.
    OR   A                  ; Every dependency must already be ordered.
    JP   NZ,CP_BIN_INVALID  ; A pending root child violates resolver invariants.
    LD   A,$FF              ; Force the first ordered source part to reopen.
    LD   (CP_ACTIVE_PART),A ; Runtime conditional state resets on that open.
    XOR  A                  ; Begin scanning dependency-order ordinal zero.
    LD   (CP_BIN_SCAN_PART),A  ; Metadata uses the assembler's part ordinals.
    LD   HL,CP_PART_DESCRIPTORS  ; The first five-byte descriptor is ordinal zero.
    LD   (CP_BIN_SCAN_DESC),HL  ; Advance this pointer once per source part.
    LD   HL,0               ; Every resolved source part begins at offset zero.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; Track the next byte requested from Atom.
    CALL CP_BIN_SCAN_LOAD_END  ; Cache this part's exclusive logical end.
CP_BIN_SCAN_LINE:
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Read the next filtered source position.
    LD   DE,(CP_BIN_SCAN_END)  ; Compare it with the descriptor's exclusive end.
    OR   A                  ; Clear carry before the unsigned subtraction.
    SBC  HL,DE              ; Has this part reached its measured end?
    JP   NC,CP_BIN_SCAN_PART_DONE  ; Move on without requesting an EOF byte.
    CALL CP_BIN_READ_BYTE   ; Apply conditional masking and advance the cursor.
    JP   C,CP_BIN_SOURCE_READ_FAILED  ; A changed file cannot pass preflight.
    CP   ' '                ; Ignore leading source indentation.
    JR   Z,CP_BIN_SCAN_LINE  ; Continue to the first token on this physical line.
    CP   9                  ; A tab also precedes an optional label or directive.
    JR   Z,CP_BIN_SCAN_LINE  ; Leave tab-separated source syntax unchanged.
    CP   13                 ; CR marks a physical line boundary.
    JR   Z,CP_BIN_SCAN_LINE  ; The next byte may be LF or the next line.
    CP   10                 ; LF-only files use the same outer scan loop.
    JR   Z,CP_BIN_SCAN_LINE  ; The line break was already consumed.
    CP   ';'                ; A comment cannot contain an assembler directive.
    JP   Z,CP_BIN_SKIP_LINE  ; Ignore its remaining bytes through line end.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; The token began at the byte just read.
    DEC  HL                 ; Convert the next-byte cursor to its start offset.
    LD   (CP_BIN_STATEMENT),HL  ; Retain a possible label's source position.
    CALL CP_BIN_SCAN_TOKEN  ; Collect and uppercase the first source token.
    JP   C,CP_BIN_TOKEN_STATUS  ; Distinguish token length after the full scan.
CP_BIN_FIRST_TOKEN_READY:
    LD   (CP_BIN_BYTE_TEMP),A  ; Keep the delimiter across keyword matching.
    LD   HL,CP_BIN_WORD_INCBIN  ; Select the exact six-byte operation name.
    LD   B,6                ; Do not accept a prefix or longer identifier.
    CALL CP_PP_MATCH_WORD   ; Compare the case-folded token buffer.
    JR   Z,CP_BIN_FIRST_IS_INCBIN  ; A direct statement may begin with INCBIN.
    LD   A,(CP_BIN_BYTE_TEMP)  ; Other first names may be colon labels.
    CP   ':'                ; Test for a directly adjacent label separator.
    JP   Z,CP_BIN_LABEL_AFTER_COLON  ; Read the operation after this label.
    CP   ' '                ; The colon may also follow source whitespace.
    JR   Z,CP_BIN_LABEL_SPACE  ; Check for that common label layout.
    CP   9                  ; Tabs may precede the optional colon as well.
    JR   Z,CP_BIN_LABEL_SPACE  ; Ignore spaces while looking for the colon.
    CP   13                 ; A consumed CR already ended this ordinary statement.
    JP   Z,CP_BIN_SCAN_LINE  ; Do not skip the following physical source line.
    CP   10                 ; LF-only files terminate the token in the same way.
    JP   Z,CP_BIN_SCAN_LINE  ; Resume immediately after the consumed line ending.
    JP   CP_BIN_SKIP_LINE   ; An unrelated statement has no binary input.
CP_BIN_FIRST_IS_INCBIN:
    LD   HL,(CP_BIN_STATEMENT)  ; Retain the token location for malformed forms too.
    LD   (CP_BIN_TOKEN_OFFSET),HL  ; Diagnostics always point at this keyword.
    LD   A,(CP_BIN_BYTE_TEMP)  ; A colon makes this token a label, not an op.
    CP   ':'                ; Permit a label named INCBIN before another op.
    JP   Z,CP_BIN_LABEL_AFTER_COLON  ; Inspect the statement after its colon.
    CP   ' '                ; Whitespace may precede a label's colon.
    JR   Z,CP_BIN_INCBIN_SPACE  ; Distinguish INCBIN: from the directive form.
    CP   9                  ; A tab may also separate a label from its colon.
    JR   Z,CP_BIN_INCBIN_SPACE  ; Use the same bounded lookahead for either form.
    CP   13                 ; A directive cannot continue on the next source line.
    JP   Z,CP_BIN_INVALID   ; Reject a missing same-line filename and count.
    CP   10                 ; LF-only source has the same operand boundary.
    JP   Z,CP_BIN_INVALID   ; Never let INCBIN borrow operands from a later line.
    CP   0                  ; EOF after the keyword is an incomplete directive.
    JP   Z,CP_BIN_INVALID   ; Require a separator and one complete operand list.
    CP   ';'                ; A comment without operands is still incomplete.
    JP   Z,CP_BIN_INVALID   ; Do not read through the comment into another line.
    JP   CP_BIN_INVALID     ; The operation requires horizontal separation.
CP_BIN_INCBIN_SPACE:
    CALL CP_BIN_READ_BYTE   ; Look past optional whitespace for a label colon.
    JP   C,CP_BIN_INVALID   ; A directive with no operands is incomplete.
    CP   ' '                ; Skip additional spaces while checking the colon.
    JR   Z,CP_BIN_INCBIN_SPACE  ; Keep the lookahead on this physical line.
    CP   9                  ; Tabs are the only other permitted lookahead space.
    JR   Z,CP_BIN_INCBIN_SPACE  ; Continue until colon or the first operand byte.
    CP   ':'                ; A matching token plus colon is a label declaration.
    JP   Z,CP_BIN_LABEL_AFTER_COLON  ; Its following token may be another operation.
    CP   13                 ; A directive's operands must remain on this line.
    JP   Z,CP_BIN_INVALID   ; Reject a line break before the quoted filename.
    CP   10                 ; Do not let LF-only input continue into a new line.
    JP   Z,CP_BIN_INVALID   ; Keep the directive grammar physically line-bounded.
    CP   ';'                ; An operand cannot be replaced by a comment.
    JP   Z,CP_BIN_INVALID   ; Reject the incomplete directive before assembly.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; The first nonspace operand byte was consumed.
    DEC  HL                 ; Restore the cursor so the operand parser reads it.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; The quote or invalid byte stays on this line.
    JR   CP_BIN_DIRECT_INCLUDE  ; Parse only after the boundary checks above.
CP_BIN_DIRECT_INCLUDE:
    CALL CP_BIN_PARSE_INCLUDE  ; Validate path/count and append one metadata row.
    JP   C,CP_BIN_PREPARE_RETURN  ; Keep the diagnostic selected by the helper.
    JP   CP_BIN_SCAN_LINE   ; Continue after the consumed source line.
CP_BIN_LABEL_SPACE:
    CALL CP_BIN_READ_BYTE   ; Find the next non-space byte after a possible label.
    JP   C,CP_BIN_SCAN_LINE  ; EOF ends this final, non-directive source line.
    CP   ' '                ; Skip another ordinary space before a colon.
    JR   Z,CP_BIN_LABEL_SPACE  ; Continue through the label's horizontal padding.
    CP   9                  ; Tabs have the same role around the colon.
    JR   Z,CP_BIN_LABEL_SPACE  ; Continue until a delimiter or another token.
    CP   ':'                ; A colon confirms this first token is a label.
    JR   Z,CP_BIN_LABEL_AFTER_COLON  ; Parse a possible INCBIN operation next.
    CP   13                 ; The delimiter was already consumed from this line.
    JP   Z,CP_BIN_SCAN_LINE  ; Do not skip the following source line as a tail.
    CP   10                 ; LF-only sources terminate the optional label probe.
    JP   Z,CP_BIN_SCAN_LINE  ; Continue directly at the next physical line.
    JP   CP_BIN_SKIP_LINE   ; No colon means this was not a supported label form.
CP_BIN_LABEL_AFTER_COLON:
    CALL CP_BIN_READ_BYTE   ; Read the first byte after the label separator.
    JP   C,CP_BIN_SCAN_LINE  ; A label-only final line has no binary operation.
    CP   ' '                ; Ignore indentation before the operation name.
    JR   Z,CP_BIN_LABEL_AFTER_COLON  ; Continue across ordinary spaces.
    CP   9                  ; Tabs may separate the colon from the operation.
    JR   Z,CP_BIN_LABEL_AFTER_COLON  ; Continue across horizontal whitespace.
    CP   13                 ; A line ending leaves the label without an operation.
    JP   Z,CP_BIN_SCAN_LINE  ; Begin the next physical line across this module.
    CP   10                 ; An LF-only line has the same empty-tail result.
    JP   Z,CP_BIN_SCAN_LINE  ; Resume at the byte after LF across this module.
    CP   ';'                ; A trailing comment has no operation token.
    JR   Z,CP_BIN_SKIP_LINE  ; Consume its remaining line before continuing.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; The operation token began at the byte read.
    DEC  HL                 ; Convert the next-byte cursor to its start offset.
    LD   (CP_BIN_TOKEN_OFFSET),HL  ; Store the exact diagnostic/sink position.
    CALL CP_BIN_SCAN_TOKEN  ; Collect the operation following the label.
    JR   NC,CP_BIN_LABEL_TOKEN_READY  ; A consumed delimiter completes the token.
    OR   A                  ; A=1 means too long; A=0 means ordinary EOF.
    JP   NZ,CP_BIN_SKIP_LINE  ; An overlong operation cannot equal INCBIN.
    XOR  A                  ; EOF acts as a delimiter for an incomplete directive.
CP_BIN_LABEL_TOKEN_READY:
    LD   (CP_BIN_BYTE_TEMP),A  ; Preserve the operation's following delimiter.
    LD   HL,CP_BIN_WORD_INCBIN  ; Select the supported binary directive name.
    LD   B,6                ; Match every letter in INCBIN.
    CALL CP_PP_MATCH_WORD   ; Compare without accepting an identifier prefix.
    JR   NZ,CP_BIN_LABEL_NOT_INCBIN  ; Other labeled statements need no rewrite.
    LD   A,(CP_BIN_BYTE_TEMP)  ; The directive needs same-line horizontal spacing.
    CP   ' '                ; Ordinary spaces separate the quoted operand.
    JR   Z,CP_BIN_LABEL_INCLUDE  ; Parse after validating this boundary.
    CP   9                  ; Tabs are the other accepted separator.
    JP   NZ,CP_BIN_INVALID  ; Do not consume a path from another source line.
CP_BIN_LABEL_INCLUDE:
    CALL CP_BIN_PARSE_INCLUDE  ; Preflight and record the labeled binary input.
    JP   C,CP_BIN_PREPARE_RETURN  ; Stop before any output transaction begins.
    JP   CP_BIN_SCAN_LINE   ; Continue at the next unconsumed source byte.
CP_BIN_LABEL_NOT_INCBIN:
    LD   A,(CP_BIN_BYTE_TEMP)  ; The parser already consumed this delimiter.
    CP   ';'                ; A comment delimiter requires skipping its tail.
    JR   Z,CP_BIN_SKIP_LINE  ; Ignore the rest of the physical line.
    CP   ' '                ; A non-INCBIN statement may have more operands.
    JR   Z,CP_BIN_SKIP_LINE  ; Skip them without scanning their text as labels.
    CP   9                  ; Tabs also begin the remainder of the statement.
    JR   Z,CP_BIN_SKIP_LINE  ; Keep operand names out of directive detection.
    JP   CP_BIN_SCAN_LINE   ; CR, LF or EOF was already consumed.
CP_BIN_TOKEN_STATUS:
    OR   A                  ; A=1 marks an overlong token; A=0 marks EOF.
    JP   Z,CP_BIN_FIRST_TOKEN_READY  ; An exact INCBIN token at EOF is malformed.
    JP   CP_BIN_SKIP_LINE   ; No supported directive can exceed the token limit.
CP_BIN_SKIP_LINE:
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Stop at the measured part end if needed.
    LD   DE,(CP_BIN_SCAN_END)  ; Keep random reads inside the source descriptor.
    OR   A                  ; Clear carry before the unsigned comparison.
    SBC  HL,DE              ; Is there another byte on this line?
    JP   NC,CP_BIN_SCAN_LINE  ; The next iteration advances to another part.
    CALL CP_BIN_READ_BYTE   ; Consume one filtered byte from the comment/tail.
    JP   C,CP_BIN_SOURCE_READ_FAILED  ; A premature read failure is not EOF.
    CP   13                 ; CR ends the current physical line.
    JP   Z,CP_BIN_SCAN_LINE  ; Resume after LF at the outer scan loop.
    CP   10                 ; LF-only and CRLF sources share this terminator.
    JR   NZ,CP_BIN_SKIP_LINE  ; Keep scanning until either byte is consumed.
    JP   CP_BIN_SCAN_LINE   ; Resume after LF without changing source offsets.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Recreate the entry-header define table after dependency ordering completes.

CP_BIN_SCAN_LOAD_END:
    LD   HL,(CP_BIN_SCAN_DESC)  ; Point to the current five-byte descriptor.
    LD   DE,3                ; Its exclusive logical end begins at byte three.
    ADD  HL,DE               ; Address the low byte of the end offset.
    LD   E,(HL)              ; Read the low byte of this source's length.
    INC  HL                  ; Advance to the high end byte.
    LD   D,(HL)              ; Complete the sixteen-bit source length.
    EX   DE,HL               ; Return the end offset in HL.
    LD   (CP_BIN_SCAN_END),HL ; Cache the exclusive scan boundary.
    RET                      ; The source itself begins at logical offset zero.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Read one condition-filtered source byte and advance the preflight cursor.

CP_BIN_READ_BYTE:
    LD   A,(CP_BIN_SCAN_PART)  ; Select the resolved source-part ordinal.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Read the next logical byte position.
    CALL CP_SOURCE_READ_BYTE  ; Apply the ordinary CP/M source and IF filters.
    RET  C                   ; Preserve premature EOF/read failure for caller.
    LD   (CP_BIN_BYTE_TEMP),A ; Keep the source byte during cursor update.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Reload the current zero-based offset.
    INC  HL                  ; Advance to the byte after the one just read.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; Publish the next position to every helper.
    LD   A,(CP_BIN_BYTE_TEMP) ; Restore the filtered source byte.
    OR   A                   ; Clear carry and preserve the byte in A.
    RET                      ; The scan cursor now names the following byte.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Collect one token into CP_PP_TOKEN, folding lowercase ASCII to uppercase.

CP_BIN_SCAN_TOKEN:
    LD   (CP_BIN_BYTE_TEMP),A ; Preserve the first byte before clearing length.
    XOR  A                   ; Start this candidate with an empty token.
    LD   (CP_PP_TOKEN_LENGTH),A  ; CP_PP_MATCH_WORD reads this exact length.
    LD   A,(CP_BIN_BYTE_TEMP) ; Restore the first character for the token loop.
CP_BIN_SCAN_TOKEN_LOOP:
    LD   (CP_BIN_BYTE_TEMP),A ; Preserve the current byte across tests.
    CP   ' '                 ; Space completes the token without being stored.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Return the delimiter to the caller.
    CP   9                   ; A tab also delimits a source token.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Preserve it as the token terminator.
    CP   ':'                 ; Colon separates a label from its operation.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Do not merge the label and colon.
    CP   ';'                 ; A comment begins after the token boundary.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Leave comment handling to the caller.
    CP   13                  ; Carriage return terminates the physical line.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Keep line endings outside the token.
    CP   10                  ; Line feed is the second accepted terminator.
    JR   Z,CP_BIN_SCAN_TOKEN_END  ; Return it without adding it to the token.
    LD   A,(CP_PP_TOKEN_LENGTH)  ; Read the current token byte count.
    CP   17                  ; The shared token buffer has seventeen positions.
    JR   NC,CP_BIN_SCAN_TOKEN_LONG  ; Ignore overlong ordinary labels safely.
    LD   C,A                 ; Use the token length as a buffer index.
    LD   A,(CP_BIN_BYTE_TEMP) ; Restore the source character.
    CP   'a'                 ; Check whether lowercase folding applies.
    JR   C,CP_BIN_TOKEN_CASED  ; Leave uppercase and punctuation unchanged.
    CP   'z'+1               ; Compare with the exclusive lowercase bound.
    JR   NC,CP_BIN_TOKEN_CASED  ; Leave bytes outside ASCII lowercase unchanged.
    AND  $DF                 ; Fold the supported keyword to uppercase.
CP_BIN_TOKEN_CASED:
    LD   (CP_BIN_BYTE_TEMP),A ; Save the normalized character while indexing.
    LD   B,0                 ; The token length is smaller than eighteen.
    LD   A,C                 ; Place the current position in BC.
    LD   C,A                 ; Complete its one-byte index.
    LD   HL,CP_PP_TOKEN      ; Select the bounded token buffer.
    ADD  HL,BC               ; Address its next free byte.
    LD   A,(CP_BIN_BYTE_TEMP) ; Restore the normalized character.
    LD   (HL),A              ; Append it to the token.
    LD   HL,CP_PP_TOKEN_LENGTH  ; Address the token's published length.
    INC  (HL)                ; Include the byte just stored above.
    CALL CP_BIN_READ_BYTE    ; Read the following token byte or delimiter.
    JR   NC,CP_BIN_SCAN_TOKEN_LOOP  ; Continue until a delimiter is consumed.
    XOR  A                   ; EOF completes the current nonempty token.
    SCF                      ; Mark the delimiter as end of this source part.
    RET                      ; The caller still compares the collected token.
CP_BIN_SCAN_TOKEN_END:
    LD   A,(CP_BIN_BYTE_TEMP) ; Return the consumed delimiter to the caller.
    OR   A                   ; Clear carry and classify the delimiter byte.
    RET                      ; CP_PP_TOKEN contains only source token bytes.
CP_BIN_SCAN_TOKEN_LONG:
    LD   A,1                 ; Distinguish an overlong token from clean EOF.
    SCF                      ; Tell the caller to ignore this unsupported name.
    RET                      ; No partial token can equal the six-byte keyword.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted 8.3 binary name and a required numeric byte count.

CP_BIN_PARSE_INCLUDE:
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Resume after the consumed INCBIN delimiter.
CP_BIN_PARSE_PATH_SPACE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next raw byte of this active source line.
    JP   C,CP_BIN_INVALID    ; A path must begin before source end.
    CP   ' '                 ; Ignore spaces between INCBIN and its path.
    JR   Z,CP_BIN_PARSE_PATH_SPACE  ; Keep scanning horizontal whitespace.
    CP   9                   ; Tabs are also valid between directive operands.
    JR   Z,CP_BIN_PARSE_PATH_SPACE  ; Continue until the opening quote.
    CP   13                  ; Never let a missing path continue onto another line.
    JP   Z,CP_BIN_INVALID    ; The opening quote must follow on this physical line.
    CP   10                  ; LF-only sources have the same operand boundary.
    JP   Z,CP_BIN_INVALID    ; Keep the binary directive on its source line.
    CP   ';'                 ; A comment cannot stand in for the filename.
    JP   Z,CP_BIN_INVALID    ; Reject an incomplete directive before assembly.
    CP   '"'                ; CP/M accepts only a quoted current-drive name.
    JP   NZ,CP_BIN_INVALID   ; Reject paths, comments and unquoted names.
    CALL CP_CLEAR_INCLUDE_FCB  ; Prepare the normalized scratch filename FCB.
    CALL CP_PARSE_INCLUDE_NAME  ; Validate and store the complete 8.3 filename.
    JP   C,CP_BIN_INVALID    ; Reject malformed or incomplete quoted names.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; Preserve the cursor after the closing quote.
    LD   HL,CP_WORK_FCB+1   ; Copy the normalized name/type from the parser FCB.
    LD   DE,CP_BIN_NAME     ; Preserve it while work FCB builds temp names.
    LD   BC,11              ; The filename has eight base and three type bytes.
    LDIR                    ; Retain this binary identity in private workspace.
    LD   HL,(CP_BIN_SCAN_OFFSET)  ; Resume at the first byte after the filename.
CP_BIN_PARSE_COMMA_SPACE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the delimiter after the closing quote.
    JP   C,CP_BIN_INVALID   ; A byte count is mandatory on the native profile.
    CP   ' '                 ; Skip optional whitespace before the comma.
    JR   Z,CP_BIN_PARSE_COMMA_SPACE  ; Keep the operand grammar simple.
    CP   9                   ; Permit a tab before the required comma.
    JR   Z,CP_BIN_PARSE_COMMA_SPACE  ; Continue over horizontal whitespace.
    CP   13                  ; Do not search a later physical line for the comma.
    JP   Z,CP_BIN_INVALID    ; A count belongs to the same INCBIN statement.
    CP   10                  ; Reject the equivalent LF-only operand break.
    JP   Z,CP_BIN_INVALID    ; Preserve original newline bytes and semantics.
    CP   ';'                 ; A trailing comment cannot replace the required count.
    JP   Z,CP_BIN_INVALID    ; Keep the count mandatory on the directive line.
    CP   ','                 ; The second operand is the exact byte count.
    JP   NZ,CP_BIN_INVALID   ; Reject a missing count or extra filename text.
    CALL CP_PP_READ_TOKEN   ; Read one bounded numeric literal after the comma.
    JP   C,CP_BIN_INVALID   ; Reject a missing or overlong count token.
    LD   A,(CP_PP_TOKEN)    ; Inspect the first byte before definition lookup.
    CP   '0'                ; Decimal and Intel suffix values start with digits.
    JR   C,CP_BIN_COUNT_PREFIX  ; Check the two supported numeric prefixes.
    CP   '9'+1              ; Accept decimal and 0FFFFH lexical starts.
    JR   C,CP_BIN_COUNT_NUMERIC  ; Parse a digit-leading number.
CP_BIN_COUNT_PREFIX:
    CP   '$'                ; Dollar selects hexadecimal.
    JR   Z,CP_BIN_COUNT_NUMERIC  ; Pass the complete token to the shared parser.
    CP   '%'                ; Percent selects binary outside a line-leading host directive.
    JP   NZ,CP_BIN_INVALID   ; Named counts are excluded from portable INCBIN.
CP_BIN_COUNT_NUMERIC:
    CALL CP_PP_PARSE_VALUE  ; Convert decimal, hex or binary to an unsigned word.
    JP   C,CP_BIN_INVALID   ; Reject invalid digits and values above $FFFF.
    LD   (CP_BIN_COUNT_VALUE),HL  ; Preserve the declared logical payload length.
    LD   HL,(CP_PP_SOURCE_CURSOR)  ; Resume at the count token's trailing delimiter.
    CALL CP_PP_CHECK_TRAILING  ; Allow only whitespace, EOL or a comment.
    JP   C,CP_BIN_INVALID   ; Reject another operand or trailing source token.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; Continue scanning after the full directive line.
    LD   (CP_BIN_LINE_END),HL  ; Start with the returned exclusive source cursor.
    CALL CP_BIN_TRIM_LINE_END  ; Remove CR/LF from the rewriteable content range.
    JP   C,CP_BIN_SOURCE_READ_FAILED  ; A changed source cannot be rewritten safely.
    CALL CP_BIN_VALIDATE_INCLUDE  ; Check span, collision, capacity and existence.
    RET                      ; Preserve the metadata check's status and message.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,ZERO,SIGN,PARITY,HALFCARRY
; Find the end of source text before a consumed CR, LF or CRLF sequence.

CP_BIN_TRIM_LINE_END:
    LD   A,H                 ; Check whether the returned end is source offset zero.
    OR   L                   ; No preceding newline can exist at zero.
    RET  Z                   ; Keep an empty content range unchanged.
    DEC  HL                  ; Address the last consumed source byte.
    PUSH HL                 ; The raw source reader uses HL as its cache cursor.
    CALL CP_RAW_SOURCE_BYTE  ; Inspect it without applying text transformation.
    POP  HL                 ; Restore the source offset for line-end storage.
    RET  C                   ; EOF leaves the initial exclusive end unchanged.
    CP   13                  ; A consumed CR is the first byte outside the line.
    JR   Z,CP_BIN_LINE_END_AT_HL  ; Keep the content end before that CR.
    CP   10                  ; A consumed LF also lies outside line content.
    JR   Z,CP_BIN_LINE_END_LF  ; Trim LF and test for a preceding CR.
    OR   A                   ; A non-newline byte returns clear carry.
    RET                      ; The original exclusive end is already correct.
CP_BIN_LINE_END_LF:
    LD   (CP_BIN_LINE_END),HL ; The content ends immediately before LF.
    LD   A,H                 ; Check whether LF was the first source byte.
    OR   L                   ; No preceding CR is possible at offset zero.
    RET  Z                   ; Preserve the LF-only content boundary.
    DEC  HL                  ; Inspect the byte before LF for a CRLF pair.
    PUSH HL                 ; Preserve its source offset across the cache lookup.
    CALL CP_RAW_SOURCE_BYTE  ; Read only the preceding physical source byte.
    POP  HL                 ; Restore the offset before deciding the boundary.
    RET  C                   ; Keep the LF boundary if source changed meanwhile.
    CP   13                  ; CRLF has one content end before its CR byte.
    JR   Z,CP_BIN_LINE_END_AT_HL  ; CR is outside content as well as LF.
    OR   A                   ; A non-CR predecessor leaves the LF boundary clear.
    RET                      ; Do not leak CP's carry for bytes below carriage return.
CP_BIN_LINE_END_AT_HL:
    LD   (CP_BIN_LINE_END),HL ; Publish the first byte of the line ending.
    RET                      ; Every source offset after the directive stays fixed.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Validate and append one active, bounded binary include record.

CP_BIN_VALIDATE_INCLUDE:
    LD   A,(CP_BIN_COUNT)    ; Read the number of preflighted binary statements.
    CP   CP_BIN_CAPACITY     ; The fixed table must not be overrun.
    JP   NC,CP_BIN_TOO_MANY  ; Reject the thirty-third include before a write.
    LD   HL,(CP_BIN_LINE_END)  ; Load the rewriteable source-content boundary.
    LD   DE,(CP_BIN_TOKEN_OFFSET)  ; Locate the directive keyword start.
    OR   A                  ; Clear carry before calculating the available span.
    SBC  HL,DE              ; Count bytes from INCBIN through line content.
    LD   DE,CP_BIN_REPLACEMENT_BYTES  ; The generated DS statement is ten bytes.
    OR   A                  ; Clear carry before checking the minimum span.
    SBC  HL,DE              ; Does the original line retain the full replacement?
    JP   C,CP_BIN_INVALID   ; Never change source offsets or truncate the line.
    CALL CP_BIN_OPEN_CHECK  ; Protect transaction names and prove the file exists.
    JP   C,CP_BIN_PREPARE_RETURN  ; Keep the failing filename and source anchor.
    CALL CP_BIN_APPEND_ROW  ; Publish a complete, source-ordered table entry.
    XOR  A                  ; Return success after the row count is incremented.
    RET                      ; The scanner continues with the next source line.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Preserve exact input names while rejecting output/temp/backup aliases.

CP_BIN_OPEN_CHECK:
    LD   DE,CP_BIN_FCB+12   ; Address the mutable tail of the private binary FCB.
    XOR  A                  ; Clear record counters, extent and random record.
    LD   B,24               ; The eleven name bytes precede this twenty-four-byte tail.
    CALL CP_CLEAR_WORK_FCB  ; Initialize all binary-FCB control fields.
    XOR  A                  ; Select the logged-in drive for every INCBIN file.
    LD   (CP_BIN_FCB),A     ; CP/M native paths cannot name another drive.
    LD   HL,CP_BIN_NAME     ; Read the normalized eleven-byte 8.3 identity.
    LD   DE,CP_BIN_FCB+1    ; Store it after the drive byte in the private FCB.
    LD   BC,11              ; Copy the complete base and extension fields.
    LDIR                    ; The runtime reader never reuses CP_WORK_FCB.
    LD   HL,CP_BIN_FCB      ; Compare the candidate's drive and 8.3 identity.
    LD   DE,CP_OUTPUT_NAME  ; The final output name must remain protected.
    CALL CP_NAMES_EQUAL     ; Z marks a destructive binary/output collision.
    JR   Z,CP_BIN_NAME_CONFLICT  ; Do not replace an input after it was assembled.
    CALL CP_SET_TEMP_FCB    ; Reconstruct the transaction's temporary filename.
    LD   HL,CP_BIN_FCB      ; Keep the binary identity in its independent FCB.
    LD   DE,CP_WORK_FCB     ; Compare with the temporary output name.
    CALL CP_NAMES_EQUAL     ; Z means ASO or final output could overwrite the input.
    JR   Z,CP_BIN_NAME_CONFLICT  ; Reject a binary alias of the temporary file.
    CALL CP_SET_BACKUP_FCB  ; Reconstruct the reserved backup/spool name.
    LD   HL,CP_BIN_FCB      ; Restore the binary FCB pointer for comparison.
    LD   DE,CP_WORK_FCB     ; The work FCB now carries the backup name.
    CALL CP_NAMES_EQUAL     ; Z means the ASO spool could destroy this input.
    JR   Z,CP_BIN_NAME_CONFLICT  ; Protect BAK when it is the private spool.
    LD   DE,CP_BIN_FCB      ; Open the candidate using its dedicated FCB.
    LD   C,CP_OPEN_FUNCTION  ; Select CP/M file-open function fifteen.
    CALL CP_BDOS            ; Confirm the binary file exists before output begins.
    INC  A                  ; BDOS returns $FF when the file cannot be opened.
    JR   Z,CP_BIN_FILE_MISSING  ; Report the source position and requested file.
    LD   DE,CP_BIN_FCB      ; Close the temporary validation open.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close function sixteen.
    CALL CP_BDOS            ; Release the FCB before assembly starts.
    INC  A                  ; Convert close failure into the zero test.
    JR   Z,CP_BIN_FILE_CLOSE_FAILED  ; Do not accept an uncertain input handle.
    XOR  A                  ; Clear carry and status after successful validation.
    RET                      ; CP_BIN_FCB is ready for a clean runtime reopen.
CP_BIN_NAME_CONFLICT:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Show the source file, line and column.
    LD   HL,CP_BIN_FCB      ; Identify the candidate binary that aliases output.
    CALL CP_PRINT_NAME      ; Print the conflicting current-drive 8.3 name.
    LD   DE,CP_BIN_CONFLICT_TEXT  ; Select the destructive-name diagnostic.
    SCF                     ; Reject this source before ASO begins.
    RET                      ; No transaction file has been created.
CP_BIN_FILE_MISSING:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Point at the active INCBIN statement.
    LD   HL,CP_BIN_FCB      ; Identify the unavailable binary source.
    CALL CP_PRINT_NAME      ; Print its exact CP/M filename.
    LD   DE,CP_BIN_READ_TEXT  ; Select the binary-input diagnostic suffix.
    SCF                     ; Refuse to assemble a missing payload.
    RET                      ; The prior output remains untouched.
CP_BIN_FILE_CLOSE_FAILED:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Keep the source anchor on close failure.
    LD   HL,CP_BIN_FCB      ; Identify the FCB whose close failed.
    CALL CP_PRINT_NAME      ; Print the requested binary filename.
    LD   DE,CP_BIN_READ_TEXT  ; Report the preflight file operation failure.
    SCF                     ; Stop before the assembler can begin a generation.
    RET                      ; No partial operation stream exists.

;@ROUTINE CLOBBERS A,BC,DE,HL,IX,IY,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the normalized source anchor, count, name and DS replacement text.

CP_BIN_APPEND_ROW:
    LD   HL,(CP_BIN_BUILD_PTR)  ; Select the next unused metadata row.
    LD   A,(CP_BIN_SCAN_PART)  ; Store its dependency-ordered source part.
    LD   (HL),A              ; Byte zero keys both filtering and sink dispatch.
    INC  HL                  ; Advance to the exact INCBIN keyword offset.
    LD   DE,(CP_BIN_TOKEN_OFFSET)  ; Load the operation's original source position.
    LD   (HL),E              ; Store the offset low byte.
    INC  HL                  ; Advance to the offset high byte.
    LD   (HL),D              ; Complete the stable statement anchor.
    INC  HL                  ; Advance to the source line's content end.
    LD   DE,(CP_BIN_LINE_END)  ; Load the exclusive end before CR/LF.
    LD   (HL),E              ; Store the line-end low byte.
    INC  HL                  ; Advance to the line-end high byte.
    LD   (HL),D              ; Preserve every original line-ending offset.
    INC  HL                  ; Advance to the requested binary byte count.
    LD   DE,(CP_BIN_COUNT_VALUE)  ; Load the explicit payload length.
    LD   (HL),E              ; Store the count low byte.
    INC  HL                  ; Advance to the count high byte.
    LD   (HL),D              ; Complete the sixteen-bit logical length.
    INC  HL                  ; Advance to the eleven-byte normalized name.
    EX   DE,HL               ; Keep the row cursor in DE while copying.
    LD   HL,CP_BIN_NAME      ; Read the candidate's base and type fields.
    LD   BC,11               ; The row stores exactly the CP/M 8.3 name bytes.
    LDIR                    ; Preserve it independently of all FCB work.
    EX   DE,HL               ; Resume at row offset eighteen, the replacement text.
    LD   A,'D'               ; Begin the fixed-width DS lowering.
    LD   (HL),A              ; Replacement byte zero is uppercase D.
    INC  HL                  ; Advance within the ten-byte directive form.
    LD   A,'S'               ; Select the second mnemonic character.
    LD   (HL),A              ; Store S after D.
    INC  HL                  ; Advance to the operand separator.
    LD   A,' '               ; Keep the assembler's ordinary token boundary.
    LD   (HL),A              ; Store the space after DS.
    INC  HL                  ; Advance to the hexadecimal prefix.
    LD   A,'$'               ; Use a fixed-width hexadecimal byte count.
    LD   (HL),A              ; Store the prefix before four digits.
    INC  HL                  ; Advance to the most-significant count nibble.
    LD   DE,(CP_BIN_COUNT_VALUE)  ; Load both count bytes for nibble extraction.
    LD   A,D                 ; Select the high byte's upper nibble.
    RRCA                    ; Move bit four into the low nibble.
    RRCA                    ; Move bit five into the low nibble.
    RRCA                    ; Move bit six into the low nibble.
    RRCA                    ; Move bit seven into the low nibble.
    AND  $0F                 ; Keep only the most-significant hexadecimal digit.
    CALL CP_BIN_HEX_CHAR     ; Convert nibble 0..15 to uppercase ASCII.
    LD   (HL),A              ; Store count digit three.
    INC  HL                  ; Advance to the next count nibble.
    LD   A,D                 ; Reload the count's high byte.
    AND  $0F                 ; Keep its lower nibble.
    CALL CP_BIN_HEX_CHAR     ; Convert it to the second hexadecimal digit.
    LD   (HL),A              ; Store count digit two.
    INC  HL                  ; Advance to the high nibble of the low byte.
    LD   A,E                 ; Select the count's low byte.
    RRCA                    ; Move bit four into the low nibble.
    RRCA                    ; Move bit five into the low nibble.
    RRCA                    ; Move bit six into the low nibble.
    RRCA                    ; Move bit seven into the low nibble.
    AND  $0F                 ; Keep the third hexadecimal digit.
    CALL CP_BIN_HEX_CHAR     ; Convert it to uppercase ASCII.
    LD   (HL),A              ; Store count digit one.
    INC  HL                  ; Advance to the least-significant nibble.
    LD   A,E                 ; Reload the low count byte.
    AND  $0F                 ; Keep its lower nibble.
    CALL CP_BIN_HEX_CHAR     ; Convert it to the final hexadecimal digit.
    LD   (HL),A              ; Store count digit zero.
    INC  HL                  ; Advance to the data-fill separator.
    LD   A,','               ; DS uses an explicit fill byte for IMAGE output.
    LD   (HL),A              ; Separate count from the zero fill value.
    INC  HL                  ; Advance to the final fill digit.
    LD   A,'0'               ; The sink replaces each fill byte with payload.
    LD   (HL),A              ; Store the tenth replacement character.
    INC  HL                  ; Point at the following 28-byte row boundary.
    LD   (CP_BIN_BUILD_PTR),HL  ; Save the append cursor only after completion.
    LD   HL,CP_BIN_COUNT    ; Publish the fully initialized metadata record.
    INC  (HL)                ; Include this row in the bounded table.
    RET                      ; Return with carry clear.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert one four-bit count nibble to an uppercase hexadecimal character.

CP_BIN_HEX_CHAR:
    CP   10                  ; Values zero through nine use decimal glyphs.
    JR   C,CP_BIN_HEX_DIGIT  ; Keep their ASCII representation direct.
    ADD  A,'A'-10            ; Convert ten through fifteen to A through F.
    RET                      ; Return the complete uppercase hex digit.
CP_BIN_HEX_DIGIT:
    ADD  A,'0'               ; Convert the nibble to its ASCII digit.
    RET                      ; Return the completed replacement character.

CP_BIN_PREPARE_RETURN:
    RET                      ; Preserve the detailed error selected above.
CP_BIN_INVALID:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Identify the malformed INCBIN line.
    LD   DE,CP_INVALID_INCBIN_TEXT  ; Select the source-syntax diagnostic.
    SCF                     ; Stop before output generation begins.
    RET                      ; Return the user-facing detail in DE.
CP_BIN_TOO_MANY:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Point to the first excess include.
    LD   DE,CP_BIN_LIMIT_TEXT  ; Report the published native-profile limit.
    SCF                     ; Do not write beyond the fixed table.
    RET                      ; Return the capacity detail in DE.
CP_BIN_SOURCE_READ_FAILED:
    CALL CP_BIN_PRINT_FAILURE_LOCATION  ; Identify the part whose bytes changed.
    LD   DE,CP_READ_FAILED_TEXT  ; Reuse the established CP/M source read text.
    SCF                     ; A measured source must not end during collection.
    RET                      ; The descriptor and physical file no longer agree.
CP_BIN_PRINT_FAILURE_LOCATION:
    LD   A,(CP_BIN_SCAN_PART)  ; Publish the dependency-order source ordinal.
    LD   (ST_EPART),A       ; Reuse the public source-diagnostic contract.
    LD   HL,(CP_BIN_TOKEN_OFFSET)  ; Point at the exact INCBIN operation name.
    LD   (ST_EOFF),HL       ; Keep byte offset stable while location is rendered.
    CALL CP_PRINT_ERROR_LOCATION  ; Print source filename and line:column.
    LD   A,' '               ; Separate the location from its diagnostic detail.
    JP   CP_PUTC             ; Return after the field separator.

CP_BIN_SCAN_PART_DONE:
    LD   HL,CP_BIN_SCAN_PART  ; Advance to the next dependency-ordered source.
    INC  (HL)                ; Descriptor ordinals are consecutive bytes.
    LD   A,(HL)              ; Read the next part or the final descriptor count.
    LD   HL,CP_DESCRIPTOR    ; Address the published number of resolved parts.
    CP   (HL)                ; Equality means every source part was scanned.
    JR   Z,CP_BIN_PREPARED   ; Enable the complete metadata table.
    LD   HL,(CP_BIN_SCAN_DESC)  ; Select the descriptor just completed.
    LD   DE,5                ; Every Atom source descriptor occupies five bytes.
    ADD  HL,DE               ; Point to the next dependency-order descriptor.
    LD   (CP_BIN_SCAN_DESC),HL  ; Retain its address for the next part.
    CALL CP_BIN_SCAN_LOAD_END  ; Load the following part's exclusive end.
    LD   HL,0                ; Each source part uses an independent zero origin.
    LD   (CP_BIN_SCAN_OFFSET),HL  ; Restart scanning at its first byte.
    JP   CP_BIN_SCAN_LINE    ; Continue with the next resolved source.
CP_BIN_PREPARED:
    XOR  A                   ; Runtime filtering begins with table row zero.
    LD   (CP_BIN_FILTER_INDEX),A  ; Initialize the binary-lowering cursor.
    LD   (CP_BIN_SINK_INDEX),A  ; The output sink consumes rows in source order.
    LD   HL,CP_BIN_TABLE     ; Point both consumers to the first fixed row.
    LD   (CP_BIN_FILTER_PTR),HL  ; Runtime source transformation starts here.
    LD   (CP_BIN_SINK_PTR),HL  ; IMAGE dispatch starts at the same source anchor.
    LD   A,$FF               ; Force filtering to resynchronize at the first byte.
    LD   (CP_BIN_FILTER_LAST_PART),A  ; No source part has been filtered yet.
    LD   HL,$FFFF            ; No valid source offset equals this sentinel.
    LD   (CP_BIN_FILTER_LAST_OFFSET),HL  ; Peeks can detect backward source reads.
    XOR  A                   ; No binary file is open and no sink is active.
    LD   (CP_BIN_SINK_ACTIVE),A  ; Clear the current binary statement state.
    LD   (CP_BIN_OPEN),A     ; The dedicated binary FCB is closed.
    LD   (CP_BIN_RECORD_LEFT),A  ; No binary record bytes are buffered.
    LD   HL,0                ; No payload byte is expected before Atom begins.
    LD   (CP_BIN_SINK_REMAIN),HL  ; Clear the active statement's remaining count.
    LD   A,$FF               ; Force Atom's first source read to reopen part zero.
    LD   (CP_ACTIVE_PART),A  ; Preflight left the final source file open at EOF.
    XOR  A                   ; Keep this operation's status clear for the caller.
    INC  A                   ; Only now expose all completely validated rows.
    LD   (CP_BIN_ENABLED),A  ; Runtime rewriting starts at the assembly boundary.
    RET                      ; Return success with metadata ready for Atom.

;@ROUTINE IN A,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Replace only the active INCBIN line's content; preserve its source offsets.

CP_BIN_RUNTIME_FILTER:
    LD   A,(CP_BIN_ENABLED)  ; Preflight must publish a complete metadata table.
    OR   A                   ; Zero means ordinary source has no rewrite rows.
    JR   NZ,.READY           ; Continue with the table cursor when enabled.
    LD   A,(CP_PP_NUM_DIGIT) ; Restore the source provider's original byte.
    OR   A                   ; This path never reports a binary I/O error.
    RET                      ; Return ordinary source unchanged.
.READY:
    LD   A,(CP_ACTIVE_PART)  ; Read the currently selected dependency ordinal.
    LD   E,A                 ; Keep it while comparing the previous filter call.
    LD   A,(CP_BIN_FILTER_LAST_PART)  ; A part change restarts the row cursor.
    CP   E                   ; Does the cached cursor belong to this part?
    JR   NZ,.RESET           ; Reset before searching another source file.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Load this byte's logical source position.
    LD   DE,(CP_BIN_FILTER_LAST_OFFSET)  ; Compare with the previous position.
    OR   A                   ; Clear borrow before the unsigned subtraction.
    SBC  HL,DE               ; Did Atom request an earlier byte again?
    JR   C,.RESET            ; Rewind the metadata cursor for a backward peek.
    JR   NC,.SAVE_POSITION   ; Keep the cursor for repeated or forward source reads.
.RESET:
    XOR  A                   ; Restart at metadata row zero.
    LD   (CP_BIN_FILTER_INDEX),A  ; Clear the byte-sized row ordinal.
    LD   HL,CP_BIN_TABLE     ; Select the first fixed-width entry.
    LD   (CP_BIN_FILTER_PTR),HL  ; Publish the reset row pointer.
.SAVE_POSITION:
    LD   A,(CP_ACTIVE_PART)  ; Retain the part used for this lookup.
    LD   (CP_BIN_FILTER_LAST_PART),A  ; The next call can detect part changes.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Reload the requested source offset.
    LD   (CP_BIN_FILTER_LAST_OFFSET),HL  ; Peeks can detect a later rewind.
.ROW:
    LD   A,(CP_BIN_FILTER_INDEX)  ; Read the next possible include row.
    LD   B,A                 ; Keep the row ordinal for the bound check.
    LD   A,(CP_BIN_COUNT)    ; Read the number of complete metadata entries.
    CP   B                   ; Equality means every include line was passed.
    JR   Z,.ORIGINAL          ; No remaining row can change this source byte.
    LD   HL,(CP_BIN_FILTER_PTR)  ; Address the current metadata row.
    LD   A,(HL)              ; Read its dependency-ordered part ordinal.
    LD   E,A                 ; Keep the row's part for the unsigned compare.
    LD   A,(CP_ACTIVE_PART)  ; Read the current source part.
    CP   E                   ; Is this byte before or after the row's part?
    JR   C,.ORIGINAL         ; A later row leaves this earlier byte untouched.
    JR   NZ,.ADVANCE         ; A previous part cannot match this source byte.
    INC  HL                  ; Advance to the include keyword's offset low byte.
    LD   E,(HL)              ; Read the operation anchor's low byte.
    INC  HL                  ; Advance to its high byte.
    LD   D,(HL)              ; Complete the operation anchor word.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Load the current byte's source offset.
    OR   A                   ; Clear borrow before comparing source positions.
    SBC  HL,DE               ; Is the current byte before the keyword?
    JR   C,.ORIGINAL         ; Keep labels and indentation before INCBIN.
    LD   HL,(CP_BIN_FILTER_PTR)  ; Address the row's exclusive content end.
    LD   DE,3                ; Its line-end word begins at byte three.
    ADD  HL,DE               ; Point at the line-end low byte.
    LD   E,(HL)              ; Read the exclusive content end's low byte.
    INC  HL                  ; Advance to the high byte.
    LD   D,(HL)              ; Complete the line-end boundary.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Reload the byte being transformed.
    OR   A                   ; Clear borrow before the boundary comparison.
    SBC  HL,DE               ; Has the source reached CR, LF or end of file?
    JP   NC,.ADVANCE         ; Preserve endings and move beyond this metadata.
    LD   HL,(CP_BIN_FILTER_PTR)  ; Address the row's operation anchor.
    INC  HL                  ; Point to the start-offset low byte.
    LD   E,(HL)              ; Read its low byte.
    INC  HL                  ; Advance to the high byte.
    LD   D,(HL)              ; Complete the start-offset word.
    LD   HL,(CP_PP_CURRENT_OFFSET)  ; Compute displacement from the keyword.
    OR   A                   ; Clear borrow before computing the replacement index.
    SBC  HL,DE               ; HL now contains the source-byte displacement.
    LD   A,H                 ; Replacement text is only ten bytes long.
    OR   A                   ; A nonzero high byte is already beyond that span.
    JR   NZ,.SPACE           ; Mask any remaining directive text with spaces.
    LD   A,L                 ; Read the small replacement-text displacement.
    CP   CP_BIN_REPLACEMENT_BYTES  ; Check whether it names one of ten bytes.
    JR   NC,.SPACE           ; The rest of the old line becomes whitespace.
    LD   C,A                 ; Preserve the replacement index across addition.
    LD   HL,(CP_BIN_FILTER_PTR)  ; Address this row's fixed DS replacement.
    LD   DE,CP_BIN_REPLACEMENT  ; Its first replacement byte is at offset eighteen.
    ADD  HL,DE               ; Point at the generated source text.
    LD   E,C                 ; Zero-extend the displacement in DE.
    LD   D,0                 ; Complete the offset pair.
    ADD  HL,DE               ; Select the character corresponding to this byte.
    LD   A,(HL)              ; Read one byte of the fixed-width DS statement.
    OR   A                   ; Return it with carry clear.
    RET                      ; Keep every original byte offset unchanged.
.SPACE:
    LD   A,' '               ; Do not leave any original filename characters.
    OR   A                   ; Return harmless assembler whitespace.
    RET                      ; The line ending remains outside the rewrite span.
.ADVANCE:
    LD   HL,(CP_BIN_FILTER_PTR)  ; Select the row just passed by the source cursor.
    LD   DE,CP_BIN_ENTRY_BYTES  ; Every fixed row has the same twenty-eight-byte size.
    ADD  HL,DE               ; Move to the following include record.
    LD   (CP_BIN_FILTER_PTR),HL  ; Save its address for the next byte request.
    LD   HL,CP_BIN_FILTER_INDEX  ; Address the byte-sized row ordinal.
    INC  (HL)                ; Advance only after this row is fully passed.
    JR   .ROW                ; Compare the following metadata entry.
.ORIGINAL:
    LD   A,(CP_PP_NUM_DIGIT) ; Return the byte originally supplied by CP/M.
    OR   A                   ; Clear carry for the ordinary active-source path.
    RET                      ; No later include row matches this position.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Substitute sequential binary bytes for the zero-fill IMAGE operations.

CP_BIN_SINK_BYTE:
    LD   A,(CP_BIN_SINK_ACTIVE)  ; Is one INCBIN statement currently emitting?
    OR   A                   ; Zero means compare the next source-ordered row.
    JR   Z,.SEEK              ; Start or skip a row when no statement is active.
    CALL CP_BIN_SINK_COMPARE ; Compare this IMAGE anchor with the active row.
    JR   Z,.READ              ; A matching anchor consumes the next payload byte.
    LD   HL,(CP_BIN_SINK_REMAIN)  ; Load any payload bytes not emitted yet.
    LD   A,H                 ; Test the remaining count's high byte.
    OR   L                   ; A nonzero count means Atom emitted too few bytes.
    JP   NZ,CP_BIN_SINK_FAIL ; Reject a short DS before another source statement.
    CALL CP_BIN_SINK_ADVANCE ; The complete row may now leave the ordered cursor.
.SEEK:
    LD   A,(CP_BIN_SINK_INDEX)  ; Read the next candidate row ordinal.
    LD   B,A                 ; Retain it while comparing with the complete count.
    LD   A,(CP_BIN_COUNT)    ; Read the number of active include statements.
    CP   B                   ; Equality means this IMAGE byte is ordinary output.
    JR   Z,.ORIGINAL          ; No metadata remains to substitute.
    LD   HL,(CP_BIN_SINK_PTR)  ; Address the candidate row's count field.
    LD   DE,5                ; The count word begins at metadata offset five.
    ADD  HL,DE               ; Select its low byte.
    LD   E,(HL)              ; Load the count low byte.
    INC  HL                  ; Advance to its high byte.
    LD   D,(HL)              ; Complete the declared byte count.
    LD   A,D                 ; Check for the zero-byte form.
    OR   E                   ; A zero count emits no IMAGE operations.
    JR   NZ,.COMPARE          ; Nonzero rows must match one sink anchor.
    CALL CP_BIN_SINK_ADVANCE ; Consume a zero-length metadata row without I/O.
    JR   .SEEK                ; Continue with the following row.
.COMPARE:
    CALL CP_BIN_SINK_COMPARE ; Compare source part and operation byte offset.
    JR   C,.ORIGINAL          ; An earlier IMAGE operation precedes this row.
    JR   Z,.START              ; A matching operation begins its binary payload.
    JP   CP_BIN_SINK_FAIL     ; Passing an unconsumed row means IMAGE was absent.
.START:
    LD   HL,(CP_BIN_SINK_PTR)  ; Address the declared count in this metadata row.
    LD   DE,5                ; Skip its part and two source-position words.
    ADD  HL,DE               ; Read the count low byte.
    LD   E,(HL)              ; Preserve the low byte in DE.
    INC  HL                  ; Advance to the high byte.
    LD   D,(HL)              ; Complete the full sixteen-bit payload count.
    EX   DE,HL               ; Move the count to HL for its workspace store.
    LD   (CP_BIN_SINK_REMAIN),HL  ; Track precisely the IMAGE bytes still expected.
    LD   A,1                 ; Mark the row active before opening its file.
    LD   (CP_BIN_SINK_ACTIVE),A  ; Any open failure still retains its source row.
    CALL CP_BIN_RUNTIME_OPEN ; Open the dedicated FCB at sequential record zero.
    JP   C,CP_BIN_SINK_FAIL  ; No output can commit after a failed binary open.
.READ:
    LD   HL,(CP_BIN_SINK_REMAIN)  ; Guard against an extra IMAGE from Atom.
    LD   A,H                 ; Inspect both count bytes before reading.
    OR   L                   ; A completed statement cannot emit another byte.
    JP   Z,CP_BIN_SINK_FAIL  ; Reject excess output at the exact source anchor.
    CALL CP_BIN_RUNTIME_READ ; Read from the buffered 128-byte binary record.
    JP   C,CP_BIN_SINK_FAIL  ; EOF or BDOS error aborts the tentative output.
    LD   (CP_BIN_SINK_VALUE),A  ; Keep the payload for HS_IB's spool call.
    LD   HL,(CP_BIN_SINK_REMAIN)  ; Load the declared bytes left after this one.
    DEC  HL                  ; Account for the just-read payload byte.
    LD   (CP_BIN_SINK_REMAIN),HL  ; Retain the remaining logical file length.
    LD   A,H                 ; Check whether the complete payload has arrived.
    OR   L                   ; Zero requires closing the FCB before returning.
    JR   NZ,.BYTE_READY       ; Keep the sequential file open for another record.
    CALL CP_BIN_RUNTIME_CLOSE ; Finish the binary input immediately at its count.
    JP   C,CP_BIN_SINK_FAIL  ; A close error prevents successful publication.
.BYTE_READY:
    XOR  A                   ; Report success; HS_IB reloads the byte from RAM.
    RET                      ; The caller restores its address and class.
.ORIGINAL:
    LD   A,(CP_BIN_SINK_VALUE)  ; Keep the ordinary zero-fill byte unchanged.
    OR   A                   ; Clear carry for the normal ASO image operation.
    RET                      ; Continue without reading any binary file.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Compare the current IMAGE source anchor with the pending metadata row.

CP_BIN_SINK_COMPARE:
    LD   HL,(CP_BIN_SINK_PTR)  ; Point at the row's source-part ordinal.
    LD   A,(HL)              ; Read the dependency-order part identity.
    LD   E,A                 ; Keep it beside the incoming IMAGE anchor.
    LD   A,(CP_BIN_SINK_PART)  ; Read the current Atom statement's part.
    CP   E                   ; Carry means current part precedes the row.
    RET  NZ                  ; Return the part ordering in the flags.
    INC  HL                  ; Advance to the metadata offset's low byte.
    LD   E,(HL)              ; Read the keyword offset's low byte.
    INC  HL                  ; Advance to the keyword offset's high byte.
    LD   D,(HL)              ; Complete the row's exact statement anchor.
    LD   HL,(CP_BIN_SINK_OFFSET)  ; Load the current Atom source position.
    OR   A                   ; Clear carry before comparing the two offsets.
    SBC  HL,DE               ; Carry means the current IMAGE is earlier.
    RET                      ; Preserve the three-way anchor comparison.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Advance both sink cursors over one completed or zero-count metadata row.

CP_BIN_SINK_ADVANCE:
    LD   HL,CP_BIN_SINK_ACTIVE  ; Address the current-operation flag.
    XOR  A                   ; No row remains active after cursor advancement.
    LD   (HL),A              ; Clear it before publishing the following pointer.
    LD   HL,(CP_BIN_SINK_PTR)  ; Select the row that was just consumed.
    LD   DE,CP_BIN_ENTRY_BYTES  ; Fixed-width rows keep the table scan bounded.
    ADD  HL,DE               ; Point at its successor.
    LD   (CP_BIN_SINK_PTR),HL  ; Publish the source-order next-row pointer.
    LD   HL,CP_BIN_SINK_INDEX  ; Address the row's byte-sized ordinal.
    INC  (HL)                ; Advance it exactly once with the pointer.
    RET                      ; Return ready to compare another IMAGE operation.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Require every nonempty INCBIN row to have produced its exact byte count.

CP_BIN_SINK_FINISH:
    LD   A,(CP_BIN_SINK_ACTIVE)  ; Check the final operation's count state.
    OR   A                   ; Zero means no payload row is active.
    JR   Z,.ROWS              ; Inspect all metadata that remains unconsumed.
    LD   HL,(CP_BIN_SINK_REMAIN)  ; Read any bytes Atom failed to request.
    LD   A,H                 ; Check the high count byte.
    OR   L                   ; A remaining payload is a short IMAGE sequence.
    JP   NZ,CP_BIN_SINK_FAIL ; Keep the diagnostic anchored to that directive.
    CALL CP_BIN_SINK_ADVANCE ; The final completed row can now be retired.
.ROWS:
    LD   A,(CP_BIN_SINK_INDEX)  ; Read the next pending metadata ordinal.
    LD   B,A                 ; Retain it while comparing against the row count.
    LD   A,(CP_BIN_COUNT)    ; Load the total number of active directives.
    CP   B                   ; Equality means no required row remains.
    JR   Z,.CLOSED            ; Confirm that no FCB escaped the final operation.
    LD   HL,(CP_BIN_SINK_PTR)  ; Address this pending row's count field.
    LD   DE,5                ; The explicit count begins at row offset five.
    ADD  HL,DE               ; Select its low byte.
    LD   A,(HL)              ; Read the low count byte.
    INC  HL                  ; Advance to its high byte.
    OR   (HL)                ; Any nonzero count means the row was never emitted.
    JP   NZ,CP_BIN_SINK_FAIL ; Refuse to commit an unconsumed binary statement.
    CALL CP_BIN_SINK_ADVANCE ; Retire a zero-count statement without opening it.
    JR   .ROWS                ; Check the rest of the fixed metadata table.
.CLOSED:
    LD   A,(CP_BIN_OPEN)    ; The normal final byte closes every binary input.
    OR   A                   ; A lingering open FCB is an internal mismatch.
    JP   NZ,CP_BIN_SINK_FAIL ; Abort instead of publishing with an open file.
    XOR  A                   ; Return success after every row has been checked.
    RET                      ; The ASO commit can now seal and publish output.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Open the metadata row's binary file with a clean sequential FCB.

CP_BIN_RUNTIME_OPEN:
    LD   DE,CP_BIN_FCB+12   ; Address its sequential-record control fields.
    XOR  A                   ; Clear extent, record and random record numbers.
    LD   B,24                ; The FCB has a twenty-four-byte mutable tail.
    CALL CP_CLEAR_WORK_FCB  ; Reset this runtime open to the first record.
    XOR  A                   ; Select CP/M's current logged-in drive.
    LD   (CP_BIN_FCB),A     ; Native INCBIN paths contain no drive prefix.
    LD   HL,(CP_BIN_SINK_PTR)  ; Address the metadata row's eleven-byte name.
    LD   DE,CP_BIN_FILENAME  ; The filename begins after the two source offsets.
    ADD  HL,DE               ; Skip the row header and explicit count.
    LD   DE,CP_BIN_FCB+1    ; Point past the drive byte in the FCB.
    LD   BC,11               ; Copy the complete normalized 8.3 identity.
    LDIR                    ; Keep the binary FCB independent of CP_INPUT_FCB.
    LD   DE,CP_BIN_FCB      ; Pass the clean filename to CP/M's open service.
    LD   C,CP_OPEN_FUNCTION  ; Select function fifteen for sequential reading.
    CALL CP_BDOS            ; Open the payload from its first record.
    INC  A                   ; Convert BDOS's $FF error into the zero test.
    JR   Z,.FAILED           ; Propagate an open failure through the sink.
    LD   A,1                 ; Record that abort cleanup now owns the FCB.
    LD   (CP_BIN_OPEN),A    ; Close it on any later assembly or sink failure.
    XOR  A                   ; Start with no buffered record bytes.
    LD   (CP_BIN_RECORD_LEFT),A  ; A new file always begins with a BDOS read.
    LD   HL,CP_SOURCE_CACHE  ; Use the existing 128-byte transfer area as DMA.
    LD   (CP_BIN_RECORD_PTR),HL  ; Payload records are consumed sequentially.
    XOR  A                   ; Return a successful open with carry clear.
    RET                      ; The first actual record is fetched on demand.
.FAILED:
    SCF                     ; No file handle was acquired on the failed open.
    RET                      ; HS_ABORT therefore has nothing to close.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close one complete binary payload and release its record buffer.

CP_BIN_RUNTIME_CLOSE:
    LD   DE,CP_BIN_FCB      ; Pass the dedicated payload FCB to CP/M.
    LD   C,CP_CLOSE_FUNCTION  ; Select sequential file close, function sixteen.
    CALL CP_BDOS            ; Flush CP/M's directory state for this input.
    INC  A                   ; A zero result becomes one; $FF becomes zero.
    JR   Z,.FAILED           ; Leave ownership set if CP/M rejects the close.
    XOR  A                   ; Clear both open and buffered-record state.
    LD   (CP_BIN_OPEN),A    ; HS_ABORT no longer owns a successfully closed FCB.
    LD   (CP_BIN_RECORD_LEFT),A  ; Do not reuse the tail of its final record.
    RET                      ; Return with carry clear after a clean close.
.FAILED:
    SCF                     ; The source statement cannot commit after CLOSE fails.
    RET                      ; Leave CP_BIN_OPEN set for abort cleanup to retry.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Return one payload byte, refilling the shared DMA page per CP/M record.

CP_BIN_RUNTIME_READ:
    LD   A,(CP_BIN_RECORD_LEFT)  ; Reuse the current physical record if possible.
    OR   A                   ; Zero requests one sequential 128-byte read.
    JR   NZ,.BYTE            ; The buffered record still contains payload.
    LD   DE,CP_SOURCE_CACHE  ; Direct CP/M's next binary record to the cache page.
    LD   C,CP_DMA_FUNCTION  ; Select CP/M set-DMA function twenty-six.
    CALL CP_BDOS            ; Install the DMA address before the disk read.
    LD   HL,$FFFF            ; No valid source record uses this cache key.
    LD   (CP_SOURCE_CACHE_KEY),HL  ; Invalidate before BDOS overwrites the page.
    LD   DE,CP_BIN_FCB      ; Pass the next sequential binary record's FCB.
    LD   C,CP_READ_FUNCTION  ; Select sequential record read, function twenty.
    CALL CP_BDOS            ; Read one physical record into CP_SOURCE_CACHE.
    OR   A                   ; Zero means success; EOF or error is nonzero.
    JR   NZ,.FAILED           ; Never treat a short binary file as text padding.
    LD   A,128               ; One complete CP/M record is now available.
    LD   (CP_BIN_RECORD_LEFT),A  ; Count down as payload bytes are returned.
    LD   HL,CP_SOURCE_CACHE  ; Restart at the first byte of this record.
    LD   (CP_BIN_RECORD_PTR),HL  ; Retain the current DMA-page cursor.
.BYTE:
    LD   HL,(CP_BIN_RECORD_PTR)  ; Address the next unconsumed payload byte.
    LD   A,(HL)              ; Binary $1A, CR and LF are ordinary data here.
    INC  HL                  ; Advance the in-memory record cursor.
    LD   (CP_BIN_RECORD_PTR),HL  ; Keep the following byte for the next IMAGE.
    LD   HL,CP_BIN_RECORD_LEFT  ; Address the bytes left in this physical record.
    DEC  (HL)                ; Consume exactly one of its 128 transferred bytes.
    OR   A                   ; The payload value itself does not set carry.
    RET                      ; Return one byte with the record state updated.
.FAILED:
    SCF                     ; BDOS EOF/error cannot satisfy the declared count.
    RET                      ; HS_IB aborts the uncommitted output transaction.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Save the INCBIN source anchor and fail the output sink without losing origin.

CP_BIN_SINK_FAIL:
    LD   A,1                 ; Tell CP_ENTRY to print a binary-source diagnostic.
    LD   (CP_BIN_ERROR),A   ; DR_SOUT otherwise identifies only the output file.
    LD   HL,(CP_BIN_SINK_PTR)  ; Read the failed metadata row's part ordinal.
    LD   A,(HL)              ; Select the dependency-order part number.
    LD   (ST_EPART),A       ; Preserve the public source-diagnostic location.
    INC  HL                  ; Advance to the operation offset's low byte.
    LD   A,(HL)              ; Read that low byte.
    LD   E,A                 ; Preserve it across the high-byte read.
    INC  HL                  ; Advance to the operation offset's high byte.
    LD   D,(HL)              ; Complete the metadata source offset.
    EX   DE,HL               ; Move the source offset into HL.
    LD   (ST_EOFF),HL       ; Keep the exact directive token as the failure site.
    LD   A,1                 ; Return a nonzero host-sink detail.
    SCF                     ; Tell Atom to abort before COMMIT.
    RET                      ; HS_ABORT closes any still-open binary FCB.

;@ROUTINE IN A OUT A,DE,CARRY CLOBBERS BC,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Scan and validate one source header. Mode zero discovers names; mode one
; reports A=1 when any dependency has not yet been emitted.

CP_SCAN_PART:
    CALL CP_OPEN_PART       ; Open the requested source part for scanning.
    JR   C,CP_SCAN_FAILURE  ; Stop if the FCB cannot be opened.
    LD   A,1                ; The header accepts directives until code begins.
    LD   (CP_HEADER_OPEN),A  ; A source statement closes this header.
    CALL CP_PP_SCAN_RESET   ; Reset conditional state and root definitions.
    LD   HL,0               ; Begin at the first logical source byte.
CP_SCAN_LINE:

; Blank space, line endings and comment lines remain in the header. The first
; ordinary source byte closes it permanently; a later percent directive fails.

    CALL CP_NEXT_SOURCE_BYTE  ; Read the byte at the current logical offset.
    JR   C,CP_SCAN_EOF      ; Carry marks EOF, failed read or offset overflow.
    CP   ' '                ; A space does not close the leading header.
    JR   Z,CP_SCAN_LINE     ; Continue over horizontal whitespace.
    CP   9                  ; Tabs are also header whitespace.
    JR   Z,CP_SCAN_LINE     ; Test the next byte without advancing a line.
    CP   13                 ; CR remains inside a blank header line.
    JR   Z,CP_SCAN_LINE     ; LF is checked separately for CR/LF and LF files.
    CP   10                 ; LF remains inside the leading header as well.
    JR   Z,CP_SCAN_LINE     ; Continue scanning after the line ending.
    CP   ';'                ; Semicolon starts a source comment.
    JR   Z,CP_SCAN_SKIP_LINE  ; Ignore the remainder of that physical line.
    CP   '%'                ; A percent byte may begin a host directive.
    JR   Z,CP_SCAN_DIRECTIVE  ; Parse one while the header is still open.
    LD   A,(CP_HEADER_OPEN)  ; Check whether the leading header is still open.
    OR   A                  ; Body source closes the header permanently.
    JR   Z,CP_SCAN_BODY     ; Closed header has no include scope.
    CALL CP_PP_CHECK_INCLUDE_SCOPE  ; Reject open IF state at include.
    JP   C,CP_SCAN_INVALID  ; Preserve the required directive error.
CP_SCAN_BODY:
    XOR  A                  ; Any ordinary source byte closes the header.
    LD   (CP_HEADER_OPEN),A  ; Later includes and definitions are invalid.
    LD   (CP_PP_DEFS_OPEN),A  ; No definition may follow ordinary source.
    LD   A,(CP_PP_ACTIVE)   ; Determine whether this source line is selected.
    OR   A                  ; Inactive source still closes the file header.
    JR   Z,CP_SCAN_SKIP_LINE  ; Skip inactive source text.
CP_SCAN_SKIP_LINE:
    CALL CP_SKIP_SOURCE_LINE  ; Discard the rest of this physical line.
    JR   NC,CP_SCAN_LINE    ; Carry clear means another line is available.
    OR   A                  ; A=0 means EOF/read failure; A=2 wrap.
    JR   Z,CP_SCAN_COMPLETE  ; Treat a zero status as the end of this source.
    JR   CP_SCAN_IO         ; Reject a source offset outside the 16-bit range.
CP_SCAN_DIRECTIVE:
    CALL CP_PP_SCAN_DIRECTIVE  ; Parse host preprocessing directives.
    JR   C,CP_SCAN_FAILURE  ; Parsing and file errors share this return path.
    OR   A                  ; In ordering mode A=1 means a child is not ready.
    JR   NZ,CP_SCAN_DONE    ; Stop so the caller can defer this source part.
    JR   CP_SCAN_LINE       ; Continue through the remaining header lines.
CP_SCAN_EOF:
    OR   A                  ; A=0 means EOF/read failure; A=2 overflow.
    JR   NZ,CP_SCAN_IO      ; Reject a source offset that wrapped.
CP_SCAN_COMPLETE:
    LD   A,(CP_PP_DEPTH)    ; Every conditional must be closed before EOF.
    OR   A                  ; A remaining frame is an unterminated IF.
    JR   NZ,CP_SCAN_INVALID  ; Do not accept an incomplete conditional file.
    XOR  A                  ; No unresolved dependencies remain.
CP_SCAN_DONE:
    RET                     ; Preserve A for the discovery/order caller.
CP_SCAN_IO:
    LD   HL,CP_INPUT_FCB    ; The current FCB names the open part.
    CALL CP_PRINT_NAME      ; Identify the file whose scan could not continue.
    LD   DE,CP_READ_FAILED_TEXT  ; Select the source-read error message.
    JR   CP_SCAN_FAILURE    ; Return the read error through the shared exit.
CP_SCAN_INVALID:
    LD   DE,CP_INVALID_DIRECTIVE_TEXT  ; Select syntax-error detail.
CP_SCAN_FAILURE:
    SCF                     ; Carry marks failure regardless of text.
    RET                     ; Do not accept an incomplete dependency scan.

;@ROUTINE IN HL OUT A,DE,HL CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Append the resolved ordinal and measured byte range to the descriptor table.

CP_APPEND_DESCRIPTOR:
    LD   DE,(CP_DESCRIPTOR_CURSOR)  ; Start the next five-byte descriptor.
    LD   A,(CP_SCAN_INDEX)  ; Assign the resolved-order ordinal.
    LD   (DE),A             ; Descriptor byte zero is that ordinal.
    INC  DE                 ; Advance to the logical start low byte.
    XOR  A                  ; Each part starts at logical zero.
    LD   (DE),A             ; Store the start low byte.
    INC  DE                 ; Advance to the logical start high byte.
    LD   (DE),A             ; Store the start high byte.
    INC  DE                 ; Advance to the exclusive end low byte.
    LD   A,L                ; HL holds the measured source length.
    LD   (DE),A             ; Store the low byte of the half-open end.
    INC  DE                 ; Advance to the exclusive end high byte.
    LD   A,H                ; Complete the 16-bit source length.
    LD   (DE),A             ; Store the high byte of the half-open end.
    INC  DE                 ; Point at the following descriptor slot.
    LD   (CP_DESCRIPTOR_CURSOR),DE  ; Save the cursor for the next descriptor.
    RET                     ; Measure the next file after return.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse INCLUDE, one quoted current-drive 8.3 name and the rest of its line.
; Discovery records the child. Ordering checks whether it was emitted.

CP_PARSE_INCLUDE:
    LD   DE,CP_INCLUDE_WORD  ; Point at the uppercase directive name.
    LD   B,7                ; Match all seven letters in INCLUDE.
CP_INCLUDE_WORD_BYTE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next directive-name byte.
    JP   C,CP_INCLUDE_INVALID  ; A truncated name is not a directive.
    CP   'a'                ; Test whether ASCII lowercase folding applies.
    JR   C,CP_INCLUDE_WORD_CASED  ; Leave uppercase and punctuation unchanged.
    CP   'z'+1              ; Test the exclusive lowercase bound.
    JR   NC,CP_INCLUDE_WORD_CASED  ; Leave bytes beyond 'z' unchanged.
    AND  $DF                ; Fold lowercase ASCII to uppercase.
CP_INCLUDE_WORD_CASED:
    EX   DE,HL              ; Keep the source cursor in HL.
    CP   (HL)               ; Match the current byte against INCLUDE.
    INC  HL                 ; Advance to the next byte of the directive name.
    EX   DE,HL              ; Restore HL as the source cursor.
    JP   NZ,CP_INCLUDE_INVALID  ; Reject any mismatched directive byte.
    DJNZ CP_INCLUDE_WORD_BYTE  ; Check the remaining keyword bytes.
    CALL CP_NEXT_SOURCE_BYTE  ; Read the delimiter after INCLUDE.
    JP   C,CP_INCLUDE_INVALID  ; The keyword must have a following delimiter.
    CP   ' '                ; Accept an ordinary space before the filename.
    JR   Z,CP_INCLUDE_SPACE  ; Skip additional horizontal whitespace.
    CP   9                  ; Also accept a horizontal tab as delimiter.
    JP   NZ,CP_INCLUDE_INVALID  ; Require whitespace before the quote.
CP_INCLUDE_SPACE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read past the current whitespace byte.
    JP   C,CP_INCLUDE_INVALID  ; A filename must follow the delimiter.
    CP   ' '                ; Check for another space before the filename.
    JR   Z,CP_INCLUDE_SPACE  ; Continue across repeated spaces.
    CP   9                  ; Check for a repeated tab.
    JR   Z,CP_INCLUDE_SPACE  ; Continue across repeated tabs.
    CP   '"'                ; The filename must begin with a double quote.
    JP   NZ,CP_INCLUDE_INVALID  ; Reject unquoted include names.
    CALL CP_CLEAR_INCLUDE_FCB  ; Prepare a blank current-drive filename.
    PUSH IX                 ; Save the caller's index register.
    CALL CP_PARSE_INCLUDE_NAME  ; Store the quoted 8.3 name in the FCB.
    POP  IX                 ; Restore the caller's index register.
    RET  C                  ; Propagate an invalid or incomplete filename.
CP_INCLUDE_TRAILING:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next byte after the closing quote.
    JR   C,CP_INCLUDE_TRAILING_EOF  ; Branch on EOF or offset overflow.
    CP   ' '                ; Permit spaces after the filename.
    JR   Z,CP_INCLUDE_TRAILING  ; Skip trailing spaces.
    CP   9                  ; Permit tabs after the filename.
    JR   Z,CP_INCLUDE_TRAILING  ; Skip trailing tabs.
    CP   ';'                ; A semicolon starts a trailing comment.
    JR   Z,CP_INCLUDE_SKIP_COMMENT  ; Validate the rest of the comment line.
    CP   13                 ; Accept a CR line ending.
    JR   Z,CP_INCLUDE_READY  ; The include name is complete.
    CP   10                 ; Also accept an LF line ending.
    JP   NZ,CP_INCLUDE_INVALID  ; Reject any other trailing byte.
CP_INCLUDE_READY:

; Deduplicate the eleven-byte CP/M name. Discovery adds missing names.
; Ordering reports whether each child has already been emitted.

    CALL CP_PP_MARK_INCLUDE  ; Retain header IF state for import.
    LD   A,(CP_PP_ACTIVE)   ; Zero means validate, but do not import.
    OR   A                  ; Zero means validate name only.
    JR   Z,CP_INCLUDE_IGNORED  ; Do not open or order an inactive dependency.

    PUSH IX                 ; Save IX across name lookup.
    PUSH HL                 ; Save the source cursor.
    CALL CP_FIND_OR_ADD_NAME  ; Reuse a known child or append its name.
    POP  HL                 ; Restore the source cursor.
    POP  IX                 ; Restore the caller's index register.
    RET  C                  ; Return a name-capacity failure to the resolver.
    PUSH HL                 ; Save cursor across child lookup.
    CALL CP_VISIT_INCLUDED_CHILD  ; Return the pending-child status.
    POP  HL                 ; Restore cursor; preserve result flags.
    RET                     ; Return the pending-child status.
CP_INCLUDE_IGNORED:
    XOR  A                  ; An inactive import creates no pending child.
    RET                     ; Continue preflight with the next directive.
CP_INCLUDE_SKIP_COMMENT:
    CALL CP_SKIP_SOURCE_LINE  ; Consume the trailing comment through line end.
    JR   C,CP_INCLUDE_TRAILING_EOF  ; Check the carried end status.
    JR   CP_INCLUDE_READY   ; The include line has no more source text.
CP_INCLUDE_TRAILING_EOF:
    OR   A                  ; Zero means EOF; NZ means overflow.
    JP   NZ,CP_INCLUDE_INVALID  ; Reject an offset that wrapped.
    JR   CP_INCLUDE_READY   ; Accept the include at end of input.
CP_INCLUDE_INVALID:
    LD   DE,CP_INVALID_INCLUDE_TEXT  ; Select the malformed-include message.
    SCF                     ; Mark the include directive as invalid.
    RET                     ; Return the message pointer and failure flag.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS BC,DE,IX,ZERO,SIGN,PARITY,HALFCARRY
; Parse one quoted include filename into the working CP/M FCB.

CP_PARSE_INCLUDE_NAME:
    LD   IX,CP_WORK_FCB+1   ; Begin writing the eight-byte base field.
    LD   D,8                ; Set the base-name capacity.
    LD   C,0                ; Count characters in the current name field.
CP_INCLUDE_NAME_BYTE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next quoted filename byte.
    JP   C,CP_INCLUDE_NAME_BAD  ; Require a complete closing quote.
    CP   '"'                ; Check for the end of the filename.
    JR   Z,CP_INCLUDE_NAME_DONE  ; Validate that the final field is nonempty.
    CP   '.'                ; Check for the single base/extension separator.
    JR   NZ,CP_INCLUDE_NAME_DATA  ; Other bytes belong to the current field.
    LD   A,D                ; Read the active field's maximum width.
    CP   8                  ; Dot is valid only after the base.
    JP   NZ,CP_INCLUDE_NAME_BAD  ; Reject repeated separators.
    LD   A,C                ; Read the number of base-name characters.
    OR   A                  ; Set Z when the base field is empty.
    JP   Z,CP_INCLUDE_NAME_BAD  ; Require at least one base character.
    LD   IX,CP_WORK_FCB+9   ; Continue writing at the three-byte type field.
    LD   D,3                ; Set the extension capacity.
    LD   C,0                ; Start the extension character count.
    JR   CP_INCLUDE_NAME_BYTE  ; Read the first extension character.
CP_INCLUDE_NAME_DATA:
    CP   'a'                ; Test for an ASCII lowercase filename letter.
    JR   C,CP_INCLUDE_NAME_CASED  ; Keep non-lowercase bytes unchanged.
    CP   'z'+1              ; Test the lowercase upper bound.
    JR   NC,CP_INCLUDE_NAME_CASED  ; Keep bytes above 'z' unchanged.
    AND  $DF                ; Fold ASCII lowercase for lookup.
CP_INCLUDE_NAME_CASED:
    CALL CP_FILENAME_CHAR   ; Reject characters outside the CP/M name set.
    JP   C,CP_INCLUDE_NAME_BAD  ; Carry marks a forbidden filename character.
    INC  C                  ; Count this field's next byte.
    LD   B,A                ; Save byte during capacity check.
    LD   A,D                ; Load the active base or extension limit.
    CP   C                  ; Compare limit with new length.
    JP   C,CP_INCLUDE_NAME_BAD  ; Reject a field wider than 8.3 allows.
    LD   A,B                ; Restore the normalized filename byte.
    LD   (IX+0),A           ; Store it in the current FCB name field.
    INC  IX                 ; Advance to the next character slot.
    JR   CP_INCLUDE_NAME_BYTE  ; Continue through the closing quote.
CP_INCLUDE_NAME_DONE:
    LD   A,C                ; Read the character count of the final field.
    OR   A                  ; Set Z only when that field is empty.
    RET  NZ                 ; Accept a nonempty base or extension field.
CP_INCLUDE_NAME_BAD:
    LD   DE,CP_INVALID_INCLUDE_TEXT  ; Select the malformed-include message.
    SCF                     ; Mark the filename as invalid.
    RET                     ; Return failure to the directive parser.

;@ROUTINE IN A OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Visit a discovered include child when dependency scanning is active.

CP_VISIT_INCLUDED_CHILD:
    LD   E,A                ; Keep the child ordinal across the mode check.
    LD   A,(CP_SCAN_MODE)   ; Read whether this is discovery or ordering.
    OR   A                  ; Discovery mode is zero.
    RET  Z                  ; Discovery needs no pending-child result.
    LD   A,E                ; Restore the child's retained-name ordinal.
    CALL CP_NAME_POINTER    ; Address its eleven-byte name record.
    BIT  7,(HL)             ; Test the emitted marker in the first name byte.
    LD   A,0                ; Zero means child already emitted.
    RET  NZ                 ; An emitted child is ready.
    INC  A                  ; One means child is still pending.
    RET                     ; Return one for a pending child.

;@ROUTINE OUT A CLOBBERS B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Reset the working include FCB to a blank 8.3 filename.

CP_CLEAR_INCLUDE_FCB:
    LD   DE,CP_WORK_FCB     ; Address the temporary working FCB.
    XOR  A                  ; Select the current drive.
    LD   (DE),A             ; Clear the explicit drive byte.
    INC  DE                 ; Advance to the eleven-byte 8.3 name.
    LD   B,11               ; Clear all eight base and three extension bytes.
    LD   A,' '              ; CP/M represents unused name bytes with spaces.
    CALL CP_CLEAR_WORK_FCB  ; Fill the name and extension fields.
    JP   CP_CLEAR_FCB_TAIL  ; Clear the remaining FCB control bytes.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains.

CP_FIND_OR_ADD_NAME:
    LD   C,0                ; Start with retained-name ordinal zero.
CP_FIND_NAME_LOOP:
    LD   A,(CP_NAME_COUNT)  ; Read the number of names already retained.
    CP   C                  ; Compare count with candidate ordinal.
    JR   Z,CP_ADD_NAME      ; Append when no existing slot remains to inspect.
    LD   A,C                ; Select this retained name's ordinal.
    CALL CP_NAME_POINTER    ; Address its eleven-byte name record.
    LD   IX,CP_WORK_FCB+1   ; Address the normalized candidate filename.
    LD   B,11               ; Compare the complete base and extension fields.
CP_FIND_NAME_BYTE:
    LD   A,(HL)             ; Read one byte from the retained name.
    AND  $7F                ; Ignore the emitted bit in the name.
    CP   (IX+0)             ; Compare with the corresponding candidate byte.
    JR   NZ,CP_FIND_NAME_NEXT  ; Try the next ordinal on any mismatch.
    INC  HL                 ; Advance the retained-name cursor.
    INC  IX                 ; Advance the candidate-name cursor.
    DJNZ CP_FIND_NAME_BYTE  ; Compare the remaining name bytes.
    LD   A,C                ; Return the ordinal whose full name matched.
    OR   A                  ; Clear carry and set zero for ordinal zero.
    RET                     ; Return the existing name ordinal.
CP_FIND_NAME_NEXT:
    INC  C                  ; Advance to the next retained-name ordinal.
    JR   CP_FIND_NAME_LOOP  ; Continue until a name matches or the table ends.
CP_ADD_NAME:

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C                ; The next ordinal is the current number of names.
    CP   255                ; The byte-sized table has no ordinal 255 entry.
    JR   Z,CP_NAME_CAPACITY  ; Reject a 256th distinct source file.
    PUSH AF                 ; Save the new source ordinal.
    CALL CP_NAME_POINTER    ; Address the next eleven-byte table slot.
    EX   DE,HL              ; Put the slot destination in DE for LDIR.
    LD   HL,CP_WORK_FCB+1   ; Point to the normalized 8.3 name bytes.
    LD   BC,11              ; Copy name and type, not drive.
    LDIR                    ; Store the new name in its ordinal slot.
    LD   HL,CP_NAME_COUNT   ; Address the count published to the resolver.
    INC  (HL)               ; Publish the completed name slot.
    POP  AF                 ; Return the allocated ordinal.
    OR   A                  ; Clear carry to mark successful insertion.
    RET                     ; Return the new retained-name identity.
CP_NAME_CAPACITY:
    LD   DE,CP_SOURCE_CAPACITY_TEXT  ; Select the part-capacity diagnostic.
    SCF                     ; Mark the resolver's name table as full.
    RET                     ; Return without changing the retained-name count.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

CP_NAME_POINTER:
    LD   L,A                ; Place the ordinal in the low byte of HL.
    LD   H,0                ; Extend the ordinal to a 16-bit value.
    LD   D,H                ; Clear the high byte of the temporary DE value.
    LD   E,L                ; Copy ordinal for ×11.
    ADD  HL,HL              ; Compute twice the ordinal.
    ADD  HL,HL              ; Compute four times the ordinal.
    ADD  HL,DE              ; Combine to make five times the ordinal.
    ADD  HL,HL              ; Compute ten times the ordinal.
    ADD  HL,DE              ; Complete eleven times the ordinal.
    LD   DE,CP_PART_NAMES   ; Load the base of the retained-name table.
    ADD  HL,DE              ; Convert the byte offset to the slot address.
    RET                     ; Return this name-record address.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild and open the ordinary input FCB from one retained name.

CP_OPEN_PART:
    PUSH AF                 ; Save ordinal while clearing FCB.
    CALL CP_CLEAR_INPUT_FCB  ; Reset the file-control block for this source.
    POP  AF                 ; Restore the source ordinal.
    CALL CP_NAME_POINTER    ; Address the source's eleven-byte name record.
    LD   DE,CP_INPUT_FCB+1  ; Point past the drive byte to the 8.3 fields.
    LD   B,11               ; Copy the full 8.3 name.
CP_OPEN_NAME_BYTE:
    LD   A,(HL)             ; Read the next byte of the retained source name.
    AND  $7F                ; Clear the first byte's order bit.
    LD   (DE),A             ; Copy the ordinary name byte into the input FCB.
    INC  HL                 ; Advance within the retained name record.
    INC  DE                 ; Advance within the input FCB name fields.
    DJNZ CP_OPEN_NAME_BYTE  ; Copy all eleven name and type bytes.
    CALL CP_CHECK_SOURCE_CONFLICT  ; Protect output and transaction files.
    RET  C                  ; Reject a source/output alias.
    LD   DE,CP_INPUT_FCB    ; Pass the prepared FCB to CP/M.
    LD   C,CP_OPEN_FUNCTION  ; Select the CP/M open-file service.
    CALL CP_BDOS            ; Open the selected source file.
    INC  A                  ; Convert BDOS's $FF failure result to zero.
    JR   Z,CP_OPEN_FAILURE  ; Report an unavailable source by name.
    LD   A,1                ; Force the next cache refill.
    LD   (CP_SOURCE_CACHE_KEY),A  ; Aligned record offsets cannot equal one.
    XOR  A                  ; Return success with carry clear.
    RET                     ; Leave the input FCB open.
CP_OPEN_FAILURE:
    LD   HL,CP_INPUT_FCB    ; Address the filename that failed to open.
    CALL CP_PRINT_NAME      ; Print its drive-independent 8.3 name.
    LD   DE,CP_READ_FAILED_TEXT  ; Select the source-open error message.
    SCF                     ; Mark the open operation as failed.
    RET                     ; Return the message pointer with carry set.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return the next raw source byte and advance HL. Carry with A=0 means EOF or
; an unsuccessful CP/M random read. Carry with A=2 means the 16-bit offset
; wrapped. BC and DE survive for parsers.
; A part is limited to 65,535 bytes so the next offset cannot wrap to zero.

CP_NEXT_SOURCE_BYTE:
    PUSH BC                 ; Preserve the parser's byte-sized working values.
    PUSH DE                 ; Save the parser's DE value.
    PUSH HL                 ; Save the logical offset.
    CALL CP_RAW_SOURCE_BYTE  ; Read from the current CP/M record cache.
    POP  HL                 ; Restore the logical offset.
    POP  DE                 ; Restore the caller's DE value.
    POP  BC                 ; Restore the caller's BC value.
    RET  C                  ; Return EOF/read failure; keep HL.
    LD   (CP_NEXT_VALUE),A  ; Save the byte while advancing the offset.
    INC  HL                 ; Advance to the following offset.
    LD   A,H                ; Test the high byte of the advanced offset.
    OR   L                  ; Zero means the 16-bit offset wrapped.
    JR   Z,CP_SOURCE_TOO_LONG  ; Reject a part that would exceed 65,535 bytes.
    LD   A,(CP_NEXT_VALUE)  ; Restore the byte read from the source.
    OR   A                  ; Clear carry; set Z for byte zero.
    RET                     ; Return byte and advanced offset.
CP_SOURCE_TOO_LONG:
    LD   A,2                ; Distinguish offset overflow.
    SCF                     ; Report that the logical source offset wrapped.
    RET                     ; Return the overflow status to the resolver.

;@ROUTINE IN HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Align the logical offset to its 128-byte CP/M record base. The cache
; key stores that base; the FCB receives it divided by 128. On a miss,
; the routine installs the source cache as DMA and reads that record.
; It then uses the low seven bits to select the requested byte.

CP_RAW_SOURCE_BYTE:
    LD   (CP_RAW_OFFSET),HL  ; Save the requested logical byte offset.
    LD   A,L                ; Inspect the low byte of the requested offset.
    AND  $80                ; Keep its 128-byte record-boundary bit.
    LD   E,A                ; Form the aligned offset's low byte.
    LD   D,H                ; Form its high byte from the logical offset.
    LD   HL,(CP_SOURCE_CACHE_KEY)  ; Read the offset currently in the cache.
    OR   A                  ; Clear carry for base subtraction.
    SBC  HL,DE              ; Compare the cached and requested record bases.
    JR   Z,CP_RAW_CACHE_READY  ; Reuse the cache when both bases match.
CP_RAW_CACHE_MISS:
    LD   (CP_SOURCE_CACHE_KEY),DE  ; Remember the aligned offset being loaded.
    RLC  E                  ; Move offset bit 7 into record bit 0.
    LD   A,D                ; Load the offset high byte.
    ADD  A,A                ; Shift its bits left one place.
    OR   E                  ; Add the original offset's bit 7.
    LD   (CP_INPUT_FCB+33),A  ; Store the random record number's low byte.
    LD   A,D                ; Reload the offset's high byte.
    RLCA                    ; Move offset bit 15 into bit 0.
    AND  1                  ; Keep only the record number's high bit.
    LD   (CP_INPUT_FCB+34),A  ; Store the random record number's high byte.
    LD   DE,CP_SOURCE_CACHE  ; Select the 128-byte DMA buffer.
    LD   C,CP_DMA_FUNCTION  ; Set the CP/M transfer address.
    CALL CP_BDOS            ; Direct the next read into the source cache.
    LD   DE,CP_INPUT_FCB    ; Pass the file and record number to CP/M.
    LD   C,CP_RANDOM_READ_FUNCTION  ; Select a random-record read.
    CALL CP_BDOS            ; Load the requested 128-byte source record.
    OR   A                  ; Zero means the random read succeeded.
    JR   NZ,CP_RAW_READ_EOF  ; Treat a BDOS read failure as no source byte.
CP_RAW_CACHE_READY:
    LD   HL,(CP_RAW_OFFSET)  ; Restore the byte's logical offset.
    RES  7,L                ; Keep its within-record offset in $00..$7F.
    LD   H,CP_SOURCE_CACHE/256  ; Select the source cache's memory page.
    LD   A,(HL)             ; Read the byte from the cached record.
    CP   $1A                ; Test CP/M's text-file end marker.
    JR   Z,CP_RAW_EOF       ; Return end-of-input at control-Z.
    OR   A                  ; Clear carry; retain source byte.
    RET                     ; Return the raw byte to the caller.
CP_RAW_READ_EOF:
CP_RAW_EOF:
    XOR  A                  ; Return EOF or read failure.
    SCF                     ; Carry reports that no source byte is available.
    RET                     ; Share the no-byte result.

;@ROUTINE IN HL OUT A,CARRY,HL CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Consume source bytes through the next CR, LF or end of file.

CP_SKIP_SOURCE_LINE:
    CALL CP_NEXT_SOURCE_BYTE  ; Read the next byte in the current line.
    RET  C                  ; Stop at EOF or offset overflow.
    CP   13                 ; Test for a carriage return.
    RET  Z                  ; Stop after consuming CR.
    CP   10                 ; Test for a line feed.
    JR   NZ,CP_SKIP_SOURCE_LINE  ; Continue until LF or another CR.
    RET                     ; Stop after consuming LF.

;@ROUTINE IN A,HL OUT A,CARRY,ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY
; Open a part on ordinal change, then return one source byte.
; Preflight accepts only %INCLUDE. Its leading percent becomes a semicolon,
; so Atom reads the rest of that directive line as a comment.

CP_RESOLVED_READ_BYTE:
    LD   E,A                ; Keep the resolved source-part ordinal.
    LD   A,(CP_ACTIVE_PART)  ; Read the ordinal of the open source file.
    CP   E                  ; Compare it with the requested part.
    JR   Z,CP_RESOLVED_SOURCE_READY  ; Reuse the file when ordinals match.
    PUSH BC                 ; Preserve the caller's byte-sized parser state.
    PUSH HL                 ; Save offset across file open.
    LD   A,E                ; Restore the requested resolved ordinal.
    LD   (CP_ACTIVE_PART),A  ; Record which resolved part is now active.
    LD   D,CP_PART_ORDER/256  ; Address the order table's fixed memory page.
    LD   A,(DE)             ; Map order to source ordinal.
    CALL CP_OPEN_PART       ; Open the source named by that original ordinal.
    CALL CP_PP_RUNTIME_RESET  ; Start each source part outside a conditional.
    POP  HL                 ; Restore the byte offset.
    POP  BC                 ; Restore the caller's parser state.
CP_RESOLVED_SOURCE_READY:
    PUSH BC                 ; Save parser BC across raw read.
    PUSH HL                 ; Preserve the source offset across cache lookup.
    CALL CP_RAW_SOURCE_BYTE  ; Read one byte from the active source file.
    POP  HL                 ; Restore the source offset.
    POP  BC                 ; Restore the caller's parser state.
    RET  C                  ; Return end-of-input or a failed read unchanged.
    JP   CP_PP_RUNTIME_FILTER  ; Filter directives and inactive lines.

;@ROUTINE IN HL OUT A,ZERO CLOBBERS BC,DE,HL,CARRY,SIGN,PARITY,HALFCARRY
; Decide whether a percent character begins a recognized host directive.

CP_PERCENT_IS_DIRECTIVE:
    LD   A,H                ; Test the current source offset's high byte.
    OR   L                  ; Zero means the percent is the first source byte.
    RET  Z                  ; Report line start when no preceding byte exists.
    DEC  HL                 ; Begin scanning at the byte before the percent.
CP_PERCENT_PREFIX:
    PUSH HL                 ; Save the backward-scan cursor.
    CALL CP_RAW_SOURCE_BYTE  ; Read the preceding source byte.
    POP  HL                 ; Restore the offset used for the backward scan.
    CP   13                 ; Does percent follow CR?
    JR   Z,CP_PERCENT_YES   ; CR marks the start of a source line.
    CP   10                 ; Check whether the percent follows a line feed.
    JR   Z,CP_PERCENT_YES   ; LF also marks the start of a source line.
    CP   ' '                ; Check for a space before the percent.
    JR   Z,CP_PERCENT_PREVIOUS  ; Skip whitespace while scanning backwards.
    CP   9                  ; Check for a horizontal tab.
    RET  NZ                 ; Other prefix means ordinary text.
CP_PERCENT_PREVIOUS:
    LD   A,H                ; Did whitespace reach offset zero?
    OR   L                  ; No preceding non-space byte.
    JR   Z,CP_PERCENT_YES   ; Only spaces or tabs precede the percent.
    DEC  HL                 ; Step back one source byte.
    JR   CP_PERCENT_PREFIX  ; Continue until line start or ordinary text.
CP_PERCENT_YES:
    XOR  A                  ; Mark a line-leading percent.
    RET                     ; Return with carry clear.
;@@ATOM_CPM_PREPROCESSOR@@
CP_SOURCE_CODE_END:

; These Atom sink entries replace the fail-closed host stubs. IMAGE and PATCH
; are appended to a private ASO spool; output publication waits until COMMIT.

CP_OUTPUT_CODE_START:
;@@ATOM_CPM_ASO_WRITER@@
HS_SCBEG:

;@ROUTINE IN IX OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Begin a fresh tentative generation. No file is created until COMMIT.

HS_BEG:
    JP   CP_ASO_BEGIN       ; Start the ordered-operation writer.

;@ROUTINE IN A,C,HL OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Serialize one IMAGE or byte-PATCH value in the private CP/M operation spool.

HS_IB:
    LD   (CP_BIN_SINK_VALUE),A  ; Retain Atom's fill byte while selecting a row.
    LD   A,(CP_BIN_COUNT)   ; Avoid the dispatch cost for ordinary CP/M sources.
    OR   A                  ; A zero count means no INCBIN metadata exists.
    JR   NZ,.BINARY         ; Only counted binary rows need the sequential reader.
    LD   A,(CP_BIN_SINK_VALUE)  ; Restore the original Atom IMAGE fill byte.
    JP   CP_ASO_IMAGE       ; Keep the no-INCBIN output path byte-for-byte intact.
.BINARY:
    PUSH BC                 ; Keep the address-space class for CP_ASO_IMAGE.
    PUSH HL                 ; Keep the logical target address for the sink.
    LD   A,(ST_EPART)       ; Read the current statement's resolved part ordinal.
    LD   (CP_BIN_SINK_PART),A  ; Match the sink event to its preflight row.
    LD   HL,(ST_EOFF)       ; Read the exact IMAGE-producing source position.
    LD   (CP_BIN_SINK_OFFSET),HL  ; Retain it while BDOS uses the shared DMA page.
    CALL CP_BIN_SINK_BYTE   ; Substitute the next binary byte when anchors match.
    JR   C,.BINARY_FAILED  ; Preserve the source-aware failure for CP_ENTRY.
    POP  HL                 ; Restore the logical IMAGE address.
    POP  BC                 ; Restore its address-space class.
    LD   A,(CP_BIN_SINK_VALUE)  ; Load either payload or original fill byte.
    JP   CP_ASO_IMAGE       ; Append the selected value to the ASO stream.
.BINARY_FAILED:
    POP  HL                 ; Restore the caller's stack before reporting failure.
    POP  BC                 ; Preserve the original address-class register.
    RET                      ; Return the failed sink status to Atom's driver.
HS_PB:
    JP   CP_ASO_PATCH_BYTE  ; Append the replacement byte to the spool.

;@ROUTINE IN C,DE,HL OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Store one little-endian word at its translated logical address.

HS_PW:
    JP   CP_ASO_PATCH_WORD  ; Append both replacement bytes to the spool.

;@ROUTINE IN A,BC,DE,HL,IX OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; COMMIT seals the operation stream and publishes its selected representation.

HS_CMT:
    PUSH AF                 ; Preserve Atom's high-water flags and endpoint bit.
    PUSH BC                 ; Preserve the low high-water/address pair.
    PUSH DE                 ; Preserve the image origin passed to COMMIT.
    PUSH HL                 ; Preserve the upper high-water word.
    PUSH IX                 ; Preserve the descriptor geometry pointer.
    CALL CP_BIN_SINK_FINISH ; Refuse publication unless every payload was consumed.
    JR   C,.INCOMPLETE      ; Restore geometry before returning a sink failure.
    POP  IX                 ; Restore the descriptor expected by CP_ASO_COMMIT.
    POP  HL                 ; Restore the high-water geometry word.
    POP  DE                 ; Restore the image origin.
    POP  BC                 ; Restore the low high-water/address pair.
    POP  AF                 ; Restore original flags and Atom's endpoint marker.
    JP   CP_ASO_COMMIT      ; Seal, materialize if needed, and publish.
.INCOMPLETE:
    POP  IX                 ; Restore every input even when validation fails.
    POP  HL                 ; Keep the caller's stack balanced for HS_ABORT.
    POP  DE                 ; Preserve caller-owned image geometry.
    POP  BC                 ; Restore its address pair.
    POP  AF                 ; Recover Atom's A before selecting sink status.
    LD   A,1                ; Return the established nonzero sink-failure status.
    SCF                     ; HS_ABORT will discard the tentative spool.
    RET                      ; No partial output may be committed.
CP_COMMIT_RAM:
    POP  AF                 ; Restore flags expected by the RAM finalizer.
    BIT  1,A                ; Is high water the mathematical endpoint $10000?
    JR   NZ,.ENDPOINT       ; Use the explicit endpoint form.
    LD   H,B                ; Load the high-water word's high byte.
    LD   L,C                ; Complete the ordinary high-water address.
    JR   .LENGTH            ; Convert the absolute address to file length.
.ENDPOINT:
    LD   HL,0               ; Zero is the stored word for mathematical $10000.
.LENGTH:
    LD   DE,CP_TARGET_START  ; Load the image's logical base address.
    OR   A                  ; Clear carry before subtracting base.
    SBC  HL,DE              ; Convert high water to image length.
    LD   (CP_OUTPUT_REMAINING),HL  ; Retain bytes to write as records.
    LD   HL,CP_OUTPUT_START  ; Point at the first byte of the tentative image.
    LD   (CP_OUTPUT_CURSOR),HL  ; Seed the sequential record cursor.
    CALL CP_SET_TEMP_FCB    ; Select the transaction's temporary filename.
    LD   DE,CP_WORK_FCB     ; Pass its FCB to the delete service.
    LD   C,CP_DELETE_FUNCTION  ; Select CP/M delete-file function 19.
    CALL CP_BDOS            ; Remove any prior temp file.
    CALL CP_SET_TEMP_FCB    ; Rebuild the FCB for file creation.
    LD   DE,CP_WORK_FCB     ; Pass the temp FCB to the make service.
    LD   C,CP_MAKE_FUNCTION  ; Select CP/M make-file function 22.
    CALL CP_BDOS            ; Create the tentative output file.
    INC  A                  ; Convert BDOS's $FF failure result to zero.
    JP   Z,CP_COMMIT_FAILURE  ; Abort if CP/M could not create the temp file.
    LD   A,1                ; Mark that abort must close the open temp file.
    LD   (CP_OUTPUT_OPEN),A  ; Record ownership of the new file.
    LD   A,(CP_OUTPUT_FORMAT)  ; Read the format selected from the extension.
    CP   2                  ; Format two is Intel HEX.
    JR   NZ,CP_WRITE_LOOP   ; Write COM and BIN as raw image records.
    CALL CP_WRITE_HEX       ; Serialize the image as Intel HEX text.
    JP   C,CP_COMMIT_FAILURE  ; Leave HEX write failures for the abort path.
    JR   CP_WRITE_CLOSE     ; Close the completed HEX temporary file.
CP_WRITE_LOOP:
    LD   HL,(CP_OUTPUT_REMAINING)  ; Read the unconsumed image byte count.
    LD   A,H                ; Test its high byte first.
    OR   L                  ; Zero means every image byte has been written.
    JR   Z,CP_WRITE_CLOSE   ; Close at end of image.
    LD   DE,(CP_OUTPUT_CURSOR)  ; Select the next 128-byte source block.
    LD   C,CP_DMA_FUNCTION  ; Point CP/M's DMA at that block.
    CALL CP_BDOS            ; Install the image block as the transfer buffer.
    LD   DE,CP_WORK_FCB     ; Pass the temporary file's FCB to CP/M.
    LD   C,CP_WRITE_FUNCTION  ; Select sequential record-write function 21.
    CALL CP_BDOS            ; Append one 128-byte image record.
    OR   A                  ; Zero indicates a successful record write.
    JP   NZ,CP_COMMIT_FAILURE  ; Abort publication after a failed write.
    LD   HL,(CP_OUTPUT_CURSOR)  ; Read the current image-block address.
    LD   DE,128             ; Advance by one CP/M record.
    ADD  HL,DE              ; Select the following image block.
    LD   (CP_OUTPUT_CURSOR),HL  ; Retain its address for the next iteration.
    LD   HL,(CP_OUTPUT_REMAINING)  ; Reload bytes not yet covered by records.
    LD   DE,128             ; Subtract the record size from that remainder.
    OR   A                  ; Clear carry before the subtraction.
    SBC  HL,DE              ; Calculate the byte count after this record.
    JR   NC,CP_WRITE_MORE   ; Keep a non-negative remainder unchanged.
    LD   HL,0               ; Clamp a partial record to zero.
CP_WRITE_MORE:
    LD   (CP_OUTPUT_REMAINING),HL  ; Save the count for the next loop test.
    JR   CP_WRITE_LOOP      ; Write another record or begin publication.

; Close temp, move an existing output to backup, rename temp to final, then
; delete the backup. Preflight proved the backup name was initially unused.

CP_WRITE_CLOSE:
    LD   DE,CP_WORK_FCB     ; Close the temporary FCB.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Flush and close the completed temporary file.
    INC  A                  ; Convert BDOS's $FF close failure to zero.
    JP   Z,CP_COMMIT_FAILURE  ; Keep the previous final file on close failure.
    XOR  A                  ; Prepare the closed-file state.
    LD   (CP_OUTPUT_OPEN),A  ; Prevent abort from closing the file again.
CP_PUBLISH_TEMP:
    CALL CP_SET_BACKUP_FCB  ; Name the backup file for the selected output.
    LD   DE,CP_WORK_FCB     ; Pass its FCB to the delete service.
    LD   C,CP_DELETE_FUNCTION  ; Select CP/M delete-file function 19.
    CALL CP_BDOS            ; Remove any prior backup file.
    LD   HL,CP_OUTPUT_NAME  ; Supply the current final name as rename source.
    LD   DE,CP_WORK_FCB     ; Supply the backup name as rename destination.
    CALL CP_BUILD_RENAME    ; Build a CP/M rename FCB for the old output.
    LD   DE,CP_RENAME_FCB   ; Pass the completed rename FCB to CP/M.
    LD   C,CP_RENAME_FUNCTION  ; Select CP/M rename-file function 23.
    CALL CP_BDOS            ; Move old output to backup.
    INC  A                  ; Set zero when CP/M returned $FF for the rename.
    JR   Z,CP_NO_BACKUP     ; Skip backup on rename failure.
    LD   A,1                ; Mark old output as backed up.
    LD   (CP_BACKED_UP),A   ; Let abort restore it if the next rename fails.
CP_NO_BACKUP:
    CALL CP_SET_TEMP_FCB    ; Select the completed temporary output name.
    LD   HL,CP_WORK_FCB     ; Supply the temporary name as rename source.
    LD   DE,CP_OUTPUT_NAME  ; Supply the requested final name as destination.
    CALL CP_BUILD_RENAME    ; Build the CP/M rename FCB for publication.
    LD   DE,CP_RENAME_FCB   ; Pass the completed rename FCB to CP/M.
    LD   C,CP_RENAME_FUNCTION  ; Select CP/M rename-file function 23.
    CALL CP_BDOS            ; Publish temp under final name.
    INC  A                  ; Test for BDOS rename failure.
    JP   Z,CP_COMMIT_FAILURE  ; Preserve the backup until abort restores it.
    CALL CP_SET_BACKUP_FCB  ; Rebuild the backup name for cleanup.
    LD   DE,CP_WORK_FCB     ; Pass the backup FCB to the delete service.
    LD   C,CP_DELETE_FUNCTION  ; Select CP/M delete-file function 19.
    CALL CP_BDOS            ; Remove old output after commit.
    XOR  A                  ; Clear transaction state.
    LD   (CP_BACKED_UP),A   ; Clear the flag after attempting backup deletion.
    RET                     ; Report successful publication with carry clear.
CP_COMMIT_FAILURE:
    LD   A,1                ; Return failed-commit status.
    SCF                     ; Mark the sink operation as failed.
    RET                     ; Driver will call HS_ABORT.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Close temporary output if open, then delete it. If commit moved the old
; final file aside, restore the backup. Cleanup tolerates early failure.

HS_ABORT:
    LD   A,(CP_BIN_OPEN)    ; Check whether a binary include still owns an FCB.
    OR   A                  ; A clear flag needs no binary close operation.
    JR   Z,CP_ABORT_ASO     ; Continue when no binary input is open.
    LD   DE,CP_BIN_FCB      ; Pass the dedicated payload FCB to CP/M.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function sixteen.
    CALL CP_BDOS            ; Release the binary input before other cleanup.
    XOR  A                  ; Clear ownership even when CLOSE itself failed.
    LD   (CP_BIN_OPEN),A    ; HS_ABORT must remain safe if called again.
CP_ABORT_ASO:
    LD   A,(CP_ASO_OPEN)    ; Check whether an ASO temporary file is open.
    OR   A                  ; A clear flag needs no ASO close operation.
    JR   Z,CP_ABORT_IMAGE   ; Continue with the ordinary temporary file.
    LD   DE,CP_ASO_FCB      ; Pass the ASO spool FCB to the close service.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Close the spool before deleting its name.
    XOR  A                  ; Mark the spool FCB closed for repeated cleanup.
    LD   (CP_ASO_OPEN),A    ; Mark the spool closed for this abort.
CP_ABORT_IMAGE:
    LD   A,(CP_MAT_READER_OPEN)  ; Check whether the spool reader is open.
    OR   A                  ; Zero means no materializer reader needs closing.
    JR   Z,CP_ABORT_TEMP    ; Continue cleanup when already closed.
    LD   DE,CP_MAT_FCB      ; Pass the relocated reader FCB to CP/M.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Release the active spool reader before reuse.
    XOR  A                  ; Clear reader ownership even if CLOSE failed.
    LD   (CP_MAT_READER_OPEN),A  ; Clear the abort close flag.
CP_ABORT_TEMP:
    LD   A,(CP_OUTPUT_OPEN)  ; Check whether the temporary file is open.
    OR   A                  ; Set zero when no close operation is required.
    JR   Z,CP_ABORT_DELETE  ; Continue directly to removing the temp name.
    LD   DE,CP_WORK_FCB     ; Pass the temporary file's FCB to CP/M.
    LD   C,CP_CLOSE_FUNCTION  ; Select CP/M close-file function 16.
    CALL CP_BDOS            ; Close the temporary file before deleting it.
CP_ABORT_DELETE:
    CALL CP_SET_TEMP_FCB    ; Rebuild the temporary file's FCB.
    LD   DE,CP_WORK_FCB     ; Pass the temporary FCB to CP/M.
    LD   C,CP_DELETE_FUNCTION  ; Select CP/M delete-file function 19.
    CALL CP_BDOS            ; Delete uncommitted temp output.
    LD   A,(CP_MAT_SPOOL_OWNED)  ; Is BAK still the spool?
    OR   A                  ; A clear flag means BAK may be a real old output.
    CALL NZ,CP_MAT_DELETE_SPOOL  ; Let overlay remove only a private spool.
CP_ABORT_RESTORE:
    LD   A,(CP_BACKED_UP)   ; Check whether commit moved an old output aside.
    OR   A                  ; No backup means no restore.
    JR   Z,CP_ABORT_DONE    ; Finish after attempting temporary-file deletion.
    CALL CP_SET_BACKUP_FCB  ; Rebuild the backup file's FCB.
    LD   HL,CP_WORK_FCB     ; Supply the backup name as rename source.
    LD   DE,CP_OUTPUT_NAME  ; Supply the requested output name as destination.
    CALL CP_BUILD_RENAME    ; Build a CP/M rename FCB for restoration.
    LD   DE,CP_RENAME_FCB   ; Pass the completed rename FCB to CP/M.
    LD   C,CP_RENAME_FUNCTION  ; Select CP/M rename-file function 23.
    CALL CP_BDOS            ; Attempt to restore the previous output name.
CP_ABORT_DONE:
    XOR  A                  ; Clear the temporary-file and backup state.
    LD   (CP_OUTPUT_OPEN),A  ; Clear the open flag after cleanup attempts.
    LD   (CP_BACKED_UP),A   ; Clear backup state after all cleanup attempts.
    LD   (CP_ASO_ACTIVE),A  ; Disable ASO dispatch after abort cleanup.
    LD   (CP_ASO_OPEN),A    ; No ASO temporary FCB remains owned.
    LD   (CP_MAT_SPOOL_OWNED),A  ; No private spool survives abort cleanup.
    RET                     ; Finish cleanup with the flags cleared.

; Obsolete RAM-image fallback. All active output formats commit through ASO.
;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Write one already-materialized image through the former HEX path.

CP_WRITE_HEX:
    CALL ZTS_CPM_HEX_BEGIN  ; Reset the helper's buffer and status flags.
    LD   HL,CP_TARGET_START  ; Set the first logical address written to HEX.
    LD   (CP_HEX_ADDRESS),HL  ; Save the address used in record headers.
    CALL ZTS_CPM_HEX_SEGMENT  ; Render the image as checksummed HEX records.
    JP   ZTS_CPM_HEX_END    ; Write HEX EOF and final record.

;@ROUTINE IN C,DE OUT A,CARRY,ZERO CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY
; Route final-image writer requests through the index-preserving BDOS wrapper.

ZTS_CPM_FINAL_BDOS:
    JP   CP_BDOS            ; Use the index-preserving wrapper.
ZTS_CPM_FINAL_FCB EQU CP_WORK_FCB  ; FCB used for writing HEX records.
ZTS_CPM_FINAL_DMA EQU CP_SOURCE_CACHE  ; HEX reuses the source-cache page.
ZTS_CPM_FINAL_SOURCE_CURSOR EQU CP_OUTPUT_CURSOR  ; Current byte in the image.
ZTS_CPM_FINAL_REMAINING EQU CP_OUTPUT_REMAINING  ; Image bytes left to render.
ZTS_CPM_FINAL_ADDRESS EQU CP_HEX_ADDRESS  ; Address in the next HEX record.
ZTS_CPM_FINAL_DMA_CURSOR EQU CP_HEX_CURSOR  ; Next byte in the HEX buffer.
ZTS_CPM_FINAL_DMA_COUNT EQU CP_HEX_COUNT  ; Bytes queued for transfer.
ZTS_CPM_FINAL_ERROR EQU CP_HEX_ERROR  ; Sticky record-write error status.
ZTS_CPM_FINAL_SUM EQU CP_HEX_SUM  ; Checksum accumulator for one HEX record.
ZTS_CPM_FINAL_SIZE EQU CP_HEX_SIZE  ; Current HEX record payload length.
ZTS_CPM_FINAL_DATA_LEFT EQU CP_HEX_DATA_LEFT  ; Payload bytes still to render.
;@@Z80_TOOL_SERVICES_CPM22_FINAL_IMAGE@@

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Rebuild the single ordinary output FCB before each new BDOS operation phase.

CP_COPY_OUTPUT_FCB:
    LD   HL,CP_OUTPUT_NAME  ; Read the normalized drive-plus-name record.
    LD   DE,CP_WORK_FCB     ; Select the reusable working FCB as destination.
    LD   BC,12              ; Count the drive byte and eleven name/type bytes.
    LDIR                    ; Copy output name to work FCB.

;@ROUTINE IN DE OUT A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Zero the unused tail of the current CP/M file-control block.

CP_CLEAR_FCB_TAIL:
    XOR  A                  ; Select zero as the byte written to the FCB tail.
    LD   B,24               ; Clear remaining FCB fields.

;@ROUTINE IN A,B,DE OUT B,DE
; Fill B bytes at DE with A while advancing the destination pointer.

CP_CLEAR_WORK_FCB:
    LD   (DE),A             ; Write the fill byte at the current FCB address.
    INC  DE                 ; Advance to the next byte in the control block.
    DJNZ CP_CLEAR_WORK_FCB  ; Repeat until B bytes have been written.
    RET                     ; Return with DE advanced past the cleared region.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's temporary filename from the requested output name.

CP_SET_TEMP_FCB:
    CALL CP_COPY_OUTPUT_FCB  ; Start from the caller's requested output name.
    LD   HL,$2424           ; Form two '$' bytes.
    LD   (CP_WORK_FCB+9),HL  ; Mark the first two extension characters.
    LD   A,'$'              ; Select '$' for the extension's final character.
    LD   (CP_WORK_FCB+11),A  ; Complete the temporary type '$$$'.
    RET                     ; Return the temporary FCB name.

;@ROUTINE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Derive the transaction's backup filename from the requested output name.

CP_SET_BACKUP_FCB:
    CALL CP_COPY_OUTPUT_FCB  ; Start from the caller's requested output name.
    LD   HL,$4142           ; Form 'B' and 'A' in little-endian memory order.
    LD   (CP_WORK_FCB+9),HL  ; Set the first two backup extension characters.
    LD   A,'K'              ; Select the extension's final character.
    LD   (CP_WORK_FCB+11),A  ; Complete the backup type 'BAK'.
    RET                     ; Return the backup filename in the working FCB.

;@ROUTINE IN DE,HL CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Construct a CP/M rename FCB in the input FCB's dead storage. HL addresses
; the old 12-byte name and DE the new 12-byte name.

CP_BUILD_RENAME:
    PUSH HL                 ; Preserve the old drive-plus-name source pointer.
    PUSH DE                 ; Save new-name source pointer.
    LD   DE,CP_RENAME_FCB   ; Select the start of the 36-byte rename FCB.
    XOR  A                  ; Use zero to clear unused FCB fields.
    LD   B,36               ; Count every byte in the rename FCB.
    CALL CP_CLEAR_WORK_FCB  ; Clear it before copying either filename.
    POP  DE                 ; Restore the pointer to the new filename.
    POP  HL                 ; Restore the pointer to the old filename.
    PUSH DE                 ; Save new name during old-name copy.
    LD   DE,CP_RENAME_FCB   ; Place the old name at the start of the FCB.
    LD   BC,12              ; Copy its drive, basename and extension fields.
    LDIR                    ; Fill the rename FCB's old-name field.
    POP  HL                 ; Use new name as LDIR source.
    LD   DE,CP_RENAME_FCB+16  ; Select the new-name field in the FCB.
    LD   BC,12              ; Copy its drive, basename and extension fields.
    LDIR                    ; Fill the rename FCB's new-name field.
    RET                     ; Return the completed rename FCB in workspace.

CP_OUTPUT_CODE_END:

;@ROUTINE IN DE OUT A CLOBBERS BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a dollar-terminated string through CP/M BDOS function 9.

CP_PRINT:
    LD   C,CP_PRINT_FUNCTION  ; Select CP/M dollar-terminated string output.
    JP   CP_BDOS            ; Print the string addressed by DE.

;@ROUTINE IN HL OUT A CLOBBERS B,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the non-space characters of one drive-plus-8.3 filename record.

CP_PRINT_NAME:
    INC  HL                 ; Skip the drive byte and point at the basename.
    LD   B,8                ; Count the eight basename characters.
CP_PRINT_NAME_BYTE:
    LD   A,(HL)             ; Read the next basename character.
    INC  HL                 ; Advance to the next FCB name byte.
    AND  $7F                ; Remove any CP/M filename attribute bit.
    CP   ' '                ; FCB padding marks an unused character position.
    CALL NZ,CP_PUTC         ; Print only non-padding bytes.
    DJNZ CP_PRINT_NAME_BYTE  ; Check the remaining basename positions.
    LD   A,(HL)             ; Inspect the first character of the extension.
    AND  $7F                ; Ignore its read-only attribute bit.
    CP   ' '                ; A blank extension has no visible suffix.
    RET  Z                  ; Return without printing a dot for an empty type.
    LD   A,'.'              ; Select the filename separator.
    CALL CP_PUTC            ; Print the dot before the extension.
    LD   B,3                ; Count the three extension characters.
CP_PRINT_TYPE_BYTE:
    LD   A,(HL)             ; Read the next extension character.
    INC  HL                 ; Advance to the following FCB byte.
    AND  $7F                ; Ignore system and archive attribute bits.
    CP   ' '                ; Skip blank extension positions.
    CALL NZ,CP_PUTC         ; Print a nonblank extension character.
    DJNZ CP_PRINT_TYPE_BYTE  ; Check the remaining extension positions.
    RET                     ; Finish printing the normalized filename.

;@ROUTINE IN A OUT A CLOBBERS CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print one character while preserving the caller's working registers.

CP_PUTC:
    PUSH BC                 ; Save caller's BC pair.
    PUSH DE                 ; Preserve the caller's DE pair.
    PUSH HL                 ; Preserve the caller's HL pair.
    LD   E,A                ; Pass the requested character in E.
    LD   C,2                ; Select CP/M console-output function 2.
    CALL CP_BDOS            ; Write the character to the console.
    POP  HL                 ; Restore the caller's HL pair.
    POP  DE                 ; Restore the caller's DE pair.
    POP  BC                 ; Restore the caller's BC pair.
    RET                     ; Return after the console output attempt.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print A as two uppercase hexadecimal digits.

CP_PRINT_HEX:
    PUSH AF                 ; Preserve the original byte for its low digit.
    RRCA                    ; Begin rotating the high nibble toward bits 0..3.
    RRCA                    ; Move high nibble toward bits 0..3.
    RRCA                    ; Rotate one more position within the byte.
    RRCA                    ; Place the original bits 4..7 in the low nibble.
    CALL CP_PRINT_NIBBLE    ; Print the high hexadecimal digit.
    POP  AF                 ; Restore original byte for low digit.

;@ROUTINE IN A OUT A CLOBBERS BC,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print the low nibble of A as one uppercase hexadecimal digit.

CP_PRINT_NIBBLE:
    AND  $0F                ; Keep only the nibble selected by the caller.
    ADD  A,'0'              ; Convert values 0..9 to ASCII.
    CP   '9'+1              ; Separate decimal from hex letters.
    JR   C,CP_PUTC          ; Send a decimal digit directly to the console.
    ADD  A,7                ; Convert 10..15 to A..F.
    JR   CP_PUTC            ; Print the uppercase hex digit.

;@ROUTINE IN HL OUT A CLOBBERS BC,DE,HL,IX,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Print a one-based 16-bit position in decimal. A wrapped zero can only mean
; 65,536 because no source part exceeds 65,535 bytes.

CP_PRINT_DECIMAL:
    LD   A,H                ; Test whether the counter wrapped to zero.
    OR   L                  ; Both bytes must be zero for 65,536.
    JR   NZ,CP_DECIMAL_START  ; Ordinary positions fit in 16 bits.
    LD   DE,CP_DECIMAL_65536  ; Select the one possible overflow value.
    JP   CP_PRINT           ; Print it and return.
CP_DECIMAL_START:
    LD   IX,CP_DECIMAL_POWERS  ; Start with the ten-thousands place.
    LD   C,5                ; Five places cover every 16-bit value.
    XOR  A                  ; No nonzero digit has been printed yet.
    LD   (CP_DECIMAL_SEEN),A  ; Suppress leading zeroes.
CP_DECIMAL_PLACE:
    LD   E,(IX+0)           ; Load the divisor's low byte.
    LD   D,(IX+1)           ; Load the divisor's high byte.
    LD   B,0                ; Count this place's decimal digit.
CP_DECIMAL_SUBTRACT:
    OR   A                  ; Clear carry before a 16-bit subtraction.
    SBC  HL,DE              ; Remove one place value if it fits.
    JR   C,CP_DECIMAL_DIGIT  ; Borrow means the digit is complete.
    INC  B                  ; Count the successful subtraction.
    JR   CP_DECIMAL_SUBTRACT  ; Try the next unit of this place.
CP_DECIMAL_DIGIT:
    ADD  HL,DE              ; Undo the first subtraction that borrowed.
    LD   A,B                ; Inspect the computed digit.
    OR   A                  ; Nonzero digits begin visible output.
    JR   NZ,CP_DECIMAL_EMIT  ; Print the first nonzero digit.
    LD   A,(CP_DECIMAL_SEEN)  ; Check whether output has begun.
    OR   A                  ; Later zero digits must still be printed.
    JR   NZ,CP_DECIMAL_EMIT  ; Preserve interior and trailing zeroes.
    LD   A,C                ; Is this the units place?
    CP   1                  ; A number must print at least one digit.
    JR   NZ,CP_DECIMAL_NEXT  ; Skip only a leading zero.
CP_DECIMAL_EMIT:
    LD   A,1                ; Mark decimal output as started.
    LD   (CP_DECIMAL_SEEN),A  ; Preserve the mark across console calls.
    LD   A,B                ; Reload the digit for ASCII conversion.
    ADD  A,'0'              ; Convert it to a printable numeral.
    CALL CP_PUTC            ; Send the digit to the CP/M console.
CP_DECIMAL_NEXT:
    INC  IX                 ; Move to the next divisor's low byte.
    INC  IX                 ; Skip the previous divisor's high byte.
    DEC  C                  ; Count down the remaining decimal places.
    JR   NZ,CP_DECIMAL_PLACE  ; Continue through units.
    RET                     ; Finish the decimal position.

CP_ADAPTER_CODE_END:

; Descriptor and FCB workspace retained for the complete command. The 36-byte
; rename FCB overlays the input FCB after all source reads finish.

CP_ADAPTER_WORKSPACE1_START:
CP_DESCRIPTOR:
    DB   1
    DW   CP_PART_DESCRIPTORS
    DW   CP_SYMBOL_START,CP_SYMBOL_END
    DW   CP_PENDING_START,CP_PENDING_END
    DW   CP_TARGET_START,CP_ASO_TARGET_CAPACITY

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
CP_READ_FAILED_TEXT:
    DB ' ','r','e','a','d',' ','f','a','i','l','e','d',13,10,'$'
CP_ASSEMBLY_TEXT: DB 13,10,'A','t','o','m',' ','e','r','r','o','r',' ','$'
CP_NEWLINE_TEXT: DB 13,10,'$'
CP_BYTE_OFFSET_TEXT: DB ':','b','y','t','e',' ','$'
CP_DECIMAL_65536: DB '6','5','5','3','6','$'
CP_DECIMAL_POWERS: DW 10000,1000,100,10,1
CP_USAGE_TEXT:
    DB 13,10,'U','s','a','g','e',':',' ','A','T','O','M',' '  ; Syntax prefix.
    DB '[','S','O','U','R','C','E',' '  ; Optional source.
    DB '[','O','U','T','P','U','T',']',']',13,10,'$'  ; Optional output.
CP_SOURCE_NAME_TEXT:
    DB 13,10,'I','n','v','a','l','i','d',' '  ; Error prefix.
    DB 's','o','u','r','c','e',' ','n','a','m','e',13,10,'$'  ; Source name.
CP_OUTPUT_NAME_TEXT:
    DB 13,10,'I','n','v','a','l','i','d',' '  ; Error prefix.
    DB 'o','u','t','p','u','t',' ','n','a','m','e',13,10,'$'  ; Output name.
CP_NAME_CONFLICT_TEXT:
    DB 13,10,'S','o','u','r','c','e','/'  ; First filename.
    DB 'o','u','t','p','u','t',' '  ; Second filename.
    DB 'c','o','n','f','l','i','c','t',13,10,'$'  ; Conflict suffix.
CP_AUXILIARY_EXISTS_TEXT:
    DB 13,10,'T','e','m','p','/'  ; Temporary file.
    DB 'b','a','c','k','u','p',' '  ; Backup file.
    DB 'f','i','l','e',' ','e','x','i','s','t','s',13,10,'$'
CP_INVALID_INCLUDE_TEXT:
    DB 13,10,'I','n','v','a','l','i','d',' '  ; Error prefix.
    DB '%','I','N','C','L','U','D','E',13,10,'$'  ; Directive name.
CP_BIN_WORD_INCBIN:
    DB 'I','N','C','B','I','N'  ; Exact assembler operation token.
CP_INVALID_INCBIN_TEXT:
    DB 13,10,'I','n','v','a','l','i','d',' '  ; Error prefix.
    DB 'I','N','C','B','I','N',13,10,'$'  ; Native byte-count directive.
CP_BIN_LIMIT_TEXT:
    DB 13,10,'T','o','o',' ','m','a','n','y',' '  ; Error prefix.
    DB 'I','N','C','B','I','N',' ','f','i','l','e','s',13,10,'$'
CP_BIN_CONFLICT_TEXT:
    DB ' ','c','o','n','f','l','i','c','t','s',' '  ; Name collision suffix.
    DB 'w','i','t','h',' ','o','u','t','p','u','t',13,10,'$'
CP_BIN_READ_TEXT:
    DB ' ','b','i','n','a','r','y',' ','r','e','a','d',' '  ; Input failure.
    DB 'f','a','i','l','e','d',13,10,'$'
CP_INVALID_DIRECTIVE_TEXT:
    DB 13,10,'I','n','v','a','l','i','d',' '  ; Error prefix.
    DB 's','o','u','r','c','e',' '  ; Describe the rejected construct.
    DB 'd','i','r','e','c','t','i','v','e',13,10,'$'  ; Finish the message.
CP_INCLUDE_CYCLE_TEXT:
    DB 13,10,'I','n','c','l','u','d','e',' '  ; Include prefix.
    DB 'c','y','c','l','e',13,10,'$'  ; Cycle suffix.
CP_SOURCE_CAPACITY_TEXT:
    DB 13,10,'T','o','o',' ','m','a','n','y',' '  ; Error prefix.
    DB 's','o','u','r','c','e','s',13,10,'$'  ; Source count.
CP_MEMORY_TEXT:
    DB 13,10                ; Start the diagnostic on a new line.
    DB "Insufficient transient memory"  ; Explain the fixed-layout failure.
    DB 13,10,'$'            ; End the line and BDOS string.
CP_INCLUDE_WORD: DB 'I','N','C','L','U','D','E'
CP_ASM_EXTENSION: DB 'A','S','M'
CP_COM_EXTENSION: DB 'C','O','M'
CP_BIN_EXTENSION: DB 'B','I','N'
CP_HEX_EXTENSION: DB 'H','E','X'
CP_ASO_EXTENSION: DB 'A','S','O'
CP_ADAPTER_IMMUTABLE_END:
CP_ADAPTER_WORKSPACE2_START:

; Small execution state. CP_OUTPUT_CURSOR overlays the source-cache key;
; source reads and patches finish before COMMIT publishes the output.

CP_OUTPUT_CURSOR: DW 0
CP_SOURCE_CACHE_KEY EQU CP_OUTPUT_CURSOR
; Replay may overwrite the binary FCB and metadata, so only these live abort
; and diagnostic flags remain in the low resident workspace.
CP_BIN_RESIDENT_ERROR: DB 0
CP_BIN_RESIDENT_OPEN: DB 0
CP_OUTPUT_REMAINING: DW 0
CP_OUTPUT_OPEN: DB 0
CP_BACKED_UP: DB 0
CP_OUTPUT_FORMAT: DB 0
CP_ASO_ACTIVE: DB 0
CP_ASO_OPEN: DB 0
CP_MAT_READER_OPEN: DB 0
CP_ASO_ERROR: DB 0
CP_ASO_STATUS: DB 0
CP_ASO_CLASS: DB 0
CP_ASO_PUT_BYTE: DB 0
CP_ASO_RECORD_COUNT: DB 0
CP_ASO_RUN_COUNT: DB 0
CP_ASO_RUN_ADDRESS: DW 0
CP_ASO_IMAGE_END: DW 0
CP_ASO_IMAGE_TOP: DB 0
CP_ASO_ORIGIN: DW 0
CP_ASO_ADDRESS: DW 0
CP_ASO_VALUE: DW 0
CP_ASO_LENGTH: DB 0
CP_ASO_FLAGS: DB 0
CP_ASO_HIGH_WATER: DW 0
CP_ASO_FINAL_CURSOR: DW 0
CP_ASO_PATCH_END: DW 0
CP_ASO_PATCH_TOP: DB 0
CP_MAT_SPOOL_OWNED: DB 0
CP_HEX_ADDRESS: DW 0
CP_HEX_CURSOR: DW 0
CP_HEX_COUNT: DB 0
CP_HEX_ERROR: DB 0
CP_HEX_SUM: DB 0
CP_HEX_SIZE: DB 0
CP_HEX_DATA_LEFT: DB 0
CP_DIAG_CURSOR: DW 0
CP_DIAG_LINE: DW 0
CP_DIAG_COLUMN: DW 0
CP_DIAG_CR: DB 0
CP_DECIMAL_SEEN: DB 0
CP_ADAPTER_WORKSPACE2_END:
HS_SCEND:
HS_REND:
CP_RESIDENT_END:
;@@ATOM_CPM_ASO_OVERLAY@@
