; CP/M source files. The front end names files by ordinal. Here each ordinal
; is a retained 8.3 name, and a file is read through one FCB and a 128-byte
; record cache. A file waiting for its include keeps its FCB and cached record
; in a saved slot, so resuming it reads nothing again.

;@ROUTINE CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Retain the root source named in srcFcb as ordinal zero.

cpmStart: ; Prepare the CP/M file host for one command.
    LD   HL,srcFcb+1                    ; Skip the drive byte and retain the 8.3 name.
    LD   DE,incNames                    ; Store it in the root's ordinal-zero slot.
    LD   BC,11                          ; FCB name and type fields occupy eleven bytes.
    LDIR                                ; Copy the root name into the name table.
    LD   A,1                            ; One name is known.
    LD   (incFound),A                   ; The root.
    XOR  A                              ; The root has not been supplied.
    LD   (srcRoot),A                    ; sfOpen supplies it once.
    RET                                 ; Ready.

;@ROUTINE IN B,HL OUT A,CARRY CLOBBERS BC,DE,HL,IX,IY,ZERO,SIGN,PARITY,HALFCARRY
; Name a file for the front end. B=0 asks for the root, which is supplied
; once. Otherwise the B bytes at HL are a quoted current-drive 8.3 name.

sfOpen: ; Return the ordinal of a named file.
    LD   A,B                            ; Is this a request for the root?
    OR   A                              ; Zero means yes.
    JR   NZ,.named                      ; No: find the name.
    LD   A,(srcRoot)                    ; Was the root supplied already?
    OR   A                              ; Nonzero means yes.
    JR   NZ,.none                       ; No root remains.
    INC  A                              ; It is supplied now.
    LD   (srcRoot),A                    ; Remember that.
    XOR  A                              ; The root is ordinal zero.
    RET                                 ; Return it with carry clear.
.none: ; Report that no root remains.
    XOR  A                              ; A=0 means none.
    SCF                                 ; Carry means no file.
    RET                                 ; The front end finishes.
.named: ; Find or add a name.
    LD   DE,cpFcb                       ; Parse into the working FCB.
    CALL srcName                        ; Validate the 8.3 name.
    JP   NC,incFind                     ; Return its ordinal.
    LD   A,incBad                       ; Reject a malformed name.
    RET                                 ; Carry is still set.

;@ROUTINE IN A OUT A,CARRY CLOBBERS BC,DE,HL,ZERO,SIGN,PARITY,HALFCARRY
; Begin reading file A from its first byte. The entry check leaves the root
; open, so it is not opened again.

sfStart: ; Open a file for reading.
    OR   A                              ; The root?
    JR   NZ,.open                       ; No: open the file.
    LD   HL,srcFresh                    ; Is the root still open from the entry check?
    OR   (HL)                           ; Nonzero means it is.
    LD   (HL),0                         ; Only the first start can use it.
    JR   Z,.open                        ; No: open it.
    XOR  A                              ; It is ready at its first byte.
    RET                                 ; Carry is clear.
.open: ; Open the file's FCB.
    CALL srcOpen                        ; Open its FCB.
    RET  NC                             ; Ready.
    LD   A,incLost                      ; It cannot be read.
    RET                                 ; Carry is still set.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Save the open FCB, cache key and cached record in slot A.

sfPark: ; Keep the current file's read state.
    CALL srcSlot                        ; Address slot A.
    EX   DE,HL                          ; DE writes the slot.
    LD   HL,srcFcb                      ; Save the open FCB.
    LD   BC,36                          ; All of it.
    LDIR                                ; Copy it.
    LD   HL,srcKey                      ; Save the cache key.
    LD   BC,2                           ; One word.
    LDIR                                ; Copy it.
    LD   HL,srcCache                    ; Save the cached record.
    LD   BC,128                         ; One record.
    LDIR                                ; Copy it.
    RET                                 ; The slot holds the file.

;@ROUTINE IN A CLOBBERS A,BC,DE,HL,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Restore the FCB, cache key and cached record kept in slot A.

sfBack: ; Restore a parked file's read state.
    CALL srcSlot                        ; Address slot A.
    LD   DE,srcFcb                      ; Restore the FCB.
    LD   BC,36                          ; All of it.
    LDIR                                ; Copy it back.
    LD   DE,srcKey                      ; Restore the cache key.
    LD   BC,2                           ; One word.
    LDIR                                ; Copy it back.
    LD   DE,srcCache                    ; Restore the cached record.
    LD   BC,128                         ; One record.
    LDIR                                ; Copy it back.
    RET                                 ; No record is read again.

