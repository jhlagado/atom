# Atom source map

Atom's Z80 source is in `src/z80`. The files are listed here in the order the
assembler includes them, which is also a sensible reading order. Each group
file opens with a short introduction to its stage.

## Roots

| File | Builds |
| --- | --- |
| `atom.asm` | The native core that the Node host runs: `core.asm` and `host.asm` |
| `cpm22.asm` | `ATOM.COM` for CP/M 2.2: `cpmorg.asm`, `core.asm` and the CP/M adapter |

## The core

`core.asm` lists the core in the order a statement flows through it.

| Stage | Files | What it does |
| --- | --- | --- |
| Names | `names.asm`: `radix40.asm`, `mnemonic.asm` | Packs names into RADIX-40 words and recognises mnemonics |
| Tokenizer | `token.asm`: `tokcore.asm`, `toknum.asm`, `tokstr.asm`, `tokdisp.asm` | Turns source bytes into tokens |
| Symbols | `symbols.asm`: `symdefs.asm`, `sympend.asm` | Stores symbols and pending references |
| Expressions | `expr.asm`: `exparse.asm`, `exreduce.asm`, `exarith.asm`, `exnum.asm`, `exdata.asm` | Reduces an expression to a value, or to a later symbol plus an addend |
| Instruction record | `insrec.asm` | Defines the record the parser fills and the encoder reads |
| Parser | `parser.asm`: `prscan.asm`, `proper.asm`, `prforms.asm`, `prdone.asm`, `prdata.asm` | Parses a mnemonic and its operands into the record |
| Encoder | `encoder.asm`: `endisp.asm`, `envbasic.asm`, `envload.asm`, `envother.asm`, `enbasic.asm`, `enload.asm`, `enops.asm`, `entables.asm` | Validates the instruction's form, then stages its bytes |
| Forward references | `refs.asm`: `fixfield.asm`, `refbind.asm`, `refpend.asm` | Records the fields to patch when a later symbol is defined |
| Output | `output.asm` | Emits bytes and resolves pending references |
| Statements | `stmts.asm`: `stparse.asm`, `ststring.asm`, `stdata.asm` | Assembles labels, equates, directives and instructions |
| Driver | `driver.asm`: `drbuild.asm`, `drfinish.asm` | Runs every source part and the final checks |

`host.asm` supplies the Node host's source reader and output services.
`nobj.asm` (`objread.asm`, `objwrite.asm`) supplies them for the named-object
harness.

## The CP/M adapter

| File | What it does |
| --- | --- |
| `cpmorg.asm` | Places the entry jump at `$0100` |
| `cpmmap.asm` | Defines every fixed address the adapter uses |
| `cpmentry.asm` | Checks memory, runs one command and leaves through warm boot |
| `cpmcmd.asm` | Parses the command tail and checks filenames |
| `cpmsrc.asm` | Opens source files and reads bytes through a 128-byte cache |
| `cpminc.asm` | Finds `%INCLUDE` lines and orders the source parts depth first |
| `cpprep.asm` (`ppctrl.asm`, `ppvalue.asm`) | Applies `%DEFINE` and `%IF` |
| `cpmbin.asm` (`cpmbscan.asm`, `cpmbpars.asm`, `cpmbsink.asm`) | Finds, checks and streams `INCBIN` data |
| `cpmpub.asm` | Receives Atom's output and publishes or rolls back the files |
| `cpmerr.asm` | Finds the line and column of a failure and prints its message |
| `cpmcon.asm` | Prints to the console |
| `cpmdata.asm`, `cpmsg.asm` | FCBs, console text and the generated message table |
| `cpmstate.asm` | Resident state that must survive the output stage |
| `spool.asm` (`aso.asm`, `mat.asm`, `cpmhex.asm`, `cpmsym.asm`) | Spools Atom's output to `NAME.$$B`, replays it into COM, BIN or HEX, and writes the symbol file |

During output, the materialiser reuses the memory that held the symbol and
source tables during assembly. `cpmmap.asm` shows which addresses change role,
and why `cpmstate.asm` sits below them.

## Labels

Names start with a lowercase area prefix, such as `tk` for the tokenizer or
`mat` for the materialiser, followed by capitalised words: `tkNext`,
`exSrcOff`, `matWin`. Private labels inside a routine start with a period:
`.nextPart`. Atom ignores case, and names have at most eight characters.
