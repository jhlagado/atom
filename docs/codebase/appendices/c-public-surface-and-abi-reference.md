# Appendix C — Public surface and ABI reference

[← Build-flow reference](b-build-flow-reference.md)

This appendix lists the package functions and native entries that form Atom's
current integration boundaries.

## Package identity

The npm package is:

```text
atom-z80
```

`package.json` exposes the normal host API, an optional native build API, and
two executables:

```text
HOST IMPORT:    atom-z80
NATIVE BUILDER: atom-z80/native-builder
BINARIES:       atom, azm-to-atom
```

The package requires Node 20 or later. It bundles
`@jhlagado/debug80-runtime` and `@jhlagado/z80-tool-services`. AZM is not
required to run the installed assembler. The optional native builder uses an
installed AZM 0.3.9 or later to link strict-contract platform profiles.

## Native profile builder

`atom-z80/native-builder` exports `buildNativeObjectHarness()`. Platform build
tools may select an image origin, a later core origin, a platform prelude, a
separate common-RAM workspace origin, a gateway implementation, and
register-contract profile and interface files. A profile may also name a Z80
source-reader target; the default is the named-object reader. This lets a
native preprocessor install an equal-offset masking reader without changing the
Atom core or the tool-service ABI. The function returns the immutable bank
bytes, fixed-state initialization bytes, measured addresses, entries,
capacities, hashes, and complete D8 build map.

This subpath is a build interface, not part of Atom's runtime host API. A
platform launcher still owns source preparation, descriptors, memory arenas,
service workspace, stack, and publication policy.

## High-level host functions

| Export | Use |
| --- | --- |
| `ATOM_VERSION` | Report the package version used by the CLI and D8 generator metadata |
| `assembleAtomProject(options)` | Resolve a filesystem project, preprocess it, lower `INCBIN`, and execute native Atom |
| `resolveAtomProject(options)` | Run only filesystem preparation and return ordered source parts |
| `renderAtomArtifacts(result, options)` | Render NOBJ, BIN, HEX, listing, and D8 in memory, with an optional flat base |
| `publishAtomArtifacts(destination, baseName, artifacts)` | Publish one content-addressed artifact generation and atomically select it through `current` |
| `publishAtomOutputFiles(outputs)` | Stage and transactionally replace a positive set of explicit output files |

The current main build option shape is:

```js
{
  root,
  entry,
  definitions,
  placement,
  limits,
  target: { start, capacity },
  maxInstructions,
  maxCycles,
  sink,
}
```

The function throws structured `SourcePreparationError` or `AtomAssemblyError`
instances on failure. A future versioned host facade may convert these to a
tagged result without changing the lower-level functions.

## Native execution functions

| Export | Use |
| --- | --- |
| `loadNativeAtomCore()` | Load and verify the checked Intel HEX and symbol map |
| `assembleResolvedAtomProject(project, options)` | Run an already prepared project through a pinned or supplied native core |
| `createMemoryAtomSink()` | Create the default append-only in-memory generation sink |
| `materializeAtomGeneration(generation, options)` | Produce a new contiguous byte array with IMAGE and PATCH operations applied |
| `NATIVE_ATOM_LIMITS` | Report native part, per-part byte, symbol, pending, and bank limits used by the Mac runner |
| `ATOM_HOST_SINK_STATUS` | Stable host-adapter status values used by the runner and tests |

`assembleResolvedAtomProject()` accepts a development-only `nativeCore` option
in addition to target, budgets, and sink. The self-host proof uses it to execute
the first Atom generation.

## Artifact functions

| Export | Use |
| --- | --- |
| `writeAtomNobj()` | Serialize one committed generation as Atom flat NOBJ 0.2 |
| `parseAtomNobj()` | Validate and summarize Atom NOBJ framing, order, map, count, and CRC |
| `crc16CcittFalse()` | Compute the object stream CRC |
| `writeIntelHex()` | Render a materialized flat image as Intel HEX |
| `writeAtomCom()` | Validate `$0100` load and entry constraints and return COM bytes |
| `writeAtomListing()` | Render original source, final bytes, reservations, and symbols |
| `writeAtomD8()` | Render Debug80 source and symbol metadata |

`renderAtomArtifacts()` calls all current writers and returns:

```js
{
  nobj,
  bin,
  hex,
  listing,
  d8,
  d8Text,
}
```

## Development and proof helpers

| Export | Use |
| --- | --- |
| `translateAtomLineToAzm()` | Translate one prepared Atom source line into AZM syntax |
| `translateResolvedAtomProjectToAzm()` | Produce one AZM oracle source from ordered prepared parts |
| `createSelfHostedAtomCore()` | Recover a runner-compatible native core from one Atom generation |
| `AtomAssemblyError` | Structured error class for execution, artifacts, translation, self-hosting, and publication |

These helpers are exported because the repository's independent proofs and
external engineering tools need them. Ordinary build integration begins with
`assembleAtomProject()`.

## Command-line surface

```text
atom [options] entry.asm [output...]
atom --project project.json [output...]
atom self-host [output...]
```

The current options are:

```text
-p, --project FILE
-t, --target NAME
-DNAME[=VALUE]
-h, --help
-V, --version
```

