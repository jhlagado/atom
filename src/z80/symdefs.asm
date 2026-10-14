;==========================================================================
;  Symbols, private scope and pending references
;==========================================================================
;
;  Store exact RADIX-40 symbol records in caller-owned memory. Each record
;  stores the packed name. Lookup compares names exactly, not by hash.
;  Globals grow upward and remain for the build. Current-scope private symbols
;  grow downward from the opposite end and are discarded transactionally when
;  the next global label begins a scope. A separate upward-growing arena holds
;  unresolved patch descriptions until their symbol is defined.
;
;  Principal entries:
;    syReset  initialise the symbol arena
;    syNoRefs  initialise the pending arena
;    syFind   find an exact global or current-scope private name
;    syDecl   define a symbol without changing private scope
;    syLabel  define a global label and begin its private scope
;    syRef    find or create an undefined symbol record
;    syAdd    append one pending reference
;    syPeek   inspect a matching pending reference without removing it
;    syTake   remove a matching pending reference after patch submission
;
;  A symbol record is eight bytes: six packed-name bytes followed by a word.
;  For a defined symbol the word is its value. While unresolved it holds the
;  first-reference source offset until syDecl replaces it. Spare high bits in
;  the final name byte hold signed-equate, defined and private flags. Each
;  pending record is nine bytes: symbol pointer, patch address, kind/anchor,
;  signed addend, full source-part ordinal and the source offset of the
;  reference, so a failed patch can name the instruction that made it.
;
;  Capacity checks occur before cursor publication. Scope changes are
;  transactional: undefined private labels or stale private pending references
;  leave the previous scope intact. The output layer preserves pending
;  atomicity by calling syTake only after PATCH succeeds.

syBeg: ; Begin executable symbol code.

; Symbol-record geometry and packed-name flag bits.

syRecLen    EQU     8                   ; Bytes in one packed symbol record.
syRefLen    EQU     9                   ; Bytes in one pending-reference record.
syKindLo    EQU     $07                 ; Low bits carrying the pending patch kind.
syPart      EQU     6                   ; Pending source-part byte offset.
sySrcOff    EQU     7                   ; Pending reference source-offset word.
syAnchor    EQU     $80                 ; Pending diagnostic-anchor flag.
syKeyLen    EQU     6                   ; Bytes occupied by one packed symbol key.
syValLo     EQU     6                   ; Offset of the symbol value's low byte.
syValHi     EQU     7                   ; Offset of the symbol value's high byte.
syNameLo    EQU     $07                 ; Name bits in final packed byte.
syFSign     EQU     $20                 ; Record flag for a signed equate value.
syFDef      EQU     $40                 ; Record flag for a defined symbol value.
syFPriv     EQU     $80                 ; Record flag for a private symbol key.

; Public status values. Symbol and pending capacity are distinct diagnostics.

syOk        EQU     0                   ; Operation completed successfully.
syMiss      EQU     1                   ; No matching symbol or pending record exists.
syDup       EQU     2                   ; Duplicate defined symbol.
sySymCap    EQU     3                   ; The symbol arena cannot hold another record.
syNoScop    EQU     4                   ; A private name was used before a global scope.
syUndef     EQU     5                   ; Private name undefined at scope close.
syRefCap    EQU     6                   ; The pending arena cannot hold another record.
syInvar     EQU     7                   ; Symbol/pending invariant failure.
syAddDef    EQU     8                   ; Pending append for a defined symbol.
syParts     EQU     9                   ; Retained source-part capacity status.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise symbol arena [HL,DE). Globals begin at HL. Private records begin
; at DE. No private scope exists until the first global label is committed.

syReset: ; Initialise global and private symbol-arena cursors.
    LD   (syBase),HL                    ; Retain the permanent global-record base.
    LD   (syFreeLo),HL                  ; Start with no globals.
    LD   (syLimit),DE                   ; Save the shared arena's exclusive end.
    LD   (syFreeHi),DE                  ; Start with no private records.
    XOR  A                              ; Zero scope state and clear carry.
    LD   (syScoped),A                   ; Mark private scope as inactive.
    RET                                 ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise the independent pending arena [HL,DE).

syNoRefs: ; Initialise the independent pending-reference arena.
    LD   (syRefBeg),HL                  ; Retain the first pending-record address.
    LD   (syRefCur),HL                  ; Start with no pending records.
    LD   (syRefEnd),DE                  ; Retain its exclusive capacity boundary.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Return without touching the symbol arena.

;@ROUTINE IN HL OUT A,CARRY,IX CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Find the exact key at HL. Its private flag selects the private interval
; or the permanent global interval. IX returns the matching eight-byte record.

