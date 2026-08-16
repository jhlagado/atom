# Native compression audit

This audit freezes the AZM implementation before Atom source becomes
authoritative. It identifies resident-byte savings in the current linked Z80
image without changing the language, native ABI, diagnostics, capacity rules,
or output bytes. No source optimization is applied in this checkpoint.

## Baseline and accounting boundary

The reviewed source is Atom `main` at
`66d9d52562399ac970249bc13ff29eb274ffa7cd`. The only untracked file is the
pre-existing `.DS_Store`. AZM 0.3.9 assembled `asm/atom-host-runtime.asm` for a
documented Zilog Z80 with strict register contracts enabled. The pinned native
artifact rebuilt without drift.

| Account | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 13,261 |
| Fixed writable workspace | Measured | 551 |
| Linked resident extent | Measured | 13,812 |
| Margin below 16 KiB | Measured | 2,572 |

The host-native integration program executed 28,250 instructions and 279,880
T-states, made 13 service calls, returned through the sentinel address with
`SP=$FEFF`, and emitted the expected ten initialized bytes and one patch. The
current Atom-local battery passes 266 of 266 tests. These measurements define
the before state for every compression experiment.

The component account remains:

| Module | Classification | Code and immutable bytes | Workspace bytes |
| --- | --- | ---: | ---: |
| Encoder, validation, recognition, and tables | Measured | 3,997 | 9 |
| Symbols and pending references | Measured | 874 | 28 |
| Tokenizer | Measured | 1,380 | 32 |
| Expression evaluator | Measured | 2,135 | 303 |
| Patch locator | Measured | 73 | 0 |
| Parser | Measured | 2,162 | 98 |
| Output | Measured | 503 | 24 |
| Statements and directives | Measured | 1,458 | 48 |
| Driver | Measured | 655 | 9 |
| Host-service stubs | Measured | 24 | 0 |

“Projected” below means that the current assembled instruction or call-site
census fixes the arithmetic, but the proposed source has not yet been
assembled. “Hypothesis” marks a representation that still needs an experiment
before its byte cost is known.

## First compression pass

The first pass should contain changes whose machine behaviour is local and
whose current call sites have been counted. The items overlap in a few branch
instructions, so their individual projections must not be added blindly.

### Branch width and fall-through

The linked listing contains Measured 604 absolute `JP` instructions whose
conditions have `JR` equivalents. Measured 89 currently fall within the signed
relative range. Their module distribution is:

| Module | Convertible sites |
| --- | ---: |
| Encoder | 39 |
| Tokenizer | 6 |
| Expression evaluator | 22 |
| Parser | 15 |
| Output | 2 |
| Statements | 4 |
| Driver | 1 |

Changing one such instruction from `JP` to `JR` saves one byte. Shrinking code
between a branch and its target can only reduce the displacement magnitude, so
the current in-range sites remain in range during a compression-only pass.
Structural tail merging will remove several of these jumps first. A fresh
census after those changes should retain Projected 75–90 bytes of branch-width
savings.

The listing also contains three jumps to the immediately following
instruction, one unconditional `JR +0`, two terminal `CALL`/`RET` pairs whose
`RET` is not shared, three invertible branch-around-jump pairs, and one
branch-around-`RET` pair. Removing or inverting those sequences contributes a
further Projected 15–20 bytes after overlap with the `JP` census is removed.

### Encoder output tails

The encoder repeats several exact suffixes:

| Exact active pattern | Sites | Projected saving |
| --- | ---: | ---: |
| `LD (ATOMSCRATCH+1),A` then return length 2 | 28 | 81 bytes |
| Equivalent byte-3 and byte-4 tails | 4 and 3 | 15 bytes |
| Store `$ED`, store `B`, then return length 2 | 6 | 30 additional bytes |
| Preserve `AF`, calculate/store an index prefix, restore `AF` | 7 | 26 bytes |
| Copy a word from an instruction value and return length 3 or 4 | 13 calls | 47 bytes |

The value-copy saving uses `HL` for the word transfer and turns each terminal
`CALL helper` / `JP length` pair into a tail `JP helper`. The four helpers then
end with a short branch to the length return. This changes the complete active
account for those helpers and call sites from 130 bytes to a Projected 83
bytes. `AtomEncodeCore` already permits `HL` to be clobbered.

