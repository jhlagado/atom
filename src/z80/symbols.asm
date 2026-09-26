;==========================================================================
;  Symbols, private scope and pending references
;==========================================================================
;
;  Store exact RADIX-40 symbol records in caller-owned memory. Each record
;  stores the packed name; lookup compares names exactly, not by hash.
;  Globals grow upward and remain for the build. Current-scope private symbols
;  grow downward from the opposite end and are discarded transactionally when
;  the next global label begins a scope. A separate upward-growing arena holds
;  unresolved patch descriptions until their symbol is defined.
;
;  Principal entries:
;    SY_RESET  initialise the symbol arena
;    SY_RESE1  initialise the pending arena
;    SY_FIND   find an exact global or current-scope private name
;    SY_DECL   define a symbol without changing private scope
;    SY_DGLAB  define a global label and begin its private scope
;    SY_REF    find or create an undefined symbol record
;    SY_ADD    append one pending reference
;    SY_PEEK   inspect a matching pending reference without removing it
;    SY_TAKE   remove a matching pending reference after patch submission
;
;  A symbol record is eight bytes: six packed-name bytes followed by a word.
;  For a defined symbol the word is its value; while unresolved it holds the
;  first-reference source offset until SY_DECL replaces it. Spare high bits in
;  the final name byte hold signed-equate, defined and private flags. Each
;  pending record is seven bytes: symbol pointer, patch address, kind/anchor,
;  signed addend and full source-part ordinal.
;
;  Capacity checks occur before cursor publication. Scope changes are
;  transactional: undefined private labels or stale private pending references
;  leave the previous scope intact. The output layer preserves pending
;  atomicity by calling SY_TAKE only after PATCH succeeds.

SY_CBEG:                       ; Begin executable symbol code.

; Symbol-record geometry and packed-name flag bits.

SY_RECB EQU 8                  ; Bytes in one packed symbol record.
SY_RECB1 EQU 7                 ; Bytes in one pending-reference record.
SY_KMASK EQU $07               ; Low bits carrying the pending patch kind.
SY_PMASK EQU 6                 ; Pending source-part byte offset.
SY_DANCH EQU $80               ; Pending diagnostic-anchor flag.
SY_NAMEB EQU 6                 ; Bytes occupied by one packed symbol key.
SY_VALLO EQU 6                 ; Offset of the symbol value's low byte.
SY_VALHI EQU 7                 ; Offset of the symbol value's high byte.
SY_NHMAS EQU $07               ; Name bits in final packed byte.
SY_FSIGN EQU $20               ; Record flag for a signed equate value.
SY_FDEFI EQU $40               ; Record flag for a defined symbol value.
SY_FPRIV EQU $80               ; Record flag for a private symbol key.

; Public status values. Symbol and pending capacity are distinct diagnostics.

SY_SOK EQU 0                   ; Operation completed successfully.
SY_SNFOU EQU 1                ; No matching symbol or pending record exists.
SY_SDUPL EQU 2                ; Duplicate defined symbol.
SY_SSCAP EQU 3                ; The symbol arena cannot hold another record.
SY_SPNSC EQU 4                ; A private name was used before a global scope.
SY_SUPRI EQU 5                 ; Private name undefined at scope close.
SY_SPCAP EQU 6                ; The pending arena cannot hold another record.
SY_SPINV EQU 7                ; Symbol/pending invariant failure.
SY_SADEF EQU 8                ; Pending append for a defined symbol.
SY_SPCA1 EQU 9                ; Retained source-part capacity status.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise symbol arena [HL,DE). Globals begin at HL; private records begin
; at DE. No private scope exists until the first global label is committed.

SY_RESET:
    LD   (SY_ABASE),HL             ; Retain the permanent global-record base.
    LD   (SY_GEND),HL              ; Start with no globals.
    LD   (SY_AEND),DE              ; Save the shared arena's exclusive end.
    LD   (SY_LBEG),DE              ; Start with no private records.
    XOR  A                         ; Zero scope state and clear carry.
    LD   (SY_SACTI),A              ; Mark private scope as inactive.
    RET                            ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
; Initialise the independent pending arena [HL,DE).

SY_RESE1:
    LD   (SY_ABAS1),HL             ; Retain the first pending-record address.
    LD   (SY_NEXT),HL              ; Start with no pending records.
    LD   (SY_AEND1),DE             ; Retain its exclusive capacity boundary.
    XOR  A                         ; Report success with carry clear.
    RET                            ; Return without touching the symbol arena.

