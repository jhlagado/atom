# Native multipart driver ABI

`AtomAssemble` consumes an ordered array of caller-owned source descriptors,
assembles every part once, performs the final symbol checks, and closes one
operating-adapter generation. Filesystem access, dependency resolution,
preprocessing, SP1 parsing, and source loading remain outside the native core.

## Build descriptor

IX points to a 15-byte descriptor:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | Source-part count, 1–16 |
| 1 | 2 | Pointer to the first source-part descriptor |
| 3 | 2 | Symbol-arena start |
| 5 | 2 | Symbol-arena end |
| 7 | 2 | Pending-arena start |
| 9 | 2 | Pending-arena end |
| 11 | 2 | Initial target address |
| 13 | 2 | Mathematical target byte capacity |

Each five-byte source-part descriptor contains its zero-based ordinal, source
start, and source end. The source interval is half-open. Ordinals must be the
exact sequence 0 through count-1. Source bytes, descriptors, and the build
descriptor remain immutable and addressable until `AtomAssemble` returns.

The driver validates count, descriptor-table arithmetic, ordinals, every source
range, both arena ranges, and the target extent before `AtomSinkBegin`. A
configuration failure therefore opens no generation and changes no caller
arena.

## Assembly sequence

After validation, `AtomAssemble` performs this sequence:

1. reset the symbol, pending, and output state from the build descriptor;
2. call `AtomSinkBegin` once;
3. reset the tokenizer and call `AtomAssemblePart` for each ordered descriptor;
4. call `AtomAssembleFinish` after the last part;
5. call `AtomSinkCommit` with the final cursor and remaining capacity; or
6. call `AtomSinkAbort` once after any post-begin failure.

Part EOF does not change private-label scope. A private label may therefore be
referenced in the following source part. Only a global label closes the current
private scope. Finalization validates the last private scope without evicting
it.

## Undefined-symbol diagnostics

The first pending record for each newly inserted undefined symbol contains a
diagnostic anchor. Its high kind bits store the part ordinal, while the
undefined symbol's value word stores the source offset. This uses the existing
six-byte pending and eight-byte symbol records.

`AtomAssembleFinish` returns `AtomStatementStatusUndefined` with carry set when
an anchor remains. It writes `AtomStatementErrorPart` and
`AtomStatementErrorOffset`, returns the symbol-record pointer in IX, and stores
the same pointer in `AtomDriverUndefinedSymbol`. A pending record without a
valid anchor, an invalid symbol pointer, a stale anchor on a defined symbol, or
an undefined record without pending metadata produces the distinct internal
status.

## Driver statuses

Success returns A=0 with carry clear. Failure returns carry set:

| Value | Category | Detail |
| ---: | --- | --- |
| 1 | Configuration | One of the seven descriptor checks |
| 2 | Source assembly | Statement category in `AtomDriverDetail`; nested component status remains in `AtomStatementDetail` |
| 3 | Undefined symbol | `AtomDriverDetail=AtomStatementStatusUndefined` |
| 4 | Operating output | Sink begin or commit status |
| 5 | Internal invariant | Nested status when one exists |

Source failures retain the statement part and offset. Begin failure receives
no abort because no generation opened. Every later failure receives one abort;
the driver preserves the original category and detail across that call.

The driver itself uses nine fixed workspace bytes. Its caller-owned build
descriptor occupies 15 bytes, and the complete 16-part descriptor array
occupies 80 bytes.
