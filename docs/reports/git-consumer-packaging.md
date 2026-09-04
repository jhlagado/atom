# Git consumer packaging correction

2026-09-05. This report covers ATOM installation as an immutable Git dependency
while retaining the existing offline npm archive.

## Reproduced failure

Nucleus pinned ATOM commit
`7692c2938a3d3fa08112988516d29aff6897a680`. Its first release snapshot had a
complete cached installation, but a later `npm ci` installed ATOM without
`@jhlagado/z80-tool-services`. A second run with a newly created empty npm cache
reproduced the omission. Importing `atom-z80` then failed before assembly.

ATOM's checked-in `package.json` marked Debug80 Runtime and Z80 Tool Services as
bundled dependencies. `npm pack` ran ATOM's `prepack` hook, which supplied both
packages to the archive. npm's Git-dependency path did not run that hook, yet it
still treated the dependencies as bundle members and omitted their normal
installation. Nucleus directly depends on Debug80 Runtime, which masked half of
the failure in one installation; it has no direct Tool Services dependency.

## Packaging boundary

The checked-in manifest now declares both packages as ordinary dependencies
without `bundledDependencies`. Revision-pinned Git consumers therefore install
them through npm's normal dependency graph.

The `prepack` helper temporarily adds the two bundle names to `package.json`
after making their package directories available. It records the exact original
and prepared manifest text. `postpack` verifies that the prepared file did not
change, removes only the links created by the helper, restores the original
manifest bytes and removes its marker. A failed preparation also restores the
original manifest and removes its links.

This split preserves two distribution modes:

- Git consumers install the pinned dependencies normally.
- The npm archive contains both dependencies and installs without network
  access.

## Verification

The focused installed-package test passes in 46.50 seconds. It creates the npm
archive, installs it with `--offline --ignore-scripts`, verifies both bundled
dependencies and the absence of AZM, then exercises the CLI, conversion,
`INCBIN`, CP/M output and self-hosting paths. The SHA-256 of `package.json` was
identical before and after the test.

ATOM's complete guarded `npm run release:check` passes all 366 tests. The native
host measurement and two-generation self-host measurement pass afterward. The
two self-host generations each execute 101,857,310 Z80 instructions and
1,086,511,840 cycles and produce the same 11,793 initialized bytes. Logs:

- `/tmp/atom-git-bundle-package-test.log`
- `/tmp/atom-git-consumer-release-check.log`

A new consumer with an empty npm cache then installed the committed ATOM tree
through a `git+file` URL. npm installed both Runtime and Tool Services as normal
dependencies, and the public `atom-z80` module imported with AZM blocked. This
qualifies the Git packaging mechanism locally. A GitHub fetch follows after the
commit is pushed and precedes the next Nucleus release gate.