;@ROUTINE IN B,HL,DE OUT A,DE,CARRY CLOBBERS BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
; Pack a source symbol at HL/B into the caller's six-byte key at DE. A leading
; period selects private scope but is not part of the packed name, so both
; global and private payloads retain up to eight characters.

EN_PSYM:
    LD   A,B                       ; Inspect the complete source-name length.
    OR   A                         ; An empty name cannot form a symbol.
    JR   Z,.PSINVALI               ; Reject it before writing the destination.
    LD   A,(HL)                    ; Read the first source character.
    CP   $2E                       ; Does '.' mark a private name?
    JR   NZ,.PSGLBL                ; Pack an unprefixed global name.
    DEC  B                         ; Exclude the private marker.
    JR   Z,.PSINVALI               ; Reject a period with no following name.
    LD   A,B                       ; Check private payload length.
    CP   9                         ; Eight characters is the limit.
    JR   NC,.PSINVALI              ; Reject a longer name before writing.
    INC  HL                        ; Skip the period before RADIX-40 packing.
;@EXPECTOUT DE,CARRY
    CALL EN_R40PK                  ; Pack the private name into six bytes.
    JR   C,.PSINVALI               ; Report invalid name syntax.
    PUSH DE                        ; Save the end of the packed key.
    DEC  DE                        ; Address the final packed-name byte.

; RADIX-40's final word uses only eleven bits. Mark private identity in
; the final byte without changing the packed name.

    LD   A,(DE)                    ; Read the byte with spare flag bits.
    OR   SY_FPRIV                  ; Mark the packed key as private.
    LD   (DE),A                    ; Set the key's private flag.
    POP  DE                        ; Restore the caller's end-of-key pointer.
    XOR  A                         ; Report successful private-name packing.
    RET                            ; Return with carry clear.
.PSGLBL:                       ; Pack a global name exactly as supplied.
;@EXPECTOUT DE,CARRY
    CALL EN_R40PK                  ; Pack and case-fold the global key.
    JR   C,.PSINVALI               ; Reject invalid name syntax.
    XOR  A                         ; Report successful global-name packing.
    RET                            ; Return the packed-key end in DE.
.PSINVALI:                     ; Return the private/public key syntax failure.
    XOR  A                         ; Construct status one compactly.
    INC  A                         ; A now identifies invalid symbol input.
    SCF                            ; Mark the packing operation as failed.
    RET                            ; Leave publication to the caller.

;@ROUTINE IN HL OUT A,CARRY,IX CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
; Find the exact key at HL. Its private flag selects the private interval
; or the permanent global interval. IX returns the matching eight-byte record.

SY_FIND:
    LD   (SY_OKEY),HL              ; Preserve the caller's packed search key.
    PUSH HL                        ; Save its first-byte address.
    LD   DE,5                      ; Select the final packed-name byte.
    ADD  HL,DE                    ; Reach the key's private flag.
    BIT  7,(HL)                    ; Choose the search interval.
    POP  HL                        ; Restore the packed key pointer.
    JR   Z,.FINDGLBL               ; Search the permanent global interval.
    LD   A,(SY_SACTI)              ; Read the current private-scope state.
    OR   A                         ; Has a global opened a private scope?
    JR   Z,.PNSCOPE                ; No scope means the lookup is invalid.
    LD   IX,(SY_LBEG)              ; Start at the first private record.
    LD   DE,(SY_AEND)              ; Stop at the shared arena's exclusive end.
    JR   .FINDLOOP                ; Enter the common record scan.
.FINDGLBL:                     ; Establish the permanent global interval.
    LD   IX,(SY_ABASE)             ; Start at the first global record.
    LD   DE,(SY_GEND)              ; Stop at the end of globals.
.FINDLOOP:                     ; Compare one eight-byte record per iteration.
    CALL AT_CIDE                   ; Has IX reached the interval end?
    JR   Z,.NOTFOUND               ; Exhaustion means the exact key is absent.
    PUSH DE                        ; Save the interval end.
;@EXPECTOUT ZERO
    CALL SY_KEQUA                  ; Compare this record's exact key.
    POP  DE                        ; Restore the scan's exclusive end address.
    JR   Z,.FOUND                  ; Return IX when all key bits match.
    LD   BC,SY_RECB                ; Load the fixed symbol-record stride.
    ADD  IX,BC                    ; Advance to the next record.
    JR   .FINDLOOP                ; Continue until a match or interval end.
