# Assembly commentary

ATOM's assembly is teaching material as well as executable code. Its short
symbols and implicit register and flag state need an English narrative alongside
the instructions. A reader should be able to follow a routine without repeatedly
looking up what a workspace name means or reconstructing why a flag matters.

This convention applies to assembly. JavaScript, TypeScript and other high-level
languages remain lightly commented, with comments for interfaces, constraints
and reasoning the code cannot express.

This policy applies to every hand-maintained assembly module.

## Make module headers easy to scan

Frame each module title with a 78-column rule above and below it. Follow it
with a short purpose statement, then leave a blank comment line before the
public contracts.

Give each public entry its own ASCII contract box. Group entries only when
their inputs and outputs share the same calling convention. Put the entry name
and action first, leave an empty row inside the box, then list inputs, results,
errors and side effects on separate lines. List error codes vertically.
Separate boxes with a blank comment line. Do not draw a box around every prose
section.

Use uppercase section labels with a short underline. Put a blank comment line
between sections. List return codes and token kinds vertically; align context
layouts and other tables. Keep each prose line to one fact, wrap at a natural
break, and stay within 78 columns. Avoid compressing unrelated guarantees into
semicolon-separated prose.

Keep the full ABI, error rules, register effects, memory ownership, stack use
and reentrancy contract in the header. Put instruction explanations beside
the instructions they explain.

```asm
;==============================================================================
;  Native pull lexer
;==============================================================================

;  PURPOSE
;  -------
;  Return one token at a time from a callback-backed byte source.

;  PUBLIC ENTRY POINTS
;  -------------------

;+---------------------------------------------------------------------------+
;| LINIT - Start a new byte stream.                                          |
;|                                                                           |
;| Entry: HL -> byte-source callback.                                        |
;| Effect: Reset state without reading from the source.                      |
;+---------------------------------------------------------------------------+

;  TOKEN KINDS
;  -----------

;  0  EOF
;  1  open parenthesis
;  2  close parenthesis
;  3  quote
;  4  dot
;  5  symbol
;  6  numeric text
;  7  scalar
;  8  string
```

## Explain the routine, then the instructions

Give the commentary room around the code. Leave a blank line before every
routine contract. Follow the contract immediately with a plain-language summary
of what the routine does. Leave one blank line after that header, put the entry
label at column one, and begin its indented body on the following line. Do not
strand the summary between the label and the first instruction. Separate later
full-line explanatory blocks from the instruction groups above and below them.
Keep the instructions that carry out one described step together without blank
lines between them.

```asm
;@ROUTINE IN A OUT A,CARRY CLOBBERS ZERO,SIGN,PARITY,HALFCARRY
; Return carry set when A is one of the eight bit-number operand classes.

EN_IBIND:
    CP   EN_BIT0                 ; Compare with the first accepted class.
    JR   C,AT_PNO                ; Reject a value below the range.
    CP   EN_BIT7+1               ; Compare with the exclusive upper bound.
    RET                          ; Carry set reports that A is below the upper bound.
```

Annotations such as `;@EXPECTOUT` remain attached to the instruction they
describe. Boundary markers used by builders also remain attached to their
defined source range. Blank lines count towards a source part's 65,535-byte
limit. Split an oversized part at a real subsystem boundary rather than
compressing the explanation back into a wall of text.

Put labels and named `EQU` definitions at column one. Indent instructions,
unlabelled data declarations and assembler or preprocessor directives by four
spaces. Keep full-line comments and contract annotations at column one. This
makes the control-flow landmarks visible without relying on syntax colouring.

Start each module with its purpose and public calling convention: inputs,
results, errors, preserved registers, scratch state, stack use and allocation or
reentrancy restrictions. Document caller-owned memory requirements explicitly.

Introduce internal labels with the step they perform. For a loop, explain what
the registers hold at its head and what changes on each iteration. Describe the
invariant that makes an unchecked access or arithmetic operation safe. Explain
joins shared by several branches so the reader can see what those paths have
established before arriving there.

Use inline comments generously. In particular, explain:

- The meaning of a value being loaded, stored or moved between registers.
- The bit fields being extracted or assembled, including units such as cell
  indices, byte offsets, exponents and mantissas.
- The comparison behind a conditional branch, and the instruction supplying its
  flags when that relationship is not immediate.
- Carry used as a borrow, shifted data bit, rounding input or error indicator.
- Temporary stack saves, restored values and changes in a register's role.
- Why a boundary, special value or error path needs separate handling.

Annotate nearly every instruction in dense arithmetic and tracing code. A few
adjacent instructions may share a comment when they form one obvious action;
complete line coverage is less important than a continuous, accurate account.
Do not fill gaps with comments that merely spell out an opcode. For example,
`ADD HL,HL` is more useful with “Convert the cell index to a two-byte offset”
than “Add HL to itself.” The next doubling should make clear that the result is
now a four-byte-cell offset.

Give each workspace declaration its full meaning. State whether a word holds an
address, index, count, tagged value payload or intermediate arithmetic result.
Mention shared or context-dependent uses where they matter. Keep compact assembler
names in the source, with their explanation close by.

## Keep the narrative true

A code change includes updating the comments for affected register meanings,
flags, branch conditions, encodings and invariants. Review comments against the
actual instructions and maintained ABI, including unusual inputs and error
returns. Avoid claims about measured speed, size or stack depth unless there is
evidence for the stated bound.

For a comment-only revision, assemble with ATOM and compare the emitted bytes
and symbol addresses against the previous source. Source line locations may
change; executable bytes and symbol values must not. Execution tests remain the
check for runtime behavior when instructions change.