syFind: ; Find an exact key within its global or current private interval.
    LD   (syInsKey),HL                  ; Preserve the caller's packed search key.
    PUSH HL                             ; Save its first-byte address.
    LD   DE,5                           ; Select the final packed-name byte.
    ADD  HL,DE                          ; Reach the key's private flag.
    BIT  7,(HL)                         ; Choose the search interval.
    POP  HL                             ; Restore the packed key pointer.
    JR   Z,.global                      ; Search the permanent global interval.
    LD   A,(syScoped)                   ; Read the current private-scope state.
    OR   A                              ; Has a global opened a private scope?
    JR   Z,.noScope                     ; No scope means the lookup is invalid.
    LD   IX,(syFreeHi)                  ; Start at the first private record.
    LD   DE,(syLimit)                   ; Stop at the shared arena's exclusive end.
    JR   .recLoop                       ; Enter the common record scan.
.global: ; Establish the permanent global interval.
    LD   IX,(syBase)                    ; Start at the first global record.
    LD   DE,(syFreeLo)                  ; Stop at the end of globals.
.recLoop: ; Compare one eight-byte record per iteration.
    CALL syAtEnd                        ; Has IX reached the interval end?
    JR   Z,.notFound                    ; Exhaustion means the exact key is absent.
    PUSH DE                             ; Save the interval end.
;@EXPECTOUT ZERO
    CALL .keyEq                         ; Compare this record's exact key.
    POP  DE                             ; Restore the scan's exclusive end address.
    JR   Z,.found                       ; Return IX when all key bits match.
    LD   BC,syRecLen                    ; Load the fixed symbol-record stride.
    ADD  IX,BC                          ; Advance to the next record.
    JR   .recLoop                       ; Continue until a match or interval end.
.found: ; IX identifies the exact live record.
    XOR  A                              ; Report lookup success with carry clear.
    RET                                 ; Preserve IX for the caller.
.notFound: ; Report interval exhaustion.
    JP   syErrMis                       ; Return the shared not-found result.
.noScope: ; Report missing private scope.
    JP   syOrphan                       ; Return private-name-without-scope.

;@ROUTINE IN IX OUT ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,B,CARRY,A
; Compare five full name bytes and three name bits in byte five. syFind
; has already selected the global or private search interval. The upper bits
; contain record flags and do not participate in identity.

.keyEq: ; Compare packed identity while excluding symbol flag bits.
    PUSH IX                             ; Transfer record address to DE.
    POP  DE                             ; DE now scans the record's packed key.
    LD   HL,(syInsKey)                  ; HL scans the caller's packed search key.
    LD   B,5                            ; Compare the five flag-free bytes first.
.keyLoop: ; Compare one full packed-name byte.
    LD   A,(DE)                         ; Load the candidate byte.
    CP   (HL)                           ; Compare it with the search key byte.
    RET  NZ                             ; Return nonzero immediately on a mismatch.
    INC  DE                             ; Advance the candidate pointer.
    INC  HL                             ; Advance the search-key pointer.
    DJNZ .keyLoop                       ; Repeat through the five complete bytes.
    LD   A,(DE)                         ; Read final key byte and flags.
    XOR  (HL)                           ; Find differences from the search key.
    AND  syNameLo                       ; Ignore flags. Zero means exact key.
    RET                                 ; Return comparison in zero flag.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Define key HL as value DE without changing scope. An undefined record is
; completed in place so pending pointers remain valid. An absent key is
; inserted. An already defined key is a duplicate.

syDecl: ; Complete or insert a definition without advancing private scope.
    LD   (syInsKey),HL                  ; Save key across lookup and insertion.
    LD   (syInsVal),DE                  ; Save the final sixteen-bit symbol value.
;@EXPECTOUT A,CARRY,IX
    CALL syFind                         ; Look for an existing exact record.
    JR   C,.missing                     ; Handle absence or private-scope failure.
    BIT  6,(IX+5)                       ; Is the existing record already defined?
    JR   NZ,.dup                        ; A second definition is always an error.
    LD   DE,(syInsVal)                  ; Reload value for the placeholder.
    LD   (IX+syValLo),E                 ; Store its low byte.
    LD   (IX+syValHi),D                 ; Store its high byte.
    LD   A,(IX+5)                       ; Read final key byte and flags.
    OR   syFDef                         ; Mark the record as defined.
    LD   (IX+5),A                       ; Publish the completed record in place.
    XOR  A                              ; Report successful definition.
    RET                                 ; Keep IX on the completed record.
.dup: ; Return the shared duplicate-definition error.
    JP   syErrDup                       ; Preserve the established public status.