.FOUND:                        ; IX identifies the exact live record.
    XOR  A                         ; Report lookup success with carry clear.
    RET                            ; Preserve IX for the caller.
.NOTFOUND:                     ; Report interval exhaustion.
    JP   SY_NFRET                  ; Return the shared not-found result.
.PNSCOPE:                      ; Report missing private scope.
    JP   SY_GLPRI                  ; Return private-name-without-scope.

;@ROUTINE IN IX OUT ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,B,CARRY,A
; Compare five full name bytes and three name bits in byte five. SY_FIND
; has already selected the global or private search interval; the upper bits
; contain record flags and do not participate in identity.

SY_KEQUA:
    PUSH IX                        ; Transfer record address to DE.
    POP  DE                        ; DE now scans the record's packed key.
    LD   HL,(SY_OKEY)              ; HL scans the caller's packed search key.
    LD   B,5                       ; Compare the five flag-free bytes first.
.KELOOP:                       ; Compare one full packed-name byte.
    LD   A,(DE)                    ; Load the candidate byte.
    CP   (HL)                      ; Compare it with the search key byte.
    RET  NZ                        ; Return nonzero immediately on a mismatch.
    INC  DE                        ; Advance the candidate pointer.
    INC  HL                        ; Advance the search-key pointer.
    DJNZ .KELOOP                  ; Repeat through the five complete bytes.
    LD   A,(DE)                    ; Read final key byte and flags.
    XOR  (HL)                      ; Find differences from the search key.
    AND  SY_NHMAS                  ; Ignore flags; zero means exact key.
    RET                            ; Return comparison in zero flag.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Define key HL as value DE without changing scope. An undefined record is
; completed in place so pending pointers remain valid; an absent key is
; inserted; an already defined key is a duplicate.

SY_DECL:
    LD   (SY_OKEY),HL              ; Save key across lookup and insertion.
    LD   (SY_OVAL),DE              ; Save the final sixteen-bit symbol value.
;@EXPECTOUT A,CARRY,IX
    CALL SY_FIND                   ; Look for an existing exact record.
    JR   C,.DMISSING               ; Handle absence or private-scope failure.
    BIT  6,(IX+5)                  ; Is the existing record already defined?
    JR   NZ,.DUPLICAT              ; A second definition is always an error.
    LD   DE,(SY_OVAL)              ; Reload value for the placeholder.
    LD   (IX+SY_VALLO),E           ; Store its low byte.
    LD   (IX+SY_VALHI),D           ; Store its high byte.
    LD   A,(IX+5)                  ; Read final key byte and flags.
    OR   SY_FDEFI                  ; Mark the record as defined.
    LD   (IX+5),A                  ; Publish the completed record in place.
    XOR  A                         ; Report successful definition.
    RET                            ; Keep IX on the completed record.
.DUPLICAT:                     ; Return the shared duplicate-definition error.
    JP   SY_GLDUP                  ; Preserve the established public status.
.DMISSING:                     ; Interpret the failed lookup status.
    CP   SY_SNFOU                  ; Was the key simply absent?
    JR   Z,.DINSERT                ; Insert a new defined record.
    SCF                            ; Restore carry after CP.
    RET                            ; Propagate the lookup status.
.DINSERT:                      ; Prepare a newly defined record.
    LD   A,SY_FDEFI                ; Supply the defined flag.
;@EXPECTOUT A,CARRY,IX
    JR   SY_INSER                 ; Insert saved key/value.

;@ROUTINE IN HL OUT A,CARRY,IX,B CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Find or create an undefined record for key HL. B=0 means existing;
; B=1 reports a newly inserted record whose value is initially zero.

SY_REF:
    LD   (SY_OKEY),HL              ; Save key across lookup and insertion.
;@EXPECTOUT A,CARRY,IX
    CALL SY_FIND                   ; Search global or current-private records.
    JR   C,.RMISSING               ; Interpret an absent key or scope failure.
    LD   B,0                       ; Report an existing record.
    RET                            ; Return IX on the existing record.
.RMISSING:                     ; Interpret the lookup failure status.
    CP   SY_SNFOU                  ; Was the key absent?
    JR   Z,.RINSERT                ; Create a placeholder if absent.
    SCF                            ; Restore carry after CP.
    RET                            ; Propagate private-scope failure.
