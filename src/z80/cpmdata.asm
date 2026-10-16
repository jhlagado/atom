; Descriptor and FCB workspace retained for the complete command. The 36-byte
; rename FCB overlays the input FCB after all source reads finish.

cpFcbBeg: ; Beginning of descriptor and FCB writable storage.
cpDesc: ; Twelve-byte native build descriptor.
    DW   cpSymBeg,cpSymEnd                                          ; Half-open caller symbol-arena bounds.
    DW   cpRefBeg,cpRefEnd                                          ; Half-open pending-reference arena bounds.
    DW   cpTpa,asoCap                                               ; CP/M target origin and maximum byte capacity.

pubFcb: ; Rename FCB overlaid after source reads finish.
srcFcb: ; Source file FCB before the publication phase.
    DB   0,'I','N','P','U','T',' ',' ',' ','A','S','M'              ; Initial source identity with current drive and ASM extension.
    DS   24                                                         ; Zero-initialised mutable source-FCB control fields.
cpFcb: ; Independent working FCB for output and reserved names.
    DB   0,'O','U','T','P','U','T',' ',' ','$','$','$'              ; Initial reserved temporary output identity.
    DS   24                                                         ; Zero-initialised mutable output-FCB control fields.
pubName: ; Retained requested output drive and 8.3 identity.
    DB   0,'O','U','T','P','U','T',' ',' ','C','O','M'              ; Initial requested output identity before argument parsing.
cpFcbEnd: ; Exclusive end of descriptor and FCB storage.

cpImmBeg: ; Beginning of immutable console text and selectors.
msgDone:   DB      ' ','w','r','i','t','t','e','n',13,10,'$'        ; Completion suffix printed after successful publication.
msgRead: ; Source-open or source-read diagnostic suffix.
    DB   ' ','r','e','a','d',' ','f','a','i','l','e','d',13,10,'$'  ; Source-read failure text followed by CRLF and BDOS terminator.
msgCrlf:   DB      13,10,'$'                                        ; Console line break terminated for BDOS function 9.
msgByte:   DB      ':','b','y','t','e',' ','$'                      ; Prefix distinguishing a raw byte-offset fallback.
msgWrap:   DB      '6','5','5','3','6','$'                          ; Decimal spelling of the wrapped position 65,536.
cpTens:    DW      10000,1000,100,10,1                              ; Descending decimal place values for position printing.
msgHelp: ; Compact command syntax for help and argument errors.
    DB   13,10,'U','s','a','g','e',':',' ','A','T','O','M',' '      ; Syntax prefix.
    DB   '[','S','O','U','R','C','E',' '                            ; Optional source.
    DB   '[','O','U','T','P','U','T',' '                            ; Optional output.
    DB   '[','S','Y','M','B','O','L','S',']',']',']',13,10,'$'      ; Optional symbol file.
msgSrc: ; Invalid source-filename diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   's','o','u','r','c','e',' ','n','a','m','e',13,10,'$'      ; Source name.
msgOut: ; Invalid output-filename diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   'o','u','t','p','u','t',' ','n','a','m','e',13,10,'$'      ; Output name.
msgDup: ; Source and output filename-conflict diagnostic.
    DB   13,10,'S','o','u','r','c','e','/'                          ; First filename.
    DB   'o','u','t','p','u','t',' '                                ; Second filename.
    DB   'c','o','n','f','l','i','c','t',13,10,'$'                  ; Conflict suffix.
msgBusy: ; Reserved work-file collision diagnostic.
    DB   " exists: erase it first",13,10,'$'                        ; Leftover work file.
msgInc: ; Malformed INCLUDE diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   '%','I','N','C','L','U','D','E',13,10,'$'                  ; Directive name.
msgDir: ; Unsupported or malformed preprocessor directive diagnostic.
    DB   13,10,'I','n','v','a','l','i','d',' '                      ; Error prefix.
    DB   's','o','u','r','c','e',' '                                ; Describe the rejected construct.
    DB   'd','i','r','e','c','t','i','v','e',13,10,'$'              ; Finish the message.
msgLoop: ; Include dependency-cycle diagnostic.
    DB   13,10,'I','n','c','l','u','d','e',' '                      ; Include prefix.
    DB   'c','y','c','l','e',13,10,'$'                              ; Cycle suffix.
msgDeep: ; Include nesting diagnostic.
    DB   13,10,'I','n','c','l','u','d','e','s',' '                  ; Include prefix.
    DB   'n','e','s','t','e','d',' ','t','o','o',' '                ; Nesting.
    DB   'd','e','e','p','l','y',13,10,'$'                          ; Finish the message.
msgCap: ; Source-part capacity diagnostic.
    DB   13,10,'T','o','o',' ','m','a','n','y',' '                  ; Error prefix.
    DB   's','o','u','r','c','e','s',13,10,'$'                      ; Source count.
msgMem: ; Insufficient transient-memory diagnostic.
    DB   13,10                                                      ; Start the diagnostic on a new line.
    DB   "Insufficient transient memory"                            ; Explain the fixed-layout failure.
    DB   13,10,'$'                                                  ; End the line and BDOS string.
cmdAsm:    DB      'A','S','M'                                      ; Default source extension.
cmdCom:    DB      'C','O','M'                                      ; COM output extension selector.
cmdBin:    DB      'B','I','N'                                      ; Raw binary output extension selector.
cmdHex:    DB      'H','E','X'                                      ; Intel HEX output extension selector.
cmdSym:    DB      'S','Y','M'                                      ; Symbol file extension.
cmdAso:    DB      'A','S','O'                                      ; Serialised-operation output extension selector.
