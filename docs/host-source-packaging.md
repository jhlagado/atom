# Atom host source packaging

Atom separates filesystem work from resident assembly. The Mac host resolves
source dependencies, evaluates host conditionals, masks preprocessing syntax,
resolves Atom binary inputs, and produces an ordered set of source parts. The
native Z80 assembler receives those parts as a stream and has no filesystem or
dependency-graph interface.

The source packager does not compile or publish an Atom object. It returns a
fully validated ordered set of source parts. `assembleAtomProject` passes those
parts to the native streaming adapter after preparation succeeds.

## Public preparation API

`resolveAtomProject` is the Atom-specific composition entry point:

```js
import { resolveAtomProject } from "./src/host/resolve-atom-project.mjs";

const project = await resolveAtomProject({
  root: "/absolute/project/root",
  entry: "src/main.asm",
  definitions: { DEBUG: 1 },
  placement: {
    defaultBank: 0,
    banks: { "src/video.asm": 1 },
  },
});
```

The result contains:

- `parts`, in compilation order;
- `bankArray`, indexed by source-part ordinal;
- parsed `sourcePlan` records and canonical `sourcePlanBytes`;
- the frozen preprocessor definition state; and
- the retained logical-path byte count.

Each part records its ordinal, bank, three source identities, original bytes,
equal-length compiler bytes, dependencies, masked or transformed ranges,
binary snapshots, and provenance. The
composition snapshots definitions, placement, and limits before its first
filesystem wait. The source reader reads each selected physical file once, so
later filesystem changes cannot alter the bytes prepared for that build.
Record containers and metadata are frozen. The returned `Uint8Array` buffers
remain ordinary mutable JavaScript storage; consumers must treat them as
read-only until the streaming adapter has consumed them.

## Source identities and resolution

The packager keeps three identities separate:

1. `physicalPath` is the canonical path opened on the current host.
2. `dependencyIdentity` identifies a physical source for diamond and cycle
   detection.
3. `logicalIdentity` is the normalized project-relative path used by SP1,
   diagnostics, listing and D8 attribution, and placement rules.

An include path is relative to its importing file. Absolute paths, lexical
escapes, and symlink targets outside the project root fail before compilation.
The reader also rejects case-conflicting physical spellings.

Resolution uses deterministic depth-first postorder. Dependencies precede
their importer, sibling order follows the source, and a diamond emits its
shared dependency once. A repeated direct include is an error rather than a
request for textual repetition. Cycles report the complete active edge cycle
with source locations.

The default Node limits are:

| Capacity | Default |
| --- | ---: |
| Source parts | 255 |
| Dependency depth, including the entry | 64 |
| Logical path | 255 ASCII bytes |
| Retained logical paths | 65,536 bytes |
| Bank ordinal | 255 |

Callers may lower these limits. Every exact limit is accepted; the first value
beyond it is rejected during preparation.

The native Atom driver and SP1 wire format both accept 1 through 255 parts.
The host rejects a 256th part during preparation, before the Z80 runtime starts.

The current Atom output ABI is flat bank zero. `assembleAtomProject` sets the
resolver's maximum bank to zero, so a nonzero placement fails before the Z80
runtime starts. The general source-plan format keeps its bank field for shared
packager consumers and later target work.

## Placement and SP1

Placement remains outside Atom source. `defaultBank` applies to every source
without a path-specific assignment; `banks` maps logical project paths to bank
ordinals. Preparation rejects invalid banks, conflicting aliases, assignments
for missing or unreachable sources, and an unassigned part when no default is
present.

The portable source plan uses restricted ASCII SP1 records:

```text
SP1 4
P 2 hardware.asm
P 1 display.asm
P 0 input.asm
P 0 main.asm
END
```

Record order determines the source-part ordinal. The serializer emits LF. The
parser accepts LF and CRLF, validates the declared count and every capacity,
requires one exact `END`, and rejects trailing bytes. Logical paths contain
ASCII letters, digits, `.`, `_`, `-`, and `/`; empty, `.` and `..` components
are invalid.

