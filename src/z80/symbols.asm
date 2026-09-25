;==============================================================================
;  Symbols, private scope and pending references
;==============================================================================
;
;  Store exact RADIX-40 symbol records in caller-owned memory. Each record owns
;  the complete packed name and value; lookup is exact rather than hashed.
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
;  A symbol record is eight bytes: six packed-name bytes followed by a word
;  value. Spare high bits in the final name byte hold signed-equate, defined and
;  private flags. A pending record is seven bytes: symbol pointer, patch address,
;  kind/diagnostic-anchor, signed addend and full source-part ordinal.
;
;  Capacity checks occur before cursor publication. Scope changes are
;  transactional: undefined private labels or stale private pending references
;  leave the previous scope intact. The output layer preserves pending
;  transactionality by calling SY_TAKE only after its PATCH operation succeeds.

SY_CBEG:                       ; Begin executable symbol and pending-record code.
; Symbol-record geometry and packed-name flag bits.
SY_RECB EQU 8                  ; Bytes in one packed symbol record.
SY_RECB1 EQU 7                 ; Bytes in one pending-reference record.
SY_KMASK EQU $07               ; Low bits carrying the pending patch kind.
SY_PMASK EQU 6                 ; Offset of the pending source-part ordinal byte.
SY_DANCH EQU $80               ; Diagnostic-anchor flag stored with a pending kind.
SY_NAMEB EQU 6                 ; Bytes occupied by one packed symbol key.
SY_VALLO EQU 6                 ; Offset of the symbol value's low byte.
SY_VALHI EQU 7                 ; Offset of the symbol value's high byte.
SY_NHMAS EQU $07               ; Name bits retained from the final packed-name byte.
SY_FSIGN EQU $20               ; Record flag for a signed equate value.
SY_FDEFI EQU $40               ; Record flag for a defined symbol value.
SY_FPRIV EQU $80               ; Record flag for a private symbol key.
; Public status values. Symbol and pending capacity are distinct diagnostics.
SY_SOK EQU 0                   ; Operation completed successfully.
SY_SNFOU EQU 1                ; No matching symbol or pending record exists.
SY_SDUPL EQU 2                ; A definition duplicates an existing defined symbol.
SY_SSCAP EQU 3                ; The symbol arena cannot hold another record.
SY_SPNSC EQU 4                ; A private name was used before a global scope.
SY_SUPRI EQU 5                 ; A private symbol remains undefined at scope close.
SY_SPCAP EQU 6                ; The pending arena cannot hold another record.
SY_SPINV EQU 7                ; Symbol or pending state violates an internal invariant.
SY_SADEF EQU 8                ; A pending reference was added to a defined symbol.
SY_SPCA1 EQU 9                ; Retained status value for source-part capacity.
; Initialise the symbol arena [HL,DE). Globals begin at HL; private records begin
; at DE. No private scope exists until the first global label is committed.

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
SY_RESET:                      ; Enter symbol-arena initialization.
LD   (SY_ABASE),HL             ; Retain the permanent global-record base.
LD   (SY_GEND),HL              ; Start the upward-growing global region empty.
LD   (SY_AEND),DE              ; Retain the exclusive end of the shared arena.
LD   (SY_LBEG),DE              ; Start the downward-growing private region empty.
XOR  A                         ; Produce both zero state and success status.
LD   (SY_SACTI),A              ; Mark private scope as inactive.
RET                            ; Return with carry clear.
; Initialise the independent pending arena [HL,DE).

;@ROUTINE IN HL,DE OUT A,CARRY CLOBBERS SIGN,PARITY,HALFCARRY,ZERO
SY_RESE1:                      ; Enter pending-arena initialization.
LD   (SY_ABAS1),HL             ; Retain the first pending-record address.
LD   (SY_NEXT),HL              ; Start the upward-growing pending arena empty.
LD   (SY_AEND1),DE             ; Retain its exclusive capacity boundary.
XOR  A                         ; Report success with carry clear.
RET                            ; Return without touching the symbol arena.
; Pack a source symbol at HL/B into the caller's six-byte key at DE. A leading
; period selects private scope but is not part of the RADIX-40 payload, so both
; global and private payloads retain up to eight characters.