.RINSERT:                      ; Initialize the placeholder value and flags.
    XOR  A                         ; Placeholder flags and value are zero.
    LD   (SY_OVAL),A               ; Clear the saved value's low byte.
    LD   (SY_OVAL+1),A             ; Clear the saved value's high byte.
;@EXPECTOUT A,CARRY,IX
    CALL SY_INSER                  ; Insert the undefined record.
    RET  C                         ; Propagate symbol-capacity failure.
    LD   B,1                       ; Report a new record.
    RET                            ; Return IX on the inserted placeholder.

;@ROUTINE IN A OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Insert SY_OKEY with flags A and value SY_OVAL. Check room for one
; complete record before moving either publication cursor.

SY_INSER:
    LD   (SY_OFLAG),A              ; Preserve the caller's definition flags.
    LD   HL,(SY_LBEG)              ; Private start is the high bound.
    LD   DE,(SY_GEND)              ; Global end is the low bound.
    LD   B,SY_RECB                 ; Require one complete eight-byte record.
    CALL AT_RHCAP                  ; Prove the shared gap can hold it.
    JR   C,.NOCAP                  ; Fail before moving either cursor.
.HASCAP:                       ; Either region has room to grow.

; Global records extend SY_GEND upward. Private records move SY_LBEG downward.

    LD   HL,(SY_OKEY)              ; Inspect the saved packed key.
    LD   DE,5                      ; Select final byte with private flag.
    ADD  HL,DE                    ; Advance to that flag byte.
    BIT  7,(HL)                    ; Choose global or private allocation.
    JR   NZ,.IPRIVATE              ; Allocate downward for a private record.
    LD   IX,(SY_GEND)              ; Allocate at the old global end.
    PUSH IX                        ; Transfer that address to HL.
    POP  HL                        ; HL now holds the new record's start.
    LD   DE,SY_RECB                ; Load the global-record stride.
    ADD  HL,DE                    ; Form the next free global address.
    LD   (SY_GEND),HL              ; Publish the extended global interval.
    JR   .CINSERT                 ; Fill the allocated record.
.IPRIVATE:                     ; Allocate one record below the private cursor.
    LD   HL,(SY_LBEG)              ; Load the first current private address.
    LD   DE,SY_RECB                ; Load the fixed record size.
    OR   A                         ; Clear carry before downward subtraction.
    SBC  HL,DE                    ; Form the new private-region start.
    LD   (SY_LBEG),HL              ; Publish the expanded private interval.
    PUSH HL                        ; Move the new record address into IX.
    POP  IX                        ; IX addresses the private record.
.CINSERT:                      ; Populate the already allocated record.

; Commit the exact key, merge definition flags and store the value.

    LD   HL,(SY_OKEY)              ; Point at the exact six-byte packed key.
    PUSH IX                        ; Transfer record address to DE.
    POP  DE                        ; DE now points at the first record byte.
    LD   BC,SY_NAMEB               ; Copy six key bytes and private flag.
    LDIR                           ; Copy key to the allocated record.
    LD   A,(SY_OFLAG)              ; Reload requested definition/sign flags.
    OR   (IX+5)                    ; Keep the key's private flag.
    LD   (IX+5),A                  ; Publish the record flags.
    LD   DE,(SY_OVAL)              ; Reload the saved sixteen-bit value.
    LD   (IX+SY_VALLO),E           ; Store its low byte after the key.
    LD   (IX+SY_VALHI),D           ; Store its high byte last.
    XOR  A                         ; Report insertion success.
    RET                            ; Return IX on the new live record.
.NOCAP:                        ; Return symbol-arena exhaustion.
    LD   A,SY_SSCAP                ; Select the symbol-capacity status.
    SCF                            ; Mark insertion as failed.
    RET                            ; Leave both publication cursors unchanged.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Validate and discard the current private scope, then leave a fresh active
; private scope. SY_CSCOP is the commit-only half used after proof.

SY_ASCOP:
    CALL SY_VSCOP                  ; Check whether private records may go.
    RET  C                         ; Keep old scope on failure.
SY_CSCOP:                      ; Commit a fresh empty private scope.
    LD   HL,(SY_AEND)              ; Load the top of the shared symbol arena.
    LD   (SY_LBEG),HL              ; Discard current private records.
    LD   A,1                       ; Construct the active-scope state.
    LD   (SY_SACTI),A              ; Publish that a global scope now exists.
    XOR  A                         ; Report successful scope advancement.
    RET                            ; Return with carry clear.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