`writeSourcePlanAtomically` serializes and reparses the complete plan before it
opens a temporary file. It uses an exclusive temporary path and replaces the
destination by rename only after the write and sync complete. Callers resolve
the project before invoking the writer, so a preprocessing failure never opens
the destination. Serialization, write, and rename failures preserve the
previous published plan.

## Atom preprocessing

A host directive starts when `%` is the first non-space byte on a line and an
ASCII letter follows it. Directive names and definition names are
case-insensitive. The supported directives are:

```asm
%DEFINE DEBUG %1
%INCLUDE "lib/console.asm"
%IF DEBUG
    CALL DEBUGRT
%ELSE
    NOP
%ENDIF
```

`%DEFINE` binds one immutable host value. It performs no textual substitution
and does not create an Atom assembler symbol; source that needs the same value
must also declare an `EQU`. Project definitions precede source definitions, and
duplicate names fail even when the values match. Source definitions occur only
in the entry's leading preprocessing header. Dependencies may test the frozen
environment but may not add definitions.

Conditions contain one literal or defined name. Zero is false; every other
16-bit value is true. The accepted literal spellings are decimal, `$`-prefixed
hexadecimal, `%`-prefixed binary, digit-led `H` hexadecimal, and `B` binary.
Values outside 0 through 65,535, undefined names, extra tokens, and malformed
suffixes fail preparation.

An active `%INCLUDE` creates an import-once dependency edge. Includes occur
only in a part's leading header. A header conditional may select includes but
must close before ordinary Atom source. Body conditionals may mask source but
cannot include files or define names. Nesting must balance within each part.

The host replaces every non-newline byte on directive lines and inactive
ordinary lines with ASCII space. CR and LF remain unchanged, so each compiler
offset maps directly to the same offset in the original part. `%` followed by
`0` or `1` remains a binary literal, and infix `%` remains the remainder
operator. The native tokenizer reports an explicit unprocessed-directive error
if a line-start host directive reaches it.

## Binary inclusion

`INCBIN "PATH"` is assembler syntax with host-owned filesystem semantics. After
dependency ordering and placement, the Atom composition layer resolves the
path relative to its containing source, applies the source reader's root,
symlink, and exact-case checks, and snapshots the complete binary. Inactive
conditional lines create no binary read.

The host replaces the active directive with an equal-length `DS COUNT,0`
compiler line. Original bytes, line endings, offsets, and the source identity
remain unchanged. Native labels, branches, capacity checks, and the streaming
output cursor therefore account for the binary without filesystem code in the
Z80 core. The Mac output bridge replaces the attributed zero IMAGE bytes with
the snapshot and rejects any count mismatch before commit.

The path is not an SP1 source part and does not enter the dependency graph.
Provenance records its logical binary identity, source line, transformed range,
and byte length. Listings and D8 ranges remain attached to the original
`INCBIN` line.

## Extraction boundary

The language-neutral modules under `src/host/source-packager/` contain path
confinement, identity, graph, placement, provenance, SP1, and atomic plan code.
They import only Node built-ins and other neutral modules. Atom syntax remains
under `src/host/atom/`, and `resolve-atom-project.mjs` supplies the composition.

The neutral source-packager modules are currently owned by Atom. They may move
to a Debug80 package or app after Atom and Nucleus host requirements stabilize.

Nucleus can use the neutral resolver with its own comment-shaped directive
profile and byte-preserving emission policy. Atom's conditional masking and
native token rules do not enter the neutral package.

## Proof map

The named Node tests below map the agreed source-packager requirements to
executable observations.