;@ROUTINE IN B,HL,DE OUT A,DE,CARRY CLOBBERS BC,HL,IX,SIGN,PARITY,HALFCARRY,ZERO
EN_PSYM:                       ; Enter symbol-key packing.
LD   A,B                       ; Inspect the complete source-name length.
OR   A                         ; An empty name cannot form a symbol.
JR   Z,.PSINVALI               ; Reject it before writing the destination.
LD   A,(HL)                    ; Read the first source character.
CP   $2E                       ; Does a leading period select private scope?
JR   NZ,.PSGLBL                ; Pack a global name without removing a prefix.
DEC  B                         ; Exclude the private marker from the payload length.
JR   Z,.PSINVALI               ; Reject a period with no following name.
LD   A,B                       ; Check the remaining private payload length.
CP   9                         ; Eight payload characters are the exact maximum.
JR   NC,.PSINVALI              ; Reject nine or more characters atomically.
INC  HL                        ; Skip the period before RADIX-40 packing.
;@EXPECTOUT DE,CARRY
CALL EN_R40PK                  ; Pack the private payload into six destination bytes.
JR   C,.PSINVALI               ; Translate any packing failure to symbol syntax.
PUSH DE                        ; Preserve the returned end of the packed key.
DEC  DE                        ; Address the final packed-name byte.
; RADIX-40's final word uses only the low eleven bits. Mark private identity in
; the final byte without changing the packed name.
LD   A,(DE)                    ; Load the byte whose upper bits are flag storage.
OR   SY_FPRIV                  ; Mark the packed key as private.
LD   (DE),A                    ; Publish the private flag with the exact key.
POP  DE                        ; Restore the caller's end-of-key pointer.
XOR  A                         ; Report successful private-name packing.
RET                            ; Return with carry clear.
.PSGLBL:                       ; Pack a global name exactly as supplied.
;@EXPECTOUT DE,CARRY
CALL EN_R40PK                  ; Pack and case-fold the global RADIX-40 key.
JR   C,.PSINVALI               ; Convert invalid characters or length to failure.
XOR  A                         ; Report successful global-name packing.
RET                            ; Return the destination pointer from the packer.
.PSINVALI:                     ; Return the private/public key syntax failure.
XOR  A                         ; Construct status one without a literal load.
INC  A                         ; A now identifies invalid symbol input.
SCF                            ; Mark the packing operation as failed.
RET                            ; Leave any publication decision to the caller.
; Find the exact key at HL. Its private flag selects the current private interval
; or the permanent global interval. IX returns the matching eight-byte record.

;@ROUTINE IN HL OUT A,CARRY,IX CLOBBERS BC,HL,SIGN,PARITY,HALFCARRY,DE,ZERO
SY_FIND:                       ; Enter exact symbol lookup.
LD   (SY_OKEY),HL              ; Preserve the caller's packed search key.
PUSH HL                        ; Save its first-byte address.
LD   DE,5                      ; Select the final packed-name byte.
ADD  HL,DE                    ; Advance to the byte carrying the private flag.
BIT  7,(HL)                    ; Choose global or current-private search bounds.
POP  HL                        ; Restore the packed key pointer.
JR   Z,.FINDGLBL               ; Search the permanent global interval.
LD   A,(SY_SACTI)              ; Read the current private-scope state.
OR   A                         ; A zero state means no global label has opened scope.
JR   Z,.PNSCOPE                ; Reject a private lookup with no active scope.
LD   IX,(SY_LBEG)              ; Start at the first current private record.
LD   DE,(SY_AEND)              ; Stop at the shared arena's exclusive end.
JR   .FINDLOOP                ; Enter the common record scan.
.FINDGLBL:                     ; Establish the permanent global interval.
LD   IX,(SY_ABASE)             ; Start at the first global record.
LD   DE,(SY_GEND)              ; Stop after the last published global record.
.FINDLOOP:                     ; Compare one eight-byte record per iteration.
CALL AT_CIDE                   ; Test whether IX has reached the half-open end.
JR   Z,.NOTFOUND               ; Exhaustion means the exact key is absent.
PUSH DE                        ; Protect the interval end during key comparison.
;@EXPECTOUT ZERO
CALL SY_KEQUA                  ; Compare this record's packed name with SY_OKEY.
POP  DE                        ; Restore the scan's exclusive end address.
JR   Z,.FOUND                  ; Return IX when all key bits match.
LD   BC,SY_RECB                ; Load the fixed symbol-record stride.
ADD  IX,BC                    ; Advance to the next record.
JR   .FINDLOOP                ; Continue until a match or interval end.
.FOUND:                        ; IX identifies the exact live record.
XOR  A                         ; Report lookup success with carry clear.
RET                            ; Preserve IX for the caller.
.NOTFOUND:                     ; Translate interval exhaustion to public status.
JP   SY_NFRET                  ; Return the shared not-found result.
.PNSCOPE:                      ; Translate missing private scope to public status.
JP   SY_GLPRI                  ; Return private-name-without-scope.
; Compare five full name bytes and the low three name bits in byte five. The
; upper bits contain record flags and do not participate in identity.

