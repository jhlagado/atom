# Native compression audit

This audit predates the host-backed source service. Its measurements remain a
historical compression account; [`limits.md`](limits.md) contains the current
linked size and workspace totals.

This document records the compression audit and its measured implementation
before Atom source becomes authoritative. The retained changes do not alter the
language, native ABI, diagnostics, capacity rules, or assembled output bytes.

## Baseline and accounting boundary

The baseline source is Atom `main` at
`66d9d52562399ac970249bc13ff29eb274ffa7cd`; the written audit was committed as
`2767709fd07ff0ed78c84ae96250c3c549a5b537`. The only untracked file was the
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

## Compression checkpoint result

All locally safe and profitable candidates survived the proof battery. The
linked result is:

| Account | Classification | Baseline bytes | Result bytes | Change |
| --- | --- | ---: | ---: | ---: |
| Code and immutable tables | Measured | 13,261 | 11,640 | -1,621 |
| Fixed writable workspace | Measured | 551 | 453 | -98 |
| Linked resident extent | Measured | 13,812 | 12,093 | -1,719 |
| Margin below 16 KiB | Measured | 2,572 | 4,291 | +1,719 |

That table is the end of the compression pass, not the current release
account. The later checked-core driver proof exposed an uninitialized
diagnostic position on sink-begin failure. Initializing the three-byte record
added eight code bytes. The current image therefore contains Measured 11,648
bytes of code and immutable tables plus 453 bytes of workspace, for a Measured
12,101-byte linked extent and 4,283-byte physical margin. The correction leaves
the language and successful output unchanged.

The module split is:

| Module | Result code and immutable bytes | Result workspace bytes | Resident change |
| --- | ---: | ---: | ---: |
| Encoder, validation, recognition, and tables | 3,132 | 6 | -868 |
| Symbols and pending references | 727 | 20 | -155 |
| Tokenizer | 1,346 | 26 | -40 |
| Expression evaluator | 1,868 | 263 | -307 |
| Patch locator | 67 | 0 | -6 |
| Parser | 2,061 | 92 | -107 |
| Output | 467 | 14 | -46 |
| Statements and directives | 1,345 | 23 | -138 |
| Driver | 619 | 9 | -36 |
| Host-service stubs | 8 | 0 | -16 |

The encoder now occupies Measured 3,132 resident bytes: 2,888 bytes of code,
244 bytes of immutable data, and 6 bytes of workspace. Validation uses 1,208
bytes, rule-driven encoding uses 1,444 bytes, and the direct LD subtotal is 881
bytes. Mnemonic recognition uses 59 bytes of code and a 207-byte exact table,
plus the shared 177-byte RADIX-40 packer. The complete encoder is now 368 bytes
below the 3,500-byte Phase 1 review gate.

The compact mnemonic table has a measured execution cost. The exhaustive
mixed-case proof reaches 934 instructions and 9,619 T-states for lowercase
`DJNZ`. The full self-build uses 99,458,987 instructions and 1,059,703,728
T-states, up from the baseline 95,471,840 instructions and 995,258,332
T-states. Both values remain below the fixed 200 million instruction and two
billion T-state limits.

After the driver correction, the current self-build uses Measured 99,498,360
instructions and 1,060,106,568 T-states. The historical values above remain the
end-of-compression comparison point.

The implementation retained shared encoder tails, prefix and ED suffixes,
word-copy tails, in-range relative branches, fall-through removal, flag
idioms, shared token and symbol helpers, common diagnostic copying, local-state
removal, arithmetic predicates, a shared mnemonic-family dispatcher,
RADIX-40 group sharing, and expression-workspace overlays. The mnemonic table
uses three exact packed bytes per dense ordinal and a bounded linear scan.

A final current-tree census found one remaining parser loop.
`AtomParserIndexBit` accepts only operand indices zero through two. Zero maps to
one; either nonzero value maps to the required mask after one doubling. The
replacement reduces that helper from 10 bytes to 7, removes 75,703 instructions
and 496,825 T-states from the self-build, and preserves `BC` and the published
flag contract.

