# Phase 1 authorities and accounting boundary

## Frozen repositories

- `zap`: `/Users/johnhardy/projects/zap`, branch `main`, initially an unborn
  repository when Phase 1 began.
- AZM and Nucleus reference tree: `/Users/johnhardy/projects/debug80`, branch
  `main`, HEAD `f0c6643c145bdcfddf11255116ad39ec9836bc9f`, clean when Phase 1 began.

AZM at that exact revision is the byte oracle and the assembler used to build
the native encoder. Nucleus at that revision supplies the proof and measurement
conventions only.

## Target and boundary

The CPU is a documented Zilog Z80 plus the undocumented instruction forms
accepted by the frozen AZM oracle: index-half registers, SLL/SLS, and indexed
CB forms with plain-register destinations.

The resident Phase 1 account includes:

- rule-driven encoder code;
- validation and `ZapFormLength` code;
- mnemonic recognition code;
- the shared one-to-eight-character RADIX-40 packer;
- immutable opcode and mnemonic tables.

The four-byte commit buffer is writable workspace and is reported separately.
The host differential harness, generated cases, emulator, and AZM are proof
infrastructure and do not enter the resident account.

Input numeric values have already been classified as `imm8`, `imm16`, or
`disp8`/`rel8`. Phase 1 does not evaluate expressions, resolve symbols, or emit
patch records.