;@ROUTINE IN IX OUT ZERO CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,B,CARRY,A
SY_KEQUA:                      ; Enter packed-key comparison.
PUSH IX                        ; Move the candidate record pointer through the stack.
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
LD   A,(DE)                    ; Load the final candidate byte with record flags.
XOR  (HL)                      ; Isolate bits that differ from the search key.
AND  SY_NHMAS                  ; Ignore upper flag bits and set zero on exact identity.
RET                            ; Return the comparison result in the zero flag.
; Define key HL as value DE without changing private scope. An existing undefined
; record is completed in place so pending pointers remain valid; an absent key is
; inserted; an already defined key is a duplicate.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
SY_DECL:                       ; Enter symbol definition without scope advancement.
LD   (SY_OKEY),HL              ; Save the packed key across lookup and insertion.
LD   (SY_OVAL),DE              ; Save the final sixteen-bit symbol value.
;@EXPECTOUT A,CARRY,IX
CALL SY_FIND                   ; Look for an existing exact record.
JR   C,.DMISSING               ; Handle absence or private-scope failure.
BIT  6,(IX+5)                  ; Is the existing record already defined?
JR   NZ,.DUPLICAT              ; A second definition is always an error.
LD   DE,(SY_OVAL)              ; Reload the value for the undefined record.
LD   (IX+SY_VALLO),E           ; Store its low byte.
LD   (IX+SY_VALHI),D           ; Store its high byte.
LD   A,(IX+5)                  ; Load the final key byte and existing flags.
OR   SY_FDEFI                  ; Mark the record as defined.
LD   (IX+5),A                  ; Publish the completed record in place.
XOR  A                         ; Report successful definition.
RET                            ; Keep IX on the completed record.
.DUPLICAT:                     ; Return the shared duplicate-definition error.
JP   SY_GLDUP                  ; Preserve the established public status.
.DMISSING:                     ; Interpret the failed lookup status.
CP   SY_SNFOU                  ; Was the key simply absent?
JR   Z,.DINSERT                ; Insert a fresh defined record in that case.
SCF                            ; Restore carry after CP changed the lookup flags.
RET                            ; Propagate private-scope or other lookup status in A.
.DINSERT:                      ; Prepare a newly defined record.
LD   A,SY_FDEFI                ; Supply the defined flag to the insertion routine.
;@EXPECTOUT A,CARRY,IX
JR   SY_INSER                 ; Insert the saved key/value and return its result.
; Find or create an undefined record for key HL. B=0 reports an existing record;
; B=1 reports a newly inserted record whose value is initially zero.

;@ROUTINE IN HL OUT A,CARRY,IX,B CLOBBERS C,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
SY_REF:                        ; Enter find-or-create for an unresolved reference.
LD   (SY_OKEY),HL              ; Preserve the packed key across lookup and insertion.
;@EXPECTOUT A,CARRY,IX
CALL SY_FIND                   ; Search global or current-private records.
JR   C,.RMISSING               ; Interpret an absent key or scope failure.
LD   B,0                       ; Tell the caller this record already existed.
RET                            ; Return IX on the existing record.
.RMISSING:                     ; Interpret the lookup failure status.
CP   SY_SNFOU                  ; Is insertion appropriate for a missing key?
JR   Z,.RINSERT                ; Create the undefined placeholder when absent.
SCF                            ; Restore carry after the status comparison.
RET                            ; Propagate a private-scope failure unchanged in A.
.RINSERT:                      ; Initialize the placeholder value and flags.
XOR  A                         ; Undefined records begin with zero definition flags and value.
LD   (SY_OVAL),A               ; Clear the saved value's low byte.
LD   (SY_OVAL+1),A             ; Clear the saved value's high byte.
;@EXPECTOUT A,CARRY,IX
CALL SY_INSER                  ; Insert an undefined record for the saved key.
RET  C                         ; Propagate symbol-capacity failure.
LD   B,1                       ; Tell the caller that a new record was created.
RET                            ; Return IX on the inserted placeholder.
; Insert SY_OKEY using flags A and value SY_OVAL. Prove the shared arena has one
; complete record of room before moving either publication cursor.

