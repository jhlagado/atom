# Streaming tokenizer ABI

## Source-part contract

`AtomTokenizerReset` initializes one source part.

- Input: `A` is the source-part ordinal; `HL..DE` is the caller-owned,
  half-open source interval.
- Success: carry clear, `A=0`, and `IX` points to the token record.
- Failure: carry set and `A=AtomTokenStatusBadSourceRange`. A reversed interval
  changes no tokenizer state.

The tokenizer reads the interval once from low address to high address. Source
bytes remain unchanged and must remain addressable until the parser has
consumed the current token. A flat-manifest adapter may call
`AtomTokenizerReset` for each ordered part. A non-empty part without a physical
line ending produces one synthetic EOL before EOF, so adjacent parts cannot
join two source words accidentally.

`AtomTokenizerNext` returns one token in the fixed record.

- Success: carry clear, `A` is the token kind, and `IX` points to the record.
- Failure: carry set and `A` is the lexical status. The previous token record
  remains unchanged. `AtomTokenErrorPart` and `AtomTokenErrorOffset` identify
  the first byte of the failed token.
- EOF is a repeatable token with kind zero, not a failure.

Both public routines are non-reentrant. Every return path restores SP and the
hardware return address. The Phase 2b runtime proof also checks that IY remains
unchanged, although the current conservative AZM summary lists IY as clobbered
for `AtomTokenizerNext`.

## Token record

The record is nine bytes:

| Offset | Bytes | Field |
| ---: | ---: | --- |
| 0 | 1 | token kind |
| 1 | 1 | source-part ordinal |
| 2 | 2 | byte offset from the start of the part |
| 4 | 2 | lexeme pointer |
| 6 | 1 | raw lexeme length |
| 7 | 2 | decoded numeric value, otherwise zero |

Private-name lexemes include the leading period. All lexeme pointers start at
the first source byte of the token. A synthetic EOL and EOF have zero
length and point at the end of the source part.

Names retain their source spelling. The parser passes the pointer and length
directly to `AtomRecognizeMnemonic`, `AtomRadix40Pack`, or `AtomPackSymbol`.
Those routines perform case-insensitive classification; the tokenizer does not
copy or fold a name.

## Phase 2b lexical surface

The tokenizer accepts:

- global names of one through eight bytes;
- private names consisting of `.` plus one through eight significant bytes;
- decimal integers, `$`-prefixed hexadecimal integers, `%`-prefixed binary
  integers, and Intel-style digit-led `H` hexadecimal and `B` binary integers
  in the range 0 through 65,535;
- single-quoted character literals containing exactly one decoded byte, with
  the same escape set as strings;
- `$` as the current-location token and `%` as the remainder operator when the
  next byte does not begin a binary literal;
- double-quoted strings with `\0`, `\n`, `\r`, `\t`, `\'`, `\"`, `\\`, and
  `\xHH` escapes;
- comma, colon, parentheses, `+ - * / % & ^ | ~`, apostrophe, `<<`, and `>>`;
- spaces, tabs, semicolon comments, LF, and CRLF.

Blank and comment-only lines produce no EOL token. A line that contains at
least one token produces exactly one EOL. Bare CR is a lexical error.

A percent sign followed by an ASCII letter before the first token on a line
fails with `AtomTokenStatusUnprocessedDirective` (status 9). The host masks
Atom preprocessing directives before native assembly; this failure prevents a
leaked `%INCLUDE`, `%IF`, or related directive from being interpreted as an
Atom expression. `%1`, `LD A,%1`, and `A % B` retain their numeric and remainder
meanings.

`AF'` remains a name followed by apostrophe punctuation rather than a
character literal. An unterminated character reports status 10. A character
with zero decoded bytes, more than one decoded byte, or an invalid escape
reports status 11.

Phase 2b does not accept AZM's `0x` or `0b` spellings. It also excludes
question-mark symbol names, brackets, layout syntax, expression precedence,
directive meaning, operand classification, and output. These are explicit
boundaries of the measured tokenizer, not claims about AZM's accepted source
language.

## Parsed-instruction handoff

The parser consumes tokens until EOL, classifies up to three operands, and
fills the ten-byte parsed-instruction record documented in `encoder-abi.md`.
Concrete values belong only in the three value words. Registers, conditions,
bit numbers, interrupt modes, and restart vectors use operand-class ordinals.
Phase 2e adds general expression evaluation and publishes up to two fixed-field
references using the layout in `symbolic-parser-abi.md`.

No token pointer may enter the symbol table, pending list, parsed-instruction
record, or output stream. Symbols are packed before insertion, and pending
records retain only the symbol-record pointer and patch metadata.