Output paths positively select BIN, HEX, COM, NOBJ, LST, or D8 JSON by suffix.
With no output path, a direct build publishes one BIN file.

## Native top-level entry

| Entry | Contract |
| --- | --- |
| `AtomAssemble` | `IX` points at the 15-byte build descriptor; returns A status and carry after commit or failure |

The complete descriptor and status values are defined in
[`native-driver-abi.md`](../../native-driver-abi.md).

## Native tokenizer entries

| Entry | Contract |
| --- | --- |
| `AtomTokenizerReset` | Install one ordinal and half-open source interval |
| `AtomSourceReadByte` | Read one byte by part ordinal and logical offset |
| `AtomTokenizerNext` | Return the next token through the fixed nine-byte record |

See [`tokenizer-abi.md`](../../tokenizer-abi.md).

## Native symbol and pending entries

| Entry | Contract |
| --- | --- |
| `AtomPackSymbol` | Pack a global or `.`-private exact key and flags |
| `AtomSymbolReset` | Install the caller-owned symbol arena |
| `AtomSymbolFind` | Find a visible exact packed symbol |
| `AtomSymbolReference` | Find or insert one undefined reference target |
| `AtomSymbolDeclare` | Define an ordinary symbol without changing private scope |
| `AtomSymbolDeclareGlobalLabel` | Validate/evict private scope and define a new global label atomically |
| `AtomSymbolAdvanceScope` | Validate and evict current private records |
| `AtomSymbolValidateScope` | Validate the current private scope without eviction |
| `AtomPendingReset` | Install the caller-owned pending arena |
| `AtomPendingCheckCapacity` | Preflight one or more seven-byte pending records |
| `AtomPendingAdd` | Append one pending record for an undefined symbol |
| `AtomPendingPeek` | Read one matching pending record without removal |
| `AtomPendingTake` | Remove one matching record and keep the arena dense |

See [`symbol-abi.md`](../../symbol-abi.md).

## Native expression and parser entries

| Entry | Contract |
| --- | --- |
| `AtomExpressionParse` | Parse a concrete expression from the tokenizer stream |
| `AtomExpressionParseDeferred` | Parse a concrete result or one retained affine symbol form |
| `AtomParserParse` | Parse and atomically publish a validated ten-byte instruction record plus zero to two references |
| `AtomParserCheckReferences` | Preflight pending capacity for the current parsed references |
| `AtomParserQueueReferences` | Convert field offsets to logical addresses and append pending records |
| `AtomPatchLocate` | Map a validated operand index to patch kind and field offset |

See [`symbolic-parser-abi.md`](../../symbolic-parser-abi.md).

## Native encoder entries

| Entry | Contract |
| --- | --- |
| `AtomRadix40Pack` | Pack one through eight identifier characters into three words atomically |
| `AtomRecognizeMnemonic` | Binary-search the packed mnemonic table and return an ordinal |
| `AtomValidateForm` | Validate classes and return encoded length without reading concrete values |
| `AtomFormLength` | Alias of the validation/length entry |
| `AtomEncode` | Validate, encode through four-byte scratch, and commit exact bytes atomically |

See [`encoder-abi.md`](../../encoder-abi.md).

## Native statement entries

| Entry | Contract |
| --- | --- |
| `AtomAssemblePart` | Assemble the source part already installed by the tokenizer until part EOF |
| `AtomAssembleFinish` | Perform final pending, undefined-symbol, global, and private-scope validation |

See [`statements-abi.md`](../../statements-abi.md).

## Native output entries

| Entry | Contract |
| --- | --- |
| `AtomOutputReset` | Set flat bank-zero cursor and mathematical capacity |
| `AtomOutputCheckCapacity` | Check a complete span without changing output state |
| `AtomOutputEmitByte` | Submit one initialized IMAGE byte and advance |
| `AtomOutputEmitWord` | Submit one little-endian IMAGE word after complete preflight |
| `AtomOutputReserve` | Advance over uninitialized bytes |
| `AtomOutputSetOrigin` | Replace the logical target cursor |
| `AtomOutputEmitInstruction` | Encode, preflight, submit IMAGE bytes, and queue pending fields |
| `AtomOutputResolveSymbol` | Form, submit, and remove every pending patch for one definition |

The operating adapter supplies `AtomSinkBegin`, `AtomSinkImageByte`,
`AtomSinkPatchByte`, `AtomSinkPatchWord`, `AtomSinkCommit`, and `AtomSinkAbort`.
See [`output-abi.md`](../../output-abi.md).

## Public data boundaries

Tool consumers should treat these shapes as integration contracts even though
the package does not yet ship TypeScript declarations:

- resolved project and source-part records;
- source provenance and diagnostic locations;
- committed generation, IMAGE, PATCH, layout, and symbol records;
- rendered artifact object;
- `AtomAssemblyError` category, code, diagnostic, native, execution, and sink
  details;
- Atom NOBJ flat profile 0.2; and
- D8 map output accepted by Debug80.

Workspace addresses, internal native labels, proof stack addresses, native
short names, and private files below `src/host/` are implementation
details. Tools should not derive behavior from them.
