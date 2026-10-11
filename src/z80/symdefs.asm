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
;    SY_RESET  initialise the symbol arena
;    SY_PINIT  initialise the pending arena
;    SY_FIND   find an exact global or current-scope private name
;    SY_DECL   define a symbol without changing private scope
;    SY_LABEL  define a global label and begin its private scope
;    SY_REF    find or create an undefined symbol record
;    SY_ADD    append one pending reference
;    SY_PEEK   inspect a matching pending reference without removing it
;    SY_TAKE   remove a matching pending reference after patch submission
;
;  A symbol record is eight bytes: six packed-name bytes followed by a word.
;  For a defined symbol the word is its value. While unresolved it holds the
;  first-reference source offset until SY_DECL replaces it. Spare high bits in
;  the final name byte hold signed-equate, defined and private flags. Each
;  pending record is nine bytes: symbol pointer, patch address, kind/anchor,
;  signed addend, full source-part ordinal and the source offset of the
;  reference, so a failed patch can name the instruction that made it.
;
;  Capacity checks occur before cursor publication. Scope changes are
;  transactional: undefined private labels or stale private pending references
;  leave the previous scope intact. The output layer preserves pending
;  atomicity by calling SY_TAKE only after PATCH succeeds.

SY_CBEG: ; Begin executable symbol code.

; Symbol-record geometry and packed-name flag bits.

SY_RECB     EQU     8                   ; Bytes in one packed symbol record.
SY_PENDB    EQU     9                   ; Bytes in one pending-reference record.
SY_KMASK    EQU     $07                 ; Low bits carrying the pending patch kind.
SY_PART     EQU     6                   ; Pending source-part byte offset.
SY_POFF     EQU     7                   ; Pending reference source-offset word.
SY_DANCH    EQU     $80                 ; Pending diagnostic-anchor flag.
SY_NAMEB    EQU     6                   ; Bytes occupied by one packed symbol key.
SY_VALLO    EQU     6                   ; Offset of the symbol value's low byte.
SY_VALHI    EQU     7                   ; Offset of the symbol value's high byte.
SY_NMASK    EQU     $07                 ; Name bits in final packed byte.
SY_FSIGN    EQU     $20                 ; Record flag for a signed equate value.
SY_FDEF     EQU     $40                 ; Record flag for a defined symbol value.
SY_FPRIV    EQU     $80                 ; Record flag for a private symbol key.

; Public status values. Symbol and pending capacity are distinct diagnostics.

SY_SOK      EQU     0                   ; Operation completed successfully.
SY_SMISS    EQU     1                   ; No matching symbol or pending record exists.
SY_SDUP     EQU     2                   ; Duplicate defined symbol.
SY_SSCAP    EQU     3                   ; The symbol arena cannot hold another record.
SY_SNOSC    EQU     4                   ; A private name was used before a global scope.
SY_SUNDF    EQU     5                   ; Private name undefined at scope close.
SY_SPCAP    EQU     6                   ; The pending arena cannot hold another record.
SY_SPINV    EQU     7                   ; Symbol/pending invariant failure.
SY_SADEF    EQU     8                   ; Pending append for a defined symbol.
SY_SPART    EQU     9                   ; Retained source-part capacity status.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise symbol arena [HL,DE). Globals begin at HL. Private records begin
; at DE. No private scope exists until the first global label is committed.

SY_RESET: ; Initialise global and private symbol-arena cursors.
    LD   (SY_ABASE),HL                  ; Retain the permanent global-record base.
    LD   (SY_GEND),HL                   ; Start with no globals.
    LD   (SY_AEND),DE                   ; Save the shared arena's exclusive end.
    LD   (SY_LBEG),DE                   ; Start with no private records.
    XOR  A                              ; Zero scope state and clear carry.
    LD   (SY_SCOPE),A                   ; Mark private scope as inactive.
    RET                                 ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise the independent pending arena [HL,DE).

SY_PINIT: ; Initialise the independent pending-reference arena.
    LD   (SY_PBASE),HL                  ; Retain the first pending-record address.
    LD   (SY_NEXT),HL                   ; Start with no pending records.
    LD   (SY_PTOP),DE                   ; Retain its exclusive capacity boundary.
    XOR  A                              ; Report success with carry clear.
    RET                                 ; Return without touching the symbol arena.

