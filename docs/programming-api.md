# Programming API

The `atom-z80` package exposes Atom as an in-process assembler. Applications
can prepare source, run the Z80 core, render files and publish selected outputs
without parsing command-line text.

## Assemble a project

```js
import { assembleAtomProject, renderAtomArtifacts } from "atom-z80";

const result = await assembleAtomProject({
  root: "/ABSOLUTE/PROJECT/ROOT",
  entry: "src/main.asm",
  definitions: { DEBUG: 1 },
  target: { start: 0x4000, capacity: 0x2000 },
});

const artifacts = renderAtomArtifacts(result, {
  entryAddress: 0x4000,
  fill: 0,
});
```

`root` must be an absolute directory. `entry` is relative to that root. The
host resolves `%INCLUDE`, evaluates conditional directives and snapshots every
source and `INCBIN` file before the Z80 assembler starts.

The result contains four main records:

| Field | Contents |
| --- | --- |
| `project` | Ordered source parts and their provenance |
| `generation` | IMAGE, PATCH, layout, symbol and target data |
| `execution` | Instruction, cycle, service and stack observations |
| `native` | Native status and nested failure detail |

`assembleResolvedAtomProject()` accepts an already prepared project. This is
the lower-level boundary for a host that supplies source parts without the Node
filesystem resolver.

## Rendered output

`renderAtomArtifacts()` returns the general output representations in memory:

```text
nobj       Uint8Array
bin        Uint8Array
hex        string
listing    string
d8         object
d8Text     string
```

The fill byte supplies gaps and uninitialised reservations in flat BIN and HEX
output. It does not change Atom's IMAGE and PATCH records.

COM is the same flat byte image under CP/M's `$0100` load convention. Use
`writeAtomCom()` to validate the base and entry address and return its bytes.

Use `publishAtomOutputFiles()` when an application wants the same transactional
file replacement as the command-line program:

```js
import {
  assembleAtomProject,
  publishAtomOutputFiles,
  renderAtomArtifacts,
} from "atom-z80";

const result = await assembleAtomProject({
  root: PROJECT_ROOT,
  entry: "src/main.asm",
});
const artifacts = renderAtomArtifacts(result);

await publishAtomOutputFiles([
  { path: "build/main.hex", bytes: artifacts.hex },
  { path: "build/main.d8.json", bytes: artifacts.d8Text },
]);
```

The publisher stages every selected file before replacing an existing output.
A staging or replacement failure restores the previous files.

`publishAtomArtifacts()` provides a separate content-addressed publication
model with an atomic `current` link. Most applications should use the simpler
selected-file publisher.

## Diagnostics

The high-level preparation and assembly entries report
`SourcePreparationError` or `AtomAssemblyError`. These expose a stable category
and code. A positioned diagnostic can include:

```text
logicalIdentity
ordinal
offset
line
column
```

Line and column are one-based. Offset and ordinal are zero-based. Native
failures are mapped through the original source bytes, so masked preprocessor
lines do not shift positions.

Low-level artifact writers validate their own arguments and may throw
`RangeError`. File publication can also surface an underlying filesystem error.

## Lower-level interfaces

The package root also exports:

- `resolveAtomProject()` for source preparation without assembly
- `loadNativeAtomCore()` for the checked Z80 image and symbol map
- `createMemoryAtomSink()` and `materializeAtomGeneration()` for IMAGE and
  PATCH consumers
- `writeAtomNobj()`, `parseAtomNobj()` and `materializeAtomNobj()`
- `writeAtomCom()`, `writeIntelHex()`, `writeAtomListing()` and `writeAtomD8()`
- `createNamedObjectAtomAdapter()` for the Z80 Tool Services boundary
- `createDebug80ExecutionAdapter()` and
  `createTriptychWasmExecutionAdapter()`
- `createSelfHostedAtomCore()` for the two-generation self-host path
- `translateAzmSourceToAtom()` for strict source conversion

Import these functions from `atom-z80`. Files below `src/host/` are private
implementation modules.

## Native object harness builder

Hosts that use Z80 Tool Services can build the native harness through its
public package subpath:

```js
import { buildNativeObjectHarness } from "atom-z80/native-builder";

const built = await buildNativeObjectHarness();
```

The result contains the executable bytes, optional relocated workspace bytes,
a D8 map and a measured build report. Builder options can set the code, image
and workspace origins and can add platform prelude or postlude source.

## Execution limits

The desktop runner defaults to 200,000,000 Z80 instructions and 2,000,000,000
T-states. Callers may lower or raise these budgets with `maxInstructions` and
`maxCycles`.

One build accepts at most 255 ordered source parts. Each part may contain at
most 65,535 bytes and the current output profile uses bank zero.

Target start and capacity are 16-bit values whose mathematical sum may reach
`$10000` but may not wrap. Capacity is at most 65,535 and zero means an empty
target. The default capacity is `$FFFF - start`, so a build that must emit at
address `$FFFF` needs an explicit capacity that reaches it.

Callers of `assembleResolvedAtomProject()` can provide `nativeMemoryLayout` to
select symbol and pending arenas that suit their own memory map. The higher
level `assembleAtomProject()` entry uses the desktop layout.
