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

## Triptych WASM adapter

`createTriptychWasmExecutionAdapter()` is an opt-in adapter for the Triptych
WASM binding. It receives the `TriptychCpu` constructor from the host rather
than importing Triptych, Rust or a browser runtime. This keeps the Atom package
portable and leaves machine selection at the edge.

The adapter uses the binding's single-instruction step and CPU-state methods.
It keeps the runner's mutable image in JavaScript-owned storage and copies it
across the binding at each instruction boundary. That is intentionally a
conformance path: a long-lived `Uint8Array::view` into wasm-bindgen linear
memory may be detached by a later allocation, while the runner must see stable
ordinary byte-array semantics. A production bulk runner can use a stronger
owned-memory contract once that contract is separately qualified.

Run the cross-host predicate after building Triptych's WASM host:

```sh
TRIPTYCH_WASM_MODULE=/path/to/triptych/dist/wasm/triptych_host_wasm.js \
  npm run verify:triptych-wasm
```

The predicate assembles one source project through both Debug80 Runtime and
Triptych WASM and compares the materialized bytes, patches, service trace and
success result. It does not make Debug80 a production dependency of Triptych;
it is a differential reference while the native adapter is developed.

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