;@ROUTINE IN B,HL,DE OUT A,DE,CARRY CLOBBERS BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack a source symbol at HL/B into the caller's six-byte key at DE. A leading
; period selects private scope but is not part of the packed name, so both
; global and private payloads retain up to eight characters.

EN_PSYM: ; Pack a source name and mark private identity when prefixed by a dot.
    LD   A,B                            ; Inspect the complete source-name length.
    OR   A                              ; An empty name cannot form a symbol.
    JR   Z,.INVALID                     ; Reject it before writing the destination.
    LD   A,(HL)                         ; Read the first source character.
    CP   $2E                            ; Does '.' mark a private name?
    JR   NZ,.GLOBAL                     ; Pack an unprefixed global name.
    DEC  B                              ; Exclude the private marker.
    JR   Z,.INVALID                     ; Reject a period with no following name.
    LD   A,B                            ; Check private payload length.
    CP   9                              ; Eight characters is the limit.
    JR   NC,.INVALID                    ; Reject a longer name before writing.
    INC  HL                             ; Skip the period before RADIX-40 packing.
;@EXPECTOUT DE,CARRY
    CALL EN_R40PK                       ; Pack the private name into six bytes.
    JR   C,.INVALID                     ; Report invalid name syntax.
    PUSH DE                             ; Save the end of the packed key.
    DEC  DE                             ; Address the final packed-name byte.

; RADIX-40's final word uses only eleven bits. Mark private identity in
; the final byte without changing the packed name.

    LD   A,(DE)                         ; Read the byte with spare flag bits.
    OR   SY_FPRIV                       ; Mark the packed key as private.
    LD   (DE),A                         ; Set the key's private flag.
    POP  DE                             ; Restore the caller's end-of-key pointer.
    XOR  A                              ; Report successful private-name packing.
    RET                                 ; Return with carry clear.
.GLOBAL: ; Pack a global name exactly as supplied.
;@EXPECTOUT DE,CARRY
    CALL EN_R40PK                       ; Pack and case-fold the global key.
    JR   C,.INVALID                     ; Reject invalid name syntax.
    XOR  A                              ; Report successful global-name packing.
    RET                                 ; Return the packed-key end in DE.
.INVALID: ; Return the private/public key syntax failure.
    XOR  A                              ; Construct status one compactly.
    INC  A                              ; A now identifies invalid symbol input.
    SCF                                 ; Mark the packing operation as failed.
    RET                                 ; Leave publication to the caller.

;@ROUTINE IN HL OUT A,CARRY,IX CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Find the exact key at HL. Its private flag selects the private interval
; or the permanent global interval. IX returns the matching eight-byte record.

SY_FIND: ; Find an exact key within its global or current private interval.
    LD   (SY_OKEY),HL                   ; Preserve the caller's packed search key.
    PUSH HL                             ; Save its first-byte address.
    LD   DE,5                           ; Select the final packed-name byte.
    ADD  HL,DE                          ; Reach the key's private flag.
    BIT  7,(HL)                         ; Choose the search interval.
    POP  HL                             ; Restore the packed key pointer.
    JR   Z,.GLOBAL                      ; Search the permanent global interval.
    LD   A,(SY_SCOPE)                   ; Read the current private-scope state.
    OR   A                              ; Has a global opened a private scope?
    JR   Z,.NOSCOPE                     ; No scope means the lookup is invalid.
    LD   IX,(SY_LBEG)                   ; Start at the first private record.
    LD   DE,(SY_AEND)                   ; Stop at the shared arena's exclusive end.
    JR   .RECLOOP                       ; Enter the common record scan.
.GLOBAL: ; Establish the permanent global interval.
    LD   IX,(SY_ABASE)                  ; Start at the first global record.
    LD   DE,(SY_GEND)                   ; Stop at the end of globals.
.RECLOOP: ; Compare one eight-byte record per iteration.
    CALL AT_IXEND                       ; Has IX reached the interval end?
    JR   Z,.NOTFOUND                    ; Exhaustion means the exact key is absent.
    PUSH DE                             ; Save the interval end.
;@EXPECTOUT ZERO
    CALL .KEYEQ                         ; Compare this record's exact key.
    POP  DE                             ; Restore the scan's exclusive end address.
    JR   Z,.FOUND                       ; Return IX when all key bits match.
    LD   BC,SY_RECB                     ; Load the fixed symbol-record stride.
    ADD  IX,BC                          ; Advance to the next record.
    JR   .RECLOOP                       ; Continue until a match or interval end.
