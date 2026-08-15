# Phase 2b authorities and accounting boundary

## Frozen repositories

- Atom: `/Users/johnhardy/projects/atom`, branch `main`, clean starting HEAD
  `869d1790fc1f93528d8c0c87b15086a96cdf14e0`, equal to `origin/main` when
  Phase 2b began.
- AZM, Debug80 runtime, and Nucleus reference tree:
  `/Users/johnhardy/projects/debug80`, branch `main`, reviewed HEAD
  `b4046badd29b1dd1bc146029728bacaa5e5fe603`. That checkout was one commit
  ahead of `origin/main` at `3f2adb669bb9e7888305c623f8c843054c3dd111` and contained the unrelated
  untracked `.worktrees/` directory. Phase 2b did not modify, commit, or push
  that repository.
- The verified AZM subtree remains
  `7889245c380334768f62805e73c13e979aa9f8c8`; the verified Debug80 runtime
  subtree remains `a921abc89dcbd88211dd008e705b69d646cfb9bb`.

The user-supplied Atom design governs scope. AZM governs instruction bytes and
supplies the assembler and strict register-contract analysis. Atom's existing
encoder and symbol ABIs govern the handoff. Nucleus's source adapter,
tokenizer, full-memory maps, direct-return tests, and measurement reports are
the implementation and proof precedent.

## Target and measured boundary

The target is a documented Zilog Z80. The Phase 2b resident account includes:

- source reset, peek, and take routines for one memory-backed part;
- whitespace, comment, newline, name, directive, number, string, and
  punctuation scanning;
- failure statuses and exact source-part/offset capture;
- immutable punctuation and escape tables.

The fixed-workspace account includes the source cursor, end and offset, scan
scratch, diagnostic state, and the nine-byte token record. Caller-owned source,
symbol and pending arenas, proof source, stack, AZM, and Debug80 remain separate
accounts.

The measurement does not include the flat-manifest iterator, a hardware input
service, expression parsing, directive semantics, operand classification,
symbol insertion, patch creation, or output. The memory-backed part boundary
keeps those costs visible instead of hiding them inside the tokenizer result.
