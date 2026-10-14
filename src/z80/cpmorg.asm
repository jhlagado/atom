; CP/M loads a COM file at $0100 and enters it there. The first sixteen bytes
; jump to the adapter and keep the core at $0110.

    ORG  $0100                          ; Start at the CP/M transient base.
    JP   cpEntry                        ; Enter the CP/M adapter.
    DS   13                             ; Start the core at $0110.
