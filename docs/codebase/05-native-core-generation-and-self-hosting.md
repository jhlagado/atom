# Chapter 5 — Native core generation and self-hosting

[← Host execution, artifacts and interfaces](04-host-execution-artifacts-and-interfaces.md) | [Verification and maintenance →](06-verification-and-maintenance.md)

The files under `src/z80/` are Atom's native implementation. The desktop
package loads a generated image from `assets/native-core.json`, but that image
is never edited by hand.

## Source entry

`src/z80/atom.asm` contains the ordered `%INCLUDE` header for the twelve core
modules:

```asm
%INCLUDE "encoder.asm"
%INCLUDE "symbols.asm"
%INCLUDE "token.asm"
%INCLUDE "tokdisp.asm"
%INCLUDE "expr.asm"
%INCLUDE "exprmath.asm"
%INCLUDE "patch.asm"
%INCLUDE "parser.asm"
%INCLUDE "output.asm"
%INCLUDE "stmts.asm"
%INCLUDE "driver.asm"
%INCLUDE "host.asm"
```

The resolver presents the twelve modules followed by the entry file, giving
the native driver thirteen source parts. Each module remains below Atom's
65,535-byte per-part limit.

Native names are limited to eight significant characters. Global names use a
two-letter module prefix, such as `PR_PARSE` or `TK_RESET`. Private labels use
the ordinary dot prefix and may be reused in another global scope.
`src/z80/atom-symbols.json` maps the short native names to the longer names
used by the host API and generated asset.

## Building the checked image

```sh
npm run build:native-core
npm run verify:native-core
```

`scripts/generate-native-core.mjs` assembles the checked source with the
shipped Atom core. It recovers the host-visible symbols through the symbol
ledger and constructs a runnable core from the result. That first-generation
core then assembles the same source again.

Generation succeeds only when both runs produce the same initialized-address
set, resident bytes and recovered symbols. The generated JSON contains Intel
HEX, the symbol map and digests covering both. `verify:native-core` performs
the same work without rewriting the asset.

## Other native builds

The same source is composed with different platform adapters:

- `scripts/generate-native-object-harness.mjs` builds the named-object image.
- `scripts/generate-cpm22.mjs` builds `assets/atom-cpm22.com`.

The object builder can place immutable code and tables separately from writable
workspace. A platform launcher still owns source preparation, descriptors,
symbol and pending arenas, service workspace, stack and publication policy.

## Self-host checks

The self-host test compares three things:

1. the first generated image with the checked package image;
2. the second generated image with the first; and
3. recovered entry points and range symbols across both generations.

The initialized-address comparison matters because a flat byte array cannot
distinguish an initialized zero from reserved storage. The symbol comparison
catches a correct byte image paired with the wrong host interface.

Run the proof directly with:

```sh
npm run measure:self-host
```

The installed package exposes the same first-generation build as:

```sh
atom self-host
```

Its default output is `build/atom.bin`. The package test runs this command from
an offline installation, which also checks that the native source, checked
image, dependencies and command paths were packaged correctly.