; Define a global label and open its private scope atomically. Undefined
; globals are completed in place; missing globals need one record after
; the old private region is reclaimed.

SY_DGLAB:
    LD   (SY_OKEY),HL              ; Preserve the packed global key.
    LD   (SY_OVAL),DE              ; Preserve the label address.
    LD   DE,5                      ; Select key byte with private flag.
    ADD  HL,DE                    ; Advance to that final packed-name byte.
    BIT  7,(HL)                    ; Is this key private?
    JR   NZ,SY_GLPRI               ; Reject before changing scope.
    LD   HL,(SY_OKEY)              ; Restore the packed key for lookup.
    CALL SY_FIND                   ; Find any existing global placeholder.
    JR   C,SY_GLMIS                ; Handle a failed lookup.
    BIT  6,(IX+5)                  ; Is the existing global already defined?
    JR   NZ,SY_GLDUP               ; Reject a duplicate label.
    XOR  A                         ; Existing record needs no allocation.
    LD   (SY_OFLAG),A              ; Save the existing-placeholder case.
    JR   SY_GLVAL                 ; Validate before committing value.
SY_GLMIS:                      ; Handle a missing or failed global lookup.
    CP   SY_SNFOU                  ; Is the key simply absent?
    RET  NZ                        ; Propagate any other status in A.
    LD   A,1                       ; Request a new global record.
    LD   (SY_OFLAG),A              ; Preserve the allocation decision.
SY_GLVAL:                      ; Preflight eviction and allocation.

; First check that private names and pending pointers can be evicted.

    CALL SY_VSCOP                  ; Check all old private records.
    RET  C                         ; Leave label and scope unchanged.
    LD   A,(SY_OFLAG)              ; Reload the new-record decision.
    OR   A                         ; Zero means placeholder exists.
    JR   Z,SY_GLCMT                ; Complete it without allocation.

; A missing global needs capacity in the post-eviction
; arena, where SY_LBEG will equal the arena end.

    LD   HL,(SY_AEND)              ; Model cursor after eviction.
    LD   DE,(SY_GEND)              ; Global end is the low bound.
    LD   B,SY_RECB                 ; Require one complete global record.
    CALL AT_RHCAP                  ; Check capacity without committing.
    JR   C,SY_GLCAP                ; Keep old scope on exhaustion.
SY_GLCMT:                      ; Commit scope and global label.
    LD   HL,(SY_AEND)              ; Load the empty-private-region cursor.
    LD   (SY_LBEG),HL              ; Discard the old private records.
    LD   A,1                       ; Construct active-scope state.
    LD   (SY_SACTI),A              ; Activate the new private scope.
    LD   HL,(SY_OKEY)              ; Restore the label key for definition.
    LD   DE,(SY_OVAL)              ; Restore its final address.
    CALL SY_DECL                   ; Complete or insert the global record.
    RET  NC                        ; Return if commit succeeds.

; All failures were preflighted, so a commit-time declaration error is an
; internal invariant violation.

    LD   A,SY_SPINV                ; Report a violated commit invariant.
    SCF                            ; Mark the transaction as failed.
    RET                            ; Scope has already changed.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return private-name-without-global-scope.

SY_GLPRI:
    LD   A,SY_SPNSC                ; Select the private-scope status.
    SCF                            ; Mark the symbol operation as failed.
    RET                            ; Leave all symbol state untouched.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return duplicate-definition status.

SY_GLDUP:
    LD   A,SY_SDUPL                ; Select the duplicate-symbol code.
    SCF                            ; Mark the definition as failed.
    RET                            ; Leave the existing record unchanged.
SY_GLCAP:                      ; Return global-record capacity failure.
    LD   A,SY_SSCAP                ; Select symbol-arena exhaustion.
    SCF                            ; Mark transaction failure.
    RET                            ; Preserve the previous private scope.

;@ROUTINE OUT A,CARRY CLOBBERS IX,DE,BC,ZERO,SIGN,PARITY,HALFCARRY,HL
; Check whether private scope may be discarded. Every private record must
; be defined, and no pending record may still point into private storage. The
; second check also catches stale references to defined private names.

SY_VSCOP:
    LD   IX,(SY_LBEG)              ; Start at first private record.
    LD   DE,(SY_AEND)              ; Stop at the arena's exclusive end.
