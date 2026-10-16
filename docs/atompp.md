# ATOMPP

Atom has no macros. ATOMPP is a separate step that expands them first: it
reads `.mac` source and writes plain Atom source. Atom then assembles that as
usual, and its errors name the lines of the `.mac` files.

```sh
atompp prog.mac
atom prog.asm
```

`atompp prog.mac` writes `prog.asm` beside its input. `--output` chooses
another file and `--stdout` prints the result. ATOMPP runs on the desktop. A
CP/M version is planned.

## Defining and using a macro

`%MACRO` names a macro and its parameters. The lines up to `%ENDM` are its
body. Inside the body, `%` before a parameter's name stands for the argument:

```asm
%MACRO WAIT n
    LD   B,%n
.w%@: DJNZ .w%@
%ENDM

Start:
    WAIT 10
    WAIT 20
```

A macro is used like an instruction, with its arguments separated by commas.
A comma inside quotes or parentheses belongs to its argument, so `(IX+2)`,
`"a,b"` and `';'` are single arguments. A call needs exactly as many
arguments as the macro has parameters. A label before a call stays on the
call's line.

`%@` in a body becomes a number that is different for every expansion. Labels
such as `.w%@` are then unique to each expansion: the two calls above define
`.w1` and `.w2`. Labels have at most eight characters, so leave room for the
number.

A body can use other macros, up to 32 deep, but cannot define one. Macro
names are case-insensitive and cannot be an instruction or directive.

## Repeating lines

`%REPT n` repeats the lines up to `%ENDR` n times:

```asm
%REPT 4
    RLCA
%ENDR
```

The count is a number from 0 to 65535 in any of Atom's spellings, such as
`16`, `$10` or `10H`. Inside a macro it can be one of the macro's parameters.

## Macro files

`%INCLUDE "lib.mac"` reads another `.mac` file in place, so a file of macros
can be shared. Its path is relative to the file that includes it. Any other
`%INCLUDE`, and every other `%` directive, passes to Atom unchanged. ATOMPP
does not evaluate `%IF`: Atom does that when it assembles the result.

## Errors

ATOMPP reports its own errors, such as a call with the wrong number of
arguments, as `FILE:line:1: message`.

In its output, ATOMPP marks where each line came from with
[`%LINE`](language-reference.md#source-directives-and-limits), so Atom's errors
name the original file and line. A line inside an expansion reports the
macro's own line: an error in `WAIT HL` above names the `LD   B,%n` line of the
macro. Columns are those of the expanded line.