Together, the exact suffix and helper changes account for Projected 199 bytes
before branch-width overlap. They do not change the four-byte commit buffer or
any generated instruction.

### Recognition state

`AtomRecognizeMnemonic` stores low, high, and midpoint search ordinals in three
resident bytes. `B` and `C` can retain the low and high bounds. The midpoint
can remain in `IXL`, which is already in the routine's clobber set. The current
absolute loads and stores then become register moves.

The current routine has enough register liveness for this substitution without
stack traffic. The saving is Projected 18 code bytes and 3 workspace bytes.
This change preserves the existing exact RADIX-40 table and binary-search
semantics.

### Shared token and pointer helpers

Ten active sites contain this seven-byte sequence:

```asm
        LD HL,(ATOMTOKENRECORD+ATOMTOKENLEXEMEOFFSET)
        LD A,(ATOMTOKENRECORD+ATOMTOKENLENGTHOFFSET)
        LD B,A
```

One eight-byte helper plus ten three-byte calls replaces 70 bytes with a
Projected 38 bytes, saving 32. The helper consists only of loads and therefore
preserves the incoming flags, as the inline sequence does.

Eight active symbol/driver sites copy `IX` to `HL`, clear carry, and compare it
with `DE`. A seven-byte helper plus eight calls replaces 48 bytes with a
Projected 31 bytes, saving 17. The extra call adds two bytes of transient stack
depth and must be covered by the stack canaries.

Two smaller statement helpers cover five token-fetch prefixes and five
expression-parser prefixes. Keeping failure dispatch at the callers gives a
combined Projected saving of 15 bytes without non-local stack unwinding.

### Diagnostic position copying

The expression evaluator has four 20-byte failure routines. They differ only
in the address of a contiguous `part,offset` source record. The parser has two
more routines of the same shape. A common routine can copy the three-byte
position with `LDIR`; saving and restoring `BC` and `DE` retains their current
contracts.

One fall-through wrapper and short or absolute jumps from the other wrappers
reduce the expression account by a Projected 39 bytes and the parser account
by 11 bytes. The destination status, part, and offset remain fully written on
every failure path.

### Module-local state

Several fixed workspace fields are avoidable:

- `AtomSymbolPackDestination` can be replaced by the successful RADIX packer's
  advanced `DE`, using `PUSH DE`, `DEC DE`, `EX DE,HL`, and `POP DE`. Direct
  carry branches also replace two seven-byte carry-to-Boolean sequences. The
  combined saving is Projected 17 code bytes and 2 workspace bytes.
- `AtomTokenNameLimit` can remain in `C`; every helper called by the name loop
  preserves `BC`. This saves Projected 8 code bytes and 1 workspace byte.
- `AtomOutputDataValue` can be removed by retaining byte values in `B`, word
  values in `BC`, and reserve counts in `BC`. Reusing
  `AtomOutputEmitByteReady` inside the instruction loop removes a second copy
  of its cursor and capacity update. The output module saves Projected 26 code
  bytes and 2 workspace bytes.

The recognizer, symbol, tokenizer, and output changes therefore remove a total
of Projected 8 fixed workspace bytes. Fixed workspace would fall from 551 to
543 bytes before any expression-workspace overlay.

### Z80 flag idioms

Six active `LD A,1` / `OR A` / `RET` tails can use `XOR A` / `INC A` / `RET`.
Both forms return `A=1`, clear carry, and produce the same documented
`S`, `Z`, `H`, `P/V`, and `N` state for the value one. This saves Projected 6
bytes.

The six fail-closed host stubs can use `SCF` / `SBC A,A` / `RET`. Each entry
keeps a distinct hook address, returns `A=$FF` with carry set, and saves one
byte under its declared clobber contract. The parser's carry-to-inverted-Boolean
sequence can use `SBC A,A` / `INC A`, saving another 3 bytes.

### First-pass target

After overlap between tail merging and branch shortening, the first pass is
Projected to remove 480–520 code bytes and 8 workspace bytes. That would put
the linked resident extent at approximately 13,284–13,324 bytes and code plus
immutable tables at approximately 12,741–12,781 bytes.

This range is a target for experiments, not a measured result. Each retained
change needs a fresh strict assembly, focused path proof, full differential,
memory audit, and cycle measurement.

## Second compression pass

The following representations can save more, but their costs need isolated
experiments.

