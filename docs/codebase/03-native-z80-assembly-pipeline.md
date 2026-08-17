# Chapter 3 — Native Z80 assembly pipeline

[← Host source preparation](02-host-source-preparation.md) | [Host execution, artifacts, and interfaces →](04-host-execution-artifacts-and-interfaces.md)

The native pipeline begins at `AtomAssemble` and ends when the output adapter
accepts a commit or abort. Everything between those points runs as Z80 code.
The compiler uses caller-owned source, symbol, and pending arenas plus 453 bytes
of fixed non-reentrant workspace linked beside the code and immutable tables.

`native/atom.atm` selects the complete configuration. Frozen AZM proof images
still use assembly-time flags to link isolated subsystem modes during their
checked-core migration, but the installed core enables deferred expressions,
statement parsing, output, symbol resolution, and the multipart driver.

## Build descriptor and driver

`AtomAssemble` receives `IX` pointing at a 15-byte build descriptor:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | Source-part count, 1 through 16 |
| 1 | 2 | Pointer to the first part descriptor |
| 3 | 2 | Symbol-arena start |
| 5 | 2 | Symbol-arena end |
| 7 | 2 | Pending-arena start |
| 9 | 2 | Pending-arena end |
| 11 | 2 | Initial target address |
| 13 | 2 | Mathematical target capacity |

Each five-byte part descriptor contains an exact ordinal followed by a
half-open source start and end address. Source and descriptor memory remain
immutable until the routine returns.

The first driver action is validation. `AtomDriverValidateDescriptor` checks:

- part count;
- descriptor-table arithmetic;
- ordinals in the exact sequence `0..COUNT-1`;
- every half-open source range;
- symbol and pending arena ranges; and
- non-wrapping target extent.

A validation failure occurs before `AtomSinkBegin`, so it opens no generation
and changes no caller arena. After validation, the driver resets symbol,
pending, and output state, calls begin once, assembles each part, performs final
symbol checks, and calls commit. Every failure after a successful begin calls
abort exactly once while preserving the original category and nested status.

The assembly loop is compact:

```text
ATOMASSEMBLE
  VALIDATE DESCRIPTOR
  RESET SYMBOLS, PENDING RECORDS, AND OUTPUT
  SINK BEGIN
  FOR EACH PART
    ATOMTOKENIZERRESET
    ATOMASSEMBLEPART
  ATOMASSEMBLEFINISH
  SINK COMMIT
```

Part EOF is not whole-build EOF. Private scope can cross a part boundary, and a
global reference in one part may be defined in a later part.

## Tokenizer

`asm/atom-tokenizer.asm` reads one installed source interval from low address to
high address. `AtomTokenizerReset` records the part ordinal, source cursor, end,
and zero-based offset. `AtomTokenizerNext` skips horizontal whitespace and
comments, then dispatches by the next source byte.

The fixed nine-byte token record contains:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | Token kind |
| 1 | 1 | Source-part ordinal |
| 2 | 2 | Byte offset from the part start |
| 4 | 2 | Lexeme pointer |
| 6 | 1 | Raw lexeme length |
| 7 | 2 | Decoded numeric value, or zero |

Names retain their source spelling and point into the caller's source buffer.
Consumers pass the pointer and length to mnemonic or RADIX-40 routines that
perform case folding. No token pointer enters the symbol table or output
stream.

The tokenizer recognizes names, private names, decimal and hexadecimal or
binary numeric forms, current location `$`, character literals, strings,
operators, punctuation, line endings, and EOF. Blank and comment-only lines
produce no EOL token. A non-empty final line receives one synthetic EOL before
EOF, preventing adjacent source parts from joining two words.

The `%` dispatch distinguishes binary literals and remainder from an
unprocessed host directive. A percent sign followed by an ASCII letter before
the first token on a line returns a dedicated lexical failure. This catches a
host-preparation leak rather than allowing `%INCLUDE` or `%IF` to reach ordinary
expression parsing.

Each public tokenizer entry has direct tests for exact SP and return PC,
immutable source, token-record commit, guards, IY preservation, repeated EOF,
and its complete declared memory write set.

## RADIX-40 and symbols

`AtomRadix40Pack` lives in `atom-encoder.asm` because mnemonic recognition and
symbol storage share the arithmetic. It accepts one through eight ASCII
letters, digits, or underscores, folds letters to uppercase, and writes three
packed words. Failure leaves the destination unchanged.

`AtomPackSymbol` in `atom-symbols.asm` adds symbol syntax and flags. A private
name begins with `.`, but the period is not stored in the RADIX-40 payload. One
eight-byte symbol record contains six packed-name bytes plus a two-byte value.
Unused high bits in the final packed-name byte record private, defined, and
signed-equate state.

The symbol arena grows from both ends:

```text
SYMBOL ARENA START
  GLOBAL RECORD 0
  GLOBAL RECORD 1
  ...
  FREE SPACE
  ...
  CURRENT PRIVATE RECORD 1
  CURRENT PRIVATE RECORD 0
SYMBOL ARENA END
```

