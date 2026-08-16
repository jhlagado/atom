# Atom Phase 9 equates, characters, and strings

Atom now accepts an optional colon before `EQU`, one-byte character literals,
and the bare `CSTR`, `PSTR`, and `ISTR` directives. The syntax is
case-insensitive. Documentation examples use uppercase assembly.

## Native cost

| Change | Classification | Bytes |
| --- | --- | ---: |
| Character-literal tokenizer rules | Measured | 199 |
| Escape table growth | Measured | 7 |
| Colon equates and string directives | Measured | 165 |
| **Code and table growth** | **Measured** | **371** |
| Fixed workspace growth | Measured | 1 |

The complete native account is:

| Item | Classification | Bytes |
| --- | --- | ---: |
| Code and immutable tables | Measured | 12,879 |
| Fixed workspace | Measured | 551 |
| Linked resident extent | Measured | 13,430 |
| Code margin below 16 KiB | Measured | 3,505 |
| Physical margin below 16 KiB | Measured | 2,954 |

## Semantics and proof

`NAME EQU VALUE` and `NAME: EQU VALUE` use the same equate path. The colon form
does not publish an address label or close private scope. Duplicate,
forward-dependent, and malformed equates retain the existing atomic failure
rules.

Character literals enter the expression evaluator as numeric tokens. They
therefore work in instructions, data directives, and arithmetic without an
extra parser rule. The tokenizer accepts one decoded byte and the established
escape set while retaining `AF'` as the alternate-register spelling.

The string directives each accept one byte string. `CSTR` appends zero, `PSTR`
prepends the decoded-byte count, and `ISTR` sets bit 7 on the final decoded
byte. An empty `ISTR` emits no bytes. Capacity and delimiter checks happen
before the first output byte.

The Atom-to-AZM translator covers the new equate and string forms. The artifact
proof classifies string output as D8 data and colon equates as constants.

Self-hosting remains byte exact. Measured source size is 96,462 bytes across
six parts. The pinned core, translated AZM build, first Atom generation, and
second Atom generation agree across all 13,430 resident bytes and all 13,054
initialized addresses. The first generation uses Measured 156,323,531
instructions and Measured 1,427,943,875 T-states.

The Atom-local suite has Measured 253 passing tests. The repository-level
`release:check` remains blocked while the shared Debug80 checkout is on the
Nucleus work branch `codex/nucleus-docs-sync`; Atom requires its pinned Debug80
`main` dependency for the release certificate. No Debug80 files or branches
were changed during this checkpoint.