### Exact keyword representation

The mnemonic recognizer occupies Measured 454 bytes: 109 bytes of search code
and a 345-byte table. Its 69 mnemonics contain only 213 source characters. A
generated prefix tree or length-bucketed exact recognizer can share prefixes
and remove the fixed five-byte record cost. The same engine could recognize the
27 reserved operand words and nine directives.

A hash-only table is invalid. Although simple 16-bit folds happen to be unique
for the 69 supported mnemonics, unsupported names can collide with a supported
hash and be accepted. A measured exact prefix tree for those mnemonics has 115
nodes, including its root. Any replacement must compare the complete spelling
or use a generated perfect recognizer with an explicit rejecting state.

The combined mnemonic, operand-word, and directive recognition account should
be tested as one unit. The saving is Hypothesis 100–180 bytes. The experiment
must retain case folding, every invalid-name discriminator, the independent AZM
denominator, and the symbol packer's RADIX-40 behaviour.

### Predicate arithmetic

Six operand predicates currently use comparison chains. Their valid classes
form compact ranges or two short ranges. Subtract-and-range implementations
would save Hypothesis 25–41 bytes. The smaller figure preserves `A`; the larger
figure widens the internal predicate contracts to permit `A` to be clobbered.
A complete caller census is required before choosing the larger form.

### Validation and encoding dispatch

`AtomValidateForm` and `AtomEncodeCore` repeat the same mnemonic-family
dispatch. A combined internal entry could validate and encode after one
dispatch, while the public `AtomFormLength` entry retains validation-only
behaviour. The second dispatch is roughly one hundred bytes, but mode handling
and common success exits have a cost. The net saving is Hypothesis 60–100
bytes.

This experiment must not weaken standalone encoder validation. `AtomEncode`
must continue to reject malformed records atomically even though the ordinary
parser path has already validated them.

### RADIX-40 grouping

The first and second three-character groups in `AtomRadix40Pack` contain
near-identical setup and store sequences. A local three-character group helper
or a two-iteration loop is Hypothesis 8–15 bytes smaller. Folding validation
into the packing pass may save more, but every failure must still leave the
destination untouched and restore the original stack shape.

### Expression workspace overlays

The expression evaluator reserves separate counters for shifts and multiply,
and separate arithmetic magnitude, quotient, and diagnostic scratch. Several
of these lifetimes do not overlap. A liveness proof may recover Hypothesis
8–16 workspace bytes without reducing the value or operator stack capacities.

The error-position record must be written only after the arithmetic scratch is
dead. Multiplication, division, range failure, unresolved-symbol failure, and
successful reduction all need separate canary traces before any overlay is
accepted.

## Candidates to reject or defer

- A shared helper for six `LD E,(HL)` / `INC HL` / `LD D,(HL)` sequences saves
  only one byte after paying for the helper and calls. The cycle regression is
  not justified.
- A full mnemonic hash without an exact-spelling check accepts false names and
  is incorrect.
- A naive 69-entry dispatch table moves bytes from code into data and does not
  beat the existing ordinal ranges once indexing and indirect transfer are
  counted.
- `RST` compression requires ownership of fixed vectors. Atom has no such
  platform contract.
- Self-modifying dispatch conflicts with the proved read-only native code
  policy.
- Alternate-register retention requires an interrupt and reentrancy contract
  that Atom does not currently have.
- Reducing expression stack capacities changes a published limit and is a
  language/ABI redesign, not compression.

## Implementation order and proof gate

The compression should remain in AZM source until the result stabilizes:

1. merge encoder tails and the other exact repeated helpers;
2. replace module-local workspace fields with proved live registers;
3. rerun the linked listing and convert every remaining in-range `JP`;
4. apply the flag and fall-through idioms;
5. assemble and run the complete correctness battery;
6. measure the new component and resident accounts;
7. experiment with keyword representation, predicates, dispatch, and
   expression overlays one at a time.

Every experiment records baseline and result bytes, workspace delta,
self-assembly instruction and T-state deltas, and the proof commands. A losing
experiment remains documented so it is not repeated without a changed premise.
The `.atm` authority flip resumes only after the retained compression pass has
passed strict contracts, all 3,445 valid instruction forms, all invalid-form
tests, exact self-host byte comparison, stack and return-PC checks, source ROM
guards, and the complete memory audit.