The second-order suffix pass removed another Measured 118 bytes. The encoder
contributed 99 bytes through shared validation-length returns, flag-preserving
validation trampolines, ED and value-copy tails, common opcode arithmetic, and
a three-byte half-index predicate reduction that still preserves `BC`.
Statements contributed 12 bytes by sharing five output-completion tails.
Expressions contributed 7 bytes through one fall-through and a shared
lower-word right-shift suffix; signed and unsigned high-byte shifts remain
separate. The added calls increase the self-build by Measured 366,875
instructions and 3,931,864 T-states relative to the preceding checkpoint.

A third linked-listing census removed another Measured 25 bytes with no
workspace change. Six newly in-range encoder branches and a shared absolute
value tail removed 15 bytes. Expression fall-through removed 3, statement
fall-through removed 1, shared symbol-status returns removed 3, and one common
fail-closed host-service body removed 3 while retaining all six hook addresses.
The complete self-build increased by Measured 413,306 instructions and
4,631,728 T-states relative to the preceding checkpoint. Most of that change
comes from the one-byte symbol-not-found tail saving, which adds one jump to a
frequent lookup path.

The final adversarial pass removed another Measured 263 resident bytes: 185
bytes of code and immutable tables and 78 bytes of workspace. Splitting the
core-opcode table by its ordinal boundary saved 45 bytes, endpoint-encoding the
mnemonic families saved 14, and deriving directive ordinals from their dense
table order saved 8. Operator kind and precedence now share one byte, and
mutually exclusive expression, parser, output, statement, symbol, and tokenizer
state shares measured workspace. Sequential reuse tests exercise those
overlays. The six fail-closed host hooks retain distinct entry addresses in an
eight-byte fall-through block; the host proof now calls every entry directly.
The final linked census contains no in-range `JP` conversion and no jump to the
next instruction.

One parser overlay experiment was rejected. The first six bytes of parser
scratch remain live while an unresolved record is being diagnosed, so placing
the diagnostic record there corrupted the source position. The retained map
uses dead bytes six through nine and passes concrete, unresolved, and failure
paths. A common parser error-return label was also rejected because it widened
AZM's strict routine control-flow contract for no useful structural benefit.

Two larger hypotheses were rejected by the current byte account. The public
`AtomFormLength` entry and the atomic `AtomEncode` entry require separate
validation and encoding handler maps. Those two maps already contain the
minimum 17 two-byte addresses apiece; the repeated mnemonic-family mapping is
shared code, and `AtomEncodeCore` itself occupies only 9 bytes. A combined
paired-pointer continuation therefore adds routing code without removing table
data. The three keyword recognizers also use different exact record shapes:
dense mnemonics use an implicit ordinal, operand words store an explicit class,
and four- and five-character directives require a second packed word.
Directives now derive their ordinal from dense table order, but a common fixed
record still enlarges the 69-entry mnemonic table or loses exact rejection.
Sharing only the three-byte stepping loop does not repay its caller setup. Both
larger ideas require a changed representation premise before another
experiment is justified.

Experiments that did not provide a safe saving were removed. These include a
broad register predicate that admitted an invalid index-half form, hash-only
mnemonic recognition, a standalone 69-entry dispatch table, the one-byte
16-bit load helper, `RST` vectors, self-modifying dispatch, alternate-register
retention, and reduced expression-stack capacities. A generated prefix tree
was unnecessary after the exact three-byte table brought the encoder below its
review gate.

The following sections preserve the preimplementation census and projections.
Their numbers describe the decisions that led to the measured result above;
they are not current size claims.

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

The compression remained in AZM source while the result stabilized:

1. merge encoder tails and the other exact repeated helpers;
2. replace module-local workspace fields with proved live registers;
3. rerun the linked listing and convert every remaining in-range `JP`;
4. apply the flag and fall-through idioms;
5. assemble and run the complete correctness battery;
6. measure the new component and resident accounts;
7. experiment with keyword representation, predicates, dispatch, and
   expression overlays one at a time.

The retained result records baseline and result bytes, workspace delta,
self-assembly instruction and T-state deltas, and the proof commands. Losing
experiments remain documented so they are not repeated without a changed
premise. The native-source authority flip can resume after review of this checkpoint:
strict contracts, all 3,445 valid instruction forms, all invalid-form tests,
exact self-host byte comparison, stack and return-PC checks, source ROM guards,
and the complete memory audit pass.
