# Release checklist

`npm run release:check` is the maintainer gate. It rebuilds the frozen proof
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

The ATOM-only migration is incomplete: object-harness and CP/M generation,
dependency checks and historical comparison tests still execute or require AZM.
Do not run those paths as normal release work or publish this checkpoint as an
ATOM-only toolchain. Native-core generation, its guarded verification test and
the self-host measurement are migrated. The misleading `verify:strict-contracts`
and `annotate:contracts` aliases are removed; static register analysis is not
claimed by the replacement self-host checks.

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