Globals grow upward and remain for the whole build. Current-scope private
records grow downward. A new global label first validates the old private scope
and the new record's capacity, then evicts the private records and declares the
global as one transaction. A global `EQU` does not change private scope.

Every declaration or reference checks capacity before publishing a cursor.
`AtomSymbolReference` either returns an existing symbol or inserts one undefined
record. `AtomSymbolDeclare` and `AtomSymbolDeclareGlobalLabel` define a value
and return the live record so the output module can resolve its pending uses.

## Pending references

The separate pending arena grows upward in six-byte records:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 2 | Symbol-record pointer |
| 2 | 2 | Logical patch address |
| 4 | 1 | Patch kind, part ordinal, and diagnostic-anchor flag |
| 5 | 1 | Signed addend or auxiliary byte |

The first pending record for a newly inserted undefined symbol carries a
diagnostic anchor. Its kind byte also retains the source-part ordinal, while
the undefined symbol's unused value field retains the reference's source
offset. Definition replaces that field with the real value, and successful
patch resolution removes all pending records for the symbol.

`AtomPendingPeek` returns a matching record without removing it. The output
module forms and submits final patch bytes, then calls `AtomPendingTake` only
after the sink accepts them. `AtomPendingTake` fills a removed hole with the
last live record, so pending storage remains dense and proportional to peak
concurrent unresolved references.

Private-scope eviction checks both symbol and pending invariants. An undefined
private label is a source error. A pending record that points at a defined
private record is an internal failure because successful definition should have
drained it.

## Expression evaluator

`asm/atom-expression.asm` implements precedence parsing with a value stack and
an operator stack. Each stack has 16 entries. Values use signed 24-bit
intermediates plus metadata for concrete or deferred state. Operators carry
kind, precedence, unary state, and source position.

The evaluator supports:

```text
|  ^  &  <<  >>  +  -  *  /  %  UNARY +  UNARY -  ~
PARENTHESES
LOW(EXPRESSION)
HIGH(EXPRESSION)
```

`AtomExpressionParse` requires a concrete result. `AtomExpressionParseDeferred`
also permits the restricted forward form used by instructions, `DB`, and `DW`.
That deferred value contains one exact symbol and a signed-byte addend. The
reducer accepts addition or subtraction that preserves the affine form and
rejects operations that would require two symbols, symbol multiplication, or a
wider retained expression.

`LOW()` and `HIGH()` may wrap one deferred affine expression. Their state is
carried to the parser as a distinct patch transform. Further arithmetic outside
the function is rejected because the six-byte pending record has nowhere to
store that expression tree.

Concrete arithmetic uses signed 24-bit intermediates. The final word domain is
`-32768..65535`; shifts accept counts `0..23`. Division and remainder share
magnitude preparation, unsigned long division, and sign restoration. Each
operator path returns a precise status for syntax, zero division, numeric
range, stack capacity, unsupported forward form, symbol failure, or internal
state.

## Parsed instruction record

`AtomParserParse` in `asm/atom-parser.asm` consumes a mnemonic and up to three
operands into the encoder's ten-byte record:

| Offset | Field |
| ---: | --- |
| 0 | Mnemonic ordinal |
| 1–3 | Operand classes |
| 4–9 | Three little-endian concrete values |

Registers, conditions, bit indexes, interrupt modes, and restart vectors are
represented by operand classes. Values are used for immediate, absolute,
relative, displacement, and port forms.

The parser first recognizes the mnemonic through the packed mnemonic table.
It classifies word operands through the generated operand table and handles
parenthesized absolute, register-indirect, port, and IX/IY displacement forms.
An expression result is normalized to the concrete operand class required by
the instruction family.

The parser builds the result in scratch storage. It calls `AtomValidateForm`
before committing the caller's record or inserting missing symbols. This order
prevents a malformed instruction from changing the symbol arena. It also
preflights all symbol records and public references needed by the complete
instruction, including the two-reference form `LD (IX+D),N`.

A successful parse publishes zero, one, or two nine-byte reference descriptions
until the next parse call. Each description retains symbol pointer, signed
addend, operand index, patch kind, field offset, source part, and source offset.
`AtomParserCheckReferences` verifies pending capacity before output begins;
`AtomParserQueueReferences` converts field offsets to logical patch addresses
after every instruction byte has been accepted.

## Patch-field locator

`asm/atom-patch.asm` is a small bridge between the validated operand record and
the output layer. `AtomPatchLocate` maps one operand index to a byte offset and
patch kind:

| Kind | Final operation |
| --- | --- |
| Byte | Require `0..255` and write one byte |
| Word | Write the final little-endian word |
| Relative | Subtract `PATCHADDRESS+1` and require `-128..127` |
| Displacement | Require `-128..127` |
| Truncating byte | Write the low byte for `DB` |
| Low byte | Write bits 0 through 7 |
| High byte | Write bits 8 through 15 |

