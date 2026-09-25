# Codebase guide

Atom consists of a Z80 assembler core and the operating code around it. The
core implements the language and emits a stream of image bytes and patches.
The operating code supplies files, runs the core and turns that stream into
the output requested by the user.

The desktop command runs the Z80 core in Debug80. The CP/M program runs the
same core on the processor and supplies its services through BDOS.

The checked core contains 11,686 bytes of code and immutable tables plus 714
bytes of fixed workspace. Its 12,400-byte resident extent remains within one
16 KiB bank. Source descriptors, symbols, pending references and the stack are
caller-owned storage outside that extent.

## Repository layout

```text
assets/       generated native images retained in the package
bin/          installed command-line programs
docs/         current user and contributor documentation
examples/     small source projects
proofs/       checked measurements, memory maps and boundary counts
scripts/      build, validation and release programs
src/host/     Node host, public API, renderers and execution adapters
src/z80/      Z80 core, native adapters and symbol ledger
test/         native, host, package and self-host tests
```

Files in `src/` are authoritative source. Files in `assets/` are generated and
must be rebuilt through their scripts. Every JSON record remaining in `proofs/`
is consumed by a test, build check, package check or release step.

## Maintainer tools

The scripts build the native images, verify selected host integrations, and
prepare packages. The installed command-line programs live in `bin/`.

| File | Purpose |
| --- | --- |
| `scripts/bundled-dependencies.mjs` | Create temporary workspace links for offline npm packaging, then remove the links and restore `package.json`. |
| `scripts/cpm22-atom-source.mjs` | Prepare source names and parts for the native CP/M build. |
| `scripts/generate-cpm22.mjs` | Build or verify the CP/M executable and its census. |
| `scripts/generate-native-core.mjs` | Assemble the core twice and build or verify its checked image and symbols. |
| `scripts/generate-native-object-harness.mjs` | Build or verify the standalone object-service harness. |
| `scripts/generate-stage1-record.mjs` | Build or check the small portable-host conformance record. |
| `scripts/measure-cpm22-output-candidates.mjs` | Measure CP/M output-kernel alternatives and verify their recorded sizes. |
| `scripts/package-census.mjs` | Record or check the files and unpacked size in the npm package. |
| `scripts/prepare-github-release.mjs` | Prepare the CP/M executable, release metadata and checksums. |
| `scripts/verify-dependencies.mjs` | Check installed shared-package versions against supported release ranges. |
| `scripts/verify-example.mjs` | Build the shipped example and check its generated artifacts. |
| `scripts/verify-stage3-node-deno.mjs` | Compare CLI output from Node and Deno. |
| `scripts/verify-triptych-wasm.mjs` | Optionally compare Atom execution through the Triptych WASM adapter; requires its local module. |

The native measurement commands use `test/measure-*.mjs` because they share the
native harnesses and fixtures; they report code, workspace and execution costs.
The separate `measure:cpm22-output-candidates` command measures alternative
CP/M output kernels. Without `--check`, it updates
`proofs/cpm22-output-candidates.json`.

## Build path

```text
root source file
        |
        v
host source preparation
        |  ordered source parts with unchanged byte positions
        v
Z80 Atom core
        |  IMAGE, PATCH, layout and symbol events
        v
host renderer
        |  NOBJ, BIN, COM, HEX, listing or D8
        v
selected output files
```

Dependency discovery and assembly are separate stages. Atom still makes one
semantic pass over the prepared source. A forward reference enters a resident
pending list. When its symbol is defined, Atom emits a PATCH containing the
final byte or word.

### Host responsibilities

The host or operating adapter:

- reads source and binary files
- resolves leading `%INCLUDE` dependencies
- evaluates host conditional directives where the platform supports them
- assigns source ordinals and retains filenames
- supplies one source byte when the native core requests it
- accepts IMAGE and PATCH operations
- renders and publishes files

### Z80 responsibilities

The core:

- tokenises source
- evaluates expressions
- stores global and private symbols
- parses and validates instructions and directives
- encodes the Z80 instruction set
- tracks forward references
- controls the output lifecycle
- checks for unresolved symbols before commit

The boundary keeps filesystem and output-format code out of the resident
assembler while preserving one implementation of the language.

## Source preparation

`resolveAtomProject()` begins the desktop path. It uses the shared Z80 Tool
Services source reader and resolver with Atom's directive profile.

