; Resident CP/M adapter state after the message table.

cpImmEnd: ; Exclusive end of immutable console text and selectors.
cpRunBeg: ; Beginning of scalar resident execution state.

; Small execution state. pubPos overlays the source-cache key;
; source reads and patches finish before COMMIT publishes the output.

pubPos:    DW      0                                                ; Current output-window or HEX input cursor.
srcKey      EQU     pubPos                                          ; Alias for source-record cache key before final rendering.
; Replay may overwrite the binary FCB and metadata, so only these live abort
; and diagnostic flags remain in the low resident workspace.
binFault:   DB      0                                               ; Binary-read failure flag retained across replay overlays.
binOwns:   DB      0                                                ; Binary-FCB ownership flag retained across replay overlays.
; The binary reader names these two live flags, which must survive replay.
binErr      EQU     binFault                    ; Alias for the low resident binary-failure flag.
binHeld     EQU     binOwns                     ; Alias for the low resident binary-FCB ownership flag.
pubLeft:   DW      0                                                ; Logical bytes remaining for final output rendering.
pubOpen:   DB      0                                                ; Nonzero while the final-output temporary FCB is open.
pubKept:   DB      0                                                ; Nonzero after old output moves to the backup name.
symOn:     DB      0                                                ; Symbol file: zero none, one asked for, two written as $$S.
symName:   DS      12                                               ; Requested symbol file's drive and 8.3 name.
cpNameTo:  DW      cpPutCh                                          ; Routine that receives decoded symbol-name characters.
pubKind:   DB      0                                                ; Output selector: zero COM, one BIN, two HEX, three ASO.
asoOn:     DB      0                                                ; Nonzero while operation-spool dispatch is active.
asoOpen:   DB      0                                                ; Nonzero while the writer owns an open spool FCB.
matOpen:   DB      0                                                ; Nonzero while replay owns an open spool reader.
asoErr:    DB      0                                                ; Sticky operation-spool failure status.
asoStat:   DB      0                                                ; BDOS or validation status retained for the caller.
asoSpace:   DB      0                                               ; Address-space class staged for PATCH validation.
asoByte:   DB      0                                                ; Serialised byte staged during record indexing.
asoInRec:   DB      0                                               ; Bytes queued in the physical output record.
asoInRun:   DB      0                                               ; Bytes buffered in the current IMAGE run.
asoBase:   DW      0                                                ; Absolute start address of the pending IMAGE run.
asoImEnd:   DW      0                                               ; Greatest accepted IMAGE exclusive-end low word.
asoImTop:   DB      0                                               ; Nonzero when accepted IMAGE extent reaches $10000.
asoOrg:    DW      0                                                ; Target origin written into the ASO header.
asoAddr:   DW      0                                                ; Absolute IMAGE or PATCH address being checked.
asoVal:    DW      0                                                ; One-byte or little-endian word replacement value.
asoLen:    DB      0                                                ; PATCH payload length of one or two bytes.
asoFlags:   DB      0                                               ; Retained cursor and high-water endpoint flags.
asoHigh:   DW      0                                                ; COMMIT high-water endpoint low word.
asoLast:   DW      0                                                ; COMMIT final cursor low word.
asoStop:   DW      0                                                ; Computed PATCH exclusive-end low word.
asoTop:   DB      0                                                 ; Nonzero when a computed PATCH end is $10000.
matOwns:   DB      0                                                ; Nonzero while the reserved $$B name contains a spool.
hexAddr:   DW      0                                                ; Target address for the next Intel HEX record.
hexPtr:    DW      0                                                ; Next free byte in the HEX transfer buffer.
hexCnt:    DB      0                                                ; Text bytes queued for a physical CP/M write.
hexErr:    DB      0                                                ; Sticky HEX physical-record write status.
hexSum:    DB      0                                                ; Checksum accumulator for one Intel HEX record.
hexSize:   DB      0                                                ; Payload length in the current Intel HEX record.
hexLeft:   DB      0                                                ; Payload bytes remaining in the current HEX record.
errPos:    DW      0                                                ; Zero-based source offset during diagnostic counting.
errLine:   DW      0                                                ; One-based source line or wrapped 65,536 sentinel.
errCol:    DW      0                                                ; One-based byte column or wrapped 65,536 sentinel.
errSawCr:     DB      0                                             ; Nonzero when the preceding diagnostic-count byte was CR.
cpSeen:    DB      0                                                ; Nonzero after decimal printing emits its first digit.
cpRunEnd: ; Exclusive end of scalar resident execution state.
hsEnd: ; Exclusive end of output-service resident storage.
hsResEnd: ; Exclusive end of host-service resident extent.
cpResEnd: ; Exclusive end of the resident CP/M adapter.
