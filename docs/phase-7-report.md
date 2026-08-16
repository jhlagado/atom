# Atom Phase 7 product and release report

## Result

**Measured: pass.** Atom is a working Mac command-line assembler with a public
language reference, architecture and capacity account, end-to-end example,
release gate, and TEC-1 deployment design. The installed package runs without
AZM or a neighbouring source checkout and publishes deterministic NOBJ,
binary, Intel HEX, listing, D8, and manifest files as one atomic generation.

The assembler's source and output claims did not change. Native Atom still
matches frozen AZM for **Measured: 3,445 of 3,445 supported instruction forms**
and rejects **Measured: 526 of 526 AZM-invalid forms**. The complete checked
source still produces the same first Atom generation, second Atom generation,
and independently translated AZM image.

## Native size

Phase 7 changes host files, tests, and documentation only.

| Native account | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 12,508 |
| Fixed workspace | Measured | 550 |
| Linked resident extent | Measured | 13,058 |
| Physical margin below 16 KiB | Measured | 3,326 |

The native assembler remains within the one-bank target. The package archive,
generated source, documentation, and Debug80 runtime consume host storage and
do not enter this account.

## End-to-end example

The shipped `examples/hello` project uses **Measured: 2 source parts**. Its
entry header exercises `%DEFINE`, `%IF`/`%ELSE`/`%ENDIF`, and conditional
`%INCLUDE`. The selected dependency and entry then exercise uppercase source,
`ORG`, `EQU`, `DB`, `DW`, both forms of `DS`, global and private labels, a
forward relative patch, and ordinary instructions. The native suite separately
proves case-insensitive parsing.

`npm run verify:example` invokes the real CLI in a temporary project and checks
the exact **Measured: 19-byte** binary, Intel HEX records and checksums, source
listing, D8 file order, symbol names, and `$4000..$4013` half-open output
segment. No generated file is written into the checkout.

## Documentation and release gate

The product documentation now separates four questions:

- `language-reference.md` defines accepted source and explicit exclusions;
- `architecture.md` assigns every stage to the host or native core;
- `limits.md` distinguishes implementation limits from the Mac proof map; and
- `tec-1-deployment.md` defines the remaining operating-adapter contract.

`npm run release:check` rebuilds proof dependencies, runs the complete suite,
checks the strict-contract core and generated source, and repeats Mac and
self-host measurements. `npm publish` invokes the same command through
`prepublishOnly`. The offline package test installs the produced archive in a
fresh prefix, confirms that AZM is absent, runs the CLI from an unrelated
project, assembles the checked self-host source, and verifies the packaged
documentation and example.

The exact dry-run package entry and unpacked-byte census is stored in the
non-packaged `proofs/package-census.json`. Keeping the census outside packaged
content avoids a self-referential size field. Compressed archive size remains
an observation rather than a release invariant.

## TEC-1 boundary

The native core is portable, but the current pinned image contains **Measured:
24 bytes** of Debug80 sink stubs that fail closed without host interception. A
TEC build must supply source loading and the six output lifecycle services.

The Mac proof's fixed workspace, symbol arena, pending arena, maximum
descriptors, and stack consume **Measured: 16,773 bytes** before source
buffering. In a **Hypothesis: 24 KiB effective-RAM budget**, only **Projected
from measured allocations: 7,803 bytes** remain before operating-adapter state.
The Mac's **Measured: 24,576-byte** source page therefore cannot be copied into
that map.

The deployment design records three choices: separate banked source memory,
smaller target-specific source parts, or a measured tokenizer refill service.
No adapter-size claim is made. It remains a **Hypothesis** that the source and
sink adapter can fit the current **Measured: 3,326-byte** resident margin.

## Reproduction

```sh
npm run verify:example
npm run release:check
npm pack --dry-run
```

The first command gives a short product smoke test. The release gate runs the
full correctness battery. The final command prints the package contents for a
human release review after the tree is frozen.
