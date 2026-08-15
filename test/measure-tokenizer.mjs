import { createTokenizerHarness } from "./tokenizer-support.mjs";

const h = await createTokenizerHarness();

function one(source, label) {
  h.reset(source);
  h.next(label);
}

one("", "empty EOF");
one(" ".repeat(512), "512-byte whitespace part");
one(`;${"x".repeat(511)}`, "512-byte comment part");
one("_ABCDEFGH", "longest private name");
one(".EXPECTOUT", "long host-only directive");
one("65535", "largest decimal");
one("$FFFF", "largest hexadecimal");
one("%1111111111111111", "largest binary");
one(`"${"A".repeat(253)}"`, "255-byte string token");
one("LD A,(IX-$80)\r\n", "representative indexed instruction line");

const s = h.symbols;
console.log(JSON.stringify({
  labels: "All byte, instruction, and cycle counts are Measured in the Phase 2b proof image.",
  tokenizer: {
    ruleCode: s.AtomTokenizerRuleCodeEnd - s.AtomTokenizerCodeStart,
    immutableTables: s.AtomTokenizerImmutableEnd - s.AtomTokenizerImmutableStart,
    codeAndTables: s.AtomTokenizerCodeEnd - s.AtomTokenizerCodeStart,
    fixedWorkspace: s.AtomTokenizerWorkspaceEnd - s.AtomTokenizerWorkspaceStart,
    tokenRecord: s.AtomTokenRecordBytes,
  },
  integrated: {
    codeAndTables:
      (s.AtomEncoderCoreEnd - s.AtomEncoderCoreStart) +
      (s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart) +
      (s.AtomTokenizerCodeEnd - s.AtomTokenizerCodeStart),
    fixedWorkspace:
      (s.AtomEncoderWorkspaceEnd - s.AtomEncoderWorkspaceStart) +
      (s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart) +
      (s.AtomTokenizerWorkspaceEnd - s.AtomTokenizerWorkspaceStart),
  },
  execution: h.statistics,
}, null, 2));
