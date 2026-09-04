# Final-byte output boundary checkpoint

2026-09-05. Qualified local candidate on `range-and-bootstrap`, based on
`b89714d`. The guarded release check passed; this revision has not been
published or selected by a downstream release pin.

## Behavior

The native descriptor now accepts a mathematical target end of `$10000`.
Previously, both host validation and the native driver rejected this extent.
Start and capacity remain unsigned words; capacity zero remains empty.
The omitted-capacity host default is unchanged.

The desktop bridge converts a zero cursor to 65,536 only when the target ends
at `$10000`. IMAGE addresses and explicit ORG operands are not converted.
The Atom NOBJ reader applies the same interpretation to its stored cursor word.
Symbols remain words: a label immediately after the last byte has value zero.
Nucleus's top-fitting relocation proof must check both the physical extent and
the wrapped symbol value, not remove the top-fitting case.

## Evidence

The first regression run failed at native and host target validation. After
the change, six focused tests pass: descriptor endpoints, last-byte emission,
instruction emission, reservations, byte/word patches, NOBJ round trips, ORG
gaps, wrapped-output rejection, zero capacity and the end-label value. Failure
cases check abort, lack of successful commit and source-line attribution.
Successful host cases check the return PC and restored stack pointer.

`npm run build:native-core` regenerated the image with ATOM and verified an
identical second generation, including initialized addresses and ABI symbols.
`node test/measure-self-host.mjs` independently reproduced that equality.

| Account | Before | Candidate | Change |
| --- | ---: | ---: | ---: |
| Native driver code | 617 | 621 | +4 bytes |
| Native code and tables | 11,682 | 11,686 | +4 bytes |
| Fixed workspace | 714 | 714 | 0 |
| Linked native extent | 12,396 | 12,400 | +4 bytes |
| CP/M executable | 15,029 | 15,033 | +4 bytes |
| Named-object executable | 13,515 | 13,519 | +4 bytes |
| Host integration instructions | 32,182 | 32,182 | 0 |
| Host integration T-states | 328,908 | 328,913 | +5 |
| Self-build instructions | 101,840,573 | 101,857,310 | +16,737 |
| Self-build T-states | 1,086,338,471 | 1,086,511,840 | +173,369 |

The ordinary descriptor path executes a taken rather than untaken conditional
JR, accounting for its extra five T-states. The self-build also assembles the
additional validation source. The representative application bytes and stack
use are unchanged. No hardware measurements were performed.

## Release qualification

The first broad run used the regenerated core with several old measurement
records and failed on 18 of 363 tests. Those failures identified size/timing
and packed-output assertions needing reconciliation. Many have since been
updated from fresh measurements; that first run is not a passing release gate.
Its log is `/tmp/atom-final-byte-tests.log`.

After the measurement updates, the focused host/driver/artifact/service run
passed all 70 tests, and the regenerated CP/M build passed all 32 CP/M tests.
Logs: `/tmp/atom-final-byte-focused.log` and
`/tmp/atom-final-byte-cpm-tests.log`.

The final guarded `npm run release:check` passed all 366 tests, including
offline installed-package assembly, relocated named-object execution,
CP/M execution, and two-generation self-host equality. Its log is
`/tmp/atom-final-byte-release-final.log`. The package census is 397 entries and
2,221,578 unpacked bytes. The archive's compression size is not an identity.

The release-account test now uses the executable self-host account in
`phase-6.json`, leaving the dated Phase 11 checkpoint unchanged. Both builders
derive the standalone core size from the checked image; the four-byte driver
increase is not attributed to adapter code. A new regression test caught the
old hard-coded named-object account before that correction. A source-census
test checks the content bytes and nonblank records, including annotations.

The native named-object adapter requires separate qualification before use
with a target ending at `$10000`: its relative-offset conversion rejects a
wrapped commit cursor. The existing CP/M target ends below this boundary.
Neither adapter is claimed to support the desktop host's full target range.

Nucleus's top-fitting relocation test is the next consumer proof. It must pass
against the packed candidate before a downstream release pin advances.

Triptych's existing pinned configuration passed `npm run check` with AZM
imports forbidden. That verifies the unchanged consumer, not this unpublished
ATOM candidate. The log is `/tmp/triptych-final-byte-check.log`.
