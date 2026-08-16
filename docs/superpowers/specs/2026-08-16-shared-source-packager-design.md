# Shared source-packager design

## Status and authority

This document records the agreed host boundary for Atom and the Nucleus rewrite.
It defines a common dependency resolver, portable source plan, multipart adapter,
and provenance model. Each language retains its own directive spelling and
emission policy.

Atom's existing source-part and tokenizer ABIs remain authoritative below this
boundary. Nucleus is undergoing a major rewrite, so its profile in this document
defines the intended shared boundary rather than preserving every detail of the
current flat-manifest specification.

This design does not place a filesystem, dependency graph, preprocessor, or
source-plan reader in either resident compiler. Those facilities belong to a
filesystem-aware Node or Z80 host.

## Architectural boundary

The build has two stages, not two compiler passes:

```text
filesystem and directive reader
        |
dependency resolver
        |
ordered source plan
        |
language-specific multipart adapter
        |
streaming compiler or assembler
```

The resolver reads dependency directives and constructs one deterministic
ordered plan. The adapter then submits each selected file as a distinct source
part. The resident compiler reads the resulting logical stream once and has no
filesystem or dependency-graph interface.

The low-level host API continues to accept an explicitly ordered source-part
array. Tests, embedded hosts, and callers that already know the order need not
run dependency discovery.

## Common conceptual interface

The common operation is:

```text
resolve(project) -> ordered parts {
    ordinal,
    bank,
    logical identity,
    original bytes,
    compiler bytes,
    provenance
}
```

`original bytes` and `compiler bytes` are conceptual byte streams. An
implementation may expose bounded chunks and must not materialize every source
part or the complete compilation in RAM. A Z80 host may write the resolved plan
to external storage, validate it, rewind it, and stream each source file.

Each part has one ordinal in plan order. Included or imported files remain
separate parts with their own identities. The resolver never pastes their bytes
anonymously into the importing part.

The two language profiles use different emission policies:

- Nucleus passes source through unchanged. `compiler bytes` and `original
  bytes` are byte-identical.
- Atom masks preprocessing. Directive lines and inactive conditional lines have
  every non-newline byte replaced by ASCII space. CR and LF bytes remain at
  their original offsets, so `compiler bytes` has exactly the same length as
  `original bytes`.

Equal-length masking gives Atom direct part-relative offset, line, and column
mapping. The host retains the original bytes for diagnostics, listings, and D8
source text.

## Identity model

The resolver keeps three identities separate:

1. The physical path opens the source on the current filesystem.
2. The dependency identity is the canonical physical identity used for cycle
   and diamond detection.
3. The logical identity is the normalized project-relative path used in the
   source plan, diagnostics, listings, D8 maps, and source placement rules.

Absolute physical paths never enter the source plan or published artifacts.
Relocating the project root therefore does not change logical identities.

Logical paths preserve ASCII letter case and use `/` separators. A resolver on
a case-insensitive filesystem verifies the physical spelling and rejects
case-conflicting aliases. Different import spellings that resolve to one
physical file receive one canonical logical identity or a diagnostic; traversal
order must not select the identity accidentally.

## Dependency resolution

The project supplies one root directory and one entry source. For every active
dependency directive, the resolver:

1. resolves the quoted path relative to the importing file;
2. rejects an absolute path or a resolution outside the project root;
3. computes physical, dependency, and logical identities;
4. recursively visits the dependency; and
5. appends the importer after all of its dependencies.

The result is deterministic depth-first postorder. Source order determines the
order of sibling dependencies. A diamond includes the shared dependency once.
A repeated direct dependency in one header is an error. A cycle is an error and
the diagnostic includes every edge and source location in the cycle.

Dependencies establish compilation membership and order. They do not create
namespaces, exports, or per-file visibility. Each language retains its own name
and declaration-order rules.

The resolver completes the graph and joins every bank assignment before it
invokes the resident compiler. Missing sources, root escapes, cycles, identity
aliases, plan capacity, and placement errors are host diagnostics.

## Portable source plan

The portable interchange is restricted line-oriented ASCII named `SP1`. JSON
may remain a Node-facing project format, but neither a Node nor Z80 compiler
reads JSON.

The grammar is:

```text
plan        = header newline part-record{declared-count} end [newline] EOF
header      = "SP1 " count
part-record = "P " bank " " logical-path newline
end         = "END"
newline     = LF | CR LF
```

Example:

```text
SP1 4
P 1 src/lib/hardware.nu
P 1 src/lib/display.nu
P 0 src/lib/input.nu
P 0 src/main.nu
END
```

The fields have these rules:

- `count` is canonical unsigned decimal in the range 1 through 255. It has no
  leading zero.