;@ROUTINE IN A OUT A,CARRY,IX CLOBBERS BC,DE,HL,SIGN,PARITY,HALFCARRY,ZERO
SY_INSER:                      ; Enter atomic symbol-record insertion.
LD   (SY_OFLAG),A              ; Preserve the caller's definition flags.
LD   HL,(SY_LBEG)              ; Use the private-region start as the high bound.
LD   DE,(SY_GEND)              ; Use the global-region end as the low bound.
LD   B,SY_RECB                 ; Require one complete eight-byte record.
CALL AT_RHCAP                  ; Prove the shared gap can hold it.
JR   C,.NOCAP                  ; Fail before moving either publication cursor.
.HASCAP:                       ; Capacity is proved for either growth direction.
; Global records extend SY_GEND upward. Private records move SY_LBEG downward.
LD   HL,(SY_OKEY)              ; Inspect the saved packed key.
LD   DE,5                      ; Select its final byte carrying the private flag.
ADD  HL,DE                    ; Advance to that flag byte.
BIT  7,(HL)                    ; Choose global or private allocation.
JR   NZ,.IPRIVATE              ; Allocate downward for a private record.
LD   IX,(SY_GEND)              ; Publish the global record at the old upper cursor.
PUSH IX                        ; Move that address into HL for cursor arithmetic.
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
POP  IX                        ; IX now identifies the allocated private record.
.CINSERT:                      ; Populate the already allocated record.
; Commit the exact key, merge definition flags and store the value.
LD   HL,(SY_OKEY)              ; Point at the exact six-byte packed key.
PUSH IX                        ; Move the destination record address into DE.
POP  DE                        ; DE now points at the first record byte.
LD   BC,SY_NAMEB               ; Copy all six key bytes, including private identity.
LDIR                           ; Transfer the key into the allocated record.
LD   A,(SY_OFLAG)              ; Reload requested definition/sign flags.
OR   (IX+5)                    ; Merge them with private identity in the final key byte.
LD   (IX+5),A                  ; Publish the record flags.
LD   DE,(SY_OVAL)              ; Reload the saved sixteen-bit value.
LD   (IX+SY_VALLO),E           ; Store its low byte after the key.
LD   (IX+SY_VALHI),D           ; Store its high byte last.
XOR  A                         ; Report successful insertion with carry clear.
RET                            ; Return IX on the new live record.
.NOCAP:                        ; Return symbol-arena exhaustion.
LD   A,SY_SSCAP                ; Select the symbol-capacity status.
SCF                            ; Mark insertion as failed.
RET                            ; Leave both publication cursors unchanged.
; Validate and discard the current private scope, then leave a fresh active
; private scope. SY_CSCOP is the commit-only half used after proof.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
SY_ASCOP:                      ; Enter validated private-scope advancement.
CALL SY_VSCOP                  ; Prove the current private region is discardable.
RET  C                         ; Preserve the old scope when validation fails.
SY_CSCOP:                      ; Commit a fresh empty private scope.
LD   HL,(SY_AEND)              ; Load the top of the shared symbol arena.
LD   (SY_LBEG),HL              ; Discard every current private record at once.
LD   A,1                       ; Construct the active-scope state.
LD   (SY_SACTI),A              ; Publish that a global scope now exists.
XOR  A                         ; Report successful scope advancement.
RET                            ; Return with carry clear.
; Define a global label and begin its private scope as one transaction. Existing
; undefined globals are completed in place; missing globals need one record after
; the old private region is reclaimed.

