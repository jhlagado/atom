# Self-hosting Atom

Atom’s native source uses ordinary `.asm` filenames. The checked source under `native/`
is the input to native-core generation, the self-host proof, the command line’s
`atom self-host`, and the npm package. The repository retains no second native
implementation. AZM consumes an automatic translation of the same `.asm`
source only as an independent development oracle.

This transition has two reasons for being staged. First, Atom stores only the
first eight significant characters of a symbol, while the AZM source was
written with names such as `AtomParserParsePublished`. A blind truncation would
create collisions. Second, AZM’s proof annotations must survive after the AZM
files disappear.

## Native naming scheme

Every global native symbol has this shape:

```asm
MM_NAME
```

`MM` is a two-letter module code. The remaining five characters are a readable
stem. The current module codes are:

| Code | Area |
| --- | --- |
| `EN` | instruction encoder and RADIX-40 support |
| `SY` | symbols and pending references |
| `TK` | tokenizer |
| `EX` | expression evaluator |
| `PT` | patch handling |
| `PR` | parser |
| `OU` | output stream |
| `ST` | directives and statements |
| `DR` | top-level driver |
| `HS` | host-service boundary |
| `AT` | shared or uncategorized native definitions |

Important entry points use fixed names rather than generated abbreviations.
For example, `AtomAssemble` becomes `DR_ASM`, `AtomParserParse` becomes
`PR_PARSE`, and `AtomTokenizerReset` becomes `TK_RESET`.

Private labels use Atom’s ordinary dot syntax:

```asm
PR_PARSE:
.OPERAND:
        CALL TK_NEXT
        JR NZ,.OPERAND
```

The private portion may contain eight significant characters. It is scoped to
the nearest preceding global label and may therefore be reused in another
routine. The migration allocates names case-insensitively. If two semantic
stems collide in one scope, it adds a deterministic base-36 suffix. It never
silently truncates one definition onto another.

## The symbol ledger

`native/atom-symbols.json` records every migration:

```json
{
  "original": "AtomParserParse",
  "short": "PR_PARSE",
  "private": false,
  "module": "PR"
}
```

A private entry also records the original global scope. The ledger serves
three purposes:

1. It records the reviewed migration from long bootstrap names to exact native
   names.
2. It lets the host recover the long ABI names required by the native runner.
3. It makes the rename reviewable instead of burying it in ordinal labels.

The test suite rejects duplicate global names, duplicate private names within a
scope, overlength names, ordinal placeholders, and changes to the fixed names
of important entry points. Reusing a private name in different global scopes
is tested and permitted.

## Preserving correctness contracts

Atom treats comments beginning with `;@` as ordinary comments. The migration
uses them to retain AZM’s proof metadata without adding syntax to the native
assembler:

```asm
;@ROUTINE IN A OUT HL,CARRY CLOBBERS BC,DE
PR_PARSE:
        ...
;@EXPECTOUT DE
        CALL EX_PARSE
```

The host’s Atom-to-AZM oracle adapter restores these as `.ROUTINE` and
`.EXPECTOUT` annotations. AZM can therefore continue checking register, flag,
and stack contracts against the `.asm` source. Atom ignores the comments while
assembling the same bytes.

## Authority

The current checkpoint establishes the complete authority path:

- `native/atom.asm` and its five ordered source parts are hand-edited source;
- `npm run build:native-core` uses the checked pinned core to assemble those
  parts and writes the resulting image to `assets/native-core.json`;
- the same prepared parts are translated to AZM syntax and assembled with
  strict register contracts;
- the build compares the exact initialized address set and every resident byte
  between Atom and AZM before publishing the asset;
- a second Atom generation must reproduce the first; and
- the encoder differential calls the checked `.asm` core directly across all
  3,445 claimed forms and the complete invalid-record corpus.

A native implementation change belongs in `native/*.asm`. No command
regenerates those files from another source language.

Every subsystem proof now executes the checked core. Encoder, symbols,
tokenizer, expressions, parser/patch, output, statements, driver, and all six
host-service boundaries are complete.

Direct tests supply caller-owned arenas and guarded source, record, and output
intervals. Their proof profiles cover all 65,536 addresses. Strict contracts
come from automatic Atom-to-AZM translation of the complete authoritative core;
byte differentials and subsystem tests execute the checked Atom-built image.
