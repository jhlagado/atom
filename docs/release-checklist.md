# Release checklist

`npm run release:check` is the maintainer gate. It rebuilds the frozen proof
dependencies, runs the complete native and host suite, verifies the checked
self-host source and strict-contract native core, and repeats the Mac and
self-host measurements. `npm publish` invokes the same gate through
`prepublishOnly`.

The release gate must establish:

- every supported instruction and invalid-form discriminator still matches the
  frozen AZM census;
- strict AZM register contracts pass for the linked native image;
- all 64 KiB proof maps, stack/canary checks, and write boundaries pass;
- the shipped example produces its exact 19-byte image and artifact metadata;
- the CP/M image and output-path candidates match their checked censuses;
- native CP/M direct and `%INCLUDE` builds preserve their exact capacity,
  rollback, BDOS, diagnostic, dependency-order, and stack proofs;
- an npm archive installs offline without AZM and runs from an unrelated
  directory;
- Atom assembles its complete checked source with the pinned core;
- that first-generation core assembles the same source identically;
- independent Atom-to-AZM translation produces the same initialized address
  set and complete resident bytes; and
- the pinned native core matches the authoritative `.asm` source.

Before publishing, also perform the repository checks that deliberately require
network or release authority:

```sh
git fetch origin
git status --short --branch
gh repo view jhlagado/atom --json visibility,licenseInfo
npm pack --dry-run
```

The repository must be clean, the checkpoint commit must be pushed, visibility
must be `PUBLIC`, and both repository and package metadata must say
`GPL-3.0-only`. The dry-run census is recorded only after all packaged files
are frozen. Compressed archive size is observational because gzip output can
vary with the npm toolchain.

Release evidence belongs in the current phase report and
`proofs/phase-11.json`. Every number must be labelled Measured, Projected, or
Hypothesis. A green test count alone is insufficient; record native size,
fixed workspace, linked extent, self-host equivalence, package census, and the
exact dependency commits.