.missing: ; Interpret the failed lookup status.
    CP   syMiss                         ; Was the key simply absent?
    JR   Z,.store                       ; Insert a new defined record.
    SCF                                 ; Restore carry after CP.
    RET                                 ; Propagate the lookup status.
.store: ; Prepare a newly defined record.
    LD   A,syFDef                       ; Supply the defined flag.
;@EXPECTOUT A,CARRY,IX
    JR   syStore                        ; Insert saved key/value.

;@ROUTINE IN HL OUT A,CARRY,IX,B CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Find or create an undefined record for key HL. B=0 means existing.
; B=1 reports a newly inserted record whose value is initially zero.

syRef: ; Find or insert an undefined record for a forward reference.
    LD   (syInsKey),HL                  ; Save key across lookup and insertion.
;@EXPECTOUT A,CARRY,IX
    CALL syFind                         ; Search global or current-private records.
    JR   C,.missing                     ; Interpret an absent key or scope failure.
    LD   B,0                            ; Report an existing record.
    RET                                 ; Return IX on the existing record.
.missing: ; Interpret the lookup failure status.
    CP   syMiss                         ; Was the key absent?
    JR   Z,.store                       ; Create a placeholder if absent.
    SCF                                 ; Restore carry after CP.
    RET                                 ; Propagate private-scope failure.
.store: ; Initialise the placeholder value and flags.
    XOR  A                              ; Placeholder flags and value are zero.
    LD   (syInsVal),A                   ; Clear the saved value's low byte.
    LD   (syInsVal+1),A                 ; Clear the saved value's high byte.
;@EXPECTOUT A,CARRY,IX
    CALL syStore                        ; Insert the undefined record.
    RET  C                              ; Propagate symbol-capacity failure.
    LD   B,1                            ; Report a new record.
    RET                                 ; Return IX on the inserted placeholder.

;@ROUTINE IN A OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Insert syInsKey with flags A and value syInsVal. Check room for one
; complete record before moving either publication cursor.

syStore: ; Preflight and insert the saved key, flags and value.
    LD   (syInsFlg),A                   ; Preserve the caller's definition flags.
    LD   HL,(syFreeHi)                  ; Private start is the high bound.
    LD   DE,(syFreeLo)                  ; Global end is the low bound.
    LD   B,syRecLen                     ; Require one complete eight-byte record.
    CALL syRoom                         ; Prove the shared gap can hold it.
    JR   C,.noCap                       ; Fail before moving either cursor.
.hasCap: ; Either region has room to grow.

; Global records extend syFreeLo upward. Private records move syFreeHi downward.

    LD   HL,(syInsKey)                  ; Inspect the saved packed key.
    LD   DE,5                           ; Select final byte with private flag.
    ADD  HL,DE                          ; Advance to that flag byte.
    BIT  7,(HL)                         ; Choose global or private allocation.
    JR   NZ,.private                    ; Allocate downward for a private record.
    LD   IX,(syFreeLo)                  ; Allocate at the old global end.
    PUSH IX                             ; Transfer that address to HL.
    POP  HL                             ; HL now holds the new record's start.
    LD   DE,syRecLen                    ; Load the global-record stride.
    ADD  HL,DE                          ; Form the next free global address.
    LD   (syFreeLo),HL                  ; Publish the extended global interval.
    JR   .fill                          ; Fill the allocated record.
.private: ; Allocate one record below the private cursor.
    LD   HL,(syFreeHi)                  ; Load the first current private address.
    LD   DE,syRecLen                    ; Load the fixed record size.
    OR   A                              ; Clear carry before downward subtraction.
    SBC  HL,DE                          ; Form the new private-region start.
    LD   (syFreeHi),HL                  ; Publish the expanded private interval.
    PUSH HL                             ; Move the new record address into IX.
    POP  IX                             ; IX addresses the private record.
.fill: ; Populate the already allocated record.

; Commit the exact key, merge definition flags and store the value.

    LD   HL,(syInsKey)                  ; Point at the exact six-byte packed key.
    PUSH IX                             ; Transfer record address to DE.
    POP  DE                             ; DE now points at the first record byte.
    LD   BC,syKeyLen                    ; Copy six key bytes and private flag.
    LDIR                                ; Copy key to the allocated record.
    LD   A,(syInsFlg)                   ; Reload requested definition/sign flags.
    OR   (IX+5)                         ; Keep the key's private flag.
    LD   (IX+5),A                       ; Publish the record flags.
    LD   DE,(syInsVal)                  ; Reload the saved sixteen-bit value.
    LD   (IX+syValLo),E                 ; Store its low byte after the key.
    LD   (IX+syValHi),D                 ; Store its high byte last.
    XOR  A                              ; Report insertion success.
    RET                                 ; Return IX on the new live record.
