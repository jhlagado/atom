# Retiring the live AZM test oracle

2026-09-05. Based on ATOM revision
`7e00661666fe8362276aa934598dce8fb82add5a` on `range-and-bootstrap`.

## Reference preservation

The remaining AZM dependency supplied expected bytes and rejection decisions
to instruction, expression, parser, statement, output and driver tests. Using
ATOM to compute those expectations would remove their independent comparison.
The replacement is fixed historical data, not another assembler implementation.

A one-time archival run intercepted `compileSource` in the installed AZM
0.3.9 package while executing the eight existing comparison test files listed
in the fixture provenance. All 117 tests passed. Each request retained its
exact wrapped source and either the emitted byte array or a rejection marker.
Repeated requests were checked for identical outcomes before deduplication.
This was an isolated historical-oracle capture; no production image was built
with AZM.

The fixture contains 6,788 distinct requests: 6,262 successful byte arrays and
526 rejections. Its record digest is
`cbc3d0f619e767a7c5f96abc06502a6fa5f818480acda4bb4a883a5820a33aba`.
The historical package's compiled-tree digest is
`7eac1bb9af4af9d566470ef207492fbafcd04bb6915b176f2a4a7cdaf8f98d67`.
That tree digest hashes JSON-encoded, path-sorted `[relativePath, sha256]`
pairs for every file below the installed package's `dist/src/` directory.
It identifies the actual installed code, not an inferred source revision.

The pre-existing census still requires all 3,445 instruction cases across 69
mnemonics, with its unchanged source/record hash. Extra reference entries cover
case variants, indexed aliases, concrete arithmetic and complete statements.
The lookup helper checks the record digest, rejects duplicate keys, returns
independent byte arrays and fails on every unrecorded request. There is no
fallback compiler. New expectations require independent review; they must not
be generated from ATOM and labelled historical evidence.

## Migration

The direct-entry tests and two measurement callers now import
`test/reference-fixtures.mjs`. Their register, stack, canary, memory-write,
capacity and exact-byte assertions remain. The original comparison corpus
passed all 117 tests again with AZM imports blocked; two fixture identity and
failure-behavior tests bring the focused result to 119 passing tests.

The two source-converter integration tests use explicit expected instruction
and data bytes, including initialized address sets and an uninitialized
reservation. Six converter tests passed with AZM imports blocked. The converter
test also translates the generated legacy text back to ATOM and checks its
assembled bytes against the explicit expectation. This retains a discriminator
for lost or changed translation output. The converter APIs remain available;
only their live comparison compiler was removed.

`package.json` and `verify-dependencies.mjs` no longer require AZM. The package
policy test rejects its reintroduction as a dependency. No source assembler or
resident image changed, so resident code, workspace, generated output and guest
execution costs are unchanged. Fixture data is test-only and is not shipped in
the npm package. Static register analysis is not part of these tests.

The first guarded full release run passed 356 of 357 tests. Its only failure
was the neutral-module import test's stale sibling-checkout path. That test
now resolves the installed Tool Services export and inspects its actual source
directory. All five boundary tests pass, including new static external-import
and directory-escape discriminators. The neutral import restrictions remain.

The next guarded `npm run release:check` passed all 358 tests, followed by
the native-host and self-host measurements. The packed CLI installed offline
with no AZM in the consumer and ran from an unrelated directory. The two
self-host generations retained exact bytes, initialized-address sets and
recovered symbols: 11,682 code/table bytes and 714 fixed-workspace bytes, for
a 12,396-byte resident extent. Each generation executed 101,840,573 instructions
and 1,086,338,471 T-states. No generated image changed.

Separate guarded encoder and parser measurements passed. Encoder coverage
remains 3,445 sources, 3,310 normalized records, 3,222 byte sequences, 526
rejected source cases and 2,453 systematic invalid records. The parser also
covered 968 indexed-zero aliases. Fresh encoder output identifies the checked
core digest; the old Debug80 revision is explicitly labelled historical.
The native-host report no longer implies that static register analysis ran.

The refreshed package census passed a separate guarded verification: 397
entries and 2,219,145 unpacked bytes, 2,511 bytes above the previous census.
The reference fixture remains outside the packaged file list.

Triptych's guarded `npm run check` passed with its unchanged published ATOM
pin. That result is a consumer regression check, not qualification of this
unpublished ATOM revision.

## Remaining boundaries

The `$FFFF` output-range issue, Nucleus reconciliation and downstream pin
updates remain separate work. This checkpoint does not establish publication,
Pages deployment, Linux execution, mobile behavior or ESP32 measurements.
