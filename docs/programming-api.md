# Atom from JavaScript

The `atom-z80` package runs the same Z80 assembler as the command-line program.
Node prepares source files and executes the core through the Z80 runtime.

## Assemble and write an output

With `main.asm` in the current directory:

```js
import {
  assembleAtomProject,
  publishAtomOutputFiles,
  renderAtomArtifacts,
} from "atom-z80";

const result = await assembleAtomProject({
  root: process.cwd(),
  entry: "main.asm",
  target: { start: 0x4000, capacity: 0x2000 },
});
const output = renderAtomArtifacts(result);

await publishAtomOutputFiles([
  { path: "build/main.bin", bytes: output.bin },
  { path: "build/main.hex", bytes: output.hex },
]);
```

`root` is an absolute directory and `entry` is relative to it. Atom reads the
entry as a stream and opens each included or `INCBIN` file when it reaches it,
so every source byte is read once. `definitions: { DEBUG: 1 }` supplies command
definitions.

Rendering returns `bin` as a `Uint8Array`, `hex` and `listing` as strings,
`d8` as an object and `d8Text` as its JSON text. The optional `fill` byte supplies
gaps and uninitialised reservations. It defaults to zero.

The publisher stages every selected destination before replacing earlier output.
A staging or replacement failure restores the previous outputs.

## Addresses and execution limits

The example's target covers `$4000` to `$5FFF`. `ORG` moves the output cursor
within that interval. Rendering begins at the target's start by default.
The default target starts at zero, so a source `ORG $4000` would leave leading
fill bytes in its BIN output. Setting the target as above gives the four-byte
image from the [first program](using-atom.md#a-first-program).

Start and capacity are 16-bit values. Their sum may reach `$10000` but cannot
wrap. The default capacity is `$FFFF - start`, so emitting at `$FFFF` requires
an explicit capacity that reaches that address. Zero capacity describes an
empty target. Builds use bank zero and accept at most 255 source parts of
65,535 bytes each.

The runner stops after 200,000,000 instructions or 2,000,000,000 T-states by
default. `maxInstructions` and `maxCycles` change those limits.

## Results and errors

The result includes the `project`, assembled `generation`, `execution`
statistics and `native` status. `project.parts` lists every source file Atom
read, in the order it reached them, with the entry first. The generation contains emitted image bytes,
forward-reference patches, symbols and placement information.

Opening the entry throws `SourcePreparationError` and assembly throws
`AtomAssemblyError`. Each has a category and code. Errors in includes and `%`
directives are assembly errors in the `source` category. When the host refused
an include, for example because it escapes the project root, `cause` holds the
host's own error. Preparation positions are in
`location` and assembly positions are in `diagnostic`. Both use `logicalIdentity` for the
filename and one-based `line` and `column` values. Source-part `ordinal` and
byte `offset` are zero-based.

Native assembly errors also expose `text`, `messageNumber` and, where applicable,
`symbol` and `relatedDiagnostic`. The full `message` includes the source position.
Filesystem failures can surface the underlying Node error.

## Prepared source and native hosts

`resolveAtomProject()` opens the entry file and returns the services Atom uses
to open the rest. It reads nothing else. `assembleResolvedAtomProject()` runs
that project. Hosts supplying source from another medium can provide their own
`openFile` and `readBinary` services in place of the resolved ones.

For a Z80 Tool Services host, the native harness builder is available through
its package subpath:

```js
import { buildNativeObjectHarness } from "atom-z80/native-builder";

const built = await buildNativeObjectHarness();
```

The result contains executable bytes, relocated workspace bytes when requested,
a D8 map and a build report. The [builder options](../src/host/build/object-harness-builder.d.mts)
cover code, image and workspace origins and platform source additions.

## Source conversion

`translateAzmSourceToAtom(source, { sourceName })` converts AZM source in memory
and returns an LF-normalised string. It performs no file operations.
An unsupported construct throws `AtomAssemblyError` with category `translation`
and a positioned diagnostic. [Using Atom](using-atom.md#converting-older-source)
describes the command-line converter.
