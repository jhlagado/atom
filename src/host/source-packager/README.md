# Source-packager boundary

This directory contains Atom's language-neutral host services for source
identity, dependency resolution, source plans, placement, and provenance.
The modules may import Node built-ins and other files in this directory. They
must not import Atom-specific syntax or resident assembler code.

The public neutral surface is `index.mjs`. It provides the confined Node source
reader, deterministic resolver, path-keyed placement join, SP1 codec, immutable
provenance records, and atomic SP1 writer. Language behavior enters through a
profile object. Atom's `%` grammar and masking implementation live in the
adjacent `src/host/atom/` directory.

Atom owns this implementation while the Atom and Nucleus host requirements are
still being measured. The modules retain a separate public boundary so the
shared services can move into a Debug80 package or app later without changing
the resident assembler interface or the SP1 interchange.

The complete contract, operational limits, and proof map are documented in
[`docs/host-source-packaging.md`](../../../docs/host-source-packaging.md).