;@ROUTINE IN HL,DE OUT A,CARRY,IX CLOBBERS BC,DE,HL,IY,ZERO,SIGN,PARITY,HALFCARRY
SY_DGLAB:                      ; Enter transactional global-label definition.
LD   (SY_OKEY),HL              ; Preserve the packed global key.
LD   (SY_OVAL),DE              ; Preserve the label address.
LD   DE,5                      ; Select the key byte carrying private identity.
ADD  HL,DE                    ; Advance to that final packed-name byte.
BIT  7,(HL)                    ; A global-label entry cannot accept a private key.
JR   NZ,SY_GLPRI               ; Reject it before validating or changing scope.
LD   HL,(SY_OKEY)              ; Restore the packed key for lookup.
CALL SY_FIND                   ; Find any existing global placeholder.
JR   C,SY_GLMIS                ; Distinguish absence from other lookup failures.
BIT  6,(IX+5)                  ; Is the existing global already defined?
JR   NZ,SY_GLDUP               ; Reject duplicate label definition atomically.
XOR  A                         ; Mark that no fresh record allocation is needed.
LD   (SY_OFLAG),A              ; Save the existing-placeholder case.
JR   SY_GLVAL                 ; Validate eviction before committing the value.
SY_GLMIS:                      ; Handle a missing or failed global lookup.
CP   SY_SNFOU                  ; Is the key simply absent?
RET  NZ                        ; Propagate any other status in A.
LD   A,1                       ; Mark that a new global record must be inserted.
LD   (SY_OFLAG),A              ; Preserve the allocation decision.
SY_GLVAL:                      ; Preflight old-scope eviction and any allocation.
; First prove that every old private symbol and pending pointer can be evicted.
CALL SY_VSCOP                  ; Prove every old private record is safe to discard.
RET  C                         ; Leave label and scope state untouched on failure.
LD   A,(SY_OFLAG)              ; Reload the new-record decision.
OR   A                         ; Zero means an undefined placeholder already exists.
JR   Z,SY_GLCMT                ; Skip capacity work when completing in place.
; A missing global is inserted only after checking capacity in the post-eviction
; arena, where SY_LBEG will equal the arena end.
LD   HL,(SY_AEND)              ; Model the private cursor after complete eviction.
LD   DE,(SY_GEND)              ; Use the permanent global end as the low bound.
LD   B,SY_RECB                 ; Require one complete global record.
CALL AT_RHCAP                  ; Prove post-eviction capacity without committing.
JR   C,SY_GLCAP                ; Preserve the old scope when no record can fit.
SY_GLCMT:                      ; Commit scope closure and the global label together.
LD   HL,(SY_AEND)              ; Load the empty-private-region cursor.
LD   (SY_LBEG),HL              ; Discard the old private records.
LD   A,1                       ; Construct active-scope state.
LD   (SY_SACTI),A              ; Publish the new global label's private scope.
LD   HL,(SY_OKEY)              ; Restore the label key for definition.
LD   DE,(SY_OVAL)              ; Restore its final address.
CALL SY_DECL                   ; Complete or insert the global record.
RET  NC                        ; Return success when the proved commit succeeds.
; All failure cases were preflighted, so a commit-time declaration failure is an
; internal invariant violation.
LD   A,SY_SPINV                ; Report a violated commit invariant.
SCF                            ; Mark the transaction as failed.
RET                            ; Return after the already committed scope change.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
SY_GLPRI:                      ; Return private-name-without-global-scope.
LD   A,SY_SPNSC                ; Select the private-scope status.
SCF                            ; Mark the symbol operation as failed.
RET                            ; Leave all symbol state untouched.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
SY_GLDUP:                      ; Return duplicate-definition status.
LD   A,SY_SDUPL                ; Select the duplicate-symbol code.
SCF                            ; Mark the definition as failed.
RET                            ; Leave the existing record unchanged.
SY_GLCAP:                      ; Return global-record capacity failure.
LD   A,SY_SSCAP                ; Select symbol-arena exhaustion.
SCF                            ; Mark the global-label transaction as failed.
RET                            ; Preserve the previous private scope.
; Prove the current private scope is safe to discard. Every private record must
; be defined, and no pending record may still point into private storage. The
; second condition also catches an impossible stale reference to a defined local.