The locator remains separate from the measured Phase 1 encoder account. It
depends only on a form that validation has already accepted.

## Instruction validation and encoding

`asm/atom-encoder.asm` combines four related facilities:

1. RADIX-40 packing;
2. packed mnemonic recognition through an exact three-byte-per-name table;
3. form validation and length calculation; and
4. byte encoding into a four-byte commit buffer.

`AtomFormLength` and `AtomValidateForm` ignore concrete operand values. They
validate mnemonic ordinal, operand classes, arity, condition restrictions,
index-half collisions, and instruction-family rules, then return a length from
one through four bytes.

`AtomEncode` calls the same validation path, encodes into `AtomScratch`, and
copies exactly the reported bytes to the destination only on success. The
destination and `DE` therefore remain unchanged when a form is invalid. Four
bytes cover the longest Z80 encoding.

The implementation exploits the instruction set's regular fields:

- register-to-register loads combine destination and source fields;
- ALU operations combine an operation ordinal and register field;
- INC and DEC combine a base opcode with a register field;
- condition codes occupy the same opcode bits in branches, calls, and returns;
- CB operations combine family, bit, and register fields; and
- DD or FD prefix selection transforms the applicable HL form.

Irregular core and ED forms use small tables. LD has its own validation and
encoding paths because it contains the broadest set of register, memory,
absolute, index, half-register, and special-register interactions. The current
measurement records 881 direct LD bytes inside the 3,132-byte encoder core.

The frozen differential census contains 69 mnemonic spellings and 3,445 valid
logical forms. The encoder also rejects 526 AZM-invalid source forms and 2,453
systematically malformed records. `test/cases.mjs` is the generated input
space; `proofs/azm-form-census.json` independently fixes its count, per-mnemonic
distribution, and canonical hash.

## Statements and directives

`AtomAssemblePart` in `asm/atom-statements.asm` consumes tokens until part EOF.
At each statement it records a diagnostic position, recognizes the first name,
and distinguishes these source shapes:

```asm
START:
START: LD A,1
LIMIT EQU 16
LIMIT: EQU 16
ORG 4000H
DB 1,"TEXT"
DW START
DS 16
ALIGN 8
```

Mnemonic recognition happens before directive recognition. A name that is
neither a mnemonic nor a bare directive may introduce a label or equate. The
optional colon before `EQU` is consumed as declaration syntax and does not
publish an address label.

The directive recognizer uses a small packed table for `EQU`, `ORG`, `DB`,
`DW`, `DS`, `CSTR`, `PSTR`, `ISTR`, and `ALIGN`. Each handler evaluates the
required expression mode, checks delimiters, preflights capacity, and calls the
output or symbol layer.

`DB` and `DW` accept deferred affine expressions. They emit placeholder IMAGE
bytes and append pending records after output succeeds. `DB` strings are
decoded in the native statement module. `CSTR`, `PSTR`, and `ISTR` share the
same scanner with different prefix or suffix rules. `DS COUNT` advances the
logical cursor without IMAGE output, while `DS COUNT,FILL` submits initialized
bytes. `ALIGN` calculates and emits the complete zero fill only after checking
the target capacity.

Every statement failure is reduced to one of nine outer categories while
retaining the nested component status and exact source part and offset. The
host converts those native fields back to the original logical path, line, and
byte column.

## Output state and patches

`asm/atom-output.asm` owns the logical target cursor and remaining capacity.
The current profile always uses bank zero.

`AtomOutputEmitInstruction` performs an ordered transaction:

1. encode into its own four-byte buffer;
2. check total output capacity;
3. check pending capacity for every deferred field;
4. submit each encoded byte as an IMAGE operation;
5. advance the cursor only after each accepted byte; and
6. append the already-built pending records after all bytes succeed.

`AtomOutputResolveSymbol` peeks at one pending record, calculates and checks its
final value, submits a byte or word PATCH, and removes the record after sink
success. It repeats until no pending record names that symbol. A patch failure
leaves the current record intact; the driver aborts the complete uncommitted
generation, including any earlier accepted operations.

`ORG` changes the logical cursor without emitting a byte. Uninitialized `DS`
checks and subtracts capacity, then advances without an IMAGE operation. The
host runner observes both calls to retain layout provenance and the high-water
mark used by materialized artifacts.

## Finalization

After the last part, `AtomAssembleFinish` scans the pending arena for a valid
diagnostic anchor. An unresolved symbol returns its record pointer and restores
the exact part and source offset captured at the first reference. Corrupt or
inconsistent anchor state returns an internal failure.

With no pending records, finalization validates the current private scope and
then checks that every retained global record is defined. Only then may the
driver call `AtomSinkCommit`.

The output boundary is append-only from the operating adapter's perspective:
IMAGE records contain source-order bytes, and PATCH records contain final
replacement bytes. A PATCH carries no symbol name or expression. This is what
allows the native assembler to remain single-pass while a sequential-storage
adapter defers only serialization.
