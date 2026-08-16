# Phase 2a authorities and accounting boundary

## Frozen repositories

- `atom`: `/Users/johnhardy/projects/atom`, branch `main`. Phase 2a began from
  clean HEAD `48143d852ea3b96d8d174f3ad6bd0cb5cc08893a`.
- AZM, Debug80 runtime, and Nucleus reference tree:
  `/Users/johnhardy/projects/debug80`, branch `main`, reviewed HEAD
  `b4046badd29b1dd1bc146029728bacaa5e5fe603`. The reviewed AZM tree is
  `7889245c380334768f62805e73c13e979aa9f8c8`; the runtime tree is
  `a921abc89dcbd88211dd008e705b69d646cfb9bb`.

The Debug80 worktree was not modified for Phase 2a. Its branch was one local
commit ahead of `origin/main` when the authority was recorded. The dependency
check freezes the two subtrees that Atom executes.

## Settled language decisions

- Symbol comparison is case-insensitive.
- RADIX-40 stores eight significant characters exactly.
- `.` is the private-symbol prefix and is not stored in the RADIX-40 payload.
- `.ABCDEFGH` is therefore valid and occupies the same eight-byte record as an
  eight-character global name.
- Private scope is the nearest preceding global label. A new global label
  evicts the preceding private namespace after checking unresolved references.
- Names over the limit are diagnosed and never truncated.

## Accounting boundary

The measured resident account includes symbol packing around the shared Phase 1
RADIX-40 routine, exact lookup, declaration and forward-reference insertion,
scope validation and eviction, pending-reference allocation, and pending-entry
reclamation. The symbol and pending arenas are writable capacity and are
reported per record rather than counted as resident code.

The tokenizer, expressions, directives, diagnostic rendering, patch-byte
construction, and NOBJ serialization remain outside Phase 2a.
