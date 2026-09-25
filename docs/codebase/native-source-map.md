# Native source map

[Engineering manual](index.md)

Atom's native assembler is one ordered Z80 program divided into ten logical
modules. The module boundaries already exist in the assembled image as named
start and end symbols. Source files should follow those boundaries so a reader
can open one file and find one complete responsibility.

## Execution order

```text
encoder and name packing
        |
        v
symbols and pending references
        |
        v
tokenizer -> expressions -> operand parser -> instruction encoder
                               |
                               v
                         output and patches
                               |
                               v
                    statements and directives
                               |
                               v
                       multipart driver
                               |
                               v
                      host-service boundary
```

This is a dependency order rather than a sequence in which every module runs
once. The statement layer repeatedly requests tokens, expressions and parsed
instructions. Symbol definitions can cause the output layer to resolve pending
patches. The driver repeats the statement layer for each ordered source part.

## Module boundaries

| Source module | Assembled range | Responsibility | Principal entries |
| --- | --- | --- | --- |
| `encoder.asm` | `EN_COREB` through `EN_WEND` | RADIX-40 packing, mnemonic recognition, form validation and Z80 instruction encoding | `EN_R40PK`, `EN_RECOG`, `EN_LEN`, `EN_VFORM`, `EN_NAME` |
| `symbols.asm` | `SY_CBEG` through `SY_WEND` | Global and private symbol records, scope transitions and pending-reference records | `SY_RESET`, `SY_FIND`, `SY_DECL`, `SY_REF`, `SY_DGLAB`, `SY_ADD`, `SY_PEEK`, `SY_TAKE` |
| `tokenizer.asm` | `TK_CBEG` through the complete `TK_SCOMM` routine | Source-byte access, lexical classifiers and complete lexeme scanners | `TK_RESET`, `TK_SPEEK`, `TK_SREAD`, `TK_STAKE`, `TK_SNAME`, `TK_SDLED`, `TK_SBASE`, `TK_SSTRI` |
| `tokenizer-dispatch.asm` | `TK_NEXT` through `TK_WEND` | Top-level token dispatch, character literals, lookup tables and published token storage | `TK_NEXT`, `TK_SCHAR`, `TK_LLEXE`, `TK_DESCA`, `TK_ILEND` |
| `expression.asm` | `EX_CBEG` through `EX_RFORW` | Expression grammar, bounded stacks and restricted deferred expressions | `EX_PARSE`, `EX_PDEFR` |
| `expression-arithmetic.asm` | `EX_LARIT` through `EX_WEND` | Concrete 24-bit arithmetic kernels and expression workspace | Arithmetic helpers called by `expression.asm` |
| `patch.asm` | `PT_CBEG` through `PT_CEND` | Mapping a validated operand to its patch byte, width and transform | `PT_LOCAT` |
| `parser.asm` | `PR_CBEG` through `PR_WEND` | Mnemonic and operand parsing, instruction records and deferred-reference descriptions | `PR_PUB`, `PR_PARSE`, `PR_CREFE`, `PR_QREFE` |
| `output.asm` | `OU_CBEG` through `OU_WEND` | Logical cursor management, IMAGE emission and resolved PATCH submission | `OU_RESET`, `OU_EMITB`, `OU_EMITW`, `OU_RESER`, `OU_SORIG`, `OU_EINS`, `OU_RSLV` |
| `statements.asm` | `ST_CBEG` through `ST_WEND` | Labels, equates, directives and complete source statements | `DR_APART`, `ST_NEXT` |
| `driver.asm` | `DR_CBEG` through `DR_WEND` | Build-descriptor validation, multipart assembly and final unresolved-symbol checks | `DR_ASM`, `DR_VDESC`, `DR_AFIN` |
| `host-services.asm` | `HS_SCBEG` through `HS_REND` | Fail-closed default implementations of the output service boundary | `HS_BEG`, `HS_IB`, `HS_PB`, `HS_PW`, `HS_CMT`, `HS_ABORT` |

The platform adapters are separate programs around this core:

- `named-object-adapter.asm` connects source and output calls to Z80 Tool
  Services named objects.
- `cpm22-adapter.asm` supplies CP/M command handling, dependency discovery,
  source reads and COM, BIN or Intel HEX publication.

## State ownership

Each module encloses its fixed writable state between a `*_WBEG` and `*_WEND`
pair. The patch locator and host-service stubs own no fixed workspace. Symbol
and pending arenas, source descriptors, output storage and the machine stack
belong to the caller and are not part of the resident core's fixed workspace.

The core is non-reentrant. A call to `DR_ASM` may use every module workspace
until it returns. Platform callbacks may temporarily use their own state but
must preserve the registers declared by the service contract.

## Source and platform seams

`TK_SREAD` is the source-byte seam. The checked desktop core contains a
memory-backed implementation. The desktop runner intercepts the entry while
native platform builds replace that bounded implementation with a jump to their
source provider.

The `HS_*` entries form the output seam. The checked core contains fail-closed
stubs. A platform build omits that module and supplies implementations that
begin a generation, accept IMAGE and PATCH operations, commit it or abort it.

These two seams are part of the source structure. Build scripts must identify
them through deliberate boundary markers or complete module files, never by
matching a register-contract comment or by assuming a numbered source part.

## Reading order

For a first reading, start with `driver.asm` and `statements.asm` to see the
outer control flow. Continue with `tokenizer.asm`, `tokenizer-dispatch.asm`,
`expression.asm`, `expression-arithmetic.asm` and
`parser.asm`, then read `output.asm` and `symbols.asm` together to understand
forward references. Read `encoder.asm` last because its dense validation and
opcode rules make more sense after the parsed instruction record is familiar.

The source comments should make this route possible without consulting the
symbol ledger. Every global name needs its long meaning and purpose beside its
declaration. Complex routines also need register roles, loop invariants and the
reason for each non-obvious flag-dependent branch.
