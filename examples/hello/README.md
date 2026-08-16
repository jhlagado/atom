# Hello example

This two-part program exercises Atom's complete build path. The host reads the
preprocessor header in `main.asm`, selects `layout.asm`, and masks the `%`
lines without changing source positions. The native Z80 assembler then handles
the labels, data, storage, branch, and instructions.

From this directory, run:

```sh
atom --origin 4000H main.asm
```

The committed bundle appears under `build/main.atom/current`. `main.bin` is 19
bytes long and covers `$4000` through `$4012`. The two uninitialized bytes from
`DS 2` appear as zero in the flat binary; the NOBJ file retains the distinction
between initialized bytes and reserved storage.

The example uses uppercase source consistently. Atom remains case-insensitive
for symbols, mnemonics, directives, hexadecimal digits, and preprocessor names.
