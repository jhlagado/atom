# Self-hosting Atom

Atom’s native source uses ordinary `.asm` filenames. The checked source under `native/`
is the input to native-core generation, the self-host proof, the command line’s
`atom self-host`, and the npm package. The repository retains no second native
implementation. Native-core generation executes the checked ATOM seed, then
executes the resulting core over the same source. Both generations must have
identical initialized addresses, bytes and recovered host ABI symbols.

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

The retained Atom-to-AZM converter can restore `.ROUTINE` and `.EXPECTOUT`
annotations, but core generation and self-host verification no longer execute
AZM. These comments remain ABI documentation. Direct execution tests check
selected register, flag, stack and memory contracts; they are not a replacement
whole-program static register analysis.

## Authority

The current checkpoint establishes the complete authority path:

- `native/atom.asm` and its five ordered source parts are hand-edited source;
- `npm run build:native-core` uses the checked pinned core to assemble those
  parts and writes the resulting image to `assets/native-core.json`;
- the first emitted core executes the same source to produce a second generation;
- both generations must reproduce the exact initialized address set, every
  resident byte and recovered ABI symbol before publishing the asset; and
- the encoder differential calls the checked `.asm` core directly across all
  3,445 claimed forms and the complete invalid-record corpus.

A native implementation change belongs in `native/*.asm`. No command
regenerates those files from another source language.

Every subsystem proof now executes the checked core. Encoder, symbols,
tokenizer, expressions, parser/patch, output, statements, driver, and all six
host-service boundaries are complete.

Direct tests supply caller-owned arenas and guarded source, record, and output
intervals. Their proof profiles cover all 65,536 addresses. Byte differentials
and subsystem tests execute the checked Atom-built image. Remaining historical
comparison tests and the object/CP/M builders still require migration before
the complete release gate can run under the ATOM-only policy.
