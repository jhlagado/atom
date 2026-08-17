import { validCases, invalidCases } from "./cases.mjs";
import { azmRejects } from "./support.mjs";
import { createParserHarness } from "./parser-support.mjs";

const h = await createParserHarness();
const valid = validCases();
const invalid = invalidCases().filter(({ source }) => azmRejects(source));
const indexedZeroAliases = valid.flatMap((item) => {
  if (!/\(I[XY]\+0\)/.test(item.source)) return [];
  return [
    item.source.replace(/\(I([XY])\+0\)/g, "(I$1)"),
    item.source.replace(/\(I([XY])\+0\)/g, "(I$1-0)"),
  ];
});

for (const item of valid) {
  h.parse(item.source);
  h.encodeParsed(item.source);
}
for (const item of invalid) h.parse(item.source);
for (const source of indexedZeroAliases) {
  h.parse(source);
  h.encodeParsed(source);
}

const s = h.symbols;
console.log(JSON.stringify({
  labels: "All byte, instruction, and cycle counts are Measured in the authoritative checked core.",
  coverage: {
    azmSupportedForms: valid.length,
    parsedRecordsMatched: valid.length,
    byteEncodingsMatched: valid.length,
    mixedCaseRecordsAndBytesMatched: valid.length,
    azmRejectedFormsRejectedAtomically: invalid.length,
    indexedZeroAliasRecordsAndBytesMatched: indexedZeroAliases.length,
  },
  parser: {
    ruleCode: s.AtomParserRuleCodeEnd - s.AtomParserCodeStart,
    operandTable: s.AtomParserImmutableEnd - s.AtomParserImmutableStart,
    codeAndTable: s.AtomParserCodeEnd - s.AtomParserCodeStart,
    fixedWorkspace: s.AtomParserWorkspaceEnd - s.AtomParserWorkspaceStart,
  },
  integrated: {
    codeAndTables:
      (s.AtomEncoderCoreEnd - s.AtomEncoderCoreStart) +
      (s.AtomSymbolCodeEnd - s.AtomSymbolCodeStart) +
      (s.AtomTokenizerCodeEnd - s.AtomTokenizerCodeStart) +
      (s.AtomExpressionCodeEnd - s.AtomExpressionCodeStart) +
      (s.AtomPatchCodeEnd - s.AtomPatchCodeStart) +
      (s.AtomParserCodeEnd - s.AtomParserCodeStart),
    fixedWorkspace:
      (s.AtomEncoderWorkspaceEnd - s.AtomEncoderWorkspaceStart) +
      (s.AtomSymbolWorkspaceEnd - s.AtomSymbolWorkspaceStart) +
      (s.AtomTokenizerWorkspaceEnd - s.AtomTokenizerWorkspaceStart) +
      (s.AtomExpressionWorkspaceEnd - s.AtomExpressionWorkspaceStart) +
      (s.AtomParserWorkspaceEnd - s.AtomParserWorkspaceStart),
  },
  execution: h.statistics,
}, null, 2));