The source reader keeps three identities:

| Identity | Use |
| --- | --- |
| Physical path | Canonical file opened by Node |
| Dependency identity | Deduplication and cycle detection |
| Logical identity | Diagnostics, listings and D8 maps |

Includes resolve relative to the importing file. The reader confines every
path to the project root and rejects case conflicts, missing files and escapes
through `..` or symbolic links.

The resolver walks dependencies in depth-first postorder. Dependencies precede
their importer, sibling order follows the source and each physical dependency
appears once. Every file remains a distinct source part.

Atom replaces host directives and inactive lines with spaces while retaining
CR and LF bytes. The native offset therefore points at the same byte in the
original file. Active `INCBIN` lines are lowered to equal-length initialised
reservations. Their binary snapshots remain beside the source part and the
desktop output bridge substitutes those bytes during assembly.

The main modules are:

```text
src/host/atom/          directives, literals, masking and INCBIN
src/host/application/   project resolution and high-level assembly
src/host/core/          checked native image loader
src/host/harness/       Z80 execution adapters
src/host/providers/     host-service providers
src/host/artifacts/     NOBJ and user output formats
src/host/self-host/     native regeneration
src/host/translation/   source migration tools
```

## Native core

`src/z80/atom.asm` includes the core modules in dependency order.

| Module | Responsibility | Principal entries |
| --- | --- | --- |
| `encoder.asm` | RADIX-40 packing, mnemonic recognition and family dispatch | `EN_R40PK`, `EN_RECOG`, `AT_DMNEM` |
| `encform.asm` | Operand validation and exact instruction-length selection | `EN_LEN`, `EN_VFORM` |
| `encode.asm` | Validated opcode and prefix emission | `EN_NAME`, `EN_CORE` |
| `symbols.asm` | Global and private symbols plus pending-reference records | `SY_RESET`, `SY_FIND`, `SY_DECL`, `SY_REF`, `SY_ADD`, `SY_PEEK`, `SY_TAKE` |
| `token.asm` | Source access, classifiers and lexeme scanners | `TK_RESET`, `TK_SREAD`, `TK_SNAME`, `TK_SBASE`, `TK_SSTRI` |
| `tokdisp.asm` | Token dispatch, character literals and token publication | `TK_NEXT`, `TK_SCHAR`, `TK_LLEXE` |
| `expr.asm` | Expression grammar, precedence and deferred values | `EX_PARSE`, `EX_PDEFR` |
| `exprmath.asm` | Concrete 24-bit arithmetic and expression workspace | internal arithmetic helpers |
| `patch.asm` | Encoded field location and patch transforms | `PT_LOCAT` |
| `parser.asm` | Mnemonic and operand syntax | `PR_PUB`, `PR_PARSE`, `PR_POP`, `PR_PMEMO` |
| `forms.asm` | Operand normalisation, form selection and concrete range checks | `PR_NAALI`, `PR_VCAND`, `PR_CCVAL` |
| `refs.asm` | Deferred symbols, reference publication, record commit and parser workspace | `PR_FREFE`, `PR_CREFE`, `PR_QREFE`, `PR_CMT` |
| `output.asm` | Logical cursor, IMAGE output and resolved patches | `OU_RESET`, `OU_EMITB`, `OU_RESER`, `OU_EINS`, `OU_RSLV` |
| `stmts.asm` | Labels, equates, directives and source statements | `DR_APART`, `ST_NEXT` |
| `driver.asm` | Descriptor validation, multipart assembly and final checks | `DR_ASM`, `DR_VDESC`, `DR_AFIN` |
| `host.asm` | Fail-closed output-service entries | `HS_BEG`, `HS_IB`, `HS_PB`, `HS_PW`, `HS_CMT`, `HS_ABORT` |

The two platform programs sit around this core:

- `nobj.asm` connects source and output calls to Z80 Tool Services named
  objects
- `cpm22.asm` handles CP/M command input, includes, source reads and output
  publication

`src/z80/atom-symbols.json` maps compact native names to their host-visible
names. Native globals have at most eight significant characters, so module
prefixes keep names distinct. Dot-prefixed labels are local to the preceding
global and do not need ledger entries.

## Driver and source descriptors

