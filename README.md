# atom

`atom` is a single-pass streaming assembler for the Z80, written in Z80
assembly. It targets a TEC-1 and is intended to assemble its own source in less
than 16 KiB of resident code and immutable data.

Phase 1 contains the parsed-instruction encoder, its case-insensitive RADIX-40
mnemonic recognizer, and host-side differential proofs against AZM. Phase 2a
adds a measured symbol and pending-reference prototype. The tokenizer,
directives, expression grammar, object serialization, macros, and op expansion
remain out of scope.

```sh
npm install
npm test
npm run measure
npm run measure:symbols
```

The local AZM oracle is frozen in [`docs/phase-1-authorities.md`](docs/phase-1-authorities.md).
The Phase 2a decisions and measurements are in
[`docs/phase-2a-report.md`](docs/phase-2a-report.md).