SY_VSLOO:                      ; Check one private record per iteration.
    CALL AT_CIDE                   ; Reached the interval end?
    JR   Z,SY_VPEND                ; Then inspect pending pointers.
    BIT  6,(IX+5)                  ; Is this private symbol defined?
    JR   Z,SY_VUNDE                ; Keep undefined private names.
    LD   BC,SY_RECB                ; Load the symbol-record stride.
    ADD  IX,BC                    ; Advance to the next private record.
    JR   SY_VSLOO                 ; Continue through the current scope.
SY_VPEND:                      ; Validate every live pending symbol pointer.

; Walk the pending arena and inspect the private flag through each saved
; symbol pointer.

    LD   IX,(SY_ABAS1)             ; Start at the first pending record.
    LD   DE,(SY_NEXT)              ; Stop at the pending publication cursor.
SY_VPLOO:                      ; Inspect one pending symbol pointer.
    CALL AT_CIDE                   ; Reached the pending scan end?
    JR   Z,SY_VOK                  ; No private references remain.
    LD   L,(IX+0)                  ; Load the saved symbol pointer low byte.
    LD   H,(IX+1)                  ; Load its high byte.
    PUSH DE                        ; Preserve the pending scan end.
    LD   DE,5                      ; Select pointed record's flag byte.
    ADD  HL,DE                    ; Advance to its private flag.
    BIT  7,(HL)                    ; Does it point to a private name?
    POP  DE                        ; Restore the pending scan end.
    JR   NZ,SY_VINVA               ; Private pointer forbids eviction.
    LD   BC,SY_RECB1               ; Load the pending-record stride.
    ADD  IX,BC                    ; Advance to the next pending record.
    JR   SY_VPLOO                 ; Continue through the complete live arena.
SY_VOK:                        ; Current private scope is safe to discard.
    XOR  A                         ; Report safe eviction.
    RET                            ; Publish no state changes.
SY_VUNDE:                      ; Return undefined-private-at-scope-close.
    LD   A,SY_SUPRI                ; Select the undefined-private status.
    SCF                            ; Mark validation as failed.
    RET                            ; Preserve the complete private scope.
SY_VINVA:                      ; Report stale private pending pointer.
    LD   A,SY_SPINV                ; Select the internal pending-state status.
    SCF                            ; Mark validation as failed.
    RET                            ; Preserve both symbol and pending arenas.

;@ROUTINE IN A,IX,DE,BC OUT A,CARRY CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,ZERO
; Append one seven-byte pending record. Inputs are IX=symbol, DE=logical patch
; address, B=kind/anchor, C=signed addend and A=source-part ordinal. Defined
; symbols are rejected because their value should have been emitted directly.

SY_ADD:
    BIT  6,(IX+5)                  ; Is this symbol already defined?
    JR   NZ,.ADEFINED              ; Reject that inconsistent request.
    PUSH AF                        ; Save source-part ordinal.
    PUSH BC                        ; Preserve kind/anchor and signed addend.
    PUSH DE                        ; Preserve the logical patch address.
    LD   HL,(SY_AEND1)             ; Pending end is high bound.
    LD   DE,(SY_NEXT)              ; Publication cursor is low bound.
    LD   B,SY_RECB1                ; Require one complete seven-byte record.
    CALL AT_RHCAP                  ; Check capacity before writing.
    JR   C,.NCSTACK                ; Unwind saved inputs on exhaustion.
.HASCAP:                       ; Capacity is proved for every record field.

; Capacity is proved; write fields in record order and publish SY_NEXT last.

    LD   HL,(SY_NEXT)              ; Point to next free pending byte.
    PUSH IX                        ; Transfer symbol pointer to DE.
    POP  DE                        ; DE now carries the stable record address.
    LD   (HL),E                    ; Store the symbol pointer low byte.
    INC  HL                        ; Advance to its high byte field.
    LD   (HL),D                    ; Store the symbol pointer high byte.
    INC  HL                        ; Advance to the patch-address field.
    POP  DE                        ; Recover logical patch address.
    LD   (HL),E                    ; Store the patch address low byte.
    INC  HL                        ; Advance to its high byte field.
    LD   (HL),D                    ; Store the patch address high byte.
    INC  HL                        ; Advance to kind/anchor metadata.
    POP  BC                        ; Recover kind/anchor in B and addend in C.
    LD   (HL),B                    ; Store patch kind and anchor bit.
    INC  HL                        ; Advance to the signed addend field.
    LD   (HL),C                    ; Store the one-byte addend.
    INC  HL                        ; Advance to the source-part ordinal.
    POP  AF                        ; Recover the caller's full part byte.
    LD   (HL),A                    ; Store the diagnostic source-part ordinal.
    INC  HL                        ; Form the next free pending address.
    LD   (SY_NEXT),HL              ; Publish the complete record atomically.
    XOR  A                         ; Report append success.
    RET                            ; All saved inputs consumed.