;@ROUTINE OUT A,CARRY CLOBBERS IX,DE,BC,ZERO,SIGN,PARITY,HALFCARRY,HL
SY_VSCOP:                      ; Enter non-mutating private-scope validation.
LD   IX,(SY_LBEG)              ; Start at the first current private record.
LD   DE,(SY_AEND)              ; Stop at the arena's exclusive end.
SY_VSLOO:                      ; Check one private record per iteration.
CALL AT_CIDE                   ; Has the record cursor reached the interval end?
JR   Z,SY_VPEND                ; Then validate pending pointers separately.
BIT  6,(IX+5)                  ; Is this private symbol defined?
JR   Z,SY_VUNDE                ; Undefined private names cannot be evicted.
LD   BC,SY_RECB                ; Load the symbol-record stride.
ADD  IX,BC                    ; Advance to the next private record.
JR   SY_VSLOO                 ; Continue through the current scope.
SY_VPEND:                      ; Validate every live pending symbol pointer.
; Walk the complete pending arena and inspect the private flag through each saved
; symbol pointer.
LD   IX,(SY_ABAS1)             ; Start at the first pending record.
LD   DE,(SY_NEXT)              ; Stop at the pending publication cursor.
SY_VPLOO:                      ; Inspect one saved symbol pointer per iteration.
CALL AT_CIDE                   ; Has the pending scan reached its half-open end?
JR   Z,SY_VOK                  ; All private records and pointers are safe.
LD   L,(IX+0)                  ; Load the saved symbol pointer low byte.
LD   H,(IX+1)                  ; Load its high byte.
PUSH DE                        ; Preserve the pending scan end.
LD   DE,5                      ; Select the pointed record's final key byte.
ADD  HL,DE                    ; Advance to its private flag.
BIT  7,(HL)                    ; Does this pending record still reference private data?
POP  DE                        ; Restore the pending scan end.
JR   NZ,SY_VINVA               ; Any private pending pointer forbids eviction.
LD   BC,SY_RECB1               ; Load the pending-record stride.
ADD  IX,BC                    ; Advance to the next pending record.
JR   SY_VPLOO                 ; Continue through the complete live arena.
SY_VOK:                        ; Current private scope is safe to discard.
XOR  A                         ; Report successful validation with carry clear.
RET                            ; Publish no state changes.
SY_VUNDE:                      ; Return undefined-private-at-scope-close.
LD   A,SY_SUPRI                ; Select the undefined-private status.
SCF                            ; Mark validation as failed.
RET                            ; Preserve the complete private scope.
SY_VINVA:                      ; Return stale-private-pending invariant failure.
LD   A,SY_SPINV                ; Select the internal pending-state status.
SCF                            ; Mark validation as failed.
RET                            ; Preserve both symbol and pending arenas.
; Append one seven-byte pending record. Inputs are IX=symbol, DE=logical patch
; address, B=kind/anchor, C=signed addend and A=source-part ordinal. Defined
; symbols are rejected because their value should have been emitted directly.

;@ROUTINE IN A,IX,DE,BC OUT A,CARRY CLOBBERS DE,HL,SIGN,PARITY,HALFCARRY,ZERO
SY_ADD:                        ; Enter atomic pending-record append.
BIT  6,(IX+5)                  ; A defined symbol should never need a pending field.
JR   NZ,.ADEFINED              ; Reject that inconsistent request.
PUSH AF                        ; Preserve the source-part ordinal across capacity checking.
PUSH BC                        ; Preserve kind/anchor and signed addend.
PUSH DE                        ; Preserve the logical patch address.
LD   HL,(SY_AEND1)             ; Use the pending arena end as the high bound.
LD   DE,(SY_NEXT)              ; Use the publication cursor as the low bound.
LD   B,SY_RECB1                ; Require one complete seven-byte record.
CALL AT_RHCAP                  ; Prove capacity before writing or moving SY_NEXT.
JR   C,.NCSTACK                ; Unwind saved inputs on exhaustion.
.HASCAP:                       ; Capacity is proved for every record field.
; Capacity is proved; write fields in record order and publish SY_NEXT last.
LD   HL,(SY_NEXT)              ; Point at the first unpublished pending byte.
PUSH IX                        ; Move the referenced symbol pointer into DE.
POP  DE                        ; DE now carries the stable record address.
LD   (HL),E                    ; Store the symbol pointer low byte.
INC  HL                        ; Advance to its high byte field.
LD   (HL),D                    ; Store the symbol pointer high byte.
INC  HL                        ; Advance to the patch-address field.
POP  DE                        ; Recover the caller's logical patch address.
LD   (HL),E                    ; Store the patch address low byte.
INC  HL                        ; Advance to its high byte field.
LD   (HL),D                    ; Store the patch address high byte.
INC  HL                        ; Advance to kind/anchor metadata.
POP  BC                        ; Recover kind/anchor in B and addend in C.
LD   (HL),B                    ; Store the patch kind and diagnostic-anchor flag.
INC  HL                        ; Advance to the signed addend field.
LD   (HL),C                    ; Store the one-byte addend.
INC  HL                        ; Advance to the source-part ordinal.
POP  AF                        ; Recover the caller's full part byte.
LD   (HL),A                    ; Store the diagnostic source-part ordinal.
INC  HL                        ; Form the next free pending address.
LD   (SY_NEXT),HL              ; Publish the complete record atomically.
XOR  A                         ; Report successful append with carry clear.
RET                            ; Return after all saved inputs are consumed.
.NCSTACK:                      ; Unwind an append rejected by capacity preflight.
POP  DE                        ; Discard the saved patch address.
POP  BC                        ; Discard the saved kind and addend.
POP  AF                        ; Restore the stack and original part value.
.NOCAP:                        ; Return pending-arena exhaustion.
LD   A,SY_SPCAP                ; Select the pending-capacity status code.
SCF                            ; Mark the append as failed.
RET                            ; Leave SY_NEXT and arena bytes unpublished.
.ADEFINED:                     ; Return pending-record-for-defined-symbol.
LD   A,SY_SADEF                ; Select the defined-symbol invariant status.
SCF                            ; Mark the append as failed.
RET                            ; Leave the pending arena untouched.
; Non-mutating preflight for one additional pending record.