- `bank` is canonical unsigned decimal in the range 0 through 255. Zero is the
  only spelling with a leading zero.
- A logical path contains 1 through 255 bytes drawn from ASCII letters, digits,
  `.`, `_`, `-`, and `/`.
- A logical path has no leading or trailing `/`, empty component, `.` component,
  or `..` component.
- Backslash, colon, whitespace, control bytes, quoting, and escapes are invalid.
- The generator emits LF. Readers accept LF and CRLF and reject lone CR.
- The file contains no blank lines, comments, optional fields, or trailing
  bytes after `END` and its optional newline.
- The declared count must equal the number of `P` records.
- Record order is compilation order and determines source-part ordinal.
- Flat builds use bank zero.

The SP1 format admits up to 255 parts and bank ordinals from 0 through 255. Each
language and host publishes its lower operational limits for part count,
dependency depth, logical path length, total retained path bytes, and banks.
Capacity excess is diagnosed before compilation starts.

The project root is supplied separately. Origins, image geometry, services,
memory regions, stack policy, and output selection remain in project or target
configuration and never enter SP1.

## Generation and lifecycle

SP1 is machine-generated and human-readable. It is not the primary authoring
interface and is not a dependency lockfile. Ordinary builds regenerate it from
the entry source and consume it in the same build operation. A stale saved plan
has no authority over changed dependency headers.

The host may retain SP1 for inspection, caching evidence, a failed build, or
transfer to a smaller operating-layer implementation. A direct SP1 input mode
is permitted for tools that deliberately supply an explicit order, but that
caller accepts responsibility for regenerating the plan after source dependency
changes.

A consumer validates the complete SP1 structure, count, paths, capacities, and
bank ordinals before invoking the compiler. A Z80 consumer may do this with a
first pass over a rewindable plan rather than retaining all records in RAM.

## Placement join

Source files contain no bank or origin declarations. A Node project description
may assign banks by logical identity:

```json
{
  "placement": {
    "defaultBank": 0,
    "banks": {
      "src/lib/hardware.nu": 1,
      "src/lib/display.nu": 1
    }
  }
}
```

The resolver joins this mapping to the resolved graph and emits the resulting
bank in each `P` record. The compact compiler interface still receives a bank
array indexed by source-part ordinal.

The host rejects assignments for unreachable or nonexistent logical identities,
conflicting assignments, out-of-range banks, and missing assignments when no
default exists. Target-specific semantic checks, including entry-bank and
cross-bank reference rules, remain with the compiler and target adapter.

## Nucleus profile

Nucleus dependency metadata uses its native line comment:

```nucleus
//% import "lib/text.nu"
//% import "lib/console.nu"
```

Only `import` is admitted by this profile. Directives occur in the leading
header block. Blank lines and ordinary `//` comments may occur in that block.
The first non-comment Nucleus token closes it. A later `//%` line is a host
diagnostic rather than an ignored comment-shaped typo.

The resolver interprets the import, but the multipart adapter passes the source
part through byte for byte. The Nucleus tokenizer therefore sees the directive
as an ordinary comment, and its existing part-relative offsets remain exact.

This profile has no defines, conditional imports, textual inclusion, macros,
or transformed-source machinery. A later Nucleus revision may reuse the common
condition evaluator without changing the resolver or SP1 format.

## Atom profile

Atom host directives use bare `%` spelling:

```asm
%include "lib/text.asm"
%define DEBUG %1

%if DEBUG
    CALL DebugRoutine
%else
    NOP
%endif
```

A host directive begins when `%` is the first non-space byte on a logical line
and the next byte is an ASCII letter. This does not conflict with `%` followed
by `0` or `1` in an Atom expression, which remains a binary literal. Infix `%`
remains the remainder operator.

The initial profile admits `include`, `define`, `if`, `else`, and `endif`.
Names are case-insensitive. An unknown directive is a host diagnostic. The host
must not pass a directive line to Atom and Atom must reject any directive that
leaks through rather than silently compiling an unprocessed conditional.

`%define` creates an immutable preprocessor value used by host conditionals. It
does not perform textual substitution and does not define an Atom assembler
symbol. Source that needs the same numeric value in assembled expressions must
declare it separately with `EQU`.

In the initial profile, source `%define` directives occur only in the entry
part's leading preprocessing header, before its first `%include`, `%if`, or
ordinary Atom line. Project-supplied definitions are established before that
header. A duplicate name is an error, even when both values match. Imported
parts may test the frozen environment but may not add definitions. These rules
make one dependency graph independent of traversal accidents and give every
selected part the same build values.

