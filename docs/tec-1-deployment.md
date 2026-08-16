# TEC-1 deployment design

Atom's native assembler is complete and fits one 16 KiB bank. The current
repository does not yet contain a TEC-1 filesystem and output adapter. This
document defines what that adapter must provide and identifies the memory
decision that must be measured before hardware deployment.

## Portable native core

The native core performs tokenization, expressions, symbols, private-scope
eviction, instructions, directives, forward patch decisions, final undefined
checks, and build lifecycle control. It depends on neither Node nor a
filesystem. Its public entry is `AtomAssemble`, which consumes memory-backed
source descriptors and caller-owned symbol and pending arenas.

The current checked image is linked at `$0000` for Debug80. Its linked extent is
Measured 12,356 bytes, leaving Measured 4,028 bytes below `$4000`. A TEC target
may keep that placement or relink the same modules at a target-specific ROM or
bank origin. Relinking must be followed by the complete strict-contract and
runtime proof battery; the Mac address is not a portable absolute contract.

## Required operating services

A TEC adapter must provide the six sink calls documented in `output-abi.md`:

- begin one tentative generation;
- append an IMAGE byte;
- append a final byte PATCH;
- append a final little-endian word PATCH;
- commit with the final cursor and remaining capacity; and
- abort an open generation.

The Debug80 image contains 18 bytes of fail-closed stubs at those names. They
return failure when executed directly. A hardware build must replace or route
those entries to real operating services; copying the pinned Mac image to the
TEC-1 is not enough.

The sink can use sequential storage. IMAGE and PATCH records are append-only,
and a PATCH contains final bytes rather than a symbol name. Intel HEX, listings,
D8 maps, and a flat binary can be rendered later by a filesystem-aware layer.

## Source loading

The settled host pipeline is still suitable on the TEC-1:

```text
entry source
    -> dependency resolver and conditional preprocessor
    -> ordered SP1 source plan
    -> source-part loader
    -> AtomAssemble
```

The preprocessor masks directives and inactive source with spaces and lowers
`INCBIN` to an equal-length initialized reservation. The loader must retain
each part's logical ordinal, original identity, and binary snapshots for
diagnostics and output substitution. It need not concatenate files or expose
filesystem calls to the assembler.

The current tokenizer takes a half-open memory interval and requires the part
to remain addressable until it reaches EOF. The Mac adapter pages at whole-part
boundaries, and each part may be as large as 24 KiB. Atom's self-host source has
five generated parts totalling Measured 101,723 bytes plus a small entry
part. This proves multipart operation but does not prove that the same page
size fits TEC RAM.

## RAM decision

With less than 24 KiB of effective RAM, the Mac proof layout cannot be copied
unchanged. Its 531-byte fixed workspace, symbol arena, pending arena, maximum
descriptors, and 256-byte stack consume Measured 16,759 bytes before source
buffering. Only 7,817 bytes remain in a 24 KiB budget, and the operating adapter
needs some of that space.

There are three credible deployment choices:

1. Put the source window in separate banked or external memory. This preserves
   the native tokenizer and is the smallest change to the assembler.
2. Generate smaller source parts whose maximum size fits the remaining RAM.
   This preserves the ABI but makes source-generation limits target-specific.
3. Add a byte-fetch or refill service below the tokenizer. This removes the
   whole-part residency requirement but changes native code and must be sized,
   cycle-measured, and reproved.

The first choice is preferred when TEC storage hardware exposes a usable bank
or window. Otherwise the next project checkpoint should measure the third
choice against the 4,028-byte resident margin. It is a Hypothesis, not a
projection, that the complete source and sink adapter will fit that margin.

A TEC filesystem adapter must also implement the measured Mac `INCBIN`
contract: confined snapshot reads relative to the containing source, whole-file
length validation, and exact IMAGE-byte substitution before commit. Its code,
metadata, and buffering cost remain unmeasured for TEC hardware.

Symbol capacity is another target choice. Use eight bytes for every permanent
global plus the peak private scope, and six bytes for the peak concurrent
unresolved list. Reducing those arenas reduces maximum program complexity but
does not change output bytes.

## Deployment acceptance proof

A TEC adapter is ready only when all of these claims are measured:

- the final linked core plus adapter remains at or below 16,384 resident bytes;
- the complete target memory map has no overlap and includes stack guards;
- source parts cannot be modified by Atom and every refill preserves offsets;
- begin/commit/abort counts are exact on success and injected failures;
- IMAGE and PATCH output survives power-safe publication or a documented
  recoverable protocol;
- one full Atom self-build matches the pinned AZM image at every initialized
  address and across the complete resident extent; and
- the second Atom-built generation is identical to the first.

Until those checks pass on the selected TEC operating layer, Atom is a working
Mac command-line assembler and a proved portable Z80 core, not a finished
TEC-1 application image.