.FOUND: ; IX identifies the exact live record.
    XOR  A                              ; Report lookup success with carry clear.
    RET                                 ; Preserve IX for the caller.
.NOTFOUND: ; Report interval exhaustion.
    JP   SY_EMISS                       ; Return the shared not-found result.
.NOSCOPE: ; Report missing private scope.
    JP   SY_ENOSC                       ; Return private-name-without-scope.

;@ROUTINE IN IX OUT ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,B,CARRY,A
; Compare five full name bytes and three name bits in byte five. SY_FIND
; has already selected the global or private search interval. The upper bits
; contain record flags and do not participate in identity.

.KEYEQ: ; Compare packed identity while excluding symbol flag bits.
    PUSH IX                             ; Transfer record address to DE.
    POP  DE                             ; DE now scans the record's packed key.
    LD   HL,(SY_OKEY)                   ; HL scans the caller's packed search key.
    LD   B,5                            ; Compare the five flag-free bytes first.
.KEYLOOP: ; Compare one full packed-name byte.
    LD   A,(DE)                         ; Load the candidate byte.
    CP   (HL)                           ; Compare it with the search key byte.
    RET  NZ                             ; Return nonzero immediately on a mismatch.
    INC  DE                             ; Advance the candidate pointer.
    INC  HL                             ; Advance the search-key pointer.
    DJNZ .KEYLOOP                       ; Repeat through the five complete bytes.
    LD   A,(DE)                         ; Read final key byte and flags.
    XOR  (HL)                           ; Find differences from the search key.
    AND  SY_NMASK                       ; Ignore flags. Zero means exact key.
    RET                                 ; Return comparison in zero flag.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Define key HL as value DE without changing scope. An undefined record is
; completed in place so pending pointers remain valid. An absent key is
; inserted. An already defined key is a duplicate.

SY_DECL: ; Complete or insert a definition without advancing private scope.
    LD   (SY_OKEY),HL                   ; Save key across lookup and insertion.
    LD   (SY_OVAL),DE                   ; Save the final sixteen-bit symbol value.
;@EXPECTOUT A,CARRY,IX
    CALL SY_FIND                        ; Look for an existing exact record.
    JR   C,.MISSING                     ; Handle absence or private-scope failure.
    BIT  6,(IX+5)                       ; Is the existing record already defined?
    JR   NZ,.DUP                        ; A second definition is always an error.
    LD   DE,(SY_OVAL)                   ; Reload value for the placeholder.
    LD   (IX+SY_VALLO),E                ; Store its low byte.
    LD   (IX+SY_VALHI),D                ; Store its high byte.
    LD   A,(IX+5)                       ; Read final key byte and flags.
    OR   SY_FDEF                        ; Mark the record as defined.
    LD   (IX+5),A                       ; Publish the completed record in place.
    XOR  A                              ; Report successful definition.
    RET                                 ; Keep IX on the completed record.
.DUP: ; Return the shared duplicate-definition error.
    JP   SY_EDUP                        ; Preserve the established public status.
.MISSING: ; Interpret the failed lookup status.
    CP   SY_SMISS                       ; Was the key simply absent?
    JR   Z,.STORE                       ; Insert a new defined record.
    SCF                                 ; Restore carry after CP.
    RET                                 ; Propagate the lookup status.
.STORE: ; Prepare a newly defined record.
    LD   A,SY_FDEF                      ; Supply the defined flag.
;@EXPECTOUT A,CARRY,IX
    JR   SY_STORE                       ; Insert saved key/value.

;@ROUTINE IN HL OUT A,CARRY,IX,B CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Find or create an undefined record for key HL. B=0 means existing.
; B=1 reports a newly inserted record whose value is initially zero.

SY_REF: ; Find or insert an undefined record for a forward reference.
    LD   (SY_OKEY),HL                   ; Save key across lookup and insertion.
;@EXPECTOUT A,CARRY,IX
    CALL SY_FIND                        ; Search global or current-private records.
    JR   C,.MISSING                     ; Interpret an absent key or scope failure.
    LD   B,0                            ; Report an existing record.
    RET                                 ; Return IX on the existing record.
