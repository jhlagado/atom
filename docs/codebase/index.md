# Atom engineering manual

This manual follows a build from a source entry through host preparation,
native Z80 assembly, output, artifact rendering and self-host verification. It
also maps the repository and the tests that protect each boundary.

Atom has two implementation domains. The assembler itself is handwritten Z80
under `src/z80/`. The Node code under `src/host/` supplies filesystem access,
preprocessing, Debug80 execution, output adapters, artifact rendering, and
publication. Keeping those domains separate is the central architectural rule
behind the repository.

## Chapters

- [Chapter 1 — Orientation and repository layout](01-orientation-and-repository-layout.md)
- [Chapter 2 — Host source preparation](02-host-source-preparation.md)
- [Chapter 3 — Native Z80 assembly pipeline](03-native-z80-assembly-pipeline.md)
- [Chapter 4 — Host execution, artifacts, and interfaces](04-host-execution-artifacts-and-interfaces.md)
- [Chapter 5 — Native core generation and self-hosting](05-native-core-generation-and-self-hosting.md)
- [Chapter 6 — Verification and maintenance](06-verification-and-maintenance.md)

## Related references

- [Documentation index](../index.md)
- [Architecture](../architecture.md)
- [Language reference](../language-reference.md)
- [Native limits and capacity](../limits.md)
- [Native source map](native-source-map.md)
