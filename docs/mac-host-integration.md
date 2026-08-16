# Mac host and native Atom integration

`assembleAtomProject` is the first complete host-to-Z80 assembly entry. The Mac
host reads the project, resolves `%include` dependencies, evaluates host
conditionals, and masks host directives. Debug80 then executes the native Atom
tokenizer, symbol table, statements, encoder, patch resolver, and multipart
driver.

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

This is a Node API rather than the final command-line interface. Artifact
serialization and atomic file publication belong to Phase 5.

## Execution boundary

The host snapshots each prepared compiler buffer before it writes Z80 memory.
It constructs the 15-byte native build descriptor and one five-byte descriptor
per source part, then enters `AtomAssemble` with IX pointing at the build
descriptor. The runner checks the return PC, final SP, stack canaries, source
buffers, descriptors, and every immutable code/table interval after the call.

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
records. `generation.highWater` retains the greatest address reached by output,
`ORG`, or an uninitialized `DS` reservation even when the final cursor later
moves backward. The byte payloads are frozen number arrays.
`materializeAtomGeneration` returns a new `Uint8Array`, so changing that copy
cannot alter the committed generation.

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

Equal-length preprocessing masks preserve the offset relation. An error in an
included file therefore names that file rather than the entry file or an
anonymous concatenated stream.

## Host proof memory layout

The Debug80 integration uses this measured layout:

| Region | Address | Bytes |
| --- | --- | ---: |
| Linked native core, fixed workspace, and host stubs | `$0000..$332F` | 13,103 |
| Free space below the descriptor bank boundary | `$332F..$4000` | 3,281 |
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
- `loadNativeAtomCore` for the strict-contract bootstrap image; and
- `AtomAssemblyError`, native limits, and host sink status constants.

The runner currently invokes AZM to build the native core. Phase 5 will package
a pinned core artifact so an installed Atom command does not require a source
checkout or a bootstrap assembly on every new process.

## Verification

```sh
npm run test:host
npm run annotate:contracts
npm run measure:host-native
```

The focused integration tests cover host preprocessing through native output,
forward patch timing, exact included-file and undefined-name diagnostics,
nonzero bank rejection, sink status and exception failures, append-only `ORG`
behavior, target commit bounds, exact source and part capacities, deterministic
fresh runs, `DS` high-water retention, intermediate `ORG` and `DS` range
failures, fail-closed stubs, the complete 64 KiB map, and runtime-budget cleanup.
