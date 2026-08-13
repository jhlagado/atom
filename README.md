# atom

`atom` is a single-pass streaming assembler for the Z80, written in Z80
assembly. It targets a TEC-1 and is intended to assemble its own source in less
than 16 KiB of resident code and immutable data.

Phase 1 contains only the parsed-instruction encoder, its case-insensitive
RADIX-40 mnemonic recognizer, and host-side differential proofs against AZM.
Tokenizer, symbols, directives, object output, macros, and op expansion are not
part of this phase.

```sh
npm install
npm test
npm run measure
```

The local AZM oracle is frozen in [`docs/phase-1-authorities.md`](docs/phase-1-authorities.md).
