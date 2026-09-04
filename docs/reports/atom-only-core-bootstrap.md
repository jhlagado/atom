# ATOM-only native-core bootstrap checkpoint

2026-09-05. Work on `range-and-bootstrap`, based on `27b32ad`. This is a
prerequisite for the remaining Nucleus relocation work, not a complete ATOM
release qualification.

## Build change

Native-core generation uses the checked ATOM seed to assemble the authoritative
source, recovers a runnable core, and executes that core over the same prepared
source. Both generations must have identical final bytes, initialized-address
sets and recovered ABI symbols. The generator's mandatory AZM import,
translation, temporary source and strict-contract invocation are removed.

The self-host test and measurement use the same ATOM-only comparison boundary.
They also compare with the checked image and retain the existing execution
counts and budgets. Static AZM register analysis is no longer claimed. The
misleading `verify:strict-contracts` and `annotate:contracts` aliases are removed.

## Verification

The new `host-core-bootstrap` regression initially failed with
`AZM import forbidden during ATOM bootstrap: @jhlagado/azm`. After the change,
the actual `generate-native-core.mjs --check` command passed with imports of
that package forbidden. Verification left its reference artifact unchanged.

- Thirty focused bootstrap, self-host, native-host and source-ledger tests passed.
- Eight architecture, documentation and product-reference tests passed.
- The actual `build:native-core` command passed with AZM imports forbidden.
  `git diff --exit-code -- assets/native-core.json` confirmed an unchanged asset.
- The guarded self-host measurement passed: each generation executed
  101,840,573 guest instructions and 1,086,338,471 T-states, with the same return
  PC, stack exit and source-read count.
- The image retains 11,682 code/table bytes, 714 fixed-workspace bytes and a
  12,396-byte resident extent. Native source, guest bytes and runtime behavior
  have no change in this checkpoint.

The unchanged artifact SHA-256 is
`22b418869eb8894ed25fd6711f27273b25e69afa46f6092a9e5d447d5eb594cc`.
No AZM assembly, full release gate, package publication or hardware test was run.

## Remaining range and release work

The desktop target check and native driver reject an exclusive end of `$10000`.
The direct output routine can emit at `$FFFF`, but its 16-bit cursor then wraps
to zero. Native label publication reads that cursor. Changing only the host
range check would therefore leave driver validation, final-cursor reporting
and endpoint labels inconsistent.

The required behavior remains a last byte at `$FFFF` without an output write
wrapping to `$0000`. Nucleus's top-fitting-origin proof must remain intact.
Next, define and test the distinction between a 16-bit byte address and a
mathematical one-past endpoint through the native driver, output, symbol and
host-artifact boundaries. The new ATOM-only core build can then construct the
native change without restoring AZM.

Object-harness and CP/M generation, historical differential tests and the
dependency gate still require migration. This branch has not been published,
and Nucleus and Triptych retain their existing ATOM pins.