The Atom profile accepts decimal, `$` hexadecimal, `%` binary, `H` hexadecimal
suffix, and `B` binary suffix values in preprocessor definitions and
conditions. A hexadecimal suffix literal begins with a decimal digit, so
`0FFFFH` is numeric while `FFFFH` is a name. A binary suffix literal contains
only `0` and `1` before `B`. Letter case is insignificant.

Atom's assembler tokenizer will accept the same four numeric families in
ordinary active source. The source packager neither rewrites nor interprets an
active instruction or `EQU`, `ORG`, `DB`, `DW`, or `DS` operand. AZM proof
translation may canonicalize suffix literals after this boundary.

The initial `%if` condition is one integer literal or one defined name. Zero is
false and every nonzero value is true. An undefined name, extra token, or value
outside 0 through 65,535 is an error. Arithmetic, comparison, Boolean operators,
and textual expansion require a later profile revision.

The resolver treats active `%include` directives as import-once dependency
edges. The spelling does not request C-style textual repetition. Inactive
includes add no graph edge. Included files retain separate source-part
identities.

`%include` occurs only in a part's leading preprocessing header. Header `%if`
blocks may select includes, but they close before the first ordinary Atom line.
Body `%if` blocks mask source and may not contain `%include` or `%define`.

During multipart emission the host masks:

- every directive line, whether active or inactive; and
- every non-directive line in an inactive conditional branch.

Masking replaces each byte other than CR and LF with ASCII space. It neither
inserts nor deletes bytes. Conditional nesting and end-of-part balance are host
checks. A false branch may contain ordinary Atom text, but directive nesting
must remain structurally valid.

The preprocessor's resolved value environment and active masks belong to the
resolved build operation. SP1 records part order and bank placement; it does
not serialize definitions or act as a reproducible configuration lock. A host
that accepts saved SP1 directly must receive the same Atom profile
configuration separately or reject conditional source.

## Provenance

For every part, provenance records:

- logical identity and diagnostic name;
- physical source used by the current host;
- source-part ordinal and selected bank;
- original byte length;
- masked ranges for Atom, empty for Nucleus; and
- dependency-directive locations and include stack used in host diagnostics.

Compiler offsets always index the equal-length `compiler bytes` stream and map
directly to the same offsets in `original bytes`. D8 and listing writers read
line text from the original source and never attribute generated bytes to an
inactive masked line.

Provenance is host state, not resident compiler workspace and not part of SP1.
An implementation may stream or spool it under published capacity limits.

## Failure and publication rules

The host invokes the compiler only after successful dependency resolution,
placement join, and complete SP1 validation. A source open failure, malformed
directive, undefined preprocessor value, conditional imbalance, capacity
failure, or masking failure prevents compilation.

The bytes compiled must be the same source snapshot that the resolver scanned.
The host retains them, spools them, or detects a change before compilation. It
must not resolve one version of a dependency header and later compile different
bytes from that path.

If preprocessing fails after an output generation has begun in a streaming
operating adapter, the adapter aborts the uncommitted generation. No failure may
replace the previous committed object, listing, map, or generated source plan.

Diagnostics distinguish project, dependency, plan, preprocessing, compiler,
and output failures. Each host diagnostic names the logical source and exact
directive location when source text caused the failure.

## Required proof set

The shared resolver and adapters require tests that distinguish these failures:

- a diamond emits the shared dependency exactly once;
- sibling imports retain written order;
- a repeated direct import, missing source, root escape, alias, and complete
  dependency cycle each receive the correct host diagnostic;
- LF and CRLF plans parse, lone CR and truncation fail, and `END` rejects
  trailing records or bytes;
- count, part, path, depth, retained-path, and bank capacities pass exactly at
  their limits and fail one unit beyond them;
- relocating a project root preserves logical identities and compiler output;
- path-keyed placement produces the same ordinal bank array after unrelated
  dependency-order changes;
- Nucleus original and compiler byte streams are identical;
- Atom masking preserves length, every CR/LF byte, and every active source byte;
- `%define DEBUG %1` distinguishes a directive marker from a binary literal;
- Intel `0FFFFH` and `01110111B` conditions match `$FFFF` and `%01110111`;
- unknown and leaked Atom directives fail closed;
- nested true and false branches, inactive includes, and end-of-part imbalance
  produce the specified graph and masks;
- compiler diagnostics, listing lines, and D8 ranges map to original part
  identities and offsets; and
- dependency or preprocessing failure publishes no partial artifact.

End-to-end proofs compare the explicit ordered-parts API with resolver-produced
parts. Both paths must produce byte-identical compiler output and identical
source attribution for the same selected build.

## Out of scope

This version does not define textual macros, token substitution, repeated C
includes, namespaces, exports, package registries, search-path guessing, glob
imports, remote dependencies, conditional Nucleus source, target geometry,
artifact formats, or resident filesystem APIs.