.noCap: ; Return symbol-arena exhaustion.
    LD   A,sySymCap                     ; Select the symbol-capacity status.
    SCF                                 ; Mark insertion as failed.
    RET                                 ; Leave both publication cursors unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate and discard the current private scope, then leave a fresh active
; private scope. syOpen is the commit-only half used after proof.

syClose: ; Validate scope eviction before committing a fresh private scope.
    CALL syDropOk                       ; Check whether private records may go.
    RET  C                              ; Keep old scope on failure.
syOpen: ; Commit a fresh empty private scope.
    LD   HL,(syLimit)                   ; Load the top of the shared symbol arena.
    LD   (syFreeHi),HL                  ; Discard current private records.
    LD   A,1                            ; Construct the active-scope state.
    LD   (syScoped),A                   ; Publish that a global scope now exists.
    XOR  A                              ; Report successful scope advancement.
    RET                                 ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Define a global label and open its private scope atomically. Undefined
; globals are completed in place. Missing globals need one record after
; the old private region is reclaimed.

syLabel: ; Define a global label and advance private scope atomically.
    LD   (syInsKey),HL                  ; Preserve the packed global key.
    LD   (syInsVal),DE                  ; Preserve the label address.
    LD   DE,5                           ; Select key byte with private flag.
    ADD  HL,DE                          ; Advance to that final packed-name byte.
    BIT  7,(HL)                         ; Is this key private?
    JR   NZ,syOrphan                    ; Reject before changing scope.
    LD   HL,(syInsKey)                  ; Restore the packed key for lookup.
    CALL syFind                         ; Find any existing global placeholder.
    JR   C,.missing                     ; Handle a failed lookup.
    BIT  6,(IX+5)                       ; Is the existing global already defined?
    JR   NZ,syErrDup                    ; Reject a duplicate label.
    XOR  A                              ; Existing record needs no allocation.
    LD   (syInsFlg),A                   ; Save the existing-placeholder case.
    JR   .validate                      ; Validate before committing value.
.missing: ; Handle a missing or failed global lookup.
    CP   syMiss                         ; Is the key simply absent?
    RET  NZ                             ; Propagate any other status in A.
    LD   A,1                            ; Request a new global record.
    LD   (syInsFlg),A                   ; Preserve the allocation decision.
.validate: ; Preflight eviction and allocation.

; First check that private names and pending pointers can be evicted.

    CALL syDropOk                       ; Check all old private records.
    RET  C                              ; Leave label and scope unchanged.
    LD   A,(syInsFlg)                   ; Reload the new-record decision.
    OR   A                              ; Zero means placeholder exists.
    JR   Z,.commit                      ; Complete it without allocation.

; A missing global needs capacity in the post-eviction
; arena, where syFreeHi will equal the arena end.

    LD   HL,(syLimit)                   ; Model cursor after eviction.
    LD   DE,(syFreeLo)                  ; Global end is the low bound.
    LD   B,syRecLen                     ; Require one complete global record.
    CALL syRoom                         ; Check capacity without committing.
    JR   C,syErrCap                     ; Keep old scope on exhaustion.
.commit: ; Commit scope and global label.
    LD   HL,(syLimit)                   ; Load the empty-private-region cursor.
    LD   (syFreeHi),HL                  ; Discard the old private records.
    LD   A,1                            ; Construct active-scope state.
    LD   (syScoped),A                   ; Activate the new private scope.
    LD   HL,(syInsKey)                  ; Restore the label key for definition.
    LD   DE,(syInsVal)                  ; Restore its final address.
    CALL syDecl                         ; Complete or insert the global record.
    RET  NC                             ; Return if commit succeeds.

; All failures were preflighted, so a commit-time declaration error is an
; internal invariant violation.

    LD   A,syInvar                      ; Report a violated commit invariant.
    SCF                                 ; Mark the transaction as failed.
    RET                                 ; Scope has already changed.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return private-name-without-global-scope.

syOrphan: ; Report a private name used before any global label.
    LD   A,syNoScop                     ; Select the private-scope status.
    SCF                                 ; Mark the symbol operation as failed.
    RET                                 ; Leave all symbol state untouched.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return duplicate-definition status.

syErrDup: ; Report a second definition of an already defined key.
    LD   A,syDup                        ; Select the duplicate-symbol code.
    SCF                                 ; Mark the definition as failed.
    RET                                 ; Leave the existing record unchanged.
syErrCap: ; Return global-record capacity failure.
    LD   A,sySymCap                     ; Select symbol-arena exhaustion.
    SCF                                 ; Mark transaction failure.
    RET                                 ; Preserve the previous private scope.
