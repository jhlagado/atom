# Release checklist

Run the complete local gate from a clean checkout:

```sh
npm run release:check
npm run verify:package-census
```

The gate rebuilds the native core, native object harness and CP/M program. It
runs the native and host test suites, installs the packed npm archive offline
and proves two generations of self-hosting. It must finish without changing a
checked asset or proof record.

Before publishing:

1. Confirm `main` is current with its remote.
2. Confirm the working tree is clean.
3. Check that `package.json` has the intended version.
4. Check that the repository and package both use `GPL-3.0-only`.
5. Inspect the packed file list and package census.
6. Tag the exact release commit as `v<version>`.

Useful checks:

```sh
git fetch origin
git status --short --branch
gh repo view jhlagado/atom --json visibility,licenseInfo
npm pack --dry-run
```

If the packaged file set changed deliberately, update its checked census only
after the files are final:

```sh
npm run update:package-census
npm run verify:package-census
```

## GitHub release

Pushing a version tag starts `.github/workflows/release.yml`. The workflow
repeats the release gate and publishes:

- `ATOM.COM`
- `ATOM.manifest.json`
- `SHA256SUMS`

The manifest records the source commit, executable size, addresses and digest.
The preparation script rejects a tag that disagrees with `package.json` or a
CP/M executable that differs from the checked census.