`DR_ASM` receives a 15-byte build descriptor:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | Source-part count, 1 to 255 |
| 1 | 2 | Part-descriptor address |
| 3 | 2 | Symbol-arena start |
| 5 | 2 | Symbol-arena end |
| 7 | 2 | Pending-arena start |
| 9 | 2 | Pending-arena end |
| 11 | 2 | Initial target address |
| 13 | 2 | Target capacity |

Each five-byte part descriptor contains an ordinal and a half-open source
range. The desktop runner uses logical ranges and serves bytes from JavaScript
snapshots. A native adapter can point the range at memory or translate it into
operating-system reads.

The driver validates every descriptor and arena before opening an output. It
then resets state, begins one generation, assembles each part and performs the
final symbol checks. A failure after begin calls abort once. Only a fully
resolved build reaches commit.

## Language pipeline

The tokenizer publishes a fixed nine-byte token record. Names remain in a
256-byte lexeme buffer until the consumer packs or classifies them. A synthetic
end-of-line token closes a non-empty final line, so two source parts cannot join
into one token.

The expression evaluator uses 16 value entries and 16 operator entries.
Concrete arithmetic uses signed 24-bit intermediates. A forward expression is
restricted to one symbol, a signed-byte addend and an optional LOW or HIGH
transform, which fits the pending-record format.

The parser builds a provisional ten-byte instruction record containing one
mnemonic, three operand classes and three values. Form validation runs before
the caller's record or symbol arena changes. The encoder writes into a
four-byte scratch buffer and commits those bytes only after validation.

The statement layer recognises labels, equates, instructions and bare
directives. It reduces lower-level failures to a public status while retaining
the nested status and exact source position.

## Symbols and patches

Each symbol record occupies eight bytes. Permanent globals grow upwards from
the start of the symbol arena. Current-scope private symbols grow downwards
from its end and are removed when the next global label begins.

Each unresolved reference occupies seven bytes in the pending arena. A pending
record stores the symbol record, output address, patch kind, addend and source
part. The first reference also preserves the source offset used if the symbol
is still undefined at the end.

The output layer submits IMAGE bytes in source order. When a definition
resolves a symbol, it calculates each final field, submits a byte or word PATCH
and removes that pending record only after the sink accepts it.

## Desktop execution

`native-atom-runner.mjs` loads `assets/native-core.json`, validates its digests
and checks the required symbols and immutable ranges. It installs the build
descriptor, guarded stack and caller-owned arenas in a 64 KiB Debug80 machine.

The runner intercepts the source-read entry and six sink entries. Source reads
return bytes from immutable host snapshots. Sink calls become operations on a
tentative in-memory generation. The linked Z80 sink entries fail closed if a
host forgets to intercept them.

After execution the runner checks the return address, stack, canaries,
descriptors, code and immutable tables. The committed generation retains IMAGE,
PATCH, layout and source-symbol records for the renderers.

## Generated files and proofs

The generated runtime files are:

| File | Build command | Check command |
| --- | --- | --- |
| `assets/native-core.json` | `npm run build:native-core` | `npm run verify:native-source` |
| `assets/atom-object-harness.bin` | `npm run build:native-object` | `npm run verify:native-object` |
| `assets/atom-cpm22.com` | `npm run build:cpm22` | `npm run verify:cpm22` |

The native-core generator uses the checked Atom image to assemble the source,
then uses that result to assemble the source again. Both generations must have
the same initialised addresses, bytes, symbols and resident extent.

The JSON files under `proofs/` fix memory maps, instruction counts, boundary
counts and package contents. Tests consume them directly.

## Reading routes

Start with `driver.asm` and `stmts.asm` for the build and statement loops. Read
`token.asm`, `tokdisp.asm`, `expr.asm`, `exprmath.asm`, `parser.asm` and
`forms.asm` for the language path. Continue through `refs.asm`, `output.asm`
and `symbols.asm` to trace forward references. Then follow `encoder.asm`,
`encform.asm` and `encode.asm` from name recognition through byte emission.

For the host, begin at `assemble-atom-project.mjs`. Follow source work into
`resolve-atom-project.mjs` and `src/host/atom/`, execution into
`native-atom-runner.mjs` and file creation into `src/host/artifacts/`.

The [maintenance guide](maintenance.md) gives the assembly-commentary rules,
test sequence and release procedure.