;@ROUTINE OUT A,CARRY CLOBBERS DE,HL,ZERO,SIGN,PARITY,HALFCARRY
SY_CCAP:                       ; Enter non-mutating pending-capacity preflight.
LD   HL,(SY_AEND1)             ; Load the arena's exclusive high bound.
LD   DE,(SY_NEXT)              ; Load the next unpublished record address.
PUSH BC                        ; Preserve caller metadata across the shared helper.
LD   B,SY_RECB1                ; Require room for one seven-byte pending record.
CALL AT_RHCAP                  ; Compare the remaining gap with the record size.
POP  BC                        ; Restore caller kind/addend registers.
JR   C,SY_CNCAP                ; Translate insufficient space to public status.
XOR  A                         ; Report successful preflight with carry clear.
RET                            ; Publish no pending-arena state.
SY_CNCAP:                      ; Return pending-capacity failure.
LD   A,SY_SPCAP                ; Select the pending-capacity status code.
SCF                            ; Mark the preflight as failed.
RET                            ; Leave all pending state unchanged.
; Find the first pending record for symbol IX. On success IX identifies the live
; record while DE=patch address, B=kind/anchor and C=signed addend. The part byte
; remains at (IX+6) for the caller to read before removal.

;@ROUTINE IN IX OUT A,CARRY,BC,DE,IX CLOBBERS SIGN,PARITY,HALFCARRY,ZERO,HL
SY_PEEK:                       ; Enter non-mutating pending lookup.
SY_FIND1:                      ; Shared search entry used by peek and take.
PUSH IX                        ; Move the requested symbol pointer into HL.
POP  HL                        ; HL now carries the exact record address.
LD   (SY_OSYM),HL              ; Preserve it across the arena scan.
LD   IX,(SY_ABAS1)             ; Start at the first pending record.
LD   DE,(SY_NEXT)              ; Stop at the publication cursor.
.PEEKLOOP:                     ; Compare one pending symbol pointer per iteration.
CALL AT_CIDE                   ; Has the scan reached the half-open end?
JR   Z,SY_NFRET                ; No matching record remains.
LD   L,(IX+0)                  ; Load this record's symbol pointer low byte.
LD   H,(IX+1)                  ; Load its high byte.
PUSH DE                        ; Protect the pending scan end.
LD   DE,(SY_OSYM)              ; Load the caller's requested symbol pointer.
OR   A                         ; Clear carry before exact pointer subtraction.
SBC  HL,DE                    ; Compare the two stable record addresses.
POP  DE                        ; Restore the pending scan end.
JR   Z,.PFOUND                 ; IX identifies the first matching record.
LD   BC,SY_RECB1               ; Load the pending-record stride.
ADD  IX,BC                    ; Advance to the next live record.
JR   .PEEKLOOP                ; Continue until a match or arena end.
.PFOUND:                       ; Return the matching record and patch metadata.
LD   E,(IX+2)                  ; Load the logical patch-address low byte.
LD   D,(IX+3)                  ; Load its high byte.
LD   B,(IX+4)                  ; Load patch kind and diagnostic-anchor flag.
LD   C,(IX+5)                  ; Load the signed one-byte addend.
XOR  A                         ; Report successful lookup with carry clear.
RET                            ; Preserve IX on the live pending record.

