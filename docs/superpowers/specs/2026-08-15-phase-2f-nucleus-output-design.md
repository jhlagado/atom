# Phase 2f Nucleus output design

## Authority

Phase 2f follows the Nucleus target-output boundary. Nucleus compiler code
submits image bytes and resolved patch bytes through target-sink calls. The
operating adapter owns the two sequential spools, NOBJ framing, CRC, `BEGIN`,
`MAP`, `COMMIT`, abort, storage capacity, and publication.

The governing references are:

1. `packages/nucleus/docs/nucleus-object-format.md` in frozen Debug80;
2. `packages/nucleus/asm/vertical-slice/target-output.asm`;
3. `packages/nucleus/asm/vertical-slice/loop-z80-sink.asm`; and
4. Atom's existing `docs/symbol-abi.md` and `docs/symbolic-parser-abi.md`.

Atom does not contain a second NOBJ encoder. Its native output layer calls the
same class of logical sink operations as Nucleus.

## Scope

Phase 2f adds native instruction-image emission and resolved-patch emission.
It drains pending references when a symbol becomes defined and releases each
six-byte pending record after the corresponding patch sink call succeeds.

Phase 2f remains a flat bank-zero measurement. The settled pending record has
no bank field. Labels, equates, directives, multipart source iteration, final
undefined-symbol checks, sink lifecycle, `MAP`, and complete object commit
remain later work.

## Sink ABI

The proof adapter and a future operating adapter provide these external calls:

- `AtomSinkImageByte`: input `A=byte`, `C=bank`, `HL=target address`;
- `AtomSinkPatchByte`: input `A=byte`, `C=bank`, `HL=target address`; and
- `AtomSinkPatchWord`: input `C=bank`, `DE=target address`, `HL=word`.

Success returns carry clear. Failure returns carry set with a nonzero adapter
status in `A`. A failed sink call appends no logical operation. Atom preserves
that status and stops; the later compiler driver will abort the open generation
exactly as Nucleus does.

The adapter turns image calls into the image spool and patch calls into the
patch spool. It serializes every image before every patch when it forms the
NOBJ stream.

## Native output state

`AtomOutputReset` initializes the flat output state with a target start address
and mathematical byte capacity. The resident state contains a target cursor,
remaining capacity, bank zero, a four-byte instruction buffer, and patch
calculation scratch. Caller-owned sink storage remains outside Atom's resident
and workspace accounts.

`AtomOutputEmitInstruction` accepts the existing ten-byte parsed record in IX.
It encodes the record into the four-byte buffer, verifies complete instruction
capacity and pending-list capacity before the first sink call, then submits one
`AtomSinkImageByte` call for each encoded byte at increasing addresses. The
cursor advances only after a successful sink call. After every image byte has
been accepted, the routine appends the parser's published references to the
pending arena.

An adapter failure may leave earlier image-byte operations in the uncommitted
generation, as it does in Nucleus. Atom reports the failure and the compiler
driver must abort that generation. Parser diagnostics and local capacity
failures occur before the first image operation.

## Patch resolution

`AtomOutputResolveSymbol` accepts IX pointing to a defined symbol record. It
repeats these steps until no pending record names that symbol:

1. inspect one matching pending record without removing it;
2. add its signed-byte addend to the symbol's unsigned stored word in a signed
   24-bit calculation;
3. validate and form the replacement bytes for its patch kind;
4. call `AtomSinkPatchByte` or `AtomSinkPatchWord`; and
5. remove that exact pending record after the sink succeeds.

Byte patches accept 0 through 255. Word patches accept Atom's existing
-32768 through 65535 expression domain and write the low word. Displacement
patches accept -128 through 127. Relative patches subtract `patchAddress+1`
and accept -128 through 127, matching the concrete parser rule.

A range or sink failure leaves the current pending record in the arena. Patches
already accepted earlier in the same drain remain only in the uncommitted patch
spool; the driver aborts the generation after the failure. A successful drain
reclaims every matching pending record.

## Proof boundary

The Phase 2f proof adapter records the same logical image-byte, patch-byte, and
patch-word operations used by Nucleus proofs. Native execution evidence covers:

- exact concrete instruction bytes and increasing target addresses;
- all four patch kinds at accepted and rejected boundaries;
- multiple references to one symbol, including descending patch addresses;
- signed addends at -128 and 127;
- image capacity, pending capacity, range, and injected sink failures;
- unchanged pending state on the failing patch;
- exact cursor, pending reclamation, return PC, and SP;
- two-sided canaries around every writable region;
- immutable code, tables, source, and parsed records;
- strict AZM register and stack contracts;
- a complete 65,536-byte memory map; and
- all historical Atom proofs.

The report separates output code and immutable data, fixed workspace, external
adapter storage, instruction counts, and T-states. It updates the projected
whole-assembler total from the fresh measured result.
