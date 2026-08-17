# Nucleus-model output ABI

Atom uses the Nucleus target-output boundary. Native compiler code submits
image bytes and final patch bytes to an operating adapter. The adapter retains
the image and patch spools and owns NOBJ framing, CRC, `BEGIN`, `MAP`,
`COMMIT`, abort, storage capacity, and publication.

Phase 2f is flat bank zero. The settled six-byte pending record has no bank
field.

## Sink entries

The operating adapter provides six routines in the complete driver build:

| Entry | Inputs | Operation |
| --- | --- | --- |
| `AtomSinkBegin` | `IX=build descriptor` | Open one uncommitted generation. |
| `AtomSinkImageByte` | `A=byte`, `C=bank`, `HL=address` | Append one byte to the image spool. |
| `AtomSinkPatchByte` | `A=byte`, `C=bank`, `HL=address` | Append one final replacement byte to the patch spool. |
| `AtomSinkPatchWord` | `C=bank`, `DE=address`, `HL=word` | Append one final little-endian replacement word to the patch spool. |
| `AtomSinkCommit` | `IX=build descriptor`, `HL=final cursor`, `DE=remaining capacity` | Form the map and atomically publish the generation. |
| `AtomSinkAbort` | none | Discard the open generation. |

Success returns carry clear. Failure returns carry set and a nonzero adapter
status in A. A failed call appends no operation. An earlier successful call may
remain in the uncommitted generation; the compiler driver must then call the
adapter's abort operation, as Nucleus does.

A failed begin leaves no open generation and receives no abort. Source,
capacity, image, patch, finalization, and commit failures after a successful
begin receive exactly one abort. Commit failure leaves the generation open
until that abort. The operating adapter constructs NOBJ framing and the flat
map from its retained descriptor and logical operation spools.

The direct output proof intercepts the production image and patch service
entries and records the same logical operation shape used by the Nucleus Z80
proofs: kind, bank, target address, byte count, and final bytes. It executes the
checked Atom-built core and adds no proof-only Z80 adapter code.

The Mac adapter intercepts these six entry addresses in Debug80 before their
stub instructions execute. It reads the documented Z80 registers, performs the
host operation, pops the native return address, and supplies A and carry as the
routine result. Each linked stub returns `$FF` with carry set when interception
is absent, so a missing host service fails at `AtomSinkBegin`.

The current memory sink accepts only bank zero. IMAGE addresses may advance or
leave gaps but may not descend or overlap. Each PATCH byte must name an earlier
IMAGE byte and may be patched once. COMMIT verifies the original descriptor,
remaining capacity, and final cursor before exposing the generation to its
caller. A forward `ORG` may leave a gap; a backward `ORG` followed by output is
rejected when its next IMAGE address descends below an earlier IMAGE end. The
Mac runner also observes native `ORG` and uninitialized `DS` entries. It retains
their highest logical extent and reports an intermediate out-of-range directive
at its original source position.

## Atom entries

`AtomOutputReset` accepts `HL=target start` and `DE=byte capacity`. It selects
flat bank zero and initializes the target cursor and remaining-capacity word.
The target descriptor must already have validated the mathematical extent.

Phase 2g adds the data and placement entries used by native directives:

| Entry | Input | Effect |
| --- | --- | --- |
| `AtomOutputCheckCapacity` | `HL=count` | Checks the remaining mathematical target span without changing state. |
| `AtomOutputEmitByte` | `A=byte` | Submits one IMAGE byte and advances the cursor. |
| `AtomOutputEmitWord` | `HL=word` | Submits two little-endian IMAGE bytes after a two-byte preflight. |
| `AtomOutputReserve` | `HL=count` | Advances over uninitialized target bytes without an IMAGE operation. |
| `AtomOutputSetOrigin` | `HL=address` | Replaces the logical target cursor without emitting output. |

`AtomOutputEmitInstruction` accepts IX pointing to the existing ten-byte parsed
instruction record. It performs these operations:

1. encodes into a four-byte resident scratch buffer;
2. checks complete instruction and pending-list capacity;
3. calls `AtomSinkImageByte` for each encoded byte at increasing addresses;
4. advances the cursor after each successful call; and
5. queues the parser's pending records after every image byte succeeds.

Local capacity failure occurs before the first sink call. Adapter failure
returns the adapter's status. The cursor counts only image bytes accepted by
the adapter.

`AtomOutputResolveSymbol` accepts IX pointing to a defined symbol record. It
peeks at one matching pending record, forms and range-checks the final patch,
submits it through the byte or word patch sink, and then removes the pending
record. It repeats until no pending record names that symbol.

The patch rules are:

| Kind | Final calculation |
| --- | --- |
| Byte | Symbol plus signed addend must fit 0–255. |
| Word | Symbol plus signed addend must remain in Atom's accepted word domain; the low word is stored little endian. |
| Relative | Subtract `patchAddress+1`; the result must fit -128–127. |
| Displacement | Symbol plus signed addend must fit -128–127. |
| Truncating byte | Store the low byte after signed-symbol and addend arithmetic; used by `DB`. |

Range or adapter failure leaves the current pending record in place. Patches
accepted earlier in the same symbol drain remain in the uncommitted adapter
spool and disappear when the driver aborts that generation.

`AtomPendingPeek` is the non-destructive counterpart of `AtomPendingTake`. It
accepts IX pointing to a symbol and returns `DE=patch address`, `B=kind`, and
`C=signed addend`. `AtomStatusNotFound` means the symbol has no remaining
pending record. In the complete driver build, the low three bits of B hold the
patch kind. The upper bits retain the source-part ordinal and diagnostic-anchor
flag; the resolver masks those bits before selecting the patch calculation.

The label and equate handlers call `AtomSymbolDeclare` or
`AtomSymbolDeclareGlobalLabel`, then `AtomOutputResolveSymbol`. The final driver
diagnoses remaining undefined symbols and calls the adapter's begin, commit,
or abort entries. Serialized NOBJ remains outside the native assembler.
