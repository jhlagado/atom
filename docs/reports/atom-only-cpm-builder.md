# ATOM-only CP/M builder

2026-09-05. Based on `6beb7d0` on `range-and-bootstrap`. This checkpoint
changes development builders; no guest command, binary format or application
behavior changes. It is not a published release.

## Build boundary

`generate-cpm22.mjs` now assembles the linked core and CP/M adapter through
the public ATOM host API. The AZM compiler, Atom-to-AZM translation, temporary
source files and static register-analysis invocation are removed. The shared
final-image renderer resolves through the installed Tool Services package
export, replacing the sibling-checkout path.

The private `cpm22-atom-source.mjs` helper maps long link identifiers to
deterministic, collision-free names within ATOM's eight-character limit. It
preserves strings, character literals, numeric tokens and comments. Pure-name
forward equates move after their target declarations; ATOM evaluates all
expressions and encodes all instructions. Prepared source parts end on whole
lines and contain at most 65,535 UTF-8 bytes. Diagnostics identify these
prepared parts, not original source line positions. This preparation is a
private builder mechanism, not an extension of the public ATOM language.

The same helper builds the two CP/M output-size candidates. Their directives
now use ATOM syntax. These remain incomplete lower-bound kernels: assembling
them proves byte counts, not usable alternative output implementations.

## Verification

The CP/M bootstrap regression first failed on its AZM import. The separate
output-candidate regression also failed on an AZM import before migration.
Both now pass with imports blocked by the repository's rejection loader.

The final focused run passed 49 tests: 32 CP/M execution cases, three guarded
build checks, seven source-preparation cases and seven architecture/document
checks. It included exact binary and census comparisons, duplicate and missing
names, cyclic aliases, local scopes, literal preservation, UTF-8 part limits,
output rollback, includes, source limits and atomic output-capacity rejection.

```sh
node --test test/host-cpm-source.test.mjs test/host-cpm-bootstrap.test.mjs \
  test/cpm22.test.mjs test/architecture-authority.test.mjs \
  test/host-documentation-contract.test.mjs
```

That run also used an outer Node import guard. The isolated build test copies
the required source and artifacts to a temporary directory with no sibling
Tool Services checkout. It links the existing installed dependencies into that
directory and reproduces the checked CP/M artifacts. This proves directory
independence, not a new clean package installation.

The unchanged executable is 15,029 bytes, with SHA-256
`cdd5d05e3131b23288914b354929cfb5c2e1639d71c35f337e8fcec8c2bdfcbb`.
Its adapter account remains 2,254 code bytes, 259 immutable bytes and 117
resident workspace bytes. External source/resolver workspace remains 4,476
bytes and output storage remains 18,304 bytes. All byte deltas are zero.

The complete `npm run build` passed with AZM imports blocked, regenerating
the native core, object harness and CP/M executable. A tracked diff confirmed
that every generated asset and proof remained unchanged.

Triptych's guarded `npm run check` also passed with its existing ATOM pin.
That consumer regression does not qualify this unpublished ATOM revision.

A fresh guarded `node test/measure-cpm22.mjs` run produced 34 output bytes
using 147,583 assembler instructions and 1,820,876 T-states. Including command
loading and surrounding execution gives 196,866 instructions and 2,584,966
T-states. Stack high-water remains 32 bytes. These match the retained census;
they are emulator measurements, not ESP32 timing.

The random-record candidate remains 142 code bytes and 137 workspace bytes;
the object-materializer candidate remains 165 and 135 respectively. The
complete-implementation size hypotheses in the existing report are unchanged
and remain hypotheses.

## Remaining release work

The guarded `npm test` stopped at the AZM package lookup in
`verify-dependencies.mjs`. Historical differential tests also still require
migration. The complete test/release gate therefore remains unfinished. No static
register analysis was performed in this migration. The ATOM `$FFFF` output
boundary and Nucleus reconciliation remain open. Downstream pins, package
publication, Pages deployment and hardware qualification are unchanged.
