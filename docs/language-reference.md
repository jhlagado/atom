# Atom language reference

Atom source is case-insensitive. Symbol spelling ignores ASCII letter case;
the same rule applies to instructions, registers, directives,
hexadecimal digits, and host-preprocessor names. A semicolon begins a comment.
One source line contains at most one label, equate, directive, or instruction,
although a label may precede an instruction or data directive on the same line.

## Names and scope

An assembler name begins with an ASCII letter or underscore and continues with
ASCII letters, digits, or underscores. A global name contains one through eight
characters. A private name starts with `.` and contains one through eight
significant characters after that prefix. Names are exact RADIX-40 values;
Atom rejects an overlength name instead of truncating or hashing it.

```asm
RENDER:
.LOOP:
    DJNZ .LOOP
NEXT:
```

A global label starts a new private scope. Private symbols from the previous
scope are then evicted. Atom reports an error if one of them still has an
unresolved reference. A private label requires a preceding global label, can
cross a source-part boundary, and remains visible until the next global label.

`NAME EQU EXPRESSION` and `NAME: EQU EXPRESSION` declare a resolved constant
without changing private scope. The colon is optional and has no label effect.

## Numbers and expressions

The following spellings all represent integers:

```asm
42          ; DECIMAL
$2A         ; HEXADECIMAL
02AH        ; INTEL HEXADECIMAL
%101010     ; BINARY
101010B     ; INTEL BINARY
```

The leading zero in `02AH` is required when an Intel hexadecimal literal would
otherwise begin with a letter. Literal values range from 0 through 65,535.
`$` by itself is the current output address.

A single-quoted character literal is also a numeric value:

```asm
LD A,'A'
DB 'A','Z'
```

It must decode to exactly one byte. Character literals use the same escape
set as byte strings.

Expression precedence, from lowest to highest, is:

```text
|
^
&
<< >>
+ -
* / %
unary + - ~
parentheses and values
```

Division truncates toward zero; remainder has the dividend's sign. Shift counts
range from 0 through 23. Concrete evaluation uses signed 24-bit intermediates
and accepts a final word-domain value from -32,768 through 65,535.

A forward reference must fit Atom's stored affine form: one symbol with a
constant addend from -128 through 127. `TARGET`, `TARGET+5`, `5+TARGET`, and
`TARGET-(2*3)` qualify. Two unresolved symbols, multiplication of an unresolved
symbol, and unary negation of an unresolved symbol do not.

`LOW(EXPRESSION)` returns bits 0–7 and `HIGH(EXPRESSION)` returns bits 8–15.
Concrete expressions may nest these functions. A forward byte function must
be the outermost operation and may retain one affine symbol, as in
`HIGH(TARGET+5)`. Further arithmetic such as `LOW(TARGET)+1` is rejected.
Forward byte functions are valid in fixed immediate or absolute fields and in
`DB` or `DW`; they are rejected for relative branches and IX/IY displacements,
whose range calculation cannot be retained in the six-byte pending record.
`LOW` and `HIGH` remain legal symbol names when they are not followed by `(`.

## Instructions

Atom accepts the complete Z80 instruction-form census used by AZM, including
CB, ED, DD, and FD encodings, IX/IY displacement forms, index-half registers,
and the undocumented `SLL` operation with AZM's `SLS` alias. The native proof
compares all 3,445 claimed logical forms with AZM byte for byte and rejects 526
AZM-invalid forms.

Branch width is explicit. Atom never promotes `JR` to `JP`; a relative target
outside -128 through 127 is an error. Enumerated operands are also checked:
`RST` accepts only multiples of eight from 0 through 56, and `IM` accepts 0, 1,
or 2.

Instruction values use these domains:

| Operand | Accepted value |
| --- | ---: |
| 8-bit immediate or immediate port | 0 through 255 |
| IX/IY displacement | -128 through 127 |
| `JR` or `DJNZ` target | -128 through 127 bytes from the end of the instruction |
| 16-bit immediate or absolute address | -32,768 through 65,535 |
| `BIT`, `RES`, or `SET` index | 0 through 7 |
| `RST` vector | 0, 8, 16, 24, 32, 40, 48, or 56 |
| `IM` mode | 0, 1, or 2 |

