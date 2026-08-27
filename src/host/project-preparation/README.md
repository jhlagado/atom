# Project-preparation boundary

This directory contains Atom's language-neutral tool services for source
identity, dependency resolution, placement, and provenance.
The modules may import Node built-ins and other files in this directory. They
must not import Atom-specific syntax or resident assembler code.

The public neutral surface is `index.mjs`. It provides the confined Node source
reader, deterministic resolver, path-keyed placement join, and immutable
provenance records. Language behavior enters through a profile object. Atom's
`%` grammar and masking implementation live in the adjacent `src/host/atom/`
directory.

Atom owns this implementation while the Atom and Nucleus host requirements are
still being measured. The modules retain a separate public boundary so the
shared services can move into a Debug80 package or app later without changing
the resident assembler interface.

The complete contract, operational limits, and proof map are documented in
[`docs/host-source-preparation.md`](../../../docs/host-source-preparation.md).