;@ROUTINE OUT A,CARRY CLOBBERS HALFCARRY
SY_NFRET:                      ; Return shared not-found status.
LD   A,SY_SNFOU                ; Select the missing-record code.
SCF                            ; Mark the search as failed.
RET                            ; Return without changing either arena.
; Remove the first pending record for symbol IX after the caller has submitted
; its patch. Preserve the returned metadata and fill any hole with the final live
; record so the arena remains dense without preserving record order.

;@ROUTINE IN IX OUT A,CARRY MAYBE-OUT BC,DE CLOBBERS HL,IX,SIGN,PARITY,HALFCARRY,BC,DE,ZERO
SY_TAKE:                       ; Enter lookup-and-remove for an accepted patch.
CALL SY_FIND1                  ; Locate the first record for the requested symbol.
RET  C                         ; Preserve the arena when none exists.
PUSH BC                        ; Save kind/anchor and addend for the caller.
PUSH DE                        ; Save the patch address for the caller.
LD   HL,(SY_NEXT)              ; Load the first byte after the final live record.
LD   DE,SY_RECB1               ; Load the fixed pending-record size.
OR   A                         ; Clear carry before moving the cursor backward.
SBC  HL,DE                    ; Address the final live record.
LD   (SY_NEXT),HL              ; Reclaim its seven bytes immediately.
PUSH IX                        ; Move the matched record address into DE.
POP  DE                        ; DE now identifies the hole to fill.
OR   A                         ; Clear carry before comparing record addresses.
SBC  HL,DE                    ; Was the matched record already the final one?
JR   Z,.TRETURN                ; No compaction is needed in that case.
; The removed record was not last: copy the last record over its slot.
LD   HL,(SY_NEXT)              ; Point at the old final record after cursor retreat.
PUSH IX                        ; Move the matched-hole address into DE.
POP  DE                        ; DE now receives the replacement record.
LD   BC,SY_RECB1               ; Copy all seven pending-record bytes.
LDIR                           ; Fill the hole with the old final record.
.TRETURN:                      ; Restore metadata from the removed record.
POP  DE                        ; Return its logical patch address.
POP  BC                        ; Return its kind/anchor and signed addend.
XOR  A                         ; Report successful removal with carry clear.
RET                            ; Leave IX unspecified after any compaction.
; Compare record cursor IX with half-open end DE.

;@ROUTINE IN IX,DE OUT HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY CLOBBERS A
AT_CIDE:                       ; Enter record-cursor/end comparison.
PUSH IX                        ; Move the current record pointer into HL.
POP  HL                        ; HL now carries the cursor value.
OR   A                         ; Clear carry before unsigned subtraction.
SBC  HL,DE                    ; Set zero exactly when cursor equals the end.
RET                            ; Return comparison flags and the difference in HL.
; Prove that the gap [DE,HL) contains at least B bytes. A non-zero high byte is
; automatically sufficient because every current record size is below 256.

;@ROUTINE IN HL,DE,B OUT CARRY MAYBE-OUT ZERO CLOBBERS A,HL,SIGN,PARITY,HALFCARRY
AT_RHCAP:                      ; Enter the shared record-gap capacity check.
OR   A                         ; Clear carry before high-bound minus low-bound.
SBC  HL,DE                    ; Calculate the available gap length.
RET  C                         ; A reversed interval cannot hold a record.
LD   A,H                       ; Inspect the high byte of the non-negative gap.
OR   A                         ; Any nonzero high byte exceeds a byte-sized record.
RET  NZ                        ; Return sufficient capacity with carry clear.
LD   A,L                       ; Load the exact small gap size.
CP   B                         ; Set carry when it is smaller than the requested bytes.
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
SY_SACTI: DB 0                 ; Nonzero when a global label has opened private scope.
SY_OKEY: DW 0                  ; Saved packed key pointer for transactions and lookup.
SY_OVAL: DW 0                  ; Saved symbol value for definition or insertion.
SY_OFLAG: DB 0                 ; Saved insertion flags or global-allocation decision.
; Pending-arena cursors. SY_OSYM reuses the key pointer during pending scans.
SY_ABAS1: DW 0                 ; Base of the independent pending-record arena.
SY_AEND1: DW 0                 ; Exclusive end of pending capacity.
SY_NEXT: DW 0                  ; First unpublished byte after live pending records.
SY_OSYM EQU SY_OKEY            ; Reuse saved-key storage for pending pointer searches.
SY_WEND:                       ; End fixed symbol and pending workspace.
