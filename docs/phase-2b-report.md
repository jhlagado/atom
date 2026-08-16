# Atom Phase 2b streaming tokenizer report

## Result

**Correctness: Measured pass.** AZM strict register contracts pass. Native Z80
tests observe the exact return PC and SP, two-sided source and stack canaries,
unchanged source and resident code, all writes across the 64 KiB address space,
exact part and byte-offset diagnostics, token publication atomicity, and IY
preservation. The byte classifiers cover all 256 inputs. Boundary tests cover
names, 16-bit integers, raw string length, source intervals, CRLF, final-line
EOL synthesis, and EOF.

**Tokenizer code and immutable data: Measured 1,219 bytes.** Rule-driven code is
**Measured 1,186 bytes** and the punctuation and escape tables are **Measured
33 bytes**. Fixed non-reentrant workspace is **Measured 32 bytes**, including
the **Measured 9-byte token record**.

The encoder, symbol core, and tokenizer now total **Measured 5,875 bytes of code
and immutable data**. Their fixed workspace totals **Measured 69 bytes**.
Caller-owned symbol records, pending records, source, output, and stack remain
separate.

## Streaming and handoff result

The tokenizer consumes a caller-owned source part once and retains no source
copy. Every token carries a part ordinal and a 16-bit offset. Name tokens retain
only a source pointer and length; the existing mnemonic and RADIX-40 routines
perform case-insensitive classification before parser state outlives the token.

The parser handoff requires no new resident wrapper. A name token already has
the `HL` pointer and `B` length accepted by `AtomRecognizeMnemonic`. Operand
classification writes the existing ten-byte parsed-instruction record, and
`AtomFormLength` remains the authority for bytes reserved before forward values
are known.

The source part must remain addressable until the current token has been
consumed. Phase 2b measures the memory-backed source path. A flat-manifest
iterator or hardware input service remains a separate, unmeasured component.

## Execution measurement

For the fixed 512-byte proof source capacity, the longest observed public path
was a whitespace-only part:

| Entry | Classification | Instructions | T-states | Case |
| --- | --- | ---: | ---: | --- |
| `AtomTokenizerReset` | Measured | 22 | 248 | empty part |
| `AtomTokenizerNext` | Measured | 24,619 | 277,004 | 512 spaces followed by EOF |

The longest path is about **Measured 69.3 ms at 4 MHz**. It is a proof-capacity
stress case; ordinary tokens return as soon as one token is complete.

## Syntax boundary

Phase 2b accepts the syntax required by Atom's current source style: ASCII
names, `_` private names, dotted directives, decimal, `$` hexadecimal, `%`
binary, Intel-style digit-led `H` hexadecimal and `B` binary, double-quoted
strings, semicolon comments, and the Phase 2b expression punctuation set.
Mixed-case `lD` flows directly into the existing mnemonic recognizer and
returns the `LD` ordinal.

The following AZM lexical forms are **Measured unsupported** in this tokenizer:

- `0x` and `0b` numeric prefixes;
- single-quoted byte literals;
- dotted and question-mark symbol spellings;
- brackets and typed-layout syntax.

These forms are outside Atom's current claimed source syntax. The instruction
encoder's complete AZM byte differential remains unchanged.

## Size result and whole-assembler projection

The previous source-adapter and tokenizer estimate was **Projected 1,300–1,800
bytes**. The measured memory-backed tokenizer is 81 bytes below the low end.
A flat-manifest iterator is still **Projected 100–250 bytes**, so the complete
source layer is **Projected 1,319–1,469 bytes** until that iterator is measured.

Replacing the old tokenizer estimate with the measured result gives:

| Remaining component | Classification | Bytes |
| --- | --- | ---: |
| Flat-manifest source-part iterator | Projected | 100–250 |
| Operand expressions and directives | Projected | 1,600–2,200 |
| Symbol integration and diagnostics beyond Phase 2a | Projected | 100–400 |
| Append-only NOBJ image and patch output | Projected | 800–1,200 |
| Control, diagnostics, and integration | Projected | 1,000–1,500 |
| **Remaining subtotal** | **Projected** | **3,600–5,550** |

The whole assembler is now **Projected 9,475–11,425 bytes**, or about
**9.3–11.2 KiB**, before symbol and pending arenas. That leaves **Projected
4.8–6.7 KiB** in a 16 KiB code bank. The range remains a projection; expression
and directive parsing is now the widest unmeasured resident-code component.

## Reproduction

```sh
npm run annotate:contracts
npm test
npm run measure
npm run measure:symbols
npm run measure:tokenizer
```

The test command verifies the frozen dependency trees, rebuilds AZM and the
runtime, assembles every proof with strict contracts, executes the native
harnesses, and checks complete 64 KiB memory profiles.