.MISSING: ; Interpret the lookup failure status.
    CP   SY_SMISS                       ; Was the key absent?
    JR   Z,.STORE                       ; Create a placeholder if absent.
    SCF                                 ; Restore carry after CP.
    RET                                 ; Propagate private-scope failure.
.STORE: ; Initialise the placeholder value and flags.
    XOR  A                              ; Placeholder flags and value are zero.
    LD   (SY_OVAL),A                    ; Clear the saved value's low byte.
    LD   (SY_OVAL+1),A                  ; Clear the saved value's high byte.
;@EXPECTOUT A,CARRY,IX
    CALL SY_STORE                       ; Insert the undefined record.
    RET  C                              ; Propagate symbol-capacity failure.
    LD   B,1                            ; Report a new record.
    RET                                 ; Return IX on the inserted placeholder.

;@ROUTINE IN A OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Insert SY_OKEY with flags A and value SY_OVAL. Check room for one
; complete record before moving either publication cursor.

SY_STORE: ; Preflight and insert the saved key, flags and value.
    LD   (SY_OFLAG),A                   ; Preserve the caller's definition flags.
    LD   HL,(SY_LBEG)                   ; Private start is the high bound.
    LD   DE,(SY_GEND)                   ; Global end is the low bound.
    LD   B,SY_RECB                      ; Require one complete eight-byte record.
    CALL AT_ROOM                        ; Prove the shared gap can hold it.
    JR   C,.NOCAP                       ; Fail before moving either cursor.
.HASCAP: ; Either region has room to grow.

; Global records extend SY_GEND upward. Private records move SY_LBEG downward.

    LD   HL,(SY_OKEY)                   ; Inspect the saved packed key.
    LD   DE,5                           ; Select final byte with private flag.
    ADD  HL,DE                          ; Advance to that flag byte.
    BIT  7,(HL)                         ; Choose global or private allocation.
    JR   NZ,.PRIVATE                    ; Allocate downward for a private record.
    LD   IX,(SY_GEND)                   ; Allocate at the old global end.
    PUSH IX                             ; Transfer that address to HL.
    POP  HL                             ; HL now holds the new record's start.
    LD   DE,SY_RECB                     ; Load the global-record stride.
    ADD  HL,DE                          ; Form the next free global address.
    LD   (SY_GEND),HL                   ; Publish the extended global interval.
    JR   .FILL                          ; Fill the allocated record.
.PRIVATE: ; Allocate one record below the private cursor.
    LD   HL,(SY_LBEG)                   ; Load the first current private address.
    LD   DE,SY_RECB                     ; Load the fixed record size.
    OR   A                              ; Clear carry before downward subtraction.
    SBC  HL,DE                          ; Form the new private-region start.
    LD   (SY_LBEG),HL                   ; Publish the expanded private interval.
    PUSH HL                             ; Move the new record address into IX.
    POP  IX                             ; IX addresses the private record.
.FILL: ; Populate the already allocated record.

; Commit the exact key, merge definition flags and store the value.

    LD   HL,(SY_OKEY)                   ; Point at the exact six-byte packed key.
    PUSH IX                             ; Transfer record address to DE.
    POP  DE                             ; DE now points at the first record byte.
    LD   BC,SY_NAMEB                    ; Copy six key bytes and private flag.
    LDIR                                ; Copy key to the allocated record.
    LD   A,(SY_OFLAG)                   ; Reload requested definition/sign flags.
    OR   (IX+5)                         ; Keep the key's private flag.
    LD   (IX+5),A                       ; Publish the record flags.
    LD   DE,(SY_OVAL)                   ; Reload the saved sixteen-bit value.
    LD   (IX+SY_VALLO),E                ; Store its low byte after the key.
    LD   (IX+SY_VALHI),D                ; Store its high byte last.
    XOR  A                              ; Report insertion success.
    RET                                 ; Return IX on the new live record.
.NOCAP: ; Return symbol-arena exhaustion.
    LD   A,SY_SSCAP                     ; Select the symbol-capacity status.
    SCF                                 ; Mark insertion as failed.
    RET                                 ; Leave both publication cursors unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate and discard the current private scope, then leave a fresh active
; private scope. SY_CSCOP is the commit-only half used after proof.

SY_ASCOP: ; Validate scope eviction before committing a fresh private scope.
    CALL SY_VSCOP                       ; Check whether private records may go.
    RET  C                              ; Keep old scope on failure.
