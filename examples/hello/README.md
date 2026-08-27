# Hello example

This two-part program exercises Atom's complete build path. The host reads the
preprocessor header in `main.asm`, selects `layout.asm`, and masks the `%`
lines without changing source positions. The native Z80 assembler then handles
the labels, data, storage, branch, and instructions.

From this directory, run:

```sh
atom main.asm
```

The command writes `build/main.bin`. The file is 19
bytes long and covers `$4000` through `$4012`. The two uninitialized bytes from
`DS 2` appear as zero in the flat binary. Request `build/main.nobj` explicitly
when the distinction between initialized bytes and reserved storage is needed.

The example uses uppercase source consistently. Atom remains case-insensitive
for symbols, mnemonics, directives, hexadecimal digits, and preprocessor names.