.NCSTACK:                      ; Unwind a rejected append.
    POP  DE                        ; Discard the saved patch address.
    POP  BC                        ; Discard the saved kind and addend.
    POP  AF                        ; Restore stack and part value.
.NOCAP:                        ; Return pending-arena exhaustion.
    LD   A,SY_SPCAP                ; Select the pending-capacity status code.
    SCF                            ; Mark the append as failed.
    RET                            ; Publish nothing on failure.
.ADEFINED:                     ; Return pending-record-for-defined-symbol.
    LD   A,SY_SADEF                ; Report defined-symbol invariant.
    SCF                            ; Mark the append as failed.
    RET                            ; Leave the pending arena untouched.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Non-mutating preflight for one additional pending record.

SY_CCAP:
    LD   HL,(SY_AEND1)             ; Load the arena's exclusive high bound.
    LD   DE,(SY_NEXT)              ; Load the next unpublished record address.
    PUSH BC                        ; Save caller metadata.
    LD   B,SY_RECB1                ; Require one pending record.
    CALL AT_RHCAP                  ; Compare gap with record size.
    POP  BC                        ; Restore caller kind/addend registers.
    JR   C,SY_CNCAP                ; Report insufficient space.
    XOR  A                         ; Report capacity available.
    RET                            ; Publish no pending-arena state.
SY_CNCAP:                      ; Return pending-capacity failure.
    LD   A,SY_SPCAP                ; Select the pending-capacity status code.
    SCF                            ; Mark the preflight as failed.
    RET                            ; Leave all pending state unchanged.

;@ROUTINE IN IX OUT A,CARRY,BC,DE,IX CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
; Find the first pending record for symbol IX. On success IX points to it,
; DE=patch address, B=kind/anchor and C=signed addend. The part byte
; remains at (IX+6) for the caller to read before removal.

SY_PEEK:
SY_FIND1:                      ; Shared search entry used by peek and take.
    PUSH IX                        ; Transfer requested symbol to HL.
    POP  HL                        ; HL now carries the exact record address.
    LD   (SY_OSYM),HL              ; Preserve it across the arena scan.
    LD   IX,(SY_ABAS1)             ; Start at the first pending record.
    LD   DE,(SY_NEXT)              ; Stop at the publication cursor.
.PEEKLOOP:                     ; Compare one pending symbol pointer.
    CALL AT_CIDE                   ; Has the scan reached the half-open end?
    JR   Z,SY_NFRET                ; No matching record remains.
    LD   L,(IX+0)                  ; Read symbol pointer low byte.
    LD   H,(IX+1)                  ; Load its high byte.
    PUSH DE                        ; Protect the pending scan end.
    LD   DE,(SY_OSYM)              ; Reload requested symbol pointer.
    OR   A                         ; Clear carry before comparison.
    SBC  HL,DE                    ; Compare the two stable record addresses.
    POP  DE                        ; Restore the pending scan end.
    JR   Z,.PFOUND                 ; IX identifies the first matching record.
    LD   BC,SY_RECB1               ; Load the pending-record stride.
    ADD  IX,BC                    ; Advance to the next live record.
    JR   .PEEKLOOP                ; Continue until a match or arena end.
.PFOUND:                       ; Return record and patch metadata.
    LD   E,(IX+2)                  ; Load the logical patch-address low byte.
    LD   D,(IX+3)                  ; Load its high byte.
    LD   B,(IX+4)                  ; Read kind and anchor bit.
    LD   C,(IX+5)                  ; Load the signed one-byte addend.
    XOR  A                         ; Report a match.
    RET                            ; Preserve IX on the live pending record.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
; Return shared not-found status.

SY_NFRET:
    LD   A,SY_SNFOU                ; Select the missing-record code.
    SCF                            ; Mark the search as failed.
    RET                            ; Return without changing either arena.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT BC,DE CLOBBERS HL,IX,SIGN,PARITY,HALFCARRY,BC,DE,ZERO
