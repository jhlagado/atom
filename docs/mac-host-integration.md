# Mac host and native Atom integration

`assembleAtomProject` is the first complete host-to-Z80 assembly entry. The Mac
host reads the project, resolves `%INCLUDE` dependencies and `INCBIN` inputs,
evaluates host conditionals, and masks or lowers host-owned syntax. Debug80
then executes the native Atom tokenizer, symbol table, statements, encoder,
patch resolver, and multipart driver.

```js
import {
  assembleAtomProject,
  materializeAtomGeneration,
} from "./src/host/index.mjs";

const result = await assembleAtomProject({
  root: "/absolute/project/root",
  entry: "src/main.asm",
  definitions: { DEBUG: 1 },
  target: { start: 0x4000, capacity: 0x2000 },
});

const { base, bytes } = materializeAtomGeneration(result.generation);
```

The `atom` executable wraps this API with deterministic artifact rendering and
atomic generation publication. [`command-line.md`](command-line.md) documents
the installed command.

## Execution boundary

The host snapshots each prepared compiler buffer before it writes Z80 memory.
It constructs the 15-byte native build descriptor and one five-byte descriptor
per source part, then enters `AtomAssemble` with IX pointing at the build
descriptor. Projects up to 24 KiB remain resident in one source window. For a
larger project, every part must fit that window and the Mac adapter installs
the next part when the native driver calls `AtomTokenizerReset`. The native
driver still processes an ordered descriptor stream and contains no filesystem
logic.

The runner checks the return PC, final SP, stack canaries, descriptors, and
every immutable code/table interval after the call. For paged input it also
checks the complete 24 KiB window, including the `$A5` padding after the source
part, before installing the next page and after the final return. Debug80 marks
the source window read-only to CPU writes. The Mac adapter installs pages by
writing the host memory array directly.

The native image contains six fail-closed sink stubs. Debug80 stops at each
entry address and transfers the register arguments to the host memory sink:

| Native call | Host record |
| --- | --- |
| `AtomSinkBegin` | Opens one tentative generation. |
| `AtomSinkImageByte` | Appends one bank-zero IMAGE byte. |
| `AtomSinkPatchByte` | Appends one final one-byte PATCH. |
| `AtomSinkPatchWord` | Appends one final little-endian two-byte PATCH. |
| `AtomSinkCommit` | Validates and retains the completed logical generation. |
| `AtomSinkAbort` | Discards all tentative records. |

The host supplies the returned A and carry values and resumes at the native
return address. A JavaScript exception inside a service becomes status `$EF`,
which lets the native driver take its ordinary failure path and call abort.
Runtime budget or halt failures also abort an open host generation.

`generation.images` and `generation.patches` are frozen append-only logical
records with source positions. `generation.layout` records `ORG` and
uninitialized `DS` extents, and `generation.symbols` records successful label
and `EQU` definitions before private-scope eviction. `generation.highWater`
retains the greatest address reached by output, `ORG`, or an uninitialized
`DS` reservation even when the final cursor later moves backward. The byte
payloads are frozen number arrays.
`materializeAtomGeneration` returns a new `Uint8Array`, so changing that copy
cannot alter the committed generation.

An active `INCBIN` line reaches the native core as an equal-length initialized
`DS` statement. The runner retains the binary snapshot keyed by source part and
line, substitutes those bytes in `AtomSinkImageByte`, and checks the exact byte
count before commit. The six-call native sink ABI does not change.

## Current target rules

Native Atom currently emits flat bank-zero output. The integrated resolver
rejects nonzero source placement before starting Debug80. The memory sink also
checks every bank argument as a defensive invariant.

The target start and capacity are unsigned 16-bit descriptor fields. Their sum
must be at most `$FFFF`; the current half-open native range cannot represent an
end address of `$10000`. IMAGE and PATCH records must remain inside that range.
The runner observes native `ORG` and uninitialized `DS` entries without
changing their Z80 implementation. It retains their logical high-water mark
and exact directive position. The commit check therefore catches an
intermediate cursor or reservation outside the target range even if a later
`ORG` returns the final cursor to a valid address.

