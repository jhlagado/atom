; Print a short message on the CP/M console, then return to CP/M.

        ORG 100H                       ; CP/M loads transient commands at 0100H.

START:                                 ; Entry point at CP/M's 0100H load address.
        LD DE,MESSAGE                  ; Point DE at the dollar-terminated text.
        LD C,9                         ; Select the BDOS print-string service.
        CALL 5                         ; Enter the CP/M BDOS.
        RET                            ; Return to the command processor.

MESSAGE:                               ; String printed by BDOS function 9.
        DB "HELLO FROM ATOM",13,10,"$" ; End with '$' for BDOS function 9.