Negative 16-bit values retain their two's-complement word encoding. Byte-sized
instruction operands do not truncate: `LD A,$100` is an error. `DB` has the
separate truncating rule described below.

The DD/FD validation follows the processor rather than treating index halves as
ordinary H and L replacements. For example, `LD A,IXH` and `LD IXH,IXL` are
valid, `LD IXH,H` is not, and the H in `LD H,(IX+1)` is the real H register.

## Assembler directives

Assembler directives are bare reserved words. Dotted aliases are deliberately
not accepted.

```asm
BASE EQU $4000
LIMIT: EQU 32
ORG BASE
DB 1,"TEXT",0
DW BASE,$+2
DS 16
DS 8,$FF
ALIGN 16
INCBIN "assets/font.bin"
CSTR "READY"
PSTR "NAME"
ISTR "TOKEN"
```

- `EQU` declares a constant. Its expression must already be resolved.
- `ORG` sets the logical output cursor and emits no byte. Its expression must
  already be resolved.
- `DB` emits comma-separated expressions and double-quoted byte strings.
  Numeric results use their low byte. Forward affine expressions produce byte
  patches.
- `DW` emits comma-separated expressions as little-endian words. Forward
  affine expressions produce word patches. Strings are not accepted.
- `DS COUNT` reserves uninitialized storage. `DS COUNT,FILL` emits initialized
  fill bytes. Both expressions must already be resolved.
- `ALIGN BOUNDARY` emits initialized zero bytes up to the next address divisible
  by a resolved positive boundary. An already aligned address emits nothing;
  the boundary need not be a power of two.
- `INCBIN "PATH"` emits the complete binary file as initialized bytes. The path
  is relative to the source file containing the directive and must remain
  inside the project root. Paths use ASCII. The Mac host snapshots the file
  before native assembly. One binary may contain from zero through 65,535
  bytes. Offset and length operands are not accepted.
- `CSTR "TEXT"` emits the decoded bytes followed by zero.
- `PSTR "TEXT"` emits the decoded byte count followed by the bytes.
- `ISTR "TEXT"` sets bit 7 on the final decoded byte. An empty `ISTR` emits
  no bytes.

In `DB` and `DW`, `$` is reevaluated at the address of each list item. Strings
decode `\0`, `\n`, `\r`, `\t`, `\'`, `\"`, `\\`, and `\xHH` to one byte.

## Host directives

The Mac host consumes preprocessing directives before the Z80 assembler runs:

```asm
%DEFINE DEBUG 1
%IF DEBUG
%INCLUDE "lib/debug.asm"
%ELSE
%INCLUDE "lib/release.asm"
%ENDIF
```

`%DEFINE` binds one immutable 16-bit preprocessor value. It does not substitute
text and does not declare an assembler symbol. Source definitions are allowed
only in the entry file's leading header; included files receive the frozen
definition environment. Command-line `-DNAME[=value]` definitions behave the
same way, and a duplicate name is an error.

`%INCLUDE` is import-once dependency discovery, not C-style textual inclusion.
It is allowed only in a part's leading header. Dependencies are assembled once,
before their importer, while retaining their own filenames and source offsets.
An include-selecting conditional must close before ordinary assembler source.
Body `%IF` blocks may select source lines but cannot include files.

The host replaces directives and inactive lines with spaces while preserving
every CR and LF byte. The native assembler therefore receives no `%` directive
but can still report positions in the original source. `%` remains available
for a binary literal when followed by `0` or `1`, and as remainder otherwise.

## Deliberate boundaries

Atom does not currently implement macros, op expansion, automatic branch
promotion, dotted directives, typed layout, modules or imports with
namespace semantics, repeated textual inclusion, string-valued equates,
forward equates, or banked output. Filesystem work, dependency resolution,
conditional assembly, listing generation, D8 maps, Intel HEX, and artifact
publication are host or operating-adapter services rather than resident
assembler features.