;@ROUTINE IN A OUT HL CLOBBERS A,B,DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Address saved-file slot A.

srcSlot: ; Address one saved-file slot.
    LD   HL,srcSaves                    ; The first slot.
    LD   DE,srcSvLen                    ; One slot's size.
    LD   B,A                            ; Count the slots to pass.
    INC  B                              ; Count from one.
.next: ; Pass one slot.
    DEC  B                              ; One fewer to pass.
    RET  Z                              ; HL addresses slot A.
    ADD  HL,DE                          ; Step past a slot.
    JR   .next                          ; Continue.

;@ROUTINE OUT A,CARRY CLOBBERS BC,DE,HL,IX,ZERO,SIGN,PARITY,HALFCARRY
; Find an exact retained name, or append it if capacity remains. Carry
; reports too many files, with the message number in A.

incFind: ; Find or allocate an exact retained source name.
    LD   C,0                            ; Start with retained-name ordinal zero.
.loop: ; Search each retained source-name slot.
    LD   A,(incFound)                   ; Read the number of names already retained.
    CP   C                              ; Compare count with candidate ordinal.
    JR   Z,.add                         ; Append when no existing slot remains to inspect.
    LD   A,C                            ; Select this retained name's ordinal.
    CALL incSlot                        ; Address its eleven-byte name record.
    LD   IX,cpFcb+1                     ; Address the normalised candidate filename.
    LD   B,11                           ; Compare the complete base and extension fields.
.byte: ; Compare each of the eleven name bytes.
    LD   A,(HL)                         ; Read one byte from the retained name.
    CP   (IX+0)                         ; Compare with the corresponding candidate byte.
    JR   NZ,.next                       ; Try the next ordinal on any mismatch.
    INC  HL                             ; Advance the retained-name cursor.
    INC  IX                             ; Advance the candidate-name cursor.
    DJNZ .byte                          ; Compare the remaining name bytes.
    LD   A,C                            ; Return the ordinal whose full name matched.
    OR   A                              ; Clear carry and set zero for ordinal zero.
    RET                                 ; Return the existing name ordinal.
.next: ; Advance after a mismatched retained name.
    INC  C                              ; Advance to the next retained-name ordinal.
    JR   .loop                          ; Continue until a name matches or the table ends.
.add: ; Append a name when no existing slot matched.

; The one-byte part ABI admits ordinals 0..254: at most 255 retained files.

    LD   A,C                            ; The next ordinal is the current number of names.
    CP   255                            ; The byte-sized table has no ordinal 255 entry.
    JR   Z,.full                        ; Reject a 256th distinct source file.
    PUSH AF                             ; Keep the new ordinal for the return.
    CALL incSlot                        ; Address the next eleven-byte table slot.
    EX   DE,HL                          ; Put the slot destination in DE for LDIR.
    LD   HL,cpFcb+1                     ; Point to the normalised 8.3 name bytes.
    LD   BC,11                          ; Copy name and type, not drive.
    LDIR                                ; Store the new name in its ordinal slot.
    LD   HL,incFound                    ; Address the count of names.
    INC  (HL)                           ; Publish the completed name slot.
    POP  AF                             ; Return the allocated ordinal.
    OR   A                              ; Clear carry to mark successful insertion.
    RET                                 ; Return the new retained-name identity.
.full: ; Reject an excess source part before writing the table.
    LD   A,incMany                      ; Select the part-capacity diagnostic.
    SCF                                 ; Mark the name table as full.
    RET                                 ; Return without changing the name count.

;@ROUTINE IN A OUT A,HL CLOBBERS DE,CARRY,ZERO,SIGN,PARITY,HALFCARRY
; Convert a source ordinal to its retained name-table entry address.

incSlot: ; Compute an eleven-byte source-name slot address.
    LD   L,A                            ; Place the ordinal in the low byte of HL.
    LD   H,0                            ; Extend the ordinal to a 16-bit value.
    LD   D,H                            ; Clear the high byte of the temporary DE value.
    LD   E,L                            ; Copy ordinal for x11.
    ADD  HL,HL                          ; Compute twice the ordinal.
    ADD  HL,HL                          ; Compute four times the ordinal.
    ADD  HL,DE                          ; Combine to make five times the ordinal.
    ADD  HL,HL                          ; Compute ten times the ordinal.
    ADD  HL,DE                          ; Complete eleven times the ordinal.
    LD   DE,incNames                    ; Load the base of the retained-name table.
    ADD  HL,DE                          ; Convert the byte offset to the slot address.
    RET                                 ; Return this name-record address.

srcEnd: ; Exclusive end of the CP/M source-file code.
