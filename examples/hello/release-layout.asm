ORG 4000H                ; Place the example at address 4000H.

COUNT EQU 1               ; Select one pass through the delay loop.
MESSAGE:                  ; Mark the start of the message bytes.
    DB "ATOM",0           ; Store a zero-terminated message.