SY_CSCOP: ; Commit a fresh empty private scope.
    LD   HL,(SY_AEND)                   ; Load the top of the shared symbol arena.
    LD   (SY_LBEG),HL                   ; Discard current private records.
    LD   A,1                            ; Construct the active-scope state.
    LD   (SY_SCOPE),A                   ; Publish that a global scope now exists.
    XOR  A                              ; Report successful scope advancement.
    RET                                 ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Define a global label and open its private scope atomically. Undefined
; globals are completed in place. Missing globals need one record after
; the old private region is reclaimed.

SY_LABEL: ; Define a global label and advance private scope atomically.
    LD   (SY_OKEY),HL                   ; Preserve the packed global key.
    LD   (SY_OVAL),DE                   ; Preserve the label address.
    LD   DE,5                           ; Select key byte with private flag.
    ADD  HL,DE                          ; Advance to that final packed-name byte.
    BIT  7,(HL)                         ; Is this key private?
    JR   NZ,SY_ENOSC                    ; Reject before changing scope.
    LD   HL,(SY_OKEY)                   ; Restore the packed key for lookup.
    CALL SY_FIND                        ; Find any existing global placeholder.
    JR   C,.MISSING                     ; Handle a failed lookup.
    BIT  6,(IX+5)                       ; Is the existing global already defined?
    JR   NZ,SY_EDUP                     ; Reject a duplicate label.
    XOR  A                              ; Existing record needs no allocation.
    LD   (SY_OFLAG),A                   ; Save the existing-placeholder case.
    JR   .VALIDATE                      ; Validate before committing value.
.MISSING: ; Handle a missing or failed global lookup.
    CP   SY_SMISS                       ; Is the key simply absent?
    RET  NZ                             ; Propagate any other status in A.
    LD   A,1                            ; Request a new global record.
    LD   (SY_OFLAG),A                   ; Preserve the allocation decision.
.VALIDATE: ; Preflight eviction and allocation.

; First check that private names and pending pointers can be evicted.

    CALL SY_VSCOP                       ; Check all old private records.
    RET  C                              ; Leave label and scope unchanged.
    LD   A,(SY_OFLAG)                   ; Reload the new-record decision.
    OR   A                              ; Zero means placeholder exists.
    JR   Z,.COMMIT                      ; Complete it without allocation.

; A missing global needs capacity in the post-eviction
; arena, where SY_LBEG will equal the arena end.

    LD   HL,(SY_AEND)                   ; Model cursor after eviction.
    LD   DE,(SY_GEND)                   ; Global end is the low bound.
    LD   B,SY_RECB                      ; Require one complete global record.
    CALL AT_ROOM                        ; Check capacity without committing.
    JR   C,SY_ECAP                      ; Keep old scope on exhaustion.
.COMMIT: ; Commit scope and global label.
    LD   HL,(SY_AEND)                   ; Load the empty-private-region cursor.
    LD   (SY_LBEG),HL                   ; Discard the old private records.
    LD   A,1                            ; Construct active-scope state.
    LD   (SY_SCOPE),A                   ; Activate the new private scope.
    LD   HL,(SY_OKEY)                   ; Restore the label key for definition.
    LD   DE,(SY_OVAL)                   ; Restore its final address.
    CALL SY_DECL                        ; Complete or insert the global record.
    RET  NC                             ; Return if commit succeeds.

; All failures were preflighted, so a commit-time declaration error is an
; internal invariant violation.

    LD   A,SY_SPINV                     ; Report a violated commit invariant.
    SCF                                 ; Mark the transaction as failed.
    RET                                 ; Scope has already changed.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return private-name-without-global-scope.

SY_ENOSC: ; Report a private name used before any global label.
    LD   A,SY_SNOSC                     ; Select the private-scope status.
    SCF                                 ; Mark the symbol operation as failed.
    RET                                 ; Leave all symbol state untouched.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return duplicate-definition status.

SY_EDUP: ; Report a second definition of an already defined key.
    LD   A,SY_SDUP                      ; Select the duplicate-symbol code.
    SCF                                 ; Mark the definition as failed.
    RET                                 ; Leave the existing record unchanged.
SY_ECAP: ; Return global-record capacity failure.
    LD   A,SY_SSCAP                     ; Select symbol-arena exhaustion.
    SCF                                 ; Mark transaction failure.
    RET                                 ; Preserve the previous private scope.
