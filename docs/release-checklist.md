# Release checklist

`npm run release:check` is the maintainer gate. It checks the pinned proof
dependencies, runs the complete native and host suite, verifies the checked
self-host source and native core, and repeats the desktop and
self-host measurements. `npm publish` invokes the same gate through
`prepublishOnly`.

The release gate must establish:

- every supported instruction and invalid-form discriminator still matches the
  frozen instruction census and reviewed expected bytes;
- all 64 KiB proof maps, stack/canary checks, and write boundaries pass;
- the shipped example produces its exact 19-byte image and artifact metadata;
- the CP/M image and output-path candidates match their checked censuses;
- native CP/M direct and `%INCLUDE` builds preserve their exact capacity,
  rollback, BDOS, diagnostic, dependency-order, and stack proofs;
- an npm archive installs offline without AZM and runs from an unrelated
  directory;
- Atom assembles its complete checked source with the pinned core;
- that first-generation core assembles the same source identically;
- both ATOM generations have identical initialized address sets, resident
  bytes and recovered ABI symbols; and
- the pinned native core matches the authoritative `.asm` source.

Normal builds, tests and measurements use ATOM. Historical comparison outputs
are retained as reviewed fixture data under `test/fixtures/historical-assembly.json`;
AZM is no longer a package or verification dependency. A new reference request
must have independently reviewed expected bytes or rejection behavior. Tests
must not generate their expected answers with ATOM. The source converters remain
available, but do not execute AZM.

The misleading `verify:strict-contracts` and `annotate:contracts` aliases are
removed; static register analysis is not claimed by the replacement self-host
checks. Successful local verification alone does not establish publication or
completion of the separate output-range and Nucleus reconciliation work.

Before publishing, also perform the repository checks that deliberately require
network or release authority:

```sh
git fetch origin
git status --short --branch
gh repo view jhlagado/atom --json visibility,licenseInfo
npm run verify:package-census
```

The repository must be clean, the checkpoint commit must be pushed, visibility
must be `PUBLIC`, and both repository and package metadata must say
`GPL-3.0-only`. The package census is recorded only after all packaged files
are frozen. Compressed archive size is observational because gzip output can
vary with the npm toolchain.

Release evidence belongs in the current phase report and
`proofs/phase-11.json`. Every number must be labelled Measured, Projected, or
Hypothesis. A green test count alone is insufficient; record native size,
fixed workspace, linked extent, self-host equivalence, package census, and the
exact dependency commits.
