# Atom host execution adapter

The resident Atom assembler is a Z80 program. The host runner therefore needs
an execution substrate, but it must not make the assembler core depend on one
emulator implementation.

`assembleResolvedAtomProject` accepts an optional `executionAdapter` with two
operations:

```js
{
  parseImage(hexText) {
    // Return an image view with the write ranges used for core validation.
  },
  create({ hexText, entry, romRanges }) {
    // Return { hardware: { memory }, cpu, step() }.
  },
}
```

The runner uses only these machine properties:

- `hardware.memory`: mutable 64 KiB byte-addressed memory;
- `cpu`: registers and flags including `pc`, `sp`, `ix`, `a`, `h`, `l`, `d`,
  `e`, `flags.C` and `halted`; and
- `step()`: execute one instruction and return an optional `cycles` count.

The default `createDebug80ExecutionAdapter()` is the current
development/reference implementation. It is the only module in this host
path that imports Debug80 Runtime. Node and Deno use it today. A future
Triptych native or WASM adapter can implement the same small surface without
changing Atom's source preparation, tool-service gateway, artifact generation,
diagnostics or conformance records.

This is an execution seam, not a generic CPU contract. The adapter must retain
the selected Atom core's reset state, memory protection ranges, flag semantics,
stack behaviour and cycle accounting. A replacement is accepted only after
the same Atom conformance record and host boundary tests pass.

## Stage 3 Node/Deno gate

`npm run verify:stage3` assembles the same small source project in separate
temporary workspaces under Node and Deno. It compares the normalized console
result, diagnostics and the SHA-256 plus size of every selected artifact
(`.bin`, `.hex`, `.lst`, `.d8.json` and `.nobj`). Temporary workspace paths
and runtime versions are deliberately excluded from the comparison.

This proves host compatibility of the existing Atom seam; it does not claim
that Debug80 Runtime is gone. A future Triptych native or WASM adapter must
pass the same artifact and diagnostic comparison before it replaces the
reference adapter.
