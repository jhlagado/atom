# Phase 1 authorities and accounting boundary

## Frozen repositories

- `atom`: `/Users/johnhardy/projects/atom`, branch `main`. The repository was
  created in Phase 1; proof hardening began from clean HEAD
  `3a2410e9b1662551736e3a8e354acfc8ff4eda91` (pre-rename HEAD
  `1e92fb27a9fd7052f130645843c30c33a57dda4c`).
- AZM and Nucleus reference tree: `/Users/johnhardy/projects/debug80`, branch
  `main`, current reviewed HEAD `24aa93e521665b0a25de9665a62330b21b6c72c6`.
  Phase 1 began at `f0c6643c145bdcfddf11255116ad39ec9836bc9f`.
  The AZM subtree is identical at both revisions, tree
  `049b9e22fb1448bbb1619406e3ea13a124286ce4`; the Debug80 runtime subtree is
  likewise identical, tree `a921abc89dcbd88211dd008e705b69d646cfb9bb`.

The proof scripts verify those subtree identities, rebuild both dependencies,
then use AZM as byte oracle and assembler. Nucleus supplies the proof and
measurement conventions only.

## Target and boundary

The CPU is a documented Zilog Z80 plus the undocumented instruction forms
accepted by the frozen AZM oracle: index-half registers, SLL/SLS, and indexed
CB forms with plain-register destinations.

The resident Phase 1 account includes:

- rule-driven encoder code;
- validation and `AtomFormLength` code;
- mnemonic recognition code;
- the shared one-to-eight-character RADIX-40 packer;
- immutable opcode and mnemonic tables.

The four-byte commit buffer is writable workspace and is reported separately.
The host differential harness, generated cases, emulator, and AZM are proof
infrastructure and do not enter the resident account.

Input numeric values have already been classified as `imm8`, `imm16`, or
`disp8`/`rel8`. Phase 1 does not evaluate expressions, resolve symbols, or emit
patch records.
