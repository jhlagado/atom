; ATOM FOR CP/M 2.2. Build it on CP/M with:
;
;     ATOM CPM22 NEWATOM.COM
;
; The CP/M adapter wraps the platform-neutral core. Atom itself makes no
; filesystem calls. The adapter does five jobs around it:
;   1. Parse the command tail and choose COM, BIN or Intel HEX output.
;   2. Find leading %INCLUDE directives and order the source parts.
;   3. Serve source bytes from CP/M files through a 128-byte cache.
;   4. Spool Atom's IMAGE and PATCH operations to NAME.$$B, then replay
;      them into the output through a fixed window in the TPA.
;   5. Publish the finished output through the $$$ and $$B work files.
;
; Each source part is a half-open range [0,length). tkRead maps a part
; ordinal to its file, opens it and supplies the byte.
;
; The COM file holds the code, through the spool and replay code at its end.
; The writable areas begin at cpWork and are set up before use, so they take
; addresses in the TPA but no bytes in the file. cpmmap.asm shows the layout.

    %INCLUDE "cpmorg.asm"               ; Place the COM entry jump at $0100.
    %INCLUDE "core.asm"                 ; Assemble the platform-neutral core.
    %INCLUDE "cpmmap.asm"               ; Define the fixed memory map.
    %INCLUDE "cpmentry.asm"             ; Check memory, run one command and exit.
    %INCLUDE "cpmcmd.asm"               ; Parse the command tail and validate CP/M filenames.
    %INCLUDE "cpmsrc.asm"               ; Open source files and read cached bytes.
    %INCLUDE "cpminc.asm"               ; Find includes and order the source parts.
    %INCLUDE "cpprep.asm"               ; Apply %DEFINE and %IF to source bytes.
    %INCLUDE "cpmbin.asm"               ; Find, validate and stream INCBIN data.
    %INCLUDE "cpmpub.asm"               ; Bind output services and publish or roll back files.
    %INCLUDE "cpmerr.asm"               ; Locate and print diagnostics.
    %INCLUDE "cpmcon.asm"               ; Print to the console.
    %INCLUDE "cpmdata.asm"              ; FCBs, console text and selectors.
    %INCLUDE "cpmsg.asm"                ; Diagnostic message table.
    %INCLUDE "cpmstate.asm"             ; Resident state that survives replay.
    %INCLUDE "spool.asm"                ; Spool and replay code.
