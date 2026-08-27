# Converting AZM source to Atom

The `azm-to-atom` command converts the common, byte-preserving subset of AZM
source into Atom source. It is a strict migration tool, not a compatibility
preprocessor. When an AZM construct has no equivalent meaning in Atom, the
command stops at that source position and does not write an output file.

## Command line

Convert one AZM source file beside the original:

```sh
azm-to-atom source.asm
```

The default output is `source.atom.asm`. An existing output file is never
overwritten. Choose another destination with `--output`, or inspect the result
without creating a file:

```sh
azm-to-atom --output migrated/main.asm source/main.asm
azm-to-atom --stdout source/main.asm
```

The converter reads the complete input before writing anything. A failed
conversion therefore cannot leave a partial `.asm` file. Command misuse
returns status 2, a conversion or filesystem failure returns status 1, and a
successful conversion returns status 0.

Diagnostics name the AZM input line and column:

```text
source/main.asm:18:1: AZM directive .INCLUDE has no Atom equivalent
```

## Direct mappings

The converter handles:

- the complete Z80 instruction syntax shared by AZM and Atom;
- AZM underscore locals, translated to Atom dot-prefixed private labels;
- `.ORG`, `.DB`, `.DW`, `.DS`, `.ALIGN`, `.CSTR`, `.PSTR`, and `.ISTR`,
  translated to Atom's bare directives;
- dotted or alias `EQU`, including the common colon form;
- `LSB()` and `MSB()`, translated to `LOW()` and `HIGH()`;
- `0X` and `0B` numeric prefixes, translated to `$` and `%`;
- Intel `H` and `B` suffixes without alteration;
- `.ROUTINE` and `.EXPECTOUT`, retained as Atom proof annotations; and
- a final `.END`, which is removed because Atom consumes the complete source
  stream.

For example, this AZM source:

```asm
.ORG 0X4000
LIMIT: .EQU 10H

START:
_LOOP: LD A,LSB(LIMIT)
       JR NZ,_LOOP
.END
```

becomes:

```asm
ORG $4000
LIMIT: EQU 10H

START:
.LOOP: LD A,LOW(LIMIT)
       JR NZ,.LOOP
```

Symbol names are checked during conversion. Atom's eight-character global
and private-name limits are enforced, and declarations that differ only by
case are rejected. An AZM local must follow a global label. Because Atom
requires `EQU` expressions to be resolved immediately, the converter also
rejects an equate that refers forward.

## Rejected constructs

The converter reports an error for semantics Atom cannot preserve:

- `.INCLUDE` and `.IMPORT`, because AZM textual inclusion and module loading
  are not Atom's import-once `%INCLUDE` model;
- `.IF`, `.ELSE`, and `.ENDIF`, because AZM expressions are not Atom host
  preprocessor conditions;
- ops and chained instruction lines;
- types, unions, fields, enums, layout casts, `SIZEOF()`, and `OFFSET()`;
- exported declarations, contract-policy controls, and register-contract
  suppressions;
- string-valued equates, typed `.DS`, and AZM output-range directives;
- multi-byte single-quoted strings and escapes outside Atom's byte-string
  escape set;
- symbols that Atom cannot spell or store; and
- any statement head that is neither an Atom instruction nor a supported
  directive.

These errors are intentional. Rewriting one of these forms requires a design
choice rather than a mechanical syntax change. Make that choice in the AZM
source, then run the converter again.

## Programmatic API

Tools can convert in memory through the package root:

```js
import { translateAzmSourceToAtom } from "atom-z80";

const atomSource = translateAzmSourceToAtom(azmSource, {
  sourceName: "source/main.asm",
});
```

The function returns one LF-normalized string. It throws `AtomAssemblyError`
with category `translation`, a stable error code, and a `diagnostic` containing
`logicalIdentity`, `line`, and `column`. It performs no filesystem work and
does not require AZM at runtime.

The development proof assembles a representative source with AZM, converts and
assembles it with Atom, and compares the exact initialized address set and
every emitted byte. The installed-package proof also runs the converter from
an offline installation where AZM is absent.