; Remove the first pending record for symbol IX after the caller has submitted
; its patch. Preserve metadata and fill any hole with the final live
; record so the arena remains dense without preserving record order.

SY_TAKE:
    CALL SY_FIND1                  ; Find first record for this symbol.
    RET  C                         ; Preserve the arena when none exists.
    PUSH BC                        ; Save kind/anchor and addend.
    PUSH DE                        ; Save the patch address for the caller.
    LD   HL,(SY_NEXT)              ; Load end of live records.
    LD   DE,SY_RECB1               ; Load the fixed pending-record size.
    OR   A                         ; Clear carry before subtraction.
    SBC  HL,DE                    ; Address the final live record.
    LD   (SY_NEXT),HL              ; Reclaim its seven bytes immediately.
    PUSH IX                        ; Move the matched record address into DE.
    POP  DE                        ; DE now identifies the hole to fill.
    OR   A                         ; Clear carry for address comparison.
    SBC  HL,DE                    ; Was the match the final record?
    JR   Z,.TRETURN                ; No compaction is needed in that case.

; The removed record was not last: copy the last record over its slot.

    LD   HL,(SY_NEXT)              ; Point to old final record.
    PUSH IX                        ; Move the matched-hole address into DE.
    POP  DE                        ; DE now receives the replacement record.
    LD   BC,SY_RECB1               ; Copy all seven pending-record bytes.
    LDIR                           ; Fill the hole with the old final record.
.TRETURN:                      ; Restore metadata from the removed record.
    POP  DE                        ; Return its logical patch address.
    POP  BC                        ; Return its kind/anchor and signed addend.
    XOR  A                         ; Report removal success.
    RET                            ; IX is unspecified on return.

;@ROUTINE IN IX,DE OUT HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY CLOBBERS A
; Compare record cursor IX with half-open end DE.

AT_CIDE:
    PUSH IX                        ; Move the current record pointer into HL.
    POP  HL                        ; HL now carries the cursor value.
    OR   A                         ; Clear carry before unsigned subtraction.
    SBC  HL,DE                    ; Zero means cursor reached end.
    RET                            ; Return flags and difference in HL.

;@ROUTINE IN HL,DE,B OUT CARRY MAYBE-OUT ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
; Check that gap [DE,HL) has at least B bytes. A nonzero high byte is
; automatically sufficient because every current record size is below 256.

AT_RHCAP:
    OR   A                         ; Clear carry before subtraction.
    SBC  HL,DE                    ; Calculate the available gap length.
    RET  C                         ; A reversed interval cannot hold a record.
    LD   A,H                       ; Read the nonnegative gap's high byte.
    OR   A                         ; Nonzero means at least 256 bytes.
    RET  NZ                        ; Enough room for a record.
    LD   A,L                       ; Load the exact small gap size.
    CP   B                         ; Carry means the gap is too small.
    RET                            ; Return the capacity result in carry.
SY_CEND:                       ; Mark the end of executable symbol code.
SY_WBEG:                       ; Begin fixed symbol and pending workspace.

; Twenty bytes of fixed workspace. The first fourteen bytes hold symbol-arena
; cursors, current-scope state and transactional input; the final six hold the
; pending arena's bounds and publication cursor.
; Symbol-arena cursors and current-scope state.

SY_ABASE: DW 0                 ; Permanent base of the global symbol interval.
SY_AEND: DW 0                  ; Exclusive end of the shared symbol arena.
SY_GEND: DW 0                  ; First free byte above permanent globals.
SY_LBEG: DW 0                  ; First live byte of current private records.
SY_SACTI: DB 0                 ; Private scope is active when nonzero.
SY_OKEY: DW 0                  ; Saved packed-key pointer.
SY_OVAL: DW 0                  ; Saved symbol value.
SY_OFLAG: DB 0                 ; Insertion flags or allocation decision.

; Pending-arena cursors. SY_OSYM reuses the key pointer during pending scans.

SY_ABAS1: DW 0                 ; Base of the independent pending-record arena.
SY_AEND1: DW 0                 ; Exclusive end of pending capacity.
SY_NEXT: DW 0                  ; First free pending byte.
SY_OSYM EQU SY_OKEY            ; Reuse key pointer during pending search.
SY_WEND:                       ; End fixed symbol and pending workspace.
