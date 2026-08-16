# Self-hosting Atom

Atom’s native source is moving permanently to `.atm`. The checked source under
`native/` is already the source consumed by the self-host proof, the command
line’s `--self-host` mode, and the npm package. The older AZM source under
`asm/` remains temporarily as a frozen bootstrap oracle. It is not the target
source format.

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

1. It proves that every original definition received an exact short name.
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
and stack contracts against the `.atm` source. Atom ignores the comments while
assembling the same bytes.

## Transition checkpoints

The present checkpoint establishes the permanent `.atm` representation:

- semantic, collision-checked names replace ordinal generated names;
- `.atm` source and its ledger are checked into `native/` and shipped;
- Atom assembles the checked source twice with byte-identical results;
- the host translates that same source to AZM and runs strict contract checks;
- the obsolete generated `self-host/*.asm` copy is removed.

During this checkpoint, `asm/` remains the frozen source used by the migration
generator. `npm run verify:self-host-source` detects any drift between that
oracle and `native/`. This is a temporary bridge, not a two-source maintenance
model.

The next checkpoint will make `native/*.atm` authoritative. Native-core
generation will run Atom over those files, while AZM will see only the
automatically translated oracle form. Once that path has produced a stable
release and the proof annotations have been audited from `.atm`, the old
`asm/*.asm` implementation and the one-way migration generator can be deleted.

At no stage are developers expected to keep two handwritten implementations in
sync.