IMAGE records may leave forward gaps but may not descend or overlap. PATCH
records can modify an earlier IMAGE byte once. A backward `ORG` is valid while
the next IMAGE remains at or beyond the prior IMAGE end. Earlier `DS` extent is
still retained in the materialized range.

## Structured diagnostics

Preparation failures remain `SourcePackagerError` values. Native or adapter
failures use `AtomAssemblyError` with a category and code. A native source
diagnostic includes:

- logical source identity and zero-based part ordinal;
- exact source byte offset;
- one-based line and byte column calculated from the original unmasked source;
- native driver, statement, and nested status values; and
- the unpacked case-folded name for a final undefined symbol.

Equal-length preprocessing masks and `INCBIN` lowering preserve the offset
relation. An error in an included file therefore names that file rather than
the entry file or an anonymous concatenated stream.

## Host proof memory layout

The Debug80 integration uses this measured layout:

| Region | Address | Bytes |
| --- | --- | ---: |
| Linked native core, fixed workspace, and host stubs | `$0000..$35F4` | 13,812 |
| Free space below the descriptor bank boundary | `$35F4..$4000` | 2,572 |
| Build and part-descriptor allocation | `$4000..$4100` | 256 |
| Symbol arena | `$4100..$7500` | 13,312 |
| Pending-reference arena | `$7500..$7F00` | 2,560 |
| Guard gap | `$7F00..$8000` | 256 |
| Source window | `$8000..$E000` | 24,576 |
| Free space below the proof stack | `$E000..$FE00` | 7,680 |
| Proof stack | `$FE00..$FF00` | 256 |
| Reserved top page | `$FF00..$10000` | 256 |

The symbol arena holds at most 1,664 simultaneous eight-byte records. Private
records remain transient across global scopes. The pending arena holds 426
complete six-byte records. These are Mac-host proof capacities, not a proposed
TEC-1 deployment map; the TEC operating layer will choose its own caller-owned
source, symbol, pending, and stack regions.

## Public modules

`src/host/index.mjs` exports:

- `assembleAtomProject` for filesystem preparation followed by native assembly;
- `assembleResolvedAtomProject` for an already prepared ordered project;
- `resolveAtomProject` for preparation alone;
- `createMemoryAtomSink` and `materializeAtomGeneration` for logical output;
- NOBJ, binary, HEX, listing, and D8 renderers;
- atomic artifact-set publication;
- `loadNativeAtomCore` for the pinned strict-contract image; and
- deterministic Atom-to-AZM and self-host source translation;
- `createSelfHostedAtomCore` for second-generation proof execution; and
- `AtomAssemblyError`, native limits, and host sink status constants.

The runner reads `assets/native-core.json` and verifies its SHA-256. AZM is used
only by the development generator and stale-asset check; it is absent from the
installed package.

## Verification

```sh
npm run test:host
node node_modules/@jhlagado/azm/dist/src/cli.js --rc strict --contracts \
  --nobin --nohex --nod8m --nolst asm/atom-host-runtime.asm
npm run measure:host-native
npm run measure:self-host
```

The focused integration tests cover host preprocessing through native output,
forward patch timing, exact included-file and undefined-name diagnostics,
nonzero bank rejection, sink status and exception failures, append-only `ORG`
behavior, target commit bounds, exact source and part capacities, deterministic
fresh runs, `DS` high-water retention, intermediate `ORG` and `DS` range
failures, fail-closed stubs, the complete 64 KiB map, and runtime-budget cleanup.
The binary-inclusion proofs additionally cover snapshot stability, path and
size failures, exact initialized bytes, native address calculation, bridge
count mismatches, listing text, and D8 data ranges.