| Requirement | Named proof |
| --- | --- |
| Diamond deduplication and sibling order | `Atom composition resolves, masks, places, snapshots, and relocates one diamond` |
| Repeated include, missing source, root escape, alias and cycle diagnostics | `Atom composition rejects dependency, preprocessing, and placement failures` |
| Physical symlink-target confinement | `reader rejects a symlink whose real target escapes the project root` |
| LF, CRLF, lone CR, truncation, `END`, and trailing-data handling | `SP1 parses complete LF and CRLF plans`; `SP1 rejects non-ASCII and invalid newline bytes`; `SP1 requires one exact END and rejects trailing data`; `SP1 rejects count mismatches and record-position errors` |
| Count and wire capacities | `SP1 wire capacities pass at 255 and fail at 256`; `SP1 enforces caller capacities exactly` |
| Graph, path, retained-path and bank capacities | `Atom composition enforces every graph and placement capacity at the boundary` |
| Relocation-stable logical identity and compiler bytes | `Atom composition resolves, masks, places, snapshots, and relocates one diamond` |
| Path-keyed placement after order changes | `path-keyed placement follows a part while unrelated order changes` |
| Byte-preserving neutral/Nucleus profile | `passthrough profile preserves the exact original byte object` |
| Atom length, newline, active-byte and mask preservation | `masking preserves length and every LF or CRLF byte`; `Atom composition resolves, masks, places, snapshots, and relocates one diamond` |
| `%DEFINE DEBUG %1` and percent-expression separation | `directive recognition does not steal binary literals, remainder, or comments` |
| Intel and prefix literal equivalence | `Intel suffix conditions select the same branches as prefix spellings`; `Intel suffix literals match prefix spellings with exact 16-bit boundaries` |
| Unknown and leaked directives | `Atom composition rejects dependency, preprocessing, and placement failures`; `leaked line-start host directives fail without stealing percent expressions` |
| Nested branches, inactive includes and imbalance | `nested conditions mask only inactive ordinary lines`; `inactive includes create no dependency while directive structure is still checked`; `Atom composition selects only active includes` |
| Original identity and offset attribution | `masked ranges and dependency locations use original byte offsets`; `resolved parts expose complete immutable provenance and identity offsets` |
| Confined binary snapshot and equal-length lowering | `INCBIN snapshots one confined binary and preserves native addresses` |
| Binary listing and D8 attribution | `INCBIN bytes retain their source line in listings and D8` |
| Binary syntax, path, size, and bridge failures | `INCBIN rejects malformed, escaping, missing, and oversized inputs`; `the native bridge fails closed when supplied INCBIN metadata disagrees with DS` |
| Explicit and resolved compiler inputs | `Atom composition resolves, masks, places, snapshots, and relocates one diamond` |
| Snapshot stability after filesystem mutation | `reader snapshots each dependency once and ignores later filesystem mutation`; `Atom composition resolves, masks, places, snapshots, and relocates one diamond` |
| Failure before publication | `preprocessing failure returns no project and preserves a prior SP1 artifact`; `write failure preserves the prior plan and removes only its temp`; `rename failure preserves the prior plan and removes only its temp` |
| Neutral static and dynamic import boundary | `neutral host modules do not import Atom implementation`; `neutral import proof rejects dynamic Atom imports` |
| Resident compiler diagnostics | `undefined global reports its exact source part, offset, and packed name`; existing tokenizer, expression, parser, and statement diagnostic proofs |
| Packager-to-native composition | `the Mac host resolves, masks, and executes one project through native Atom` |
| Included-part diagnostics | `an error in an included part is attributed to that physical source identity` |
| Listing lines and D8 ranges | `INCBIN bytes retain their source line in listings and D8`; the general artifact proofs cover ordinary source |

Prepared compiler bytes and provenance are proved at this boundary. The native
host runner copies those bytes before execution and checks them again when the
Z80 routine returns. The artifact pipeline proves listing and D8 attribution
for both ordinary source and binary inclusion.

## Verification

```sh
npm run test:host
npm test
npm run measure:tokenizer
npm run measure:host-native
```

`npm test` rebuilds the frozen AZM and Debug80 runtime dependencies, assembles
the native proofs with strict register contracts, executes them, and checks the
declared 64 KiB memory profiles.
