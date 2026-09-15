# Assembly commentary

ATOM's assembly is teaching material as well as executable code. Its short
symbols and implicit register and flag state need an English narrative alongside
the instructions. A reader should be able to follow a routine without repeatedly
looking up what a workspace name means or reconstructing why a flag matters.

This convention applies to assembly. JavaScript, TypeScript and other high-level
languages remain lightly commented, with comments for interfaces, constraints
and reasoning the code cannot express.

This is the policy for new and revised assembly commentary. Existing source
files have not been brought into conformance as part of adopting this policy.

## Explain the routine, then the instructions

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
Mention shared or phase-dependent uses where they matter. Keep compact assembler
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
