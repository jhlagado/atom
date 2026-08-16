# Native statement ABI

`AtomAssemblePart` assembles the source part already installed by
`AtomTokenizerReset`. It returns success at that part's EOF. EOF does not imply
that the complete build has ended, because a later source part may define a
global reference.

The syntax is case-insensitive:

```asm
ORG $4000

BufferSize EQU 32

Start:
    LD A,BufferSize
_Loop:
    DB "A\n",0
    DW Start,_Loop
    DS 8
    DS 4,$FF
    DJNZ _Loop
```

Assembler directives are bare reserved words: `EQU`, `ORG`, `DB`, `DW`, and
`DS`. Dotted spellings are rejected. Lines beginning with `%` belong to the
host preprocessor and must have been masked before native assembly.

## Labels and equates

A global label records the current output cursor and begins a new private
scope. The scope transition is atomic: duplicate, unresolved-private,
pending-invariant, and capacity failures retain the preceding scope and every
record. A `_`-prefixed private label requires an active global scope and remains
visible until the next global label.

A label may occupy its own line or precede an instruction, `ORG`, `DB`, `DW`,
or `DS`. `EQU` uses `Name EQU expression`; a colon before `EQU` is unsupported.
Global equates do not change private scope.

An equate expression must be resolved when declared. Atom rejects a
forward-dependent equate without inserting either the equate or its missing
dependency. Instructions, `DB`, and `DW` may refer to an equate or label that
appears later.

Equate records preserve whether a word-domain value was negative. This makes
later arithmetic on `Neg EQU -1` behave as arithmetic on -1 while retaining the
same eight-byte symbol record.

## Data and placement directives

`ORG expression` requires a resolved word and sets the logical output cursor.
It emits no IMAGE operation.

`DB` accepts a comma-separated list of expressions and double-quoted byte
strings. Concrete expression results are truncated to their low byte, matching
AZM data emission. A forward affine expression emits a zero placeholder and a
truncating-byte PATCH record. Strings decode `\0`, `\n`, `\r`, `\t`, `\'`,
`\"`, `\\`, and `\xHH` to one byte each.

`DW` accepts a comma-separated expression list. Words are emitted little
endian; a forward affine expression produces a word PATCH record.

`DS count` advances over uninitialized bytes without IMAGE records.
`DS count,fill` emits `count` copies of the low byte of a resolved fill value.
The count and optional fill must both be resolved. A trailing uninitialized
reservation therefore advances subsequent labels but does not extend the
loadable byte stream, matching AZM.

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
| 8 | final undefined symbol, reserved for the finish entry |
| 9 | internal invariant |

`AtomStatementDetail` contains the nested component status.
`AtomStatementErrorPart` and `AtomStatementErrorOffset` identify the captured
source position when one exists. The statement module uses 47 bytes of fixed
workspace, including its ten-byte parsed-instruction record and six-byte
packed symbol key.

## Current limits

Phase 2g intentionally rejects forward-dependent `EQU`, unresolved `ORG`,
unresolved `DS` count or fill, strings in `DW`, string-valued equates,
colon-prefixed equates, and dotted directive aliases. The host AZM translator
must rewrite Atom's decoded string escapes as explicit byte values because
AZM's quoted data syntax has different escape semantics.

The multipart iterator, final undefined-symbol check, sink commit/abort driver,
map construction, and final artifact writers are later integration work.
