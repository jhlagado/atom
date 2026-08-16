# Native statement ABI

`AtomAssemblePart` assembles the source part already installed by
`AtomTokenizerReset`. It returns success at that part's EOF. EOF does not imply
that the complete build has ended, because a later source part may define a
global reference.

The syntax is case-insensitive:

```asm
ORG $4000

BUFFERSZ EQU 32

START:
    LD A,BUFFERSZ
.LOOP:
    DB "A\n",0
    DW START,.LOOP
    DS 8
    DS 4,$FF
    ALIGN 16
    DJNZ .LOOP
```

Assembler directives are bare reserved words: `EQU`, `ORG`, `DB`, `DW`, `DS`,
`ALIGN`, `CSTR`, `PSTR`, and `ISTR`. Dotted spellings are rejected. Lines
beginning with `%` belong to the host preprocessor and must have been masked
before native assembly.

## Labels and equates

A global label records the current output cursor and begins a new private
scope. The scope transition is atomic: duplicate, unresolved-private,
pending-invariant, and capacity failures retain the preceding scope and every
record. A `.`-prefixed private label requires an active global scope and remains
visible until the next global label.

A label may occupy its own line or precede an instruction or directive. `EQU`
accepts both `NAME EQU EXPRESSION` and `NAME: EQU EXPRESSION`; the optional
colon does not publish an address label. Global equates do not change private
scope.

An equate expression must be resolved when declared. Atom rejects a
forward-dependent equate without inserting either the equate or its missing
dependency. Instructions, `DB`, and `DW` may refer to an equate or label that
appears later.

Equate records preserve whether a word-domain value was negative. This makes
later arithmetic on `NEGATIVE EQU -1` behave as arithmetic on -1 while
retaining the same eight-byte symbol record.

## Data and placement directives

`ORG EXPRESSION` requires a resolved word and sets the logical output cursor.
It emits no IMAGE operation.

`DB` accepts a comma-separated list of expressions and double-quoted byte
strings. Concrete expression results are truncated to their low byte, matching
AZM data emission. A forward affine expression emits a zero placeholder and a
truncating-byte PATCH record. Strings decode `\0`, `\n`, `\r`, `\t`, `\'`,
`\"`, `\\`, and `\xHH` to one byte each.

`DW` accepts a comma-separated expression list. Words are emitted little
endian; a forward affine expression produces a word PATCH record.

`CSTR`, `PSTR`, and `ISTR` each accept one double-quoted byte string. `CSTR`
adds a zero terminator, `PSTR` adds a leading decoded-byte count, and `ISTR`
sets bit 7 on the final decoded byte. An empty `ISTR` emits no bytes.

`DS COUNT` advances over uninitialized bytes without IMAGE records.
`DS COUNT,FILL` emits `COUNT` copies of the low byte of a resolved fill value.
The count and optional fill must both be resolved. A trailing uninitialized
reservation therefore advances subsequent labels but does not extend the
loadable byte stream, matching AZM.

`ALIGN BOUNDARY` requires a resolved positive word and emits initialized zero
bytes until the cursor is divisible by that boundary. It accepts non-power-of-two
boundaries and emits nothing when the cursor is already aligned. Complete
capacity is checked before the first byte.

Each list item evaluates `$` at that item's output address. Output and pending
capacity are checked before a forward data symbol is inserted or its
placeholder is emitted. A later sink failure is terminal for the uncommitted
generation; the driver must abort it through the operating adapter.

## Status and diagnostics

Success returns `A=0` with carry clear. Failure returns carry set and one
category in A:

| Value | Category |
| ---: | --- |
| 1 | tokenizer or leaked-preprocessor failure |
| 2 | expected statement or head |
| 3 | directive syntax or resolution |
| 4 | equate syntax or unresolved equate |
| 5 | symbol or pending capacity/state |
| 6 | instruction parsing or validation |
| 7 | output capacity, range, or sink failure |
| 8 | final undefined symbol |
| 9 | internal invariant |

`AtomStatementDetail` contains the nested component status.
`AtomStatementErrorPart` and `AtomStatementErrorOffset` identify the captured
source position when one exists. The statement module uses 48 bytes of fixed
workspace, including its ten-byte parsed-instruction record and six-byte
packed symbol key.

## Current limits

Atom intentionally rejects forward-dependent `EQU`, unresolved `ORG`,
unresolved `DS` count or fill, unresolved `ALIGN`, strings in `DW`,
string-valued equates, and dotted directive aliases. The host AZM translator
must rewrite Atom's decoded string escapes as explicit byte values because
AZM's quoted data syntax has different escape semantics.

Single-quoted character literals enter expressions as numeric byte values and
use the same escapes as strings.

`LOW()` and `HIGH()` are expression functions. Their forward forms use the
low-byte and high-byte pending kinds described in `symbolic-parser-abi.md`.

`AtomAssembleFinish` performs the final undefined-symbol and private-scope
checks after the last part. An undefined result sets the exact part and offset
of the anchored reference and returns the symbol-record pointer in IX. The
multipart driver and lifecycle contract are in
[`native-driver-abi.md`](native-driver-abi.md). Final artifact writers remain
host or operating-adapter work.
