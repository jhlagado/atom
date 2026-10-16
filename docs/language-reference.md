# The Atom language

Atom source uses ordinary Z80 instructions with bare data directives such as
`DB` and `DW`. Instructions, directives and symbol names are case-insensitive.
A semicolon starts a comment. A line can contain a label followed by an
instruction or data directive.

## Labels and constants

A global name contains up to eight ASCII letters, digits or underscores.
The first character must be a letter or underscore. A private name adds a
leading dot:

```asm
DELAY:
    LD B,10
.LOOP:
    DJNZ .LOOP
    RET
```

`DELAY` starts a private scope. `.LOOP` is visible until the next global label,
so another routine can use its own `.LOOP`. A private label needs a preceding
global label. Its scope can cross a source-file boundary.

An unresolved private reference at the end of its scope is an error.
Names longer than eight characters are rejected rather than truncated.

`EQU` defines a constant whose value is already resolved:

```asm
PORT EQU $80
COUNT: EQU 10
```

The colon is optional for an equate. An equate does not start a new private scope.

## Numbers and expressions

These literals all have the value 42:

```asm
42
$2A
02AH
%101010
101010B
'*'
```

Intel hexadecimal literals need a leading digit, so `0FFH` is valid and `FFH`
is a symbol name. Numeric literals range from 0 to 65,535. A single-quoted
character must decode to exactly one byte. `$` alone is the current output
address.

Expression precedence runs from lowest to highest as follows:

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

`1+2*3` is 7 and `(1+2)*3` is 9. Division truncates towards zero and remainder
has the dividend's sign. Shift counts range from 0 to 23. Evaluation uses signed
24-bit intermediates. A final word value can range from -32,768 to 65,535.

`LOW(value)` extracts bits 0–7 and `HIGH(value)` extracts bits 8–15:

```asm
ADDRESS EQU $1234
DB LOW(ADDRESS),HIGH(ADDRESS)  ; Emits 34 12.
```

## Forward references

An instruction can refer to a label defined later. Atom emits its opcode and
stores the unresolved operand for correction when the label is defined:

```asm
ORG $4000
JR DONE
DB 0
DONE: RET
```

`JR` occupies `$4000` and `$4001`. Its displacement is measured from `$4002`,
the address after the instruction. `DONE` is at `$4003`, so the displacement
is 1. Atom patches that operand after reading `DONE`:

```text
              JR DONE       DB 0   RET
Address    $4000  $4001     $4002  $4003
Final bytes   18     01        00     C9
                    ^
                    displacement patched when DONE is defined
```

The source is read once. The correction changes an earlier output byte rather
than requiring another pass over the source.

A forward expression can contain a symbol plus a constant from -128 to 127.
`TARGET`, `TARGET+5`, `5+TARGET` and `TARGET-(2*3)` are valid forms.
A forward expression is rejected if it needs two unresolved names,
multiplication by the pending value or negation of it.

`LOW(TARGET+5)` and `HIGH(TARGET+5)` are valid forward byte expressions.
The byte function must be outermost, so `LOW(TARGET)+1` is rejected.
These functions work in `DB`, `DW` and fixed immediate or absolute instruction
fields. Forward byte functions are rejected for relative branches and IX/IY
displacements. Concrete expressions can nest `LOW` and `HIGH`.

## Instruction operands

Atom supports the Z80 instruction set, including index-half registers and the
undocumented `SLL` instruction with its `SLS` alias. Instruction width stays as
written: an out-of-range `JR` is an error and is never promoted to `JP`.

| Operand | Range |
| --- | ---: |
| 8-bit immediate or immediate port | 0 to 255 |
| IX/IY displacement | -128 to 127 |
| `JR` or `DJNZ` displacement from the instruction's end | -128 to 127 |
| 16-bit immediate or absolute address | -32,768 to 65,535 |
| `BIT`, `RES` or `SET` bit number | 0 to 7 |
| `RST` address | 0, 8, 16, 24, 32, 40, 48 or 56 |
| `IM` mode | 0, 1 or 2 |

Negative word values use two's-complement encoding. Byte operands must fit:
`LD A,$100` is an error.

Index-half combinations follow the processor's encoding rules. `LD A,IXH`
and `LD IXH,IXL` are valid. `LD IXH,H` is not. In `LD H,(IX+1)`, H is the
ordinary H register.

## Data and placement

| Directive | Effect |
| --- | --- |
| `ORG address` | Sets the output cursor |
| `DB values` | Emits bytes and double-quoted strings |
| `DW values` | Emits little-endian words |
| `DS count` | Reserves space without emitting bytes |
| `DS count,fill` | Emits repeated fill bytes |
| `ALIGN boundary` | Emits zeros up to the next multiple of the boundary |
| `CSTR "text"` | Emits a string followed by zero |
| `PSTR "text"` | Emits the byte count followed by the string |
| `ISTR "text"` | Emits a string with bit 7 set on its last byte |
| `INCBIN "file",count` | Emits the first count bytes of a binary file |

`ORG`, `DS` and `ALIGN` require resolved expressions. An already aligned address
needs no padding and the boundary can be any positive value. An empty `ISTR`
emits nothing.

`DB` truncates numeric values to their low byte. `DW` accepts numeric expressions
but no strings. Both support forward references. `$` is evaluated at each list
item's own address:

```asm
ORG $4000
DB LOW($),LOW($),LOW($)  ; Emits 00 01 02.
DW $                   ; Emits 03 40.
```

Strings decode `\0`, `\n`, `\r`, `\t`, `\'`, `\"`, `\\` and `\xHH` to bytes.
`INCBIN` reads its file when Atom reaches the statement. The count can be any
expression that is resolved at that point. Node permits an omitted count to
include the whole file. CP/M requires the count because its files occupy whole
128-byte records.

## Source directives and limits

Atom applies `%DEFINE`, `%INCLUDE`, `%IF`, `%ELSE` and `%ENDIF` as it reads the
source, so these directives do not cost another pass either. The assembler sees
a directive line as a comment and an inactive branch as blank text. Offsets,
lines and columns are unchanged, so diagnostics still refer to the original
file. [Using Atom](using-atom.md#source-files-and-conditions) explains where the
directives belong and the platform limits.

`%LINE "FILE",n` says the next line is line n of `FILE`. Errors in the lines
that follow name that file and line, until the file ends or another `%LINE`
names something else. It is meant for tools that write Atom source, such as
[ATOMPP](atompp.md), so Atom's errors point at the tool's input. It can appear
anywhere, and is ignored inside an inactive branch. On CP/M the name must be an
8.3 name.

Atom has no macros, automatic branch promotion, forward equates, typed layouts,
namespace imports or banked output. [ATOMPP](atompp.md) expands macros before
assembly. Includes import each source file once.
