# Atom engineering manual

This manual is a technical guide for engineers working on Atom. It follows a
build from a source entry through host preparation, native Z80 assembly,
append-only output, artifact rendering, publication, and self-host verification.
It also maps the repository and identifies the tests that protect each boundary.

The guide describes the codebase as it stands on 17 August 2026. The source,
ABI documents, and executable proofs remain the final authority when a detail
changes.

Atom has two implementation domains. The assembler itself is handwritten Z80
under `native/`. The Node code under `src/host/` supplies filesystem access,
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

## Appendices

- [Appendix A — Directory and file reference](appendices/a-directory-and-file-reference.md)
- [Appendix B — Build-flow reference](appendices/b-build-flow-reference.md)
- [Appendix C — Public surface and ABI reference](appendices/c-public-surface-and-abi-reference.md)

## Related references

- [Architecture](../architecture.md)
- [Language reference](../language-reference.md)
- [Native limits and capacity](../limits.md)
- [Mac host integration](../mac-host-integration.md)
- [TEC-1 deployment design](../tec-1-deployment.md)
